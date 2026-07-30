import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/community_post_images.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// 이미지 계약(앱 계약 §5·§6.1) — 로컬 검증(MIME·magic bytes·크기)·ref 해석·
/// signed URL 해석기(TTL 3600·메모리 캐시·레거시 URL 호환) 단위 고정.

Uint8List _png() => Uint8List.fromList(
    <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4]);

Uint8List _jpeg() => Uint8List.fromList(
    <int>[0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0]);

class _FakeBackend implements CommunityPostImageBackend {
  int signCalls = 0;
  String? lastPath;
  int? lastTtl;

  @override
  Future<String> createSignedUrl(String objectPath, int ttlSeconds) async {
    signCalls++;
    lastPath = objectPath;
    lastTtl = ttlSeconds;
    return 'https://s.example/sign/$objectPath?n=$signCalls';
  }

  @override
  Future<void> removeObjects(List<String> objectPaths) async {}

  @override
  Future<void> uploadObject({
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {}
}

void main() {
  group('validateCommunityPostImage (§6.1 로컬 1차 검증)', () {
    test('정상 PNG 통과 + safe name 정규화', () {
      final ValidatedPostImage v = validateCommunityPostImage(
          bytes: _png(), fileName: '내 사진 (1).PNG');
      expect(v.contentType, 'image/png');
      expect(v.ext, 'png');
      expect(RegExp(r'^[a-z0-9._-]+$').hasMatch(v.safeName), isTrue);
    });

    test('jpeg 확장자는 jpg 로 정규화', () {
      final ValidatedPostImage v =
          validateCommunityPostImage(bytes: _jpeg(), fileName: 'a.jpeg');
      expect(v.ext, 'jpg');
      expect(v.contentType, 'image/jpeg');
    });

    test('허용 외 확장자(pdf) 거부', () {
      expect(
          () => validateCommunityPostImage(bytes: _png(), fileName: 'a.pdf'),
          throwsA(isA<AppError>()));
    });

    test('확장자 위장(magic bytes 불일치) 거부 — png 이름 + jpeg 바이트', () {
      expect(
          () => validateCommunityPostImage(bytes: _jpeg(), fileName: 'a.png'),
          throwsA(isA<AppError>()));
    });

    test('5MiB 초과 거부', () {
      final Uint8List big = Uint8List(kCommunityPostImageMaxBytes + 1);
      big.setRange(0, 12, _png());
      expect(
          () => validateCommunityPostImage(bytes: big, fileName: 'big.png'),
          throwsA(isA<AppError>()));
    });
  });

  group('parseCommunityPostImageRef (§5 — 정본 ref + 레거시 URL 호환)', () {
    test('정본 ref → objectPath', () {
      expect(parseCommunityPostImageRef('community-post-images/u-1/a.png'),
          'u-1/a.png');
    });

    test('레거시 signed URL → path 추출(만료 토큰 무시·재서명용)', () {
      expect(
          parseCommunityPostImageRef(
              'https://xyz.supabase.co/storage/v1/object/sign/'
              'community-post-images/u-1/legacy.jpg?token=EXPIRED'),
          'u-1/legacy.jpg');
    });

    test('타 버킷·비정형·경로조작 → null(그 이미지만 숨김)', () {
      expect(parseCommunityPostImageRef('shortform-videos/u/v.mp4'), isNull);
      expect(parseCommunityPostImageRef('community-post-images/solo'), isNull);
      expect(parseCommunityPostImageRef('community-post-images/u/../x.png'),
          isNull);
      expect(parseCommunityPostImageRef('https://evil.example/a.png'), isNull);
      expect(parseCommunityPostImageRef(''), isNull);
    });
  });

  group('CommunityPostImagePath.forUpload', () {
    test('경로 첫 세그먼트 = uid, ref = 버킷 접두(§6.1)', () {
      final CommunityPostImagePath p = CommunityPostImagePath.forUpload(
        uid: 'u-77',
        image: validateCommunityPostImage(bytes: _png(), fileName: 'x.png'),
        objectId: 'fixed-id',
      );
      expect(p.objectPath, 'u-77/fixed-id-x.png');
      expect(p.ref, 'community-post-images/u-77/fixed-id-x.png');
    });
  });

  group('CommunityPostImageUrlResolver (TTL 3600·메모리 캐시)', () {
    test('TTL 3600 로 서명 + 만료 전 재사용(재서명 없음)', () async {
      final _FakeBackend backend = _FakeBackend();
      DateTime now = DateTime(2026, 7, 30, 12);
      final CommunityPostImageUrlResolver r = CommunityPostImageUrlResolver(
          backend: backend, now: () => now);
      final String? u1 =
          await r.resolve('community-post-images/u-1/a.png');
      expect(u1, isNotNull);
      expect(backend.lastTtl, kCommunityPostImageSignedUrlTtlSeconds);
      final String? u2 =
          await r.resolve('community-post-images/u-1/a.png');
      expect(u2, u1);
      expect(backend.signCalls, 1); // 캐시 히트.

      // 안전 마진 지나면 재서명.
      now = now.add(const Duration(seconds: 3600));
      await r.resolve('community-post-images/u-1/a.png');
      expect(backend.signCalls, 2);
    });

    test('레거시 signed URL 값도 path 추출 후 재서명(읽기 호환)', () async {
      final _FakeBackend backend = _FakeBackend();
      final CommunityPostImageUrlResolver r =
          CommunityPostImageUrlResolver(backend: backend);
      final String? u = await r.resolve(
          'https://old.supabase.co/storage/v1/object/sign/'
          'community-post-images/u-2/old.webp?token=x');
      expect(u, isNotNull);
      expect(backend.lastPath, 'u-2/old.webp');
    });

    test('파싱 불가 ref → null(서명 시도 없음 — 이미지 하나만 숨김)', () async {
      final _FakeBackend backend = _FakeBackend();
      final CommunityPostImageUrlResolver r =
          CommunityPostImageUrlResolver(backend: backend);
      expect(await r.resolve('garbage'), isNull);
      expect(backend.signCalls, 0);
    });
  });

  group('generateUuidV4', () {
    test('RFC 4122 v4 형식', () {
      final String id = generateUuidV4();
      expect(
          RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
              .hasMatch(id),
          isTrue,
          reason: id);
      expect(generateUuidV4(), isNot(id));
    });
  });
}
