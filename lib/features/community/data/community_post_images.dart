import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/errors/app_error.dart';

/// 커뮤니티 게시글 이미지 계약(앱 계약 v1.1 §5·§6.1).
///
/// - 정본 ref: `community-post-images/{uid}/{object}` (private bucket)
/// - 업로드: 최대 5장 · 장당 5MiB · JPEG/PNG/WebP/GIF · upsert=false
/// - 읽기: ref 를 표시 시점에 signed URL(TTL 3600초)로 해석, 메모리 캐시만
/// - 레거시 signed URL(`https://.../object/sign/community-post-images/...`)은
///   path 를 추출해 다시 서명(읽기 호환)
/// - 파싱 불가 ref 는 그 이미지 하나만 숨기고 구조화 로그를 남긴다
const String kCommunityPostImageBucket = 'community-post-images';
const int kCommunityPostImageMaxCount = 5;
const int kCommunityPostImageMaxBytes = 5 * 1024 * 1024; // 5 MiB
const int kCommunityPostImageSignedUrlTtlSeconds = 3600;

/// 확장자 → MIME(계약 허용 4종만).
const Map<String, String> kCommunityPostImageMimeByExt = <String, String>{
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
};

/// magic bytes 로 판별한 실제 이미지 형식(허용 4종 외 null).
String? sniffImageMime(Uint8List bytes) {
  if (bytes.length < 12) return null;
  // JPEG: FF D8 FF
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  // GIF: 'GIF87a' | 'GIF89a'
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return 'image/gif';
  }
  // WebP: 'RIFF' .... 'WEBP'
  if (bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

/// 업로드 대상 이미지 1장(로컬 검증 통과본).
class ValidatedPostImage {
  const ValidatedPostImage({
    required this.bytes,
    required this.contentType,
    required this.ext,
    required this.safeName,
  });

  final Uint8List bytes;
  final String contentType;
  final String ext;
  final String safeName;
}

/// 로컬 1차 검증(§6.1 — 확장자·MIME·magic bytes·크기). 실패는 AppError.
/// Storage bucket 제한(5MiB·MIME)은 서버 측 2차 검증으로 그대로 둔다.
ValidatedPostImage validateCommunityPostImage({
  required Uint8List bytes,
  required String fileName,
}) {
  final String lower = fileName.toLowerCase();
  final int dot = lower.lastIndexOf('.');
  final String ext = dot < 0 ? '' : lower.substring(dot + 1);
  final String? extMime = kCommunityPostImageMimeByExt[ext];
  if (extMime == null) {
    throw const AppError('JPG·PNG·WebP·GIF 이미지만 첨부할 수 있어요.');
  }
  final String? sniffed = sniffImageMime(bytes);
  if (sniffed == null || sniffed != extMime) {
    throw const AppError('이미지 형식을 확인하지 못했어요. 다른 이미지로 다시 시도해 주세요.');
  }
  if (bytes.lengthInBytes > kCommunityPostImageMaxBytes) {
    throw const AppError('이미지 한 장은 5MB 이하만 첨부할 수 있어요.');
  }
  // 경로 안전 이름: 영숫자·일부 구분자만 유지(한글 등은 치환) + 길이 제한.
  final String base = dot < 0 ? lower : lower.substring(0, dot);
  String safe = base.replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
  if (safe.length > 40) safe = safe.substring(0, 40);
  if (safe.isEmpty || safe.replaceAll('_', '').isEmpty) safe = 'image';
  return ValidatedPostImage(
    bytes: bytes,
    contentType: extMime,
    ext: ext == 'jpeg' ? 'jpg' : ext,
    safeName: safe,
  );
}

/// RFC 4122 v4 UUID(F4 멱등키·객체명용 — 외부 의존성 없이 생성).
String generateUuidV4({Random? random}) {
  final Random r = random ?? Random.secure();
  final List<int> b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${hex(0)}${hex(1)}${hex(2)}${hex(3)}-${hex(4)}${hex(5)}-'
      '${hex(6)}${hex(7)}-${hex(8)}${hex(9)}-'
      '${hex(10)}${hex(11)}${hex(12)}${hex(13)}${hex(14)}${hex(15)}';
}

/// 업로드 객체 경로(`{uid}/{uuid}-{safe}.{ext}`)와 DB ref 를 만든다.
class CommunityPostImagePath {
  const CommunityPostImagePath({required this.objectPath, required this.ref});

  /// bucket 내부 경로(첫 세그먼트 = 본인 uid — Storage RLS 요건).
  final String objectPath;

  /// DB 저장 정본 ref(`community-post-images/{objectPath}`).
  final String ref;

  factory CommunityPostImagePath.forUpload({
    required String uid,
    required ValidatedPostImage image,
    String? objectId,
  }) {
    final String id = objectId ?? generateUuidV4();
    final String objectPath = '$uid/$id-${image.safeName}.${image.ext}';
    return CommunityPostImagePath(
      objectPath: objectPath,
      ref: '$kCommunityPostImageBucket/$objectPath',
    );
  }
}

/// ref → bucket 내부 objectPath 해석. 지원 형태:
/// ① 정본 `community-post-images/{uid}/{object}`
/// ② 레거시 signed/public URL — path 에 `/community-post-images/` 가 포함된
///    절대 http(s) URL(만료 토큰 무시, path 만 추출해 재서명)
/// 그 외(타 버킷·경로조작·불량)는 null — 호출부는 그 이미지 하나만 숨긴다.
String? parseCommunityPostImageRef(String raw) {
  final String value = raw.trim();
  if (value.isEmpty) return null;

  String? candidate;
  if (value.startsWith('$kCommunityPostImageBucket/')) {
    candidate = value.substring(kCommunityPostImageBucket.length + 1);
  } else if (value.startsWith('http://') || value.startsWith('https://')) {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null) return null;
    const String marker = '/$kCommunityPostImageBucket/';
    final int idx = uri.path.indexOf(marker);
    if (idx < 0) return null;
    candidate = Uri.decodeComponent(uri.path.substring(idx + marker.length));
  } else {
    return null;
  }

  if (candidate.isEmpty) return null;
  final List<String> segments = candidate.split('/');
  // 최소 {uid}/{object}. 경로조작·빈 세그먼트 거부.
  if (segments.length < 2 ||
      segments.any((String s) => s.isEmpty || s == '.' || s == '..')) {
    return null;
  }
  if (candidate.contains('\\') || candidate.contains('\n')) return null;
  return candidate;
}

