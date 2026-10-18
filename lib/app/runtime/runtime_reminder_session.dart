import 'package:flutter/foundation.dart';

import '../../contracts/job_repository.dart';
import '../../contracts/native_reminders.dart';
import '../../contracts/user_preferences.dart';
import '../../data/reminders/reminder_state_store.dart';
import '../../features/common/app_language.dart';
import '../../features/common/reminder_sync_status.dart';

/// Required binding, not an optional no-op. The Captain's runtime factory
/// supplies the ledger-backed synchronizer before the session starts.
typedef RuntimeReminderSessionFactory = Future<RuntimeReminderSession> Function(
  ReminderSessionDependencies deps,
);

class ReminderSessionDependencies {
  const ReminderSessionDependencies({
    required this.repository,
    required this.preferences,
    required this.ledger,
    required this.notifications,
    required this.synchronizer,
    required this.initialLanguage,
  });

  final JobRepository repository;
  final UserPreferences preferences;
  final ReminderStateStore ledger;
  final NativeNotifications notifications;
  final ReminderSynchronizer synchronizer;
  final AppLang initialLanguage;
}

/// UI-safe state for the status banner. Detailed errors remain developer-only;
/// the UI gets generic bilingual copy and an explicit retry action.
class RuntimeReminderStatus {
  const RuntimeReminderStatus({
    this.phase = ReminderSyncUiPhase.idle,
    this.report,
    this.error,
  });

  final ReminderSyncUiPhase phase;
  final ReminderSyncReport? report;
  final Object? error;
}

/// Optional status/retry surface implemented by the real native session.
abstract interface class RuntimeReminderStatusSource {
  ValueListenable<RuntimeReminderStatus> get status;
  Future<void> retry();
}

abstract interface class RuntimeReminderSession {
  /// Attach listeners and reconcile only a fresh validated feed. An unloaded or
  /// stale cache is not an empty desired plan. Must never prompt for permission.
  Future<void> start();

  /// Current session language changes even when its persistence later fails.
  void languageChanged(AppLang language);

  /// Re-query permission and pending state without displaying a prompt.
  Future<void> resumed();

  /// Detach listeners synchronously, then drain in-flight effects. Never cancel
  /// durable OS schedules simply because the application is closing.
  Future<void> close();
}
