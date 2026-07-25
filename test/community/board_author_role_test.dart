import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/board_author_gate.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/ui/board/board_write_screen.dart';
import 'package:ssambership_app/features/community/ui/widgets/content_policy_gate.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

import 'fakes.dart';

/// 게시판 author_role 오염 차단(세션1 §2) — 역할 정본은 "본인 users 행 SELECT"
/// 하나뿐이고, 모든 실패는 fail-closed(INSERT 0회)이며 mentor fallback 이 없다.
/// 저장 반환 행(author_id/author_role) 재검증 실패도 성공 처리 금지.

const String _uid = 'auth-uid-0001';

class _Harness {
  _Harness({
    this.authUserId = _uid,
    List<Map<String, dynamic>>? rows,
    Object? fetchError,
    Map<String, dynamic>? returned,
    Object? deleteError,
  })  : _rows = rows,
        _fetchError = fetchError,
        _returned = returned,
        _deleteError = deleteError;

  final String? authUserId;
  final List<Map<String, dynamic>>? _rows;
  final Object? _fetchError;
  final Map<String, dynamic>? _returned;
  final Object? _deleteError;

  int fetchCalls = 0;
  int insertCalls = 0;
  int deleteCalls = 0;
  String? deletedPostId;
  Map<String, dynamic>? lastPayload;

  Future<BoardPost> run() {
    return createBoardPostGated(
      authUserId: authUserId,
      fetchOwnUserRows: (String userId) async {
        fetchCalls++;
        if (_fetchError != null) throw _fetchError;
        return _rows ?? <Map<String, dynamic>>[];
      },
      insert: (Map<String, dynamic> payload) async {
        insertCalls++;
        lastPayload = payload;
        // 반환 행 기본값 = 요청 payload 그대로(정합 케이스).
        return _returned ??
            <String, dynamic>{
              ...payload,
              'id': 'post-1',
              'created_at': '2026-07-24T00:00:00Z',
            };
      },
      title: '제목',
      body: '본문',
      category: 'study',
      deleteOwnPostForCompensation: (String postId) async {
        deleteCalls++;
        deletedPostId = postId;
        if (_deleteError != null) throw _deleteError;
      },
    );
  }
}

Map<String, dynamic> _row({Object? id = _uid, Object? role = 'student'}) =>
    <String, dynamic>{'id': id, 'role': role};

