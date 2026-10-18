import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../feed_transport.dart';

/// Why a [HttpFeedTransport] fetch failed.
///
/// These are developer-facing categories only: `CachedJobRepository` maps
/// every transport failure onto its own fixed, user-safe message, so no enum
/// name, URL or status code can reach the UI.
enum FeedTransportFailure { network, status, timeout, tooLarge, invalidUtf8 }

/// Failure raised by [HttpFeedTransport].
///
/// The underlying client error, when there is one, is kept in [cause] so it can
/// be logged; [message] is for developers and must not be shown to users.
class FeedTransportException implements Exception {
  FeedTransportException(
    this.kind,
    this.message, {
    this.statusCode,
    this.cause,
  });

  final FeedTransportFailure kind;
  final String message;

  /// HTTP status for [FeedTransportFailure.status], otherwise `null`.
  final int? statusCode;

  /// Original error from `package:http` when one exists.
  final Object? cause;

  @override
  String toString() =>
      'FeedTransportException(${kind.name})'
      '${statusCode == null ? '' : ' HTTP $statusCode'}: $message';
}

/// Production [FeedTransport] over `package:http`.
///
/// The URL and client are injected, so no production feed URL, host or auth
/// header is baked in: the captain supplies the real endpoint and owns closing
/// [client]. This class never closes or mutates the injected client.
///
/// Guarantees (see `docs/CONTRACTS.md`, "Batch 2 — concrete platform adapters"):
///  * Public HTTPS only. `http:`, embedded credentials (`user:pass@`) and
///    fragments are rejected in the constructor, so a misconfigured URL fails
///    at composition time instead of leaking a secret at request time.
///  * Exactly one GET. No retries, no redirect loops of our own; the injected
///    client's normal redirect policy applies and the *final* response must be
///    HTTP 200.
///  * The body is bounded by [maxBytes] twice: the declared `Content-Length`
///    is rejected up front when it is already too large, and the number of
///    bytes actually streamed is counted for chunked responses that declare
///    nothing. The stream subscription is cancelled as soon as the limit is
///    crossed, so an oversized body is not read to the end.
///  * The total budget [timeout] covers connecting, headers *and* body.
///  * The body is decoded as strict UTF-8: malformed bytes fail the fetch
///    instead of yielding replacement characters that would be cached as if
///    they were reviewed content.
///  * The payload is returned as raw text and is **not** trusted: JSON
///    validation stays in `CachedJobRepository`/`JobFeed`.
///
/// Web compatibility: only `dart:async`, `dart:convert`, `dart:typed_data` and
/// `package:http` are used, so the file compiles for web. On web the browser
/// (not Dart) follows redirects, may omit `Content-Length` under CORS, and
/// buffers the body; the streamed byte cap and the timeout then still protect
/// the app, but they cannot stop the browser's own transfer after we cancel.
class HttpFeedTransport implements FeedTransport {
  HttpFeedTransport({
    required Uri feedUrl,
    required this._client,
    Duration timeout = const Duration(seconds: 20),
    int maxBytes = 2097152,
  }) : _feedUrl = _validateUrl(feedUrl),
       _timeout = timeout,
       _maxBytes = maxBytes {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'must be greater than zero',
      );
    }
    if (maxBytes <= 0) {
      throw ArgumentError.value(
        maxBytes,
        'maxBytes',
        'must be greater than zero',
      );
    }
  }

  /// Content type the feed endpoint must serve; JSON is always UTF-8.
  static const String acceptHeader = 'application/json';

  final Uri _feedUrl;
  final http.Client _client;
  final Duration _timeout;
  final int _maxBytes;

  /// The configured endpoint (no credentials are accepted).
  Uri get feedUrl => _feedUrl;

  /// Configured total budget for one fetch.
  Duration get timeout => _timeout;

  /// Configured maximum accepted body size.
  int get maxBytes => _maxBytes;

  @override
  Future<String> fetch() async {
    final watch = Stopwatch()..start();
    final request = http.Request('GET', _feedUrl)
      ..headers['accept'] = acceptHeader
      ..followRedirects = true;

    final http.StreamedResponse response;
    Future<http.StreamedResponse>? sendFuture;
    try {
      // Inside the try: a hand-written Client may throw synchronously here.
      sendFuture = _client.send(request);
      response = await sendFuture.timeout(_timeout);
    } on TimeoutException catch (cause) {
      // package:http has no request-abort API, so a late response is drained
      // and cancelled here instead of leaking a live body stream.
      unawaited(
        sendFuture?.then<void>(
          (late) => late.stream.listen(null).cancel(),
          onError: (Object _) {},
        ),
      );
      throw FeedTransportException(
        FeedTransportFailure.timeout,
        'No response headers within ${_timeout.inMilliseconds} ms.',
        cause: cause,
      );
    } catch (cause) {
      throw FeedTransportException(
        FeedTransportFailure.network,
        'The request to the feed endpoint failed.',
        cause: cause,
      );
    }

    if (response.statusCode != 200) {
      // Release the connection: a non-200 body is never used.
      await response.stream.listen(null).cancel();
      throw FeedTransportException(
        FeedTransportFailure.status,
        'The feed endpoint answered ${response.statusCode}, expected 200.',
        statusCode: response.statusCode,
      );
    }

    final declared = response.contentLength;
    if (declared != null && declared > _maxBytes) {
      await response.stream.listen(null).cancel();
      throw FeedTransportException(
        FeedTransportFailure.tooLarge,
        'Declared body size $declared bytes exceeds the $_maxBytes byte limit.',
      );
    }

    return _readBoundedBody(response.stream, watch);
  }

  /// Reads the body with the remaining time budget, the streamed byte cap and
  /// strict UTF-8 decoding. Exactly one subscription is created and it is
  /// cancelled on every failure path.
  Future<String> _readBoundedBody(Stream<List<int>> stream, Stopwatch watch) {
    final completer = Completer<String>();
    final chunks = <List<int>>[];
    var total = 0;
    var settled = false;
    StreamSubscription<List<int>>? subscription;
    Timer? timer;

    void fail(FeedTransportException error) {
      if (settled) return;
      settled = true;
      timer?.cancel();
      final active = subscription;
      if (active != null) unawaited(active.cancel());
      if (!completer.isCompleted) completer.completeError(error);
    }

    void succeed() {
      if (settled) return;
      settled = true;
      timer?.cancel();
      try {
        final bytes = Uint8List(total);
        var offset = 0;
        for (final chunk in chunks) {
          bytes.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }
        // allowMalformed: false rejects invalid UTF-8 instead of substituting
        // U+FFFD, which would quietly corrupt a cached reviewed feed.
        if (!completer.isCompleted) {
          completer.complete(utf8.decode(bytes, allowMalformed: false));
        }
      } on FormatException catch (cause) {
        if (!completer.isCompleted) {
          completer.completeError(
            FeedTransportException(
              FeedTransportFailure.invalidUtf8,
              'The feed body is not valid UTF-8.',
              cause: cause,
            ),
          );
        }
      }
    }

    final remaining = _timeout - watch.elapsed;
    timer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      fail(
        FeedTransportException(
          FeedTransportFailure.timeout,
          'The feed body did not finish within ${_timeout.inMilliseconds} ms.',
        ),
      );
    });

    subscription = stream.listen(
      (chunk) {
        if (settled) return;
        total += chunk.length;
        if (total > _maxBytes) {
          fail(
            FeedTransportException(
              FeedTransportFailure.tooLarge,
              'Streamed body exceeded the $_maxBytes byte limit.',
            ),
          );
          return;
        }
        chunks.add(chunk);
      },
      onError: (Object cause, StackTrace _) => fail(
        FeedTransportException(
          FeedTransportFailure.network,
          'The feed body stream failed before it completed.',
          cause: cause,
        ),
      ),
      onDone: succeed,
      cancelOnError: true,
    );
    // A synchronously-failing stream can settle during listen(); make sure the
    // freshly created subscription is not left hanging in that case.
    if (settled) unawaited(subscription.cancel());

    return completer.future;
  }
}

/// Rejects anything that is not a credential-free, host-bearing HTTPS URL.
Uri _validateUrl(Uri uri) {
  if (!uri.isScheme('https') || uri.host.isEmpty) {
    throw ArgumentError.value(
      uri,
      'feedUrl',
      'must be an absolute https URL with a host',
    );
  }
  if (uri.userInfo.isNotEmpty) {
    throw ArgumentError.value(uri, 'feedUrl', 'must not embed credentials');
  }
  if (uri.hasFragment) {
    throw ArgumentError.value(uri, 'feedUrl', 'must not contain a fragment');
  }
  return uri;
}
