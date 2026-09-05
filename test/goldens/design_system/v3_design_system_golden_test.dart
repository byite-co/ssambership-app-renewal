import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/design/role_theme.dart';
import 'package:ssambership_app/design/tokens/app_colors.dart';
import 'package:ssambership_app/design/tokens/app_spacing.dart';
import 'package:ssambership_app/design/tokens/app_typography.dart';
import 'package:ssambership_app/design/widgets/app_empty_state.dart';
import 'package:ssambership_app/design/widgets/app_input_field.dart';
import 'package:ssambership_app/design/widgets/app_primary_button.dart';
import 'package:ssambership_app/design/widgets/app_secondary_button.dart';
import 'package:ssambership_app/design/widgets/app_skeleton.dart';
import 'package:ssambership_app/design/widgets/glass_badge.dart';
import 'package:ssambership_app/design/widgets/glass_bars.dart';
import 'package:ssambership_app/design/widgets/glass_card.dart';
import 'package:ssambership_app/design/widgets/glass_surface.dart';

import 'v3_golden_harness.dart';

void main() {
  testWidgets('background and typography specimen',
      (WidgetTester tester) async {
    await pumpV3Golden(
      tester,
      _page(
        title: '타이포그래피',
        child: const GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('연결되는 배움', style: AppTypography.title),
              SizedBox(height: 24),
              Text('12,345', style: AppTypography.bigNumber),
              SizedBox(height: 24),
              Text('오늘의 질문', style: AppTypography.section),
              SizedBox(height: 12),
              Text(
                '어려운 문제를 멘토와 함께 차근차근 풀어보세요.',
                style: AppTypography.body,
              ),
              SizedBox(height: 12),
              Text(
                '답변은 평균 10분 안에 시작돼요',
                style: AppTypography.caption,
              ),
              SizedBox(height: 20),
              Text('질문 시작하기', style: AppTypography.button),
            ],
          ),
        ),
      ),
    );

    await expectV3Golden(tester, 'background_typography');
  });

  testWidgets('glass app bar keeps content visible behind it', (
    WidgetTester tester,
  ) async {
    await pumpV3Golden(
      tester,
      Scaffold(
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(
          title: const Text('질문방'),
          actions: <Widget>[
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.search, color: AppColors.textPrimary),
            ),
          ],
        ),
        body: const _BackdropContent(topInset: 8),
      ),
    );

    await expectV3Golden(tester, 'glass_app_bar');
  });

  testWidgets('student glass tab bar', (WidgetTester tester) async {
    await pumpV3Golden(
      tester,
      Scaffold(
        extendBody: true,
        body: const _BackdropContent(),
        bottomNavigationBar: GlassTabBar(
          selectedIndex: 2,
          onSelected: (_) {},
        ),
      ),
    );

    await expectV3Golden(tester, 'glass_tab_bar_student');
  });

  testWidgets('mentor glass tab bar', (WidgetTester tester) async {
    await pumpV3Golden(
      tester,
      Scaffold(
        extendBody: true,
        body: const _BackdropContent(),
        bottomNavigationBar: GlassTabBar(
          selectedIndex: 2,
          onSelected: (_) {},
        ),
      ),
      role: AppRole.mentor,
    );

    await expectV3Golden(tester, 'glass_tab_bar_mentor');
  });

  testWidgets('bottom sheet over app bar and tab bar', (
    WidgetTester tester,
  ) async {
    await pumpV3Golden(tester, const _SheetShowcase());

    await tester.tap(find.text('시트 열기'));
    await tester.pumpAndSettle();

    await expectV3Golden(tester, 'glass_bottom_sheet');
  });

  testWidgets('three cards stay separated without per-card blur', (
    WidgetTester tester,
  ) async {
    await pumpV3Golden(
      tester,
      _page(
        title: '진행 중인 질문',
        child: Column(
          children: <Widget>[
            for (final (String subject, String question, String state)
                in <(String, String, String)>[
              ('수학', '이차함수의 최댓값을 모르겠어요', '답변 대기'),
              ('영어', '관계대명사 문장을 확인해주세요', '진행 중'),
              ('과학', '가속도 그래프 해석이 궁금해요', '답변 완료'),
            ]) ...<Widget>[
              GlassCard(
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.chat_bubble_outline),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(subject, style: AppTypography.caption),
                          const SizedBox(height: 4),
                          Text(question, style: AppTypography.body),
                        ],
                      ),
                    ),
                    AppBadge(label: state),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );

    await expectV3Golden(tester, 'glass_card_list');
  });

  testWidgets('card blur comparison', (WidgetTester tester) async {
    await pumpV3Golden(
      tester,
      _page(
        title: '카드 블러 비교',
        child: SizedBox(
          height: 420,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const _ComparisonPattern(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: GlassCard(
                        child: _comparisonCopy('블러 없음', '표준 카드'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassSurface.panel(
                        padding: const EdgeInsets.all(AppSpacing.base),
                        child: _comparisonCopy('블러 있음', '비교 전용'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await expectV3Golden(tester, 'glass_card_blur_comparison');
  });

  testWidgets('role buttons and disabled state', (WidgetTester tester) async {
    await pumpV3Golden(
      tester,
      _page(
        title: '버튼',
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _RoleButtonGroup(role: AppRole.student, label: '학생'),
            SizedBox(height: 24),
            _RoleButtonGroup(role: AppRole.mentor, label: '멘토'),
            SizedBox(height: 24),
            Text('비활성', style: AppTypography.caption),
            SizedBox(height: 8),
            AppPrimaryButton(label: '질문 전송'),
          ],
        ),
      ),
    );

    await expectV3Golden(tester, 'buttons');
  });

  testWidgets('default and focused input with badge', (
    WidgetTester tester,
  ) async {
    final FocusNode focusNode = FocusNode();
    final TextEditingController controller = TextEditingController(
      text: '함수 질문',
    );
    addTearDown(focusNode.dispose);
    addTearDown(controller.dispose);

    await pumpV3Golden(
      tester,
      _page(
        title: '입력과 배지',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('기본', style: AppTypography.caption),
            const SizedBox(height: 8),
            const AppInputField(
              hintText: '질문 제목을 입력해주세요',
              showCursor: false,
            ),
            const SizedBox(height: 24),
            const Text('포커스', style: AppTypography.caption),
            const SizedBox(height: 8),
            AppInputField(
              focusNode: focusNode,
              controller: controller,
              showCursor: false,
            ),
            const SizedBox(height: 24),
            const Wrap(
              spacing: 8,
              children: <Widget>[
                AppBadge(label: '답변 대기'),
                AppBadge(label: '수학'),
              ],
            ),
          ],
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    await expectV3Golden(tester, 'input_badge');
  });

  testWidgets('empty state and skeleton specimen', (
    WidgetTester tester,
  ) async {
    await pumpV3Golden(
      tester,
      _page(
        title: '상태',
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 320,
              child: AppEmptyState(
                icon: Icons.question_answer_outlined,
                title: '아직 질문이 없어요',
                description: '궁금한 내용을 남기면 멘토가 함께 풀어드려요.',
                actionLabel: '첫 질문 남기기',
                onAction: () {},
              ),
            ),
            const AppSkeleton(height: 72),
            const SizedBox(height: 12),
            const AppSkeleton(height: 92),
            const SizedBox(height: 12),
            const AppSkeleton(height: 56),
          ],
        ),
      ),
    );

    await expectV3Golden(tester, 'empty_state_skeleton');
  });
}

Widget _page({required String title, required Widget child}) {
  return Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
        children: <Widget>[
          Text(title, style: AppTypography.title),
          const SizedBox(height: 24),
          child,
        ],
      ),
    ),
  );
}

Widget _comparisonCopy(String title, String caption) {
  return Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[
      Text(title, textAlign: TextAlign.center, style: AppTypography.section),
      const SizedBox(height: 8),
      Text(
        caption,
        textAlign: TextAlign.center,
        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      ),
    ],
  );
}

