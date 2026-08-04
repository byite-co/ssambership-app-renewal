import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/scan/picked_image.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import 'board_post_create_gateway.dart';
import 'board_post_media_gateway.dart';
import 'board_post_update_gateway.dart';
import 'comments_gateway.dart';
import 'community_models.dart';

/// 커뮤니티 쓰기(반응·댓글·신고·게시판 글 작성). ★ 숏폼 '작성'은 이 레포에 없다 —
/// 실제 write 는 웹 작성기(인앱 WebView, ShortformComposeScreen)가 담당한다.
/// 본인(author_id/user_id/reporter_id = 현재 사용자) 행만 다룬다(RLS도 강제).
class CommunityWriteRepository {
  const CommunityWriteRepository(
      {CommentsGateway gateway = const CommentsGateway()})
      : _gateway = gateway;

  /// 댓글 원천 테이블 접근 통로(테스트 seam — 계약 검증용 가짜 주입 가능).
  final CommentsGateway _gateway;

  /// 반응 종류(자유 텍스트 컬럼 — 앱 내부 규약).
  static const String reactionLike = 'like';
  static const String reactionScrap = 'scrap';

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) {
      throw const AppError('백엔드에 연결되어 있지 않아요.');
    }
    return c;
  }

  String get _uid {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) throw const AppError('로그인이 필요해요.');
    return id;
  }

  /// 현재 로그인 사용자 id(비로그인·미연결이면 null).
  /// ★ 소유권 UI 게이트(내 글에만 수정 노출) 전용 — 화면에 노출하지 않는다.
  ///   보안 정본은 서버(community_post_update 의 author_id 검사)다.
  String? get currentUserId => SupabaseInit.clientOrNull?.auth.currentUser?.id;

  /// 게시판 글 반응 토글(좋아요/스크랩). on=true면 추가, false면 제거.
  /// like_count 자체는 서버(트리거)가 관리 — 앱은 내 반응 행만 만든다/지운다.
  Future<void> toggleBoardReaction({
    required String postId,
    required String type,
    required bool on,
  }) async {
    final String uid = _uid;
    if (on) {
      await _client.from('post_reactions').insert(<String, dynamic>{
        'user_id': uid,
        'post_id': postId,
        'type': type,
      });
    } else {
      await _client
          .from('post_reactions')
          .delete()
          .eq('user_id', uid)
          .eq('post_id', postId)
          .eq('type', type);
    }
  }

  /// 숏폼 반응 토글(좋아요/스크랩).
  Future<void> toggleShortformReaction({
    required String shortformId,
    required String type,
    required bool on,
  }) async {
    final String uid = _uid;
    if (on) {
      await _client.from('shortform_reactions').insert(<String, dynamic>{
        'user_id': uid,
        'shortform_id': shortformId,
        'type': type,
      });
    } else {
      await _client
          .from('shortform_reactions')
          .delete()
          .eq('user_id', uid)
          .eq('shortform_id', shortformId)
          .eq('type', type);
    }
  }

  /// 게시글 조회수 +1(상세 진입 시). 기존 RPC 사용. ★ RPC 부재/실패 시 조용히 무시(조회수만 안 오름).
  Future<void> incrementBoardView(String postId) async {
    try {
      await _client.rpc('increment_community_post_view',
          params: <String, dynamic>{'p_post_id': postId});
    } catch (_) {
      // 증분 RPC 미존재/권한 등 → 조용히 폴백(조회 자체엔 영향 없음).
    }
  }

  /// 숏폼 조회 기록 v2(상세 진입 시) — (post, event_key) 멱등.
  ///
  /// ★ 구 `increment_shortform_post_view` 는 앱 권한이 REVOKE 됐다 — 호출
  ///   코드를 남기지 않는다. [eventKey] 는 **화면 노출 1회당 1개**(UUID v4,
  ///   화면 initState 에서 생성)를 재사용한다: 실패해도 새 키로 재시도하지
  ///   않는다(조회수는 비핵심 — 실패는 조용히 무시, 중복 가산 0).
  Future<void> recordShortformView({
    required String postId,
    required String eventKey,
  }) async {
    try {
      await _client.rpc('shortform_view_record_v2', params: <String, dynamic>{
        'p_post_id': postId,
        'p_event_key': eventKey,
      });
    } catch (_) {
      // 조용한 폴백(조회 자체엔 영향 없음).
    }
  }

  /// 댓글 작성(본인). author_id 는 항상 현재 사용자.
  ///
  /// v16 정본 전환 — 게시판: 정본 `comments` 에 {post_id, author_id, content}만
  /// INSERT(보호·모더레이션 필드 전송 금지 — 서버 트리거가 그 외 컬럼 변경을 거부).
  /// 숏폼: 기존 `community_comments`(post_type='shortform', status='visible') 유지.
  /// [parentId] 는 게시판 답글(최대 2-depth)용 — 현재 UI는 평면이라 미사용(null=미전송).
  Future<CommunityComment> addComment({
    required CommunityPostType postType,
    required String postId,
    required String body,
    String? parentId,
  }) async {
    final String? uid = _gateway.currentUserId;
    if (uid == null) throw const AppError('로그인이 필요해요.');
    final Map<String, dynamic> values = postType == CommunityPostType.board
        ? boardCommentInsertValues(
            postId: postId, authorId: uid, content: body, parentId: parentId)
        : <String, dynamic>{
            'post_type': postType.code,
            'post_id': postId,
            'author_id': uid,
            'body': body,
            'status': 'visible',
          };
    try {
      final Map<String, dynamic> row = await _gateway.insertComment(
          table: postType.commentsTable, values: values);
      return CommunityComment.fromMap(row);
    } catch (e) {
      // 서버 트리거 계약 위반(깊이 초과 등)은 한글 문구로 변환, 그 외는 그대로.
      final AppError? friendly = commentContractError(e);
      if (friendly != null) throw friendly;
      rethrow;
    }
  }

  /// 게시판 댓글 INSERT 페이로드(정본 comments) — 정확히 {post_id, author_id,
  /// content} 만. ★ status/like_count/legacy_comment_id 등 보호·모더레이션 필드는
  /// 절대 넣지 않는다(서버 트리거가 거부). [parentId] 지정 시에만 parent_id 추가.
  static Map<String, dynamic> boardCommentInsertValues({
    required String postId,
    required String authorId,
    required String content,
    String? parentId,
  }) {
    return <String, dynamic>{
      'post_id': postId,
      'author_id': authorId,
      'content': content,
      if (parentId != null) 'parent_id': parentId,
    };
  }

  /// 숏폼 댓글 **본인** 소프트삭제 — 서버 RPC 단일 경로.
  ///
  /// 서버 계약(5): community_comment_soft_delete_self(p_comment_id uuid)
  ///   성공: {ok:true, contract_version:1, comment_id, idempotent_hit}
  ///   실패 코드: COMMENT_NOT_FOUND · COMMENT_TYPE_NOT_SUPPORTED ·
  ///     COMMENT_NOT_OWNED · COMMENT_MODERATED · ACCOUNT_* (봉투 code 또는
  ///     raise exception 어느 형태로 와도 한글 문구로 변환한다).
  /// 멱등 히트(idempotent_hit)는 정상 성공으로 취급한다(이중 탭 안전).
  Future<void> deleteMyShortformComment(String commentId) async {
    final Object? data;
    try {
      data = await _gateway.softDeleteShortformComment(commentId);
    } catch (e) {
      final AppError? friendly = shortformCommentDeleteError(e.toString());
      if (friendly != null) throw friendly;
      rethrow;
    }
    if (data is Map && data['ok'] == true) {
      if (data['contract_version'] != 1) {
        throw const AppError('댓글 삭제 결과를 확인하지 못했어요. 다시 시도해 주세요.');
      }
      return; // 성공(멱등 히트 포함).
    }
    // 실패 봉투({ok:false, code}) 또는 계약 밖 응답 — 성공 위장 금지.
    final Object? code = data is Map ? data['code'] : null;
    throw shortformCommentDeleteError(code is String ? code : '') ??
        const AppError('댓글을 삭제하지 못했어요. 잠시 후 다시 시도해 주세요.');
  }

  /// 숏폼 댓글 삭제 서버 오류 코드 → 사용자용 한글 문구(코드·원문 비노출).
  /// 매핑 대상이 아니면 null(호출부가 공통 문구/원 예외로 폴백).
  static AppError? shortformCommentDeleteError(String raw) {
    if (raw.contains('COMMENT_NOT_FOUND')) {
      return const AppError('댓글을 찾을 수 없어요. 이미 삭제됐을 수 있어요.');
    }
    if (raw.contains('COMMENT_TYPE_NOT_SUPPORTED')) {
      return const AppError('이 댓글은 앱에서 삭제할 수 없어요.');
    }
    if (raw.contains('COMMENT_NOT_OWNED')) {
      return const AppError('내가 쓴 댓글만 삭제할 수 있어요.');
    }
    if (raw.contains('COMMENT_MODERATED')) {
      return const AppError('운영팀이 처리한 댓글은 삭제할 수 없어요.');
    }
    if (raw.contains('ACCOUNT_BANNED') || raw.contains('ACCOUNT_SUSPENDED')) {
      return const AppError('계정 이용이 제한된 상태예요. 자세한 내용은 문의해 주세요.');
    }
    if (raw.contains('ACCOUNT_DELETION_IN_PROGRESS')) {
      return const AppError('탈퇴 처리 중에는 이 기능을 사용할 수 없어요.');
    }
    if (raw.contains('ACCOUNT_NOT_ACTIVE')) {
      return const AppError('현재 계정 상태에서는 이 기능을 사용할 수 없어요.');
    }
    return null;
  }

  /// 정본 comments 서버 트리거 오류 → 사용자용 한글 문구(코드·원문 비노출).
  /// 매핑 대상이 아니면 null(호출부가 원 예외 유지 → friendlyError 일반 문구).
  static AppError? commentContractError(Object e) {
    final String raw = e.toString();
    if (raw.contains('COMMENT_DEPTH_EXCEEDED')) {
      return const AppError('답글에는 다시 답글을 달 수 없어요.');
    }
    if (raw.contains('COMMENT_PARENT_POST_MISMATCH')) {
      return const AppError('답글 대상 댓글을 찾을 수 없어요. 새로고침 후 다시 시도해 주세요.');
    }
    if (raw.contains('COMMENT_HARD_DELETE_FORBIDDEN')) {
      return const AppError('댓글은 삭제 처리만 가능해요. 잠시 후 다시 시도해 주세요.');
    }
    return null;
  }

  /// 게시판 글 작성(본인) — **서버 RPC 단일 경로**(S3-D).
  ///
  /// 운영 DB 는 `community_posts` 에 authenticated SELECT 만 허용한다(INSERT
  /// 권한·policy 없음). 그래서 직접 INSERT 도, 그 뒤처리용 보상 DELETE 도 이
  /// 경로에 존재하지 않는다 — 작성 판정·본문 정규화·author_role 도출은 전부
  /// `api_app_v1.community_post_create` 가 수행한다.
  ///
  /// [idempotencyKey] 는 **제출 작업 1건**을 식별한다. 같은 작업의 재시도는
  /// 같은 키를 보내야 서버가 기존 글로 수렴시킨다(중복 글 방지). 새 키 생성은
  /// 화면(작성 작업 시작 시점)의 책임이다 — `newBoardPostIdempotencyKey()`.
  Future<BoardPost> createPost({
    required String title,
    required String body,
    required String category,
    required String idempotencyKey,
    List<String> imageRefs = kBoardPostCreateEmptyImageRefs,
  }) {
    final SupabaseClient client = _client;
    return createBoardPostViaRpc(
      authUserId: client.auth.currentUser?.id,
      title: title,
      body: body,
      category: category,
      idempotencyKey: idempotencyKey,
      imageRefs: imageRefs,
      callRpc: (Map<String, dynamic> params) async {
        // ★ schema() 를 생략하면 public 으로 나가 함수를 찾지 못한다(PGRST202).
        final Object? data = await client
            .schema(kBoardPostCreateSchema)
            .rpc(kBoardPostCreateFunction, params: params);
        return data;
      },
      // 저장 정본 재조회 — 읽기 레포(D-3 계약)를 건드리지 않는 단건 SELECT.
      fetchPostById: _fetchPostById,
    );
  }

  /// 게시판 글 수정(본인) — **서버 RPC 단일 경로**(작성과 동일 원칙).
  ///
  /// 직접 UPDATE 는 존재하지 않는다 — 소유·역할·계정 상태 판정과 본문
  /// 정규화·이미지 ref 검증은 전부 `api_app_v1.community_post_update` 가
  /// 수행한다(서버 소유권 검사가 보안 정본).
  ///
  /// [expectedUpdatedAt] 은 수정 시작 시점 행의 `updated_at` **원문**
  /// (`BoardPost.updatedAtRaw`)이어야 한다 — 서버가 exact 비교로 낙관적 충돌
  /// (UPDATE_CONFLICT)을 판정한다. [imageRefs] 는 수정 후 글에 남을 전체 ref
  /// 집합(유지+추가). 빠진 기존 ref 의 Storage 삭제는 서버가 돌려준
  /// `removed_image_refs` 기준으로 **RPC 성공 후에만** best-effort 수행한다.
  Future<BoardPost> updatePost({
    required String postId,
    required String title,
    required String body,
    required String category,
    required String expectedUpdatedAt,
    required List<String> imageRefs,
  }) {
    final SupabaseClient client = _client;
    return updateBoardPostViaRpc(
      authUserId: client.auth.currentUser?.id,
      postId: postId,
      title: title,
      body: body,
      category: category,
      expectedUpdatedAt: expectedUpdatedAt,
      imageRefs: imageRefs,
      callRpc: (Map<String, dynamic> params) async {
        // ★ 작성과 같은 api_app_v1 스키마 — 생략 시 public 으로 나가 PGRST202.
        final Object? data = await client
            .schema(kBoardPostCreateSchema)
            .rpc(kBoardPostUpdateFunction, params: params);
        return data;
      },
      fetchPostById: _fetchPostById,
      removeImageRefs: (List<String> refs) => removeCommunityPostImageRefs(
        backend: const SupabaseCommunityPostMediaBackend(),
        refs: refs,
      ),
    );
  }

  /// 게시글 이미지 1장 업로드 → 서버 정본 ref 반환(작성·수정 공용).
  /// 검증(5MB·4종 MIME)·경로 규약·버킷은 board_post_media_gateway 가 정본이다.
  Future<String> uploadPostImage(PickedImage image) {
    return uploadCommunityPostImage(
      authUserId: currentUserId,
      backend: const SupabaseCommunityPostMediaBackend(),
      image: image,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 저장 정본 재조회 — 읽기와 같은 뷰(api_web_v1.community_posts_v1) 경유.
  /// 본인 행은 status 무관 보이므로 작성·수정 직후 재조회가 항상 성립한다.
  Future<List<Map<String, dynamic>>> _fetchPostById(String postId) async {
    final List<dynamic> rows = await _client
        .schema('api_web_v1')
        .from('community_posts_v1')
        .select('*')
        .eq('id', postId)
        .limit(1);
    return rows.cast<Map<String, dynamic>>();
  }

  /// 신고 접수(content_reports). 외부 연락처 유도 등도 사유로 신고할 수 있다.
  /// reporter_id 는 현재 사용자, status='pending'.
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
    String? description,
  }) async {
    await _client.from('content_reports').insert(<String, dynamic>{
      'reporter_id': _uid,
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      'status': 'pending',
    });
  }
}
