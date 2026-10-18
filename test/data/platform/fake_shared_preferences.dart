import 'package:shared_preferences/shared_preferences.dart';

/// In-memory `SharedPreferencesAsync` with injectable failures.
///
/// Implements the real class so the production adapters are exercised through
/// their real signatures; `noSuchMethod` satisfies the rest of the plugin's
/// surface, which the adapters never call. Nothing here touches platform
/// channels, so the tests stay deterministic on any host.
// A test double is intentionally mutable: counters and failure switches are the
// whole point. The @immutable marker on the plugin class does not apply here.
// ignore: must_be_immutable
class FakeSharedPreferences implements SharedPreferencesAsync {
  /// Pass the same map to two instances to model an app restart; omit it for
  /// an isolated store.
  FakeSharedPreferences({Map<String, Object>? initial})
    : values = initial ?? <String, Object>{};

  /// Backing store; a second adapter over the same map models an app restart.
  final Map<String, Object> values;

  /// When set, every read throws this error.
  Object? readError;

  /// When set, every write throws this error.
  Object? writeError;

  int getCalls = 0;
  int setCalls = 0;
  int removeCalls = 0;
  int clearCalls = 0;
  final List<String> writtenKeys = [];
  final List<List<String>> writtenLists = [];

  @override
  Future<String?> getString(String key) async {
    getCalls++;
    _maybeThrowRead();
    final value = values[key];
    return value is String ? value : null;
  }

  @override
  Future<void> setString(String key, String value) async {
    setCalls++;
    writtenKeys.add(key);
    _maybeThrowWrite();
    values[key] = value;
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    getCalls++;
    _maybeThrowRead();
    final value = values[key];
    if (value == null) return null;
    if (value is! List) {
      throw StateError('stored value for "$key" is not a string list');
    }
    return List<String>.from(value.cast<String>());
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    setCalls++;
    writtenKeys.add(key);
    writtenLists.add(List<String>.of(value));
    _maybeThrowWrite();
    values[key] = List<String>.of(value);
  }

  @override
  Future<void> remove(String key) async {
    removeCalls++;
    _maybeThrowWrite();
    values.remove(key);
  }

  @override
  Future<void> clear({Set<String>? allowList}) async {
    clearCalls++;
    _maybeThrowWrite();
    if (allowList == null) {
      values.clear();
    } else {
      allowList.forEach(values.remove);
    }
  }

  void _maybeThrowRead() {
    final error = readError;
    if (error != null) throw error;
  }

  void _maybeThrowWrite() {
    final error = writeError;
    if (error != null) throw error;
  }

  /// Every other plugin member is deliberately unused by the adapters.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
