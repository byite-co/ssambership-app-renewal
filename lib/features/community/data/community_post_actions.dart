import 'package:flutter/foundation.dart';

import '../../../shared/errors/app_error.dart';
import 'community_post_envelope.dart';
import 'community_post_images.dart';

/// 커뮤니티 게시글 F4/F5/F6 오케스트레이터(앱 계약 v1.1 §3.3·§6.3·§6.6).
///
/// 순수 함수 + 주입 포트로 구성 — 단위 테스트가 replay-first 순서(재호출 전
/// Storage DELETE 0회)·보상 4분기·멱등키 보존을 호출 횟수 단위로 고정한다.
///
/// ★ DB 게시글 hard DELETE 보상은 존재하지 않는다(HD-1 — 구
///   `deleteOwnPostForCompensation` 폐기). 보상 삭제는 이번 요청이 새로 올린
///   Storage 객체 한정이며, 그마저도 '확정 실패'가 판정된 분기에서만 수행한다.

/// F4 성공 결과.
class CreatedBoardPostV1 {
  const CreatedBoardPostV1({
    required this.postId,
    required this.idempotentReplay,
  });

  final String postId;

  /// true = 멱등 재생(기존 커밋 행 확인 — 정상 성공).
  final bool idempotentReplay;
}

/// F5 성공 결과.
class UpdatedBoardPostV1 {
  const UpdatedBoardPostV1({
    required this.postId,
    required this.updatedAt,
    required this.removedImageRefs,
  });

  final String postId;
  final String? updatedAt;
  final List<String> removedImageRefs;
}

/// F6 성공 결과(already_deleted=true 도 정상 성공 — §7.4).
class SoftDeletedBoardPostV1 {
  const SoftDeletedBoardPostV1({
    required this.postId,
    required this.alreadyDeleted,
  });

  final String postId;
  final bool alreadyDeleted;
}

/// 응답 불명확(성공도 확정 실패도 아님) — 같은 멱등키로 재시도해야 한다.
/// 호출부(화면)는 이 오류를 받으면 **멱등키를 새로 만들지 않고 유지**한다.
class CommunityCreateUnclear extends AppError {
  const CommunityCreateUnclear({Object? cause})
      : super('등록 결과를 확인하지 못했어요. 네트워크 확인 후 다시 등록을 눌러 주세요.',
            cause: cause);
}

/// api_app_v1 wrapper 호출 seam(named arguments — 계약 §3.3 호출 규약).
typedef CommunityPostRpcCall = Future<Object?> Function(
    Map<String, dynamic> namedParams);

