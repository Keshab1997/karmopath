import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/data/local_user_preferences.dart';
import 'package:karmopath/data/platform/shared_preferences_store.dart';
import 'package:karmopath/data/preferences_store.dart';

import 'fake_shared_preferences.dart';

void main() {
  test('is a PreferencesStore and leaves keys to the caller', () async {
    final prefs = FakeSharedPreferences();
    final store = SharedPreferencesStore(preferences: prefs);

    expect(store, isA<PreferencesStore>());
    expect(await store.readStrings('karmopath.saved.v1'), isNull);
  });

  test('round-trips a string list under the requested key', () async {
    final prefs = FakeSharedPreferences();
    final store = SharedPreferencesStore(preferences: prefs);

    await store.writeStrings('karmopath.saved.v1', ['b-job', 'a-job']);

    expect(prefs.writtenKeys, ['karmopath.saved.v1']);
    expect(await store.readStrings('karmopath.saved.v1'), ['b-job', 'a-job']);
  });

  test('returns a copy so callers cannot mutate stored state', () async {
    final prefs = FakeSharedPreferences();
    final store = SharedPreferencesStore(preferences: prefs);
    await store.writeStrings('karmopath.saved.v1', ['a-job']);

    final read = await store.readStrings('karmopath.saved.v1');
    read!.add('injected');

    expect(await store.readStrings('karmopath.saved.v1'), ['a-job']);
  });

  test('write copies its input list as well', () async {
    final prefs = FakeSharedPreferences();
    final store = SharedPreferencesStore(preferences: prefs);
    final values = <String>['a-job'];

    await store.writeStrings('karmopath.saved.v1', values);
    values.add('mutated-after-write');

    expect(prefs.values['karmopath.saved.v1'], ['a-job']);
  });

  test('saved ids survive a restart', () async {
    final backing = <String, Object>{};
    await SharedPreferencesStore(
      preferences: FakeSharedPreferences(initial: backing),
    ).writeStrings('karmopath.saved.v1', ['wb-police-2026', 'wb-rail-2026']);

    final nextLaunch = SharedPreferencesStore(
      preferences: FakeSharedPreferences(initial: backing),
    );

    expect(await nextLaunch.readStrings('karmopath.saved.v1'), [
      'wb-police-2026',
      'wb-rail-2026',
    ]);
  });

  test(
    'a read failure propagates instead of looking like "nothing saved"',
    () async {
      final prefs = FakeSharedPreferences(
        initial: {
          'karmopath.saved.v1': <String>['a-job'],
        },
      )..readError = StateError('platform channel unavailable');

      await expectLater(
        SharedPreferencesStore(preferences: prefs)
            .readStrings('karmopath.saved.v1'),
        throwsStateError,
      );
    },
  );

  test('a write failure propagates and changes nothing', () async {
    final prefs = FakeSharedPreferences(
      initial: {
        'karmopath.saved.v1': <String>['a-job'],
      },
    )..writeError = StateError('disk full');

    await expectLater(
      SharedPreferencesStore(preferences: prefs)
          .writeStrings('karmopath.saved.v1', ['a-job', 'b-job']),
      throwsStateError,
    );
    expect(prefs.values['karmopath.saved.v1'], ['a-job']);
  });

  test(
    'a wrongly typed stored value is an error, not a silent empty set',
    () async {
      final prefs = FakeSharedPreferences(initial: {'karmopath.saved.v1': 42});

      await expectLater(
        SharedPreferencesStore(preferences: prefs)
            .readStrings('karmopath.saved.v1'),
        throwsStateError,
      );
    },
  );

  test('writes only the given key and never clears the store', () async {
    final prefs = FakeSharedPreferences(
      initial: {
        'karmopath.saved.v1': <String>['a-job'],
        'karmopath.reminders.v1': <String>['a-job'],
        'karmopath.feed.v1': '{"jobs":[]}',
        'theme': 'dark',
      },
    );
    final store = SharedPreferencesStore(preferences: prefs);

    await store.writeStrings('karmopath.reminders.v1', ['a-job', 'b-job']);

    expect(prefs.values['karmopath.reminders.v1'], ['a-job', 'b-job']);
    expect(prefs.values['karmopath.saved.v1'], ['a-job']);
    expect(prefs.values['karmopath.feed.v1'], '{"jobs":[]}');
    expect(prefs.values['theme'], 'dark');
    expect(prefs.clearCalls, 0, reason: 'clear() would delete unrelated keys');
    expect(prefs.removeCalls, 0);
  });

  group('with LocalUserPreferences', () {
    test('a saved job persists and reloads after a restart', () async {
      final backing = <String, Object>{};

      final first = LocalUserPreferences(
        store: SharedPreferencesStore(
          preferences: FakeSharedPreferences(initial: backing),
        ),
      );
      await first.initialize();
      await first.setSaved('wb-police-2026', true);
      await first.setReminder('wb-police-2026', true);
      first.dispose();

      final next = LocalUserPreferences(
        store: SharedPreferencesStore(
          preferences: FakeSharedPreferences(initial: backing),
        ),
      );
      await next.initialize();

      expect(next.savedJobIds.value, {'wb-police-2026'});
      expect(next.reminderJobIds.value, {'wb-police-2026'});
      next.dispose();
    });

    test('a storage write failure is not shown as a saved job', () async {
      final prefs = FakeSharedPreferences();
      final store = LocalUserPreferences(
        store: SharedPreferencesStore(preferences: prefs),
      );
      await store.initialize();
      prefs.writeError = StateError('disk full');

      await expectLater(store.setSaved('a-job', true), throwsStateError);

      expect(store.savedJobIds.value, isEmpty);
      expect(prefs.values['karmopath.saved.v1'], isNull);
      store.dispose();
    });
  });
}
