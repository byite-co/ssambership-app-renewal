import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_navigation.dart';
import '../../app/app_route_paths.dart';
import '../../app/app_scope.dart';
import '../../app/app_tabs.dart';
import '../../app/entry_guard.dart';
import '../../core/auth/app_auth.dart';
import '../../core/refresh/data_refresh_bus.dart';
import '../../design/tokens/app_colors.dart';
import '../../design/tokens/app_spacing.dart';
import '../../design/tokens/app_typography.dart';
import '../../design/widgets/app_blocks.dart';
import '../../design/widgets/app_page.dart';
import '../dev/dev_flags.dart';
import 'data/mypage_models.dart';
import 'data/mypage_repository.dart';
import 'ui/profile_edit_screen.dart';
import 'ui/sections/cash_section.dart';
import 'ui/sections/mentor_dashboard_section.dart';
import 'ui/sections/profile_section.dart';
import 'ui/sections/settings_section.dart';
import 'ui/sections/student_subscription_section.dart';
import 'ui/sections/support_section.dart';
import '../../shared/errors/friendly_error.dart';
import '../../shared/widgets/withdrawal_pending_banner.dart';
import '../../shared/widgets/screen_visibility.dart';

/// 마이페이지(보강) — 조회 중심 대시보드. role(student/mentor)별로 내용이 다르다.
/// ★ Commerce-Zero: 결제·충전·정산 출금은 앱에서 실행하지 않고 '웹'으로만 연결한다.
///   기존 S2(이름·역할·로그아웃)를 설정 섹션으로 통합한다.
///
/// HomeShell 이 AppBar/하단탭을 제공하므로 본문만 구성(자체 Scaffold 없음).
class MyPageScreen extends StatefulWidget {
  const MyPageScreen({
    super.key,
    this.loaderOverride,
    this.onOpenQuestionsTab,
    this.onOpenNotifications,
  });

  /// 테스트용 데이터 주입(실제 DB·네트워크 대신 mock). null 이면 실제 레포 사용.
  final Future<MyPageData> Function()? loaderOverride;

  /// '질문하러 가기'·'받은 질문 보기'에서 질문방 탭으로 보내는 핸드오프.
  /// push 라우트(_MyPagePage)는 route 를 pop 하며 탭 index 를 반환하는 콜백을 주입한다
  /// (미주입 시 TabNavigator 폴백 — push 위에서는 무반응이므로 반드시 주입할 것).
  final VoidCallback? onOpenQuestionsTab;

  /// 마이페이지 '알림' 행 핸드오프 — SupportSection 의 기존 콜백을 그대로 재사용한다.
  final VoidCallback? onOpenNotifications;

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen>
    with WidgetsBindingObserver, ResumeVisibilityGate {
  // A-2: 레포지토리·인증 상태는 AppScope 에서 받는다(직접 생성·싱글턴 참조 0).
  late final AppDependencies _deps;
  MyPageRepository get _repo => _deps.myPage;
  AppAuth get _auth => _deps.auth;

  /// v19 보정1: 마지막 '정상 완료' MyPageData 스냅샷 — 이후 재조회가 어떤
  /// 원인(지갑 신호·resume·수동 재시도)으로 실패하든 이 화면을 지우지 않는다.
  MyPageData? _lastGoodData;

  /// 지갑 '확정값'(balanceCents != null)까지 확인된 마지막 캐시 스냅샷.
  CashSummary? _lastGoodCash;

  /// 지갑 변경 신호 후 아직 확정 재조회 성공을 확인하지 못한 상태(stale 표지).
  bool _walletSyncPending = false;

  bool _loading = true;

  /// 직전 재조회가 Future.error 로 실패했는가(마지막 정상 화면 위 배너 표지).
  bool _loadFailed = false;
  Object? _lastError;

  /// 늦게 도착한 이전 재조회 응답 폐기용 세대 토큰.
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _deps = AppScope.of(context);
    _reload();
    // §4: 지갑 변경 신호(IQ 예치·환불·정산 등) 수신 → 잔액·최근 내역 재조회.
    DataRefreshBus.walletGeneration.addListener(_onWalletChanged);
    // v19: 앱 복귀(resumed)도 일반 재조회 경로 — 실패해도 화면 보존 계약 동일.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) handleResumed();
  }

