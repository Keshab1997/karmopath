import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../contracts/job_feed.dart';
import '../contracts/job_repository.dart';
import 'feed_cache.dart';
import 'feed_transport.dart';

/// Repository that serves a strictly validated job feed and keeps the last
/// known good copy in an injected cache.
///
/// Rules this class enforces (see `docs/CONTRACTS.md`):
///  * The transport payload is validated **before** anything is cached, so a
///    malformed or unknown-schema document can never become the offline copy.
///  * A failed or invalid refresh preserves the previous good feed and the
///    previous cache; the failure is visible through [JobFeedState.lastError].
///  * Concurrent [refresh] calls share one in-flight attempt instead of racing
///    each other, so two responses cannot interleave and commit out of order.
///  * A corrupt cache is discarded and recovered by the next successful
///    refresh; it never crashes the app and never masquerades as fresh data.
///  * [JobFeedState.lastError] is always user-safe prose: no exception types,
///    URLs, stack traces or HTTP status codes.
///
/// [JobFeedState.isOffline] means "what you see is not fresh from the network":
/// it is true while a saved copy is on screen or the network failed, and false
/// when the server answered with unusable data and nothing is shown.
class CachedJobRepository implements JobRepository {
  CachedJobRepository({required this._transport, required this._cache});

  /// Shown when fresh data could not be fetched but a saved copy is on screen.
  static const String offlineWithCacheMessage =
      'You are offline. Showing the last saved job list.';

  /// Shown on a first launch that has neither network nor a saved copy.
  static const String offlineNoCacheMessage =
      'Could not load jobs. Check your internet connection and try again.';

  /// Shown when a saved copy exists but the freshly fetched one could not be
  /// trusted, so the app kept the reviewed copy on screen.
  static const String invalidFeedWithCacheMessage =
      'The job list could not be verified, so the last saved copy is shown.';

  /// Shown when the only fetched copy was invalid and nothing was saved yet.
  static const String invalidFeedNoCacheMessage =
      'The job list could not be verified, so no jobs are shown. '
      'Please try again later.';

  /// Shown when the saved copy itself was damaged and no fresh copy arrived.
  static const String corruptCacheMessage =
      'The saved job list could not be read. Connect to the internet to '
      'load jobs again.';

  /// Shown when fresh data loaded but the offline copy could not be written.
  static const String cacheWriteFailedMessage =
      'Jobs are up to date, but the offline copy could not be saved.';

  final FeedTransport _transport;
  final FeedCache _cache;

  final ValueNotifier<JobFeedState> _state = ValueNotifier<JobFeedState>(
    const JobFeedState(),
  );

  Future<void>? _inFlight;
  bool _disposed = false;

  @override
  ValueListenable<JobFeedState> get state => _state;

  /// Loads a saved copy when there is none in memory yet, then refreshes from
  /// the transport. Never throws for network, validation or cache problems:
  /// every outcome is reported through [state].
  @override
  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    final running = _inFlight;
    if (running != null) return running;
    return _inFlight = _runRefresh();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return; // idempotent: double disposal must not assert
    // Mark first: any in-flight attempt checks this flag before emitting or
    // writing, so a slow transport cannot revive a disposed repository.
    _disposed = true;
    _state.dispose();
  }

  Future<void> _runRefresh() async {
    try {
      final previous = _state.value;
      _emit(
        feed: previous.feed,
        isLoading: true,
        isOffline: previous.isOffline,
        lastError: previous.lastError,
      );

      JobFeed? feed = previous.feed;
      String? cacheNote;
      if (feed == null) {
        final saved = await _readSavedFeed();
        if (_disposed) return;
        feed = saved.feed;
        if (feed != null) {
          // Show the saved copy immediately, still marked as stale/last-known.
          _emit(feed: feed, isLoading: true, isOffline: true, lastError: null);
        } else if (saved.corrupt) {
          cacheNote = corruptCacheMessage;
        }
      }

      try {
        final raw = await _transport.fetch();
        final fresh = _parse(raw); // validate fully before any cache commit
        if (_disposed) return;
        var warning = cacheNote;
        try {
          await _cache.write(raw);
          warning = null; // a successful refresh also repairs a corrupt cache
        } catch (_) {
          warning = cacheWriteFailedMessage;
        }
        if (_disposed) return;
        _emit(
          feed: fresh,
          isLoading: false,
          isOffline: false,
          lastError: warning,
        );
      } on _InvalidFeed {
        if (_disposed) return;
        _emit(
          feed: feed,
          isLoading: false,
          isOffline: feed != null,
          lastError: feed == null
              ? invalidFeedNoCacheMessage
              : invalidFeedWithCacheMessage,
        );
      } catch (_) {
        if (_disposed) return;
        _emit(
          feed: feed,
          isLoading: false,
          isOffline: true,
          lastError: feed == null
              ? (cacheNote ?? offlineNoCacheMessage)
              : offlineWithCacheMessage,
        );
      }
    } finally {
      _inFlight = null;
    }
  }

  /// Reads and validates the saved copy. A read error and a damaged document
  /// are treated the same way: no usable copy, recover on the next refresh.
  Future<_SavedFeed> _readSavedFeed() async {
    String? raw;
    try {
      raw = await _cache.read();
    } catch (_) {
      return const _SavedFeed.corrupt();
    }
    if (raw == null || raw.trim().isEmpty) return const _SavedFeed.empty();
    try {
      return _SavedFeed(_parse(raw));
    } catch (_) {
      return const _SavedFeed.corrupt();
    }
  }

  /// Strict parse shared by the transport and cache paths. Anything that is
  /// not a complete, contract-valid feed becomes [_InvalidFeed].
  JobFeed _parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Feed root is not an object');
      }
      return JobFeed.fromJson(decoded);
    } catch (_) {
      throw const _InvalidFeed();
    }
  }

  void _emit({
    required JobFeed? feed,
    required bool isLoading,
    required bool isOffline,
    required String? lastError,
  }) {
    if (_disposed) return;
    _state.value = JobFeedState(
      feed: feed,
      isLoading: isLoading,
      isOffline: isOffline,
      lastError: lastError,
    );
  }
}

/// Internal marker for "the document failed contract validation".
class _InvalidFeed implements Exception {
  const _InvalidFeed();
}

class _SavedFeed {
  const _SavedFeed(this.feed) : corrupt = false;
  const _SavedFeed.empty() : feed = null, corrupt = false;
  const _SavedFeed.corrupt() : feed = null, corrupt = true;

  final JobFeed? feed;
  final bool corrupt;
}
