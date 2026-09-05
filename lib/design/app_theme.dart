import 'package:flutter/material.dart';

import 'tokens/app_colors.dart';
import 'tokens/app_typography.dart';

/// Theme definition for v3 widgets. Wiring it into MaterialApp is an A-6b task.
abstract class AppTheme {
  static ThemeData build() {
    final ColorScheme colors = ColorScheme.fromSeed(
      seedColor: RoleColors.student,
      brightness: Brightness.light,
    ).copyWith(
      surface: Colors.transparent,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      outline: Colors.transparent,
      outlineVariant: Colors.transparent,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      fontFamily: AppTypography.fontFamily,
      scaffoldBackgroundColor: Colors.transparent,
      dividerColor: Colors.transparent,
      textTheme: const TextTheme(
        displaySmall: AppTypography.bigNumber,
        headlineSmall: AppTypography.title,
        titleMedium: AppTypography.section,
        bodyMedium: AppTypography.body,
        bodySmall: AppTypography.caption,
        labelLarge: AppTypography.button,
      ).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        hintStyle: AppTypography.body.copyWith(
          color: AppColors.textSecondary,
        ),
        labelStyle: AppTypography.caption.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
