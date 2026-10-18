import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/data/reminders/reminder_apply.dart';
import 'package:karmopath/data/reminders/reminder_diff.dart';
import 'package:karmopath/data/reminders/reminder_plan.dart';
import 'package:karmopath/data/reminders/reminder_state.dart';
import 'package:karmopath/data/reminders/reminder_state_store.dart';

import '../fakes.dart';

/// Recording [ReminderPlatform] fake.
///
/// Every attempt is appended to [events] *before* failure injection, so a
/// test can distinguish "attempted and failed" from "never attempted".
/// [onSchedule]/[onCancel] hooks run mid-apply (used to flip the
/// preferences store into a failing state exactly before the ledger record
/// write), and [scheduleGate] can hold a schedule open to prove that
/// concurrent applies serialise.
class FakeReminderPlatform implements ReminderPlatform {
  final List<String> events = <String>[];
  final Set<int> failingCancelIds = <int>{};
  final Set<String> failingScheduleJobs = <String>{};
  Object cancelError = StateError('platform cancel failed');
  Object scheduleError = StateError('platform schedule failed');
  Future<void>? scheduleGate;
  void Function(int id)? onCancel;
  void Function(ReminderPlanEntry entry)? onSchedule;
  int cancelCalls = 0;
  int scheduleCalls = 0;

  @override
  Future<void> cancel(int id) async {
    cancelCalls++;
    events.add('cancel:$id');
    onCancel?.call(id);
    if (failingCancelIds.contains(id)) throw cancelError;
  }

  @override
  Future<void> schedule(ReminderPlanEntry entry, int platformId) async {
    scheduleCalls++;
    events.add('schedule:${entry.jobId}:$platformId');
    onSchedule?.call(entry);
    final gate = scheduleGate;
    if (gate != null) await gate;
    if (failingScheduleJobs.contains(entry.jobId)) throw scheduleError;
  }
}

DateTime utc(int y, int m, int d, [int h = 0]) => DateTime.utc(y, m, d, h);

ReminderPlanEntry entry(
  String jobId, {
  DateTime? due,
  String contentKey = 'key-v1',
}) {
  final dueAt = due ?? utc(2026, 11, 19, 12);
  return ReminderPlanEntry(
    jobId: jobId,
    dueAtUtc: dueAt,
    closesAtUtc: dueAt.add(const Duration(days: 1)),
    contentKey: contentKey,
  );
}

ReminderPlan plan(List<ReminderPlanEntry> entries) => ReminderPlan(
  generatedAtUtc: utc(2026, 1, 1),
  entries: entries,
  skipped: const <ReminderSkip>[],
);

/// One wired-up stack: shared fake preferences -> ledger -> applier.
class Stack {
  Stack({FakePreferencesStore? prefs})
    : prefs = prefs ?? FakePreferencesStore() {
    store = ReminderStateStore(store: this.prefs);
    applier = ReminderApplier(store);
  }

  final FakePreferencesStore prefs;
  late final ReminderStateStore store;
  late final ReminderApplier applier;
  final FakeReminderPlatform platform = FakeReminderPlatform();

  int get writeAttempts => prefs.writeCounts.values.fold(0, (a, b) => a + b);
}

