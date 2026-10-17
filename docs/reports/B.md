# Worker B — batch 1 report

Branch: `agent/B/screens-v1` (no merge, no PR, no CI)
Base: `f184482e4b74216c5ab91b0fd45f3f6d180a3d76` (immutable foundation from `docs/DISPATCH_BATCH_1.md`)
Scope: `lib/features/**`, `test/features/**`, this file only.

## What was built

All five screens use the exact `docs/CONTRACTS.md` constructors and only the
frozen contracts (`Job`, `JobFeed`, `JobRepository`, `UserPreferences`,
`AppActions`) plus the shared theme. No worker A/B/C implementation is imported
and no shared file was touched.

| Screen | Path | Behaviour |
|---|---|---|
| Home | `lib/features/home/home_screen.dart` | Karmopath header + bell, local search (title/organisation/district/qualification/category, both languages), illustrated coral hero (`KarmopathTheme.heroAsset`), pastel category strip, kind + "closing soon" filters, local sort by `published_at` desc, pull-to-refresh |
| Job detail | `lib/features/job_detail/job_detail_screen.dart` | Structured eligibility/dates/application sections, notice + source + optional apply links through `AppActions.openExternal`, reviewed timestamp, independence disclaimer (EN + BN), reminder opt-in, bookmark |
| Saved | `lib/features/saved/saved_screen.dart` | IDs resolved against the current feed; missing IDs render an "unavailable" tile that can be removed instead of crashing |
| Calendar | `lib/features/calendar/calendar_screen.dart` | Upcoming/All scopes, IST month grouping, ascending deadline order, closed entries labelled, read-only reminder indicator |
| Settings | `lib/features/settings/settings_screen.dart` | Bengali/English switch, about + disclaimer, notification info, five unprovisioned links shown disabled with a lock ("not available yet") — no invented URLs, emails or versions |

Shared B layer (`lib/features/common/`): bilingual copy table, language
notifier, deadline/date formatting, pastel category icons (generic Material
icons — no crests/emblems), job card, state views, permission-first reminder
controller.

Behaviour that follows the contracts and acceptance rules:

- **IST deadlines.** Date-only `application_end_date` is inclusive through
  23:59:59 Asia/Kolkata (= `18:29:59Z`); an exact `application_end_at` wins and
  is compared directly. `2026-11-15` renders as `15 Nov 2026` / `১৫ নভেম্বর ২০২৬`
  with no timezone shift.
- **Stale status.** A job whose deadline has passed is shown closed even when
  the feed still says `open`; `withdrawn` always beats everything.
- **Reminders.** Permission is requested through `AppActions` *before*
  `preferences.setReminder`; a denial persists nothing and shows a denial
  message. Switching off needs no permission. Closed/withdrawn jobs cannot get
  a new reminder.
- **States.** Loading, empty feed, no matches (with clear-filters), error with
  retry, offline/stale banner with cached jobs, first-launch-without-network.
- **Accessibility.** 48dp touch targets, tooltips/semantics on icon actions,
  text-driven hero height (no clipped Bengali at 320px / 1.3× text), no
  fabricated unread counts.

## Evidence (actual runs)

Environment: Flutter 3.47.7 / Dart 3.13.5 (sandbox reinstall), `flutter pub get`
run; `pubspec.yaml`/`pubspec.lock` unchanged.

| Command | Result |
|---|---|
| `python3 tool/preflight.py` | `PASS: structural preflight only; run targeted Flutter tests separately.` |
| `flutter test test/features` | `00:13 +52: All tests passed!` (52 widget/unit tests) |
| `flutter analyze` | `No issues found!` (run once for the whole feature surface) |

Test files (all under `test/features/`): `home_screen_test.dart` (14),
`job_detail_screen_test.dart` (15), `saved_screen_test.dart` (6),
`calendar_screen_test.dart` (7), `settings_screen_test.dart` (3),
`formatting_test.dart` (17 IST/boundary/label unit tests),
`reminder_controller_test.dart` (11 controller/permission/storage tests),
`review_b_regressions_test.dart` (4 captain review probes, copied unmodified),
`support/fakes.dart` (in-memory repository/preferences/actions with a
write-failure mode).

Not run, deliberately: `flutter build`/`gradlew`, CI dispatch, full test suite
(captain gate), screenshots/goldens. An in-test screenshot render was attempted
and abandoned (flutter_tester hung); no visual artefact is claimed.

## Review fixes (round 2, captain regressions)

The four captain probes from `docs/review/B_regressions.dart.txt` (main) were
copied verbatim to `test/features/review_b_regressions_test.dart` and reproduced
on branch head `bfaebc6` before any fix:

