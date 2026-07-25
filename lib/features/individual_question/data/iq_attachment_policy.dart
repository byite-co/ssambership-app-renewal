import 'dart:typed_data';

import '../../../core/scan/picked_image.dart';

/// IQ 첨부 허용 정책(세션1 §6) — 서버 버킷 계약의 '상한' 안에서만 허용한다.
///
/// staging 실측(2026-07-24, storage.buckets):
/// `individual-question-attachments` private, file_size_limit=20971520(20MB),
/// allowed_mime_types 8종 + application/json(json 은 첨삭 ink 내부용이라
/// 사용자 선택 허용에서 제외 — 서버보다 좁게는 허용, 넓게는 금지).
const int kIqAttachmentMaxBytes = 20 * 1024 * 1024; // 버킷 20971520 실측

const Set<String> kIqAttachmentAllowedMimeTypes = <String>{
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/gif',
  'application/pdf',
  'application/zip',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
};

const String kIqAttachmentRestrictionText =
    '이미지(PNG·JPG·WebP·GIF)·PDF·ZIP·DOCX·PPTX, 20MB 이하만 첨부할 수 있어요.';

/// 매직 바이트 스니핑 — 파일명·클라이언트 주장 MIME 만으로 신뢰하지 않는다.
/// 반환: 감지된 대표 MIME(모르면 null).
String? sniffIqAttachmentMime(Uint8List bytes) {
  if (bytes.length < 4) return null;
  // PNG
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E) {
    return 'image/png';
  }
  // JPEG
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  // GIF87a/89a
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return 'image/gif';
  }
  // WebP: RIFF....WEBP
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  // PDF: %PDF
  if (bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46) {
    return 'application/pdf';
  }
  // ZIP 계열(zip/docx/pptx): PK\x03\x04
  if (bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04) {
    return 'application/zip';
  }
  return null;
}

/// zip 컨테이너(docx/pptx 포함) 여부.
bool _isZipFamily(String mime) =>
    mime == 'application/zip' ||
    mime ==
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
    mime ==
        'application/vnd.openxmlformats-officedocument.presentationml.presentation';

/// 검증 실패 사유(한글) 또는 null(통과).
/// - 서버 버킷 허용 MIME·20MB 상한 밖은 업로드 자체를 시작하지 않는다.
/// - 주장 MIME 과 매직 바이트가 모순이면 거부(파일명 신뢰 금지).
String? validateIqAttachmentFile(PickedImage file) {
  if (file.bytes.isEmpty) return '빈 파일은 첨부할 수 없어요.';
  if (file.bytes.length > kIqAttachmentMaxBytes) {
    return '파일이 너무 커요. 20MB 이하만 첨부할 수 있어요.';
  }
  final String claimed = file.mimeType;
  if (!kIqAttachmentAllowedMimeTypes.contains(claimed)) {
    return kIqAttachmentRestrictionText;
  }
  final String? sniffed = sniffIqAttachmentMime(file.bytes);
  if (sniffed == null) return kIqAttachmentRestrictionText;
  final bool consistent =
      _isZipFamily(claimed) ? sniffed == 'application/zip' : sniffed == claimed;
  if (!consistent) {
    return '파일 형식이 내용과 달라요. 원본 파일로 다시 시도해 주세요.';
  }
  return null;
}
