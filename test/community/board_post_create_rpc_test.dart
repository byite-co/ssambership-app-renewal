import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/board_post_create_gateway.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/ui/board/board_write_screen.dart';
import 'package:ssambership_app/features/community/ui/widgets/content_policy_gate.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

import 'fakes.dart';

/// S3-D 게시판 글 작성 RPC 계약.
///
/// 운영 DB 는 community_posts 에 authenticated SELECT 만 준다(INSERT 권한·
/// policy 없음). 작성은 api_app_v1.community_post_create 단일 경로이고, 앱은
/// 직접 INSERT 도 보상 DELETE 도 하지 않는다. 운영 RPC 를 실제로 호출하지
/// 않고(전부 주입 seam), 계약 표면만 고정한다.

const String _uid = 'auth-uid-0001';
const String _postId = '3f1a9b2c-1111-4222-8333-444455556666';
const String _key = '9a8b7c6d-5555-4444-8333-222211110000';

/// 서버가 저장한 정본 행(재조회 결과) 기본값.
Map<String, dynamic> _row({String id = _postId}) => <String, dynamic>{
      'id': id,
      'title': '오답노트 공유',
      'content': '이렇게 정리했어요. 충분히 긴 본문입니다.',
      'category': 'study',
      'author_label': '쌤버십 사용자',
      'author_role': 'student',
      'like_count': 0,
      'comment_count': 0,
      'view_count': 0,
      'created_at': '2026-08-02T00:00:00Z',
    };

class _Harness {
  _Harness({
    this.authUserId = _uid,
    this.envelope,
    this.rpcError,
    List<Map<String, dynamic>>? rows,
    this.fetchError,
  }) : _rows = rows;

  final String? authUserId;
  final Object? envelope;
  final Object? rpcError;
  final List<Map<String, dynamic>>? _rows;
  final Object? fetchError;

  int rpcCalls = 0;
  int fetchCalls = 0;
  Map<String, dynamic>? lastParams;
  String? fetchedId;

  Future<BoardPost> run({String key = _key}) {
    return createBoardPostViaRpc(
      authUserId: authUserId,
      title: '오답노트 공유',
      body: '이렇게 정리했어요. 충분히 긴 본문입니다.',
      category: 'study',
      idempotencyKey: key,
      callRpc: (Map<String, dynamic> params) async {
        rpcCalls++;
        lastParams = params;
        if (rpcError != null) throw rpcError!;
        return envelope ??
            <String, dynamic>{
              'ok': true,
              'post_id': _postId,
              'idempotent_replay': false,
              'contract_version': 1,
            };
      },
      fetchPostById: (String postId) async {
        fetchCalls++;
        fetchedId = postId;
        if (fetchError != null) throw fetchError!;
        return _rows ?? <Map<String, dynamic>>[_row()];
      },
    );
  }
}

Future<Object?> _catch(Future<void> Function() run) async {
  try {
    await run();
    return null;
  } catch (e) {
    return e;
  }
}

