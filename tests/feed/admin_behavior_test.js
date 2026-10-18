'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const Core = require('../../admin/admin-core.js');

function recordDraft(id, { existing = false, reviewed = false } = {}) {
  return { key: `key-${id}`, data: { id, status: 'open' }, existing, reviewed, idLocked: existing };
}

function memoryStorage(initial = null, { failGet = false, failSet = false } = {}) {
  let value = initial;
  let setCalls = 0;
  return {
    getItem() {
      if (failGet) throw new Error('read blocked');
      return value;
    },
    setItem(_key, next) {
      setCalls += 1;
      if (failSet) throw new Error('quota exceeded');
      value = next;
    },
    get value() { return value; },
    get setCalls() { return setCalls; },
  };
}

test('edited existing record blocks whole-feed export instead of disappearing', () => {
  const plan = Core.planCandidate([
    recordDraft('existing-needs-review', { existing: true, reviewed: false }),
    recordDraft('another-reviewed', { existing: true, reviewed: true }),
  ]);
  assert.equal(plan.ok, false);
  assert.deepEqual(plan.blockingExistingIds, ['existing-needs-review']);
  assert.deepEqual(plan.jobs.map((job) => job.id), ['another-reviewed']);
});

test('existing records cannot be physically deleted; never-published drafts can', () => {
  assert.equal(Core.canDeleteDraft(recordDraft('published', { existing: true })), false);
  assert.equal(Core.canDeleteDraft(recordDraft('local-draft')), true);
});

test('new unreviewed drafts are returned as explicit omissions', () => {
  const plan = Core.planCandidate([
    recordDraft('reviewed', { reviewed: true }),
    recordDraft('new-draft-to-omit'),
  ]);
  assert.equal(plan.ok, true);
  assert.deepEqual(plan.jobs.map((job) => job.id), ['reviewed']);
  assert.deepEqual(plan.omittedNewDraftIds, ['new-draft-to-omit']);
});

test('failed workspace replacement retains drafts and selection', () => {
  const oldDrafts = [recordDraft('old', { existing: true, reviewed: true })];
  const current = { drafts: oldDrafts, currentKey: oldDrafts[0].key, recovery: null };
  const storage = memoryStorage(null, { failSet: true });
  const result = Core.commitWorkspace({
    storage, key: 'karmopath.admin.drafts.v1', current,
    next: { drafts: [recordDraft('imported', { existing: true, reviewed: true })], currentKey: 'key-imported' },
  });
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'storage-failed');
  assert.equal(result.drafts, oldDrafts);
  assert.equal(result.currentKey, current.currentKey);
  assert.equal(storage.setCalls, 1);
});

test('corrupt storage remains untouched until raw backup and explicit confirmation', () => {
  const raw = '{ broken saved draft bytes';
  const storage = memoryStorage(raw);
  const current = Core.loadWorkspace(storage, 'karmopath.admin.drafts.v1', () => null);
  assert.equal(current.recovery.kind, 'corrupt');
  assert.equal(current.recovery.raw, raw);
  assert.equal(storage.setCalls, 0);

  const next = { drafts: [recordDraft('replacement')], currentKey: 'key-replacement' };
  const ordinaryWrite = Core.commitWorkspace({ storage, key: 'karmopath.admin.drafts.v1', current, next });
  assert.equal(ordinaryWrite.ok, false);
  assert.equal(ordinaryWrite.reason, 'recovery-required');
  assert.equal(storage.value, raw);
  assert.equal(storage.setCalls, 0);

  const noBackup = Core.recoverWorkspace({ storage, key: 'karmopath.admin.drafts.v1', current, backupDownloaded: false, confirmed: true });
  assert.equal(noBackup.ok, false);
  assert.equal(noBackup.reason, 'backup-required');
  const noConfirmation = Core.recoverWorkspace({ storage, key: 'karmopath.admin.drafts.v1', current, backupDownloaded: true, confirmed: false });
  assert.equal(noConfirmation.ok, false);
  assert.equal(noConfirmation.reason, 'confirmation-required');
  assert.equal(storage.value, raw);
  assert.equal(storage.setCalls, 0);

  const recovered = Core.recoverWorkspace({ storage, key: 'karmopath.admin.drafts.v1', current, backupDownloaded: true, confirmed: true });
  assert.equal(recovered.ok, true);
  assert.equal(recovered.recovery, null);
  assert.deepEqual(recovered.drafts, []);
  assert.equal(storage.setCalls, 1);
  assert.deepEqual(JSON.parse(storage.value), { version: 1, drafts: [] });
});

test('unavailable storage cannot be overwritten through ordinary transitions', () => {
  const storage = memoryStorage(null, { failGet: true });
  const current = Core.loadWorkspace(storage, 'karmopath.admin.drafts.v1');
  assert.equal(current.recovery.kind, 'unavailable');
  const result = Core.commitWorkspace({
    storage, key: 'karmopath.admin.drafts.v1', current,
    next: { drafts: [recordDraft('replacement')], currentKey: 'key-replacement' },
  });
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'recovery-required');
  assert.equal(storage.setCalls, 0);
});

test('date-only closing date stays open through the full IST calendar day', () => {
  const job = { kind: 'recruitment', status: 'open', application_end_date: '2026-10-18', application_end_at: null };
  assert.equal(Core.effectiveStatus(job, '2026-10-18T18:29:59.999Z'), 'open'); // 23:59:59.999 IST
  assert.equal(Core.effectiveStatus(job, '2026-10-18T18:30:00.000Z'), 'closed'); // 00:00 IST next day
  assert.equal(job.status, 'open'); // preview-only status never mutates feed data
});

