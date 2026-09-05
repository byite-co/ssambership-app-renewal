import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Canonical v3 type scale. Every style names Pretendard explicitly.
///
/// §5 의 6단계(title·bigNumber·section·body·caption·button)가 정본이고, 아래
/// 파생 3종(bodyStrong·captionSecondary·meta)은 시안(design-v3 §0·§3-1)의
/// 목록 행 제목(15 SemiBold)·보조 문장(13 보조색)·행 우측 시각(12 보조색)을
/// 그대로 옮긴 것이다 — 화면마다 copyWith 를 반복하지 않기 위해 둔다.
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

  /// 목록 행 제목·강조 본문 — 15 SemiBold.
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    fontFamily: fontFamily,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    fontFamily: fontFamily,
  );

  /// 보조 문장(설명·메타) — 13 · 보조색.
  static const TextStyle captionSecondary = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    fontFamily: fontFamily,
    color: AppColors.textSecondary,
  );

  /// 행 우측 시각·아주 작은 메타 — 12 · 보조색.
  static const TextStyle meta = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    fontFamily: fontFamily,
    color: AppColors.textSecondary,
  );
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontFamily: fontFamily,
  );
}
