import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/contracts/job_repository.dart';
import 'package:karmopath/features/calendar/calendar_screen.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/common/palette.dart';
import 'package:karmopath/features/home/home_screen.dart';
import 'package:karmopath/features/job_detail/job_detail_screen.dart';
import 'package:karmopath/features/saved/saved_screen.dart';
import 'package:karmopath/features/settings/settings_screen.dart';

import 'support/fakes.dart';

/// 320 CSS px wide at 2x text: the smallest supported phone with the largest
/// text the design must survive. Every screen is scrolled end to end so that
/// off-screen rows are laid out too.
const Size phone320 = Size(320, 720);
const double textScale2x = 2.0;

void main() {
  setUp(() => appLanguage.value = AppLang.bn);
  tearDown(() => appLanguage.value = AppLang.bn);

  final longTitleBn =
      'পশ্চিমবঙ্গ পুলিশ ভাইস প্রেসিডেন্ট ও নিরাপত্তা বিভাগে বিশাল নিয়োগ '
      'নতুন নিয়ম ও আবেদনের সম্পূর্ণ নির্দেশিকা';
  final longTitleEn =
      'West Bengal Police Recruitment Board invites applications for '
      'Constable, Sub-Inspector and Lady Constable posts across all districts';
  final longJob = makeJob(
    id: 'long-title-job',
    titleBn: longTitleBn,
    titleEn: longTitleEn,
    organization:
        'West Bengal Police Recruitment Board, Aravind Building, Kolkata',
    districts: const ['Kolkata', 'Howrah', 'Darjeeling', 'West Bengal'],
    qualifications: const ['Madhyamik or equivalent from a recognised board'],
    summaryBn: 'মূল বিজ্ঞপ্তি অনুযায়ী যোগ্যতা যাচাই করে আবেদন করুন। ' * 3,
    summaryEn:
        'Verify eligibility in the original notice before applying. ' * 3,
    howToApplyBn: 'অনলাইনে আবেদন করুন এবং রসিদ সংরক্ষণ করুন। ' * 3,
    howToApplyEn: 'Apply online and keep the receipt. ' * 3,
    applicationEndAt: utcNow().add(const Duration(days: 2)),
  );
  final otherJob = makeJob(
    id: 'second-job',
    titleBn: 'স্বাস্থ্য দপ্তরে স্টাফ নার্স নিয়োগ',
    districts: const ['Darjeeling'],
    qualifications: const ['B.Sc Nursing'],
    category: JobCategory.medical,
  );

  Widget home(FakeJobRepository repo, FakePreferences prefs) =>
      HomeScreen(repository: repo, preferences: prefs, onOpenJob: (_) {});

  /// Drags the vertical list through the whole page, so lazily built rows are
  /// laid out and any overflow surfaces.
  Future<void> scrollThrough(WidgetTester tester) async {
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isEmpty) return;
    final state = tester.state<ScrollableState>(scrollable.first);
    for (var i = 0; i < 14; i++) {
      await tester.drag(scrollable.first, const Offset(0, -260));
      await tester.pump();
      if (state.position.pixels >= state.position.maxScrollExtent - 1) break;
    }
    await tester.pump();
  }

  void expectNoOverflow(WidgetTester tester) {
    expect(tester.takeException(), isNull);
  }

  /// WCAG-style target check: a tap target must be at least 48x48.
  void expectMinTarget(WidgetTester tester, Finder finder, String label) {
    final elements = finder.evaluate();
    expect(elements, isNotEmpty, reason: 'no widget found for $label');
    for (final element in elements) {
      final renderObject = element.renderObject;
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      expect(
        renderObject.size.width,
        greaterThanOrEqualTo(48),
        reason: '$label width',
      );
      expect(
        renderObject.size.height,
        greaterThanOrEqualTo(48),
        reason: '$label height',
      );
    }
  }

  group('320px at 2x text', () {
    testWidgets('home renders, scrolls and keeps 48dp targets', (tester) async {
      final prefs = FakePreferences(saved: {longJob.id});
      await pumpScreen(
        tester,
        home(FakeJobRepository(readyState([longJob, otherJob])), prefs),
        surfaceSize: phone320,
        textScale: textScale2x,
      );
      expectNoOverflow(tester);

      expectMinTarget(tester, find.byType(IconButton).first, 'header icon');

      final allChip = find.byWidgetPredicate(
        (w) => w is HomeFilterChip && w.label == 'সব',
      );
      await tester.scrollUntilVisible(
        allChip,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expectMinTarget(tester, allChip, 'filter chip');

      await scrollThrough(tester);
      expectNoOverflow(tester);
    });

    testWidgets('notification sheet survives 2x text', (tester) async {
      final prefs = FakePreferences(
        reminders: {longJob.id, 'ghost-reminder-id'},
      );
      await pumpScreen(
        tester,
        home(FakeJobRepository(readyState([longJob, otherJob])), prefs),
        surfaceSize: phone320,
        textScale: textScale2x,
      );

      await tester.tap(find.byTooltip('নোটিফিকেশন'));
      await tester.pumpAndSettle();
      expectNoOverflow(tester);

      expect(find.text('নোটিফিকেশন'), findsWidgets);
      expect(find.text('২টি রিমাইন্ডার চালু'), findsOneWidget);

      // The missing id is listed as unavailable; scroll the sheet list to it.
      final ghost = find.text('এই চাকরির তথ্য আর নেই');
      await tester.scrollUntilVisible(
        ghost,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(ghost, findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('job detail renders all sections without overflow', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        JobDetailScreen(
          job: longJob,
          preferences: FakePreferences(),
          actions: FakeActions(),
        ),
        surfaceSize: phone320,
        textScale: textScale2x,
      );
      expectNoOverflow(tester);

      expectMinTarget(tester, find.byType(IconButton).first, 'bookmark');

      final reminder = find.widgetWithText(FilledButton, 'রিমাইন্ডার দিন');
      await tester.scrollUntilVisible(
        reminder,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expectMinTarget(tester, reminder, 'reminder button');

      final disclaimer = find.textContaining(
        'independent information platform',
      );
      await tester.scrollUntilVisible(
        disclaimer,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(disclaimer, findsOneWidget);
      expectNoOverflow(tester);

      await scrollThrough(tester);
      expectNoOverflow(tester);
    });

    testWidgets('saved renders mixed saved and unavailable rows', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        SavedScreen(
          repository: FakeJobRepository(readyState([longJob])),
          preferences: FakePreferences(saved: {longJob.id, 'ghost-job'}),
          onOpenJob: (_) {},
        ),
        surfaceSize: phone320,
        textScale: textScale2x,
      );
      expectNoOverflow(tester);

      await scrollThrough(tester);
      expectNoOverflow(tester);
      expect(find.text('ghost-job'), findsOneWidget);
      expectMinTarget(
        tester,
        find.widgetWithText(TextButton, 'সরান'),
        'remove action',
      );
    });

    testWidgets('calendar renders mixed deadlines without overflow', (
      tester,
    ) async {
      final past = makeJob(
        id: 'past-job',
        titleBn: 'পুরোনো নিয়োগ',
        applicationEndDate: dateOnly(
          utcNow().subtract(const Duration(days: 5)),
        ),
      );
      await pumpScreen(
        tester,
        CalendarScreen(
          repository: FakeJobRepository(
            JobFeedState(
              feed: makeFeed([longJob, otherJob, past]),
              isOffline: true,
            ),
          ),
          preferences: FakePreferences(reminders: {longJob.id}),
          onOpenJob: (_) {},
        ),
        surfaceSize: phone320,
        textScale: textScale2x,
      );
      expectNoOverflow(tester);

      expectMinTarget(
        tester,
        find
            .byWidgetPredicate((w) => w.runtimeType.toString() == '_Segment')
            .first,
        'scope segment',
      );

      expect(find.text('আপনি অফলাইনে'), findsOneWidget);
      await scrollThrough(tester);
      expectNoOverflow(tester);
    });

    testWidgets('settings renders disabled links without overflow', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        SettingsScreen(actions: FakeActions()),
        surfaceSize: phone320,
        textScale: textScale2x,
      );
      expectNoOverflow(tester);

      await scrollThrough(tester);
      expectNoOverflow(tester);

      final tiles = find.byType(ListTile);
      expect(tiles, findsNWidgets(5));
      for (final tile in tester.widgetList<ListTile>(tiles)) {
        expect(tile.enabled, isFalse);
      }
      expectMinTarget(tester, tiles.first, 'disabled link row');
    });
  });

  group('coral contrast', () {
    test('text-bearing coral surfaces reach WCAG AA', () {
      // White on the darkened coral: safe for small labels.
      expect(
        KPalette.contrastRatio(Colors.white, KPalette.coralStrong),
        greaterThanOrEqualTo(4.5),
      );
      // The decorative brand coral alone fails with white text; that is why
      // the darkened token exists for text-bearing surfaces.
      expect(
        KPalette.contrastRatio(Colors.white, KPalette.coral),
        lessThan(4.5),
      );
      // Ink on brand coral is the other compliant pairing the design allows.
      expect(
        KPalette.contrastRatio(KarmopathThemeInk.value, KPalette.coral),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets('urgent deadline pill uses the contrast-safe coral', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        home(FakeJobRepository(readyState([longJob])), FakePreferences()),
        surfaceSize: const Size(420, 1200),
      );

      final pill = tester.widgetList<Container>(find.byType(Container)).where((
        widget,
      ) {
        final decoration = widget.decoration;
        return decoration is BoxDecoration &&
            decoration.color == KPalette.coralStrong;
      });
      expect(pill, isNotEmpty);
    });
  });
}

/// Local ink colour so the test does not reach into the theme for a constant.
abstract final class KarmopathThemeInk {
  static const Color value = Color(0xFF1F2937);
}
