import 'package:flutter/material.dart';

import '../../design_system/karmopath_theme.dart';

/// Feature-local accessibility palette.
///
/// The shared design tokens (`KarmopathTheme`) are captain-owned, so B keeps
/// its contrast adjustments here. Brand coral stays the decorative colour;
/// [coralStrong] is the same hue darkened until white *and* ink text on it
/// reach WCAG AA, which the approved design requires for text-bearing
/// surfaces (docs/DESIGN.md: "Coral is decorative; use contrast-tested dark
/// text/buttons where needed").
abstract final class KPalette {
  /// Decorative-only brand coral from the shared theme.
  static const Color coral = KarmopathTheme.coral;

  /// Coral usable behind small text (white on it ≈ 5.7:1).
  static const Color coralStrong = Color(0xFFB23F27);

  /// WCAG 2.x contrast ratio between two opaque colours.
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
}
