import 'package:flutter/material.dart';

import 'role_theme.dart';
import 'tokens/app_colors.dart';
import 'tokens/app_glass.dart';
import 'tokens/app_spacing.dart';
import 'tokens/app_typography.dart';

/// v3 글래스 테마 — `MaterialApp.theme` 에 연결된다(A-6b).
///
/// 화면은 유리 컴포넌트(`GlassCard`·`AppPrimaryButton`…)를 직접 쓰지만, 다이얼로그·
/// 스낵바·스위치·팝업 메뉴처럼 Material 이 그리는 표면도 같은 재료로 보이도록
/// 서브테마를 여기서 한 번에 정한다. 역할색은 [role] 에 따라 primary 슬롯과
/// 컨트롤(스위치·체크·커서·텍스트 버튼)에만 들어가고, 표면·글자색은 역할과 무관하다.
///
/// 배경은 이 테마가 칠하지 않는다 — [scaffoldBackgroundColor] 는 투명이고
/// `AppBackground` 가 그라디언트를 그린다(앱 루트 builder + 페이지 스캐폴드).
abstract class AppTheme {
  static ThemeData build({AppRole role = AppRole.student}) {
    final Color roleColor = RoleTheme.colorOf(role);
    final Color roleTint = roleColor.withValues(alpha: AppGlass.tintAlpha);

    final ColorScheme colors = ColorScheme.fromSeed(
      seedColor: roleColor,
      brightness: Brightness.light,
    ).copyWith(
      primary: roleColor,
      onPrimary: Colors.white,
      primaryContainer: roleTint,
      onPrimaryContainer: roleColor,
      secondary: roleColor,
      onSecondary: Colors.white,
      secondaryContainer: roleTint,
      onSecondaryContainer: roleColor,
      surface: AppColors.glass,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AppColors.bgTop,
      surfaceContainer: AppColors.glass,
      surfaceContainerHigh: AppColors.bgBot,
      surfaceContainerHighest: AppColors.bgMid,
      error: AppColors.danger,
      onError: Colors.white,
      outline: AppColors.ring,
      outlineVariant: AppColors.ring,
      surfaceTint: Colors.transparent,
    );

    final RoundedRectangleBorder glassShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
      side: const BorderSide(color: AppColors.ring),
    );
    final RoundedRectangleBorder buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      fontFamily: AppTypography.fontFamily,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: AppColors.glass,
      dividerColor: Colors.transparent,
      splashColor: roleColor.withValues(alpha: 0.10),
      highlightColor: roleColor.withValues(alpha: 0.05),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      textTheme: const TextTheme(
        displaySmall: AppTypography.bigNumber,
        headlineSmall: AppTypography.title,
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          fontFamily: AppTypography.fontFamily,
        ),
        titleMedium: AppTypography.section,
        titleSmall: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFamily: AppTypography.fontFamily,
        ),
        bodyLarge: AppTypography.body,
        bodyMedium: AppTypography.body,
        bodySmall: AppTypography.caption,
        labelLarge: AppTypography.button,
        labelMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          fontFamily: AppTypography.fontFamily,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFamily: AppTypography.fontFamily,
        ),
      ).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      // 남아 있는 Material AppBar 가 있어도 유리 앱바와 같은 톤으로 보이게.
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          fontFamily: AppTypography.fontFamily,
          color: AppColors.textPrimary,
        ),
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
        helperStyle: AppTypography.caption.copyWith(
          color: AppColors.textSecondary,
        ),
        errorStyle: AppTypography.caption.copyWith(color: AppColors.danger),
        counterStyle: AppTypography.caption.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: roleColor,
        selectionColor: roleColor.withValues(alpha: 0.24),
        selectionHandleColor: roleColor,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.glass,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: glassShape,
        titleTextStyle: AppTypography.section.copyWith(
          color: AppColors.textPrimary,
        ),
        contentTextStyle: AppTypography.body.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.glass,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          side: const BorderSide(color: AppColors.ring),
        ),
        textStyle: AppTypography.body.copyWith(color: AppColors.textPrimary),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      // v3 토스트: 짙은 남색 유리 위 흰 글자(design-v3 §0).
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary.withValues(alpha: 0.88),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: buttonShape,
        contentTextStyle: AppTypography.body.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        actionTextColor: Colors.white,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: roleColor,
          disabledForegroundColor: AppColors.textSecondary,
          textStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
          shape: buttonShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          disabledForegroundColor: AppColors.textSecondary.withValues(
            alpha: 0.5,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll<Color>(Colors.white),
        trackColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? roleColor
              : AppColors.navy.withValues(alpha: 0.16),
        ),
        trackOutlineColor:
            const WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? roleColor
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll<Color>(Colors.white),
        side: BorderSide(color: AppColors.navy.withValues(alpha: 0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStatePropertyAll<Color>(roleColor),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: roleColor),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withValues(alpha: AppGlass.innerFill),
        selectedColor: roleTint,
        disabledColor: Colors.white.withValues(alpha: 0.3),
        side: const BorderSide(color: AppColors.ring),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        labelStyle: AppTypography.caption.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: AppTypography.caption.copyWith(
          color: roleColor,
          fontWeight: FontWeight.w600,
        ),
        checkmarkColor: roleColor,
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        textColor: AppColors.textPrimary,
        iconColor: AppColors.textSecondary,
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: AppGlass.panelFill),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: glassShape,
        margin: EdgeInsets.zero,
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: AppColors.danger,
        textColor: Colors.white,
        textStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          fontFamily: AppTypography.fontFamily,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: roleColor,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        extendedTextStyle: AppTypography.button,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: roleColor,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: roleColor,
        dividerColor: Colors.transparent,
        labelStyle: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: AppTypography.caption,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.textPrimary.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: AppTypography.caption.copyWith(
          fontSize: 12,
          color: Colors.white,
        ),
      ),
    );
  }
}
