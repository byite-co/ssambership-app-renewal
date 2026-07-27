import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/individual_question/data/iq_attachment_url_resolver.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// P3-6 — IQ 첨부 서명 URL 리졸버: 캐시 재사용·안전 여유 만료·사용자 전환
/// 무효화·실패 미캐시(재시도). fake 백엔드 + 가짜 시계(주입형)로 검증한다.
class _FakeBackend implements IqAttachmentUrlBackend {
  int signCount = 0;
  int lastExpiresIn = 0;
  String? userId = 'user-1';
  Object? nextError;

  @override
  String? get currentUserId => userId;

  @override
  Future<String> createSignedUrl(
      String storagePath, int expiresInSeconds) async {
    final Object? error = nextError;
    if (error != null) {
      nextError = null; // 1회성 실패 — 다음 호출은 성공(재시도 검증용).
      throw error;
    }
    signCount++;
    lastExpiresIn = expiresInSeconds;
    return 'signed://$userId/$storagePath#$signCount';
  }
}

void main() {
  test('만료 전엔 캐시 재사용, 안전 여유(60초) 이후엔 재발급', () async {
    final _FakeBackend backend = _FakeBackend();
    DateTime now = DateTime(2026, 7, 1, 12, 0, 0);
    final IqAttachmentUrlResolver resolver = IqAttachmentUrlResolver(
      backend,
      ttl: const Duration(hours: 1),
      safetyMargin: const Duration(seconds: 60),
      now: () => now,
    );

    final String u1 = await resolver.signedUrl('q-1/a.png');
    expect(backend.signCount, 1);
    expect(backend.lastExpiresIn, 3600); // ttl 초 전달.

    // 58분 뒤 — 아직 (ttl - 여유) 전 → 같은 URL 재사용(재발급 없음).
    now = now.add(const Duration(minutes: 58));
    final String u2 = await resolver.signedUrl('q-1/a.png');
    expect(backend.signCount, 1);
    expect(u2, u1);

    // 59분 30초 시점 — 실제 만료(60분) 전이지만 안전 여유(60초) 안 → 재발급.
    now = now.add(const Duration(seconds: 90));
    final String u3 = await resolver.signedUrl('q-1/a.png');
    expect(backend.signCount, 2);
    expect(u3, isNot(u1));
  });

  test('경로가 다르면 각각 발급(캐시 키 분리)', () async {
    final _FakeBackend backend = _FakeBackend();
    final IqAttachmentUrlResolver resolver = IqAttachmentUrlResolver(backend);

    await resolver.signedUrl('q-1/a.png');
    await resolver.signedUrl('q-1/b.png');
    expect(backend.signCount, 2);
  });

  test('사용자가 바뀌면 이전 사용자 캐시를 재사용하지 않는다(키에 uid 포함)', () async {
    final _FakeBackend backend = _FakeBackend();
    final IqAttachmentUrlResolver resolver = IqAttachmentUrlResolver(backend);

    final String u1 = await resolver.signedUrl('q-1/a.png');
    expect(backend.signCount, 1);

    // 계정 전환 — 같은 경로라도 새 사용자 키로 재발급(RLS 와 일관).
    backend.userId = 'user-2';
    final String u2 = await resolver.signedUrl('q-1/a.png');
    expect(backend.signCount, 2);
    expect(u2, isNot(u1));
  });

  test('발급 실패는 캐시를 오염시키지 않는다 — 다음 호출이 재시도해 성공', () async {
    final _FakeBackend backend = _FakeBackend()
      ..nextError = const AppError('백엔드에 연결되어 있지 않아요.');
    final IqAttachmentUrlResolver resolver = IqAttachmentUrlResolver(backend);

    await expectLater(
        resolver.signedUrl('q-1/a.png'), throwsA(isA<AppError>()));
    expect(backend.signCount, 0); // 실패 — 발급 기록 없음.

    // 재시도 → 성공하고, 이후엔 캐시 재사용.
    final String url = await resolver.signedUrl('q-1/a.png');
    expect(backend.signCount, 1);
    expect(await resolver.signedUrl('q-1/a.png'), url);
    expect(backend.signCount, 1);
  });
}
