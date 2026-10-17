import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/data/cached_job_repository.dart';

import 'fakes.dart';

/// `lastError` reaches the UI, so it must read like prose, never like a log.
void expectUserSafe(String? message) {
  expect(message, isNotNull, reason: 'a visible failure needs a message');
  expect(message, isNotEmpty);
  final lower = message!.toLowerCase();
  for (final token in <String>[
    'exception',
    'error:',
    'http',
    'stack',
    'trace',
    'file:',
    'socket',
  ]) {
    expect(
      lower.contains(token),
      isFalse,
      reason: 'unexpected technical token "$token" in "$message"',
    );
  }
}

void main() {
  group('refresh from the network', () {
    test(
      'a valid feed replaces state and is cached after validation',
      () async {
        final raw = feedJson();
        final cache = FakeCache();
        final repo = CachedJobRepository(
          transport: FakeTransport.json(raw),
          cache: cache,
        );

        await repo.refresh();

        final state = repo.state.value;
        expect(state.feed, isNotNull);
        expect(state.feed!.jobs.single.id, 'wb-police-constable-2026');
        expect(state.isLoading, isFalse);
        expect(state.isOffline, isFalse);
        expect(state.lastError, isNull);
        expect(cache.writes, 1);
        expect(
          cache.stored,
          raw,
          reason: 'the validated document is cached verbatim',
        );
        await repo.dispose();
      },
    );

    test('isLoading is published while the request is in flight', () async {
      final gate = Completer<String>();
      final repo = CachedJobRepository(
        transport: FakeTransport(() => gate.future),
        cache: FakeCache(),
      );
      final recorder = StateRecorder(repo.state);

      final refresh = repo.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(recorder.loadingStates, isNotEmpty);
      expect(recorder.last.isLoading, isTrue);
      expect(recorder.last.feed, isNull);

      gate.complete(feedJson());
      await refresh;
      expect(recorder.last.isLoading, isFalse);
      expect(recorder.last.feed, isNotNull);

      recorder.dispose();
      await repo.dispose();
    });

    test(
      'an invalid payload is never cached and yields a safe error',
      () async {
        final cache = FakeCache();
        final repo = CachedJobRepository(
          transport: FakeTransport.json('{"schema_version":1,"jobs":['),
          cache: cache,
        );

        await repo.refresh();

        final state = repo.state.value;
        expect(state.feed, isNull);
        expect(state.isLoading, isFalse);
        expect(
          state.isOffline,
          isFalse,
          reason: 'the device was online; the payload was untrustworthy',
        );
        expect(state.lastError, CachedJobRepository.invalidFeedNoCacheMessage);
        expect(
          cache.writes,
          0,
          reason: 'nothing unvalidated may become the cache',
        );
        expect(cache.stored, isNull);
        await repo.dispose();
      },
    );

    test('an unknown schema version is rejected like malformed JSON', () async {
      final cache = FakeCache();
      final repo = CachedJobRepository(
        transport: FakeTransport.json(feedJson(schemaVersion: 2)),
        cache: cache,
      );

      await repo.refresh();

      expect(repo.state.value.feed, isNull);
      expect(
        repo.state.value.lastError,
        CachedJobRepository.invalidFeedNoCacheMessage,
      );
      expect(cache.writes, 0);
      await repo.dispose();
    });

    test('duplicate ids reject the whole candidate feed', () async {
      final cache = FakeCache();
      final repo = CachedJobRepository(
        transport: FakeTransport.json(feedJson(jobs: [jobJson(), jobJson()])),
        cache: cache,
      );

      await repo.refresh();

      expect(repo.state.value.feed, isNull);
      expect(cache.writes, 0, reason: 'one bad job fails the whole feed');
      await repo.dispose();
    });

    test(
      'an invalid refresh preserves the previous good feed and cache',
      () async {
        final good = feedJson();
        final transport = SwitchTransport(good);
        final cache = FakeCache();
        final repo = CachedJobRepository(transport: transport, cache: cache);

        await repo.refresh();
        final firstFeed = repo.state.value.feed;
        expect(firstFeed, isNotNull);

        transport.next = feedJson(schemaVersion: 2);
        await repo.refresh();

        final state = repo.state.value;
        expect(
          state.feed,
          same(firstFeed),
          reason: 'the reviewed copy stays on screen',
        );
        expect(state.isOffline, isTrue);
        expect(state.isLoading, isFalse);
        expect(
          state.lastError,
          CachedJobRepository.invalidFeedWithCacheMessage,
        );
        expect(
          cache.stored,
          good,
          reason: 'the last good cache must not be replaced',
        );
        expect(cache.writes, 1);
        await repo.dispose();
      },
    );

    test(
      'a transport failure keeps the good feed and reports offline',
      () async {
        final transport = SwitchTransport(feedJson());
        final cache = FakeCache();
        final repo = CachedJobRepository(transport: transport, cache: cache);

        await repo.refresh();
        final firstFeed = repo.state.value.feed;

        transport.next = StateError('network down');
        await repo.refresh();

        final state = repo.state.value;
        expect(state.feed, same(firstFeed));
        expect(state.isOffline, isTrue);
        expect(state.lastError, CachedJobRepository.offlineWithCacheMessage);
        expectUserSafe(state.lastError);
        await repo.dispose();
      },
    );

    test('first launch without network gives a usable empty state', () async {
      final repo = CachedJobRepository(
        transport: FakeTransport.failing(StateError('offline')),
        cache: FakeCache(),
      );

      await repo.refresh();

      final state = repo.state.value;
      expect(state.feed, isNull);
      expect(state.isLoading, isFalse);
      expect(state.isOffline, isTrue);
      expect(state.lastError, CachedJobRepository.offlineNoCacheMessage);
      expectUserSafe(state.lastError);
      await repo.dispose();
    });

    test('a failed refresh can be retried successfully', () async {
      final transport = SwitchTransport(StateError('timeout'));
      final repo = CachedJobRepository(
        transport: transport,
        cache: FakeCache(),
      );

      await repo.refresh();
      expect(repo.state.value.feed, isNull);

      transport.next = feedJson();
      await repo.refresh();

      expect(repo.state.value.feed, isNotNull);
      expect(repo.state.value.isOffline, isFalse);
      expect(repo.state.value.lastError, isNull);
      await repo.dispose();
    });
  });

  group('cache handling', () {
    test('the saved feed is shown before the network answers', () async {
      final savedRaw = feedJson(
        jobs: [jobJson(id: 'saved-only-2026')],
        updatedAt: '2025-12-31T00:00:00Z',
      );
      final gate = Completer<String>();
      final repo = CachedJobRepository(
        transport: FakeTransport(() => gate.future),
        cache: FakeCache(stored: savedRaw),
      );
      final recorder = StateRecorder(repo.state);

      final refresh = repo.refresh();
      await Future<void>.delayed(Duration.zero);

      expect(recorder.last.feed, isNotNull, reason: 'cache-first hydration');
      expect(recorder.last.feed!.jobs.single.id, 'saved-only-2026');
      expect(recorder.last.isLoading, isTrue);
      expect(recorder.last.isOffline, isTrue);

      gate.complete(feedJson());
      await refresh;
      expect(recorder.last.isOffline, isFalse);
      expect(recorder.last.isLoading, isFalse);
      expect(recorder.last.feed!.jobs.single.id, 'wb-police-constable-2026');

      recorder.dispose();
      await repo.dispose();
    });

    test(
      'a corrupt cache is repaired by the next successful refresh',
      () async {
        final raw = feedJson();
        final cache = FakeCache(stored: 'not json at all');
        final repo = CachedJobRepository(
          transport: FakeTransport.json(raw),
          cache: cache,
        );

        await repo.refresh();

        final state = repo.state.value;
        expect(state.feed, isNotNull);
        expect(state.isOffline, isFalse);
        expect(
          state.lastError,
          isNull,
          reason: 'recovery needs no scary banner',
        );
        expect(cache.stored, raw, reason: 'the broken copy is replaced');
        expect(cache.writes, 1);
        await repo.dispose();
      },
    );

    test(
      'a corrupt cache without network reports damage, not a crash',
      () async {
        final repo = CachedJobRepository(
          transport: FakeTransport.failing(StateError('offline')),
          cache: FakeCache(stored: '{"schema_version":1,"jobs":42}'),
        );

        await repo.refresh();

        final state = repo.state.value;
        expect(state.feed, isNull);
        expect(state.isOffline, isTrue);
        expect(state.lastError, CachedJobRepository.corruptCacheMessage);
        expectUserSafe(state.lastError);
        await repo.dispose();
      },
    );

    test(
      'a saved feed with an unknown schema is not offered to the UI',
      () async {
        final repo = CachedJobRepository(
          transport: FakeTransport.failing(StateError('offline')),
          cache: FakeCache(stored: feedJson(schemaVersion: 7)),
        );

        await repo.refresh();

        expect(repo.state.value.feed, isNull);
        expect(
          repo.state.value.lastError,
          CachedJobRepository.corruptCacheMessage,
        );
        await repo.dispose();
      },
    );

    test('a cache read failure behaves like an empty cache', () async {
      final raw = feedJson();
      final cache = FakeCache()..readError = StateError('unreadable file');
      final repo = CachedJobRepository(
        transport: FakeTransport.json(raw),
        cache: cache,
      );

      await repo.refresh();

      expect(repo.state.value.feed, isNotNull);
      expect(repo.state.value.lastError, isNull);
      expect(cache.stored, raw);
      await repo.dispose();
    });

    test('a cache write failure still shows fresh data and says so', () async {
      final cache = FakeCache()..writeError = StateError('disk full');
      final repo = CachedJobRepository(
        transport: FakeTransport.json(feedJson()),
        cache: cache,
      );

      await repo.refresh();

      final state = repo.state.value;
      expect(state.feed, isNotNull, reason: 'fresh valid data is still useful');
      expect(state.isOffline, isFalse);
      expect(state.lastError, CachedJobRepository.cacheWriteFailedMessage);
      expectUserSafe(state.lastError);
      await repo.dispose();
    });

    test('a repository hydrates a previously cached feed offline', () async {
      final cache = FakeCache();
      final online = CachedJobRepository(
        transport: FakeTransport.json(feedJson()),
        cache: cache,
      );
      await online.refresh();
      await online.dispose();

      final offline = CachedJobRepository(
        transport: FakeTransport.failing(StateError('offline')),
        cache: cache,
      );
      await offline.refresh();

      final state = offline.state.value;
      expect(state.feed, isNotNull);
      expect(state.feed!.jobs.single.id, 'wb-police-constable-2026');
      expect(state.isOffline, isTrue);
      await offline.dispose();
    });
  });

  group('concurrency and lifecycle', () {
    test('concurrent refreshes share one transport attempt', () async {
      final gate = Completer<String>();
      final transport = FakeTransport(() => gate.future);
      final cache = FakeCache();
      final repo = CachedJobRepository(transport: transport, cache: cache);

      final first = repo.refresh();
      final second = repo.refresh();
      final third = repo.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(transport.calls, 1, reason: 'a refresh race must not fan out');

      // A call that arrives while the first attempt is still waiting joins it.
      final fourth = repo.refresh();
      gate.complete(feedJson());
      await Future.wait([first, second, third, fourth]);

      expect(transport.calls, 1);
      expect(cache.writes, 1, reason: 'one validated write, not three');
      expect(repo.state.value.feed, isNotNull);
      await repo.dispose();
    });

    test(
      'a refresh after the in-flight one finishes is a new attempt',
      () async {
        final transport = FakeTransport.json(feedJson());
        final repo = CachedJobRepository(
          transport: transport,
          cache: FakeCache(),
        );

        await repo.refresh();
        await repo.refresh();

        expect(transport.calls, 2);
        await repo.dispose();
      },
    );

    test(
      'dispose during flight prevents late state and cache writes',
      () async {
        final gate = Completer<String>();
        final transport = FakeTransport(() => gate.future);
        final cache = FakeCache();
        final repo = CachedJobRepository(transport: transport, cache: cache);

        final refresh = repo.refresh();
        await Future<void>.delayed(Duration.zero);
        expect(transport.calls, 1);
        await repo.dispose();

        gate.complete(feedJson());
        await refresh;

        expect(
          cache.writes,
          0,
          reason: 'a disposed repository must not commit',
        );
      },
    );

    test('refresh after dispose completes quietly', () async {
      final repo = CachedJobRepository(
        transport: FakeTransport.json(feedJson()),
        cache: FakeCache(),
      );
      await repo.dispose();
      await repo.refresh();
    });
  });
}
