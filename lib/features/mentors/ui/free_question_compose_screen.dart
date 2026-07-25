import 'package:flutter/material.dart';

import '../../../design/shape_tokens.dart';
import '../../../design/spacing_tokens.dart';
import '../../../design/tokens/color_tokens.dart';
import '../../../design/typography_tokens.dart';
import '../../../design/widgets/primary_button.dart';
import '../../../shared/errors/friendly_error.dart';
import '../data/free_question_entry.dart';

/// 무료 질문 작성(세션1 §3) — 무료 전용 RPC 1회 호출.
///
/// 캐시 차감형 개별질문(IqCreateScreen)과 handler·RPC·상태를 공유하지 않는다.
/// 결제·충전·구독 문구/이동 없음. 성공 시 서버 정본 결과(CreatedFreeQuestion)를
/// pop 으로 돌려주고, 이동은 호출부(멘토 상세)가 기존 질문방 이동 계약으로 수행.
class FreeQuestionComposeScreen extends StatefulWidget {
  const FreeQuestionComposeScreen({
    super.key,
    required this.roomId,
    required this.mentorName,
    required this.port,
  });

  final String roomId;
  final String mentorName;
  final FreeQuestionEntryPort port;

  @override
  State<FreeQuestionComposeScreen> createState() =>
      _FreeQuestionComposeScreenState();
}

class _FreeQuestionComposeScreenState extends State<FreeQuestionComposeScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return; // 연타 in-flight guard — 생성 RPC 최대 1회.
    final String body = _body.text.trim();
    if (body.isEmpty) {
      _snack('질문 내용을 입력해 주세요.');
      return;
    }
    final String titleInput = _title.text.trim();
    setState(() => _busy = true);
    try {
      final CreatedFreeQuestion created = await widget.port.createFreeThread(
        roomId: widget.roomId,
        // 서버가 제목을 요구(TITLE_REQUIRED) — 미입력이면 중립 기본 제목.
        title: titleInput.isEmpty ? '무료 질문' : titleInput,
        firstMessageBody: body,
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      _snack('무료 질문 등록에 실패했어요. ${friendlyError(e)}');
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: ColorTokens.elevated,
      border: const OutlineInputBorder(
        borderRadius: AppShape.inputRadius,
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const _FreeQuestionAppBar(),
      body: ListView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenH, vertical: AppSpacing.s16),
        children: <Widget>[
          Text('${widget.mentorName} 멘토에게 보내는 무료 질문이에요.',
              style: AppType.caption),
          const SizedBox(height: AppSpacing.s16),
          const Text('제목 (선택)', style: AppType.caption),
          const SizedBox(height: AppSpacing.titleBody),
          TextField(
            controller: _title,
            style: AppType.body,
            decoration: _decoration('한 줄 제목'),
          ),
          const SizedBox(height: AppSpacing.s16),
          const Text('질문 내용', style: AppType.caption),
          const SizedBox(height: AppSpacing.titleBody),
          TextField(
            controller: _body,
            style: AppType.body,
            minLines: 5,
            maxLines: 10,
            decoration: _decoration('궁금한 점을 적어주세요.'),
          ),
          const SizedBox(height: AppSpacing.s24),
          PrimaryButton(
            label: _busy ? '등록 중…' : '무료 질문 보내기',
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _FreeQuestionAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _FreeQuestionAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(title: const Text('무료 질문하기'));
}
