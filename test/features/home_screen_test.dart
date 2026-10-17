import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/contracts/job_repository.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/home/home_screen.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => appLanguage.value = AppLang.bn);
  tearDown(() => appLanguage.value = AppLang.bn);

  final police = makeJob();
  final railway = makeJob(
    id: 'metro-railway-station-master-2026',
    titleBn: 'মেট্রো রেলওয়ে স্টেশন মাস্টার',
    titleEn: 'Metro Railway Station Master',
    organization: 'Metro Railway Kolkata',
    category: JobCategory.railway,
    districts: const ['Kolkata', 'Howrah'],
    qualifications: const ['Graduation'],
    vacancies: 50,
  );

  Widget home(
    FakeJobRepository repo,
    FakePreferences prefs, {
    void Function(String)? onOpen,
  }) {
    return HomeScreen(
      repository: repo,
      preferences: prefs,
      onOpenJob: onOpen ?? (_) {},
    );
  }

  testWidgets('renders header, hero, categories and job cards', (tester) async {
    final repo = FakeJobRepository(readyState([police, railway]));
    await pumpScreen(tester, home(repo, FakePreferences()));

    expect(find.text('Karmopath'), findsOneWidget);
    expect(find.textContaining('কোনো ডেডলাইন'), findsWidgets);
    expect(find.text('সাম্প্রতিক সুযোগ'), findsOneWidget);
    expect(find.text(police.titleBn), findsOneWidget);
    expect(find.text(railway.titleBn), findsOneWidget);
    expect(find.text('রেলওয়ে'), findsOneWidget);
  });

  testWidgets('search filters the visible jobs', (tester) async {
    final repo = FakeJobRepository(readyState([police, railway]));
    await pumpScreen(tester, home(repo, FakePreferences()));

    await tester.enterText(find.byType(TextField), 'metro');
    await tester.pump();

    expect(find.text(railway.titleEn), findsNothing); // Bengali mode
    expect(find.text(railway.titleBn), findsOneWidget);
    expect(find.text(police.titleBn), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text(police.titleBn), findsOneWidget);
  });

  testWidgets('category strip filters and toggles off', (tester) async {
    final repo = FakeJobRepository(readyState([police, railway]));
    await pumpScreen(tester, home(repo, FakePreferences()));

    await tester.tap(find.text('রেলওয়ে'));
    await tester.pump();
    expect(find.text(railway.titleBn), findsOneWidget);
    expect(find.text(police.titleBn), findsNothing);

    await tester.tap(find.text('রেলওয়ে'));
    await tester.pump();
    expect(find.text(police.titleBn), findsOneWidget);
  });

  testWidgets('closing-soon chip keeps only imminent deadlines', (
    tester,
  ) async {
    final soon = makeJob(
      id: 'closing-soon',
      titleBn: 'শেষ হচ্ছে শীঘ্রই',
      applicationEndAt: utcNow().add(const Duration(hours: 20)),
      status: JobStatus.open,
    );
    final later = makeJob(
      id: 'closing-later',
      titleBn: 'পরে শেষ হবে',
      applicationEndAt: utcNow().add(const Duration(days: 20)),
    );
    final repo = FakeJobRepository(readyState([soon, later]));
    await pumpScreen(tester, home(repo, FakePreferences()));

    await tester.tap(find.text('শেষ হচ্ছে'));
    await tester.pump();
    expect(find.text(soon.titleBn), findsOneWidget);
    expect(find.text(later.titleBn), findsNothing);
  });

  testWidgets('no matches shows an empty state with a clear action', (
    tester,
  ) async {
    final repo = FakeJobRepository(readyState([police]));
    await pumpScreen(tester, home(repo, FakePreferences()));

    await tester.enterText(find.byType(TextField), 'zzz-no-such-job');
    await tester.pump();
    expect(find.text('কোনো মিল পাওয়া যায়নি'), findsOneWidget);

    await scrollTo(tester, find.text('ফিল্টার মুছুন').last);
    await tester.tap(find.text('ফিল্টার মুছুন').last);
    await tester.pump();
    expect(find.text('কোনো মিল পাওয়া যায়নি'), findsNothing);
    await scrollTo(tester, find.text(police.titleBn));
    expect(find.text(police.titleBn), findsOneWidget);
  });

  testWidgets('loading state while the first feed is in flight', (
    tester,
  ) async {
    final repo = FakeJobRepository(const JobFeedState(isLoading: true));
    await pumpScreen(tester, home(repo, FakePreferences()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('লোড হচ্ছে…'), findsOneWidget);
  });

  testWidgets('error state offers retry and calls refresh', (tester) async {
    final repo = FakeJobRepository(
      const JobFeedState(lastError: 'network down'),
    );
    await pumpScreen(tester, home(repo, FakePreferences()));

    expect(find.text('তথ্য লোড করা যায়নি'), findsOneWidget);
    await scrollTo(tester, find.text('আবার চেষ্টা করুন'));
    await tester.tap(find.text('আবার চেষ্টা করুন'));
    await tester.pump();
    expect(repo.refreshCalls, 1);
  });

  testWidgets('first launch without network shows the empty state', (
    tester,
  ) async {
    final repo = FakeJobRepository(const JobFeedState());
    await pumpScreen(tester, home(repo, FakePreferences()));

    expect(find.text('কোনো সুযোগ পাওয়া যায়নি'), findsOneWidget);
  });

  testWidgets('empty published feed is a useful empty state', (tester) async {
    final repo = FakeJobRepository(readyState(const []));
    await pumpScreen(tester, home(repo, FakePreferences()));

    expect(find.text('কোনো সুযোগ পাওয়া যায়নি'), findsOneWidget);
  });

  testWidgets('offline banner keeps cached jobs visible', (tester) async {
    final repo = FakeJobRepository(
      JobFeedState(feed: makeFeed([police]), isOffline: true),
    );
    await pumpScreen(tester, home(repo, FakePreferences()));

    expect(find.text('আপনি অফলাইনে'), findsOneWidget);
    expect(find.text(police.titleBn), findsOneWidget);
  });

  testWidgets('bookmark writes through preferences', (tester) async {
    final prefs = FakePreferences();
    final repo = FakeJobRepository(readyState([police]));
    await pumpScreen(tester, home(repo, prefs));

    await tester.tap(find.byTooltip('সংরক্ষণ করুন'));
    await tester.pump();

    expect(prefs.savedCalls, [(police.id, true)]);
    expect(find.byTooltip('সংরক্ষণ বাতিল'), findsOneWidget);
  });

  testWidgets('tapping a card reports the job id', (tester) async {
    String? opened;
    final repo = FakeJobRepository(readyState([police, railway]));
    await pumpScreen(
      tester,
      home(repo, FakePreferences(), onOpen: (id) => opened = id),
    );

    await tester.tap(find.text(railway.titleBn));
    await tester.pump();
    expect(opened, railway.id);
  });

  testWidgets('renders at 320px with large text without layout overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final repo = FakeJobRepository(readyState([police, railway]));
    await pumpScreen(
      tester,
      home(repo, FakePreferences()),
      surfaceSize: const Size(320, 900),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Karmopath'), findsOneWidget);
    expect(find.text(police.titleBn), findsOneWidget);
  });

  testWidgets('bell opens reminder preferences without invented counts', (
    tester,
  ) async {
    final prefs = FakePreferences(reminders: {police.id});
    final repo = FakeJobRepository(readyState([police]));
    await pumpScreen(tester, home(repo, prefs));

    await tester.tap(find.byTooltip('নোটিফিকেশন'));
    await tester.pumpAndSettle();

    expect(find.text('১টি রিমাইন্ডার চালু'), findsOneWidget);
    expect(find.text(police.titleBn), findsNWidgets(2));
    expect(find.textContaining('পড়া না পড়া'), findsOneWidget);
  });
}
