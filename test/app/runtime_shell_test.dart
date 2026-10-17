import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/app/runtime/app_runtime.dart';
import 'package:karmopath/app/runtime/feed_configuration.dart';
import 'package:karmopath/app/runtime/production_bootstrap.dart';
import 'package:karmopath/features/common/app_language.dart';

import '../features/support/fakes.dart';

AppRuntime runtime(
  FakeJobRepository repo, {
  Future<AppLang> Function()? read,
  Future<void> Function(AppLang)? write,
  Future<void> Function()? close,
}) => AppRuntime(
  repository: repo,
  preferences: FakePreferences(),
  actions: FakeActions(permission: false),
  readLanguage: read ?? () async => AppLang.en,
  writeLanguage: write ?? (_) async {},
  close: close ?? () async {},
);
void main() {
  setUp(() => appLanguage.value = AppLang.bn);
  tearDown(() => appLanguage.value = AppLang.bn);
  test('feed URL must be explicit public HTTPS without credentials', () {
    for (final value in [
      '',
      'http://example.org/jobs',
      'https://user:pass@example.org/jobs',
      'https://example.org/jobs#private',
    ]) {
      expect(() => FeedConfiguration(value), throwsFormatException);
    }
    expect(
      FeedConfiguration('https://example.org/jobs.json').uri.host,
      'example.org',
    );
  });
  testWidgets('bootstrap failure is visible and retry uses fresh runtime', (
    tester,
  ) async {
    var calls = 0;
    final repo = FakeJobRepository(readyState([]));
    await tester.pumpWidget(
      ProductionBootstrap(
        createRuntime: () async {
          calls++;
          if (calls == 1) throw StateError('private details');
          return runtime(repo);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not initialize'), findsOneWidget);
    expect(find.textContaining('private details'), findsNothing);
    await tester.tap(find.text('আবার চেষ্টা / Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Home'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('opened detail follows updates and missing ID safely', (
    tester,
  ) async {
    final job = makeJob();
    final repo = FakeJobRepository(readyState([job]));
    await tester.pumpWidget(
      ProductionBootstrap(createRuntime: () async => runtime(repo)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(job.titleEn),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text(job.titleEn));
    await tester.pumpAndSettle();
    expect(find.text('Job details'), findsOneWidget);
    final changed = makeJob(titleEn: 'Corrected title');
    repo.state.value = readyState([changed]);
    await tester.pumpAndSettle();
    expect(find.text('Corrected title'), findsOneWidget);
    expect(find.text(job.titleEn), findsNothing);
    repo.state.value = readyState([]);
    await tester.pumpAndSettle();
    expect(find.text('This job is no longer available'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('language restored and changes persisted; errors stay visible', (
    tester,
  ) async {
    final writes = <AppLang>[];
    final repo = FakeJobRepository(readyState([]));
    await tester.pumpWidget(
      ProductionBootstrap(
        createRuntime: () async => runtime(
          repo,
          write: (language) async {
            writes.add(language);
            throw StateError('disk');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    appLanguage.value = AppLang.bn;
    await tester.pumpAndSettle();
    expect(writes, [AppLang.bn]);
    expect(find.text('সেটিংস'), findsOneWidget);
    expect(find.textContaining('could not be saved'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('runtime arriving after unmount is closed once', (tester) async {
    final pending = Completer<AppRuntime>();
    var closed = 0;
    final resource = runtime(
      FakeJobRepository(readyState([])),
      close: () async {
        closed++;
      },
    );
    await tester.pumpWidget(
      ProductionBootstrap(createRuntime: () => pending.future),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(resource);
    await tester.pumpAndSettle();
    expect(closed, 1);
    await resource.close();
    expect(closed, 1);
  });
  testWidgets('failed language load closes candidate and is retryable', (
    tester,
  ) async {
    var closed = 0;
    await tester.pumpWidget(
      ProductionBootstrap(
        createRuntime: () async => runtime(
          FakeJobRepository(readyState([])),
          read: () async => throw StateError('read failure'),
          close: () async {
            closed++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(find.textContaining('Could not initialize'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(closed, 1);
  });
  test(
    'language writes are ordered and runtime waits before closing',
    () async {
      final gate = Completer<void>();
      final events = <String>[];
      final service = runtime(
        FakeJobRepository(readyState([])),
        write: (lang) async {
          events.add('start-${lang.name}');
          if (lang == AppLang.bn) await gate.future;
          events.add('end-${lang.name}');
        },
        close: () async {
          events.add('closed');
        },
      );
      final first = service.persistLanguage(AppLang.bn);
      final second = service.persistLanguage(AppLang.en);
      final closing = service.close();
      await Future<void>.delayed(Duration.zero);
      expect(events, ['start-bn']);
      gate.complete();
      await Future.wait([first, second, closing]);
      expect(events, ['start-bn', 'end-bn', 'start-en', 'end-en', 'closed']);
      await expectLater(service.persistLanguage(AppLang.en), throwsStateError);
    },
  );
  testWidgets('shell refreshes once and closes runtime on unmount', (
    tester,
  ) async {
    var closed = 0;
    final repo = FakeJobRepository(readyState([]));
    final service = runtime(
      repo,
      close: () async {
        closed++;
      },
    );
    await tester.pumpWidget(
      ProductionBootstrap(createRuntime: () async => service),
    );
    await tester.pumpAndSettle();
    expect(repo.refreshCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(closed, 1);
    await service.close();
    expect(closed, 1);
  });
}
