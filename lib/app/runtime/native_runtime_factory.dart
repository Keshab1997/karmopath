import 'dart:async';

import 'package:http/http.dart' as http;

import '../../contracts/job.dart';
import '../../contracts/native_reminders.dart';
import '../../data/cached_job_repository.dart';
import '../../data/local_user_preferences.dart';
import '../../data/platform/http_feed_transport.dart';
import '../../data/reminders/native_reminder_sync.dart';
import '../../data/reminders/reminder_state_store.dart';
import '../../features/common/app_language.dart';
import '../../features/common/reminder_notification_content.dart';
import '../../features/common/reminder_tap_intent.dart';
import '../../platform/notifications/android_native_notifications.dart';
import '../notifications/external_uri_launcher.dart';
import '../notifications/native_app_actions.dart';
import 'app_runtime.dart';
import 'feed_configuration.dart';
import 'native_reminder_session.dart';
import 'native_storage.dart';
import 'runtime_reminder_session.dart';

/// Native composition, intentionally NOT selected by lib/main.dart yet.
///
/// A reviewed feed config is required. The external launcher defaults to the
/// real system handler and may be replaced only for tests. The default binding
/// composes the reviewed synchronizer, Android backend, bilingual content, tap
/// handoff and status/retry session. No demo content or no-op success is a
/// fallback. Every acquired resource is registered before the next await;
/// failure unwinds all of them and preserves the primary error.
Future<AppRuntime> createNativeRuntime({
  required FeedConfiguration feed,
  Future<void> Function(Uri uri)? openExternal,
  RuntimeReminderSessionFactory? createReminderSession,
  Future<NativeStorage> Function()? openStorage,
  http.Client Function()? createHttpClient,
  NativeNotifications Function()? createNotifications,
}) async {
  final resources = _RuntimeResources();
  try {
    final storage = await (openStorage ?? NativeStorage.open)();
    resources.add(storage.close);
    final client = (createHttpClient ?? http.Client.new)();
    resources.add(client.close);
    final preferences = LocalUserPreferences(store: storage.preferences);
    resources.add(preferences.dispose);
    await preferences.initialize();
    final ledger = ReminderStateStore(store: storage.preferences);
    resources.add(ledger.dispose);
    await ledger.initialize();
    final language = await storage.readLanguage();

    final tapIntents = ReminderTapIntentQueue();
    resources.add(tapIntents.clear);
    final notifications =
        (createNotifications ?? AndroidNativeNotifications.new)();
    resources.add(notifications.dispose);
    await notifications.initialize(onJobTap: tapIntents.accept);

    final repository = CachedJobRepository(
      transport: HttpFeedTransport(feedUrl: feed.uri, client: client),
      cache: storage.feedCache,
    );
    resources.add(repository.dispose);
    final actions = NativeAppActions(
      notifications: notifications,
      openExternal: openExternal ?? launchExternalHttpsUri,
    );
    resources.add(actions.close);
    final synchronizer = LedgerNativeReminderSynchronizer(
      store: storage.preferences,
      stateStore: ledger,
      notifications: notifications,
      textForJob: _notificationText,
    );
    resources.add(synchronizer.close);

    final dependencies = ReminderSessionDependencies(
      repository: repository,
      preferences: preferences,
      ledger: ledger,
      notifications: notifications,
      synchronizer: synchronizer,
      initialLanguage: language,
    );
    final session = createReminderSession == null
        ? NativeReminderSession(
            repository: repository,
            preferences: preferences,
            synchronizer: synchronizer,
            initialLanguage: language,
          )
        : await createReminderSession(dependencies);
    resources.add(session.close);
    await session.start();

    final RuntimeReminderStatusSource? statusSource =
        session is RuntimeReminderStatusSource
        ? session as RuntimeReminderStatusSource
        : null;
    return AppRuntime(
      repository: repository,
      preferences: preferences,
      actions: actions,
      readLanguage: () async => language,
      writeLanguage: storage.writeLanguage,
      onLanguageChanged: session.languageChanged,
      onResume: session.resumed,
      reminderStatus: statusSource?.status,
      retryReminderSync: statusSource?.retry,
      reminderTapIntents: tapIntents,
      close: resources.close,
    );
  } catch (_) {
    // Secondary cleanup errors must not mask the actual initialization failure.
    try {
      await resources.close();
    } catch (_) {}
    rethrow;
  }
}

ReminderNotificationText _notificationText(Job job, String languageCode) {
  final language = switch (languageCode) {
    'bn' => AppLang.bn,
    'en' => AppLang.en,
    _ => throw ArgumentError.value(languageCode, 'languageCode'),
  };
  final content = buildReminderNotificationContent(
    job: job,
    language: language,
  );
  if (content.payloadVariant != reminderPayloadVariant(languageCode)) {
    throw StateError(
      'Reminder copy variant does not match the native contract',
    );
  }
  return ReminderNotificationText(title: content.title, body: content.body);
}

class _RuntimeResources {
  final _releases = <FutureOr<void> Function()>[];
  Future<void>? _closing;

  void add(FutureOr<void> Function() release) => _releases.add(release);

  Future<void> close() => _closing ??= _releaseAll();

  Future<void> _releaseAll() async {
    (Object, StackTrace)? firstFailure;
    for (final release in _releases.reversed) {
      try {
        await release();
      } catch (error, stack) {
        firstFailure ??= (error, stack);
      }
    }
    _releases.clear();
    final failure = firstFailure;
    if (failure != null) Error.throwWithStackTrace(failure.$1, failure.$2);
  }
}
