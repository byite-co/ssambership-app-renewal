import '../../../../core/config/app_config.dart';

/// 서명 URL 외부 열기(P3-7) 전 신뢰 검증 — 우리 Supabase 스토리지 호스트만 허용.
///
/// 규칙:
/// - https 필수. 단, 로컬 개발 스택(AppConfig 가 http 루프백)일 때만 http 루프백 허용.
/// - 호스트는 [AppConfig.supabaseUrl] 의 호스트와 정확히 일치해야 한다
///   (suffix 우회 금지 — 'evil{host}' 형태 불통).
bool isTrustedAttachmentUri(Uri uri, {Uri? backendBase}) {
  final Uri base = backendBase ?? Uri.parse(AppConfig.supabaseUrl);
  if (uri.host.isEmpty || uri.host != base.host) return false;
  if (uri.scheme == 'https') return true;
  // 로컬 supabase(http://127.0.0.1:54321 등) 개발 편의 — 루프백 http 만.
  final bool loopback = uri.host == '127.0.0.1' || uri.host == 'localhost';
  return uri.scheme == 'http' && loopback && base.scheme == 'http';
}