/// Storage 접근 seam(테스트 주입용).
abstract class CommunityPostImageBackend {
  /// upsert=false 업로드(§6.1). 실패는 예외.
  Future<void> uploadObject({
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  });

  /// 이번 요청의 신규 객체 보상 삭제(§6.3 — Storage 한정). 실패는 예외.
  Future<void> removeObjects(List<String> objectPaths);

  /// 표시 시점 signed URL 발급(TTL 3600 — §5).
  Future<String> createSignedUrl(String objectPath, int ttlSeconds);
}

/// 운영 구현 — Supabase Storage `community-post-images`(private bucket).
class SupabaseCommunityPostImageBackend implements CommunityPostImageBackend {
  const SupabaseCommunityPostImageBackend(this._client);

  final SupabaseClient _client;

  @override
  Future<void> uploadObject({
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    await _client.storage.from(kCommunityPostImageBucket).uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
  }

  @override
  Future<void> removeObjects(List<String> objectPaths) async {
    if (objectPaths.isEmpty) return;
    await _client.storage.from(kCommunityPostImageBucket).remove(objectPaths);
  }

  @override
  Future<String> createSignedUrl(String objectPath, int ttlSeconds) {
    return _client.storage
        .from(kCommunityPostImageBucket)
        .createSignedUrl(objectPath, ttlSeconds);
  }
}

/// 게시글 이미지 signed URL 해석기 — 메모리 캐시만 사용(§5: DB·로컬 영구
/// 저장 금지). 만료·서명 실패 시 해당 이미지만 재서명하고 글 본문 표시는
/// 막지 않는다(호출부 계약).
class CommunityPostImageUrlResolver {
  CommunityPostImageUrlResolver({
    required CommunityPostImageBackend backend,
    DateTime Function()? now,
  })  : _backend = backend,
        _now = now ?? DateTime.now;

  final CommunityPostImageBackend _backend;
  final DateTime Function() _now;

  static const int _safetyMarginSeconds = 60;

  final Map<String, ({String url, DateTime expiresAt})> _cache =
      <String, ({String url, DateTime expiresAt})>{};

  /// ref → 표시용 URL. 파싱 불가 ref 는 null(그 이미지 하나만 숨김 + 구조화 로그).
  Future<String?> resolve(String ref) async {
    final String? objectPath = parseCommunityPostImageRef(ref);
    if (objectPath == null) {
      // 구조화 로그 — URL·토큰 원문은 남기지 않는다(비민감 사실만).
      debugPrint('community_post_image_ref_unparseable len=${ref.length}');
      return null;
    }
    final ({String url, DateTime expiresAt})? hit = _cache[objectPath];
    if (hit != null && _now().isBefore(hit.expiresAt)) return hit.url;
    final String url = await _backend.createSignedUrl(
        objectPath, kCommunityPostImageSignedUrlTtlSeconds);
    _cache[objectPath] = (
      url: url,
      expiresAt: _now().add(const Duration(
          seconds: kCommunityPostImageSignedUrlTtlSeconds -
              _safetyMarginSeconds)),
    );
    return url;
  }

  /// 특정 ref 재서명(만료·로드 실패 시 호출부가 개별 재시도).
  void invalidate(String ref) {
    final String? objectPath = parseCommunityPostImageRef(ref);
    if (objectPath != null) _cache.remove(objectPath);
  }
}
