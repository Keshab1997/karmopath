/// Deterministic reminder planning for the data layer.
///
/// Policy frozen in `docs/BATCH_4.md`: **one local reminder 24 hours before**
/// each selected, open recruitment deadline, and only when that reminder time is
/// **strictly in the future**. A late opt-in produces no catch-up alert.
///
/// This library is pure: it reads [Job] values and returns values. It never
/// touches storage, the network, permissions, plugins or the OS, allocates no
/// platform notification IDs, and mutates neither the jobs nor the selected
/// IDs it is given. Whether a notification is really scheduled or delivered is
/// the captain's platform concern; a plan proves intent, not delivery.
library;

import '../../contracts/job.dart';

/// Asia/Kolkata is UTC+05:30 all year (no DST), so a fixed offset is exact.
const Duration _istOffset = Duration(hours: 5, minutes: 30);

/// How far ahead of the closing instant a reminder is planned.
const Duration reminderLeadTime = Duration(hours: 24);

/// Why a selected job produced no reminder.
///
/// These are stable, semantic reasons (no user-facing copy): the captain maps
/// them to bilingual strings so a pending/no-alert state can be explained
/// instead of being presented as a successful schedule.
enum ReminderSkipReason {
  /// The selected ID is not in the current feed. It may be a job that was
  /// removed, or one this device has not downloaded yet.
  jobUnavailable,

  /// Results and admit cards carry no application deadline to remind about.
  unsupportedKind,

  /// The feed says the job is closed or withdrawn, even if a date remains.
  notOpen,

  /// An open recruitment whose deadline cannot be resolved (no date fields).
  noDeadline,

  /// The closing instant has already passed at [ReminderPlan.generatedAtUtc].
  deadlinePassed,

  /// The job is still open, but its 24-hour reminder time is now or already in
  /// the past — switching reminders on this late creates no catch-up alert.
  optedInTooLate,
}

/// One scheduled-or-planned reminder. No platform ID: the captain allocates and
/// persists those separately.
class ReminderPlanEntry {
  const ReminderPlanEntry({
    required this.jobId,
    required this.dueAtUtc,
    required this.closesAtUtc,
    required this.contentKey,
  });

  /// Full stable job ID (never truncated, never hashed).
  final String jobId;

  /// When the reminder should fire: [closesAtUtc] minus [reminderLeadTime].
  final DateTime dueAtUtc;

  /// Effective closing instant resolved from the contract's deadline rule.
  final DateTime closesAtUtc;

  /// Stable fingerprint of everything the alert would *say* about this job
  /// (both titles, organization, deadline source and value). It is used only to
  /// detect that a previously planned reminder is now stale — the captain's
  /// notification copy is localized outside the data layer.
  final String contentKey;

  @override
  bool operator ==(Object other) =>
      other is ReminderPlanEntry &&
      other.jobId == jobId &&
      other.dueAtUtc == dueAtUtc &&
      other.closesAtUtc == closesAtUtc &&
      other.contentKey == contentKey;

  @override
  int get hashCode => Object.hash(jobId, dueAtUtc, closesAtUtc, contentKey);

  @override
  String toString() =>
      'ReminderPlanEntry($jobId, due $dueAtUtc, closes $closesAtUtc)';
}

/// A selected job that produced no reminder, with the reason.
class ReminderSkip {
  const ReminderSkip({required this.jobId, required this.reason});

  final String jobId;
  final ReminderSkipReason reason;

  @override
  bool operator ==(Object other) =>
      other is ReminderSkip && other.jobId == jobId && other.reason == reason;

  @override
  int get hashCode => Object.hash(jobId, reason);

  @override
  String toString() => 'ReminderSkip($jobId, ${reason.name})';
}

/// The full desired reminder state at one instant.
class ReminderPlan {
  ReminderPlan({
    required this.generatedAtUtc,
    required List<ReminderPlanEntry> entries,
    required List<ReminderSkip> skipped,
  }) : entries = List<ReminderPlanEntry>.unmodifiable(entries),
       skipped = List<ReminderSkip>.unmodifiable(skipped);

