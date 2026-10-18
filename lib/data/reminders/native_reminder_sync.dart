/// Ledger-backed synchronization for native notification reminders.
///
/// This module composes the pure planner and durable reminder ledger with the
/// frozen [NativeNotifications] port. It does not own plugin lifecycle, ask for
/// permission, mutate selected-job intent, or infer that a pending record proves
/// an alarm is live or has been delivered.
library;

import 'dart:async';

import '../../contracts/job.dart';
import '../../contracts/native_reminders.dart';
import '../preferences_store.dart';
import 'reminder_apply.dart';
import 'reminder_plan.dart';
import 'reminder_state.dart';
import 'reminder_state_store.dart';

/// Localized copy used to construct a native reminder request.
class ReminderNotificationText {
  const ReminderNotificationText({required this.title, required this.body});

  final String title;
  final String body;
}

typedef ReminderNotificationTextBuilder = ReminderNotificationText Function(
  Job job,
  String languageCode,
);

/// Synchronizes a verified feed and selected reminder intent against the
/// durable ledger and the backend's complete pending-notification records.
class LedgerNativeReminderSynchronizer implements ReminderSynchronizer {
  LedgerNativeReminderSynchronizer({
    required PreferencesStore store,
    ReminderStateStore? stateStore,
    required NativeNotifications notifications,
    required ReminderNotificationTextBuilder textForJob,
    DateTime Function()? nowUtc,
  }) : _store = stateStore ?? ReminderStateStore(store: store),
       _notifications = notifications,
       _textForJob = textForJob,
       _nowUtc = nowUtc ?? _currentUtc {
    _applier = ReminderApplier(_store);
  }

  final ReminderStateStore _store;
  final NativeNotifications _notifications;
  final ReminderNotificationTextBuilder _textForJob;
  final DateTime Function() _nowUtc;
  late final ReminderApplier _applier;

  Future<void>? _queue;
  Future<void>? _closeFuture;
  bool _closing = false;

