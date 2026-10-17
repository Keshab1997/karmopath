import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/common/formatting.dart';
import 'package:karmopath/features/common/reminder_controller.dart';

import 'support/fakes.dart';

void main() {
  test('date-only stays open in last 999 milliseconds of IST closing day', () {
    final job = makeJob(applicationEndDate: '2026-11-15');
    expect(
      deadlineInfo(job, DateTime.utc(2026, 11, 15, 18, 29, 59, 999)).isClosed,
      isFalse,
    );
  });
  test('English calendar month is English', () {
    expect(formatMonthYear(DateTime.utc(2026, 11, 1), AppLang.en), 'Nov 2026');
  });
  test('server-closed early must not claim future scheduled deadline as actual closing', () {
    final job = makeJob(
      status: JobStatus.closed,
      applicationEndDate: '2026-11-15',
    );
    final label = deadlineLabel(
      deadlineInfo(job, DateTime.utc(2026, 11, 1)),
      job.kind,
      AppLang.en,
    )!;
    expect(label, isNot(contains('Closed on')));
  });
  test('deadline reminder without deadline never persists intent', () async {
    final job = makeJob(
      kind: JobKind.result,
      status: JobStatus.published,
      hasDeadline: false,
    );
    final prefs = FakePreferences();
    final actions = FakeActions();
    await setReminderIntent(
      preferences: prefs,
      actions: actions,
      jobId: job.id,
      enable: true,
      deadline: deadlineInfo(job, utcNow()),
    );
    expect(prefs.reminderCalls, isEmpty);
    expect(actions.permissionRequests, 0);
  });
}
