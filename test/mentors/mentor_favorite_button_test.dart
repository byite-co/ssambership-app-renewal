import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/design/tokens/app_colors.dart';
import 'package:ssambership_app/features/mentors/ui/widgets/mentor_favorite_button.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

Icon _iconOf(WidgetTester tester) => tester.widget<Icon>(find.byType(Icon));

void main() {
  testWidgets('찜=파랑 채움 하트, 미찜=외곽선(muted), 탭 콜백', (WidgetTester tester) async {
    int taps = 0;

    // 미찜: 외곽선 + 보조색.
    await tester.pumpWidget(_wrap(
      MentorFavoriteButton(favorited: false, onTap: () => taps++),
    ));
    expect(_iconOf(tester).icon, Icons.favorite_border_rounded);
    expect(_iconOf(tester).color, AppColors.textSecondary);

    await tester.tap(find.byType(MentorFavoriteButton));
    expect(taps, 1);

    // 찜: 채움 + 학생 파랑(역할색 폴백).
    await tester.pumpWidget(_wrap(
      MentorFavoriteButton(favorited: true, onTap: () {}),
    ));
    expect(_iconOf(tester).icon, Icons.favorite_rounded);
    expect(_iconOf(tester).color, const Color(0xFF2563EB));
  });
}
