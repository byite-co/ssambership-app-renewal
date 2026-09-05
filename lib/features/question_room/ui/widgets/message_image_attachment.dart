import 'package:flutter/material.dart';

import '../../../../design/tokens/app_colors.dart';
import '../../data/attachments/attachment_url_resolver.dart';
import '../../data/models/question_attachment.dart';

/// 채팅 말풍선 안/옆의 이미지 첨부 썸네일. 탭 시 [onOpen](전체화면 뷰어).
///
/// 서명 URL 을 [resolver] 로 발급(만료 전 캐시 재사용)해 표시하고, 로딩·실패는
/// 플레이스홀더로 대체한다(깨진 이미지·크래시 방지). 말풍선 안에 인라인으로
/// 들어가므로 모서리 10(design-v3 §3-2 '문제 사진').
class MessageImageAttachment extends StatefulWidget {
  const MessageImageAttachment({
    super.key,
    required this.attachment,
    required this.resolver,
    required this.onOpen,
    this.size = 180,
  });

  final QuestionAttachment attachment;
  final AttachmentUrlResolver resolver;
  final VoidCallback onOpen;
  final double size;

  @override
  State<MessageImageAttachment> createState() => _MessageImageAttachmentState();
}

class _MessageImageAttachmentState extends State<MessageImageAttachment> {
  late Future<String> _url;

  @override
  void initState() {
    super.initState();
    _url = widget.resolver.signedUrl(widget.attachment.storagePath);
  }

  @override
  void didUpdateWidget(MessageImageAttachment old) {
    super.didUpdateWidget(old);
    if (old.attachment.storagePath != widget.attachment.storagePath) {
      _url = widget.resolver.signedUrl(widget.attachment.storagePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onOpen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: FutureBuilder<String>(
            future: _url,
            builder: (BuildContext context, AsyncSnapshot<String> snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const _ThumbBox(child: _Spinner());
              }
              final String? url = snap.data;
              if (snap.hasError || url == null) {
                return const _ThumbBox(child: _BrokenIcon());
              }
              return Image.network(
                url,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
                loadingBuilder: (BuildContext c, Widget child,
                    ImageChunkEvent? progress) {
                  if (progress == null) return child;
                  return const _ThumbBox(child: _Spinner());
                },
                errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                    const _ThumbBox(child: _BrokenIcon()),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ThumbBox extends StatelessWidget {
  const _ThumbBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy.withValues(alpha: 0.07),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}

class _BrokenIcon extends StatelessWidget {
  const _BrokenIcon();
  @override
  Widget build(BuildContext context) => const Icon(
        Icons.broken_image_outlined,
        color: AppColors.textSecondary,
        size: 28,
      );
}
