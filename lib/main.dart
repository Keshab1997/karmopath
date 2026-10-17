import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'app/karmopath_app.dart';
import 'app/preview/preview_app.dart';

void main() => runApp(
  const bool.fromEnvironment('KARMOPATH_PREVIEW', defaultValue: kIsWeb)
      ? const KarmopathPreviewApp()
      : const KarmopathApp(),
);
