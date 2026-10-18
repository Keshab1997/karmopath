# Batch 7 — frozen integration contract

The owner requested parallel workers. A implements pure reconciliation, B the
Android notification boundary, C a native runtime factory. Captain retains all
existing shared surfaces and final app composition. **None imports another
worker's new implementation**; tests use test-only fakes of the ports below.
This dispatch prepares native integration, not a production launch.

## Foundation and package decisions

Authoritative shared Dart API: `lib/contracts/native_reminders.dart`. It contains
values/abstract ports only—no working scheduler, no fabricated OS success.

Captain pins `flutter_local_notifications: 22.3.2`, `timezone: 0.11.2`,
`url_launcher: 6.3.3` and the resolved lockfile. Flutter 3.47.7 / Dart 3.13.5;
workers run `flutter pub get --enforce-lockfile`, never upgrade/edit dependencies.
Metadata/source reviewed at https://pub.dev/packages/flutter_local_notifications/versions/22.3.2
and https://pub.dev/packages/url_launcher/versions/6.3.3 .

Captain supplies Android INTERNET, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED,
plugin scheduled/boot receivers, `ic_stat_karmopath` with an explicit resource-
shrinker keep rule, and desugaring 2.1.4. The
verified SDK's inherited compile/target SDK is 36, min SDK 24; AGP/Gradle pins
are not downgraded. **Android compilation, permission UI, reboot and actual
notification delivery are NOT proven by this foundation or by unit tests.**

Use **one-shot inexactAllowWhileIdle** scheduling, UTC `TZDateTime`, no repeat
components, exact-alarm permission, full-screen intent, foreground service or
DND bypass. Due is 24h before closing; OS delivery may be delayed. Never promise
exact delivery or translate OS acceptance into a delivered/missed badge.

## Shared ports (exact source signatures win)

- `NativeNotifications`: initialize(onJobTap), passive permissionStatus(),
  explicit-user-action requestPermission(), pendingReminders(), schedule(request),
  idempotent cancel(id), dispose(). Disposal must NOT cancel existing schedules.
- `ReminderPermission`: granted / denied / unavailable / unsupported. Never turn
  null, exception or unsupported platform into a grant. No startup/resume prompt.
- `NativeReminderIdentity`: full jobId, dueAtUtc, closesAtUtc, contentKey,
  payloadVariant. Equality compares every field; no truncated IDs/fingerprints.
- `NativeReminderRequest`: platformId + identity + localized title/body.
- `NativePendingReminder`: backend platformId, isManaged, nullable decoded identity.
  Return even foreign/unknown payloads, so ID collisions cannot be overlooked.
- `ReminderSyncInput`: nullable jobs, copied selectedJobIds, languageCode bn/en.
  **jobs == null means no verified feed; it is not an empty feed.**
- `ReminderSyncReport`: permission, feedAvailable, confirmed scheduledJobIds,
  cancelledJobIds, cancelledOrphanIds, typed problems. Diagnostics are not UI copy.
- `ReminderSynchronizer`: synchronize(input), close(). Serialize operations;
  close rejects new work and drains accepted work without erasing user intent.

Frozen literals: namespace `karmopath.reminder.v1`, channel
`karmopath.deadlines.v1`, channel name `Deadline reminders`, Android icon
`ic_stat_karmopath`, variants `bn@reminder-v1` / `en@reminder-v1` via the shared
`reminderPayloadVariant()` function. Existing ledger/preferences keys do not change.

## A output — pure synchronizer

File `lib/data/reminders/reminder_synchronizer.dart` exports:

```dart
class DefaultReminderSynchronizer implements ReminderSynchronizer {
  DefaultReminderSynchronizer({
    required PreferencesStore store,
    required NativeNotifications notifications,
    required DateTime Function() nowUtc,
  });
  // Implements the two shared methods; owns one ReminderStateStore/applier.
}
```