/// F4 생성 — 업로드 → finalize → 보상 4분기(§6.3).
///
/// 분기 규약:
/// ① 업로드 자체 실패 → 이번 요청 신규 객체만 즉시 삭제 후 실패 전파.
/// ② F4 확정 실패(ok:false envelope) → 신규 객체 삭제 후 [CommunityWriteRejected].
/// ③ 응답 불명확(예외·envelope 아님·ok 필드 없음) → **Storage DELETE 0회**,
///    동일 멱등키로 F4 1회 재호출(replay-first — 재호출 자체가 기존 행 조회를
///    겸한다. 별도 조회 RPC 없음). 재호출도 불명확이면 객체를 보존한 채
///    [CommunityCreateUnclear] — 호출부가 같은 키로 다시 시도한다.
/// ④ 신규 성공 또는 `idempotent_replay:true` → 객체 유지.
Future<CreatedBoardPostV1> createBoardPostV1({
  required String uid,
  required String title,
  required String body,
  required String category,
  required String idempotencyKey,
  required List<ValidatedPostImage> images,
  required CommunityPostImageBackend storage,
  required CommunityPostRpcCall callCreate,
  String status = 'published',
}) async {
  if (images.length > kCommunityPostImageMaxCount) {
    throw const AppError('이미지는 최대 5장까지 첨부할 수 있어요.');
  }

  // 1) 업로드(upsert=false). 실패 시 이번 요청 신규 객체만 즉시 보상 삭제(①).
  final List<String> uploadedPaths = <String>[];
  final List<String> refs = <String>[];
  try {
    for (final ValidatedPostImage image in images) {
      final CommunityPostImagePath path =
          CommunityPostImagePath.forUpload(uid: uid, image: image);
      await storage.uploadObject(
        objectPath: path.objectPath,
        bytes: image.bytes,
        contentType: image.contentType,
      );
      uploadedPaths.add(path.objectPath);
      refs.add(path.ref);
    }
  } catch (e) {
    await _compensateNewObjects(storage, uploadedPaths);
    throw AppError('이미지 업로드에 실패했어요. 잠시 후 다시 시도해 주세요.', cause: e);
  }

  final Map<String, dynamic> params = <String, dynamic>{
    'p_title': title,
    'p_body': body,
    'p_category': category,
    'p_idempotency_key': idempotencyKey,
    'p_image_refs': refs,
    'p_status': status,
  };

  // 2) finalize 1차 호출.
  final _F4Outcome first = await _callF4(callCreate, params);
  switch (first.kind) {
    case _F4Kind.ok:
      return first.created!; // ④ 성공 — 객체 유지.
    case _F4Kind.rejected:
      // ② 확정 실패(도메인 거부 = 트랜잭션 rollback) — 신규 객체 보상 삭제.
      await _compensateNewObjects(storage, uploadedPaths);
      throw CommunityWriteRejected(first.code!);
    case _F4Kind.unclear:
      break; // ③ 로 계속.
  }

  // 3) ③ 응답 불명확 — 삭제 없이 동일 멱등키 재호출(replay-first).
  final _F4Outcome retry = await _callF4(callCreate, params);
  switch (retry.kind) {
    case _F4Kind.ok:
      return retry.created!; // 커밋돼 있었음(재생) 또는 이번에 성공 — 객체 유지.
    case _F4Kind.rejected:
      // replay-first 가 기존 행 없음 + 확정 실패 envelope 로 종결 — 미커밋 확인.
      await _compensateNewObjects(storage, uploadedPaths);
      throw CommunityWriteRejected(retry.code!);
    case _F4Kind.unclear:
      // 여전히 불명확 — 객체 보존, 같은 키로 추후 재시도(새 키 금지).
      throw CommunityCreateUnclear(cause: retry.cause);
  }
}

enum _F4Kind { ok, rejected, unclear }

class _F4Outcome {
  const _F4Outcome.ok(this.created)
      : kind = _F4Kind.ok,
        code = null,
        cause = null;
  const _F4Outcome.rejected(this.code)
      : kind = _F4Kind.rejected,
        created = null,
        cause = null;
  const _F4Outcome.unclear(this.cause)
      : kind = _F4Kind.unclear,
        created = null,
        code = null;

  final _F4Kind kind;
  final CreatedBoardPostV1? created;
  final String? code;
  final Object? cause;
}

Future<_F4Outcome> _callF4(
    CommunityPostRpcCall callCreate, Map<String, dynamic> params) async {
  final Object? data;
  try {
    data = await callCreate(params);
  } catch (e) {
    // 연결 실패·timeout·예상 밖 예외 전파 — 성공도 확정 실패도 아니다(§3.3).
    return _F4Outcome.unclear(e);
  }
  final CommunityWriteEnvelope? env = CommunityWriteEnvelope.tryParse(data);
  if (env == null) {
    // `ok` 없는 응답을 성공으로 간주하지 않는다(§3.3) — 불명확으로 분류.
    return const _F4Outcome.unclear(null);
  }
  if (!env.ok) return _F4Outcome.rejected(env.code!);
  final Object? postId = env.fields['post_id'];
  if (postId is! String || postId.isEmpty) {
    return const _F4Outcome.unclear(null);
  }
  return _F4Outcome.ok(CreatedBoardPostV1(
    postId: postId,
    idempotentReplay: env.idempotentReplay,
  ));
}