  /// The injected `now`, normalised to UTC. Part of the plan so callers can
  /// tell which instant the decision was made at.
  final DateTime generatedAtUtc;

  /// Entries to keep scheduled, ordered by `(dueAtUtc, jobId)`.
  final List<ReminderPlanEntry> entries;

  /// Selected jobs with no reminder, ordered by `jobId`.
  final List<ReminderSkip> skipped;

  bool get isEmpty => entries.isEmpty;

  /// The reason recorded for [jobId], if it was skipped.
  ReminderSkipReason? skipReasonFor(String jobId) {
    for (final skip in skipped) {
      if (skip.jobId == jobId) return skip.reason;
    }
    return null;
  }

  ReminderPlanEntry? entryFor(String jobId) {
    for (final entry in entries) {
      if (entry.jobId == jobId) return entry;
    }
    return null;
  }

  @override
  String toString() =>
      'ReminderPlan(at $generatedAtUtc, ${entries.length} entries, '
      '${skipped.length} skipped)';
}

/// Resolves a job's effective closing instant, or `null` when it has none.
///
/// The contract rule, applied identically everywhere:
///  * an exact `applicationEndAt` (UTC timestamp) wins, always;
///  * otherwise a date-only `applicationEndDate` is **inclusive for that
///    calendar day in Asia/Kolkata**, so it closes at 00:00 IST the next day
///    (`2026-11-15` -> `2026-11-15T18:30:00Z`). No closing time is invented for
///    display; this is a comparison boundary only;
///  * no deadline fields -> `null`.
///
/// `lib/features/common/formatting.dart` implements the same rule for the UI;
/// a data-layer copy exists because the planner may not import feature code.
/// `test/data/reminders/deadline_rule_consistency_test.dart` guards the two
/// against divergence.
DateTime? reminderDeadlineUtc(Job job) {
  final exact = job.applicationEndAt;
  if (exact != null) return exact.toUtc();
  final dateOnly = job.applicationEndDate;
  if (dateOnly == null) return null;
  try {
    return istExclusiveNextDayUtc(dateOnly);
  } on FormatException {
    return null;
  }
}

/// Exclusive closing boundary for a date-only deadline, in UTC.
///
/// `2026-11-15` (inclusive) closes at `2026-11-16T00:00:00+05:30`
/// == `2026-11-15T18:30:00Z`.
///
/// Only the contract's exact `YYYY-MM-DD` shape is accepted, with a real
/// calendar day (the same rule `Job.fromJson` enforces). Anything else throws
/// [FormatException] and [reminderDeadlineUtc] turns that into `null` rather
/// than inventing a boundary from a malformed string.
DateTime istExclusiveNextDayUtc(String dateOnly) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateOnly)) {
    throw FormatException('Not a date-only value: $dateOnly');
  }
  final parts = dateOnly.split('-');
  final y = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  final d = int.parse(parts[2]);
  final startOfDay = DateTime.utc(y, m, d);
  // Reject overflow such as 2026-02-30: DateTime.utc would silently roll it to
  // March, which would move a deadline the feed never stated.
  if (startOfDay.year != y || startOfDay.month != m || startOfDay.day != d) {
    throw FormatException('Not a calendar date: $dateOnly');
  }
  return startOfDay.add(const Duration(days: 1)).subtract(_istOffset);
}

