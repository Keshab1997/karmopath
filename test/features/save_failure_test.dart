import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/common/strings.dart';
import 'package:karmopath/features/home/home_screen.dart';
import 'package:karmopath/features/job_detail/job_detail_screen.dart';
import 'package:karmopath/features/saved/saved_screen.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => appLanguage.value = AppLang.bn);
  tearDown(() => appLanguage.value = AppLang.bn);

  final job = makeJob();
  final railway = makeJob(
    id: 'metro-railway-master',
    titleBn: 'মেট্রো রেলওয়ে স্টেশন মাস্টার',
    titleEn: 'Metro Railway Station Master',
  );

  Widget home(FakeJobRepository repo, FakePreferences prefs) =>
      HomeScreen(repository: repo, preferences: prefs, onOpenJob: (_) {});

  group('JobCard bookmark failures', () {
    testWidgets('a failed save is reported and the stored state is unchanged', (
      tester,
    ) async {
      final prefs = FakePreferences(throwOnWrite: true);
      await pumpScreen(
        tester,
        home(FakeJobRepository(readyState([job])), prefs),
        surfaceSize: const Size(420, 1200),
      );

      await tester.tap(find.byTooltip('সংরক্ষণ করুন'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(K.saveFailed.bn), findsOneWidget);
      expect(prefs.savedCalls, isEmpty);
      expect(prefs.savedJobIds.value, isEmpty);
      // Card still shows the unsaved icon.
      expect(find.byTooltip('সংরক্ষণ করুন'), findsOneWidget);
    });

    testWidgets(
      'a failed unsave uses removal copy, not save or reminder copy',
      (tester) async {
        final prefs = FakePreferences(saved: {job.id}, throwOnWrite: true);
        await pumpScreen(
          tester,
          home(FakeJobRepository(readyState([job])), prefs),
          surfaceSize: const Size(420, 1200),
        );

        await tester.tap(find.byTooltip('সংরক্ষণ বাতিল'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text(K.removeFailed.bn), findsOneWidget);
        expect(find.text(K.saveFailed.bn), findsNothing);
        expect(find.text(K.reminderFailedMsg.bn), findsNothing);
        expect(prefs.savedJobIds.value, {job.id});
      },
    );

    testWidgets('English locale gets the English failure copy', (tester) async {
      appLanguage.value = AppLang.en;
      final prefs = FakePreferences(throwOnWrite: true);
      await pumpScreen(
        tester,
        home(FakeJobRepository(readyState([job])), prefs),
        surfaceSize: const Size(420, 1200),
      );

      await tester.tap(find.byTooltip('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(K.saveFailed.en), findsOneWidget);
      expect(find.text(K.saveFailed.bn), findsNothing);
    });

    testWidgets(
      'rapid taps while a write is pending make one call, no false success',
      (tester) async {
        final prefs = FakePreferences(
          writeDelay: const Duration(milliseconds: 400),
        );
        await pumpScreen(
          tester,
          home(FakeJobRepository(readyState([job])), prefs),
          surfaceSize: const Size(420, 1200),
        );

        await tester.tap(find.byTooltip('সংরক্ষণ করুন'));
        await tester.pump(const Duration(milliseconds: 20));
        // The second tap lands while the first write is still in flight and must
        // be ignored: exactly one write may ever reach the store.
        await tester.tap(find.byTooltip('সংরক্ষণ করুন'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 20));

        await tester.pumpAndSettle();
        expect(prefs.savedCalls, [(job.id, true)]);
        expect(prefs.savedJobIds.value, {job.id});
        expect(find.byTooltip('সংরক্ষণ বাতিল'), findsOneWidget);
      },
    );
  });

  group('Saved screen removal failures', () {
    Widget saved(FakePreferences prefs) => SavedScreen(
      repository: FakeJobRepository(readyState([railway])),
      preferences: prefs,
      onOpenJob: (_) {},
    );

    testWidgets('failed remove keeps the unavailable tile and says so', (
      tester,
    ) async {
      final prefs = FakePreferences(
        saved: {'ghost-job-2025'},
        throwOnWrite: true,
      );
      await pumpScreen(
        tester,
        saved(prefs),
        surfaceSize: const Size(420, 1200),
      );

      await tester.tap(find.text('সরান'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(K.removeFailed.bn), findsOneWidget);
      expect(find.text('ghost-job-2025'), findsOneWidget);
      expect(prefs.savedJobIds.value, {'ghost-job-2025'});
    });

    testWidgets('remove button is disabled while the write is pending', (
      tester,
    ) async {
      final prefs = FakePreferences(
        saved: {'ghost-job-2025'},
        writeDelay: const Duration(milliseconds: 400),
      );
      await pumpScreen(
        tester,
        saved(prefs),
        surfaceSize: const Size(420, 1200),
      );

      await tester.tap(find.text('সরান'));
      await tester.pump(const Duration(milliseconds: 20));
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'সরান'),
      );
      expect(button.onPressed, isNull);

      await tester.pumpAndSettle();
      expect(prefs.savedCalls, [('ghost-job-2025', false)]);
      expect(find.text('ghost-job-2025'), findsNothing);
    });
  });

  group('Detail bookmark failures', () {
    Widget detail(FakePreferences prefs) =>
        JobDetailScreen(job: job, preferences: prefs, actions: FakeActions());

    testWidgets('detail save failure shows saving copy, never reminder copy', (
      tester,
    ) async {
      final prefs = FakePreferences(throwOnWrite: true);
      await pumpScreen(tester, detail(prefs));

      await tester.tap(find.byTooltip('সংরক্ষণ করুন'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(K.saveFailed.bn), findsOneWidget);
      expect(find.text(K.reminderFailedMsg.bn), findsNothing);
      expect(find.text(K.reminderDeniedMsg.bn), findsNothing);
      expect(prefs.savedJobIds.value, isEmpty);
    });

    testWidgets('rapid bookmark taps on detail make a single write', (
      tester,
    ) async {
      final prefs = FakePreferences(
        writeDelay: const Duration(milliseconds: 400),
      );
      await pumpScreen(tester, detail(prefs));

      await tester.tap(find.byTooltip('সংরক্ষণ করুন'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.byTooltip('সংরক্ষণ করুন'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 20));

      await tester.pumpAndSettle();
      expect(prefs.savedCalls, [(job.id, true)]);
      expect(find.byTooltip('সংরক্ষণ বাতিল'), findsOneWidget);
    });
  });

  group('failure copy is distinct per context', () {
    test('save, remove and reminder failures never share wording', () {
      final messages = <String>{
        K.saveFailed.bn,
        K.removeFailed.bn,
        K.reminderFailedMsg.bn,
        K.reminderDeniedMsg.bn,
        K.reminderNoDeadlineMsg.bn,
      };
      expect(messages.length, 5);
      expect(K.saveFailed.en.toLowerCase(), contains("couldn't save"));
      expect(K.removeFailed.en.toLowerCase(), contains('remove'));
      expect(K.reminderFailedMsg.en.toLowerCase(), contains('reminder'));
    });
  });
}
