import 'package:flutter/material.dart';

import '../../../../core/commerce/commerce_policy.dart';
import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/app_badge.dart';
import '../../../../design/widgets/app_empty_state.dart';
import '../../../../design/widgets/money_display.dart';
import '../../../../shared/format/formatters.dart';
import '../../../../shared/widgets/commerce_notice_card.dart';
import '../../data/mypage_models.dart';
import '../../format/cash_format.dart';
import '../widgets/mypage_section.dart';

/// 캐시 섹션 — 잔액·최근 내역 '조회만' + "충전하기(웹)". ★ 앱에서 결제/충전 실행 없음.
///
/// [stale]=true(세션1.5 보정3): 지갑 변경(예: 환불) 후 최신 재조회에 실패해
/// **마지막 정상값을 보존 표시**하는 상태 — 금액을 최신 확정값처럼 보이지 않게
/// '최신 정보 아님' 을 명시하고 재시도를 제공한다(캐시 데이터 삭제 금지).
class CashSection extends StatelessWidget {
  const CashSection(
      {super.key, required this.cash, this.stale = false, this.onRetryStale});

  final CashSummary cash;
  final bool stale;
  final VoidCallback? onRetryStale;

  @override
  Widget build(BuildContext context) {
    return MyPageSection(
      icon: Icons.account_balance_wallet_rounded,
      title: '캐시',
      trailing: const AppBadge(label: '조회만', tone: AppBadgeTone.neutral),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (stale) ...<Widget>[
            // v19: walletGeneration 은 환불 전용 신호가 아니다(예치·정산도 bump)
            // — 원인을 단정하지 않는 공통 문구만 사용한다.
            Text('캐시 변경은 완료됐지만 최신 잔액을 불러오지 못했습니다.',
                style: AppTypography.caption.copyWith(color: AppColors.danger)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onRetryStale,
                child: const Text('다시 시도'),
              ),
            ),
          ],
          // D1-C: 금액 강조(토스식 Number Display) — 라벨 작게 위, 금액 크게.
          MoneyDisplay(
            label: stale ? '보유 캐시 (최신 정보 아님)' : '보유 캐시',
            // 잔액 미확인이면 숫자 날조 없이 '-' 표기.
            amount: cash.hasBalance ? CashFormat.won(cash.balanceCents!) : '-',
          ),
          const SizedBox(height: 12),
          if (cash.recent.isEmpty)
            // 커머스 제로: 충전 유도 CTA 없이 정보 문구만.
            const AppEmptyState(
              icon: Icons.receipt_long_rounded,
              title: '거래 내역이 없어요',
              description: '구독·충전 내역이 여기에 표시돼요',
            )
          else ...<Widget>[
            const Text('최근 내역', style: AppTypography.captionSecondary),
            const SizedBox(height: 6),
            for (final CashEntry e in cash.recent) _EntryRow(entry: e),
          ],
          const SizedBox(height: 12),
          // 커머스 제로: 구매 유도(충전하기) 제거 → 비상호작용 안내.
          const CommerceNoticeCard(text: kRechargeNoticeText),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});
  final CashEntry entry;

  @override
  Widget build(BuildContext context) {
    final Color amountColor =
        entry.isCredit ? AppColors.success : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Text(entry.kindLabel, style: AppTypography.body),
          const SizedBox(width: 8),
          Text(Formatters.monthDay(entry.createdAt), style: AppTypography.meta),
          const Spacer(),
          Text(
            CashFormat.signedWon(entry.deltaCents),
            style: AppTypography.bodyStrong.copyWith(color: amountColor),
          ),
        ],
      ),
    );
  }
}
