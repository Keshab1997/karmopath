/// Pure reconciliation between a previously applied reminder plan and the
/// desired one.
///
/// The captain owns the OS: this library only says *what to change*, never how.
/// There are no platform IDs here because notification IDs must be allocated
/// and persisted by the platform layer — deriving them from a job ID hash would
/// silently collide or change across runs.
library;

import 'reminder_plan.dart';

/// A reminder that must be removed (job unselected, no longer schedulable, or
/// replaced by a changed entry with the same job ID).
class ReminderCancellation {
  const ReminderCancellation({required this.jobId, required this.previous});

  final String jobId;

  /// The entry that the platform currently has scheduled.
  final ReminderPlanEntry previous;

  @override
  bool operator ==(Object other) =>
      other is ReminderCancellation &&
      other.jobId == jobId &&
      other.previous == previous;

  @override
  int get hashCode => Object.hash(jobId, previous);

  @override
  String toString() => 'ReminderCancellation($jobId)';
}

/// A reminder that must be (re)created: either brand new, or a replacement for
/// a changed entry with the same job ID.
class ReminderScheduling {
  const ReminderScheduling({required this.entry, required this.isReplacement});

  final ReminderPlanEntry entry;

  /// `true` when a cancellation for the same job ID is in the same diff.
  final bool isReplacement;

  @override
  bool operator ==(Object other) =>
      other is ReminderScheduling &&
      other.entry == entry &&
      other.isReplacement == isReplacement;

  @override
  int get hashCode => Object.hash(entry, isReplacement);

  @override
  String toString() =>
      'ReminderScheduling(${entry.jobId}, replacement: $isReplacement)';
}

/// The exact change set to apply, in a safe order.
class ReminderDiff {
  ReminderDiff({
    required List<ReminderCancellation> cancellations,
    required List<ReminderScheduling> schedules,
    required List<ReminderPlanEntry> retained,
  }) : cancellations = List<ReminderCancellation>.unmodifiable(cancellations),
       schedules = List<ReminderScheduling>.unmodifiable(schedules),
       retained = List<ReminderPlanEntry>.unmodifiable(retained);

  /// Removals, ordered by `jobId`.
  final List<ReminderCancellation> cancellations;

  /// (Re)creations, ordered by `(dueAtUtc, jobId)`.
  final List<ReminderScheduling> schedules;

  /// Entries that are already correct and must be left alone, ordered by
  /// `(dueAtUtc, jobId)`.
  final List<ReminderPlanEntry> retained;

  /// True when applying this diff would change nothing.
  bool get isNoOp => cancellations.isEmpty && schedules.isEmpty;

  /// Apply order: **every cancellation first, then every scheduling.**
  ///
  /// A replacement appears in both lists under the same job ID; cancelling
  /// before scheduling means a platform that keys notifications by job ID never
  /// ends up with two live reminders for one job. Applying a diff twice is
  /// safe only if the platform treats "cancel an absent ID" and "schedule an
  /// existing entry" as idempotent — the diff itself reports [isNoOp] on the
  /// second pass because the desired plan is unchanged.
  List<Object> get applyOrder => <Object>[...cancellations, ...schedules];

  @override
  String toString() =>
      'ReminderDiff(${cancellations.length} cancel, '
      '${schedules.length} schedule, ${retained.length} retained)';
}

/// Computes the change set from [previous] to [desired].
///
/// Both plans are keyed by **full job ID**. An entry is unchanged only when its
/// due instant *and* its [ReminderPlanEntry.contentKey] are identical, so a
/// corrected title, a newly added language, or a moved deadline replaces the
/// stale reminder instead of silently keeping obsolete text on screen.
///
/// Duplicate job IDs inside one plan are impossible from [planReminders]; if a
/// hand-built plan contains them this throws [ArgumentError] rather than
/// emitting two commands for one job.
ReminderDiff diffReminderPlans({
  required ReminderPlan previous,
  required ReminderPlan desired,
}) {
  final previousById = _indexPrevious(previous);
  final desiredById = _indexDesired(desired);

  final cancellations = <ReminderCancellation>[];
  final schedules = <ReminderScheduling>[];
  final retained = <ReminderPlanEntry>[];

  for (final entry in desired.entries) {
    final old = previousById[entry.jobId];
    if (old == null) {
      schedules.add(ReminderScheduling(entry: entry, isReplacement: false));
    } else if (old == entry) {
      retained.add(entry);
    } else {
      // Same job, different time or different alert text: cancel and replace.
      cancellations.add(
        ReminderCancellation(jobId: entry.jobId, previous: old),
      );
      schedules.add(ReminderScheduling(entry: entry, isReplacement: true));
    }
  }

  for (final old in previous.entries) {
    if (!desiredById.containsKey(old.jobId)) {
      // Removed, unselected, closed or no longer schedulable.
      cancellations.add(ReminderCancellation(jobId: old.jobId, previous: old));
    }
  }

  cancellations.sort((a, b) => a.jobId.compareTo(b.jobId));
  schedules.sort((a, b) {
    final byDue = a.entry.dueAtUtc.compareTo(b.entry.dueAtUtc);
    return byDue != 0 ? byDue : a.entry.jobId.compareTo(b.entry.jobId);
  });
  retained.sort((a, b) {
    final byDue = a.dueAtUtc.compareTo(b.dueAtUtc);
    return byDue != 0 ? byDue : a.jobId.compareTo(b.jobId);
  });

  return ReminderDiff(
    cancellations: cancellations,
    schedules: schedules,
    retained: retained,
  );
}

Map<String, ReminderPlanEntry> _indexPrevious(ReminderPlan plan) {
  final out = <String, ReminderPlanEntry>{};
  for (final entry in plan.entries) {
    if (out.containsKey(entry.jobId)) {
      throw ArgumentError.value(
        entry.jobId,
        'previous',
        'duplicate job id in the previous plan',
      );
    }
    out[entry.jobId] = entry;
  }
  return out;
}

Map<String, ReminderPlanEntry> _indexDesired(ReminderPlan plan) {
  final out = <String, ReminderPlanEntry>{};
  for (final entry in plan.entries) {
    if (out.containsKey(entry.jobId)) {
      throw ArgumentError.value(
        entry.jobId,
        'desired',
        'duplicate job id in the desired plan',
      );
    }
    out[entry.jobId] = entry;
  }
  return out;
}
