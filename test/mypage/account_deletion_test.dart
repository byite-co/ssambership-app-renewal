import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/app/app_chrome.dart';
import 'package:ssambership_app/design/app_theme.dart';
import 'package:ssambership_app/features/mypage/data/account_deletion_repository.dart';
import 'package:ssambership_app/features/mypage/ui/account_delete_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// P1-10 계정 탈퇴 — RPC 계약(dry_run=false 명시·멱등·취소창)과 화면 흐름,
/// 그리고 **잔액 보유 계정의 소멸 동의 흐름**(Build 12 실기기 FAIL 수정).
/// 실 staging 계정으로 삭제 RPC 를 실행하지 않는다(전부 fake).
class _FakeBackend implements AccountDeletionBackend {
  _FakeBackend({this.result, this.error});

  Object? result;
  Object? error;

  /// fn 별 응답을 다르게 줘야 할 때(일반 → 동의필요, 동의 → 성공) 사용.
  final Map<String, Object?> resultByFn = <String, Object?>{};

  /// fn 별 응답 큐 — 같은 fn 을 연속 호출할 때 앞에서부터 소비한다
  /// (동의 → stale → 재동의 → 성공). 비면 [resultByFn]/[result] 로 떨어진다.
  final Map<String, List<Object?>> queueByFn = <String, List<Object?>>{};

  final List<(String, Map<String, dynamic>)> calls =
      <(String, Map<String, dynamic>)>[];

  /// 특정 fn 에 전달된 파라미터만 추린다.
  List<Map<String, dynamic>> paramsFor(String fn) => <Map<String, dynamic>>[
        for (final (String f, Map<String, dynamic> p) in calls)
          if (f == fn) p,
      ];

  @override
  Future<Object?> rpc(String fn, Map<String, dynamic> params) async {
    calls.add((fn, Map<String, dynamic>.of(params)));
    final Object? e = error;
    if (e != null) throw e;
    final List<Object?>? q = queueByFn[fn];
    if (q != null && q.isNotEmpty) return q.removeAt(0);
    if (resultByFn.containsKey(fn)) return resultByFn[fn];
    return result;
  }
}

/// 화면 흐름용 fake 포트.
class _FakePort implements AccountDeletionPort {
  _FakePort({
    this.requestOutcome,
    this.consentOutcome,
    this.cancelResult,
    this.statusResult,
    this.error,
  });

  DeletionRequestOutcome? requestOutcome;

  /// 동의 RPC 응답. 여러 번 호출되면 앞에서부터 소비하고, 다 쓰면 마지막을 유지한다
  /// (불일치 → 재동의 → 성공 시나리오용).
  final List<DeletionRequestOutcome> consentOutcomes = <DeletionRequestOutcome>[];
  DeletionRequestOutcome? consentOutcome;

  DeletionCancelResult? cancelResult;
  DeletionStatusResult? statusResult;
  Object? error;
  Object? consentError;

  int requestCalls = 0;
  int consentCalls = 0;
  int cancelCalls = 0;

  /// 동의 RPC 에 실제로 전달된 금액(cents) — 서버 응답 원본과 exact 일치해야 한다.
  final List<int> acknowledgedBalances = <int>[];

  @override
  Future<DeletionRequestOutcome> requestDeletion() async {
    requestCalls += 1;
    final Object? e = error;
    if (e != null) throw e;
    return requestOutcome!;
  }

