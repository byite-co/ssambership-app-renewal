import 'package:flutter/material.dart';

import '../../design/tokens/app_colors.dart';
import '../../design/tokens/app_typography.dart';
import '../../design/widgets/app_badge.dart';
import '../../design/widgets/app_blocks.dart';
import '../../design/widgets/app_empty_state.dart';
import '../../design/widgets/app_input_field.dart';
import '../../design/widgets/app_page.dart';
import '../../design/widgets/app_primary_button.dart';
import '../../design/widgets/app_secondary_button.dart';
import '../../design/widgets/app_skeleton.dart';
import '../../design/widgets/chip_scroll.dart';
import '../../design/widgets/count_badge.dart';
import '../../design/widgets/glass_card.dart';
import '../../design/widgets/glass_inner.dart';
import '../../design/widgets/initial_avatar.dart';
import '../../design/widgets/quota_text.dart';
import '../../design/widgets/status_pill.dart';

/// 개발 전용 위젯 갤러리 — v3 글래스 컴포넌트를 상태별로 한눈에 본다.
/// ★ dev 전용 — 출시 빌드에서는 라우트가 등록되지 않는다(dev_flags / router 분기).
class WidgetGallery extends StatefulWidget {
  const WidgetGallery({super.key});

  @override
  State<WidgetGallery> createState() => _WidgetGalleryState();
}

class _WidgetGalleryState extends State<WidgetGallery> {
  int _chipIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: '위젯 갤러리 (개발용)',
      body: ListView(
        padding: AppPage.contentPadding(context),
        clipBehavior: Clip.none,
        children: <Widget>[
          _section('버튼 — 역할색 채움(α0.92) · 보조 · 비활성 · 위험'),
          AppPrimaryButton(label: '질문 보내기', onPressed: () {}),
          const SizedBox(height: 10),
          const AppPrimaryButton(label: '비활성', onPressed: null),
          const SizedBox(height: 10),
          AppPrimaryButton(
            label: '아이콘',
            icon: Icons.send_rounded,
            onPressed: () {},
          ),
          const SizedBox(height: 10),
          AppSecondaryButton(label: '나중에', onPressed: () {}),
          const SizedBox(height: 10),
          AppSecondaryButton(
            label: '구독 해지하기',
            danger: true,
            onPressed: () {},
          ),
          _section('배지 — 톤별'),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              AppBadge(label: '미적분'),
              AppBadge(label: '확인함', tone: AppBadgeTone.neutral),
              AppBadge(label: '진행중', tone: AppBadgeTone.info),
              AppBadge(label: '답변 완료', tone: AppBadgeTone.success),
              AppBadge(label: '답변 대기', tone: AppBadgeTone.warning),
              AppBadge(label: '해지 예정', tone: AppBadgeTone.danger),
            ],
          ),
          _section('StatusPill · CountBadge'),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              StatusPill(label: '이용 중', tone: StatusTone.success, showDot: true),
              StatusPill(label: '만료됨'),
              CountBadge(count: 3),
              CountBadge(count: 150),
            ],
          ),
          _section('InitialAvatar — 사진 없음(이니셜)'),
          const Row(
            children: <Widget>[
              InitialAvatar(name: '김멘토'),
              SizedBox(width: 12),
              InitialAvatar(name: '이학생', tinted: false),
              SizedBox(width: 12),
              InitialAvatar(name: 'A', size: 56),
              SizedBox(width: 12),
              InitialAvatar(name: '', size: 56),
            ],
          ),
          _section('QuotaText — "잔여 N개"'),
          const Row(
            children: <Widget>[
              QuotaText(remaining: 3),
              SizedBox(width: 16),
              QuotaText(remaining: 0, emphasize: false),
            ],
          ),
          _section('ChipScroll'),
          ChipScroll(
            labels: const <String>['전체', '김멘토', '박멘토', '최멘토', '정멘토'],
            selectedIndex: _chipIndex,
            onSelected: (int i) => setState(() => _chipIndex = i),
          ),
          _section('GlassCard · GlassInner · 입력'),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('카드 제목', style: AppTypography.section),
                const SizedBox(height: 8),
                const GlassInner(child: Text('안쪽 블록', style: AppTypography.body)),
                const SizedBox(height: 8),
                const AppInputField(hintText: '무엇이 궁금한가요?'),
                const SizedBox(height: 8),
                AppEntryRow(
                  icon: Icons.receipt_long_rounded,
                  label: '건별 내역 보기',
                  onTap: () {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const AppCallout(
            tone: AppCalloutTone.warning,
            title: '정산 계좌를 등록해 주세요',
            text: '등록하지 않으면 지급이 다음 달로 미뤄져요.',
          ),
          _section('AppSkeleton'),
          const AppSkeleton(height: 60),
          _section('AppEmptyState'),
          AppEmptyState(
            icon: Icons.forum_rounded,
            title: '아직 주고받은 질문이 없어요',
            description: '사진만 찍어 올려도 괜찮아요',
            actionLabel: '첫 질문 하기',
            onAction: () {},
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        title,
        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}
