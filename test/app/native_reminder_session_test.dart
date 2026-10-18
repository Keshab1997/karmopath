import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/app/runtime/native_reminder_session.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/contracts/job_repository.dart';
import 'package:karmopath/data/reminders/reminder_apply.dart';
import 'package:karmopath/data/reminders/reminder_plan.dart';
import 'package:karmopath/features/common/app_language.dart';

import '../data/fakes.dart' show jobJson;
import '../features/support/fakes.dart';

const success = ReminderApplyResult(
  cancelledJobIds: [],
  scheduledEntries: [],
  failures: [],
);
Job job({String id = 'a-job', String status = 'open'}) => Job.fromJson(
  jobJson(id: id, status: status, applicationEndDate: '2030-01-05'),
);

void main() {
  late FakeJobRepository repo;
  late FakePreferences prefs;
  late DateTime now;
  late List<(ReminderPlan, AppLang)> calls;
  late NativeReminderSession session;
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  setUp(() {
    repo = FakeJobRepository(readyState([job(), job(id: 'b-job')]));
    prefs = FakePreferences(reminders: {'a-job'});
    now = DateTime.utc(2030, 1, 1);
    calls = [];
    session = NativeReminderSession(
      repository: repo,
      preferences: prefs,
      initialLanguage: AppLang.bn,
      now: () => now,
      reconcile: (plan, language) async {
        calls.add((plan, language));
        return success;
      },
    );
  });
  tearDown(() async => session.close());

  test(
    'startup waits for a validated feed rather than cancelling from no feed',
    () async {
      repo.state.value = const JobFeedState(
        isOffline: true,
        lastError: 'No cache',
      );
      await session.start();
      await session.resumed();
      expect(calls, isEmpty);
      expect(prefs.reminderJobIds.value, {'a-job'});
      repo.state.value = readyState([job()]);
      await tick();
      expect(calls.single.$1.entries.single.jobId, 'a-job');
    },
  );
  test('startup is idempotent and preserves stored intent', () async {
    await session.start();
    await session.start();
    expect(calls, hasLength(1));
    expect(calls.single.$2, AppLang.bn);
    expect(calls.single.$1.entries.single.jobId, 'a-job');
    expect(prefs.reminderCalls, isEmpty);
  });
  test(
    'stored-intent changes and feed withdrawal generate fresh plans',
    () async {
      await session.start();
      await prefs.setReminder('b-job', true);
      await tick();
      expect(calls.last.$1.entries.map((e) => e.jobId), ['a-job', 'b-job']);
      repo.state.value = readyState([
        job(status: 'withdrawn'),
        job(id: 'b-job'),
      ]);
      await tick();
      expect(calls.last.$1.entries.map((e) => e.jobId), ['b-job']);
      expect(prefs.reminderJobIds.value, {'a-job', 'b-job'});
    },
  );
  test(
    'language change triggers with explicit language, duplicates do not',
    () async {
      await session.start();
      session.languageChanged(AppLang.en);
      await tick();
      expect(calls.map((c) => c.$2), [AppLang.bn, AppLang.en]);
      session.languageChanged(AppLang.en);
      await tick();
      expect(calls, hasLength(2));
    },
  );
  test(
    'resume recomputes the clock cutoff without catch-up or intent mutation',
    () async {
      await session.start();
      now = calls.single.$1.entries.single.dueAtUtc;
      await session.resumed();
      expect(calls.last.$1.entries, isEmpty);
      expect(
        calls.last.$1.skipped.single.reason,
        ReminderSkipReason.optedInTooLate,
      );
      expect(prefs.reminderCalls, isEmpty);
      expect(prefs.reminderJobIds.value, {'a-job'});
    },
  );
  test(
    'a validated empty feed really does produce an empty desired plan',
    () async {
      await session.start();
      repo.state.value = readyState([]);
      await tick();
      expect(calls.last.$1.entries, isEmpty);
      expect(
        calls.last.$1.skipped.single.reason,
        ReminderSkipReason.jobUnavailable,
      );
    },
  );
  test(
    'callback failure stays explicit and does not poison retry queue',
    () async {
      await session.close();
      var fail = true;
      final error = StateError('pending query failed');
      session = NativeReminderSession(
        repository: repo,
        preferences: prefs,
        initialLanguage: AppLang.bn,
        now: () => now,
        reconcile: (_, _) async {
          if (fail) throw error;
          return success;
        },
      );
      await expectLater(session.start(), throwsA(same(error)));
      expect(session.state.value.error, same(error));
      expect(session.state.value.hasFailure, isTrue);
      fail = false;
      await session.resumed();
      expect(session.state.value.error, isNull);
      expect(session.state.value.hasFailure, isFalse);
    },
  );
  test(
    'per-job failure is retained, not turned into whole-plan success',
    () async {
      await session.close();
      final failure = ReminderApplyFailure(
        jobId: 'a-job',
        error: StateError('denied'),
        stackTrace: StackTrace.current,
        duringCancellation: false,
      );
      session = NativeReminderSession(
        repository: repo,
        preferences: prefs,
        initialLanguage: AppLang.bn,
        now: () => now,
        reconcile: (_, _) async => ReminderApplyResult(
          cancelledJobIds: [],
          scheduledEntries: [],
          failures: [failure],
        ),
      );
      await session.start();
      expect(session.state.value.hasFailure, isTrue);
      expect(session.state.value.result!.failures, [failure]);
    },
  );
  test(
    'all triggers serialize and read fresh language at execution time',
    () async {
      await session.close();
      final gate = Completer<void>();
      var active = 0;
      var maximum = 0;
      session = NativeReminderSession(
        repository: repo,
        preferences: prefs,
        initialLanguage: AppLang.bn,
        now: () => now,
        reconcile: (plan, language) async {
          active++;
          if (active > maximum) maximum = active;
          calls.add((plan, language));
          if (calls.length == 1) await gate.future;
          active--;
          return success;
        },
      );
      final starting = session.start();
      await tick();
      session.languageChanged(AppLang.en);
      final resumed = session.resumed();
      expect(calls, hasLength(1));
      gate.complete();
      await Future.wait([starting, resumed]);
      expect(maximum, 1);
      expect(calls.map((c) => c.$2), [AppLang.bn, AppLang.en, AppLang.en]);
    },
  );
  test(
    'close detaches immediately, drains active call and skips queued work',
    () async {
      await session.close();
      final gate = Completer<void>();
      session = NativeReminderSession(
        repository: repo,
        preferences: prefs,
        initialLanguage: AppLang.bn,
        now: () => now,
        reconcile: (plan, language) async {
          calls.add((plan, language));
          await gate.future;
          return success;
        },
      );
      final starting = session.start();
      await tick();
      final queued = session.resumed();
      final closing = session.close();
      var closed = false;
      closing.then((_) => closed = true);
      repo.state.value = readyState([]);
      session.languageChanged(AppLang.en);
      await tick();
      expect(closed, isFalse);
      gate.complete();
      await Future.wait([starting, queued, closing]);
      expect(closed, isTrue);
      expect(calls, hasLength(1));
      await session.resumed();
      await expectLater(session.start(), throwsStateError);
    },
  );
}
