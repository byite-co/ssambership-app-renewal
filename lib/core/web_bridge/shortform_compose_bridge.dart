import 'dart:convert';
import 'dart:typed_data';

/// 숏폼 작성 완료 종류 — 웹 완료 브릿지의 `result` enum 과 1:1.
enum ShortformComposeResult { draft, published }

/// 앱 숏폼 작성 WebView 의 URL 계약(순수 — 플랫폼·플러그인 미의존, 단위테스트 대상).
///
/// ★ 이 WebView 는 `shortform_create` 단일 목적이다. 결제·구독·충전 경로는
///   allowlist 에 존재하지 않아 탐색 자체가 차단된다(Commerce-Zero 불변).
/// ★ 토큰은 bootstrap POST 의 body 로만 전달한다 — URL query/fragment·JS 채널·
///   localStorage 로는 절대 싣지 않는다.
class ShortformComposeBridge {
  ShortformComposeBridge({required String baseUrl})
      : baseUri = Uri.parse(baseUrl);

  /// WEB_BASE_URL(끝 슬래시 없음) 파싱 결과. host 는 exact 비교에 쓴다.
  final Uri baseUri;

  static const String bootstrapPath = '/api/app-session/bootstrap';
  static const String composePath = '/app/community/shortform/new';
  static const String bridgeCompletePath = '/app/bridge/complete';
  static const String bridgeErrorPath = '/app/bridge/error';

  /// 서버 enum 과 1:1 인 단일 target. 결제용 target 은 만들지 않는다.
  static const String bootstrapTarget = 'shortform_create';

  Uri get bootstrapUri => Uri.parse('${_origin()}$bootstrapPath');

  String _origin() => Uri(
          scheme: baseUri.scheme,
          host: baseUri.host,
          port: baseUri.hasPort ? baseUri.port : null)
      .toString();

  /// Android WebView 의 postUrl 경로는 커스텀 헤더가 적용되지 않고
  /// `application/x-www-form-urlencoded` 로 전송된다 — 그 계약에 맞춰
  /// 토큰·target 을 percent-encode 한 form 본문을 만든다.
  static Uint8List buildBootstrapBody({
    required String accessToken,
    required String refreshToken,
  }) {
    final String body = Uri(queryParameters: <String, String>{
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'target': bootstrapTarget,
    }).query;
    return Uint8List.fromList(utf8.encode(body));
  }

  /// 탐색(문서 이동) allowlist.
  ///
  /// - https 만(javascript:, file:, data:, intent:, http: 전부 차단)
  /// - host 는 WEB_BASE_URL 과 **정확히 일치**(evil suffix — 예:
  ///   `ssambership.com.evil.com` — 차단. 서브도메인도 허용하지 않는다)
  /// - 경로는 bootstrap·작성 표면·완료/오류 브릿지 4종만.
  ///   `/subscribe`·`/wallet/charge` 등 그 외 전부 차단.
  bool isAllowedNavigation(Uri uri) {
    if (uri.scheme != 'https') return false;
    if (uri.host.isEmpty || uri.host != baseUri.host) return false;
    final String p = uri.path;
    return p == bootstrapPath ||
        p == composePath ||
        p == bridgeCompletePath ||
        p == bridgeErrorPath;
  }

  /// 완료 브릿지 판정 — 같은 host 의 `/app/bridge/complete` 이고
  /// `kind=shortform` + `result∈{draft,published}` 일 때만 결과를 돌려준다.
  /// (그 외 값은 null → 호출자가 일반 allowlist 규칙으로 처리)
  ShortformComposeResult? completionOf(Uri uri) {
    if (uri.scheme != 'https' || uri.host != baseUri.host) return null;
    if (uri.path != bridgeCompletePath) return null;
    if (uri.queryParameters['kind'] != 'shortform') return null;
    switch (uri.queryParameters['result']) {
      case 'draft':
        return ShortformComposeResult.draft;
      case 'published':
        return ShortformComposeResult.published;
    }
    return null;
  }
}
