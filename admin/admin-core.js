/* Shared, dependency-free state rules used by the browser UI and Node behavior tests. */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.KarmopathAdminCore = api;
})(typeof globalThis === 'object' ? globalThis : this, function () {
  'use strict';

  const IST_OFFSET_MINUTES = 5 * 60 + 30;

  function validDateOnly(value) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
    const [year, month, day] = value.split('-').map(Number);
    const date = new Date(Date.UTC(year, month - 1, day));
    if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null;
    return { year, month, day };
  }

  function timestampMilliseconds(value) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value) || !validDateOnly(value.slice(0, 10))) return null;
    const hour = Number(value.slice(11, 13));
    const minute = Number(value.slice(14, 16));
    const second = Number(value.slice(17, 19));
    if (hour > 23 || minute > 59 || second > 59) return null;
    const milliseconds = Date.parse(value);
    return Number.isFinite(milliseconds) ? milliseconds : null;
  }

  function closingDeadlineMilliseconds(job) {
    if (!job || job.kind !== 'recruitment' || job.status !== 'open') return null;
    const exact = timestampMilliseconds(job.application_end_at);
    if (exact !== null) return exact;
    const date = validDateOnly(job.application_end_date);
    if (!date) return null;
    // Date-only deadline is inclusive for the full date in Asia/Kolkata.
    // Midnight IST on the following day is 18:30Z on the given date.
    return Date.UTC(date.year, date.month - 1, date.day + 1) - IST_OFFSET_MINUTES * 60 * 1000;
  }

  function effectiveStatus(job, now = Date.now()) {
    if (!job || typeof job.status !== 'string') return 'draft';
    if (job.status === 'withdrawn') return 'withdrawn';
    if (job.kind !== 'recruitment' || job.status !== 'open') return job.status;
    const deadline = closingDeadlineMilliseconds(job);
    const nowMilliseconds = now instanceof Date ? now.getTime() : (typeof now === 'number' ? now : Date.parse(now));
    if (deadline === null || !Number.isFinite(nowMilliseconds)) return job.status;
    return nowMilliseconds >= deadline ? 'closed' : 'open';
  }

  function recordId(draft) {
    return (draft && draft.data && draft.data.id) || (draft && draft.key) || '(missing ID)';
  }

  function planCandidate(drafts) {
    const blockingExistingIds = [];
    const omittedNewDraftIds = [];
    const jobs = [];
    for (const draft of drafts) {
      if (draft.existing && !draft.reviewed) blockingExistingIds.push(recordId(draft));
      if (!draft.existing && !draft.reviewed) omittedNewDraftIds.push(recordId(draft));
      if (draft.reviewed) jobs.push(draft.data);
    }
    return { ok: blockingExistingIds.length === 0, jobs, blockingExistingIds, omittedNewDraftIds };
  }

  function canDeleteDraft(draft) {
    return Boolean(draft) && !draft.existing;
  }

  function emptyWorkspace(recovery = null) {
    return { drafts: [], currentKey: null, recovery };
  }

  function loadWorkspace(storage, key, hydrate = (value) => value) {
    let raw;
    try {
      if (!storage || typeof storage.getItem !== 'function') throw new Error('browser storage is unavailable');
      raw = storage.getItem(key);
    } catch (error) {
      return { ...emptyWorkspace({ kind: 'unavailable', raw: null, backupDownloaded: false }), error: String(error && error.message || error) };
    }
    if (raw === null) return emptyWorkspace();
    try {
      const parsed = JSON.parse(raw);
      if (!parsed || parsed.version !== 1 || !Array.isArray(parsed.drafts)) throw new Error('unexpected saved format');
      const drafts = parsed.drafts.map(hydrate);
      if (drafts.some((draft) => !draft)) throw new Error('saved drafts are malformed');
      const keys = drafts.map((draft) => draft.key);
      if (new Set(keys).size !== keys.length) throw new Error('saved draft keys are duplicated');
      return { drafts, currentKey: drafts[0] ? drafts[0].key : null, recovery: null };
    } catch (error) {
      return { ...emptyWorkspace({ kind: 'corrupt', raw, backupDownloaded: false }), error: String(error && error.message || error) };
    }
  }

  function commitWorkspace({ storage, key, current, next, allowRecovery = false }) {
    if (current.recovery && !allowRecovery) {
      return { ok: false, ...current, reason: 'recovery-required' };
    }
    try {
      if (!storage || typeof storage.setItem !== 'function') throw new Error('browser storage is unavailable');
      storage.setItem(key, JSON.stringify({ version: 1, drafts: next.drafts }));
      return { ok: true, drafts: next.drafts, currentKey: next.currentKey, recovery: null };
    } catch (error) {
      return { ok: false, ...current, reason: 'storage-failed', error: String(error && error.message || error) };
    }
  }

  function recoverWorkspace({ storage, key, current, backupDownloaded, confirmed }) {
    if (!current.recovery || current.recovery.kind !== 'corrupt' || typeof current.recovery.raw !== 'string') {
      return { ok: false, ...current, reason: 'raw-backup-unavailable' };
    }
    if (!backupDownloaded) return { ok: false, ...current, reason: 'backup-required' };
    if (!confirmed) return { ok: false, ...current, reason: 'confirmation-required' };
    return commitWorkspace({
      storage, key, current, next: emptyWorkspace(), allowRecovery: true,
    });
  }

  // Publication-readiness link rule (additive checklist only; the validator in
  // app.js/tools keeps owning the frozen contract rules). Returns null when the
  // value is a nonempty absolute HTTPS URL without credentials or fragment.
  function httpsLinkIssue(value) {
    if (value === null || value === undefined) return 'is null or missing; publication requires a nonempty absolute HTTPS URL';
    if (typeof value !== 'string' || !value.trim() || /\s/.test(value)) return 'is empty; publication requires a nonempty absolute HTTPS URL';
    let url;
    try { url = new URL(value); } catch (_) { return 'must be an absolute HTTPS URL'; }
    if (url.protocol !== 'https:' || !url.hostname) return 'must be an absolute HTTPS URL';
    if (url.username || url.password) return 'must not embed credentials';
    if (url.hash) return 'must not contain a fragment (#...); link to the page itself';
    return null;
  }

  // Read-only publish-readiness checklist over exported candidate jobs.
  // Mirrors tools/feed/check_publish.py: source_url/notice_url links,
  // published_at presence/future check (same 5-minute clock tolerance as the
  // validator), and empty districts/qualifications warnings. It never blocks
  // or approves anything; it only reports deterministic counts.
  function publishChecklist(jobs, nowMs) {
    const items = [];
    let jobsChecked = 0;
    let passed = 0;
    let failed = 0;
    let warned = 0;
    const list = Array.isArray(jobs) ? jobs : [];
    list.forEach((job, index) => {
      if (!job || typeof job !== 'object' || Array.isArray(job)) return;
      jobsChecked += 1;
      const path = `jobs[${index}]`;
      const jobId = typeof job.id === 'string' && job.id ? job.id : '(missing id)';
      const add = (field, status, detail) => {
        if (status === 'PASS') passed += 1;
        else if (status === 'FAIL') failed += 1;
        else warned += 1;
        items.push({ path, jobId, field, status, detail });
      };
      for (const field of ['source_url', 'notice_url']) {
        const issue = httpsLinkIssue(job[field]);
        add(field, issue ? 'FAIL' : 'PASS', issue || 'nonempty absolute HTTPS, no credentials, no fragment');
      }
      const published = job.published_at;
      if (published === null || published === undefined) {
        add('published_at', 'FAIL', 'is missing; the actual publication time must be set before publication review');
      } else if (timestampMilliseconds(published) === null) {
        add('published_at', 'FAIL', 'must be an ISO 8601 UTC timestamp ending in Z');
      } else if (timestampMilliseconds(published) > nowMs + 5 * 60 * 1000) {
        add('published_at', 'FAIL', 'is in the future; must not be ahead of now beyond the 5-minute clock tolerance');
      } else {
        add('published_at', 'PASS', 'present and not in the future (5-minute clock tolerance)');
      }
      for (const field of ['districts', 'qualifications']) {
        if (Array.isArray(job[field]) && job[field].length === 0) {
          add(field, 'WARN', 'is empty; add at least one entry where applicable (statewide uses the literal "West Bengal")');
        }
      }
    });
    return { items, jobsChecked, passed, failed, warned, ready: failed === 0 };
  }

  return {
    canDeleteDraft,
    closingDeadlineMilliseconds,
    commitWorkspace,
    effectiveStatus,
    httpsLinkIssue,
    loadWorkspace,
    planCandidate,
    publishChecklist,
    recoverWorkspace,
  };
});
