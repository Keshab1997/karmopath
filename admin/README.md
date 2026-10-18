# Karmopath local manual-post admin

This is a dependency-free, browser-local editor for human-reviewed candidate posts. It is not a service, login system, publisher, or secure multi-user admin. No post is published by this tool.

## Open the workspace

1. Open `admin/index.html` directly in a modern browser (or use a local static file preview). The page, `admin-core.js`, and `app.js` have no CDN, remote scripts, fonts, API calls, or network dependencies.
2. Choose **New draft**, enter both Bengali and English content, and use the official source page and original notice links. Leave unknown facts blank/null; do not infer eligibility, dates, or vacancies.
3. Save drafts in browser local storage, and export a private draft backup regularly. Browser storage is not durable backup. Draft exports can contain unpublished editorial work; keep them out of git and public feeds. If saved data is unreadable, ordinary create/import actions are blocked: download the raw stored value first, then explicitly confirm recovery before replacing it. If storage itself is unavailable, no replacement is attempted; manual exports remain available.
4. Import an existing candidate feed or a saved draft backup. The tool validates an entire candidate feed before offering replacement; a bad import leaves the current workspace unchanged. Replacing drafts requires confirmation.
5. Preview in Bengali or English. The preview and imported values are rendered as text, not HTML. The tool only links to HTTPS URLs and never fetches the linked pages.
6. After personally checking the original notice, eligibility, and dates, use **Confirm source review**. This records an owner attestation; it does not prove that a source is official. A new item gets a candidate `published_at` initialized to the review time. That time is not a publication event; the captain must set the actual timestamp when approving the candidate.
7. **Export candidate** includes reviewed records only, blocks if any existing record still needs review, and names any omitted new drafts. It downloads `karmopath-candidate-feed.json`; there is no publish action or endpoint. Run the CLI validator and review the candidate diff before any separately approved publication.

## Local export, validation, and comparison handoff

The candidate export is a local review artifact, not a publication. Keep it separate from the exact local snapshot of the currently published schema-v1 feed. From the repository root, validate first and then compare:

```sh
python3 tools/feed/validate.py path/to/karmopath-candidate-feed.json
python3 tools/feed/compare.py path/to/currently-published-feed.json path/to/karmopath-candidate-feed.json
```

The comparison validates **both** files before summarizing added, unchanged, changed (with field names), withdrawn, and missing IDs in deterministic ID order. It rejects invalid/duplicate IDs, prior-ID deletion (including remove-plus-add replacement), a backwards feed envelope or existing-job `updated_at`, a changed existing `published_at`, and content changes without both advancing `updated_at` and a fresh advancing `reviewed_at`. Timestamp ordering uses parsed UTC instants, including fractional seconds. Equivalent spellings of `application_end_at` also compare as instants, not content edits. Field additions/removals (even null-valued extensions) and JSON value/type changes require fresh review; object-key order does not. Unchanged content may keep its timestamps; valid additions and a schema-v1 empty-baseline bootstrap are allowed. A passing result only establishes contract/comparison consistency; it does not authenticate sources, establish truth, or authorize publication. Both commands are offline, read-only, and report nonzero on errors.

After a passing comparison, a human must review the **original source and notice** for every new or changed item, inspect the listed field changes and withdrawals, reconfirm eligibility and deadlines, and decide whether the candidate is appropriate. Neither tool fetches sources or performs publication. Only after that review may the separately authorized feed owner hand the approved artifact to the existing publication process; this admin and the comparison CLI have no upload or publish action.

Before any separately authorized publication, retain the last known-good published feed and its publication record, plan cache/CDN invalidation and propagation, and verify the served feed after cache expiry/invalidation. Keep a rollback plan that accounts for caches and preserves auditability. Do not blindly restore an old timestamped object as a new candidate: this gate rejects backwards envelope/job timestamps, and existing IDs must retain `published_at`; an approved rollback/reversion may need to be represented as a newly reviewed, advancing candidate. None of these publication or rollback actions are performed here.

## Validator and tests

From the repository root:

```sh
python3 tools/feed/validate.py path/to/karmopath-candidate-feed.json
python3 tools/feed/compare.py path/to/currently-published-feed.json path/to/karmopath-candidate-feed.json
python3 -m unittest discover -s tests/feed
node --check admin/admin-core.js
node --check admin/app.js
node --test tests/feed/admin_behavior_test.js tests/feed/admin_ui_flow_test.js
```

The validator uses Python's standard library only, performs no network requests, and writes no feed or repository files. The Node suite exercises shared state rules and `app.js` events through a deterministic fake DOM. For a real-browser smoke, install tooling outside the repo (no production dependency is added):

```sh
npm install --prefix /home/user/c3-browser-tools playwright
PLAYWRIGHT_BROWSERS_PATH=/home/user/c3-browser-tools/browsers \
  /home/user/c3-browser-tools/node_modules/.bin/playwright install chromium
PLAYWRIGHT_MODULE=/home/user/c3-browser-tools/node_modules/playwright \
PLAYWRIGHT_BROWSERS_PATH=/home/user/c3-browser-tools/browsers \
  node tests/feed/admin_browser_smoke.js
```

The smoke starts a static server bound only to `127.0.0.1`, uses `test/fixtures/sample_feed.json`, and aborts every browser request outside that local origin. It covers real Chromium import/edit/review/export/CLI validation, unsafe content, storage recovery, and desktop/320px layout. It does not publish or contact any source site. Exit status is `0` for a structurally valid schema-v1 candidate and nonzero for malformed JSON, inaccessible files, or field-path validation errors. Structural validity does not establish official-source authenticity or human review; those remain human responsibilities.

## Data safety and boundaries

- No credentials, applicant data, or private information belongs in drafts.
- No browser GitHub token, authentication theater, scraping, remote HTML, open publishing endpoint, or secret is used.
- Do not commit private drafts or backup exports. The app draft storage key is local to this browser profile.
- Candidate export is separate from draft backup. A pending review on any existing record blocks the entire export; new, never-published drafts may be omitted but are named in the export message. Existing records cannot be deleted; use a reviewed closed/withdrawn status to retain their ID.
- Preview derives `Closed` at the exact UTC closing instant or after the inclusive date-only day ends at midnight Asia/Kolkata. This is display-only; it does not mutate the declared feed status.
- IDs are locked after the first successful review. Edits to an imported or reviewed record require a fresh review; existing `published_at` is preserved.
- Never-published drafts can be deleted only after confirmation. Existing records cannot be physically removed; represent a closure or withdrawal with the same ID and a fresh review.
- The CLI mirrors the frozen v1 job/feed contract where applicable. It validates shape, types, enum values, dates, URLs, timestamp order, duplicate IDs, and status rules. It cannot verify the real-world source, notice contents, or editorial truth.
