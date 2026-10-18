import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/app/runtime/native_storage.dart';
import 'package:karmopath/features/common/app_language.dart';

import '../data/platform/fake_shared_preferences.dart';

void main() {
  test(
    'absent language defaults Bengali without writing or clearing anything',
    () async {
      final shared = FakeSharedPreferences();
      final storage = await NativeStorage.open(preferences: shared);
      expect(await storage.readLanguage(), AppLang.bn);
      expect(shared.setCalls, 0);
      await storage.close();
      expect(shared.removeCalls, 0);
      expect(shared.clearCalls, 0);
    },
  );
  test(
    'language persists across sessions; other preferences/cache stay intact',
    () async {
      final values = <String, Object>{
        'theme': 'dark',
        'karmopath.saved.v1': ['a-job'],
        'karmopath.feed.v1': '{"sample":"cache-only"}',
      };
      final shared = FakeSharedPreferences(initial: values);
      final first = await NativeStorage.open(preferences: shared);
      await first.writeLanguage(AppLang.en);
      await first.close();
      final second = await NativeStorage.open(
        preferences: FakeSharedPreferences(initial: values),
      );
      expect(await second.readLanguage(), AppLang.en);
      expect(await second.preferences.readStrings('karmopath.saved.v1'), [
        'a-job',
      ]);
      expect(await second.feedCache.read(), '{"sample":"cache-only"}');
      expect(values['theme'], 'dark');
      expect(shared.writtenKeys, [NativeStorage.languageKey]);
      expect(shared.clearCalls, 0);
      expect(shared.removeCalls, 0);
      await second.close();
    },
  );
  test(
    'unknown language is an init failure, not an empty/default overwrite',
    () async {
      final shared = FakeSharedPreferences(
        initial: {NativeStorage.languageKey: 'unknown'},
      );
      final storage = await NativeStorage.open(preferences: shared);
      await expectLater(storage.readLanguage(), throwsFormatException);
      expect(shared.values[NativeStorage.languageKey], 'unknown');
      expect(shared.setCalls, 0);
      await storage.close();
    },
  );
  test(
    'language read/write failures propagate and preserve stored language',
    () async {
      final shared = FakeSharedPreferences(
        initial: {NativeStorage.languageKey: 'bn'},
      );
      final storage = await NativeStorage.open(preferences: shared);
      shared.readError = StateError('read failed');
      await expectLater(storage.readLanguage(), throwsStateError);
      shared.readError = null;
      shared.writeError = StateError('write failed');
      await expectLater(storage.writeLanguage(AppLang.en), throwsStateError);
      expect(shared.values[NativeStorage.languageKey], 'bn');
      await storage.close();
    },
  );
}
