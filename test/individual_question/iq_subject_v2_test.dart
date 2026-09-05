import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ssambership_app/features/individual_question/data/iq_error_mapper.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_create_screen.dart';

import '../support/app_scope_test_harness.dart';

IndividualQuestion _created(String id) => IndividualQuestion(
      id: id,
      studentId: 's1',
      type: IndividualQuestionType.open,
      status: IndividualQuestionStatus.open,
      title: '제목',
      body: '내용',
      priceCents: 200000,
      createdAt: DateTime(2026, 9, 5),
    );

/// A-4b ⑧ 개별질문 등록 v2 — 과목 선택(코드 정본) · 공개형 필수 안내 · 지정형 선택.
void main() {
  void bigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<List<Map<String, Object?>>> pumpAndSubmit(
    WidgetTester tester, {
    String? mentorId,
    String? tapSubject,
  }) async {
    final List<Map<String, Object?>> calls = <Map<String, Object?>>[];
    bigSurface(tester);
    await tester.pumpScopedWidget(MaterialApp(
      home: IqCreateScreen(
        mentorId: mentorId,
        mentorName: mentorId == null ? null : '김멘토',
        prefillOverride: () async => IqCreatePrefill(
          balanceCents: 1000000,
          pricing: mentorId == null ? null : IqPricing(mentorId: mentorId, amountCents: 250000),
        ),
        submitWithSubjectOverride: ({
          required IndividualQuestionType type,
          required String title,
          required String body,
          int? amountCents,
          String? designatedMentorId,
          String? idempotencyKey,
          String? subject,
        }) async {
          calls.add(<String, Object?>{'type': type, 'subject': subject, 'mentor': designatedMentorId});
          return _created('q-new');
        },
      ),
    ));
    await tester.pumpAndSettle();
    if (tapSubject != null) {
      await tester.tap(find.byKey(const ValueKey<String>('iq-subject-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tapSubject));
      await tester.pumpAndSettle();
    }
    if (mentorId == null) {
      await tester.enterText(find.widgetWithText(TextField, '질문 금액 (캐시)'), '2000');
    }
    await tester.enterText(find.widgetWithText(TextField, '제목'), '제목');
    await tester.enterText(find.widgetWithText(TextField, '질문 내용'), '질문 내용');
    await tester.ensureVisible(find.text('질문 등록'));
    await tester.tap(find.text('질문 등록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('공개형: 과목 칩(코드 정본) · 선택한 코드가 v2 에 실린다', (tester) async {
    final List<Map<String, Object?>> calls =
        await pumpAndSubmit(tester, tapSubject: '수학');
    expect(calls.single['type'], IndividualQuestionType.open);
    expect(calls.single['subject'], 'math');
    expect(calls.single['mentor'], isNull);
  });

  testWidgets('공개형: 앱바 과목 액션 → 시트(한글 라벨만) → 헤더 문장 갱신', (tester) async {
    bigSurface(tester);
    await tester.pumpScopedWidget(MaterialApp(
      home: IqCreateScreen(
        prefillOverride: () async => const IqCreatePrefill(balanceCents: 1000000),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('과목 선택'), findsOneWidget);
    expect(find.text('공개 · 과목을 고르면 그 과목 멘토에게 먼저 보여요'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('iq-subject-action')));
    await tester.pumpAndSettle();
    expect(find.text('과목을 골라 주세요'), findsOneWidget);
    expect(find.text('공개 질문은 과목을 골라야 그 과목 멘토에게 배정돼요.'), findsOneWidget);
    expect(find.text('수학'), findsOneWidget);
    expect(find.text('영어'), findsOneWidget);
    expect(find.text('math'), findsNothing);
    expect(find.text('선택 안 함'), findsNothing); // 공개형엔 없음.
    expect(find.textContaining('충전'), findsNothing);
    await tester.tap(find.text('영어'));
    await tester.pumpAndSettle();
    expect(find.text('과목을 골라 주세요'), findsNothing);
    expect(find.text('영어'), findsOneWidget); // 앱바 액션 라벨.
    expect(find.text('공개 · 영어 멘토에게 먼저 보여요'), findsOneWidget);
  });

  testWidgets("지정형: '과목 (선택)' · 고르지 않으면 subject null", (tester) async {
    final List<Map<String, Object?>> calls = await pumpAndSubmit(tester, mentorId: 'm1');
    expect(calls.single['type'], IndividualQuestionType.direct);
    expect(calls.single['subject'], isNull);
    expect(calls.single['mentor'], 'm1');
  });

  test('v2 오류 코드 → 문구(코드 비노출)', () {
    expect(iqErrorMessage(const PostgrestException(message: 'SUBJECT_REQUIRED')),
        '공개 질문은 과목을 골라야 해요.');
    expect(iqErrorMessage(const PostgrestException(message: 'INVALID_SUBJECT')),
        '과목을 다시 선택해 주세요.');
  });
}
