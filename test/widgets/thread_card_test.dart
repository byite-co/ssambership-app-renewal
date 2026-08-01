import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/ui/widgets/thread_card.dart';

QuestionThread _thread({
  String? title = '미분 질문',
  String? subject = 'math_calculus',
  ThreadStatus status = ThreadStatus.pending,
}) {
  final DateTime now = DateTime(2026, 7, 1);
  return QuestionThread(
    id: 't1',
    roomId: 'r1',
    title: title,
    subject: subject,
    status: status,
    masteryStatus: MasteryStatus.unknown,
    createdAt: now,
    updatedAt: now,
  );
}

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('제목·과목(한글)·상태칩(한글) 렌더, 영문 코드 비노출',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(
      ThreadCard(thread: _thread(), onOpen: () {}),
    ));
    expect(find.text('미분 질문'), findsOneWidget);
    expect(find.text('미적분'), findsOneWidget); // math_calculus → 한글
    expect(find.text('답변 대기'), findsOneWidget); // 상태 한글
    // 영문 코드가 화면에 새어나오지 않는다.
    expect(find.text('math_calculus'), findsNothing);
    expect(find.text('pending'), findsNothing);
  });

  testWidgets('제목 없으면 "(제목 없음)" 폴백', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(
      ThreadCard(thread: _thread(title: null), onOpen: () {}),
    ));
    expect(find.text('(제목 없음)'), findsOneWidget);
  });

  testWidgets('오답노트 배지 미노출(기능 제거 회귀 가드)', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(
      ThreadCard(thread: _thread(), onOpen: () {}),
    ));
    expect(find.text('오답노트'), findsNothing);
  });

  testWidgets('bottomAction 주입 시 렌더(예: 학생 답변 확인 버튼)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(
      ThreadCard(
        thread: _thread(status: ThreadStatus.answered),
        onOpen: () {},
        bottomAction: const Text('답변 확인 완료'),
      ),
    ));
    expect(find.text('답변 확인 완료'), findsOneWidget);
  });

  testWidgets('카드 탭 → onOpen 콜백', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(_wrap(
      ThreadCard(thread: _thread(), onOpen: () => taps++),
    ));
    await tester.tap(find.text('미분 질문'));
    await tester.pump();
    expect(taps, 1);
  });
}
