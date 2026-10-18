import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/data/feed_cache.dart';
import 'package:karmopath/data/platform/preferences_feed_cache.dart';

import 'fake_shared_preferences.dart';

void main() {
  test('uses the frozen versioned key', () {
    expect(PreferencesFeedCache.cacheKey, 'karmopath.feed.v1');
  });

  test('reading an empty store returns null, not an empty document', () async {
    final prefs = FakeSharedPreferences();
    final cache = PreferencesFeedCache(preferences: prefs);

    expect(cache, isA<FeedCache>());
    expect(await cache.read(), isNull);
    expect(prefs.getCalls, 1);
  });

  test('write then read round-trips the exact document', () async {
    final prefs = FakeSharedPreferences();
    final cache = PreferencesFeedCache(preferences: prefs);
    const raw =
        '{"schema_version":1,"updated_at":"2026-01-01T00:00:00Z","jobs":[]}';

    await cache.write(raw);

    expect(prefs.values[PreferencesFeedCache.cacheKey], raw);
    expect(prefs.writtenKeys, [PreferencesFeedCache.cacheKey]);
    expect(await cache.read(), raw);
  });

  test('a later write replaces the previous document', () async {
    final prefs = FakeSharedPreferences();
    final cache = PreferencesFeedCache(preferences: prefs);

    await cache.write('{"v":1}');
    await cache.write('{"v":2}');

    expect(await cache.read(), '{"v":2}');
  });

  test('the cached document survives an app restart', () async {
    final store = <String, Object>{};
    final firstRun = PreferencesFeedCache(
      preferences: FakeSharedPreferences(initial: store),
    );
    await firstRun.write('{"jobs":[]}');

    // A new adapter instance over the same persisted map = next launch.
    final nextRun = PreferencesFeedCache(
      preferences: FakeSharedPreferences(initial: store),
    );

    expect(await nextRun.read(), '{"jobs":[]}');
  });

  test(
    'a read failure propagates instead of looking like an empty cache',
    () async {
      final prefs = FakeSharedPreferences()
        ..readError = StateError('platform channel unavailable');

      await expectLater(
        PreferencesFeedCache(preferences: prefs).read(),
        throwsStateError,
      );
    },
  );

  test('a write failure propagates instead of reporting success', () async {
    final prefs = FakeSharedPreferences()..writeError = StateError('disk full');
    final cache = PreferencesFeedCache(preferences: prefs);

    await expectLater(cache.write('{"jobs":[]}'), throwsStateError);
    expect(prefs.values, isEmpty, reason: 'nothing may be reported as cached');
  });

  test('writing one key never touches unrelated settings', () async {
    final prefs = FakeSharedPreferences(
      initial: {
        'karmopath.saved.v1': <String>['a-job'],
        'karmopath.reminders.v1': <String>['a-job'],
        'theme': 'dark',
        'language': 'bn',
      },
    );
    final cache = PreferencesFeedCache(preferences: prefs);

    await cache.write('{"jobs":[]}');

    expect(prefs.values['karmopath.saved.v1'], ['a-job']);
    expect(prefs.values['karmopath.reminders.v1'], ['a-job']);
    expect(prefs.values['theme'], 'dark');
    expect(prefs.values['language'], 'bn');
    expect(prefs.removeCalls, 0);
    expect(prefs.clearCalls, 0, reason: 'clear() must never be used');
  });
}
