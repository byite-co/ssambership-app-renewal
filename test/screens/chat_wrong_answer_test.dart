import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/data/question_room_write_repository.dart';
import 'package:ssambership_app/features/question_room/ui/chat_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

import '../goldens/golden_fixtures.dart';
import '../support/app_scope_test_harness.dart';

/// 학생 오답 표시(A-4a α6) — 앱바 메뉴 토글 · RPC 인자 · 배너 · 실패 안내.
class _FakeWrite extends QuestionRoomWriteRepository {
  const _FakeWrite(this.log, {this.error});

  final List<String> log;
  final Object? error;

  @override
  Future<bool> flagWrongAnswer({
    required String threadId,
    required bool isWrong,
  }) async {
    log.add('$threadId:$isWrong');
    final Object? e = error;
    if (e != null) throw e;
    return isWrong;
  }
}

void main() {
  Widget app({
    required MasteryStatus mastery,
    required QuestionRoomWriteRepository write,
  }) =>
      withTestAppScope(
        MaterialApp(
          home: ChatScreen(
            thread: goldenThread(
              id: 't3',
              status: ThreadStatus.answered,
              title: '삼각함수 합성',
              mastery: mastery,
            ),
            mentorName: kMentorName,
            room: goldenRoom(),
            currentUserIdOverride: kStudentId,
            readRepository:
                GoldenReadRepository(messageRows: goldenMessages('t3')),
            realtimeFactory: (String _) => GoldenNoopRealtime(),
            writeRepository: write,
          ),
        ),
        auth: TestAppAuth(role: AppRole.student, userId: kStudentId),
      );

  testWidgets('메뉴 "오답으로 표시" → RPC(true) → 배너 + 문구 "오답 표시 해제"', (
    WidgetTester tester,
  ) async {
    final List<String> log = <String>[];
    await tester.pumpWidget(app(
      mastery: MasteryStatus.unknown,
      write: _FakeWrite(log),
    ));
    await tester.pumpAndSettle();
    expect(find.text('오답으로 표시한 질문이에요. 복습할 때 다시 보세요.'), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('오답으로 표시'), findsOneWidget);
    expect(find.text('신고하기'), findsOneWidget); // 기존 항목 유지.
    await tester.tap(find.text('오답으로 표시'));
    await tester.pumpAndSettle();

    expect(log, <String>['t3:true']);
    expect(find.text('오답으로 표시했어요.'), findsOneWidget);
    expect(find.text('오답으로 표시한 질문이에요. 복습할 때 다시 보세요.'), findsOneWidget);

    // 첫 스낵바가 내려간 뒤(큐 대기 방지) 해제.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('오답 표시 해제'), findsOneWidget);
    await tester.tap(find.text('오답 표시 해제'));
    await tester.pumpAndSettle();
    expect(log, <String>['t3:true', 't3:false']);
    expect(find.text('오답 표시를 해제했어요.'), findsOneWidget);
    expect(find.text('오답으로 표시한 질문이에요. 복습할 때 다시 보세요.'), findsNothing);
  });

  testWidgets('이미 오답(mastery=wrong)인 질문은 배너와 함께 열린다', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(
      mastery: MasteryStatus.wrong,
      write: const _FakeWrite(<String>[]),
    ));
    await tester.pumpAndSettle();
    expect(find.text('오답으로 표시한 질문이에요. 복습할 때 다시 보세요.'), findsOneWidget);
  });

  testWidgets('RPC 실패 → 스낵바 안내 · 배너는 바뀌지 않는다', (WidgetTester tester) async {
    final List<String> log = <String>[];
    await tester.pumpWidget(app(
      mastery: MasteryStatus.unknown,
      write: _FakeWrite(log, error: const AppError('이 질문방에서 할 수 없는 동작이에요.')),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('오답으로 표시'));
    await tester.pumpAndSettle();

    expect(log, <String>['t3:true']);
    expect(find.textContaining('오답 표시를 저장하지 못했어요.'), findsOneWidget);
    expect(find.text('오답으로 표시한 질문이에요. 복습할 때 다시 보세요.'), findsNothing);
  });
}
