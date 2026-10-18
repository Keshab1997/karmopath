import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/app/preview/preview_app.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/common/strings.dart';

void main() {
  setUp(() => appLanguage.value = AppLang.bn);
  tearDown(() => appLanguage.value = AppLang.bn);
  testWidgets('preview loads marked samples, detail and session bookmarks', (
    tester,
  ) async {
    await tester.pumpWidget(const KarmopathPreviewApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('DEMO · নমুনা তথ্য'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('অফিস অ্যাসিস্ট্যান্ট · নমুনা'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('অফিস অ্যাসিস্ট্যান্ট · নমুনা'), findsOneWidget);
    await tester.tap(find.byTooltip('সংরক্ষণ করুন').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();
    expect(find.text('অফিস অ্যাসিস্ট্যান্ট · নমুনা'), findsOneWidget);
    await tester.tap(find.text('অফিস অ্যাসিস্ট্যান্ট · নমুনা'));
    await tester.pumpAndSettle();
    expect(find.text('চাকরির বিবরণ'), findsOneWidget);
    expect(find.textContaining('DEMO · নমুনা তথ্য'), findsOneWidget);
    await tester.tap(find.text('রিমাইন্ডার দিন'));
    await tester.pumpAndSettle();
    expect(find.text(K.reminderDeniedMsg.bn), findsOneWidget);
    expect(find.text('রিমাইন্ডার দিন'), findsOneWidget);
    expect(find.text('রিমাইন্ডার চালু'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('preview fits narrow screen and opens calendar/settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const KarmopathPreviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.text('আবেদনের শেষ তারিখ'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('প্রোফাইল ও সেটিংস'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
