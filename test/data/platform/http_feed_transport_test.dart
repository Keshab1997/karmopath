import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/data/feed_transport.dart';
import 'package:karmopath/data/platform/http_feed_transport.dart';

import 'fake_http_client.dart';

final Uri kFeedUrl = Uri.parse('https://feed.example.org/karmopath/jobs.json');

HttpFeedTransport transportWith(
  FakeHttpClient client, {
  Duration timeout = const Duration(seconds: 20),
  int maxBytes = 2097152,
  Uri? url,
}) => HttpFeedTransport(
  feedUrl: url ?? kFeedUrl,
  client: client,
  timeout: timeout,
  maxBytes: maxBytes,
);

Matcher throwsFeedFailure(FeedTransportFailure kind) =>
    throwsA(isA<FeedTransportException>().having((e) => e.kind, 'kind', kind));

void main() {
  test(
    'synchronous TimeoutException is categorized without late-init failure',
    () async {
      final client = FakeHttpClient(
        onSend: (_) => throw TimeoutException('sync timeout'),
      );
      await expectLater(
        transportWith(client).fetch(),
        throwsFeedFailure(FeedTransportFailure.timeout),
      );
    },
  );

  group('configuration', () {
    test('rejects plain http', () {
      expect(
        () => transportWith(
          FakeHttpClient.hanging(),
          url: Uri.parse('http://x.example.org/f.json'),
        ),
        throwsArgumentError,
      );
    });

    test('rejects embedded credentials', () {
      expect(
        () => transportWith(
          FakeHttpClient.hanging(),
          url: Uri.parse('https://user:pass@feed.example.org/f.json'),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a missing host and a fragment', () {
      expect(
        () => transportWith(
          FakeHttpClient.hanging(),
          url: Uri.parse('https:///f.json'),
        ),
        throwsArgumentError,
      );
      expect(
        () => transportWith(
          FakeHttpClient.hanging(),
          url: Uri.parse('https://feed.example.org/f.json#frag'),
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-positive timeout and byte limit', () {
      expect(
        () => transportWith(FakeHttpClient.hanging(), timeout: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => transportWith(FakeHttpClient.hanging(), maxBytes: 0),
        throwsArgumentError,
      );
    });

    test('accepts a credential-free https URL and exposes its config', () {
      final transport = transportWith(FakeHttpClient.hanging());
      expect(transport, isA<FeedTransport>());
      expect(transport.feedUrl, kFeedUrl);
      expect(transport.timeout, const Duration(seconds: 20));
      expect(transport.maxBytes, 2097152);
    });
  });

  group('request shape', () {
    test(
      'sends exactly one credential-free GET with a JSON accept header',
      () async {
        final client = FakeHttpClient.respond(body: '{"ok":true}');
        final transport = transportWith(client);

        await transport.fetch();

        expect(
          client.sendCalls,
          1,
          reason: 'no retries, no duplicate requests',
        );
        final request = client.sentRequests.single;
        expect(request.method, 'GET');
        expect(request.url, kFeedUrl);
        expect(request.headers['accept'], HttpFeedTransport.acceptHeader);
        final headerNames = request.headers.keys.map((k) => k.toLowerCase());
        expect(headerNames, isNot(contains('authorization')));
        expect(headerNames, isNot(contains('cookie')));
        expect(headerNames, isNot(contains('proxy-authorization')));
      },
    );

    test(
      'never closes the injected client, on success or on failure',
      () async {
        final okClient = FakeHttpClient.respond(body: '{}');
        await transportWith(okClient).fetch();
        expect(okClient.closed, isFalse);

        final badClient = FakeHttpClient.respond(statusCode: 500);
        await expectLater(
          transportWith(badClient).fetch(),
          throwsFeedFailure(FeedTransportFailure.status),
        );
        expect(badClient.closed, isFalse, reason: 'the caller owns the client');
      },
    );
  });

  group('status handling', () {
    test('a 200 body is returned verbatim as text', () async {
      const raw =
          '{"schema_version":1,"updated_at":"2026-01-01T00:00:00Z","jobs":[]}';
      final transport = transportWith(FakeHttpClient.respond(body: raw));

      expect(await transport.fetch(), raw);
    });

    test('a non-200 status fails and releases the body', () async {
      final body = ControlledBody();
      final client = FakeHttpClient.streaming(body, statusCode: 503);
      final transport = transportWith(client);

      await expectLater(
        transport.fetch(),
        throwsFeedFailure(FeedTransportFailure.status),
      );
      expect(body.canceled, isTrue, reason: 'a 503 body is discarded at once');
      expect(body.closed, isFalse);
    });

    test('the status exception carries the code for logging', () async {
      final transport = transportWith(FakeHttpClient.respond(statusCode: 404));

      await expectLater(
        transport.fetch(),
        throwsA(
          isA<FeedTransportException>()
              .having((e) => e.kind, 'kind', FeedTransportFailure.status)
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  });

  group('byte limit', () {
    test(
      'a declared Content-Length over the cap is rejected before reading',
      () async {
        final body = ControlledBody();
        final client = FakeHttpClient.streaming(body, declaredLength: 4096);
        final transport = transportWith(client, maxBytes: 1024);

        await expectLater(
          transport.fetch(),
          throwsFeedFailure(FeedTransportFailure.tooLarge),
        );
        expect(body.canceled, isTrue);
        expect(body.emittedChunks, 0, reason: 'the body is never consumed');
      },
    );

    test('a declared size inside the cap is accepted', () async {
      final client = FakeHttpClient.respond(body: '{"a":1}', declaredLength: 7);
      final transport = transportWith(client, maxBytes: 1024);

      expect(await transport.fetch(), '{"a":1}');
    });

    test(
      'a chunked body with no Content-Length is bounded while streaming',
      () async {
        final body = ControlledBody();
        final client = FakeHttpClient.streaming(body); // contentLength is null
        final transport = transportWith(client, maxBytes: 1000);

        final expectation = expectLater(
          transport.fetch(),
          throwsFeedFailure(FeedTransportFailure.tooLarge),
        );
        await pumpEventQueue();
        body.emit(List<int>.filled(400, 0x20));
        body.emit(List<int>.filled(400, 0x20));
        await pumpEventQueue();
        body.emit(List<int>.filled(400, 0x20)); // 1200 > 1000
        await expectation;

        expect(
          body.canceled,
          isTrue,
          reason: 'the oversize read stops immediately',
        );
        expect(body.listenCount, 1);
        expect(body.closed, isFalse);
      },
    );

    test(
      'a body exactly at the cap is accepted (limit is inclusive)',
      () async {
        final client = FakeHttpClient.respond(
          body: 'abcde',
          declaredLength: null, // force the streamed path
        );
        final transport = transportWith(client, maxBytes: 5);

        expect(await transport.fetch(), 'abcde');
      },
    );

    test('a body one byte over the cap fails', () async {
      final client = FakeHttpClient.respond(
        body: 'abcdef',
        declaredLength: null,
      );
      final transport = transportWith(client, maxBytes: 5);

      await expectLater(
        transport.fetch(),
        throwsFeedFailure(FeedTransportFailure.tooLarge),
      );
    });
  });

  group('encoding', () {
    test('valid multi-byte UTF-8 (Bengali) round-trips', () async {
      const bengali = 'কর্মপথ';
      final client = FakeHttpClient.respond(body: jsonEncode({'t': bengali}));

      expect(jsonDecode(await transportWith(client).fetch())['t'], bengali);
    });

    test('malformed UTF-8 is rejected, not replaced with U+FFFD', () async {
      final client = FakeHttpClient.bytes(
        bytes: [0x7B, 0xC3, 0x28, 0x7D], // '{"' + invalid sequence + '}'
      );

      await expectLater(
        transportWith(client).fetch(),
        throwsFeedFailure(FeedTransportFailure.invalidUtf8),
      );
    });

    test('a leading UTF-8 byte-order mark is consumed, not kept', () async {
      final client = FakeHttpClient.bytes(
        bytes: [0xEF, 0xBB, 0xBF, 0x7B, 0x7D],
      );

      // Dart's strict UTF-8 decoder drops a leading BOM, so a BOM-prefixed
      // document reaches the repository as plain JSON instead of failing
      // `jsonDecode`. Documented behaviour, verified here rather than assumed.
      expect(await transportWith(client).fetch(), '{}');
    });
  });

  group('timeouts', () {
    test('a hanging request fails within the configured budget', () async {
      final client = FakeHttpClient.hanging();
      final transport = transportWith(
        client,
        timeout: const Duration(milliseconds: 40),
      );

      final watch = Stopwatch()..start();
      await expectLater(
        transport.fetch(),
        throwsFeedFailure(FeedTransportFailure.timeout),
      );
      watch.stop();
      expect(client.sendCalls, 1, reason: 'a timeout is not retried');
      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason: 'the error must arrive promptly, not after a default 30 s',
      );
    });

    test('a stalled body fails and its subscription is cancelled', () async {
      final body = ControlledBody();
      final client = FakeHttpClient.streaming(body);
      final transport = transportWith(
        client,
        timeout: const Duration(milliseconds: 40),
      );

      await expectLater(
        transport.fetch(),
        throwsFeedFailure(FeedTransportFailure.timeout),
      );
      expect(body.listenCount, 1);
      expect(body.canceled, isTrue);
      expect(body.closed, isFalse);
    });

    test('the timeout covers headers and body together', () async {
      final body = ControlledBody();
      final client = FakeHttpClient.streaming(body);
      final transport = transportWith(
        client,
        timeout: const Duration(milliseconds: 60),
      );

      final expectation = expectLater(
        transport.fetch(),
        throwsFeedFailure(FeedTransportFailure.timeout),
      );
      await pumpEventQueue();
      // Keep the body alive with traffic but never finish it.
      for (var i = 0; i < 6; i++) {
        body.emit(const [0x20]);
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      await expectation;
      expect(body.canceled, isTrue);
    });
  });

  group('stream failures and cleanup', () {
    test('a mid-body stream error surfaces as a network failure', () async {
      final body = ControlledBody();
      final client = FakeHttpClient.streaming(body);

      final expectation = expectLater(
        transportWith(client).fetch(),
        throwsFeedFailure(FeedTransportFailure.network),
      );
      await pumpEventQueue();
      body.emit(utf8.encode('{"partial":'));
      await pumpEventQueue();
      body.fail(StateError('connection reset'));
      await expectation;

      expect(body.canceled, isTrue);
      expect(body.listenCount, 1);
    });

    test(
      'a synchronously throwing client still becomes a network failure',
      () async {
        final client = FakeHttpClient(
          onSend: (_) => throw StateError('client misconfigured'),
        );

        await expectLater(
          transportWith(client).fetch(),
          throwsFeedFailure(FeedTransportFailure.network),
        );
      },
    );

    test('a client.send failure surfaces as a network failure', () async {
      final client = FakeHttpClient(
        onSend: (_) async => throw StateError('dns failure'),
      );

      await expectLater(
        transportWith(client).fetch(),
        throwsFeedFailure(FeedTransportFailure.network),
      );
    });

    test('the original client error is preserved as the cause', () async {
      final original = StateError('dns failure');
      final client = FakeHttpClient(onSend: (_) async => throw original);

      await expectLater(
        transportWith(client).fetch(),
        throwsA(
          isA<FeedTransportException>().having(
            (e) => e.cause,
            'cause',
            original,
          ),
        ),
      );
    });

    test('each fetch creates exactly one subscription', () async {
      final body = ControlledBody();
      final client = FakeHttpClient.streaming(body);
      final transport = transportWith(client);

      final fetch = transport.fetch();
      await pumpEventQueue();
      body.emit(utf8.encode('{}'));
      await body.finish();
      await fetch;

      expect(body.listenCount, 1);
      expect(client.sendCalls, 1);
    });

    test('a slow success is still returned when inside the budget', () async {
      final body = ControlledBody();
      final transport = transportWith(
        FakeHttpClient.streaming(body),
        timeout: const Duration(seconds: 2),
      );

      final fetch = transport.fetch();
      await pumpEventQueue();
      body.emit(utf8.encode('{"slow":'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      body.emit(utf8.encode('true}'));
      await body.finish();

      expect(await fetch, '{"slow":true}');
    });
  });

  group('web compatibility (static evidence only)', () {
    // Analyzer/compiler coverage is the real proof of importability; this test
    // only guarantees the adapter never reaches for a VM-only library, which
    // would pass on the VM test runner and fail at web build time.
    for (final path in <String>[
      'lib/data/platform/http_feed_transport.dart',
      'lib/data/platform/preferences_feed_cache.dart',
      'lib/data/platform/shared_preferences_store.dart',
    ]) {
      test('$path does not import dart:io', () {
        final source = File(path).readAsStringSync();
        expect(source.contains("dart:io"), isFalse);
      });
    }

    test('browser runtime limits are documented in the adapter', () {
      final source = File('lib/data/platform/http_feed_transport.dart')
          .readAsStringSync();
      expect(source, contains('Web compatibility'));
      expect(source, contains('CORS'));
    });
  });
}
