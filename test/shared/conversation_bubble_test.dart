import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/design/app_theme.dart';
import 'package:ssambership_app/design/role_theme.dart';
import 'package:ssambership_app/design/tokens/app_colors.dart';
import 'package:ssambership_app/shared/conversation_ui/conversation_bubble.dart';

/// ★ 반드시 RoleTheme(role) 로 역할을 구성한다.
///   RoleTheme 을 안 두르면 RoleTheme.of 가 조용히 student 폴백을 주기 때문에
///   멘토 강조색 단언이 '엉뚱한 이유로' 통과한다.
Widget _themed(AppRole role, Widget child) => RoleTheme(
      role: role,
      child: MaterialApp(
        theme: AppTheme.build(role: role),
        home: Scaffold(body: child),
      ),
    );

Container _bubbleBox(WidgetTester tester) => tester.widget<Container>(
      find
          .descendant(
            of: find.byType(ConversationBubble),
            matching: find.byType(Container),
          )
          .first,
    );

Row _bubbleRow(WidgetTester tester) => tester.widget<Row>(
      find
          .descendant(
            of: find.byType(ConversationBubble),
            matching: find.byType(Row),
          )
          .first,
    );

void main() {
  testWidgets('align=end → 우측 정렬', (WidgetTester tester) async {
    await tester.pumpWidget(_themed(
      AppRole.student,
      const ConversationBubble(body: '안녕', align: ConversationAlign.end),
    ));
    expect(_bubbleRow(tester).mainAxisAlignment, MainAxisAlignment.end);
  });

  testWidgets('align=start → 좌측 정렬', (WidgetTester tester) async {
    await tester.pumpWidget(_themed(
      AppRole.student,
      const ConversationBubble(body: '안녕', align: ConversationAlign.start),
    ));
    expect(_bubbleRow(tester).mainAxisAlignment, MainAxisAlignment.start);
  });

  testWidgets('align=center → 가운데 정렬(작성자 미확정용)', (WidgetTester tester) async {
    await tester.pumpWidget(_themed(
      AppRole.student,
      const ConversationBubble(body: '안녕', align: ConversationAlign.center),
    ));
    expect(_bubbleRow(tester).mainAxisAlignment, MainAxisAlignment.center);
  });

  testWidgets('tone=neutral → 유리 실효색(불투명) 채움', (WidgetTester tester) async {
    await tester.pumpWidget(_themed(
      AppRole.student,
      const ConversationBubble(body: '안녕'),
    ));
    final BoxDecoration d = _bubbleBox(tester).decoration! as BoxDecoration;
    expect(d.color, AppColors.glass);
  });

  testWidgets('tone=accent → 학생 역할색(불투명) 채움', (WidgetTester tester) async {
    await tester.pumpWidget(_themed(
      AppRole.student,
      const ConversationBubble(body: '안녕', tone: ConversationTone.accent),
    ));
    final BoxDecoration d = _bubbleBox(tester).decoration! as BoxDecoration;
    expect(d.color, RoleColors.student);
  });

  testWidgets('tone=accent → 멘토 역할에서는 멘토 초록(거울상 색)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_themed(
      AppRole.mentor,
      const ConversationBubble(body: '안녕', tone: ConversationTone.accent),
    ));
    final BoxDecoration d = _bubbleBox(tester).decoration! as BoxDecoration;
    expect(d.color, RoleColors.mentor);
    expect(d.color, isNot(RoleColors.student));
  });

  testWidgets('꼬리 모서리 거울상(end=우하단 각짐 / start=좌하단 각짐)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_themed(
      AppRole.student,
      const ConversationBubble(body: '안녕', align: ConversationAlign.end),
    ));
    BoxDecoration d = _bubbleBox(tester).decoration! as BoxDecoration;
    BorderRadius r = d.borderRadius! as BorderRadius;
    expect(r.bottomRight.x, ConversationMetrics.tailRadius);
    expect(r.bottomLeft.x, isNot(ConversationMetrics.tailRadius));

    await tester.pumpWidget(_themed(
      AppRole.student,
      const ConversationBubble(body: '안녕', align: ConversationAlign.start),
    ));
    d = _bubbleBox(tester).decoration! as BoxDecoration;
    r = d.borderRadius! as BorderRadius;
    expect(r.bottomLeft.x, ConversationMetrics.tailRadius);
    expect(r.bottomRight.x, isNot(ConversationMetrics.tailRadius));
  });

  testWidgets('최대 폭 = 화면 폭 72%', (WidgetTester tester) async {
    await tester.pumpWidget(_themed(
      AppRole.student,
      const ConversationBubble(body: '안녕'),
    ));
    final double screen =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(
      _bubbleBox(tester).constraints!.maxWidth,
      closeTo(screen * ConversationMetrics.maxWidthFactor, 0.01),
    );
  });

  testWidgets('timeLabel 은 받은 문자열 그대로 렌더, null 이면 미노출',
      (WidgetTester tester) async {
    await tester.pumpWidget(_themed(
      AppRole.student,
      const ConversationBubble(body: '안녕', timeLabel: '09:05'),
    ));
    expect(find.text('09:05'), findsOneWidget);

    await tester.pumpWidget(_themed(
      AppRole.student,
      const ConversationBubble(body: '안녕'),
    ));
    expect(find.text('09:05'), findsNothing);
  });

  testWidgets('authorLabel 렌더, null 이면 미노출', (WidgetTester tester) async {
    await tester.pumpWidget(_themed(
      AppRole.student,
      const ConversationBubble(body: '안녕', authorLabel: '학생'),
    ));
    expect(find.text('학생'), findsOneWidget);

    await tester.pumpWidget(_themed(
      AppRole.student,
      const ConversationBubble(body: '안녕'),
    ));
    expect(find.text('학생'), findsNothing);
  });

  testWidgets('titleLabel 은 본문 위 제목 줄로 렌더, null 이면 미노출',
      (WidgetTester tester) async {
    await tester.pumpWidget(_themed(
      AppRole.student,
      const ConversationBubble(body: '본문', titleLabel: '제목 줄'),
    ));
    expect(find.text('제목 줄'), findsOneWidget);
    // 제목이 본문보다 위에 있다(같은 말풍선 안 한 그룹).
    expect(
      tester.getTopLeft(find.text('제목 줄')).dy,
      lessThan(tester.getTopLeft(find.text('본문')).dy),
    );

    await tester.pumpWidget(_themed(
      AppRole.student,
      const ConversationBubble(body: '본문'),
    ));
    expect(find.text('제목 줄'), findsNothing);
  });

  testWidgets('본문 빈 문자열 + 첨부만 → 첨부만 렌더', (WidgetTester tester) async {
    await tester.pumpWidget(_themed(
      AppRole.student,
      const ConversationBubble(
        body: '',
        attachments: <Widget>[Text('첨부칩')],
      ),
    ));
    expect(find.text('첨부칩'), findsOneWidget);
  });
}
