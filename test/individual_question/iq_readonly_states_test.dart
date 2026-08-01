import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_detail_screen.dart';

/// 개별질문 상세의 상태별 액션 노출. IndividualQuestionStatus 10개 값을 전부 덮는다.
const String kRelease = '해결 완료 (멘토에게 정산)';
const String kRefund = '질문 취소 (캐시 환불)';

IndividualQuestion _q(IndividualQuestionStatus status) => IndividualQuestion(
      id: 'q1',
      studentId: 's1',
      type: IndividualQuestionType.direct,
      status: status,
      title: '수열 질문이에요',
      body: '문제 본문',
      priceCents: 500000,
      designatedMentorId: 'm1',
      createdAt: DateTime(2026, 7, 1),
    );

Future<void> _pump(
  WidgetTester tester,
  IndividualQuestionStatus status, {
  required AppRole role,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(
    home: IqDetailScreen(
      questionId: 'q1',
      roleOverride: role,
      loaderOverride: () async => IqDetailData(
        question: _q(status),
        messages: const <IqMessage>[],
        attachments: const <IqAttachment>[],
        mentorName: '수학멘토',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('학생 — 종결 상태는 액션 0 + 안내 문구', () {
    for (final IndividualQuestionStatus s in <IndividualQuestionStatus>[
      IndividualQuestionStatus.refunded,
      IndividualQuestionStatus.expired,
      IndividualQuestionStatus.canceled,
    ]) {
      testWidgets('$s: 버튼 0 + 안내 문구 노출', (WidgetTester tester) async {
        await _pump(tester, s, role: AppRole.student);

        expect(find.text(kRelease), findsNothing);
        expect(find.text(kRefund), findsNothing);
        expect(find.text(iqReadOnlyNotice(s)!), findsOneWidget);
      });
    }

    testWidgets('released: 정산 안내만, 버튼 0', (WidgetTester tester) async {
      await _pump(tester, IndividualQuestionStatus.released,
          role: AppRole.student);

      expect(find.text(kRelease), findsNothing);
      expect(find.text(kRefund), findsNothing);
      expect(find.textContaining('해결 완료했어요'), findsOneWidget);
    });
  });

  group('학생 — 진행 상태의 액션', () {
    testWidgets('answered: 해결 완료 노출, 취소 미노출', (WidgetTester tester) async {
      await _pump(tester, IndividualQuestionStatus.answered,
          role: AppRole.student);

      expect(find.text(kRelease), findsOneWidget);
      expect(find.text(kRefund), findsNothing);
    });

    // escrowed / open 은 학생이 취소 버튼을 보는 유일한 구간이다.
    for (final IndividualQuestionStatus s in <IndividualQuestionStatus>[
      IndividualQuestionStatus.escrowed,
      IndividualQuestionStatus.open,
      IndividualQuestionStatus.assigned,
      IndividualQuestionStatus.claimed,
    ]) {
      testWidgets('$s: 안전 보관 안내 + 취소 버튼 노출, 해결 완료 미노출',
          (WidgetTester tester) async {
        await _pump(tester, s, role: AppRole.student);

        expect(find.textContaining('안전 보관 중인 캐시'), findsOneWidget);
        expect(find.text(kRefund), findsOneWidget);
        expect(find.text(kRelease), findsNothing);
      });
    }

    testWidgets('unknown: 크래시 없이 렌더, 종결 안내는 붙지 않는다',
        (WidgetTester tester) async {
      await _pump(tester, IndividualQuestionStatus.unknown,
          role: AppRole.student);

      expect(find.text('수열 질문이에요'), findsOneWidget);
      expect(find.text(kRelease), findsNothing);
      expect(find.text(kRefund), findsNothing);
    });
  });

  group('멘토 — 종결 상태', () {
    for (final IndividualQuestionStatus s in <IndividualQuestionStatus>[
      IndividualQuestionStatus.refunded,
      IndividualQuestionStatus.expired,
      IndividualQuestionStatus.canceled,
    ]) {
      testWidgets('$s: 답변 작성 없음 + 안내 문구 노출', (WidgetTester tester) async {
        await _pump(tester, s, role: AppRole.mentor);

        expect(find.text('답변 등록'), findsNothing);
        expect(find.text(iqReadOnlyNotice(s)!), findsOneWidget);
      });
    }

    testWidgets('released: 정산 완료 안내', (WidgetTester tester) async {
      await _pump(tester, IndividualQuestionStatus.released,
          role: AppRole.mentor);

      expect(find.text('정산이 완료된 질문이에요.'), findsOneWidget);
      expect(find.text('답변 등록'), findsNothing);
    });

    testWidgets('claimed: 답변 작성 노출', (WidgetTester tester) async {
      await _pump(tester, IndividualQuestionStatus.claimed,
          role: AppRole.mentor);

      expect(find.text('답변 등록'), findsOneWidget);
    });
  });

  test('모든 상태값이 위 그룹에 덮여 있다(누락 가드)', () {
    // 새 상태가 추가되면 이 테스트가 먼저 깨져서 QA 매트릭스 갱신을 강제한다.
    expect(IndividualQuestionStatus.values.length, 10);
  });
}
