import 'package:flutter/material.dart';

/// Canonical v3 glass colors. These values are contrast-verified and fixed.
abstract class AppColors {
  static const Color bgTop = Color(0xFFF6F9FD);
  static const Color bgMid = Color(0xFFEDF3FA);
  static const Color bgBot = Color(0xFFF2F6FB);

  static const Color textPrimary = Color(0xFF191F28);
  static const Color textSecondary = Color(0xFF5F6B7A);

  static const Color warning = Color(0xFFB54708);
  static const Color danger = Color(0xFFC2334D);

  static const Color navy = Color(0xFF1C2A4A);
}

/// Role accents selected for sufficient contrast on the glass surface.
abstract class RoleColors {
  static const Color student = Color(0xFF2563EB);
  static const Color mentor = Color(0xFF0B6B4E);
}
