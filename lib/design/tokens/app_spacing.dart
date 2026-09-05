/// Canonical v3 spacing values — 4의 배수(design-tokens §5).
abstract class AppSpacing {
  static const double unit = 4;
  static const double base = 16;
  static const double section = 24;
  static const double screenH = 20;
  static const double buttonHeight = 56;
  static const double listRowMin = 56;

  // 4의 배수 스텝 — 화면은 임의 숫자 대신 이 값을 쓴다.
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;

  /// 카드와 카드 사이(목록). v3 는 링·그림자로 카드를 분리하므로 12 면 충분하다.
  static const double listGap = 12;
}

/// Canonical v3 corner radii.
abstract class AppRadius {
  static const double card = 16;
  static const double button = 12;
  static const double input = 12;
  static const double badge = 6;

  /// 이니셜 아바타(둥근 사각 — design-v3 §3-1 목록 행 44px·반경 16).
  static const double avatar = 16;
}
