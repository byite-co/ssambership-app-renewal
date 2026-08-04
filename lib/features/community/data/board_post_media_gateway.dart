import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/scan/picked_image.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';

/// 게시판 글 이미지 — 서버 정본 Storage 계약(스테이징 실측, 2026-08-02).
///
/// 버킷 `community-post-images`: private · file_size_limit=5242880(5MB) ·
/// allowed_mime_types = JPEG/PNG/WEBP/GIF. Storage RLS 는 경로 첫 세그먼트가
/// 본인 uid 인 객체만 INSERT/DELETE 를 허용한다(cpi_auth_insert_own /
/// cpi_auth_delete_own).
///
/// RPC 로 보내는 정본 ref 형식(§14.1 — `core_private.community_image_refs_validate`):
///   `community-post-images/{uid}/{object}`
/// 서버는 ① 버킷 접두사 ② 첫 세그먼트=소유자 ③ storage.objects 실존
/// ④ 소유자·MIME·5MB 를 검사한다(IMAGE_* 코드로 거부). 앱이 임의 bucket·path
/// 규칙을 만들지 않는다 — 이 파일의 빌더/파서만 사용한다.
///
/// 제거된 이미지의 실제 Storage 삭제는 **DB 반영(update RPC 성공) 후**
/// 클라이언트가 서버가 돌려준 `removed_image_refs` 기준으로 best-effort 수행
/// 한다(§14.4). DB 성공 전에 기존 객체를 지우지 않는다.
const String kCommunityPostImagesBucket = 'community-post-images';

/// 버킷 실측 상한(5242880 bytes).
const int kCommunityPostImageMaxBytes = 5 * 1024 * 1024;

/// 버킷 실측 허용 MIME 4종.
const Set<String> kCommunityPostImageAllowedMimeTypes = <String>{
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
};

/// 서버 계약(community_image_refs_validate) 최대 장수.
const int kCommunityPostImageMaxCount = 5;

/// Storage object 경로 조립(순수 함수 — 테스트 가능).
/// RLS·서버 검증 모두 첫 세그먼트=본인 uid 를 강제한다: '{uid}/{ts}_{safeName}'.
String buildCommunityPostImageObjectPath({
  required String uid,
  required String fileName,
  required int timestamp,
}) {
  final String safeName = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
  return '$uid/${timestamp}_$safeName';
}

/// object 경로 → RPC 정본 ref(버킷 접두사 포함).
String communityPostImageRef(String objectPath) =>
    '$kCommunityPostImagesBucket/$objectPath';

/// 정본 ref → Storage object 경로. 계약 형식이 아니면 null(삭제 등에서 건너뜀).
/// 형식: `community-post-images/{uid}/{object}` — 접두사 뒤 최소 2세그먼트.
String? communityPostImageObjectPath(String ref) {
  const String prefix = '$kCommunityPostImagesBucket/';
  if (!ref.startsWith(prefix)) return null;
  final String path = ref.substring(prefix.length);
  final int slash = path.indexOf('/');
  if (slash <= 0 || slash == path.length - 1) return null;
  return path;
}

/// 선택 이미지 사전 검증(버킷 상한 안에서만 허용 — 서버보다 좁게는 허용,
/// 넓게는 금지). 통과하면 null, 아니면 사용자에게 보여줄 한글 사유.
String? validateCommunityPostImage(PickedImage image) {
  if (image.bytes.isEmpty) return '빈 파일은 첨부할 수 없어요.';
  if (image.sizeBytes > kCommunityPostImageMaxBytes) {
    return '이미지는 한 장당 5MB까지 첨부할 수 있어요.';
  }
  if (!kCommunityPostImageAllowedMimeTypes
      .contains(image.mimeType.toLowerCase())) {
    return 'JPG·PNG·WEBP·GIF 이미지만 첨부할 수 있어요.';
  }
  return null;
}

/// 게시글 이미지 Storage 접근 포트(테스트 fake 주입 지점).
abstract class CommunityPostMediaBackend {
  /// Storage 업로드(upsert 금지 — 동일 경로 재업로드는 실패해야 정상).
  Future<void> uploadObject({
    required String path,
    required List<int> bytes,
    required String mimeType,
  });

  /// 본인 소유 객체 삭제(RLS cpi_auth_delete_own 가 그 이상을 서버에서 거부).
  Future<void> removeObjects(List<String> paths);
}

/// 운영 기본 구현(Supabase Storage).
class SupabaseCommunityPostMediaBackend implements CommunityPostMediaBackend {
  const SupabaseCommunityPostMediaBackend();

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) throw const AppError('백엔드에 연결되어 있지 않아요.');
    return c;
  }

  @override
  Future<void> uploadObject({
    required String path,
    required List<int> bytes,
    required String mimeType,
  }) async {
    await _client.storage.from(kCommunityPostImagesBucket).uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
  }

  @override
  Future<void> removeObjects(List<String> paths) async {
    if (paths.isEmpty) return;
    await _client.storage.from(kCommunityPostImagesBucket).remove(paths);
  }
}

/// 이미지 1장 업로드 → 정본 ref 반환. 검증 실패·미로그인은 업로드를 시작하지
/// 않는다(fail-closed). Storage 원문 경로·서버 원문은 사용자 문구에 싣지 않는다.
Future<String> uploadCommunityPostImage({
  required String? authUserId,
  required CommunityPostMediaBackend backend,
  required PickedImage image,
  required int timestamp,
}) async {
  if (authUserId == null || authUserId.isEmpty) {
    throw const AppError('로그인이 필요해요.');
  }
  final String? invalid = validateCommunityPostImage(image);
  if (invalid != null) throw AppError(invalid);
  final String objectPath = buildCommunityPostImageObjectPath(
    uid: authUserId,
    fileName: image.fileName,
    timestamp: timestamp,
  );
  try {
    await backend.uploadObject(
      path: objectPath,
      bytes: image.bytes,
      mimeType: image.mimeType,
    );
  } catch (e) {
    throw AppError('이미지를 올리지 못했어요. 잠시 후 다시 시도해 주세요.', cause: e);
  }
  return communityPostImageRef(objectPath);
}

/// 서버가 돌려준 `removed_image_refs` 의 실제 Storage 삭제(best-effort §14.4).
///
/// **update RPC 성공 후에만 호출한다.** 계약 형식이 아닌 ref 는 건너뛰고,
/// 삭제 실패는 조용히 무시한다(글 수정 자체는 이미 성공 — 고아 객체는 본인
/// 소유 private 객체라 노출되지 않는다).
Future<void> removeCommunityPostImageRefs({
  required CommunityPostMediaBackend backend,
  required List<String> refs,
}) async {
  final List<String> paths = <String>[
    for (final String ref in refs)
      if (communityPostImageObjectPath(ref) != null)
        communityPostImageObjectPath(ref)!,
  ];
  if (paths.isEmpty) return;
  try {
    await backend.removeObjects(paths);
  } catch (_) {
    // best-effort — 수정 성공을 삭제 실패로 뒤집지 않는다.
  }
}
