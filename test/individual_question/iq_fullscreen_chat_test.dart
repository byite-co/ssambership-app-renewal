import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/design/app_theme.dart';
import 'package:ssambership_app/design/role_theme.dart' as design;
import 'package:ssambership_app/design/widgets/glass_card.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_detail_screen.dart';
import 'package:ssambership_app/shared/conversation_ui/conversation_bubble.dart';
import '../support/app_scope_test_harness.dart';

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

/// 학생 작성 이미지(author_id 정본) — 최초 질문 말풍선 귀속 검증용.
/// 작성자 미기록 레거시는 중립 그룹으로 빠진다(iq_media_attribution_test).
const IqAttachment _image = IqAttachment(
  id: 'a1',
  storagePath: 'q1/1-000001.png',
  authorId: kStudentId,
  fileName: '문제.png',
  mimeType: 'image/png',
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
  await tester.pumpScopedWidget(const SizedBox.shrink());
  await tester.pumpScopedWidget(design.RoleTheme(
    role: _designRole(role),
    child: MaterialApp(
    theme: AppTheme.build(role: _designRole(role)),
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
  ),
  ));
  await tester.pumpAndSettle();
}

Finder _bubble(String body) => find.byWidgetPredicate(
      (Widget w) => w is ConversationBubble && w.body == body,
    );

ConversationBubble _bubbleWidget(WidgetTester tester, String body) {
  final Finder f = _bubble(body);
  expect(f, findsOneWidget, reason: '본문 "$body" 말풍선을 찾지 못했다');
  return tester.widget<ConversationBubble>(f);
}

/// 타임라인(대화 스크롤 영역) 파인더 — 화면의 유일한 ListView 여야 한다.
Finder get _timeline => find.byType(ListView);

