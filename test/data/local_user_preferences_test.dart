import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/data/local_user_preferences.dart';

import 'fakes.dart';

void main() {
  group('initialize', () {
    test('loads both sets as immutable snapshots', () async {
      final store = FakePreferencesStore(
        initial: {
          LocalUserPreferences.savedKey: ['b-job', 'a-job', 'a-job', '  '],
          LocalUserPreferences.remindersKey: ['a-job'],
        },
      );
      final prefs = LocalUserPreferences(store: store);

      await prefs.initialize();

      expect(prefs.savedJobIds.value, {'a-job', 'b-job'});
      expect(prefs.reminderJobIds.value, {'a-job'});
      expect(
        () => prefs.savedJobIds.value.add('sneaky'),
        throwsUnsupportedError,
        reason: 'published sets must be immutable snapshots',
      );
      expect(
        () => prefs.reminderJobIds.value.remove('a-job'),
        throwsUnsupportedError,
      );
      prefs.dispose();
    });

    test('missing keys yield empty sets, not nulls', () async {
      final prefs = LocalUserPreferences(store: FakePreferencesStore());

      await prefs.initialize();

      expect(prefs.savedJobIds.value, isEmpty);
      expect(prefs.reminderJobIds.value, isEmpty);
      prefs.dispose();
    });

    test('is idempotent and reads each key once', () async {
      final store = FakePreferencesStore();
      final prefs = LocalUserPreferences(store: store);

      await prefs.initialize();
      await prefs.initialize();

      expect(store.readCounts[LocalUserPreferences.savedKey], 1);
      expect(store.readCounts[LocalUserPreferences.remindersKey], 1);
      prefs.dispose();
    });

    test('a read failure is rethrown, not disguised as empty', () async {
      final store = FakePreferencesStore(
        initial: {
          LocalUserPreferences.savedKey: ['a-job'],
        },
      )..readErrors[LocalUserPreferences.savedKey] = StateError('unreadable');

      final prefs = LocalUserPreferences(store: store);
      await expectLater(prefs.initialize(), throwsStateError);

      // Nothing was loaded, so the empty set is honest rather than invented.
      expect(prefs.savedJobIds.value, isEmpty);

      // A later attempt retries instead of caching the failure forever.
      store.readErrors.clear();
      await prefs.initialize();
      expect(prefs.savedJobIds.value, {'a-job'});
      prefs.dispose();
    });
  });

  group('setSaved', () {
    test(
      'persists under the versioned key and publishes a sorted snapshot',
      () async {
        final store = FakePreferencesStore();
        final prefs = LocalUserPreferences(store: store);
        await prefs.initialize();

        await prefs.setSaved('wb-police-2026', true);

        expect(prefs.savedJobIds.value, {'wb-police-2026'});
        expect(prefs.savedJobIds.value, isA<Set<String>>());
        expect(store.data[LocalUserPreferences.savedKey], [
          'wb-police-2026',
        ], reason: 'persisted lists are stable for diffing and debugging');
        prefs.dispose();
      },
    );

    test('removing persists the remaining ids', () async {
      final store = FakePreferencesStore(
        initial: {
          LocalUserPreferences.savedKey: ['a-job', 'b-job'],
        },
      );
      final prefs = LocalUserPreferences(store: store);
      await prefs.initialize();

      await prefs.setSaved('a-job', false);

      expect(prefs.savedJobIds.value, {'b-job'});
      expect(store.data[LocalUserPreferences.savedKey], ['b-job']);
      prefs.dispose();
    });

    test('re-setting the same value performs no write', () async {
      final store = FakePreferencesStore();
      final prefs = LocalUserPreferences(store: store);
      await prefs.initialize();

      await prefs.setSaved('a-job', true);
      await prefs.setSaved('a-job', true);

      expect(store.writeCounts[LocalUserPreferences.savedKey], 1);
      prefs.dispose();
    });

    test('a write failure is visible and publishes nothing', () async {
      final store = FakePreferencesStore()
        ..writeError = StateError('persistence unavailable');
      final prefs = LocalUserPreferences(store: store);
      await prefs.initialize();

      await expectLater(prefs.setSaved('a-job', true), throwsStateError);

      expect(
        prefs.savedJobIds.value,
        isEmpty,
        reason: 'an unsaved bookmark must never look saved',
      );
      expect(store.data, isEmpty);

      store.writeError = null;
      await prefs.setSaved('a-job', true);
      expect(prefs.savedJobIds.value, {
        'a-job',
      }, reason: 'one failure must not poison later writes');
      prefs.dispose();
    });

    test(
      'writes merge with stored ids even before initialize is awaited',
      () async {
        final store = FakePreferencesStore(
          initial: {
            LocalUserPreferences.savedKey: ['older-job'],
          },
        );
        final prefs = LocalUserPreferences(store: store);

        await prefs.setSaved('newer-job', true);

        expect(prefs.savedJobIds.value, {'older-job', 'newer-job'});
        expect(store.data[LocalUserPreferences.savedKey], [
          'newer-job',
          'older-job',
        ]);
        prefs.dispose();
      },
    );

    test('two rapid toggles are both persisted in call order', () async {
      final store = FakePreferencesStore();
      final prefs = LocalUserPreferences(store: store);
      await prefs.initialize();

      final first = prefs.setSaved('a-job', true);
      final second = prefs.setSaved('b-job', true);
      await Future.wait([first, second]);

      expect(prefs.savedJobIds.value, {'a-job', 'b-job'});
      expect(store.data[LocalUserPreferences.savedKey], ['a-job', 'b-job']);
      expect(store.writeCounts[LocalUserPreferences.savedKey], 2);
      prefs.dispose();
    });

    test('a blank id is rejected before it reaches the store', () async {
      final store = FakePreferencesStore();
      final prefs = LocalUserPreferences(store: store);
      await prefs.initialize();

      await expectLater(prefs.setSaved('   ', true), throwsArgumentError);

      expect(store.writeCounts, isEmpty);
      prefs.dispose();
    });

    test('listeners receive each published snapshot', () async {
      final prefs = LocalUserPreferences(store: FakePreferencesStore());
      await prefs.initialize();
      final seen = <Set<String>>[];
      void listener() => seen.add(prefs.savedJobIds.value);
      prefs.savedJobIds.addListener(listener);

      await prefs.setSaved('a-job', true);
      await prefs.setSaved('a-job', false);

      expect(seen, [
        {'a-job'},
        <String>{},
      ]);
      prefs.savedJobIds.removeListener(listener);
      prefs.dispose();
    });
  });

  group('reminders', () {
    test('reminder intent is stored apart from saved jobs', () async {
      final store = FakePreferencesStore();
      final prefs = LocalUserPreferences(store: store);
      await prefs.initialize();

      await prefs.setReminder('wb-police-2026', true);

      expect(prefs.reminderJobIds.value, {'wb-police-2026'});
      expect(prefs.savedJobIds.value, isEmpty);
      expect(store.data[LocalUserPreferences.remindersKey], ['wb-police-2026']);
      expect(store.data.containsKey(LocalUserPreferences.savedKey), isFalse);
      prefs.dispose();
    });

    test('reminder persistence failure is visible', () async {
      final store = FakePreferencesStore()
        ..writeError = StateError('persistence unavailable');
      final prefs = LocalUserPreferences(store: store);
      await prefs.initialize();

      await expectLater(prefs.setReminder('a-job', true), throwsStateError);

      expect(
        prefs.reminderJobIds.value,
        isEmpty,
        reason: 'permission/denial handling must never invent a reminder',
      );
      prefs.dispose();
    });

    test('reminder and saved keys keep their versioned names', () {
      expect(LocalUserPreferences.savedKey, 'karmopath.saved.v1');
      expect(LocalUserPreferences.remindersKey, 'karmopath.reminders.v1');
    });
  });
}
