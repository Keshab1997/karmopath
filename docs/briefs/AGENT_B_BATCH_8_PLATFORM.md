# Agent B — Batch 8 Android native notification backend

**Captain-issued follow-up.** Branch: `agent/B/b8-android-native-notifications-20261018`  
**Immutable base:** `00d9662de63847671a21cc888eeb2c9508205de7` (your reviewed codec handoff)  
**Do not start until given this brief in your independent workspace.**

## Goal

Implement the concrete Android-side `NativeNotifications` adapter using the existing frozen port and the payload codec already present at the base. This completes a distinct lower-level backend component; it does not wire or activate the app runtime.

## Exact write allowlist — no other files

- `lib/platform/notifications/android_native_notifications.dart` — new backend.
- `test/platform/notifications/android_native_notifications_test.dart` — new focused tests; keep test fakes/channel handlers in this file.

Do not edit `lib/app/**`, `lib/contracts/**`, `android/**`, `ios/**`, `lib/main.dart`, dependencies/lockfile, shared test helpers, fixtures, workflows, or docs.

## Frozen API

```dart
class AndroidNativeNotifications implements NativeNotifications {
  AndroidNativeNotifications({
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? nowUtc,
  });

  Future<void> initialize({required void Function(String jobId) onJobTap});
  Future<ReminderPermission> permissionStatus();
  Future<ReminderPermission> requestPermission();
  Future<List<NativePendingReminder>> pendingReminders();
  Future<void> schedule(NativeReminderRequest request);
  Future<void> cancel(int platformId);
  Future<void> dispose();
}
```

Use the existing `flutter_local_notifications: 22.3.2`, `timezone: 0.11.2`, `lib/contracts/native_reminders.dart`, and B's `encodeNativeReminderPayload` / `decodeNativeReminderPayload`. Do not change their APIs or literals.

## Required behavior

- Default construction must use the real pinned plugin, not a fake/stub. Do not use `lib/app/**` implementations or change them.
- This backend is Android-only. Web/unsupported platforms must not invoke Android APIs. Unknown/null plugin permission answers are `unavailable` (or `unsupported` when the platform is unsupported), never `granted`.
- `initialize` installs foreground and cold-start tap handling. Call `onJobTap` only for a valid decoded managed identity, passing the full validated job ID; ignore malformed/foreign payloads and callbacks after `dispose`. Initialization failure is retryable. Initialization/status/pending/schedule never display a permission prompt.
- `permissionStatus` is passive. `requestPermission` is the only prompting operation and returns the actual subsequent status, not an assumed grant.
- `pendingReminders` returns **every** plugin-pending record. Use the OS record's integer ID, decode the payload with B's codec, and preserve foreign/unknown records as `isManaged: false`; malformed exact-namespace records remain `isManaged: true, identity: null`. Do not filter by payload or claim the plugin list proves AlarmManager state/delivery.
- `schedule` validates ID/title/body/identity and an injected-clock future due time, confirms actual permission without prompting, serializes the full identity with B's codec, and uses UTC `TZDateTime` plus `AndroidScheduleMode.inexactAllowWhileIdle`. Recheck the due time immediately before the plugin call. Reuse the existing channel/icon constants; default importance only. No exact-alarm permission, repeat schedule, full-screen/DND bypass, or invented success.
- `cancel` is per-ID and idempotent; never expose `cancelAll`. `dispose` detaches callbacks/resources only and never cancels durable schedules.
- Preserve platform/plugin errors as failures. The plugin pending registry and successful API return are not delivery receipts.

## Required tests

Use Flutter test method-channel handlers or a test-only injected plugin boundary; add no dependency. Cover initialization/retry, valid and invalid cold/foreground taps, passive permission mapping, explicit permission result, all pending IDs including foreign/malformed payloads, codec round-trip on schedule, ID/channel/UTC/inexact scheduling, no prompt, due-time cutoff, cancellation, unsupported platform, and dispose preserving scheduled records.

## Focused verification

```bash
flutter test test/platform/notifications/android_native_notifications_test.dart
python3 tool/preflight.py
```

If Flutter is unavailable, report **NOT RUN**. No analyze/full test/build/Gradle/CI or real-device delivery claims.

## Handoff

Push only `agent/B/b8-android-native-notifications-20261018`, then provide the exact branch SHA and the five-line Batch 8 report. The Captain owns app/runtime wiring and native activation.
