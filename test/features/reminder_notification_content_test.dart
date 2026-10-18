import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/common/reminder_notification_content.dart';
import 'package:karmopath/features/common/strings.dart';

import 'support/fakes.dart';

void main() {
  final longId = 'n${List.filled(10, 'notice123').join('-')}';
  final job = Job.fromJson(
    makeJob(
      id: longId,
      titleBn: '  নিয়োগ: শিক্ষক—২০২৬! বিস্তারিত দেখুন।  ',
      titleEn: '  Recruitment: Teacher—2026! Read the notice.  ',
      applicationEndDate: '2026-12-31',
    ).toJson(),
  );

  for (final language in AppLang.values) {
    final isBn = language == AppLang.bn;
    final expectedBody = isBn
        ? 'আবেদনের শেষ সময় ও মূল বিজ্ঞপ্তি দেখে নিন।'
        : 'Check the application deadline and the original notice.';
    final expectedVariant = isBn ? 'bn@reminder-v1' : 'en@reminder-v1';

    test('${language.name}: exact title, body, full payload and variant', () {
      final content = buildReminderNotificationContent(
        job: job,
        language: language,
      );
      expect(content.title, isBn ? job.titleBn : job.titleEn);
      expect(content.body, expectedBody);
      expect(content.body, K.reminderNotificationBody.inLang(language));
      expect(content.payload, longId);
      expect(longId.length, 100);
      expect(content.payloadVariant, expectedVariant);
      expect(reminderNotificationVariant(language), expectedVariant);
      expect(content.payloadVariant, reminderNotificationVariant(language));
    });

    test(
      '${language.name}: repeat calls are deterministic, input unchanged',
      () {
        final before = job.toJson();
        final first = buildReminderNotificationContent(
          job: job,
          language: language,
        );
        for (var i = 0; i < 3; i++) {
          final next = buildReminderNotificationContent(
            job: job,
            language: language,
          );
          expect(
            [next.title, next.body, next.payload, next.payloadVariant],
            [first.title, first.body, first.payload, first.payloadVariant],
          );
        }
        expect(job.toJson(), before);
      },
    );

    test(
      '${language.name}: explicit language ignores and preserves global',
      () {
        final original = appLanguage.value;
        var changes = 0;
        void onChange() => changes++;
        addTearDown(() => appLanguage.value = original);
        for (final global in AppLang.values) {
          appLanguage.value = global;
          appLanguage.addListener(onChange);
          try {
            final content = buildReminderNotificationContent(
              job: job,
              language: language,
            );
            expect(content.title, isBn ? job.titleBn : job.titleEn);
            expect(content.body, expectedBody);
            expect(content.payloadVariant, expectedVariant);
            expect(appLanguage.value, global);
            expect(changes, 0);
          } finally {
            appLanguage.removeListener(onChange);
          }
        }
      },
    );

    test(
      '${language.name}: date-only deadline adds no time or success claims',
      () {
        expect(job.applicationEndAt, isNull);
        final content = buildReminderNotificationContent(
          job: job,
          language: language,
        );
        expect(content.body, expectedBody);
        expect(
          RegExp(
            r'00:00|midnight|24|২৪|countdown|scheduled|delivered|missed|government|মধ্যরাত|পাঠানো|নির্ধারিত|মিস|সরকারি',
            caseSensitive: false,
          ).hasMatch(content.body),
          isFalse,
        );
        expect(content.body.contains(job.applicationEndDate!), isFalse);
      },
    );
  }
}
