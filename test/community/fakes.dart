import 'package:ssambership_app/core/scan/picked_image.dart';
import 'package:ssambership_app/features/community/data/comments_gateway.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/data/community_read_repository.dart';
import 'package:ssambership_app/features/community/data/community_write_repository.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// "결과 미지정" 과 "명시적 null 결과" 를 구분하는 const 센티넬 —
/// `softDeleteResult ?? default` 로는 null 봉투 케이스를 만들 수 없기 때문.
class _Unset {
  const _Unset();
}

const _Unset _kUnset = _Unset();

/// 실제 DB·네트워크 대신 주입할 가짜 레포. 고정 데이터만 반환(Supabase 미접촉).
class FakeCommunityRead extends CommunityReadRepository {
  const FakeCommunityRead({
    this.boardsList = const <BoardPost>[],
    this.shortformsList = const <ShortformPost>[],
    this.commentsList = const <CommunityComment>[],
    this.activity = const MyActivity(),
  });

  final List<BoardPost> boardsList;
  final List<ShortformPost> shortformsList;
  final List<CommunityComment> commentsList;
  final MyActivity activity;

  /// 실제 repo 와 같은 페이지 계약: nextOffset 은 필터 전 행 수 기준(여긴 필터 없음).
  CommunityPage<T> _page<T>(List<T> all, int? limit, int offset) {
    final List<T> items;
    if (limit == null) {
      items = all;
    } else {
      final int start = offset.clamp(0, all.length);
      final int end = (offset + limit).clamp(0, all.length);
      items = all.sublist(start, end);
    }
    return CommunityPage<T>(
      items: items,
      rawCount: items.length,
      nextOffset: offset + items.length,
      hasMore: limit != null && items.length == limit,
    );
  }

  @override
  Future<CommunityPage<BoardPost>> boards(
      {String? category, int? limit, int offset = 0}) async {
    final List<BoardPost> all = category == null
        ? boardsList
        : boardsList.where((BoardPost p) => p.category == category).toList();
    return _page<BoardPost>(all, limit, offset);
  }

  @override
  Future<CommunityPage<ShortformPost>> shortforms(
      {int? limit, int offset = 0}) async {
    return _page<ShortformPost>(shortformsList, limit, offset);
  }

  @override
  Future<List<CommunityComment>> comments(CommunityPostType type, String postId,
          {int? limit, int offset = 0}) async =>
      commentsList;

  @override
  Future<Set<String>> myBoardReactionIds(String reactionType,
          {String? postId}) async =>
      <String>{};

  @override
  Future<Set<String>> myShortformReactionIds(String reactionType,
          {String? shortformId}) async =>
      <String>{};

  @override
  Future<MyActivity> myActivity() async => activity;
}

/// 반응·댓글·신고 쓰기를 삼키는 가짜 레포(호출 기록만).
/// [failReactions] 로 반응 토글 실패(서버 오류)를 흉내낼 수 있다(낙관적 롤백 검증용).
class FakeCommunityWrite extends CommunityWriteRepository {
  FakeCommunityWrite({this.uid});

  /// currentUserId 로 돌려줄 값(null=비로그인) — 소유권 UI 게이트 테스트용.
  final String? uid;

  int reactionCalls = 0;
  int commentCalls = 0;
  int reportCalls = 0;
  int postCalls = 0;
  int updateCalls = 0;
  int uploadImageCalls = 0;
  String? lastReportReason;
  String? lastReportTargetType;
  String? lastReportTargetId;
  CommunityPostType? lastCommentPostType;
  String? lastCommentParentId;
  String? lastPostTitle;
  String? lastPostBody;
  String? lastPostCategory;
  List<String>? lastPostImageRefs;
  String? lastUpdatePostId;
  String? lastUpdateTitle;
  String? lastUpdateBody;
  String? lastUpdateCategory;
  String? lastUpdateExpectedUpdatedAt;
  List<String>? lastUpdateImageRefs;

  /// createPost 로 들어온 멱등키 이력(재시도 시 같은 키가 유지되는지 검증용).
  final List<String> postIdempotencyKeys = <String>[];

  /// 숏폼 조회 기록 v2 로 들어온 (postId, eventKey) 이력 — 키 안정성 검증용.
  final List<String> shortformViewKeys = <String>[];
  String? lastShortformViewPostId;

  /// 숏폼 댓글 본인 삭제 호출 기록.
  int deleteCommentCalls = 0;
  String? lastDeletedCommentId;

  /// true 면 deleteMyShortformComment 가 호출 기록 후 throw.
  bool failDeleteComment = false;

