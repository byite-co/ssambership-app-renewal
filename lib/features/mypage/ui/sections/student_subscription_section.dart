import 'package:flutter/material.dart';

import '../../../../app/app_tabs.dart';
import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/app_badge.dart';
import '../../../../design/widgets/app_empty_state.dart';
import '../../../../design/widgets/app_primary_button.dart';
import '../../../../design/widgets/app_secondary_button.dart';
import '../../../../design/widgets/count_badge.dart';
import '../../../../design/widgets/quota_bar.dart';
import '../../../../design/widgets/status_pill.dart';
import '../../../../shared/format/formatters.dart';
import '../../data/mypage_models.dart';
import '../widgets/mypage_section.dart';
import '../../../../core/web_bridge/web_bridge_actions.dart';
import '../../../../core/commerce/commerce_policy.dart';
import '../../../../shared/widgets/commerce_notice_card.dart';

/// 학생 구독 현황 섹션 — 멘토별 카드(요금제·갱신일·상태). "질문하러 가기"·"결제 관리(웹)".
/// ★ 잔여 질문수 미확정이면 숫자 대신 구독 상태로만 표기(S4와 동일, 날조 금지).
class StudentSubscriptionSection extends StatelessWidget {
  const StudentSubscriptionSection({
    super.key,
    required this.subscriptions,
    required this.onGoToQuestions,
  });

  final List<SubscriptionCardInfo> subscriptions;

  /// 질문방 탭으로 이동(질문하러 가기).
  final VoidCallback onGoToQuestions;

  @override
  Widget build(BuildContext context) {
    // 이미 조회된 구독 리스트에서 파생(새 fetch 없음). 0이면 배지 생략.
    final int activeCount =
        subscriptions.where((SubscriptionCardInfo s) => s.isActive).length;
    return MyPageSection(
      icon: Icons.bookmark_rounded,
      title: '구독 현황',
      trailing: activeCount > 0
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('이용중', style: AppTypography.captionSecondary),
                const SizedBox(width: 6),
                CountBadge(count: activeCount, tone: StatusTone.success),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (subscriptions.isEmpty)
            AppEmptyState(
              icon: Icons.bookmark_rounded,
              title: '구독 중인 멘토가 없어요',
              description: '관심 있는 멘토를 구독해 보세요',
              // 기존 탭 전환 경로만 재사용(멘토 찾기 탭). 결제 유도 아님.
              actionLabel: '멘토 찾기',
              onAction: () => TabNavigator.go(AppTab.mentors),
            )
          else
            for (int i = 0; i < subscriptions.length; i++) ...<Widget>[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: SizedBox(
                      height: 1, child: ColoredBox(color: AppColors.ring)),
                ),
              _SubCard(info: subscriptions[i]),
            ],
          const SizedBox(height: 12),
          AppPrimaryButton(
            label: '질문하러 가기',
            icon: Icons.forum_rounded,
            onPressed: onGoToQuestions,
          ),
          const SizedBox(height: 8),
          // P0-3 옵션1: 구독 관리 링크는 스토어 빌드에서 숨기고 안내로 대체
          // (kSubscriptionManageLinkEnabled — dev 는 dart-define 주입으로 on).
          if (kSubscriptionManageLinkEnabled)
            AppSecondaryButton(
              label: '구독 관리 (웹)',
              icon: Icons.open_in_new_rounded,
              onPressed: () => openBillingManageWeb(context),
            )
          else
            const CommerceNoticeCard(text: kSubscriptionManageNoticeText),
        ],
      ),
    );
  }
}

class _SubCard extends StatelessWidget {
  const _SubCard({required this.info});
  final SubscriptionCardInfo info;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                info.mentorName,
                style: AppTypography.bodyStrong.copyWith(fontSize: 16),
              ),
            ),
            const SizedBox(width: 8),
            // D1-B: 상태 도트 + 기존 상태칩(스캔성↑).
            StatusPill(
              label: info.statusLabel,
              tone: info.statusTone,
              showDot: true,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            if (info.planLabel != null)
              AppBadge(label: info.planLabel!, tinted: true),
            // design-tokens §6: '다음 갱신 7/27' → '7월 27일에 갱신돼요'(해지 예정이면 해지돼요).
            if (info.nextRenewal != null)
              Text(
                info.status?.trim() == 'cancel_scheduled'
                    ? '${Formatters.monthDay(info.nextRenewal!)}에 해지돼요'
                    : '${Formatters.monthDay(info.nextRenewal!)}에 갱신돼요',
                style: AppTypography.captionSecondary,
              ),
            // 잔여 바(D1-A)로 못 보여주는 폴백 문구만 텍스트로 유지(한도 정보 없을 때).
            if (info.usage == null || !info.usage!.hasQuota)
              Text(
                info.remaining != null
                    ? '남은 질문 ${info.remaining}개'
                    : (info.isActive ? '구독 상태로 질문 가능' : '구독이 필요해요'),
                style: AppTypography.captionSecondary,
              ),
          ],
        ),
        // D1-A: 주간 잔여 질문권 프로그레스 바(있는 값만 — RPC used/limit).
        if (info.usage != null && info.usage!.hasQuota) ...<Widget>[
          const SizedBox(height: 8),
          QuotaBar(used: info.usage!.used, limit: info.usage!.limit),
        ],
      ],
    );
  }
}
