import 'package:flutter/material.dart';

import '../core/auth/auth_service.dart';
import 'role_accent.dart';
import 'tokens/color_tokens.dart';
import 'typography_tokens.dart';

/// 토큰 → ThemeData 빌드. 화면은 raw 색 대신 Theme/토큰을 참조한다.
///
/// 라이트 테마 + 역할색: role 에 따라 강조(accent) 계열만 분기(학생 파랑/멘토 초록).
/// 배경·표면·텍스트·상태색은 [ColorTokens] 공통.
class AppTheme {
  AppTheme._();

  static ThemeData build(AppRole role) {
    final RoleAccent ra = RoleAccent.forRole(role);

    // ★ seed 는 '역할 무관 중립 슬레이트'로 고정한다.
    //   과거 seedColor=ra.accent 는 ColorScheme.fromSeed 가 파생 표면
    //   (surfaceContainer*/secondaryContainer/surfaceVariant/surfaceTint)까지
    //   역할 hue(멘토 초록/학생 파랑)로 물들여 Card·Chip·Switch·Dialog·filled
    //   TextField·Dropdown 배경이 오염됐다(실사 지적). → seed 를 중립으로 두고,
    //   역할색은 아래 primary 슬롯에만 명시 공급한다(강조 요소 전용).
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: ColorTokens.muted, // 중립 슬레이트(page/surface/border 계열과 조화)
      brightness: Brightness.light,
    ).copyWith(
      // ── 역할 강조색: primary 슬롯에만(버튼·강조 요소가 참조) ──
      primary: ra.accent,
      onPrimary: ra.onAccent,
      error: ColorTokens.danger,
      // ── 표면·컨테이너 전 계층을 중립 토큰으로 고정(M3 파생 틴트 제거) ──
      surface: ColorTokens.surface,
      onSurface: ColorTokens.primary,
      onSurfaceVariant: ColorTokens.secondary,
      surfaceContainerLowest: ColorTokens.surface,
      surfaceContainerLow: ColorTokens.surface,
      surfaceContainer: ColorTokens.elevated,
      surfaceContainerHigh: ColorTokens.elevated,
      surfaceContainerHighest: ColorTokens.elevated,
      surfaceDim: ColorTokens.page,
      surfaceBright: ColorTokens.surface,
      // Chip(filled)·tonal 버튼 등이 읽는 컨테이너 → 중립(역할색은 명시 슬롯에서만).
      secondaryContainer: ColorTokens.elevated,
      onSecondaryContainer: ColorTokens.primary,
      // 외곽선 계열 → 우리 border 토큰.
      outline: ColorTokens.border,
      outlineVariant: ColorTokens.border,
      // elevation 오버레이 틴트 제거(기본=primary라 역할색으로 물듦).
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // 전역 폰트: Pretendard(정적 4종 400/500/600/700 등록). 시스템 폰트 대체.
      fontFamily: AppType.fontFamily,
      scaffoldBackgroundColor: ColorTokens.page,
      // 터치 피드백(A-6): 탭 가능한 카드·리스트·버튼 InkWell 에 은은한 역할색 리플.
      // "정적 웹페이지" → "반응형 앱" 느낌. 과하지 않게(splash ~10%, highlight ~5%).
      splashColor: ra.accent.withValues(alpha: 0.10),
      highlightColor: ra.accent.withValues(alpha: 0.05),
      // 하단 탭: 활성 표시(indicator)=역할 soft, 선택 아이콘/라벨=역할 accent.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ColorTokens.surface,
        indicatorColor: ra.accentSoft,
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
          (Set<WidgetState> states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? ra.accent
                : ColorTokens.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? ra.accent
                : ColorTokens.muted,
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: ColorTokens.page,
        foregroundColor: ColorTokens.primary,
        elevation: 0,
        centerTitle: false,
        // 화면 타이틀 = 새 타입 스케일 display(24/w700). 전역 일관.
        titleTextStyle: AppType.display,
      ),
      // 역할 강조색을 화면/위젯이 AppAccent.of(context) 로 읽는다.
      extensions: <ThemeExtension<dynamic>>[ra],
    );
  }
}
