import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/contracts/native_reminders.dart';
import 'package:karmopath/data/preferences_store.dart';
import 'package:karmopath/data/reminders/native_reminder_sync.dart';
import 'package:karmopath/data/reminders/reminder_plan.dart';
import 'package:karmopath/data/reminders/reminder_state_store.dart';

final DateTime _baseNow = DateTime.utc(2026, 11, 1, 12);

Job _job(
  String id, {
  DateTime? closesAt,
  String titleEn = 'Recruitment notice',
  JobStatus status = JobStatus.open,
}) {
  final closes = closesAt ?? _baseNow.add(const Duration(days: 5));
  return Job(
    id: id,
    kind: JobKind.recruitment,
    titleBn: 'নিয়োগ বিজ্ঞপ্তি',
    titleEn: titleEn,
    organization: 'Public Service Board',
    category: JobCategory.office,
    districts: const ['West Bengal'],
    qualifications: const ['Graduate'],
    status: status,
    sourceUrl: 'https://example.org/source',
    noticeUrl: 'https://example.org/notice',
    reviewedAt: DateTime.utc(2026, 1, 1),
    publishedAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    summaryBn: 'নমুনা সারসংক্ষেপ।',
    summaryEn: 'Sample summary.',
    howToApplyBn: '',
    howToApplyEn: '',
    vacancies: 10,
    applicationStartDate: '2026-01-01',
    applicationEndDate: null,
    applicationEndAt: closes,
    examDate: null,
    applyUrl: null,
    ageNoteBn: null,
    ageNoteEn: null,
  );
}

ReminderSyncInput _input({
  required Iterable<Job>? jobs,
  Iterable<String> selectedJobIds = const <String>[],
  String languageCode = 'bn',
}) => ReminderSyncInput(
  jobs: jobs,
  selectedJobIds: selectedJobIds,
  languageCode: languageCode,
);

ReminderPlanEntry _plannedEntry(Job job, {required DateTime now}) =>
    planReminders(
      jobs: [job],
      selectedJobIds: [job.id],
      now: now,
    ).entries.single;

NativeReminderIdentity _identity(
  ReminderPlanEntry entry, {
  String variant = 'bn@reminder-v1',
}) => NativeReminderIdentity(
  jobId: entry.jobId,
  dueAtUtc: entry.dueAtUtc,
  closesAtUtc: entry.closesAtUtc,
  contentKey: entry.contentKey,
  payloadVariant: variant,
);

class _MemoryPreferences implements PreferencesStore {
  final Map<String, List<String>> data = <String, List<String>>{};
  final Map<String, Object> readErrors = <String, Object>{};
  Object? writeError;
  int reads = 0;
  int writes = 0;

  @override
  Future<List<String>?> readStrings(String key) async {
    reads++;
    final error = readErrors[key];
    if (error != null) throw error;
    final value = data[key];
    return value == null ? null : List<String>.of(value);
  }

  @override
  Future<void> writeStrings(String key, List<String> values) async {
    writes++;
    final error = writeError;
    if (error != null) throw error;
    data[key] = List<String>.of(values);
  }
}

class _FakeNativeNotifications implements NativeNotifications {
  _FakeNativeNotifications({this.permission = ReminderPermission.granted});

  ReminderPermission permission;
  Object? permissionError;
  Object? pendingError;
  Object? cancelError;
  Object? scheduleError;
  Future<void>? permissionGate;
  Future<void>? pendingGate;
  void Function(int id)? onCancel;
  void Function(NativeReminderRequest request)? onSchedule;

  final List<NativePendingReminder> pending = <NativePendingReminder>[];
  final List<String> events = <String>[];
  final List<NativeReminderRequest> scheduledRequests =
      <NativeReminderRequest>[];
  int initializeCalls = 0;
  int permissionCalls = 0;
  int requestPermissionCalls = 0;
  int pendingCalls = 0;
  int cancelCalls = 0;
  int scheduleCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> initialize({
    required void Function(String jobId) onJobTap,
  }) async {
    initializeCalls++;
  }

  @override
  Future<ReminderPermission> permissionStatus() async {
    permissionCalls++;
    final gate = permissionGate;
    if (gate != null) await gate;
    final error = permissionError;
    if (error != null) throw error;
    return permission;
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    requestPermissionCalls++;
    return permission;
  }

