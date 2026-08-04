import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/design/theme.dart';
import 'package:ssambership_app/features/individual_question/data/iq_realtime.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_detail_screen.dart';
import 'package:ssambership_app/shared/conversation_ui/conversation_bubble.dart';

/// §2-1 대화 타임라인 미디어 귀속 렌더 계약.
///
/// - 학생 첨부는 학생 말풍선(최초 질문·학생 메시지)에, 멘토 첨부는 멘토
///   메시지에 붙는다 — 전체 첨부를 질문 말풍선에 합치지 않는다.
/// - `message_id = null` + 작성자 미기록 레거시는 '이전 첨부 · 작성자 미확인'
///   중립 그룹으로만 표시한다(백필·추측 금지).
/// - 좌우 거울상은 뷰어 uid 기준(학생 뷰 ↔ 멘토 뷰 미러).
/// - 새로고침·실시간 재조회 후에도 같은 귀속(중복 0).
const String kStudentId = 's1';
const String kMentorId = 'm1';

IndividualQuestion _question({
  IndividualQuestionStatus status = IndividualQuestionStatus.answered,
}) =>
    IndividualQuestion(
      id: 'q1',
      studentId: kStudentId,
      type: IndividualQuestionType.open,
      status: status,
      title: '수열 질문이에요',
      body: '문제 본문',
      priceCents: 500000,
      claimedMentorId: kMentorId,
      createdAt: DateTime(2026, 7, 1),
    );

IqMessage _msg(String id, String authorId, String body, {int minute = 0}) =>
    IqMessage(
      id: id,
      questionId: 'q1',
      authorId: authorId,
      body: body,
      createdAt: DateTime(2026, 7, 2, 10, minute),
    );

/// 서명 URL 은 해석하지 않는다 — 파일명 행으로 렌더되는 비이미지 첨부를 써서
/// 네트워크 이미지를 피한다(첨부 파일명이 귀속 단언의 앵커).
IqAttachment _fileAtt(String id, {String? messageId, String? authorId}) =>
    IqAttachment(
      id: id,
      storagePath: 'q1/$id.pdf',
      messageId: messageId,
      authorId: authorId,
      fileName: '$id.pdf',
      mimeType: 'application/pdf',
      createdAt: DateTime(2026, 7, 2, 11),
    );

Future<void> _pump(
  WidgetTester tester, {
  required AppRole role,
  String? viewerId,
  List<IqMessage> messages = const <IqMessage>[],
  List<IqAttachment> attachments = const <IqAttachment>[],
  Future<IqDetailData> Function()? loader,
  IqRealtimePort Function(String)? realtimeFactory,
}) async {
  // 긴 타임라인에서도 전 말풍선이 마운트되게 세로로 넉넉한 뷰포트를 쓴다
  // (ListView lazy mount — 화면 밖 항목은 파인더에 잡히지 않는다).
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.build(role),
    home: IqDetailScreen(
      questionId: 'q1',
      roleOverride: role,
      currentUserId: viewerId,
      realtimeFactoryOverride: realtimeFactory,
      loaderOverride: loader ??
          () async => IqDetailData(
                question: _question(),
                messages: messages,
                attachments: attachments,
                mentorName: '수학멘토',
              ),
    ),
  ));
  await tester.pumpAndSettle();
}

ConversationBubble _bubbleWithBody(WidgetTester tester, String body) {
  final Finder f = find.byWidgetPredicate(
    (Widget w) => w is ConversationBubble && w.body == body,
  );
  expect(f, findsOneWidget, reason: '본문 "$body" 말풍선을 찾지 못했다');
  return tester.widget<ConversationBubble>(f);
}

Finder _inBubble(String body, String text) => find.descendant(
      of: find.byWidgetPredicate(
          (Widget w) => w is ConversationBubble && w.body == body),
      matching: find.text(text),
    );

