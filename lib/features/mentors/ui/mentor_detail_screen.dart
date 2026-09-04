import 'package:flutter/material.dart';

import '../../../design/tokens/color_tokens.dart';
import '../../../design/spacing_tokens.dart';
import '../../../design/typography_tokens.dart';
import '../../../design/widgets/app_badge.dart';
import '../../../design/widgets/app_card.dart';
import '../../../design/widgets/initial_avatar.dart';
import '../../../design/widgets/primary_button.dart';
import '../data/free_question_entry.dart';
import '../data/mentor_directory_repository.dart';
import '../data/mentor_favorites_repository.dart';
import '../data/mentor_models.dart';
import '../data/mentor_subject.dart';
import 'widgets/free_question_entry_section.dart';
import 'widgets/mentor_favorite_button.dart';
import 'widgets/mentor_meta_item.dart';
import '../../../app/app_tabs.dart';
import '../../../app/app_scope.dart';
import '../../../core/auth/auth_service.dart' show AppRole;
import '../../../core/commerce/commerce_policy.dart';
import '../../../core/refresh/data_refresh_bus.dart';
import '../../../design/widgets/secondary_button.dart';
import '../../../shared/widgets/commerce_notice_card.dart';
import '../../../core/web_bridge/web_bridge.dart';
import '../../../core/web_bridge/web_bridge_actions.dart';
import '../../individual_question/iq_flags.dart';
import '../../../shared/widgets/screen_visibility.dart';

/// 멘토 상세(열람 전용). 목록에서 받은 항목을 재사용하고, 평균 답변시간·구독 여부만
/// 추가로 불러온다. CTA 는 구독 상태에 따라 [질문방으로]/[구독하기](웹 브릿지).
///
/// §4-2 최신성: 구독은 앱 밖(웹)에서 일어나므로(Commerce-Zero — 앱 내 구독 진입 없음)
/// 구독 성공 후 앱으로 돌아오면 **resume 재조회**가 정본 경로다. 앱 안에서 구독 상태
/// 변화를 알게 된 지점은 [DataRefreshBus.bumpSubscription] 으로 보완한다.
/// 두 경로 모두 세대 토큰(`_extrasGeneration`)을 지나 늦은 이전 응답을 폐기한다.
class MentorDetailScreen extends StatefulWidget {
  const MentorDetailScreen({
    super.key,
    required this.item,
    this.initialFavorited = false,
    this.extrasLoaderOverride,
    this.webBridgeOverride,
    this.createCtaOverride,
  });

  final MentorListItem item;

  /// 목록에서 넘어올 때의 찜 상태(하트 초기값). 상세에서 토글하면 서버 반영.
  final bool initialFavorited;

  /// 테스트용 extras 로더 주입(loaderOverride 패턴) — 실사용은 null.
  final Future<MentorDetailExtras> Function()? extrasLoaderOverride;

  /// 테스트용 웹 브릿지 주입(loaderOverride 패턴) — 실사용은 null.
  final WebBridge? webBridgeOverride;

  /// 테스트용 '개별질문 하기' CTA 노출 강제 — 실사용은 null
  /// (null 이면 플래그·역할 기준 기존 판정 그대로).
  final bool? createCtaOverride;

  @override
  State<MentorDetailScreen> createState() => _MentorDetailScreenState();
}

