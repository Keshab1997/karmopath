import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/data/reminders/reminder_diff.dart';
import 'package:karmopath/data/reminders/reminder_plan.dart';

import 'reminder_test_jobs.dart';

DateTime utc(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min);

/// Builds a plan from jobs+selection at [now].
ReminderPlan plan({
  required List<Job> jobs,
  required List<String> selected,
  required DateTime now,
}) => planReminders(jobs: jobs, selectedJobIds: selected, now: now);

void main() {
  final early = utc(2026, 11, 1);

  group('first reconciliation', () {
    test('everything new is scheduled, nothing is cancelled', () {
      final desired = plan(
        jobs: [
          exactDeadlineJob(id: 'a-job', closesAt: utc(2026, 11, 20, 12)),
          exactDeadlineJob(id: 'b-job', closesAt: utc(2026, 11, 21, 12)),
        ],
        selected: ['a-job', 'b-job'],
        now: early,
      );

      final diff = diffReminderPlans(
        previous: plan(jobs: const [], selected: const [], now: early),
        desired: desired,
      );

      expect(diff.cancellations, isEmpty);
      expect(diff.schedules.map((s) => s.entry.jobId), ['a-job', 'b-job']);
      expect(diff.schedules.every((s) => !s.isReplacement), isTrue);
      expect(diff.retained, isEmpty);
      expect(diff.isNoOp, isFalse);
    });

    test('an empty desired plan cancels everything that was scheduled', () {
      final previous = plan(
        jobs: [
          exactDeadlineJob(id: 'a-job', closesAt: utc(2026, 11, 20, 12)),
          exactDeadlineJob(id: 'b-job', closesAt: utc(2026, 11, 21, 12)),
        ],
        selected: ['a-job', 'b-job'],
        now: early,
      );

      final diff = diffReminderPlans(
        previous: previous,
        desired: plan(jobs: const [], selected: const [], now: early),
      );

      expect(diff.schedules, isEmpty);
      expect(diff.cancellations.map((c) => c.jobId), ['a-job', 'b-job']);
      expect(diff.cancellations.map((c) => c.previous.jobId), [
        'a-job',
        'b-job',
      ]);
    });
  });

  group('no work when nothing changed', () {
    test('an identical plan yields an empty diff and keeps every entry', () {
      final jobs = [
        exactDeadlineJob(id: 'a-job', closesAt: utc(2026, 11, 20, 12)),
        exactDeadlineJob(id: 'b-job', closesAt: utc(2026, 11, 21, 12)),
      ];
      const selected = ['a-job', 'b-job'];

      final diff = diffReminderPlans(
        previous: plan(jobs: jobs, selected: selected, now: early),
        desired: plan(jobs: jobs, selected: selected, now: early),
      );

      expect(diff.isNoOp, isTrue);
      expect(diff.cancellations, isEmpty);
      expect(diff.schedules, isEmpty);
      expect(diff.retained.map((e) => e.jobId), ['a-job', 'b-job']);
    });

    test('repeated reconciliation stays a no-op', () {
      final jobs = [exactDeadlineJob(closesAt: utc(2026, 11, 20, 12))];
      const selected = ['wb-police-constable-2026'];
      final previous = plan(jobs: jobs, selected: selected, now: early);

      var current = previous;
      for (var i = 0; i < 3; i++) {
        final diff = diffReminderPlans(previous: current, desired: previous);
        expect(diff.isNoOp, isTrue, reason: 'pass ${i + 1} must not churn');
        current = previous;
      }
    });

    test('a different `now` with the same outcome is still a no-op', () {
      final jobs = [exactDeadlineJob(closesAt: utc(2026, 11, 20, 12))];
      const selected = ['wb-police-constable-2026'];

      final diff = diffReminderPlans(
        previous: plan(jobs: jobs, selected: selected, now: early),
        desired: plan(
          jobs: jobs,
          selected: selected,
          now: early.add(const Duration(hours: 5)),
        ),
      );

      expect(diff.isNoOp, isTrue, reason: 'time passing is not a change');
    });
  });

  group('changes that replace a reminder', () {
    test(
      'an extended deadline cancels the old entry and schedules the new one',
      () {
        final previous = plan(
          jobs: [exactDeadlineJob(closesAt: utc(2026, 11, 20, 12))],
          selected: const ['wb-police-constable-2026'],
          now: early,
        );
        final desired = plan(
          jobs: [exactDeadlineJob(closesAt: utc(2026, 11, 25, 12))],
          selected: const ['wb-police-constable-2026'],
          now: early,
        );

        final diff = diffReminderPlans(previous: previous, desired: desired);

        expect(diff.cancellations.single.jobId, 'wb-police-constable-2026');
        expect(
          diff.cancellations.single.previous.dueAtUtc,
          utc(2026, 11, 19, 12),
        );
        final scheduled = diff.schedules.single;
        expect(scheduled.isReplacement, isTrue);
        expect(scheduled.entry.dueAtUtc, utc(2026, 11, 24, 12));
        expect(diff.retained, isEmpty);
      },
    );

    test('a title correction replaces the reminder even at the same time', () {
      final previous = plan(
        jobs: [
          exactDeadlineJob(
            closesAt: utc(2026, 11, 20, 12),
            titleBn: 'পুরনো শিরোনাম',
          ),
        ],
        selected: const ['wb-police-constable-2026'],
        now: early,
      );
      final desired = plan(
        jobs: [
          exactDeadlineJob(
            closesAt: utc(2026, 11, 20, 12),
            titleBn: 'সংশোধিত শিরোনাম',
          ),
        ],
        selected: const ['wb-police-constable-2026'],
        now: early,
      );

      final diff = diffReminderPlans(previous: previous, desired: desired);

      expect(diff.cancellations, hasLength(1));
      expect(diff.schedules.single.isReplacement, isTrue);
      expect(
        diff.schedules.single.entry.dueAtUtc,
        diff.cancellations.single.previous.dueAtUtc,
        reason: 'same instant, different alert text',
      );
    });

    test('a language correction replaces the reminder', () {
      final previous = plan(
        jobs: [
          exactDeadlineJob(
            closesAt: utc(2026, 11, 20, 12),
            titleEn: 'Old English title',
          ),
        ],
        selected: const ['wb-police-constable-2026'],
        now: early,
      );
      final desired = plan(
        jobs: [
          exactDeadlineJob(
            closesAt: utc(2026, 11, 20, 12),
            titleEn: 'Corrected English title',
          ),
        ],
        selected: const ['wb-police-constable-2026'],
        now: early,
      );

      expect(
        diffReminderPlans(previous: previous, desired: desired).isNoOp,
        isFalse,
      );
    });
  });

  group('changes that only cancel', () {
    test('toggling the intent off cancels that job', () {
      final jobs = [
        exactDeadlineJob(id: 'a-job', closesAt: utc(2026, 11, 20, 12)),
        exactDeadlineJob(id: 'b-job', closesAt: utc(2026, 11, 21, 12)),
      ];
      final previous = plan(
        jobs: jobs,
        selected: ['a-job', 'b-job'],
        now: early,
      );
      final desired = plan(jobs: jobs, selected: ['b-job'], now: early);

      final diff = diffReminderPlans(previous: previous, desired: desired);

      expect(diff.cancellations.map((c) => c.jobId), ['a-job']);
      expect(diff.schedules, isEmpty);
      expect(diff.retained.map((e) => e.jobId), ['b-job']);
    });

    test('a deleted job cancels its reminder', () {
      final previous = plan(
        jobs: [
          exactDeadlineJob(id: 'gone-job', closesAt: utc(2026, 11, 20, 12)),
        ],
        selected: const ['gone-job'],
        now: early,
      );
      // The next feed no longer contains the job; the intent still exists.
      final desired = plan(
        jobs: const [],
        selected: const ['gone-job'],
        now: early,
      );

      final diff = diffReminderPlans(previous: previous, desired: desired);

      expect(diff.cancellations.single.jobId, 'gone-job');
      expect(diff.schedules, isEmpty);
      expect(diff.isNoOp, isFalse);
      expect(
        desired.skipReasonFor('gone-job'),
        ReminderSkipReason.jobUnavailable,
        reason: 'the reason travels with the plan so the UI can explain it',
      );
    });

    test('an explicitly closed job cancels its reminder', () {
      final previous = plan(
        jobs: [exactDeadlineJob(id: 'a-job', closesAt: utc(2026, 11, 20, 12))],
        selected: const ['a-job'],
        now: early,
      );
      final desired = plan(
        jobs: [
          exactDeadlineJob(
            id: 'a-job',
            closesAt: utc(2026, 11, 20, 12),
            status: JobStatus.closed,
          ),
        ],
        selected: const ['a-job'],
        now: early,
      );

      final diff = diffReminderPlans(previous: previous, desired: desired);

      expect(diff.cancellations.single.jobId, 'a-job');
      expect(desired.skipReasonFor('a-job'), ReminderSkipReason.notOpen);
    });

    test('a job that becomes unsupported cancels its reminder', () {
      final previous = plan(
        jobs: [exactDeadlineJob(id: 'a-job', closesAt: utc(2026, 11, 20, 12))],
        selected: const ['a-job'],
        now: early,
      );
      final desired = plan(
        jobs: [
          job(
            id: 'a-job',
            kind: JobKind.result,
            status: JobStatus.published,
            endDate: '2026-11-20',
          ),
        ],
        selected: const ['a-job'],
        now: early,
      );

      final diff = diffReminderPlans(previous: previous, desired: desired);

      expect(diff.cancellations.single.jobId, 'a-job');
      expect(
        desired.skipReasonFor('a-job'),
        ReminderSkipReason.unsupportedKind,
      );
    });
  });

  group('apply order and stability', () {
    test(
      'cancellations come before schedules, including for a replacement',
      () {
        final previous = plan(
          jobs: [exactDeadlineJob(closesAt: utc(2026, 11, 20, 12))],
          selected: const ['wb-police-constable-2026'],
          now: early,
        );
        final desired = plan(
          jobs: [exactDeadlineJob(closesAt: utc(2026, 11, 25, 12))],
          selected: const ['wb-police-constable-2026'],
          now: early,
        );

        final diff = diffReminderPlans(previous: previous, desired: desired);
        final order = diff.applyOrder;

        expect(order, hasLength(2));
        expect(order.first, isA<ReminderCancellation>());
        expect(order.last, isA<ReminderScheduling>());
        expect(
          (order.first as ReminderCancellation).jobId,
          (order.last as ReminderScheduling).entry.jobId,
          reason:
              'cancel-then-schedule for one job ID must never leave two alerts',
        );
      },
    );

    test('commands are sorted and contain no duplicates', () {
      final previous = plan(
        jobs: [
          exactDeadlineJob(id: 'c-job', closesAt: utc(2026, 11, 20, 12)),
          exactDeadlineJob(id: 'a-job', closesAt: utc(2026, 11, 21, 12)),
        ],
        selected: ['c-job', 'a-job'],
        now: early,
      );
      final desired = plan(
        jobs: [
          exactDeadlineJob(id: 'b-job', closesAt: utc(2026, 11, 22, 12)),
          exactDeadlineJob(id: 'a-job', closesAt: utc(2026, 11, 23, 12)),
        ],
        selected: ['b-job', 'a-job'],
        now: early,
      );

      final diff = diffReminderPlans(previous: previous, desired: desired);

      expect(diff.cancellations.map((c) => c.jobId), ['a-job', 'c-job']);
      expect(diff.schedules.map((s) => s.entry.jobId), ['b-job', 'a-job']);
      expect(
        diff.cancellations.map((c) => c.jobId).toSet(),
        hasLength(diff.cancellations.length),
      );
      expect(
        diff.schedules.map((s) => s.entry.jobId).toSet(),
        hasLength(diff.schedules.length),
      );
    });

    test('input order of the plans does not change the diff', () {
      final jobsA = exactDeadlineJob(
        id: 'a-job',
        closesAt: utc(2026, 11, 20, 12),
      );
      final jobsB = exactDeadlineJob(
        id: 'b-job',
        closesAt: utc(2026, 11, 21, 12),
      );
      final previous = plan(
        jobs: [jobsA, jobsB],
        selected: ['a-job', 'b-job'],
        now: early,
      );
      final desired = plan(
        jobs: [jobsB, jobsA],
        selected: ['b-job', 'a-job'],
        now: early,
      );

      final diff = diffReminderPlans(previous: previous, desired: desired);
      expect(diff.isNoOp, isTrue);
      expect(diff.retained.map((e) => e.jobId), ['a-job', 'b-job']);
    });

    test('a duplicate job id in a hand-built plan is a loud error', () {
      final entry = ReminderPlanEntry(
        jobId: 'a-job',
        dueAtUtc: utc(2026, 11, 19, 12),
        closesAtUtc: utc(2026, 11, 20, 12),
        contentKey: 'x',
      );
      final duplicated = ReminderPlan(
        generatedAtUtc: early,
        entries: [entry, entry],
        skipped: const [],
      );

      expect(
        () => diffReminderPlans(previous: duplicated, desired: duplicated),
        throwsArgumentError,
      );
    });
  });

  group('after a diff is applied', () {
    test('applying the desired plan makes the next diff a no-op', () {
      final previous = plan(
        jobs: [
          exactDeadlineJob(id: 'a-job', closesAt: utc(2026, 11, 20, 12)),
          exactDeadlineJob(id: 'b-job', closesAt: utc(2026, 11, 21, 12)),
        ],
        selected: ['a-job', 'b-job'],
        now: early,
      );
      final desired = plan(
        jobs: [
          exactDeadlineJob(id: 'a-job', closesAt: utc(2026, 11, 24, 12)),
          exactDeadlineJob(id: 'c-job', closesAt: utc(2026, 11, 22, 12)),
        ],
        selected: ['a-job', 'c-job'],
        now: early,
      );

      final first = diffReminderPlans(previous: previous, desired: desired);
      expect(first.cancellations.map((c) => c.jobId), ['a-job', 'b-job']);
      expect(first.schedules.map((s) => s.entry.jobId), ['c-job', 'a-job']);

      final second = diffReminderPlans(previous: desired, desired: desired);
      expect(second.isNoOp, isTrue);
      expect(second.retained, hasLength(desired.entries.length));
    });

    test('a plan built at a later `now` keeps already-due entries stable', () {
      // The reminder is due in 2 hours: still scheduled, unchanged by time.
      final closes = utc(2026, 11, 20, 12);
      final jobs = [exactDeadlineJob(closesAt: closes)];
      const selected = ['wb-police-constable-2026'];

      final previous = plan(
        jobs: jobs,
        selected: selected,
        now: utc(2026, 11, 19, 10),
      );
      final later = plan(
        jobs: jobs,
        selected: selected,
        now: utc(2026, 11, 19, 10, 30),
      );

      expect(
        diffReminderPlans(previous: previous, desired: later).isNoOp,
        isTrue,
      );
    });
  });
}
