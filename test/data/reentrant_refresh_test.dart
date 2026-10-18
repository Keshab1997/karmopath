import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/data/cached_job_repository.dart';
import 'package:karmopath/data/feed_cache.dart';
import 'package:karmopath/data/feed_transport.dart';

import 'fakes.dart';

/// Regression suite for batch 3: re-entrant refresh and lifecycle correctness.
///
/// Every test here is about *ordering*: what a synchronous `ValueNotifier`
/// listener is allowed to do while the repository is publishing a state, and
/// what must not happen after `dispose()`.
void main() {
  group('re-entrant refresh from a listener', () {
    test('a listener that refreshes on the loading notification does not duplicate the attempt', () async {
      final transport = FakeTransport.json(feedJson());
      final cache = FakeCache();
      final repo = CachedJobRepository(transport: transport, cache: cache);

      var triggered = false;
      Future<void>? listenerRefresh;
      void listener() {
        if (triggered) return; // one-shot: never recurse forever
        if (!repo.state.value.isLoading) return;
        triggered = true;
        // Exactly what a "pull to refresh" banner or a retry widget does:
        // ask for a refresh from inside the state callback.
        listenerRefresh = repo.refresh();
      }

      repo.state.addListener(listener);
      final caller = repo.refresh();
      await caller;
      await listenerRefresh;

      expect(triggered, isTrue, reason: 'the listener really did re-enter');
      expect(transport.calls, 1, reason: 'one attempt, not two');
      expect(cache.writes, 1, reason: 'one commit, not two');
      expect(repo.state.value.feed, isNotNull);
      expect(repo.state.value.isLoading, isFalse);

      repo.state.removeListener(listener);
      await repo.dispose();
    });

    test(
      'the re-entrant caller joins the attempt it was notified by',
      () async {
        final gate = Completer<String>();
        final transport = FakeTransport(() => gate.future);
        final repo = CachedJobRepository(
          transport: transport,
          cache: FakeCache(),
        );

        Future<void>? joined;
        var once = false;
        void listener() {
          if (once) return;
          once = true;
          joined = repo.refresh();
        }

        repo.state.addListener(listener);
        final caller = repo.refresh();
        await Future<void>.delayed(Duration.zero);

        expect(transport.calls, 1);
        // The joined future must be the very same in-flight attempt.
        expect(joined, isNotNull);
        expect(identical(joined, caller), isTrue);

        gate.complete(feedJson());
        await Future.wait([caller, joined!]);
        repo.state.removeListener(listener);
        await repo.dispose();
      },
    );

    test(
      'the single-flight marker is free again after a re-entrant attempt',
      () async {
        final transport = FakeTransport.json(feedJson());
        final repo = CachedJobRepository(
          transport: transport,
          cache: FakeCache(),
        );

        var once = false;
        void listener() {
          if (once) return;
          once = true;
          if (repo.state.value.isLoading) unawaited(repo.refresh());
        }

        repo.state.addListener(listener);
        await repo.refresh();
        expect(transport.calls, 1);

        // A later, ordinary refresh must be a brand-new attempt.
        await repo.refresh();
        expect(transport.calls, 2, reason: 'the marker must not stay stuck');

        repo.state.removeListener(listener);
        await repo.dispose();
      },
    );
  });

  group('listener-triggered retry after a failure', () {
    test(
      'a listener reacting to the error state starts a new attempt',
      () async {
        final transport = SwitchTransport(StateError('offline'));
        final repo = CachedJobRepository(
          transport: transport,
          cache: FakeCache(),
        );

        var retried = false;
        Future<void>? retryFuture;
        void listener() {
          final state = repo.state.value;
          if (retried || state.isLoading) return;
          if (state.lastError == null) return;
          retried = true;
          transport.next =
              feedJson(); // the network is back when the user retries
          retryFuture = repo.refresh(); // "tap to retry" from the error banner
        }

        repo.state.addListener(listener);
        await repo.refresh();
        await retryFuture;

        expect(retried, isTrue);
        expect(
          transport.calls,
          2,
          reason:
              'the retry must be a real attempt, not a join with a dead one',
        );
        expect(repo.state.value.feed, isNotNull);
        expect(repo.state.value.lastError, isNull);

        repo.state.removeListener(listener);
        await repo.dispose();
      },
    );
  });

  group('disposal from a state listener', () {
    test(
      'disposing while loading stops the attempt before any transport call',
      () async {
        final transport = FakeTransport.json(feedJson());
        final cache = FakeCache();
        final repo = CachedJobRepository(transport: transport, cache: cache);

        var disposed = false;
        void listener() {
          if (disposed) return;
          if (!repo.state.value.isLoading) return;
          disposed = true;
          unawaited(repo.dispose());
        }

        repo.state.addListener(listener);
        await repo.refresh();

        expect(disposed, isTrue);
        expect(transport.calls, 0, reason: 'no fetch may start after disposal');
        expect(cache.writes, 0);
        expect(
          cache.reads,
          0,
          reason:
              'disposal lands before the cache read even begins, so the '
              'attempt stops at the loading notification',
        );
        expect(
          repo.state.value.isLoading,
          isTrue,
          reason: 'no late state value',
        );
      },
    );

    test(
      'disposing while loading an already-loaded feed fetches nothing new',
      () async {
        final transport = FakeTransport.json(feedJson());
        final repo = CachedJobRepository(
          transport: transport,
          cache: FakeCache(),
        );
        await repo.refresh();
        expect(transport.calls, 1);

        var disposed = false;
        void listener() {
          if (disposed) return;
          if (!repo.state.value.isLoading) return;
          disposed = true;
          unawaited(repo.dispose());
        }

        repo.state.addListener(listener);
        await repo.refresh(); // feed is already in memory: no cache read first

        expect(disposed, isTrue);
        expect(
          transport.calls,
          1,
          reason:
              'the loading emission happens before the fetch, so dispose must '
              'be checked before fetching again',
        );
      },
    );

    test('a pending refresh future completes when disposal happens', () async {
      final gate = Completer<String>();
      final transport = FakeTransport(() => gate.future);
      final repo = CachedJobRepository(
        transport: transport,
        cache: FakeCache(),
      );

      final pending = repo.refresh();
      await Future<void>.delayed(Duration.zero);
      await repo.dispose();

      // Must not hang until the transport decides to answer.
      await pending.timeout(const Duration(seconds: 2));

      gate.complete(feedJson());
      await Future<void>.delayed(Duration.zero);
      expect(
        repo.state.value.feed,
        isNull,
        reason: 'nothing published after dispose',
      );
    });
  });

  group('disposal during an await', () {
    test(
      'disposal during the cache read prevents the transport fetch',
      () async {
        final readGate = Completer<String?>();
        final cache = CacheWithGates(onRead: () => readGate.future);
        final transport = FakeTransport.json(feedJson());
        final repo = CachedJobRepository(transport: transport, cache: cache);

        final pending = repo.refresh();
        await Future<void>.delayed(Duration.zero);
        await repo.dispose();

        readGate.complete(feedJson());
        await pending;

        expect(transport.calls, 0, reason: 'disposed before the fetch');
        expect(cache.writes, 0);
      },
    );

    test('disposal during the fetch prevents the cache write', () async {
      final fetchGate = Completer<String>();
      final transport = FakeTransport(() => fetchGate.future);
      final cache = FakeCache();
      final repo = CachedJobRepository(transport: transport, cache: cache);

      final pending = repo.refresh();
      await Future<void>.delayed(Duration.zero);
      await repo.dispose();

      fetchGate.complete(feedJson());
      await pending;

      expect(
        cache.writes,
        0,
        reason: 'no new cache write begun after disposal',
      );
      expect(cache.stored, isNull);
    });

    test('a cache write already begun when dispose lands finishes, but is not published', () async {
      final writeGate = Completer<void>();
      final cache = CacheWithGates(onWrite: () => writeGate.future);
      final repo = CachedJobRepository(
        transport: FakeTransport.json(feedJson()),
        cache: cache,
      );

      final notifications = <bool>[];
      repo.state.addListener(
        () => notifications.add(repo.state.value.isLoading),
      );

      final pending = repo.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(cache.writes, 1, reason: 'the write had already begun');

      await repo.dispose();
      final countAtDispose = notifications.length;
      writeGate.complete();
      await pending;
      await Future<void>.delayed(Duration.zero);

      expect(
        notifications.length,
        countAtDispose,
        reason: 'no state notification may follow disposal',
      );
      expect(
        cache.stored,
        isNotNull,
        reason:
            'documented boundary: an already-started platform write is not '
            'cancelled retroactively',
      );
    });
  });

  group('no permanently stuck in-flight marker', () {
    test(
      'a transport that throws synchronously still frees the marker',
      () async {
        final transport = SyncThrowingTransport();
        final repo = CachedJobRepository(
          transport: transport,
          cache: FakeCache(),
        );

        await repo.refresh();
        expect(transport.calls, 1);
        expect(repo.state.value.isLoading, isFalse);
        expect(
          repo.state.value.lastError,
          CachedJobRepository.offlineNoCacheMessage,
        );

        transport.failSynchronously = false;
        await repo.refresh();
        expect(transport.calls, 2, reason: 'the next refresh must run');
        expect(repo.state.value.feed, isNotNull);
        await repo.dispose();
      },
    );

    test(
      'a cache that throws synchronously does not wedge the repository',
      () async {
        final cache = ThrowingCache();
        final repo = CachedJobRepository(
          transport: FakeTransport.json(feedJson()),
          cache: cache,
        );

        await repo.refresh();
        expect(
          repo.state.value.feed,
          isNotNull,
          reason: 'the fetch still completes',
        );
        expect(
          repo.state.value.lastError,
          CachedJobRepository.cacheWriteFailedMessage,
        );

        cache.throwOnWrite = false;
        await repo.refresh();
        expect(cache.writes, 2);
        expect(repo.state.value.lastError, isNull);
        await repo.dispose();
      },
    );

    test('refresh after disposal returns without work', () async {
      final transport = FakeTransport.json(feedJson());
      final repo = CachedJobRepository(
        transport: transport,
        cache: FakeCache(),
      );
      await repo.dispose();

      await repo.refresh();
      await repo.dispose(); // idempotent

      expect(transport.calls, 0);
    });
  });
}

