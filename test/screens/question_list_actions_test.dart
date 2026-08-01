import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/entitlement/weekly_question_usage.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/data/models/room.dart';
import 'package:ssambership_app/features/question_room/data/question_room_read_repository.dart';
import 'package:ssambership_app/features/question_room/data/question_room_write_repository.dart';
import 'package:ssambership_app/features/question_room/ui/question_list_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// 학생 질문목록 화면(QuestionListScreen)의 카드 하단 액션·빈 상태·오류 상태.
///
/// ★ 이 파일은 저장소에서 QuestionListScreen 을 생성하는 유일한 지점이다
///   (구 wrong_answer_toggle_test.dart 를 대체). 삭제·축소 금지.
class _FakeRead extends QuestionRoomReadRepository {
  _FakeRead(this._threads, {this.error});

  List<QuestionThread> _threads;
  final Object? error;
  set threadsData(List<QuestionThread> v) => _threads = v;

  int threadCalls = 0;

  @override
  Future<List<QuestionThread>> threads(String roomId) async {
    threadCalls++;
    final Object? e = error;
    if (e != null) throw e;
    return _threads;
  }

  @override
  Future<WeeklyQuestionUsage?> weeklyUsage({
    required String studentId,
    required String mentorId,
  }) async =>
      null;
}

class _FakeWrite extends QuestionRoomWriteRepository {
  _FakeWrite({this.error});

  final Object? error;
  final List<String> confirmCalls = <String>[];

  @override
  Future<void> confirmThread(String threadId) async {
    confirmCalls.add(threadId);
    final Object? e = error;
    if (e != null) throw e;
  }
}

QuestionThread _thread({required ThreadStatus status}) {
  final DateTime now = DateTime(2026, 7, 1);
  return QuestionThread(
    id: 't1',
    roomId: 'r1',
    title: '미분 질문',
    status: status,
    isWrongAnswer: false,
    masteryStatus: MasteryStatus.unknown,
    createdAt: now,
    updatedAt: now,
  );
}

Room _room() {
  final DateTime now = DateTime(2026, 7, 1);
  return Room(
    id: 'r1',
    studentId: 's-1',
    mentorId: 'm-1',
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeRead read,
  required _FakeWrite write,
}) async {
  // ★ 같은 tester 에서 두 번 이상 pump 할 때 앞 트리를 반드시 걷어낸다.
  //   QuestionListScreen 은 StatefulWidget 이라 타입이 같으면 Element 가 재사용되고
  //   initState 가 다시 돌지 않는다 → 새 fake 를 주입해도 조회가 일어나지 않아
  //   단언이 '엉뚱한 이유로' 통과한다.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(
    home: QuestionListScreen(
      room: _room(),
      mentorName: '김선생',
      readRepository: read,
      writeRepository: write,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('answered 스레드: "답변 확인 완료" 버튼 노출', (WidgetTester tester) async {
    final _FakeRead read =
        _FakeRead(<QuestionThread>[_thread(status: ThreadStatus.answered)]);
    await _pump(tester, read: read, write: _FakeWrite());

    expect(find.text('답변 확인 완료'), findsOneWidget);
  });

  testWidgets('pending 스레드: 하단 액션 없음', (WidgetTester tester) async {
    final _FakeRead read =
        _FakeRead(<QuestionThread>[_thread(status: ThreadStatus.pending)]);
    await _pump(tester, read: read, write: _FakeWrite());

    expect(find.text('미분 질문'), findsOneWidget); // 카드 자체는 렌더된다
    expect(find.text('답변 확인 완료'), findsNothing);
  });

  testWidgets('confirmed 스레드: 하단 액션 없음(오답 토글 제거 후 확정 동작)',
      (WidgetTester tester) async {
    final _FakeRead read =
        _FakeRead(<QuestionThread>[_thread(status: ThreadStatus.confirmed)]);
    await _pump(tester, read: read, write: _FakeWrite());

    expect(find.text('미분 질문'), findsOneWidget);
    expect(find.text('답변 확인 완료'), findsNothing);
  });

  testWidgets('답변 확인 완료 탭 → confirmThread 1회 + 목록 재조회',
      (WidgetTester tester) async {
    final _FakeRead read =
        _FakeRead(<QuestionThread>[_thread(status: ThreadStatus.answered)]);
    final _FakeWrite write = _FakeWrite();
    await _pump(tester, read: read, write: write);

    final int before = read.threadCalls;
    read.threadsData = <QuestionThread>[
      _thread(status: ThreadStatus.confirmed),
    ];
    await tester.tap(find.text('답변 확인 완료'));
    await tester.pumpAndSettle();

    expect(write.confirmCalls, <String>['t1']);
    expect(read.threadCalls, greaterThan(before)); // _refresh() 재조회
    expect(find.text('답변 확인 완료'), findsNothing); // confirmed 로 수렴
  });

  testWidgets('confirmThread 실패 → 안내 스낵바 + 버튼 상태 유지',
      (WidgetTester tester) async {
    final _FakeRead read =
        _FakeRead(<QuestionThread>[_thread(status: ThreadStatus.answered)]);
    final _FakeWrite write = _FakeWrite(error: const AppError('서버 오류'));
    await _pump(tester, read: read, write: write);

    await tester.tap(find.text('답변 확인 완료'));
    await tester.pumpAndSettle();

    expect(find.textContaining('확인 처리에 실패했어요'), findsOneWidget);
    expect(find.text('답변 확인 완료'), findsOneWidget); // 원상 유지
  });

  testWidgets('질문 0개 → 빈 상태 렌더', (WidgetTester tester) async {
    final _FakeRead read = _FakeRead(<QuestionThread>[]);
    await _pump(tester, read: read, write: _FakeWrite());

    expect(find.text('이 멘토에게 첫 질문을 남겨보세요'), findsOneWidget);
  });

  testWidgets('조회 실패 → 안내 문구 노출', (WidgetTester tester) async {
    final _FakeRead read =
        _FakeRead(<QuestionThread>[], error: const AppError('서버 오류'));
    await _pump(tester, read: read, write: _FakeWrite());

    expect(find.textContaining('질문을 불러오지 못했어요'), findsOneWidget);
  });
}
