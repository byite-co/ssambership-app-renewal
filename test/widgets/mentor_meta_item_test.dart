import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/design/tokens/app_colors.dart';
import 'package:ssambership_app/features/mentors/ui/widgets/mentor_meta_item.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('아이콘 + 텍스트를 함께 렌더한다', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const MentorMetaItem(
      icon: Icons.school_rounded,
      text: 'KAIST · 물리학과',
    )));
    expect(find.text('KAIST · 물리학과'), findsOneWidget);
    expect(find.byIcon(Icons.school_rounded), findsOneWidget);
  });

  testWidgets('아이콘 색 기본은 보조색 토큰', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const MentorMetaItem(
        icon: Icons.menu_book_rounded, text: '수학 · 과학')));
    final Icon icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, AppColors.textSecondary);
    expect(icon.size, 16);
  });
}
