import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/features/individual_question/data/individual_question_repository.dart';
import 'package:ssambership_app/features/individual_question/data/iq_messages_controller.dart';
import 'package:ssambership_app/features/individual_question/data/iq_realtime.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_detail_screen.dart';

/// §G/§H — IQ 실시간(dedup upsert·채널 정리)과 당사자 공용 컴포저
/// (iq_append_message) 배선. 실네트워크 없이 fake 포트/레포로 검증한다.
class _FakeIqRealtime implements IqRealtimePort {
  void Function(IqMessage message)? onMessageInsert;
  void Function()? onQuestionUpdate;
  void Function()? onAttachmentInsert;
  void Function()? onReconnected;
  int startCalls = 0;
  int disposeCalls = 0;

  @override
  void start({
    required void Function(IqMessage message) onMessageInsert,
    void Function()? onQuestionUpdate,
    void Function()? onAttachmentInsert,
    void Function()? onReconnected,
  }) {
    startCalls++;
    this.onMessageInsert = onMessageInsert;
    this.onQuestionUpdate = onQuestionUpdate;
    this.onAttachmentInsert = onAttachmentInsert;
    this.onReconnected = onReconnected;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

class _AppendRepo extends IndividualQuestionRepository {
  const _AppendRepo(this.log);

  final List<(String, String)> log;

  @override
  Future<IqAppendResult> appendMessage(String questionId, String body) async {
    log.add((questionId, body));
    return const IqAppendResult(messageId: 'srv-1', answeredTransition: false);
  }
}

IndividualQuestion _q(IndividualQuestionStatus status) => IndividualQuestion(
      id: 'q1',
      studentId: 's1',
      type: IndividualQuestionType.direct,
      status: status,
      title: '수열 질문이에요',
      body: '문제 본문',
      priceCents: 500000,
      designatedMentorId: 'm1',
      claimedMentorId: 'm1',
      createdAt: DateTime(2026, 7, 1),
    );

IqMessage _m(String id, String body, {int minute = 0}) => IqMessage(
      id: id,
      questionId: 'q1',
      authorId: 'm1',
      body: body,
      createdAt: DateTime(2026, 7, 1, 10, minute),
    );

Future<void> _pump(
  WidgetTester tester, {
  required AppRole role,
  required IndividualQuestionStatus status,
  required _FakeIqRealtime realtime,
  List<(String, String)>? appendLog,
  List<IqMessage> messages = const <IqMessage>[],
}) async {
  await tester.pumpWidget(MaterialApp(
    home: IqDetailScreen(
      questionId: 'q1',
      roleOverride: role,
      currentUserId: role == AppRole.student ? 's1' : 'm1',
      repositoryOverride: _AppendRepo(appendLog ?? <(String, String)>[]),
      realtimeFactoryOverride: (String questionId) => realtime,
      loaderOverride: () async => IqDetailData(
        question: _q(status),
        messages: messages,
        attachments: const <IqAttachment>[],
        mentorName: '수학멘토',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('IqMessagesController — dedup by id(중복 이벤트 → 중복 행 0)', () {
    test('같은 id upsert 2회 → 1행, 서버 행으로 교체', () {
      final IqMessagesController c = IqMessagesController();
      c.upsertFromServer(_m('a', '첫 수신'));
      c.upsertFromServer(_m('a', '서버 정본'));
      expect(c.length, 1);
      expect(c.items.single.body, '서버 정본');
    });

    test('resetTo(재조회) 와 실시간 수신이 id 로 수렴한다', () {
      final IqMessagesController c = IqMessagesController();
      c.upsertFromServer(_m('a', '실시간', minute: 1));
      c.resetTo(<IqMessage>[_m('a', '재조회 정본', minute: 1), _m('b', '둘째', minute: 2)]);
      expect(c.length, 2);
      expect(c.items.first.body, '재조회 정본');
    });

    test('created_at 오름차순 정렬 · 동시각/미상은 도착 순서 유지', () {
      final IqMessagesController c = IqMessagesController();
      c.upsertFromServer(_m('b', '늦게 온 과거', minute: 1));
      c.upsertFromServer(_m('a', '먼저 온 미래', minute: 5));
      c.upsertFromServer(_m('c', '동시각1', minute: 5));
      expect(
        c.items.map((IqMessage m) => m.id).toList(),
        <String>['b', 'a', 'c'],
      );
    });
  });

  group('실시간 배선 — 채널 시작/정리·이벤트 반영', () {
    testWidgets('메시지 INSERT 중복 수신 → 말풍선 1개(중복 행 0)',
        (WidgetTester tester) async {
      final _FakeIqRealtime rt = _FakeIqRealtime();
      await _pump(
        tester,
        role: AppRole.student,
        status: IndividualQuestionStatus.answered,
        realtime: rt,
      );
      expect(rt.startCalls, 1);

      rt.onMessageInsert!(_m('m-1', '실시간 답변'));
      rt.onMessageInsert!(_m('m-1', '실시간 답변'));
      await tester.pumpAndSettle();

      expect(find.text('실시간 답변'), findsOneWidget);
    });

    testWidgets('dispose → 채널 정리(누수 0)', (WidgetTester tester) async {
      final _FakeIqRealtime rt = _FakeIqRealtime();
      await _pump(
        tester,
        role: AppRole.student,
        status: IndividualQuestionStatus.answered,
        realtime: rt,
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(rt.disposeCalls, 1);
    });
  });

  group('당사자 공용 컴포저(iq_append_message)', () {
    testWidgets('학생 answered: 본문 비면 전송 비활성 → 입력 시 활성 → 전송 1회',
        (WidgetTester tester) async {
      final List<(String, String)> log = <(String, String)>[];
      final _FakeIqRealtime rt = _FakeIqRealtime();
      await _pump(
        tester,
        role: AppRole.student,
        status: IndividualQuestionStatus.answered,
        realtime: rt,
        appendLog: log,
      );

      final Finder sendIcon = find.byIcon(Icons.send_rounded);
      final Finder sendBtn =
          find.ancestor(of: sendIcon, matching: find.byType(IconButton));
      expect(sendBtn, findsOneWidget);
      expect(tester.widget<IconButton>(sendBtn).onPressed, isNull,
          reason: '빈 본문 — 전송 비활성(첨부만 전송 없음)');

      await tester.enterText(find.byType(TextField).first, '여기 이해가 안 돼요');
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(sendBtn).onPressed, isNotNull);

      await tester.tap(sendIcon);
      await tester.pumpAndSettle();

      expect(log, <(String, String)>[('q1', '여기 이해가 안 돼요')]);
    });

    testWidgets('학생 종결(released) — 컴포저 미노출(서버 QUESTION_LOCKED 게이트 미러)',
        (WidgetTester tester) async {
      await _pump(
        tester,
        role: AppRole.student,
        status: IndividualQuestionStatus.released,
        realtime: _FakeIqRealtime(),
      );
      expect(find.byTooltip('보내기'), findsNothing);
    });

    testWidgets('멘토 answered: 추가 답글 컴포저 노출 + append 경로 전송',
        (WidgetTester tester) async {
      final List<(String, String)> log = <(String, String)>[];
      await _pump(
        tester,
        role: AppRole.mentor,
        status: IndividualQuestionStatus.answered,
        realtime: _FakeIqRealtime(),
        appendLog: log,
      );

      await tester.enterText(find.byType(TextField).first, '추가 설명이에요');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(log, <(String, String)>[('q1', '추가 설명이에요')]);
    });

    testWidgets('멘토 claimed(첫 답변 전) — 기존 답변 컴포저 유지·append 컴포저 없음',
        (WidgetTester tester) async {
      await _pump(
        tester,
        role: AppRole.mentor,
        status: IndividualQuestionStatus.claimed,
        realtime: _FakeIqRealtime(),
      );
      expect(find.text('답변 등록'), findsOneWidget); // answer_individual_question 경로
      expect(find.byTooltip('보내기'), findsNothing);
    });
  });
}
