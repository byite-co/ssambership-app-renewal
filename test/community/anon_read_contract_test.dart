import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/data/community_read_repository.dart';
import 'package:ssambership_app/features/community/data/user_blocks_repository.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// D-3 익명(게스트) 읽기 계약 회귀 가드.
///
/// 게스트는 Supabase 세션이 없다. 커뮤니티 열람은 anon key 로만 이뤄지며,
/// 로그인 사용자와 **완전히 같은 SQL** 을 발행한다(개인화는 uid 가드가 걸린
/// 별도 호출로만 추가된다). 이 불변식이 깨지면 게스트 세션에서만 재현되는
/// 오류가 되어 일반 네트워크 실패와 구분되지 않는다.
///
/// boards()/shortforms() 는 SupabaseInit.clientOrNull 을 직접 읽어 주입 seam 이
/// 없다. 그래서 쿼리 모양은 소스 수준에서 잠근다 — 저장소가 이미 쓰는 방식이다
/// (test/push/firebase_free_test.dart 가 같은 패턴).
const String _repoPath = 'lib/features/community/data/community_read_repository.dart';

String _source() => File(_repoPath).readAsStringSync();

/// 주어진 메서드 본문만 잘라낸다(다음 `Future<` 선언 직전까지).
String _method(String src, String signatureStart) {
  final int i = src.indexOf(signatureStart);
  expect(i, greaterThanOrEqualTo(0), reason: '$signatureStart 를 찾지 못했다');
  final int next = src.indexOf('\n  /// ', i + signatureStart.length);
  return next == -1 ? src.substring(i) : src.substring(i, next);
}

