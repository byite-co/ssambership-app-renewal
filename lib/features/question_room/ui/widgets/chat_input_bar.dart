import 'package:flutter/material.dart';

import '../../../../design/role_theme.dart';
import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/glass_inner.dart';
import '../../../../design/widgets/glass_surface.dart';
import '../../data/attachments/attachment_upload.dart';
import 'pen_hint_once.dart';

/// 채팅 입력 바(학생·멘토 공용) — 하단 고정 유리 바(design-v3 §2-1 '답변을 입력하세요').
/// 첨부 버튼 → 이미지 선택 → 미리보기 → 전송.
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
      return GlassSurface.bar(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Text(
              notice,
              textAlign: TextAlign.center,
              style: AppTypography.captionSecondary,
            ),
          ),
        ),
      );
    }
    final bool active = !sending && enabled;
    final Color roleColor = RoleTheme.of(context).color;
    return GlassSurface.bar(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (pendingImage != null)
                _AttachmentPreview(
                  image: pendingImage!,
                  onRemove: onRemovePending,
                  onAnnotate: onAnnotate,
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  IconButton(
                    icon: Icon(
                      Icons.attach_file,
                      color: active
                          ? AppColors.textSecondary
                          : AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                    tooltip: '사진 첨부',
                    onPressed: active ? onAttach : null,
                  ),
                  Expanded(
                    child: GlassInner(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 2,
                      ),
                      fillColor: AppColors.inputFill,
                      child: TextField(
                        controller: controller,
                        enabled: enabled,
                        style: AppTypography.body.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        cursorColor: roleColor,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSend(),
                        decoration: InputDecoration(
                          hintText: hintText,
                          hintStyle: AppTypography.body.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.send_rounded,
                      color: active
                          ? roleColor
                          : AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                    tooltip: sendTooltip,
                    onPressed: active ? onSend : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 선택 이미지 미리보기 + 업로드 제한 문구 + 제거 버튼.
///
/// design-v3 §3-3: 사진을 붙인 직후 **한 번만** 펜 안내를 띄운다(앱의 강점인데
/// 아무도 모른다). 썸네일을 탭해도 바로 주석 화면으로 간다.
class _AttachmentPreview extends StatefulWidget {
  const _AttachmentPreview(
      {required this.image, this.onRemove, this.onAnnotate});

  final PickedImage image;
  final VoidCallback? onRemove;
  final VoidCallback? onAnnotate;

  @override
  State<_AttachmentPreview> createState() => _AttachmentPreviewState();
}

class _AttachmentPreviewState extends State<_AttachmentPreview> {
  bool _showPenHint = false;

  @override
  void initState() {
    super.initState();
    if (widget.onAnnotate != null) _loadHint();
  }

  Future<void> _loadHint() async {
    final bool show = await PenHintOnce.consume();
    if (show && mounted) setState(() => _showPenHint = true);
  }

  @override
  Widget build(BuildContext context) {
    final Color roleColor = RoleTheme.of(context).color;
    final VoidCallback? onAnnotate = widget.onAnnotate;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 8, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GestureDetector(
                onTap: onAnnotate,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    widget.image.bytes,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 44,
                      height: 44,
                      color: AppColors.navy.withValues(alpha: 0.07),
                      child: const Icon(
                        Icons.image_outlined,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.image.fileName,
                  style: AppTypography.captionSecondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onAnnotate != null)
                IconButton(
                  icon: Icon(
                    Icons.draw_rounded,
                    size: 18,
                    color: roleColor,
                  ),
                  tooltip: '주석 달기',
                  onPressed: onAnnotate,
                ),
              IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                tooltip: '첨부 제거',
                onPressed: widget.onRemove,
              ),
            ],
          ),
          if (_showPenHint) ...<Widget>[
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Icon(Icons.draw_rounded, size: 14, color: roleColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '펜으로 막힌 곳을 표시해 보세요 · 사진을 탭하면 바로 그릴 수 있어요',
                    style: AppTypography.meta.copyWith(color: roleColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          const Text(kAttachmentRestrictionText, style: AppTypography.meta),
        ],
      ),
    );
  }
}
