import '../../../core/scan/picked_image.dart';
import '../../../shared/errors/app_error.dart';
import 'iq_attachment_policy.dart';
import 'models/individual_question_models.dart';

/// IQ 첨부 업로드 오케스트레이션(세션1 §6 + 세션1.5 보정1) — 순수 코어.
///
/// 절대 원칙(v18): `add_individual_question_attachment` 에는 멱등 계약이 없다
/// (멱등키 인자 없음·plain INSERT·ON CONFLICT 없음·PK 외 UNIQUE 없음 — 실측).
/// 따라서 **모호 결과에서 등록 RPC 를 재호출하지 않는다**. 등록 여부의 정본은
/// 당사자 SELECT(iqa_select_party) 다.
///
/// 결과 분기:
/// - 명시적 등록 실패(서버가 거부 응답 = 미등록 확정): 보상삭제 시도.
/// - 모호 결과(timeout·연결 끊김·응답 파싱 실패): RPC 재호출 0 → 동일
///   question_id+storage_path SELECT →
///   · 행 확인 → 그 DB 행을 정본으로 성공 수렴(보상삭제 0)
///   · SELECT 정상·0건 → 미등록 확정 — 그때만 보상삭제 시도
///   · SELECT 실패 → AMBIGUOUS_SERVER_RESULT(자동삭제 0·성공 표시 0)
/// - 수동 재시도(existingObjectPath): 등록 RPC 보다 **SELECT 를 선행** — 행이
///   확인되면 RPC 0회로 성공 수렴, 미등록 확정일 때만 등록 RPC 허용.
///
/// ★ "DELETE 가 이미 등록된 객체라 거부되면 성공 수렴" 분기는 현재 계약이
///   아니다 — NOT EXISTS(등록 행) 조건부 DELETE 정책(후속 SQL) 도입 뒤에만
///   성립할 미래 분기이며, 현재 코드·테스트는 이를 전제하지 않는다.
///   (현재 IQA 버킷 Storage DELETE 정책 0건 — 보상삭제는 거부될 수 있고,
///   그 경우가 orphaned=true 다.)

typedef IqBinaryUploader = Future<void> Function(
    String objectPath, PickedImage file);

/// 반환 = 등록된 행 id.
typedef IqAttachmentRegistrar = Future<String> Function(
    String objectPath, PickedImage file, String? messageId);

typedef IqObjectRemover = Future<void> Function(String objectPath);

/// 당사자 SELECT 정본 확인 — 행 없으면 null, SELECT 자체 실패는 throw.
typedef IqRegisteredFinder = Future<IqAttachment?> Function(String objectPath);

/// true = 서버가 명시적으로 거부(INSERT 미수행 확정). false = 모호(전송·응답
/// 계층 실패 — 서버 성공 여부 미상).
typedef IqDefiniteFailureClassifier = bool Function(Object error);

/// 등록 단계 '확정' 실패(미등록 정본 확인 후) — 재시도 정보 포함.
class IqAttachmentRegisterFailure implements Exception {
  const IqAttachmentRegisterFailure({
    required this.message,
    required this.orphaned,
    this.retryObjectPath,
  });

  /// 사용자용 한글 메시지(경로·토큰·URL 미포함).
  final String message;

  /// 보상삭제까지 실패해 미정리 객체가 남았는가(orphan cleanup 필요 상태).
  final bool orphaned;

  /// orphaned=true 일 때 같은 경로로 재시도(재업로드·중복 객체 0).
  final String? retryObjectPath;

  @override
  String toString() => message;
}

/// AMBIGUOUS_SERVER_RESULT — 등록 여부를 확정할 수 없는 상태.
/// 자동삭제 0회·성공 표시 0회·로컬 임시 성공 삽입 0회. 수동 재시도는
/// retryObjectPath 로 SELECT 선행 수렴을 다시 밟는다.
class IqAttachmentAmbiguousResult implements Exception {
  const IqAttachmentAmbiguousResult({required this.retryObjectPath});

  final String retryObjectPath;

  String get message => '첨부 등록 여부를 확인하지 못했어요. 네트워크 확인 후 다시 시도해 주세요.';

  @override
  String toString() => message;
}

Future<IqAttachment> uploadIqAttachmentCore({
  required String questionId,
  required PickedImage file,
  String? messageId,

  /// 재시도용: 이전 시도에서 업로드까지 성공한 경로(재업로드 생략 + SELECT 선행).
  String? existingObjectPath,
  required String Function() buildPath,
  required IqBinaryUploader uploadBinary,
  required IqAttachmentRegistrar register,
  required IqObjectRemover removeObject,
  required IqRegisteredFinder findRegistered,
  required IqDefiniteFailureClassifier isDefiniteRegisterFailure,
}) async {
  final String? invalid = validateIqAttachmentFile(file);
  if (invalid != null) throw AppError(invalid); // 업로드 0·등록 0

  final String objectPath;
  if (existingObjectPath != null) {
    objectPath = existingObjectPath;
    // 수동 재시도: 등록 RPC 전에 SELECT 정본 확인을 선행한다(v18 보정1).
    final IqAttachment? already;
    try {
      already = await findRegistered(objectPath);
    } catch (_) {
      // 확인 불가 — RPC 를 호출하면 중복 행 위험. AMBIGUOUS 유지.
      throw IqAttachmentAmbiguousResult(retryObjectPath: objectPath);
    }
    if (already != null) return already; // RPC 0회 — DB 행이 등록 정본.
    // SELECT 정상·0건 = 미등록 확정 → 아래에서 등록 RPC 허용(재업로드는 생략).
  } else {
    objectPath = buildPath();
    await uploadBinary(objectPath, file); // 실패 → 등록 0(그대로 전파)
  }

  final String id;
  try {
    id = await register(objectPath, file, messageId);
  } catch (e) {
    if (!isDefiniteRegisterFailure(e)) {
      // 모호 결과 — RPC 재호출 금지. SELECT 로 정본 확인.
      final IqAttachment? registered;
      try {
        registered = await findRegistered(objectPath);
      } catch (_) {
        // 등록 여부 미확정 → AMBIGUOUS(자동삭제 0·성공 0).
        throw IqAttachmentAmbiguousResult(retryObjectPath: objectPath);
      }
      if (registered != null) {
        return registered; // 서버 INSERT 는 성공했었다 — DB 행이 정본.
      }
      // SELECT 정상·0건 → 미등록 확정. 아래 보상삭제 경로로 합류.
    }
    // 미등록 확정(명시 거부 또는 SELECT 0건 확인) 시에만 보상삭제.
    bool orphaned = false;
    try {
      await removeObject(objectPath);
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