/// 이번 요청 신규 Storage 객체 보상 삭제(best-effort). 실패해도 원 결과를
/// 뒤집지 않고 orphan 정리 대상으로 구조화 로그만 남긴다(§6.3).
Future<void> _compensateNewObjects(
    CommunityPostImageBackend storage, List<String> objectPaths) async {
  if (objectPaths.isEmpty) return;
  try {
    await storage.removeObjects(objectPaths);
  } catch (_) {
    debugPrint(
        'community_post_image_orphan count=${objectPaths.length} (cleanup queue)');
  }
}

/// F5 수정 — 실제 조회한 updated_at 을 `p_expected_updated_at` 으로 보낸다
/// (조회값이 NULL 이면 NULL 그대로 — 서버가 IS DISTINCT FROM 으로 정합 비교).
/// `UPDATE_CONFLICT` 는 자동 덮어쓰기하지 않고 그대로 전파한다(§7.3).
/// 성공 응답의 removed_image_refs 만 commit 이후 best-effort Storage 삭제하며,
/// 그 삭제 실패가 수정 성공을 뒤집지 않는다.
Future<UpdatedBoardPostV1> updateBoardPostV1({
  required String postId,
  required String title,
  required String body,
  required String category,
  required String? expectedUpdatedAt,
  required List<String> imageRefs,
  required CommunityPostImageBackend storage,
  required CommunityPostRpcCall callUpdate,
  String status = 'published',
}) async {
  final Object? data = await callUpdate(<String, dynamic>{
    'p_post_id': postId,
    'p_title': title,
    'p_body': body,
    'p_category': category,
    'p_expected_updated_at': expectedUpdatedAt,
    'p_image_refs': imageRefs,
    'p_status': status,
  });
  final CommunityWriteEnvelope? env = CommunityWriteEnvelope.tryParse(data);
  if (env == null) {
    throw const AppError('수정 결과를 확인하지 못했어요. 새로고침 후 다시 시도해 주세요.');
  }
  if (!env.ok) throw CommunityWriteRejected(env.code!);

  final List<String> removed = <String>[
    for (final Object? r in (env.fields['removed_image_refs'] as List?) ??
        const <Object?>[])
      if (r is String) r,
  ];
  if (removed.isNotEmpty) {
    // commit 이후 구객체 best-effort 삭제 — 실패는 성공을 뒤집지 않는다.
    final List<String> paths = <String>[
      for (final String ref in removed)
        if (parseCommunityPostImageRef(ref) != null)
          parseCommunityPostImageRef(ref)!,
    ];
    await _compensateNewObjects(storage, paths);
  }
  return UpdatedBoardPostV1(
    postId: (env.fields['post_id'] as String?) ?? postId,
    updatedAt: env.fields['updated_at'] as String?,
    removedImageRefs: removed,
  );
}

/// F6 soft-delete — hard delete 금지. `already_deleted:true` 는 정상 성공.
/// 이미지 객체 즉시 purge 는 하지 않는다(감사 보존 — §7.4).
Future<SoftDeletedBoardPostV1> softDeleteBoardPostV1({
  required String postId,
  required CommunityPostRpcCall callSoftDelete,
}) async {
  final Object? data =
      await callSoftDelete(<String, dynamic>{'p_post_id': postId});
  final CommunityWriteEnvelope? env = CommunityWriteEnvelope.tryParse(data);
  if (env == null) {
    throw const AppError('삭제 결과를 확인하지 못했어요. 새로고침 후 다시 확인해 주세요.');
  }
  if (!env.ok) throw CommunityWriteRejected(env.code!);
  return SoftDeletedBoardPostV1(
    postId: (env.fields['post_id'] as String?) ?? postId,
    alreadyDeleted: env.fields['already_deleted'] == true,
  );
}
