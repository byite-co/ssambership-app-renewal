import 'package:url_launcher/url_launcher.dart';

import 'web_bridge_config.dart';

/// 웹 열기 결과. notConfigured = baseUrl 미확정(안내 폴백),
/// failed = 열기 실패 또는 URL 검증 탈락(https/허용 호스트 아님 — 열지 않음).
enum WebOpenResult { opened, notConfigured, failed }

/// URL 열기 함수(주입 가능 — 테스트에서 fake).
typedef UrlLauncher = Future<bool> Function(Uri uri);

/// 웹 브릿지 서비스 — 관리/정보/계정 동선을 '웹으로만' 연다(Commerce-Zero).
///
/// ★ 앱은 결제/가격입력/구매를 하지 않는다. 이 서비스는 결제 행위를 하지 않고,
///   웹의 해당 페이지를 외부 브라우저로 여는 것뿐이다. URL 은 [WebBridgeConfig] 한 곳에서 온다.
///   baseUrl 미확정이면 아무 URL 도 만들지 않고 [WebOpenResult.notConfigured] 를 돌려준다(날조 없음).
/// ★ 구매 유도 동선(구독 신청·캐시 충전)은 두지 않는다 — P0-3 死배선 정리(2026-07-12).
class WebBridge {
  WebBridge({UrlLauncher? launcher, String? baseUrl})
      : _launcher = launcher ?? _defaultLauncher,
        _baseUrl = baseUrl ?? WebBridgeConfig.baseUrl;

  final UrlLauncher _launcher;
  final String _baseUrl;

  static Future<bool> _defaultLauncher(Uri uri) async {
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool get isConfigured => _baseUrl.isNotEmpty;

  /// 결제·구독 관리(학생).
  Future<WebOpenResult> openBillingManage({String source = 'app'}) =>
      _open(WebBridgeConfig.billingManagePath, <String, String>{'src': source});

  /// 정산 관리(멘토).
  Future<WebOpenResult> openPayoutManage({String source = 'app'}) =>
      _open(WebBridgeConfig.payoutManagePath, <String, String>{'src': source});

  /// 프로필 편집(멘토 — 웹 우선).
  Future<WebOpenResult> openProfileEdit({String source = 'app'}) =>
      _open(WebBridgeConfig.profileEditPath, <String, String>{'src': source});

  /// 이용약관(정보 페이지).
  Future<WebOpenResult> openTerms({String source = 'app'}) =>
      _open(WebBridgeConfig.termsPath, <String, String>{'src': source});

  /// 개인정보처리방침(정보 페이지).
  Future<WebOpenResult> openPrivacy({String source = 'app'}) =>
      _open(WebBridgeConfig.privacyPath, <String, String>{'src': source});

  /// 고객지원 허브(FAQ·분쟁·환불·신고 안내).
  Future<WebOpenResult> openSupport({String source = 'app'}) =>
      _open(WebBridgeConfig.supportPath, <String, String>{'src': source});

  /// 리뷰(멘토 계정 기준).
  Future<WebOpenResult> openReviews({String source = 'app'}) =>
      _open(WebBridgeConfig.reviewsPath, <String, String>{'src': source});

  /// 회원 탈퇴(계정 삭제) — 웹 페이지만 연다(앱 내 삭제 흐름 없음).
  Future<WebOpenResult> openAccountDelete({String source = 'app'}) =>
      _open(WebBridgeConfig.accountDeletePath, <String, String>{'src': source});

  /// URL 조립(테스트/검토용). baseUrl 미확정/파싱 불가면 null.
  /// ★ 조립만 한다 — 실제 열기 전 검증은 [isAllowedUri] 가 한다.
  Uri? buildUri(String path,
      [Map<String, String> query = const <String, String>{}]) {
    if (_baseUrl.isEmpty || path.isEmpty) return null;
    final Uri? base = Uri.tryParse('$_baseUrl$path');
    if (base == null) return null;
    if (query.isEmpty) return base;
    return base.replace(queryParameters: <String, String>{
      ...base.queryParameters,
      ...query,
    });
  }

  /// 열어도 되는 URL 인지(P3-7 하드닝) — 어긋나면 열지 않는다.
  ///
  /// - https 만 허용(http 등 다른 스킴 차단).
  /// - 호스트는 설정된 base 호스트와 **정확히 같거나** 그 서브도메인만 허용.
  ///   서브도메인 판정은 반드시 '.' 를 붙인 접미사 비교로 한다 —
  ///   `evilssambership.com` 이 `.ssambership.com` 허용목록을 통과하면 안 되고,
  ///   `ssambership.com.evil.com` 같은 접두 위장도 통과하면 안 된다.
  bool isAllowedUri(Uri uri) {
    if (_baseUrl.isEmpty) return false;
    final Uri? base = Uri.tryParse(_baseUrl);
    if (base == null) return false;
    final String baseHost = base.host.toLowerCase();
    if (baseHost.isEmpty) return false;
    if (uri.scheme != 'https') return false; // https 강제
    final String host = uri.host.toLowerCase();
    return host == baseHost || host.endsWith('.$baseHost');
  }

  Future<WebOpenResult> _open(String path, Map<String, String> query) async {
    if (_baseUrl.isEmpty) return WebOpenResult.notConfigured; // 미확정 → 안내 폴백.
    final Uri? uri = buildUri(path, query);
    // 조립 실패 또는 검증 탈락(http/타 호스트) → 열지 않고 실패 반환.
    if (uri == null || !isAllowedUri(uri)) return WebOpenResult.failed;
    final bool ok = await _launcher(uri);
    return ok ? WebOpenResult.opened : WebOpenResult.failed;
  }
}
