import 'package:flutter/material.dart';

import '../../../../design/role_accent.dart';
import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/shape_tokens.dart';
import '../../../../design/typography_tokens.dart';
import '../../data/attachments/attachment_upload.dart';

/// 채팅 입력 바(학생·멘토 공용). 첨부 버튼 → 이미지 선택 → 미리보기 → 전송.
///
/// 선택된 이미지가 있으면 입력창 위에 미리보기 + 업로드 제한 문구를 보여준다.
/// 실제 선택/업로드는 부모가 주입한 포트가 담당(테스트에서는 mock).
class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.sending,
    required this.onSend,
    required this.onAttach,
    this.sendTooltip = '전송',
    this.pendingImage,
    this.onRemovePending,
    this.onAnnotate,
    this.enabled = true,
    this.disabledNotice,
  });

  final TextEditingController controller;
  final String hintText;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  /// 전송 버튼 tooltip(멘토는 '답변 전송' 등으로 구분).
  final String sendTooltip;

  /// 선택했지만 아직 안 보낸 이미지(미리보기). null 이면 미리보기 없음.
  final PickedImage? pendingImage;
  final VoidCallback? onRemovePending;

  /// 선택 이미지에 '주석 달기'(S15). null 이면 주석 액션을 숨긴다(하위호환).
  final VoidCallback? onAnnotate;

  /// false 면 입력·첨부·전송을 모두 막는다(예: 상대를 차단한 질문방 = 읽기 전용).
  /// 기존 대화는 계속 보인다 — 이 바만 비활성화된다.
  final bool enabled;

  /// 비활성 사유 안내(입력창 자리에 표시). [enabled]=false 일 때만 쓰인다.
  final String? disabledNotice;

  @override
  Widget build(BuildContext context) {
    final String? notice = disabledNotice;
    if (!enabled && notice != null) {
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: const BoxDecoration(
            color: ColorTokens.surface,
            border: Border(top: BorderSide(color: ColorTokens.border)),
          ),
          child: Text(
            notice,
            textAlign: TextAlign.center,
            style: AppType.caption.copyWith(color: ColorTokens.muted),
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
        decoration: const BoxDecoration(
          color: ColorTokens.surface,
          border: Border(top: BorderSide(color: ColorTokens.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (pendingImage != null) _AttachmentPreview(
              image: pendingImage!,
              onRemove: onRemovePending,
              onAnnotate: onAnnotate,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.attach_file, color: ColorTokens.muted),
                  tooltip: '사진 첨부',
                  onPressed: (sending || !enabled) ? null : onAttach,
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: enabled,
                    style: AppType.body,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      hintText: hintText,
                      filled: true,
                      fillColor: ColorTokens.elevated,
                      border: OutlineInputBorder(
                        borderRadius: AppShape.inputRadius,
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.send_rounded,
                    color: (sending || !enabled)
                        ? ColorTokens.muted
                        : AppAccent.of(context).accent,
                  ),
                  tooltip: sendTooltip,
                  onPressed: (sending || !enabled) ? null : onSend,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 선택 이미지 미리보기 + 업로드 제한 문구 + 제거 버튼.
class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.image, this.onRemove, this.onAnnotate});

  final PickedImage image;
  final VoidCallback? onRemove;
  final VoidCallback? onAnnotate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  image.bytes,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 44,
                    height: 44,
                    color: ColorTokens.elevated,
                    child: const Icon(Icons.image_outlined,
                        size: 20, color: ColorTokens.muted),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  image.fileName,
                  style: AppType.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onAnnotate != null)
                IconButton(
                  icon: Icon(Icons.draw_rounded,
                      size: 18, color: AppAccent.of(context).accent),
                  tooltip: '주석 달기',
                  onPressed: onAnnotate,
                ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: ColorTokens.muted),
                tooltip: '첨부 제거',
                onPressed: onRemove,
              ),
            ],
          ),
          const Text(kAttachmentRestrictionText, style: AppType.caption),
        ],
      ),
    );
  }
}
