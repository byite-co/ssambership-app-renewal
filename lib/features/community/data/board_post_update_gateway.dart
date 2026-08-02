import '../../../shared/errors/app_error.dart';
import 'board_post_create_gateway.dart'
    show BoardPostCreateRpc, BoardPostFetcher, kBoardPostCreateStatus;
import 'community_models.dart';
import 'community_post_error_mapper.dart';

/// 게시판 글 수정 = 서버 RPC 단일 경로(작성 S3-D 와 동일 원칙).
///
/// 운영 DB 의 `public.community_posts` 는 authenticated 에게 SELECT 만 준다 —
/// 직접 UPDATE 권한도 policy 도 없다. 수정 권한 판정(소유·역할·계정 상태)·
/// 본문 정규화·연락처 마스킹·이미지 ref 검증은 전부 서버 계약 함수가 수행하고,
/// 앱은 그 결과를 그대로 따른다(서버 소유권 검사가 보안 정본 — 앱 UI 게이트는
/// 편의일 뿐이다).
///
/// 정본 계약(스테이징 실측, 2026-08-02):
///   api_app_v1.community_post_update(
///     p_post_id uuid, p_title text, p_body text, p_category text,
///     p_expected_updated_at timestamptz, p_image_refs text[], p_status text)
///   returns jsonb
///
/// 반환은 예외가 아니라 봉투다 — `{ok: bool, ...}` (+wrapper 의 contract_version:1).
///   성공: {ok:true, post_id, updated_at, removed_image_refs, contract_version:1}
///   실패: {ok:false, code:'POST_NOT_FOUND_OR_NOT_OWNED'|'UPDATE_CONFLICT'|...,
///          contract_version:1}
/// 계약 밖 응답은 **성공으로 처리하지 않는다**(fail-closed). 서버 원문·SQL·
/// UUID·Storage 경로는 어떤 경로로도 화면에 노출하지 않는다.
///
/// 낙관적 충돌: `p_expected_updated_at` 은 수정 시작 시점에 읽은 행의
/// `updated_at` **원문 문자열 그대로** 보낸다(재직렬화 금지 — 서버가
/// IS DISTINCT FROM 으로 exact 비교, 불일치 시 UPDATE_CONFLICT).
const String kBoardPostUpdateFunction = 'community_post_update';

/// 성공 봉투 파싱 결과.
class BoardPostUpdateResult {
  const BoardPostUpdateResult({
    required this.postId,
    required this.updatedAt,
    required this.removedImageRefs,
  });

  /// 서버가 확정한 글 ID(비민감 식별자 — 화면에 노출하지 않는다).
  final String postId;

  /// 서버가 확정한 새 updated_at 원문(다음 수정의 expected 값).
  final String updatedAt;

  /// 이번 수정으로 글에서 빠진 기존 이미지 ref — **RPC 성공 후에만** 클라이언트가
  /// best-effort 삭제한다(§14.4).
  final List<String> removedImageRefs;
}

/// 계약 밖 응답 공통 문구 — 코드·원문을 싣지 않는다.
const AppError kBoardPostUpdateMalformed =
    AppError('글을 수정하지 못했어요. 잠시 후 다시 시도해 주세요.');

/// 서버가 글은 고쳤는데 앱이 그 행을 확인하지 못한 경우(수정 자체는 반영됨).
const AppError kBoardPostUpdatedButUnverified =
    AppError('글은 수정됐지만 화면을 갱신하지 못했어요. 목록을 새로고침해 확인해 주세요.');

/// 서버 오류 코드 → 사용자용 한글 문구. 수정 전용 코드를 먼저 처리하고,
/// 나머지는 작성·수정 공용 매퍼로 위임한다. 미지의 코드는 공통 문구(fail-closed).
AppError boardPostUpdateError(Object? code) {
  if (code is String) {
    switch (code) {
      // 비존재·타인 글·삭제 글 동일 코드(서버가 존재 여부를 구분해 주지 않는다).
      case 'POST_NOT_FOUND_OR_NOT_OWNED':
        return const AppError('글이 없거나 수정 권한이 없어요. 새로고침 후 다시 확인해 주세요.');
      // 낙관적 충돌 — 수정 시작 이후 다른 곳에서 글이 바뀌었다.
      case 'UPDATE_CONFLICT':
        return const AppError('다른 곳에서 글이 수정됐어요. 새로고침 후 다시 시도해 주세요.');
    }
  }
  return communityPostWriteContractError(code) ?? kBoardPostUpdateMalformed;
}

/// RPC params — 키 이름·개수가 서버 signature 와 정확히 일치해야 한다
/// (PostgREST 는 이름으로 함수를 해석한다 — 하나라도 다르면 404 PGRST202).
Map<String, dynamic> buildBoardPostUpdateParams({
  required String postId,
  required String title,
  required String body,
  required String category,
  required String expectedUpdatedAt,
  required List<String> imageRefs,
}) {
  return <String, dynamic>{
    'p_post_id': postId,
    'p_title': title,
    'p_body': body,
    'p_category': category,
    'p_expected_updated_at': expectedUpdatedAt,
    'p_image_refs': imageRefs,
    'p_status': kBoardPostCreateStatus,
  };
}

