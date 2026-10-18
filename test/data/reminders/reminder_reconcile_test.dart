import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/data/reminders/reminder_apply.dart';
import 'package:karmopath/data/reminders/reminder_plan.dart';
import 'package:karmopath/data/reminders/reminder_state.dart';
import 'package:karmopath/data/reminders/reminder_state_store.dart';

import '../fakes.dart';

DateTime _utc(int day, [int hour = 12]) => DateTime.utc(2026, 11, day, hour);

ReminderPlanEntry _entry(
  String jobId, {
  DateTime? dueAtUtc,
  String contentKey = 'content-v1',
}) {
  final due = dueAtUtc ?? _utc(19);
  return ReminderPlanEntry(
    jobId: jobId,
    dueAtUtc: due,
    closesAtUtc: due.add(const Duration(days: 1)),
    contentKey: contentKey,
  );
}

ReminderPlan _plan(List<ReminderPlanEntry> entries) => ReminderPlan(
  generatedAtUtc: DateTime.utc(2026, 1, 1),
  entries: entries,
  skipped: const <ReminderSkip>[],
);

class _RecordingPlatform implements ReminderPlatform {
  final List<String> events = <String>[];
  final Set<int> pendingIds = <int>{};
  final Set<int> failingCancelIds = <int>{};
  final Set<String> failingScheduleJobs = <String>{};

  Object cancelError = StateError('platform cancel failed');
  Object scheduleError = StateError('platform schedule failed');
  Future<void>? scheduleGate;
  void Function(int id)? onCancel;
  void Function(ReminderPlanEntry entry, int id)? onSchedule;
  int cancelCalls = 0;
  int scheduleCalls = 0;

  @override
  Future<void> cancel(int id) async {
    cancelCalls++;
    events.add('cancel:$id');
    onCancel?.call(id);
    if (failingCancelIds.contains(id)) throw cancelError;
    pendingIds.remove(id);
  }

  @override
  Future<void> schedule(ReminderPlanEntry entry, int platformId) async {
    scheduleCalls++;
    events.add('schedule:${entry.jobId}:$platformId');
    onSchedule?.call(entry, platformId);
    final gate = scheduleGate;
    if (gate != null) await gate;
    if (failingScheduleJobs.contains(entry.jobId)) throw scheduleError;
    pendingIds.add(platformId);
  }
}

class _Stack {
  _Stack({FakePreferencesStore? prefs})
    : prefs = prefs ?? FakePreferencesStore() {
    store = ReminderStateStore(store: this.prefs);
    applier = ReminderApplier(store);
  }

  final FakePreferencesStore prefs;
  late final ReminderStateStore store;
  late final ReminderApplier applier;
  final _RecordingPlatform platform = _RecordingPlatform();

  int get writes =>
      prefs.writeCounts.values.fold(0, (total, count) => total + count);

  void dispose() => store.dispose();
}

Future<int> _seedApplied(
  _Stack stack,
  ReminderPlanEntry entry, {
  String variant = 'bn@copy-1',
}) async {
  final reservation = await stack.store.reserve(entry.jobId);
  await stack.store.recordSchedulingSuccess(
    entry: entry,
    payloadVariant: variant,
  );
  return reservation.platformId;
}

