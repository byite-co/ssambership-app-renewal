import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/attachments/trusted_attachment_url.dart';

/// P3-7: 서명 URL 외부 열기 전 신뢰 검증 — 우리 스토리지 호스트만, https 강제.
void main() {
  final Uri prodBase = Uri.parse('https://abc.supabase.co');
  final Uri localBase = Uri.parse('http://127.0.0.1:54321');

  test('동일 호스트 + https → 허용', () {
    expect(
      isTrustedAttachmentUri(
          Uri.parse('https://abc.supabase.co/storage/v1/object/sign/x'),
          backendBase: prodBase),
      isTrue,
    );
  });

  test('http(비루프백)·다른 호스트·suffix 우회 → 차단', () {
    expect(
      isTrustedAttachmentUri(Uri.parse('http://abc.supabase.co/x'),
          backendBase: prodBase),
      isFalse,
      reason: 'https 강제',
    );
    expect(
      isTrustedAttachmentUri(Uri.parse('https://evil.com/x'),
          backendBase: prodBase),
      isFalse,
    );
    expect(
      isTrustedAttachmentUri(Uri.parse('https://evilabc.supabase.co/x'),
          backendBase: prodBase),
      isFalse,
      reason: '호스트 정확 일치 — suffix 우회 금지',
    );
    expect(
      isTrustedAttachmentUri(Uri.parse('https://abc.supabase.co.evil.com/x'),
          backendBase: prodBase),
      isFalse,
    );
  });

  test('로컬 개발(http 루프백 백엔드)일 때만 http 루프백 허용', () {
    expect(
      isTrustedAttachmentUri(Uri.parse('http://127.0.0.1:54321/storage/x'),
          backendBase: localBase),
      isTrue,
    );
    // 운영(https 백엔드)에서는 루프백 http 도 불허.
    expect(
      isTrustedAttachmentUri(Uri.parse('http://127.0.0.1/x'),
          backendBase: prodBase),
      isFalse,
    );
  });

  test('상대 경로·호스트 없음 → 차단', () {
    expect(
        isTrustedAttachmentUri(Uri.parse('/local/path'), backendBase: prodBase),
        isFalse);
  });
}