test('exact UTC closing instant is inclusive until the exact instant, then closed', () => {
  const job = { kind: 'recruitment', status: 'open', application_end_date: '2026-10-18', application_end_at: '2026-10-18T16:30:00Z' };
  assert.equal(Core.effectiveStatus(job, '2026-10-18T16:29:59.999Z'), 'open');
  assert.equal(Core.effectiveStatus(job, '2026-10-18T16:30:00.000Z'), 'closed');
});

test('withdrawn status overrides an expired deadline', () => {
  const job = { kind: 'recruitment', status: 'withdrawn', application_end_date: '2020-01-01', application_end_at: null };
  assert.equal(Core.effectiveStatus(job, '2026-10-18T18:30:00Z'), 'withdrawn');
});

const CHECK_NOW = Date.parse('2026-10-18T06:00:00Z');

function checklistJob(id, updates = {}) {
  return {
    id,
    kind: 'recruitment',
    title_bn: 'নমুনা',
    title_en: 'Sample',
    organization: 'Sample organization',
    category: 'office',
    districts: ['West Bengal'],
    qualifications: ['Graduate'],
    status: 'open',
    source_url: 'https://official.example/notice',
    notice_url: 'https://official.example/notice.pdf',
    reviewed_at: '2026-10-18T05:00:00Z',
    published_at: '2026-10-18T04:00:00Z',
    updated_at: '2026-10-18T05:00:00Z',
    summary_bn: 'সারাংশ',
    summary_en: 'Summary',
    how_to_apply_bn: '',
    how_to_apply_en: '',
    vacancies: null,
    application_start_date: null,
    application_end_date: '2026-12-31',
    application_end_at: null,
    exam_date: null,
    apply_url: null,
    age_note_bn: null,
    age_note_en: null,
    ...updates,
  };
}

function checklistField(result, jobId, field) {
  return result.items.find((item) => item.jobId === jobId && item.field === field);
}

test('publish checklist passes a ready job with three deterministic PASS items', () => {
  const result = Core.publishChecklist([checklistJob('ready-1')], CHECK_NOW);
  assert.equal(result.ready, true);
  assert.equal(result.jobsChecked, 1);
  assert.deepEqual(result.items.map((item) => item.field), ['source_url', 'notice_url', 'published_at']);
  assert.ok(result.items.every((item) => item.status === 'PASS'), result.items);
  assert.deepEqual({ passed: result.passed, failed: result.failed, warned: result.warned }, { passed: 3, failed: 0, warned: 0 });
  assert.equal(checklistField(result, 'ready-1', 'published_at').detail.includes('5-minute'), true);
});

test('publish checklist fails missing, empty, and non-HTTPS links with the job id', () => {
  const result = Core.publishChecklist([
    checklistJob('no-source', { source_url: null }),
    checklistJob('empty-notice', { notice_url: '' }),
    checklistJob('http-link', { source_url: 'http://official.example/notice' }),
  ], CHECK_NOW);
  assert.equal(result.ready, false);
  assert.equal(result.failed, 3);
  for (const [jobId, field] of [['no-source', 'source_url'], ['empty-notice', 'notice_url'], ['http-link', 'source_url']]) {
    const item = checklistField(result, jobId, field);
    assert.equal(item.status, 'FAIL');
    assert.match(item.detail, /HTTPS/i);
    assert.match(item.path, /^jobs\[\d+\]$/);
  }
});

test('publish checklist enforces future published_at with the same 5-minute tolerance as the validator', () => {
  const futureFar = Core.publishChecklist(
    [checklistJob('future-job', { published_at: '2099-01-01T00:00:00Z' })], CHECK_NOW);
  assert.equal(checklistField(futureFar, 'future-job', 'published_at').status, 'FAIL');
  assert.match(checklistField(futureFar, 'future-job', 'published_at').detail, /future/i);
  const withinTolerance = Core.publishChecklist(
    [checklistJob('tolerance-job', { published_at: '2026-10-18T06:03:00Z' })], CHECK_NOW);
  assert.equal(checklistField(withinTolerance, 'tolerance-job', 'published_at').status, 'PASS');
  const missing = Core.publishChecklist([checklistJob('missing-time', { published_at: null })], CHECK_NOW);
  assert.equal(checklistField(missing, 'missing-time', 'published_at').status, 'FAIL');
});

test('publish checklist rejects fragments and embedded credentials additively', () => {
  const result = Core.publishChecklist([
    checklistJob('fragment', { notice_url: 'https://official.example/notice.pdf#page=2' }),
    checklistJob('creds', { source_url: 'https://user:pass@official.example/notice' }),
  ], CHECK_NOW);
  assert.equal(result.ready, false);
  assert.match(checklistField(result, 'fragment', 'notice_url').detail, /fragment/i);
  assert.match(checklistField(result, 'creds', 'source_url').detail, /credentials/i);
});

test('publish checklist warns on empty districts/qualifications without failing', () => {
  const result = Core.publishChecklist(
    [checklistJob('statewide-unknown', { districts: [], qualifications: [] })], CHECK_NOW);
  assert.equal(result.ready, true); // warnings never fail the checklist
  assert.equal(result.warned, 2);
  assert.equal(result.failed, 0);
  for (const field of ['districts', 'qualifications']) {
    const item = checklistField(result, 'statewide-unknown', field);
    assert.equal(item.status, 'WARN');
    assert.match(item.detail, /West Bengal/);
  }
  assert.deepEqual(result.items.filter((item) => item.status === 'WARN').map((item) => item.field),
    ['districts', 'qualifications']);
});
