import 'package:flutter/foundation.dart';

import '../contracts/user_preferences.dart';
import 'preferences_store.dart';

/// Saved-job and reminder-intent storage backed by an injected [PreferencesStore].
///
/// Intent and delivery are separate concerns: this class only persists the
/// user's choice. The captain schedules/cancels Android notifications from the
/// exposed sets; it never confirms a reminder the user did not enable.
///
/// Guarantees:
///  * Every published set is an immutable snapshot, so neither the UI nor a
///    listener can mutate repository state by accident.
///  * Writes are serialised and applied in call order; a rapid double tap
///    cannot lose one of the two changes.
///  * A failing store never yields a false success: the in-memory set changes
///    only after the write succeeded, and the caller receives the error.
///  * [initialize] is idempotent and is also awaited lazily by the setters, so
///    a write can never silently drop previously stored ids.
class LocalUserPreferences implements UserPreferences {
  LocalUserPreferences({required this._store});

  /// Versioned keys — bump the version instead of migrating silently.
  static const String savedKey = 'karmopath.saved.v1';
  static const String remindersKey = 'karmopath.reminders.v1';

  final PreferencesStore _store;

  final ValueNotifier<Set<String>> _saved = ValueNotifier<Set<String>>(
    const <String>{},
  );
  final ValueNotifier<Set<String>> _reminders = ValueNotifier<Set<String>>(
    const <String>{},
  );

  Future<void>? _initialization;
  Future<void> _writes = Future<void>.value();
  bool _disposed = false;

  @override
  ValueListenable<Set<String>> get savedJobIds => _saved;

  @override
  ValueListenable<Set<String>> get reminderJobIds => _reminders;

  /// Loads the persisted sets. Call once before composing the UI; repeated
  /// calls are cheap and return the same attempt.
  ///
  /// A store read failure is rethrown on purpose: an unreadable preference
  /// store must not be presented as "nothing saved".
  Future<void> initialize() => _initialization ??= _initializeOnce();

  @override
  Future<void> setSaved(String jobId, bool saved) => _update(
    key: savedKey,
    notifier: _saved,
    jobId: jobId,
    enabled: saved,
    label: 'saved',
  );

  @override
  Future<void> setReminder(String jobId, bool enabled) => _update(
    key: remindersKey,
    notifier: _reminders,
    jobId: jobId,
    enabled: enabled,
    label: 'reminder',
  );

  /// Releases the notifiers. Pending writes finish harmlessly; their results
  /// are not published after disposal.
  void dispose() {
    if (_disposed) return; // idempotent: double disposal must not assert
    _disposed = true;
    _saved.dispose();
    _reminders.dispose();
  }

  /// A failed load is not cached: the next call retries, so one transient store
  /// error does not permanently disable saving.
  Future<void> _initializeOnce() async {
    try {
      await _load();
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<void> _load() async {
    final saved = await _store.readStrings(savedKey);
    final reminders = await _store.readStrings(remindersKey);
    if (_disposed) return;
    _saved.value = _normalize(saved);
    _reminders.value = _normalize(reminders);
  }

  Future<void> _update({
    required String key,
    required ValueNotifier<Set<String>> notifier,
    required String jobId,
    required bool enabled,
    required String label,
  }) {
    if (_disposed) return Future<void>.value();
    final id = jobId.trim();
    if (id.isEmpty) {
      return Future<void>.error(
        ArgumentError.value(jobId, 'jobId', 'a $label target needs a job id'),
      );
    }
    // Serialise behind earlier writes so two taps cannot overwrite each other.
    final task = _writes.then(
      (_) => _apply(key: key, notifier: notifier, id: id, enabled: enabled),
    );
    // A failed write must not poison the queue for the next attempt.
    _writes = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  Future<void> _apply({
    required String key,
    required ValueNotifier<Set<String>> notifier,
    required String id,
    required bool enabled,
  }) async {
    await initialize();
    if (_disposed) return;
    final current = notifier.value;
    if (current.contains(id) == enabled) return; // already in the wanted state
    final next = <String>{...current};
    if (enabled) {
      next.add(id);
    } else {
      next.remove(id);
    }
    final snapshot = next.toList()..sort();
    // Persist first: a storage failure must not look like a saved reminder.
    await _store.writeStrings(key, snapshot);
    if (_disposed) return;
    notifier.value = Set<String>.unmodifiable(next);
  }

  /// Drops blanks and duplicates from whatever the store handed back.
  Set<String> _normalize(List<String>? values) {
    if (values == null) return const <String>{};
    return Set<String>.unmodifiable(
      values.map((value) => value.trim()).where((value) => value.isNotEmpty),
    );
  }
}