void main() {
  testWidgets('학생 후속 메시지 첨부는 그 학생 메시지 말풍선에 붙는다(질문 말풍선 아님)',
      (WidgetTester tester) async {
    await _pump(
      tester,
      role: AppRole.student,
      messages: <IqMessage>[_msg('m-1', kStudentId, '추가 질문이에요')],
      attachments: <IqAttachment>[
        _fileAtt('followup', messageId: 'm-1', authorId: kStudentId),
      ],
    );

    expect(_inBubble('추가 질문이에요', 'followup.pdf'), findsOneWidget);
    expect(_inBubble('문제 본문', 'followup.pdf'), findsNothing,
        reason: '메시지 연결 첨부가 질문 말풍선으로 합쳐지면 안 된다');
  });

  testWidgets('멘토 답변 첨부는 멘토 메시지 말풍선에 멘토 라벨로 붙는다',
      (WidgetTester tester) async {
    await _pump(
      tester,
      role: AppRole.student,
      messages: <IqMessage>[_msg('m-1', kMentorId, '이렇게 풀어요')],
      attachments: <IqAttachment>[
        _fileAtt('solution', messageId: 'm-1', authorId: kMentorId),
      ],
    );

    expect(_inBubble('이렇게 풀어요', 'solution.pdf'), findsOneWidget);
    expect(_inBubble('문제 본문', 'solution.pdf'), findsNothing);
    expect(_bubbleWithBody(tester, '이렇게 풀어요').authorLabel, '멘토');
  });

  testWidgets('최초 질문 첨부(학생 작성·미연결)는 질문 말풍선에 남는다',
      (WidgetTester tester) async {
    await _pump(
      tester,
      role: AppRole.student,
      messages: <IqMessage>[_msg('m-1', kMentorId, '답변')],
      attachments: <IqAttachment>[_fileAtt('original', authorId: kStudentId)],
    );

    expect(_inBubble('문제 본문', 'original.pdf'), findsOneWidget);
    expect(_inBubble('답변', 'original.pdf'), findsNothing);
  });

  testWidgets('레거시(message_id·작성자 모두 없음)는 중립 그룹 — 학생·멘토 말풍선 금지',
      (WidgetTester tester) async {
    await _pump(
      tester,
      role: AppRole.student,
      messages: <IqMessage>[_msg('m-1', kMentorId, '답변')],
      attachments: <IqAttachment>[_fileAtt('legacy')],
    );

    expect(find.text('이전 첨부 · 작성자 미확인'), findsOneWidget);
    expect(_inBubble('문제 본문', 'legacy.pdf'), findsNothing,
        reason: '작성자 미확인 레거시를 학생 말풍선에 넣으면 안 된다');
    expect(_inBubble('답변', 'legacy.pdf'), findsNothing);
    expect(_inBubble('', 'legacy.pdf'), findsOneWidget); // 중립 그룹 소속.

    final ConversationBubble neutral = _bubbleWithBody(tester, '');
    expect(neutral.tone, ConversationTone.neutral);
    expect(neutral.align, ConversationAlign.start);
  });

  testWidgets('멘토 작성·미연결 첨부는 멘토 라벨 그룹 — 학생 말풍선 금지',
      (WidgetTester tester) async {
    await _pump(
      tester,
      role: AppRole.student,
      attachments: <IqAttachment>[_fileAtt('mentor-old', authorId: kMentorId)],
    );

    expect(_inBubble('문제 본문', 'mentor-old.pdf'), findsNothing);
    final ConversationBubble group = _bubbleWithBody(tester, '');
    expect(group.authorLabel, '멘토');
  });

  testWidgets('다중 타임라인: 양측 메시지·첨부가 각자 말풍선에 정확히 귀속된다',
      (WidgetTester tester) async {
    await _pump(
      tester,
      role: AppRole.student,
      messages: <IqMessage>[
        _msg('m-1', kStudentId, '추가 질문', minute: 1),
        _msg('m-2', kMentorId, '첫 답변', minute: 2),
        _msg('m-3', kMentorId, '후속 답글', minute: 3),
      ],
      attachments: <IqAttachment>[
        _fileAtt('q-img', authorId: kStudentId),
        _fileAtt('s-img', messageId: 'm-1', authorId: kStudentId),
        _fileAtt('a-img', messageId: 'm-2', authorId: kMentorId),
        _fileAtt('f-img', messageId: 'm-3', authorId: kMentorId),
      ],
    );

    expect(_inBubble('문제 본문', 'q-img.pdf'), findsOneWidget);
    expect(_inBubble('추가 질문', 's-img.pdf'), findsOneWidget);
    expect(_inBubble('첫 답변', 'a-img.pdf'), findsOneWidget);
    expect(_inBubble('후속 답글', 'f-img.pdf'), findsOneWidget);
    // 합쳐진 곳 없음 — 각 파일명은 화면 전체에서 1회만 보인다.
    for (final String name in <String>[
      'q-img.pdf', 's-img.pdf', 'a-img.pdf', 'f-img.pdf',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('학생 뷰 ↔ 멘토 뷰 좌우 거울상(첨부 소속 말풍선 기준)',
      (WidgetTester tester) async {
    final List<IqMessage> messages = <IqMessage>[
      _msg('m-1', kStudentId, '추가 질문', minute: 1),
      _msg('m-2', kMentorId, '첫 답변', minute: 2),
    ];
    final List<IqAttachment> attachments = <IqAttachment>[
      _fileAtt('s-img', messageId: 'm-1', authorId: kStudentId),
      _fileAtt('a-img', messageId: 'm-2', authorId: kMentorId),
    ];

    await _pump(tester,
        role: AppRole.student,
        viewerId: kStudentId,
        messages: messages,
        attachments: attachments);
    expect(_bubbleWithBody(tester, '추가 질문').align, ConversationAlign.end);
    expect(_bubbleWithBody(tester, '첫 답변').align, ConversationAlign.start);

    await _pump(tester,
        role: AppRole.mentor,
        viewerId: kMentorId,
        messages: messages,
        attachments: attachments);
    expect(_bubbleWithBody(tester, '추가 질문').align, ConversationAlign.start);
    expect(_bubbleWithBody(tester, '첫 답변').align, ConversationAlign.end);
  });

  testWidgets('작성자 불명 메시지의 첨부는 그 메시지에 붙고 라벨은 미확인 유지',
      (WidgetTester tester) async {
    await _pump(
      tester,
      role: AppRole.student,
      messages: <IqMessage>[_msg('m-x', 'x9', '운영 메모')],
      attachments: <IqAttachment>[_fileAtt('memo', messageId: 'm-x')],
    );

    expect(_inBubble('운영 메모', 'memo.pdf'), findsOneWidget);
    expect(_bubbleWithBody(tester, '운영 메모').authorLabel, '작성자 미확인');
    // 작성자 불명 메시지의 이미지에는 멘토 첨삭도 열리지 않는다(추측 금지)
    // — 첨삭 게이트는 iq_annotate_flow_test·iq_readonly_states_test 참조.
  });

  testWidgets('실시간 첨부 INSERT → 재조회 수렴 — 중복 첨부·중복 메시지 0',
      (WidgetTester tester) async {
    final _FakeRealtime rt = _FakeRealtime();
    int loads = 0;
    await _pump(
      tester,
      role: AppRole.student,
      realtimeFactory: (String _) => rt,
      loader: () async {
        loads++;
        return IqDetailData(
          question: _question(),
          messages: <IqMessage>[_msg('m-1', kMentorId, '첫 답변')],
          attachments: <IqAttachment>[
            _fileAtt('a-img', messageId: 'm-1', authorId: kMentorId),
          ],
          mentorName: '수학멘토',
        );
      },
    );
    expect(loads, 1);

    rt.onAttachmentInsert!(); // 실시간 신호 → 서버 재조회(payload 정본 금지).
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(find.text('a-img.pdf'), findsOneWidget, reason: '재조회 후 중복 0');
    expect(find.text('첫 답변'), findsOneWidget, reason: '메시지 중복 0');
    expect(_inBubble('첫 답변', 'a-img.pdf'), findsOneWidget,
        reason: '새로고침 후에도 동일한 귀속 유지');
  });
}

class _FakeRealtime implements IqRealtimePort {
  void Function(IqMessage message)? onMessageInsert;
  void Function()? onAttachmentInsert;

  @override
  void start({
    required void Function(IqMessage message) onMessageInsert,
    void Function()? onQuestionUpdate,
    void Function()? onAttachmentInsert,
    void Function()? onReconnected,
  }) {
    this.onMessageInsert = onMessageInsert;
    this.onAttachmentInsert = onAttachmentInsert;
  }

  @override
  Future<void> dispose() async {}
}