void _setView(WidgetTester tester, Size logical) {
  tester.view.physicalSize = logical;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 인증 역할 → 테마 역할(멘토만 초록). 화면이 RoleTheme 을 읽으므로 감싼다.
design.AppRole _designRole(AppRole role) =>
    role == AppRole.mentor ? design.AppRole.mentor : design.AppRole.student;

void main() {
  group('A. 전체 화면 구조 — 카드 스택이 아니라 대화방', () {
    testWidgets('GlassCard 스택 0 — 질문·첨부·대화 카드와 그 헤더가 모두 사라진다',
        (WidgetTester tester) async {
      await _pump(
        tester,
        role: AppRole.student,
        messages: <IqMessage>[_msg('a', kMentorId, '이렇게 풀어요')],
        attachments: const <IqAttachment>[_image],
      );

      expect(find.byType(GlassCard), findsNothing,
          reason: '상세 화면 어디에도 GlassCard 스택이 남으면 안 된다');
      expect(find.text('질문'), findsNothing, reason: '독립 질문 카드 헤더 금지');
      expect(find.text('첨부'), findsNothing, reason: '타임라인 밖 첨부 섹션 금지');
      expect(find.text('대화'), findsNothing, reason: '작은 중첩 대화 카드 금지');
    });

    testWidgets('타임라인이 Expanded 가 소유한 주 영역이다', (WidgetTester tester) async {
      await _pump(tester,
          role: AppRole.student,
          messages: <IqMessage>[_msg('a', kMentorId, '답변')]);

      expect(_timeline, findsOneWidget);
      expect(find.ancestor(of: _timeline, matching: find.byType(Expanded)),
          findsWidgets,
          reason: '대화 타임라인은 남는 세로 공간 전부를 차지해야 한다');
    });

    testWidgets('학생 하단 액션은 타임라인 스크롤 밖에 고정된다', (WidgetTester tester) async {
      await _pump(tester,
          role: AppRole.student,
          messages: <IqMessage>[_msg('a', kMentorId, '답변')]);

      expect(find.text(kRelease), findsOneWidget);
      expect(find.descendant(of: _timeline, matching: find.text(kRelease)),
          findsNothing,
          reason: '상태 액션은 타임라인과 함께 스크롤되면 안 된다');
    });

    testWidgets('멘토 답변 컴포저도 타임라인 스크롤 밖에 고정된다', (WidgetTester tester) async {
      await _pump(tester,
          role: AppRole.mentor, status: IndividualQuestionStatus.claimed);

      expect(find.text('답변 등록'), findsOneWidget);
      expect(find.descendant(of: _timeline, matching: find.text('답변 등록')),
          findsNothing);
      expect(find.descendant(of: _timeline, matching: find.byType(TextField)),
          findsNothing,
          reason: '답변 입력은 하단 고정 영역 소속이어야 한다');
    });

    testWidgets('종결 상태 안내도 하단 영역에 남는다(빈 액션 영역 금지)',
        (WidgetTester tester) async {
      for (final IndividualQuestionStatus s in <IndividualQuestionStatus>[
        IndividualQuestionStatus.refunded,
        IndividualQuestionStatus.expired,
        IndividualQuestionStatus.canceled,
      ]) {
        for (final AppRole role in <AppRole>[AppRole.student, AppRole.mentor]) {
          await _pump(tester, role: role, status: s);
          final String notice = iqReadOnlyNotice(s)!;
          expect(find.text(notice), findsOneWidget, reason: '$role/$s');
          expect(find.descendant(of: _timeline, matching: find.text(notice)),
              findsNothing,
              reason: '$role/$s: 안내는 하단 고정 영역에 있어야 한다');
        }
      }

      // released 도 동일 — 학생/멘토 각자의 안내 문구가 하단 영역에 남는다.
      await _pump(tester,
          role: AppRole.student, status: IndividualQuestionStatus.released);
      expect(
          find.descendant(
              of: _timeline, matching: find.textContaining('해결 완료했어요')),
          findsNothing);
      expect(find.textContaining('해결 완료했어요'), findsOneWidget);

      await _pump(tester,
          role: AppRole.mentor, status: IndividualQuestionStatus.released);
      expect(find.text('정산이 완료된 질문이에요.'), findsOneWidget);
      expect(
          find.descendant(of: _timeline, matching: find.text('정산이 완료된 질문이에요.')),
          findsNothing);
    });
  });

  group('B. 원본 질문 = 첫 대화 항목', () {
    testWidgets('원본 질문이 학생 말풍선으로 타임라인 맨 위에 온다', (WidgetTester tester) async {
      await _pump(tester,
          role: AppRole.student,
          messages: <IqMessage>[_msg('a', kMentorId, '이렇게 풀어요')]);

      final List<ConversationBubble> bubbles = tester
          .widgetList<ConversationBubble>(find.byType(ConversationBubble))
          .toList();
      expect(bubbles, hasLength(2));
      expect(bubbles.first.body, kBody, reason: '첫 대화 항목은 원본 질문 본문');
      expect(bubbles.first.authorLabel, '학생',
          reason: '질문 작성자는 정의상 학생(question.student_id)');

      // 제목도 첫 말풍선 그룹 안에서 함께 보인다(별도 카드 금지).
      expect(find.descendant(of: _bubble(kBody), matching: find.text(kTitle)),
          findsOneWidget);

      // 위치: 질문이 후속 메시지보다 위.
      expect(
        tester.getTopLeft(_bubble(kBody)).dy,
        lessThan(tester.getTopLeft(_bubble('이렇게 풀어요')).dy),
      );
    });

    testWidgets('원본 첨부는 첫 질문 항목에 붙는다 — 대화 이전 섹션 금지',
        (WidgetTester tester) async {
      await _pump(
        tester,
        role: AppRole.student,
        messages: <IqMessage>[_msg('a', kMentorId, '답변')],
        attachments: const <IqAttachment>[_image],
      );

      // 저장(당사자 다운로드) 액션이 질문 말풍선 그룹 내부에 있다 = 첨부가
      // 첫 타임라인 항목에 통합됐다는 양성 대조.
      expect(find.descendant(of: _bubble(kBody), matching: find.text('저장')),
          findsOneWidget);
      expect(find.text('첨부'), findsNothing);
    });

    testWidgets('첨삭 폐쇄(2026-08): 질문 항목 첨부에도 첨삭하기 미노출',
        (WidgetTester tester) async {
      // 첨삭 기능이 제품에서 닫혀 있는 동안 진입 버튼을 노출하지 않는다 —
      // 재개 시 iq_detail_screen._canAnnotateGroup 원복과 함께 되살릴 것.
      await _pump(
        tester,
        role: AppRole.mentor,
        status: IndividualQuestionStatus.claimed,
        attachments: const <IqAttachment>[_image],
      );

      expect(find.descendant(of: _bubble(kBody), matching: find.text('첨삭하기')),
          findsNothing);
      // 첨부 카드 자체는 살아 있다 — 저장(다운로드) 유지.
      expect(find.descendant(of: _bubble(kBody), matching: find.text('저장')),
          findsOneWidget);
    });

    testWidgets('메시지 0건 → 질문 말풍선 하나만 자연스럽게 보인다', (WidgetTester tester) async {
      await _pump(tester,
          role: AppRole.student, status: IndividualQuestionStatus.escrowed);

      final List<ConversationBubble> bubbles = tester
          .widgetList<ConversationBubble>(find.byType(ConversationBubble))
          .toList();
      expect(bubbles, hasLength(1));
      expect(bubbles.single.body, kBody);
    });

    testWidgets('시간순: 원본 질문 → 메시지 작성순', (WidgetTester tester) async {
      await _pump(tester, role: AppRole.student, messages: <IqMessage>[
        _msg('a', kStudentId, '추가 질문'),
        _msg('b', kMentorId, '답변'),
      ]);

      final List<String> bodies = tester
          .widgetList<ConversationBubble>(find.byType(ConversationBubble))
          .map((ConversationBubble b) => b.body)
          .toList();
      expect(bodies, <String>[kBody, '추가 질문', '답변']);
    });
  });

  group('C. 작성자 방향 — 질문 말풍선도 같은 규칙', () {
    testWidgets('학생 뷰어: 내 질문 우측 강조 / 멘토 뷰어: 좌측 중립',
        (WidgetTester tester) async {
      await _pump(tester,
          role: AppRole.student,
          viewerId: kStudentId,
          messages: <IqMessage>[_msg('a', kMentorId, '답변')]);
      ConversationBubble q = _bubbleWidget(tester, kBody);
      expect(q.align, ConversationAlign.end);
      expect(q.tone, ConversationTone.accent);

      await _pump(tester,
          role: AppRole.mentor,
          viewerId: kMentorId,
          status: IndividualQuestionStatus.claimed,
          messages: <IqMessage>[_msg('a', kMentorId, '답변')]);
      q = _bubbleWidget(tester, kBody);
      expect(q.align, ConversationAlign.start);
      expect(q.tone, ConversationTone.neutral);
      expect(q.authorLabel, '학생');
    });

    testWidgets('빈 student_id 는 절대 매칭되지 않는다 — 질문 말풍선도 미확인 중립',
        (WidgetTester tester) async {
      await _pump(tester,
          role: AppRole.student, studentId: '', viewerId: kStudentId);

      final ConversationBubble q = _bubbleWidget(tester, kBody);
      expect(q.authorLabel, '작성자 미확인');
      expect(q.tone, ConversationTone.neutral);
      expect(q.align, ConversationAlign.start);
    });
  });

  group('D. 뷰포트 계약 — 실기기 대표 해상도', () {
    final List<IqMessage> many = <IqMessage>[
      for (int i = 1; i <= 12; i++)
        _msg('m$i', i.isEven ? kMentorId : kStudentId,
            '메시지 $i — 긴 본문이 줄바꿈되어도 가로 오버플로가 없어야 한다. 수열의 일반항을 구하는 과정.'),
    ];
    const String longBody = '질문 본문 첫머리. 아주 긴 질문 본문이 말풍선 폭 안에서 줄바꿈되는지 확인한다. '
        '점화식 a(n+1) = 2a(n) + 3 에서 일반항을 구하는 과정을 자세히 알려주세요. '
        '치환을 어떻게 잡는지, 왜 그렇게 잡는지가 궁금해요.';

    for (final Size size in const <Size>[
      Size(360, 800),
      Size(390, 844),
      Size(411, 891),
      Size(844, 390), // 가로 모드
    ]) {
      testWidgets(
          '(${size.width.toInt()}×${size.height.toInt()}) '
          '학생 answered: 오버플로 0 · 하단 액션 즉시 도달 · 처음/끝 도달',
          (WidgetTester tester) async {
        _setView(tester, size);
        await _pump(
          tester,
          role: AppRole.student,
          viewerId: kStudentId,
          questionBody: longBody,
          messages: many,
          attachments: const <IqAttachment>[_image],
        );
        expect(tester.takeException(), isNull);

        // 하단 액션은 스크롤 없이 항상 보인다(고정 영역).
        expect(find.text(kRelease).hitTestable(), findsOneWidget);

        // 끝(최신 메시지) 도달.
        await tester.drag(_timeline, const Offset(0, -8000));
        await tester.pumpAndSettle();
        expect(find.textContaining('메시지 12').hitTestable(), findsOneWidget);

        // 처음(원본 질문) 도달 — 위로 스크롤하면 항상 돌아갈 수 있다.
        await tester.drag(_timeline, const Offset(0, 8000));
        await tester.pumpAndSettle();
        expect(find.textContaining('질문 본문 첫머리').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('초기 위치: 메시지가 있으면 최신 대화 근처에서 시작한다', (WidgetTester tester) async {
      _setView(tester, const Size(390, 844));
      final List<IqMessage> twenty = <IqMessage>[
        for (int i = 1; i <= 20; i++)
          _msg('m$i', i.isEven ? kMentorId : kStudentId,
              '메시지 $i — 초기 스크롤 위치 확인용 본문.'),
      ];
      await _pump(tester,
          role: AppRole.student, viewerId: kStudentId, messages: twenty);

      expect(find.textContaining('메시지 20').hitTestable(), findsOneWidget,
          reason: '최신 메시지가 첫 화면에 보여야 한다');
      expect(find.textContaining('메시지 1 —').hitTestable(), findsNothing,
          reason: '타임라인이 맨 위(질문)에서 시작하면 안 된다');
    });

    testWidgets('(390×844) 키보드가 열려도 답변 입력·등록이 가려지지 않는다',
        (WidgetTester tester) async {
      _setView(tester, const Size(390, 844));
      await _pump(
        tester,
        role: AppRole.mentor,
        status: IndividualQuestionStatus.claimed,
        messages: <IqMessage>[_msg('a', kStudentId, '추가 질문')],
        attachments: const <IqAttachment>[_image],
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 300); // IME
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('답변 등록').hitTestable(), findsOneWidget);
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
    });

    testWidgets('(844×390) 가로 모드 멘토 claimed: 고정 컴포저가 넘치지 않는다',
        (WidgetTester tester) async {
      _setView(tester, const Size(844, 390));
      await _pump(tester,
          role: AppRole.mentor, status: IndividualQuestionStatus.claimed);

      expect(tester.takeException(), isNull);
      expect(find.text('답변 등록').hitTestable(), findsOneWidget);
    });
  });
}
