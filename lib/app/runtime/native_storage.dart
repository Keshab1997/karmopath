import 'package:shared_preferences/shared_preferences.dart';

import '../../data/feed_cache.dart';
import '../../data/platform/preferences_feed_cache.dart';
import '../../data/platform/shared_preferences_store.dart';
import '../../data/preferences_store.dart';
import '../../features/common/app_language.dart';

/// One acquired storage session. Injected openers must clean up their own
/// partially acquired resources if they throw before returning this handle.
class NativeStorage {
  NativeStorage({
    required this.preferences,
    required this.feedCache,
    required this.readLanguage,
    required this.writeLanguage,
    required this.close,
  });

  static const languageKey = 'karmopath.language.v1';
  final PreferencesStore preferences;
  final FeedCache feedCache;
  final Future<AppLang> Function() readLanguage;
  final Future<void> Function(AppLang language) writeLanguage;
  final Future<void> Function() close;

  static Future<NativeStorage> open({
    SharedPreferencesAsync? preferences,
  }) async {
    final shared = preferences ?? SharedPreferencesAsync();
    return NativeStorage(
      preferences: SharedPreferencesStore(preferences: shared),
      feedCache: PreferencesFeedCache(preferences: shared),
      readLanguage: () async {
        final value = await shared.getString(languageKey);
        return switch (value) {
          null || 'bn' => AppLang.bn,
          'en' => AppLang.en,
          _ => throw const FormatException('Unrecognized stored language'),
        };
      },
      writeLanguage: (language) => shared.setString(languageKey, language.name),
      // SharedPreferencesAsync owns no per-session client/notifier to dispose.
      // Never clear it or delete reminders/settings on runtime shutdown.
      close: () async {},
    );
  }
}
