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

    test('정본 소스는 api_web_v1.community_posts_v1 뷰(anon 허용)', () {
      expect(body.contains(".schema('api_web_v1')"), isTrue);
      expect(body.contains("from('community_posts_v1')"), isTrue);
      // 베이스 테이블 직접 조회로 회귀하지 않는다.
      expect(body.contains("from('community_posts')"), isFalse);
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
    const String modelsPath = 'lib/features/community/data/community_models.dart';

    // ★ toString() 으로 검사하지 않는다. 두 모델 모두 toString 을 override 하지
    //   않아 Object.toString() = "Instance of 'BoardPost'" 가 나오고, 그러면
    //   모델에 authorId 를 추가해도 단언이 통과하는 공허한 가드가 된다.
    //   대신 (1) 공개 문자열 필드를 하나씩 대조하고 (2) 소스에 필드 선언이
    //   생기지 않는지 잠근다.

    test('BoardPost 의 어떤 공개 문자열 필드에도 author_id 가 실리지 않는다', () {
      final BoardPost p = BoardPost.fromMap(<String, dynamic>{
        'id': 'p1',
        'title': '제목',
        'content': '본문',
        'author_id': uuid,
        'author_role': 'student',
        'created_at': '2026-07-01T00:00:00Z',
      });
      final List<String?> surface = <String?>[
        p.id,
        p.title,
        p.body,
        p.category,
        p.authorLabel,
        p.authorRole,
        p.authorName,
      ];
      for (final String? v in surface) {
        expect(v, isNot(contains(uuid)));
      }
    });

    test('ShortformPost 도 마찬가지', () {
      final ShortformPost s = ShortformPost.fromMap(<String, dynamic>{
        'id': 's1',
        'title': '숏폼',
        'author_id': uuid,
        'author_role': 'mentor',
        'created_at': '2026-07-01T00:00:00Z',
      });
      final List<String?> surface = <String?>[
        s.id,
        s.title,
        s.description,
        s.category,
        s.authorLabel,
        s.authorRole,
        s.thumbnailUrl,
        s.videoUrl,
        s.authorName,
      ];
      for (final String? v in surface) {
        expect(v, isNot(contains(uuid)));
      }
    });

    test('authorId 는 내부 게이트 전용 — UI 가 렌더하지 않는다(소스 잠금)', () {
      // Build 13 수정 기능이 소유권 UI 게이트(내 글에만 수정 노출)를 위해
      // BoardPost.authorId 를 내부 필드로 승격했다(리뷰 승인 계약 변경).
      // 잠금의 목적은 유지된다: UUID 를 **화면에 렌더**하는 코드가 없어야 한다.
      // 위 표면(runtime) 대조가 공개 문자열 필드를 지키고, 여기서는 커뮤니티
      // UI 코드가 authorId 를 텍스트로 보간하지 않음을 소스로 잠근다.
      final List<File> uiFiles = Directory('lib/features/community/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
      expect(uiFiles, isNotEmpty);
      for (final File f in uiFiles) {
        final String src = f.readAsStringSync();
        // Text(...authorId...)·문자열 보간($...authorId) 금지 — 비교 연산만 허용.
        expect(RegExp(r'Text\([^)]*authorId').hasMatch(src), isFalse,
            reason: '${f.path} 가 authorId 를 렌더한다');
        expect(RegExp(r'\$\{?[a-zA-Z._]*authorId').hasMatch(src), isFalse,
            reason: '${f.path} 가 authorId 를 문자열에 보간한다');
      }
      // ShortformPost 는 여전히 author_id 를 승격하지 않는다(수정 기능 없음).
      // ★ ShortformPost **클래스 본문만** 검사한다 — 파일 뒤쪽 CommunityComment 는
      //   본인 댓글 소프트삭제 소유권 게이트(§F/§10.6)를 위해 authorId 를 내부 필드로
      //   승격했고(리뷰 승인 계약), 그 필드는 위 소스 잠금 루프가 UI 미노출을 보증한다.
      final String models = File(modelsPath).readAsStringSync();
      final int idx = models.indexOf('class ShortformPost');
      expect(idx, greaterThan(0));
      final int nextClass = models.indexOf('\nclass ', idx + 1);
      final String shortformBody =
          nextClass > idx ? models.substring(idx, nextClass) : models.substring(idx);
      expect(shortformBody.contains('authorId'), isFalse,
          reason: 'ShortformPost 에 authorId 가 생겼다');
    });

    test('가드 자기-검증 — 위 대조가 실제로 UUID 를 잡아낸다', () {
      // 필드 하나라도 uuid 를 담으면 같은 방식으로 탐지된다는 증명.
      final BoardPost leaky = BoardPost.fromMap(<String, dynamic>{
        'id': 'p1',
        'title': uuid, // 유출을 흉내낸 값
        'created_at': '2026-07-01T00:00:00Z',
      });
      expect(leaky.title, contains(uuid));
    });

    test('작성자 표기는 한글 라벨로만 수렴한다', () {
      expect(communityAuthorName(null, 'mentor'), '멘토');
      expect(communityAuthorName(null, 'student'), '학생');
      expect(communityAuthorName(null, null), '쌤버십 회원');
      expect(communityAuthorName(null, 'unknown_role'), isNot(contains('_')));
    });
  });
}
