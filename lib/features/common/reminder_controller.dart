import '../../contracts/app_actions.dart';
import '../../contracts/user_preferences.dart';
import 'deadline_clock.dart';
import 'formatting.dart';
import 'strings.dart';

enum ReminderOutcome {
  /// Permission granted and the intent was persisted.
  enabled,

  /// Intent removed (no permission needed to switch off).
  disabled,

  /// Permission refused or unavailable: nothing was scheduled.
  permissionDenied,

  /// The permission check itself threw, so the grant state is unknown and
  /// nothing was saved. Distinct from a storage failure.
  permissionError,

  /// Storage threw while writing; the previous stored state is unchanged.
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
///
/// [deadlineAt] normally recomputes the deadline for a given instant. It is
/// re-evaluated after the permission prompt returns: a dialog can stay open
/// across the deadline, and an enable intent must not be written for a job
/// that has closed in the meantime.
Future<ReminderOutcome> setReminderIntent({
  required UserPreferences preferences,
  required AppActions actions,
  required String jobId,
  required bool enable,
  DeadlineInfo? deadline,
  DeadlineInfo Function(DateTime now)? deadlineAt,
  NowProvider? now,
}) async {
  if (!enable) {
    try {
      await preferences.setReminder(jobId, false);
      return ReminderOutcome.disabled;
    } on Object {
      return ReminderOutcome.failed;
    }
  }
  final clock = now ?? DeadlineClock.now;
  final current = deadlineAt?.call(clock()) ?? deadline;
  if (current == null || !current.hasDeadline) {
    return ReminderOutcome.noDeadline;
  }
  if (current.isClosed || current.isWithdrawn) {
    return ReminderOutcome.closed;
  }
  final bool granted;
  try {
    granted = await actions.requestReminderPermission();
  } on Object {
    return ReminderOutcome.permissionError;
  }
  if (!granted) return ReminderOutcome.permissionDenied;

  // Permission may have outlived the deadline: recheck before persisting.
  final afterPermission = deadlineAt?.call(clock());
  if (afterPermission != null) {
    if (!afterPermission.hasDeadline) return ReminderOutcome.noDeadline;
    if (afterPermission.isClosed || afterPermission.isWithdrawn) {
      return ReminderOutcome.closed;
    }
  }
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
  ReminderOutcome.permissionError => K.reminderPermissionErrorMsg,
  ReminderOutcome.failed => K.reminderFailedMsg,
  ReminderOutcome.closed => K.reminderClosedMsg,
  ReminderOutcome.noDeadline => K.reminderNoDeadlineMsg,
};
