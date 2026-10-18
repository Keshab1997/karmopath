import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A scripted `http.Client` for [HttpFeedTransport] tests.
///
/// No sockets: each test decides exactly when headers arrive, which chunks the
/// body emits and when it closes, so timeout, byte-limit and cleanup behaviour
/// can be asserted without real network or wall-clock races.
class FakeHttpClient extends http.BaseClient {
  FakeHttpClient({required this.onSend});

  /// A complete in-memory response.
  factory FakeHttpClient.respond({
    int statusCode = 200,
    String body = '{}',
    Map<String, String> headers = const {},
    int? declaredLength,
  }) {
    return FakeHttpClient(
      onSend: (request) async => http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(body)),
        statusCode,
        contentLength: declaredLength,
        headers: headers,
        request: request,
      ),
    );
  }

  /// Exact bytes, used for invalid-UTF-8 payloads.
  factory FakeHttpClient.bytes({
    required List<int> bytes,
    int statusCode = 200,
    int? declaredLength,
  }) {
    return FakeHttpClient(
      onSend: (request) async => http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        statusCode,
        contentLength: declaredLength,
        request: request,
      ),
    );
  }

  /// Answers headers immediately; the test drives [body] itself.
  factory FakeHttpClient.streaming(
    ControlledBody body, {
    int statusCode = 200,
    int? declaredLength,
  }) {
    return FakeHttpClient(
      onSend: (request) async => http.StreamedResponse(
        body.stream,
        statusCode,
        contentLength: declaredLength,
        request: request,
      ),
    );
  }

  /// Never answers: the send future stays pending (header-timeout test).
  factory FakeHttpClient.hanging() =>
      FakeHttpClient(onSend: (_) => Completer<http.StreamedResponse>().future);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) onSend;

  int sendCalls = 0;
  bool closed = false;
  final List<http.BaseRequest> sentRequests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sendCalls++;
    sentRequests.add(request);
    return onSend(request);
  }

  /// Overridden only so a test can prove the transport left the injected
  /// client open (the caller owns it).
  @override
  void close() {
    closed = true;
  }
}

/// A response body a test drives chunk by chunk.
///
/// Counts subscriptions and cancellations so "no leaked subscription" is an
/// assertion rather than a claim. A body that the transport cancels before it
/// closes stays open: [closed] is false while [canceled] is true.
class ControlledBody {
  ControlledBody() {
    _controller.onListen = () => listenCount++;
    _controller.onCancel = () => cancelCount++;
  }

  final StreamController<List<int>> _controller = StreamController<List<int>>();
  int listenCount = 0;
  int cancelCount = 0;
  int emittedChunks = 0;

  bool get canceled => cancelCount > 0;
  bool get closed => _controller.isClosed;

  Stream<List<int>> get stream => _controller.stream;

  /// Emits one chunk; ignored once the transport has cancelled.
  void emit(List<int> bytes) {
    if (_controller.isClosed) return;
    emittedChunks++;
    _controller.add(bytes);
  }

  /// Emits an error into the body stream.
  void fail(Object error) {
    if (_controller.isClosed) return;
    _controller.addError(error);
  }

  Future<void> finish() async {
    if (!_controller.isClosed) await _controller.close();
  }
}