  @override
  Future<ReminderSyncReport> synchronize(ReminderSyncInput input) {
    if (_closing) {
      return Future<ReminderSyncReport>.error(
        StateError('the reminder synchronizer is closing or closed'),
      );
    }

    final completer = Completer<ReminderSyncReport>();
    final previous = _queue ?? Future<void>.value();
    _queue = previous.then((_) async {
      try {
        completer.complete(await _synchronize(input));
      } catch (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  @override
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;

    _closing = true;
    final previous = _queue ?? Future<void>.value();
    _closeFuture = previous.then((_) {
      _store.dispose();
    });
    return _closeFuture!;
  }

  Future<ReminderSyncReport> _synchronize(ReminderSyncInput input) async {
    final feedAvailable = input.jobs != null;
    final ReminderPermission permission;
    try {
      permission = await _notifications.permissionStatus();
    } catch (error, stack) {
      return _problemReport(
        permission: ReminderPermission.unavailable,
        feedAvailable: feedAvailable,
        stage: ReminderSyncStage.permission,
        error: error,
        stackTrace: stack,
      );
    }

    // Without a verified feed, permission is passive status only. An empty
    // verified feed is different: it proceeds below and may remove known work.
    if (!feedAvailable) {
      return _emptyReport(permission: permission, feedAvailable: false);
    }

    if (permission == ReminderPermission.unavailable ||
        permission == ReminderPermission.unsupported) {
      return _emptyReport(permission: permission, feedAvailable: true);
    }

    final jobs = input.jobs!;
    final now = _nowUtc().toUtc();
    final ReminderPlan desiredPlan;
    final Map<String, Job> jobsById;
    try {
      desiredPlan = planReminders(
        jobs: jobs,
        selectedJobIds: permission == ReminderPermission.granted
            ? input.selectedJobIds
            : const <String>[],
        now: now,
      );
      jobsById = <String, Job>{for (final job in jobs) job.id: job};
    } catch (error, stack) {
      return _problemReport(
        permission: permission,
        feedAvailable: true,
        stage: ReminderSyncStage.conflict,
        error: error,
        stackTrace: stack,
      );
    }

    final String payloadVariant;
    try {
      payloadVariant = reminderPayloadVariant(input.languageCode);
    } catch (error, stack) {
      return _problemReport(
        permission: permission,
        feedAvailable: true,
        stage: ReminderSyncStage.conflict,
        error: error,
        stackTrace: stack,
      );
    }

    try {
      await _store.initialize();
    } catch (error, stack) {
      return _problemReport(
        permission: permission,
        feedAvailable: true,
        stage: ReminderSyncStage.ledger,
        error: error,
        stackTrace: stack,
      );
    }

    final before = _store.snapshot;
    final pendingRecords = <NativePendingReminder>[];
    final bridge = _NativeReminderPlatform(
      notifications: _notifications,
      textForJob: _textForJob,
      jobsById: jobsById,
      languageCode: input.languageCode,
      payloadVariant: payloadVariant,
      nowUtc: _nowUtc,
    );

    final ReminderApplyResult result;
    try {
      result = await _applier.reconcile(
        desiredPlan,
        bridge,
        payloadVariant,
        readPendingReminders: () async {
          try {
            final records = await _notifications.pendingReminders();
            final copy = List<NativePendingReminder>.of(records);
            pendingRecords
              ..clear()
              ..addAll(copy);
            return copy;
          } catch (error, stack) {
            Error.throwWithStackTrace(
              _PendingQueryFailure(error, stack),
              stack,
            );
          }
        },
      );
    } catch (error, stack) {
      if (error is _PendingQueryFailure) {
        return _problemReport(
          permission: permission,
          feedAvailable: true,
          stage: ReminderSyncStage.pending,
          error: error.error,
          stackTrace: error.stackTrace,
        );
      }
      return _problemReport(
        permission: permission,
        feedAvailable: true,
        stage: error is ReminderStateException
            ? ReminderSyncStage.ledger
            : ReminderSyncStage.conflict,
        error: error,
        stackTrace: stack,
      );
    }

    final problems = <ReminderSyncProblem>[
      for (final failure in result.failures)
        ReminderSyncProblem(
          stage: failure.error is ReminderStateException
              ? ReminderSyncStage.ledger
              : failure.duringCancellation
              ? ReminderSyncStage.cancel
              : ReminderSyncStage.schedule,
          jobId: failure.jobId,
          platformId: _store.snapshot.platformIdFor(failure.jobId),
          error: failure.error,
          stackTrace: failure.stackTrace,
        ),
    ];

    final pendingIds = pendingRecords
        .map((record) => record.platformId)
        .toSet();
    final cancelledOrphanIds = <int>[];
    for (final jobId in result.cancelledJobIds) {
      final registry = before.entryFor(jobId);
      if (registry != null &&
          registry.applied == null &&
          pendingIds.contains(registry.platformId)) {
        cancelledOrphanIds.add(registry.platformId);
      }
    }

    return ReminderSyncReport(
      permission: permission,
      feedAvailable: true,
      scheduledJobIds: result.scheduledEntries.map((entry) => entry.jobId),
      cancelledJobIds: result.cancelledJobIds,
      cancelledOrphanIds: cancelledOrphanIds,
      problems: problems,
    );
  }

  static ReminderSyncReport _emptyReport({
    required ReminderPermission permission,
    required bool feedAvailable,
  }) => ReminderSyncReport(
    permission: permission,
    feedAvailable: feedAvailable,
    scheduledJobIds: const <String>[],
    cancelledJobIds: const <String>[],
    cancelledOrphanIds: const <int>[],
    problems: const <ReminderSyncProblem>[],
  );

  static ReminderSyncReport _problemReport({
    required ReminderPermission permission,
    required bool feedAvailable,
    required ReminderSyncStage stage,
    required Object error,
    required StackTrace stackTrace,
  }) => ReminderSyncReport(
    permission: permission,
    feedAvailable: feedAvailable,
    scheduledJobIds: const <String>[],
    cancelledJobIds: const <String>[],
    cancelledOrphanIds: const <int>[],
    problems: <ReminderSyncProblem>[
      ReminderSyncProblem(stage: stage, error: error, stackTrace: stackTrace),
    ],
  );

  static DateTime _currentUtc() => DateTime.now().toUtc();
}

class _NativeReminderPlatform implements ReminderPlatform {
  const _NativeReminderPlatform({
    required NativeNotifications notifications,
    required ReminderNotificationTextBuilder textForJob,
    required Map<String, Job> jobsById,
    required String languageCode,
    required String payloadVariant,
    required DateTime Function() nowUtc,
  }) : _notifications = notifications,
       _textForJob = textForJob,
       _jobsById = jobsById,
       _languageCode = languageCode,
       _payloadVariant = payloadVariant,
       _nowUtc = nowUtc;

  final NativeNotifications _notifications;
  final ReminderNotificationTextBuilder _textForJob;
  final Map<String, Job> _jobsById;
  final String _languageCode;
  final String _payloadVariant;
  final DateTime Function() _nowUtc;

  @override
  Future<void> cancel(int id) => _notifications.cancel(id);

  @override
  Future<void> schedule(ReminderPlanEntry entry, int platformId) async {
    final job = _jobsById[entry.jobId];
    if (job == null) {
      throw StateError('no feed Job matches reminder ${entry.jobId}');
    }

    final text = _textForJob(job, _languageCode);
    if (text.title.trim().isEmpty || text.body.trim().isEmpty) {
      throw StateError('reminder title and body must not be blank');
    }

    final identity = NativeReminderIdentity(
      jobId: entry.jobId,
      dueAtUtc: entry.dueAtUtc,
      closesAtUtc: entry.closesAtUtc,
      contentKey: entry.contentKey,
      payloadVariant: _payloadVariant,
    );
    final request = NativeReminderRequest(
      platformId: platformId,
      identity: identity,
      title: text.title,
      body: text.body,
    );

    if (!entry.dueAtUtc.isAfter(_nowUtc().toUtc())) {
      throw StateError('reminder ${entry.jobId} is no longer in the future');
    }
    await _notifications.schedule(request);
  }
}

class _PendingQueryFailure implements Exception {
  const _PendingQueryFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}
