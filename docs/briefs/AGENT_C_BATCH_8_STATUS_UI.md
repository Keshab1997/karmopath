# Agent C — Batch 8 reminder synchronization status UI

**Captain-issued follow-up.** Branch: `agent/C/b8-reminder-status-ui-20261018`  
**Immutable base:** `6de52013ca3574087d4a9c2c1e363a053f426090` (your reviewed tap-queue handoff)  
**Do not start until given this brief in your independent workspace.**

## Goal

Build a reusable bilingual feature-layer status/retry component for native reminder reconciliation. The runtime's failure is not success, but the production shell does not yet have a small reusable status surface. The Captain will wire it to `ReminderSessionState` later.

## Exact write allowlist — no other files

- `lib/features/common/strings.dart` — add only the two frozen `KText` values below; leave all existing copy untouched.
- `lib/features/common/reminder_sync_status.dart` — new widget and phase enum.
- `test/features/reminder_sync_status_test.dart` — new focused widget tests; no shared helper edits.

Do not edit `lib/app/**`, `lib/contracts/**`, `lib/main.dart`, design system, tap queue, shared test helpers, fixtures, dependencies, workflows, Android, or docs.

## Frozen API and copy

```dart
enum ReminderSyncUiPhase { idle, syncing, failed }

class ReminderSyncStatusBanner extends StatelessWidget {
  const ReminderSyncStatusBanner({
    super.key,
    required this.phase,
    required this.language,
    required this.onRetry,
  });
  final ReminderSyncUiPhase phase;
  final AppLang language;
  final VoidCallback onRetry;
}
```

Add exactly these new strings to `K`; reuse the existing `K.retry` for the action:

```dart
static const reminderSyncChecking = KText(
  'রিমাইন্ডারের অবস্থা যাচাই হচ্ছে…',
  'Checking reminder status…',
);
static const reminderSyncFailed = KText(
  'রিমাইন্ডারের অবস্থা যাচাই করা যায়নি। আবার চেষ্টা করুন।',
  'Could not check reminder status. Try again.',
);
```

## Required behavior

- `idle` renders no banner. `syncing` renders an accessible progress/status indicator and `reminderSyncChecking`; no retry button. `failed` renders `reminderSyncFailed` and one explicit `K.retry` action invoking `onRetry` once.
- Do not add a success/delivered state, green success badge, or copy claiming that a notification was scheduled, delivered, or missed. Do not auto-retry or request notification permission.
- Use the explicit `language` argument, never global language state. Keep UI responsive and testable; do not import app/runtime types. The component should be a simple Material widget using the existing theme context, not a new design-system API.
- The Captain will connect the widget to runtime state and decide where it appears; do not edit production shell/screens.

## Required tests

Cover idle-hidden behavior, Bengali and English copy in syncing/failed states, progress semantics, retry visibility/callback only on failure, and absence of any delivery/success claim. Include a widget test that changing the explicit language changes copy without touching global state.

## Focused verification

```bash
flutter test test/features/reminder_sync_status_test.dart
python3 tool/preflight.py
```

If Flutter is unavailable, report **NOT RUN**. No analyze/full test/build/Gradle/CI.

## Handoff

Push only `agent/C/b8-reminder-status-ui-20261018`, then provide the exact branch SHA and five-line Batch 8 report. The Captain owns runtime wiring/integration.
