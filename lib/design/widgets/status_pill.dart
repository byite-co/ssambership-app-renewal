import 'package:flutter/material.dart';
import '../shape_tokens.dart';
import '../tokens/color_tokens.dart';

/// 상태 칩의 의미색(시맨틱 토큰에만 매핑 — hex 하드코딩 금지).
/// 전 tone 이 **역할 무관 공통 시맨틱색**이다.
///
/// [QA-C4] info 는 원래 역할 강조색(학생 파랑 #2563EB / 멘토 초록 #059669)이었다.
/// 그런데 상태칩에서 info 는 '진행 중', success 는 '답변 완료'를 뜻하는데
/// success(#047857)도 초록이라, **멘토 화면에서는 진행 중과 답변 완료가 둘 다
/// 초록으로 보여 구분되지 않았다**. 상태색은 역할이 아니라 상태를 말해야 하므로
/// info 를 역할 무관 파랑으로 고정한다 — 학생 화면은 종전과 동일하고, 멘토 화면만
/// 진행 중이 파랑으로 돌아온다(QA 기대 동작).
///
/// 역할 강조색이 필요한 곳(버튼·링크 등)은 그대로 AppAccent 를 쓴다 —
/// 여기서 바꾸는 것은 **상태 의미색**뿐이다.
enum StatusTone { neutral, info, success, warning, danger }

/// tone → 시맨틱 색(단일 소스). StatusPill·StatusDot·CountBadge 가 공유한다.
Color statusToneColor(BuildContext context, StatusTone tone) {
  switch (tone) {
    case StatusTone.success:
      return ColorTokens.success;
    case StatusTone.warning:
      return ColorTokens.warning;
    case StatusTone.danger:
      return ColorTokens.danger;
    case StatusTone.info:
      // 역할 무관 고정 파랑 — success(초록)와 반드시 구분돼야 한다(QA-C4).
      return ColorTokens.accent;
    case StatusTone.neutral:
      return ColorTokens.secondary;
  }
}

/// 상태 색 도트(D1-B). 상태칩 앞에서 스캔성을 높이는 작은 solid 원.
/// 색만 tone 에서 가져오고 텍스트/의미는 기존 칩·문구가 유지한다.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, this.tone = StatusTone.neutral, this.size = 8});

  final StatusTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: statusToneColor(context, tone),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// 상태 한글 칩. 예: 답변대기/진행중/답변완료/분쟁.
/// label 은 '한글'만 받는다(영문 enum/코드 노출 금지). 색은 tone → 시맨틱 토큰.
/// [showDot] = true 면 라벨 앞에 같은 색 solid 도트(스캔성↑, D1-B).
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.showDot = false,
  });

  final String label;
  final StatusTone tone;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final Color c = statusToneColor(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      // 틴트 스타일: 채운 원색 대신 옅은 틴트 배경(12%) + 같은 계열 진한 텍스트.
      // 무거운 외곽선 제거(토스식 soft pill).
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: AppShape.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showDot) ...<Widget>[
            StatusDot(tone: tone, size: 6),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style:
                TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
