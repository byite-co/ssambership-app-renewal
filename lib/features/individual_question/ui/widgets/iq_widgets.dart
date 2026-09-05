import 'package:flutter/material.dart';

import '../../../../data/mappings/subject_labels.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/app_badge.dart';
import '../../../../design/widgets/glass_card.dart';
import '../../../../design/widgets/status_pill.dart';
import '../../../../shared/format/formatters.dart';
import '../../data/models/individual_question_models.dart';

/// 상태 → 시맨틱 톤(웹 배지색 규약 미러: released(답변완료)=info,
/// answered(답변 도착)=success, 진행(예치·공개·답변중)=warning,
/// 종결(환불·만료·취소)=neutral). 톤 매핑은 미변경 — 라벨 문구만 앱 전용.
StatusTone iqStatusTone(IndividualQuestionStatus s) {
  switch (s) {
    case IndividualQuestionStatus.released:
      return StatusTone.info;
    case IndividualQuestionStatus.answered:
      return StatusTone.success;
    case IndividualQuestionStatus.escrowed:
    case IndividualQuestionStatus.assigned:
    case IndividualQuestionStatus.open:
    case IndividualQuestionStatus.claimed:
      return StatusTone.warning;
    case IndividualQuestionStatus.refunded:
    case IndividualQuestionStatus.expired:
    case IndividualQuestionStatus.canceled:
    case IndividualQuestionStatus.unknown:
      return StatusTone.neutral;
  }
}

/// 상태 칩(한글 라벨만).
class IqStatusPill extends StatelessWidget {
  const IqStatusPill({super.key, required this.status});

  final IndividualQuestionStatus status;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: iqStatusLabel(status),
      tone: iqStatusTone(status),
    );
  }
}

/// 목록용 질문 카드 — 제목·유형·가격·상태·마감 남은시간.
class IqQuestionCard extends StatelessWidget {
  const IqQuestionCard({
    super.key,
    required this.question,
    this.onTap,
  });

  final IndividualQuestion question;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final String? remaining =
        formatIqExpiryRemaining(question.expiresAt, question.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 컴플라이언스: 카드에서 금액 표시 제거(유형·상태만).
            Row(
              children: <Widget>[
                AppBadge(label: iqTypeLabel(question.type), tinted: true),
                const SizedBox(width: 6),
                IqStatusPill(status: question.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              question.title.isEmpty ? '(제목 없음)' : question.title,
              style: AppTypography.bodyStrong,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            // [QA-B6] 학생 본인 목록에서도 자신이 건 조건을 확인할 수 있어야 한다.
            IqRequirementChips(
              subject: question.subject,
              requiredSchoolTier: question.requiredSchoolTier,
              requiredMajorCategory: question.requiredMajorCategory,
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                if (question.createdAt != null)
                  Text(
                    Formatters.relativeKorean(question.createdAt!),
                    style: AppTypography.meta,
                  ),
                if (remaining != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Text(remaining, style: AppTypography.meta),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 멘토용 공개 대기 질문 카드(위생 필드만 — 본문·학생 정보 없음).
class IqOpenQuestionCard extends StatelessWidget {
  const IqOpenQuestionCard({
    super.key,
    required this.question,
    this.onClaim,
  });

  final OpenIndividualQuestion question;
  final VoidCallback? onClaim;

  @override
  Widget build(BuildContext context) {
    final String? remaining = formatIqExpiryRemaining(
      question.expiresAt,
      IndividualQuestionStatus.open,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 컴플라이언스: 금액 표시 제거(유형 뱃지만).
            const Row(
              children: <Widget>[
                AppBadge(label: '공개형', tinted: true),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              question.title.isEmpty ? '(제목 없음)' : question.title,
              style: AppTypography.bodyStrong,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            // [QA-B6] 수락 전에 조건을 볼 수 있어야 한다.
            IqRequirementChips(
              subject: question.subject,
              requiredSchoolTier: question.requiredSchoolTier,
              requiredMajorCategory: question.requiredMajorCategory,
            ),
            if (remaining != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(remaining, style: AppTypography.meta),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onClaim,
                child: const Text('수락하고 답변하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [QA-B6] 질문의 조건(과목 · 요구 학교군 · 요구 계열)을 한 줄 칩으로 보여준다.
///
/// 멘토는 이 조건을 보고 수락 여부를 판단한다 — 종전에는 서버에 값이 있고 웹은
/// 보여주는데 앱만 아무것도 그리지 않아, 조건을 모른 채 질문을 잡아야 했다.
/// 값이 하나도 없으면 아무것도 그리지 않는다(빈 줄·빈 칩 금지).
class IqRequirementChips extends StatelessWidget {
  const IqRequirementChips({
    super.key,
    this.subject,
    this.requiredSchoolTier,
    this.requiredMajorCategory,
  });

  final String? subject;
  final String? requiredSchoolTier;
  final String? requiredMajorCategory;

  static String? _clean(String? v) {
    final String t = (v ?? '').trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    // subject 는 DB 정본 코드(`korean_reading` 등)로 내려온다 — 반드시 한글 라벨화.
    // (학교군·계열은 한글로 저장되어 그대로 쓴다. 실측 2026-08-07)
    final String? rawSubject = _clean(subject);
    final String? s = rawSubject == null ? null : subjectLabel(rawSubject);
    final String? tier = _clean(requiredSchoolTier);
    final String? major = _clean(requiredMajorCategory);
    if (s == null && tier == null && major == null)
      return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          if (s != null) AppBadge(label: s, tone: AppBadgeTone.neutral),
          // 문구는 웹 작성 폼의 어휘를 그대로 쓴다('학교군'·'전공계열') —
          // 앱이 '이상'·'계열' 같은 순서·의미를 지어내면 학생이 건 조건과 어긋난다.
          if (tier != null)
            AppBadge(label: '학교군 · $tier', tone: AppBadgeTone.neutral),
          if (major != null)
            AppBadge(label: '전공계열 · $major', tone: AppBadgeTone.neutral),
        ],
      ),
    );
  }
}
