import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/app/runtime/app_runtime.dart';
import 'package:karmopath/app/runtime/production_bootstrap.dart';
import 'package:karmopath/features/common/app_language.dart';

import '../features/support/fakes.dart';

void main() {
  setUp(() => appLanguage.value = AppLang.bn);
  tearDown(() => appLanguage.value = AppLang.bn);

  testWidgets(
    'shell forwards resume, detaches observer and does not leak raw errors',
    (tester) async {
      var resumes = 0;
      final runtime = AppRuntime(
        repository: FakeJobRepository(readyState([])),
        preferences: FakePreferences(),
        actions: FakeActions(permission: false),
        readLanguage: () async => AppLang.en,
        writeLanguage: (_) async {},
        close: () async {},
        onResume: () async {
          resumes++;
          throw StateError('private channel detail');
        },
      );
      await tester.pumpWidget(
        ProductionBootstrap(createRuntime: () async => runtime),
      );
      await tester.pumpAndSettle();
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(resumes, 1);
      expect(find.textContaining('Could not check reminders'), findsOneWidget);
      expect(find.textContaining('private channel detail'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(resumes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings summary receives the real runtime preferences', (
    tester,
  ) async {
    final prefs = FakePreferences(reminders: {'a-job'});
    final runtime = AppRuntime(
      repository: FakeJobRepository(readyState([])),
      preferences: prefs,
      actions: FakeActions(permission: false),
      readLanguage: () async => AppLang.en,
      writeLanguage: (_) async {},
      close: () async {},
    );
    await tester.pumpWidget(
      ProductionBootstrap(createRuntime: () async => runtime),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('1 stored reminder'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('1 stored reminder'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
