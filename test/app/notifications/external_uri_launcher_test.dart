import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/app/notifications/external_uri_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  test('opens only through the external system handler', () async {
    Uri? opened;
    LaunchMode? usedMode;
    await launchExternalHttpsUri(
      Uri.parse('https://example.org/notices/123'),
      launcher: (uri, {required mode}) async {
        opened = uri;
        usedMode = mode;
        return true;
      },
    );
    expect(opened, Uri.parse('https://example.org/notices/123'));
    expect(usedMode, LaunchMode.externalApplication);
  });

  test('rejects non-public or non-HTTPS values before launcher call', () async {
    var calls = 0;
    Future<bool> launcher(Uri _, {required LaunchMode mode}) async {
      calls++;
      return true;
    }

    for (final raw in [
      'http://example.org',
      'https://user:pass@example.org',
      'https://example.org/path#fragment',
      'https:///missing-host',
    ]) {
      await expectLater(
        launchExternalHttpsUri(Uri.parse(raw), launcher: launcher),
        throwsArgumentError,
      );
    }
    expect(calls, 0);
  });

  test(
    'a false system-handler result is an error, not a no-op success',
    () async {
      await expectLater(
        launchExternalHttpsUri(
          Uri.parse('https://example.org'),
          launcher: (_, {required mode}) async => false,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('launcher errors propagate to the caller', () async {
    final error = StateError('platform launch failed');
    await expectLater(
      launchExternalHttpsUri(
        Uri.parse('https://example.org'),
        launcher: (_, {required mode}) async => throw error,
      ),
      throwsA(same(error)),
    );
  });
}
