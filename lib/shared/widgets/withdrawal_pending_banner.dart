import 'package:flutter/material.dart';

import '../../core/auth/deletion_notice_controller.dart';
import '../../design/shape_tokens.dart';
import '../../design/spacing_tokens.dart';
import '../../design/tokens/color_tokens.dart';
import '../../design/typography_tokens.dart';
import '../../features/mypage/ui/account_delete_screen.dart';
import '../format/formatters.dart';

/// 탈퇴 예약 상시 배너(§5) — 홈 셸·마이페이지가 함께 쓰는 **공통 위젯 1개**.
///
/// - 노출 판정·취소 가능 판정은 전부 [DeletionNoticeController](서버 self RPC 정본).
///   이 위젯은 서버가 준 값을 그리기만 한다.
/// - 취소 버튼은 서버 `can_cancel` 이 참일 때만 만든다. locked/purging 이거나
///   판정 불가면 버튼 자체를 만들지 않는다(fail-closed §5-3·§5-4).
/// - 취소 '실행'은 이 배너가 직접 RPC 를 부르지 않고 기존 탈퇴 화면
///   ([AccountDeleteScreen])으로 넘긴다 — 서버 재판정·재로그인 계약이 그쪽에
///   이미 구현돼 있어 취소 경로를 두 벌로 만들지 않는다.
class WithdrawalPendingBanner extends StatefulWidget {
  const WithdrawalPendingBanner({
    super.key,
    this.controllerOverride,
    this.onOpenCancel,
  });

  /// 테스트 주입. 기본은 앱 공통 인스턴스(홈·마이페이지가 같은 상태를 본다).
  final DeletionNoticeController? controllerOverride;

  /// 테스트 주입. 기본은 [AccountDeleteScreen] push.
  final Future<void> Function(BuildContext context)? onOpenCancel;

  @override
  State<WithdrawalPendingBanner> createState() =>
      _WithdrawalPendingBannerState();
}

class _WithdrawalPendingBannerState extends State<WithdrawalPendingBanner>
    with WidgetsBindingObserver {
  DeletionNoticeController get _c =>
      widget.controllerOverride ?? DeletionNoticeController.instance;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChanged);
    // 앱 재시작·재로그인 후에도 서버 상태로만 복원한다(로컬 캐시 의존 0).
    _c.ensureLoaded();
    // 웹에서 탈퇴를 취소하고 돌아온 경우 등 앱 밖 변경 반영.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // single-flight 라 홈·마이페이지 배너가 동시에 깨어나도 RPC 는 1회.
    if (state == AppLifecycleState.resumed) _c.refresh();
  }

  /// 컨트롤러가 바뀌면 구독을 옮긴다 — 이전 컨트롤러 상태를 계속 그리지 않는다.
  @override
  void didUpdateWidget(covariant WithdrawalPendingBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final DeletionNoticeController previous =
        oldWidget.controllerOverride ?? DeletionNoticeController.instance;
    final DeletionNoticeController current = _c;
    if (identical(previous, current)) return;
    previous.removeListener(_onChanged);
    current.addListener(_onChanged);
    current.ensureLoaded();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openCancel() async {
    final Future<void> Function(BuildContext)? override = widget.onOpenCancel;
    if (override != null) {
      await override(context);
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const AccountDeleteScreen()),
      );
    }
    // 탈퇴 화면에서 취소했다면 서버 상태가 바뀌었다 — 배너를 서버 기준으로 재판정.
    if (mounted) await _c.refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_c.showsNotice) return const SizedBox.shrink();
    final DateTime? until = _c.cancelableUntil;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.screenH, AppSpacing.s8, AppSpacing.screenH, 0),
      padding: const EdgeInsets.all(AppSpacing.cardPad),
      decoration: BoxDecoration(
        color: ColorTokens.elevated,
        borderRadius: AppShape.cardRadius,
        border: Border.all(color: ColorTokens.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.info_rounded,
                  size: 20, color: ColorTokens.warning),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('탈퇴 요청이 접수된 계정이에요', style: AppType.body),
                    if (until != null) ...<Widget>[
                      const SizedBox(height: 2),
                      // 서버 cancelable_until 만 표시 — 로컬 추정 문구 금지.
                      Text(
                        '${_formatUntil(until)}까지 취소할 수 있어요',
                        style: AppType.caption,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // 서버 can_cancel 이 참일 때만 버튼을 만든다(값 부재·locked/purging → 비노출).
          if (_c.canCancel) ...<Widget>[
            const SizedBox(height: AppSpacing.s8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey<String>('withdrawal-banner-cancel'),
                onPressed: _openCancel,
                child: const Text('탈퇴 취소'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// '2026년 7월 25일 15:30' — 기기 로컬 시각으로 표시(서버 값은 UTC).
  /// 탈퇴 화면과 같은 포맷터를 쓴다(표시가 두 벌로 갈리지 않도록).
  static String _formatUntil(DateTime until) =>
      Formatters.dateTimeMinute(until);
}