  // N12: 보일 때만 재조회(가려진 탭·덮인 라우트는 재노출 시 1회).
  @override
  void onResumeRefresh() {
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DataRefreshBus.walletGeneration.removeListener(_onWalletChanged);
    super.dispose();
  }

  void _onWalletChanged() {
    if (!mounted) return; // dispose 후 상태 변경 금지.
    _walletSyncPending = true; // 이 시점 이전 잔액은 stale generation.
    _reload();
  }

  /// v20 정정1: 수동 재시도(오류 배너·CashSection 두 버튼 공용) single-flight.
  /// 진행 중 요청이 있으면 새 loader 를 시작하지 않는다(연타 병렬 요청 0) —
  /// 버튼 비활성(onPressed=null)과 이중 방어. 진행 중 요청이 성공/실패로
  /// 끝나면 _loading 해제와 함께 재시도가 다시 가능해진다.
  ///
  /// 반면 최신성 신호(지갑 변경·resume·프로필 저장·initState)는 이 가드를
  /// 타지 않고 [_reload] 를 직접 호출한다 — 이미 시작된 요청보다 뒤에 생긴
  /// 변경을 반영해야 하므로 기존 요청을 supersede(새 세대 시작)하고, 이전
  /// 응답은 _loadGeneration 계약으로 폐기된다(최신 조회 유실 0).
  void _retryManual() {
    if (_loading) return;
    _reload();
  }

