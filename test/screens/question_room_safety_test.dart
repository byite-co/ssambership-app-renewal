import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/data/models/room.dart';
import 'package:ssambership_app/features/question_room/data/room_safety_repository.dart';
import 'package:ssambership_app/features/question_room/ui/chat_screen.dart';
import 'package:ssambership_app/features/question_room/ui/mentor/mentor_answer_screen.dart';
import '../support/app_scope_test_harness.dart';

/// S3-E §5·§6·§8 — 질문방 신고·차단 진입점 계약.
///
/// 백엔드 없이(SupabaseInit 미초기화) 화면 구조와 포트 호출만 검증한다.
/// 상대 id 는 room 참여자 데이터에서만 도출된다(§7).
const String _studentId = 'student-uuid-1';
const String _mentorId = 'mentor-uuid-1';

/// 호출을 기록하는 fake 포트. DB 의미(멱등 차단)를 흉내낸다.
class _FakeSafety implements RoomSafetyPort {
  _FakeSafety({
    this.reportOutcome = SafetyOutcome.ok,
    this.blockOutcome = SafetyOutcome.ok,
    this.alreadyBlocked = false,
  });

  final SafetyOutcome reportOutcome;
  final SafetyOutcome blockOutcome;
  bool alreadyBlocked;

  final List<Map<String, String?>> reports = <Map<String, String?>>[];
  final List<String> blocks = <String>[];
  final Set<String> blockedRows = <String>{};

  @override
  Future<SafetyOutcome> reportUser({
    required String targetUserId,
    required String reason,
    String? description,
  }) async {
    reports.add(<String, String?>{
      'target_type': SupabaseRoomSafetyRepository.userTargetType,
      'target_id': targetUserId,
      'reason': reason,
      'description': description,
    });
    return reportOutcome;
  }

  @override
  Future<SafetyOutcome> blockUser(String targetUserId) async {
    blocks.add(targetUserId);
    blockedRows.add(targetUserId); // PK (blocker, blocked) — 중복이 쌓이지 않는다.
    return blockOutcome;
  }

  @override
  Future<bool> isBlockedByMe(String targetUserId) async => alreadyBlocked;
}

QuestionThread _thread() {
  final DateTime now = DateTime(2026, 8, 1);
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

Room _room() {
  final DateTime now = DateTime(2026, 8, 1);
  return Room(
    id: 'r1',
    studentId: _studentId,
    mentorId: _mentorId,
    createdAt: now,
    updatedAt: now,
  );
}

Widget _studentScreen(_FakeSafety safety, {Room? room, String? uid}) =>
    MaterialApp(
      home: ChatScreen(
        thread: _thread(),
        mentorName: '김선생',
        room: room ?? _room(),
        safety: safety,
        currentUserIdOverride: uid ?? _studentId,
      ),
    );

Widget _mentorScreen(_FakeSafety safety, {Room? room, String? uid}) =>
    MaterialApp(
      home: MentorAnswerScreen(
        thread: _thread(),
        studentName: '박학생',
        room: room ?? _room(),
        safety: safety,
        currentUserIdOverride: uid ?? _mentorId,
      ),
    );

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
}

