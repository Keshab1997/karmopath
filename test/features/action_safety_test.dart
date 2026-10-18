import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/common/external_link.dart';
import 'package:karmopath/features/common/formatting.dart';
import 'package:karmopath/features/common/reminder_controller.dart';
import 'package:karmopath/features/common/strings.dart';
import 'package:karmopath/features/job_detail/job_detail_screen.dart';

import 'support/fakes.dart';

/// Builds a [Job] directly (bypassing JSON validation) so unsafe URLs can be
/// exercised at the widget boundary. The feed parser already refuses these;
/// this proves the screen refuses them too if a bad value ever reaches it.
Job jobWithLinks({
  required String noticeUrl,
  String? sourceUrl,
  String? applyUrl,
}) {
  final base = makeJob();
  return Job(
    id: base.id,
    kind: base.kind,
    titleBn: base.titleBn,
    titleEn: base.titleEn,
    organization: base.organization,
    category: base.category,
    districts: base.districts,
    qualifications: base.qualifications,
    status: base.status,
    sourceUrl: sourceUrl ?? base.sourceUrl,
    noticeUrl: noticeUrl,
    reviewedAt: base.reviewedAt,
    publishedAt: base.publishedAt,
    updatedAt: base.updatedAt,
    summaryBn: base.summaryBn,
    summaryEn: base.summaryEn,
    howToApplyBn: base.howToApplyBn,
    howToApplyEn: base.howToApplyEn,
    vacancies: base.vacancies,
    applicationStartDate: base.applicationStartDate,
    applicationEndDate: base.applicationEndDate,
    applicationEndAt: base.applicationEndAt,
    examDate: base.examDate,
    applyUrl: applyUrl,
    ageNoteBn: base.ageNoteBn,
    ageNoteEn: base.ageNoteEn,
  );
}

Widget detail(Job job, FakeActions actions, {FakePreferences? prefs}) =>
    JobDetailScreen(
      job: job,
      preferences: prefs ?? FakePreferences(),
      actions: actions,
    );

