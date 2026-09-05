import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/design/app_theme.dart';
import 'package:ssambership_app/design/role_theme.dart';
import 'package:ssambership_app/design/tokens/app_colors.dart';
import 'package:ssambership_app/design/tokens/app_glass.dart';
import 'package:ssambership_app/design/tokens/app_spacing.dart';
import 'package:ssambership_app/design/tokens/app_typography.dart';
import 'package:ssambership_app/design/widgets/app_background.dart';
import 'package:ssambership_app/design/widgets/app_empty_state.dart';
import 'package:ssambership_app/design/widgets/app_input_field.dart';
import 'package:ssambership_app/design/widgets/app_primary_button.dart';
import 'package:ssambership_app/design/widgets/app_secondary_button.dart';
import 'package:ssambership_app/design/widgets/app_skeleton.dart';
import 'package:ssambership_app/design/widgets/app_badge.dart';
import 'package:ssambership_app/design/widgets/glass_bars.dart';
import 'package:ssambership_app/design/widgets/glass_card.dart';
import 'package:ssambership_app/design/widgets/glass_inner.dart';

void main() {
  test('v3 canonical tokens stay exact', () {
    expect(AppColors.bgTop, const Color(0xFFF6F9FD));
    expect(AppColors.bgMid, const Color(0xFFEDF3FA));
    expect(AppColors.bgBot, const Color(0xFFF2F6FB));
    expect(AppColors.textPrimary, const Color(0xFF191F28));
    expect(AppColors.textSecondary, const Color(0xFF5F6B7A));
    expect(RoleColors.student, const Color(0xFF2563EB));
    expect(RoleColors.mentor, const Color(0xFF0B6B4E));
    expect(AppGlass.panelFill, 0.48);
    expect(AppGlass.panelBlur, 15);
    expect(AppGlass.innerFill, 0.58);
    expect(AppGlass.barFill, 0.85);
    expect(AppSpacing.screenH, 20);
    expect(AppRadius.card, 16);
  });

  test('every canonical text style names Pretendard', () {
    const List<TextStyle> styles = <TextStyle>[
      AppTypography.title,
      AppTypography.bigNumber,
      AppTypography.section,
      AppTypography.body,
      AppTypography.caption,
      AppTypography.button,
    ];
    expect(
      styles.every(
        (TextStyle style) => style.fontFamily == AppTypography.fontFamily,
      ),
      isTrue,
    );
  });

  test('glass source keeps the performance and clipping contracts', () {
    final String card =
        File('lib/design/widgets/glass_card.dart').readAsStringSync();
    final String surface =
        File('lib/design/widgets/glass_surface.dart').readAsStringSync();

    expect(card.contains('BackdropFilter'), isFalse);
    expect(card.contains('AppGlass.highlightAlpha'), isTrue);
    expect(surface.contains('ClipRect('), isTrue);
    expect(surface.contains('BackdropFilter('), isTrue);
  });

  testWidgets('RoleTheme exposes role colors and falls back to student',
      (WidgetTester tester) async {
    late RoleTheme studentTheme;
    await tester.pumpWidget(
      MaterialApp(
        home: RoleTheme(
          role: AppRole.student,
          child: Builder(
            builder: (BuildContext context) {
              studentTheme = RoleTheme.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(studentTheme.color, RoleColors.student);
    expect(
      studentTheme.button,
      RoleColors.student.withValues(alpha: AppGlass.buttonAlpha),
    );
    expect(
      studentTheme.tint,
      RoleColors.student.withValues(alpha: AppGlass.tintAlpha),
    );

    // 조상에 RoleTheme 이 없으면(화면을 단독 pump 하는 테스트) 학생 기본값.
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            expect(RoleTheme.maybeOf(context), isNull);
            expect(RoleTheme.of(context).role, AppRole.student);
            expect(RoleTheme.of(context).color, RoleColors.student);
            return const SizedBox();
          },
        ),
      ),
    );
  });

  testWidgets('v3 components render together without touching app screens',
      (WidgetTester tester) async {
    int primaryTaps = 0;
    int secondaryTaps = 0;
    int selectedTab = -1;
    await tester.pumpWidget(
      _wrap(
        Scaffold(
          appBar: const GlassAppBar(title: Text('디자인 시스템')),
          body: AppBackground(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                const GlassCard(child: Text('카드')),
                const SizedBox(height: 12),
                const GlassInner(child: Text('안쪽 블록')),
                const SizedBox(height: 12),
                AppPrimaryButton(
                  label: '계속하기',
                  onPressed: () => primaryTaps++,
                ),
                const SizedBox(height: 12),
                AppSecondaryButton(
                  label: '나중에',
                  onPressed: () => secondaryTaps++,
                ),
                const SizedBox(height: 12),
                const AppInputField(hintText: '답변을 입력하세요'),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: AppBadge(label: '진행중'),
                ),
                const AppEmptyState(
                  icon: Icons.inbox_outlined,
                  title: '아직 질문이 없어요',
                  description: '사진만 찍어 올려도 괜찮아요',
                ),
                const AppSkeleton(),
              ],
            ),
          ),
          bottomNavigationBar: GlassTabBar(
            selectedIndex: 0,
            onSelected: (int value) => selectedTab = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('계속하기'));
    await tester.tap(find.text('나중에'));
    await tester.tap(find.text('멘토찾기'));
    expect(primaryTaps, 1);
    expect(secondaryTaps, 1);
    expect(selectedTab, 2);
    expect(
      find.byType(AppSkeleton, skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('mentor tab labels replace mentor search with settlements',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        Scaffold(
          bottomNavigationBar: GlassTabBar(
            selectedIndex: 2,
            onSelected: (_) {},
          ),
        ),
        role: AppRole.mentor,
      ),
    );

    expect(find.text('정산'), findsOneWidget);
    expect(find.text('멘토찾기'), findsNothing);
    expect(find.text('질문방'), findsOneWidget);
    expect(find.text('개별질문'), findsOneWidget);
    expect(find.text('커뮤니티'), findsOneWidget);
    expect(find.text('알림'), findsOneWidget);
  });

  testWidgets('input decoration stays borderless and focus uses the role ring',
      (WidgetTester tester) async {
    final FocusNode focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      _wrap(
        Scaffold(
          body: AppBackground(
            child: Center(
              child: SizedBox(
                width: 300,
                child: AppInputField(
                  focusNode: focusNode,
                  hintText: '질문을 입력하세요',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.border, InputBorder.none);
    expect(field.decoration?.enabledBorder, InputBorder.none);
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('GlassBottomSheet applies a modal scrim and keeps content behind',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (BuildContext context) => Scaffold(
            body: AppBackground(
              child: Center(
                child: TextButton(
                  onPressed: () => GlassBottomSheet.show<void>(
                    context,
                    builder: (_) => const SizedBox(
                      height: 180,
                      child: Center(child: Text('시트 내용')),
                    ),
                  ),
                  child: const Text('시트 열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('시트 열기'));
    await tester.pumpAndSettle();
    expect(find.text('시트 내용'), findsOneWidget);
    expect(find.byType(ModalBarrier), findsWidgets);
    expect(find.byType(GlassBottomSheet), findsOneWidget);
  });

  test('v3 theme stays transparent until AppBackground paints the page', () {
    final ThemeData theme = AppTheme.build();
    expect(theme.scaffoldBackgroundColor, Colors.transparent);
    expect(theme.dividerColor, Colors.transparent);
    expect(theme.textTheme.headlineSmall?.fontFamily, 'Pretendard');
    expect(theme.inputDecorationTheme.border, InputBorder.none);
  });
}

Widget _wrap(Widget child, {AppRole role = AppRole.student}) {
  return RoleTheme(
    role: role,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: child,
    ),
  );
}
