import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/app/notifications/local_reminder_platform.dart';
import 'package:karmopath/data/reminders/reminder_apply.dart';
import 'package:karmopath/data/reminders/reminder_plan.dart';
import 'package:karmopath/data/reminders/reminder_state_store.dart';

import '../../data/fakes.dart';
import '../support/native_test_support.dart';

void main() {
  final start = DateTime.utc(2030, 1, 1);
  ReminderPlanEntry entry() => ReminderPlanEntry(
    jobId: 'long-full-job-id',
    dueAtUtc: start.add(const Duration(days: 1)),
    closesAtUtc: start.add(const Duration(days: 2)),
    contentKey: 'validated-content',
  );
  late FakeNativeNotifications driver;
  late DateTime now;
  late LocalReminderPlatform platform;
  setUp(() {
    driver = FakeNativeNotifications();
    now = start;
    platform = LocalReminderPlatform(
      driver: driver,
      contentFor: (entry) =>
          (title: 'নিয়োগ', body: 'Check the notice.', payload: entry.jobId),
      now: () => now,
    );
  });

  test(
    'schedules reserved ID, UTC instant and full payload without a prompt',
    () async {
      await platform.schedule(entry(), 7);
      expect(driver.scheduled.single.id, 7);
      expect(driver.scheduled.single.dueAtUtc, entry().dueAtUtc);
      expect(driver.scheduled.single.dueAtUtc.isUtc, isTrue);
      expect(driver.scheduled.single.title, 'নিয়োগ');
      expect(driver.scheduled.single.payload, 'long-full-job-id');
      expect(driver.permissionRequests, 0);
    },
  );
  test('denied permission is failure, not silent schedule success', () async {
    driver.enabled = false;
    await expectLater(platform.schedule(entry(), 7), throwsStateError);
    expect(driver.scheduled, isEmpty);
    expect(driver.permissionRequests, 0);
  });
  test(
    'unknown permission/channel error propagates, without prompting',
    () async {
      final error = StateError('channel failed');
      driver.queryError = error;
      await expectLater(platform.schedule(entry(), 7), throwsA(same(error)));
      expect(driver.scheduled, isEmpty);
      expect(driver.permissionRequests, 0);
    },
  );
  test(
    'permission denial never records applied success in the ledger',
    () async {
      driver.enabled = false;
      final store = ReminderStateStore(store: FakePreferencesStore());
      final result = await ReminderApplier(store).apply(
        ReminderPlan(generatedAtUtc: now, entries: [entry()], skipped: []),
        platform,
        'opaque-variant',
      );
      expect(result.failures, hasLength(1));
      expect(result.scheduledEntries, isEmpty);
      expect(store.snapshot.platformIdFor(entry().jobId), 1);
      expect(store.snapshot.appliedFor(entry().jobId), isNull);
      store.dispose();
    },
  );
  test(
    'cancellation remains allowed when permission has been revoked',
    () async {
      driver.enabled = false;
      await platform.cancel(7);
      expect(driver.cancelled, [7]);
      expect(driver.events, ['driver.cancel:7']);
    },
  );
  test(
    'due instant equality and past plans never become catch-up alerts',
    () async {
      for (final date in [
        entry().dueAtUtc,
        entry().dueAtUtc.add(const Duration(seconds: 1)),
      ]) {
        now = date;
        await expectLater(platform.schedule(entry(), 7), throwsStateError);
      }
      expect(driver.events, isEmpty);
    },
  );
  test('cutoff is checked again after asynchronous permission query', () async {
    driver.onEnabled = () => now = entry().dueAtUtc;
    await expectLater(platform.schedule(entry(), 7), throwsStateError);
    expect(driver.scheduled, isEmpty);
    expect(driver.permissionRequests, 0);
  });
  test(
    'wrong job payload is rejected before permission or platform work',
    () async {
      final wrong = LocalReminderPlatform(
        driver: driver,
        now: () => now,
        contentFor: (_) =>
            (title: 'Job', body: 'Notice', payload: 'another-job'),
      );
      await expectLater(wrong.schedule(entry(), 7), throwsStateError);
      expect(driver.events, isEmpty);
    },
  );
  test(
    'blank text is rejected rather than scheduling an empty alert',
    () async {
      final blank = LocalReminderPlatform(
        driver: driver,
        now: () => now,
        contentFor: (e) => (title: ' ', body: 'Notice', payload: e.jobId),
      );
      await expectLater(blank.schedule(entry(), 7), throwsStateError);
      expect(driver.events, isEmpty);
    },
  );
  test('invalid IDs are rejected for scheduling and cancellation', () async {
    for (final id in [0, -1, 2147483648]) {
      await expectLater(platform.schedule(entry(), id), throwsArgumentError);
      await expectLater(platform.cancel(id), throwsArgumentError);
    }
    expect(driver.events, isEmpty);
  });
  test('platform schedule/cancel exceptions are not swallowed', () async {
    final scheduleError = StateError('schedule failed');
    final cancelError = StateError('cancel failed');
    driver.scheduleError = scheduleError;
    driver.cancelError = cancelError;
    await expectLater(
      platform.schedule(entry(), 7),
      throwsA(same(scheduleError)),
    );
    await expectLater(platform.cancel(7), throwsA(same(cancelError)));
  });
  test(
    'pending query failure is not translated into an empty OS list',
    () async {
      final error = StateError('pending query failed');
      driver.queryError = error;
      await expectLater(platform.pendingIds(), throwsA(same(error)));
    },
  );
}
