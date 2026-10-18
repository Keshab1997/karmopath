import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/app/runtime/app_runtime.dart';
import 'package:karmopath/app/runtime/feed_configuration.dart';
import 'package:karmopath/app/runtime/native_runtime_factory.dart';
import 'package:karmopath/app/runtime/native_storage.dart';
import 'package:karmopath/app/runtime/runtime_reminder_session.dart';
import 'package:karmopath/data/local_user_preferences.dart';
import 'package:karmopath/data/reminders/reminder_state.dart';
import 'package:karmopath/data/reminders/reminder_state_store.dart';
import 'package:karmopath/features/common/app_language.dart';

import '../data/fakes.dart';
import 'support/native_test_support.dart';

class TestSession implements RuntimeReminderSession {
  TestSession(this.events);
  final List<String> events;
  final languages = <AppLang>[];
  Object? startError;
  Object? closeError;
  Future<void>? closeGate;
  int closes = 0;
  int resumes = 0;
  @override
  Future<void> start() async {
    events.add('session.start');
    if (startError case final error?) throw error;
  }

  @override
  void languageChanged(AppLang language) => languages.add(language);
  @override
  Future<void> resumed() async {
    resumes++;
  }

  @override
  Future<void> close() async {
    events.add('session.close');
    closes++;
    if (closeGate case final gate?) await gate;
    if (closeError case final error?) throw error;
  }
}

class Harness {
  Harness() {
    notifications = FakeNativeNotificationBackend(events: events);
    client = RecordingHttpClient(events);
    session = TestSession(events);
  }
  final events = <String>[];
  final prefs = FakePreferencesStore(
    initial: {
      LocalUserPreferences.savedKey: ['old-saved'],
      LocalUserPreferences.remindersKey: ['a-job'],
    },
  );
  final cache = FakeCache();
  late final FakeNativeNotificationBackend notifications;
  late final RecordingHttpClient client;
  late final TestSession session;
  ReminderSessionDependencies? dependencies;
  Object? storageOpenError;
  Object? languageError;
  Object? bindError;
  Object? storageCloseError;
  Future<void>? languageWriteGate;
  Object? languageWriteError;
  int storageCloses = 0;

  Future<AppRuntime> create({
    bool useDefaultSession = false,
  }) => createNativeRuntime(
    // Fixture-only injected URL/client, never real production approval/network.
    feed: FeedConfiguration('https://example.org/fixture-feed.json'),
    openExternal: (_) async {},
    openStorage: () async {
      events.add('storage.open');
      if (storageOpenError case final error?) throw error;
      return NativeStorage(
        preferences: prefs,
        feedCache: cache,
        readLanguage: () async {
          if (languageError case final error?) throw error;
          return AppLang.en;
        },
        writeLanguage: (_) async {
          if (languageWriteGate case final gate?) await gate;
          if (languageWriteError case final error?) throw error;
        },
        close: () async {
          events.add('storage.close');
          storageCloses++;
          if (storageCloseError case final error?) throw error;
        },
      );
    },
    createHttpClient: () => client,
    createNotifications: () => notifications,
    createReminderSession: useDefaultSession
        ? null
        : (deps) async {
            dependencies = deps;
            if (bindError case final error?) throw error;
            return session;
          },
  );
}

