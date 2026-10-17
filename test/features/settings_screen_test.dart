import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/settings/settings_screen.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => appLanguage.value = AppLang.bn);
  tearDown(() => appLanguage.value = AppLang.bn);

  testWidgets('settings lists language, about and notification info', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      SettingsScreen(actions: FakeActions()),
      surfaceSize: const Size(500, 2000),
    );

    expect(find.text('প্রোফাইল ও সেটিংস'), findsOneWidget);
    expect(find.text('ভাষা'), findsOneWidget);
    expect(find.text('অ্যাপ সম্পর্কে'), findsOneWidget);
    expect(
      find.textContaining('independent information platform'),
      findsOneWidget,
    );
    expect(find.textContaining('কোনো লগইন'), findsOneWidget);
  });

  testWidgets('unprovisioned links are visibly unavailable', (tester) async {
    await pumpScreen(
      tester,
      SettingsScreen(actions: FakeActions()),
      surfaceSize: const Size(500, 2000),
    );

    expect(find.text('এখনো চালু হয়নি'), findsNWidgets(5));
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(5));

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles, hasLength(5));
    for (final tile in tiles) {
      expect(tile.enabled, isFalse);
    }

    // Tapping a disabled tile must not navigate or throw.
    await tester.tap(find.text('প্রাইভেসি পলিসি'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('language toggle switches the whole copy', (tester) async {
    await pumpScreen(
      tester,
      SettingsScreen(actions: FakeActions()),
      surfaceSize: const Size(500, 2000),
    );

    expect(find.text('প্রোফাইল ও সেটিংস'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pump();

    expect(appLanguage.value, AppLang.en);
    expect(find.text('Profile & settings'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(
      find.textContaining('independent information platform'),
      findsOneWidget,
    );
  });
}
