import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/entitlement/weekly_question_usage.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/data/models/room.dart';
import 'package:ssambership_app/features/question_room/data/question_room_read_repository.dart';
import 'package:ssambership_app/features/question_room/data/question_room_write_repository.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

import 'package:ssambership_app/features/question_room/ui/new_question_screen.dart';

/// P2-13(usage fail-closed) + P1-8(원자 생성 RPC 1회) 제출 흐름 검증.
class _FakeRead extends QuestionRoomReadRepository {
  const _FakeRead({this.usage, this.usageFails = false});

  final WeeklyQuestionUsage? usage;
  final bool usageFails;

  @override
  Future<List<String>> mentorTeachingSubjects(String mentorId) async =>
      <String>['math'];

  @override
  Future<List<QuestionThread>> threads(String roomId) async =>
      <QuestionThread>[];

  @override
  Future<WeeklyQuestionUsage?> weeklyUsage({
    required String studentId,
    required String mentorId,
  }) async =>
      usageFails ? null : usage;
}

class _FakeWrite extends QuestionRoomWriteRepository {
  _FakeWrite({this.error});

  final Object? error;
  int createCalls = 0;
  String? lastTitle;
  String? lastBody;
  String? lastSubject;

  @override
  Future<CreatedQuestionThread> createThread({
    required String roomId,
    required String title,
    String? subject,
    String? topic,
    required String firstMessageBody,
  }) async {
    createCalls += 1;
    lastTitle = title;
    lastBody = firstMessageBody;
    lastSubject = subject;
    final Object? e = error;
    if (e != null) throw e;
    return const CreatedQuestionThread(
      threadId: 'th-1',
      messageId: 'm-1',
      path: 'subscription',
      usedFreeQuota: false,
    );
  }
}

Room _room() {
  final DateTime now = DateTime(2026, 7, 1);
  return Room(
    id: 'room-1',
    studentId: 's-1',
    mentorId: 'm-1',
    createdAt: now,
    updatedAt: now,
  );
}

const WeeklyQuestionUsage _ok = WeeklyQuestionUsage(
    used: 1, limit: 9, remaining: 8, canAsk: true, planTier: 'standard');
const WeeklyQuestionUsage _exhausted = WeeklyQuestionUsage(
    used: 9, limit: 9, remaining: 0, canAsk: false, planTier: 'standard');

Future<void> _pumpAndSubmit(
  WidgetTester tester, {
  required QuestionRoomReadRepository read,
  required _FakeWrite write,
  String body = '이 문제 풀이가 궁금해요',
}) async {
  await tester.pumpWidget(MaterialApp(
    home: NewQuestionScreen(
        room: _room(), readRepository: read, writeRepository: write),
  ));
  await tester.pumpAndSettle();
  // 질문 내용(두 번째 TextField)에 본문 입력 후 등록.
  await tester.enterText(find.byType(TextField).last, body);
  await tester.tap(find.text('질문 등록'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('usage 조회 실패(null) → 제출 차단, 생성 RPC 미호출(P2-13 fail-closed)',
      (WidgetTester tester) async {
    final _FakeWrite write = _FakeWrite();
    await _pumpAndSubmit(tester,
        read: const _FakeRead(usageFails: true), write: write);

    expect(write.createCalls, 0);
    expect(find.textContaining('질문 가능 여부를 확인하지 못했어요'), findsOneWidget);
    expect(find.byType(NewQuestionScreen), findsOneWidget); // pop 안 됨.
  });

  testWidgets('한도 소진(can_ask=false) → 차단 문구, 생성 RPC 미호출',
      (WidgetTester tester) async {
    final _FakeWrite write = _FakeWrite();
    await _pumpAndSubmit(tester,
        read: const _FakeRead(usage: _exhausted), write: write);

    expect(write.createCalls, 0);
    expect(find.textContaining('모두 사용했어요'), findsOneWidget);
  });

  testWidgets('정상 제출 → 원자 생성 RPC 1회(본문 포함), 별도 append 없음, 성공 pop',
      (WidgetTester tester) async {
    final _FakeWrite write = _FakeWrite();
    await _pumpAndSubmit(tester,
        read: const _FakeRead(usage: _ok), write: write);

    expect(write.createCalls, 1);
    expect(write.lastBody, '이 문제 풀이가 궁금해요');
    expect(write.lastTitle, isNotEmpty); // 제목 미입력 → 자동 제목.
    expect(find.byType(NewQuestionScreen), findsNothing); // 성공 pop.
  });

  testWidgets('생성 RPC 실패(서버 한도 판정) → 오류 노출, 로컬 성공 없음',
      (WidgetTester tester) async {
    final _FakeWrite write =
        _FakeWrite(error: const AppError('이번 주 질문 한도를 모두 사용했어요.'));
    await _pumpAndSubmit(tester,
        read: const _FakeRead(usage: _ok), write: write);

    expect(write.createCalls, 1);
    expect(find.textContaining('질문 등록에 실패했어요'), findsOneWidget);
    expect(find.byType(NewQuestionScreen), findsOneWidget); // pop 안 됨.
  });
}
