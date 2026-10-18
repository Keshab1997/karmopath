# Captain Batch 6 review — A, B and C integrated

## Reviewed immutable inputs
- A: `6e855332acc27936c1406bcc3f9e25c2c00f58a4` (code `6e85533`)
- B: `a9bd235621da8e07248d264e9a331fae32df2121`
- C: `a17a977a7e118e5494580b444bde7dc5f8cf8a94`

All three cut from `4ca4156` (which contains `2f4ae45` plus Batch 6 dispatch), file-partitioned, no shared-surface touch.

## A acceptance
Pure orchestrator `lib/data/reminders/reminder_apply.dart` with abstract `ReminderPlatform`, `ReminderApplier.apply/applyDiff`, `ReminderApplyResult`/`Failure`. Cancel-before-schedule, reserve via store before schedule, per-job record only after platform success, never whole-plan marking, re-entrant queue, exhaustion at 2147483647 terminal, blank payloadVariant rejected upfront, variant freshness via cancel+schedule. No plugin, no lib/features import, no extra key. Worker evidence: 24 new tests + 214 data tests pass, analyze clean. Captain verified: `flutter analyze lib/data` clean, `flutter test test/data/reminders/reminder_apply_test.dart` 24 passed, preflight PASS, diff --check PASS. Scope clean: 3 files only. Integrated as `efc6e6a`.

## B acceptance
Calendar/saved/settings surfaces reuse `reminder_intent_state.dart` truthfully: calendar cards render `reminderRowSubtitle`, saved cards + missing-job tile render same, settings summary row via `storedRemindersSummarySubtitle` with 0/1/many and tap no-op. Live 24h cutoff updates via existing ticker. Worker evidence: 12 new tests + 212 features tests pass, analyze clean. Captain verified: `flutter test test/features/reminder_surface_test.dart` 12 passed, `flutter analyze lib/features` clean, 320px 2x no overflow. Scope clean: 7 files only. Integrated as `ce388e4`.

## C acceptance
`tools/feed/check_publish.py` reuses `validate.py`, additive checks for source/notice HTTPS (no creds/fragment), published_at not future (5-min tolerance), districts/qualifications warnings (--strict fails), deterministic [PASS]/[FAIL]/[WARN] + RESULT, --now flag, no network/upload. Admin panel read-only checklist after valid export, hidden on blocked/invalid, cleared on import/recovery, not blocking export. Worker evidence: 60 Python (41 existing + 19 new) pass, 34 Node (26 existing + 8 new) pass, syntax/preflight clean, Chromium NOT RUN documented. Captain verified: `python3 -m unittest discover -s tests/feed` 60 passed, `node --test` 34 passed, `flutter analyze` still clean, preflight PASS. Scope clean: 9 files only. Integrated as `574f7c0`.

## Combined gates after all three
- `flutter test`: **452 passed** (416 baseline + 24 + 12)
- `flutter analyze`: **No issues found**
- `python3 tool/preflight.py`: **PASS**
- `python3 -m unittest discover -s tests/feed`: **60 passed**
- `node --test tests/feed/admin_behavior_test.js tests/feed/admin_ui_flow_test.js`: **34 passed**
- `git diff --check`: **PASS**
- `git ls-files` secrets check: **PASS**

Flutter 3.47.7 / Dart 3.13.5. No build/CI/workflow/release/notification delivery triggered. Preview deployment not changed. Concrete plugin wiring and native entrypoint activation remain pending captain work.