/// Cache whose reads/writes can be held open by the test.
class CacheWithGates implements FeedCache {
  CacheWithGates({this.onRead, this.onWrite});

  final Future<String?> Function()? onRead;
  final Future<void> Function()? onWrite;
  final FakeCache _inner = FakeCache();
  int reads = 0;
  int writes = 0;

  String? get stored => _inner.stored;

  @override
  Future<String?> read() async {
    reads++;
    final gate = onRead;
    if (gate != null) await gate();
    return _inner.stored;
  }

  @override
  Future<void> write(String raw) async {
    writes++;
    final gate = onWrite;
    if (gate != null) await gate();
    _inner.stored = raw;
  }
}

/// Transport that fails by throwing before it ever returns a Future.
class SyncThrowingTransport implements FeedTransport {
  int calls = 0;
  bool failSynchronously = true;

  @override
  Future<String> fetch() {
    calls++;
    if (failSynchronously) throw StateError('synchronous adapter failure');
    return Future<String>.value(feedJson());
  }
}

/// Cache that fails by throwing before it ever returns a Future.
class ThrowingCache implements FeedCache {
  int writes = 0;
  bool throwOnWrite = true;

  @override
  Future<String?> read() => Future<String?>.value(null);

  @override
  Future<void> write(String raw) {
    writes++;
    if (throwOnWrite) throw StateError('synchronous store failure');
    return Future<void>.value();
  }
}
