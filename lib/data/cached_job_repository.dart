import 'dart:async';
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
///
/// ## Lifecycle contract (batch 3)
///
/// `ValueNotifier` listeners run **synchronously** inside [_emit], so a listener
/// is free to call [refresh] or [dispose] while a state is being published.
/// This class is built for that:
///  * The single-flight window opens *before* the first notification is
///    published, so a listener that refreshes on the loading state joins the
///    running attempt instead of starting a second one.
///  * The terminal (success/error) state is published *after* the window
///    closes, so a listener that retries from an error banner starts a real new
///    attempt instead of joining one that has already finished.
///  * [dispose] cancels the attempt: pending [refresh] futures complete, no
///    further state is published, and no new transport call or cache write is
///    begun. A platform write that had *already* started is not cancelled
///    retroactively — the repository simply does not publish its result.
///  * The internal notifier is disposed one microtask after [dispose] so that a
///    listener may call `dispose()` directly (Flutter asserts when a
///    `ChangeNotifier` is disposed during its own `notifyListeners`).
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

  /// The attempt that new `refresh()` calls join, or `null` when idle.
  Completer<void>? _attempt;

  /// `_attempt?.future`, cached so the in-flight window opens synchronously.
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
    // Register the attempt BEFORE any listener can observe the loading state:
    // the notifier notifies synchronously, and a listener that calls refresh()
    // from that callback must join this attempt, not start a second one.
    final attempt = Completer<void>();
    _attempt = attempt;
    _inFlight = attempt.future;
    _startAttempt(attempt);
    return attempt.future;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return; // idempotent: double disposal must not assert
    // Mark first: any in-flight attempt checks this flag before emitting,
    // fetching or writing, so a slow provider cannot revive a disposed
    // repository.
    _disposed = true;
    // Release anyone awaiting refresh(): the attempt will never publish now.
    final attempt = _attempt;
    if (attempt != null) _release(attempt);
    // Flutter asserts when a ChangeNotifier is disposed during its own
    // notifyListeners(), and a state listener may call dispose() directly.
    // Leaving the synchronous stack first makes that legal; no new state can be
    // published in between because [_disposed] is already set.
    await Future<void>.microtask(() {});
    _state.dispose();
  }

  /// Runs one attempt and always closes its single-flight window, even if an
  /// unexpected error escapes [_runRefresh].
  Future<void> _startAttempt(Completer<void> attempt) async {
    try {
      await _runRefresh(attempt);
    } catch (_) {
      // _runRefresh converts every expected failure into state; this is only a
      // last-resort guard so the in-flight marker can never stay stuck.
    } finally {
      _release(attempt);
    }
  }

  /// Closes [attempt]'s single-flight window exactly once.
  ///
  /// The identity check matters: a listener may already have started a newer
  /// attempt from the terminal notification, and that newer window must not be
  /// cleared by the finishing one.
  void _release(Completer<void> attempt) {
    if (identical(_attempt, attempt)) {
      _attempt = null;
      _inFlight = null;
    }
    if (!attempt.isCompleted) attempt.complete();
  }

  Future<void> _runRefresh(Completer<void> attempt) async {
    final previous = _state.value;
    _emit(
      feed: previous.feed,
      isLoading: true,
      isOffline: previous.isOffline,
      lastError: previous.lastError,
    );
    // A listener may have disposed us from that notification.
    if (_disposed) return;

    JobFeed? feed = previous.feed;
    String? cacheNote;
    if (feed == null) {
      final saved = await _readSavedFeed();
      if (_disposed) return;
      feed = saved.feed;
      if (feed != null) {
        // Show the saved copy immediately, still marked as stale/last-known.
        _emit(feed: feed, isLoading: true, isOffline: true, lastError: null);
        if (_disposed) return;
      } else if (saved.corrupt) {
        cacheNote = corruptCacheMessage;
      }
    }

    final terminal = await _fetchTerminalState(
      feed: feed,
      cacheNote: cacheNote,
    );
    if (terminal == null || _disposed) return;

    // Close the window first: a listener that retries from this success/error
    // state must start a fresh attempt rather than join a finished one.
    _release(attempt);
    _emitState(terminal);
  }

  /// Fetches, validates and (only then) caches, returning the state to publish.
  ///
  /// Returns `null` when the repository was disposed mid-flight: in that case no
  /// state may be published, and no *new* transport call or cache write is
  /// started. Everything after validation is inside the same error handling, so
  /// a throwing provider can only ever produce a truthful terminal state.
  Future<JobFeedState?> _fetchTerminalState({
    required JobFeed? feed,
    required String? cacheNote,
  }) async {
    try {
      final raw = await _transport.fetch();
      final fresh = _parse(raw); // validate fully before any cache commit
      if (_disposed) return null;
      var warning = cacheNote;
      try {
        await _cache.write(raw);
        warning = null; // a successful refresh also repairs a corrupt cache
      } catch (_) {
        warning = cacheWriteFailedMessage;
      }
      // A write that began before disposal is allowed to finish (it cannot be
      // recalled); its result is simply not published.
      if (_disposed) return null;
      return JobFeedState(
        feed: fresh,
        isLoading: false,
        isOffline: false,
        lastError: warning,
      );
    } on _InvalidFeed {
      if (_disposed) return null;
      return JobFeedState(
        feed: feed,
        isLoading: false,
        isOffline: feed != null,
        lastError: feed == null
            ? invalidFeedNoCacheMessage
            : invalidFeedWithCacheMessage,
      );
    } catch (_) {
      if (_disposed) return null;
      return JobFeedState(
        feed: feed,
        isLoading: false,
        isOffline: true,
        lastError: feed == null
            ? (cacheNote ?? offlineNoCacheMessage)
            : offlineWithCacheMessage,
      );
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
  }) => _emitState(
    JobFeedState(
      feed: feed,
      isLoading: isLoading,
      isOffline: isOffline,
      lastError: lastError,
    ),
  );

  void _emitState(JobFeedState state) {
    if (_disposed) return;
    _state.value = state;
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
