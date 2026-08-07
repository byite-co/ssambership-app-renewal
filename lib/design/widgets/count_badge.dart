import 'package:flutter/material.dart';

import '../role_accent.dart';
import '../shape_tokens.dart';
import 'status_pill.dart';

/// 카운트 배지(D1-D) — 주목 필요한 개수를 원형/pill 배지로. ★값(count)만 받는 순수 위젯★.
///
/// 색: tone 을 주면 그 상태색, 안 주면 **역할 강조색**(학생 파랑/멘토 초록).
/// solid 배경 + 흰 숫자(스캔성↑, tabular).
/// count ≤ 0 이면 아무것도 그리지 않는다. [max] 초과는 'max+'(예: 99+).
///
/// [QA-C4] 종전 기본값은 StatusTone.info 였다. 상태칩의 info 를 역할 무관
/// 파랑으로 고정하면서(진행 중 vs 답변 완료 구분) 이 배지까지 파래지는 건
/// 과한 변경이다 — 개수 배지는 '상태'가 아니라 정체성 장식에 가깝다.
/// 그래서 tone 을 nullable 로 두고 기본은 AppAccent 를 직접 쓴다.
class CountBadge extends StatelessWidget {
  const CountBadge({
    super.key,
    required this.count,
    this.tone,
    this.max = 99,
  });

  final int count;

  /// null 이면 역할 강조색을 쓴다(정체성 유지). 상태를 뜻할 때만 tone 을 준다.
  final StatusTone? tone;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final StatusTone? t = tone;
    final Color c =
        t == null ? AppAccent.of(context).accent : statusToneColor(context, t);
    final String text = count > max ? '$max+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c, borderRadius: AppShape.pillRadius),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.2,
          fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
