import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'app/karmopath_app.dart';
import 'app/preview/preview_app.dart';
import 'app/runtime/feed_configuration.dart';
import 'app/runtime/native_runtime_factory.dart';
import 'app/runtime/production_bootstrap.dart';

/// Selects the application root from compile-time configuration.
///
/// Pure by design — the `fromEnvironment` reads stay in [main] — so the
/// selection can be asserted without `runApp` or any platform channel.
///
/// * `KARMOPATH_PREVIEW` (default: on the web) selects the isolated, labelled
///   demo. It never reaches the network or the notification plugin.
/// * `KARMOPATH_FEED_URL` selects the native composition. An empty value is
///   deliberate: it falls back to the foundation screen rather than guessing an
///   endpoint, the same rule `FeedConfiguration` enforces.
///
/// The external-link launcher and reminder session are left at the factory
/// defaults, so no platform callback is re-implemented here.
Widget buildAppRoot({required bool preview, required String feedUrl}) {
  if (preview) return const KarmopathPreviewApp();
  if (feedUrl.trim().isEmpty) return const KarmopathApp();
  return ProductionBootstrap(
    createRuntime: () => createNativeRuntime(feed: FeedConfiguration(feedUrl)),
  );
}

/// The web demo is only the default when no feed URL is configured. A web build
/// that supplies `KARMOPATH_FEED_URL` therefore shows the reviewed feed instead
/// of sample data; `KARMOPATH_PREVIEW=true` still forces the demo explicitly.
void main() {
  const feedUrl = String.fromEnvironment('KARMOPATH_FEED_URL');
  runApp(
    buildAppRoot(
      preview: bool.fromEnvironment(
        'KARMOPATH_PREVIEW',
        defaultValue: kIsWeb && feedUrl == '',
      ),
      feedUrl: feedUrl,
    ),
  );
}
