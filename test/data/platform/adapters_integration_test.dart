import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/data/cached_job_repository.dart';
import 'package:karmopath/data/platform/http_feed_transport.dart';
import 'package:karmopath/data/platform/preferences_feed_cache.dart';

import '../fakes.dart';
import 'fake_http_client.dart';
import 'fake_shared_preferences.dart';

/// Adapters wired exactly as the captain will wire them, minus the network:
/// `HttpFeedTransport` -> `CachedJobRepository` -> `PreferencesFeedCache`.
///
/// Proves the seam holds: what the transport accepts is what the repository
/// validates, and only validated documents become the persisted cache.
final Uri feedUrl = Uri.parse('https://feed.example.org/karmopath/jobs.json');

CachedJobRepository build({
  required FakeHttpClient client,
  required Map<String, Object> storage,
}) => CachedJobRepository(
  transport: HttpFeedTransport(feedUrl: feedUrl, client: client),
  cache: PreferencesFeedCache(
    preferences: FakeSharedPreferences(initial: storage),
  ),
);

void main() {
  test(
    'a fetched feed is validated, cached and reloads after a restart',
    () async {
      final storage = <String, Object>{};
      final online = build(
        client: FakeHttpClient.respond(body: feedJson()),
        storage: storage,
      );

      await online.refresh();
      expect(
        online.state.value.feed?.jobs.single.id,
        'wb-police-constable-2026',
      );
      expect(online.state.value.isOffline, isFalse);
      expect(online.state.value.lastError, isNull);
      expect(storage[PreferencesFeedCache.cacheKey], feedJson());
      await online.dispose();

      // Next launch, offline: the same persisted map is all that survives.
      final offline = build(
        client: FakeHttpClient(
          onSend: (_) async => throw StateError('offline'),
        ),
        storage: storage,
      );
      await offline.refresh();

      final state = offline.state.value;
      expect(state.feed?.jobs.single.id, 'wb-police-constable-2026');
      expect(state.isOffline, isTrue);
      expect(state.lastError, CachedJobRepository.offlineWithCacheMessage);
      await offline.dispose();
    },
  );

  test('an invalid HTTP document never reaches the cache', () async {
    final storage = <String, Object>{};
    final repo = build(
      client: FakeHttpClient.respond(body: feedJson(schemaVersion: 2)),
      storage: storage,
    );

    await repo.refresh();

    expect(repo.state.value.feed, isNull);
    expect(
      repo.state.value.lastError,
      CachedJobRepository.invalidFeedNoCacheMessage,
    );
    expect(storage, isEmpty, reason: 'unvalidated bytes are never persisted');
    await repo.dispose();
  });

  test('a non-200 keeps the previously cached feed on screen', () async {
    final storage = <String, Object>{};
    final online = build(
      client: FakeHttpClient.respond(body: feedJson()),
      storage: storage,
    );
    await online.refresh();
    await online.dispose();

    final next = build(
      client: FakeHttpClient.respond(statusCode: 503),
      storage: storage,
    );
    await next.refresh();

    expect(next.state.value.feed, isNotNull);
    expect(next.state.value.isOffline, isTrue);
    expect(
      next.state.value.lastError,
      CachedJobRepository.offlineWithCacheMessage,
    );
    expect(storage[PreferencesFeedCache.cacheKey], feedJson());
    await next.dispose();
  });

  test('an oversized body is a safe repository error, not a crash', () async {
    final storage = <String, Object>{};
    final repo = CachedJobRepository(
      transport: HttpFeedTransport(
        feedUrl: feedUrl,
        client: FakeHttpClient.respond(
          body: jsonEncode({'padding': 'x' * 5000}),
        ),
        maxBytes: 1024,
      ),
      cache: PreferencesFeedCache(
        preferences: FakeSharedPreferences(initial: storage),
      ),
    );

    await repo.refresh();

    expect(repo.state.value.feed, isNull);
    expect(
      repo.state.value.lastError,
      CachedJobRepository.offlineNoCacheMessage,
    );
    expect(storage, isEmpty);
    await repo.dispose();
  });

  test('invalid UTF-8 is a safe repository error, not a crash', () async {
    final storage = <String, Object>{};
    final repo = CachedJobRepository(
      transport: HttpFeedTransport(
        feedUrl: feedUrl,
        client: FakeHttpClient.bytes(bytes: [0x7B, 0xC3, 0x28, 0x7D]),
      ),
      cache: PreferencesFeedCache(
        preferences: FakeSharedPreferences(initial: storage),
      ),
    );

    await repo.refresh();

    expect(repo.state.value.feed, isNull);
    expect(
      repo.state.value.lastError,
      CachedJobRepository.offlineNoCacheMessage,
    );
    expect(storage, isEmpty);
    await repo.dispose();
  });
}
