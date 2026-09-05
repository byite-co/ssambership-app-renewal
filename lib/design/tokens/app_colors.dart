import 'package:flutter/material.dart';

/// Canonical v3 glass colors. These values are contrast-verified and fixed.
abstract class AppColors {
  static const Color bgTop = Color(0xFFF6F9FD);
  static const Color bgMid = Color(0xFFEDF3FA);
  static const Color bgBot = Color(0xFFF2F6FB);

  /// 배경 그라디언트 위 48% 유리 패널의 실효색(design-tokens §2-1). 다이얼로그·
  /// 팝업 메뉴처럼 반투명 채움을 쓸 수 없는 Material 표면에 이 값을 쓴다.
  static const Color glass = Color(0xFFF6F9FC);

  static const Color textPrimary = Color(0xFF191F28);
  static const Color textSecondary = Color(0xFF5F6B7A);

  /// 성공 = 멘토 초록과 동일(design-tokens §3-3).
  static const Color success = Color(0xFF0B6B4E);
  static const Color warning = Color(0xFFB54708);
  static const Color danger = Color(0xFFC2334D);

  static const Color navy = Color(0xFF1C2A4A);

  /// 유리 가장자리 링(남색 9%). 콘텐츠 사이 구분선으로는 쓰지 않는다.
  static const Color ring = Color(0x171C2A4A);
}

/// Role accents selected for sufficient contrast on the glass surface.
abstract class RoleColors {
  static const Color student = Color(0xFF2563EB);
  static const Color mentor = Color(0xFF0B6B4E);
}