void main() {
  group('신고', () {
    testWidgets('학생이 멘토를 신고 — target_type=user, target_id=멘토 id',
        (WidgetTester tester) async {
      final _FakeSafety safety = _FakeSafety();
      await tester.pumpScopedWidget(_studentScreen(safety));
      await tester.pump();

      await _openMenu(tester);
      await tester.tap(find.text('신고하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('신고 접수'));
      await tester.pumpAndSettle();

      expect(safety.reports, hasLength(1));
      expect(safety.reports.single['target_type'], 'user');
      expect(safety.reports.single['target_id'], _mentorId);
      expect(safety.reports.single['reason'], isNotNull);
      expect(find.text('신고를 접수했어요. 운영팀이 검토할게요.'), findsOneWidget);
    });

    testWidgets('멘토가 학생을 신고 — target_id=학생 id', (WidgetTester tester) async {
      final _FakeSafety safety = _FakeSafety();
      await tester.pumpScopedWidget(_mentorScreen(safety));
      await tester.pump();

      await _openMenu(tester);
      await tester.tap(find.text('신고하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('신고 접수'));
      await tester.pumpAndSettle();

      expect(safety.reports.single['target_id'], _studentId);
    });

    testWidgets('시트를 닫으면 쓰기 0회', (WidgetTester tester) async {
      final _FakeSafety safety = _FakeSafety();
      await tester.pumpScopedWidget(_studentScreen(safety));
      await tester.pump();

      await _openMenu(tester);
      await tester.tap(find.text('신고하기'));
      await tester.pumpAndSettle();
      // 시트 밖(배리어) 탭 = 취소.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(safety.reports, isEmpty);
      expect(find.textContaining('접수했어요'), findsNothing);
    });

    testWidgets('실패는 fail-closed — 성공 문구를 보여주지 않는다',
        (WidgetTester tester) async {
      final _FakeSafety safety =
          _FakeSafety(reportOutcome: SafetyOutcome.failed);
      await tester.pumpScopedWidget(_studentScreen(safety));
      await tester.pump();

      await _openMenu(tester);
      await tester.tap(find.text('신고하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('신고 접수'));
      await tester.pumpAndSettle();

      expect(find.text('신고 접수에 실패했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
      expect(find.textContaining('접수했어요'), findsNothing);
    });

    testWidgets('상대 raw UUID 는 어디에도 노출되지 않는다', (WidgetTester tester) async {
      final _FakeSafety safety = _FakeSafety();
      await tester.pumpScopedWidget(_studentScreen(safety));
      await tester.pump();
      await _openMenu(tester);
      expect(find.textContaining(_mentorId), findsNothing);
      await tester.tap(find.text('신고하기'));
      await tester.pumpAndSettle();
      expect(find.textContaining(_mentorId), findsNothing);
      expect(find.textContaining(_studentId), findsNothing);
    });
  });

  group('차단', () {
    testWidgets('학생이 멘토를 차단 → composer 비활성, 기존 대화 유지',
        (WidgetTester tester) async {
      final _FakeSafety safety = _FakeSafety();
      await tester.pumpScopedWidget(_studentScreen(safety));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      // 대화 영역(백엔드 없는 테스트에선 조회 실패 상태)의 렌더 내용을 기준으로 잡는다.
      final int conversationRowsBefore =
          tester.widgetList<Text>(find.byType(Text)).length;
      expect(find.textContaining('대화를 불러오지 못했어요'), findsOneWidget);

      await _openMenu(tester);
      await tester.tap(find.text('사용자 차단'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '차단'));
      await tester.pumpAndSettle();

      expect(safety.blocks, <String>[_mentorId]);
      // composer 제거 + 사유 안내(읽기 전용).
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.send_rounded), findsNothing);
      expect(find.byIcon(Icons.attach_file), findsNothing);
      expect(find.textContaining('지난 대화는 그대로 볼 수 있고'), findsOneWidget);
      // 대화 영역은 차단과 무관하게 그대로 렌더된다(읽기 유지).
      expect(find.textContaining('대화를 불러오지 못했어요'), findsOneWidget);
      expect(conversationRowsBefore, greaterThan(0));
    });

    testWidgets('멘토가 학생을 차단 → blocked_id=학생 id', (WidgetTester tester) async {
      final _FakeSafety safety = _FakeSafety();
      await tester.pumpScopedWidget(_mentorScreen(safety));
      await tester.pump();

      await _openMenu(tester);
      await tester.tap(find.text('사용자 차단'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '차단'));
      await tester.pumpAndSettle();

      expect(safety.blocks, <String>[_mentorScreenTarget]);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('확인 다이얼로그 취소 → 쓰기 0회, composer 유지',
        (WidgetTester tester) async {
      final _FakeSafety safety = _FakeSafety();
      await tester.pumpScopedWidget(_studentScreen(safety));
      await tester.pump();

      await _openMenu(tester);
      await tester.tap(find.text('사용자 차단'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pumpAndSettle();

      expect(safety.blocks, isEmpty);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('차단 후 전송·첨부를 시도해도 append/upload 진입 0회',
        (WidgetTester tester) async {
      final _FakeSafety safety = _FakeSafety(alreadyBlocked: true);
      await tester.pumpScopedWidget(_studentScreen(safety));
      await tester.pumpAndSettle();

      // 입장 시점부터 읽기 전용 — 전송/첨부 버튼 자체가 없다.
      expect(find.byIcon(Icons.send_rounded), findsNothing);
      expect(find.byIcon(Icons.attach_file), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('중복 차단은 멱등 — 다시 차단해도 행이 늘지 않는다', (WidgetTester tester) async {
      final _FakeSafety safety = _FakeSafety();
      await tester.pumpScopedWidget(_studentScreen(safety));
      await tester.pump();

      await _openMenu(tester);
      await tester.tap(find.text('사용자 차단'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '차단'));
      await tester.pumpAndSettle();

      // 이미 차단된 상태에서는 메뉴 항목이 비활성 표기로 바뀐다.
      await _openMenu(tester);
      expect(find.text('차단한 사용자'), findsOneWidget);
      expect(find.text('사용자 차단'), findsNothing);
      await tester.tap(find.text('차단한 사용자'));
      await tester.pumpAndSettle();

      expect(safety.blocks, hasLength(1));
      expect(safety.blockedRows, <String>{_mentorId});
    });

    testWidgets('차단 실패는 성공으로 위장하지 않는다 — composer 유지',
        (WidgetTester tester) async {
      final _FakeSafety safety =
          _FakeSafety(blockOutcome: SafetyOutcome.failed);
      await tester.pumpScopedWidget(_studentScreen(safety));
      await tester.pump();

      await _openMenu(tester);
      await tester.tap(find.text('사용자 차단'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '차단'));
      await tester.pumpAndSettle();

      expect(find.text('차단에 실패했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('상대 미확인', () {
    testWidgets('room 없음 → 안전 메뉴 비활성(신고·차단 항목 열리지 않음)',
        (WidgetTester tester) async {
      final _FakeSafety safety = _FakeSafety();
      await tester.pumpScopedWidget(MaterialApp(
        home: ChatScreen(
          thread: _thread(),
          mentorName: '김선생',
          safety: safety,
          currentUserIdOverride: _studentId,
        ),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('신고하기'), findsNothing);
      expect(find.text('사용자 차단'), findsNothing);
      expect(safety.reports, isEmpty);
      expect(safety.blocks, isEmpty);
    });

    testWidgets('이 방의 당사자가 아니면 메뉴 비활성', (WidgetTester tester) async {
      final _FakeSafety safety = _FakeSafety();
      await tester.pumpScopedWidget(_studentScreen(safety, uid: '제3자-uuid'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('신고하기'), findsNothing);
    });
  });
}

/// 멘토 화면에서 차단 대상은 학생이다(상대 = 방 참여자 중 나 아닌 쪽).
const String _mentorScreenTarget = _studentId;