/// Builds the desired reminder plan.
///
/// [jobs] is the current feed, [selectedJobIds] the persisted reminder intent
/// (`UserPreferences.reminderJobIds`), and [now] the injected clock. No global
/// clock is read: the same inputs always produce the same plan.
///
/// Rules, in order, per selected ID:
///  1. not in [jobs] -> [ReminderSkipReason.jobUnavailable];
///  2. not a recruitment -> [ReminderSkipReason.unsupportedKind];
///  3. feed status not open -> [ReminderSkipReason.notOpen];
///  4. no resolvable deadline -> [ReminderSkipReason.noDeadline];
///  5. deadline already reached (`closesAt <= now`) ->
///     [ReminderSkipReason.deadlinePassed];
///  6. reminder time not strictly in the future (`dueAt <= now`) ->
///     [ReminderSkipReason.optedInTooLate].
///
/// Duplicate IDs in [jobs] would mean an invalid feed (the contract parser
/// rejects them); the planner fails loudly with [ArgumentError] rather than
/// silently picking one.
ReminderPlan planReminders({
  required Iterable<Job> jobs,
  required Iterable<String> selectedJobIds,
  required DateTime now,
}) {
  final byId = <String, Job>{};
  for (final job in jobs) {
    if (byId.containsKey(job.id)) {
      throw ArgumentError.value(
        job.id,
        'jobs',
        'duplicate job id: the feed contract guarantees unique ids',
      );
    }
    byId[job.id] = job;
  }

  final nowUtc = now.toUtc();
  final entries = <ReminderPlanEntry>[];
  final skipped = <ReminderSkip>[];

  // Sorting the selection makes the result independent of input order and
  // makes the skip list stable.
  final selected = selectedJobIds.toSet().toList()..sort();

  for (final id in selected) {
    final job = byId[id];
    if (job == null) {
      skipped.add(
        ReminderSkip(jobId: id, reason: ReminderSkipReason.jobUnavailable),
      );
      continue;
    }
    if (job.kind != JobKind.recruitment) {
      skipped.add(
        ReminderSkip(jobId: id, reason: ReminderSkipReason.unsupportedKind),
      );
      continue;
    }
    if (job.status != JobStatus.open) {
      skipped.add(ReminderSkip(jobId: id, reason: ReminderSkipReason.notOpen));
      continue;
    }
    final closesAt = reminderDeadlineUtc(job);
    if (closesAt == null) {
      skipped.add(
        ReminderSkip(jobId: id, reason: ReminderSkipReason.noDeadline),
      );
      continue;
    }
    if (!closesAt.isAfter(nowUtc)) {
      skipped.add(
        ReminderSkip(jobId: id, reason: ReminderSkipReason.deadlinePassed),
      );
      continue;
    }
    final dueAt = closesAt.subtract(reminderLeadTime);
    if (!dueAt.isAfter(nowUtc)) {
      // Equality is not new work: the reminder time has arrived or passed.
      skipped.add(
        ReminderSkip(jobId: id, reason: ReminderSkipReason.optedInTooLate),
      );
      continue;
    }
    entries.add(
      ReminderPlanEntry(
        jobId: job.id,
        dueAtUtc: dueAt,
        closesAtUtc: closesAt,
        contentKey: reminderContentKey(job, closesAt),
      ),
    );
  }

  entries.sort((a, b) {
    final byDue = a.dueAtUtc.compareTo(b.dueAtUtc);
    return byDue != 0 ? byDue : a.jobId.compareTo(b.jobId);
  });

  return ReminderPlan(
    generatedAtUtc: nowUtc,
    entries: entries,
    skipped: skipped,
  );
}

/// Stable fingerprint of what an alert would say about [job].
///
/// Deliberately not `Object.hashCode`: that is not stable across runs or
/// platforms, and this value is compared between two plan builds. It is a
/// change detector, **not** a platform notification ID — the captain allocates
/// those and must not derive them from this string.
///
/// Both language titles and the deadline source are included, so correcting a
/// title, adding the other language, or fixing the deadline replaces a stale
/// reminder instead of silently keeping it.
String reminderContentKey(Job job, DateTime closesAtUtc) {
  final parts = <String>[
    job.id,
    job.kind.name,
    job.status.name,
    job.titleBn,
    job.titleEn,
    job.organization,
    // The date-only value is kept verbatim next to the resolved instant so a
    // change from date-only to an exact timestamp is visible even when the
    // resolved instant happens to coincide.
    job.applicationEndDate ?? '',
    job.applicationEndAt?.toUtc().toIso8601String() ?? '',
    closesAtUtc.toUtc().toIso8601String(),
  ];
  // Length-prefixing keeps the key unambiguous when a field contains '|'.
  return parts.map((p) => '${p.length}:$p').join('|');
}
