import 'package:flutter/material.dart';

import '../../../../app/app_navigation.dart';
import '../../../../app/app_route_paths.dart';
import '../../../../app/app_scope.dart';
import '../../../../app/app_tabs.dart';
import '../../../../core/refresh/data_refresh_bus.dart';
import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/app_badge.dart';
import '../../../../design/widgets/app_empty_state.dart';
import '../../../../design/widgets/app_primary_button.dart';
import '../../../../design/widgets/app_secondary_button.dart';
import '../../../../design/widgets/count_badge.dart';
import '../../../../design/widgets/quota_bar.dart';
import '../../../../design/widgets/status_pill.dart';
import '../../../../shared/errors/friendly_error.dart';
import '../../../../shared/format/formatters.dart';
import '../../../subscription/data/subscription_commerce_models.dart';
import '../../../subscription/data/subscription_commerce_repository.dart';
import '../../../subscription/ui/refund_request_screen.dart';
import '../../../subscription/ui/subscription_cancel_sheet.dart';
import '../../data/mypage_models.dart';
import '../widgets/mypage_section.dart';

/// 학생 구독 현황 섹션 — 멘토별 카드(요금제·갱신일·상태) + 해지 예약·취소·환불 신청
/// (A-4b ②③ — `api_app_v1` 래퍼). "질문하러 가기".
/// ★ 잔여 질문수 미확정이면 숫자 대신 구독 상태로만 표기(S4와 동일, 날조 금지).
class StudentSubscriptionSection extends StatelessWidget {
  const StudentSubscriptionSection({
    super.key,
    required this.subscriptions,
    required this.onGoToQuestions,
    this.port,
    this.onChanged,
  });

  final List<SubscriptionCardInfo> subscriptions;

  /// 질문방 탭으로 이동(질문하러 가기).
  final VoidCallback onGoToQuestions;

  /// 테스트 주입(기본: [AppScope] 의 subscriptionCommerce).
  final SubscriptionCommercePort? port;

  /// 해지 예약·취소·환불 신청이 서버에 반영된 뒤 — 호출부가 마이페이지를 재조회.
  final VoidCallback? onChanged;

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
              _SubCard(
                info: subscriptions[i],
                port: port,
                onChanged: onChanged,
              ),
            ],
          const SizedBox(height: 12),
          AppPrimaryButton(
            label: '질문하러 가기',
            icon: Icons.forum_rounded,
            onPressed: onGoToQuestions,
          ),
        ],
      ),
    );
  }
}

class _SubCard extends StatefulWidget {
  const _SubCard({required this.info, this.port, this.onChanged});

  final SubscriptionCardInfo info;
  final SubscriptionCommercePort? port;
  final VoidCallback? onChanged;

  @override
  State<_SubCard> createState() => _SubCardState();
}

class _SubCardState extends State<_SubCard> {
  bool _busy = false;

  SubscriptionCardInfo get info => widget.info;

  SubscriptionCommercePort get _port =>
      widget.port ?? AppScope.of(context).subscriptionCommerce;

  /// 해지·환불 동작이 가능한 카드 — 구독 id 를 알고 자격이 살아 있을 때만.
  bool get _actionable => info.subscriptionId != null && info.isActive;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _scheduleCancel() async {
    if (_busy) return;
    final bool? ok = await SubscriptionCancelSheet.confirmSchedule(
      context,
      mentorName: info.mentorName,
      planLabel: info.planLabel,
      periodEnd: info.nextRenewal,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final CancelScheduleResult r =
          await _port.cancelAtPeriodEnd(info.subscriptionId!);
      if (!mounted) return;
      DataRefreshBus.bumpSubscription();
      final DateTime? end = r.currentPeriodEnd ?? info.nextRenewal;
      _snack(end == null
          ? '해지를 예약했어요. 남은 기간은 계속 쓸 수 있어요.'
          : '${Formatters.monthDay(end)}에 해지돼요. 그때까지는 계속 쓸 수 있어요.');
      widget.onChanged?.call();
    } catch (e) {
      _snack('해지 예약에 실패했어요. ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undoCancel() async {
    if (_busy) return;
    final bool? ok = await SubscriptionCancelSheet.confirmUndo(
      context,
      mentorName: info.mentorName,
      planLabel: info.planLabel,
      periodEnd: info.nextRenewal,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _port.cancelUndo(info.subscriptionId!);
      if (!mounted) return;
      DataRefreshBus.bumpSubscription();
      _snack('해지 예약을 취소했어요. 구독이 그대로 이어져요.');
      widget.onChanged?.call();
    } catch (e) {
      _snack('해지 취소에 실패했어요. ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRefund() async {
    if (_busy) return;
    final String id = info.subscriptionId!;
    final bool? requested = await AppNavigation.push<bool>(
      context,
      AppRoutePaths.subscriptionRefund(
        id,
        mentorName: info.mentorName,
        planLabel: info.planLabel,
      ),
      fallbackBuilder: (_) => RefundRequestScreen(
        subscriptionId: id,
        mentorName: info.mentorName,
        planLabel: info.planLabel,
        port: widget.port,
      ),
    );
    if (requested == true && mounted) widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bool scheduled = info.isCancelScheduled;
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
              label: scheduled && info.status?.trim() == 'active'
                  ? '해지 예정'
                  : info.statusLabel,
              tone: scheduled ? StatusTone.warning : info.statusTone,
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
                scheduled
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
        // A-4b ②③: 해지 예약 / 해지 취소 · 환불 신청 — 자격이 살아 있는 카드만.
        if (_actionable) ...<Widget>[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              if (scheduled)
                AppSecondaryButton(
                  label: '해지 취소',
                  expand: false,
                  onPressed: _busy ? null : _undoCancel,
                )
              else
                AppSecondaryButton(
                  label: '해지 예약',
                  filled: false,
                  expand: false,
                  onPressed: _busy ? null : _scheduleCancel,
                ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _busy ? null : _openRefund,
                child: const Text('환불 신청'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