void main() {
  test('학생: payload author_role=student · author_id=본인 uid', () async {
    final _Harness h = _Harness(rows: <Map<String, dynamic>>[_row()]);
    final BoardPost post = await h.run();
    expect(h.insertCalls, 1);
    expect(h.lastPayload!['author_role'], 'student');
    expect(h.lastPayload!['author_id'], _uid);
    expect(post.authorRole, 'student');
  });

  test('멘토: payload author_role=mentor', () async {
    final _Harness h =
        _Harness(rows: <Map<String, dynamic>>[_row(role: 'mentor')]);
    await h.run();
    expect(h.lastPayload!['author_role'], 'mentor');
  });

  test('로컬 캐시 role 은 입력조차 아니다 — users 행(student)이 정본', () async {
    // createBoardPostGated 는 로컬 role 을 받는 인자 자체가 없다(정본 단일화).
    // 캐시가 mentor 였더라도 users 행이 student 면 student 로 저장된다.
    final _Harness h = _Harness(rows: <Map<String, dynamic>>[_row()]);
    await h.run();
    expect(h.lastPayload!['author_role'], 'student');
  });

  group('fail-closed — INSERT 0회 · mentor fallback 0', () {
    Future<void> expectClosed(_Harness h, {bool expectFetch = true}) async {
      await expectLater(h.run(), throwsA(isA<AppError>()));
      expect(h.insertCalls, 0, reason: 'INSERT 0회');
      expect(h.lastPayload, isNull, reason: 'payload 생성 자체가 없어야 한다');
      if (!expectFetch) expect(h.fetchCalls, 0);
    }

    test('미로그인: 조회·INSERT 모두 0회', () async {
      await expectClosed(_Harness(authUserId: null), expectFetch: false);
    });

    test('본인 users 행 없음', () async {
      await expectClosed(_Harness(rows: const <Map<String, dynamic>>[]));
    });

    test('복수 행(비정상 반환)', () async {
      await expectClosed(
          _Harness(rows: <Map<String, dynamic>>[_row(), _row()]));
    });

    test('role SELECT 오류', () async {
      await expectClosed(_Harness(fetchError: StateError('network')));
    });

    test('role null', () async {
      await expectClosed(
          _Harness(rows: <Map<String, dynamic>>[_row(role: null)]));
    });

    test('role 비문자(int)', () async {
      await expectClosed(_Harness(rows: <Map<String, dynamic>>[_row(role: 7)]));
    });

    test('unknown role', () async {
      await expectClosed(
          _Harness(rows: <Map<String, dynamic>>[_row(role: 'teacher')]));
    });

    test('게시판 작성 미지원 role(admin)', () async {
      await expectClosed(
          _Harness(rows: <Map<String, dynamic>>[_row(role: 'admin')]));
    });

    test('Auth uid 와 users.id 불일치', () async {
      await expectClosed(
          _Harness(rows: <Map<String, dynamic>>[_row(id: 'other-uid')]));
    });
  });

  group('반환 행 재검증 — 불일치는 성공 처리 0', () {
    test('반환 author_id 불일치 → AppError (BoardPost 미반환)', () async {
      final _Harness h = _Harness(
        rows: <Map<String, dynamic>>[_row()],
        returned: <String, dynamic>{
          'id': 'post-1',
          'author_id': 'someone-else',
          'author_role': 'student',
        },
      );
      await expectLater(h.run(), throwsA(isA<AppError>()));
      expect(h.insertCalls, 1); // INSERT 는 됐지만 성공으로 승격하지 않는다.
    });

    test('반환 author_role 불일치(DEFAULT mentor 개입 감지) → AppError', () async {
      final _Harness h = _Harness(
        rows: <Map<String, dynamic>>[_row()],
        returned: <String, dynamic>{
          'id': 'post-1',
          'author_id': _uid,
          'author_role': 'mentor', // 요청은 student 였다
        },
      );
      await expectLater(h.run(), throwsA(isA<AppError>()));
    });

    test('정합 반환은 mismatch null', () {
      const BoardAuthorIdentity a =
          BoardAuthorIdentity(userId: _uid, role: 'student');
      expect(
          boardPostReturnMismatch(returned: <String, dynamic>{
            'author_id': _uid,
            'author_role': 'student',
          }, author: a),
          isNull);
    });
  });

  group('보정2 — SERVER_CANONICALIZATION_MISMATCH 보상 전용 삭제', () {
    test('케이스 A: 본인 행·ID 확정 → 보상 삭제 1회·postDeleted=true·구조화 보고', () async {
      final _Harness h = _Harness(
        rows: <Map<String, dynamic>>[_row()],
        returned: <String, dynamic>{
          'id': 'post-9',
          'author_id': _uid,
          'author_role': 'mentor', // DEFAULT 개입 감지
        },
      );
      Object? caught;
      try {
        await h.run();
      } catch (e) {
        caught = e;
      }
      final BoardCanonicalizationMismatch m =
          caught! as BoardCanonicalizationMismatch;
      expect(h.deleteCalls, 1);
      expect(h.deletedPostId, 'post-9');
      expect(m.ownRow, isTrue);
      expect(m.postDeleted, isTrue);
      expect(m.mismatchField, 'author_role');
      expect(m.expectedRole, 'student');
      expect(m.returnedRole, 'mentor');
    });

    test('케이스 A: 삭제 실패 → postDeleted=false·성공 처리 0(부분 실패 분리)', () async {
      final _Harness h = _Harness(
        rows: <Map<String, dynamic>>[_row()],
        returned: <String, dynamic>{
          'id': 'post-9',
          'author_id': _uid,
          'author_role': 'mentor',
        },
        deleteError: StateError('rls'),
      );
      Object? caught;
      try {
        await h.run();
      } catch (e) {
        caught = e;
      }
      final BoardCanonicalizationMismatch m =
          caught! as BoardCanonicalizationMismatch;
      expect(m.postDeleted, isFalse);
      expect(h.deleteCalls, 1);
    });

    test('케이스 B: 반환 author_id 불일치 → 삭제 시도 0·postDeleted=null', () async {
      final _Harness h = _Harness(
        rows: <Map<String, dynamic>>[_row()],
        returned: <String, dynamic>{
          'id': 'post-9',
          'author_id': 'someone-else',
          'author_role': 'student',
        },
      );
      Object? caught;
      try {
        await h.run();
      } catch (e) {
        caught = e;
      }
      final BoardCanonicalizationMismatch m =
          caught! as BoardCanonicalizationMismatch;
      expect(h.deleteCalls, 0, reason: '권한 밖 행 삭제 시도 금지');
      expect(m.ownRow, isFalse);
      expect(m.postDeleted, isNull);
      expect(m.mismatchField, 'author_id');
    });

    test('행 ID 미확정 → 삭제 시도 0·postDeleted=null', () async {
      final _Harness h = _Harness(
        rows: <Map<String, dynamic>>[_row()],
        returned: <String, dynamic>{
          'author_id': _uid,
          'author_role': 'mentor', // id 없음
        },
      );
      Object? caught;
      try {
        await h.run();
      } catch (e) {
        caught = e;
      }
      final BoardCanonicalizationMismatch m =
          caught! as BoardCanonicalizationMismatch;
      expect(h.deleteCalls, 0);
      expect(m.postDeleted, isNull);
      expect(m.returnedPostId, isNull);
    });

    test('불일치 예외는 AppError 하위(한글 메시지·성공 승격 불가)', () {
      const BoardCanonicalizationMismatch m = BoardCanonicalizationMismatch(
        '메시지',
        mismatchField: 'author_role',
        ownRow: true,
        returnedPostId: 'p',
        expectedRole: 'student',
        returnedRole: 'mentor',
        postDeleted: true,
      );
      expect(m, isA<AppError>());
    });
  });

  test('지원 role 집합은 정확히 student·mentor (exact 비교)', () {
    expect(kSupportedBoardAuthorRoles, <String>{'student', 'mentor'});
    expect(kSupportedBoardAuthorRoles.contains('mentor2'), isFalse);
  });

  testWidgets('연속 탭에도 createPost 최대 1회(_submitting 가드)',
      (WidgetTester tester) async {
    ContentPolicyGate.agreedThisSession = true; // 게이트는 전용 테스트에서 검증
    final _SlowFakeWrite fake = _SlowFakeWrite();
    await tester.pumpWidget(MaterialApp(home: BoardWriteScreen(write: fake)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '제목');
    await tester.enterText(find.byType(TextField).at(1), '내용');
    await tester.tap(find.text('등록'));
    await tester.pump();
    // 제출 중 라벨('등록 중…') 상태에서 연속 탭 — 버튼 onPressed=null 이지만
    // 프로그램적 재호출까지 가드되는지 pump 사이 재탭으로 확인.
    await tester.tap(find.text('등록 중…'), warnIfMissed: false);
    await tester.pump();

    fake.gate.complete();
    await tester.pumpAndSettle();
    expect(fake.postCalls, 1);
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
  }) async {
    await gate.future;
    return super.createPost(title: title, body: body, category: category);
  }
}
