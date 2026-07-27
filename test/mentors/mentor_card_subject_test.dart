import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/mentors/data/mentor_models.dart';
import 'package:ssambership_app/features/mentors/ui/widgets/mentor_card.dart';

/// 멘토 카드가 raw 과목 코드를 한글 라벨로 표시하고, 코드를 화면에 노출하지 않는지 검증.
MentorListItem _m(List<String> subjects) => MentorListItem(
      id: 'x',
      nickname: '멘토',
      profile: MentorProfileInfo(
        userId: 'x',
        teachingSubjects: subjects,
      ),
    );

Future<void> _pump(WidgetTester tester, List<String> subjects) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: MentorCard(item: _m(subjects), onOpen: () {}),
    ),
  ));
}

void main() {
  testWidgets('raw math → 카드에 수학 표시, math 코드 비노출', (WidgetTester tester) async {
    await _pump(tester, <String>['math']);
    expect(find.text('수학'), findsOneWidget);
    expect(find.text('math'), findsNothing);
  });

  testWidgets('raw math_calculus → 카드에 미적분 표시', (WidgetTester tester) async {
    await _pump(tester, <String>['math_calculus']);
    expect(find.text('미적분'), findsOneWidget);
    expect(find.text('math_calculus'), findsNothing);
  });

  testWidgets('미지 ASCII 코드 → 기타 표시, raw code 비노출', (WidgetTester tester) async {
    await _pump(tester, <String>['unknown_subject']);
    expect(find.text('기타'), findsOneWidget);
    expect(find.text('unknown_subject'), findsNothing);
  });

  testWidgets('한글 자유 라벨(코딩)은 그대로 표시', (WidgetTester tester) async {
    await _pump(tester, <String>['코딩']);
    expect(find.text('코딩'), findsOneWidget);
  });

  testWidgets('수학+math 혼재 → 수학 칩 1개만', (WidgetTester tester) async {
    await _pump(tester, <String>['수학', 'math']);
    expect(find.text('수학'), findsOneWidget);
  });
}
