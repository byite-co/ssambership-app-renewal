import 'package:flutter/material.dart';

import '../../../../design/shape_tokens.dart';
import '../../../../design/spacing_tokens.dart';
import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/typography_tokens.dart';
import '../../../../design/widgets/primary_button.dart';
import '../../data/community_labels.dart';
import '../../data/community_models.dart';
import '../../data/community_post_envelope.dart';
import '../../data/community_write_repository.dart';
import '../widgets/content_policy_gate.dart';
import '../../../../shared/errors/friendly_error.dart';

/// 게시판 글 수정(F5 — `api_app_v1.community_post_update`, 본인 멘토 글 전용).
///
/// - `p_expected_updated_at` = 실제 조회한 행의 updated_at 원문(낙관적 잠금).
/// - `UPDATE_CONFLICT` 는 자동 덮어쓰기하지 않는다 — 안내 후 사용자가 최신
///   내용을 확인하고 다시 수정한다(§7.3).
/// - 이미지 ref 는 기존 값을 그대로 유지해 전달한다(수정 화면은 텍스트·카테고리만).
/// - 학생이 과거에 작성한 글의 수정은 서버가 거부한다(ROLE_NOT_MENTOR — §6.5).
class BoardEditScreen extends StatefulWidget {
  const BoardEditScreen({
    super.key,
    required this.post,
    this.write = const CommunityWriteRepository(),
  });

  final BoardPost post;
  final CommunityWriteRepository write;

  @override
  State<BoardEditScreen> createState() => _BoardEditScreenState();
}

class _BoardEditScreenState extends State<BoardEditScreen> {
  late final TextEditingController _title =
      TextEditingController(text: widget.post.title);
  late final TextEditingController _body =
      TextEditingController(text: widget.post.body ?? '');
  late String _category = widget.post.category != null &&
          communityCategoryOptions
              .any((MapEntry<String, String> e) => e.key == widget.post.category)
      ? widget.post.category!
      : communityCategoryOptions.first.key;
  bool _submitting = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final String title = _title.text.trim();
    final String body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _snack('제목과 내용을 입력해 주세요.');
      return;
    }
    if (!await ContentPolicyGate.ensureAgreed(context)) return;
    if (!mounted) return;
    setState(() => _submitting = true);
    try {
      // 실제 조회한 updated_at 원문(NULL 포함)을 그대로 전달 — 낙관적 잠금(§7.3).
      await widget.write.updatePost(
        postId: widget.post.id,
        title: title,
        body: body,
        category: _category,
        expectedUpdatedAt: widget.post.updatedAtRaw,
        imageRefs: widget.post.imageRefs,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CommunityWriteRejected catch (e) {
      // UPDATE_CONFLICT 포함 — 자동 덮어쓰기 없이 안내만(§7.3).
      _snack(e.userMessage);
      if (mounted) setState(() => _submitting = false);
    } catch (e) {
      _snack('글 수정에 실패했어요. ${friendlyError(e)}');
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: AppType.caption,
      filled: true,
      fillColor: ColorTokens.elevated,
      border: const OutlineInputBorder(
        borderRadius: AppShape.inputRadius,
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('글 수정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH, 16, AppSpacing.screenH, 24),
        children: <Widget>[
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: _decoration('카테고리'),
            style: AppType.body,
            items: <DropdownMenuItem<String>>[
              for (final MapEntry<String, String> e in communityCategoryOptions)
                DropdownMenuItem<String>(value: e.key, child: Text(e.value)),
            ],
            onChanged: _submitting
                ? null
                : (String? v) {
                    if (v != null) setState(() => _category = v);
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            style: AppType.body,
            decoration: _decoration('제목'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            style: AppType.body,
            minLines: 8,
            maxLines: 16,
            decoration: _decoration('내용'),
          ),
          const SizedBox(height: AppSpacing.s24),
          PrimaryButton(
            label: _submitting ? '수정 중…' : '수정 완료',
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}
