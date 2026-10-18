/// Pure reminder apply orchestrator: turns a desired plan (via a
/// [ReminderDiff]) into durable platform effects through [ReminderStateStore].
///
/// This module owns the *what-happens-in-what-order* between the pure diff
/// (A4), the durable ledger (A5), and the captain's OS-facing plugin. It never
/// imports a plugin, `lib/features`, the network or the file system: the
/// captain supplies a [ReminderPlatform] implementation, and this library only
/// sequences calls and persists reported successes.
///
/// Rules for one apply:
///
///  1. **Reconcile against what the ledger says is applied.** [apply]
///     reconstructs the previous plan from the store snapshot (only entries
///     with non-null applied metadata count as "on the platform") and diffs it
///     against the desired plan with A4's `diffReminderPlans`. [applyDiff]
///     skips that step and executes a caller-computed diff verbatim.
///  2. **Cancel before schedule.** Every cancellation runs before any
///     scheduling, so a replacement for the same job never leaves two live
///     notifications for one job. If the cancellation half of a replacement
///     fails, that job's scheduling in the same apply is skipped (a later
///     apply retries it, because the ledger still shows the old entry as
///     applied and the same diff is produced again).
///  3. **Stable IDs, never reused, never wrapped.** [ReminderStateStore]
///     `reserve()` runs before any schedule attempt; an existing reservation
///     is returned without a write, a new ID is allocated monotonically and
///     persisted before the platform is touched, and exhaustion at
///     `2147483647` (`maxPlatformId`) surfaces as a per-job
///     [ReminderStateFailure.exhausted] instead of reusing an ID.
///  4. **Persist per success, never before.** `recordCancellationSuccess` is
///     called only after `platform.cancel` reports success, and
///     `recordSchedulingSuccess` only after `platform.schedule` reports
///     success, with the exact [ReminderPlanEntry] and the captain-supplied
///     `payloadVariant` passed through untouched. A platform or storage
///     failure leaves the ledger on its previous value for that job (A5's
///     write-then-publish store guarantees this) and surfaces in the result
///     instead of marking the plan applied. Note the unavoidable crash
///     window documented in A5: if the OS accepts an operation and the
///     process dies before the record write, the ledger lags the OS until a
///     later apply reconciles (same ID, idempotent re-apply).
///  5. **Variant freshness.** An otherwise-retained entry whose recorded
///     `payloadVariant` differs from the one supplied to [apply] is treated
///     as a replacement (cancel + schedule under the same platform ID), so
///     switching language or notification copy never leaves stale text on
///     the lock screen. [applyDiff] does not do this: a hand-built diff is
///     executed exactly as given.
///  6. **Serialised applies.** Concurrent [apply]/[applyDiff] calls on one
///     applier run strictly one after another, and the store serialises its
///     own read-modify-writes underneath, so duplicate platform IDs are
///     impossible even when callers do not coordinate.
///  7. **Unknown jobs in a diff are ignored.** A cancellation naming a job
///     with no reservation (or nothing applied) in the ledger cannot be
///     executed — there is no platform ID to cancel — and is skipped
///     silently rather than failing the whole apply.
library;

import 'dart:async';

import 'reminder_diff.dart';
import 'reminder_plan.dart';
import 'reminder_state.dart';
import 'reminder_state_store.dart';

/// The captain's OS-facing notification surface.
///
/// Implementations wrap whatever plugin or channel actually talks to the
/// operating system. A method reports success by completing normally and
/// failure by throwing; the orchestrator records a throw as a per-job
/// failure and moves on to the next job. No plugin is imported here, which
/// keeps the data layer pure and testable without a Flutter engine.
abstract class ReminderPlatform {
  /// Cancels the notification previously scheduled under [id].
  ///
  /// Implementations should treat "nothing scheduled under this id" as
  /// success rather than throwing, because the A5 crash window can leave
  /// the OS and the ledger briefly out of sync.
  Future<void> cancel(int id);

  /// Schedules a notification for [entry] under [platformId].
  ///
  /// [platformId] is stable for the life of the job's reservation and is the
  /// same ID later passed to [cancel] on removal or replacement.
  Future<void> schedule(ReminderPlanEntry entry, int platformId);
}

