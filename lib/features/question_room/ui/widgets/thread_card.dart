import 'package:flutter/material.dart';

import '../../../../data/mappings/subject_labels.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/app_badge.dart';
import '../../../../design/widgets/glass_card.dart';
import '../../../../shared/format/formatters.dart';
import '../../data/models/question_thread.dart';
import 'thread_status_pill.dart';

/// 질문 스레드 카드(공통). 학생 질문목록(S4)·멘토 질문목록(S5)이 함께 쓴다.
///
/// 제목 + 상태칩 / 과목 배지 + 활동시각 / (선택)하단 액션.
/// 역할별 차이는 [bottomAction] 으로만 주입한다(학생=답변 확인, 멘토=없음 등).
class ThreadCard extends StatelessWidget {
  const ThreadCard({
    super.key,
    required this.thread,
    required this.onOpen,
    this.bottomAction,
  });

  final QuestionThread thread;
  final VoidCallback onOpen;

  /// 카드 하단에 붙는 선택적 액션(예: 학생의 '답변 확인 완료' 버튼).
  final Widget? bottomAction;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  thread.title?.trim().isNotEmpty == true
                      ? thread.title!.trim()
                      : '(제목 없음)',
                  style: AppTypography.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ThreadStatusPill(status: thread.status),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              AppBadge(
                label: subjectLabel(thread.subject),
                tone: AppBadgeTone.neutral,
              ),
              const Spacer(),
              Text(
                Formatters.relativeKorean(thread.updatedAt),
                style: AppTypography.meta,
              ),
            ],
          ),
          if (bottomAction != null) ...<Widget>[
            const SizedBox(height: 12),
            bottomAction!,
          ],
        ],
      ),
    );
  }
}
