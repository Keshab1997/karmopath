import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/common/reminder_sync_status.dart';
import 'package:karmopath/features/common/strings.dart';

Widget host({
  required ReminderSyncUiPhase phase,
  required AppLang language,
  required VoidCallback onRetry,
  double textScale = 1,
}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: SingleChildScrollView(
          child: ReminderSyncStatusBanner(
            phase: phase,
            language: language,
            onRetry: onRetry,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  for (final language in AppLang.values) {
    final checking = language == AppLang.bn
        ? 'রিমাইন্ডারের অবস্থা যাচাই হচ্ছে…'
        : 'Checking reminder status…';
    final failed = language == AppLang.bn
        ? 'রিমাইন্ডারের অবস্থা যাচাই করা যায়নি। আবার চেষ্টা করুন।'
        : 'Could not check reminder status. Try again.';
    final retry = language == AppLang.bn ? 'আবার চেষ্টা করুন' : 'Try again';

    testWidgets('${language.name}: idle is hidden and does not retry', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        host(
          phase: ReminderSyncUiPhase.idle,
          language: language,
          onRetry: () => calls++,
        ),
      );
      final banner = find.byType(ReminderSyncStatusBanner);
      expect(tester.getSize(banner).height, 0);
      expect(
        find.descendant(of: banner, matching: find.byType(Material)),
        findsNothing,
      );
      expect(find.byType(Text), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 0);
    });

    testWidgets('${language.name}: syncing has accessible progress, no retry', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        var calls = 0;
        await tester.pumpWidget(
          host(
            phase: ReminderSyncUiPhase.syncing,
            language: language,
            onRetry: () => calls++,
          ),
        );
        expect(K.reminderSyncChecking.inLang(language), checking);
        expect(find.text(checking), findsOneWidget);
        expect(find.text(failed), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          tester
              .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator),
              )
              .value,
          isNull,
        );
        expect(find.bySemanticsLabel(checking), findsOneWidget);
        expect(
          tester.getSemantics(find.bySemanticsLabel(checking)),
          matchesSemantics(
            label: checking,
            isLiveRegion: true,
            textDirection: TextDirection.ltr,
          ),
        );
        expect(find.byType(TextButton), findsNothing);
        expect(find.text(retry), findsNothing);
        await tester.pump(const Duration(seconds: 1));
        expect(calls, 0);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('${language.name}: failure retries once only on explicit tap', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        var calls = 0;
        await tester.pumpWidget(
          host(
            phase: ReminderSyncUiPhase.failed,
            language: language,
            onRetry: () => calls++,
          ),
        );
        expect(K.reminderSyncFailed.inLang(language), failed);
        expect(find.text(failed), findsOneWidget);
        expect(find.bySemanticsLabel(failed), findsOneWidget);
        expect(find.text(checking), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(TextButton), findsOneWidget);
        expect(find.widgetWithText(TextButton, retry), findsOneWidget);
        expect(K.retry.inLang(language), retry);
        await tester.pump(const Duration(seconds: 1));
        expect(calls, 0);
        await tester.tap(find.widgetWithText(TextButton, retry));
        await tester.pump();
        expect(calls, 1);
        await tester.pump(const Duration(seconds: 1));
        expect(calls, 1);
      } finally {
        semantics.dispose();
      }
    });

    for (final phase in ReminderSyncUiPhase.values) {
      testWidgets(
        '${language.name}/${phase.name}: no delivery or success claim',
        (tester) async {
          await tester.pumpWidget(
            host(phase: phase, language: language, onRetry: () {}),
          );
          final copy = tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data)
              .toList();
          expect(copy, switch (phase) {
            ReminderSyncUiPhase.idle => <String>[],
            ReminderSyncUiPhase.syncing => [checking],
            ReminderSyncUiPhase.failed => [failed, retry],
          });
          expect(
            find.textContaining(
              RegExp(
                'success|scheduled|delivered|missed|সফল|পাঠানো|নির্ধারিত|মিস',
                caseSensitive: false,
              ),
            ),
            findsNothing,
          );
          expect(find.byType(Icon), findsNothing);
        },
      );
    }

    for (final phase in [
      ReminderSyncUiPhase.syncing,
      ReminderSyncUiPhase.failed,
    ]) {
      testWidgets('${language.name}/${phase.name}: fits 320px at 2x text', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 720);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          host(phase: phase, language: language, onRetry: () {}, textScale: 2),
        );
        expect(tester.takeException(), isNull);
        final text = find.text(
          phase == ReminderSyncUiPhase.syncing ? checking : failed,
        );
        expect(tester.getRect(text).right, lessThanOrEqualTo(320));
        if (phase == ReminderSyncUiPhase.failed) {
          expect(
            find.widgetWithText(TextButton, retry).hitTestable(),
            findsOneWidget,
          );
        }
      });
    }
  }

  for (final phase in [
    ReminderSyncUiPhase.syncing,
    ReminderSyncUiPhase.failed,
  ]) {
    testWidgets(
      '${phase.name}: explicit language changes without global writes',
      (tester) async {
        final original = appLanguage.value;
        var changes = 0;
        void onLanguageChange() => changes++;
        appLanguage.addListener(onLanguageChange);
        addTearDown(() => appLanguage.removeListener(onLanguageChange));
        final copy = phase == ReminderSyncUiPhase.syncing
            ? K.reminderSyncChecking
            : K.reminderSyncFailed;
        for (final language in [AppLang.bn, AppLang.en, AppLang.bn]) {
          await tester.pumpWidget(
            host(phase: phase, language: language, onRetry: () {}),
          );
          expect(find.text(copy.inLang(language)), findsOneWidget);
          expect(
            find.text(
              copy.inLang(language == AppLang.bn ? AppLang.en : AppLang.bn),
            ),
            findsNothing,
          );
          if (phase == ReminderSyncUiPhase.failed) {
            expect(
              find.widgetWithText(TextButton, K.retry.inLang(language)),
              findsOneWidget,
            );
          }
          expect(appLanguage.value, original);
          expect(changes, 0);
        }
      },
    );
  }

  testWidgets('phase changes remove stale status and retry controls', (
    tester,
  ) async {
    var calls = 0;
    for (final phase in [
      ReminderSyncUiPhase.failed,
      ReminderSyncUiPhase.syncing,
      ReminderSyncUiPhase.idle,
    ]) {
      await tester.pumpWidget(
        host(phase: phase, language: AppLang.en, onRetry: () => calls++),
      );
      expect(
        find.byType(TextButton),
        phase == ReminderSyncUiPhase.failed ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(CircularProgressIndicator),
        phase == ReminderSyncUiPhase.syncing ? findsOneWidget : findsNothing,
      );
      expect(calls, 0);
    }
    expect(find.byType(Text), findsNothing);
  });
}
