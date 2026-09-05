import 'package:flutter/material.dart';

import '../../../../core/commerce/commerce_policy.dart';
import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_spacing.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/app_secondary_button.dart';
import '../../../../shared/widgets/commerce_notice_card.dart';
import '../../data/mypage_models.dart';
import '../../format/cash_format.dart';
import '../widgets/mypage_section.dart';

/// 멘토 대시보드 — 답변·정산 요약(조회만). 정산 계좌·요금제·내역은 정산 탭.
/// design-v3 §4-2: 금액은 가장 크게, 대기 건수는 한 눈에.
/// ★ IQ(개별질문)·CR(의뢰결제)는 앱 범위 밖 → 표시하지 않는다. 구독·질문방 중심.
class MentorDashboardSection extends StatelessWidget {
  const MentorDashboardSection({
    super.key,
    required this.data,
    required this.onGoToQuestions,
    this.showPayoutNotice = true,
  });

  final MentorDashboard data;

  /// 정산 안내 카드 표시 여부. 정산 탭 본문(정산 화면)에서는 끈다 — 정산 계좌·
  /// 요금제·내역이 앱에 있어 안내가 불필요하다(A-4a 정리 ③).
  final bool showPayoutNotice;

  /// 질문방(받은 학생) 탭으로 이동.
  final VoidCallback onGoToQuestions;

  @override
  Widget build(BuildContext context) {
    final int? cents = data.latestSettlementCents;
    return MyPageSection(
      icon: Icons.insights_rounded,
      title: '답변 · 정산 요약',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 최근 정산 — 라벨 작게 위, 금액 크게(§4-2). 값은 그대로.
          const Text('최근 정산', style: AppTypography.captionSecondary),
          const SizedBox(height: 4),
          Text(
            cents != null ? CashFormat.won(cents) : '-',
            style: AppTypography.bigNumber,
          ),
          const SizedBox(height: AppSpacing.s16),
          Row(
            children: <Widget>[
              Expanded(
                child: _Stat(label: '구독 학생', count: data.studentCount),
              ),
              const SizedBox(
                width: 1,
                height: 36,
                child: ColoredBox(color: AppColors.ring),
              ),
              Expanded(
                child: _Stat(
                  label: '답변 대기',
                  count: data.pendingAnswers,
                  // 대기>0이면 '숫자만' warning 텍스트로 은은히 강조(꽉 찬 원 아님).
                  emphasizeWhenPositive: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          AppSecondaryButton(
            label: '받은 질문 보기',
            icon: Icons.forum_rounded,
            onPressed: onGoToQuestions,
          ),
          // A-4b ⑩: 정산 관리 웹 링크 제거 — 정산 계좌·요금제·내역은 앱 정산 탭(A-4a).
          if (showPayoutNotice) ...<Widget>[
            const SizedBox(height: 8),
            const CommerceNoticeCard(text: kPayoutManageNoticeText),
          ],
        ],
      ),
    );
  }
}

/// 요약 통계 한 칸 — 큰 숫자(tabular) + 작은 라벨. 색 원(배지) 대신 메트릭 표기.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.count,
    this.emphasizeWhenPositive = false,
  });
  final String label;
  final int count;

  /// 값>0일 때 '숫자만' warning(주황)으로 은은히 강조(꽉 찬 원 금지). 0이면 기본색.
  final bool emphasizeWhenPositive;

  @override
  Widget build(BuildContext context) {
    final bool warn = emphasizeWhenPositive && count > 0;
    return Column(
      children: <Widget>[
        Text(
          '$count',
          style: AppTypography.title.copyWith(
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            color: warn ? AppColors.warning : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: AppTypography.captionSecondary),
      ],
    );
  }
}