/// One job's failure during an apply.
///
/// The orchestrator continues with the next job whenever it can, so one
/// broken notification never blocks the rest of the plan; the caller decides
/// whether to surface a retry affordance.
class ReminderApplyFailure {
  const ReminderApplyFailure({
    required this.jobId,
    required this.error,
    required this.stackTrace,
    required this.duringCancellation,
  });

  /// The job this failure belongs to.
  final String jobId;

  /// What was thrown: a [ReminderStateException] when the ledger was the
  /// failing side, otherwise the platform implementation's own error,
  /// verbatim.
  final Object error;

  /// Stack trace captured where [error] was thrown.
  final StackTrace stackTrace;

  /// `true` when the failure happened in the cancellation phase (platform
  /// cancel or its record write); `false` in the scheduling phase
  /// (reservation, platform schedule, or its record write).
  final bool duringCancellation;

  /// The A5 failure category when [error] came from the ledger, else `null`.
  ReminderStateFailure? get stateFailure => error is ReminderStateException
      ? (error as ReminderStateException).failure
      : null;

  @override
  String toString() =>
      'ReminderApplyFailure($jobId, '
      '${duringCancellation ? 'cancel' : 'schedule'}: $error)';
}

/// The outcome of one [ReminderApplier.apply] or
/// [ReminderApplier.applyDiff] call.
///
/// Successes are already durable on both sides when this is returned: each
/// listed cancellation/schedule reached the platform *and* was recorded in
/// the ledger. Anything not listed either was not attempted or is named in
/// [failures].
class ReminderApplyResult {
  const ReminderApplyResult({
    required this.cancelledJobIds,
    required this.scheduledEntries,
    required this.failures,
  });

  /// Jobs whose cancellation reached the platform and was recorded, in the
  /// order executed (diff cancellation order: by job ID).
  final List<String> cancelledJobIds;

  /// Entries whose scheduling reached the platform and was recorded with the
  /// supplied `payloadVariant`, in the order executed (by due time, then
  /// job ID).
  final List<ReminderPlanEntry> scheduledEntries;

  /// Per-job failures in encounter order (cancellations first, then
  /// schedules). A job listed here appears in neither success list — with
  /// one exception: if the platform operation succeeded but the ledger
  /// record write failed, the OS-side effect happened and the failure's
  /// [ReminderApplyFailure.duringCancellation] says which half is unrecorded;
  /// the next apply reconciles it.
  final List<ReminderApplyFailure> failures;

  /// True when nothing was applied (empty diff, or every job failed —
  /// distinguish via [failures]).
  bool get isNoOp => cancelledJobIds.isEmpty && scheduledEntries.isEmpty;

  /// True when every attempted job succeeded.
  bool get isFullySuccessful => failures.isEmpty;

  @override
  String toString() =>
      'ReminderApplyResult(${cancelledJobIds.length} cancel, '
      '${scheduledEntries.length} schedule, ${failures.length} failed)';
}

/// Applies desired reminder plans to a [ReminderPlatform], reconciling
/// through a [ReminderStateStore].
///
/// Construct one applier per store for the app's lifetime and call [apply]
/// whenever the desired plan or the payload variant changes (reminder
/// toggled, feed refreshed, language/copy version switched).
class ReminderApplier {
  ReminderApplier(this._store);

  final ReminderStateStore _store;

  /// Tail of the apply queue; each call chains behind the previous one.
  Future<void>? _queue;

  /// Diffs [desiredPlan] against the ledger's applied state and applies the
  /// result: cancellations first, then schedules, persisting each success.
  ///
  /// [payloadVariant] is the captain's opaque variant string (for example
  /// `bn@copy-3`); it is recorded verbatim and a change in it re-schedules
  /// retained entries. It must not be blank.
  ///
  /// Per-job failures never throw — they are returned in
  /// [ReminderApplyResult.failures]. This throws only when no job could be
  /// processed safely at all: a blank [payloadVariant] ([ArgumentError]), or
  /// a ledger that cannot be loaded ([ReminderStateException] such as
  /// `unreadable`/`corrupt`), in which case the platform was not touched and
  /// nothing was written.
  Future<ReminderApplyResult> apply(
    ReminderPlan desiredPlan,
    ReminderPlatform platform,
    String payloadVariant,
  ) {
    return _enqueue(() async {
      _validateVariant(payloadVariant);
      await _store.initialize();
      final snapshot = _store.snapshot;
      var diff = diffReminderPlans(
        previous: _previousPlanFromSnapshot(snapshot),
        desired: desiredPlan,
      );
      diff = _withVariantReplacements(diff, snapshot, payloadVariant);
      return _executeDiff(diff, platform, payloadVariant);
    });
  }

