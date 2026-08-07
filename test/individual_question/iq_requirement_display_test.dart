import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/widgets/iq_widgets.dart';

/// [QA-B6] 개별질문에 과목·요구 학교·요구 계열이 전부 표시되지 않았다.
///
/// 원인이 둘로 갈린다:
///   ① 앱 모델에 두 필드가 아예 없었다(여기서 검증).
///   ② 공개형 대기 목록 RPC 가 두 컬럼을 돌려주지 않았다
///      (웹 migration 20260807010000 에서 반환 계약을 넓혔다).
/// 멘토는 이 조건을 보고 수락 여부를 판단하므로 목록에서 보이는 것이 핵심이다.
void main() {
  group('모델 파싱', () {
    test('OpenIndividualQuestion 이 조건 2종을 읽는다(넓힌 RPC 계약)', () {
      final OpenIndividualQuestion q =
          OpenIndividualQuestion.fromMap(<String, dynamic>{
        'id': 'q1',
        'title': '미분 질문',
        'price_cents': 500000,
        'subject': '수학',
        'topic': '미분',
        'required_school_tier': '서연고',
        'required_major_category': '메디컬',
      });
      expect(q.subject, '수학');
      expect(q.requiredSchoolTier, '서연고');
      expect(q.requiredMajorCategory, '메디컬');
    });

    test('IndividualQuestion 도 같은 컬럼명을 읽는다', () {
      final IndividualQuestion q = IndividualQuestion.fromMap(<String, dynamic>{
        'id': 'q1',
        'student_id': 's1',
        'question_type': 'open',
        'status': 'open',
        'title': 't',
        'body': 'b',
        'price_cents': 500000,
        'required_school_tier': '서연고',
        'required_major_category': '메디컬',
      });
      expect(q.requiredSchoolTier, '서연고');
      expect(q.requiredMajorCategory, '메디컬');
    });

    test('컬럼이 없으면 null — 구서버(넓히기 전) 응답에도 깨지지 않는다', () {
      final OpenIndividualQuestion q =
          OpenIndividualQuestion.fromMap(<String, dynamic>{
        'id': 'q1',
        'title': 't',
        'price_cents': 1,
      });
      expect(q.requiredSchoolTier, isNull);
      expect(q.requiredMajorCategory, isNull);
    });
  });

  group('표시', () {
    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
          MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
        );

    testWidgets('공개 대기 카드에 과목·요구 학교·요구 계열이 보인다',
        (WidgetTester tester) async {
      await pump(
        tester,
        IqOpenQuestionCard(
          question: const OpenIndividualQuestion(
            id: 'q1',
            title: '미분 질문',
            priceCents: 500000,
            subject: '수학',
            requiredSchoolTier: '서연고',
            requiredMajorCategory: '메디컬',
          ),
        ),
      );
      expect(find.text('수학'), findsOneWidget);
      expect(find.text('서연고 이상'), findsOneWidget);
      expect(find.text('메디컬 계열'), findsOneWidget);
    });

    testWidgets('조건이 하나도 없으면 아무것도 그리지 않는다(빈 칩 금지)',
        (WidgetTester tester) async {
      await pump(tester, const IqRequirementChips());
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.byType(Wrap), findsNothing);
    });

    testWidgets('공백만 있는 값은 조건으로 치지 않는다', (WidgetTester tester) async {
      await pump(
        tester,
        const IqRequirementChips(
          subject: '   ',
          requiredSchoolTier: '',
          requiredMajorCategory: '메디컬',
        ),
      );
      expect(find.text('메디컬 계열'), findsOneWidget);
      expect(find.textContaining('이상'), findsNothing);
    });
  });
}