void main() {
  group('D-3 쿼리 모양 — 게시판 목록(A1)', () {
    late String body;
    setUpAll(() => body = _method(_source(), 'Future<CommunityPage<BoardPost>> boards('));

    test('정본 테이블은 community_posts', () {
      expect(body.contains("from('community_posts')"), isTrue);
    });

    test("select('*') 를 좁히지 않는다", () {
      // 차단 필터가 뷰모델에 없는 raw author_id 로 동작한다. projection 이
      // author_id 를 빠뜨리면 크래시가 아니라 '차단이 조용히 풀리는' fail-open 이 된다.
      expect(body.contains("select('*')"), isTrue,
          reason: "select('*') 가 사라졌다 — 차단 필터가 fail-open 된다");
    });

    test('임베드(조인)를 추가하지 않는다', () {
      // PostgREST 임베드는 임베드 대상 테이블의 anon SELECT 도 요구한다.
      expect(RegExp(r"select\('\*\s*,").hasMatch(body), isFalse,
          reason: '임베드는 게스트 세션에서만 401/403 이 된다');
    });

    test('published 필터와 최신순 정렬을 유지한다', () {
      expect(body.contains("eq('status', 'published')"), isTrue);
      expect(body.contains("order('created_at', ascending: false)"), isTrue);
    });

    test('로그인 여부로 분기하지 않는다(anon 과 로그인이 동일 SQL)', () {
      expect(body.contains('_uid'), isFalse,
          reason: '개인화가 필요하면 uid 가드가 걸린 별도 호출로 추가할 것');
      expect(RegExp(r'\bcurrentUser\b').hasMatch(body), isFalse);
    });

    test('오프셋은 필터 전 행 수(rawCount)로 전진한다', () {
      expect(body.contains('rawCount: rows.length'), isTrue);
    });
  });

  group('D-3 쿼리 모양 — 숏폼 목록(A2)', () {
    late String body;
    setUpAll(() =>
        body = _method(_source(), 'Future<CommunityPage<ShortformPost>> shortforms('));

    test('정본 테이블은 shortform_posts', () {
      expect(body.contains("from('shortform_posts')"), isTrue);
    });

    test("select('*') 를 좁히지 않는다", () {
      expect(body.contains("select('*')"), isTrue);
    });

    test('임베드(조인)를 추가하지 않는다', () {
      expect(RegExp(r"select\('\*\s*,").hasMatch(body), isFalse);
    });

    test('published 필터와 최신순 정렬을 유지한다', () {
      expect(body.contains("eq('status', 'published')"), isTrue);
      expect(body.contains("order('created_at', ascending: false)"), isTrue);
    });

    test('로그인 여부로 분기하지 않는다', () {
      expect(body.contains('_uid'), isFalse);
    });
  });

  group('가드 자기-검증 — 위 단언이 공허하지 않다', () {
    test('_method 는 해당 메서드만 잘라낸다(파일 전체가 아니다)', () {
      final String src = _source();
      final String boards =
          _method(src, 'Future<CommunityPage<BoardPost>> boards(');

      expect(boards.length, lessThan(src.length));
      // 다른 메서드가 섞여 들어오지 않는다.
      expect(boards.contains("from('shortform_posts')"), isFalse);
      expect(boards.contains('myActivity'), isFalse);
    });

    test('파일 전체에는 _uid 가 존재한다(= 분기 단언이 슬라이싱 덕분에 성립)', () {
      // 이게 없으면 '_uid 없음' 단언이 잘못된 슬라이스 때문에 통과한 것이다.
      expect(_source().contains('_uid'), isTrue);
    });

    test('탐지 로직은 실제 위반 문자열에 반응한다', () {
      const String narrowed = "select('id, title')";
      const String embedded = "select('*, users(nickname)')";
      expect(narrowed.contains("select('*')"), isFalse);
      expect(RegExp(r"select\('\*\s*,").hasMatch(embedded), isTrue);
    });
  });

  group('D-3 — 읽기 경로에 RPC 를 쓰지 않는다', () {
    test('community_read_repository 에 .rpc( 호출이 없다', () {
      // 조회수 RPC 2건은 write 레포에 있고 실패가 침묵이라, anon EXECUTE 권한이
      // UI 로 증명된 적이 없다. 읽기를 RPC 로 바꾸면 게스트에서 조용히 죽는다.
      expect(_source().contains('.rpc('), isFalse);
    });
  });

  group('게스트 단축회로 — 네트워크 0회', () {
    // 이 테스트들은 SupabaseInit 미초기화 상태(clientOrNull == null)로 돈다.
    // = 세션 없는 게스트와 같은 조건.
    test('myBlockedIds → 빈 집합(쿼리 미발행)', () async {
      expect(await const UserBlocksRepository().myBlockedIds(), isEmpty);
    });

    test('myBlockedUsers → 빈 목록', () async {
      expect(await const UserBlocksRepository().myBlockedUsers(), isEmpty);
    });

    test('myBoardReactionIds → 빈 집합', () async {
      expect(
          await const CommunityReadRepository().myBoardReactionIds('like'),
          isEmpty);
    });

    test('myShortformReactionIds → 빈 집합', () async {
      expect(
          await const CommunityReadRepository().myShortformReactionIds('like'),
          isEmpty);
    });

    test('myActivity → 빈 활동(로그인 유도는 화면 몫)', () async {
      final MyActivity a = await const CommunityReadRepository().myActivity();
      expect(a.isEmpty, isTrue);
    });

    test('차단 시도 → notLoggedIn (INSERT 미시도)', () async {
      final BlockResult r = await const UserBlocksRepository()
          .blockAuthorOf(table: 'community_posts', contentId: 'p1');
      expect(r, BlockResult.notLoggedIn);
    });
  });

  group('백엔드 미연결 시 목록 조회는 조용히 성공하지 않는다', () {
    test('boards() 는 AppError 를 던진다(빈 목록 위장 금지)', () async {
      await expectLater(
        const CommunityReadRepository().boards(),
        throwsA(isA<AppError>()),
      );
    });

    test('shortforms() 는 AppError 를 던진다', () async {
      await expectLater(
        const CommunityReadRepository().shortforms(),
        throwsA(isA<AppError>()),
      );
    });
  });

  group('author_id 계약 — 내부 식별자는 뷰모델에 새지 않는다', () {
    const String uuid = '3f2b1c9e-0000-4aaa-bbbb-cccccccccccc';

    test('BoardPost 는 author_id 를 표면에 두지 않는다', () {
      final BoardPost p = BoardPost.fromMap(<String, dynamic>{
        'id': 'p1',
        'title': '제목',
        'content': '본문',
        'author_id': uuid,
        'author_role': 'student',
        'created_at': '2026-07-01T00:00:00Z',
      });
      expect(p.toString().contains(uuid), isFalse);
      expect(p.authorName, isNot(contains(uuid)));
    });

    test('ShortformPost 도 마찬가지', () {
      final ShortformPost s = ShortformPost.fromMap(<String, dynamic>{
        'id': 's1',
        'title': '숏폼',
        'author_id': uuid,
        'created_at': '2026-07-01T00:00:00Z',
      });
      expect(s.toString().contains(uuid), isFalse);
    });

    test('작성자 표기는 한글 라벨로만 수렴한다', () {
      expect(communityAuthorName(null, 'mentor'), '멘토');
      expect(communityAuthorName(null, 'student'), '학생');
      expect(communityAuthorName(null, null), '쌤버십 회원');
      expect(communityAuthorName(null, 'unknown_role'), isNot(contains('_')));
    });
  });
}
