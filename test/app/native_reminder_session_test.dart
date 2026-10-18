import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/app/runtime/native_reminder_session.dart';
import 'package:karmopath/contracts/job_repository.dart';
import 'package:karmopath/contracts/native_reminders.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/common/reminder_sync_status.dart';

import '../features/support/fakes.dart';

class RecordingSynchronizer implements ReminderSynchronizer {
  final calls = <ReminderSyncInput>[];
  Future<ReminderSyncReport> Function(ReminderSyncInput input)? onSync;
  int closes = 0;

  @override
  Future<ReminderSyncReport> synchronize(ReminderSyncInput input) async {
    calls.add(input);
    return onSync?.call(input) ?? report(feedAvailable: input.jobs != null);
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

ReminderSyncReport report({
  required bool feedAvailable,
  List<ReminderSyncProblem> problems = const [],
}) => ReminderSyncReport(
  permission: ReminderPermission.granted,
  feedAvailable: feedAvailable,
  scheduledJobIds: const [],
  cancelledJobIds: const [],
  cancelledOrphanIds: const [],
  problems: problems,
);

void main() {
  late FakeJobRepository repository;
  late FakePreferences preferences;
  late RecordingSynchronizer synchronizer;
  late NativeReminderSession session;
  Future<void> tick() => Future<void>.delayed(Duration.zero);

  NativeReminderSession createSession() => NativeReminderSession(
    repository: repository,
    preferences: preferences,
    synchronizer: synchronizer,
    initialLanguage: AppLang.bn,
  );

  setUp(() {
    repository = FakeJobRepository(readyState([makeJob(id: 'a-job')]));
    preferences = FakePreferences(reminders: {'a-job'});
    synchronizer = RecordingSynchronizer();
    session = createSession();
  });
  tearDown(() async => session.close());

  test(
    'start is idempotent and synchronizes the validated feed and intent',
    () async {
      await session.start();
      await session.start();
      expect(synchronizer.calls, hasLength(1));
      expect(synchronizer.calls.single.jobs!.map((job) => job.id), ['a-job']);
      expect(synchronizer.calls.single.selectedJobIds, {'a-job'});
      expect(synchronizer.calls.single.languageCode, 'bn');
      expect(session.status.value.phase, ReminderSyncUiPhase.idle);
    },
  );

  test('unloaded feed is not treated as a successful empty feed', () async {
    repository.state.value = const JobFeedState();
    await session.start();
    expect(synchronizer.calls, isEmpty);
    expect(session.status.value.phase, ReminderSyncUiPhase.idle);
  });

  test(
    'offline cached feed is passed as unavailable, never as an empty snapshot',
    () async {
      repository.state.value = JobFeedState(
        feed: makeFeed([makeJob(id: 'a-job')]),
        isOffline: true,
        lastError: 'offline',
      );
      await session.start();
      expect(synchronizer.calls, hasLength(1));
      expect(synchronizer.calls.single.jobs, isNull);
      expect(session.status.value.phase, ReminderSyncUiPhase.failed);
      expect(session.status.value.report!.feedAvailable, isFalse);
    },
  );

  test(
    'preference and verified-feed changes reconcile with fresh values',
    () async {
      await session.start();
      await preferences.setReminder('b-job', true);
      await session.resumed();
      expect(synchronizer.calls.last.selectedJobIds, {'a-job', 'b-job'});

      repository.state.value = readyState([makeJob(id: 'b-job')]);
      await session.resumed();
      expect(synchronizer.calls.last.jobs!.map((job) => job.id), ['b-job']);
      expect(preferences.reminderJobIds.value, {'a-job', 'b-job'});
    },
  );

  test('a validated empty feed is distinct from an unavailable feed', () async {
    repository.state.value = readyState([]);
    await session.start();
    expect(synchronizer.calls.single.jobs, isEmpty);
    expect(session.status.value.phase, ReminderSyncUiPhase.idle);
  });

  test('language change triggers sync with explicit language; duplicate is a no-op', () async {
    await session.start();
    session.languageChanged(AppLang.en);
    await session.resumed();
    expect(synchronizer.calls.last.languageCode, 'en');
    final count = synchronizer.calls.length;
    session.languageChanged(AppLang.en);
    await tick();
    expect(synchronizer.calls, hasLength(count));
  });

  test('resume rechecks without changing user intent', () async {
    await session.start();
    await session.resumed();
    expect(synchronizer.calls, hasLength(2));
    expect(preferences.reminderCalls, isEmpty);
    expect(preferences.reminderJobIds.value, {'a-job'});
  });

  test(
    'sync failures show generic failed state and explicit retry clears it',
    () async {
      var fail = true;
      synchronizer.onSync = (input) async => report(
        feedAvailable: input.jobs != null,
        problems: fail
            ? [
                ReminderSyncProblem(
                  stage: ReminderSyncStage.pending,
                  error: StateError('private backend detail'),
                ),
              ]
            : const [],
      );
      await session.start();
      expect(session.status.value.phase, ReminderSyncUiPhase.failed);
      expect(session.status.value.error, isNull);
      expect(
        session.status.value.report!.problems.single.error,
        isA<StateError>(),
      );

      fail = false;
      await session.retry();
      expect(session.status.value.phase, ReminderSyncUiPhase.idle);
      expect(synchronizer.calls, hasLength(2));
    },
  );

  test('retry refreshes an unavailable feed before reconciling', () async {
    repository.state.value = const JobFeedState(
      isOffline: true,
      lastError: 'offline',
    );
    await session.start();
    repository.nextState = readyState([makeJob(id: 'a-job')]);
    await session.retry();
    expect(repository.refreshCalls, 1);
    expect(synchronizer.calls.last.jobs!.map((job) => job.id), ['a-job']);
    expect(session.status.value.phase, ReminderSyncUiPhase.idle);
  });

  test(
    'all triggers serialize and close drains active synchronization',
    () async {
      final gate = Completer<ReminderSyncReport>();
      var active = 0;
      var maximum = 0;
      synchronizer.onSync = (input) async {
        active++;
        if (active > maximum) maximum = active;
        if (synchronizer.calls.length == 1) await gate.future;
        active--;
        return report(feedAvailable: input.jobs != null);
      };

      final starting = session.start();
      await tick();
      session.languageChanged(AppLang.en);
      final queued = session.resumed();
      final closing = session.close();
      var closed = false;
      closing.then((_) => closed = true);
      repository.state.value = readyState([]);
      await tick();
      expect(closed, isFalse);
      gate.complete(report(feedAvailable: true));
      await Future.wait([starting, queued, closing]);
      expect(maximum, 1);
      expect(synchronizer.calls, hasLength(1));
      expect(closed, isTrue);
      expect(synchronizer.closes, 1);
      await session.resumed();
    },
  );
}
