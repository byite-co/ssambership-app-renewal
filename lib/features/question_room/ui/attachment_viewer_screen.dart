import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../design/tokens/app_typography.dart';
import '../../scan_annotation/scan_annotation_screen.dart';
import '../data/attachments/attachment_url_resolver.dart';
import '../data/models/question_attachment.dart';
import '../../../shared/errors/friendly_error.dart';

/// 첨부 이미지 전체화면 뷰어 — 서명 URL 로 원본을 보여주고(InteractiveViewer 줌·팬),
/// '주석 달기'로 S15 주석 화면에 진입한다.
///
/// ★ 재사용: 주석은 [ScanAnnotationScreen] 을 그대로 호출한다(재구현 금지). 완료
///   흐름(평탄화 PNG 새 첨부 전송)도 S15 그대로다. 주석이 전송되면 true 로 닫혀,
///   호출부(채팅)가 첨부 목록을 새로고침한다.
class AttachmentViewerScreen extends StatefulWidget {
  const AttachmentViewerScreen({
    super.key,
    required this.attachment,
    required this.roomId,
    required this.threadId,
    required this.resolver,
  });

  final QuestionAttachment attachment;
  final String roomId;
  final String threadId;
  final AttachmentUrlResolver resolver;

  @override
  State<AttachmentViewerScreen> createState() => _AttachmentViewerScreenState();
}

class _AttachmentViewerScreenState extends State<AttachmentViewerScreen> {
  late final Future<String> _url;
  bool _preparing = false;

  @override
  void initState() {
    super.initState();
    _url = widget.resolver.signedUrl(widget.attachment.storagePath);
  }

  /// '주석 달기' — 원본 bytes 를 내려받아 S15 주석 화면으로 진입.
  Future<void> _annotate() async {
    setState(() => _preparing = true);
    try {
      final Uint8List bytes =
          await widget.resolver.download(widget.attachment.storagePath);
      if (!mounted) return;
      final bool? sent = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (BuildContext context) => ScanAnnotationScreen(
            background: bytes,
            roomId: widget.roomId,
            threadId: widget.threadId,
          ),
        ),
      );
      if (!mounted) return;
      setState(() => _preparing = false);
      if (sent == true) Navigator.of(context).pop(true); // 채팅이 새로고침하도록.
    } catch (e) {
      if (!mounted) return;
      setState(() => _preparing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이미지를 불러오지 못했어요. ${friendlyError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 전체화면 이미지 뷰어 — 사진이 주인공이라 유리 배경 대신 검정 바탕.
    // 앱바도 같은 검정 위 흰 글자(v3 §0 예외: 미디어 뷰어).
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        titleTextStyle: AppTypography.section.copyWith(color: Colors.white),
        title: const Text('이미지'),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _preparing ? null : _annotate,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: _preparing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.draw_rounded, color: Colors.white),
            label: const Text('주석 달기'),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: FutureBuilder<String>(
            future: _url,
            builder: (BuildContext context, AsyncSnapshot<String> snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const CircularProgressIndicator();
              }
              final String? url = snap.data;
              if (snap.hasError || url == null) {
                return const _ViewerError();
              }
              return Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (BuildContext c, Widget child,
                        ImageChunkEvent? progress) =>
                    progress == null
                        ? child
                        : const CircularProgressIndicator(),
                errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                    const _ViewerError(),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ViewerError extends StatelessWidget {
  const _ViewerError();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '이미지를 불러오지 못했어요.',
          style: TextStyle(color: Colors.white70),
        ),
      );
}
