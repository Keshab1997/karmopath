'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const Core = require('../../admin/admin-core.js');

const ROOT = path.resolve(__dirname, '../..');
const ADMIN_SOURCE = fs.readFileSync(path.join(ROOT, 'admin/app.js'), 'utf8');
const HTML_SOURCE = fs.readFileSync(path.join(ROOT, 'admin/index.html'), 'utf8');

class FakeElement {
  constructor(tagName = 'div', id = '') {
    this.tagName = tagName.toUpperCase();
    this.id = id;
    this.value = '';
    this.files = [];
    this.disabled = false;
    this.hidden = false;
    this.className = '';
    this.textContent = '';
    this.dataset = {};
    this.childNodes = [];
    this.attributes = {};
    this.listeners = new Map();
  }
  addEventListener(type, listener) {
    const handlers = this.listeners.get(type) || [];
    handlers.push(listener);
    this.listeners.set(type, handlers);
  }
  dispatch(type, extra = {}) {
    if (type === 'click' && this.disabled) return;
    const event = { target: this, ...extra };
    for (const listener of this.listeners.get(type) || []) listener(event);
  }
  click() { this.dispatch('click'); }
  append(...children) { this.childNodes.push(...children); }
  replaceChildren(...children) { this.childNodes = [...children]; }
  setAttribute(name, value) { this.attributes[name] = String(value); }
  getAttribute(name) { return this.attributes[name] ?? null; }
  remove() {}
  focus() {}
}

function makeStorage(raw = null) {
  return {
    raw,
    failRead: false,
    failSet: false,
    writes: 0,
    getItem() {
      if (this.failRead) throw new Error('storage read denied');
      return this.raw;
    },
    setItem(_key, value) {
      this.writes += 1;
      if (this.failSet) throw new Error('quota exceeded');
      this.raw = value;
    },
  };
}

function runAdmin(storage = makeStorage(null), confirmAnswers = []) {
  const elements = new Map();
  for (const [, id] of HTML_SOURCE.matchAll(/\bid="([^"]+)"/g)) {
    const escapedId = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const tagMatch = HTML_SOURCE.match(new RegExp(`<([a-z][a-z0-9-]*)\\b[^>]*\\bid="${escapedId}"`, 'i'));
    elements.set(id, new FakeElement(tagMatch?.[1] || 'div', id));
  }
  const getElementById = (id) => {
    if (!elements.has(id)) elements.set(id, new FakeElement('div', id));
    return elements.get(id);
  };
  const downloads = [];
  const objectUrls = new Map();
  let objectUrlIndex = 0;
  class TestBlob {
    constructor(parts, options = {}) {
      this.content = parts.map((part) => String(part)).join('');
      this.type = options.type || '';
    }
  }
  class TestURL extends URL {
    static createObjectURL(blob) {
      const id = `blob:test-${++objectUrlIndex}`;
      objectUrls.set(id, blob);
      return id;
    }
    static revokeObjectURL(id) { objectUrls.delete(id); }
  }
  const body = new FakeElement('body', 'body');
  body.append = (...children) => {
    for (const child of children) {
      child.click = () => {
        const blob = objectUrls.get(child.href);
        if (child.download && blob) downloads.push({ filename: child.download, content: blob.content, type: blob.type });
      };
    }
    body.childNodes.push(...children);
  };
  const langBn = new FakeElement('button'); langBn.dataset.lang = 'bn';
  const langEn = new FakeElement('button'); langEn.dataset.lang = 'en';
  const docListeners = new Map();
  const document = {
    body,
    hidden: false,
    getElementById,
    createElement: (tag) => new FakeElement(tag),
    querySelectorAll: (selector) => selector === '.lang-switch button' ? [langBn, langEn] : [],
    addEventListener(type, listener) { docListeners.set(type, listener); },
  };
  const prompts = [];
  const window = {
    localStorage: storage,
    KarmopathAdminCore: Core,
    confirm(message) { prompts.push(message); return confirmAnswers.length ? confirmAnswers.shift() : true; },
  };
  vm.runInNewContext(ADMIN_SOURCE, {
    window, document, URL: TestURL, Blob: TestBlob,
    setTimeout: () => 1, clearTimeout: () => {},
  }, { filename: 'admin/app.js' });
  return { elements, get: getElementById, storage, downloads, prompts, document, window };
}

function validJob(id, updates = {}) {
  const now = Date.now();
  const published = new Date(now - 60_000).toISOString();
  const reviewed = new Date(now - 30_000).toISOString();
  const updated = new Date(now - 15_000).toISOString();
  return {
    id,
    kind: 'recruitment',
    title_bn: `নমুনা ${id}`,
    title_en: `Sample ${id}`,
    organization: 'Sample organization',
    category: 'office',
    districts: ['West Bengal'],
    qualifications: ['Graduate'],
    status: 'open',
    source_url: 'https://example.org/source',
    notice_url: 'https://example.org/notice.pdf',
    reviewed_at: reviewed,
    published_at: published,
    updated_at: updated,
    summary_bn: 'নমুনা বিবরণ।',
    summary_en: 'Sample factual summary.',
    how_to_apply_bn: '',
    how_to_apply_en: '',
    vacancies: null,
    application_start_date: null,
    application_end_date: '2099-12-31',
    application_end_at: null,
    exam_date: null,
    apply_url: null,
    age_note_bn: null,
    age_note_en: null,
    ...updates,
  };
}

