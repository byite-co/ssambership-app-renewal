import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/iq_flags.dart';
import 'package:ssambership_app/features/individual_question/ui/student_iq_list_screen.dart';
import '../support/app_scope_test_harness.dart';

/// 개별질문 '작성' 진입점 ↔ kIndividualQuestionCreateEnabled 연동 상시 검증.
///
/// ★ A안(2026-07): 플래그는 컴파일 타임 주입(bool.fromEnvironment) — 기본 false,
///   `flutter test --dart-define=IQ_CREATE_ENABLED=true` 로 on 상태도 같은
///   테스트로 검증한다(플래그 값 기준 단언이라 양쪽 모두 녹색이어야 함).
///   릴리즈 게이트: docs/PLAY_STORE_REVIEW_PLAN.md.
void main() {
  IndividualQuestion question() => IndividualQuestion(
        id: 'q1',
        studentId: 's1',
        type: IndividualQuestionType.open,
        status: IndividualQuestionStatus.open,
        title: '수열 질문이에요',
        body: '문제 본문',
        priceCents: 500000,
        createdAt: DateTime(2026, 7, 1),
      );

  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('빈 목록: EmptyState 의 "새 개별질문" 액션이 플래그를 따른다',
      (WidgetTester tester) async {
    await tester.pumpScopedWidget(wrap(StudentIqListScreen(
      loaderOverride: () async => <IndividualQuestion>[],
    )));
    await tester.pumpAndSettle();

    expect(find.text('아직 개별질문이 없어요'), findsOneWidget);
    expect(
      find.text('새 개별질문'),
      kIndividualQuestionCreateEnabled ? findsOneWidget : findsNothing,
      reason: '작성 진입점은 kIndividualQuestionCreateEnabled 에만 지배돼야 한다',
    );
  });

  testWidgets('목록 있음: "새 개별질문 (공개형)" 버튼이 플래그를 따른다 — 목록·상세는 항상 유지',
      (WidgetTester tester) async {
    await tester.pumpScopedWidget(wrap(StudentIqListScreen(
      loaderOverride: () async => <IndividualQuestion>[question()],
    )));
    await tester.pumpAndSettle();

    // 조회(목록)는 플래그와 무관하게 항상 보인다(A안: 소비가 아니므로 유지).
    expect(find.text('수열 질문이에요'), findsOneWidget);
    expect(
      find.text('새 개별질문 (공개형)'),
      kIndividualQuestionCreateEnabled ? findsOneWidget : findsNothing,
    );
  });
}