Use existing `planReminders`, `ReminderStateStore`, `ReminderApplier`; do not
reimplement deadline rules, allocation or codec, or change old public APIs.
A private ReminderPlatform bridge creates NativeReminderRequest values.
Copy: title `আবেদনের সময়সীমার রিমাইন্ডার` / `Application deadline reminder`;
body is the current job's title_bn/title_en + newline +
`মূল বিজ্ঞপ্তিতে শেষ সময় যাচাই করুন।` / `Verify the deadline in the original notice.`
Variant tracks the input language; contentKey comes from the existing planner.

Before apply: load ledger, passively query permission and backend pending records.
Unreadable/corrupt ledger or unreadable/unknown permission/pending state means
no guessed empty state or destructive apply; return/throw an observable failure.
A missing OS record is confirmed by idempotent cancel before clearing applied
metadata. Match the full identity, not ID alone. Cancel managed stale/orphan
records before replacement; record cancellations only after real success.
Reservations without applied metadata can still have a crash-window OS entry.
Keep matched future entries; reschedule only after reconciliation via the applier.
A failed cancel/storage operation blocks scheduling that job and remains retryable;
other safe jobs may proceed and each failure stays visible in the combined report.

Never cancel foreign/unknown-namespace notifications. A foreign ID colliding
with a reservation OR a prospective allocation range is a conflict: fail closed
before effects, not overwrite it or advance the allocator around it. If an
orphan managed ID reaches/exceeds the allocator counter, the ledger may have
been lost: report the inconsistency and perform NO cancellation/allocation in
that run. Do not erase the only OS evidence and then reuse that ID on a retry.
Recovery needs a separate captain-approved design, not an invented ledger repair.
Do not clear or silently migrate corrupt state. No cancelAll.

Denied permission: cancel only managed schedules with confirmed per-ID results;
keep user intent. Unavailable/unsupported is not a reliable denial or grant and
must not cause a destructive reset. With jobs == null, do not cancel selected
reminders just because their jobs are unavailable and never create schedules
from invented data; explicit deselections/known owned orphans may be cleaned up.
A verified empty/changed feed is authoritative. No schedule at/after due, no
catch-up or repeat alert; recheck the injected clock when executing, not only
when a request entered a queue. All queue/error paths must remain usable.

## B output — Android implementation

File `lib/platform/notifications/android_native_notifications.dart` exports:
`AndroidNativeNotifications({DateTime Function()? nowUtc}) implements NativeNotifications`.
Additional test-injection helpers may stay within B's directory; the default
constructor must actually use the pinned plugin, not a fake/stub backend.

Payload is JSON with exactly these canonical keys: `namespace`, `job_id`,
`due_at_utc`, `closes_at_utc`, `content_key`, `payload_variant`. Timestamps are
UTC ISO8601 strings ending in Z. ID comes from the OS pending record, not payload.
Only the exact namespace is managed. A decodable matching namespace with invalid
fields yields isManaged=true, identity=null; undecodable/foreign payloads are
unmanaged. Valid foreground/cold-start taps forward only a validated jobId,
never arbitrary URLs. Ignore callbacks after disposal; initialization is retryable.

Return every record from pendingNotificationRequests, not only managed ones.
That API reports the plugin's pending registry, not an independent AlarmManager
audit or delivery receipt; do not claim it detects every OS/OEM failure or IDs
managed outside this backend. Real-device reboot/delivery gates remain required.

Create the channel with default importance, no permission dialog. User permission
requests serialize and return the subsequent actual status, not an assumed grant;
respect disabled app/channel notifications. Unsupported platforms do not invoke
Android APIs (initialization/effects fail clearly; permission may say unsupported).
Validate future due and ID/copy, check real permission before scheduling, use
UTC zonedSchedule/inexactAllowWhileIdle, preserve errors. The pinned plugin uses
named args such as `initialize(settings: ...)`, `cancel(id: ...)`,
`zonedSchedule(id: ..., ...)`; do not copy old positional API examples.

