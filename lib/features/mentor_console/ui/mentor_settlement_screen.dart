import 'package:flutter/material.dart';

import '../../../app/app_navigation.dart';
import '../../../app/app_route_paths.dart';
import '../../../app/app_scope.dart';
import '../../../design/role_theme.dart';
import '../../../design/tokens/app_colors.dart';
import '../../../design/tokens/app_spacing.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_primary_button.dart';
import '../../../design/widgets/glass_card.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/widgets/v3_page.dart';
import '../data/mentor_console_models.dart';
import '../data/mentor_console_repository.dart';
import 'mentor_plans_screen.dart';
import 'payout_account_screen.dart';
import 'settlement_format.dart';
import 'settlement_lines_screen.dart';

/// 정산 허브(A-4a #7) — `/settlements/history`. design-v3 §4-2.
///
/// 이번 달 금액을 가장 크게, 계좌 미등록 경고를 최상단에. "무엇으로 벌었나요"로
/// 구독·개별질문·맞춤의뢰를 한눈에. 아래에 멘토 자기 관리 진입(계좌·요금제…).
/// ★ 충전 유도 문구·링크 0. 계좌 미등록은 '이월된다'는 사실 안내까지만.
class MentorSettlementScreen extends StatefulWidget {
  const MentorSettlementScreen({super.key, this.portOverride});

  /// 진입 아이콘 툴팁(HomeShell 정산 탭·마이페이지 AppBar 공통).
  static const String entryTooltip = '정산 상세';

  final MentorConsolePort? portOverride;

  @override
  State<MentorSettlementScreen> createState() => _MentorSettlementScreenState();
}

class _MentorSettlementScreenState extends State<MentorSettlementScreen> {
  late final MentorConsolePort _port;
  late Future<SettlementSummary> _future;

  @override
  void initState() {
    super.initState();
    _port = widget.portOverride ?? AppScope.of(context).mentorConsole;
    _future = _port.loadSettlementSummary();
  }

  void _reload() {
    setState(() {
      _future = _port.loadSettlementSummary();
    });
  }

  Future<void> _openAccount() async {
    final bool? changed = await AppNavigation.push<bool>(
      context,
      AppRoutePaths.settlementAccount,
      fallbackBuilder: (_) => PayoutAccountScreen(portOverride: widget.portOverride),
    );
    if (changed == true && mounted) _reload();
  }

  Future<void> _openPlans() async {
    await AppNavigation.push<bool>(
      context,
      AppRoutePaths.mentorPlans,
      fallbackBuilder: (_) => MentorPlansScreen(portOverride: widget.portOverride),
    );
  }

  Future<void> _openLines() async {
    await AppNavigation.push<void>(
      context,
      AppRoutePaths.settlementLines,
      fallbackBuilder: (_) =>
          SettlementLinesScreen(portOverride: widget.portOverride),
    );
  }

  @override
  Widget build(BuildContext context) {
    return V3Page(
      title: '정산',
      body: FutureBuilder<SettlementSummary>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<SettlementSummary> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const V3LoadingView(cards: 3);
          }
          if (snap.hasError || snap.data == null) {
            return V3ErrorView(
              title: '정산 정보를 불러오지 못했어요',
              message: friendlyError(snap.error ?? ''),
              onRetry: _reload,
            );
          }
          return _body(context, snap.data!);
        },
      ),
    );
  }

  Widget _body(BuildContext context, SettlementSummary s) {
    final String runDate = settlementRunDateLabel(s.runDate);
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        padding: V3Page.contentPadding(context),
        children: <Widget>[
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${settlementMonthLabel(s.month)} 받을 금액',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  settlementWon(s.thisMonthNetCents),
                  style: AppTypography.bigNumber,
                ),
                const SizedBox(height: 4),
                Text(
                  s.confirmedCount == 0
                      ? '아직 확정된 정산이 없어요'
                      : '$runDate에 입금돼요',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!s.payoutAccountRegistered) ...<Widget>[
            V3Callout(
              tone: V3CalloutTone.warning,
              title: '정산 계좌를 등록해 주세요',
              text: '등록하지 않으면 $runDate 지급이 다음 달로 미뤄져요.',
            ),
            const SizedBox(height: 10),
            AppPrimaryButton(
              label: '계좌 등록하기',
              icon: Icons.account_balance_rounded,
              onPressed: _openAccount,
            ),
            const SizedBox(height: AppSpacing.section),
          ],
          const V3SectionTitle('무엇으로 벌었나요'),
          GlassCard(
            child: Column(
              children: <Widget>[
                _SourceRow(
                  label: '구독',
                  countLabel: '${s.source('subscription').count}명',
                  cents: s.source('subscription').mentorAmountCents,
                ),
                _SourceRow(
                  label: '개별질문',
                  countLabel: '${s.source('individual_question').count}건',
                  cents: s.source('individual_question').mentorAmountCents,
                ),
                _SourceRow(
                  label: '맞춤의뢰',
                  countLabel: '${s.source('custom_request').count}건',
                  cents: s.source('custom_request').mentorAmountCents,
                ),
                const SizedBox(height: 6),
                Text(
                  '플랫폼 수수료를 뺀 이번 달 발생 금액이에요. 원천징수는 지급 때 반영돼요.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: <Widget>[
                V3KeyValueRow(
                  label: '적립 중 · ${s.accruingCount}건',
                  value: settlementWon(s.accruingNetCents),
                ),
                V3KeyValueRow(
                  label: '보류 · ${s.heldCount}건',
                  value: settlementWon(s.heldMentorAmountCents),
                  valueColor: s.heldCount > 0 ? AppColors.warning : null,
                ),
                V3KeyValueRow(
                  label: '지금까지 지급 · ${s.paidTotalCount}건',
                  value: settlementWon(s.paidTotalNetCents),
                ),
                V3EntryRow(
                  icon: Icons.receipt_long_rounded,
                  label: '건별 내역 보기',
                  onTap: _openLines,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          const V3SectionTitle('멘토 관리'),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: <Widget>[
                V3EntryRow(
                  icon: Icons.account_balance_rounded,
                  label: '정산 계좌',
                  caption: s.payoutAccountRegistered ? '등록됨' : '미등록',
                  onTap: _openAccount,
                ),
                V3EntryRow(
                  icon: Icons.sell_outlined,
                  label: '요금제 · 개별질문 단가',
                  onTap: _openPlans,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.label,
    required this.countLabel,
    required this.cents,
  });

  final String label;
  final String countLabel;
  final int cents;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Text(label, style: AppTypography.body),
          const SizedBox(width: 8),
          Text(
            countLabel,
            style: AppTypography.caption.copyWith(color: roleTheme.color),
          ),
          const Spacer(),
          Text(
            settlementWon(cents),
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
