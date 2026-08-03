import 'dart:math';

import '../../../shared/errors/app_error.dart';
import 'community_models.dart';
import 'community_post_error_mapper.dart';

/// 게시판 글 작성 = 서버 RPC 단일 경로(S3-D).
///
/// 배경: 운영 DB 의 `public.community_posts` 는 authenticated 에게 SELECT 만
/// 준다 — INSERT/UPDATE/DELETE 권한도, INSERT policy 도 없다. 그래서 앱의
/// 직접 INSERT 는 구조적으로 실패하며(Build 12 학생·멘토 등록 FAIL), 되살릴
/// 수단이 아니다. 작성 권한 판정·본문 정규화·author_role 도출은 전부 서버
/// 계약 함수가 수행하고, 앱은 그 결과를 그대로 따른다.
///
/// 정본 계약(frozen signature):
///   api_app_v1.community_post_create(
///     p_title text, p_body text, p_category text, p_idempotency_key uuid,
///     p_image_refs text[], p_status text) returns jsonb
///
/// 반환은 예외가 아니라 봉투(envelope) 다 — `{ok: bool, ...}`.
///   성공: {ok: true, post_id: uuid, idempotent_replay: bool, contract_version: 1}
///   실패: {ok: false, code: 'AUTH_REQUIRED' | ... , contract_version: 1}
/// 계약 밖 응답(shape 불일치·post_id 누락)은 **성공으로 처리하지 않는다**
/// (fail-closed). 서버 원문·SQL·UUID 는 어떤 경로로도 화면에 노출하지 않는다.

/// 호출 스키마 — public 이 아니다. `client.schema(...).rpc(...)` 로만 도달한다.
const String kBoardPostCreateSchema = 'api_app_v1';

/// 계약 함수명.
const String kBoardPostCreateFunction = 'community_post_create';

/// 앱 게시판 작성은 검수 없이 즉시 공개(동업자 확정) — draft 를 보내지 않는다.
const String kBoardPostCreateStatus = 'published';

/// 이미지 미첨부 작성의 기본 ref 집합. 이미지 첨부 시 정본 ref
/// (`community-post-images/{uid}/{object}` — board_post_media_gateway.dart)만
/// 담아 보낸다.
const List<String> kBoardPostCreateEmptyImageRefs = <String>[];

/// RPC 호출 seam(반환 = 디코딩된 jsonb). 테스트가 네트워크 없이 계약을 고정한다.
typedef BoardPostCreateRpc = Future<Object?> Function(
    Map<String, dynamic> params);

/// 성공 후 `public.community_posts` 단건 조회 seam(반환 = 행 목록).
typedef BoardPostFetcher = Future<List<Map<String, dynamic>>> Function(
    String postId);

