import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/ui/chat_screen.dart';
import 'package:ssambership_app/features/question_room/ui/mentor/mentor_answer_screen.dart';
import '../support/app_scope_test_harness.dart';

/// 채팅/답변 화면의 '입력창 하단 고정' 구조 검증.
/// 입력 바는 FutureBuilder(데이터) 바깥 Column 에 있어, 백엔드 없이도 항상 렌더된다.
/// → 실제 DB·네트워크 없이 구조만 본다(메시지 목록은 데이터 의존이라 검증 대상 아님).
QuestionThread _thread() {
  final DateTime now = DateTime(2026, 7, 1);
  return QuestionThread(
    id: 't1',
    roomId: 'r1',
    title: '미분 질문',
    status: ThreadStatus.pending,
    masteryStatus: MasteryStatus.unknown,
    createdAt: now,
    updatedAt: now,
  );
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('학생 채팅: 입력창이 하단에 있고 첨부·전송 아이콘이 있다', (WidgetTester tester) async {
    await tester.pumpScopedWidget(
        _wrap(ChatScreen(thread: _thread(), mentorName: '김선생')));
    await tester.pump(); // FutureBuilder 1프레임(데이터는 무시)

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.attach_file), findsOneWidget);
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    // 상태칩 한글(앱바)
    expect(find.text('답변 대기'), findsOneWidget);

    // 입력창이 화면 하단(아래 절반)에 위치.
    final double dy = tester.getCenter(find.byType(TextField)).dy;
    final double h = tester.getSize(find.byType(MaterialApp)).height;
    expect(dy, greaterThan(h / 2));
  });

  testWidgets('멘토 답변: 입력창 하단 + 전송 버튼 tooltip "답변 전송" + 학생명/제목 헤더',
      (WidgetTester tester) async {
    await tester.pumpScopedWidget(
        _wrap(MentorAnswerScreen(thread: _thread(), studentName: '로컬학생')));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.attach_file), findsOneWidget);
    // 헤더에 학생명 + 질문 제목.
    expect(find.text('로컬학생'), findsOneWidget);
    expect(find.text('미분 질문'), findsOneWidget);
    // 답변 전송 액션(전송 버튼 tooltip).
    expect(find.byTooltip('답변 전송'), findsOneWidget);

    final double dy = tester.getCenter(find.byType(TextField)).dy;
    final double h = tester.getSize(find.byType(MaterialApp)).height;
    expect(dy, greaterThan(h / 2));
  });
}
