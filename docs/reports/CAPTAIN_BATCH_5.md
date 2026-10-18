# Captain Batch 5 review — A, B and C integrated

## Reviewed immutable inputs
- A: `fd6475fb79134015853c717d92bb05a5a590da0e` (code `ac5bcf9293355f6c4b118ae233bb2b61efcb1001`)
- B: `c1953b4de132d8be6542ff22ecc2b6c36585cd93`
- C: `d63f5cb83a800745cddf8b70059dba479fcb04d7` (code `c227648`)

All three cut from `f09d8bdfd602fc584bbc916d100986d3be86ad76`, file-partitioned, no shared-surface touch.

## A acceptance
Durable registry `karmopath.reminder_state.v1` as single-element string list, schema_version inside doc, monotonic 1..2147483647, strict validation (corrupt/inconsistent/unknownSchema/unreadable/exhausted), serialised queue, per-job applied ledger. No plugin, no OS call, no extra key. Docs note crash window and OS reconciliation requirement. Worker evidence: 40 data tests + 46 adjacent A4 tests pass, analyze clean. Captain independently verified: `flutter test test/data/reminders/reminder_state_test.dart` 40 passed, `flutter analyze lib/data` clean, preflight PASS, `git diff --check` PASS. Scope clean: 5 files only. Integrated as `ce24afb`.

Integration note: ledger entries are intent records, not delivery receipts; captain must reconcile OS pending notifications on startup and never mark whole plan applied on partial failure (covered in next batch orchestrator).

## B acceptance
New `reminderDueAtUtc`/`reminderWindowOpen` (strict `isBefore`), `ReminderOutcome.tooLate` with `K.reminderTooLateMsg` bn/en, intent_state `StoredReminderState` with truthful copy (never scheduled/delivered/missed), ticker adds `closes-24h`, detail keeps enable tappable when late (snackbar), home sheet renders `reminderRowSubtitle`. Re-evaluates deadline/status/cutoff after permission prompt; disable needs no permission. Worker evidence: 36 new tests + 138 focused + 45 adjacent, analyze clean. Captain verified: `flutter test test/features/reminder_eligibility_test.dart` 36 passed, `flutter test test/features/deadline_live_test.dart` 17 passed, `flutter analyze lib/features` clean, preflight PASS. Scope clean: 9 files, no shared surface bump. Integrated as `3de761f`.

## C acceptance
Canonical JSON ledger, `draftIsDirty`/`persistedDraftSignatures`, `renderSaveIndicators` (per-draft + workspace), beforeunload/import/reset/delete/recovery warnings, `compareTimestamps` submicrosecond-aware, review freshness guard (`now > existing reviewed_at && updated_at`), preservation of published_at, null/unknown extensions preserved. Worker evidence: 26 Node tests pass, Python 41 pass, syntax/preflight clean, Chromium NOT RUN (documented reproduce). Captain verified: `node --test tests/feed/admin_behavior_test.js tests/feed/admin_ui_flow_test.js` 26 passed, `python3 -m unittest discover -s tests/feed` 41 passed, syntax checks pass, `git diff --check` PASS, `flutter analyze` still clean. Scope clean: 6 files only. Integrated as `3834407`.

## Combined gates after all three
- `flutter test`: **416 passed** (340 baseline + 40 + 36)
- `flutter analyze`: **No issues found**
- `python3 tool/preflight.py`: **PASS**
- `python3 -m unittest discover -s tests/feed`: **41 passed**
- `node --test tests/feed/admin_behavior_test.js tests/feed/admin_ui_flow_test.js`: **26 passed**
- `git diff --check`: **PASS**
- `git ls-files` secrets check: **PASS**

Flutter 3.47.7 / Dart 3.13.5. No build/CI/workflow/release/notification delivery triggered. Preview deployment not changed. Native factory/activation, real notification plugin wiring, production feed approval remain pending captain work.

