import 'package:flutter/material.dart';

abstract final class KarmopathTheme {
  static const background = Color(0xFFFFF8F0);
  static const coral = Color(0xFFF4654A);
  static const teal = Color(0xFF0F766E);
  static const ink = Color(0xFF1F2937);
  static const heroAsset = 'assets/illustrations/hero.png';
  static ThemeData light() => ThemeData(
    useMaterial3: true,
    fontFamily: 'NotoSansBengali',
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(seedColor: teal),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: ink,
    ),
  );
}