class _RoleButtonGroup extends StatelessWidget {
  const _RoleButtonGroup({required this.role, required this.label});

  final AppRole role;
  final String label;

  @override
  Widget build(BuildContext context) {
    return RoleTheme(
      role: role,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: AppTypography.caption),
          const SizedBox(height: 8),
          const Row(
            children: <Widget>[
              Expanded(
                child: AppPrimaryButton(label: '계속하기', onPressed: _noop),
              ),
              SizedBox(width: 12),
              Expanded(
                child: AppSecondaryButton(label: '나중에', onPressed: _noop),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SheetShowcase extends StatelessWidget {
  const _SheetShowcase();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: const GlassAppBar(title: Text('질문방')),
      bottomNavigationBar: GlassTabBar(
        selectedIndex: 0,
        onSelected: (_) {},
      ),
      body: _BackdropContent(
        topInset: 8,
        action: (BuildContext actionContext) {
          unawaited(
            GlassBottomSheet.show<void>(
              actionContext,
              builder: (_) => const SizedBox(
                height: 240,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: SizedBox(
                        width: 44,
                        child: Divider(thickness: 4),
                      ),
                    ),
                    SizedBox(height: 20),
                    Text('질문 옵션', style: AppTypography.section),
                    SizedBox(height: 12),
                    Text(
                      '알림과 공개 범위를 선택할 수 있어요.',
                      style: AppTypography.body,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BackdropContent extends StatelessWidget {
  const _BackdropContent({this.topInset = 72, this.action});

  final double topInset;
  final void Function(BuildContext context)? action;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (BuildContext actionContext) => ListView(
        padding: EdgeInsets.fromLTRB(20, topInset, 20, 108),
        children: <Widget>[
          Container(
            height: 180,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[RoleColors.student, Color(0xFF8BB7FF)],
              ),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            padding: const EdgeInsets.all(20),
            alignment: Alignment.bottomLeft,
            child: Text(
              '오늘도 한 문제씩',
              style: AppTypography.section.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          for (int index = 1; index <= 5; index++) ...<Widget>[
            GlassCard(
              child: Text('학습 기록 $index', style: AppTypography.body),
            ),
            const SizedBox(height: 12),
          ],
          if (action != null)
            AppPrimaryButton(
              label: '시트 열기',
              onPressed: () => action!(actionContext),
            ),
        ],
      ),
    );
  }
}

class _ComparisonPattern extends StatelessWidget {
  const _ComparisonPattern();

  @override
  Widget build(BuildContext context) {
    const List<Color> colors = <Color>[
      Color(0xFF2563EB),
      Color(0xFFF7B84B),
      Color(0xFF0B6B4E),
      Color(0xFFC2334D),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Opacity(
        opacity: 0.7,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const ColoredBox(color: RoleColors.student),
            for (int index = 0; index < 28; index++)
              Positioned(
                top: index * 15,
                left: 0,
                right: 0,
                height: 15,
                child: ColoredBox(color: colors[index % colors.length]),
              ),
          ],
        ),
      ),
    );
  }
}

void _noop() {}
