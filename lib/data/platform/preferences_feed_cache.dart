import 'package:shared_preferences/shared_preferences.dart';

import '../feed_cache.dart';

/// [FeedCache] backed by `shared_preferences`.
///
/// The captain supplies the [SharedPreferencesAsync] instance so the storage
/// options stay a composition decision. Only one key is ever touched:
/// [cacheKey]. Errors from the platform store are not swallowed — a failed read
/// is handled by `CachedJobRepository` as "no saved copy" and a failed write as
/// "fresh data shown, offline copy not saved", which is why they must surface
/// instead of being reported as success.
///
/// The value stored is exactly the document that passed `JobFeed` validation,
/// unchanged, so the cache can never contain a payload the contract rejected.
class PreferencesFeedCache implements FeedCache {
  PreferencesFeedCache({required this._preferences});

  /// Versioned key; bump the version rather than migrating silently.
  static const String cacheKey = 'karmopath.feed.v1';

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read() => _preferences.getString(cacheKey);

  @override
  Future<void> write(String raw) => _preferences.setString(cacheKey, raw);
}
