import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ssambership_app/features/mypage/data/account_deletion_repository.dart';
import 'package:ssambership_app/features/mypage/ui/account_delete_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// P1-10 계정 탈퇴 — RPC 계약(dry_run=false 명시·멱등·취소창)과 화면 흐름.
/// 실 staging 계정으로 삭제 RPC 를 실행하지 않는다(전부 fake).
class _FakeBackend implements AccountDeletionBackend {
  _FakeBackend({this.result, this.error});

  Object? result;
  Object? error;
  final List<(String, Map<String, dynamic>)> calls =
      <(String, Map<String, dynamic>)>[];

  @override
  Future<Object?> rpc(String fn, Map<String, dynamic> params) async {
    calls.add((fn, Map<String, dynamic>.of(params)));
    final Object? e = error;
    if (e != null) throw e;
    return result;
  }
}

/// 화면 흐름용 fake 포트.
class _FakePort implements AccountDeletionPort {
  _FakePort(
      {this.requestResult, this.cancelResult, this.statusResult, this.error});

  DeletionRequestResult? requestResult;
  DeletionCancelResult? cancelResult;
  DeletionStatusResult? statusResult;
  Object? error;
  int requestCalls = 0;
  int cancelCalls = 0;

  @override
  Future<DeletionRequestResult> requestDeletion() async {
    requestCalls += 1;
    final Object? e = error;
    if (e != null) throw e;
    return requestResult!;
  }

  @override
  Future<DeletionCancelResult> cancelDeletion() async {
    cancelCalls += 1;
    final Object? e = error;
    if (e != null) throw e;
    return cancelResult!;
  }

  @override
  Future<DeletionStatusResult> fetchStatus() async {
    return statusResult ??
        const DeletionStatusResult(
            exists: true,
            state: 'pending',
            writeBlocked: false,
            canCancel: true);
  }
}

