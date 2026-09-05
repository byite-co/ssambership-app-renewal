import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../design/tokens/app_colors.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_empty_state.dart';
import '../../../design/widgets/app_badge.dart';
import '../../../design/widgets/glass_card.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../design/widgets/app_page.dart';
import '../../../design/widgets/app_blocks.dart';
import '../data/mentor_console_models.dart';
import '../data/mentor_console_repository.dart';
import 'settlement_format.dart';

/// 정산 건별 내역(A-4a #7) — `/settlements/lines`. 월별로 묶어 최신순.
/// 금액·상태는 RPC 검증값 그대로(재계산 0). 5종 밖 상태는 '상태 확인 필요'로 드러낸다.
class SettlementLinesScreen extends StatefulWidget {
  const SettlementLinesScreen({super.key, this.portOverride});

  final MentorConsolePort? portOverride;

  @override
  State<SettlementLinesScreen> createState() => _SettlementLinesScreenState();
}

class _SettlementLinesScreenState extends State<SettlementLinesScreen> {
  late final MentorConsolePort _port;
  late Future<List<SettlementLine>> _future;

  @override
  void initState() {
    super.initState();
    _port = widget.portOverride ?? AppScope.of(context).mentorConsole;
    _future = _port.loadSettlementLines();
  }

  void _reload() {
    setState(() {
      _future = _port.loadSettlementLines();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: '건별 내역',
      body: FutureBuilder<List<SettlementLine>>(
        future: _future,
        builder:
            (BuildContext context, AsyncSnapshot<List<SettlementLine>> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const AppLoadingView(cards: 4);
          }
          if (snap.hasError || snap.data == null) {
            return AppErrorView(
              title: '정산 내역을 불러오지 못했어요',
              message: friendlyError(snap.error ?? ''),
              onRetry: _reload,
            );
          }
          final List<SettlementLine> lines = snap.data!;
          if (lines.isEmpty) {
            return const AppEmptyState(
              icon: Icons.receipt_long_rounded,
              title: '아직 정산 내역이 없어요',
              description: '구독·개별질문이 확정되면 여기에 쌓여요',
            );
          }
          return _list(context, lines);
        },
      ),
    );
  }

  Widget _list(BuildContext context, List<SettlementLine> lines) {
    final List<Widget> children = <Widget>[];
    String? month;
    for (final SettlementLine line in lines) {
      final DateTime? at = line.occurredAt;
      final String group = at == null ? '날짜 미상' : settlementMonthOf(at);
      if (group != month) {
        month = group;
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
            child: Text(group, style: AppTypography.section),
          ),
        );
      }
      children.add(_LineCard(line: line));
      children.add(const SizedBox(height: 10));
    }
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        padding: AppPage.contentPadding(context),
        children: children,
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.line});

  final SettlementLine line;

  String get _description {
    switch (line.sourceType) {
      case 'subscription':
        final DateTime? a = line.periodStart;
        final DateTime? b = line.periodEnd;
        if (a != null && b != null) {
          return '구독 정산 · ${settlementShortDate(a)}~${settlementShortDate(b)}';
        }
        return '구독 정산';
      case 'individual_question':
        return '개별질문 답변';
      case 'custom_request':
        return '맞춤의뢰 주문';
      default:
        return '정산 항목';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool negative = line.status == SettlementLineStatus.canceled;
    final String? payDate = line.payDate;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppBadge(label: settlementSourceLabel(line.sourceType)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  line.occurredAt == null
                      ? ''
                      : settlementShortDate(line.occurredAt!),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              _StatusChip(status: line.status),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(child: Text(_description, style: AppTypography.body)),
              Text(
                settlementWon(line.netCents),
                style: AppTypography.section.copyWith(
                  color: negative ? AppColors.textSecondary : AppColors.textPrimary,
                  decoration: negative ? TextDecoration.lineThrough : null,
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            <String>[
              '멘토 몫 ${settlementWon(line.mentorAmountCents)}',
              '원천징수 ${settlementWon(line.withholdingCents)}',
              if (payDate != null)
                (line.status == SettlementLineStatus.paid ? '지급 ' : '지급 예정 ') +
                    settlementRunDateLabel(payDate),
            ].join(' · '),
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
          if (line.holdReason != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              line.holdReason == 'active_dispute'
                  ? '분쟁 진행 중이라 보류됐어요'
                  : '보류 사유: ${line.holdReason}',
              style: AppTypography.caption.copyWith(color: AppColors.warning),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final SettlementLineStatus status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (status) {
      case SettlementLineStatus.paid:
        color = AppColors.textSecondary;
      case SettlementLineStatus.hold:
      case SettlementLineStatus.unknown:
        color = AppColors.warning;
      case SettlementLineStatus.canceled:
        color = AppColors.danger;
      case SettlementLineStatus.pending:
      case SettlementLineStatus.accruing:
        color = AppColors.textPrimary;
    }
    return Text(
      settlementLineStatusLabel(status),
      style: AppTypography.caption.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