void main() {
  setUp(() => appLanguage.value = AppLang.bn);
  tearDown(() => appLanguage.value = AppLang.bn);

  group('validateExternalLink', () {
    test('accepts absolute HTTPS links from the feed', () {
      for (final url in [
        'https://wbp.example.gov.in/notice.pdf',
        'https://apply.example.gov.in/form?post=constable&id=42',
        'https://example.gov.in/a/b/c.html',
        'https://example.gov.in:8443/notice',
      ]) {
        final check = validateExternalLink(url);
        expect(check.isValid, isTrue, reason: url);
        expect(check.uri!.toString(), url);
      }
    });

    test('rejects non-HTTPS and pseudo schemes', () {
      for (final url in [
        'http://wbp.example.gov.in/notice.pdf',
        'HTTP://wbp.example.gov.in/notice.pdf',
        'javascript:alert(1)',
        'data:text/html;base64,PHNjcmlwdD4=',
        'file:///etc/passwd',
        'ftp://example.gov.in/notice',
        'mailto:someone@example.gov.in',
        'intent://scan/#Intent;scheme=zxing;end',
      ]) {
        final check = validateExternalLink(url);
        expect(check.isValid, isFalse, reason: url);
        expect(check.rejection, LinkRejection.notHttps, reason: url);
      }
    });

    test('rejects embedded credentials and fragments', () {
      final credentials = validateExternalLink(
        'https://user:secret@wbp.example.gov.in/notice.pdf',
      );
      expect(credentials.isValid, isFalse);
      expect(credentials.rejection, LinkRejection.embeddedCredentials);

      final userOnly = validateExternalLink(
        'https://token@wbp.example.gov.in/notice.pdf',
      );
      expect(userOnly.rejection, LinkRejection.embeddedCredentials);

      final fragment = validateExternalLink(
        'https://wbp.example.gov.in/notice.pdf#page=4',
      );
      expect(fragment.isValid, isFalse);
      expect(fragment.rejection, LinkRejection.fragment);
    });

    test('rejects malformed input and missing hosts', () {
      for (final url in [
        '',
        '   ',
        'not a url',
        '/relative/path',
        'https://',
      ]) {
        final check = validateExternalLink(url);
        expect(check.isValid, isFalse, reason: url);
      }
      expect(
        validateExternalLink('https://').rejection,
        anyOf(LinkRejection.missingHost, LinkRejection.malformed),
      );
      expect(
        validateExternalLink('/relative/path').rejection,
        LinkRejection.malformed,
      );
    });

    test('rejects whitespace, control characters and padded input', () {
      for (final url in [
        ' https://wbp.example.gov.in/notice.pdf',
        'https://wbp.example.gov.in/notice.pdf ',
        'https://wbp.example.gov.in/a b.pdf',
        'https://wbp.example.gov.in/\nnotice.pdf',
        'https://wbp.example.gov.in/\u0000notice.pdf',
      ]) {
        final check = validateExternalLink(url);
        expect(check.isValid, isFalse, reason: url);
        expect(
          check.rejection,
          anyOf(LinkRejection.unsafeCharacters, LinkRejection.malformed),
          reason: url,
        );
      }
    });

    test('never repairs a rejected scheme and passes URLs unchanged', () {
      // A rejected URL is never rewritten into an https one.
      expect(validateExternalLink('http://a.gov.in/x').uri, isNull);
      // An accepted URL reaches AppActions as the same Uri the feed supplied.
      const url = 'https://example.gov.in/notice.pdf?v=2&post=constable';
      expect(validateExternalLink(url).uri, Uri.parse(url));
    });
  });

  group('ExternalLinkGuard', () {
    test('invalid URLs never reach AppActions', () async {
      final actions = FakeActions();
      final guard = ExternalLinkGuard();

      final status = await guard.open(
        actions: actions,
        rawUrl: 'http://wbp.example.gov.in/notice.pdf',
      );

      expect(status, LinkOpenStatus.invalid);
      expect(actions.opened, isEmpty);
    });

    test('synchronous launcher failures become a value', () async {
      final actions = FakeActions(openThrowsSync: true);
      final status = await ExternalLinkGuard().open(
        actions: actions,
        rawUrl: 'https://wbp.example.gov.in/notice.pdf',
      );
      expect(status, LinkOpenStatus.failed);
    });

    test('asynchronous launcher failures become a value', () async {
      final actions = FakeActions(openThrowsAsync: true);
      final status = await ExternalLinkGuard().open(
        actions: actions,
        rawUrl: 'https://wbp.example.gov.in/notice.pdf',
      );
      expect(status, LinkOpenStatus.failed);
    });

    test('a duplicate URL while pending is suppressed', () async {
      final actions = FakeActions(openDelay: const Duration(milliseconds: 200));
      final guard = ExternalLinkGuard();
      const url = 'https://wbp.example.gov.in/notice.pdf';

      final first = guard.open(actions: actions, rawUrl: url);
      final second = await guard.open(actions: actions, rawUrl: url);
      final firstStatus = await first;

      expect(firstStatus, LinkOpenStatus.opened);
      expect(second, LinkOpenStatus.duplicate);
      expect(actions.opened, hasLength(1));
      expect(guard.isPending(url), isFalse);
    });
  });

  group('JobDetail external links', () {
    testWidgets('safe notice and source links open through AppActions', (
      tester,
    ) async {
      final job = makeJob();
      final actions = FakeActions();
      await pumpScreen(
        tester,
        detail(job, actions),
        surfaceSize: const Size(500, 1800),
      );

      await tester.tap(find.text('মূল বিজ্ঞপ্তি খুলুন'));
      await tester.pumpAndSettle();
      expect(actions.opened, [Uri.parse(job.noticeUrl)]);

      await tester.tap(find.text('সরকারি সূত্র দেখুন'));
      await tester.pumpAndSettle();
      expect(actions.opened.last, Uri.parse(job.sourceUrl));
    });

    testWidgets('unsafe notice URL is refused before AppActions', (
      tester,
    ) async {
      final job = jobWithLinks(noticeUrl: 'http://wbp.example.gov.in/x.pdf');
      final actions = FakeActions();
      await pumpScreen(
        tester,
        detail(job, actions),
        surfaceSize: const Size(500, 1800),
      );

      await tester.tap(find.text('মূল বিজ্ঞপ্তি খুলুন'));
      await tester.pumpAndSettle();

      expect(actions.opened, isEmpty);
      expect(find.text(K.linkUnsafe.bn), findsOneWidget);
    });

    testWidgets('embedded credentials are never launched', (tester) async {
      final job = jobWithLinks(
        noticeUrl: 'https://user:pw@wbp.example.gov.in/x.pdf',
      );
      final actions = FakeActions();
      await pumpScreen(
        tester,
        detail(job, actions),
        surfaceSize: const Size(500, 1800),
      );

      await tester.tap(find.text('মূল বিজ্ঞপ্তি খুলুন'));
      await tester.pumpAndSettle();
      expect(actions.opened, isEmpty);
      expect(find.text(K.linkUnsafe.bn), findsOneWidget);

      await tester.tap(find.text('সরকারি সূত্র দেখুন'));
      await tester.pumpAndSettle();
      // The source URL of this fixture is still safe and must still open.
      expect(actions.opened, hasLength(1));
    });

    testWidgets('apply link with a fragment is refused', (tester) async {
      final job = makeJob(applyUrl: 'https://apply.example.gov.in/form#step-2');
      final actions = FakeActions();
      await pumpScreen(
        tester,
        detail(job, actions),
        surfaceSize: const Size(500, 1800),
      );

      await tester.tap(find.text('অনলাইনে আবেদন করুন'));
      await tester.pumpAndSettle();
      expect(actions.opened, isEmpty);
      expect(find.text(K.linkUnsafe.bn), findsOneWidget);
    });

    testWidgets('English users get English refusal copy', (tester) async {
      appLanguage.value = AppLang.en;
      final job = jobWithLinks(noticeUrl: 'javascript:alert(1)');
      final actions = FakeActions();
      await pumpScreen(
        tester,
        detail(job, actions),
        surfaceSize: const Size(500, 2000),
      );

      await tester.tap(find.text('Open original notice'));
      await tester.pumpAndSettle();

      expect(actions.opened, isEmpty);
      expect(find.text(K.linkUnsafe.en), findsOneWidget);
      expect(find.text(K.linkUnsafe.bn), findsNothing);
    });

    testWidgets('async launcher failure shows localized feedback', (
      tester,
    ) async {
      final job = makeJob();
      final actions = FakeActions(openThrowsAsync: true);
      await pumpScreen(
        tester,
        detail(job, actions),
        surfaceSize: const Size(500, 1800),
      );

      await tester.tap(find.text('মূল বিজ্ঞপ্তি খুলুন'));
      await tester.pumpAndSettle();

      expect(actions.opened, isEmpty);
      expect(find.text(K.linkOpenFailed.bn), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sync launcher failure shows localized feedback', (
      tester,
    ) async {
      final job = makeJob();
      final actions = FakeActions(openThrowsSync: true);
      await pumpScreen(
        tester,
        detail(job, actions),
        surfaceSize: const Size(500, 1800),
      );

      await tester.tap(find.text('মূল বিজ্ঞপ্তি খুলুন'));
      await tester.pumpAndSettle();

      expect(find.text(K.linkOpenFailed.bn), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rapid taps on one link launch it exactly once', (
      tester,
    ) async {
      final job = makeJob();
      final actions = FakeActions(openDelay: const Duration(milliseconds: 400));
      await pumpScreen(
        tester,
        detail(job, actions),
        surfaceSize: const Size(500, 1800),
      );

      await tester.tap(find.text('মূল বিজ্ঞপ্তি খুলুন'));
      await tester.pump(const Duration(milliseconds: 20));
      // Second and third taps land on the disabled (pending) button.
      await tester.tap(find.text('মূল বিজ্ঞপ্তি খুলুন'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('মূল বিজ্ঞপ্তি খুলুন'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(actions.opened, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a pending link does not block save or reminder actions', (
      tester,
    ) async {
      final job = makeJob();
      final actions = FakeActions(openDelay: const Duration(milliseconds: 400));
      final prefs = FakePreferences();
      await pumpScreen(
        tester,
        detail(job, actions, prefs: prefs),
        surfaceSize: const Size(500, 1800),
      );

      await tester.tap(find.text('মূল বিজ্ঞপ্তি খুলুন'));
      await tester.pump(const Duration(milliseconds: 20));

      // Bookmark still works while the launcher is pending.
      await tester.tap(find.byTooltip('সংরক্ষণ করুন'));
      await tester.pump();
      expect(prefs.savedCalls, [(job.id, true)]);

      // Reminder still works too.
      await tester.tap(find.widgetWithText(FilledButton, 'রিমাইন্ডার দিন'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(prefs.reminderCalls, [(job.id, true)]);
      expect(actions.opened, hasLength(1));
    });

    testWidgets('launcher completing after disposal throws nothing', (
      tester,
    ) async {
      final job = makeJob();
      final actions = FakeActions(openDelay: const Duration(milliseconds: 300));
      await pumpScreen(
        tester,
        detail(job, actions),
        surfaceSize: const Size(500, 1800),
      );

      await tester.tap(find.text('মূল বিজ্ঞপ্তি খুলুন'));
      await tester.pump(const Duration(milliseconds: 20));

      // The user navigates away before the launcher returns.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(actions.opened, hasLength(1));
    });

    testWidgets('failing launcher after disposal throws nothing', (
      tester,
    ) async {
      final job = makeJob();
      final actions = FakeActions(
        openDelay: const Duration(milliseconds: 300),
        openThrowsAsync: true,
      );
      await pumpScreen(
        tester,
        detail(job, actions),
        surfaceSize: const Size(500, 1800),
      );

      await tester.tap(find.text('মূল বিজ্ঞপ্তি খুলুন'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('reminder feedback is truthful', () {
    test('success copy describes a saved 24h request only', () {
      final en = K.reminderEnabledMsg.en.toLowerCase();
      final bn = K.reminderEnabledMsg.bn;
      expect(en, contains('saved'));
      expect(en, contains('24 hours before'));
      expect(en, contains('not'));
      for (final claim in [
        'scheduled',
        'delivered',
        'delivery',
        'guaranteed',
        'will notify',
        'device settings',
      ]) {
        expect(en, isNot(contains(claim)), reason: claim);
      }
      expect(bn, contains('২৪'));
      expect(bn, contains('সংরক্ষণ'));
      // Negated guarantee wording is allowed; an affirmative claim is not.
      expect(bn, contains('নিশ্চিত নয়'));
      expect(bn, isNot(contains('পাঠানো হয়েছে')));
    });

    test('disabling never claims OS cancellation', () {
      final en = K.reminderDisabledMsg.en.toLowerCase();
      final bn = K.reminderDisabledMsg.bn;
      expect(en, contains('removed'));
      expect(en, isNot(contains('cancelled')));
      expect(en, isNot(contains('canceled')));
      expect(bn, contains('মুছে'));
      expect(bn, isNot(contains('বাতিল করা হয়েছে')));
    });

    test('denied, permission error and storage failure stay distinct', () {
      final messages = {
        K.reminderDeniedMsg.en,
        K.reminderPermissionErrorMsg.en,
        K.reminderFailedMsg.en,
        K.reminderClosedMsg.en,
        K.reminderNoDeadlineMsg.en,
      };
      expect(messages, hasLength(5));
      expect(K.reminderDeniedMsg.en.toLowerCase(), contains('not granted'));
      expect(
        K.reminderPermissionErrorMsg.en.toLowerCase(),
        contains('could not be checked'),
      );
      expect(
        K.reminderFailedMsg.en.toLowerCase(),
        contains('could not be saved'),
      );
      expect(
        reminderOutcomeMessage(ReminderOutcome.permissionError).en,
        K.reminderPermissionErrorMsg.en,
      );
      expect(
        reminderOutcomeMessage(ReminderOutcome.permissionDenied).en,
        K.reminderDeniedMsg.en,
      );
    });

    test('policy copy states 24h-before and no catch-up in both languages', () {
      final en = K.reminderPolicyHelp.en.toLowerCase();
      final bn = K.reminderPolicyHelp.bn;
      expect(en, contains('24 hours before'));
      expect(en, contains('still ahead'));
      expect(en, contains('catch-up'));
      expect(en, contains('does not create'));
      expect(bn, contains('২৪'));
      expect(bn, contains('ভবিষ্যতে'));
      expect(
        K.reminderSheetPolicy.en.toLowerCase(),
        contains('24 hours before'),
      );
    });

    test('permission channel exception is not reported as denial', () async {
      final job = makeJob();
      final prefs = FakePreferences();
      final actions = FakeActions(permissionThrows: true);

      final outcome = await setReminderIntent(
        preferences: prefs,
        actions: actions,
        jobId: job.id,
        enable: true,
        deadline: deadlineInfo(job, DateTime.now()),
      );

      expect(outcome, ReminderOutcome.permissionError);
      expect(prefs.reminderCalls, isEmpty);
    });
  });

  group('reminder panel state', () {
    testWidgets('policy help is visible before enabling', (tester) async {
      final job = makeJob();
      await pumpScreen(
        tester,
        detail(job, FakeActions()),
        surfaceSize: const Size(500, 1800),
      );

      expect(find.text(K.reminderPolicyHelp.bn), findsOneWidget);
    });

    testWidgets('a stored intent can be turned off after the job closed', (
      tester,
    ) async {
      final job = makeJob(status: JobStatus.closed);
      final prefs = FakePreferences(reminders: {job.id});
      await pumpScreen(
        tester,
        detail(job, FakeActions(), prefs: prefs),
        surfaceSize: const Size(500, 1800),
      );

      await tester.tap(find.text('রিমাইন্ডার চালু'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(prefs.reminderCalls, [(job.id, false)]);
      expect(find.text(K.reminderDisabledMsg.bn), findsOneWidget);
    });

    testWidgets(
      'permission completion after unmount persists intent without widget callback',
      (tester) async {
        final job = makeJob();
        final prefs = FakePreferences();
        final actions = FakeActions(
          permissionDelay: const Duration(milliseconds: 300),
        );
        await pumpScreen(
          tester,
          detail(job, actions, prefs: prefs),
          surfaceSize: const Size(500, 1800),
        );

        await tester.tap(find.widgetWithText(FilledButton, 'রিমাইন্ডার দিন'));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();

        expect(tester.takeException(), isNull);
        // The permission request finishes after disposal. The user intent is
        // still persisted; widget disposal is not a controller cancellation.
        expect(prefs.reminderCalls, [(job.id, true)]);
        expect(actions.permissionRequests, 1);
      },
    );

    testWidgets('rapid taps request permission only once', (tester) async {
      final job = makeJob();
      final prefs = FakePreferences();
      final actions = FakeActions(
        permissionDelay: const Duration(milliseconds: 300),
      );
      await pumpScreen(
        tester,
        detail(job, actions, prefs: prefs),
        surfaceSize: const Size(500, 1800),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'রিমাইন্ডার দিন'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(
        find.widgetWithText(FilledButton, 'রিমাইন্ডার দিন'),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();

      expect(actions.permissionRequests, 1);
      expect(prefs.reminderCalls, [(job.id, true)]);
    });
  });

  group('320px at 2x text', () {
    for (final entry in {AppLang.bn: 'bn', AppLang.en: 'en'}.entries) {
      testWidgets('link buttons and policy help fit (${entry.value})', (
        tester,
      ) async {
        appLanguage.value = entry.key;
        final job = makeJob(applyUrl: 'https://apply.example.gov.in/form');
        await pumpScreen(
          tester,
          detail(job, FakeActions()),
          surfaceSize: const Size(320, 720),
          textScale: 2.0,
        );
        expect(tester.takeException(), isNull);

        // Reminder control and policy help, reached by scrolling at 2x.
        final reminderButton = find.widgetWithText(
          FilledButton,
          K.reminderOff.inLang(entry.key),
        );
        await tester.scrollUntilVisible(
          reminderButton,
          240,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.getSize(reminderButton).height, greaterThanOrEqualTo(48));
        expect(
          find.text(K.reminderPolicyHelp.inLang(entry.key)),
          findsOneWidget,
        );

        // Scroll to the link section at 2x text.
        final notice = find.text(K.openNotice.inLang(entry.key));
        await tester.scrollUntilVisible(
          notice,
          240,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          tester
              .getSize(
                find
                    .ancestor(of: notice, matching: find.byType(FilledButton))
                    .first,
              )
              .height,
          greaterThanOrEqualTo(48),
        );

        final scrollable = find.byType(Scrollable).first;
        for (var i = 0; i < 20; i++) {
          await tester.drag(scrollable, const Offset(0, -260));
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}