  /// uploadPostImage 로 들어온 이미지 이력(업로드 횟수·중복 방지 검증용).
  final List<PickedImage> uploadedImages = <PickedImage>[];

  /// true 면 createPost 가 호출 기록 후 throw(재시도 경로 테스트).
  bool failPost = false;

  /// true 면 updatePost 가 호출 기록 후 throw(수정 실패 경로 테스트).
  bool failUpdate = false;

  /// true 면 uploadPostImage 가 throw(업로드 실패 시 RPC 미호출 검증용).
  bool failUpload = false;

  /// true 면 반응 토글이 호출 기록 후 throw(낙관적 상태 롤백 경로 테스트).
  bool failReactions = false;

  /// 반응 토글 호출 로그('like:on' 형식) — like/scrap 독립성 검증용.
  final List<String> reactionLog = <String>[];

  @override
  Future<void> toggleBoardReaction({
    required String postId,
    required String type,
    required bool on,
  }) async {
    reactionCalls++;
    reactionLog.add('$type:${on ? 'on' : 'off'}');
    if (failReactions) throw Exception('reaction failed');
  }

  @override
  Future<void> toggleShortformReaction({
    required String shortformId,
    required String type,
    required bool on,
  }) async {
    reactionCalls++;
    reactionLog.add('$type:${on ? 'on' : 'off'}');
    if (failReactions) throw Exception('reaction failed');
  }

  @override
  Future<CommunityComment> addComment({
    required CommunityPostType postType,
    required String postId,
    required String body,
    String? parentId,
  }) async {
    commentCalls++;
    lastCommentPostType = postType;
    lastCommentParentId = parentId;
    return CommunityComment(
      id: 'fake-comment',
      body: body,
      parentId: parentId,
      authorLabel: '나',
      createdAt: DateTime(2026, 7, 1),
    );
  }

  @override
  String? get currentUserId => uid;

  @override
  Future<BoardPost> createPost({
    required String title,
    required String body,
    required String category,
    required String idempotencyKey,
    List<String> imageRefs = const <String>[],
  }) async {
    postCalls++;
    lastPostTitle = title;
    lastPostBody = body;
    lastPostCategory = category;
    lastPostImageRefs = List<String>.of(imageRefs);
    postIdempotencyKeys.add(idempotencyKey);
    if (failPost) throw const AppError('등록에 실패했어요.');
    return BoardPost(
      id: 'fake-post',
      title: title,
      body: body,
      category: category,
      authorLabel: '나',
      authorRole: 'student',
      likeCount: 0,
      commentCount: 0,
      viewCount: 0,
      createdAt: DateTime(2026, 7, 1),
    );
  }

  @override
  Future<BoardPost> updatePost({
    required String postId,
    required String title,
    required String body,
    required String category,
    required String expectedUpdatedAt,
    required List<String> imageRefs,
  }) async {
    updateCalls++;
    lastUpdatePostId = postId;
    lastUpdateTitle = title;
    lastUpdateBody = body;
    lastUpdateCategory = category;
    lastUpdateExpectedUpdatedAt = expectedUpdatedAt;
    lastUpdateImageRefs = List<String>.of(imageRefs);
    if (failUpdate) throw const AppError('수정에 실패했어요.');
    return BoardPost(
      id: postId,
      title: title,
      body: body,
      category: category,
      authorLabel: '나',
      authorRole: 'student',
      likeCount: 0,
      commentCount: 0,
      viewCount: 0,
      createdAt: DateTime(2026, 7, 1),
    );
  }

  @override
  Future<String> uploadPostImage(PickedImage image) async {
    uploadImageCalls++;
    if (failUpload) throw const AppError('이미지를 올리지 못했어요. 잠시 후 다시 시도해 주세요.');
    uploadedImages.add(image);
    return 'community-post-images/fake-uid/${uploadedImages.length}_${image.fileName}';
  }

  @override
  Future<void> recordShortformView({
    required String postId,
    required String eventKey,
  }) async {
    lastShortformViewPostId = postId;
    shortformViewKeys.add(eventKey);
  }

  @override
  Future<void> deleteMyShortformComment(String commentId) async {
    deleteCommentCalls++;
    lastDeletedCommentId = commentId;
    if (failDeleteComment) throw const AppError('댓글 삭제에 실패했어요.');
  }

  @override
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
    String? description,
  }) async {
    reportCalls++;
    lastReportReason = reason;
    lastReportTargetType = targetType;
    lastReportTargetId = targetId;
  }
}