void main() {
  group('matching and repair', () {
    test(
      'matching applied entry and pending ID is a no-op with no writes',
      () async {
        final stack = _Stack();
        final desiredEntry = _entry('a-job');
        final id = await _seedApplied(stack, desiredEntry);
        stack.platform.pendingIds.add(id);
        final writesBefore = stack.writes;
        var queryCalls = 0;

        final result = await stack.applier.reconcile(
          _plan([desiredEntry]),
          stack.platform,
          'bn@copy-1',
          readPendingPlatformIds: () async {
            queryCalls++;
            return stack.platform.pendingIds;
          },
        );

        expect(result.isNoOp, isTrue);
        expect(result.failures, isEmpty);
        expect(queryCalls, 1);
        expect(stack.platform.events, isEmpty);
        expect(stack.writes, writesBefore);
        expect(stack.store.snapshot.appliedFor('a-job'), isNotNull);
        stack.dispose();
      },
    );

    test('missing OS reminder is repaired with its stable ID', () async {
      final stack = _Stack();
      final desiredEntry = _entry('a-job');
      final id = await _seedApplied(stack, desiredEntry);
      final writesBefore = stack.writes;

      final result = await stack.applier.reconcile(
        _plan([desiredEntry]),
        stack.platform,
        'bn@copy-1',
        readPendingPlatformIds: () async => stack.platform.pendingIds,
      );

      expect(stack.platform.events, ['cancel:$id', 'schedule:a-job:$id']);
      expect(result.cancelledJobIds, ['a-job']);
      expect(result.scheduledEntries, [desiredEntry]);
      expect(stack.store.snapshot.platformIdFor('a-job'), id);
      expect(
        stack.store.snapshot.appliedFor('a-job')?.contentKey,
        'content-v1',
      );
      expect(stack.writes, writesBefore + 2);
      stack.dispose();
    });

    test(
      'changed deadline/content and stale variant replace under stable IDs',
      () async {
        final stack = _Stack();
        final changedOld = _entry('a-changed', contentKey: 'old-content');
        final staleVariant = _entry('b-variant');
        final changedId = await _seedApplied(stack, changedOld);
        final variantId = await _seedApplied(
          stack,
          staleVariant,
          variant: 'bn@copy-0',
        );
        stack.platform.pendingIds.addAll([changedId, variantId]);
        final changedNew = _entry(
          'a-changed',
          dueAtUtc: _utc(22),
          contentKey: 'new-content',
        );

        final result = await stack.applier.reconcile(
          _plan([staleVariant, changedNew]),
          stack.platform,
          'bn@copy-1',
          readPendingPlatformIds: () async => stack.platform.pendingIds,
        );

        expect(stack.platform.events, [
          'cancel:$changedId',
          'cancel:$variantId',
          'schedule:b-variant:$variantId',
          'schedule:a-changed:$changedId',
        ]);
        expect(result.cancelledJobIds, ['a-changed', 'b-variant']);
        expect(result.scheduledEntries, [staleVariant, changedNew]);
        expect(stack.store.snapshot.platformIdFor('a-changed'), changedId);
        expect(stack.store.snapshot.platformIdFor('b-variant'), variantId);
        expect(
          stack.store.snapshot.appliedFor('a-changed')?.dueAtUtc,
          _utc(22),
        );
        expect(
          stack.store.snapshot.appliedFor('a-changed')?.contentKey,
          'new-content',
        );
        expect(
          stack.store.snapshot.appliedFor('b-variant')?.payloadVariant,
          'bn@copy-1',
        );
        stack.dispose();
      },
    );
  });

  group('removals and reservations', () {
    test('applied-but-removed work is cancelled and recorded', () async {
      final stack = _Stack();
      final id = await _seedApplied(stack, _entry('removed-job'));
      stack.platform.pendingIds.add(id);
      final writesBefore = stack.writes;

      final result = await stack.applier.reconcile(
        _plan(const []),
        stack.platform,
        'bn@copy-1',
        readPendingPlatformIds: () async => stack.platform.pendingIds,
      );

      expect(stack.platform.events, ['cancel:$id']);
      expect(result.cancelledJobIds, ['removed-job']);
      expect(result.scheduledEntries, isEmpty);
      expect(stack.store.snapshot.appliedFor('removed-job'), isNull);
      expect(stack.store.snapshot.platformIdFor('removed-job'), id);
      expect(stack.writes, writesBefore + 1);
      stack.dispose();
    });

    test(
      'pending reservation-only orphan is cancelled before desired retry',
      () async {
        final stack = _Stack();
        final reservation = await stack.store.reserve('orphan-job');
        stack.platform.pendingIds.add(reservation.platformId);
        final desiredEntry = _entry('orphan-job');
        final writesBefore = stack.writes;

        final result = await stack.applier.reconcile(
          _plan([desiredEntry]),
          stack.platform,
          'bn@copy-1',
          readPendingPlatformIds: () async => stack.platform.pendingIds,
        );

        expect(stack.platform.events, [
          'cancel:${reservation.platformId}',
          'schedule:orphan-job:${reservation.platformId}',
        ]);
        expect(result.cancelledJobIds, ['orphan-job']);
        expect(result.scheduledEntries, [desiredEntry]);
        expect(
          stack.store.snapshot.platformIdFor('orphan-job'),
          reservation.platformId,
        );
        expect(
          stack.store.snapshot.appliedFor('orphan-job')?.payloadVariant,
          'bn@copy-1',
        );
        expect(
          stack.writes,
          writesBefore + 1,
          reason: 'orphan cancellation record is a no-op',
        );
        stack.dispose();
      },
    );

    test(
      'undesired pending reservation-only orphan is cancelled, not applied',
      () async {
        final stack = _Stack();
        final reservation = await stack.store.reserve('orphan-job');
        stack.platform.pendingIds.add(reservation.platformId);
        final writesBefore = stack.writes;

        final result = await stack.applier.reconcile(
          _plan(const []),
          stack.platform,
          'bn@copy-1',
          readPendingPlatformIds: () async => stack.platform.pendingIds,
        );

        expect(stack.platform.events, ['cancel:${reservation.platformId}']);
        expect(result.cancelledJobIds, ['orphan-job']);
        expect(result.scheduledEntries, isEmpty);
        expect(stack.store.snapshot.appliedFor('orphan-job'), isNull);
        expect(
          stack.store.snapshot.platformIdFor('orphan-job'),
          reservation.platformId,
        );
        expect(
          stack.writes,
          writesBefore,
          reason: 'no applied metadata is fabricated',
        );
        stack.dispose();
      },
    );

    test(
      'bare reservation absent from OS and desired plan is untouched',
      () async {
        final stack = _Stack();
        await stack.store.reserve('bare-job');
        final writesBefore = stack.writes;

        final result = await stack.applier.reconcile(
          _plan(const []),
          stack.platform,
          'bn@copy-1',
          readPendingPlatformIds: () async => stack.platform.pendingIds,
        );

        expect(result.isNoOp, isTrue);
        expect(stack.platform.events, isEmpty);
        expect(stack.writes, writesBefore);
        expect(stack.store.snapshot.appliedFor('bare-job'), isNull);
        stack.dispose();
      },
    );

    test('unregistered OS IDs are left alone', () async {
      final stack = _Stack();
      stack.platform.pendingIds.add(777);

      final result = await stack.applier.reconcile(
        _plan(const []),
        stack.platform,
        'bn@copy-1',
        readPendingPlatformIds: () async => stack.platform.pendingIds,
      );

      expect(result.isNoOp, isTrue);
      expect(stack.platform.events, isEmpty);
      expect(stack.platform.pendingIds, {777});
      expect(stack.writes, 0);
      stack.dispose();
    });

    test(
      'new allocation will not overwrite an unregistered pending ID',
      () async {
        final stack = _Stack();
        stack.platform.pendingIds.add(1);

        final result = await stack.applier.reconcile(
          _plan([_entry('new-job')]),
          stack.platform,
          'bn@copy-1',
          readPendingPlatformIds: () async => stack.platform.pendingIds,
        );

        expect(stack.platform.events, isEmpty);
        expect(stack.platform.pendingIds, {1});
        expect(result.scheduledEntries, isEmpty);
        expect(result.failures, hasLength(1));
        expect(result.failures.single.jobId, 'new-job');
        expect(result.failures.single.duringCancellation, isFalse);
        expect(stack.store.snapshot.platformIdFor('new-job'), isNull);
        expect(stack.writes, 0);
        stack.dispose();
      },
    );
  });

  group('preflight failures and recovery', () {
    test(
      'blank variant and duplicate desired jobs fail before query or writes',
      () async {
        final stack = _Stack();
        final duplicate = _entry('same-job');
        var queryCalls = 0;
        Future<Set<int>> readPending() async {
          queryCalls++;
          return stack.platform.pendingIds;
        }

        await expectLater(
          stack.applier.reconcile(
            _plan([duplicate]),
            stack.platform,
            '  ',
            readPendingPlatformIds: readPending,
          ),
          throwsArgumentError,
        );
        await expectLater(
          stack.applier.reconcile(
            _plan([duplicate, duplicate]),
            stack.platform,
            'bn@copy-1',
            readPendingPlatformIds: readPending,
          ),
          throwsArgumentError,
        );

        expect(queryCalls, 0);
        expect(stack.prefs.readCounts[ReminderStateStore.storageKey] ?? 0, 0);
        expect(stack.platform.events, isEmpty);
        expect(stack.writes, 0);
        stack.dispose();
      },
    );

    test(
      'failed pending query has no effects or writes, then queue recovers',
      () async {
        final stack = _Stack();
        final desiredEntry = _entry('retry-job');
        final queryError = StateError('pending query failed');
        var failQuery = true;
        var queryCalls = 0;
        Future<Set<int>> readPending() async {
          queryCalls++;
          if (failQuery) throw queryError;
          return stack.platform.pendingIds;
        }

        await expectLater(
          stack.applier.reconcile(
            _plan([desiredEntry]),
            stack.platform,
            'bn@copy-1',
            readPendingPlatformIds: readPending,
          ),
          throwsA(same(queryError)),
        );
        expect(queryCalls, 1);
        expect(stack.platform.events, isEmpty);
        expect(stack.writes, 0);

        failQuery = false;
        final recovered = await stack.applier.reconcile(
          _plan([desiredEntry]),
          stack.platform,
          'bn@copy-1',
          readPendingPlatformIds: readPending,
        );
        expect(recovered.failures, isEmpty);
        expect(recovered.scheduledEntries, [desiredEntry]);
        expect(stack.platform.events, ['schedule:retry-job:1']);
        expect(stack.store.snapshot.platformIdFor('retry-job'), 1);
        expect(queryCalls, 2);
        stack.dispose();
      },
    );

    test(
      'unreadable ledger fails before querying or touching the platform',
      () async {
        final prefs = FakePreferencesStore()
          ..readErrors[ReminderStateStore.storageKey] = StateError(
            'read failed',
          );
        final stack = _Stack(prefs: prefs);
        var queryCalls = 0;

        await expectLater(
          stack.applier.reconcile(
            _plan([_entry('a-job')]),
            stack.platform,
            'bn@copy-1',
            readPendingPlatformIds: () async {
              queryCalls++;
              return stack.platform.pendingIds;
            },
          ),
          throwsA(
            isA<ReminderStateException>().having(
              (error) => error.failure,
              'failure',
              ReminderStateFailure.unreadable,
            ),
          ),
        );

        expect(queryCalls, 0);
        expect(stack.platform.events, isEmpty);
        expect(stack.writes, 0);
        stack.dispose();
      },
    );
  });

  group('failure ordering and retries', () {
    test('platform cancellation failure blocks only its replacement', () async {
      final stack = _Stack();
      final oldEntry = _entry('a-change');
      final id = await _seedApplied(stack, oldEntry);
      stack.platform.pendingIds.add(id);
      stack.platform.failingCancelIds.add(id);
      final changed = _entry('a-change', dueAtUtc: _utc(22), contentKey: 'new');
      final independent = _entry('b-new', dueAtUtc: _utc(20));

      final result = await stack.applier.reconcile(
        _plan([changed, independent]),
        stack.platform,
        'bn@copy-1',
        readPendingPlatformIds: () async => stack.platform.pendingIds,
      );

      expect(stack.platform.events, ['cancel:$id', 'schedule:b-new:2']);
      expect(result.failures, hasLength(1));
      expect(result.failures.single.jobId, 'a-change');
      expect(result.failures.single.error, same(stack.platform.cancelError));
      expect(result.failures.single.duringCancellation, isTrue);
      expect(result.scheduledEntries, [independent]);
      expect(
        stack.store.snapshot.appliedFor('a-change')?.dueAtUtc,
        oldEntry.dueAtUtc,
      );
      expect(stack.store.snapshot.platformIdFor('b-new'), 2);
      stack.dispose();
    });

    test(
      'cancellation record failure blocks unsafe replacement schedule',
      () async {
        final stack = _Stack();
        final oldEntry = _entry('a-job');
        final id = await _seedApplied(stack, oldEntry);
        stack.platform.pendingIds.add(id);
        stack.platform.onCancel = (_) {
          stack.prefs.writeError = StateError('ledger write failed');
        };
        final changed = _entry('a-job', dueAtUtc: _utc(23), contentKey: 'new');

        final result = await stack.applier.reconcile(
          _plan([changed]),
          stack.platform,
          'bn@copy-1',
          readPendingPlatformIds: () async => stack.platform.pendingIds,
        );

        expect(stack.platform.events, ['cancel:$id']);
        expect(stack.platform.scheduleCalls, 0);
        expect(result.scheduledEntries, isEmpty);
        expect(result.failures, hasLength(1));
        expect(result.failures.single.jobId, 'a-job');
        expect(result.failures.single.duringCancellation, isTrue);
        expect(
          result.failures.single.stateFailure,
          ReminderStateFailure.storage,
        );
        expect(
          stack.store.snapshot.appliedFor('a-job')?.dueAtUtc,
          oldEntry.dueAtUtc,
        );
        stack.dispose();
      },
    );

    test(
      'schedule-record failure is repaired by a later reconciliation',
      () async {
        final stack = _Stack();
        final desiredEntry = _entry('record-retry');
        stack.platform.onSchedule = (_, _) {
          stack.prefs.writeError = StateError('ledger write failed');
        };

        final first = await stack.applier.reconcile(
          _plan([desiredEntry]),
          stack.platform,
          'bn@copy-1',
          readPendingPlatformIds: () async => stack.platform.pendingIds,
        );

        expect(stack.platform.events, ['schedule:record-retry:1']);
        expect(first.scheduledEntries, isEmpty);
        expect(
          first.failures.single.stateFailure,
          ReminderStateFailure.storage,
        );
        expect(stack.store.snapshot.platformIdFor('record-retry'), 1);
        expect(stack.store.snapshot.appliedFor('record-retry'), isNull);
        expect(stack.platform.pendingIds, {1});

        stack.prefs.writeError = null;
        stack.platform.onSchedule = null;
        final recovered = await stack.applier.reconcile(
          _plan([desiredEntry]),
          stack.platform,
          'bn@copy-1',
          readPendingPlatformIds: () async => stack.platform.pendingIds,
        );

        expect(stack.platform.events, [
          'schedule:record-retry:1',
          'cancel:1',
          'schedule:record-retry:1',
        ]);
        expect(recovered.cancelledJobIds, ['record-retry']);
        expect(recovered.scheduledEntries, [desiredEntry]);
        expect(recovered.failures, isEmpty);
        expect(stack.store.snapshot.platformIdFor('record-retry'), 1);
        expect(
          stack.store.snapshot.appliedFor('record-retry')?.payloadVariant,
          'bn@copy-1',
        );
        stack.dispose();
      },
    );
  });

  test('all cancellations precede schedules in deterministic order', () async {
    final stack = _Stack();
    final removed = _entry('z-removed');
    final oldChanged = _entry('b-changed', dueAtUtc: _utc(19));
    final removedId = await _seedApplied(stack, removed);
    final changedId = await _seedApplied(stack, oldChanged);
    stack.platform.pendingIds.addAll([removedId, changedId]);
    final changed = _entry('b-changed', dueAtUtc: _utc(25), contentKey: 'new');
    final newEntry = _entry('a-new', dueAtUtc: _utc(18));

    final result = await stack.applier.reconcile(
      _plan([changed, newEntry]),
      stack.platform,
      'bn@copy-1',
      readPendingPlatformIds: () async => stack.platform.pendingIds,
    );

    expect(stack.platform.events, [
      'cancel:$changedId',
      'cancel:$removedId',
      'schedule:a-new:3',
      'schedule:b-changed:$changedId',
    ]);
    expect(result.cancelledJobIds, ['b-changed', 'z-removed']);
    expect(result.scheduledEntries, [newEntry, changed]);
    stack.dispose();
  });

  test(
    'reconcile query waits behind an earlier apply and sees settled OS IDs',
    () async {
      final stack = _Stack();
      final gate = Completer<void>();
      stack.platform.scheduleGate = gate.future;
      final desired = _plan([_entry('a-job')]);

      final applying = stack.applier.apply(
        desired,
        stack.platform,
        'bn@copy-1',
      );
      await pumpEventQueue();
      expect(stack.platform.events, ['schedule:a-job:1']);

      var queryCalls = 0;
      Set<int>? pendingSeenByQuery;
      final reconciling = stack.applier.reconcile(
        desired,
        stack.platform,
        'bn@copy-1',
        readPendingPlatformIds: () async {
          queryCalls++;
          pendingSeenByQuery = Set<int>.of(stack.platform.pendingIds);
          return stack.platform.pendingIds;
        },
      );
      await pumpEventQueue();

      expect(
        queryCalls,
        0,
        reason: 'query must not run before the queued apply settles',
      );
      expect(stack.platform.scheduleCalls, 1);
      gate.complete();
      final applyResult = await applying;
      final reconcileResult = await reconciling;

      expect(applyResult.scheduledEntries.map((entry) => entry.jobId), [
        'a-job',
      ]);
      expect(queryCalls, 1);
      expect(pendingSeenByQuery, {
        1,
      }, reason: 'query observes the completed schedule');
      expect(reconcileResult.isNoOp, isTrue);
      expect(stack.platform.events, ['schedule:a-job:1']);
      stack.dispose();
    },
  );
}
