import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/data/reminders/reminder_plan.dart';

import 'reminder_test_jobs.dart';

/// `now` is always injected, so every boundary below is exact arithmetic.
DateTime utc(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min);

void main() {
  group('deadline resolution (contract rule)', () {
    test('an exact UTC timestamp is authoritative', () {
      final closes = utc(2026, 11, 20, 12, 30);
      expect(
        reminderDeadlineUtc(
          exactDeadlineJob(closesAt: closes, endDate: '2026-01-01'),
        ),
        closes,
      );
    });

    test('a date-only deadline closes at next midnight Asia/Kolkata', () {
      // 2026-11-15 inclusive -> 2026-11-16T00:00+05:30 == 2026-11-15T18:30Z.
      expect(
        reminderDeadlineUtc(dateOnlyJob(endDate: '2026-11-15')),
        utc(2026, 11, 15, 18, 30),
      );
    });

    test('a non-UTC clock instant is compared as an instant', () {
      // 2026-11-15T23:59:59+05:30 is still 2026-11-15T18:29:59Z: before close.
      final istNow = DateTime.parse('2026-11-15T23:59:59+05:30');
      final closes = reminderDeadlineUtc(dateOnlyJob(endDate: '2026-11-15'));
      expect(closes!.isAfter(istNow), isTrue);
      expect(closes.isAtSameMomentAs(utc(2026, 11, 15, 18, 30)), isTrue);
    });

    test('no deadline fields resolve to null', () {
      expect(reminderDeadlineUtc(job()), isNull);
    });

    test('an unparsable date-only value resolves to null, not a guess', () {
      expect(reminderDeadlineUtc(job(endDate: '2026-1-5')), isNull);
    });

    test('a leap day is handled by calendar arithmetic', () {
      // 2028-02-29 inclusive -> closes 2028-03-01T00:00 IST.
      expect(
        reminderDeadlineUtc(dateOnlyJob(endDate: '2028-02-29')),
        utc(2028, 2, 29, 18, 30),
      );
    });
  });

  group('24 hour lead time', () {
    test('a plan is due exactly 24 h before the exact closing instant', () {
      final closes = utc(2026, 11, 20, 12, 30);
      final plan = planReminders(
        jobs: [exactDeadlineJob(closesAt: closes)],
        selectedJobIds: ['wb-police-constable-2026'],
        now: utc(2026, 11, 1),
      );

      expect(plan.entries, hasLength(1));
      expect(plan.entries.single.closesAtUtc, closes);
      expect(
        plan.entries.single.dueAtUtc,
        utc(2026, 11, 19, 12, 30),
        reason: 'due = closesAt - 24h',
      );
      expect(reminderLeadTime, const Duration(hours: 24));
    });

    test(
      'a date-only deadline is due 24 h before the IST midnight boundary',
      () {
        final plan = planReminders(
          jobs: [dateOnlyJob(endDate: '2026-11-15')],
          selectedJobIds: ['wb-health-recruitment-2026'],
          now: utc(2026, 11, 1),
        );

        expect(plan.entries.single.closesAtUtc, utc(2026, 11, 15, 18, 30));
        expect(plan.entries.single.dueAtUtc, utc(2026, 11, 14, 18, 30));
      },
    );

    test('one second before due time still plans', () {
      final plan = planReminders(
        jobs: [exactDeadlineJob(closesAt: utc(2026, 11, 20, 12))],
        selectedJobIds: ['wb-police-constable-2026'],
        now: utc(2026, 11, 19, 11, 59).add(const Duration(seconds: 59)),
      );
      expect(plan.entries, hasLength(1));
    });

    test('the exact due instant is not new work (equality excluded)', () {
      final plan = planReminders(
        jobs: [exactDeadlineJob(closesAt: utc(2026, 11, 20, 12))],
        selectedJobIds: ['wb-police-constable-2026'],
        now: utc(2026, 11, 19, 12), // exactly dueAt
      );

      expect(
        plan.entries,
        isEmpty,
        reason: 'dueAt == now is not in the future',
      );
      expect(
        plan.skipReasonFor('wb-police-constable-2026'),
        ReminderSkipReason.optedInTooLate,
      );
    });

    test('late opt-in inside the 24 hour window creates no catch-up alert', () {
      final plan = planReminders(
        jobs: [exactDeadlineJob(closesAt: utc(2026, 11, 20, 12))],
        selectedJobIds: ['wb-police-constable-2026'],
        now: utc(2026, 11, 20, 6), // 6 h before closing, 18 h after dueAt
      );

      expect(plan.entries, isEmpty);
      expect(
        plan.skipReasonFor('wb-police-constable-2026'),
        ReminderSkipReason.optedInTooLate,
      );
    });

    test(
      'a deadline that has passed is reported distinctly from late opt-in',
      () {
        final plan = planReminders(
          jobs: [
            exactDeadlineJob(id: 'past-job', closesAt: utc(2026, 11, 19, 12)),
            exactDeadlineJob(id: 'soon-job', closesAt: utc(2026, 11, 20, 12)),
          ],
          selectedJobIds: ['past-job', 'soon-job'],
          now: utc(2026, 11, 20, 6),
        );

        expect(plan.entries, isEmpty);
        expect(
          plan.skipReasonFor('past-job'),
          ReminderSkipReason.deadlinePassed,
        );
        expect(
          plan.skipReasonFor('soon-job'),
          ReminderSkipReason.optedInTooLate,
        );
      },
    );
  });

  group('what does not create a reminder', () {
    test('a selected id that is not in the feed', () {
      final plan = planReminders(
        jobs: const <Job>[],
        selectedJobIds: ['deleted-job'],
        now: utc(2026, 11, 1),
      );

      expect(plan.entries, isEmpty);
      expect(
        plan.skipReasonFor('deleted-job'),
        ReminderSkipReason.jobUnavailable,
      );
    });

    test('closed and withdrawn jobs, even with a future deadline', () {
      final closes = utc(2026, 11, 20, 12);
      final plan = planReminders(
        jobs: [
          exactDeadlineJob(
            id: 'closed-job',
            closesAt: closes,
            status: JobStatus.closed,
          ),
          exactDeadlineJob(
            id: 'withdrawn-job',
            closesAt: closes,
            status: JobStatus.withdrawn,
          ),
        ],
        selectedJobIds: ['closed-job', 'withdrawn-job'],
        now: utc(2026, 11, 1),
      );

      expect(plan.entries, isEmpty);
      expect(plan.skipReasonFor('closed-job'), ReminderSkipReason.notOpen);
      expect(plan.skipReasonFor('withdrawn-job'), ReminderSkipReason.notOpen);
    });

    test('results and admit cards are unsupported kinds', () {
      final plan = planReminders(
        jobs: [
          job(
            id: 'result-job',
            kind: JobKind.result,
            status: JobStatus.published,
          ),
          job(
            id: 'admit-job',
            kind: JobKind.admitCard,
            status: JobStatus.published,
          ),
        ],
        selectedJobIds: ['result-job', 'admit-job'],
        now: utc(2026, 11, 1),
      );

      expect(plan.entries, isEmpty);
      expect(
        plan.skipReasonFor('result-job'),
        ReminderSkipReason.unsupportedKind,
      );
      expect(
        plan.skipReasonFor('admit-job'),
        ReminderSkipReason.unsupportedKind,
      );
    });

    test('an open recruitment without a deadline', () {
      final plan = planReminders(
        jobs: [job(id: 'no-deadline-job')],
        selectedJobIds: ['no-deadline-job'],
        now: utc(2026, 11, 1),
      );

      expect(plan.entries, isEmpty);
      expect(
        plan.skipReasonFor('no-deadline-job'),
        ReminderSkipReason.noDeadline,
      );
    });

    test('a job that was never selected', () {
      final plan = planReminders(
        jobs: [exactDeadlineJob(closesAt: utc(2026, 11, 20, 12))],
        selectedJobIds: const <String>[],
        now: utc(2026, 11, 1),
      );

      expect(plan.entries, isEmpty);
      expect(plan.skipped, isEmpty, reason: 'unselected jobs are not skips');
    });
  });

  group('purity and determinism', () {
    test('input order never changes the output', () {
      final jobs = [
        exactDeadlineJob(id: 'b-job', closesAt: utc(2026, 11, 20, 12)),
        exactDeadlineJob(id: 'a-job', closesAt: utc(2026, 11, 20, 12)),
        exactDeadlineJob(id: 'c-job', closesAt: utc(2026, 11, 19, 12)),
      ];
      const selected = ['c-job', 'a-job', 'b-job'];

      final first = planReminders(
        jobs: jobs,
        selectedJobIds: selected,
        now: utc(2026, 11, 1),
      );
      final shuffled = planReminders(
        jobs: jobs.reversed.toList(),
        selectedJobIds: selected.reversed.toList(),
        now: utc(2026, 11, 1),
      );

      expect(
        shuffled.entries.map((e) => e.jobId).toList(),
        first.entries.map((e) => e.jobId).toList(),
      );
      // Ordered by due instant, then id.
      expect(first.entries.map((e) => e.jobId).toList(), [
        'c-job',
        'a-job',
        'b-job',
      ]);
      expect(first.entries, equals(shuffled.entries));
    });

    test('the plan is immutable and does not touch the inputs', () {
      final jobs = [exactDeadlineJob(closesAt: utc(2026, 11, 20, 12))];
      final selected = ['wb-police-constable-2026'];
      final jobsSnapshot = jobs.single.toJson();
      final selectedSnapshot = List<String>.of(selected);

      final plan = planReminders(
        jobs: jobs,
        selectedJobIds: selected,
        now: utc(2026, 11, 1),
      );

      expect(
        () => plan.entries.add(plan.entries.single),
        throwsUnsupportedError,
      );
      expect(
        () => plan.skipped.add(
          const ReminderSkip(jobId: 'x', reason: ReminderSkipReason.noDeadline),
        ),
        throwsUnsupportedError,
      );
      expect(jobs.single.toJson(), jobsSnapshot);
      expect(selected, selectedSnapshot);
    });

    test('duplicate selected ids collapse to one entry', () {
      final plan = planReminders(
        jobs: [exactDeadlineJob(closesAt: utc(2026, 11, 20, 12))],
        selectedJobIds: const [
          'wb-police-constable-2026',
          'wb-police-constable-2026',
        ],
        now: utc(2026, 11, 1),
      );

      expect(plan.entries, hasLength(1));
    });

    test('a duplicate id in the feed is a loud error, not a silent choice', () {
      final closes = utc(2026, 11, 20, 12);
      expect(
        () => planReminders(
          jobs: [
            exactDeadlineJob(closesAt: closes),
            exactDeadlineJob(closesAt: closes),
          ],
          selectedJobIds: const ['wb-police-constable-2026'],
          now: utc(2026, 11, 1),
        ),
        throwsArgumentError,
      );
    });

    test('the plan records the normalised instant it was built at', () {
      final istNow = DateTime.parse('2026-11-01T12:00:00+05:30');
      final plan = planReminders(
        jobs: [exactDeadlineJob(closesAt: utc(2026, 11, 20, 12))],
        selectedJobIds: const ['wb-police-constable-2026'],
        now: istNow,
      );

      expect(plan.generatedAtUtc.isUtc, isTrue);
      expect(plan.generatedAtUtc, utc(2026, 11, 1, 6, 30));
    });
  });

  group('content key', () {
    test('a title correction changes the key', () {
      final before = planReminders(
        jobs: [
          exactDeadlineJob(
            closesAt: utc(2026, 11, 20, 12),
            titleBn: 'পুরনো শিরোনাম',
          ),
        ],
        selectedJobIds: const ['wb-police-constable-2026'],
        now: utc(2026, 11, 1),
      );
      final after = planReminders(
        jobs: [
          exactDeadlineJob(
            closesAt: utc(2026, 11, 20, 12),
            titleBn: 'সংশোধিত শিরোনাম',
          ),
        ],
        selectedJobIds: const ['wb-police-constable-2026'],
        now: utc(2026, 11, 1),
      );

      expect(
        before.entries.single.contentKey,
        isNot(after.entries.single.contentKey),
      );
    });

    test('the key is stable across runs and does not use Object.hashCode', () {
      final a = planReminders(
        jobs: [exactDeadlineJob(closesAt: utc(2026, 11, 20, 12))],
        selectedJobIds: const ['wb-police-constable-2026'],
        now: utc(2026, 11, 1),
      ).entries.single.contentKey;
      final b = planReminders(
        jobs: [exactDeadlineJob(closesAt: utc(2026, 11, 20, 12))],
        selectedJobIds: const ['wb-police-constable-2026'],
        now: utc(2026, 11, 1),
      ).entries.single.contentKey;

      expect(a, b);
      expect(a, isNot(contains('Instance of')));
      expect(
        a.contains('পশ্চিমবঙ্গ পুলিশ কনস্টেবল নিয়োগ ২০২৬'),
        isTrue,
        reason: 'the key covers the Bengali title actually shown',
      );
    });

    test('switching from date-only to an exact instant changes the key', () {
      final dateOnly = planReminders(
        jobs: [dateOnlyJob(endDate: '2026-11-15')],
        selectedJobIds: const ['wb-health-recruitment-2026'],
        now: utc(2026, 11, 1),
      ).entries.single;
      final exact = planReminders(
        jobs: [
          exactDeadlineJob(
            id: 'wb-health-recruitment-2026',
            closesAt: utc(2026, 11, 15, 18, 30),
          ),
        ],
        selectedJobIds: const ['wb-health-recruitment-2026'],
        now: utc(2026, 11, 1),
      ).entries.single;

      expect(exact.dueAtUtc, dateOnly.dueAtUtc, reason: 'same instant');
      expect(
        exact.contentKey,
        isNot(dateOnly.contentKey),
        reason: 'the deadline source changed even though the instant did not',
      );
    });
  });
}
