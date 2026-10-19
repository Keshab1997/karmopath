import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/app/karmopath_app.dart';
import 'package:karmopath/app/preview/preview_app.dart';
import 'package:karmopath/app/runtime/production_bootstrap.dart';
import 'package:karmopath/main.dart';

/// The root selection decides which of three composers runs. Asserting the
/// returned widget without pumping keeps this free of platform channels: a
/// pumped `ProductionBootstrap` would immediately build the real runtime,
/// storage and notification plugin.
void main() {
  test('the preview flag selects the isolated demo', () {
    expect(
      buildAppRoot(preview: true, feedUrl: ''),
      isA<KarmopathPreviewApp>(),
    );
  });

  test('the preview flag wins over a configured feed URL', () {
    expect(
      buildAppRoot(preview: true, feedUrl: 'https://example.org/jobs.json'),
      isA<KarmopathPreviewApp>(),
    );
  });

  test('no feed URL falls back to the foundation screen', () {
    expect(buildAppRoot(preview: false, feedUrl: ''), isA<KarmopathApp>());
  });

  test('a blank feed URL never becomes a guessed endpoint', () {
    expect(buildAppRoot(preview: false, feedUrl: '   '), isA<KarmopathApp>());
  });

  test('a feed URL selects the native production composition', () {
    expect(
      buildAppRoot(preview: false, feedUrl: 'https://example.org/jobs.json'),
      isA<ProductionBootstrap>(),
    );
  });
}
