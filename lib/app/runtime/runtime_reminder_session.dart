import '../../contracts/job_repository.dart';
import '../../contracts/user_preferences.dart';
import '../../data/reminders/reminder_apply.dart';
import '../../data/reminders/reminder_state_store.dart';
import '../../features/common/app_language.dart';
import '../notifications/native_notification_driver.dart';

/// Required binding, not an optional no-op. Captain supplies the real A/B
/// integration only after reviewing their changes. No production entrypoint
/// calls this factory before the owner approves a feed and that binding exists.
typedef RuntimeReminderSessionFactory = Future<RuntimeReminderSession> Function(
  ReminderSessionDependencies deps,
);

class ReminderSessionDependencies {
  const ReminderSessionDependencies({
    required this.repository,
    required this.preferences,
    required this.ledger,
    required this.applier,
    required this.notifications,
    required this.initialLanguage,
  });

  final JobRepository repository;
  final UserPreferences preferences;
  final ReminderStateStore ledger;
  final ReminderApplier applier;
  final NativeNotificationDriver notifications;
  final AppLang initialLanguage;
}

abstract interface class RuntimeReminderSession {
  /// Attach listeners and reconcile only once a validated feed is available.
  /// An unloaded feed is NOT an empty desired plan. Must never prompt. The real
  /// binding must repair OS/cache divergence: plugin pending IDs alone cannot
  /// establish that alarms survived a force-stop or reboot.
  Future<void> start();

  /// Current session language changes even when its persistence later fails.
  void languageChanged(AppLang language);

  /// Re-query OS pending/permission state without displaying a prompt.
  Future<void> resumed();

  /// Detach listeners synchronously, then drain in-flight effects. Never
  /// cancel durable OS schedules simply because the application is closing.
  Future<void> close();
}