## C output — native runtime factory, independent of A/B implementations

File `lib/native/runtime/native_runtime_factory.dart` exports these exact names:

```dart
typedef ReminderSynchronizerFactory = ReminderSynchronizer Function({
  required PreferencesStore store,
  required NativeNotifications notifications,
  required DateTime Function() nowUtc,
});
typedef NativeResourcesFactory = Future<NativeRuntimeResources> Function(
  FeedConfiguration feedConfiguration,
);
Future<NativeRuntimeSession> createNativeRuntime({
  required FeedConfiguration feedConfiguration,
  required NativeNotifications notifications,
  required ReminderSynchronizerFactory createSynchronizer,
  NativeResourcesFactory? createResources,
  Future<bool> Function(Uri)? launchExternal,
  DateTime Function()? nowUtc,
});
```

`NativeRuntimeResources` has named constructor fields `transport: FeedTransport`,
`cache: FeedCache`, `preferencesStore: PreferencesStore`,
`readLanguageCode: Future<String?> Function()`,
`writeLanguageCode: Future<void> Function(String)`, `close: Future<void> Function()`.
Default resources actually use http.Client, SharedPreferencesAsync and the three
existing lib/data/platform adapters. The String language key is
`karmopath.language.v1` (bn/en); absent defaults to bn, invalid/read failure is
not silently overwritten. All injected resources/gateway become factory-owned
for cleanup when construction starts. Test resources/fakes live only in tests.

`NativeRuntimeSession` exposes `AppRuntime runtime`,
`ValueListenable<NativeReminderRuntimeState> reminderState`,
`ValueListenable<String?> pendingNotificationJobId`,
`void consumeNotificationJobId()`, `Future<void> onResume()`, `Future<void> close()`.
`NativeReminderRuntimeState` has `NativeReminderPhase phase` and nullable
`ReminderSyncReport report`; phase = idle / syncing / permissionRequired /
feedUnavailable / failed / closed. These are state signals, not delivered badges.
Captain will bind onResume/tap navigation/state rendering in lib/app/** later;
C must not register a second global lifecycle observer or edit shared UI.

Await preference/language initialization before returning. Construct the existing
CachedJobRepository/LocalUserPreferences, then use the injected synchronizer
factory and gateway. Do not import A's/B's new implementations. Listen for
repository feed, reminder-intent and successful persisted-language changes;
serialize sync with fresh snapshots, preserve null-feed meaning and catch every
background error. Return observable sync state rather than suppressing failures.
ProductionShell owns initial refresh; the factory must not make a duplicate
startup fetch. onResume triggers passive reconciliation, never a permission prompt.

AppActions.openExternal validates public HTTPS/no credentials/fragment and calls
url_launcher externally by default; false/throws is failure. requestReminderPermission
calls the real gateway only in response to UI action, returns true only for a
confirmed grant, and triggers passive sync afterwards. Track pending writes;
close removes listeners, drains work, closes synchronizer before gateway, disposes
repository before http.Client, releases preference/notifier resources, and tries
all cleanup even if one step fails. Failed startup and retries must not leak.
Persist language before switching notification variant; a failed write must not
claim persistence. Cold-start tap IDs remain queued until the captain consumes
them and resolves the current job; no external navigation or fake job fallback.

## Captain-only acceptance after workers return

Read each complete diff and its tests; integrate B/A/C without worker cross-imports,
then connect their constructors in lib/app/**. Wire resume, safe tap routing and
visible sync failure state, pass SettingsScreen its existing optional summary
inputs, and keep web demo isolated. Native entrypoint activation requires an
explicit owner-approved feed URL. No guessed feed, publication, build, CI dispatch,
settings/secrets change or release is authorized by these briefs. Device
permission-denial/regrant, cold-start tap, process restart, reboot/upgrade and
inexact scheduling/delivery require real-device/owner-authorized evidence later.
