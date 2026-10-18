# Agent B — reminder badges everywhere and truthful settings summary

Repository: `Keshab1997/karmopath.git` (public).
Read `AGENTS.md`, `docs/CONTRACTS.md`, `docs/BATCH_5.md` and this brief. Batch 5 is now squash-integrated (`2f4ae45`); old worker branches are stale. **Start a NEW branch from `2f4ae45` (origin/main)**, do not continue/merge/cherry-pick any `agent/B/**` branch. Do not rebase/force-push/main-merge.

Captain owns shared surfaces/dependencies, `lib/app/**`, `lib/main.dart`, `lib/contracts/**`, `test/contracts/**`, `android/ios`, `workflows`, root docs/assets and generated/version files. Only the listed report is an extra write exception. No new dependencies, secret handling, remote scraping, feed publication, deployment, workflow dispatch, `build`/`gradlew`, tags/releases or repository settings changes. Use your own pairing; never copy credentials. Work under `/home/user`. Other workers are independent; do not wait for or import their new code.

**Branch:** `agent/B/reminder-surface-v1` from the frozen base above.

**Allowed writes ONLY:** `lib/features/**`, `test/features/**`, `docs/reports/B6.md`. Preserve approved Home v2 layout, action safety, deadline ticker and B5 eligibility.

## Implement

Surface the already-persisted reminder intent truthfully on every job surface beyond Home sheet and detail:

- Calendar (`lib/features/calendar/calendar_screen.dart`): each job row/card that has a stored intent shows the same `reminderRowSubtitle`/`storedReminderMessage` used in detail/home (via `lib/features/common/reminder_intent_state.dart`), without claiming scheduled/delivered/missed. A bell or dot alone is not enough — the subtitle must appear. Keep existing expired/closing-soon logic untouched.
- Saved (`lib/features/saved/saved_screen.dart`): same subtitle under each saved card that has a stored intent; handle missing job (still shows stored row) and no-deadline/withdrawn states.
- Settings (`lib/features/settings/settings_screen.dart`): add a lightweight summary row "X stored reminder(s)" derived from `UserPreferences.reminderIds` + current feed jobs, using the same intent_state copy for empty vs non-empty. Tapping it navigates nowhere (captain will wire later); do not add new navigation or persistence.
- Keep `ReminderOutcome.tooLate` and `reminderWindowOpen` enforcement already in `reminder_controller.dart` — do not reimplement cutoff logic in screens. Screens only read intent_state + deadlineInfo + stored IDs.

All copy stays Bengali-first via `lib/features/common/strings.dart` (add only if missing); English fallback remains.

## Evidence

Widget tests: calendar row pending/duePassed/closed/withdrawn shows correct subtitle (bn + en, no scheduled/delivered text), saved row with stored intent + missing job, settings summary 0/1/many stored, 320px + 2x text for modified cards, no horizontal overflow. Retain all earlier eligibility/deadline/accessibility tests. Run `flutter test test/features` focused + targeted `analyze`.

Deliver: push branch, write `B6.md` behavior/tests/limits and actual gates, exactly five-line ready report with immutable SHA. No build/CI.