void main() {
  test('successful init restores preferences/language/ledger without network/prompt', () async {
    final h = Harness();
    final runtime = await h.create();
    expect(runtime.preferences.savedJobIds.value, {'old-saved'});
    expect(runtime.preferences.reminderJobIds.value, {'a-job'});
    expect(await runtime.readLanguage(), AppLang.en);
    expect(h.dependencies!.initialLanguage, AppLang.en);
    expect(h.dependencies!.ledger.isInitialized, isTrue);
    expect(h.client.sends, 0);
    expect(h.notifications.permissionRequests, 0);
    expect(h.prefs.writeKeys, isEmpty);
    await runtime.close();
    await runtime.close();
    expect(h.session.closes, 1);
    expect(h.notifications.closes, 1);
    expect(h.client.closes, 1);
    expect(h.storageCloses, 1);
  });
  test(
    'default binding reconciles fresh selected feed through ledger and backend',
    () async {
      final h = Harness();
      h.client.body = feedJson(
        jobs: [jobJson(id: 'a-job', applicationEndDate: '2027-01-31')],
      );
      final runtime = await h.create(useDefaultSession: true);
      await runtime.repository.refresh();
      await runtime.resumed();

      expect(h.notifications.scheduled, hasLength(1));
      expect(h.notifications.permissionRequests, 0);
      final request = h.notifications.scheduled.single;
      expect(request.identity.jobId, 'a-job');
      expect(request.identity.payloadVariant, 'en@reminder-v1');
      expect(request.title, 'West Bengal Police constable recruitment');
      expect(request.body, isNotEmpty);
      expect(h.notifications.pending.single.identity, request.identity);
      await runtime.close();
    },
  );

  test(
    'default binding wires the backend, sync status, retry, and tap queue',
    () async {
      final h = Harness();
      final runtime = await h.create(useDefaultSession: true);
      expect(runtime.reminderStatus, isNotNull);
      expect(runtime.retryReminderSync, isNotNull);
      final taps = runtime.reminderTapIntents!;
      h.notifications.tap('a-job');
      expect(taps.pendingJobId, 'a-job');
      h.notifications.tap('bad/job');
      expect(taps.pendingJobId, 'a-job');
      await runtime.close();
      expect(taps.hasPending, isFalse);
    },
  );

  test('storage-open error does not pretend empty preferences or acquire later resources', () async {
    final h = Harness();
    final error = StateError('storage unavailable');
    h.storageOpenError = error;
    await expectLater(h.create(), throwsA(same(error)));
    expect(h.events, ['storage.open']);
    expect(h.client.closes, 0);
  });
  test(
    'unreadable user preferences release HTTP/storage before plugin creation',
    () async {
      final h = Harness();
      final error = StateError('saved settings unreadable');
      h.prefs.readErrors[LocalUserPreferences.savedKey] = error;
      await expectLater(h.create(), throwsA(same(error)));
      expect(h.client.closes, 1);
      expect(h.storageCloses, 1);
      expect(h.notifications.events, isNot(contains('driver.initialize')));
      expect(h.prefs.writeKeys, isEmpty);
    },
  );
  test('corrupt ledger fails safely, is not overwritten and can retry after repair', () async {
    final h = Harness();
    h.prefs.data[ReminderStateStore.storageKey] = ['not-json'];
    await expectLater(h.create(), throwsA(isA<ReminderStateException>()));
    expect(h.prefs.data[ReminderStateStore.storageKey], ['not-json']);
    expect(h.prefs.writeKeys, isEmpty);
    expect(h.notifications.permissionRequests, 0);
    expect(h.client.closes, 1);
    expect(h.storageCloses, 1);
    // Retry always uses a fresh factory/resource session, not a disposed client.
    final retry = Harness();
    final runtime = await retry.create();
    await runtime.close();
  });
  test('language-read failure closes acquired resources, never falls back silently', () async {
    final h = Harness();
    final error = StateError('language unreadable');
    h.languageError = error;
    await expectLater(h.create(), throwsA(same(error)));
    expect(h.client.closes, 1);
    expect(h.storageCloses, 1);
    expect(h.dependencies, isNull);
  });
  test(
    'plugin init failure preserves primary error despite cleanup failures',
    () async {
      final h = Harness();
      final error = StateError('plugin init failed');
      h.notifications.initError = error;
      h.notifications.closeError = StateError('plugin close failed');
      h.storageCloseError = StateError('storage close failed');
      await expectLater(h.create(), throwsA(same(error)));
      expect(h.notifications.closes, 1);
      expect(h.client.closes, 1);
      expect(h.storageCloses, 1);
    },
  );
  test(
    'binding creation failure disposes repository and all acquired resources',
    () async {
      final h = Harness();
      final error = StateError('binding failed');
      h.bindError = error;
      await expectLater(h.create(), throwsA(same(error)));
      expect(h.notifications.closes, 1);
      expect(h.client.closes, 1);
      expect(h.storageCloses, 1);
      await h.dependencies!.repository.refresh();
      expect(h.client.sends, 0);
    },
  );
  test('session startup failure is retryable and unwinds it before its dependencies', () async {
    final h = Harness();
    final error = StateError('startup pending query failed');
    h.session.startError = error;
    await expectLater(h.create(), throwsA(same(error)));
    expect(h.session.closes, 1);
    expect(
      h.events.indexOf('session.close'),
      lessThan(h.events.indexOf('driver.close')),
    );
    expect(h.notifications.closes, 1);
    expect(h.client.closes, 1);
    expect(h.storageCloses, 1);
  });
  test(
    'close drains session before closing plugin/HTTP/storage even on error',
    () async {
      final h = Harness();
      final runtime = await h.create();
      final gate = Completer<void>();
      final error = StateError('session close failed');
      h.session.closeGate = gate.future;
      h.session.closeError = error;
      final closing = runtime.close();
      final assertion = expectLater(closing, throwsA(same(error)));
      await Future<void>.delayed(Duration.zero);
      expect(h.session.closes, 1);
      expect(h.notifications.closes, 0);
      expect(h.client.closes, 0);
      gate.complete();
      await assertion;
      expect(h.notifications.closes, 1);
      expect(h.client.closes, 1);
      expect(h.storageCloses, 1);
    },
  );
  test(
    'visible language triggers session immediately despite persistence failure',
    () async {
      final h = Harness();
      final runtime = await h.create();
      final error = StateError('language write failed');
      h.languageWriteError = error;
      final write = runtime.persistLanguage(AppLang.bn);
      expect(h.session.languages, [AppLang.bn]);
      await expectLater(write, throwsA(same(error)));
      h.languageWriteError = null;
      await runtime.persistLanguage(AppLang.en);
      expect(h.session.languages, [AppLang.bn, AppLang.en]);
      await runtime.close();
    },
  );
  test(
    'runtime waits for language writes before close and blocks late callbacks',
    () async {
      final h = Harness();
      final runtime = await h.create();
      final gate = Completer<void>();
      h.languageWriteGate = gate.future;
      final writing = runtime.persistLanguage(AppLang.bn);
      final closing = runtime.close();
      await Future<void>.delayed(Duration.zero);
      expect(h.session.closes, 0);
      await runtime.resumed();
      expect(h.session.resumes, 0);
      await expectLater(runtime.persistLanguage(AppLang.en), throwsStateError);
      expect(h.session.languages, [AppLang.bn]);
      gate.complete();
      await Future.wait([writing, closing]);
      expect(h.session.closes, 1);
    },
  );
  test(
    'resume forwards to the bound session without asking permission',
    () async {
      final h = Harness();
      final runtime = await h.create();
      await runtime.resumed();
      expect(h.session.resumes, 1);
      expect(h.notifications.permissionRequests, 0);
      await runtime.close();
    },
  );
}
