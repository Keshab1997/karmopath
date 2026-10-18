import 'package:shared_preferences/shared_preferences.dart';

import '../preferences_store.dart';

/// [PreferencesStore] backed by `shared_preferences`.
///
/// The caller passes the key (`karmopath.saved.v1`, `karmopath.reminders.v1`
/// from `LocalUserPreferences`), so this adapter stays key-agnostic and never
/// invents a second namespace. It reads and writes exactly one key per call:
/// it never calls `clear()` and never rewrites other stored settings (theme,
/// language or another feature's keys are left byte-for-byte alone).
///
/// Errors are propagated, not converted: a failed read must reach
/// `LocalUserPreferences` as an error rather than look like "nothing saved",
/// and a failed write must reach the caller so the in-memory set is not
/// updated behind the user's back.
class SharedPreferencesStore implements PreferencesStore {
  SharedPreferencesStore({required this._preferences});

  final SharedPreferencesAsync _preferences;

  @override
  Future<List<String>?> readStrings(String key) async {
    final stored = await _preferences.getStringList(key);
    // Copy: a caller must not be able to mutate the platform's list alias.
    return stored == null ? null : List<String>.of(stored);
  }

  @override
  Future<void> writeStrings(String key, List<String> values) =>
      _preferences.setStringList(key, List<String>.of(values));
}
