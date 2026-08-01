import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/design/role_accent.dart';
import 'package:ssambership_app/design/theme.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_detail_screen.dart';
import 'package:ssambership_app/shared/conversation_ui/conversation_bubble.dart';

/// D-10 렌더 계약: 개별질문 상세의 대화 영역이 학생·멘토 작성자를 구분한다.
const String kStudentId = 's1';
const String kMentorId = 'm1';

IndividualQuestion _question({
  IndividualQuestionStatus status = IndividualQuestionStatus.answered,
  String? claimedMentorId = kMentorId,
}) {
  return IndividualQuestion(
    id: 'q1',
    studentId: kStudentId,
    type: IndividualQuestionType.open,
    status: status,
    title: '수열 질문이에요',
    body: '문제 본문',
    priceCents: 500000,
    claimedMentorId: claimedMentorId,
    createdAt: DateTime(2026, 7, 1),
  );
}

IqMessage _msg(String id, String authorId, String body) => IqMessage(
      id: id,
      questionId: 'q1',
      authorId: authorId,
      body: body,
      createdAt: DateTime(2026, 7, 2),
    );

Future<void> _pump(
  WidgetTester tester, {
  required AppRole role,
  required List<IqMessage> messages,
  String? viewerId,
  IndividualQuestionStatus status = IndividualQuestionStatus.answered,
  String? claimedMentorId = kMentorId,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.build(role),
    home: IqDetailScreen(
      questionId: 'q1',
      roleOverride: role,
      currentUserId: viewerId,
      loaderOverride: () async => IqDetailData(
        question: _question(status: status, claimedMentorId: claimedMentorId),
        messages: messages,
        attachments: const <IqAttachment>[],
        mentorName: '수학멘토',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// 대화 말풍선 안으로 스코프를 좁힌 파인더.
/// ★ 본문 카드에도 '학생' 배지가 있으므로 전역 find.text 로는 단언할 수 없다.
Finder _inBubbles(String text) => find.descendant(
      of: find.byType(ConversationBubble),
      matching: find.text(text),
    );

ConversationBubble _bubbleWithBody(WidgetTester tester, String body) {
  final Finder f = find.byWidgetPredicate(
    (Widget w) => w is ConversationBubble && w.body == body,
  );
  expect(f, findsOneWidget, reason: '본문 "$body" 말풍선을 찾지 못했다');
  return tester.widget<ConversationBubble>(f);
}

void main() {
  testWidgets('학생 작성 메시지 → 대화 영역에 학생 라벨', (WidgetTester tester) async {
    await _pump(tester,
        role: AppRole.student,
        messages: <IqMessage>[_msg('m1', kStudentId, '추가로 여쭤봐요')]);

    expect(_inBubbles('학생'), findsOneWidget);
    expect(_inBubbles('멘토'), findsNothing);
  });

  testWidgets('멘토 작성 메시지 → 대화 영역에 멘토 라벨', (WidgetTester tester) async {
    await _pump(tester,
        role: AppRole.student,
        messages: <IqMessage>[_msg('m1', kMentorId, '이렇게 푸시면 돼요')]);

    expect(_inBubbles('멘토'), findsOneWidget);
    expect(_inBubbles('학생'), findsNothing);
  });

  testWidgets('혼합 스레드: 학생·멘토·미확인 3건이 각각 다르게 표기된다',
      (WidgetTester tester) async {
    await _pump(tester, role: AppRole.student, messages: <IqMessage>[
      _msg('a', kStudentId, '질문 추가'),
      _msg('b', kMentorId, '답변'),
      _msg('c', 'x9', '운영자 메모'),
    ]);

    expect(_inBubbles('학생'), findsOneWidget);
    expect(_inBubbles('멘토'), findsOneWidget);
    expect(_inBubbles('작성자 미확인'), findsOneWidget);
  });

  testWidgets('학생 시점: 내 메시지 우측(accent) / 멘토 메시지 좌측(중립)',
      (WidgetTester tester) async {
    await _pump(tester,
        role: AppRole.student,
        viewerId: kStudentId,
        messages: <IqMessage>[
          _msg('a', kStudentId, '내 글'),
          _msg('b', kMentorId, '상대 글'),
        ]);

    final ConversationBubble mine = _bubbleWithBody(tester, '내 글');
    expect(mine.align, ConversationAlign.end);
    expect(mine.tone, ConversationTone.accent);

    final ConversationBubble theirs = _bubbleWithBody(tester, '상대 글');
    expect(theirs.align, ConversationAlign.start);
    expect(theirs.tone, ConversationTone.neutral);
  });

  testWidgets('멘토 시점: 거울상 — 내 답변이 우측으로 간다',
      (WidgetTester tester) async {
    await _pump(tester,
        role: AppRole.mentor,
        viewerId: kMentorId,
        messages: <IqMessage>[
          _msg('a', kStudentId, '학생 글'),
          _msg('b', kMentorId, '내 답변'),
        ]);

    expect(_bubbleWithBody(tester, '내 답변').align, ConversationAlign.end);
    expect(_bubbleWithBody(tester, '학생 글').align, ConversationAlign.start);
  });

  testWidgets('뷰어 uid 없음 → 거울상 없이 전부 좌측(내 것으로 오인 금지), 라벨은 유지',
      (WidgetTester tester) async {
    await _pump(tester, role: AppRole.student, messages: <IqMessage>[
      _msg('a', kStudentId, '내 글'),
      _msg('b', kMentorId, '상대 글'),
    ]);

    for (final String body in <String>['내 글', '상대 글']) {
      final ConversationBubble b = _bubbleWithBody(tester, body);
      expect(b.align, ConversationAlign.start);
      expect(b.tone, ConversationTone.neutral);
    }
    // 방향 구분은 uid 없이도 살아 있다 — 그게 D-10 의 핵심.
    expect(_inBubbles('학생'), findsOneWidget);
    expect(_inBubbles('멘토'), findsOneWidget);
  });

  testWidgets('작성자 미확인은 accent 를 절대 받지 않는다', (WidgetTester tester) async {
    await _pump(tester,
        role: AppRole.student,
        viewerId: kStudentId,
        messages: <IqMessage>[_msg('c', '', '작성자 미기록 행')]);

    final ConversationBubble b = _bubbleWithBody(tester, '작성자 미기록 행');
    expect(b.tone, ConversationTone.neutral);
    expect(b.align, ConversationAlign.start);
    expect(_inBubbles('작성자 미확인'), findsOneWidget);
  });

  testWidgets('미클레임 공개형(mentorId null): 멘토 단정 없이 미확인 표기',
      (WidgetTester tester) async {
    await _pump(tester,
        role: AppRole.student,
        status: IndividualQuestionStatus.open,
        claimedMentorId: null,
        messages: <IqMessage>[_msg('b', kMentorId, '수락 전 메모')]);

    expect(_inBubbles('작성자 미확인'), findsOneWidget);
    expect(_inBubbles('멘토'), findsNothing);
  });

  testWidgets('author_id UUID 원문은 화면에 노출되지 않는다',
      (WidgetTester tester) async {
    const String uuid = '3f2b1c9e-0000-4aaa-bbbb-cccccccccccc';
    await _pump(tester,
        role: AppRole.student,
        viewerId: uuid,
        messages: <IqMessage>[_msg('a', uuid, '본문')]);

    expect(find.textContaining(uuid), findsNothing);
    expect(find.textContaining('3f2b1c9e'), findsNothing);
  });

  testWidgets('메시지 0건 → 대화 영역 미노출', (WidgetTester tester) async {
    await _pump(tester, role: AppRole.student, messages: const <IqMessage>[]);

    expect(find.byType(ConversationBubble), findsNothing);
    expect(find.text('대화'), findsNothing);
  });

  testWidgets('createdAt null 이어도 크래시 없이 렌더(시각만 생략)',
      (WidgetTester tester) async {
    await _pump(tester, role: AppRole.student, messages: <IqMessage>[
      const IqMessage(
          id: 'a', questionId: 'q1', authorId: kMentorId, body: '시각 없는 답변'),
    ]);

    expect(_bubbleWithBody(tester, '시각 없는 답변').timeLabel, isNull);
    expect(_inBubbles('멘토'), findsOneWidget);
  });

  testWidgets("'답변' 고정 헤더는 더 이상 쓰지 않는다(작성자 단정 제거)",
      (WidgetTester tester) async {
    await _pump(tester,
        role: AppRole.student,
        messages: <IqMessage>[_msg('a', kStudentId, '학생 추가 질문')]);

    expect(find.text('대화'), findsOneWidget);
    // 학생이 쓴 행까지 '답변' 이라고 부르던 헤더는 사라졌다.
    expect(find.text('답변'), findsNothing);
  });

  testWidgets('멘토 테마에서 내 답변은 멘토 accentSoft 로 칠해진다',
      (WidgetTester tester) async {
    await _pump(tester,
        role: AppRole.mentor,
        viewerId: kMentorId,
        messages: <IqMessage>[_msg('b', kMentorId, '내 답변')]);

    final Finder box = find
        .descendant(
          of: find.byType(ConversationBubble),
          matching: find.byType(Container),
        )
        .first;
    final BoxDecoration d =
        tester.widget<Container>(box).decoration! as BoxDecoration;
    expect(d.color, RoleAccent.mentor.accentSoft);
  });
}
