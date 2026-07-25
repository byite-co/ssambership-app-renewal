import '../../../core/scan/picked_image.dart';
import '../../../shared/errors/app_error.dart';
import 'iq_attachment_policy.dart';
import 'models/individual_question_models.dart';

/// IQ 첨부 업로드 오케스트레이션(세션1 §6) — 순수 코어(의존 전부 주입).
///
/// 순서: 정책 검증 → (재시도가 아니면) Storage 업로드 → RPC 행 등록.
/// - 검증 실패: 업로드 0·등록 0.
/// - 업로드 실패: 등록 0(그대로 throw).
/// - 등록(RPC) 실패: **보상삭제** 시도. 삭제 성공이면 처음부터 재시도 가능,
///   삭제 실패면 고아 객체 경로를 재시도용으로 보존해(중복 객체 방지)
///   같은 경로로 '등록만' 재시도하게 한다. 어느 쪽도 성공으로 표시하지 않는다.
///   ★ staging 실측: IQA 버킷엔 owner 미등록 객체 DELETE 정책이 없어(QRA 의
///   qra_storage_delete_unregistered_owner 부재) 보상삭제가 RLS 로 거부될 수
///   있다 — 그 경우가 정확히 orphaned=true 경로다(서버 게이트로 보고).

typedef IqBinaryUploader = Future<void> Function(
    String objectPath, PickedImage file);

/// 반환 = 등록된 행 id.
typedef IqAttachmentRegistrar = Future<String> Function(
    String objectPath, PickedImage file, String? messageId);

typedef IqObjectRemover = Future<void> Function(String objectPath);

/// 등록 단계 실패(업로드는 성공) — 재시도 정보 포함.
class IqAttachmentRegisterFailure implements Exception {
  const IqAttachmentRegisterFailure({
    required this.message,
    required this.orphaned,
    this.retryObjectPath,
  });

  /// 사용자용 한글 메시지(경로·토큰·URL 미포함).
  final String message;

  /// 보상삭제까지 실패해 미정리 객체가 남았는가.
  final bool orphaned;

  /// orphaned=true 일 때 같은 경로로 등록만 재시도(재업로드·중복 객체 0).
  final String? retryObjectPath;

  @override
  String toString() => message;
}

Future<IqAttachment> uploadIqAttachmentCore({
  required String questionId,
  required PickedImage file,
  String? messageId,

  /// 재시도용: 이전 시도에서 업로드까지 성공한 경로(재업로드 생략).
  String? existingObjectPath,
  required String Function() buildPath,
  required IqBinaryUploader uploadBinary,
  required IqAttachmentRegistrar register,
  required IqObjectRemover removeObject,
}) async {
  final String? invalid = validateIqAttachmentFile(file);
  if (invalid != null) throw AppError(invalid); // 업로드 0·등록 0

  final String objectPath = existingObjectPath ?? buildPath();
  if (existingObjectPath == null) {
    await uploadBinary(objectPath, file); // 실패 → 등록 0(그대로 전파)
  }

  final String id;
  try {
    id = await register(objectPath, file, messageId);
  } catch (_) {
    bool orphaned = false;
    try {
      await removeObject(objectPath); // 보상삭제
    } catch (_) {
      orphaned = true; // 삭제도 실패 — 성공 표시 금지, 경로 보존.
    }
    throw IqAttachmentRegisterFailure(
      message: orphaned
          ? '첨부 등록이 완료되지 않았어요. 다시 시도해 주세요. (미정리 파일 1건: ${file.fileName})'
          : '첨부 등록에 실패했어요. 다시 시도해 주세요.',
      orphaned: orphaned,
      retryObjectPath: orphaned ? objectPath : null,
    );
  }

  return IqAttachment(
    id: id,
    storagePath: objectPath,
    messageId: messageId,
    fileName: file.fileName,
    mimeType: file.mimeType,
  );
}
