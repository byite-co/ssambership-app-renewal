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
import '../../../core/auth/auth_service.dart';
import '../../../core/commerce/commerce_policy.dart';
import '../../../design/widgets/secondary_button.dart';
import '../../../shared/widgets/commerce_notice_card.dart';
import '../../individual_question/iq_flags.dart';
import '../../individual_question/ui/iq_create_screen.dart';

/// 멘토 상세(열람 전용). 목록에서 받은 항목을 재사용하고, 평균 답변시간·구독 여부만
/// 추가로 불러온다. CTA 는 구독 상태에 따라 [질문방으로]/[구독하기](웹 브릿지).
class MentorDetailScreen extends StatefulWidget {
  const MentorDetailScreen({
    super.key,
    required this.item,
    this.initialFavorited = false,
  });

  final MentorListItem item;

  /// 목록에서 넘어올 때의 찜 상태(하트 초기값). 상세에서 토글하면 서버 반영.
  final bool initialFavorited;

  @override
  State<MentorDetailScreen> createState() => _MentorDetailScreenState();
}

class _MentorDetailScreenState extends State<MentorDetailScreen> {
  final MentorDirectoryRepository _repo = const MentorDirectoryRepository();
  final MentorFavoritesRepository _favRepo = const MentorFavoritesRepository();
  late Future<MentorDetailExtras> _future;
  late bool _favorited = widget.initialFavorited;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchExtras(widget.item.id);
  }

  /// 하트 탭 — 비로그인이면 로그인 유도, 아니면 낙관적 토글 후 서버 반영(실패 시 되돌림).
  Future<void> _toggleFavorite() async {
    if (!_favRepo.isLoggedIn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인하면 멘토를 찜할 수 있어요.')),
        );
      }
      return;
    }
    final bool wasFav = _favorited;
    setState(() => _favorited = !wasFav);
    final bool ok = wasFav
        ? await _favRepo.remove(widget.item.id)
        : await _favRepo.add(widget.item.id);
    if (!ok && mounted) {
      setState(() => _favorited = wasFav);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('찜 처리에 실패했어요. 잠시 후 다시 시도해 주세요.')),
      );
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
          FutureBuilder<MentorDetailExtras>(
            future: _future,
            builder:
                (BuildContext context, AsyncSnapshot<MentorDetailExtras> snap) {
              final MentorDetailExtras extras =
                  snap.data ?? const MentorDetailExtras();
              return _Section(
                title: '활동',
                child: _StatsView(
                  extras: extras,
                  loading: snap.connectionState != ConnectionState.done,
                ),
              );
            },
          ),
          // 컴플라이언스: 요금제 섹션(가격 숫자·안내문) 제거 — 결제 유도 방지.
          // 구독 CTA는 가격 없이 이동만 유지.
          const SizedBox(height: AppSpacing.s24),
          FutureBuilder<MentorDetailExtras>(
            future: _future,
            builder:
                (BuildContext context, AsyncSnapshot<MentorDetailExtras> snap) {
              // null = 구독 여부 미확정(로딩·조회 실패) — 무료 CTA 활성화 금지.
              final bool? subscribed =
                  snap.hasData ? snap.data!.alreadySubscribed : null;
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
                      setState(
                          () => _future = _repo.fetchExtras(widget.item.id));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('무료 질문을 보냈어요. 질문방에서 확인할 수 있어요.')));
                      _goToQuestionRoom(context);
                    },
                  ),
                ],
              );
            },
          ),
          // 개별질문: 구독 없이 1건씩 캐시로 질문(지정형). 학생만.
          if (kIndividualQuestionEnabled &&
              kIndividualQuestionCreateEnabled &&
              AuthService.instance.currentRole == AppRole.student) ...<Widget>[
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

  Future<void> _openIndividualQuestion(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => IqCreateScreen(
          mentorId: widget.item.id,
          mentorName: widget.item.displayName,
        ),
      ),
    );
  }

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
