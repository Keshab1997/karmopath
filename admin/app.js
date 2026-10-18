(() => {
  'use strict';

  const STORAGE_KEY = 'karmopath.admin.drafts.v1';
  const Core = window.KarmopathAdminCore;
  const FORM_FIELDS = [
    'id', 'kind', 'title_bn', 'title_en', 'organization', 'category', 'status',
    'vacancies', 'districts', 'qualifications', 'source_url', 'notice_url', 'apply_url',
    'application_start_date', 'application_end_date', 'application_end_at', 'exam_date',
    'summary_bn', 'summary_en', 'how_to_apply_bn', 'how_to_apply_en', 'age_note_bn', 'age_note_en',
  ];
  const REQUIRED_KEYS = [
    'id', 'kind', 'title_bn', 'title_en', 'organization', 'category', 'districts',
    'qualifications', 'status', 'source_url', 'notice_url', 'reviewed_at', 'published_at',
    'updated_at', 'summary_bn', 'summary_en', 'how_to_apply_bn', 'how_to_apply_en',
    'vacancies', 'application_start_date', 'application_end_date', 'application_end_at',
    'exam_date', 'apply_url', 'age_note_bn', 'age_note_en',
  ];
  const $ = (id) => document.getElementById(id);
  const els = {
    draftList: $('draftList'), draftCount: $('draftCount'), fields: $('formFields'),
    title: $('editorTitle'), subtitle: $('editorSubtitle'), reviewState: $('reviewState'),
    feedback: $('feedback'), preview: $('preview'), save: $('saveButton'), review: $('reviewButton'),
    reset: $('resetButton'), remove: $('deleteDraftButton'), importFile: $('importFile'),
    recoveryPanel: $('recoveryPanel'), recoveryMessage: $('recoveryMessage'),
    rawBackupButton: $('rawBackupButton'), confirmRecoveryButton: $('confirmRecoveryButton'),
    newDraftButton: $('newDraftButton'), importButton: $('importButton'),
  };
  let drafts = [];
  let currentKey = null;
  let storageRecovery = null;
  let previewLanguage = 'bn';
  let previewExpiryTimer = null;

  function blankData() {
    return {
      id: '', kind: 'recruitment', title_bn: '', title_en: '', organization: '', category: 'other',
      districts: [], qualifications: [], status: 'open', source_url: '', notice_url: '',
      reviewed_at: null, published_at: null, updated_at: null, summary_bn: '', summary_en: '',
      how_to_apply_bn: '', how_to_apply_en: '', vacancies: null, application_start_date: null,
      application_end_date: null, application_end_at: null, exam_date: null, apply_url: null,
      age_note_bn: null, age_note_en: null,
    };
  }

  function makeKey() {
    return `draft-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  }

  function setFeedback(message, type = 'info') {
    els.feedback.textContent = message;
    els.feedback.className = `feedback ${type}`;
    els.feedback.hidden = !message;
  }

  function storageHandle() {
    try { return window.localStorage; }
    catch (_) { return null; }
  }

  function currentWorkspace() {
    return { drafts, currentKey, recovery: storageRecovery };
  }

  function renderRecoveryPanel() {
    const recovery = storageRecovery;
    els.recoveryPanel.hidden = !recovery;
    els.newDraftButton.disabled = Boolean(recovery);
    els.importButton.disabled = Boolean(recovery);
    if (!recovery) return;
    if (recovery.kind === 'corrupt') {
      els.recoveryMessage.textContent = 'Saved draft data is unreadable. Its original bytes have not been changed. Download the raw backup first, then explicitly confirm clearing this browser storage before creating or importing replacements.';
      els.rawBackupButton.disabled = false;
      els.confirmRecoveryButton.disabled = !recovery.backupDownloaded;
    } else {
      els.recoveryMessage.textContent = 'Browser storage could not be read, so existing data cannot be safely replaced. No raw backup is accessible here. Use manual export if any drafts are available; refresh after restoring browser storage access.';
      els.rawBackupButton.disabled = true;
      els.confirmRecoveryButton.disabled = true;
    }
  }

  function applyWorkspaceResult(result) {
    if (!result.ok) {
      if (result.reason === 'recovery-required' || result.reason === 'backup-required' || result.reason === 'confirmation-required') {
        setFeedback('Workspace unchanged. Download the raw recovery backup and complete the explicit recovery confirmation before replacing unreadable storage.', 'error');
      } else if (result.reason === 'raw-backup-unavailable') {
        setFeedback('Workspace unchanged. Raw recovery data is unavailable; no replacement was attempted.', 'error');
      } else {
        setFeedback('Browser storage write failed. The saved workspace and selection were kept. Export drafts now, check storage availability, then retry.', 'error');
      }
      return false;
    }
    drafts = result.drafts;
    currentKey = result.currentKey;
    storageRecovery = result.recovery;
    renderRecoveryPanel();
    return true;
  }

  function commitDrafts(nextDrafts, nextKey) {
    const result = Core.commitWorkspace({
      storage: storageHandle(), key: STORAGE_KEY, current: currentWorkspace(),
      next: { drafts: nextDrafts, currentKey: nextKey },
    });
    return applyWorkspaceResult(result);
  }

  function checkDraftData(data) {
    if (!data || typeof data !== 'object' || Array.isArray(data)) return false;
    if (!REQUIRED_KEYS.every((key) => Object.prototype.hasOwnProperty.call(data, key))) return false;
    const arrayKeys = ['districts', 'qualifications'];
    const nullableStrings = [
      'reviewed_at', 'published_at', 'updated_at', 'application_start_date',
      'application_end_date', 'application_end_at', 'exam_date', 'apply_url', 'age_note_bn', 'age_note_en',
    ];
    for (const key of arrayKeys) {
      if (!Array.isArray(data[key]) || data[key].some((item) => typeof item !== 'string')) return false;
    }
    for (const key of nullableStrings) {
      if (data[key] !== null && typeof data[key] !== 'string') return false;
    }
    for (const key of REQUIRED_KEYS.filter((key) => !arrayKeys.includes(key) && !nullableStrings.includes(key) && key !== 'vacancies')) {
      if (typeof data[key] !== 'string') return false;
    }
    return data.vacancies === null || (Number.isInteger(data.vacancies) && data.vacancies >= 0);
  }

  function hydrateDraft(item) {
    if (!item || typeof item !== 'object' || typeof item.key !== 'string' ||
        typeof item.reviewed !== 'boolean' || typeof item.existing !== 'boolean' ||
        typeof item.idLocked !== 'boolean' || !checkDraftData(item.data)) return null;
    return { key: item.key, data: { ...blankData(), ...item.data }, reviewed: item.reviewed,
      existing: item.existing, idLocked: item.idLocked };
  }

  function readStorage() {
    const loaded = Core.loadWorkspace(storageHandle(), STORAGE_KEY, hydrateDraft);
    drafts = loaded.drafts;
    currentKey = loaded.currentKey;
    storageRecovery = loaded.recovery;
    renderRecoveryPanel();
    if (storageRecovery) {
      const message = storageRecovery.kind === 'corrupt'
        ? 'Unreadable saved drafts were left untouched. Download the raw backup and confirm recovery before replacing them.'
        : 'Browser storage is unavailable. The workspace is read-only until storage access returns.';
      setFeedback(message, 'error');
    }
  }

  function selectedDraft() {
    return drafts.find((draft) => draft.key === currentKey) || null;
  }

  function fillForm(data) {
    for (const id of FORM_FIELDS) {
      const input = $(id);
      if (!input) continue;
      if (id === 'districts' || id === 'qualifications') input.value = Array.isArray(data[id]) ? data[id].join('\n') : '';
      else if (id === 'vacancies') input.value = data[id] == null ? '' : String(data[id]);
      else input.value = data[id] == null ? '' : String(data[id]);
    }
  }

  function readForm() {
    const draft = selectedDraft();
    const data = { ...(draft ? draft.data : blankData()) };
    for (const id of FORM_FIELDS) {
      const value = $(id).value;
      if (id === 'districts' || id === 'qualifications') {
        data[id] = value.split(/[\n,]/).map((part) => part.trim()).filter(Boolean);
      } else if (id === 'vacancies') {
        data[id] = value.trim() === '' ? null : Number(value);
      } else if (['application_start_date', 'application_end_date', 'application_end_at', 'exam_date', 'apply_url', 'age_note_bn', 'age_note_en'].includes(id)) {
        data[id] = value.trim() === '' ? null : value.trim();
      } else {
        data[id] = value.trim();
      }
    }
    return data;
  }

  function renderList() {
    els.draftList.replaceChildren();
    els.draftCount.textContent = `${drafts.length} ${drafts.length === 1 ? 'item' : 'items'}`;
    if (!drafts.length) {
      const empty = document.createElement('div');
      empty.className = 'empty-list';
      empty.textContent = 'No local drafts yet. Start with New draft.';
      els.draftList.append(empty);
    }
    for (const draft of drafts) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'draft-item';
      button.setAttribute('aria-current', String(draft.key === currentKey));
      const title = document.createElement('strong');
      title.textContent = draft.data.title_bn || draft.data.title_en || draft.data.id || 'Untitled draft';
      const status = document.createElement('small');
      status.textContent = draft.existing && !draft.reviewed
        ? 'Existing record · re-review required'
        : (draft.reviewed ? 'Reviewed · candidate only' : 'New draft · not reviewed');
      button.append(title, status);
      button.addEventListener('click', () => selectDraft(draft.key));
      els.draftList.append(button);
    }
  }

  function renderEditor() {
    const draft = selectedDraft();
    const enabled = Boolean(draft);
    els.fields.disabled = !enabled;
    els.save.disabled = !enabled;
    els.review.disabled = !enabled;
    els.reset.disabled = !enabled;
    els.remove.disabled = !enabled;
    if (!draft) {
      currentKey = null;
      els.title.textContent = 'Choose or create a draft';
      els.subtitle.textContent = 'Drafts are not published.';
      els.reviewState.textContent = '—';
      fillForm(blankData());
      $('id').disabled = false;
      $('idHint').textContent = 'Lowercase letters, numbers, hyphens; freeze after first review.';
      renderPreview(null);
      return;
    }
    fillForm(draft.data);
    $('id').disabled = draft.idLocked;
    $('idHint').textContent = draft.idLocked ? 'ID is frozen after initial candidate review.' : 'Lowercase letters, numbers, hyphens; freeze after first review.';
    els.title.textContent = draft.data.title_en || draft.data.title_bn || 'Untitled draft';
    els.subtitle.textContent = draft.existing ? 'Imported candidate · published_at is preserved.' : 'Local draft · nothing is published by this tool.';
    els.reviewState.textContent = draft.reviewed ? 'REVIEWED CANDIDATE' : (draft.existing ? 'RE-REVIEW NEEDED' : 'DRAFT');
    renderPreview(draft.data);
  }

  function renderAll() {
    renderRecoveryPanel();
    renderList();
    renderEditor();
  }

  function selectDraft(key) {
    currentKey = key;
    renderAll();
    setFeedback('', 'info');
  }

  function newDraft() {
    const draft = { key: makeKey(), data: blankData(), reviewed: false, existing: false, idLocked: false };
    const nextDrafts = [draft, ...drafts];
    if (!commitDrafts(nextDrafts, draft.key)) return;
    renderAll();
    setFeedback('New local draft created. Save it to keep changes in this browser.', 'info');
    $('id').focus();
  }

  function validDate(value) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    const [year, month, day] = value.split('-').map(Number);
    const date = new Date(Date.UTC(year, month - 1, day));
    return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
  }

  function validTimestamp(value) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value) ||
        !validDate(value.slice(0, 10))) return false;
    const hour = Number(value.slice(11, 13));
    const minute = Number(value.slice(14, 16));
    const second = Number(value.slice(17, 19));
    return hour <= 23 && minute <= 59 && second <= 59 && Number.isFinite(Date.parse(value));
  }

  function checkHttps(value, path, errors, nullable = false) {
    if (value === null && nullable) return;
    if (typeof value !== 'string' || !value.trim() || /\s/.test(value)) {
      errors.push(`${path}: must be an HTTPS URL${nullable ? ' or null' : ''}`); return;
    }
    try {
      const url = new URL(value);
      if (url.protocol !== 'https:' || !url.hostname || url.username || url.password) {
        errors.push(`${path}: must be an HTTPS URL without embedded credentials`);
      }
    } catch (_) { errors.push(`${path}: must be a valid HTTPS URL`); }
  }

  function validateJob(job, path, nowMs = Date.now()) {
    const errors = [];
    if (!job || typeof job !== 'object' || Array.isArray(job)) return [`${path}: must be an object`];
    for (const key of REQUIRED_KEYS) if (!Object.prototype.hasOwnProperty.call(job, key)) errors.push(`${path}.${key}: required field is missing`);
    if (typeof job.id !== 'string' || !/^[a-z0-9-]{1,100}$/.test(job.id)) errors.push(`${path}.id: must match [a-z0-9-] and be 1–100 characters`);
    for (const key of ['title_bn', 'title_en', 'organization', 'summary_bn', 'summary_en', 'how_to_apply_bn', 'how_to_apply_en']) {
      const value = job[key];
      const allowEmpty = key.startsWith('how_to_apply_');
      if (typeof value !== 'string' || (!allowEmpty && !value.trim())) errors.push(`${path}.${key}: must be ${allowEmpty ? 'a string' : 'a non-empty string'}`);
      else if (/<\/?[a-z][^>]*>/i.test(value)) errors.push(`${path}.${key}: HTML markup is not allowed`);
    }
    for (const key of ['age_note_bn', 'age_note_en']) {
      const value = job[key];
      if (value !== null && typeof value !== 'string') errors.push(`${path}.${key}: must be a string or null`);
      else if (typeof value === 'string' && /<\/?[a-z][^>]*>/i.test(value)) errors.push(`${path}.${key}: HTML markup is not allowed`);
    }
    const enums = { kind: ['recruitment', 'result', 'admit_card'], category: ['police', 'railway', 'banking', 'teaching', 'medical', 'office', 'other'], status: ['open', 'closed', 'withdrawn', 'published'] };
    for (const [key, values] of Object.entries(enums)) if (typeof job[key] !== 'string' || !values.includes(job[key])) errors.push(`${path}.${key}: has an unknown value`);
    for (const key of ['districts', 'qualifications']) if (!Array.isArray(job[key]) || job[key].some((item) => typeof item !== 'string' || !item.trim())) errors.push(`${path}.${key}: must be an array of non-empty strings`);
    checkHttps(job.source_url, `${path}.source_url`, errors);
    checkHttps(job.notice_url, `${path}.notice_url`, errors);
    checkHttps(job.apply_url, `${path}.apply_url`, errors, true);
    const times = {};
    for (const key of ['reviewed_at', 'published_at', 'updated_at']) {
      if (!validTimestamp(job[key])) errors.push(`${path}.${key}: must be an ISO 8601 UTC timestamp ending in Z`);
      else times[key] = Date.parse(job[key]);
    }
    if (job.application_end_at !== null) {
      if (!validTimestamp(job.application_end_at)) errors.push(`${path}.application_end_at: must be a UTC timestamp ending in Z or null`);
    }
    for (const key of ['application_start_date', 'application_end_date', 'exam_date']) {
      if (job[key] !== null && !validDate(job[key])) errors.push(`${path}.${key}: must be a valid YYYY-MM-DD date or null`);
    }
    if (validDate(job.application_start_date) && validDate(job.application_end_date) && job.application_start_date > job.application_end_date) errors.push(`${path}.application_start_date: must not be after application_end_date`);
    if (job.vacancies !== null && (!Number.isInteger(job.vacancies) || job.vacancies < 0)) errors.push(`${path}.vacancies: must be a non-negative integer or null`);
    if (times.updated_at !== undefined && times.published_at !== undefined && times.updated_at < times.published_at) errors.push(`${path}.updated_at: must be at or after published_at`);
    if (times.reviewed_at !== undefined && times.updated_at !== undefined && times.reviewed_at > times.updated_at) errors.push(`${path}.reviewed_at: must be at or before updated_at`);
    for (const key of ['reviewed_at', 'published_at']) if (times[key] !== undefined && times[key] > nowMs + 5 * 60 * 1000) errors.push(`${path}.${key}: must not be more than 5 minutes in the future`);
    if (job.kind === 'recruitment' && job.status === 'open' && job.application_end_date === null) errors.push(`${path}.application_end_date: is required for open recruitment`);
    if (['result', 'admit_card'].includes(job.kind) && ['open', 'closed'].includes(job.status)) errors.push(`${path}.status: result/admit_card must use published or withdrawn`);
    return errors;
  }

  function validateFeed(feed) {
    if (!feed || typeof feed !== 'object' || Array.isArray(feed)) return ['feed: must be an object'];
    const errors = [];
    if (feed.schema_version !== 1 || !Number.isInteger(feed.schema_version)) errors.push('schema_version: must be integer 1');
    if (!validTimestamp(feed.updated_at)) errors.push('updated_at: must be an ISO 8601 UTC timestamp ending in Z');
    if (!Array.isArray(feed.jobs)) return [...errors, 'jobs: must be an array'];
    const seen = new Set();
    feed.jobs.forEach((job, index) => {
      errors.push(...validateJob(job, `jobs[${index}]`));
      if (job && typeof job === 'object' && typeof job.id === 'string') {
        if (seen.has(job.id)) errors.push(`jobs[${index}].id: duplicate id ${JSON.stringify(job.id)}`);
        seen.add(job.id);
      }
    });
    return errors;
  }

  function appendText(parent, tag, text, className) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    node.textContent = text;
    parent.append(node);
    return node;
  }

  function renderPreview(data) {
    if (previewExpiryTimer !== null) clearTimeout(previewExpiryTimer);
    previewExpiryTimer = null;
    els.preview.replaceChildren();
    if (!data) {
      els.preview.className = 'preview-placeholder';
      els.preview.textContent = 'Choose a draft to preview it. / পূর্বরূপ দেখতে একটি খসড়া বাছুন।';
      return;
    }
    const deadline = Core.closingDeadlineMilliseconds(data);
    if (deadline !== null && deadline > Date.now()) {
      previewExpiryTimer = setTimeout(() => renderPreview(selectedDraft()?.data || null), Math.min(deadline - Date.now() + 5, 2147483647));
    }
    els.preview.className = 'job-card';
    const isBn = previewLanguage === 'bn';
    const top = document.createElement('div'); top.className = 'job-top';
    const left = document.createElement('div');
    appendText(left, 'div', data.kind.replace('_', ' '), 'job-type');
    appendText(left, 'h3', (isBn ? data.title_bn : data.title_en) || 'Untitled opportunity');
    appendText(left, 'div', data.organization || (isBn ? 'সংস্থার নাম' : 'Organization'), 'org');
    const statusLabels = isBn ? { open: 'আবেদন চলছে', closed: 'বন্ধ', withdrawn: 'প্রত্যাহৃত', published: 'প্রকাশিত' } : { open: 'Open', closed: 'Closed', withdrawn: 'Withdrawn', published: 'Published' };
    const displayStatus = Core.effectiveStatus(data, new Date());
    const statusBadge = document.createElement('span');
    statusBadge.className = `status ${displayStatus || ''}`;
    statusBadge.textContent = statusLabels[displayStatus] || 'Draft';
    top.append(left, statusBadge);
    els.preview.append(top);
    const meta = document.createElement('div'); meta.className = 'meta';
    const district = Array.isArray(data.districts) && data.districts.length ? data.districts.join(', ') : (isBn ? 'জেলা অজানা' : 'District not stated');
    const qualifications = Array.isArray(data.qualifications) && data.qualifications.length ? data.qualifications.join(', ') : (isBn ? 'যোগ্যতা বিজ্ঞপ্তি দেখুন' : 'See original notice for qualification');
    const due = data.application_end_date || (isBn ? 'তারিখ উল্লেখ নেই' : 'Date not stated');
    appendText(meta, 'div', `${isBn ? 'জেলা' : 'District'}: ${district}`);
    appendText(meta, 'div', `${isBn ? 'যোগ্যতা' : 'Qualification'}: ${qualifications}`);
    appendText(meta, 'div', `${isBn ? 'শেষ তারিখ' : 'Closing date'}: ${due}`);
    if (data.vacancies !== null && data.vacancies !== '') appendText(meta, 'div', `${isBn ? 'শূন্যপদ' : 'Vacancies'}: ${data.vacancies}`);
    els.preview.append(meta);
    const addPreviewSection = (label, value) => {
      if (!value) return;
      const section = document.createElement('div'); section.className = 'preview-section';
      appendText(section, 'b', label); appendText(section, 'p', value); els.preview.append(section);
    };
    addPreviewSection(isBn ? 'সংক্ষিপ্ত বিবরণ' : 'Summary', isBn ? data.summary_bn : data.summary_en);
    addPreviewSection(isBn ? 'আবেদনের পদ্ধতি' : 'How to apply', isBn ? data.how_to_apply_bn : data.how_to_apply_en);
    if (data.age_note_bn || data.age_note_en) addPreviewSection(isBn ? 'বয়স সংক্রান্ত তথ্য' : 'Age note', isBn ? data.age_note_bn : data.age_note_en);
    const links = document.createElement('div'); links.className = 'preview-links';
    for (const [label, value] of [[isBn ? 'মূল সূত্র' : 'Official source', data.source_url], [isBn ? 'বিজ্ঞপ্তি' : 'Original notice', data.notice_url], [isBn ? 'আবেদন লিঙ্ক' : 'Apply link', data.apply_url]]) {
      if (typeof value !== 'string') continue;
      try {
        const url = new URL(value);
        if (url.protocol !== 'https:' || !url.hostname || url.username || url.password) continue;
        const anchor = document.createElement('a'); anchor.href = url.href; anchor.target = '_blank'; anchor.rel = 'noopener noreferrer'; anchor.textContent = label; links.append(anchor);
      } catch (_) { /* Invalid/incomplete URLs are omitted from preview. */ }
    }
    if (links.childNodes.length) els.preview.append(links);
    appendText(els.preview, 'p', isBn ? 'কর্মপথ একটি স্বাধীন তথ্য প্ল্যাটফর্ম। আবেদন করার আগে মূল সরকারি বিজ্ঞপ্তিতে যোগ্যতা ও তারিখ যাচাই করুন।' : 'Karmopath is an independent information platform. Verify eligibility and dates in the original official notice before applying.', 'preview-caution');
  }

  function saveCurrent() {
    const draft = selectedDraft();
    if (!draft) return;
    const data = readForm();
    const nextDrafts = drafts.map((item) => item.key === draft.key
      ? { ...item, data, reviewed: false }
      : item);
    if (!commitDrafts(nextDrafts, currentKey)) return;
    renderAll();
    setFeedback('Draft saved in this browser only. Export a backup; browser storage is not durable.', 'success');
  }

  function confirmReview() {
    const draft = selectedDraft();
    if (!draft) return;
    if (!window.confirm('Confirm only after checking the original notice, eligibility and dates. This records your review; it does not publish the post. Continue?')) return;
    const data = readForm();
    const now = new Date().toISOString();
    if (!draft.existing || !data.published_at) data.published_at = now;
    data.reviewed_at = now;
    data.updated_at = now;
    const errors = validateJob(data, 'job');
    if (errors.length) {
      setFeedback(`Cannot confirm review yet:\n${errors.map((error) => `• ${error}`).join('\n')}`, 'error');
      return;
    }
    const nextDrafts = drafts.map((item) => item.key === draft.key
      ? { ...item, data, reviewed: true, existing: true, idLocked: true }
      : item);
    if (!commitDrafts(nextDrafts, currentKey)) return;
    renderAll();
    setFeedback('Review attestation saved. This is still a local candidate, not a published post.', 'success');
  }

  function resetCurrent() {
    const draft = selectedDraft();
    if (!draft) return;
    const savedKey = draft.key;
    readStorage();
    currentKey = drafts.some((item) => item.key === savedKey) ? savedKey : (drafts[0]?.key || null);
    renderAll();
    if (storageRecovery) setFeedback('Saved draft could not be restored. Existing storage was left untouched.', 'error');
    else setFeedback('Unsaved edits discarded; restored the last saved local draft.', 'info');
  }

  function deleteCurrent() {
    const draft = selectedDraft();
    if (!draft) return;
    if (!Core.canDeleteDraft(draft)) {
      const requiredStatus = draft.data.kind === 'recruitment' ? 'closed or withdrawn' : 'withdrawn';
      setFeedback(`Existing record ${draft.data.id || '(missing ID)'} cannot be deleted. Keep its ID, set status to ${requiredStatus}, then confirm a fresh source review.`, 'error');
      return;
    }
    if (!window.confirm('Delete this never-published local draft? This cannot be undone.')) return;
    const nextDrafts = drafts.filter((item) => item.key !== draft.key);
    const nextKey = nextDrafts[0]?.key || null;
    if (!commitDrafts(nextDrafts, nextKey)) return;
    renderAll();
    setFeedback('Selected never-published local draft deleted.', 'success');
  }

  function downloadFile(filename, content, type) {
    const blob = new Blob([content], { type });
    const link = document.createElement('a');
    const objectUrl = URL.createObjectURL(blob);
    link.href = objectUrl; link.download = filename; link.hidden = true;
    document.body.append(link); link.click(); link.remove();
    setTimeout(() => URL.revokeObjectURL(objectUrl), 1000);
  }

  function downloadJson(filename, payload) {
    downloadFile(filename, `${JSON.stringify(payload, null, 2)}\n`, 'application/json;charset=utf-8');
  }

  function downloadRawBackup() {
    if (!storageRecovery || storageRecovery.kind !== 'corrupt' || typeof storageRecovery.raw !== 'string') {
      setFeedback('No readable raw storage value is available to back up.', 'error');
      return;
    }
    downloadFile('karmopath-corrupt-local-storage-raw.txt', storageRecovery.raw, 'text/plain;charset=utf-8');
    storageRecovery = { ...storageRecovery, backupDownloaded: true };
    renderRecoveryPanel();
    setFeedback('Raw recovery backup download started. Save that file before confirming storage recovery.', 'info');
  }

  function confirmStorageRecovery() {
    if (!storageRecovery || !storageRecovery.backupDownloaded) {
      setFeedback('Download the raw backup before recovery can continue.', 'error');
      return;
    }
    if (!window.confirm('I have saved the raw backup. Clear only this browser’s unreadable saved draft value and start an empty local workspace?')) return;
    const result = Core.recoverWorkspace({
      storage: storageHandle(), key: STORAGE_KEY, current: currentWorkspace(),
      backupDownloaded: storageRecovery.backupDownloaded, confirmed: true,
    });
    if (!applyWorkspaceResult(result)) return;
    renderAll();
    setFeedback('Recovery confirmed; unreadable storage was replaced only after the raw backup step. Import a validated backup or start a new draft.', 'success');
  }

  function exportDrafts() {
    downloadJson('karmopath-admin-drafts.json', {
      format: 'karmopath-admin-drafts-v1', exported_at: new Date().toISOString(),
      drafts: drafts.map(({ key, data, reviewed, existing, idLocked }) => ({ key, data, reviewed, existing, idLocked })),
    });
    setFeedback('Draft backup exported. Keep this file private; it may contain unpublished editorial work.', 'success');
  }

  function exportCandidate() {
    const plan = Core.planCandidate(drafts);
    if (plan.blockingExistingIds.length) {
      setFeedback(`Candidate export blocked: existing record(s) need re-review and cannot be omitted: ${plan.blockingExistingIds.join(', ')}. Re-review or explicitly close/withdraw each record.`, 'error');
      return;
    }
    if (!plan.jobs.length) {
      const omitted = plan.omittedNewDraftIds.length ? ` New draft(s) not exported: ${plan.omittedNewDraftIds.join(', ')}.` : '';
      setFeedback(`No reviewed records to export. Confirm a genuine source review first.${omitted}`, 'error');
      return;
    }
    const candidate = { schema_version: 1, updated_at: new Date().toISOString(), jobs: plan.jobs };
    const errors = validateFeed(candidate);
    if (errors.length) { setFeedback(`Candidate blocked by validation:\n${errors.map((error) => `• ${error}`).join('\n')}`, 'error'); return; }
    downloadJson('karmopath-candidate-feed.json', candidate);
    const omitted = plan.omittedNewDraftIds.length
      ? ` New never-published draft(s) omitted: ${plan.omittedNewDraftIds.join(', ')}.`
      : '';
    setFeedback(`Candidate feed exported with ${plan.jobs.length} reviewed record(s).${omitted} Nothing was published; run the CLI validator and ask the captain to review.`, 'success');
  }

  function validDraftBundle(value) {
    if (!value || value.format !== 'karmopath-admin-drafts-v1' || !Array.isArray(value.drafts)) return false;
    const hydrated = value.drafts.map(hydrateDraft);
    return hydrated.every(Boolean) && new Set(hydrated.map((draft) => draft.key)).size === hydrated.length;
  }

  async function importFile(file) {
    if (!file) return;
    if (storageRecovery) {
      setFeedback('Import blocked. Download the raw recovery backup and explicitly recover storage before replacing the workspace.', 'error');
      return;
    }
    let value;
    try { value = JSON.parse(await file.text()); }
    catch (_) { setFeedback('Import rejected: file is not valid JSON. Nothing was changed.', 'error'); return; }
    let imported;
    const isDraftBundle = value && value.format === 'karmopath-admin-drafts-v1';
    if (isDraftBundle) {
      if (!validDraftBundle(value)) { setFeedback('Import rejected: saved-drafts file has an unsupported or malformed structure. Nothing was changed.', 'error'); return; }
      imported = value.drafts.map(hydrateDraft);
    } else {
      const errors = validateFeed(value);
      if (errors.length) { setFeedback(`Import rejected; candidate feed failed validation. Existing drafts were not replaced:\n${errors.map((error) => `• ${error}`).join('\n')}`, 'error'); return; }
      imported = value.jobs.map((data) => ({ key: makeKey(), data: { ...blankData(), ...data }, reviewed: true, existing: true, idLocked: true }));
    }
    const kind = isDraftBundle ? 'saved drafts' : 'candidate feed';
    if (!window.confirm(`Replace the current ${drafts.length} local draft(s) with ${imported.length} validated ${kind}? This changes only this browser's local workspace.`)) return;
    const nextKey = imported[0]?.key || null;
    if (!commitDrafts(imported, nextKey)) return;
    renderAll();
    setFeedback(`${imported.length} ${kind} imported after validation. No network request was made.`, 'success');
  }

  els.newDraftButton.addEventListener('click', newDraft);
  els.rawBackupButton.addEventListener('click', downloadRawBackup);
  els.confirmRecoveryButton.addEventListener('click', confirmStorageRecovery);
  els.save.addEventListener('click', saveCurrent);
  els.review.addEventListener('click', confirmReview);
  els.reset.addEventListener('click', resetCurrent);
  els.remove.addEventListener('click', deleteCurrent);
  $('draftExportButton').addEventListener('click', exportDrafts);
  $('candidateExportButton').addEventListener('click', exportCandidate);
  els.importButton.addEventListener('click', () => els.importFile.click());
  els.importFile.addEventListener('change', (event) => { importFile(event.target.files?.[0]); event.target.value = ''; });
  for (const id of FORM_FIELDS) $(id).addEventListener('input', () => {
    const draft = selectedDraft();
    if (!draft) return;
    draft.data = readForm();
    if (draft.reviewed) draft.reviewed = false;
    els.reviewState.textContent = draft.existing ? 'RE-REVIEW NEEDED' : 'DRAFT · UNSAVED';
    renderPreview(draft.data);
    renderList();
  });
  for (const button of document.querySelectorAll('.lang-switch button')) button.addEventListener('click', () => {
    previewLanguage = button.dataset.lang;
    for (const item of document.querySelectorAll('.lang-switch button')) item.setAttribute('aria-pressed', String(item === button));
    renderPreview(selectedDraft()?.data || null);
  });

  readStorage();
  renderAll();
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) renderPreview(selectedDraft()?.data || null);
  });
})();
