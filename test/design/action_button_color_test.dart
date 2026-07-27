import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/design/role_accent.dart';
import 'package:ssambership_app/design/theme.dart';
import 'package:ssambership_app/design/tokens/color_tokens.dart';
import 'package:ssambership_app/design/widgets/primary_button.dart';
import 'package:ssambership_app/design/widgets/secondary_button.dart';

/// 버튼 색 위계(QA4 §8): 액션 CTA = 고정 파랑 #2563EB(역할 무관),
/// 멘토 정체성(배지·탭·장식용 AppAccent)은 초록 유지. 위험/중립 계열 불변.

const Color kActionBlue = Color(0xFF2563EB);
const Color kMentorGreen = Color(0xFF059669);

Widget _themed(AppRole role, Widget child) => MaterialApp(
      theme: AppTheme.build(role),
      home: Scaffold(body: Center(child: child)),
    );

Color _resolvedBg(WidgetTester tester) => tester
    .widget<FilledButton>(find.byType(FilledButton))
    .style!
    .backgroundColor!
    .resolve(<WidgetState>{})!;

Color _resolvedFg(WidgetTester tester) => tester
    .widget<FilledButton>(find.byType(FilledButton))
    .style!
    .foregroundColor!
    .resolve(<WidgetState>{})!;

void main() {
  for (final AppRole role in <AppRole>[AppRole.student, AppRole.mentor]) {
    testWidgets('PrimaryButton — $role 테마에서도 액션 파랑 + 흰 글자(대비 확보)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _themed(role, PrimaryButton(label: '저장', onPressed: () {})));
      expect(_resolvedBg(tester), kActionBlue);
      expect(_resolvedFg(tester), Colors.white);
    });

    testWidgets('SecondaryButton(액션) — $role 테마에서도 파랑 외곽선/글자',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _themed(role, SecondaryButton(label: '받은 질문 보기', onPressed: () {})));
      final OutlinedButton b =
          tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(b.style!.foregroundColor!.resolve(<WidgetState>{}), kActionBlue);
      expect(b.style!.side!.resolve(<WidgetState>{})!.color, kActionBlue);
    });
  }

  testWidgets('SecondaryButton(neutral) — 중립 회색 계열 불변',
      (WidgetTester tester) async {
    await tester.pumpWidget(_themed(AppRole.mentor,
        SecondaryButton(label: '웹에서 진행', neutral: true, onPressed: () {})));
    final OutlinedButton b =
        tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(b.style!.foregroundColor!.resolve(<WidgetState>{}),
        ColorTokens.secondary);
    expect(b.style!.side!.resolve(<WidgetState>{})!.color, ColorTokens.border);
  });

  testWidgets('멘토 정체성 색은 유지 — 액션 파랑 수렴이 AppAccent(장식·배지)를 바꾸지 않는다',
      (WidgetTester tester) async {
    late RoleAccent ra;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(AppRole.mentor),
      home: Builder(builder: (BuildContext context) {
        ra = AppAccent.of(context);
        return const SizedBox.shrink();
      }),
    ));
    expect(ra.accent, kMentorGreen);
  });

  testWidgets('비활성(Primary) — 기존 muted 계열 유지', (WidgetTester tester) async {
    await tester.pumpWidget(_themed(
        AppRole.student, const PrimaryButton(label: '저장', onPressed: null)));
    final FilledButton b =
        tester.widget<FilledButton>(find.byType(FilledButton));
    expect(
        b.style!.backgroundColor!.resolve(<WidgetState>{WidgetState.disabled}),
        ColorTokens.muted);
  });
}