  /// v19 보정1: 상태 갱신은 전부 loader 완료 지점(then/catchError)에서만 —
  /// build/렌더링 경로는 주어진 상태를 그리기만 한다(숨은 상태 변경 0).
  /// v20 정정1: 직접 호출 = 최신성 확보 경로(supersede). 수동 재시도 버튼은
  /// 반드시 [_retryManual] 을 거친다.
  void _reload() {
    if (!mounted) return;
    final int gen = ++_loadGeneration;
    final Future<MyPageData> next = (widget.loaderOverride ?? _repo.load)();
    setState(() {
      _loading = true;
    });
    next.then((MyPageData data) {
      if (!mounted || gen != _loadGeneration) return; // 늦은 이전 응답 폐기
      setState(() {
        _loading = false;
        _loadFailed = false;
        _lastError = null;
        _lastGoodData = data; // loader 정상 완료 = 정상 스냅샷 갱신
        final CashSummary? cash = data.cash;
        if (cash != null && cash.balanceCents != null) {
          // 지갑 확정값 확인 시에만 stale 해제·정상 지갑 스냅샷 갱신.
          _lastGoodCash = cash;
          _walletSyncPending = false;
        }
        // cash == null / balanceCents == null 이면 확정 불가 — pending 유지.
      });
    }).catchError((Object e) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _loading = false;
        _loadFailed = true; // 마지막 정상 스냅샷은 삭제하지 않는다.
        _lastError = e;
      });
    });
  }

  /// 캐시 섹션 렌더(순수 — 상태 변경 없음):
  /// - 지갑 변경 후 확정 실패(로드 실패·cash null·balance null) → 마지막 정상
  ///   지갑을 stale 로 보존 표시(이전 금액을 최신 확정값처럼 표시 금지).
  /// - 그 외엔 최신 데이터 그대로(변경 신호 없는 '-' 동작 유지).
  List<Widget> _cashSectionFor(MyPageData data) {
    if (_walletSyncPending && _lastGoodCash != null) {
      return <Widget>[
        CashSection(
          cash: _lastGoodCash!,
          stale: true,
          // v20 정정1: 수동 재시도 — 로딩 중 비활성 + single-flight 공유 가드.
          onRetryStale: _loading ? null : _retryManual,
        ),
      ];
    }
    final CashSummary? fetched = data.cash;
    if (fetched == null) return const <Widget>[];
    return <Widget>[CashSection(cash: fetched)];
  }

  Future<void> _openProfileEdit(MyProfile profile) async {
    final bool? saved = await AppNavigation.push<bool>(
      context,
      AppRoutePaths.profileEdit,
      fallbackBuilder: (_) => ProfileEditScreen(
        profile: profile,
        repository: _deps.profileEdit,
      ),
    );
    if (saved == true && mounted) _reload();
  }

  void _goToQuestions() {
    // 질문방 탭으로 전환(TabNavigator → HomeShell 수신). 테스트는 override 주입.
    if (widget.onOpenQuestionsTab != null) {
      widget.onOpenQuestionsTab!();
      return;
    }
    TabNavigator.go(AppTab.questionRoom);
  }

  @override
  Widget build(BuildContext context) {
    // v19 보정1: 렌더링은 상태를 그리기만 한다. 마지막 정상 스냅샷이 있으면
    // 이후 재조회가 Future.error 로 실패해도 전체 오류 화면으로 교체하지 않는다.
    final MyPageData? good = _lastGoodData;
    final Widget child;
    if (good == null) {
      if (_loading) {
        child = const Center(child: CircularProgressIndicator());
      } else {
        // 초기 진입부터 실패 — 정상 스냅샷이 전혀 없을 때만 전체 오류 화면.
        child = AppErrorView(
          title: '내 정보를 불러오지 못했어요',
          message: _lastError == null ? '' : friendlyError(_lastError!),
          onRetry: _retryManual,
        );
      }
    } else {
      child = _body(good);
    }
    return SafeArea(child: child);
  }

  Widget _body(MyPageData data) {
    // §5-1: 탈퇴 예약 상시 배너(홈 셸과 같은 공통 위젯·공통 상태 소스).
    // ★ ListView 안에 두지 않는다 — SliverList 는 높이 0 인 선두 child 를
    //   수거해버려서, 배너가 '미노출' 상태로 시작하면 element 가 사라지고
    //   나중에 서버 상태가 도착해도 다시 뜨지 않는다(실측). 스크롤 바깥에 두면
    //   상태가 바뀌는 즉시 나타난다. 미노출일 땐 높이 0 이라 레이아웃 영향 없음.
    return Column(
      children: <Widget>[
        const WithdrawalPendingBanner(),
        Expanded(child: _sections(data)),
      ],
    );
  }

  Widget _sections(MyPageData data) {
    final bool signedIn = _auth.isSignedIn;
    return ListView(
      clipBehavior: Clip.none,
      padding: AppPage.contentPadding(context, top: AppSpacing.s16),
      children: <Widget>[
        // v19 보정1: 일반 재조회 실패 — 마지막 정상 화면 위 비단정 안내만.
        if (_loadFailed) ...<Widget>[
          Text('최신 정보를 불러오지 못했습니다.',
              style: AppTypography.caption.copyWith(color: AppColors.danger)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey<String>('mypage-reload-retry'),
              // v20 정정1: 수동 재시도 — 로딩 중 비활성 + single-flight 가드.
              onPressed: _loading ? null : _retryManual,
              child: const Text('다시 시도'),
            ),
          ),
          const SizedBox(height: 4),
        ],
        ProfileSection(
          profile: data.profile,
          // 게스트(비로그인)는 수정 불가 — 세션 있을 때만 수정 진입 노출.
          onEdit:
              _auth.isSignedIn ? () => _openProfileEdit(data.profile) : null,
        ),
        const SizedBox(height: AppSpacing.section),
        if (data.isMentor)
          ..._mentorSections(data)
        else
          ..._studentSections(data),
        SettingsSection(
          onLogout: () => _auth.signOut(),
          showLogout: signedIn,
        ),
        if (kDevToolsEnabled) ...<Widget>[
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () => context.go(EntryGuard.devS3),
              child: const Text('S3 데이터 점검 (개발용)',
                  style: AppTypography.captionSecondary),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _studentSections(MyPageData data) {
    return <Widget>[
      StudentSubscriptionSection(
        subscriptions: data.subscriptions,
        onGoToQuestions: _goToQuestions,
      ),
      ..._cashSectionFor(data),
      // 학생: 리뷰 행 미노출(범용 '리뷰 작성' 메뉴는 폐기 — 역할 게이트).
      SupportSection(onOpenNotifications: widget.onOpenNotifications),
    ];
  }

  List<Widget> _mentorSections(MyPageData data) {
    return <Widget>[
      if (data.mentor != null)
        MentorDashboardSection(
          data: data.mentor!,
          onGoToQuestions: _goToQuestions,
        ),
      // 멘토: '받은 리뷰'(웹 /mentor/reviews — 받은 리뷰 관리 화면) 노출.
      SupportSection(
        onOpenNotifications: widget.onOpenNotifications,
        showReceivedReviews: true,
      ),
    ];
  }
}
