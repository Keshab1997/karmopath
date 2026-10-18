# Agent A — Batch 8 native reminder synchronizer

**Captain-issued assignment.** Branch: `agent/A/b8-native-sync-20261018`  
**Immutable base:** `68808ee41485138c6a22db3ee012d60c7f644175`  
**Do not start until given this brief in your independent workspace.**

## Goal

Implement the real data-layer synchronizer for the existing frozen `ReminderSynchronizer` contract, and harden the existing pending-aware applier to match complete managed notification identities. This is not the old Batch 7 dispatch: use the current code at the SHA above and the exact scope below.

## Exact write allowlist — no other files

- `lib/data/reminders/reminder_apply.dart` — change only `reconcile` to consume full pending records and compare identity.
- `lib/data/reminders/native_reminder_sync.dart` — new synchronizer and private platform bridge.
- `test/data/reminders/reminder_reconcile_test.dart` — adapt existing reconciliation tests and add identity/collision regressions.
- `test/data/reminders/native_reminder_sync_test.dart` — new synchronizer tests; define any fakes locally in this test file.

Do not edit shared test helpers, contracts, app/runtime, plugin, Android, dependency, fixture, workflow, or docs files.

## Frozen API

The new file exports these declarations; do not change their names or signatures:

```dart
class ReminderNotificationText {
  const ReminderNotificationText({required this.title, required this.body});
  final String title;
  final String body;
}

typedef ReminderNotificationTextBuilder = ReminderNotificationText Function(
  Job job,
  String languageCode,
);

class LedgerNativeReminderSynchronizer implements ReminderSynchronizer {
  LedgerNativeReminderSynchronizer({
    required PreferencesStore store,
    required NativeNotifications notifications,
    required ReminderNotificationTextBuilder textForJob,
    DateTime Function()? nowUtc,
  });

  Future<ReminderSyncReport> synchronize(ReminderSyncInput input);
  Future<void> close();
}
```

Change the `ReminderApplier.reconcile` pending-query named argument to this frozen shape (the current repo has no production caller yet; update all callers inside your allowlist):

```dart
required Future<List<NativePendingReminder>> Function() readPendingReminders
```

Do not change `apply`, `applyDiff`, the storage schema, the reminder plan, or any declarations in `lib/contracts/native_reminders.dart`.

## Required behavior

- Use `planReminders`, `ReminderStateStore`, and `ReminderApplier`; do not reimplement deadline policy, ID allocation, storage encoding, or preference intent. The synchronizer owns its ledger/applier and must dispose the ledger on `close`; it does **not** own or dispose the injected `NativeNotifications` instance.
- Serialize `synchronize` calls. `close` rejects new work, drains already accepted work, and does not erase stored intent or cancel schedules merely because the app closes.
- `jobs == null` means no verified feed: report `feedAvailable: false`, passively report permission if possible, and do not query-and-clear reminders, schedule, cancel, or mutate intent. A non-null empty feed is authoritative.
- Use only passive `permissionStatus()`; never call `requestPermission()` from synchronization. `unavailable`, `unsupported`, or a permission-query error must not trigger destructive cleanup or scheduling. If status is `denied` and a verified feed exists, reconcile an empty desired plan to cancel only known managed schedules; keep user intent unchanged. If granted, plan from the supplied jobs/selected IDs and explicit `bn`/`en` language.
- Build `NativeReminderIdentity` from the full job ID, UTC due/close instants, full content key, and `reminderPayloadVariant(languageCode)`. Call the injected text builder with the matching `Job` and language; blank title/body or a builder error must not be reported as scheduled. Recheck the due time immediately before scheduling; never catch up.
- Query and retain every `NativePendingReminder`, including unknown/foreign records. Pending IDs are backend observations, not proof of a live OS alarm or delivery.
- Before **any** cancellation or schedule, fail closed on duplicate pending IDs; a foreign (`isManaged == false`) ID colliding with a ledger reservation or an ID needed for the desired new reservations; or a managed identity whose job ID claims a different ledger reservation. Return a `ReminderSyncProblem` at `conflict` and perform no platform/ledger effects for that run. Never cancel foreign notifications.
- For a known reserved ID, a malformed exact-namespace record (`isManaged == true`, `identity == null`) or a same-job but stale full identity is not a match: cancel before replacement under the same reservation. A no-op match requires the full identity (job ID, due, closes, content key, payload variant) to match the ledger and the exact managed pending record. Unknown managed orphans without a ledger owner are never guessed/cancelled; if one blocks a prospective allocation, report conflict rather than reuse it.
- Preserve A7 semantics: global cancel-before-schedule ordering, stable non-reused IDs, per-job failures, retryable queue, no `cancelAll`, unreadable ledger/pending state never treated as empty, and unrelated safe jobs may continue only after conflict preflight passes.
- Map failures into the existing `ReminderSyncProblem` stages. Report only schedule operations that completed and were durably recorded; do not call them delivered. `cancelledOrphanIds` stays empty unless a real, safe orphan cancellation was actually confirmed.

## Focused verification

Run:

```bash
flutter test test/data/reminders/reminder_reconcile_test.dart
flutter test test/data/reminders/native_reminder_sync_test.dart
python3 tool/preflight.py
```

If Flutter cannot be installed in your session, report the tests as **NOT RUN**. No full suite/analyze/build/Gradle/CI.

## Handoff

Push only `agent/A/b8-native-sync-20261018`, then provide the exact branch SHA and the five-line Batch 8 report from `docs/DISPATCH_BATCH_8.md`. No merge or `main` push.
