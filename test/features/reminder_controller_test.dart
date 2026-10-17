import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/features/common/formatting.dart';
import 'package:karmopath/features/common/reminder_controller.dart';

import 'support/fakes.dart';

void main() {
  group('setReminderIntent', () {
    test(
      'no supported deadline requests nothing and persists nothing',
      () async {
        final result = makeJob(
          kind: JobKind.result,
          status: JobStatus.published,
          hasDeadline: false,
        );
        final prefs = FakePreferences();
        final actions = FakeActions();

        final outcome = await setReminderIntent(
          preferences: prefs,
          actions: actions,
          jobId: result.id,
          enable: true,
          deadline: deadlineInfo(result, utcNow()),
        );

        expect(outcome, ReminderOutcome.noDeadline);
        expect(actions.permissionRequests, 0);
        expect(prefs.reminderCalls, isEmpty);
        expect(prefs.reminderJobIds.value, isEmpty);
      },
    );

    test('a missing deadline object is treated the same way', () async {
      final prefs = FakePreferences();
      final actions = FakeActions();

      final outcome = await setReminderIntent(
        preferences: prefs,
        actions: actions,
        jobId: 'unknown-job',
        enable: true,
      );

      expect(outcome, ReminderOutcome.noDeadline);
      expect(actions.permissionRequests, 0);
      expect(prefs.reminderCalls, isEmpty);
    });

    test('denied permission persists nothing', () async {
      final job = makeJob();
      final prefs = FakePreferences();
      final actions = FakeActions(permission: false);

      final outcome = await setReminderIntent(
        preferences: prefs,
        actions: actions,
        jobId: job.id,
        enable: true,
        deadline: deadlineInfo(job, utcNow()),
      );

      expect(outcome, ReminderOutcome.permissionDenied);
      expect(actions.permissionRequests, 1);
      expect(prefs.reminderCalls, isEmpty);
    });

    test('granted permission persists the intent', () async {
      final job = makeJob();
      final prefs = FakePreferences();
      final actions = FakeActions();

      final outcome = await setReminderIntent(
        preferences: prefs,
        actions: actions,
        jobId: job.id,
        enable: true,
        deadline: deadlineInfo(job, utcNow()),
      );

      expect(outcome, ReminderOutcome.enabled);
      expect(prefs.reminderCalls, [(job.id, true)]);
    });

    test('a closed job cannot get a new reminder', () async {
      final past = utcNow().subtract(const Duration(days: 2));
      final job = makeJob(applicationEndDate: dateOnly(past));
      final prefs = FakePreferences();
      final actions = FakeActions();

      final outcome = await setReminderIntent(
        preferences: prefs,
        actions: actions,
        jobId: job.id,
        enable: true,
        deadline: deadlineInfo(job, utcNow()),
      );

      expect(outcome, ReminderOutcome.closed);
      expect(actions.permissionRequests, 0);
      expect(prefs.reminderCalls, isEmpty);
    });

    test('withdrawn jobs cannot get a new reminder', () async {
      final job = makeJob(status: JobStatus.withdrawn);
      final prefs = FakePreferences();
      final actions = FakeActions();

      final outcome = await setReminderIntent(
        preferences: prefs,
        actions: actions,
        jobId: job.id,
        enable: true,
        deadline: deadlineInfo(job, utcNow()),
      );

      expect(outcome, ReminderOutcome.closed);
      expect(prefs.reminderCalls, isEmpty);
    });

    test(
      'an existing intent can be disabled without a deadline or permission',
      () async {
        final result = makeJob(
          kind: JobKind.result,
          status: JobStatus.published,
          hasDeadline: false,
        );
        final prefs = FakePreferences(reminders: {result.id});
        final actions = FakeActions(permission: false);

        final outcome = await setReminderIntent(
          preferences: prefs,
          actions: actions,
          jobId: result.id,
          enable: false,
          deadline: deadlineInfo(result, utcNow()),
        );

        expect(outcome, ReminderOutcome.disabled);
        expect(actions.permissionRequests, 0);
        expect(prefs.reminderCalls, [(result.id, false)]);
        expect(prefs.reminderJobIds.value, isEmpty);
      },
    );

    test(
      'storage failure while enabling reports failure, not success',
      () async {
        final job = makeJob();
        final prefs = FakePreferences(throwOnWrite: true);
        final actions = FakeActions();

        final outcome = await setReminderIntent(
          preferences: prefs,
          actions: actions,
          jobId: job.id,
          enable: true,
          deadline: deadlineInfo(job, utcNow()),
        );

        expect(outcome, ReminderOutcome.failed);
        expect(prefs.reminderJobIds.value, isEmpty);
      },
    );

    test('storage failure while disabling reports failure', () async {
      final job = makeJob();
      final prefs = FakePreferences(reminders: {job.id}, throwOnWrite: true);

      final outcome = await setReminderIntent(
        preferences: prefs,
        actions: FakeActions(),
        jobId: job.id,
        enable: false,
        deadline: deadlineInfo(job, utcNow()),
      );

      expect(outcome, ReminderOutcome.failed);
      expect(prefs.reminderJobIds.value, {job.id});
    });
  });

  group('reminder messages', () {
    test('success copy describes a saved intent, not guaranteed delivery', () {
      final en = reminderOutcomeMessage(ReminderOutcome.enabled).en;
      final bn = reminderOutcomeMessage(ReminderOutcome.enabled).bn;
      expect(en.toLowerCase(), contains('saved'));
      expect(en.toLowerCase(), contains('device settings'));
      expect(en.toLowerCase(), isNot(contains('will notify')));
      expect(en.toLowerCase(), isNot(contains('guaranteed')));
      expect(bn, contains('সংরক্ষণ'));
      expect(bn, isNot(contains('নিশ্চিত')));
    });

    test('honest copy for every failure mode', () {
      expect(
        reminderOutcomeMessage(ReminderOutcome.permissionDenied).bn,
        contains('অনুমতি'),
      );
      expect(
        reminderOutcomeMessage(ReminderOutcome.noDeadline).en,
        contains('no application deadline'),
      );
      expect(
        reminderOutcomeMessage(ReminderOutcome.closed).en,
        contains('closed'),
      );
      expect(
        reminderOutcomeMessage(ReminderOutcome.failed).en,
        contains('Could not'),
      );
    });
  });
}
