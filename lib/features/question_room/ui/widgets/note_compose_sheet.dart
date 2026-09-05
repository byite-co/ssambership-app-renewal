import 'package:flutter/material.dart';

import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_spacing.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/app_input_field.dart';
import '../../../../design/widgets/app_primary_button.dart';
import '../../../../design/widgets/app_blocks.dart';
import '../../data/mentor_note_format.dart';

/// 멘토 노트 작성 시트(A-5 §2-2) — 답변 전송 직후 화면 이동 없이 올라온다.
/// 빈 칸 대신 두 질문을 던지고, '나중에'를 반드시 둔다. 저장하면 규약 본문을
/// 돌려주고(호출 화면이 INSERT), 나중에·닫기는 null.
Future<String?> showNoteComposeSheet(
  BuildContext context, {
  required String studentName,
  String title = '답변을 보냈어요',
}) {
  return showAppBottomSheet<String>(
    context,
    builder: (BuildContext sheet) =>
        _NoteComposeSheet(studentName: studentName, title: title),
  );
}

class _NoteComposeSheet extends StatefulWidget {
  const _NoteComposeSheet({required this.studentName, required this.title});

  final String studentName;
  final String title;

  @override
  State<_NoteComposeSheet> createState() => _NoteComposeSheetState();
}

class _NoteComposeSheetState extends State<_NoteComposeSheet> {
  final TextEditingController _weakness = TextEditingController();
  final TextEditingController _next = TextEditingController();

  @override
  void dispose() {
    _weakness.dispose();
    _next.dispose();
    super.dispose();
  }

  String? get _body =>
      composeMentorNote(weakness: _weakness.text, next: _next.text);

  @override
  Widget build(BuildContext context) {
    final EdgeInsets viewInsets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.title, style: AppTypography.section),
          const SizedBox(height: 4),
          Text(
            '${widget.studentName} 학생 노트에 한 줄 남길까요?',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.base),
          AppField(
            label: '오늘 무엇이 약했나요?',
            child: AppInputField(
              controller: _weakness,
              hintText: '예: 분모 조건을 확인하지 않고 대입해요',
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 12),
          AppField(
            label: '다음에 어떤 유형을 풀면 좋을까요?',
            child: AppInputField(
              controller: _next,
              hintText: '예: 좌·우극한이 다른 그래프 문제',
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          AppPrimaryButton(
            label: '저장하기',
            onPressed: _body == null
                ? null
                : () => Navigator.of(context).pop<String>(_body),
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop<String>(null),
              child: const Text('나중에'),
            ),
          ),
        ],
      ),
    );
  }
}