  /// Applies a caller-computed [diff] exactly as given (no variant
  /// re-check of its retained entries).
  ///
  /// Cancellations for jobs the ledger has never reserved (or no longer
  /// shows as applied) are ignored: there is no platform ID to cancel.
  /// Otherwise the same ordering, persistence and failure rules as [apply]
  /// hold, including a throw when the ledger cannot be loaded.
  Future<ReminderApplyResult> applyDiff(
    ReminderDiff diff,
    ReminderPlatform platform,
    String payloadVariant,
  ) {
    return _enqueue(() async {
      _validateVariant(payloadVariant);
      await _store.initialize();
      return _executeDiff(diff, platform, payloadVariant);
    });
  }

  /// Runs [task] after every previously enqueued apply has finished.
  ///
  /// Enqueueing happens synchronously at call time, so calls made in the
  /// same event turn execute in call order. A throwing task reports to its
  /// own caller only and never poisons the queue.
  Future<ReminderApplyResult> _enqueue(
    Future<ReminderApplyResult> Function() task,
  ) {
    final completer = Completer<ReminderApplyResult>();
    final previous = _queue ?? Future<void>.value();
    _queue = previous.then((_) async {
      try {
        completer.complete(await task());
      } catch (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<ReminderApplyResult> _executeDiff(
    ReminderDiff diff,
    ReminderPlatform platform,
    String payloadVariant,
  ) async {
    final cancelled = <String>[];
    final scheduled = <ReminderPlanEntry>[];
    final failures = <ReminderApplyFailure>[];
    final failedJobs = <String>{};

    // Phase 1: every cancellation, in diff order (by job ID).
    for (final cancellation in diff.cancellations) {
      final registry = _store.snapshot.entryFor(cancellation.jobId);
      if (registry == null || registry.applied == null) {
        // Unknown (or already-cancelled) job: no platform ID is known to
        // cancel, and the ledger already agrees nothing is applied. Ignore.
        continue;
      }
      try {
        await platform.cancel(registry.platformId);
      } catch (error, stack) {
        failures.add(
          ReminderApplyFailure(
            jobId: cancellation.jobId,
            error: error,
            stackTrace: stack,
            duringCancellation: true,
          ),
        );
        failedJobs.add(cancellation.jobId);
        continue;
      }
      try {
        await _store.recordCancellationSuccess(cancellation.jobId);
      } catch (error, stack) {
        failures.add(
          ReminderApplyFailure(
            jobId: cancellation.jobId,
            error: error,
            stackTrace: stack,
            duringCancellation: true,
          ),
        );
        failedJobs.add(cancellation.jobId);
        continue;
      }
      cancelled.add(cancellation.jobId);
    }

    // Phase 2: every schedule, in diff order (due time, then job ID).
    // Replacements reuse the reservation cancelled in phase 1, so the
    // platform ID is unchanged; new jobs allocate here, before scheduling.
    for (final scheduling in diff.schedules) {
      if (failedJobs.contains(scheduling.entry.jobId)) {
        // Its cancellation just failed; scheduling over a possibly-live
        // old notification would leave the OS state unknown. The next
        // apply reproduces this diff and retries the pair.
        continue;
      }
      final ReminderReservation reservation;
      try {
        reservation = await _store.reserve(scheduling.entry.jobId);
      } catch (error, stack) {
        // Includes ReminderStateFailure.exhausted: terminal, never a wrap
        // or reuse, and this job simply does not schedule.
        failures.add(
          ReminderApplyFailure(
            jobId: scheduling.entry.jobId,
            error: error,
            stackTrace: stack,
            duringCancellation: false,
          ),
        );
        failedJobs.add(scheduling.entry.jobId);
        continue;
      }
      try {
        await platform.schedule(scheduling.entry, reservation.platformId);
      } catch (error, stack) {
        failures.add(
          ReminderApplyFailure(
            jobId: scheduling.entry.jobId,
            error: error,
            stackTrace: stack,
            duringCancellation: false,
          ),
        );
        failedJobs.add(scheduling.entry.jobId);
        continue;
      }
      try {
        await _store.recordSchedulingSuccess(
          entry: scheduling.entry,
          payloadVariant: payloadVariant,
        );
      } catch (error, stack) {
        failures.add(
          ReminderApplyFailure(
            jobId: scheduling.entry.jobId,
            error: error,
            stackTrace: stack,
            duringCancellation: false,
          ),
        );
        failedJobs.add(scheduling.entry.jobId);
        continue;
      }
      scheduled.add(scheduling.entry);
    }

    return ReminderApplyResult(
      cancelledJobIds: List<String>.unmodifiable(cancelled),
      scheduledEntries: List<ReminderPlanEntry>.unmodifiable(scheduled),
      failures: List<ReminderApplyFailure>.unmodifiable(failures),
    );
  }

  static void _validateVariant(String payloadVariant) {
    if (payloadVariant.trim().isEmpty) {
      throw ArgumentError.value(
        payloadVariant,
        'payloadVariant',
        'must not be empty or whitespace',
      );
    }
  }

  /// The plan the OS currently holds, according to the ledger.
  ///
  /// Only rows with applied metadata count; a bare reservation means
  /// "allocated but never recorded as scheduled", which is exactly how the
  /// diff must treat it (as a fresh schedule, reusing the ID). The
  /// generation timestamp is a placeholder — the diff reads only entries.
  static ReminderPlan _previousPlanFromSnapshot(ReminderState snapshot) {
    final entries = <ReminderPlanEntry>[
      for (final registry in snapshot.entries)
        if (registry.applied != null)
          ReminderPlanEntry(
            jobId: registry.jobId,
            dueAtUtc: registry.applied!.dueAtUtc,
            closesAtUtc: registry.applied!.closesAtUtc,
            contentKey: registry.applied!.contentKey,
          ),
    ];
    entries.sort((a, b) {
      final byDue = a.dueAtUtc.compareTo(b.dueAtUtc);
      return byDue != 0 ? byDue : a.jobId.compareTo(b.jobId);
    });
    return ReminderPlan(
      generatedAtUtc: DateTime.utc(1970),
      entries: entries,
      skipped: const <ReminderSkip>[],
    );
  }

  /// Moves retained entries recorded under a different payload variant into
  /// the cancel/schedule sets as replacements (same platform ID), keeping
  /// the diff's documented orderings.
  static ReminderDiff _withVariantReplacements(
    ReminderDiff diff,
    ReminderState snapshot,
    String payloadVariant,
  ) {
    final stale = <ReminderPlanEntry>[
      for (final entry in diff.retained)
        if (snapshot.appliedFor(entry.jobId)?.payloadVariant != null &&
            snapshot.appliedFor(entry.jobId)!.payloadVariant != payloadVariant)
          entry,
    ];
    if (stale.isEmpty) return diff;
    final staleIds = stale.map((e) => e.jobId).toSet();
    final cancellations = <ReminderCancellation>[
      ...diff.cancellations,
      for (final entry in stale)
        ReminderCancellation(jobId: entry.jobId, previous: entry),
    ]..sort((a, b) => a.jobId.compareTo(b.jobId));
    final schedules =
        <ReminderScheduling>[
          ...diff.schedules,
          for (final entry in stale)
            ReminderScheduling(entry: entry, isReplacement: true),
        ]..sort((a, b) {
          final byDue = a.entry.dueAtUtc.compareTo(b.entry.dueAtUtc);
          return byDue != 0 ? byDue : a.entry.jobId.compareTo(b.entry.jobId);
        });
    return ReminderDiff(
      cancellations: cancellations,
      schedules: schedules,
      retained: <ReminderPlanEntry>[
        for (final entry in diff.retained)
          if (!staleIds.contains(entry.jobId)) entry,
      ],
    );
  }
}