void main() {
  group('계약 표면 — schema · 함수명 · 파라미터', () {
    test('스키마는 api_app_v1, 함수명은 community_post_create', () {
      expect(kBoardPostCreateSchema, 'api_app_v1');
      expect(kBoardPostCreateFunction, 'community_post_create');
    });

    test('params 키 집합이 서버 frozen signature 와 정확히 일치한다', () {
      final Map<String, dynamic> p = buildBoardPostCreateParams(
        title: 't',
        body: 'b',
        category: 'study',
        idempotencyKey: _key,
      );
      // 이름이 하나라도 다르면 PostgREST 가 함수를 찾지 못한다(PGRST202).
      expect(
          p.keys.toSet(),
          <String>{
            'p_title',
            'p_body',
            'p_category',
            'p_idempotency_key',
            'p_image_refs',
            'p_status',
          });
    });

    test('status 는 published, image_refs 기본값은 빈 배열', () {
      final Map<String, dynamic> p = buildBoardPostCreateParams(
        title: 't',
        body: 'b',
        category: 'study',
        idempotencyKey: _key,
      );
      expect(p['p_status'], 'published');
      expect(p['p_image_refs'], isA<List<String>>());
      expect(p['p_image_refs'], isEmpty);
      expect(kBoardPostCreateStatus, 'published');
    });

    test('입력값은 그대로 전달한다(앱이 임의 가공하지 않는다)', () {
      final Map<String, dynamic> p = buildBoardPostCreateParams(
        title: '제목',
        body: '본문',
        category: 'career',
        idempotencyKey: _key,
      );
      expect(p['p_title'], '제목');
      expect(p['p_body'], '본문');
      expect(p['p_category'], 'career');
      expect(p['p_idempotency_key'], _key);
    });

    test('실제 호출도 같은 params 로 나간다', () async {
      final _Harness h = _Harness();
      await h.run();
      expect(h.rpcCalls, 1);
      expect(h.lastParams!['p_status'], 'published');
      expect(h.lastParams!['p_image_refs'], isEmpty);
      expect(h.lastParams!['p_idempotency_key'], _key);
    });
  });

  group('멱등키 — UUID v4', () {
    test('UUID v4 형식(version 4 · variant 10x)', () {
      final RegExp v4 = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      for (int i = 0; i < 50; i++) {
        expect(v4.hasMatch(newBoardPostIdempotencyKey()), isTrue);
      }
    });

    test('호출마다 새 키(새 작성 작업 = 새 키)', () {
      final Set<String> keys = <String>{
        for (int i = 0; i < 200; i++) newBoardPostIdempotencyKey(),
      };
      expect(keys.length, 200);
    });

    test('빈 멱등키는 RPC 를 호출하지 않는다(중복 글 방지 — fail-closed)',
        () async {
      final _Harness h = _Harness();
      final Object? e = await _catch(() => h.run(key: '   '));
      expect(e, isA<AppError>());
      expect(h.rpcCalls, 0);
    });
  });

  group('성공 경로', () {
    test('신규 생성 → post_id 확인 후 저장 행을 조회해 BoardPost 반환', () async {
      final _Harness h = _Harness();
      final BoardPost p = await h.run();
      expect(h.rpcCalls, 1);
      expect(h.fetchCalls, 1);
      expect(h.fetchedId, _postId); // 서버가 준 post_id 로만 조회한다
      expect(p.id, _postId);
      expect(p.title, '오답노트 공유');
      expect(p.authorRole, 'student');
    });

    test('idempotent_replay=true 도 정상 성공(재시도 수렴)', () async {
      final _Harness h = _Harness(envelope: <String, dynamic>{
        'ok': true,
        'post_id': _postId,
        'idempotent_replay': true,
        'contract_version': 1,
      });
      final BoardPost p = await h.run();
      expect(p.id, _postId);
      expect(h.fetchCalls, 1);
    });

    test('idempotent_replay 필드가 없어도 성공(선택 필드)', () async {
      final _Harness h = _Harness(envelope: <String, dynamic>{
        'ok': true,
        'post_id': _postId,
      });
      final BoardPost p = await h.run();
      expect(p.id, _postId);
    });

    test('봉투 파서가 replay 플래그를 그대로 읽는다', () {
      final BoardPostCreateResult r =
          parseBoardPostCreateEnvelope(<String, dynamic>{
        'ok': true,
        'post_id': _postId,
        'idempotent_replay': true,
      });
      expect(r.postId, _postId);
      expect(r.idempotentReplay, isTrue);
    });
  });

  group('malformed success — fail-closed', () {
    Future<void> expectMalformed(Object? envelope) async {
      final _Harness h = _Harness(envelope: envelope);
      final Object? e = await _catch(() => h.run());
      expect(e, isA<AppError>(), reason: '계약 밖 응답: $envelope');
      expect(h.fetchCalls, 0, reason: '성공이 아니면 조회하지 않는다');
    }

    test('Map 이 아닌 응답', () => expectMalformed('ok'));
    test('ok 누락', () => expectMalformed(<String, dynamic>{'post_id': _postId}));
    test(
        'ok 가 bool 이 아님',
        () => expectMalformed(
            <String, dynamic>{'ok': 'true', 'post_id': _postId}));
    test('ok=true 인데 post_id 누락',
        () => expectMalformed(<String, dynamic>{'ok': true}));
    test(
        'post_id 가 빈 문자열',
        () =>
            expectMalformed(<String, dynamic>{'ok': true, 'post_id': '   '}));
    test(
        'post_id 가 문자열이 아님',
        () => expectMalformed(<String, dynamic>{'ok': true, 'post_id': 123}));
    test(
        'idempotent_replay 가 bool 이 아님',
        () => expectMalformed(<String, dynamic>{
              'ok': true,
              'post_id': _postId,
              'idempotent_replay': 'yes',
            }));

    test('성공 후 조회가 0행이면 성공 처리하지 않는다', () async {
      final _Harness h = _Harness(rows: <Map<String, dynamic>>[]);
      expect(await _catch(() => h.run()), isA<AppError>());
    });

    test('성공 후 조회 행 id 가 다르면 성공 처리하지 않는다', () async {
      final _Harness h =
          _Harness(rows: <Map<String, dynamic>>[_row(id: 'other-id')]);
      expect(await _catch(() => h.run()), isA<AppError>());
    });

    test('성공 후 조회가 실패하면 성공 처리하지 않는다', () async {
      final _Harness h = _Harness(fetchError: Exception('network'));
      expect(await _catch(() => h.run()), isA<AppError>());
    });

    test('RPC 전송 자체가 실패하면 성공 처리하지 않는다(예외를 삼키지 않는다)',
        () async {
      final _Harness h = _Harness(rpcError: Exception('network down'));
      expect(await _catch(() => h.run()), isNotNull);
      expect(h.fetchCalls, 0);
    });
  });

  group('서버 오류 코드 → 한글 문구', () {
    const List<String> codes = <String>[
      'AUTH_REQUIRED',
      'ROLE_NOT_ALLOWED',
      'ROLE_NOT_MENTOR',
      'MENTOR_NOT_APPROVED',
      'ACCOUNT_BANNED',
      'ACCOUNT_SUSPENDED',
      'ACCOUNT_DELETION_IN_PROGRESS',
      'ACCOUNT_NOT_ACTIVE',
      'TITLE_REQUIRED',
      'CATEGORY_INVALID',
      'BODY_TOO_SHORT',
      'IMAGE_COUNT_EXCEEDED',
      'IMAGE_MIME_NOT_ALLOWED',
      'IMAGE_SIZE_EXCEEDED',
      'IMAGE_REF_INVALID',
      'IMAGE_NOT_OWNED',
      'IMAGE_OBJECT_NOT_FOUND',
    ];

    test('모든 계약 코드가 한글 문구로 매핑된다', () {
      for (final String code in codes) {
        final AppError e = boardPostCreateError(code);
        expect(e.userMessage, isNotEmpty, reason: code);
        // 서버 원문·코드·SQL·UUID 를 화면 문구에 싣지 않는다.
        expect(e.userMessage.contains(code), isFalse, reason: code);
        // 코드꼴 토큰(SCREAMING_SNAKE)이 새어 나오지 않는지 — 파일 확장자 같은
        // 일반 영문 단어(JPG·WEBP)는 안내 문구의 정상 구성 요소다.
        expect(RegExp(r'[A-Z][A-Z0-9]*_[A-Z0-9_]*').hasMatch(e.userMessage),
            isFalse,
            reason: '$code 문구에 서버 코드가 섞였다: ${e.userMessage}');
      }
    });

    test('상황별로 서로 다른 안내를 준다(뭉뚱그리지 않는다)', () {
      expect(boardPostCreateError('AUTH_REQUIRED').userMessage,
          isNot(boardPostCreateError('TITLE_REQUIRED').userMessage));
      expect(boardPostCreateError('BODY_TOO_SHORT').userMessage,
          isNot(boardPostCreateError('CATEGORY_INVALID').userMessage));
      expect(boardPostCreateError('ACCOUNT_BANNED').userMessage,
          isNot(boardPostCreateError('ACCOUNT_SUSPENDED').userMessage));
    });

    test('ACCOUNT_NOT_ACTIVE — 게시글 작성(create) 표면 명시 문구(공통 fallback 아님)', () {
      final AppError e = boardPostCreateError('ACCOUNT_NOT_ACTIVE');
      expect(e.userMessage, '현재 계정 상태에서는 이 기능을 사용할 수 없어요.');
      expect(e.userMessage, isNot(kBoardPostCreateMalformed.userMessage));
    });

    test('ACCOUNT_NOT_ACTIVE — 게시글 수정(update) 표면도 같은 쓰기 매퍼로 명시 문구', () {
      // 커뮤니티 게시글 쓰기(작성·수정)는 boardPostCreateError 를 단일 오류
      // 매퍼로 공유한다 — 수정 경로가 서버 RPC 로 확장돼도 이 명시 문구가 나온다.
      final AppError e = boardPostCreateError('ACCOUNT_NOT_ACTIVE');
      expect(e.userMessage, '현재 계정 상태에서는 이 기능을 사용할 수 없어요.');
      expect(e.userMessage, isNot(kBoardPostCreateMalformed.userMessage));
    });

    test('기존 계정 상태 문구 회귀 없음(BANNED/SUSPENDED/DELETION_IN_PROGRESS)', () {
      expect(boardPostCreateError('ACCOUNT_BANNED').userMessage,
          '이용이 제한된 계정이에요. 고객센터로 문의해 주세요.');
      expect(boardPostCreateError('ACCOUNT_SUSPENDED').userMessage,
          '일시 정지된 계정이에요. 정지 기간이 끝난 뒤 다시 시도해 주세요.');
      expect(boardPostCreateError('ACCOUNT_DELETION_IN_PROGRESS').userMessage,
          '탈퇴 처리 중에는 글을 쓸 수 없어요.');
      // 신규 명시 문구가 기존 계정 상태 문구를 대체하지 않는다.
      expect(boardPostCreateError('ACCOUNT_NOT_ACTIVE').userMessage,
          isNot(boardPostCreateError('ACCOUNT_DELETION_IN_PROGRESS').userMessage));
    });

    test('역할 계약(S3-C student+mentor) 수렴 전후 코드가 같은 문구로 묶인다', () {
      expect(boardPostCreateError('ROLE_NOT_ALLOWED').userMessage,
          boardPostCreateError('ROLE_NOT_MENTOR').userMessage);
    });

    test('미지의 IMAGE_* 는 첨부 안내로 수렴한다', () {
      expect(boardPostCreateError('IMAGE_SOMETHING_NEW').userMessage,
          boardPostCreateError('IMAGE_REF_INVALID').userMessage);
    });

    test('미지의 코드·비문자 코드는 공통 문구(fail-closed)', () {
      expect(boardPostCreateError('WAT').userMessage,
          kBoardPostCreateMalformed.userMessage);
      expect(boardPostCreateError(null).userMessage,
          kBoardPostCreateMalformed.userMessage);
      expect(boardPostCreateError(42).userMessage,
          kBoardPostCreateMalformed.userMessage);
    });

    test('ok=false 응답은 조회로 넘어가지 않는다', () async {
      final _Harness h = _Harness(envelope: <String, dynamic>{
        'ok': false,
        'code': 'BODY_TOO_SHORT',
        'contract_version': 1,
      });
      final Object? e = await _catch(() => h.run());
      expect(e, isA<AppError>());
      expect((e! as AppError).userMessage, contains('10자'));
      expect(h.fetchCalls, 0);
    });
  });

  group('anon 작성 불가', () {
    test('미로그인은 RPC 를 호출조차 하지 않는다', () async {
      for (final String? uid in <String?>[null, '']) {
        final _Harness h = _Harness(authUserId: uid);
        final Object? e = await _catch(() => h.run());
        expect(e, isA<AppError>());
        expect((e! as AppError).userMessage, '로그인이 필요해요.');
        expect(h.rpcCalls, 0);
        expect(h.fetchCalls, 0);
      }
    });
  });

  group('production 소스 가드', () {
    const String writeRepo =
        'lib/features/community/data/community_write_repository.dart';
    const String gateway =
        'lib/features/community/data/board_post_create_gateway.dart';
    const String screen =
        'lib/features/community/ui/board/board_write_screen.dart';

    List<String> productionDart() {
      return Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .map((File f) => f.path)
          .toList();
    }

    test('community_posts 직접 INSERT 가 production 코드에 0건', () {
      final RegExp insert =
          RegExp(r"from\(\s*'community_posts'\s*\)\s*\.\s*insert");
      for (final String path in productionDart()) {
        expect(insert.hasMatch(File(path).readAsStringSync()), isFalse,
            reason: '$path 에 community_posts 직접 INSERT 가 남아 있다');
      }
    });

    test('community_posts DELETE(보상 삭제 포함)가 production 코드에 0건', () {
      final RegExp del =
          RegExp(r"from\(\s*'community_posts'\s*\)\s*\.\s*delete");
      for (final String path in productionDart()) {
        expect(del.hasMatch(File(path).readAsStringSync()), isFalse,
            reason: '$path 에 community_posts DELETE 가 남아 있다');
      }
    });

    test('보상 삭제 잔재(심볼)가 production 코드에 0건', () {
      for (final String path in productionDart()) {
        final String src = File(path).readAsStringSync();
        expect(src.contains('deleteOwnPostForCompensation'), isFalse,
            reason: path);
        expect(src.contains('verifyCompensationDeleteReturn'), isFalse,
            reason: path);
        expect(src.contains('COMPENSATION_DELETE'), isFalse, reason: path);
      }
    });

    test('createPost 는 schema(api_app_v1).rpc 로만 나간다', () {
      final String src = File(writeRepo).readAsStringSync();
      expect(src.contains('schema(kBoardPostCreateSchema)'), isTrue);
      expect(src.contains('rpc(kBoardPostCreateFunction'), isTrue);
      // 스키마를 생략하면 public 으로 나가 함수를 찾지 못한다.
      expect(RegExp(r"_client\.rpc\(\s*'community_post_create'").hasMatch(src),
          isFalse);
    });

    test('게이트웨이가 public wrapper 를 임의로 만들지 않는다', () {
      final String src = File(gateway).readAsStringSync();
      expect(src.contains("'api_app_v1'"), isTrue);
      expect(src.contains("public.community_post_create"), isFalse);
    });

    test('작성 화면이 멱등키를 만들어 넘긴다', () {
      final String src = File(screen).readAsStringSync();
      expect(src.contains('newBoardPostIdempotencyKey()'), isTrue);
      expect(src.contains('idempotencyKey: operationKey'), isTrue);
    });
  });

  group('작성 화면 — 학생·멘토 UI 유지와 멱등 작업 키', () {
    setUp(() => ContentPolicyGate.agreedThisSession = true);

    testWidgets('작성 UI 는 역할로 분기하지 않는다(학생·멘토 동일 화면)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          MaterialApp(home: BoardWriteScreen(write: FakeCommunityWrite())));
      await tester.pumpAndSettle();
      // 카테고리 + 제목 + 내용 + 등록 — 역할별 숨김/비활성이 없다.
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('등록'), findsOneWidget);
    });

    testWidgets('제출 성공 시 UUID v4 멱등키가 1회 전달된다',
        (WidgetTester tester) async {
      final FakeCommunityWrite fake = FakeCommunityWrite();
      await tester.pumpWidget(MaterialApp(home: BoardWriteScreen(write: fake)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '제목');
      await tester.enterText(find.byType(TextField).at(1), '충분히 긴 본문입니다.');
      await tester.tap(find.text('등록'));
      await tester.pumpAndSettle();

      expect(fake.postCalls, 1);
      expect(fake.postIdempotencyKeys, hasLength(1));
      expect(
          RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
              .hasMatch(fake.postIdempotencyKeys.single),
          isTrue);
    });

    testWidgets('같은 제출 작업의 재시도는 같은 키를 유지한다(중복 글 방지)',
        (WidgetTester tester) async {
      final FakeCommunityWrite fake = FakeCommunityWrite()..failPost = true;
      await tester.pumpWidget(MaterialApp(home: BoardWriteScreen(write: fake)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '제목');
      await tester.enterText(find.byType(TextField).at(1), '충분히 긴 본문입니다.');

      // 실패 스낵바가 버튼 위에 남지 않도록 매번 걷어내고 다시 누른다.
      Future<void> tapSubmit() async {
        await tester.tap(find.text('등록'));
        await tester.pumpAndSettle();
        ScaffoldMessenger.of(
                tester.element(find.byType(BoardWriteScreen)))
            .clearSnackBars();
        await tester.pumpAndSettle();
      }

      await tapSubmit();
      await tapSubmit(); // 명시적 재시도
      await tapSubmit(); // 한 번 더

      expect(fake.postCalls, 3);
      expect(fake.postIdempotencyKeys.toSet(), hasLength(1),
          reason: '재시도마다 키가 바뀌면 중복 글이 생긴다');
    });

    testWidgets('새 작성 작업(새 화면)은 새 키로 시작한다',
        (WidgetTester tester) async {
      final FakeCommunityWrite fake = FakeCommunityWrite();

      // 성공하면 화면이 pop 되어 Navigator 스택이 빈다. 그 상태로 같은
      // MaterialApp 을 다시 pump 하면 Element 가 재사용돼 빈 Navigator 를
      // rebuild 하다 죽는다(_history.isNotEmpty assertion). 루트 위젯 타입을
      // 바꿔 앱 전체를 해제한 뒤 새로 세워야 진짜 '새 작성 작업'이 된다.
      Future<void> writeOnce(String title) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester
            .pumpWidget(MaterialApp(home: BoardWriteScreen(write: fake)));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(0), title);
        await tester.enterText(find.byType(TextField).at(1), '충분히 긴 본문입니다.');
        await tester.tap(find.text('등록'));
        await tester.pumpAndSettle();
      }

      await writeOnce('첫 글');
      await writeOnce('두 번째 글'); // 새 작성 작업

      expect(fake.postCalls, 2);
      expect(fake.postIdempotencyKeys.toSet(), hasLength(2),
          reason: '새 작성 작업은 새 키여야 한다');
    });

    testWidgets('연속 탭에도 createPost 최대 1회(_submitting 가드)',
        (WidgetTester tester) async {
      final _SlowFakeWrite fake = _SlowFakeWrite();
      await tester.pumpWidget(MaterialApp(home: BoardWriteScreen(write: fake)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '제목');
      await tester.enterText(find.byType(TextField).at(1), '충분히 긴 본문입니다.');
      await tester.tap(find.text('등록'));
      await tester.pump();
      await tester.tap(find.text('등록 중…'), warnIfMissed: false);
      await tester.pump();

      fake.gate.complete();
      await tester.pumpAndSettle();
      expect(fake.postCalls, 1);
    });
  });
}

/// createPost 를 지연시켜 이중 제출 창을 여는 fake.
class _SlowFakeWrite extends FakeCommunityWrite {
  final Completer<void> gate = Completer<void>();

  @override
  Future<BoardPost> createPost({
    required String title,
    required String body,
    required String category,
    required String idempotencyKey,
    List<String> imageRefs = const <String>[],
  }) async {
    await gate.future;
    return super.createPost(
      title: title,
      body: body,
      category: category,
      idempotencyKey: idempotencyKey,
      imageRefs: imageRefs,
    );
  }
}
