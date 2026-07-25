import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import 'board_author_gate.dart';
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

  /// 숏폼 조회수 +1(상세 진입 시). 기존 RPC 사용. ★ RPC 부재/실패 시 조용히 무시.
  Future<void> incrementShortformView(String postId) async {
    try {
      await _client.rpc('increment_shortform_post_view',
          params: <String, dynamic>{'p_post_id': postId});
    } catch (_) {
      // 조용한 폴백.
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

  /// 게시판 글 작성(본인). ★ 검수 없이 즉시 공개(status='published' — 동업자 확정).
  /// author_role 정본 = 본인 users 행 role SELECT(BoardAuthorGate) — DB
  /// DEFAULT('mentor') 의존 금지, 모든 실패 fail-closed(INSERT 0회), 저장 후
  /// 반환 행 author_id/author_role 재검증까지 통과해야 성공 처리한다.
  Future<BoardPost> createPost({
    required String title,
    required String body,
    required String category,
  }) {
    final SupabaseClient client = _client;
    return createBoardPostGated(
      authUserId: client.auth.currentUser?.id,
      fetchOwnUserRows: (String userId) async {
        final List<dynamic> rows =
            await client.from('users').select('id, role').eq('id', userId);
        return rows.cast<Map<String, dynamic>>();
      },
      insert: (Map<String, dynamic> payload) =>
          client.from('community_posts').insert(payload).select().single(),
      title: title,
      body: body,
      category: category,
      // 보정2: 반환 정본 불일치 '보상 전용' 내부 삭제 — 공개 API·UI·라우트로
      // 노출하지 않는다. id+본인 author_id 로 클라이언트 범위를 좁히고,
      // 실제 권한 판정은 RLS cp_delete_own(author 본인 또는 admin)에 맡긴다.
      deleteOwnPostForCompensation: (String postId) async {
        final String? uid = client.auth.currentUser?.id;
        if (uid == null) throw const AppError('로그인이 필요해요.');
        // v19 보정2: representation 을 요청해 실제 삭제 행을 확인한다 —
        // 0행(조건 불일치·RLS 비가시성·기삭제)은 성공이 아니다.
        final List<dynamic> deleted = await client
            .from('community_posts')
            .delete()
            .eq('id', postId)
            .eq('author_id', uid)
            .select('id');
        verifyCompensationDeleteReturn(deleted, postId);
      },
    );
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
