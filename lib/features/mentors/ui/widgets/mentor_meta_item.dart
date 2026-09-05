import 'package:flutter/material.dart';

import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_typography.dart';

/// 멘토 카드 메타 항목(D-2 P1) — leading Material 아이콘 + 텍스트로 스캔성↑.
/// ★표현 전용: 데이터/로직 없음. 큰 일러스트 아님(본문에 맞춘 인라인 16px 표준 아이콘).★
///
/// 아이콘 색 기본 = 보조 텍스트색([AppColors.textSecondary]). 평점 등 의미색이
/// 맞는 항목만 호출부에서 [iconColor] 에 상태색 토큰을 넘긴다(raw hex 금지).
class MentorMetaItem extends StatelessWidget {
  const MentorMetaItem({
    super.key,
    required this.icon,
    required this.text,
    this.style,
    this.iconColor,
    this.maxLines = 1,
  });

  final IconData icon;
  final String text;

  /// 텍스트 스타일(기본 보조 캡션). 본문 위계가 필요한 항목은 body 를 넘긴다.
  final TextStyle? style;

  /// 아이콘 색(기본 보조색).
  final Color? iconColor;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: iconColor ?? AppColors.textSecondary),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: style ?? AppTypography.captionSecondary,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
