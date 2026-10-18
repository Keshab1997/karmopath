# Agent C — publish-readiness checklist (offline, no upload)

Repository: `Keshab1997/karmopath.git` (public).
Read `AGENTS.md`, `docs/CONTRACTS.md`, `docs/BATCH_5.md`, `docs/ADMIN.md`, `docs/POLICY.md` and this brief. Batch 5 is now squash-integrated (`2f4ae45`); old `agent/C/**` branches are stale. **Start a NEW branch from `2f4ae45` (origin/main)**, do not continue/merge/cherry-pick any old branch. Do not rebase/force-push/main-merge.

Captain owns shared surfaces/dependencies, `lib/app/**`, `lib/main.dart`, `lib/contracts/**`, `test/contracts/**`, `android/ios`, `workflows`, root docs/assets and generated/version files. Only the listed report is an extra write exception. No new dependencies, secret handling, remote scraping, feed publication, deployment, workflow dispatch, `build`/`gradlew`, tags/releases or repository settings changes. Use your own pairing; never copy credentials. Work under `/home/user`. Other workers are independent; do not wait for or import their new code.

**Branch:** `agent/C/publish-check-v1` from the frozen base above.

**Allowed writes ONLY:** `admin/**`, `tools/feed/**`, `tests/feed/**`, `docs/reports/C6.md`. Do not write real notices, root docs, fixture originals, workflows or remote publication tooling.

## Implement

Add an offline checklist that proves a candidate feed is ready for human publication — it does **not** publish, upload or change browser storage format.

- CLI `tools/feed/check_publish.py`: reuse `validate.py` (do not fork rules), validate candidate, then check that every job has nonempty `source_url` + `notice_url` as absolute HTTPS (no credentials/fragment), that `published_at` is present and not in the future, and that at least one `districts`/`qualifications` entry exists where applicable. Reject with actionable job IDs/field paths. Exit 0 only when validation + checklist pass. No network/Git write/upload.
- Admin UI (`admin/app.js` + `admin/index.html` + `admin/README.md`): after an export validates, show a checklist panel listing the same checks per job (source/notice/published_at) with pass/fail counts. Checklist is read-only display; it does not block export and does not auto-approve. Keep existing dirty-tracking/review guards untouched.
- Keep `tools/feed/compare.py` untouched; this is additive, not a replacement. Document in `admin/README.md` the handoff: export → validate → compare (if baseline) → checklist → human verify source/dates → owner-authorized publication (separate step).

## Evidence

Python tests: valid feed passes checklist, missing source_url/notice_url fails with job ID, future published_at fails, null source_url flagged, empty districts warning where required, deterministic output. Rerun all `tests/feed` Python + 26 Node admin tests (or document NOT RUN if browser missing) + syntax checks + `tool/preflight.py`. Existing validator/compare compatibility unchanged.

Deliver: push branch + `C6.md` (commands, results, limitations, manual publication boundary), exactly five-line ready report and immutable SHA. No workflow/build/release/publication.

