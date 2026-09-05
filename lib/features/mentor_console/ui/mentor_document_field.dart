import 'package:flutter/material.dart';

import '../../../core/scan/picked_image.dart';
import '../../../core/scan/scan_source_picker.dart';
import '../../../design/role_theme.dart';
import '../../../design/tokens/app_colors.dart';
import '../../../design/tokens/app_spacing.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/glass_inner.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/widgets/v3_page.dart';
import '../data/document_validation.dart';

/// 학력 인증·학적 변경 공용 서류 선택 — 소스 시트(촬영/갤러리/파일) → 매직바이트
/// 검증 → 파일명·크기 표시. PDF 는 래스터화하지 않고 원본 그대로 올린다(웹 동일).
///
/// 검증 실패 문구는 [problem] 로 즉시 아래에 나온다(토스트 아님).
class MentorDocumentField extends StatelessWidget {
  const MentorDocumentField({
    super.key,
    required this.picked,
    required this.onPick,
    required this.onClear,
    this.enabled = true,
    this.problem,
  });

  final PickedImage? picked;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final bool enabled;

  /// 검증 실패 사유(null 이면 통과 또는 미선택).
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    final PickedImage? file = picked;
    return V3Field(
      label: '증명 서류',
      help: file == null ? 'JPG, PNG, PDF · 최대 $kMentorDocumentMaxBytesLabel' : null,
      error: problem,
      child: file == null
          ? InkWell(
              onTap: enabled ? onPick : null,
              borderRadius: BorderRadius.circular(AppRadius.input),
              child: GlassInner(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.upload_file_rounded,
                      color: enabled ? roleTheme.color : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '서류 선택하기',
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: enabled
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            )
          : GlassInner(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: <Widget>[
                  Icon(
                    isPdfPickedImage(file)
                        ? Icons.picture_as_pdf_rounded
                        : Icons.image_rounded,
                    color: roleTheme.color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          file.fileName,
                          style: AppTypography.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          mentorDocumentSizeLabel(file.sizeBytes),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '서류 삭제',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: enabled ? onClear : null,
                  ),
                ],
              ),
            ),
    );
  }
}

/// 크기 표시('812KB' · '3.2MB').
String mentorDocumentSizeLabel(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
  return '${(bytes / 1024).ceil()}KB';
}

/// 서류 소스 시트 — 촬영 / 갤러리 / 파일. 선택하면 [ScanSourcePort.pick] 결과를
/// 돌려주고, 취소면 null. 선택 실패(AppError)는 스낵바로 알린다.
///
/// [title]·[includeFile] 로 프로필 사진(촬영/갤러리만) 같은 변형에도 쓴다.
Future<PickedImage?> pickMentorDocument(
  BuildContext context,
  ScanSourcePort port, {
  String title = '서류 올리기',
  bool includeFile = true,
}) async {
  final ScanSource? source = await showV3BottomSheet<ScanSource>(
    context,
    builder: (BuildContext sheet) =>
        _DocumentSourceSheet(title: title, includeFile: includeFile),
  );
  if (source == null || !context.mounted) return null;
  try {
    return await port.pick(source);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
    return null;
  }
}

class _DocumentSourceSheet extends StatelessWidget {
  const _DocumentSourceSheet({required this.title, required this.includeFile});

  final String title;
  final bool includeFile;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Text(title, style: AppTypography.section),
        ),
        const _SourceRow(
          icon: Icons.photo_camera_rounded,
          label: '촬영',
          caption: '카메라로 찍어요',
          source: ScanSource.camera,
        ),
        const _SourceRow(
          icon: Icons.photo_library_rounded,
          label: '갤러리',
          caption: '저장된 사진에서 골라요',
          source: ScanSource.gallery,
        ),
        if (includeFile)
          const _SourceRow(
            icon: Icons.folder_rounded,
            label: '파일',
            caption: 'JPG · PNG · PDF',
            source: ScanSource.file,
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.icon,
    required this.label,
    required this.caption,
    required this.source,
  });

  final IconData icon;
  final String label;
  final String caption;
  final ScanSource source;

  @override
  Widget build(BuildContext context) {
    return V3EntryRow(
      icon: icon,
      label: label,
      caption: caption,
      onTap: () => Navigator.of(context).pop(source),
    );
  }
}
