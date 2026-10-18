import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/data/reminders/reminder_plan.dart';
import 'package:karmopath/features/common/formatting.dart' as ui;

import 'reminder_test_jobs.dart';

/// Guards against the one duplication the brief warns about: the data layer may
/// not import feature code, so [reminderDeadlineUtc] re-states the contract's
/// deadline rule. This test fails the moment the two drift apart.
///
/// Only the batch-4 planner is tested against UI formatting (read-only); the
/// planner itself never imports `lib/features`. If the captain prefers no
/// cross-layer test at all, this file can be deleted without touching the
/// planner — it is deliberately isolated to make that a one-line decision.
void main() {
  test('both layers resolve the same date-only boundary', () {
    for (final date in <String>[
      '2026-01-01',
      '2026-02-28',
      '2028-02-29',
      '2026-11-15',
      '2026-12-31',
      '2027-06-30',
    ]) {
      expect(
        reminderDeadlineUtc(dateOnlyJob(endDate: date)),
        ui.effectiveClosingUtc(dateOnlyJob(endDate: date)),
        reason: 'date-only $date',
      );
    }
  });

  test('both layers prefer an exact UTC timestamp over date-only', () {
    final closes = DateTime.utc(2026, 11, 20, 12, 30);
    final job = exactDeadlineJob(closesAt: closes, endDate: '2026-01-01');

    expect(reminderDeadlineUtc(job), closes);
    expect(ui.effectiveClosingUtc(job), closes);
  });

  test('neither layer invents a deadline that the feed did not supply', () {
    final withoutDeadline = job(); // no deadline fields at all

    expect(reminderDeadlineUtc(withoutDeadline), isNull);
    expect(ui.effectiveClosingUtc(withoutDeadline), isNull);
  });
}
