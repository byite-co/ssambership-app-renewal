import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import 'comments_gateway.dart';
import 'community_models.dart';
import 'community_post_actions.dart';
import 'community_post_images.dart';

/// 커뮤니티 쓰기(반응·댓글·신고·게시판 글). ★ 숏폼 '작성'은 이 레포에 없다 —
/// 실제 write 는 웹 작성기(인앱 WebView, ShortformComposeScreen)가 담당한다.
///
/// S2-2 M17 전환: 게시판 글 생성/수정/삭제는 `api_app_v1` wrapper
/// (`community_post_create/update/soft_delete`)만 사용한다 — `community_posts`
/// 직접 INSERT/UPDATE/DELETE/UPSERT 0건. author_id/author_role/author_label 은
/// 서버가 `auth.uid()` 로 도출하므로 앱이 보내지 않는다(앱 계약 §3.3·§6.2).
/// DB 게시글 hard DELETE 보상(구 deleteOwnPostForCompensation)은 폐기됐고,
/// Storage 신규 이미지 보상 삭제만 §6.3 4분기 규약으로 유지한다.
class CommunityWriteRepository {
  const CommunityWriteRepository({
    CommentsGateway? gateway,
    SupabaseClient? client,
  })  : _gatewayOverride = gateway,
        _clientOverride = client;

  /// 댓글 원천 테이블 접근 통로 명시 주입(테스트 seam — 계약 검증용 가짜).
  final CommentsGateway? _gatewayOverride;

  /// 로컬 검증 하네스 주입용(운영은 SupabaseInit 전역 클라이언트).
  final SupabaseClient? _clientOverride;

  /// 명시 게이트웨이 > 클라이언트 override 게이트웨이 > 기본(전역 클라이언트).
  CommentsGateway get _gateway =>
      _gatewayOverride ?? CommentsGateway(client: _clientOverride);

  /// 반응 종류(자유 텍스트 컬럼 — 앱 내부 규약).
  static const String reactionLike = 'like';
  static const String reactionScrap = 'scrap';

  SupabaseClient get _client {
    final SupabaseClient? c = _clientOverride ?? SupabaseInit.clientOrNull;
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
  /// M13: author_label/author_role 은 서버 BEFORE INSERT 트리거가 users.nickname
  /// 기준으로 도출·강제한다 — 앱은 라벨을 권위값으로 전송하지 않는다(§3.5).
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

  /// `api_app_v1` wrapper 호출(named arguments — 계약 §3.3 호출 규약).
  Future<Object?> _appV1Rpc(String fn, Map<String, dynamic> params) {
    return _client.schema('api_app_v1').rpc<dynamic>(fn, params: params);
  }

  /// 게시판 글 생성(F4 — `api_app_v1.community_post_create`).
  ///
  /// - 작성 자격(승인 멘토 전용)·본문 검증·author 도출은 전부 서버 공용
  ///   구현부 몫 — 앱은 author_id/role/label 을 보내지 않는다.
  /// - [idempotencyKey] 는 작성 시도당 1회 생성(UUID). 응답 불명확
  ///   ([CommunityCreateUnclear]) 후 재시도에는 **같은 키를 다시 넘겨야 한다**.
  /// - 이미지 업로드·보상 삭제(§6.3 4분기)·replay-first 재호출은
  ///   [createBoardPostV1] 이 수행한다.
  Future<CreatedBoardPostV1> createPost({
    required String title,
    required String body,
    required String category,
    required String idempotencyKey,
    List<ValidatedPostImage> images = const <ValidatedPostImage>[],
  }) {
    return createBoardPostV1(
      uid: _uid,
      title: title,
      body: body,
      category: category,
      idempotencyKey: idempotencyKey,
      images: images,
      storage: SupabaseCommunityPostImageBackend(_client),
      callCreate: (Map<String, dynamic> params) =>
          _appV1Rpc('community_post_create', params),
    );
  }

  /// 게시판 글 수정(F5 — `api_app_v1.community_post_update`).
  /// [expectedUpdatedAt] 은 실제 조회한 행의 updated_at 원문(NULL 포함)이어야
  /// 하며, `UPDATE_CONFLICT` 는 자동 덮어쓰기 없이 그대로 사용자에게 안내한다.
  Future<UpdatedBoardPostV1> updatePost({
    required String postId,
    required String title,
    required String body,
    required String category,
    required String? expectedUpdatedAt,
    required List<String> imageRefs,
  }) {
    return updateBoardPostV1(
      postId: postId,
      title: title,
      body: body,
      category: category,
      expectedUpdatedAt: expectedUpdatedAt,
      imageRefs: imageRefs,
      storage: SupabaseCommunityPostImageBackend(_client),
      callUpdate: (Map<String, dynamic> params) =>
          _appV1Rpc('community_post_update', params),
    );
  }

  /// 게시판 글 삭제(F6 — `api_app_v1.community_post_soft_delete`).
  /// hard delete 아님 — 행·이미지 참조는 감사 목적으로 보존된다.
  Future<SoftDeletedBoardPostV1> softDeletePost(String postId) {
    return softDeleteBoardPostV1(
      postId: postId,
      callSoftDelete: (Map<String, dynamic> params) =>
          _appV1Rpc('community_post_soft_delete', params),
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
