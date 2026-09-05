import 'package:flutter/material.dart';

import '../../../../design/role_theme.dart';
import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_spacing.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../shared/format/formatters.dart';
import '../../data/mentor_note_format.dart';
import '../../data/models/connection_note.dart';

/// 답변 화면 상단 노트 배너(A-5 §2-1 · design-v3 2-1/2-1b) — 1줄로 접혀 있고 탭하면
/// 펼쳐진다. 답변을 쓰는 동안 이 학생의 맥락(내가 마지막으로 남긴 노트)이 눈앞에 있게 한다.
/// 역할 틴트 블록 + 📌 — 목록의 노트 한 줄([NotePreviewLine])과 같은 언어.
class MentorNoteBanner extends StatelessWidget {
  const MentorNoteBanner({
    super.key,
    required this.latest,
    required this.noteCount,
    required this.expanded,
    required this.onToggle,
    required this.onOpenAll,
  });

  /// 내가 이 방에 마지막으로 남긴 노트. 없으면 null.
  final ConnectionNote? latest;
  final int noteCount;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    final ConnectionNote? n = latest;
    final MentorNoteParts? parts =
        n == null ? null : MentorNoteParts.parse(n.body);
    final String headline = n == null
        ? '아직 노트가 없어요 · 답변 후 한 줄 남겨보세요'
        : '${Formatters.relativeKorean(n.createdAt)}에 남긴 노트 · ${parts!.summary}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH, AppSpacing.s8, AppSpacing.screenH, 0),
      child: Material(
        color: roleTheme.tint,
        borderRadius: BorderRadius.circular(AppRadius.button),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.push_pin_rounded,
                        size: 16, color: roleTheme.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        headline,
                        maxLines: expanded ? 3 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
                if (expanded) ...<Widget>[
                  const SizedBox(height: 8),
                  if (parts != null && parts.isStructured) ...<Widget>[
                    if (parts.weakness != null)
                      _PartRow(
                          label: kMentorNoteWeaknessLabel,
                          text: parts.weakness!),
                    if (parts.next != null)
                      _PartRow(label: kMentorNoteNextLabel, text: parts.next!),
                  ] else if (parts != null)
                    Text(parts.plain ?? '', style: AppTypography.body)
                  else
                    const Text(
                      '답변을 보낸 뒤 약점과 다음에 풀 유형을 한 줄씩 적어 두면, 다음 답변에서 이 자리에 보여요.',
                      style: AppTypography.captionSecondary,
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onOpenAll,
                      child: Text(
                          noteCount > 0 ? '노트 $noteCount개 전체 보기' : '연결노트 열기'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PartRow extends StatelessWidget {
  const _PartRow({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(label, style: AppTypography.captionSecondary),
          ),
          Expanded(child: Text(text, style: AppTypography.body)),
        ],
      ),
    );
  }
}
