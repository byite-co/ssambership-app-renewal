import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/features/individual_question/data/individual_question_repository.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_detail_screen.dart';

/// P0-5 개별질문 환불 — 공개 wrapper 계약(허용 상태·멱등·오류 UX) 회귀.
/// core RPC(refund_individual_question_hold) 는 앱이 호출하지 않는다(레포에 부재).
class _FakeRepo extends IndividualQuestionRepository {
  _FakeRepo({this.result, this.error});

  IqEscrowResult? result;
  Object? error;
  int refundCalls = 0;

  @override
  Future<IqEscrowResult> refund(String questionId) async {
    refundCalls += 1;
    final Object? e = error;
    if (e != null) throw e;
    return result!;
  }
}

IndividualQuestion _question(IndividualQuestionStatus status) {
  return IndividualQuestion(
    id: 'q1',
    studentId: 's1',
    type: IndividualQuestionType.open,
    status: status,
    title: '수열 질문이에요',
    body: '문제 본문',
    priceCents: 500000,
    createdAt: DateTime(2026, 7, 1),
  );
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required IndividualQuestionStatus status,
  required _FakeRepo repo,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: IqDetailScreen(
      key: ValueKey<String>('iq-${status.name}'), // 상태별 새 State 강제.
      questionId: 'q1',
      roleOverride: AppRole.student,
      repositoryOverride: repo,
      loaderOverride: () async => IqDetailData(
        question: _question(status),
        messages: const <IqMessage>[],
        attachments: const <IqAttachment>[],
        mentorName: '멘토',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tapRefund(WidgetTester tester) async {
  await tester.tap(find.text('질문 취소 (캐시 환불)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('질문 취소').last); // 확인 다이얼로그.
  await tester.pumpAndSettle();
}

void main() {
  group('취소 버튼 노출 상태 매트릭스(9종 + unknown) — 서버 wrapper 허용 상태와 1:1', () {
    const Map<IndividualQuestionStatus, bool> matrix =
        <IndividualQuestionStatus, bool>{
      IndividualQuestionStatus.escrowed: true,
      IndividualQuestionStatus.open: true,
      IndividualQuestionStatus.assigned: true,
      IndividualQuestionStatus.claimed: true,
      IndividualQuestionStatus.answered: false,
      IndividualQuestionStatus.released: false,
      IndividualQuestionStatus.expired: false,
      IndividualQuestionStatus.refunded: false,
      IndividualQuestionStatus.canceled: false,
      IndividualQuestionStatus.unknown: false,
    };

    test('iqCanStudentRefund 게이트가 서버 허용 집합과 정확히 일치', () {
      matrix.forEach((IndividualQuestionStatus s, bool allowed) {
        expect(iqCanStudentRefund(s), allowed, reason: s.name);
      });
      // enum 전수(누락 없는 매트릭스) 확인.
      expect(matrix.length, IndividualQuestionStatus.values.length);
    });

    testWidgets('escrowed 상세: 취소 버튼 노출 / answered 상세: 미노출',
        (WidgetTester tester) async {
      await _pumpDetail(tester,
          status: IndividualQuestionStatus.escrowed, repo: _FakeRepo());
      expect(find.text('질문 취소 (캐시 환불)'), findsOneWidget);

      await _pumpDetail(tester,
          status: IndividualQuestionStatus.answered, repo: _FakeRepo());
      expect(find.text('질문 취소 (캐시 환불)'), findsNothing);
    });
  });

  group('환불 오류 UX 매핑', () {
    test('REFUND_NOT_ALLOWED / NOT_QUESTION_OWNER / 환불실패 / already_refunded',
        () {
      expect(iqFailureMessage(Exception('REFUND_NOT_ALLOWED: status=answered')),
          contains('취소할 수 없어요'));
      expect(iqFailureMessage(Exception('NOT_QUESTION_OWNER')),
          contains('권한이 없어요'));
      expect(
          iqFailureMessage(
              Exception('INDIVIDUAL_QUESTION_REFUND_FAILED:X:boom')),
          contains('환불을 완료하지 못했어요'));
      expect(
          iqFailureMessage(Exception('already_refunded')), contains('이미 환불'));
      // 내부 코드 비노출.
      expect(iqFailureMessage(Exception('REFUND_NOT_ALLOWED')),
          isNot(contains('REFUND')));
    });
  });

  group('환불 실행 흐름(fake 레포 — 로컬 선반영·지갑 선반영 없음)', () {
    testWidgets('정상 성공(ok=true) → 성공 안내 + RPC 1회', (WidgetTester tester) async {
      final _FakeRepo repo =
          _FakeRepo(result: const IqEscrowResult(ok: true, code: 'refunded'));
      await _pumpDetail(tester,
          status: IndividualQuestionStatus.escrowed, repo: repo);
      await _tapRefund(tester);

      expect(repo.refundCalls, 1);
      expect(find.textContaining('질문을 취소했어요'), findsOneWidget);
    });

    testWidgets('already_refunded → 멱등 성공(이미 환불 안내, 실패 아님)',
        (WidgetTester tester) async {
      final _FakeRepo repo = _FakeRepo(
          result: const IqEscrowResult(ok: false, code: 'already_refunded'));
      await _pumpDetail(tester,
          status: IndividualQuestionStatus.escrowed, repo: repo);
      await _tapRefund(tester);

      expect(find.textContaining('이미 환불된 질문이에요'), findsOneWidget);
      expect(find.textContaining('실패'), findsNothing);
    });

    testWidgets('ok=false(기타 코드) → 실패 안내, 성공 토스트 없음',
        (WidgetTester tester) async {
      final _FakeRepo repo = _FakeRepo(
          result: const IqEscrowResult(ok: false, code: 'LEDGER_ERROR'));
      await _pumpDetail(tester,
          status: IndividualQuestionStatus.escrowed, repo: repo);
      await _tapRefund(tester);

      expect(find.textContaining('질문을 취소했어요'), findsNothing);
      expect(find.textContaining('잠시 후 다시 시도'), findsOneWidget);
    });

    testWidgets('answered 거부(REFUND_NOT_ALLOWED 예외) → 매핑 문구, 성공 없음',
        (WidgetTester tester) async {
      final _FakeRepo repo =
          _FakeRepo(error: Exception('REFUND_NOT_ALLOWED: status=answered'));
      await _pumpDetail(tester,
          status: IndividualQuestionStatus.escrowed, repo: repo);
      await _tapRefund(tester);

      expect(find.textContaining('취소할 수 없어요'), findsOneWidget);
      expect(find.textContaining('질문을 취소했어요'), findsNothing);
    });

    testWidgets('비소유자 거부(NOT_QUESTION_OWNER) → 권한 안내',
        (WidgetTester tester) async {
      final _FakeRepo repo = _FakeRepo(error: Exception('NOT_QUESTION_OWNER'));
      await _pumpDetail(tester,
          status: IndividualQuestionStatus.escrowed, repo: repo);
      await _tapRefund(tester);

      expect(find.textContaining('권한이 없어요'), findsOneWidget);
    });

    testWidgets('실패 시 질문 UI 원복 — 상태 라벨·취소 버튼 그대로(선반영 없음)',
        (WidgetTester tester) async {
      final _FakeRepo repo = _FakeRepo(error: Exception('network'));
      await _pumpDetail(tester,
          status: IndividualQuestionStatus.escrowed, repo: repo);
      await _tapRefund(tester);

      // 로컬에서 refunded 로 바꾸지 않는다 — 버튼·라벨 유지(재시도 가능).
      expect(find.text('질문 취소 (캐시 환불)'), findsOneWidget);
      expect(find.text('환불'), findsNothing);
    });
  });
}