  @override
  Future<List<NativePendingReminder>> pendingReminders() async {
    pendingCalls++;
    final gate = pendingGate;
    if (gate != null) await gate;
    final error = pendingError;
    if (error != null) throw error;
    return List<NativePendingReminder>.of(pending);
  }

  @override
  Future<void> schedule(NativeReminderRequest request) async {
    scheduleCalls++;
    events.add('schedule:${request.identity.jobId}:${request.platformId}');
    scheduledRequests.add(request);
    onSchedule?.call(request);
    final error = scheduleError;
    if (error != null) throw error;
    pending.removeWhere((record) => record.platformId == request.platformId);
    pending.add(
      NativePendingReminder(
        platformId: request.platformId,
        isManaged: true,
        identity: request.identity,
      ),
    );
  }

  @override
  Future<void> cancel(int platformId) async {
    cancelCalls++;
    events.add('cancel:$platformId');
    onCancel?.call(platformId);
    final error = cancelError;
    if (error != null) throw error;
    pending.removeWhere((record) => record.platformId == platformId);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

class _Harness {
  _Harness({
    ReminderPermission permission = ReminderPermission.granted,
    ReminderNotificationTextBuilder? textForJob,
  }) : notifications = _FakeNativeNotifications(permission: permission) {
    synchronizer = LedgerNativeReminderSynchronizer(
      store: preferences,
      notifications: notifications,
      textForJob:
          textForJob ??
          (job, language) => ReminderNotificationText(
            title: '$language title',
            body: '${job.id} body',
          ),
      nowUtc: () => this.now,
    );
  }

  final _MemoryPreferences preferences = _MemoryPreferences();
  final _FakeNativeNotifications notifications;
  DateTime now = _baseNow;
  late final LedgerNativeReminderSynchronizer synchronizer;
}

Future<int> _seedApplied(
  _MemoryPreferences preferences,
  ReminderPlanEntry entry, {
  String variant = 'bn@reminder-v1',
}) async {
  final ledger = ReminderStateStore(store: preferences);
  final reservation = await ledger.reserve(entry.jobId);
  await ledger.recordSchedulingSuccess(entry: entry, payloadVariant: variant);
  ledger.dispose();
  return reservation.platformId;
}

NativePendingReminder _pending(
  int id,
  ReminderPlanEntry entry, {
  String variant = 'bn@reminder-v1',
  bool managed = true,
}) => NativePendingReminder(
  platformId: id,
  isManaged: managed,
  identity: managed ? _identity(entry, variant: variant) : null,
);

void main() {
  group('permission and feed availability', () {
    test(
      'null feed only reports passive permission and leaves pending work alone',
      () async {
        final harness = _Harness();
        final job = _job('job-a');
        final entry = _plannedEntry(job, now: harness.now);
        final id = await _seedApplied(harness.preferences, entry);
        harness.notifications.pending.add(_pending(id, entry));
        final writesBefore = harness.preferences.writes;
        harness.preferences.data['karmopath.reminders.v1'] = [job.id];

        final report = await harness.synchronizer.synchronize(
          _input(jobs: null, selectedJobIds: [job.id]),
        );

        expect(report.feedAvailable, isFalse);
        expect(report.permission, ReminderPermission.granted);
        expect(report.scheduledJobIds, isEmpty);
        expect(report.cancelledJobIds, isEmpty);
        expect(harness.notifications.permissionCalls, 1);
        expect(harness.notifications.requestPermissionCalls, 0);
        expect(harness.notifications.pendingCalls, 0);
        expect(harness.notifications.cancelCalls, 0);
        expect(harness.notifications.scheduleCalls, 0);
        expect(harness.notifications.pending, hasLength(1));
        expect(harness.preferences.writes, writesBefore);
        expect(harness.preferences.data['karmopath.reminders.v1'], [job.id]);
        await harness.synchronizer.close();
      },
    );

    test(
      'permission unavailable or unsupported never queries or changes work',
      () async {
        for (final status in [
          ReminderPermission.unavailable,
          ReminderPermission.unsupported,
        ]) {
          final harness = _Harness(permission: status);
          final report = await harness.synchronizer.synchronize(
            _input(jobs: [_job('job-a')], selectedJobIds: ['job-a']),
          );

          expect(report.permission, status);
          expect(report.feedAvailable, isTrue);
          expect(report.problems, isEmpty);
          expect(harness.notifications.pendingCalls, 0);
          expect(harness.notifications.cancelCalls, 0);
          expect(harness.notifications.scheduleCalls, 0);
          expect(harness.notifications.requestPermissionCalls, 0);
          expect(harness.preferences.writes, 0);
          await harness.synchronizer.close();
        }
      },
    );

    test(
      'permission query failure is reported without pending query or effects',
      () async {
        final harness = _Harness()
          ..notifications.permissionError = StateError(
            'permission query failed',
          );

        final report = await harness.synchronizer.synchronize(
          _input(jobs: [_job('job-a')], selectedJobIds: ['job-a']),
        );

        expect(report.permission, ReminderPermission.unavailable);
        expect(report.problems.single.stage, ReminderSyncStage.permission);
        expect(harness.notifications.pendingCalls, 0);
        expect(harness.notifications.cancelCalls, 0);
        expect(harness.notifications.scheduleCalls, 0);
        expect(harness.notifications.requestPermissionCalls, 0);
        expect(harness.preferences.writes, 0);
        await harness.synchronizer.close();
      },
    );

    test('denied permission with a verified feed cancels known work but keeps intent', () async {
      final harness = _Harness(permission: ReminderPermission.denied);
      final job = _job('job-a');
      final entry = _plannedEntry(job, now: harness.now);
      final id = await _seedApplied(harness.preferences, entry);
      harness.notifications.pending.add(_pending(id, entry));
      harness.preferences.data['karmopath.reminders.v1'] = [job.id];

      final report = await harness.synchronizer.synchronize(
        _input(jobs: [job], selectedJobIds: [job.id]),
      );

      expect(report.permission, ReminderPermission.denied);
      expect(report.feedAvailable, isTrue);
      expect(report.cancelledJobIds, [job.id]);
      expect(report.scheduledJobIds, isEmpty);
      expect(harness.notifications.events, ['cancel:$id']);
      expect(harness.notifications.requestPermissionCalls, 0);
      expect(harness.preferences.data['karmopath.reminders.v1'], [job.id]);
      await harness.synchronizer.close();
    });

    test(
      'a non-null empty feed is authoritative and cancels known applied work',
      () async {
        final harness = _Harness();
        final job = _job('job-a');
        final entry = _plannedEntry(job, now: harness.now);
        final id = await _seedApplied(harness.preferences, entry);
        harness.notifications.pending.add(_pending(id, entry));

        final report = await harness.synchronizer.synchronize(
          _input(jobs: const <Job>[], selectedJobIds: [job.id]),
        );

        expect(report.feedAvailable, isTrue);
        expect(report.cancelledJobIds, [job.id]);
        expect(report.scheduledJobIds, isEmpty);
        expect(harness.notifications.events, ['cancel:$id']);
        await harness.synchronizer.close();
      },
    );
  });

  group('identity, copy, and due recheck', () {
    test('granted sync builds the complete identity and only durable schedules are reported', () async {
      final job = _job('wb-recruitment-2026');
      Job? builtFor;
      String? builtLanguage;
      final harness = _Harness(
        textForJob: (receivedJob, language) {
          builtFor = receivedJob;
          builtLanguage = language;
          return ReminderNotificationText(
            title: 'Localized title',
            body: 'Localized body',
          );
        },
      );
      final entry = _plannedEntry(job, now: harness.now);

      final report = await harness.synchronizer.synchronize(
        _input(jobs: [job], selectedJobIds: [job.id]),
      );

      expect(report.scheduledJobIds, [job.id]);
      expect(report.cancelledJobIds, isEmpty);
      expect(report.problems, isEmpty);
      expect(builtFor, same(job));
      expect(builtLanguage, 'bn');
      final request = harness.notifications.scheduledRequests.single;
      expect(request.platformId, 1);
      expect(request.title, 'Localized title');
      expect(request.body, 'Localized body');
      expect(request.identity.jobId, job.id);
      expect(request.identity.dueAtUtc, entry.dueAtUtc);
      expect(request.identity.closesAtUtc, entry.closesAtUtc);
      expect(request.identity.contentKey, entry.contentKey);
      expect(request.identity.payloadVariant, 'bn@reminder-v1');
      expect(harness.notifications.requestPermissionCalls, 0);

      final writesBefore = harness.preferences.writes;
      final again = await harness.synchronizer.synchronize(
        _input(jobs: [job], selectedJobIds: [job.id]),
      );
      expect(again.scheduledJobIds, isEmpty);
      expect(again.problems, isEmpty);
      expect(harness.notifications.events, ['schedule:${job.id}:1']);
      expect(harness.preferences.writes, writesBefore);
      await harness.synchronizer.close();
    });

    test(
      'language change replaces on the same ID with the new text variant',
      () async {
        final job = _job('language-job');
        final harness = _Harness();
        final bn = await harness.synchronizer.synchronize(
          _input(jobs: [job], selectedJobIds: [job.id], languageCode: 'bn'),
        );
        expect(bn.scheduledJobIds, [job.id]);
        final id = harness.notifications.scheduledRequests.single.platformId;

        final en = await harness.synchronizer.synchronize(
          _input(jobs: [job], selectedJobIds: [job.id], languageCode: 'en'),
        );

        expect(en.cancelledJobIds, [job.id]);
        expect(en.scheduledJobIds, [job.id]);
        expect(harness.notifications.events, [
          'schedule:${job.id}:$id',
          'cancel:$id',
          'schedule:${job.id}:$id',
        ]);
        expect(
          harness.notifications.scheduledRequests.last.identity.payloadVariant,
          'en@reminder-v1',
        );
        expect(harness.notifications.scheduledRequests.last.title, 'en title');
        await harness.synchronizer.close();
      },
    );

    test('blank copy and a throwing builder are schedule failures, never successes', () async {
      final blankHarness = _Harness(
        textForJob: (_, __) =>
            const ReminderNotificationText(title: '   ', body: 'body'),
      );
      final blankJob = _job('blank-copy');
      final blank = await blankHarness.synchronizer.synchronize(
        _input(jobs: [blankJob], selectedJobIds: [blankJob.id]),
      );
      expect(blank.scheduledJobIds, isEmpty);
      expect(blank.problems.single.stage, ReminderSyncStage.schedule);
      expect(blank.problems.single.jobId, blankJob.id);
      expect(blankHarness.notifications.scheduleCalls, 0);
      expect(
        blankHarness.preferences.writes,
        1,
        reason: 'the stable reservation is kept',
      );
      await blankHarness.synchronizer.close();

      final throwingHarness = _Harness(
        textForJob: (_, __) => throw StateError('copy builder failed'),
      );
      final throwingJob = _job('throwing-copy');
      final throwing = await throwingHarness.synchronizer.synchronize(
        _input(jobs: [throwingJob], selectedJobIds: [throwingJob.id]),
      );
      expect(throwing.scheduledJobIds, isEmpty);
      expect(throwing.problems.single.stage, ReminderSyncStage.schedule);
      expect(throwing.problems.single.jobId, throwingJob.id);
      expect(throwingHarness.notifications.scheduleCalls, 0);
      await throwingHarness.synchronizer.close();
    });

    test('due time is rechecked immediately before native schedule', () async {
      final closes = _baseNow.add(const Duration(days: 3));
      final job = _job('late-by-scheduling', closesAt: closes);
      final due = closes.subtract(const Duration(days: 1));
      late _Harness harness;
      harness = _Harness(
        textForJob: (_, __) {
          harness.now = due;
          return const ReminderNotificationText(title: 'title', body: 'body');
        },
      );

      final report = await harness.synchronizer.synchronize(
        _input(jobs: [job], selectedJobIds: [job.id]),
      );

      expect(report.scheduledJobIds, isEmpty);
      expect(report.problems.single.stage, ReminderSyncStage.schedule);
      expect(harness.notifications.scheduleCalls, 0);
      expect(harness.notifications.pending, isEmpty);
      await harness.synchronizer.close();
    });
  });

  group('pending and ledger failures', () {
    test(
      'unreadable pending state is never treated as an empty list',
      () async {
        final harness = _Harness()
          ..notifications.pendingError = StateError('pending read failed');
        final job = _job('pending-read');

        final report = await harness.synchronizer.synchronize(
          _input(jobs: [job], selectedJobIds: [job.id]),
        );

        expect(report.problems.single.stage, ReminderSyncStage.pending);
        expect(report.scheduledJobIds, isEmpty);
        expect(harness.notifications.pendingCalls, 1);
        expect(harness.notifications.scheduleCalls, 0);
        expect(harness.notifications.cancelCalls, 0);
        expect(harness.preferences.writes, 0);
        await harness.synchronizer.close();
      },
    );

    test('unreadable ledger stops before querying pending reminders', () async {
      final harness = _Harness();
      harness.preferences.readErrors[ReminderStateStore.storageKey] =
          StateError('ledger read failed');

      final report = await harness.synchronizer.synchronize(
        _input(jobs: [_job('ledger-read')], selectedJobIds: ['ledger-read']),
      );

      expect(report.problems.single.stage, ReminderSyncStage.ledger);
      expect(harness.notifications.pendingCalls, 0);
      expect(harness.notifications.scheduleCalls, 0);
      expect(harness.notifications.cancelCalls, 0);
      expect(harness.preferences.writes, 0);
      await harness.synchronizer.close();
    });

    test('schedule record failure is not reported and the pending orphan is repaired', () async {
      final harness = _Harness();
      final job = _job('record-failure');
      harness.notifications.onSchedule = (_) {
        harness.preferences.writeError = StateError('ledger write failed');
      };

      final first = await harness.synchronizer.synchronize(
        _input(jobs: [job], selectedJobIds: [job.id]),
      );

      expect(first.scheduledJobIds, isEmpty);
      expect(first.problems.single.stage, ReminderSyncStage.ledger);
      expect(first.problems.single.jobId, job.id);
      expect(harness.notifications.pending, hasLength(1));
      expect(harness.notifications.scheduledRequests, hasLength(1));
      harness.preferences.writeError = null;
      harness.notifications.onSchedule = null;

      final recovered = await harness.synchronizer.synchronize(
        _input(jobs: [job], selectedJobIds: [job.id]),
      );

      expect(recovered.scheduledJobIds, [job.id]);
      expect(recovered.cancelledJobIds, [job.id]);
      expect(recovered.cancelledOrphanIds, [1]);
      expect(recovered.problems, isEmpty);
      expect(harness.notifications.events, [
        'schedule:${job.id}:1',
        'cancel:1',
        'schedule:${job.id}:1',
      ]);
      await harness.synchronizer.close();
    });

    test('cancellation record failure is a ledger-stage problem', () async {
      final harness = _Harness();
      final job = _job('cancel-record-failure');
      final entry = _plannedEntry(job, now: harness.now);
      final id = await _seedApplied(harness.preferences, entry);
      harness.notifications.pending.add(_pending(id, entry));
      harness.notifications.onCancel = (_) {
        harness.preferences.writeError = StateError('cancel record failed');
      };

      final report = await harness.synchronizer.synchronize(
        _input(jobs: const <Job>[], selectedJobIds: const []),
      );

      expect(report.cancelledJobIds, isEmpty);
      expect(report.problems.single.stage, ReminderSyncStage.ledger);
      expect(report.problems.single.jobId, job.id);
      expect(harness.notifications.events, ['cancel:$id']);
      expect(harness.notifications.scheduleCalls, 0);
      await harness.synchronizer.close();
    });
  });

  group('global conflict preflight', () {
    test(
      'duplicate pending IDs abort before any cancellation or schedule',
      () async {
        final harness = _Harness();
        harness.notifications.pending.addAll([
          const NativePendingReminder(
            platformId: 41,
            isManaged: false,
            identity: null,
          ),
          const NativePendingReminder(
            platformId: 41,
            isManaged: true,
            identity: null,
          ),
        ]);

        final report = await harness.synchronizer.synchronize(
          _input(
            jobs: [_job('conflict-job')],
            selectedJobIds: ['conflict-job'],
          ),
        );

        expect(report.problems.single.stage, ReminderSyncStage.conflict);
        expect(report.scheduledJobIds, isEmpty);
        expect(harness.notifications.events, isEmpty);
        expect(harness.preferences.writes, 0);
        await harness.synchronizer.close();
      },
    );

    test(
      'foreign ID colliding with a ledger reservation aborts removal',
      () async {
        final harness = _Harness();
        final job = _job('foreign-collision');
        final entry = _plannedEntry(job, now: harness.now);
        final id = await _seedApplied(harness.preferences, entry);
        harness.notifications.pending.add(
          const NativePendingReminder(
            platformId: 1,
            isManaged: false,
            identity: null,
          ),
        );

        final report = await harness.synchronizer.synchronize(
          _input(jobs: const <Job>[], selectedJobIds: const []),
        );

        expect(report.problems.single.stage, ReminderSyncStage.conflict);
        expect(harness.notifications.events, isEmpty);
        expect(harness.notifications.pending.single.platformId, id);
        expect(
          harness.preferences.writes,
          2,
          reason: 'preflight adds no ledger writes',
        );
        await harness.synchronizer.close();
      },
    );

    test(
      'managed identity claiming another reservation aborts cleanup',
      () async {
        final harness = _Harness();
        final owner = _job('owner-job');
        final claimed = _job('claimed-job');
        final ownerEntry = _plannedEntry(owner, now: harness.now);
        final claimedEntry = _plannedEntry(claimed, now: harness.now);
        final ownerId = await _seedApplied(harness.preferences, ownerEntry);
        await _seedApplied(harness.preferences, claimedEntry);
        harness.notifications.pending.add(_pending(ownerId, claimedEntry));
        final writesBefore = harness.preferences.writes;

        final report = await harness.synchronizer.synchronize(
          _input(jobs: const <Job>[], selectedJobIds: const []),
        );

        expect(report.problems.single.stage, ReminderSyncStage.conflict);
        expect(harness.notifications.events, isEmpty);
        expect(harness.notifications.pending, hasLength(1));
        expect(harness.preferences.writes, writesBefore);
        final ledger = ReminderStateStore(store: harness.preferences);
        await ledger.initialize();
        expect(ledger.snapshot.appliedFor(owner.id), isNotNull);
        expect(ledger.snapshot.appliedFor(claimed.id), isNotNull);
        ledger.dispose();
        await harness.synchronizer.close();
      },
    );

    test(
      'unregistered managed orphan blocks a new monotonic allocation',
      () async {
        final harness = _Harness();
        harness.notifications.pending.add(
          const NativePendingReminder(
            platformId: 1,
            isManaged: true,
            identity: null,
          ),
        );

        final report = await harness.synchronizer.synchronize(
          _input(
            jobs: [_job('blocked-allocation')],
            selectedJobIds: ['blocked-allocation'],
          ),
        );

        expect(report.problems.single.stage, ReminderSyncStage.conflict);
        expect(harness.notifications.events, isEmpty);
        expect(harness.notifications.pending.single.platformId, 1);
        expect(harness.preferences.writes, 0);
        await harness.synchronizer.close();
      },
    );

    test('unknown noncolliding managed orphan is retained while safe work proceeds', () async {
      final harness = _Harness();
      harness.notifications.pending.add(
        const NativePendingReminder(
          platformId: 777,
          isManaged: true,
          identity: null,
        ),
      );
      final job = _job('safe-allocation');

      final report = await harness.synchronizer.synchronize(
        _input(jobs: [job], selectedJobIds: [job.id]),
      );

      expect(report.scheduledJobIds, [job.id]);
      expect(report.problems, isEmpty);
      expect(harness.notifications.events, ['schedule:${job.id}:1']);
      expect(
        harness.notifications.pending.map((item) => item.platformId).toSet(),
        {1, 777},
      );
      await harness.synchronizer.close();
    });
  });

  test(
    'synchronize serializes and close drains without disposing notifications',
    () async {
      final harness = _Harness();
      final gate = Completer<void>();
      harness.notifications.pendingGate = gate.future;
      final job = _job('queued-job');
      final input = _input(jobs: [job], selectedJobIds: [job.id]);

      final first = harness.synchronizer.synchronize(input);
      await pumpEventQueue();
      expect(harness.notifications.pendingCalls, 1);
      final second = harness.synchronizer.synchronize(input);
      await pumpEventQueue();
      expect(harness.notifications.permissionCalls, 1);

      var closeFinished = false;
      final closing = harness.synchronizer.close().then((_) {
        closeFinished = true;
      });
      await pumpEventQueue();
      expect(closeFinished, isFalse);
      await expectLater(
        harness.synchronizer.synchronize(input),
        throwsA(isA<StateError>()),
      );

      gate.complete();
      final firstReport = await first;
      final secondReport = await second;
      await closing;

      expect(firstReport.scheduledJobIds, [job.id]);
      expect(secondReport.scheduledJobIds, isEmpty);
      expect(harness.notifications.permissionCalls, 2);
      expect(harness.notifications.requestPermissionCalls, 0);
      expect(harness.notifications.disposeCalls, 0);
      expect(harness.notifications.cancelCalls, 0);
      expect(harness.notifications.pending, hasLength(1));
      expect(closeFinished, isTrue);
    },
  );
}
