import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/job_detail/job_detail_screen.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => appLanguage.value = AppLang.bn);
  tearDown(() => appLanguage.value = AppLang.bn);

  Widget detail(Job job, FakePreferences prefs, FakeActions actions) =>
      JobDetailScreen(job: job, preferences: prefs, actions: actions);

  testWidgets('renders structured detail and the independence disclaimer', (
    tester,
  ) async {
    final job = makeJob();
    await pumpScreen(tester, detail(job, FakePreferences(), FakeActions()));

    expect(find.text('চাকরির বিবরণ'), findsOneWidget);
    expect(find.text(job.titleBn), findsOneWidget);
    expect(find.text(job.organization), findsOneWidget);
    expect(find.text(job.summaryBn), findsOneWidget);
    await scrollTo(
      tester,
      find.textContaining('independent information platform'),
    );
    expect(
      find.textContaining('independent information platform'),
      findsOneWidget,
    );
    expect(find.textContaining('স্বাধীন তথ্যপ্ল্যাটফর্ম'), findsOneWidget);
  });

  testWidgets('official notice and source open through AppActions', (
    tester,
  ) async {
    final job = makeJob();
    final actions = FakeActions();
    await pumpScreen(tester, detail(job, FakePreferences(), actions));

    await scrollTo(tester, find.text('মূল বিজ্ঞপ্তি খুলুন'));
    await tester.tap(find.text('মূল বিজ্ঞপ্তি খুলুন'));
    await tester.pump();
    expect(actions.opened, [Uri.parse(job.noticeUrl)]);

    await scrollTo(tester, find.text('সরকারি সূত্র দেখুন'));
    await tester.tap(find.text('সরকারি সূত্র দেখুন'));
    await tester.pump();
    expect(actions.opened.last, Uri.parse(job.sourceUrl));
  });

  testWidgets('apply button only exists when the feed carries apply_url', (
    tester,
  ) async {
    final without = makeJob();
    await pumpScreen(tester, detail(without, FakePreferences(), FakeActions()));
    expect(find.text('অনলাইনে আবেদন করুন'), findsNothing);

    final withUrl = makeJob(applyUrl: 'https://apply.example.gov.in/form');
    final actions = FakeActions();
    await pumpScreen(tester, detail(withUrl, FakePreferences(), actions));
    await scrollTo(tester, find.text('অনলাইনে আবেদন করুন'));
    await tester.tap(find.text('অনলাইনে আবেদন করুন'));
    await tester.pump();
    expect(actions.opened, [Uri.parse('https://apply.example.gov.in/form')]);
  });

  testWidgets('denied permission never schedules a reminder', (tester) async {
    final job = makeJob();
    final prefs = FakePreferences();
    final actions = FakeActions(permission: false);
    await pumpScreen(tester, detail(job, prefs, actions));

    await tester.tap(find.text('রিমাইন্ডার দিন'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(actions.permissionRequests, 1);
    expect(prefs.reminderCalls, isEmpty);
    expect(find.textContaining('অনুমতি পাওয়া যায়নি'), findsOneWidget);
  });

  testWidgets('granted permission persists the reminder intent', (
    tester,
  ) async {
    final job = makeJob();
    final prefs = FakePreferences();
    final actions = FakeActions();
    await pumpScreen(tester, detail(job, prefs, actions));

    await tester.tap(find.text('রিমাইন্ডার দিন'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(actions.permissionRequests, 1);
    expect(prefs.reminderCalls, [(job.id, true)]);
    expect(find.text('রিমাইন্ডার চালু'), findsOneWidget);
  });

  testWidgets('turning an existing reminder off needs no permission', (
    tester,
  ) async {
    final job = makeJob();
    final prefs = FakePreferences(reminders: {job.id});
    final actions = FakeActions();
    await pumpScreen(tester, detail(job, prefs, actions));

    await tester.tap(find.text('রিমাইন্ডার চালু'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(actions.permissionRequests, 0);
    expect(prefs.reminderCalls, [(job.id, false)]);
  });

  testWidgets(
    'stale open status still shows the closed banner and blocks reminders',
    (tester) async {
      final past = utcNow().subtract(const Duration(days: 2));
      final job = makeJob(
        applicationEndDate: dateOnly(past),
        status: JobStatus.open,
      );
      await pumpScreen(tester, detail(job, FakePreferences(), FakeActions()));

      expect(
        find.text('আবেদনের সময় শেষ। তথ্য রেফারেন্সের জন্য রাখা হয়েছে।'),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'রিমাইন্ডার দিন'),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets('withdrawn jobs show the withdrawn banner', (tester) async {
    final job = makeJob(status: JobStatus.withdrawn);
    await pumpScreen(tester, detail(job, FakePreferences(), FakeActions()));

    expect(
      find.text('এই নিয়োগ প্রত্যাহার করা হয়েছে। আবেদন করবেন না।'),
      findsOneWidget,
    );
  });

  testWidgets('correction action is visibly unavailable, not fabricated', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      detail(makeJob(), FakePreferences(), FakeActions()),
    );

    await scrollTo(tester, find.text('সংশোধন জানান'));
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'সংশোধন জানান · এখনো চালু হয়নি'),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('কোনো ঠিকানা বানানো হয়নি'), findsOneWidget);
  });

  testWidgets('no deadline disables reminders and states why', (tester) async {
    final job = makeJob(
      id: 'wb-police-result-2026',
      kind: JobKind.result,
      status: JobStatus.published,
      hasDeadline: false,
      applicationEndAt: null,
    );
    final prefs = FakePreferences();
    final actions = FakeActions();
    await pumpScreen(tester, detail(job, prefs, actions));

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'রিমাইন্ডার দিন'),
    );
    expect(button.onPressed, isNull);
    expect(
      find.text(
        'এই আপডেটে কোনো আবেদনের শেষ তারিখ নেই, তাই রিমাইন্ডার দেওয়া যায় না।',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('রিমাইন্ডার দিন'));
    await tester.pump();
    expect(actions.permissionRequests, 0);
    expect(prefs.reminderCalls, isEmpty);
  });

  testWidgets('an existing intent on a no-deadline job can still be disabled', (
    tester,
  ) async {
    final job = makeJob(
      id: 'wb-police-result-2026',
      kind: JobKind.result,
      status: JobStatus.published,
      hasDeadline: false,
      applicationEndAt: null,
    );
    final prefs = FakePreferences(reminders: {job.id});
    final actions = FakeActions();
    await pumpScreen(tester, detail(job, prefs, actions));

    await tester.tap(find.text('রিমাইন্ডার চালু'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(actions.permissionRequests, 0);
    expect(prefs.reminderCalls, [(job.id, false)]);
  });

  testWidgets('success copy promises a saved request, not delivery', (
    tester,
  ) async {
    final job = makeJob();
    await pumpScreen(tester, detail(job, FakePreferences(), FakeActions()));

    await tester.tap(find.text('রিমাইন্ডার দিন'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.textContaining('রিমাইন্ডারের অনুরোধ সংরক্ষণ করা হয়েছে'),
      findsOneWidget,
    );
    // No delivery guarantee is implied by the snackbar copy.
    expect(find.textContaining('নিশ্চিত নয়'), findsOneWidget);
  });

  testWidgets(
    'server-closed page keeps the scheduled deadline, no closure time',
    (tester) async {
      final job = makeJob(
        status: JobStatus.closed,
        applicationEndDate: '2026-12-31',
      );
      // Tall surface so the whole detail page is built for inspection.
      await pumpScreen(
        tester,
        detail(job, FakePreferences(), FakeActions()),
        surfaceSize: const Size(500, 1800),
      );

      // Generic banner — no invented "closed on" moment.
      expect(find.textContaining('আবেদনের সময় শেষ'), findsOneWidget);
      expect(find.textContaining('বন্ধ হয়েছে'), findsNothing);
      // The scheduled date stays visible in the dates section (rich text row).
      expect(find.textContaining('৩১ ডিসেম্বর ২০২৬'), findsOneWidget);
    },
  );

  testWidgets('notice card links to the original and offers no reminder', (
    tester,
  ) async {
    final notice = makeJob(
      kind: JobKind.notice,
      status: JobStatus.published,
      hasDeadline: false,
      qualifications: const [],
      vacancies: null,
      summaryBn: 'সরকারি সাইটে প্রকাশিত বিজ্ঞপ্তি। যোগ্যতা যাচাই করা হয়নি।',
      summaryEn: 'Official notice. Eligibility was not checked here.',
    );
    final actions = FakeActions();
    await pumpScreen(
      tester,
      detail(notice, FakePreferences(), actions),
      surfaceSize: const Size(500, 1800),
    );

    expect(find.text(notice.titleBn), findsOneWidget);
    expect(find.text(notice.summaryBn), findsOneWidget);
    // A notice has no deadline, so no reminder is offered and no dates
    // section claims one.
    expect(find.text('রিমাইন্ডার দিন'), findsNothing);
    expect(find.text('গুরুত্বপূর্ণ তারিখ'), findsNothing);

    await scrollTo(tester, find.text('মূল বিজ্ঞপ্তি খুলুন'));
    await tester.tap(find.text('মূল বিজ্ঞপ্তি খুলুন'));
    await tester.pump();
    expect(actions.opened, [Uri.parse(notice.noticeUrl)]);
  });

  testWidgets('app-bar bookmark writes through preferences', (tester) async {
    final job = makeJob();
    final prefs = FakePreferences();
    await pumpScreen(tester, detail(job, prefs, FakeActions()));

    await tester.tap(find.byTooltip('সংরক্ষণ করুন'));
    await tester.pump();
    expect(prefs.savedCalls, [(job.id, true)]);
  });

  testWidgets('English fallback renders when the language switches', (
    tester,
  ) async {
    appLanguage.value = AppLang.en;
    final job = makeJob();
    await pumpScreen(tester, detail(job, FakePreferences(), FakeActions()));

    expect(find.text('Job details'), findsOneWidget);
    expect(find.text(job.titleEn), findsOneWidget);
    expect(find.text('Remind me'), findsOneWidget);
  });
}
