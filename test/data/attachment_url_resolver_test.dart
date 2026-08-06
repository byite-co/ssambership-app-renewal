import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/attachments/attachment_url_resolver.dart';

/// 서명 URL 발급 호출 횟수를 세는 fake 백엔드.
class _FakeBackend implements AttachmentUrlBackend {
  @override
  String? get currentUserId => userId;

  String? userId;

  int signCount = 0;
  int lastExpiresIn = 0;

  @override
  Future<String> createSignedUrl(String storagePath, int expiresInSeconds) async {
    signCount++;
    lastExpiresIn = expiresInSeconds;
    return 'signed://$storagePath#$signCount';
  }

  @override
  Future<Uint8List> download(String storagePath) async =>
      Uint8List.fromList(<int>[1, 2, 3]);
}

void main() {
  test('만료 전엔 캐시 재사용, 만료 후엔 재발급', () async {
    final _FakeBackend backend = _FakeBackend();
    DateTime now = DateTime(2026, 7, 1, 12, 0, 0);
    final AttachmentUrlResolver resolver = AttachmentUrlResolver(
      backend,
      ttl: const Duration(hours: 1),
      now: () => now,
    );

    final String u1 = await resolver.signedUrl('r1/t1/a.png');
    expect(backend.signCount, 1);
    expect(backend.lastExpiresIn, 3600); // ttl 초 전달

    // 59분 뒤 — 아직 만료 전 → 같은 URL 재사용(재발급 없음).
    now = now.add(const Duration(minutes: 59));
    final String u2 = await resolver.signedUrl('r1/t1/a.png');
    expect(backend.signCount, 1);
    expect(u2, u1);

    // 61분 시점 — 만료됨 → 재발급.
    now = now.add(const Duration(minutes: 2));
    final String u3 = await resolver.signedUrl('r1/t1/a.png');
    expect(backend.signCount, 2);
    expect(u3, isNot(u1));
  });

  test('경로가 다르면 각각 발급(캐시 키 분리)', () async {
    final _FakeBackend backend = _FakeBackend();
    final AttachmentUrlResolver resolver = AttachmentUrlResolver(backend);

    await resolver.signedUrl('r1/t1/a.png');
    await resolver.signedUrl('r1/t1/b.png');
    expect(backend.signCount, 2);
  });

  test('download 는 캐시 없이 백엔드로 위임', () async {
    final _FakeBackend backend = _FakeBackend();
    final AttachmentUrlResolver resolver = AttachmentUrlResolver(backend);

    final Uint8List bytes = await resolver.download('r1/t1/a.png');
    expect(bytes, <int>[1, 2, 3]);
    expect(backend.signCount, 0); // 서명 URL 발급과 무관
  });

  test('사용자가 바뀌면 캐시 미재사용(계정 전환 격리 — N14 전역 공유 안전장치)', () async {
    final _FakeBackend backend = _FakeBackend()..userId = 'u1';
    final AttachmentUrlResolver resolver = AttachmentUrlResolver(backend);

    await resolver.signedUrl('r1/t1/a.png');
    backend.userId = 'u2'; // 계정 전환
    await resolver.signedUrl('r1/t1/a.png');
    expect(backend.signCount, 2); // 이전 사용자 캐시 재사용 금지
  });

  test('supabase() 는 프로세스 전역 공유 인스턴스를 돌려준다(N14)', () {
    expect(identical(AttachmentUrlResolver.supabase(),
        AttachmentUrlResolver.supabase()), isTrue);
  });

  test('isImageAttachment: image/* 만 true', () {
    expect(isImageAttachment('image/png'), isTrue);
    expect(isImageAttachment('image/jpeg'), isTrue);
    expect(isImageAttachment('application/pdf'), isFalse);
    expect(isImageAttachment(null), isFalse);
  });
}
