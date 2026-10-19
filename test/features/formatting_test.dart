import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/common/formatting.dart';
import 'package:karmopath/features/common/strings.dart';

import 'support/fakes.dart';

void main() {
  group('IST deadline semantics', () {
    test('date-only boundary is exclusive 00:00 IST of the next day', () {
      final job = makeJob(applicationEndDate: '2026-11-15');
      // 2026-11-16T00:00 IST == 2026-11-15T18:30Z
      expect(effectiveClosingUtc(job), DateTime.utc(2026, 11, 15, 18, 30));

      // The final instants of the inclusive day stay open ...
      expect(
        deadlineInfo(job, DateTime.utc(2026, 11, 15, 18, 29, 59, 999)).isClosed,
        isFalse,
      );
      expect(
        deadlineInfo(
          job,
          DateTime.utc(2026, 11, 15, 18, 29, 59, 999, 999),
        ).isClosed,
        isFalse,
      );
      // ... and the next IST midnight closes it.
      expect(
        deadlineInfo(job, DateTime.utc(2026, 11, 15, 18, 30)).isClosed,
        isTrue,
      );
    });

    test('an exact timestamp still closes at that instant', () {
      final exact = DateTime.utc(2026, 11, 15, 6, 30);
      final job = makeJob(
        applicationEndDate: '2026-11-15',
        applicationEndAt: exact,
      );
      expect(
        deadlineInfo(
          job,
          exact.subtract(const Duration(microseconds: 1)),
        ).isClosed,
        isFalse,
      );
      expect(deadlineInfo(job, exact).isClosed, isTrue);
    });

    test('date-only display never shifts across time zones', () {
      expect(formatDateOnly('2026-11-15', AppLang.en), '15 Nov 2026');
      expect(formatDateOnly('2026-11-15', AppLang.bn), '১৫ নভেম্বর ২০২৬');
    });

    test('exact timestamp wins over the date-only field', () {
      final exact = DateTime.utc(2026, 11, 15, 6, 30);
      final job = makeJob(
        applicationEndDate: '2026-11-15',
        applicationEndAt: exact,
      );
      expect(effectiveClosingUtc(job), exact);
      expect(
        deadlineInfo(job, exact.subtract(const Duration(seconds: 1))).isClosed,
        isFalse,
      );
      expect(deadlineInfo(job, exact).isClosed, isTrue);
    });

    test('server status can close a job before its deadline', () {
      final job = makeJob(status: JobStatus.closed);
      final info = deadlineInfo(job, utcNow());
      expect(info.isClosed, isTrue);
      expect(info.isWithdrawn, isFalse);
    });

    test('withdrawn jobs report withdrawn', () {
      final info = deadlineInfo(makeJob(status: JobStatus.withdrawn), utcNow());
      expect(info.isWithdrawn, isTrue);
      expect(info.isClosed, isTrue);
    });

    test('closing soon is limited to three days and open jobs', () {
      final soon = makeJob(
        applicationEndAt: utcNow().add(const Duration(days: 2)),
      );
      final later = makeJob(
        applicationEndAt: utcNow().add(const Duration(days: 5)),
      );
      expect(deadlineInfo(soon, utcNow()).closesSoon, isTrue);
      expect(deadlineInfo(later, utcNow()).closesSoon, isFalse);
    });
  });

  group('labels', () {
    test('deadline label counts down in both languages', () {
      final job = makeJob(
        applicationEndAt: utcNow().add(const Duration(days: 3, hours: 1)),
      );
      final info = deadlineInfo(job, utcNow());
      expect(deadlineLabel(info, job.kind, AppLang.en), 'Closes in 3 days');
      expect(deadlineLabel(info, job.kind, AppLang.bn), '৩ দিনে শেষ হচ্ছে');
    });

    test('date-only closure is labelled without an invented time', () {
      final past = utcNow().subtract(const Duration(days: 2));
      final job = makeJob(applicationEndDate: dateOnly(past));
      final info = deadlineInfo(job, utcNow());
      expect(info.expired, isTrue);
      final en = deadlineLabel(
        info,
        job.kind,
        AppLang.en,
        endDateOnly: job.applicationEndDate,
      )!;
      expect(en, 'Closed on ${formatDateOnly(dateOnly(past), AppLang.en)}');
      expect(en, isNot(contains('IST')));
      expect(en, isNot(contains('PM')));
      final bn = deadlineLabel(
        info,
        job.kind,
        AppLang.bn,
        endDateOnly: job.applicationEndDate,
      )!;
      expect(bn, contains(formatDateOnly(dateOnly(past), AppLang.bn)));
      expect(bn, isNot(contains('IST')));
    });

    test('exact-timestamp expiration keeps its official time', () {
      final exact = utcNow().subtract(const Duration(hours: 3));
      final job = makeJob(applicationEndAt: exact);
      final info = deadlineInfo(job, utcNow());
      expect(info.expired, isTrue);
      expect(
        deadlineLabel(info, job.kind, AppLang.en, endDateOnly: null),
        'Closed on ${formatInstant(exact, AppLang.en)}',
      );
    });

    test('early server closure never claims a closure date', () {
      final future = utcNow().add(const Duration(days: 20));
      for (final job in [
        makeJob(status: JobStatus.closed),
        makeJob(status: JobStatus.closed, applicationEndAt: future),
      ]) {
        final info = deadlineInfo(job, utcNow());
        expect(info.serverClosed, isTrue);
        expect(info.expired, isFalse);
        expect(
          deadlineLabel(
            info,
            job.kind,
            AppLang.en,
            endDateOnly: job.applicationEndDate,
          ),
          'Closed',
        );
        expect(
          deadlineLabel(
            info,
            job.kind,
            AppLang.bn,
            endDateOnly: job.applicationEndDate,
          ),
          'বন্ধ',
        );
      }
    });

    test('withdrawn wins over expiry and server closure', () {
      final past = utcNow().subtract(const Duration(days: 1));
      final expiredWithdrawn = makeJob(
        status: JobStatus.withdrawn,
        applicationEndDate: dateOnly(past),
      );
      final info = deadlineInfo(expiredWithdrawn, utcNow());
      expect(info.isWithdrawn, isTrue);
      expect(info.expired, isTrue);
      expect(info.serverClosed, isFalse);
      expect(
        deadlineLabel(info, expiredWithdrawn.kind, AppLang.en),
        'Withdrawn',
      );
    });

    test('notice label is bilingual and carries no deadline text', () {
      expect(kindLabel(JobKind.notice, AppLang.bn), 'নোটিশ');
      expect(kindLabel(JobKind.notice, AppLang.en), 'Notice');
      final job = makeJob(
        kind: JobKind.notice,
        status: JobStatus.published,
        hasDeadline: false,
      );
      expect(
        deadlineLabel(deadlineInfo(job, utcNow()), job.kind, AppLang.en),
        isNull,
      );
    });

    test('results without a deadline show no deadline label', () {
      final job = makeJob(
        kind: JobKind.result,
        status: JobStatus.published,
        hasDeadline: false,
        applicationEndAt: null,
      );
      final info = deadlineInfo(job, utcNow());
      expect(deadlineLabel(info, job.kind, AppLang.en), isNull);
    });

    test('posts render relative time', () {
      final now = DateTime.utc(2026, 11, 15, 12);
      expect(
        postedLabel(now.subtract(const Duration(days: 1)), now, AppLang.en),
        'Posted 1d ago',
      );
      expect(
        postedLabel(now.subtract(const Duration(hours: 4)), now, AppLang.bn),
        '৪ ঘণ্টা আগে প্রকাশিত',
      );
    });

    test('Bengali numerals localise counts', () {
      expect(K.updatesCount(12, AppLang.bn), '১২টি আপডেট');
      expect(K.updatesCount(1, AppLang.en), '1 update');
      expect(K.reminderCount(2, AppLang.bn), '২টি রিমাইন্ডার চালু');
    });

    test('month headings use the requested language table', () {
      final november = DateTime.utc(2026, 11, 1);
      expect(formatMonthYear(november, AppLang.en), 'Nov 2026');
      expect(formatMonthYear(november, AppLang.bn), 'নভেম্বর ২০২৬');
      final january = DateTime.utc(2027, 1, 4);
      expect(formatMonthYear(january, AppLang.en), 'Jan 2027');
      expect(formatMonthYear(january, AppLang.bn), 'জানুয়ারি ২০২৭');
    });

    test('instant formatting uses the IST wall clock', () {
      expect(
        formatInstant(DateTime.utc(2026, 11, 15, 13, 0), AppLang.en),
        '15 Nov 2026, 6:30 PM IST',
      );
    });
  });
}