  @override
  Future<DeletionRequestOutcome> requestDeletionWithForfeitConsent({
    required int acknowledgedBalanceCents,
  }) async {
    consentCalls += 1;
    acknowledgedBalances.add(acknowledgedBalanceCents);
    final Object? e = consentError;
    if (e != null) throw e;
    if (consentOutcomes.isNotEmpty) {
      final int i = consentCalls - 1;
      return consentOutcomes[
          i < consentOutcomes.length ? i : consentOutcomes.length - 1];
    }
    return consentOutcome!;
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

/// 네트워크 단절 스탠드인 — PostgrestException 이 아닌 '그냥 실패'.
/// 이런 오류가 웹 폴백(=서버 미배포 안내)으로 둔갑하면 안 된다.
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}

/// 접수 성공 outcome 헬퍼.
DeletionAccepted _accepted({
  bool existing = false,
  String state = 'pending',
  DateTime? cancelableUntil,
}) =>
    DeletionAccepted(DeletionRequestResult(
      existing: existing,
      jobId: 'job-1',
      state: state,
      cancelableUntil: cancelableUntil,
    ));

void main() {
  group('SupabaseAccountDeletionRepository (RPC 계약)', () {
    test('요청: self RPC v2 — 파라미터 0개(취소창 서버 고정·dry_run 폐기·p_user_id 미전송)',
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

      final DeletionRequestOutcome o = await repo.requestDeletion();

      final (String fn, Map<String, dynamic> params) = backend.calls.single;
      expect(fn, 'account_deletion_request_self_v2');
      expect(params, isEmpty,
          reason: 'v2 계약: p_cancelable_minutes/p_dry_run/p_user_id 전송 금지 — '
              '취소창 30분은 서버 고정');
      final DeletionRequestResult r = (o as DeletionAccepted).result;
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

      final DeletionRequestResult r =
          (await repo.requestDeletion() as DeletionAccepted).result;
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

  /// ── 잔액 보유 계정(Build 12 실기기 FAIL — 학생/멘토 공통) ────────────────
  /// 일반 RPC 의 {ok:false, code:FORFEIT_CONSENT_REQUIRED, balance_cents} 는
  /// 오류가 아니라 **정상 반환**이다 — AppError 로 뭉개면 막다른 길이 된다.
  group('SupabaseAccountDeletionRepository (잔액 소멸 동의 계약)', () {
    SupabaseAccountDeletionRepository repoOf(_FakeBackend b) =>
        SupabaseAccountDeletionRepository(backend: b);

    test('잔액 양수 → FORFEIT_CONSENT_REQUIRED typed result(서버 balance_cents 그대로)',
        () async {
      final _FakeBackend backend = _FakeBackend(result: <String, dynamic>{
        'ok': false,
        'code': 'FORFEIT_CONSENT_REQUIRED',
        'balance_cents': 4500000,
      });

      final DeletionRequestOutcome o = await repoOf(backend).requestDeletion();

      expect(o, isA<DeletionForfeitConsentRequired>());
      expect((o as DeletionForfeitConsentRequired).balanceCents, 4500000);
      expect(backend.calls.single.$1, 'account_deletion_request_self_v2');
    });

    test('FORFEIT_CONSENT_REQUIRED 는 throw 하지 않는다(AppError·웹 폴백 변환 금지)',
        () async {
      final _FakeBackend backend = _FakeBackend(result: <String, dynamic>{
        'ok': false,
        'code': 'FORFEIT_CONSENT_REQUIRED',
        'balance_cents': 100,
      });
      await expectLater(
        repoOf(backend).requestDeletion(),
        completion(isA<DeletionForfeitConsentRequired>()),
      );
    });

    test('balance_cents 가 문자열/num 으로 와도 정수 그대로 파싱', () async {
      final _FakeBackend backend = _FakeBackend(result: <String, dynamic>{
        'ok': false,
        'code': 'FORFEIT_CONSENT_REQUIRED',
        'balance_cents': '9007199254740', // bigint → 문자열로 올 수 있다
      });
      expect(
        ((await repoOf(backend).requestDeletion())
                as DeletionForfeitConsentRequired)
            .balanceCents,
        9007199254740,
      );

      backend.result = <String, dynamic>{
        'ok': false,
        'code': 'FORFEIT_CONSENT_REQUIRED',
        'balance_cents': 1200.0,
      };
      expect(
        ((await repoOf(backend).requestDeletion())
                as DeletionForfeitConsentRequired)
            .balanceCents,
        1200,
      );
    });

    test('동의 RPC v2: 함수명·ack 금액 단일 파라미터·p_user_id/dry_run 없음', () async {
      final _FakeBackend backend = _FakeBackend(result: <String, dynamic>{
        'ok': true,
        'existing': false,
        'job_id': 'job-9',
        'state': 'pending',
        'cancelable_until': '2026-08-02T09:00:00Z',
      });

      final DeletionRequestOutcome o = await repoOf(backend)
          .requestDeletionWithForfeitConsent(acknowledgedBalanceCents: 4500000);

      final (String fn, Map<String, dynamic> params) = backend.calls.single;
      expect(fn, 'account_deletion_request_self_consented_v2');
      expect(params['p_acknowledged_balance_cents'], 4500000,
          reason: '서버가 준 금액을 가공 없이 그대로 되돌려준다');
      expect(params.keys.toList(), <String>['p_acknowledged_balance_cents'],
          reason: 'v2 계약: 동의 금액 외 파라미터 전송 금지(취소창은 서버 고정)');
      expect((o as DeletionAccepted).result.isPending, isTrue);
    });

    test('동의 RPC 기존 job → 멱등 성공(existing=true)', () async {
      final _FakeBackend backend = _FakeBackend(result: <String, dynamic>{
        'ok': true,
        'existing': true,
        'job_id': 'job-9',
        'state': 'pending',
      });
      final DeletionRequestOutcome o = await repoOf(backend)
          .requestDeletionWithForfeitConsent(acknowledgedBalanceCents: 100);
      expect((o as DeletionAccepted).result.existing, isTrue);
    });

    /// 운영 함수 exact 응답:
    /// {ok:false, code:"FORFEIT_CONSENT_STALE",
    ///  acknowledged_balance_cents:<보낸 값>, current_balance_cents:<현재 잔액>}
    test('운영 exact FORFEIT_CONSENT_STALE → 불일치 결과 + current_balance_cents',
        () async {
      final _FakeBackend backend = _FakeBackend(result: <String, dynamic>{
        'ok': false,
        'code': 'FORFEIT_CONSENT_STALE',
        'acknowledged_balance_cents': 4500000,
        'current_balance_cents': 5000000,
      });

      final DeletionRequestOutcome o = await repoOf(backend)
          .requestDeletionWithForfeitConsent(acknowledgedBalanceCents: 4500000);

      expect(o, isA<DeletionBalanceMismatch>());
      expect((o as DeletionBalanceMismatch).serverBalanceCents, 5000000,
          reason: '새 잔액은 current_balance_cents — 우리가 보낸 acknowledged 가 아니다');
    });

    test('current_balance_cents 가 정본 — balance_cents 는 하위 호환 fallback',
        () async {
      // 두 필드가 함께 오면 current 가 이긴다.
      final _FakeBackend backend = _FakeBackend(result: <String, dynamic>{
        'ok': false,
        'code': 'FORFEIT_CONSENT_STALE',
        'acknowledged_balance_cents': 4500000,
        'current_balance_cents': 5000000,
        'balance_cents': 123,
      });
      expect(
        ((await repoOf(backend).requestDeletionWithForfeitConsent(
                acknowledgedBalanceCents: 4500000)) as DeletionBalanceMismatch)
            .serverBalanceCents,
        5000000,
      );

      // 구버전 함수(balance_cents 만) 도 읽는다.
      backend.result = <String, dynamic>{
        'ok': false,
        'code': 'FORFEIT_CONSENT_STALE',
        'balance_cents': 700,
      };
      expect(
        ((await repoOf(backend).requestDeletionWithForfeitConsent(
                acknowledgedBalanceCents: 100)) as DeletionBalanceMismatch)
            .serverBalanceCents,
        700,
      );
    });

    test('stale 응답이 새 잔액을 안 주거나 형식이 깨졌으면 → 금액 null(fail-closed)',
        () async {
      for (final Map<String, dynamic> payload in <Map<String, dynamic>>[
        <String, dynamic>{
          'ok': false,
          'code': 'FORFEIT_CONSENT_STALE',
          'acknowledged_balance_cents': 4500000, // 새 잔액 필드 없음
        },
        <String, dynamic>{
          'ok': false,
          'code': 'FORFEIT_CONSENT_STALE',
          'current_balance_cents': 'not-a-number',
        },
        <String, dynamic>{
          'ok': false,
          'code': 'FORFEIT_CONSENT_STALE',
          'current_balance_cents': 0, // 0 은 '동의받을 잔액'이 아니다
        },
        <String, dynamic>{
          'ok': false,
          'code': 'FORFEIT_CONSENT_STALE',
          'current_balance_cents': -100,
        },
      ]) {
        final _FakeBackend backend = _FakeBackend(result: payload);
        final DeletionRequestOutcome o = await repoOf(backend)
            .requestDeletionWithForfeitConsent(
                acknowledgedBalanceCents: 4500000);
        expect(o, isA<DeletionBalanceMismatch>(), reason: '$payload');
        expect((o as DeletionBalanceMismatch).serverBalanceCents, isNull,
            reason: '금액을 지어내지 않는다 — 화면이 동의 단계를 폐기한다');
      }
    });

    test('acknowledged_balance_cents 를 새 잔액으로 오인하지 않는다', () async {
      final _FakeBackend backend = _FakeBackend(result: <String, dynamic>{
        'ok': false,
        'code': 'FORFEIT_CONSENT_STALE',
        'acknowledged_balance_cents': 4500000, // 우리가 보낸 값 — 새 잔액 아님
      });
      final DeletionRequestOutcome o = await repoOf(backend)
          .requestDeletionWithForfeitConsent(acknowledgedBalanceCents: 4500000);
      expect((o as DeletionBalanceMismatch).serverBalanceCents, isNull);
    });

    test('구/동등 불일치 코드도 성공으로 오인하지 않는다(exact 코드 우선 처리 후 alias)',
        () async {
      for (final String code in <String>[
        'BALANCE_ACK_MISMATCH',
        'BALANCE_CHANGED',
        'STALE_BALANCE_ACK',
        'CONSENT_BALANCE_MISMATCH',
      ]) {
        final _FakeBackend backend = _FakeBackend(result: <String, dynamic>{
          'ok': false,
          'code': code,
          'current_balance_cents': 700,
        });
        final DeletionRequestOutcome o = await repoOf(backend)
            .requestDeletionWithForfeitConsent(acknowledgedBalanceCents: 100);
        expect(o, isA<DeletionBalanceMismatch>(), reason: code);
        expect((o as DeletionBalanceMismatch).serverBalanceCents, 700,
            reason: code);
      }
    });

    test('동의필요인데 balance_cents 누락/0 → fail-closed(AppError, 금액 날조 없음)',
        () async {
      final _FakeBackend backend = _FakeBackend(result: <String, dynamic>{
        'ok': false,
        'code': 'FORFEIT_CONSENT_REQUIRED',
      });
      await expectLater(
          repoOf(backend).requestDeletion(), throwsA(isA<AppError>()));

      backend.result = <String, dynamic>{
        'ok': false,
        'code': 'FORFEIT_CONSENT_REQUIRED',
        'balance_cents': 0,
      };
      await expectLater(
          repoOf(backend).requestDeletion(), throwsA(isA<AppError>()));

      backend.result = <String, dynamic>{
        'ok': false,
        'code': 'FORFEIT_CONSENT_REQUIRED',
        'balance_cents': 'not-a-number',
      };
      await expectLater(
          repoOf(backend).requestDeletion(), throwsA(isA<AppError>()));
    });

    test('미지 서버 코드 / ok 누락 → 성공 위장 없이 AppError', () async {
      final _FakeBackend backend =
          _FakeBackend(result: <String, dynamic>{'ok': false, 'code': 'BOOM'});
      await expectLater(
          repoOf(backend).requestDeletion(), throwsA(isA<AppError>()));

      backend.result = <String, dynamic>{'ok': true}; // job_id 없음
      await expectLater(
          repoOf(backend).requestDeletion(), throwsA(isA<AppError>()));

      backend.result = <String, dynamic>{'existing': false, 'job_id': 'j'};
      await expectLater(
          repoOf(backend)
              .requestDeletionWithForfeitConsent(acknowledgedBalanceCents: 1),
          throwsA(isA<AppError>()));
    });

    test('동의 RPC 미배포(42883/PGRST202) → 웹 폴백 분기', () async {
      for (final String code in <String>['42883', 'PGRST202']) {
        final _FakeBackend backend = _FakeBackend(
          error: PostgrestException(
              message: 'Could not find the function ...', code: code),
        );
        await expectLater(
          repoOf(backend)
              .requestDeletionWithForfeitConsent(acknowledgedBalanceCents: 1),
          throwsA(isA<AccountDeletionUnavailable>()),
          reason: code,
        );
      }
    });

    test('일반 네트워크/서버 오류는 웹 폴백으로 위장하지 않는다', () async {
      final _FakeBackend backend =
          _FakeBackend(error: const SocketExceptionLike());
      await expectLater(
        repoOf(backend).requestDeletion(),
        throwsA(isA<SocketExceptionLike>()),
      );

      backend.error = const PostgrestException(
          message: 'internal server error', code: 'XX000');
      await expectLater(
        repoOf(backend)
            .requestDeletionWithForfeitConsent(acknowledgedBalanceCents: 1),
        throwsA(isA<PostgrestException>()),
      );
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
        requestOutcome: const DeletionAccepted(DeletionRequestResult(
            existing: false, jobId: 'j', state: 'pending')),
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
        requestOutcome: const DeletionAccepted(DeletionRequestResult(
            existing: true, jobId: 'j', state: 'locked')),
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

    testWidgets('일반 네트워크 오류 → 웹 폴백 아님(오류 안내만)', (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = _FakePort(error: const SocketExceptionLike());
      await pump(tester, port: port, journal: journal);
      await ackAndRequest(tester);

      expect(find.textContaining('탈퇴 요청에 실패했어요'), findsOneWidget);
      expect(find.textContaining('앱에서 바로 탈퇴할 수 없어요'), findsNothing);
      expect(find.text('웹에서 진행'), findsNothing);
      expect(journal, isEmpty);
    });

    testWidgets('요청 버튼 연타 → 요청 RPC 1회(다이얼로그도 1개)',
        (WidgetTester tester) async {
      final _FakePort port = _FakePort(requestOutcome: _accepted());
      await pump(tester, port: port, journal: <String>[]);

      await tester.tap(find.text('위 내용을 모두 확인했어요'));
      await tester.pumpAndSettle();

      // 리빌드 전 연타 — _busy 가드가 동기적으로 서야 두 번째 탭이 막힌다.
      final Finder btn = find.text('탈퇴 요청');
      await tester.tap(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(find.text('정말 탈퇴할까요?'), findsOneWidget);
      await tester.tap(find.text('탈퇴 요청').last);
      await tester.pumpAndSettle();

      expect(port.requestCalls, 1);
    });
  });

  /// ── 잔액 보유 계정: 소멸 동의 흐름(Build 12 실기기 FAIL 수정) ────────────
  group('AccountDeleteScreen (잔액 소멸 동의)', () {
    const int kBalance = 4500000; // 서버 정본 cents → "45,000원"
    const String kBalanceText = '45,000원';

    Future<void> pump(
      WidgetTester tester, {
      required _FakePort port,
      required List<String> journal,
      AppRole role = AppRole.student,
    }) async {
      // 화면 문구는 역할과 무관하다 — 역할은 테마로만 들어간다(학생/멘토 회귀용).
      await tester.pumpWidget(MaterialApp(
        // A-6b: 옛 AppTheme.build(role) → v3 AppTheme.build(role:) (역할 매핑은 앱 루트와 동일).
        theme: AppTheme.build(role: themeRoleOf(role)),
        home: AccountDeleteScreen(
          port: port,
          pendingOverride: false,
          signOutOverride: () async => journal.add('signOut'),
          openWebFallbackOverride: (_) async => journal.add('web'),
        ),
      ));
      await tester.pumpAndSettle();
    }

    /// 일반 확인 → 탈퇴 요청 → 확인 다이얼로그 승인(= 서버가 동의 요구를 돌려줌).
    Future<void> toConsentStage(WidgetTester tester) async {
      await tester.tap(find.text('위 내용을 모두 확인했어요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('탈퇴 요청'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('탈퇴 요청').last);
      await tester.pumpAndSettle();
    }

    _FakePort consentRequiredPort({DeletionRequestOutcome? consentOutcome}) =>
        _FakePort(
          requestOutcome:
              const DeletionForfeitConsentRequired(balanceCents: kBalance),
          consentOutcome: consentOutcome,
        );

    testWidgets('잔액 양수 → 오류·웹 폴백 아님, 잔액·소멸 시점·취소창 고지가 뜬다',
        (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = consentRequiredPort();
      await pump(tester, port: port, journal: journal);
      await toConsentStage(tester);

      // Build 12 증상(일반 오류만 표시·웹 폴백 없음)이 재발하지 않는다.
      expect(find.textContaining('탈퇴 요청에 실패했어요'), findsNothing);
      expect(find.textContaining('앱에서 바로 탈퇴할 수 없어요'), findsNothing);
      expect(find.text('웹에서 진행'), findsNothing);

      // 현재 잔액 표시(서버 값 포맷) + 소멸/복구불가/취소창 고지.
      expect(find.textContaining(kBalanceText), findsWidgets);
      expect(find.textContaining('삭제 처리가 시작되면 남은 캐시 잔액'), findsOneWidget);
      expect(find.textContaining('소멸 처리 후에는 환불·복구할 수 없어요'), findsOneWidget);
      expect(find.textContaining('취소하면 캐시 잔액은 소멸되지 않아요'), findsOneWidget);

      // 아직 접수 아님 — 성공 화면·로그아웃 없음.
      expect(find.textContaining('접수됐어요'), findsNothing);
      expect(journal, isEmpty);
      expect(port.consentCalls, 0);
    });

    testWidgets('동의는 일반 확인과 별도 체크박스 — 체크 전 버튼 비활성(consent RPC 0회)',
        (WidgetTester tester) async {
      final _FakePort port = consentRequiredPort();
      await pump(tester, port: port, journal: <String>[]);
      await toConsentStage(tester);

      // 일반 확인은 이미 체크된 상태지만 그것으로 동의를 대신하지 않는다.
      expect(find.textContaining('소멸되는 데 동의해요'), findsOneWidget);
      await tester.tap(find.text('동의하고 탈퇴 요청'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('동의하고 탈퇴'), findsNothing); // 확인 다이얼로그도 안 뜸.
      expect(port.consentCalls, 0);
    });

    testWidgets('동의 후 확인 다이얼로그에서 취소 → consent RPC 0회',
        (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = consentRequiredPort();
      await pump(tester, port: port, journal: journal);
      await toConsentStage(tester);

      await tester.tap(find.textContaining('소멸되는 데 동의해요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴 요청'));
      await tester.pumpAndSettle();

      // 다이얼로그가 떴고(고유 액션 라벨) 금액을 다시 적었다.
      expect(find.text('동의하고 탈퇴'), findsOneWidget);
      expect(find.textContaining('캐시 잔액 $kBalanceText이 소멸돼요'), findsWidgets);
      await tester.tap(find.text('돌아가기').last);
      await tester.pumpAndSettle();

      expect(port.consentCalls, 0);
      expect(journal, isEmpty);
      expect(find.text('동의하고 탈퇴 요청'), findsOneWidget); // 재시도 가능.
    });

    testWidgets('동의 완료 → consent RPC 1회 + ack 금액 exact + 접수 안내 + signOut',
        (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = consentRequiredPort(
        consentOutcome:
            _accepted(cancelableUntil: DateTime(2026, 8, 2, 18, 30)),
      );
      await pump(tester, port: port, journal: journal);
      await toConsentStage(tester);

      await tester.tap(find.textContaining('소멸되는 데 동의해요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴 요청'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴'));
      await tester.pumpAndSettle();

      expect(port.consentCalls, 1);
      expect(port.acknowledgedBalances, <int>[kBalance],
          reason: '서버 응답 balance_cents 원본 그대로 — 앱 계산값 금지');
      expect(find.textContaining('탈퇴 요청이 접수됐어요'), findsOneWidget);
      expect(find.textContaining('2026년 8월 2일 18:30까지'), findsOneWidget);

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(journal, <String>['signOut']);
    });

    testWidgets('동의 버튼 연타 → consent RPC 1회', (WidgetTester tester) async {
      final _FakePort port = consentRequiredPort(consentOutcome: _accepted());
      await pump(tester, port: port, journal: <String>[]);
      await toConsentStage(tester);

      await tester.tap(find.textContaining('소멸되는 데 동의해요'));
      await tester.pumpAndSettle();

      final Finder btn = find.text('동의하고 탈퇴 요청');
      await tester.tap(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(find.text('동의하고 탈퇴'), findsOneWidget); // 다이얼로그 1개.
      await tester.tap(find.text('동의하고 탈퇴'));
      await tester.pumpAndSettle();

      expect(port.consentCalls, 1);
    });

    testWidgets('잔액 불일치(TOCTOU) → 성공 화면 없음 · signOut 없음 · 새 금액으로 재동의',
        (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = consentRequiredPort();
      port.consentOutcomes.add(
          const DeletionBalanceMismatch(serverBalanceCents: 5000000));
      await pump(tester, port: port, journal: journal);
      await toConsentStage(tester);

      await tester.tap(find.textContaining('소멸되는 데 동의해요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴 요청'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴'));
      await tester.pumpAndSettle();

      expect(port.consentCalls, 1);
      expect(find.textContaining('접수됐어요'), findsNothing);
      expect(journal, isEmpty, reason: '접수 실패 — 로그아웃 금지');

      // 새 서버 금액으로 갱신 + 동의 초기화(옛 금액 동의를 재사용하지 않는다).
      expect(find.textContaining('50,000원'), findsWidgets);
      expect(find.textContaining(kBalanceText), findsNothing);
      final CheckboxListTile box = tester.widget<CheckboxListTile>(
          find.byType(CheckboxListTile));
      expect(box.value, isFalse);
    });

    testWidgets('불일치 재동의 → 새 금액을 ack 로 전달하고 접수', (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = consentRequiredPort();
      port.consentOutcomes
        ..add(const DeletionBalanceMismatch(serverBalanceCents: 5000000))
        ..add(_accepted());
      await pump(tester, port: port, journal: journal);
      await toConsentStage(tester);

      Future<void> consent() async {
        await tester.tap(find.textContaining('소멸되는 데 동의해요'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('동의하고 탈퇴 요청'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('동의하고 탈퇴'));
        await tester.pumpAndSettle();
      }

      await consent();
      await consent();

      expect(port.acknowledgedBalances, <int>[kBalance, 5000000]);
      expect(find.textContaining('탈퇴 요청이 접수됐어요'), findsOneWidget);
    });

    testWidgets('불일치인데 서버가 새 금액을 안 주면 처음부터(동의 UI 유지 금지)',
        (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = consentRequiredPort();
      port.consentOutcomes.add(const DeletionBalanceMismatch());
      await pump(tester, port: port, journal: journal);
      await toConsentStage(tester);

      await tester.tap(find.textContaining('소멸되는 데 동의해요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴 요청'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴'));
      await tester.pumpAndSettle();

      expect(journal, isEmpty);
      expect(find.text('동의하고 탈퇴 요청'), findsNothing);
      expect(find.text('탈퇴 요청'), findsOneWidget); // 첫 화면으로 복귀.
    });

    testWidgets('동의 RPC 기존 job → 멱등 성공(진행 중 안내 + signOut)',
        (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = consentRequiredPort(
          consentOutcome: _accepted(existing: true, state: 'locked'));
      await pump(tester, port: port, journal: journal);
      await toConsentStage(tester);

      await tester.tap(find.textContaining('소멸되는 데 동의해요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴 요청'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴'));
      await tester.pumpAndSettle();

      expect(port.consentCalls, 1);
      expect(find.textContaining('이미 탈퇴 처리가 진행 중'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(journal, <String>['signOut']);
    });

    testWidgets('동의 RPC 미배포(42501/미배포) → 웹 폴백, 성공 위장 없음',
        (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = consentRequiredPort();
      port.consentError = const AccountDeletionUnavailable();
      await pump(tester, port: port, journal: journal);
      await toConsentStage(tester);

      await tester.tap(find.textContaining('소멸되는 데 동의해요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴 요청'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴'));
      await tester.pumpAndSettle();

      expect(find.text('웹에서 진행'), findsOneWidget);
      expect(find.textContaining('접수됐어요'), findsNothing);
      expect(journal, isEmpty);
    });

    testWidgets('동의 단계 네트워크 오류 → 웹 폴백 아님 · 접수 안 됨',
        (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = consentRequiredPort();
      port.consentError = const SocketExceptionLike();
      await pump(tester, port: port, journal: journal);
      await toConsentStage(tester);

      await tester.tap(find.textContaining('소멸되는 데 동의해요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴 요청'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴'));
      await tester.pumpAndSettle();

      expect(find.textContaining('탈퇴 요청에 실패했어요'), findsOneWidget);
      expect(find.text('웹에서 진행'), findsNothing);
      expect(journal, isEmpty);
      expect(find.text('동의하고 탈퇴 요청'), findsOneWidget); // 재시도 가능.
    });

    testWidgets('학생: 캐시 잔액 보유 탈퇴가 끝까지 간다(역할 무관 문구)', (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = consentRequiredPort(consentOutcome: _accepted());
      await pump(tester, port: port, journal: journal, role: AppRole.student);
      await toConsentStage(tester);

      expect(find.textContaining('남은 캐시 잔액이 있어요'), findsOneWidget);
      expect(find.textContaining('소멸되는 캐시 잔액'), findsOneWidget);
      expect(find.textContaining('정산'), findsNothing);

      await tester.tap(find.textContaining('소멸되는 데 동의해요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴 요청'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      expect(port.acknowledgedBalances, <int>[kBalance]);
      expect(journal, <String>['signOut']);
    });

    testWidgets('멘토: 캐시 잔액 보유 탈퇴가 끝까지 간다(역할 무관 문구)',
        (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = consentRequiredPort(consentOutcome: _accepted());
      await pump(tester, port: port, journal: journal, role: AppRole.mentor);
      await toConsentStage(tester);

      // 서버가 보는 잔액은 역할 무관 cash_wallets.balance_cents 하나다 —
      // 멘토에게도 '정산 금액'이 아니라 학생과 같은 '캐시 잔액'으로 표시한다.
      expect(find.textContaining('남은 캐시 잔액이 있어요'), findsOneWidget);
      expect(find.textContaining('소멸되는 캐시 잔액'), findsOneWidget);
      expect(find.textContaining('정산'), findsNothing);

      await tester.tap(find.textContaining('소멸되는 데 동의해요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴 요청'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      expect(port.acknowledgedBalances, <int>[kBalance]);
      expect(journal, <String>['signOut']);
    });

    testWidgets('동의 단계에서 돌아가기 → RPC 0회, 첫 화면 복귀', (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = consentRequiredPort();
      await pump(tester, port: port, journal: journal);
      await toConsentStage(tester);

      await tester.tap(find.text('돌아가기'));
      await tester.pumpAndSettle();

      expect(port.consentCalls, 0);
      expect(find.text('탈퇴 요청'), findsOneWidget);
      expect(journal, isEmpty);
    });
  });

  /// ── 운영 exact 계약을 화면까지 끝까지(실 파서 경유) ────────────────────────
  /// fake 는 **RPC 트랜스포트**뿐이다. 응답 payload 는 운영 함수 exact 형태를 쓰고,
  /// 파싱은 실제 SupabaseAccountDeletionRepository 가 한다.
  group('AccountDeleteScreen × 운영 exact 응답(FORFEIT_CONSENT_STALE)', () {
    const String kConsentFn = 'account_deletion_request_self_consented_v2';

    Map<String, dynamic> consentRequired(int cents) => <String, dynamic>{
          'ok': false,
          'code': 'FORFEIT_CONSENT_REQUIRED',
          'balance_cents': cents,
        };

    /// 과제에 명시된 운영 exact stale payload.
    Map<String, dynamic> stale({
      required int acknowledged,
      Object? current = 5000000,
    }) =>
        <String, dynamic>{
          'ok': false,
          'code': 'FORFEIT_CONSENT_STALE',
          'acknowledged_balance_cents': acknowledged,
          if (current != null) 'current_balance_cents': current,
        };

    Map<String, dynamic> accepted() => <String, dynamic>{
          'ok': true,
          'existing': false,
          'job_id': 'job-1',
          'state': 'pending',
        };

    Future<void> pumpScreen(
      WidgetTester tester, {
      required _FakeBackend backend,
      required List<String> journal,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: AccountDeleteScreen(
          port: SupabaseAccountDeletionRepository(backend: backend),
          pendingOverride: false,
          signOutOverride: () async => journal.add('signOut'),
          openWebFallbackOverride: (_) async => journal.add('web'),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> toConsentStage(WidgetTester tester) async {
      await tester.tap(find.text('위 내용을 모두 확인했어요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('탈퇴 요청'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('탈퇴 요청').last);
      await tester.pumpAndSettle();
    }

    Future<void> consent(WidgetTester tester) async {
      await tester.tap(find.textContaining('소멸되는 데 동의해요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴 요청'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴'));
      await tester.pumpAndSettle();
    }

    testWidgets('stale → 성공 화면 0 · signOut 0 · 50,000원 갱신 · 체크박스 해제 → 재동의 성공',
        (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakeBackend backend = _FakeBackend();
      backend.queueByFn['account_deletion_request_self_v2'] = <Object?>[
        consentRequired(4500000),
      ];
      backend.queueByFn[kConsentFn] = <Object?>[
        stale(acknowledged: 4500000, current: 5000000),
        accepted(),
      ];

      await pumpScreen(tester, backend: backend, journal: journal);
      await toConsentStage(tester);
      expect(find.textContaining('45,000원'), findsWidgets);

      await consent(tester); // 1회차 — 서버가 stale 로 거절.

      expect(backend.paramsFor(kConsentFn).single['p_acknowledged_balance_cents'],
          4500000);
      expect(find.textContaining('접수됐어요'), findsNothing, reason: 'success dialog 0');
      expect(journal, isEmpty, reason: 'signOut 0');
      expect(find.textContaining('50,000원'), findsWidgets, reason: 'UI 갱신');
      expect(find.textContaining('45,000원'), findsNothing, reason: '옛 금액 잔존 금지');
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
        reason: '동의 체크 초기화',
      );

      await consent(tester); // 2회차 — 새 금액으로 재동의.

      expect(
        backend
            .paramsFor(kConsentFn)
            .map((Map<String, dynamic> p) => p['p_acknowledged_balance_cents'])
            .toList(),
        <int>[4500000, 5000000],
        reason: '재동의 ack 은 current_balance_cents 정본',
      );
      expect(find.textContaining('탈퇴 요청이 접수됐어요'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(journal, <String>['signOut']);
    });

    testWidgets('stale 인데 새 잔액 없음 → fail-closed(동의 단계 폐기 · 옛 ack 재사용 0)',
        (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakeBackend backend = _FakeBackend();
      backend.queueByFn['account_deletion_request_self_v2'] = <Object?>[
        consentRequired(4500000),
      ];
      backend.queueByFn[kConsentFn] = <Object?>[
        stale(acknowledged: 4500000, current: null),
      ];

      await pumpScreen(tester, backend: backend, journal: journal);
      await toConsentStage(tester);
      await consent(tester);

      expect(find.textContaining('접수됐어요'), findsNothing);
      expect(journal, isEmpty);
      // 동의 UI 를 유지하지 않는다 — 서버에 다시 물어봐야 금액을 안다.
      expect(find.text('동의하고 탈퇴 요청'), findsNothing);
      expect(find.text('탈퇴 요청'), findsOneWidget);
      expect(backend.paramsFor(kConsentFn).length, 1, reason: '자동 재시도 금지');
    });

    testWidgets('잔액 0 계정은 동의 단계 없이 일반 RPC 로 접수', (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakeBackend backend = _FakeBackend();
      backend.queueByFn['account_deletion_request_self_v2'] = <Object?>[accepted()];

      await pumpScreen(tester, backend: backend, journal: journal);
      await toConsentStage(tester);

      expect(find.textContaining('탈퇴 요청이 접수됐어요'), findsOneWidget);
      expect(backend.paramsFor(kConsentFn), isEmpty, reason: '동의 RPC 0회');
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(journal, <String>['signOut']);
    });
  });

  /// ── 캐시 소멸 '시점' 문구 정합성 ─────────────────────────────────────────
  /// 요청 단계는 job·동의 금액만 기록한다. 실제 몰수·지갑 0화는 취소창이 지난 뒤
  /// worker(storage_purged 이후)가 한다 → 취소창 안에서 취소하면 캐시는 남는다.
  group('잔액 소멸 시점 문구 — 서버 동작과 일치', () {
    testWidgets('"탈퇴를 취소해도 캐시가 돌아오지 않는다"류 문장이 없다',
        (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final _FakePort port = _FakePort(
        requestOutcome:
            const DeletionForfeitConsentRequired(balanceCents: 4500000),
      );
      await tester.pumpWidget(MaterialApp(
        home: AccountDeleteScreen(
          port: port,
          pendingOverride: false,
          signOutOverride: () async => journal.add('signOut'),
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

      expect(find.textContaining('탈퇴를 취소해도'), findsNothing);
      expect(find.textContaining('돌아오지 않아요'), findsNothing);
    });

    testWidgets('소멸은 "취소 가능 시간이 지나 삭제 처리가 시작되면" 으로 고지한다',
        (WidgetTester tester) async {
      final _FakePort port = _FakePort(
        requestOutcome:
            const DeletionForfeitConsentRequired(balanceCents: 4500000),
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

      // 소멸 시점 + 복구 불가 + 취소하면 안 사라짐, 세 가지가 모두 있어야 한다.
      expect(find.textContaining('취소 가능 시간이 지나 삭제 처리가 시작되면'),
          findsOneWidget);
      expect(find.textContaining('소멸 처리 후에는 환불·복구할 수 없어요'), findsOneWidget);
      expect(find.textContaining('취소하면 캐시 잔액은 소멸되지 않아요'), findsOneWidget);

      // 확인 다이얼로그도 같은 시점을 말한다(요청 즉시 소멸이라고 하지 않는다).
      await tester.tap(find.textContaining('소멸되는 데 동의해요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 탈퇴 요청'));
      await tester.pumpAndSettle();
      expect(find.textContaining('취소 가능 시간이 지나 삭제 처리가 시작되면'), findsWidgets);
      expect(find.textContaining('탈퇴 요청을 취소할 수 있어요'), findsOneWidget);
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
        requestOutcome: DeletionAccepted(DeletionRequestResult(
          existing: false,
          jobId: 'job-1',
          state: 'pending',
          cancelableUntil: DateTime(2026, 7, 25, 9, 5),
        )),
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
