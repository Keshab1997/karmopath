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
