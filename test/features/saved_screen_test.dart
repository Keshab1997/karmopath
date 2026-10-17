import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job_repository.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/saved/saved_screen.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => appLanguage.value = AppLang.bn);
  tearDown(() => appLanguage.value = AppLang.bn);

  testWidgets('empty saved list shows the empty state', (tester) async {
    final repo = FakeJobRepository(readyState([makeJob()]));
    await pumpScreen(
      tester,
      SavedScreen(
        repository: repo,
        preferences: FakePreferences(),
        onOpenJob: (_) {},
      ),
    );

    expect(find.text('সংরক্ষিত তালিকা খালি'), findsOneWidget);
  });

  testWidgets('saved jobs resolve against the current feed', (tester) async {
    final police = makeJob();
    final railway = makeJob(
      id: 'metro-railway-station-master-2026',
      titleBn: 'মেট্রো রেলওয়ে স্টেশন মাস্টার',
    );
    final repo = FakeJobRepository(readyState([police, railway]));
    await pumpScreen(
      tester,
      SavedScreen(
        repository: repo,
        preferences: FakePreferences(saved: {police.id}),
        onOpenJob: (_) {},
      ),
    );

    expect(find.text(police.titleBn), findsOneWidget);
    expect(find.text(railway.titleBn), findsNothing);
    expect(find.text('১টি সংরক্ষিত'), findsOneWidget);
  });

  testWidgets('missing jobs show unavailable and can be removed', (
    tester,
  ) async {
    final prefs = FakePreferences(saved: {'ghost-job-2025'});
    final repo = FakeJobRepository(readyState([makeJob()]));
    await pumpScreen(
      tester,
      SavedScreen(repository: repo, preferences: prefs, onOpenJob: (_) {}),
    );

    expect(find.text('এই চাকরির তথ্য আর নেই'), findsOneWidget);
    expect(find.text('ghost-job-2025'), findsOneWidget);

    await tester.tap(find.text('সরান'));
    await tester.pump();
    expect(prefs.savedCalls, [('ghost-job-2025', false)]);
    expect(find.text('এই চাকরির তথ্য আর নেই'), findsNothing);
  });

  testWidgets('offline with a cached feed keeps saved jobs visible', (
    tester,
  ) async {
    final job = makeJob();
    final repo = FakeJobRepository(
      JobFeedState(feed: makeFeed([job]), isOffline: true),
    );
    await pumpScreen(
      tester,
      SavedScreen(
        repository: repo,
        preferences: FakePreferences(saved: {job.id}),
        onOpenJob: (_) {},
      ),
    );

    expect(find.text('আপনি অফলাইনে'), findsOneWidget);
    expect(find.text(job.titleBn), findsOneWidget);
  });

  testWidgets('error without a feed offers retry', (tester) async {
    final repo = FakeJobRepository(const JobFeedState(lastError: 'offline'));
    await pumpScreen(
      tester,
      SavedScreen(
        repository: repo,
        preferences: FakePreferences(saved: {makeJob().id}),
        onOpenJob: (_) {},
      ),
    );

    expect(find.text('তথ্য লোড করা যায়নি'), findsOneWidget);
    await tester.tap(find.text('আবার চেষ্টা করুন'));
    await tester.pump();
    expect(repo.refreshCalls, 1);
  });

  testWidgets('tapping a saved card reports the job id', (tester) async {
    String? opened;
    final job = makeJob();
    final repo = FakeJobRepository(readyState([job]));
    await pumpScreen(
      tester,
      SavedScreen(
        repository: repo,
        preferences: FakePreferences(saved: {job.id}),
        onOpenJob: (id) => opened = id,
      ),
    );

    await tester.tap(find.text(job.titleBn));
    await tester.pump();
    expect(opened, job.id);
  });
}
