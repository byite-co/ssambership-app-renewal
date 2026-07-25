import '../../../shared/errors/app_error.dart';
import 'community_models.dart';

/// 게시판 작성 author_role 정본 게이트 (신규 오염 차단).
///
/// 배경: 앱 INSERT 가 author_role 을 보내지 않아 DB DEFAULT('mentor')가 채워져
/// 학생 글이 mentor 로 오염됐다. 이 게이트는 앱 경로에서 오염을 차단한다.
///
/// 역할 정본 = "현재 Auth user ID 와 일치하는 **본인 public.users 행**의 role
/// SELECT 결과" 하나뿐이다. 토큰 user_metadata/app_metadata·이전 화면 전달값·
/// 로컬 저장 role·AuthService.currentRole 캐시 단독값은 정본이 아니다.
/// 어떤 실패에서도 mentor 를 기본값(fallback)으로 쓰지 않는다 — 전부 fail-closed
/// (구조화 오류로 중단, INSERT 0회).
///
/// 저장 성공 후에도 반환 행의 author_id/author_role 을 재검증해, 불일치면
/// 성공으로 처리하지 않는다(서버 DEFAULT·트리거 개입 감지).

/// 본인 users 행 조회(`select id, role ... where id = userId` 결과 행 목록).
typedef OwnUserRowsFetcher = Future<List<Map<String, dynamic>>> Function(
    String userId);

/// community_posts INSERT 실행(반환 = `.select().single()` 행).
typedef BoardPostInserter = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> payload);

/// 앱 게시판 작성이 지원하는 역할(exact 문자열 비교 — 부분 문자열 의미 없음).
const Set<String> kSupportedBoardAuthorRoles = <String>{'student', 'mentor'};

/// 작성 직전 확정된 작성자 정본(Auth uid + users 행 role).
class BoardAuthorIdentity {
  const BoardAuthorIdentity({required this.userId, required this.role});

  final String userId;

  /// 'student' 또는 'mentor' 만 유효(생성 경로가 보장).
  final String role;
}

/// 역할 정본 확정 — 실패는 전부 throw(호출부는 INSERT 를 시작하지 않는다).
Future<BoardAuthorIdentity> resolveBoardAuthorIdentity({
  required String? authUserId,
  required OwnUserRowsFetcher fetchOwnUserRows,
}) async {
  // 미로그인: 조회조차 하지 않는다.
  if (authUserId == null || authUserId.isEmpty) {
    throw const AppError('로그인이 필요해요.');
  }
  late final List<Map<String, dynamic>> rows;
  try {
    rows = await fetchOwnUserRows(authUserId);
  } catch (_) {
    // role SELECT 오류 — 어떤 role 도 추정하지 않는다.
    throw const AppError('내 계정 정보를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
  }
  if (rows.isEmpty) {
    throw const AppError('계정 정보를 찾을 수 없어요. 다시 로그인해 주세요.');
  }
  if (rows.length != 1) {
    // 복수 행/비정상 반환 — 정본 판정 불가.
    throw const AppError('계정 정보가 올바르지 않아요. 다시 로그인해 주세요.');
  }
  final Map<String, dynamic> row = rows.first;
  final Object? idValue = row['id'];
  if (idValue is! String || idValue != authUserId) {
    // Auth uid 와 조회된 users.id 불일치 — 남의 행이거나 손상된 응답.
    throw const AppError('계정 정보가 일치하지 않아요. 다시 로그인해 주세요.');
  }
  final Object? roleValue = row['role'];
  if (roleValue is! String) {
    // null·비문자 role — fail-closed.
    throw const AppError('회원 유형을 확인하지 못했어요. 다시 로그인해 주세요.');
  }
  final String role = roleValue.trim();
  if (!kSupportedBoardAuthorRoles.contains(role)) {
    // unknown role·게시판 작성 미지원 role(admin 등) — 작성 중단.
    throw const AppError('현재 회원 유형으로는 게시판 글을 쓸 수 없어요.');
  }
  return BoardAuthorIdentity(userId: authUserId, role: role);
}

/// INSERT payload — author_role 을 항상 명시해 DB DEFAULT('mentor')에 의존하지
/// 않는다. 본문은 읽기 모델(content 우선·body 폴백)과 정합하도록 두 컬럼 동일.
Map<String, dynamic> buildBoardPostPayload({
  required String title,
  required String body,
  required String category,
  required BoardAuthorIdentity author,
}) {
  return <String, dynamic>{
    'title': title,
    'content': body,
    'body': body,
    'category': category,
    'author_id': author.userId,
    'author_role': author.role,
    'status': 'published',
  };
}

/// 저장 반환 행 재검증 — 불일치 필드명을 돌려준다(null = 정합).
String? boardPostReturnMismatch({
  required Map<String, dynamic> returned,
  required BoardAuthorIdentity author,
}) {
  if (returned['author_id'] != author.userId) return 'author_id';
  if (returned['author_role'] != author.role) return 'author_role';
  return null;
}

/// 게시판 글 작성 전체 흐름(정본 확정 → INSERT → 반환 행 재검증).
/// 순수 오케스트레이터 — 의존은 전부 주입이라 단위 테스트로 INSERT 호출 횟수까지
/// 고정할 수 있다.
Future<BoardPost> createBoardPostGated({
  required String? authUserId,
  required OwnUserRowsFetcher fetchOwnUserRows,
  required BoardPostInserter insert,
  required String title,
  required String body,
  required String category,
}) async {
  final BoardAuthorIdentity author = await resolveBoardAuthorIdentity(
    authUserId: authUserId,
    fetchOwnUserRows: fetchOwnUserRows,
  );
  final Map<String, dynamic> returned = await insert(buildBoardPostPayload(
    title: title,
    body: body,
    category: category,
    author: author,
  ));
  final String? mismatch =
      boardPostReturnMismatch(returned: returned, author: author);
  if (mismatch != null) {
    // 저장은 됐을 수 있으나 정합이 깨졌다 — 성공 토스트/이동 금지.
    throw const AppError('글 저장 결과가 요청과 달라 등록을 완료하지 못했어요. 목록을 새로고침해 확인해 주세요.');
  }
  return BoardPost.fromMap(returned);
}
