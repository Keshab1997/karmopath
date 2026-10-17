import 'package:flutter/material.dart';

import 'app/karmopath_app.dart';
import 'app/preview/preview_app.dart';

void main() => runApp(
  const bool.fromEnvironment('KARMOPATH_PREVIEW')
      ? const KarmopathPreviewApp()
      : const KarmopathApp(),
);
