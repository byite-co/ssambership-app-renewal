import 'package:flutter/material.dart';

/// Canonical v3 type scale. Every style names Pretendard explicitly.
abstract class AppTypography {
  static const String fontFamily = 'Pretendard';

  static const TextStyle title = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    fontFamily: fontFamily,
  );
  static const TextStyle bigNumber = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    fontFamily: fontFamily,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
  static const TextStyle section = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    fontFamily: fontFamily,
  );
  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    fontFamily: fontFamily,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    fontFamily: fontFamily,
  );
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontFamily: fontFamily,
  );
}
