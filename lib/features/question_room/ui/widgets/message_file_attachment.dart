import 'package:flutter/material.dart';

import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/glass_inner.dart';
import '../../data/models/question_attachment.dart';

/// 말풍선 안/독립 행의 파일(비이미지) 첨부 칩. 탭 시 [onOpen](서명 URL 열기).
///
/// 첨부 v2 계약 §2-6: 렌더는 전 mime 대응 — 이미지는 썸네일(MessageImageAttachment),
/// 그 외(pdf·zip·docx·pptx 등, 주로 웹에서 전송)는 이 칩으로 표시한다.
class MessageFileAttachment extends StatelessWidget {
  const MessageFileAttachment({
    super.key,
    required this.attachment,
    required this.onOpen,
    this.maxWidth = 220,
  });

  final QuestionAttachment attachment;
  final VoidCallback onOpen;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final String raw = (attachment.fileName ?? '').trim();
    final String name = raw.isEmpty ? '첨부 파일' : raw;
    return GestureDetector(
      onTap: onOpen,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: GlassInner(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.insert_drive_file_outlined,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.open_in_new,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
