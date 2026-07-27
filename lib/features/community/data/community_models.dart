import 'model_parse.dart';

/// 작성자 표시명 폴백(공통). author_label(비정규화 표시명)이 비면 역할 기반 중립 라벨.
/// ★ 내부 author_id(UUID)는 절대 노출하지 않는다.
String communityAuthorName(String? authorLabel, String? authorRole) {
  final String label = authorLabel?.trim() ?? '';
  if (label.isNotEmpty) return label;
  switch (authorRole?.trim()) {
    case 'mentor':
      return '멘토';
    case 'student':
      return '학생';
    default:
      return '쌤버십 회원';
  }
}

/// 여러 텍스트 컬럼 중 [keys] 순서대로 처음 나오는 비어 있지 않은 값(트림).
/// (스키마 과도기: content/body/description 컬럼 혼재 — 우선순위를 한곳에서.)
String? _pickText(Map<String, dynamic> m, List<String> keys) {
  for (final String k in keys) {
    final Object? v = m[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}

/// 목록 페이지 결과 — 차단 필터로 [items] 가 줄어도, 다음 페이지 오프셋은
/// DB에서 실제로 가져온 행 수([rawCount]) 기준으로 전진해야 행 누락·중복이 없다(P2-21).
class CommunityPage<T> {
  const CommunityPage({
    required this.items,
    required this.rawCount,
    required this.nextOffset,
    required this.hasMore,
  });

  /// 차단 작성자 필터 적용 '후' 화면에 표시할 항목.
  final List<T> items;

  /// 필터 '전' DB에서 가져온 행 수 — 오프셋 전진 기준(★ items.length 아님).
  final int rawCount;

  /// 다음 페이지 요청 오프셋(= 요청 offset + rawCount).
  final int nextOffset;

  /// 다음 페이지 존재 가능성(rawCount == limit). limit 미지정(전체 조회)이면 false.
  final bool hasMore;
}

/// 게시판 글(community_posts). 열람 전용 뷰모델.
class BoardPost {
  const BoardPost({
    required this.id,
    required this.title,
    this.body,
    this.category,
    this.authorLabel,
    this.authorRole,
    required this.likeCount,
    required this.commentCount,
    required this.viewCount,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String? body;
  final String? category;
  final String? authorLabel;
  final String? authorRole;
  final int likeCount;
  final int commentCount;
  final int viewCount;
  final DateTime createdAt;

  String get authorName => communityAuthorName(authorLabel, authorRole);

  factory BoardPost.fromMap(Map<String, dynamic> m) {
    return BoardPost(
      id: m['id'] as String,
      title: (m['title'] as String?)?.trim().isNotEmpty == true
          ? (m['title'] as String).trim()
          : '(제목 없음)',
      // 스키마상 body/content 둘 다 존재 — 게시판은 legacy content 우선(기존 계약 유지).
      body: _pickText(m, const <String>['content', 'body']),
      category: m['category'] as String?,
      authorLabel: m['author_label'] as String?,
      authorRole: m['author_role'] as String?,
      likeCount: parseInt(m['like_count']),
      commentCount: parseInt(m['comment_count']),
      viewCount: parseInt(m['view_count']),
      createdAt: parseTime(m['created_at']),
    );
  }
}

/// 숏폼(shortform_posts). 열람 전용 뷰모델. 실제 재생 플러그인은 없음(썸네일+재생 어포던스).
class ShortformPost {
  const ShortformPost({
    required this.id,
    required this.title,
    this.description,
    this.category,
    this.authorLabel,
    this.authorRole,
    this.thumbnailUrl,
    this.videoUrl,
    required this.likeCount,
    required this.viewCount,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String? description;
  final String? category;
  final String? authorLabel;
  final String? authorRole;
  final String? thumbnailUrl;
  final String? videoUrl;
  final int likeCount;
  final int viewCount;
  final DateTime createdAt;

  String get authorName => communityAuthorName(authorLabel, authorRole);

  factory ShortformPost.fromMap(Map<String, dynamic> m) {
    return ShortformPost(
      id: m['id'] as String,
      title: (m['title'] as String?)?.trim().isNotEmpty == true
          ? (m['title'] as String).trim()
          : '(제목 없음)',
      // 본문/설명: 숏폼은 'body' 우선, legacy 'content' 폴백(서버 계약),
      // 구(舊) 'description' 컬럼만 있는 행은 그대로 표시(최종 폴백).
      description:
          _pickText(m, const <String>['body', 'content', 'description']),
      category: m['category'] as String?,
      authorLabel: m['author_label'] as String?,
      authorRole: m['author_role'] as String?,
      thumbnailUrl: (m['thumbnail_url'] as String?)?.trim(),
      videoUrl: (m['video_url'] as String?)?.trim(),
      likeCount: parseInt(m['like_count']),
      viewCount: parseInt(m['view_count']),
      createdAt: parseTime(m['created_at']),
    );
  }
}

/// 커뮤니티 댓글 뷰모델 — 게시판은 정본 `comments`, 숏폼은 기존
/// `community_comments` 행을 공용으로 담는다(v16 정본 전환).
/// 본문은 content(정본) 우선·body(legacy) 폴백으로 읽는다.
class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.body,
    this.parentId,
    this.authorLabel,
    required this.createdAt,
  });

  final String id;
  final String body;

  /// 부모 댓글 id(정본 comments 의 최대 2-depth 답글). 현재 UI는 평면 표시라
  /// 렌더링에 쓰지 않지만, 향후 답글 표시를 위해 모델에 실어 둔다.
  final String? parentId;

  final String? authorLabel;
  final DateTime createdAt;

  String get authorName => communityAuthorName(authorLabel, null);

  factory CommunityComment.fromMap(Map<String, dynamic> m) {
    return CommunityComment(
      id: m['id'] as String,
      // 정본 comments 는 content, legacy community_comments 는 body(브리지 행은
      // content 도 채워짐) — 어느 쪽 행이 와도 관대하게 읽는다.
      body: _pickText(m, const <String>['content', 'body']) ?? '',
      parentId: m['parent_id'] as String?,
      authorLabel: m['author_label'] as String?,
      createdAt: parseTime(m['created_at']),
    );
  }
}

/// 게시글 종류 — 댓글/반응 대상 구분(community_comments.post_type 등).
enum CommunityPostType {
  board,
  shortform;

  String get code => this == CommunityPostType.board ? 'board' : 'shortform';

  /// 이 타입의 댓글 원천 테이블(v16 정본 전환) — 게시판은 정본 `comments`,
  /// 숏폼은 기존 `community_comments`(post_type='shortform') 유지.
  String get commentsTable =>
      this == CommunityPostType.board ? 'comments' : 'community_comments';
}

/// 내 활동(읽기): 내가 쓴 글·좋아요·스크랩한 글.
class MyActivity {
  const MyActivity({
    this.myPosts = const <BoardPost>[],
    this.liked = const <BoardPost>[],
    this.scrapped = const <BoardPost>[],
  });

  final List<BoardPost> myPosts;
  final List<BoardPost> liked;
  final List<BoardPost> scrapped;

  bool get isEmpty => myPosts.isEmpty && liked.isEmpty && scrapped.isEmpty;
}
