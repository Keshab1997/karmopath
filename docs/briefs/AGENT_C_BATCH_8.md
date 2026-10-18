# Agent C — Batch 8 cold-start reminder tap intent

**Captain-issued assignment.** Branch: `agent/C/b8-tap-intent-20261018`  
**Immutable base:** `68808ee41485138c6a22db3ee012d60c7f644175`  
**Do not start until given this brief in your independent workspace.**

## Goal

Build a tiny pure queue that safely holds a validated notification job tap until the Captain's production navigator is ready. The current shell can open a job by ID, but no safe pending-tap handoff exists. This task is only the independently testable state helper; the Captain wires plugin callbacks and navigation later.

## Exact write allowlist — no other files

- `lib/features/common/reminder_tap_intent.dart` — new pure helper.
- `test/features/reminder_tap_intent_test.dart` — new focused tests; no shared fixture edits.

Do not edit `lib/app/**`, `lib/contracts/**`, screens, routes, notification/plugin code, Android, `lib/main.dart`, shared test helpers, fixtures, dependencies, workflows, or docs.

## Frozen API

```dart
class ReminderTapIntentQueue {
  bool get hasPending;
  String? get pendingJobId;
  bool accept(String? candidateJobId);
  String? consume({required bool navigationReady});
  void clear();
}
```

## Required behavior

- Accept only the full contract-shaped job slug `[a-z0-9-]{1,100}`. Do not trim, lowercase, truncate, hash, parse as a URL, or accept arbitrary navigation targets.
- A valid new tap replaces the previous pending tap (latest intent wins). A null/invalid candidate returns `false` and must not erase an already valid pending tap.
- `consume(navigationReady: false)` returns null and retains the pending ID. `consume(navigationReady: true)` returns the full ID once and clears it. Empty consume returns null. `clear()` is idempotent.
- Keep the helper synchronous, deterministic, and independent of Flutter widgets, global state, feeds, storage, plugins, network, and permissions. It is not a delivery receipt.

## Required tests

Cover valid full IDs, invalid/null input, latest-valid-wins behavior, invalid input preserving an earlier valid intent, navigation-not-ready retention, one-time consume, no pending value, and idempotent clear.

## Focused verification

```bash
flutter test test/features/reminder_tap_intent_test.dart
python3 tool/preflight.py
```

If Flutter is unavailable, report **NOT RUN**. No analyze/full test/build/Gradle/CI.

## Handoff

Push only `agent/C/b8-tap-intent-20261018`, then provide the exact branch SHA and five-line Batch 8 report. The Captain alone connects the queue to the native tap callback and `ProductionShell`.
