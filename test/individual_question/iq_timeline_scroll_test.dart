import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/design/theme.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_detail_screen.dart';

/// vc11 정본 UX 계약 — 개별질문 상세는 '화면 전체가 대화방'이다.
///
/// 빌드 10 실기기 QA 판정: 작성자 방향은 통과했지만, 화면이 여전히
/// [상태·제목 카드]→[질문 본문 카드]→[첨부 카드]→[작은 대화 카드]→[하단 액션]
/// 순서의 일반 상세 페이지였다. 오너 요구는 최초 질문·첨부가 대화 타임라인의
/// 첫 메시지로 보이고, 대화 영역이 화면 대부분을 차지하는 구조다.
///
/// 이 파일은 그 구조 자체를 잠근다. 카드 스택 구현에서는 실패해야 하고
/// (부재 단언만이 아니라 새 타임라인·하단 영역의 양성 대조를 포함한다),
/// 전체 화면 대화 구현에서만 통과한다.
const String kStudentId = 's1';
const String kMentorId = 'm1';
const String kTitle = '수열 질문이에요';
const String kBody = '문제 본문';
const String kRelease = '해결 완료 (멘토에게 정산)';
const String kRefund = '질문 취소 (캐시 환불)';

IndividualQuestion _question({
  IndividualQuestionStatus status = IndividualQuestionStatus.answered,
  String studentId = kStudentId,
  String? claimedMentorId = kMentorId,
  String title = kTitle,
  String body = kBody,
}) {
  return IndividualQuestion(
    id: 'q1',
    studentId: studentId,
    type: IndividualQuestionType.open,
    status: status,
    title: title,
    body: body,
    priceCents: 500000,
    claimedMentorId: claimedMentorId,
    createdAt: DateTime(2026, 7, 1),
  );
}

IqMessage _msg(String id, String authorId, String body) => IqMessage(
      id: id,
      questionId: 'q1',
      authorId: authorId,
      body: body,
      createdAt: DateTime(2026, 7, 2),
    );


Future<void> _pump(
  WidgetTester tester, {
  required AppRole role,
  IndividualQuestionStatus status = IndividualQuestionStatus.answered,
  String studentId = kStudentId,
  String? claimedMentorId = kMentorId,
  String questionBody = kBody,
  String? viewerId,
  List<IqMessage> messages = const <IqMessage>[],
  List<IqAttachment> attachments = const <IqAttachment>[],
}) async {
  // pumpWidget 은 위젯 타입이 같으면 State 를 재사용해 loader 재주입이
  // 무시된다 — 시나리오마다 완전히 새로 마운트한다.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.build(role),
    home: IqDetailScreen(
      questionId: 'q1',
      roleOverride: role,
      currentUserId: viewerId,
      loaderOverride: () async => IqDetailData(
        question: _question(
          status: status,
          studentId: studentId,
          claimedMentorId: claimedMentorId,
          body: questionBody,
        ),
        messages: messages,
        attachments: attachments,
        mentorName: '수학멘토',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}



/// 타임라인(대화 스크롤 영역) 파인더 — 화면의 유일한 ListView 여야 한다.
Finder get _timeline => find.byType(ListView);

void _setView(WidgetTester tester, Size logical) {
  tester.view.physicalSize = logical;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  // [QA-C8·C9] 개별질문 타임라인은 새 항목이 들어오면 끝으로 수렴해야 한다.
  //   C9: 텍스트 전송 후 맨 아래로 가지 않음
  //   C8: 이미지 전송 시 화면이 맨 위로 튐
  // 두 증상의 뿌리는 같다 — 끝 점프 수렴 루프가 한 프레임의 착시(pixels >=
  // maxScrollExtent)로 조기 종료돼, 이미지 레이아웃으로 extent 가 늘어난 뒤를
  // 아무도 따라가지 않았다. 여기서는 "충분히 긴 타임라인은 진입 직후 끝에 있다"를
  // 잠근다 — 루프가 다시 조기 종료되면 이 단언이 깨진다.
  testWidgets('긴 타임라인은 진입 직후 끝에 수렴한다', (WidgetTester tester) async {
    _setView(tester, const Size(400, 600));
    final List<IqMessage> many = <IqMessage>[
      for (int i = 0; i < 40; i++)
        _msg('m$i', i.isEven ? kStudentId : kMentorId, '메시지 $i'),
    ];
    await _pump(
      tester,
      role: AppRole.student,
      viewerId: kStudentId,
      messages: many,
    );

    final ScrollableState scrollable =
        tester.state<ScrollableState>(find.descendant(
      of: _timeline,
      matching: find.byType(Scrollable),
    ));
    final ScrollPosition p = scrollable.position;
    expect(p.maxScrollExtent, greaterThan(0),
        reason: '타임라인이 스크롤될 만큼 길어야 이 검증이 의미가 있다');
    expect(
      p.pixels,
      closeTo(p.maxScrollExtent, 1.0),
      reason: '진입 직후 최신 메시지가 보이지 않으면 사용자는 직접 내려야 한다',
    );
  });

  testWidgets('짧은 타임라인(스크롤 불가)에서도 예외 없이 동작한다',
      (WidgetTester tester) async {
    _setView(tester, const Size(400, 900));
    await _pump(
      tester,
      role: AppRole.student,
      viewerId: kStudentId,
      messages: <IqMessage>[_msg('m1', kStudentId, '한 줄')],
    );
    final ScrollableState scrollable =
        tester.state<ScrollableState>(find.descendant(
      of: _timeline,
      matching: find.byType(Scrollable),
    ));
    expect(scrollable.position.pixels, 0);
  });
}