/// 댓글 원천 테이블 접근 통로의 기록형 가짜 — v16 정본 전환 계약 검증용.
/// 실제 레포지토리(read/write)에 주입해 어느 테이블에 어떤 필터/페이로드가
/// 전달되는지 확인한다(Supabase 미접촉).
class RecordingCommentsGateway extends CommentsGateway {
  RecordingCommentsGateway({
    this.userId,
    this.selectRows = const <Map<String, dynamic>>[],
    this.insertError,
  });

  /// currentUserId 로 돌려줄 값(null=비로그인).
  final String? userId;

  /// selectComments 가 돌려줄 행.
  final List<Map<String, dynamic>> selectRows;

  /// 지정 시 insertComment 가 이 오류를 던진다(서버 트리거 거부 흉내).
  final Object? insertError;

  String? lastSelectTable;
  Map<String, Object>? lastSelectFilters;
  int? lastSelectLimit;
  int? lastSelectOffset;
  String? lastInsertTable;
  Map<String, dynamic>? lastInsertValues;

  /// softDeleteShortformComment 가 돌려줄 jsonb(성공/실패 봉투). 미지정(_kUnset)
  /// 이면 기본 성공 봉투를, 명시 설정 시 그 값(널 포함)을 그대로 돌려준다.
  Object? softDeleteResult = _kUnset;
  Object? softDeleteError;
  final List<String> softDeletedCommentIds = <String>[];

  @override
  String? get currentUserId => userId;

  @override
  Future<List<Map<String, dynamic>>> selectComments({
    required String table,
    required Map<String, Object> filters,
    int? limit,
    int offset = 0,
  }) async {
    lastSelectTable = table;
    lastSelectFilters = filters;
    lastSelectLimit = limit;
    lastSelectOffset = offset;
    return selectRows;
  }

  @override
  Future<Map<String, dynamic>> insertComment({
    required String table,
    required Map<String, dynamic> values,
  }) async {
    lastInsertTable = table;
    lastInsertValues = values;
    final Object? err = insertError;
    if (err != null) throw err;
    // 서버가 채우는 필드(id/created_at)를 더해 생성된 행처럼 돌려준다.
    return <String, dynamic>{
      ...values,
      'id': 'new-comment',
      'created_at': '2026-07-21T00:00:00Z',
    };
  }

  @override
  Future<Object?> softDeleteShortformComment(String commentId) async {
    softDeletedCommentIds.add(commentId);
    final Object? err = softDeleteError;
    if (err != null) throw err;
    if (identical(softDeleteResult, _kUnset)) {
      return <String, dynamic>{
        'ok': true,
        'contract_version': 1,
        'comment_id': commentId,
        'idempotent_hit': false,
      };
    }
    return softDeleteResult; // 명시적으로 넘긴 값(널 포함)을 그대로 반환.
  }
}

/// 샘플 데이터 빌더.
BoardPost sampleBoard({
  String id = 'b1',
  String title = '게시판 제목',
  String category = 'study',
  String authorRole = 'student',
  String? authorId,
  String? updatedAtRaw,
  List<String> imageRefs = const <String>[],
  int likeCount = 3,
  int commentCount = 7,
  int viewCount = 100,
}) {
  return BoardPost(
    id: id,
    title: title,
    body: '본문 내용입니다.',
    category: category,
    authorLabel: '익명1',
    authorRole: authorRole,
    authorId: authorId,
    updatedAtRaw: updatedAtRaw,
    imageRefs: imageRefs,
    likeCount: likeCount,
    commentCount: commentCount,
    viewCount: viewCount,
    createdAt: DateTime(2026, 6, 28),
  );
}

ShortformPost sampleShortform({
  String id = 's1',
  String title = '숏폼 제목',
  String? videoUrl, // null=미디어 없음, 지정 시 해석·재생 경로 테스트
  String? thumbnailUrl, // 기본 null(웹 finalize 현재 계약) — legacy 행만 지정
  int likeCount = 5,
  int viewCount = 69,
}) {
  return ShortformPost(
    id: id,
    title: title,
    description: '숏폼 설명',
    category: 'study',
    authorLabel: '멘토쌤',
    authorRole: 'mentor',
    thumbnailUrl: thumbnailUrl,
    videoUrl: videoUrl,
    likeCount: likeCount,
    viewCount: viewCount,
    createdAt: DateTime(2026, 6, 28),
  );
}

CommunityComment sampleComment({
  String id = 'c1',
  String body = '좋은 글이에요.',
  String? parentId,
  String? authorId,
}) {
  return CommunityComment(
    id: id,
    body: body,
    parentId: parentId,
    authorLabel: '익명2',
    authorId: authorId,
    createdAt: DateTime(2026, 6, 29),
  );
}
