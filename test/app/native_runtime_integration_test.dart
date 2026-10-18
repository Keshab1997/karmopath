import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/app/runtime/app_runtime.dart';
import 'package:karmopath/app/runtime/production_shell.dart';
import 'package:karmopath/app/runtime/runtime_reminder_session.dart';
import 'package:karmopath/contracts/native_reminders.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/common/reminder_sync_status.dart';
import 'package:karmopath/features/common/reminder_tap_intent.dart';

import '../features/support/fakes.dart';

AppRuntime runtime({
  required FakeJobRepository repository,
  ValueListenable<RuntimeReminderStatus>? status,
  Future<void> Function()? retry,
  ReminderTapIntentQueue? taps,
}) => AppRuntime(
  repository: repository,
  preferences: FakePreferences(),
  actions: FakeActions(permission: false),
  readLanguage: () async => AppLang.en,
  writeLanguage: (_) async {},
  reminderStatus: status,
  retryReminderSync: retry,
  reminderTapIntents: taps,
  close: () async {},
);

void main() {
  setUp(() => appLanguage.value = AppLang.en);
  tearDown(() => appLanguage.value = AppLang.bn);

  testWidgets('cold-start and foreground taps route only the queued job ID', (
    tester,
  ) async {
    final repository = FakeJobRepository(
      readyState([
        makeJob(id: 'a-job'),
        makeJob(id: 'b-job', titleEn: 'Second job'),
      ]),
    );
    final taps = ReminderTapIntentQueue()..accept('a-job');
    final appRuntime = runtime(repository: repository, taps: taps);

    await tester.pumpWidget(ProductionShell(runtime: appRuntime));
    await tester.pumpAndSettle();
    expect(find.text('Job details'), findsOneWidget);
    expect(taps.hasPending, isFalse);

    taps.accept('b-job');
    await tester.pumpAndSettle();
    expect(find.text('Second job'), findsOneWidget);
    expect(taps.hasPending, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await appRuntime.close();
    await repository.dispose();
  });

  testWidgets('sync banner exposes explicit retry and hides on recovery', (
    tester,
  ) async {
    final repository = FakeJobRepository(readyState([]));
    final status = ValueNotifier(
      const RuntimeReminderStatus(phase: ReminderSyncUiPhase.syncing),
    );
    var retries = 0;
    final appRuntime = runtime(
      repository: repository,
      status: status,
      retry: () async {
        retries++;
        status.value = const RuntimeReminderStatus();
      },
    );

    await tester.pumpWidget(ProductionShell(runtime: appRuntime));
    await tester.pump();
    expect(find.text('Checking reminder status…'), findsOneWidget);

    status.value = const RuntimeReminderStatus(
      phase: ReminderSyncUiPhase.failed,
    );
    await tester.pump();
    expect(
      find.text('Could not check reminder status. Try again.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Try again'));
    await tester.pumpAndSettle();
    expect(retries, 1);
    expect(
      find.text('Could not check reminder status. Try again.'),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await appRuntime.close();
    status.dispose();
    await repository.dispose();
  });
}
