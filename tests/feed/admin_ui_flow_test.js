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

function runAdmin(storage = makeStorage(null), confirmAnswers = [], { now = null } = {}) {
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
  const windowListeners = new Map();
  const window = {
    localStorage: storage,
    KarmopathAdminCore: Core,
    addEventListener(type, listener) {
      const listeners = windowListeners.get(type) || [];
      listeners.push(listener);
      windowListeners.set(type, listeners);
    },
    confirm(message) { prompts.push(message); return confirmAnswers.length ? confirmAnswers.shift() : true; },
  };
  let ClockDate = Date;
  if (now !== null) {
    const fixedNow = typeof now === 'number' ? now : new Date(now).getTime();
    ClockDate = class extends Date {
      constructor(...args) { super(...(args.length ? args : [fixedNow])); }
      static now() { return fixedNow; }
    };
  }
  vm.runInNewContext(ADMIN_SOURCE, {
    window, document, URL: TestURL, Blob: TestBlob, Date: ClockDate,
    setTimeout: () => 1, clearTimeout: () => {},
  }, { filename: 'admin/app.js' });
  return { elements, get: getElementById, storage, downloads, prompts, document, window, windowListeners, languages: { bn: langBn, en: langEn } };
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
async function importText(harness, text) {
  const input = harness.get('importFile');
  input.files = [{ text: async () => text }];
  input.dispatch('change');
  await new Promise((resolve) => setImmediate(resolve));
}
async function importJson(harness, data) {
  await importText(harness, JSON.stringify(data));
}
function downloadedCandidate(harness) {
  const file = harness.downloads.find((item) => item.filename === 'karmopath-candidate-feed.json');
  return file ? JSON.parse(file.content) : null;
}
function fireBeforeUnload(harness) {
  const event = { defaultPrevented: false, returnValue: undefined, preventDefault() { this.defaultPrevented = true; } };
  for (const listener of harness.windowListeners.get('beforeunload') || []) listener(event);
  return event;
}

// A small deterministic DOM harness runs the real app.js listeners/state flow.
// It is not a browser engine: it validates user-event wiring and state effects.
test('dirty indicators survive draft selection and preview-language changes without autosaving', () => {
  const first = validJob('dirty-first');
  const second = validJob('clean-second');
  const raw = seedWorkspace([savedDraft('key-first', first), savedDraft('key-second', second)]);
  const storage = makeStorage(raw);
  const harness = runAdmin(storage);
  const writesBeforeInput = storage.writes;

  enter(harness, 'summary_en', 'Live edit stays in memory');
  assert.equal(storage.writes, writesBeforeInput);
  assert.equal(harness.get('draftSaveState').textContent, 'UNSAVED · MEMORY ONLY');
  assert.match(harness.get('workspaceSaveState').textContent, /1 draft.*unsaved in-memory/i);
  assert.match(draftButtons(harness)[0].childNodes[1].textContent, /UNSAVED · IN MEMORY/);
  assert.match(harness.get('reviewState').textContent, /RE-REVIEW NEEDED/);
  assert.equal(fireBeforeUnload(harness).defaultPrevented, true);

  harness.languages.en.click();
  assert.equal(harness.get('draftSaveState').textContent, 'UNSAVED · MEMORY ONLY');
  draftButtons(harness)[1].click();
  assert.equal(harness.get('draftSaveState').textContent, 'SAVED IN BROWSER');
  assert.match(harness.get('workspaceSaveState').textContent, /1 draft.*unsaved in-memory/i);
  assert.match(draftButtons(harness)[0].childNodes[1].textContent, /UNSAVED · IN MEMORY/);
  draftButtons(harness)[0].click();
  assert.equal(harness.get('summary_en').value, 'Live edit stays in memory');
  assert.equal(harness.get('draftSaveState').textContent, 'UNSAVED · MEMORY ONLY');

  click(harness, 'saveButton');
  assert.equal(storage.writes, writesBeforeInput + 1);
  assert.equal(harness.get('draftSaveState').textContent, 'SAVED IN BROWSER');
  assert.match(harness.get('workspaceSaveState').textContent, /all current drafts are saved/i);
  assert.equal(fireBeforeUnload(harness).defaultPrevented, false);
  assert.match(harness.get('reviewState').textContent, /RE-REVIEW NEEDED/);
});

test('sample baseline handoff keeps deadline correction and unknown null extensions through compare gate', async () => {
  const baseline = JSON.parse(fs.readFileSync(path.join(ROOT, 'test/fixtures/sample_feed.json'), 'utf8'));
  baseline.jobs[0].sample_extension = null;
  baseline.jobs[0].sample_nested_extension = { preserved: true, values: [null, 'sample-only'] };
  const temp = fs.mkdtempSync(path.join('/home/user', 'karmopath-admin-handoff-'));
  try {
    const baselinePath = path.join(temp, 'baseline.json');
    const candidatePath = path.join(temp, 'candidate.json');
    const baselineText = `${JSON.stringify(baseline, null, 2)}\n`;
    fs.writeFileSync(baselinePath, baselineText, 'utf8');
    const untouchedBaseline = fs.readFileSync(baselinePath);
    const harness = runAdmin();
    await importText(harness, baselineText);
    assert.match(harness.get('feedback').textContent, /imported after validation/);
    const storageAfterImport = harness.storage.raw;

    enter(harness, 'application_end_date', '2027-01-31');
    assert.equal(harness.get('draftSaveState').textContent, 'UNSAVED · MEMORY ONLY');
    click(harness, 'candidateExportButton');
    assert.match(harness.get('feedback').textContent, /existing record.*cannot be omitted/i);
    assert.equal(downloadedCandidate(harness), null);

    click(harness, 'draftExportButton');
    const backup = JSON.parse(harness.downloads.at(-1).content);
    assert.equal(backup.drafts[0].data.application_end_date, '2027-01-31');
    assert.equal(backup.drafts[0].data.sample_extension, null);
    assert.deepEqual(backup.drafts[0].data.sample_nested_extension, { preserved: true, values: [null, 'sample-only'] });
    assert.equal(harness.storage.raw, storageAfterImport);
    assert.equal(harness.get('draftSaveState').textContent, 'UNSAVED · MEMORY ONLY');

    click(harness, 'reviewButton');
    assert.match(harness.get('reviewState').textContent, /REVIEWED CANDIDATE/);
    assert.equal(harness.get('draftSaveState').textContent, 'SAVED IN BROWSER');
    click(harness, 'candidateExportButton');
    const candidate = downloadedCandidate(harness);
    assert.ok(candidate);
    assert.equal(candidate.jobs[0].application_end_date, '2027-01-31');
    assert.equal(candidate.jobs[0].sample_extension, null);
    assert.deepEqual(candidate.jobs[0].sample_nested_extension, { preserved: true, values: [null, 'sample-only'] });
    assert.equal(candidate.jobs[0].published_at, baseline.jobs[0].published_at);
    fs.writeFileSync(candidatePath, JSON.stringify(candidate, null, 2), 'utf8');

    const validation = spawnSync('python3', [path.join(ROOT, 'tools/feed/validate.py'), candidatePath], { encoding: 'utf8' });
    assert.equal(validation.status, 0, validation.stdout + validation.stderr);
    const comparison = spawnSync('python3', [path.join(ROOT, 'tools/feed/compare.py'), baselinePath, candidatePath], { encoding: 'utf8' });
    assert.equal(comparison.status, 0, comparison.stdout + comparison.stderr);
    assert.match(comparison.stdout, /Changed \(1\):/);
    assert.match(comparison.stdout, new RegExp(`${baseline.jobs[0].id}: application_end_date`));
    assert.deepEqual(fs.readFileSync(baselinePath), untouchedBaseline);
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
});

test('re-review rejects equal or regressed real review instants without fabricating timestamps', async () => {
  const fixedNow = Date.now();
  const nowTimestamp = new Date(fixedNow).toISOString();
  const wholeSecond = nowTimestamp.slice(0, 19);
  const milliseconds = nowTimestamp.slice(20, -1);
  const justFuture = `${wholeSecond}.${milliseconds}0001Z`;
  for (const [label, priorTimestamp] of [['equal', nowTimestamp], ['sub-millisecond future', justFuture]]) {
    const job = validJob(`timestamp-${label.replace(/[^a-z]+/g, '-')}`, {
      published_at: new Date(fixedNow - 60_000).toISOString(),
      reviewed_at: priorTimestamp,
      updated_at: priorTimestamp,
    });
    const harness = runAdmin(makeStorage(null), [], { now: fixedNow });
    await importJson(harness, validFeed(job));
    const persistedRaw = harness.storage.raw;
    enter(harness, 'summary_en', `Edit with ${label} timestamp`);
    click(harness, 'candidateExportButton');
    assert.equal(downloadedCandidate(harness), null);
    click(harness, 'reviewButton');
    assert.match(harness.get('feedback').textContent, /No timestamps were changed/i);
    assert.match(harness.get('feedback').textContent, /current review time must be later/i);
    assert.equal(harness.storage.raw, persistedRaw);
    assert.equal(harness.get('draftSaveState').textContent, 'UNSAVED · MEMORY ONLY');
    click(harness, 'draftExportButton');
    const backup = JSON.parse(harness.downloads.at(-1).content);
    assert.equal(backup.drafts[0].data.reviewed_at, priorTimestamp);
    assert.equal(backup.drafts[0].data.updated_at, priorTimestamp);
  }
});

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

test('draft backup contains live edits but never clears the dirty state or persists to browser storage', () => {
  const job = validJob('backup-dirty');
  const raw = seedWorkspace([savedDraft('backup-key', job)]);
  const storage = makeStorage(raw);
  const harness = runAdmin(storage);
  enter(harness, 'summary_en', 'Private unsaved backup value');
  const writesBeforeBackup = storage.writes;
  click(harness, 'draftExportButton');
  const backup = JSON.parse(harness.downloads.find((file) => file.filename === 'karmopath-admin-drafts.json').content);
  assert.equal(backup.drafts[0].data.summary_en, 'Private unsaved backup value');
  assert.equal(storage.raw, raw);
  assert.equal(storage.writes, writesBeforeBackup);
  assert.equal(harness.get('draftSaveState').textContent, 'UNSAVED · MEMORY ONLY');
  assert.match(harness.get('feedback').textContent, /does not change browser storage or clear the unsaved indicators/i);
});

test('failed Save and review writes retain edited values and keep them in private backup', () => {
  const job = validJob('write-failure');
  const raw = seedWorkspace([savedDraft('write-key', job)]);
  const storage = makeStorage(raw);
  const harness = runAdmin(storage);
  enter(harness, 'summary_en', 'Edit survives failed writes');
  storage.failSet = true;

  click(harness, 'saveButton');
  assert.equal(storage.raw, raw);
  assert.equal(draftButtons(harness).length, 1);
  assert.equal(harness.get('summary_en').value, 'Edit survives failed writes');
  assert.equal(harness.get('draftSaveState').textContent, 'UNSAVED · MEMORY ONLY');
  assert.match(harness.get('feedback').textContent, /write failed/i);
  assert.equal(harness.downloads.length, 0);
  click(harness, 'draftExportButton');
  let backup = JSON.parse(harness.downloads.at(-1).content);
  assert.equal(backup.drafts[0].data.summary_en, 'Edit survives failed writes');

  click(harness, 'reviewButton');
  assert.equal(storage.raw, raw);
  assert.equal(harness.get('summary_en').value, 'Edit survives failed writes');
  assert.equal(harness.get('draftSaveState').textContent, 'UNSAVED · MEMORY ONLY');
  assert.match(harness.get('feedback').textContent, /write failed/i);
  click(harness, 'draftExportButton');
  backup = JSON.parse(harness.downloads.at(-1).content);
  assert.equal(backup.drafts[0].data.summary_en, 'Edit survives failed writes');
  assert.equal(backup.drafts[0].reviewed, false);
  assert.equal(storage.writes, 2); // failed Save and failed review; backups do not write storage
  assert.equal(storage.raw, raw);
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

test('invalid and cancelled replacement imports keep selection, live edits, and storage intact', async () => {
  const first = validJob('import-first');
  const second = validJob('import-second');
  const raw = seedWorkspace([savedDraft('first-key', first), savedDraft('second-key', second)]);
  const storage = makeStorage(raw);
  const harness = runAdmin(storage, [false]);
  draftButtons(harness)[1].click();
  enter(harness, 'summary_en', 'Unsaved selected-draft text');
  const selectedKey = 'second-key';

  const invalid = validFeed(validJob('bad-import', { title_en: '' }));
  await importJson(harness, invalid);
  assert.match(harness.get('feedback').textContent, /Import rejected/i);
  assert.equal(harness.prompts.length, 0);
  assert.equal(storage.raw, raw);
  assert.equal(harness.get('summary_en').value, 'Unsaved selected-draft text');
  assert.equal(draftButtons(harness).find((button) => button.getAttribute('aria-current') === 'true').childNodes[0].textContent, `নমুনা import-second`);
  assert.equal(harness.get('draftSaveState').textContent, 'UNSAVED · MEMORY ONLY');

  await importJson(harness, validFeed(validJob('replacement-import')));
  assert.match(harness.prompts[0], /unsaved in-memory edits.*will be discarded/i);
  assert.equal(storage.raw, raw);
  assert.equal(harness.get('summary_en').value, 'Unsaved selected-draft text');
  assert.equal(draftButtons(harness).length, 2);
  assert.equal(draftButtons(harness).find((button) => button.getAttribute('aria-current') === 'true').childNodes[0].textContent, `নমুনা import-second`);
  assert.equal(harness.get('draftSaveState').textContent, 'UNSAVED · MEMORY ONLY');
  assert.equal(selectedKey, 'second-key');

  storage.failSet = true;
  await importJson(harness, validFeed(validJob('write-failed-import')));
  assert.match(harness.get('feedback').textContent, /write failed/i);
  assert.equal(storage.raw, raw);
  assert.equal(harness.get('summary_en').value, 'Unsaved selected-draft text');
  assert.equal(draftButtons(harness).length, 2);
  assert.equal(harness.get('draftSaveState').textContent, 'UNSAVED · MEMORY ONLY');
});

test('new and delete transitions disclose consequences and commit or retain the whole workspace exactly', () => {
  const first = validJob('workspace-first');
  const second = validJob('workspace-second');
  const raw = seedWorkspace([savedDraft('workspace-first-key', first), savedDraft('workspace-second-key', second)]);
  const storage = makeStorage(raw);
  const harness = runAdmin(storage, [false, true]);
  enter(harness, 'summary_en', 'Edit persisted by explicit new-draft action');
  click(harness, 'newDraftButton'); // cancel: the live workspace remains exactly as before
  assert.match(harness.prompts[0], /save the workspace.*no edits will be discarded/i);
  assert.equal(storage.raw, raw);
  assert.equal(draftButtons(harness).length, 2);
  assert.equal(harness.get('summary_en').value, 'Edit persisted by explicit new-draft action');
  assert.equal(harness.get('draftSaveState').textContent, 'UNSAVED · MEMORY ONLY');

  storage.failSet = true;
  click(harness, 'newDraftButton'); // accepted, but failed write must retain old live workspace
  assert.equal(storage.raw, raw);
  assert.equal(draftButtons(harness).length, 2);
  assert.equal(harness.get('summary_en').value, 'Edit persisted by explicit new-draft action');
  assert.equal(harness.get('draftSaveState').textContent, 'UNSAVED · MEMORY ONLY');
  assert.match(harness.get('feedback').textContent, /write failed/i);

  storage.failSet = false;
  click(harness, 'newDraftButton'); // retry: full current workspace, including edit, is persisted
  const persisted = JSON.parse(storage.raw);
  assert.equal(persisted.drafts.length, 3);
  assert.equal(persisted.drafts.find((draft) => draft.key === 'workspace-first-key').data.summary_en,
    'Edit persisted by explicit new-draft action');
  assert.equal(harness.get('draftSaveState').textContent, 'SAVED IN BROWSER');
  assert.match(harness.get('workspaceSaveState').textContent, /all current drafts are saved/i);
  assert.equal(fireBeforeUnload(harness).defaultPrevented, false);
});

test('failed reload after reset confirmation preserves in-memory edits and selection', () => {
  const job = validJob('reset-read-failure');
  const raw = seedWorkspace([savedDraft('reset-key', job)]);
  const storage = makeStorage(raw);
  const harness = runAdmin(storage);
  enter(harness, 'summary_en', 'Keep this in memory after read failure');
  storage.failRead = true;
  click(harness, 'resetButton');
  assert.match(harness.prompts[0], /discards in-memory changes/i);
  assert.equal(harness.storage.raw, raw);
  assert.equal(draftButtons(harness).length, 1);
  assert.equal(harness.get('summary_en').value, 'Keep this in memory after read failure');
  assert.equal(harness.get('draftSaveState').textContent, 'UNSAVED · MEMORY ONLY');
  assert.match(harness.get('feedback').textContent, /in-memory drafts were kept/i);
  assert.equal(harness.get('recoveryPanel').hidden, false);
});

test('deleting a dirty never-published draft warns before consent and cancellation preserves it', () => {
  const job = validJob('delete-unsaved');
  const raw = seedWorkspace([savedDraft('delete-key', job, { existing: false, reviewed: false, idLocked: false })]);
  const storage = makeStorage(raw);
  const harness = runAdmin(storage, [false, true]);
  enter(harness, 'summary_en', 'Will be deleted only after explicit warning');

  click(harness, 'deleteDraftButton');
  assert.match(harness.prompts[0], /unsaved in-memory edits will be discarded/i);
  assert.equal(storage.raw, raw);
  assert.equal(draftButtons(harness).length, 1);
  assert.equal(harness.get('summary_en').value, 'Will be deleted only after explicit warning');
  assert.equal(harness.get('draftSaveState').textContent, 'UNSAVED · MEMORY ONLY');

  click(harness, 'deleteDraftButton');
  assert.equal(draftButtons(harness).length, 0);
  assert.deepEqual(JSON.parse(storage.raw), { version: 1, drafts: [] });
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
