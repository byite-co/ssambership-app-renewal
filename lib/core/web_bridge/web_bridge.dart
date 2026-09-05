import 'package:url_launcher/url_launcher.dart';

import 'web_bridge_config.dart';

/// 웹 열기 결과. notConfigured = baseUrl 미확정(안내 폴백),
/// failed = 열기 실패 또는 URL 검증 탈락(https/허용 호스트 아님 — 열지 않음).
enum WebOpenResult { opened, notConfigured, failed }

/// URL 열기 함수(주입 가능 — 테스트에서 fake).
typedef UrlLauncher = Future<bool> Function(Uri uri);

/// 웹 브릿지 서비스 — 정보 페이지·본인인증·회원 탈퇴 폴백을 외부 브라우저로 연다.
///
/// ★ A-4b ⑩: 구독·해지·환불·정산·요금제·프로필·개별질문은 앱이 직접 처리한다 —
///   이 서비스에 결제·관리 동선은 없다. URL 은 [WebBridgeConfig] 한 곳에서 온다.
///   baseUrl 미확정이면 아무 URL 도 만들지 않고 [WebOpenResult.notConfigured] 를 돌려준다(날조 없음).
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

  /// 본인인증 온보딩(웹 위임 — 앱은 인증 플로우를 두지 않는다).
  Future<WebOpenResult> openIdentityVerify({String source = 'app'}) =>
      _open(WebBridgeConfig.identityVerifyPath, <String, String>{'src': source});

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
