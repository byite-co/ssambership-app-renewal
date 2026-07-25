import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'iq_attachments_repository.dart';

/// IQ 첨부 저장 포트(세션1 §6) — 당사자 다운로드 후 플랫폼 저장 대화상자로.
///
/// - 바이트는 RLS(iqa_storage_read_party) 경유 storage download 로 받는다
///   (signed URL 발급·보관 없음).
/// - 저장은 SAF/플랫폼 파일 선택기(FilePicker.saveFile) — 전체 저장소 권한 불요.
abstract class IqAttachmentSaverPort {
  /// true=저장됨, false=사용자 취소. 실패는 throw.
  Future<bool> save({required String storagePath, required String fileName});
}

class SafIqAttachmentSaver implements IqAttachmentSaverPort {
  const SafIqAttachmentSaver(
      {SupabaseIqAttachmentsRepository repository =
          const SupabaseIqAttachmentsRepository()})
      : _repository = repository;

  final SupabaseIqAttachmentsRepository _repository;

  @override
  Future<bool> save(
      {required String storagePath, required String fileName}) async {
    final List<int> bytes = await _repository.downloadBytes(storagePath);
    // file_picker 11.x: 정적 FilePicker.saveFile(SAF/플랫폼 저장 대화상자).
    final String? out = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
    );
    return out != null;
  }
}
