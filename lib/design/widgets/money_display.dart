import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_typography.dart';

/// 금액 강조 — 큰 숫자(32 Bold · tabular). ★표시 전용: 포맷된 문자열만 받음★.
///
/// 라벨(작게, 위) + 금액(크게). 화면의 '주인공' 금액(캐시 잔액·정산 등)에만 쓴다.
/// [emphasizeColor] 로 역할색 강조 선택.
class MoneyDisplay extends StatelessWidget {
  const MoneyDisplay({
    super.key,
    required this.label,
    required this.amount,
    this.emphasizeColor,
  });

  /// 위에 작게 표기할 라벨(예: '지금 쓸 수 있는 캐시').
  final String label;

  /// 이미 포맷된 금액 문자열(예: '45,000원', '-'). ★앱에서 재계산하지 않는다.★
  final String amount;

  /// 금액 색 강조(선택). null 이면 기본 본문색.
  final Color? emphasizeColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: AppTypography.captionSecondary),
        const SizedBox(height: 4),
        Text(
          amount,
          style: AppTypography.bigNumber.copyWith(
            color: emphasizeColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
