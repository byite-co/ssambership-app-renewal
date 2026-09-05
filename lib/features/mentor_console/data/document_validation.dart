import 'dart:typed_data';

import '../../../core/scan/picked_image.dart';

/// 학력 인증·학적 변경 서류 검증 — 웹 `uploadMagicBytes.ts`·`studentIdImageStorage.ts`
/// 규칙 미러: JPG/PNG/PDF · 최대 20MB · 매직바이트가 확장자와 일치.
///
/// 버킷 `student-id-images` 는 `file_size_limit`·`allowed_mime_types` 가 없어
/// 서버가 크기·형식을 막지 않는다 — 앱이 웹 서버 액션 자리를 대신한다.
const int kMentorDocumentMaxBytes = 20 * 1024 * 1024;
const String kMentorDocumentMaxBytesLabel = '20MB';

enum MentorDocumentKind { jpg, png, pdf }

class VerifiedMentorDocument {
  const VerifiedMentorDocument({
    required this.bytes,
    required this.kind,
  });

  final Uint8List bytes;
  final MentorDocumentKind kind;

  String get extension {
    switch (kind) {
      case MentorDocumentKind.jpg:
        return 'jpg';
      case MentorDocumentKind.png:
        return 'png';
      case MentorDocumentKind.pdf:
        return 'pdf';
    }
  }

  String get mimeType {
    switch (kind) {
      case MentorDocumentKind.jpg:
        return 'image/jpeg';
      case MentorDocumentKind.png:
        return 'image/png';
      case MentorDocumentKind.pdf:
        return 'application/pdf';
    }
  }
}

/// 검증 실패 사유(한글). 통과하면 null.
String? mentorDocumentProblem(PickedImage picked) {
  if (picked.sizeBytes <= 0) return '서류 파일을 선택해 주세요.';
  if (picked.sizeBytes > kMentorDocumentMaxBytes) {
    return '서류는 최대 $kMentorDocumentMaxBytesLabel까지 올릴 수 있어요.';
  }
  if (detectMentorDocumentKind(picked.bytes) == null) {
    return 'JPG, PNG, PDF 형식의 서류만 올릴 수 있어요.';
  }
  return null;
}

/// 매직바이트로 형식 판별(확장자·MIME 신뢰하지 않음). 모르면 null.
MentorDocumentKind? detectMentorDocumentKind(Uint8List bytes) {
  bool starts(List<int> sig) {
    if (bytes.length < sig.length) return false;
    for (int i = 0; i < sig.length; i++) {
      if (bytes[i] != sig[i]) return false;
    }
    return true;
  }

  if (starts(const <int>[0xFF, 0xD8, 0xFF])) return MentorDocumentKind.jpg;
  if (starts(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return MentorDocumentKind.png;
  }
  if (starts(const <int>[0x25, 0x50, 0x44, 0x46, 0x2D])) {
    return MentorDocumentKind.pdf;
  }
  return null;
}

/// 검증 통과 서류. 실패면 [ArgumentError] 대신 null(호출부가 [mentorDocumentProblem]
/// 문구를 먼저 보여준다).
VerifiedMentorDocument? verifyMentorDocument(PickedImage picked) {
  if (mentorDocumentProblem(picked) != null) return null;
  final MentorDocumentKind kind = detectMentorDocumentKind(picked.bytes)!;
  return VerifiedMentorDocument(bytes: picked.bytes, kind: kind);
}
