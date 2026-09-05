import 'package:flutter/material.dart';

import '../../design/tokens/app_colors.dart';
import '../../design/tokens/app_typography.dart';
import '../../design/widgets/glass_inner.dart';

/// 커머스 제로 안내 카드 — 결제 유도(구독하기·충전하기) 버튼을 대체하는 '비상호작용' 카드.
///
/// ★ 클릭 동작 없음(정보 표시만). 유리 안쪽 채움 + 안내 아이콘 + 문장. 버튼처럼
///   눌리는 느낌을 배제한다(design-v3 §3-5 "충전은 웹에서 할 수 있어요" 톤).
class CommerceNoticeCard extends StatelessWidget {
  const CommerceNoticeCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return GlassInner(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppTypography.captionSecondary)),
        ],
      ),
    );
  }
}
