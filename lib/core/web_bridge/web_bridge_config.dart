/// 웹 브릿지 URL 단일 소스(Commerce-Zero). ★ 결제/구독/충전/정산은 앱이 아니라 '웹'에서.
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

  /// 관리(구독·정산)/프로필 웹 경로. 실제 Next.js 라우트와 대조해 확정(2026-07 실측).
  /// ★ 구매 유도 경로(구독 신청 `/subscribe`·충전 `/wallet/charge`)는 두지 않는다 —
  ///   P0-3 死배선 정리(2026-07-12). 재도입은 정책 판단 확정 후.
  static const String billingManagePath =
      '/subscriptions'; // app/(student)/subscriptions (구독 취소·관리)
  static const String payoutManagePath =
      '/mentor/payouts'; // app/(mentor)/mentor/payouts
  static const String profileEditPath =
      '/mentor/profile'; // app/(mentor)/mentor/profile

  /// 정보/지원/리뷰 웹 경로(마이페이지 행 배선용, 실측 라우트).
  static const String termsPath = '/legal/terms'; // app/(public)/legal/terms
  static const String privacyPath =
      '/legal/privacy'; // app/(public)/legal/privacy
  static const String supportPath =
      '/support'; // app/(public)/support (고객센터·FAQ 허브)
  static const String reviewsPath =
      '/mentor/reviews'; // app/(mentor)/mentor/reviews

  /// 회원 탈퇴(계정 삭제) — 앱은 삭제하지 않고 웹 페이지만 연다.
  static const String accountDeletePath =
      '/account/delete'; // app/(student)/account/delete

  /// 개별질문 신규 등록(학생) — 경계 확정(2026-08-05): 네이티브 등록 화면 진입을
  /// 제거했고 신규 등록은 웹에서만 한다. 조회·답변·첨부·첨삭은 앱에 그대로 남는다.
  static const String iqCreatePath =
      '/individual-questions/new'; // app/(student)/individual-questions/new

  /// 멘토 지정형 개별질문 등록 — 웹 실측 라우트의 path param 계약을 그대로 쓴다.
  static String iqCreateForMentorPath(String mentorId) =>
      // app/(student)/mentors/[mentorId]/individual-question/new
      '/mentors/${Uri.encodeComponent(mentorId)}/individual-question/new';

  /// baseUrl 이 채워졌는지(=웹 열기 가능). 비면 안내 폴백.
  static bool get isConfigured => baseUrl.isNotEmpty;
}
