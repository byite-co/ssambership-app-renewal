import 'package:flutter/material.dart';

import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/typography_tokens.dart';
import '../../../../design/widgets/app_badge.dart';
import '../../../../design/widgets/app_card.dart';
import '../../../../design/widgets/initial_avatar.dart';
import '../../data/mentor_models.dart';
import '../../data/mentor_subject.dart';
import 'mentor_favorite_button.dart';
import 'mentor_meta_item.dart';

/// 멘토 목록 카드(열람 전용). 탭하면 상세로, '구독하기'는 웹 브릿지로 연결.
class MentorCard extends StatelessWidget {
  const MentorCard({
    super.key,
    required this.item,
    required this.onOpen,
    this.favorited = false,
    this.onToggleFavorite,
  });

  final MentorListItem item;
  final VoidCallback onOpen;

  /// 이 멘토를 찜했는지(하트 채움 여부).
  final bool favorited;

  /// 찜 토글 콜백. null 이면 하트를 표시하지 않는다(비로그인 목록 등).
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final MentorProfileInfo? profile = item.profile;
    final List<MentorSubject> subjects = item.subjectViews;
    final String? school = profile?.schoolLine;
    final String? intro = profile?.introLine?.trim();

    return AppCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              InitialAvatar(name: item.displayName, size: 48),
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
                      const SizedBox(height: 3),
                      // 대학·학과 → school 아이콘(보조색).
                      MentorMetaItem(icon: Icons.school_rounded, text: school),
                    ],
                  ],
                ),
              ),
              // 우상단 찜 하트(콜백 있을 때만 — 카드 탭보다 우선 처리).
              if (onToggleFavorite != null)
                MentorFavoriteButton(
                  favorited: favorited,
                  onTap: onToggleFavorite!,
                ),
            ],
          ),
          if (subjects.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            // 담당 과목/태그 → menu_book 아이콘(보조색) + 기존 칩(로직·색 불변).
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Icon(Icons.menu_book_rounded,
                      size: 16, color: ColorTokens.secondary),
                ),
                const SizedBox(width: 5),
                Expanded(child: _SubjectChips(subjects: subjects)),
              ],
            ),
          ],
          if (intro != null && intro.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              intro,
              style: AppType.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          // 컴플라이언스: 앱 내 가격 표시 제거(결제 유도 방지).
          // 학교·과목·소개만 노출, 상세 진입은 카드 탭.
        ],
      ),
    );
  }
}

/// 과목 칩(최대 4개 + 초과분은 '+N'). canonical 한글 라벨만 표시(raw 코드 노출 금지).
class _SubjectChips extends StatelessWidget {
  const _SubjectChips({required this.subjects});

  final List<MentorSubject> subjects;

  @override
  Widget build(BuildContext context) {
    const int maxShown = 4;
    final List<MentorSubject> shown = subjects.take(maxShown).toList();
    final int extra = subjects.length - shown.length;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final MentorSubject s in shown) AppBadge(label: s.label),
        if (extra > 0) AppBadge(label: '+$extra'),
      ],
    );
  }
}
