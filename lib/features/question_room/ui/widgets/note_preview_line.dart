import 'package:flutter/material.dart';

import '../../../../design/role_theme.dart';
import '../../../../design/tokens/app_typography.dart';

/// 목록 행 안의 최근 노트 한 줄(design-v3 §3-1·§4-1 '📌 …') — 역할 틴트 위 역할색 글자.
/// 노트가 목록에서 먼저 보이게 한다. 본문 요약은 호출부가 [MentorNoteParts] 로 만든다.
class NotePreviewLine extends StatelessWidget {
  const NotePreviewLine({super.key, required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: roleTheme.tint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.push_pin_rounded, size: 14, color: roleTheme.color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              summary,
              style: AppTypography.caption.copyWith(color: roleTheme.color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
