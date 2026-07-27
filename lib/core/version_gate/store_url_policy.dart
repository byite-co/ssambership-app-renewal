/// 스토어 URL 재검증(앱측 최종 방어선).
///
/// 서버(get_mobile_app_version_policy)가 store_url 을 검증해 내려주지만,
/// 앱은 열기 직전에 **반드시** 다시 검증한다 — https + 허용 호스트 '정확 일치'만.
/// (서브도메인/접미 위장 차단: 정확 일치이므로 `play.google.com.evil.com` 류는
/// 통과할 수 없다.)
library;

/// 허용 스토어 호스트(정확 일치 전용).
const Set<String> kAllowedStoreHosts = <String>{
  'play.google.com',
  'apps.apple.com',
  'itunes.apple.com',
};

/// 검증 통과 시 Uri, 아니면 null(열지 않는다).
/// - null/빈 문자열/파싱 불가 → null
/// - https 아님(http 등) → null
/// - 호스트가 허용 목록과 정확히 일치하지 않음 → null
Uri? validatedStoreUri(String? url) {
  if (url == null || url.isEmpty) return null;
  final Uri? uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (uri.scheme != 'https') return null;
  if (!kAllowedStoreHosts.contains(uri.host.toLowerCase())) return null;
  return uri;
}