/// 제출 작업 1건을 식별하는 멱등키(UUID v4).
///
/// 같은 submit operation 의 재시도(네트워크 응답 유실·명시적 재시도)는 **같은
/// 키를 유지**해야 서버가 재생(replay)으로 수렴시켜 중복 글이 생기지 않는다.
/// 새 키는 작성 작업 자체가 새로 시작될 때만 만든다.
///
/// `uuid` 패키지는 transitive 의존이라 직접 import 하지 않는다(pubspec 불변).
String newBoardPostIdempotencyKey() {
  final Random rnd = Random.secure();
  final List<int> b = List<int>.generate(16, (_) => rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant 10x
  final String hex =
      b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// RPC params — 키 이름·개수가 서버 signature 와 정확히 일치해야 한다
/// (PostgREST 는 이름으로 함수를 해석한다 — 하나라도 다르면 404 PGRST202).
Map<String, dynamic> buildBoardPostCreateParams({
  required String title,
  required String body,
  required String category,
  required String idempotencyKey,
  List<String> imageRefs = kBoardPostCreateEmptyImageRefs,
}) {
  return <String, dynamic>{
    'p_title': title,
    'p_body': body,
    'p_category': category,
    'p_idempotency_key': idempotencyKey,
    'p_image_refs': imageRefs,
    'p_status': kBoardPostCreateStatus,
  };
}

/// 성공 봉투 파싱 결과.
class BoardPostCreateResult {
  const BoardPostCreateResult({
    required this.postId,
    required this.idempotentReplay,
  });

  /// 서버가 확정한 글 ID(비민감 식별자 — 화면에 노출하지 않는다).
  final String postId;

  /// true = 같은 멱등키의 기존 글로 수렴(재시도 성공). 정상 성공으로 취급한다.
  final bool idempotentReplay;
}

/// 계약 밖 응답 공통 문구 — 코드·원문을 싣지 않는다.
const AppError kBoardPostCreateMalformed =
    AppError('글을 등록하지 못했어요. 잠시 후 다시 시도해 주세요.');

/// 서버가 글은 만들었는데 앱이 그 행을 확인하지 못한 경우.
/// ★ 중복 글을 만들지 않는다 — 같은 멱등키로 재시도하면 같은 글로 수렴한다.
const AppError kBoardPostCreatedButUnverified =
    AppError('글은 등록됐지만 화면을 갱신하지 못했어요. 목록을 새로고침해 확인해 주세요.');

/// 서버 오류 코드 → 사용자용 한글 문구.
///
/// 코드 집합·문구는 작성·수정 공용 매퍼(community_post_error_mapper.dart)가
/// 정본이다. 미지의 코드·비문자 코드는 전부 공통 문구로 수렴한다(fail-closed).
AppError boardPostCreateError(Object? code) {
  return communityPostWriteContractError(code) ?? kBoardPostCreateMalformed;
}

/// jsonb 봉투 파싱 — 성공만 통과시키고 나머지는 전부 throw.
///
/// `ok` 가 bool 이 아니거나, 성공인데 `post_id` 가 비어 있거나,
/// `idempotent_replay` 가 bool 이 아니면 계약 밖 응답이다(fail-closed).
BoardPostCreateResult parseBoardPostCreateEnvelope(Object? raw) {
  if (raw is! Map) throw kBoardPostCreateMalformed;
  final Object? ok = raw['ok'];
  if (ok is! bool) throw kBoardPostCreateMalformed;
  if (!ok) throw boardPostCreateError(raw['code']);
  final Object? postId = raw['post_id'];
  if (postId is! String || postId.trim().isEmpty) {
    throw kBoardPostCreateMalformed;
  }
  final Object? replay = raw['idempotent_replay'];
  if (replay != null && replay is! bool) throw kBoardPostCreateMalformed;
  return BoardPostCreateResult(
    postId: postId,
    idempotentReplay: replay == true,
  );
}

/// 게시판 글 작성 전체 흐름(RPC → 봉투 검증 → 저장된 행 조회 → BoardPost).
/// 순수 오케스트레이터 — 의존은 전부 주입이라 RPC 호출 횟수·파라미터까지
/// 단위 테스트로 고정할 수 있다. **직접 INSERT·보상 DELETE 는 존재하지 않는다.**
Future<BoardPost> createBoardPostViaRpc({
  required String? authUserId,
  required BoardPostCreateRpc callRpc,
  required BoardPostFetcher fetchPostById,
  required String title,
  required String body,
  required String category,
  required String idempotencyKey,
  List<String> imageRefs = kBoardPostCreateEmptyImageRefs,
}) async {
  // 미로그인은 호출조차 하지 않는다(게스트 작성 차단 — 서버도 AUTH_REQUIRED).
  if (authUserId == null || authUserId.isEmpty) {
    throw const AppError('로그인이 필요해요.');
  }
  if (idempotencyKey.trim().isEmpty) {
    // 멱등키 없는 create 는 중복 글을 만들 수 있다 — 보내지 않는다.
    throw kBoardPostCreateMalformed;
  }

  final Object? raw = await callRpc(buildBoardPostCreateParams(
    title: title,
    body: body,
    category: category,
    idempotencyKey: idempotencyKey,
    imageRefs: imageRefs,
  ));
  // 성공(신규·재생 모두) 이면 post_id 가 확정된다.
  final BoardPostCreateResult result = parseBoardPostCreateEnvelope(raw);

  // 저장된 정본 행을 다시 읽어 화면 모델을 만든다(서버가 제목·본문을 정규화
  // 하므로 요청값으로 화면을 구성하지 않는다).
  late final List<Map<String, dynamic>> rows;
  try {
    rows = await fetchPostById(result.postId);
  } catch (_) {
    throw kBoardPostCreatedButUnverified;
  }
  if (rows.length != 1) throw kBoardPostCreatedButUnverified;
  final Map<String, dynamic> row = rows.first;
  if (row['id'] != result.postId) throw kBoardPostCreatedButUnverified;
  try {
    return BoardPost.fromMap(row);
  } catch (_) {
    throw kBoardPostCreatedButUnverified;
  }
}
