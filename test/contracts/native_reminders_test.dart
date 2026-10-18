import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/contracts/job_feed.dart';
import 'package:karmopath/contracts/native_reminders.dart';

NativeReminderIdentity identity({
  String jobId = 'job-one',
  String contentKey = 'full-content-key',
  String payloadVariant = 'bn@reminder-v1',
  DateTime? due,
  DateTime? closes,
}) => NativeReminderIdentity(
  jobId: jobId,
  dueAtUtc: due ?? DateTime.utc(2030, 1, 1),
  closesAtUtc: closes ?? DateTime.utc(2030, 1, 2),
  contentKey: contentKey,
  payloadVariant: payloadVariant,
);

void main() {
  test('namespace/channel/icon are shared literals, not worker guesses', () {
    expect(reminderPayloadNamespace, 'karmopath.reminder.v1');
    expect(reminderAndroidChannelId, 'karmopath.deadlines.v1');
    expect(reminderAndroidChannelName, 'Deadline reminders');
    expect(reminderAndroidIcon, 'ic_stat_karmopath');
  });

  test('Bengali and English variants remain distinct', () {
    expect(reminderPayloadVariant('bn'), 'bn@reminder-v1');
    expect(reminderPayloadVariant('en'), 'en@reminder-v1');
  });

  test('unsupported language never silently becomes Bengali', () {
    for (final value in ['', 'BN', 'fr', ' en ']) {
      expect(() => reminderPayloadVariant(value), throwsArgumentError);
    }
  });

  test('identity normalizes timestamps to UTC', () {
    final value = identity(
      due: DateTime.parse('2030-01-01T05:30:00+05:30'),
      closes: DateTime.parse('2030-01-02T05:30:00+05:30'),
    );
    expect(value, identity());
    expect(value.dueAtUtc.isUtc, isTrue);
    expect(value.closesAtUtc.isUtc, isTrue);
    expect(value.hashCode, identity().hashCode);
  });

  test('identity compares full job ID and content, not a truncated hash', () {
    expect(identity(), isNot(identity(jobId: 'job-two')));
    expect(identity(), isNot(identity(contentKey: 'different-full-key')));
    expect(identity(), isNot(identity(payloadVariant: 'en@reminder-v1')));
    expect(identity(), isNot(identity(due: DateTime.utc(2029, 12, 31))));
    expect(identity(), isNot(identity(closes: DateTime.utc(2030, 1, 3))));
  });

  test('identity rejects invalid contract job IDs', () {
    for (final value in ['', 'UPPER', 'has space', 'a' * 101]) {
      expect(() => identity(jobId: value), throwsArgumentError);
    }
  });

  test('identity rejects due at or after closing instant', () {
    expect(
      () => identity(closes: DateTime.utc(2030, 1, 1)),
      throwsArgumentError,
    );
    expect(
      () => identity(closes: DateTime.utc(2029, 1, 1)),
      throwsArgumentError,
    );
  });

  test('identity rejects blank content and payload variant', () {
    expect(() => identity(contentKey: ' '), throwsArgumentError);
    expect(() => identity(payloadVariant: ''), throwsArgumentError);
  });

  test('request accepts the two allocator boundary IDs', () {
    for (final id in [1, 2147483647]) {
      final request = NativeReminderRequest(
        platformId: id,
        identity: identity(),
        title: 'Title',
        body: 'Body',
      );
      expect(request.platformId, id);
    }
  });

  test('request refuses out-of-range platform IDs', () {
    for (final id in [-1, 0, 2147483648]) {
      expect(
        () => NativeReminderRequest(
          platformId: id,
          identity: identity(),
          title: 'Title',
          body: 'Body',
        ),
        throwsArgumentError,
      );
    }
  });

  test('request refuses blank visible copy', () {
    expect(
      () => NativeReminderRequest(
        platformId: 1,
        identity: identity(),
        title: ' ',
        body: 'Body',
      ),
      throwsArgumentError,
    );
    expect(
      () => NativeReminderRequest(
        platformId: 1,
        identity: identity(),
        title: 'Title',
        body: '',
      ),
      throwsArgumentError,
    );
  });

  test(
    'unknown and malformed managed pending entries stay distinguishable',
    () {
      const foreign = NativePendingReminder(
        platformId: 1,
        isManaged: false,
        identity: null,
      );
      const malformedManaged = NativePendingReminder(
        platformId: 2,
        isManaged: true,
        identity: null,
      );
      expect(foreign.isManaged, isFalse);
      expect(malformedManaged.isManaged, isTrue);
      expect(foreign.identity, isNull);
    },
  );

  test('missing feed is not represented as an empty verified feed', () {
    final missing = ReminderSyncInput(
      jobs: null,
      selectedJobIds: ['job-one'],
      languageCode: 'bn',
    );
    final empty = ReminderSyncInput(
      jobs: [],
      selectedJobIds: ['job-one'],
      languageCode: 'bn',
    );
    expect(missing.jobs, isNull);
    expect(empty.jobs, isEmpty);
  });

  test('sync input captures an immutable job snapshot', () {
    final feed = JobFeed.fromJson(
      jsonDecode(File('test/fixtures/sample_feed.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final jobs = List<Job>.of(feed.jobs);
    final count = jobs.length;
    final input = ReminderSyncInput(
      jobs: jobs,
      selectedJobIds: const [],
      languageCode: 'bn',
    );
    jobs.clear();
    expect(input.jobs, hasLength(count));
    expect(() => input.jobs!.clear(), throwsUnsupportedError);
  });

  test('selected IDs are copied, deduplicated and immutable', () {
    final selected = ['job-one', 'job-one'];
    final input = ReminderSyncInput(
      jobs: null,
      selectedJobIds: selected,
      languageCode: 'en',
    );
    selected.add('job-two');
    expect(input.selectedJobIds, {'job-one'});
    expect(() => input.selectedJobIds.add('job-three'), throwsUnsupportedError);
  });

  test('sync input rejects unsupported language at the boundary', () {
    expect(
      () =>
          ReminderSyncInput(jobs: null, selectedJobIds: [], languageCode: 'fr'),
      throwsArgumentError,
    );
  });

  test('report snapshots cannot be modified by a worker or consumer', () {
    final scheduled = ['job-one'];
    final cancelled = ['job-two'];
    final orphans = [3];
    final problems = <ReminderSyncProblem>[];
    final report = ReminderSyncReport(
      permission: ReminderPermission.granted,
      feedAvailable: true,
      scheduledJobIds: scheduled,
      cancelledJobIds: cancelled,
      cancelledOrphanIds: orphans,
      problems: problems,
    );
    scheduled.clear();
    cancelled.clear();
    orphans.clear();
    problems.add(
      ReminderSyncProblem(
        stage: ReminderSyncStage.schedule,
        error: StateError('later failure'),
      ),
    );
    expect(report.scheduledJobIds, ['job-one']);
    expect(report.cancelledJobIds, ['job-two']);
    expect(report.cancelledOrphanIds, [3]);
    expect(report.hasFailures, isFalse);
    expect(() => report.scheduledJobIds.clear(), throwsUnsupportedError);
    expect(() => report.problems.clear(), throwsUnsupportedError);
  });

  test('denied/unavailable are not inferred to be permission grants', () {
    for (final permission in [
      ReminderPermission.denied,
      ReminderPermission.unavailable,
      ReminderPermission.unsupported,
    ]) {
      final report = ReminderSyncReport(
        permission: permission,
        feedAvailable: false,
        scheduledJobIds: [],
        cancelledJobIds: [],
        cancelledOrphanIds: [],
        problems: [],
      );
      expect(report.permission, isNot(ReminderPermission.granted));
      expect(report.scheduledJobIds, isEmpty);
      expect(report.feedAvailable, isFalse);
    }
  });

  test('partial failures remain visible alongside confirmed successes', () {
    final error = StateError('OS failure');
    final report = ReminderSyncReport(
      permission: ReminderPermission.granted,
      feedAvailable: true,
      scheduledJobIds: ['job-one'],
      cancelledJobIds: [],
      cancelledOrphanIds: [],
      problems: [
        ReminderSyncProblem(
          stage: ReminderSyncStage.schedule,
          jobId: 'job-two',
          platformId: 2,
          error: error,
        ),
      ],
    );
    expect(report.hasFailures, isTrue);
    expect(report.problems.single.error, same(error));
    expect(report.problems.single.jobId, 'job-two');
    expect(report.scheduledJobIds, ['job-one']);
  });
}
