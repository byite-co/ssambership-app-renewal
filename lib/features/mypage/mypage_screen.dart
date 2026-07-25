import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_tabs.dart';
import '../../app/entry_guard.dart';
import '../../core/auth/auth_service.dart';
import '../../core/refresh/data_refresh_bus.dart';
import '../../design/spacing_tokens.dart';
import '../../design/tokens/color_tokens.dart';
import '../../design/typography_tokens.dart';
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

class _MyPageScreenState extends State<MyPageScreen> {
  final MyPageRepository _repo = const MyPageRepository();
  late Future<MyPageData> _future;

  @override
  void initState() {
    super.initState();
    _future = (widget.loaderOverride ?? _repo.load)();
    // §4: 지갑 변경 신호(IQ 예치·환불·정산 등) 수신 → 잔액·최근 내역 재조회.
    // Future 교체 + FutureBuilder 라 늦은 이전 응답이 최신 상태를 덮지 않는다.
    DataRefreshBus.walletGeneration.addListener(_onWalletChanged);
  }

  @override
  void dispose() {
    DataRefreshBus.walletGeneration.removeListener(_onWalletChanged);
    super.dispose();
  }

  void _onWalletChanged() {
    if (!mounted) return; // dispose 후 상태 변경 금지.
    _reload();
  }

  void _reload() {
    if (!mounted) return;
    // ★ 블록 바디: setState(() => _future = future) 는 클로저가 Future 를 반환해
    //   'setState callback returned a Future' 로 리빌드가 취소된다.
    final Future<MyPageData> next = (widget.loaderOverride ?? _repo.load)();
    setState(() {
      _future = next;
    });
  }

  Future<void> _openProfileEdit(MyProfile profile) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProfileEditScreen(profile: profile),
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
    return SafeArea(
      child: FutureBuilder<MyPageData>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<MyPageData> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('내 정보를 불러오지 못했어요.\n${friendlyError(snap.error!)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: ColorTokens.danger)),
              ),
            );
          }
          return _body(snap.data!);
        },
      ),
    );
  }

  Widget _body(MyPageData data) {
    final bool signedIn = AuthService.instance.isSignedIn;
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(20, AppSpacing.s16, 20, AppSpacing.s24),
      children: <Widget>[
        ProfileSection(
          profile: data.profile,
          // 게스트(비로그인)는 수정 불가 — 세션 있을 때만 수정 진입 노출.
          onEdit: AuthService.instance.isSignedIn
              ? () => _openProfileEdit(data.profile)
              : null,
        ),
        const SizedBox(height: AppSpacing.section),
        if (data.isMentor)
          ..._mentorSections(data)
        else
          ..._studentSections(data),
        SettingsSection(
          onLogout: () => AuthService.instance.signOut(),
          showLogout: signedIn,
        ),
        if (kDevToolsEnabled) ...<Widget>[
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () => context.go(EntryGuard.devS3),
              child: Text('S3 데이터 점검 (개발용)', style: AppType.caption),
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
      if (data.cash != null) CashSection(cash: data.cash!),
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
