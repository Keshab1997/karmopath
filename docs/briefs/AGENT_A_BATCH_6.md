# Agent A — reminder apply orchestrator (pure, failure-safe)

Repository: `Keshab1997/karmopath.git` (public).
Read `AGENTS.md`, `docs/CONTRACTS.md`, `docs/BATCH_5.md` and this brief. Batch 5 is now squash-integrated (`2f4ae45`); old worker branches contain stale history. **Start a NEW branch from `2f4ae45` (origin/main)**, do not continue, merge or cherry-pick any `agent/A/**` branch. Do not rebase/force-push/main-merge.

Captain owns shared surfaces/dependencies, `lib/app/**`, `lib/main.dart`, `lib/contracts/**`, `test/contracts/**`, `android/ios`, `workflows`, root docs/assets and generated/version files. Only the listed report is an extra write exception. No new dependencies, secret handling, remote scraping, feed publication, deployment, workflow dispatch, `build`/`gradlew`, tags/releases or repository settings changes. Use your own pairing; never copy credentials. Work under `/home/user`. Other workers are independent; do not wait for or import their new code.

**Branch:** `agent/A/reminder-apply-v1` from the frozen base above.

**Allowed writes ONLY:** `lib/data/**`, `test/data/**`, `docs/reports/A6.md`. Preserve all existing adapter/repository/planner/diff/state behavior and captain regressions.

## Implement

Create a small pure orchestrator under `lib/data/reminders/` that turns a `ReminderDiff` (from `reminder_plan.dart`/`reminder_diff.dart`) into durable platform effects via the existing `ReminderStateStore` — **without** importing `lib/features`, plugins, or real OS scheduling.

Inputs for one `apply()` call: `desiredPlan` (A4 `ReminderPlan`), `previousApplied` snapshot or store state, and an abstract `ReminderPlatform` you define in this module (e.g. `cancel(int id)`, `schedule(ReminderPlanEntry entry, int platformId)` returning success/failure). The orchestrator must:

- Cancel stale/removed entries **before** scheduling replacements that share the same `jobId` (A4 diff already orders cancel-before-schedule; preserve it).
- Allocate or reuse a stable `platformId` via `ReminderStateStore.reserve()` **before** any schedule attempt; never derive IDs from `hashCode`.
- On each successful platform operation, call `recordCancellationSuccess` or `recordSchedulingSuccess(payloadVariant)` with the exact `ReminderPlanEntry` and the captain-supplied `payloadVariant` (pass it through; do not invent copy). On a platform or storage failure, leave the ledger on its previous value and surface a per-job `ReminderStateFailure` without marking the whole plan applied.
- Be re-entrant safe: a second concurrent `apply()` waits on the first's queue (reuse `ReminderStateStore` queue or your own), so duplicate IDs are impossible. Exhaustion (`2147483647`) is a terminal failure, not a reuse.

No network, no file I/O, no `SharedPreferences` direct access beyond the injected store, no permission prompt.

## Evidence

Deterministic tests: apply empty diff (no writes), cancel-then-schedule same jobId with new deadline+content, schedule failure leaves ledger unchanged, cancellation failure leaves applied record, failed storage write not published to `state`, concurrent applies serialize, exhaustion at max ID, `payloadVariant` round-trips, unknown jobId in diff ignored. Preserve all existing `test/data` (A4/A5) tests. Run `flutter test test/data` and targeted `analyze`.

Deliver: push branch, write `A6.md` API/integration notes and actual gates, exactly five-line ready report with immutable SHA. No build/CI.

