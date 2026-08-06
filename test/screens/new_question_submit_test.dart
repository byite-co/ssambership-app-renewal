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
  const _FakeRead({
    this.usage,
    this.usageFails = false,
    this.teachingSubjects = const <String>['math'],
  });

  final WeeklyQuestionUsage? usage;
  final bool usageFails;
  final List<String> teachingSubjects;

  @override
  Future<List<String>> mentorTeachingSubjects(String mentorId) async =>
      teachingSubjects;

  @override
  Future<List<QuestionThread>> threads(String roomId) async =>
      <QuestionThread>[];

  @override
  Future<int> threadCount(String roomId) async => 0; // N23: 자동 제목 순번용.

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

  group('과목 드롭다운(A1: 멘토 담당 과목 제한 + 전체 폴백)', () {
    Future<void> pump(WidgetTester tester,
        {required QuestionRoomReadRepository read,
        required _FakeWrite write}) async {
      await tester.pumpWidget(MaterialApp(
        home: NewQuestionScreen(
            room: _room(), readRepository: read, writeRepository: write),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('코드형 담당 과목(math) → 해당 과목만 한글 라벨로 표시', (WidgetTester tester) async {
      await pump(tester,
          read: const _FakeRead(
              usage: _ok, teachingSubjects: <String>['math', 'english']),
          write: _FakeWrite());
      await tester.tap(find.text('선택 안 함').first);
      await tester.pumpAndSettle();

      expect(find.text('수학'), findsOneWidget);
      expect(find.text('영어'), findsOneWidget);
      // 담당 밖 과목은 후보에 없다(전체 폴백 아님) + 영문 코드 비노출.
      expect(find.text('국어'), findsNothing);
      expect(find.text('math'), findsNothing);
    });

    testWidgets('한글형 담당 과목(수학) → 정규화되어 표시·선택 시 정본 코드 전송',
        (WidgetTester tester) async {
      final _FakeWrite write = _FakeWrite();
      await pump(tester,
          read: const _FakeRead(usage: _ok, teachingSubjects: <String>['수학']),
          write: write);
      await tester.tap(find.text('선택 안 함').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('수학').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '수학 질문이에요');
      await tester.tap(find.text('질문 등록'));
      await tester.pumpAndSettle();

      expect(write.createCalls, 1);
      expect(write.lastSubject, 'math'); // 정본 code 전송(한글 라벨 금지).
    });

    testWidgets('담당 과목이 비면(미지정·조회 실패) 전체 정본 과목 폴백', (WidgetTester tester) async {
      await pump(tester,
          read: const _FakeRead(usage: _ok, teachingSubjects: <String>[]),
          write: _FakeWrite());
      await tester.tap(find.text('선택 안 함').first);
      await tester.pumpAndSettle();

      // 전체 카탈로그가 후보로 뜬다('선택 안 함'만 남지 않음).
      expect(find.text('수학'), findsOneWidget);
      expect(find.text('국어'), findsOneWidget);
      expect(find.text('영어'), findsOneWidget);
    });

    testWidgets('정규화 불가 자유 라벨만이면 전체 폴백', (WidgetTester tester) async {
      await pump(tester,
          read: const _FakeRead(usage: _ok, teachingSubjects: <String>['코딩']),
          write: _FakeWrite());
      await tester.tap(find.text('선택 안 함').first);
      await tester.pumpAndSettle();

      expect(find.text('수학'), findsOneWidget);
      expect(find.text('국어'), findsOneWidget);
    });

    testWidgets('과목 미선택 제출 → 생성 RPC 에 subject=null 전달', (WidgetTester tester) async {
      final _FakeWrite write = _FakeWrite();
      await _pumpAndSubmit(tester,
          read: const _FakeRead(usage: _ok), write: write);

      expect(write.createCalls, 1);
      expect(write.lastSubject, isNull);
    });
  });
}
