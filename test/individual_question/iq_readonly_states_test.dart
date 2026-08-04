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

/// 학생 작성 이미지(author_id 정본 — 첨삭 게이트 검증용).
const List<IqAttachment> _oneImage = <IqAttachment>[
  IqAttachment(
    id: 'a1',
    storagePath: 'q1/1-000001.png',
    authorId: 's1',
    fileName: '문제.png',
    mimeType: 'image/png',
  ),
];

Future<void> _pump(
  WidgetTester tester,
  IndividualQuestionStatus status, {
  required AppRole role,
  List<IqAttachment> attachments = const <IqAttachment>[],
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(
    home: IqDetailScreen(
      questionId: 'q1',
      roleOverride: role,
      loaderOverride: () async => IqDetailData(
        question: _q(status),
        messages: const <IqMessage>[],
        attachments: attachments,
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

      // 제목은 컴팩트 헤더(한 줄)와 첫 질문 말풍선(전문) 두 곳에서 보인다.
      expect(find.text('수열 질문이에요'), findsNWidgets(2));
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

  group('첨삭 진입 상태 게이트 — 활성 구간(assigned/claimed/answered)에서만', () {
    // §4-1: 첫 답변 전(claimed/assigned)과 답변 도착 후 해결 완료 전(answered).
    for (final IndividualQuestionStatus s in <IndividualQuestionStatus>[
      IndividualQuestionStatus.assigned,
      IndividualQuestionStatus.claimed,
      IndividualQuestionStatus.answered,
    ]) {
      testWidgets('멘토 · $s: 첨삭하기 표시', (WidgetTester tester) async {
        await _pump(tester, s, role: AppRole.mentor, attachments: _oneImage);

        expect(find.text('첨삭하기'), findsOneWidget);
      });
    }

    // 종결·답변자 미정·미지 7개 상태는 전부 읽기 전용.
    for (final IndividualQuestionStatus s in <IndividualQuestionStatus>[
      IndividualQuestionStatus.escrowed,
      IndividualQuestionStatus.open,
      IndividualQuestionStatus.released,
      IndividualQuestionStatus.refunded,
      IndividualQuestionStatus.expired,
      IndividualQuestionStatus.canceled,
      IndividualQuestionStatus.unknown,
    ]) {
      testWidgets('멘토 · $s: 첨삭하기 미표시(첨부 조회·저장은 유지)',
          (WidgetTester tester) async {
        await _pump(tester, s, role: AppRole.mentor, attachments: _oneImage);

        expect(find.text('첨삭하기'), findsNothing);
        // 게이트가 첨부 카드 자체를 죽이면 안 된다 — 저장(다운로드)은 유지된다.
        expect(find.text('저장'), findsOneWidget);
      });
    }

    for (final IndividualQuestionStatus s in IndividualQuestionStatus.values) {
      testWidgets('학생 · $s: 첨삭하기 미표시', (WidgetTester tester) async {
        await _pump(tester, s, role: AppRole.student, attachments: _oneImage);

        expect(find.text('첨삭하기'), findsNothing);
      });
    }

    testWidgets('게이트는 iqCanMentorAnnotate 와 같은 구간을 쓴다(정의 이탈 가드)',
        (WidgetTester tester) async {
      for (final IndividualQuestionStatus s
          in IndividualQuestionStatus.values) {
        await _pump(tester, s, role: AppRole.mentor, attachments: _oneImage);

        expect(
          find.text('첨삭하기'),
          iqCanMentorAnnotate(s) ? findsOneWidget : findsNothing,
          reason: '$s: iqCanMentorAnnotate=${iqCanMentorAnnotate(s)} 와 어긋난다',
        );
      }
    });

    testWidgets('작성자 미기록 레거시 첨부: 활성 상태에서도 첨삭하기 미노출(추측 금지)',
        (WidgetTester tester) async {
      const List<IqAttachment> legacy = <IqAttachment>[
        IqAttachment(
          id: 'a1',
          storagePath: 'q1/1-000001.png',
          fileName: '문제.png',
          mimeType: 'image/png',
        ),
      ];
      await _pump(tester, IndividualQuestionStatus.claimed,
          role: AppRole.mentor, attachments: legacy);

      expect(find.text('첨삭하기'), findsNothing);
      expect(find.text('저장'), findsOneWidget);
    });
  });

  test('모든 상태값이 위 그룹에 덮여 있다(누락 가드)', () {
    // 새 상태가 추가되면 이 테스트가 먼저 깨져서 QA 매트릭스 갱신을 강제한다.
    expect(IndividualQuestionStatus.values.length, 10);
  });
}
