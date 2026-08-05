import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/data/models/room.dart';
import 'package:ssambership_app/features/question_room/data/question_room_read_repository.dart';
import 'package:ssambership_app/features/question_room/ui/mentor/mentor_question_list_screen.dart';

/// 멘토 질문 목록 상태 탭(전체/답변 대기/진행 중/완료) + 과목 필터 + 정렬.
/// 기본 선택이 '전체'라 과거 기록이 첫 진입에서 바로 보이는지 검증한다.
class _FakeRead extends QuestionRoomReadRepository {
  const _FakeRead(this._threads);

  final List<QuestionThread> _threads;

  @override
  Future<List<QuestionThread>> threads(String roomId) async => _threads;
}

QuestionThread _thread(
  String id,
  ThreadStatus status, {
  String? subject,
  DateTime? updatedAt,
}) {
  final DateTime base = DateTime(2026, 7, 1);
  return QuestionThread(
    id: id,
    roomId: 'room-1',
    title: '질문 $id',
    status: status,
    subject: subject,
    masteryStatus: MasteryStatus.unknown,
    createdAt: base,
    updatedAt: updatedAt ?? base,
  );
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

/// 7건 고정 세트: pending 1 / answered+open 2 / confirmed+closed+archived 3 /
/// unknown 1(전체 탭에서만 보임).
List<QuestionThread> _sevenThreads() => <QuestionThread>[
      _thread('p1', ThreadStatus.pending,
          subject: 'math', updatedAt: DateTime(2026, 7, 7)),
      _thread('a1', ThreadStatus.answered,
          subject: 'korean', updatedAt: DateTime(2026, 7, 6)),
      _thread('o1', ThreadStatus.open,
          subject: 'math', updatedAt: DateTime(2026, 7, 5)),
      _thread('c1', ThreadStatus.confirmed,
          subject: 'english', updatedAt: DateTime(2026, 7, 4)),
      _thread('cl1', ThreadStatus.closed, updatedAt: DateTime(2026, 7, 3)),
      _thread('ar1', ThreadStatus.archived, updatedAt: DateTime(2026, 7, 2)),
      _thread('u1', ThreadStatus.unknown, updatedAt: DateTime(2026, 7, 1)),
    ];

Future<void> _pump(WidgetTester tester, List<QuestionThread> threads) async {
  // 7건 카드가 리스트에 전부 그려지도록 세로 여유 확보(lazy build 로 인한
  // 미표시 오탐 방지). 테스트 종료 시 원복.
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: MentorQuestionListScreen(
      room: _room(),
      studentName: '학생',
      readRepository: _FakeRead(threads),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('첫 진입 = 전체 탭 선택, 조회된 모든 질문(unknown 포함) 표시',
      (WidgetTester tester) async {
    await _pump(tester, _sevenThreads());

    // 탭 라벨에 정확한 개수.
    expect(find.text('전체 7'), findsOneWidget);
    expect(find.text('답변 대기 1'), findsOneWidget);
    expect(find.text('진행 중 2'), findsOneWidget);
    expect(find.text('완료 3'), findsOneWidget);

    // 기본(전체)에서 7건 전부 — 과거 기록이 숨지 않는다.
    for (final String id in <String>['p1', 'a1', 'o1', 'c1', 'cl1', 'ar1', 'u1']) {
      expect(find.text('질문 $id'), findsOneWidget);
    }
  });

  testWidgets('답변 대기 탭 = pending 만', (WidgetTester tester) async {
    await _pump(tester, _sevenThreads());
    await tester.tap(find.text('답변 대기 1'));
    await tester.pumpAndSettle();

    expect(find.text('질문 p1'), findsOneWidget);
    expect(find.text('질문 a1'), findsNothing);
    expect(find.text('질문 c1'), findsNothing);
    expect(find.text('질문 u1'), findsNothing);
  });

  testWidgets('진행 중 탭 = answered/open', (WidgetTester tester) async {
    await _pump(tester, _sevenThreads());
    await tester.tap(find.text('진행 중 2'));
    await tester.pumpAndSettle();

    expect(find.text('질문 a1'), findsOneWidget);
    expect(find.text('질문 o1'), findsOneWidget);
    expect(find.text('질문 p1'), findsNothing);
    expect(find.text('질문 u1'), findsNothing);
  });

  testWidgets('완료 탭 = confirmed/closed/archived', (WidgetTester tester) async {
    await _pump(tester, _sevenThreads());
    await tester.tap(find.text('완료 3'));
    await tester.pumpAndSettle();

    expect(find.text('질문 c1'), findsOneWidget);
    expect(find.text('질문 cl1'), findsOneWidget);
    expect(find.text('질문 ar1'), findsOneWidget);
    expect(find.text('질문 p1'), findsNothing);
    expect(find.text('질문 u1'), findsNothing); // unknown 은 전체 탭에서만.
  });

  testWidgets('과목 필터는 전체 탭에서도 동작(수학만)', (WidgetTester tester) async {
    await _pump(tester, _sevenThreads());
    // 카드 과목 배지에도 '수학'이 있으므로 필터 칩(트리 상단, first)만 탭한다.
    await tester.tap(find.text('수학').first);
    await tester.pumpAndSettle();

    expect(find.text('질문 p1'), findsOneWidget);
    expect(find.text('질문 o1'), findsOneWidget);
    expect(find.text('질문 a1'), findsNothing); // korean
    expect(find.text('질문 c1'), findsNothing); // english
  });

  testWidgets('정렬 토글: 최신순 ↔ 오래된순', (WidgetTester tester) async {
    await _pump(tester, _sevenThreads());

    Offset topOf(String title) => tester.getTopLeft(find.text(title));
    // 기본 최신순: p1(7/7) 이 u1(7/1)보다 위.
    expect(topOf('질문 p1').dy, lessThan(topOf('질문 u1').dy));

    await tester.tap(find.byTooltip('최신순'));
    await tester.pumpAndSettle();
    // 오래된순: u1 이 p1 보다 위.
    expect(topOf('질문 u1').dy, lessThan(topOf('질문 p1').dy));
  });

  testWidgets('질문 0건 → 빈 상태 안내(전체 탭)', (WidgetTester tester) async {
    await _pump(tester, const <QuestionThread>[]);
    expect(find.text('전체 0'), findsOneWidget);
    expect(find.text('아직 받은 질문이 없어요'), findsOneWidget);
  });
}
