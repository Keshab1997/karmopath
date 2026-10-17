import '../../contracts/app_actions.dart';
import '../../contracts/user_preferences.dart';
import 'formatting.dart';
import 'strings.dart';

enum ReminderOutcome {
  /// Permission granted and the intent was persisted.
  enabled,

  /// Intent removed (no permission needed to switch off).
  disabled,

  /// Permission refused or unavailable: nothing was scheduled.
  permissionDenied,

  /// Storage/action threw; nothing was scheduled.
  failed,

  /// Deadline already passed or the job was withdrawn.
  closed,

  /// The job carries no supported deadline (e.g. result/admit card), so there
  /// is nothing to remind about. Nothing is requested or persisted.
  noDeadline,
}

/// Single place for the "remind me" flow so detail and calendar agree.
///
/// Order is fixed by docs/CONTRACTS.md: ask [AppActions] for permission first,
/// and only persist the preference when it is granted. The captain schedules
/// and cancels the actual notification.
Future<ReminderOutcome> setReminderIntent({
  required UserPreferences preferences,
  required AppActions actions,
  required String jobId,
  required bool enable,
  DeadlineInfo? deadline,
}) async {
  if (!enable) {
    try {
      await preferences.setReminder(jobId, false);
      return ReminderOutcome.disabled;
    } on Object {
      return ReminderOutcome.failed;
    }
  }
  if (deadline == null || !deadline.hasDeadline) {
    return ReminderOutcome.noDeadline;
  }
  if (deadline.isClosed || deadline.isWithdrawn) {
    return ReminderOutcome.closed;
  }
  final bool granted;
  try {
    granted = await actions.requestReminderPermission();
  } on Object {
    return ReminderOutcome.failed;
  }
  if (!granted) return ReminderOutcome.permissionDenied;
  try {
    await preferences.setReminder(jobId, true);
    return ReminderOutcome.enabled;
  } on Object {
    return ReminderOutcome.failed;
  }
}

KText reminderOutcomeMessage(ReminderOutcome outcome) => switch (outcome) {
  ReminderOutcome.enabled => K.reminderEnabledMsg,
  ReminderOutcome.disabled => K.reminderDisabledMsg,
  ReminderOutcome.permissionDenied => K.reminderDeniedMsg,
  ReminderOutcome.failed => K.reminderFailedMsg,
  ReminderOutcome.closed => K.reminderClosedMsg,
  ReminderOutcome.noDeadline => K.reminderNoDeadlineMsg,
};
