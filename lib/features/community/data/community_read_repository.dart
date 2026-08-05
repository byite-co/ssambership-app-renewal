import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import 'comments_gateway.dart';
import 'community_models.dart';
import 'user_blocks_repository.dart';

/// 커뮤니티 열람(읽기 전용). 게시판·숏폼·댓글은 공개 열람(published/visible),
/// 내 반응·내 활동은 RLS(본인 행)로 걸러진다. ★ 여기서 mutate 하지 않는다.
/// ★ 차단(user_blocks): 목록·댓글에서 내가 차단한 작성자(author_id)의 콘텐츠는
///   결과에서 숨긴다(모델엔 author_id 를 노출하지 않고 raw 행에서 필터).
class CommunityReadRepository {
  const CommunityReadRepository(
      {CommentsGateway gateway = const CommentsGateway()})
      : _gateway = gateway;

  /// 댓글 원천 테이블 접근 통로(테스트 seam — 계약 검증용 가짜 주입 가능).
  final CommentsGateway _gateway;

  final UserBlocksRepository _blocks = const UserBlocksRepository();

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) {
      throw const AppError('백엔드에 연결되어 있지 않아요.');
    }
    return c;
  }

  String? get _uid => SupabaseInit.clientOrNull?.auth.currentUser?.id;

  /// 차단 작성자 행 제거(author_id 는 화면에 노출하지 않고 여기서만 사용).
  List<Map<String, dynamic>> _dropBlocked(
      List<Map<String, dynamic>> rows, Set<String> blocked) {
    if (blocked.isEmpty) return rows;
    return rows
        .where((Map<String, dynamic> r) => !blocked.contains(r['author_id']))
        .toList();
  }

  /// 페이지 결과 조립 — 오프셋 전진 기준은 필터 '전' 행 수(P2-21: 차단 필터로
  /// items 가 줄어도 다음 페이지가 행을 건너뛰거나 중복하지 않도록).
  CommunityPage<T> _page<T>({
    required List<T> items,
    required int rawCount,
    required int offset,
    required int? limit,
  }) {
    return CommunityPage<T>(
      items: items,
      rawCount: rawCount,
      nextOffset: offset + rawCount,
      hasMore: limit != null && rawCount == limit,
    );
  }

  /// 게시판 글 목록(공개=published, 최신순). category 지정 시 그 분류만.
  /// [limit] 지정 시 [offset]부터 그만큼만(페이징). null 이면 전체(하위 호환).
  /// ★ 반환 페이지의 nextOffset/rawCount 로만 페이징을 전진할 것(items.length 금지).
  ///
  /// 정본 소스는 뷰 `api_web_v1.community_posts_v1` 다(계약 수렴 — anon 허용,
  /// deleted_at IS NULL + (published OR 본인 행)은 서버가 강제). 컬럼명은
  /// 베이스 테이블과 다르다: 본문 `body`, 이미지 `image_refs`.
  Future<CommunityPage<BoardPost>> boards(
      {String? category, int? limit, int offset = 0}) async {
    dynamic q = _client
        .schema('api_web_v1')
        .from('community_posts_v1')
        .select('*')
        .eq('status', 'published');
    if (category != null && category.isNotEmpty) {
      q = q.eq('category', category);
    }
    q = q.order('created_at', ascending: false);
    if (limit != null) q = q.range(offset, offset + limit - 1);
    final Future<Set<String>> blockedF = _blocks.myBlockedIds();
    final List<Map<String, dynamic>> rows = await q;
    final List<BoardPost> items =
        _dropBlocked(rows, await blockedF).map(BoardPost.fromMap).toList();
    return _page<BoardPost>(
        items: items, rawCount: rows.length, offset: offset, limit: limit);
  }

  /// 숏폼 목록(공개=published, 최신순). [limit]/[offset] 로 페이징(하위 호환: null=전체).
  /// ★ 반환 페이지의 nextOffset/rawCount 로만 페이징을 전진할 것(items.length 금지).
  Future<CommunityPage<ShortformPost>> shortforms(
      {int? limit, int offset = 0}) async {
    dynamic q = _client
        .from('shortform_posts')
        .select('*')
        .eq('status', 'published')
        .order('created_at', ascending: false);
    if (limit != null) q = q.range(offset, offset + limit - 1);
    final Future<Set<String>> blockedF = _blocks.myBlockedIds();
    final List<Map<String, dynamic>> rows = await q;
    final List<ShortformPost> items =
        _dropBlocked(rows, await blockedF).map(ShortformPost.fromMap).toList();
    return _page<ShortformPost>(
        items: items, rawCount: rows.length, offset: offset, limit: limit);
  }

  /// 글/숏폼의 댓글(대화순=오름차순). [limit]/[offset] 로 페이징(하위 호환: null=전체).
  ///
  /// v16 정본 전환 — 게시판: 정본 `comments` 에서 post_id 로만 조회
  /// (삭제 댓글 제외 is_deleted=false 는 서버 RLS 가 보장, 앱 필터 불필요).
  /// 숏폼: 기존 `community_comments`(post_type='shortform', status='visible') 유지.
  Future<List<CommunityComment>> comments(
    CommunityPostType type,
    String postId, {
    int? limit,
    int offset = 0,
  }) async {
    final Map<String, Object> filters = type == CommunityPostType.board
        ? <String, Object>{'post_id': postId}
        : <String, Object>{
            'post_type': type.code,
            'post_id': postId,
            'status': 'visible',
          };
    final Future<Set<String>> blockedF = _blocks.myBlockedIds();
    final List<Map<String, dynamic>> rows = await _gateway.selectComments(
      table: type.commentsTable,
      filters: filters,
      limit: limit,
      offset: offset,
    );
    return _dropBlocked(rows, await blockedF)
        .map(CommunityComment.fromMap)
        .toList();
  }

  /// 내가 특정 반응(type: like|scrap)을 남긴 게시판 글 id 집합(반응 상태 표시용).
  ///
  /// [postId] 를 주면 그 글 1건으로 서버에서 필터한다(C9 — 상세 화면이 내 반응
  /// 전체를 내려받아 contains 하던 전체 스캔 제거). 내 활동 탭처럼 전체 집합이
  /// 필요한 곳만 postId 없이 부른다.
  Future<Set<String>> myBoardReactionIds(String reactionType,
      {String? postId}) async {
    final String? uid = _uid;
    if (uid == null) return <String>{};
    PostgrestFilterBuilder<List<Map<String, dynamic>>> q = _client
        .from('post_reactions')
        .select('post_id')
        .eq('user_id', uid)
        .eq('type', reactionType);
    if (postId != null) q = q.eq('post_id', postId);
    final List<Map<String, dynamic>> rows = await q;
    return <String>{
      for (final Map<String, dynamic> r in rows)
        if (r['post_id'] != null) r['post_id'] as String,
    };
  }

  /// 내가 특정 반응(type: like|scrap)을 남긴 숏폼 id 집합(숏폼 반응 상태 표시용).
  /// [shortformId] 를 주면 그 숏폼 1건으로 서버에서 필터한다(C9).
  Future<Set<String>> myShortformReactionIds(String reactionType,
      {String? shortformId}) async {
    final String? uid = _uid;
    if (uid == null) return <String>{};
    PostgrestFilterBuilder<List<Map<String, dynamic>>> q = _client
        .from('shortform_reactions')
        .select('shortform_id')
        .eq('user_id', uid)
        .eq('type', reactionType);
    if (shortformId != null) q = q.eq('shortform_id', shortformId);
    final List<Map<String, dynamic>> rows = await q;
    return <String>{
      for (final Map<String, dynamic> r in rows)
        if (r['shortform_id'] != null) r['shortform_id'] as String,
    };
  }

  /// 내 활동: 내가 쓴 글 + 좋아요/스크랩한 글(읽기). 반응은 게시판 글 기준.
  /// 게시판 읽기는 전부 뷰(community_posts_v1) 경유 — 본인 행은 뷰가
  /// status 무관 허용하므로 초안도 내 활동에 보인다(서버 판정 정본).
  Future<MyActivity> myActivity() async {
    final String? uid = _uid;
    if (uid == null) return const MyActivity();

    final List<Map<String, dynamic>> mineRows = await _client
        .schema('api_web_v1')
        .from('community_posts_v1')
        .select('*')
        .eq('author_id', uid)
        .order('created_at', ascending: false);
    final List<BoardPost> myPosts = mineRows.map(BoardPost.fromMap).toList();

    final Set<String> likedIds = await myBoardReactionIds('like');
    final Set<String> scrapIds = await myBoardReactionIds('scrap');
    final List<BoardPost> liked = await _postsByIds(likedIds);
    final List<BoardPost> scrapped = await _postsByIds(scrapIds);

    return MyActivity(myPosts: myPosts, liked: liked, scrapped: scrapped);
  }

  Future<List<BoardPost>> _postsByIds(Set<String> ids) async {
    if (ids.isEmpty) return <BoardPost>[];
    final List<Map<String, dynamic>> rows = await _client
        .schema('api_web_v1')
        .from('community_posts_v1')
        .select('*')
        .inFilter('id', ids.toList())
        .order('created_at', ascending: false);
    return rows.map(BoardPost.fromMap).toList();
  }

  /// 게시판 글 1건(알림 딥링크 → 상세 진입용). 없거나 접근 밖이면 null.
  Future<BoardPost?> boardPostById(String postId) async {
    final List<BoardPost> rows = await _postsByIds(<String>{postId});
    return rows.isEmpty ? null : rows.first;
  }

  /// 숏폼 1건(알림 딥링크 → 상세 진입용). 없으면 null. 숏폼 읽기는 계속
  /// 베이스 `shortform_posts`(published 공개 열람) 다.
  Future<ShortformPost?> shortformById(String id) async {
    final Map<String, dynamic>? row = await _client
        .from('shortform_posts')
        .select('*')
        .eq('id', id)
        .eq('status', 'published')
        .maybeSingle();
    return row == null ? null : ShortformPost.fromMap(row);
  }
}