| Probe | Pre-fix result |
|---|---|
| date-only open at 23:59:59.999 IST | FAIL — `Actual: <true>` (closed) |
| `formatMonthYear(..., AppLang.en)` | FAIL — `Actual: 'নভেম্বর 2026'` |
| server-closed early vs future deadline | FAIL — `Actual: 'Closed on 15 Nov 2026, 11:59 PM IST'` |
| no-deadline reminder | FAIL — `Actual: [(wb-police-constable-2026, true)]` |

Fixes, implementation only:

1. **Exclusive date-only boundary.** `istExclusiveNextDayUtc` returns
   00:00 IST of the following day (`2026-11-16T00:00 IST == 2026-11-15T18:30Z`),
   so the last instant of the inclusive day stays open and the next IST
   midnight closes. Exact `application_end_at` still closes at that instant.
   The boundary is a comparison rule only; closed labels for date-only deadlines
   render the date (`Closed on 15 Nov 2026`) with **no** invented time, while
   exact timestamps keep their official time (`… 12:00 AM IST`).
2. **Month table.** `formatMonthYear` now uses the English table for
   `AppLang.en` (`Nov 2026`) and the Bengali table for `AppLang.bn`
   (`নভেম্বর ২০২৬`).
3. **Closure honesty.** `DeadlineInfo` now exposes `expired` (the scheduled
   deadline actually passed) and `serverClosed` (feed closed it early, no
   timestamp exists). Only `expired` can produce `Closed on <date>`; early
   server closure renders the generic `Closed` / `বন্ধ`, with the scheduled
   deadline left in the Important dates section. Withdrawn still wins.
4. **No-deadline reminders.** `setReminderIntent` returns the new
   `ReminderOutcome.noDeadline` for jobs without a supported deadline: no
   permission request, no preference write. The detail page disables the button
   and states why; an existing intent can still be switched off (no permission
   needed). Storage failures return `failed` and leave state unchanged.
   Success copy now describes a saved request whose timing depends on device
   settings — not guaranteed delivery.

Verification after fixes (same day, same sandbox): `flutter test
test/features/review_b_regressions_test.dart` → `+4: All tests passed!`;
`flutter test test/features` → `+77: All tests passed!`; `flutter analyze` →
`No issues found!`; `python3 tool/preflight.py` → PASS. New/extended tests were
added for the boundary (open at 23:59:59.999 and .999999, closed at IST
midnight, exact instant), both month languages, server-closed date-only and
exact cases plus genuine expiration, withdrawn precedence, and
permission/storage/no-deadline controller paths. No assertion was relaxed.

Calendar constructor is unchanged and still matches the contract exactly (no
`AppActions`); its bell remains a read-only indicator — captain decision
recorded, row → detail is the only reminder path.

Not verified in this round: Android runtime behaviour of reminder delivery
(captain-owned), goldens/screenshots (not produced), CI (never dispatched).

## Captain integration needed

1. **Routes/composition:** wire `HomeScreen`, `SavedScreen`, `CalendarScreen`
   and `SettingsScreen` (pass `onOpenJob`, `repository`, `preferences`,
   `actions`) — B did not touch `lib/app/**` or `lib/main.dart`.
2. **Calendar constructor:** stays exactly as contracted (no `AppActions`); the
   bell is a read-only indicator and reminder changes happen on the detail page.
   No contract change is requested.
3. **Notification scheduling:** `preferences.reminderJobIds` is intent only;
   captain schedules/cancels the actual local notifications.
4. **Provisioned content:** correction channel, developer contact, privacy
   policy, terms, Play listing — deliberately disabled placeholders.
5. **Assets:** pastel category strips currently use Material icons, as the brief
   directs; sliced decorative icons remain a captain asset deliverable.
6. **Language state:** `lib/features/common/app_language.dart` is a B-local
   notifier; if the language should persist, the app shell should own it and
   pass the choice down.

## Five-line report

Batch 1: B ready (branch head after review fixes; all four captain probes pass)
Changed: deadline boundary/labels, English month table and no-deadline/permission/storage reminder rules in lib/features/**; captain probes kept + 25 new/extended tests in test/features/**; this report.
Evidence: probes FAIL→PASS; flutter test test/features → 77 passed; flutter analyze → no issues; python3 tool/preflight.py PASS; no build/gradlew/CI; no goldens or Android runtime claims.
Not touched: lib/app/**, lib/main.dart, lib/contracts/**, lib/design_system/**, lib/data/**, pubspec*, .github/**, android/**, ios/**, assets/**, root docs, review files, other workers' paths, secrets.
Next: captain diff/visual/integration review; wiring, notification scheduling and legal/contact links remain captain-owned.
