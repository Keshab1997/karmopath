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

  /// The job is still open, but the single reminder for it is due 24 hours
  /// before the deadline and that instant has already arrived. Nothing is
  /// requested or persisted: the policy has no catch-up alert.
  tooLate,

  /// The job carries no supported deadline (e.g. result/admit card), so there
  /// is nothing to remind about. Nothing is requested or persisted.
  noDeadline,
}

/// Instant at which the single reminder for [closesAtUtc] becomes due.
///
/// Frozen policy: exactly one reminder, 24 hours before the effective
/// deadline. This helper only does arithmetic on the instant the feature
/// already computed; it never invents a closing time.
DateTime reminderDueAtUtc(DateTime closesAtUtc) =>
    closesAtUtc.toUtc().subtract(const Duration(hours: 24));

/// Whether a *new* reminder request may still be stored at [now].
///
/// A request is accepted only while the job is open and **strictly before**
/// the due instant: at equality the reminder is already due, so it is too
/// late. Turning an existing intent off never consults this.
bool reminderWindowOpen(DeadlineInfo info, DateTime now) {
  final closes = info.closesAtUtc;
  if (closes == null) return false;
  if (info.isClosed || info.isWithdrawn) return false;
  return now.toUtc().isBefore(reminderDueAtUtc(closes));
}

/// Single place for the "remind me" flow so detail and calendar agree.
///
/// Order is fixed by docs/CONTRACTS.md: ask [AppActions] for permission first,
/// and only persist the preference when it is granted. The captain schedules
/// and cancels the actual notification.
///
/// Order for enabling is fixed: supported deadline, then closed/withdrawn,
/// then the 24-hour cutoff, and only then the permission prompt. Nothing is
/// requested or stored for a late or closed job.
///
/// [deadlineAt] normally recomputes the deadline for a given instant. It is
/// re-evaluated after the permission prompt returns: a dialog can stay open
/// across the deadline (or across the 24-hour cutoff) and across a feed
/// correction, so the current fields and the current clock decide whether the
/// intent may be written.
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

  // Status before cutoff: a closed or withdrawn job answers "closed" even
  // when its 24-hour instant is also in the past.
  ReminderOutcome? ineligible(DeadlineInfo? info) {
    if (info == null || !info.hasDeadline) return ReminderOutcome.noDeadline;
    if (info.isClosed || info.isWithdrawn) return ReminderOutcome.closed;
    if (!reminderWindowOpen(info, clock())) return ReminderOutcome.tooLate;
    return null;
  }

  final current = deadlineAt?.call(clock()) ?? deadline;
  final blocked = ineligible(current);
  if (blocked != null) return blocked;

  final bool granted;
  try {
    granted = await actions.requestReminderPermission();
  } on Object {
    return ReminderOutcome.permissionError;
  }
  if (!granted) return ReminderOutcome.permissionDenied;

  // The prompt may have outlived the deadline or the 24-hour cutoff, and a
  // feed correction may have changed the job while it was open: re-evaluate
  // everything against the current fields and the current clock.
  final afterPermission = deadlineAt?.call(clock());
  if (afterPermission != null) {
    final blockedAfter = ineligible(afterPermission);
    if (blockedAfter != null) return blockedAfter;
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
  ReminderOutcome.tooLate => K.reminderTooLateMsg,
  ReminderOutcome.noDeadline => K.reminderNoDeadlineMsg,
};