function validFeed(...jobs) {
  return { schema_version: 1, updated_at: new Date(Date.now() - 5_000).toISOString(), jobs };
}

function seedWorkspace(drafts) {
  return JSON.stringify({ version: 1, drafts });
}

function savedDraft(key, data, { existing = true, reviewed = true, idLocked = true } = {}) {
  return { key, data, existing, reviewed, idLocked };
}

function click(harness, id) { harness.get(id).click(); }
function enter(harness, id, value) {
  const input = harness.get(id);
  input.value = value;
  input.dispatch('input');
}
function draftButtons(harness) { return harness.get('draftList').childNodes.filter((node) => node.tagName === 'BUTTON'); }
function statusBadge(harness) {
  const visit = (node) => {
    if (node.className && node.className.split(/\s+/).includes('status')) return node;
    for (const child of node.childNodes || []) {
      const found = visit(child);
      if (found) return found;
    }
    return null;
  };
  return visit(harness.get('preview'));
}
async function importJson(harness, data) {
  const input = harness.get('importFile');
  input.files = [{ text: async () => JSON.stringify(data) }];
  input.dispatch('change');
  await new Promise((resolve) => setImmediate(resolve));
}
function downloadedCandidate(harness) {
  const file = harness.downloads.find((item) => item.filename === 'karmopath-candidate-feed.json');
  return file ? JSON.parse(file.content) : null;
}

// A small deterministic DOM harness runs the real app.js listeners/state flow.
// It is not a browser engine: it validates user-event wiring and state effects.
test('real app.js blocks candidate export after editing an imported existing job', async () => {
  const job = validJob('existing-req');
  const harness = runAdmin();
  await importJson(harness, validFeed(job));
  assert.match(harness.get('feedback').textContent, /imported after validation/);

  enter(harness, 'summary_en', 'Corrected summary pending review');
  click(harness, 'candidateExportButton');
  assert.match(harness.get('feedback').textContent, /existing record.*cannot be omitted/i);
  assert.match(harness.get('feedback').textContent, /existing-req/);
  assert.equal(downloadedCandidate(harness), null);
});

test('real app.js prevents deletion of imported records and keeps their identity', async () => {
  const job = validJob('keep-this-id');
  const harness = runAdmin();
  await importJson(harness, validFeed(job));
  const rawBefore = harness.storage.raw;
  const promptCount = harness.prompts.length;

  click(harness, 'deleteDraftButton');
  assert.match(harness.get('feedback').textContent, /cannot be deleted/);
  assert.match(harness.get('feedback').textContent, /keep-this-id/);
  assert.equal(harness.storage.raw, rawBefore);
  assert.equal(harness.prompts.length, promptCount);

  enter(harness, 'status', 'withdrawn');
  click(harness, 'reviewButton');
  click(harness, 'candidateExportButton');
  const candidate = downloadedCandidate(harness);
  assert.ok(candidate);
  assert.equal(candidate.jobs[0].id, 'keep-this-id');
  assert.equal(candidate.jobs[0].status, 'withdrawn');
});

test('real app.js reports new-draft omission and keeps candidate IDs stable', async () => {
  const job = validJob('stable-existing-id');
  const harness = runAdmin();
  await importJson(harness, validFeed(job));
  click(harness, 'newDraftButton');
  enter(harness, 'id', 'new-unreviewed');
  click(harness, 'candidateExportButton');

  const candidate = downloadedCandidate(harness);
  assert.ok(candidate);
  assert.deepEqual(candidate.jobs.map((entry) => entry.id), ['stable-existing-id']);
  assert.match(harness.get('feedback').textContent, /new-unreviewed/);
  assert.match(harness.get('feedback').textContent, /omitted/);
});

test('failed import/new/delete storage writes retain old workspace and never show success', async () => {
  const existing = validJob('existing-retained');
  const local = validJob('local-delete-target');
  const initialRaw = seedWorkspace([
    savedDraft('key-existing', existing),
    savedDraft('key-local', local, { existing: false, reviewed: false, idLocked: false }),
  ]);
  const storage = makeStorage(initialRaw);
  const harness = runAdmin(storage);
  const initialButtons = draftButtons(harness);
  assert.equal(initialButtons.length, 2);
  initialButtons[1].click();
  assert.equal(draftButtons(harness)[1].getAttribute('aria-current'), 'true');
  storage.failSet = true;

  await importJson(harness, validFeed(validJob('replacement')));
  assert.equal(storage.raw, initialRaw);
  assert.equal(draftButtons(harness).length, 2);
  assert.equal(draftButtons(harness)[1].getAttribute('aria-current'), 'true');
  assert.match(harness.get('feedback').textContent, /write failed/i);
  assert.doesNotMatch(harness.get('feedback').textContent, /imported after validation/);

  click(harness, 'newDraftButton');
  assert.equal(storage.raw, initialRaw);
  assert.equal(draftButtons(harness).length, 2);
  assert.equal(draftButtons(harness)[1].getAttribute('aria-current'), 'true');
  assert.match(harness.get('feedback').textContent, /write failed/i);
  assert.doesNotMatch(harness.get('feedback').textContent, /new local draft created/i);

  click(harness, 'deleteDraftButton');
  assert.equal(storage.raw, initialRaw);
  assert.equal(draftButtons(harness).length, 2);
  assert.equal(draftButtons(harness)[1].getAttribute('aria-current'), 'true');
  assert.match(harness.get('feedback').textContent, /write failed/i);
  assert.doesNotMatch(harness.get('feedback').textContent, /deleted/i);
});

