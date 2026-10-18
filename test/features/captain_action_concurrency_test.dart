import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/common/external_link.dart';
import 'package:karmopath/features/job_detail/job_detail_screen.dart';

import 'support/fakes.dart';

class ControlledActions extends FakeActions {
  final pending = <String, Completer<void>>{};

  @override
  Future<void> openExternal(Uri uri) {
    opened.add(uri);
    return (pending[uri.toString()] = Completer<void>()).future;
  }
}

class SynchronouslyFailingActions extends FakeActions {
  @override
  Future<void> openExternal(Uri uri) {
    throw StateError('Thrown before a Future is returned');
  }
}

void main() {
  setUp(() => appLanguage.value = AppLang.en);
  tearDown(() => appLanguage.value = AppLang.bn);

  test(
    'guard catches a real synchronous throw before Future creation',
    () async {
      expect(
        await ExternalLinkGuard().open(
          actions: SynchronouslyFailingActions(),
          rawUrl: 'https://example.org/notice',
        ),
        LinkOpenStatus.failed,
      );
    },
  );

  testWidgets('out-of-order link completions preserve each pending button', (
    tester,
  ) async {
    final job = makeJob(applyUrl: 'https://example.org/apply');
    final actions = ControlledActions();
    await pumpScreen(
      tester,
      JobDetailScreen(
        job: job,
        preferences: FakePreferences(),
        actions: actions,
      ),
      surfaceSize: const Size(500, 1800),
    );

    final notice = find.widgetWithText(FilledButton, 'Open original notice');
    final source = find.widgetWithText(OutlinedButton, 'Open official source');
    final apply = find.widgetWithText(FilledButton, 'Apply online');
    await tester.tap(notice);
    await tester.pump();
    await tester.tap(source);
    await tester.pump();
    expect(tester.widget<FilledButton>(notice).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(source).onPressed, isNull);

    actions.pending[job.sourceUrl]!.complete();
    await tester.pump();
    expect(tester.widget<OutlinedButton>(source).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(notice).onPressed, isNull);
    await tester.tap(apply);
    await tester.pump();
    actions.pending[job.noticeUrl]!.complete();
    await tester.pump();
    expect(tester.widget<FilledButton>(notice).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    actions.pending[job.applyUrl]!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
    expect(actions.opened, hasLength(3));
    expect(tester.takeException(), isNull);
  });
}