class _MentorDetailScreenState extends State<MentorDetailScreen>
    with WidgetsBindingObserver, ResumeVisibilityGate {

  late final MentorDirectoryRepository _repo;
  late final MentorFavoritesRepository _favRepo;
  late bool _favorited = widget.initialFavorited;

  /// 마지막 '정상 완료' extras 스냅샷. 재조회 중에도 이 값을 계속 그린다 —
  /// 재조회 때마다 구독 CTA 가 미확정(null)으로 깜빡이던 문제를 막는다.
  MentorDetailExtras? _extras;

  /// 아직 한 번도 정상 완료하지 못한 첫 로드 진행 중인지(활동 통계 '불러오는 중…').
  bool _loading = true;

  /// 늦게 도착한 이전 재조회 응답 폐기용 세대 토큰(mypage v20 계약과 동일).
  int _extrasGeneration = 0;

  @override
  void initState() {
    super.initState();
    final AppDependencies dependencies = AppScope.of(context);
    _repo = dependencies.mentorDirectory;
    _favRepo = dependencies.mentorFavorites;
    _reloadExtras();
    // 웹에서 구독을 마치고 앱으로 복귀 → 구독 여부 재조회(CTA stale 제거).
    WidgetsBinding.instance.addObserver(this);
    // 앱 안에서 알게 된 구독 상태 변화 신호.
    DataRefreshBus.subscriptionGeneration.addListener(_onSubscriptionChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) handleResumed();
  }

  // N12: 보일 때만 재조회(가려진 탭·덮인 라우트는 재노출 시 1회).
  @override
  void onResumeRefresh() {
    _reloadExtras();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DataRefreshBus.subscriptionGeneration
        .removeListener(_onSubscriptionChanged);
    super.dispose();
  }

  void _onSubscriptionChanged() {
    if (!mounted) return; // dispose 후 상태 변경 금지.
    _reloadExtras();
  }

  /// extras 재조회 — 상태 갱신은 loader 완료 지점에서만. 실패해도 마지막 정상
  /// 스냅샷을 지우지 않는다(최초 로드 실패는 기존과 동일하게 빈 extras 로 렌더).
  void _reloadExtras() {
    if (!mounted) return;
    final int gen = ++_extrasGeneration;
    // C26: 목록 항목이 이미 가진 평점·리뷰 수를 넘겨 뷰 단건 재조회를 생략.
    final Future<MentorDetailExtras> next = (widget.extrasLoaderOverride ??
        () => _repo.fetchExtras(
              widget.item.id,
              knownAvgRating: widget.item.avgRating,
              knownReviewCount: widget.item.reviewCount,
            ))();
    next.then((MentorDetailExtras data) {
      if (!mounted || gen != _extrasGeneration) return; // 늦은 이전 응답 폐기
      setState(() {
        _extras = data;
        _loading = false;
      });
    }).catchError((Object _) {
      if (!mounted || gen != _extrasGeneration) return;
      setState(() => _loading = false); // 마지막 정상 스냅샷은 보존
    });
  }

  /// C24: 연타 가드 — 목록 화면(_favPending)과 동일하게 in-flight 중 재탭 무시.
  bool _favPending = false;

  /// 하트 탭 — 비로그인이면 로그인 유도, 아니면 낙관적 토글 후 서버 반영(실패 시 되돌림).
  Future<void> _toggleFavorite() async {
    if (_favPending) return;
    if (!_favRepo.isLoggedIn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인하면 멘토를 찜할 수 있어요.')),
        );
      }
      return;
    }
    final bool wasFav = _favorited;
    _favPending = true;
    setState(() => _favorited = !wasFav);
    try {
      final bool ok = wasFav
          ? await _favRepo.remove(widget.item.id)
          : await _favRepo.add(widget.item.id);
      if (!ok && mounted) {
        setState(() => _favorited = wasFav);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('찜 처리에 실패했어요. 잠시 후 다시 시도해 주세요.')),
        );
      }
    } finally {
      _favPending = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final MentorListItem m = widget.item;
    return Scaffold(
      appBar: AppBar(
        title: Text(m.displayName),
        actions: <Widget>[
          MentorFavoriteButton(favorited: _favorited, onTap: _toggleFavorite),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH, 16, AppSpacing.screenH, 24),
        children: <Widget>[
          _Header(item: m),
          if (m.subjectViews.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.cardGap),
            _Section(
              icon: Icons.menu_book_rounded,
              title: '지도 과목',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  // canonical 한글 라벨만 노출(raw 코드 노출 금지).
                  for (final MentorSubject s in m.subjectViews)
                    AppBadge(label: s.label),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.cardGap),
          _Section(
            title: '소개',
            child: Text(
              (m.profile?.introLine?.trim().isNotEmpty ?? false)
                  ? m.profile!.introLine!.trim()
                  : '아직 소개가 등록되지 않은 신규 멘토예요.',
              style: AppType.body,
            ),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          _Section(
            title: '활동',
            child: _StatsView(
              extras: _extras ?? const MentorDetailExtras(),
              // 첫 정상 응답 전까지만 '불러오는 중…' — 재조회 중에는 직전 값을 유지.
              loading: _loading && _extras == null,
            ),
          ),
          // 컴플라이언스: 요금제 섹션(가격 숫자·안내문) 제거 — 결제 유도 방지.
          // 구독 CTA는 가격 없이 이동만 유지.
          const SizedBox(height: AppSpacing.s24),
          Builder(
            builder: (BuildContext context) {
              // null = 구독 여부 미확정(첫 로딩·조회 실패) — 무료 CTA 활성화 금지.
              final bool? subscribed = _extras?.alreadySubscribed;
              if (subscribed == true) {
                return PrimaryButton(
                  label: '질문방으로',
                  icon: Icons.forum_rounded,
                  onPressed: () => _goToQuestionRoom(context),
                );
              }
              // 커머스 제로: 구매 유도(구독하기) 제거 → 비상호작용 안내.
              // 무료 질문(세션1 §3): 비구독 학생 전용 — 개별질문 CTA 와 독립.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const CommerceNoticeCard(text: kSubscribeNoticeText),
                  FreeQuestionEntrySection(
                    mentorId: widget.item.id,
                    mentorName: widget.item.displayName,
                    alreadySubscribed: subscribed,
                    onCreated: (CreatedFreeQuestion created) {
                      // 성공: 상세 extras 재조회 + 성공 안내 + 기존 질문방
                      // 이동 계약(_goToQuestionRoom) 재사용 — 정본 room 으로.
                      _reloadExtras();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('무료 질문을 보냈어요. 질문방에서 확인할 수 있어요.')));
                      _goToQuestionRoom(context);
                    },
                  ),
                ],
              );
            },
          ),
          // 개별질문(지정형) 신규 등록: 경계 확정(2026-08-05) — 등록은 웹에서만.
          // 이 CTA 는 네이티브 등록 화면이 아니라 웹 등록 페이지를 연다. 학생만.
          if (widget.createCtaOverride ??
              (kIndividualQuestionEnabled &&
                  kIndividualQuestionCreateEnabled &&
                  AppScope.of(context).auth.currentRole ==
                      AppRole.student)) ...<Widget>[
            const SizedBox(height: 10),
            SecondaryButton(
              label: '개별질문 하기',
              icon: Icons.help_outline,
              onPressed: () => _openIndividualQuestion(context),
            ),
          ],
        ],
      ),
    );
  }

  /// 경계 확정(2026-08-05): 신규 개별질문 등록은 웹 전용 — 네이티브 등록 화면을
  /// 열지 않고 멘토 지정형 웹 등록 페이지로 연결한다(실패·미확정 시 안내 폴백).
  Future<void> _openIndividualQuestion(BuildContext context) =>
      openIqCreateWeb(context,
          mentorId: widget.item.id, bridge: widget.webBridgeOverride);

  void _goToQuestionRoom(BuildContext context) {
    // 루트(HomeShell)로 되돌아간 뒤 질문방 탭으로 전환 요청.
    // TabNavigator(app_tabs) → HomeShell 이 수신해 탭 인덱스를 바꾼다(라우터 변경 불필요).
    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    TabNavigator.go(AppTab.questionRoom);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item});
  final MentorListItem item;

  @override
  Widget build(BuildContext context) {
    final String? school = item.profile?.schoolLine;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InitialAvatar(name: item.displayName, size: 64),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      item.displayName,
                      style: AppType.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (item.isVerified) ...<Widget>[
                    const SizedBox(width: 6),
                    const AppBadge(label: '인증', tinted: true),
                  ],
                ],
              ),
              if (school != null) ...<Widget>[
                const SizedBox(height: 4),
                // 대학·학과 → school 아이콘(멘토 카드 D-2 P1과 동일 패턴).
                MentorMetaItem(icon: Icons.school_rounded, text: school),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 활동 통계: 공개 가능한 항목만 표시(평점·리뷰수·평균 답변시간). 값이 없으면 날조하지
/// 않고 자연스러운 빈 처리. 표시는 공통 [MentorMetaItem] 재사용(별=warning 토큰).
class _StatsView extends StatelessWidget {
  const _StatsView({required this.extras, required this.loading});
  final MentorDetailExtras extras;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Text('불러오는 중…', style: AppType.caption);
    }
    if (extras.hasNoActivity) {
      return const Text('아직 활동 정보가 없어요.', style: AppType.body);
    }

    final List<Widget> lines = <Widget>[];
    // 평점(별 + 숫자) · 리뷰 수 — 공개 리뷰가 있을 때만. 별은 의미색(warning) 토큰.
    final String? rating = extras.ratingLabel;
    if (rating != null) {
      lines.add(MentorMetaItem(
        icon: Icons.star_rounded,
        iconColor: ColorTokens.warning,
        text: rating,
        style: AppType.body,
      ));
    }
    // 평균 응답시간 — 값이 있을 때만(schedule 아이콘).
    final String? response = extras.responseLabel;
    if (response != null) {
      lines.add(MentorMetaItem(
        icon: Icons.schedule_rounded,
        text: response,
        style: AppType.body,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < lines.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.s8),
          lines[i],
        ],
      ],
    );
  }
}

// 컴플라이언스: 요금제 표시(_PlansView) 제거 — 앱 내 가격 노출 금지.

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.icon});
  final String title;
  final Widget child;

  /// 섹션 제목 앞 leading 아이콘(선택). 없으면 기존과 동일(제목만).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 18, color: ColorTokens.secondary),
                const SizedBox(width: 6),
              ],
              Text(title, style: AppType.title),
            ],
          ),
          const SizedBox(height: AppSpacing.titleBody),
          child,
        ],
      ),
    );
  }
}
