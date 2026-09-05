import 'package:flutter/material.dart';

/// Opacity, blur, and shadow constants for the v3 glass material.
abstract class AppGlass {
  static const double panelFill = 0.48;
  static const double panelBlur = 15;
  static const BoxShadow panelShadow = BoxShadow(
    color: Color(0x141C2A4A),
    offset: Offset(0, 8),
    blurRadius: 32,
  );
  static const double ringAlpha = 0.09;
  static const double highlightAlpha = 0.5;

  static const double innerFill = 0.58;
  static const double innerBlur = 12;

  static const double barFill = 0.85;
  static const double barBlur = 15;

  static const double scrimAlpha = 0.14;

  static const double buttonAlpha = 0.92;
  static const double tintAlpha = 0.09;
}
