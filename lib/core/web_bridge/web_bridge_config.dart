/// 웹 브릿지 URL 단일 소스 — 정보 페이지·본인인증·회원 탈퇴 폴백만 남는다(A-4b ⑩).
///
/// ══════════════════════════════════════════════════════════════════════
/// ★★ 운영 도메인 확정(2026-07) ★★
///   기본값(아래 defaultValue)이 곧 출시용 운영 웹 도메인이다 — 릴리즈 빌드는
///   별도 주입 없이 그대로 쓴다. 스테이징·로컬 웹 테스트는
///   `--dart-define=WEB_BASE_URL=https://…` 로 오버라이드한다.
///   빈 값(`--dart-define=WEB_BASE_URL=`)을 주입하면 웹을 열지 않고
///   "웹에서 진행(준비 중)" 안내 폴백이 동작한다([isConfigured]).
/// ══════════════════════════════════════════════════════════════════════
class WebBridgeConfig {
  WebBridgeConfig._();

  /// 웹 베이스 URL. ★끝 슬래시 없음 — buildUri 가 '$baseUrl$path'(path 는 '/…' 시작)로
  /// 조립하므로 슬래시를 붙이면 '//' 이중슬래시가 난다.
  static const String baseUrl = String.fromEnvironment(
    'WEB_BASE_URL',
    defaultValue: 'https://ssambership.com', // 운영 도메인(오너 확정, 2026-07)
  );

  /// 정보/지원/리뷰 웹 경로(마이페이지 행 배선용, 실측 라우트).
  /// ★ A-4b ⑩: 구독 관리·정산 관리·멘토 프로필·개별질문 등록 경로는 앱이 직접
  ///   처리하므로 삭제했다. 남는 웹 진입은 정보 페이지·본인인증·회원 탈퇴 폴백뿐.
  static const String termsPath = '/legal/terms'; // app/(public)/legal/terms
  static const String privacyPath =
      '/legal/privacy'; // app/(public)/legal/privacy
  static const String supportPath =
      '/support'; // app/(public)/support (고객센터·FAQ 허브)
  static const String reviewsPath =
      '/mentor/reviews'; // app/(mentor)/mentor/reviews

  /// 본인인증(NICE) 온보딩 — 앱은 인증 플로우를 두지 않고 웹에 위임한다(S-C).
  /// 게이트 판정은 앱(IdentityGate)·웹이 같은 플래그로 하고, 인증 자체는 이 페이지.
  static const String identityVerifyPath =
      '/onboarding/verify'; // app/onboarding/verify

  /// 회원 탈퇴(계정 삭제) — 앱은 삭제하지 않고 웹 페이지만 연다.
  static const String accountDeletePath =
      '/account/delete'; // app/(student)/account/delete

  /// baseUrl 이 채워졌는지(=웹 열기 가능). 비면 안내 폴백.
  static bool get isConfigured => baseUrl.isNotEmpty;
}
