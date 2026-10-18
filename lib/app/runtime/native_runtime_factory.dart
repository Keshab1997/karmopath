import 'dart:async';

import 'package:http/http.dart' as http;

import '../../data/cached_job_repository.dart';
import '../../data/local_user_preferences.dart';
import '../../data/platform/http_feed_transport.dart';
import '../../data/reminders/reminder_apply.dart';
import '../../data/reminders/reminder_state_store.dart';
import '../notifications/native_app_actions.dart';
import '../notifications/native_notification_driver.dart';
import 'app_runtime.dart';
import 'feed_configuration.dart';
import 'native_storage.dart';
import 'runtime_reminder_session.dart';

/// Native composition, intentionally NOT selected by lib/main.dart yet.
///
/// A reviewed feed config, a real external launcher and a real reminder-session
/// binding are required. Neither demo content nor no-op success is a fallback.
/// Every successfully acquired resource is registered before the next await;
/// failure unwinds all of them, preserving the original initialization error.
Future<AppRuntime> createNativeRuntime({
  required FeedConfiguration feed,
  required Future<void> Function(Uri uri) openExternal,
  required RuntimeReminderSessionFactory createReminderSession,
  Future<NativeStorage> Function()? openStorage,
  http.Client Function()? createHttpClient,
  NativeNotificationDriver Function()? createNotifications,
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
    final notifications =
        (createNotifications ?? AndroidNotificationDriver.new)();
    resources.add(notifications.close);
    await notifications.initialize();
    final repository = CachedJobRepository(
      transport: HttpFeedTransport(feedUrl: feed.uri, client: client),
      cache: storage.feedCache,
    );
    resources.add(repository.dispose);
    final actions = NativeAppActions(
      notifications: notifications,
      openExternal: openExternal,
    );
    resources.add(actions.close);
    final session = await createReminderSession(
      ReminderSessionDependencies(
        repository: repository,
        preferences: preferences,
        ledger: ledger,
        applier: ReminderApplier(ledger),
        notifications: notifications,
        initialLanguage: language,
      ),
    );
    resources.add(session.close);
    await session.start();
    return AppRuntime(
      repository: repository,
      preferences: preferences,
      actions: actions,
      readLanguage: () async => language,
      writeLanguage: storage.writeLanguage,
      onLanguageChanged: session.languageChanged,
      onResume: session.resumed,
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