test('corrupt browser storage is backed up and requires explicit recovery consent', () => {
  const raw = '{corrupt browser bytes';
  const storage = makeStorage(raw);
  const harness = runAdmin(storage, [false, true]);
  assert.equal(harness.get('recoveryPanel').hidden, false);
  assert.equal(harness.get('newDraftButton').disabled, true);
  assert.equal(harness.get('importButton').disabled, true);
  assert.equal(storage.writes, 0);

  click(harness, 'rawBackupButton');
  assert.equal(harness.downloads[0].filename, 'karmopath-corrupt-local-storage-raw.txt');
  assert.equal(harness.downloads[0].content, raw);
  assert.equal(harness.get('confirmRecoveryButton').disabled, false);
  assert.equal(storage.raw, raw);
  assert.equal(storage.writes, 0);

  click(harness, 'confirmRecoveryButton'); // user cancels first confirmation
  assert.equal(storage.raw, raw);
  assert.equal(storage.writes, 0);
  click(harness, 'confirmRecoveryButton'); // user explicitly confirms
  assert.deepEqual(JSON.parse(storage.raw), { version: 1, drafts: [] });
  assert.equal(storage.writes, 1);
  assert.equal(harness.get('recoveryPanel').hidden, true);
  assert.equal(harness.get('newDraftButton').disabled, false);
});

test('real app.js invalidates review after edits, then exports stable IDs through Python validation', async () => {
  const first = validJob('review-me', { published_at: '2026-10-01T00:00:00Z' });
  const second = validJob('keep-me', { published_at: '2026-10-02T00:00:00Z' });
  const harness = runAdmin();
  await importJson(harness, validFeed(first, second));
  enter(harness, 'summary_en', 'Revised after notice check');
  assert.match(harness.get('reviewState').textContent, /RE-REVIEW NEEDED/);
  click(harness, 'candidateExportButton');
  assert.match(harness.get('feedback').textContent, /review-me/);
  assert.equal(downloadedCandidate(harness), null);

  click(harness, 'reviewButton');
  assert.match(harness.get('reviewState').textContent, /REVIEWED CANDIDATE/);
  click(harness, 'candidateExportButton');
  const candidate = downloadedCandidate(harness);
  assert.ok(candidate);
  assert.deepEqual(candidate.jobs.map((job) => job.id), ['review-me', 'keep-me']);
  assert.equal(candidate.jobs[0].published_at, first.published_at);
  assert.equal(candidate.jobs[0].summary_en, 'Revised after notice check');

  const temp = fs.mkdtempSync(path.join('/home/user', 'karmopath-candidate-'));
  try {
    const candidatePath = path.join(temp, 'candidate.json');
    fs.writeFileSync(candidatePath, JSON.stringify(candidate), 'utf8');
    const checked = spawnSync('python3', [path.join(ROOT, 'tools/feed/validate.py'), candidatePath], { encoding: 'utf8' });
    assert.equal(checked.status, 0, checked.stdout + checked.stderr);
    assert.match(checked.stdout, /VALID candidate feed/);
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
});

test('real app.js rejects duplicate IDs during import without replacing the workspace', async () => {
  const original = validJob('original-kept');
  const harness = runAdmin();
  await importJson(harness, validFeed(original));
  const rawBefore = harness.storage.raw;
  await importJson(harness, validFeed(validJob('duplicate'), validJob('duplicate')));
  assert.match(harness.get('feedback').textContent, /jobs\[1\]\.id: duplicate id/);
  assert.equal(harness.storage.raw, rawBefore);
  assert.equal(draftButtons(harness).length, 1);
  assert.match(draftButtons(harness)[0].childNodes[0].textContent, /নমুনা original-kept/);
});

test('expired preview shows Closed but leaves the declared feed status unchanged', () => {
  const job = validJob('expired-open', { application_end_date: '2000-01-01', application_end_at: null, status: 'open' });
  const draft = savedDraft('expired-key', job, { existing: true, reviewed: true, idLocked: true });
  const storage = makeStorage(seedWorkspace([draft]));
  const harness = runAdmin(storage);
  assert.equal(statusBadge(harness).textContent, 'বন্ধ');
  click(harness, 'candidateExportButton');
  const candidate = downloadedCandidate(harness);
  assert.equal(candidate.jobs[0].status, 'open');
  assert.equal(candidate.jobs[0].id, 'expired-open');
});
