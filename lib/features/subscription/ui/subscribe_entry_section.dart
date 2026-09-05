import 'package:flutter/material.dart';

import '../../../app/app_navigation.dart';
import '../../../app/app_route_paths.dart';
import '../../../app/app_scope.dart';
import '../../../core/auth/auth_service.dart' show AppRole;
import '../../../core/identity/identity_gate.dart';
import '../../../core/refresh/data_refresh_bus.dart';
import '../../../core/web_bridge/web_bridge_actions.dart';
import '../../../design/tokens/app_spacing.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_primary_button.dart';
import '../../../design/widgets/glass_bars.dart';
import '../../mentors/data/mentor_models.dart';
import '../../mentors/format/mentor_price_format.dart';
import '../data/subscription_commerce_models.dart';
import '../data/subscription_commerce_repository.dart';
import 'subscribe_plan_sheet.dart';

/// 멘토 상세의 네이티브 '구독하기' 진입(A-4b ① · design-v3 §5-3).
///
/// - 학생만 결제할 수 있다. 게스트는 로그인 안내, 멘토·관리자에게는 그리지 않는다.
/// - 본인인증 게이트([IdentityGate]) ON 이고 미인증이면 시트 대신 안내 + 웹 본인인증.
///   판독 실패는 fail-closed(미인증 취급 — 웹 `requireVerifiedIdentity` 동일).
/// - 성공하면 구독·지갑·질문방 세대를 올리고 반환된 방으로 이동한다.
class SubscribeEntrySection extends StatefulWidget {
  const SubscribeEntrySection({
    super.key,
    required this.mentor,
    this.port,
    this.identityGateOverride,
    this.roleOverride,
    this.idempotencyKeyFactory,
    this.onSubscribed,
    this.onAlreadySubscribed,
  });

  final MentorListItem mentor;

  /// 테스트 주입(기본: [AppScope]).
  final SubscriptionCommercePort? port;

  /// 테스트 주입(null = [IdentityGate.isEnabled]).
  final bool? identityGateOverride;

  /// 테스트 주입(null = [AppScope] 인증의 currentRole).
  final AppRole? roleOverride;

  /// 테스트 주입(시트 멱등 키).
  final String Function()? idempotencyKeyFactory;

  /// 결제 성공 콜백(방 이동 전에 호출). null 이면 기본 이동만.
  final ValueChanged<SubscribeSuccess>? onSubscribed;

  /// 서버가 '이미 구독 중' 으로 거부했을 때 — 호출부가 구독 여부를 재조회한다.
  final VoidCallback? onAlreadySubscribed;

  @override
  State<SubscribeEntrySection> createState() => _SubscribeEntrySectionState();
}

class _SubscribeEntrySectionState extends State<SubscribeEntrySection> {
  bool _busy = false;

  AppRole get _role =>
      widget.roleOverride ?? AppScope.of(context).auth.currentRole;

  SubscriptionCommercePort get _port =>
      widget.port ?? AppScope.of(context).subscriptionCommerce;

  bool get _gateEnabled => widget.identityGateOverride ?? IdentityGate.isEnabled;

  int? get _minWon {
    int? min;
    for (final MentorPlan p in widget.mentor.plans) {
      if (!p.isActive) continue;
      if (min == null || p.won < min) min = p.won;
    }
    return min;
  }

  Future<void> _onTap() async {
    if (_busy) return;
    if (_role == AppRole.guest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인하면 구독할 수 있어요.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      if (_gateEnabled) {
        bool verified = false;
        try {
          verified = await _port.fetchIdentityVerified();
        } catch (_) {
          verified = false; // fail-closed
        }
        if (!mounted) return;
        if (!verified) {
          await _showIdentityRequired();
          return;
        }
      }
      if (!mounted) return;
      final SubscribeSheetOutcome? outcome = await SubscribePlanSheet.show(
        context,
        mentor: widget.mentor,
        port: widget.port,
        idempotencyKeyFactory: widget.idempotencyKeyFactory,
      );
      if (!mounted || outcome == null) return;
      switch (outcome) {
        case SubscribeSheetSuccess(:final SubscribeSuccess result):
          _afterSuccess(result);
        case SubscribeSheetAlreadySubscribed():
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이미 구독 중인 멘토예요. 질문방으로 갈 수 있어요.')),
          );
          widget.onAlreadySubscribed?.call();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _afterSuccess(SubscribeSuccess result) {
    // 구독·지갑·질문방 표면 무효화 — 각 화면이 서버 정본을 재조회한다.
    DataRefreshBus.bumpSubscription();
    DataRefreshBus.bumpWallet();
    DataRefreshBus.bumpQuestionRooms();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.idempotent
            ? '이미 완료된 결제예요. 질문방으로 이동할게요.'
            : '구독을 시작했어요. 질문방으로 이동할게요.'),
      ),
    );
    widget.onSubscribed?.call(result);
    if (result.roomId.isNotEmpty) {
      AppNavigation.finishAtLocation(context, AppRoutePaths.room(result.roomId));
    } else {
      AppNavigation.finishAtLocation(context, AppRoutePaths.rooms);
    }
  }

  Future<void> _showIdentityRequired() {
    return GlassBottomSheet.show<void>(
      context,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 6),
          const Text('본인인증 후 구독할 수 있어요', style: AppTypography.section),
          const SizedBox(height: 8),
          const Text(
            '결제가 있는 기능은 본인인증을 마친 계정만 쓸 수 있어요. 인증을 마치고 돌아오면 바로 구독할 수 있어요.',
            style: AppTypography.captionSecondary,
          ),
          const SizedBox(height: AppSpacing.s16),
          AppPrimaryButton(
            label: '본인인증 하러 가기',
            icon: Icons.verified_user_outlined,
            onPressed: () {
              Navigator.of(sheetContext).pop();
              openIdentityVerifyWeb(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppRole role = _role;
    if (role != AppRole.student && role != AppRole.guest) {
      return const SizedBox.shrink();
    }
    final int? minWon = _minWon;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppPrimaryButton(
          label: '구독하기',
          icon: Icons.bookmark_add_rounded,
          onPressed: _busy ? null : _onTap,
        ),
        if (minWon != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            '월 ${formatWon(minWon)}부터 · 요금제 ${widget.mentor.plans.where((MentorPlan p) => p.isActive).length}가지',
            textAlign: TextAlign.center,
            style: AppTypography.captionSecondary,
          ),
        ],
      ],
    );
  }
}