/// jsonb 봉투 파싱 — 성공만 통과시키고 나머지는 전부 throw.
///
/// **성공 봉투는 strict 검증한다** — 성공 판정은 파괴적 후속 동작(제거된
/// 기존 이미지의 Storage 삭제)의 근거이므로, 정본 필드가 하나라도 빠지거나
/// 형이 다르면 성공으로 처리하지 않는다(fail-closed):
///   ok=true · post_id 비어있지 않은 문자열 · updated_at 비어있지 않은 문자열 ·
///   removed_image_refs **필수** List<String>(빈 배열 정상, null·비목록·혼합
///   타입 거부) · contract_version **정수 1**.
///
/// 공용 규칙(작성·수정 동일): **실패 봉투는 contract_version 을 게이트하지
/// 않는다** — 실패에서 정본은 `code` 매핑(사용자 안내)이고, 버전까지
/// 게이트하면 실제 오류 코드의 안내가 공통 문구로 가려질 뿐 안전성이 늘지
/// 않는다. 성공만 strict 한 이유는 성공이 데이터(삭제 목록·충돌 토큰)를
/// 신뢰해 행동하는 유일한 분기이기 때문이다. (create 봉투도 같은 규칙 —
/// 실패는 code 매핑, 성공은 행동 근거 필드(post_id) 검증. create 성공에는
/// 삭제 같은 파괴적 후속 동작이 없어 PR #38 동결 검증 범위를 유지한다.)
BoardPostUpdateResult parseBoardPostUpdateEnvelope(Object? raw) {
  if (raw is! Map) throw kBoardPostUpdateMalformed;
  final Object? ok = raw['ok'];
  if (ok is! bool) throw kBoardPostUpdateMalformed;
  if (!ok) throw boardPostUpdateError(raw['code']);
  final Object? version = raw['contract_version'];
  if (version is! int || version != 1) throw kBoardPostUpdateMalformed;
  final Object? postId = raw['post_id'];
  if (postId is! String || postId.trim().isEmpty) {
    throw kBoardPostUpdateMalformed;
  }
  final Object? updatedAt = raw['updated_at'];
  if (updatedAt is! String || updatedAt.trim().isEmpty) {
    throw kBoardPostUpdateMalformed;
  }
  final Object? removed = raw['removed_image_refs'];
  if (removed is! List || removed.any((Object? e) => e is! String)) {
    throw kBoardPostUpdateMalformed;
  }
  return BoardPostUpdateResult(
    postId: postId,
    updatedAt: updatedAt,
    removedImageRefs: removed.cast<String>(),
  );
}

/// 제거된 기존 이미지의 Storage 삭제 seam(best-effort — 실패해도 수정 성공 유지).
typedef BoardPostRemovedRefsCleaner = Future<void> Function(List<String> refs);

/// 게시판 글 수정 전체 흐름(RPC → 봉투 검증 → 제거 이미지 정리 → 정본 행 조회).
/// 순수 오케스트레이터 — 의존은 전부 주입이라 호출 순서·파라미터까지 단위
/// 테스트로 고정할 수 있다. **직접 UPDATE 는 존재하지 않고, 기존 이미지 삭제는
/// RPC 성공이 확정된 뒤에만 일어난다.**
Future<BoardPost> updateBoardPostViaRpc({
  required String? authUserId,
  required BoardPostCreateRpc callRpc,
  required BoardPostFetcher fetchPostById,
  required BoardPostRemovedRefsCleaner removeImageRefs,
  required String postId,
  required String title,
  required String body,
  required String category,
  required String expectedUpdatedAt,
  required List<String> imageRefs,
}) async {
  // 미로그인은 호출조차 하지 않는다(서버도 AUTH_REQUIRED).
  if (authUserId == null || authUserId.isEmpty) {
    throw const AppError('로그인이 필요해요.');
  }
  if (postId.trim().isEmpty) throw kBoardPostUpdateMalformed;
  if (expectedUpdatedAt.trim().isEmpty) {
    // expected 없이 보내면 충돌 검사가 성립하지 않는다 — 보내지 않는다.
    throw kBoardPostUpdateMalformed;
  }

  final Object? raw = await callRpc(buildBoardPostUpdateParams(
    postId: postId,
    title: title,
    body: body,
    category: category,
    expectedUpdatedAt: expectedUpdatedAt,
    imageRefs: imageRefs,
  ));
  final BoardPostUpdateResult result = parseBoardPostUpdateEnvelope(raw);
  if (result.postId != postId) {
    // 계약 밖 — 어떤 글이 바뀌었는지 확정할 수 없으니 삭제도 하지 않는다.
    throw kBoardPostUpdatedButUnverified;
  }

  // DB 반영 확정 후에만 서버가 계산한 제거 목록을 정리한다(best-effort §14.4).
  if (result.removedImageRefs.isNotEmpty) {
    try {
      await removeImageRefs(result.removedImageRefs);
    } catch (_) {
      // 삭제 실패가 수정 성공을 뒤집지 않는다.
    }
  }

  // 저장된 정본 행을 다시 읽어 화면 모델을 만든다(서버가 제목·본문을 정규화
  // 하므로 요청값으로 화면을 구성하지 않는다).
  late final List<Map<String, dynamic>> rows;
  try {
    rows = await fetchPostById(result.postId);
  } catch (_) {
    throw kBoardPostUpdatedButUnverified;
  }
  if (rows.length != 1) throw kBoardPostUpdatedButUnverified;
  final Map<String, dynamic> row = rows.first;
  if (row['id'] != result.postId) throw kBoardPostUpdatedButUnverified;
  try {
    return BoardPost.fromMap(row);
  } catch (_) {
    throw kBoardPostUpdatedButUnverified;
  }
}