void main() {
  group('SupabaseAccountDeletionRepository (RPC 계약)', () {
    test('요청: self RPC + p_dry_run=false 명시 + p_user_id 미전송(서버 auth.uid 정본)',
        () async {
      final _FakeBackend backend = _FakeBackend(result: <String, dynamic>{
        'ok': true,
        'existing': false,
        'job_id': 'job-1',
        'state': 'pending',
        'cancelable_until': '2026-07-21T08:00:00Z',
      });
      final SupabaseAccountDeletionRepository repo =
          SupabaseAccountDeletionRepository(backend: backend);

      final DeletionRequestResult r = await repo.requestDeletion();

      final (String fn, Map<String, dynamic> params) = backend.calls.single;
      expect(fn, 'account_deletion_request_self');
      expect(params['p_dry_run'], isFalse, reason: '서버 기본값 의존 금지');
      expect(params['p_cancelable_minutes'], 30);
      expect(params.containsKey('p_user_id'), isFalse,
          reason: '타인 ID 전송 경로 원천 제거 — 서버 auth.uid() 단독');
      expect(r.existing, isFalse);
      expect(r.isPending, isTrue);
      expect(r.cancelableUntil, isNotNull);
    });

    test('취소/상태도 self RPC — 인자에 사용자 ID 없음', () async {
      final _FakeBackend backend = _FakeBackend(
          result: <String, dynamic>{'ok': true, 'state': 'canceled'});
      final SupabaseAccountDeletionRepository repo =
          SupabaseAccountDeletionRepository(backend: backend);
      await repo.cancelDeletion();
      backend.result = <String, dynamic>{
        'ok': true,
        'exists': true,
        'state': 'pending',
        'cancelable_until': '2026-07-21T08:00:00Z',
        'write_blocked': false,
        'can_cancel': true,
      };
      final DeletionStatusResult s = await repo.fetchStatus();

      expect(backend.calls[0].$1, 'account_deletion_cancel_self');
      expect(backend.calls[1].$1, 'account_deletion_status_self');
      for (final (_, Map<String, dynamic> p) in backend.calls) {
        expect(p.containsKey('p_user_id'), isFalse);
      }
      expect(s.canCancel, isTrue);
      expect(s.writeBlocked, isFalse);
    });

    test('기존 job 멱등 응답(existing=true) 파싱 — 이중 탭/재요청 안전', () async {
      final _FakeBackend backend = _FakeBackend(result: <String, dynamic>{
        'ok': true,
        'existing': true,
        'job_id': 'job-1',
        'state': 'locked',
      });
      final SupabaseAccountDeletionRepository repo =
          SupabaseAccountDeletionRepository(backend: backend);

      final DeletionRequestResult r = await repo.requestDeletion();
      expect(r.existing, isTrue);
      expect(r.isPending, isFalse);
    });

    test('취소 결과 코드 파싱: ok / NOT_CANCELABLE / CANCEL_WINDOW_PASSED / NOT_FOUND',
        () async {
      final _FakeBackend backend = _FakeBackend();
      final SupabaseAccountDeletionRepository repo =
          SupabaseAccountDeletionRepository(backend: backend);

      backend.result = <String, dynamic>{'ok': true, 'state': 'canceled'};
      expect((await repo.cancelDeletion()).ok, isTrue);

      backend.result = <String, dynamic>{'ok': false, 'code': 'NOT_CANCELABLE'};
      expect((await repo.cancelDeletion()).notCancelable, isTrue);

      backend.result = <String, dynamic>{
        'ok': false,
        'code': 'CANCEL_WINDOW_PASSED'
      };
      expect((await repo.cancelDeletion()).windowPassed, isTrue);

      backend.result = <String, dynamic>{'ok': false, 'code': 'NOT_FOUND'};
      expect((await repo.cancelDeletion()).notFound, isTrue);
    });

    test('42501(permission denied) → AccountDeletionUnavailable(웹 폴백 분기)',
        () async {
      final _FakeBackend backend = _FakeBackend(
        error: const PostgrestException(
            message: 'permission denied for function account_deletion_request',
            code: '42501'),
      );
      final SupabaseAccountDeletionRepository repo =
          SupabaseAccountDeletionRepository(backend: backend);

      await expectLater(
        repo.requestDeletion(),
        throwsA(isA<AccountDeletionUnavailable>()),
      );
    });

    test('예상 밖 반환형 → 성공 위장 없이 AppError', () async {
      final _FakeBackend backend = _FakeBackend(result: 'weird');
      final SupabaseAccountDeletionRepository repo =
          SupabaseAccountDeletionRepository(backend: backend);
      await expectLater(repo.requestDeletion(), throwsA(isA<AppError>()));
    });
  });

  group('AccountDeleteScreen (요청 흐름)', () {
    Future<void> pump(
      WidgetTester tester, {
      required _FakePort port,
      required List<String> journal,
      bool pending = false,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: AccountDeleteScreen(
          port: port,
          pendingOverride: pending,
          signOutOverride: () async => journal.add('signOut'),
          openWebFallbackOverride: (_) async => journal.add('web'),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> ackAndRequest(WidgetTester tester) async {
      await tester.tap(find.text('위 내용을 모두 확인했어요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('탈퇴 요청'));
      await tester.pumpAndSettle();
      // 확인 다이얼로그.
      await tester.tap(find.text('탈퇴 요청').last);
      await tester.pumpAndSettle();
    }

    testWidgets('확인 체크 전에는 요청 버튼 비활성', (WidgetTester tester) async {
      final _FakePort port = _FakePort();
      await pump(tester, port: port, journal: <String>[]);

      await tester.tap(find.text('탈퇴 요청'));
      await tester.pumpAndSettle();
      expect(port.requestCalls, 0); // 비활성 — 다이얼로그도 안 뜸.
    });

    testWidgets('요청 성공(pending) → 안내 → signOut(토큰 revoke 는 signOut 내부 보장)',
        (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = _FakePort(
        requestResult: const DeletionRequestResult(
            existing: false, jobId: 'j', state: 'pending'),
      );
      await pump(tester, port: port, journal: journal);
      await ackAndRequest(tester);

      expect(find.textContaining('탈퇴 요청이 접수됐어요'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      expect(port.requestCalls, 1);
      expect(journal, <String>['signOut']);
    });

    testWidgets('기존 job(existing, locked) → 진행 중 안내 + signOut, 취소 UI 없음',
        (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = _FakePort(
        requestResult: const DeletionRequestResult(
            existing: true, jobId: 'j', state: 'locked'),
      );
      await pump(tester, port: port, journal: journal);
      await ackAndRequest(tester);

      expect(find.textContaining('이미 탈퇴 처리가 진행 중'), findsOneWidget);
      expect(find.text('탈퇴 취소'), findsNothing);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(journal, <String>['signOut']);
    });

    testWidgets('요청 실패 → 성공 화면·signOut 없음 + 재시도 가능',
        (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = _FakePort(error: const AppError('서버 오류'));
      await pump(tester, port: port, journal: journal);
      await ackAndRequest(tester);

      expect(find.textContaining('탈퇴 요청에 실패했어요'), findsOneWidget);
      expect(find.textContaining('접수됐어요'), findsNothing);
      expect(journal, isEmpty);
      expect(find.text('탈퇴 요청'), findsOneWidget); // 재시도 가능.
    });

    testWidgets('42501 → 웹 진행 폴백 노출, 성공 위장 없음', (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port =
          _FakePort(error: const AccountDeletionUnavailable());
      await pump(tester, port: port, journal: journal);
      await ackAndRequest(tester);

      expect(find.textContaining('앱에서 바로 탈퇴할 수 없어요'), findsOneWidget);
      final Finder webBtn = find.text('웹에서 진행');
      expect(webBtn, findsOneWidget);
      await tester.tap(webBtn);
      await tester.pumpAndSettle();
      expect(journal, <String>['web']);
    });
  });

  group('AccountDeleteScreen (취소 흐름 — deletionPending 재로그인 사용자)', () {
    Future<void> pumpPending(
      WidgetTester tester, {
      required _FakePort port,
      required List<String> journal,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: AccountDeleteScreen(
          port: port,
          pendingOverride: true,
          signOutOverride: () async => journal.add('signOut'),
          openWebFallbackOverride: (_) async => journal.add('web'),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('pending: 취소 버튼 노출 → 성공 시 재로그인 안내 + signOut',
        (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = _FakePort(
          cancelResult:
              const DeletionCancelResult(ok: true, state: 'canceled'));
      await pumpPending(tester, port: port, journal: journal);

      await tester.tap(find.text('탈퇴 취소'));
      await tester.pumpAndSettle();

      expect(find.textContaining('다시 로그인해 주세요'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(port.cancelCalls, 1);
      expect(journal, <String>['signOut']); // 세션 복원 가정 없음 — 재로그인.
    });

    testWidgets('취소창 경과(CANCEL_WINDOW_PASSED) → 취소 버튼 제거 + 안내',
        (WidgetTester tester) async {
      final _FakePort port = _FakePort(
          cancelResult: const DeletionCancelResult(
              ok: false, code: 'CANCEL_WINDOW_PASSED'));
      await pumpPending(tester, port: port, journal: <String>[]);

      await tester.tap(find.text('탈퇴 취소'));
      await tester.pumpAndSettle();

      expect(find.textContaining('취소 가능 시간이 지났어요'), findsOneWidget);
      expect(find.text('탈퇴 취소'), findsNothing); // 버튼 제거.
    });

    testWidgets('locked/purging(NOT_CANCELABLE) → 취소 버튼 제거 + 안내',
        (WidgetTester tester) async {
      final _FakePort port = _FakePort(
          cancelResult:
              const DeletionCancelResult(ok: false, code: 'NOT_CANCELABLE'));
      await pumpPending(tester, port: port, journal: <String>[]);

      await tester.tap(find.text('탈퇴 취소'));
      await tester.pumpAndSettle();

      expect(find.textContaining('이미 처리 중'), findsOneWidget);
      expect(find.text('탈퇴 취소'), findsNothing);
    });

    testWidgets('취소 실패(일시 오류) → 상태 유지·signOut 없음', (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = _FakePort(error: const AppError('네트워크'));
      await pumpPending(tester, port: port, journal: journal);

      await tester.tap(find.text('탈퇴 취소'));
      await tester.pumpAndSettle();

      expect(find.textContaining('취소에 실패했어요'), findsOneWidget);
      expect(find.text('탈퇴 취소'), findsOneWidget); // 재시도 가능.
      expect(journal, isEmpty);
    });

    testWidgets('status_self can_cancel=false(창 경과/locked) → 진입 시부터 취소 버튼 없음',
        (WidgetTester tester) async {
      final _FakePort port = _FakePort(
        statusResult: const DeletionStatusResult(
            exists: true,
            state: 'pending',
            writeBlocked: false,
            canCancel: false),
      );
      await pumpPending(tester, port: port, journal: <String>[]);

      expect(find.text('탈퇴 취소'), findsNothing);
      expect(find.textContaining('지금은 취소할 수 없어요'), findsOneWidget);
      expect(port.cancelCalls, 0);
    });
  });

  /// 탈퇴 안내 문구 정정 — '30분' 하드코딩 폐기.
  ///
  /// 취소 마감은 **서버 `cancelable_until` 정본**만 표시한다. 값이 없으면
  /// 시간을 명시하지 않는 중립 문구로 돌아간다 — 클라이언트 시계로 마감을
  /// 재계산하지 않는다.
  group('탈퇴 안내 문구 — 서버 cancelable_until 정본 표시', () {
    Future<void> pumpPending(
      WidgetTester tester, {
      required _FakePort port,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: AccountDeleteScreen(
          port: port,
          pendingOverride: true,
          signOutOverride: () async {},
          openWebFallbackOverride: (_) async {},
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('pending: 서버가 준 마감 시각을 그대로 표시(로컬 재계산 0)',
        (WidgetTester tester) async {
      final DateTime until = DateTime(2026, 7, 25, 15, 30);
      final _FakePort port = _FakePort(
        statusResult: DeletionStatusResult(
          exists: true,
          state: 'pending',
          cancelableUntil: until,
          writeBlocked: false,
          canCancel: true,
        ),
      );
      await pumpPending(tester, port: port);

      expect(find.textContaining('2026년 7월 25일 15:30까지'), findsOneWidget);
      expect(find.textContaining('30분'), findsNothing);
    });

    testWidgets('pending: 서버 값이 없으면 시간 미명시 중립 문구(추정 표시 금지)',
        (WidgetTester tester) async {
      final _FakePort port = _FakePort(
        statusResult: const DeletionStatusResult(
          exists: true,
          state: 'pending',
          writeBlocked: false,
          canCancel: true,
        ),
      );
      await pumpPending(tester, port: port);

      expect(find.textContaining('취소 가능 시간 내에는'), findsOneWidget);
      expect(find.textContaining('30분'), findsNothing);
      expect(find.textContaining('분 이내'), findsNothing);
    });

    testWidgets('요청 전 안내(고지 목록·확인 다이얼로그)에는 구체 시간이 없다',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AccountDeleteScreen(
          port: _FakePort(),
          pendingOverride: false,
          signOutOverride: () async {},
          openWebFallbackOverride: (_) async {},
        ),
      ));
      await tester.pumpAndSettle();

      // 고지 목록: 접수 전이라 서버 마감 시각이 없다 → 시간 미명시.
      expect(find.textContaining('취소 가능 시간 내에만'), findsOneWidget);
      expect(find.textContaining('30분'), findsNothing);

      await tester.tap(find.text('위 내용을 모두 확인했어요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('탈퇴 요청'));
      await tester.pumpAndSettle();
      expect(find.textContaining('취소 가능 시간 내에는'), findsOneWidget);
      expect(find.textContaining('30분'), findsNothing);
    });

    testWidgets('접수 완료 안내는 요청 응답의 cancelable_until 을 표시',
        (WidgetTester tester) async {
      final _FakePort port = _FakePort(
        requestResult: DeletionRequestResult(
          existing: false,
          jobId: 'job-1',
          state: 'pending',
          cancelableUntil: DateTime(2026, 7, 25, 9, 5),
        ),
      );
      await tester.pumpWidget(MaterialApp(
        home: AccountDeleteScreen(
          port: port,
          pendingOverride: false,
          signOutOverride: () async {},
          openWebFallbackOverride: (_) async {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('위 내용을 모두 확인했어요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('탈퇴 요청'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('탈퇴 요청').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('2026년 7월 25일 09:05까지'), findsOneWidget);
      expect(find.textContaining('30분'), findsNothing);
    });
  });
}
