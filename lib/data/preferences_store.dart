/// Minimal keyed string-list storage used by [LocalUserPreferences].
///
/// Deliberately tiny so it maps onto any platform store (shared_preferences,
/// a file, an in-memory fake) without a new dependency. The captain supplies
/// the concrete adapter under `lib/app`; only string lists cross this boundary.
abstract class PreferencesStore {
  /// Returns the stored list for [key], or `null` when the key is absent.
  ///
  /// Throwing is allowed and is surfaced to the caller of the preference
  /// method: a broken read must never look like an empty preference set.
  Future<List<String>?> readStrings(String key);

  /// Replaces the stored list for [key].
  ///
  /// Throwing leaves the in-memory preference set unchanged, so the UI never
  /// shows a saved/reminder state that was not actually persisted.
  Future<void> writeStrings(String key, List<String> values);
}
