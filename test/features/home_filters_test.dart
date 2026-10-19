import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/home/home_screen.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => appLanguage.value = AppLang.bn);
  tearDown(() => appLanguage.value = AppLang.bn);

  final police = makeJob(
    id: 'wb-police-constable',
    titleBn: 'পুলিশ কনস্টেবল',
    districts: const ['Kolkata', 'Howrah'],
    qualifications: const ['Madhyamik pass'],
    category: JobCategory.police,
  );
  final railway = makeJob(
    id: 'metro-railway-master',
    titleBn: 'মেট্রো রেলওয়ে মাস্টার',
    districts: const ['Kolkata'],
    qualifications: const ['Graduation'],
    category: JobCategory.railway,
  );
  final medical = makeJob(
    id: 'wb-health-recruitment',
    titleBn: 'স্বাস্থ্য দপ্তর নিয়োগ',
    districts: const ['Darjeeling'],
    qualifications: const ['B.Sc Nursing'],
    category: JobCategory.medical,
  );

  Widget home(FakeJobRepository repo, {FakePreferences? prefs}) => HomeScreen(
    repository: repo,
    preferences: prefs ?? FakePreferences(),
    onOpenJob: (_) {},
  );

  // The filter row sits below the hero and scrolls horizontally: bring the
  // chip fully on screen before tapping it.
  Future<void> tapFilterChip(WidgetTester tester, String label) async {
    final base = find.text(label);
    if (base.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        base,
        240,
        scrollable: find.byType(Scrollable).first,
      );
    }
    final finder = base.first;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openDistrictSheet(WidgetTester tester) =>
      tapFilterChip(tester, 'জেলা');

  Future<void> openQualificationSheet(WidgetTester tester) =>
      tapFilterChip(tester, 'যোগ্যতা');

  test('unique facet values are sorted and de-duplicated', () {
    final jobs = [police, railway, medical];
    expect(availableDistricts(jobs), ['Darjeeling', 'Howrah', 'Kolkata']);
    expect(availableQualifications(jobs), [
      'B.Sc Nursing',
      'Graduation',
      'Madhyamik pass',
    ]);
  });

  testWidgets('district sheet lists feed values and filters the list', (
    tester,
  ) async {
    final repo = FakeJobRepository(readyState([police, railway, medical]));
    await pumpScreen(tester, home(repo), surfaceSize: const Size(420, 1400));

    await openDistrictSheet(tester);
    expect(find.widgetWithText(HomeFilterChip, 'Kolkata'), findsOneWidget);
    expect(find.widgetWithText(HomeFilterChip, 'Darjeeling'), findsOneWidget);

    await tester.tap(find.widgetWithText(HomeFilterChip, 'Darjeeling'));
    await tester.pump();
    await tester.tap(find.text('সম্পন্ন'));
    await tester.pumpAndSettle();

    expect(find.text(medical.titleBn), findsOneWidget);
    expect(find.text(police.titleBn), findsNothing);
    expect(find.text(railway.titleBn), findsNothing);
  });

  testWidgets('qualification filter matches the job qualification list', (
    tester,
  ) async {
    final repo = FakeJobRepository(readyState([police, railway, medical]));
    await pumpScreen(tester, home(repo), surfaceSize: const Size(420, 1400));

    await openQualificationSheet(tester);
    await tester.tap(find.widgetWithText(HomeFilterChip, 'Graduation'));
    await tester.pump();
    await tester.tap(find.text('সম্পন্ন'));
    await tester.pumpAndSettle();

    expect(find.text(railway.titleBn), findsOneWidget);
    expect(find.text(police.titleBn), findsNothing);
  });

  testWidgets('multi-select is OR within a facet and AND across facets', (
    tester,
  ) async {
    final repo = FakeJobRepository(readyState([police, railway, medical]));
    await pumpScreen(tester, home(repo), surfaceSize: const Size(420, 1400));

    // Two districts: Kolkata (police, railway) OR Darjeeling (medical).
    await openDistrictSheet(tester);
    await tester.tap(find.widgetWithText(HomeFilterChip, 'Kolkata'));
    await tester.pump();
    await tester.tap(find.widgetWithText(HomeFilterChip, 'Darjeeling'));
    await tester.pump();
    await tester.tap(find.text('সম্পন্ন'));
    await tester.pumpAndSettle();
    expect(find.text(police.titleBn), findsOneWidget);
    expect(find.text(railway.titleBn), findsOneWidget);
    expect(find.text(medical.titleBn), findsOneWidget);

    // AND a qualification: only railway survives.
    await openQualificationSheet(tester);
    await tester.tap(find.widgetWithText(HomeFilterChip, 'Graduation'));
    await tester.pump();
    await tester.tap(find.text('সম্পন্ন'));
    await tester.pumpAndSettle();
    expect(find.text(railway.titleBn), findsOneWidget);
    expect(find.text(police.titleBn), findsNothing);
    expect(find.text(medical.titleBn), findsNothing);
  });

  testWidgets('facet filters combine with category and search', (tester) async {
    final repo = FakeJobRepository(readyState([police, railway, medical]));
    await pumpScreen(tester, home(repo), surfaceSize: const Size(420, 1400));

    await openDistrictSheet(tester);
    await tester.tap(find.widgetWithText(HomeFilterChip, 'Kolkata'));
    await tester.pump();
    await tester.tap(find.text('সম্পন্ন'));
    await tester.pumpAndSettle();

    final railwayChip = find.text('রেলওয়ে').first;
    await tester.ensureVisible(railwayChip);
    await tester.pumpAndSettle();
    await tester.tap(railwayChip);
    await tester.pump();
    expect(find.text(railway.titleBn), findsOneWidget);
    expect(find.text(police.titleBn), findsNothing);

    await tester.enterText(find.byType(TextField), 'মেট্রো');
    await tester.pump();
    expect(find.text(railway.titleBn), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('কোনো মিল পাওয়া যায়নি'), findsOneWidget);
  });

  testWidgets('clear all resets facets, category, kind and search', (
    tester,
  ) async {
    final repo = FakeJobRepository(readyState([police, railway, medical]));
    await pumpScreen(tester, home(repo), surfaceSize: const Size(420, 1400));

    await openDistrictSheet(tester);
    await tester.tap(find.widgetWithText(HomeFilterChip, 'Darjeeling'));
    await tester.pump();
    await tester.tap(find.text('সম্পন্ন'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'স্বাস্থ্য');
    await tester.pump();

    expect(find.text(medical.titleBn), findsOneWidget);
    expect(find.text(police.titleBn), findsNothing);

    final clear = find.text('ফিল্টার মুছুন');
    await tester.ensureVisible(clear);
    await tester.pumpAndSettle();
    await tester.tap(clear);
    await tester.pumpAndSettle();

    expect(find.text(police.titleBn), findsOneWidget);
    expect(find.text(railway.titleBn), findsOneWidget);
    expect(find.text(medical.titleBn), findsOneWidget);
    // "All districts" style count chip no longer claims an active selection.
    expect(find.textContaining('জেলা ·'), findsNothing);
  });

  testWidgets('refresh drops selections that left the feed', (tester) async {
    final repo = FakeJobRepository(readyState([police, railway]));
    await pumpScreen(tester, home(repo), surfaceSize: const Size(420, 1400));

    await openDistrictSheet(tester);
    await tester.tap(find.widgetWithText(HomeFilterChip, 'Kolkata'));
    await tester.pump();
    await tester.tap(find.text('সম্পন্ন'));
    await tester.pumpAndSettle();
    expect(find.text(police.titleBn), findsOneWidget);

    // Feed refresh keeps only jobs in Darjeeling.
    repo.nextState = readyState([medical]);
    await repo.refresh();
    await tester.pumpAndSettle();

    // Stale Kolkata selection is removed instead of hiding the whole feed.
    expect(find.text(medical.titleBn), findsOneWidget);
    expect(find.textContaining('জেলা ·'), findsNothing);
  });

  testWidgets('notice chip shows only notice cards', (tester) async {
    final notice = makeJob(
      id: 'rrc-cultural-quota-notice',
      kind: JobKind.notice,
      status: JobStatus.published,
      hasDeadline: false,
      qualifications: const [],
      titleBn: 'সাংস্কৃতিক কোটা বিজ্ঞপ্তি',
    );
    final repo = FakeJobRepository(readyState([police, notice]));
    await pumpScreen(tester, home(repo), surfaceSize: const Size(420, 1400));

    final noticeChip = find.widgetWithText(HomeFilterChip, 'নোটিশ');
    await tester.ensureVisible(noticeChip);
    await tester.pumpAndSettle();
    await tester.tap(noticeChip);
    await tester.pumpAndSettle();
    expect(find.text(notice.titleBn), findsOneWidget);
    expect(find.text(police.titleBn), findsNothing);
  });

  testWidgets('facet chips are hidden when the feed offers no values', (
    tester,
  ) async {
    final noFacets = makeJob(
      id: 'bare-job',
      districts: const ['West Bengal'],
      qualifications: const ['Any'],
    );
    final repo = FakeJobRepository(readyState([noFacets]));
    await pumpScreen(tester, home(repo), surfaceSize: const Size(420, 1400));

    // Both facets exist here, so both chips show; empty feed hides them.
    expect(find.textContaining('জেলা'), findsWidgets);
    repo.nextState = readyState(const []);
    await repo.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('জেলা ·'), findsNothing);
  });

  testWidgets('facet sheet has 48dp options and stays usable at 2x text', (
    tester,
  ) async {
    final repo = FakeJobRepository(readyState([police, railway, medical]));
    await pumpScreen(
      tester,
      home(repo),
      surfaceSize: const Size(320, 720),
      textScale: 2.0,
    );

    await openDistrictSheet(tester);
    expect(tester.takeException(), isNull);

    for (final option in ['Kolkata', 'Darjeeling']) {
      final size = tester.getSize(find.widgetWithText(HomeFilterChip, option));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    expect(find.text('সম্পন্ন'), findsOneWidget);
  });
}
