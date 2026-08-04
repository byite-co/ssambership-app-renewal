import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/scan/picked_image.dart';
import 'package:ssambership_app/features/community/data/board_post_media_gateway.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// 게시글 이미지 Storage 계약(버킷 community-post-images — 스테이징 실측).
///
/// 정본 ref 형식 `community-post-images/{uid}/{object}` · 5MB · 4종 MIME ·
/// 최대 5장. Storage 를 실제로 호출하지 않는다(전부 주입 seam).

const String _uid = 'auth-uid-0001';

PickedImage _img({
  String name = 'photo.png',
  String mime = 'image/png',
  int size = 1024,
}) =>
    PickedImage(
      bytes: Uint8List(size),
      fileName: name,
      mimeType: mime,
    );

class _RecordingBackend implements CommunityPostMediaBackend {
  _RecordingBackend({this.uploadError, this.removeError});

  final Object? uploadError;
  final Object? removeError;

  final List<String> uploadedPaths = <String>[];
  final List<String> uploadedMimes = <String>[];
  final List<List<String>> removeCalls = <List<String>>[];

  @override
  Future<void> uploadObject({
    required String path,
    required List<int> bytes,
    required String mimeType,
  }) async {
    if (uploadError != null) throw uploadError!;
    uploadedPaths.add(path);
    uploadedMimes.add(mimeType);
  }

  @override
  Future<void> removeObjects(List<String> paths) async {
    removeCalls.add(List<String>.of(paths));
    if (removeError != null) throw removeError!;
  }
}

void main() {
  group('정본 ref 형식 — 서버 계약(community_image_refs_validate)과 동일', () {
    test('버킷·경로 상수가 서버 실측과 일치한다', () {
      expect(kCommunityPostImagesBucket, 'community-post-images');
      expect(kCommunityPostImageMaxBytes, 5242880);
      expect(kCommunityPostImageMaxCount, 5);
      expect(kCommunityPostImageAllowedMimeTypes,
          <String>{'image/jpeg', 'image/png', 'image/webp', 'image/gif'});
    });

    test('object 경로는 {uid}/{ts}_{safeName} — 첫 세그먼트가 소유자', () {
      final String path = buildCommunityPostImageObjectPath(
          uid: _uid, fileName: '내 사진 (1).png', timestamp: 1234);
      expect(path.startsWith('$_uid/'), isTrue);
      expect(path, '$_uid/1234_______1_.png'); // 경로 위험 문자는 _ 로 치환
    });

    test('ref ↔ object 경로 왕복이 정확하다', () {
      const String objectPath = '$_uid/1234_a.png';
      final String ref = communityPostImageRef(objectPath);
      expect(ref, 'community-post-images/$objectPath');
      expect(communityPostImageObjectPath(ref), objectPath);
    });

    test('계약 밖 ref 는 파싱을 거부한다(null)', () {
      expect(communityPostImageObjectPath('other-bucket/$_uid/a.png'), isNull);
      expect(communityPostImageObjectPath('community-post-images/'), isNull);
      // 접두사 뒤 최소 2세그먼트({uid}/{object}) — 아니면 계약 밖.
      expect(communityPostImageObjectPath('community-post-images/only-uid'),
          isNull);
      expect(communityPostImageObjectPath('community-post-images/$_uid/'),
          isNull);
      expect(communityPostImageObjectPath('http://x/community-post-images/a/b'),
          isNull);
    });
  });

  group('선택 이미지 사전 검증(버킷 상한)', () {
    test('허용 4종 MIME·5MB 이하만 통과한다', () {
      for (final String mime in <String>[
        'image/jpeg',
        'image/png',
        'image/webp',
        'image/gif',
      ]) {
        expect(validateCommunityPostImage(_img(mime: mime)), isNull,
            reason: mime);
      }
      expect(validateCommunityPostImage(_img(mime: 'image/heic')),
          'JPG·PNG·WEBP·GIF 이미지만 첨부할 수 있어요.');
      expect(validateCommunityPostImage(_img(mime: 'application/pdf')),
          isNotNull);
      expect(
          validateCommunityPostImage(
              _img(size: kCommunityPostImageMaxBytes + 1)),
          '이미지는 한 장당 5MB까지 첨부할 수 있어요.');
      expect(validateCommunityPostImage(_img(size: 0)), isNotNull);
    });
  });

  group('업로드 — 정본 경로·fail-closed', () {
    test('성공 시 정본 ref(버킷 접두사 포함)를 돌려준다', () async {
      final _RecordingBackend backend = _RecordingBackend();
      final String ref = await uploadCommunityPostImage(
        authUserId: _uid,
        backend: backend,
        image: _img(),
        timestamp: 1234,
      );
      expect(backend.uploadedPaths.single, '$_uid/1234_photo.png');
      expect(backend.uploadedMimes.single, 'image/png');
      expect(ref, 'community-post-images/$_uid/1234_photo.png');
    });

    test('미로그인·검증 실패는 업로드를 시작하지 않는다', () async {
      final _RecordingBackend backend = _RecordingBackend();
      await expectLater(
          uploadCommunityPostImage(
              authUserId: null,
              backend: backend,
              image: _img(),
              timestamp: 1),
          throwsA(isA<AppError>()));
      await expectLater(
          uploadCommunityPostImage(
              authUserId: _uid,
              backend: backend,
              image: _img(mime: 'video/mp4'),
              timestamp: 1),
          throwsA(isA<AppError>()));
      expect(backend.uploadedPaths, isEmpty);
    });

    test('Storage 실패는 원문 경로 없는 한글 문구로 감싼다', () async {
      final _RecordingBackend backend =
          _RecordingBackend(uploadError: Exception('bucket policy denied'));
      Object? caught;
      try {
        await uploadCommunityPostImage(
            authUserId: _uid, backend: backend, image: _img(), timestamp: 1);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<AppError>());
      final String msg = (caught as AppError).userMessage;
      expect(msg, '이미지를 올리지 못했어요. 잠시 후 다시 시도해 주세요.');
      expect(msg.contains(_uid), isFalse);
      expect(msg.contains('community-post-images'), isFalse);
    });
  });

  group('제거 이미지 정리 — RPC 성공 후 best-effort', () {
    test('정본 ref 만 object 경로로 바꿔 삭제한다(계약 밖 ref 는 건너뜀)', () async {
      final _RecordingBackend backend = _RecordingBackend();
      await removeCommunityPostImageRefs(
        backend: backend,
        refs: <String>[
          'community-post-images/$_uid/1_a.png',
          'other-bucket/$_uid/x.png', // 계약 밖 — 건너뜀
          'community-post-images/$_uid/2_b.jpg',
        ],
      );
      expect(backend.removeCalls.single,
          <String>['$_uid/1_a.png', '$_uid/2_b.jpg']);
    });

    test('삭제 대상이 없으면 Storage 를 호출하지 않는다', () async {
      final _RecordingBackend backend = _RecordingBackend();
      await removeCommunityPostImageRefs(
          backend: backend, refs: const <String>[]);
      await removeCommunityPostImageRefs(
          backend: backend, refs: const <String>['other-bucket/a/b.png']);
      expect(backend.removeCalls, isEmpty);
    });

    test('삭제 실패는 조용히 삼킨다(수정 성공을 뒤집지 않는다)', () async {
      final _RecordingBackend backend =
          _RecordingBackend(removeError: Exception('storage down'));
      await removeCommunityPostImageRefs(
          backend: backend,
          refs: const <String>['community-post-images/$_uid/1_a.png']);
      expect(backend.removeCalls, hasLength(1)); // 시도는 했다
    });
  });
}