void main() {
  group('no-op and idempotence', () {
    test(
      'applying an empty plan touches neither platform nor storage',
      () async {
        final s = Stack();
        final result = await s.applier.apply(
          plan(const []),
          s.platform,
          'bn@copy-1',
        );

        expect(result.isNoOp, isTrue);
        expect(result.isFullySuccessful, isTrue);
        expect(s.platform.events, isEmpty);
        expect(s.writeAttempts, 0, reason: 'an empty diff must not write');
        expect(s.store.snapshot.isEmpty, isTrue);
        s.store.dispose();
      },
    );

    test(
      're-applying the applied plan is a no-op (no calls, no writes)',
      () async {
        final s = Stack();
        final desired = plan([entry('a-job')]);
        await s.applier.apply(desired, s.platform, 'bn@copy-1');
        s.platform.events.clear();
        final writesBefore = s.writeAttempts;

        final result = await s.applier.apply(desired, s.platform, 'bn@copy-1');

        expect(result.isNoOp, isTrue);
        expect(result.failures, isEmpty);
        expect(s.platform.events, isEmpty);
        expect(s.writeAttempts, writesBefore);
        s.store.dispose();
      },
    );
  });

  group('scheduling', () {
    test('new jobs schedule in due order with sequential stable IDs', () async {
      final s = Stack();
      // Deliberately unordered input: the diff orders by (due, jobId).
      final result = await s.applier.apply(
        plan([
          entry('b-job', due: utc(2026, 11, 21, 12)),
          entry('a-job', due: utc(2026, 11, 19, 12)),
        ]),
        s.platform,
        'bn@copy-1',
      );

      expect(result.isFullySuccessful, isTrue);
      expect(result.scheduledEntries.map((e) => e.jobId), ['a-job', 'b-job']);
      expect(s.platform.events, ['schedule:a-job:1', 'schedule:b-job:2']);
      expect(s.store.snapshot.platformIdFor('a-job'), 1);
      expect(s.store.snapshot.platformIdFor('b-job'), 2);
      expect(s.store.snapshot.appliedFor('a-job')?.payloadVariant, 'bn@copy-1');
      s.store.dispose();
    });

    test('applyDiff schedules a new job and records it', () async {
      final s = Stack();
      final diff = ReminderDiff(
        cancellations: const [],
        schedules: [
          ReminderScheduling(entry: entry('a-job'), isReplacement: false),
        ],
        retained: const [],
      );

      final result = await s.applier.applyDiff(diff, s.platform, 'bn@copy-1');

      expect(result.scheduledEntries.map((e) => e.jobId), ['a-job']);
      expect(s.platform.events, ['schedule:a-job:1']);
      expect(s.store.snapshot.appliedFor('a-job'), isNotNull);
      s.store.dispose();
    });
  });

  group('cancellation and replacement', () {
    test(
      'removal cancels, clears applied, but retains the reservation',
      () async {
        final s = Stack();
        await s.applier.apply(
          plan([entry('a-job'), entry('b-job', due: utc(2026, 11, 21, 12))]),
          s.platform,
          'bn@copy-1',
        );
        s.platform.events.clear();

        final result = await s.applier.apply(
          plan([entry('a-job')]),
          s.platform,
          'bn@copy-1',
        );

        expect(result.cancelledJobIds, ['b-job']);
        expect(s.platform.events, ['cancel:2']);
        expect(s.store.snapshot.appliedFor('b-job'), isNull);
        expect(
          s.store.snapshot.platformIdFor('b-job'),
          2,
          reason: 'IDs are never returned to the pool',
        );
        expect(s.store.snapshot.appliedFor('a-job'), isNotNull);
        s.store.dispose();
      },
    );

    test('re-adding a removed job reuses its retained platform ID', () async {
      final s = Stack();
      final both = plan([
        entry('a-job'),
        entry('b-job', due: utc(2026, 11, 21, 12)),
      ]);
      await s.applier.apply(both, s.platform, 'bn@copy-1');
      await s.applier.apply(plan([entry('a-job')]), s.platform, 'bn@copy-1');
      s.platform.events.clear();

      await s.applier.apply(both, s.platform, 'bn@copy-1');

      expect(s.platform.events, ['schedule:b-job:2']);
      s.store.dispose();
    });

    test(
      'cancel runs before schedule for the same jobId on replacement',
      () async {
        final s = Stack();
        await s.applier.apply(
          plan([entry('job-x', due: utc(2026, 11, 19, 12))]),
          s.platform,
          'bn@copy-1',
        );
        s.platform.events.clear();

        final moved = entry(
          'job-x',
          due: utc(2026, 11, 25, 12),
          contentKey: 'key-v2',
        );
        final result = await s.applier.apply(
          plan([moved]),
          s.platform,
          'bn@copy-1',
        );

        expect(s.platform.events, [
          'cancel:1',
          'schedule:job-x:1',
        ], reason: 'same stable ID, cancel strictly first');
        expect(result.cancelledJobIds, ['job-x']);
        expect(result.scheduledEntries, [moved]);
        final applied = s.store.snapshot.appliedFor('job-x')!;
        expect(applied.dueAtUtc, moved.dueAtUtc);
        expect(applied.contentKey, 'key-v2');
        s.store.dispose();
      },
    );

    test('multiple removals cancel in jobId order', () async {
      final s = Stack();
      // Due order gives c-job ID 1, a-job ID 2, b-job ID 3; cancellation
      // order must follow jobId, not ID.
      await s.applier.apply(
        plan([
          entry('c-job', due: utc(2026, 11, 18, 12)),
          entry('a-job', due: utc(2026, 11, 19, 12)),
          entry('b-job', due: utc(2026, 11, 20, 12)),
        ]),
        s.platform,
        'bn@copy-1',
      );
      s.platform.events.clear();

      final result = await s.applier.apply(
        plan(const []),
        s.platform,
        'bn@copy-1',
      );

      expect(result.cancelledJobIds, ['a-job', 'b-job', 'c-job']);
      expect(s.platform.events, ['cancel:2', 'cancel:3', 'cancel:1']);
      expect(s.store.snapshot.entries.every((e) => e.applied == null), isTrue);
      s.store.dispose();
    });

    test('unknown jobId in a diff is ignored, not an error', () async {
      final s = Stack();
      final diff = ReminderDiff(
        cancellations: [
          ReminderCancellation(
            jobId: 'ghost-job',
            previous: entry('ghost-job'),
          ),
        ],
        schedules: const [],
        retained: const [],
      );

      final result = await s.applier.applyDiff(diff, s.platform, 'bn@copy-1');

      expect(result.isFullySuccessful, isTrue);
      expect(result.cancelledJobIds, isEmpty);
      expect(s.platform.events, isEmpty, reason: 'no ID is known to cancel');
      expect(s.writeAttempts, 0);
      s.store.dispose();
    });
  });

  group('payload variant', () {
    test('payloadVariant round-trips through the persisted document', () async {
      final s = Stack();
      await s.applier.apply(
        plan([entry('a-job')]),
        s.platform,
        'bn-IN@copy-2026.10',
      );

      expect(
        s.store.snapshot.appliedFor('a-job')?.payloadVariant,
        'bn-IN@copy-2026.10',
      );
      final document = jsonDecode(
        s.prefs.data[ReminderStateStore.storageKey]!.single,
      ) as Map<String, dynamic>;
      final applied =
          (document['entries'] as List).single['applied']
              as Map<String, dynamic>;
      expect(applied['payload_variant'], 'bn-IN@copy-2026.10');

      // A fresh store over the same backing (a process restart) reads it back.
      final restarted = ReminderStateStore(
        store: FakePreferencesStore(initial: s.prefs.data),
      );
      await restarted.initialize();
      expect(
        restarted.snapshot.appliedFor('a-job')?.payloadVariant,
        'bn-IN@copy-2026.10',
      );
      expect(restarted.snapshot.platformIdFor('a-job'), 1);
      restarted.dispose();
      s.store.dispose();
    });

    test('changing only the variant reschedules under the same ID', () async {
      final s = Stack();
      final desired = plan([entry('a-job')]);
      await s.applier.apply(desired, s.platform, 'bn@copy-1');
      s.platform.events.clear();

      final result = await s.applier.apply(desired, s.platform, 'en@copy-2');

      expect(s.platform.events, [
        'cancel:1',
        'schedule:a-job:1',
      ], reason: 'stale copy must not linger after a language/copy switch');
      expect(result.scheduledEntries.map((e) => e.jobId), ['a-job']);
      expect(s.store.snapshot.appliedFor('a-job')?.payloadVariant, 'en@copy-2');
      s.store.dispose();
    });

    test(
      'a blank payloadVariant is rejected before touching anything',
      () async {
        final s = Stack();
        await expectLater(
          s.applier.apply(plan([entry('a-job')]), s.platform, '  '),
          throwsArgumentError,
        );
        expect(s.platform.events, isEmpty);
        expect(s.writeAttempts, 0);
        s.store.dispose();
      },
    );
  });

  group('per-job failure surfacing', () {
    test(
      'schedule failure leaves the applied ledger unchanged for that job',
      () async {
        final s = Stack();
        s.platform.failingScheduleJobs.add('b-job');

        final result = await s.applier.apply(
          plan([entry('a-job'), entry('b-job', due: utc(2026, 11, 21, 12))]),
          s.platform,
          'bn@copy-1',
        );

        expect(result.scheduledEntries.map((e) => e.jobId), ['a-job']);
        expect(result.failures.map((f) => f.jobId), ['b-job']);
        expect(result.failures.single.duringCancellation, isFalse);
        expect(result.failures.single.error, same(s.platform.scheduleError));
        expect(s.store.snapshot.appliedFor('a-job'), isNotNull);
        expect(
          s.store.snapshot.appliedFor('b-job'),
          isNull,
          reason: 'a failed schedule is never recorded as applied',
        );
        expect(
          s.store.snapshot.platformIdFor('b-job'),
          2,
          reason: 'the reservation persists so the retry reuses the ID',
        );

        // Retry after the platform recovers: same ID, a-job untouched.
        s.platform.failingScheduleJobs.clear();
        s.platform.events.clear();
        final retry = await s.applier.apply(
          plan([entry('a-job'), entry('b-job', due: utc(2026, 11, 21, 12))]),
          s.platform,
          'bn@copy-1',
        );
        expect(retry.isFullySuccessful, isTrue);
        expect(s.platform.events, ['schedule:b-job:2']);
        expect(s.store.snapshot.appliedFor('b-job'), isNotNull);
        s.store.dispose();
      },
    );

    test('cancellation failure leaves the applied record in place', () async {
      final s = Stack();
      await s.applier.apply(plan([entry('a-job')]), s.platform, 'bn@copy-1');
      s.platform.failingCancelIds.add(1);

      final result = await s.applier.apply(
        plan(const []),
        s.platform,
        'bn@copy-1',
      );

      expect(result.cancelledJobIds, isEmpty);
      expect(result.failures.single.jobId, 'a-job');
      expect(result.failures.single.duringCancellation, isTrue);
      expect(
        s.store.snapshot.appliedFor('a-job'),
        isNotNull,
        reason: 'the OS still holds it, so the ledger must keep saying so',
      );
      s.store.dispose();
    });

    test(
      'a failed cancellation skips the replacement schedule for that job',
      () async {
        final s = Stack();
        final old = entry('job-x', due: utc(2026, 11, 19, 12));
        await s.applier.apply(plan([old]), s.platform, 'bn@copy-1');
        s.platform.failingCancelIds.add(1);
        final scheduleCallsBefore = s.platform.scheduleCalls;

        final moved = entry(
          'job-x',
          due: utc(2026, 11, 25, 12),
          contentKey: 'key-v2',
        );
        final result = await s.applier.apply(
          plan([moved]),
          s.platform,
          'bn@copy-1',
        );

        expect(result.failures.map((f) => f.jobId), ['job-x']);
        expect(s.platform.scheduleCalls, scheduleCallsBefore);
        expect(s.store.snapshot.appliedFor('job-x')?.dueAtUtc, old.dueAtUtc);

        // Once the platform recovers, the same apply retries the pair.
        s.platform.failingCancelIds.clear();
        s.platform.events.clear();
        final retry = await s.applier.apply(
          plan([moved]),
          s.platform,
          'bn@copy-1',
        );
        expect(retry.isFullySuccessful, isTrue);
        expect(s.platform.events, ['cancel:1', 'schedule:job-x:1']);
        s.store.dispose();
      },
    );

    test(
      'an invalid job id fails per-job without blocking other jobs',
      () async {
        final s = Stack();
        final result = await s.applier.apply(
          plan([
            entry('good-job', due: utc(2026, 11, 19, 12)),
            entry('Bad Job!', due: utc(2026, 11, 20, 12)),
          ]),
          s.platform,
          'bn@copy-1',
        );

        expect(result.scheduledEntries.map((e) => e.jobId), ['good-job']);
        expect(result.failures.single.jobId, 'Bad Job!');
        expect(
          result.failures.single.stateFailure,
          ReminderStateFailure.invalidJobId,
        );
        expect(s.platform.events, ['schedule:good-job:1']);
        s.store.dispose();
      },
    );

    test('an unreadable ledger throws and the platform is untouched', () async {
      final s = Stack();
      s.prefs.readErrors[ReminderStateStore.storageKey] = StateError(
        'io error',
      );

      await expectLater(
        s.applier.apply(plan([entry('a-job')]), s.platform, 'bn@copy-1'),
        throwsA(
          isA<ReminderStateException>().having(
            (e) => e.failure,
            'failure',
            ReminderStateFailure.unreadable,
          ),
        ),
      );
      expect(s.platform.events, isEmpty);
      expect(s.writeAttempts, 0);
      s.store.dispose();
    });
  });

  group('storage failure discipline', () {
    test(
      'a failing reservation write is surfaced and nothing is published',
      () async {
        final s = Stack();
        s.prefs.writeError = StateError('disk full');

        final result = await s.applier.apply(
          plan([entry('a-job')]),
          s.platform,
          'bn@copy-1',
        );

        expect(result.scheduledEntries, isEmpty);
        expect(result.failures.single.jobId, 'a-job');
        expect(
          result.failures.single.stateFailure,
          ReminderStateFailure.storage,
        );
        expect(
          s.platform.scheduleCalls,
          0,
          reason: 'reserve precedes scheduling',
        );
        expect(
          s.store.snapshot.isEmpty,
          isTrue,
          reason: 'failed writes never publish',
        );
        s.store.dispose();
      },
    );

    test('a record write failing after OS success is surfaced, not published, '
        'and reconciles on retry', () async {
      final s = Stack();
      // Fail exactly the record write: the platform hook flips the store
      // into failure after reserve succeeded, before record runs.
      s.platform.onSchedule = (_) =>
          s.prefs.writeError = StateError('disk full');

      final result = await s.applier.apply(
        plan([entry('a-job')]),
        s.platform,
        'bn@copy-1',
      );

      expect(s.platform.scheduleCalls, 1, reason: 'the OS accepted it');
      expect(result.scheduledEntries, isEmpty);
      expect(result.failures.single.stateFailure, ReminderStateFailure.storage);
      expect(
        s.store.snapshot.appliedFor('a-job'),
        isNull,
        reason: 'an unrecorded success must not look applied in state',
      );

      s.platform.onSchedule = null;
      s.prefs.writeError = null;
      final retry = await s.applier.apply(
        plan([entry('a-job')]),
        s.platform,
        'bn@copy-1',
      );
      expect(retry.isFullySuccessful, isTrue);
      expect(
        s.platform.events.last,
        'schedule:a-job:1',
        reason: 'retry reuses the same stable ID',
      );
      expect(s.store.snapshot.appliedFor('a-job'), isNotNull);
      s.store.dispose();
    });

    test(
      'a cancellation record write failing keeps the applied record published',
      () async {
        final s = Stack();
        await s.applier.apply(plan([entry('a-job')]), s.platform, 'bn@copy-1');
        s.platform.onCancel = (_) =>
            s.prefs.writeError = StateError('disk full');

        final result = await s.applier.apply(
          plan(const []),
          s.platform,
          'bn@copy-1',
        );

        expect(s.platform.cancelCalls, 1, reason: 'the OS accepted the cancel');
        expect(result.cancelledJobIds, isEmpty);
        expect(result.failures.single.duringCancellation, isTrue);
        expect(
          result.failures.single.stateFailure,
          ReminderStateFailure.storage,
        );
        expect(
          s.store.snapshot.appliedFor('a-job'),
          isNotNull,
          reason: 'the failed write must not change the published state',
        );
        s.store.dispose();
      },
    );
  });

  group('concurrency', () {
    test(
      'concurrent applies serialise: the second waits for the first',
      () async {
        final s = Stack();
        final gate = Completer<void>();
        s.platform.scheduleGate = gate.future;

        final first = s.applier.apply(
          plan([entry('a-job')]),
          s.platform,
          'bn@copy-1',
        );
        final second = s.applier.apply(
          plan([entry('a-job'), entry('b-job', due: utc(2026, 11, 21, 12))]),
          s.platform,
          'bn@copy-1',
        );
        await pumpEventQueue();

        expect(
          s.platform.scheduleCalls,
          1,
          reason: 'the second apply must not reach the platform yet',
        );
        expect(s.platform.events, ['schedule:a-job:1']);

        gate.complete();
        final r1 = await first;
        final r2 = await second;

        expect(r1.scheduledEntries.map((e) => e.jobId), ['a-job']);
        expect(r2.scheduledEntries.map((e) => e.jobId), [
          'b-job',
        ], reason: 'by the time the second apply diffs, a-job is retained');
        expect(s.platform.events, ['schedule:a-job:1', 'schedule:b-job:2']);
        expect(s.store.snapshot.platformIdFor('b-job'), 2);
        s.store.dispose();
      },
    );

    test('two identical concurrent applies schedule each job once', () async {
      final s = Stack();
      final desired = plan([entry('a-job')]);

      final results = await Future.wait([
        s.applier.apply(desired, s.platform, 'bn@copy-1'),
        s.applier.apply(desired, s.platform, 'bn@copy-1'),
      ]);

      expect(s.platform.scheduleCalls, 1);
      expect(results[0].scheduledEntries, hasLength(1));
      expect(results[1].scheduledEntries, isEmpty);
      expect(results.every((r) => r.isFullySuccessful), isTrue);
      s.store.dispose();
    });
  });

  group('exhaustion', () {
    test('an already-exhausted ledger fails per-job and never wraps', () async {
      final s = Stack(
        prefs: FakePreferencesStore(
          initial: {
            ReminderStateStore.storageKey: [
              '{"schema_version":1,"next_platform_id":2147483648,"entries":[]}',
            ],
          },
        ),
      );

      final result = await s.applier.apply(
        plan([entry('a-job')]),
        s.platform,
        'bn@copy-1',
      );

      expect(result.scheduledEntries, isEmpty);
      expect(result.failures.single.jobId, 'a-job');
      expect(
        result.failures.single.stateFailure,
        ReminderStateFailure.exhausted,
      );
      expect(s.platform.scheduleCalls, 0);
      expect(s.writeAttempts, 0, reason: 'exhaustion writes nothing');
      expect(s.store.snapshot.nextPlatformId, maxPlatformId + 1);
      expect(s.store.snapshot.platformIdFor('a-job'), isNull);
      s.store.dispose();
    });

    test('the last ID (2147483647) is handed out, the next job exhausts', () async {
      final s = Stack(
        prefs: FakePreferencesStore(
          initial: {
            ReminderStateStore.storageKey: [
              '{"schema_version":1,"next_platform_id":2147483647,"entries":[]}',
            ],
          },
        ),
      );

      final result = await s.applier.apply(
        plan([
          entry('a-job', due: utc(2026, 11, 19, 12)),
          entry('b-job', due: utc(2026, 11, 21, 12)),
        ]),
        s.platform,
        'bn@copy-1',
      );

      expect(result.scheduledEntries.map((e) => e.jobId), ['a-job']);
      expect(s.platform.events, ['schedule:a-job:2147483647']);
      expect(s.store.snapshot.platformIdFor('a-job'), maxPlatformId);
      expect(result.failures.single.jobId, 'b-job');
      expect(
        result.failures.single.stateFailure,
        ReminderStateFailure.exhausted,
      );
      expect(
        s.store.snapshot.platformIdFor('b-job'),
        isNull,
        reason: 'no wrap-around and no reuse of the last ID',
      );
      expect(s.store.snapshot.nextPlatformId, maxPlatformId + 1);
      s.store.dispose();
    });
  });
}
