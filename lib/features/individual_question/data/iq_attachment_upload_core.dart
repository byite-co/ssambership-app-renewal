import '../../../core/scan/picked_image.dart';
import '../../../shared/errors/app_error.dart';
import 'iq_attachment_policy.dart';
import 'models/individual_question_models.dart';

/// IQ 첨부 업로드 오케스트레이션(세션1 §6 + 세션1.5 보정1) — 순수 코어.
///
/// 절대 원칙(v21 개정): **모호 결과에서 등록 RPC 를 재호출하지 않는다.**
/// v18 은 그 근거를 "`add_individual_question_attachment` 에는 멱등 계약이
/// 없다"에서 찾았다. SQL 168 이 그 전제를 뒤집어 멱등 계약(`on conflict
/// (question_id, storage_path) do nothing` + SELECT 폴백)을 도입했지만,
/// **원칙은 그대로 유지된다** — 근거만 바뀐다:
///   멱등 계약이 있어도 모호 결과에서는 그 회차의 응답이 없어 계약이 적용된
///   서버인지 확인할 수 없으므로 재호출하지 않는다.
/// 계약 형태([IqAttachmentRegistration.idempotentContract])는 **그 호출의
/// 응답에서만** 읽는 1회성 값이며 세션·프로세스·디스크 어디에도 저장하지
/// 않는다(capability 캐시 금지). 응답이 없으면 형태도 알 수 없다 = 재호출
/// 금지. 이것이 fail-closed 의 실제 의미다.
/// 등록 여부의 정본은 언제나 당사자 SELECT(iqa_select_party) 다.
///
/// 유일한 재호출 허용 사례는 `40001` REGISTER_CONFLICT_UNRESOLVED **1회**다
/// ([IqRegisterConflictClassifier]). 이것은 모호 결과가 아니라 응답이 도착한
/// 명시 오류이고, 그 응답이 도착했다는 사실 자체가 168 적용을 증명한다.
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
/// - 멱등 히트(`status=='existing'` 또는 `message_id_mismatch`): 168 은 기존
///   행을 UPDATE 하지 않고 성공 반환에 file_name·mime_type·message_id 를 담지
///   않는다 → 반환값만으로 화면을 맞추면 서버 정본과 갈라진다. **서버가
///   돌려준 storage_path 로 1회 재조회**해 그 행을 정본으로 삼는다.
///
/// ★ "DELETE 가 이미 등록된 객체라 거부되면 성공 수렴" 분기는 SQL 169 가
///   도입할 정책(등록 행이 있으면 Storage DELETE 거부)에 달려 있는데, 앱은
///   그 정책의 적용 여부를 알 수 없다. 따라서 **정책 존재를 가정하지 않고
///   관측으로만** 분기한다 — DELETE 가 거부되면 등록 여부를 재조회해서
///   등록돼 있을 때만 성공 수렴하고, 미등록이면 기존 orphaned=true 처리를
///   유지한다. 169 미적용(정책 0건 → 전건 거부) 상태에서도 안전하다.

typedef IqBinaryUploader = Future<void> Function(
    String objectPath, PickedImage file);

/// 반환 = 등록 결과([IqAttachmentRegistration]) — 레거시/신규 두 계약 형태를
/// 호출부(레포)가 [parseIqAttachmentRegistration] 로 흡수해 넘긴다.
typedef IqAttachmentRegistrar = Future<IqAttachmentRegistration> Function(
    String objectPath, PickedImage file, String? messageId);

typedef IqObjectRemover = Future<void> Function(String objectPath);

/// 당사자 SELECT 정본 확인 — 행 없으면 null, SELECT 자체 실패는 throw.
typedef IqRegisteredFinder = Future<IqAttachment?> Function(String objectPath);

/// true = 서버가 명시적으로 거부(INSERT 미수행 확정). false = 모호(전송·응답
/// 계층 실패 — 서버 성공 여부 미상).
typedef IqDefiniteFailureClassifier = bool Function(Object error);

/// true = `40001` REGISTER_CONFLICT_UNRESOLVED — 등록 RPC 1회 재호출 허용
/// (§4-3 의 유일한 예외). 그 외 오류에서는 언제나 false 여야 한다.
typedef IqRegisterConflictClassifier = bool Function(Object error);

/// 명시적 등록 거부의 사용자 문구 매핑(계약 7 신규 코드 — STORAGE_*·MIME_*·
/// SIZE_EXCEEDED·ACCOUNT_*). null = 미지 코드 → 기존 일반 문구 유지.
/// ★ 화면에 코드·원문을 싣지 않는다(매퍼가 한글 문구만 돌려준다).
typedef IqRegisterFailureDescriber = String? Function(Object error);

/// 등록 결과를 읽지 못했을 때의 사용자 문구(계약 형태 무관 — 변경 금지).
const String kIqRegisterResultUnreadable = '첨부 등록 결과를 확인하지 못했어요.';

/// 168 성공 반환의 `status` 값.
const String kIqRegisterStatusCreated = 'created';
const String kIqRegisterStatusExisting = 'existing';

/// 등록 RPC 1회분의 응답 — 레거시(uuid text)와 신규(jsonb) 두 계약 형태를
/// 하나로 흡수한 값 객체.
///
/// ★ [idempotentContract] 는 **그 호출의 응답에서만** 읽는 1회성 값이다.
///   세션·프로세스·디스크 어디에도 저장하지 않는다(capability 캐시 금지 —
///   모호 결과에서는 응답이 없어 언제나 '알 수 없음' = 재호출 금지).
class IqAttachmentRegistration {
  const IqAttachmentRegistration({
    required this.attachmentId,
    required this.storagePath,
    required this.idempotentContract,
    this.idempotentHit = false,
    this.status,
    this.messageIdMismatch = false,
  });

  /// 등록된 행 id(신규 계약의 `attachment_id`).
  final String attachmentId;

  /// 이후 모든 조회·정리의 **경로 정본**. 신규 계약이면 서버 정규화 경로
  /// (`storage_path`), 레거시 계약이면 앱이 만든 경로.
  final String storagePath;

  /// 이 응답이 멱등 계약(168)이었는가. 저장 금지 — 위 주석 참조.
  final bool idempotentContract;

  /// 서버가 알려준 멱등 히트 여부(`idempotent_hit`).
  final bool idempotentHit;

  /// `created` | `existing`. 레거시 계약이면 null.
  final String? status;

  /// 기존 행의 `message_id` 가 이번 요청과 다름. **실패가 아니다** — 168 은
  /// 기존 행을 UPDATE 하지 않고 보존한 정상 멱등 히트를 이렇게 알린다.
  /// 사용자에게 오류로 노출하지 않고, 로컬 상태를 서버 값에 맞춘다.
  final bool messageIdMismatch;

  /// 반환값만으로는 화면 상태를 맞출 수 없어 SELECT 재조회가 필요한가.
  ///
  /// - 레거시 계약: 항상 false(재조회 없음 — 종전 동작 그대로).
  /// - `created`: 방금 이 호출이 만든 행이므로 재조회하지 않는다(RPC 1회로 끝).
  /// - `existing`·`message_id_mismatch`: 서버 정본으로 수렴해야 한다.
  /// - 그 외(누락·미지 status): fail-closed — 서버 정본으로 수렴시킨다.
  bool get needsCanonicalRefetch =>
      idempotentContract &&
      (messageIdMismatch || status != kIqRegisterStatusCreated);
}

/// 전환기 **이중 형태 리더**(dual-shape reader) — 서버 적용 여부를 묻지 않고
/// 응답의 *형태* 로만 분기한다. 이 함수 덕분에 앱은 168 배포 시점을 몰라도
/// 안전하며, 두 세션 사이에 조정 창이 필요 없다.
///
/// - `String`  → 레거시 계약(168 미적용). 경로 정본 = 앱이 만든 경로.
/// - `Map`     → 신규 계약(168 적용). 경로 정본 = 서버 `storage_path`.
/// - 그 외/파싱 실패 → [kIqRegisterResultUnreadable] AppError(사용자 문구 불변).
///   이 오류는 PostgrestException 이 아니므로 코어의 **모호 결과** 경로를 타
///   SELECT 선행 확인으로 수렴한다(재호출 0).
///
/// ★ v22 fail-closed 강화(신규 계약 경로에만 적용): 168 은 성공 payload 에
///   `question_id`·`storage_path` 를 **항상** 채워 보낸다. 따라서
///   - `question_id` 누락·비문자·[expectedQuestionId] 불일치 → 거부.
///     (누락 자체가 계약 위반 신호다 — 응답 뒤바뀜·오라우팅을 침묵으로 덮지
///     않는다.)
///   - `storage_path` 누락·비문자·공백 → 거부. **[requestedPath] 폴백을 두지
///     않는다** — 서버 정규화 경로가 정본인데 앱 추정값을 정본으로 승격하면
///     경로 불일치가 신호 없이 묻힌다.
///   - `storage_path` 의 첫 세그먼트 ≠ [expectedQuestionId] → 거부
///     (`question_id=q-1` 인데 `storage_path=q-2/...` 인 자기모순 응답 차단).
///   [requestedPath] 와의 **완전 일치는 요구하지 않는다** — 서버가 경로를
///   정규화할 여지를 남긴다(현행 168 은 btrim 만 한다).
///   근거: 168 은 서버에서 이미 `split_part(v_path,'/',1) <> p_question_id`
///   를 강제한다. 즉 이 검사는 정상 계약을 깨지 않는 **순수 이중 방어**이고
///   정상 응답은 언제나 통과한다.
///   거부는 전부 기존 [kIqRegisterResultUnreadable] — 새 에러 코드·새 사용자
///   문구를 만들지 않는다. AppError 는 PostgrestException 이 아니므로 코어의
///   모호 결과 경로를 타 SELECT 선행 확인으로 수렴한다(자동삭제 0·재호출 0).
///
/// 레거시(String) 분기는 이 강화의 대상이 아니다 — 168 미적용 배포에는
/// `question_id` 가 애초에 없다. 이중 형태 리더의 전환기 안전성이 그 분기에
/// 걸려 있으므로 종전 동작을 그대로 둔다.
IqAttachmentRegistration parseIqAttachmentRegistration(
  Object? result, {
  required String requestedPath,
  required String expectedQuestionId,
}) {
  // 레거시 계약: 반환형이 등록 행 uuid 문자열.
  if (result is String) {
    final String id = result.trim();
    if (id.isEmpty) throw const AppError(kIqRegisterResultUnreadable);
    return IqAttachmentRegistration(
      attachmentId: id,
      storagePath: requestedPath,
      idempotentContract: false,
    );
  }
  // 신규 계약(168): jsonb. 실패는 예외로만 오므로 여기 오면 성공 반환이다.
  if (result is Map) {
    if (result['ok'] != true) {
      throw const AppError(kIqRegisterResultUnreadable);
    }
    final Object? id = result['attachment_id'];
    if (id is! String || id.trim().isEmpty) {
      throw const AppError(kIqRegisterResultUnreadable);
    }
    final String expectedId = expectedQuestionId.trim();
    // question_id: 168 이 항상 채우므로 누락도 이상 신호 — 정확 일치만 통과.
    final Object? questionId = result['question_id'];
    if (questionId is! String || questionId.trim() != expectedId) {
      throw const AppError(kIqRegisterResultUnreadable);
    }
    // storage_path: 서버 값이 유일한 정본 — requestedPath 폴백 없음.
    final Object? path = result['storage_path'];
    if (path is! String || path.trim().isEmpty) {
      throw const AppError(kIqRegisterResultUnreadable);
    }
    final String serverPath = path.trim();
    // 자기모순 차단: question_id 는 맞는데 경로가 다른 질문을 가리키는 응답.
    if (serverPath.split('/').first != expectedId) {
      throw const AppError(kIqRegisterResultUnreadable);
    }
    final Object? status = result['status'];
    return IqAttachmentRegistration(
      attachmentId: id.trim(),
      // 서버 정규화 경로가 정본(앱 경로 폴백 금지 — 위 주석 참조).
      storagePath: serverPath,
      idempotentContract: true,
      idempotentHit: result['idempotent_hit'] == true,
      status: status is String ? status.trim() : null,
      messageIdMismatch: result['message_id_mismatch'] == true,
    );
  }
  throw const AppError(kIqRegisterResultUnreadable);
}

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

/// v19 보정3: SELECT 응답 → 등록 정본 행 생성.
/// - rows 가 **실제 0건**일 때만 null(미등록 확정은 이 경우뿐).
/// - 행이 존재하는데 id 가 null·비문자·빈 문자열이거나 storage_path /
///   question_id 가 요청과 모순이면 정본 생성 불가 — throw 하고, finder 의
///   throw 는 코어에서 AMBIGUOUS_SERVER_RESULT 로 수렴한다
///   (자동삭제 0·RPC 재호출 0·성공 표시 0 — 손상 응답을 '미등록 확정'으로
///   해석해 보상삭제로 진행하지 않는다).
/// - v20 정정2: question_id 는 필수 검증 필드다 — repository projection 이
///   명시 선택하므로 **키 누락 자체가 비정상 response shape** 이며, 누락·
///   null·비문자·빈 문자열·불일치 전부 throw(정확 일치만 통과).
IqAttachment? canonicalRegisteredAttachment(
  List<dynamic> rows, {
  required String questionId,
  required String objectPath,
}) {
  if (rows.isEmpty) return null;
  final Object? first = rows.first;
  if (first is! Map) {
    throw const FormatException('IQ_ATTACHMENT_ROW_BAD_SHAPE');
  }
  final Map<dynamic, dynamic> r = first;
  final Object? id = r['id'];
  if (id is! String || id.trim().isEmpty) {
    throw const FormatException('IQ_ATTACHMENT_ROW_BAD_ID');
  }
  final Object? sp = r['storage_path'];
  if (sp is! String || sp != objectPath) {
    throw const FormatException('IQ_ATTACHMENT_ROW_PATH_MISMATCH');
  }
  final Object? q = r['question_id'];
  if (q is! String || q.trim().isEmpty || q != questionId) {
    throw const FormatException('IQ_ATTACHMENT_ROW_QUESTION_MISMATCH');
  }
  return IqAttachment(
    id: id,
    storagePath: objectPath,
    messageId: r['message_id'] is String ? r['message_id'] as String : null,
    authorId: r['author_id'] is String ? r['author_id'] as String : null,
    fileName: r['file_name'] is String ? r['file_name'] as String : null,
    mimeType: r['mime_type'] is String ? r['mime_type'] as String : null,
    createdAt: r['created_at'] is String
        ? DateTime.tryParse(r['created_at'] as String)?.toLocal()
        : null,
  );
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

  /// `40001` 판정. 기본은 '재호출 없음'(fail-closed) — 호출부가 명시할 때만
  /// 1회 재호출이 열린다.
  IqRegisterConflictClassifier isRetriableRegisterConflict = _neverRetriable,

  /// 명시 거부 코드 → 한글 문구(없으면 기존 일반 문구). 흐름·판정은 불변 —
  /// 문구만 바꾼다.
  IqRegisterFailureDescriber describeRegisterFailure = _noDescription,
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

  final IqAttachmentRegistration registration;
  try {
    registration = await _registerWithConflictRetry(
      register: register,
      objectPath: objectPath,
      file: file,
      messageId: messageId,
      isRetriableRegisterConflict: isRetriableRegisterConflict,
    );
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
      // DELETE 거부를 곧바로 실패로 단정하지 않는다(169 대응). 정책의 존재
      // 여부는 앱이 알 수 없으므로 **관측**으로만 분기한다 — 등록돼 있다면
      // '등록된 첨부는 삭제 불가'가 정상이므로 성공 수렴한다.
      IqAttachment? registeredAfterDeny;
      try {
        registeredAfterDeny = await findRegistered(objectPath);
      } catch (_) {
        registeredAfterDeny = null; // 확인 불가 → 기존 고아 처리 유지.
      }
      if (registeredAfterDeny != null) return registeredAfterDeny;
      orphaned = true; // 삭제도 실패·미등록 — 성공 표시 금지, 경로 보존.
    }
    // 계약 7: 명시 거부 코드(STORAGE_*·MIME_*·SIZE_EXCEEDED·ACCOUNT_*)는
    // 사용자에게 원인 있는 한글 문구로 안내한다(미지 코드는 기존 일반 문구).
    final String? mapped = describeRegisterFailure(e);
    throw IqAttachmentRegisterFailure(
      message: orphaned
          ? '첨부 등록이 완료되지 않았어요. 다시 시도해 주세요. (미정리 파일 1건: ${file.fileName})'
          : (mapped ?? '첨부 등록에 실패했어요. 다시 시도해 주세요.'),
      orphaned: orphaned,
      retryObjectPath: orphaned ? objectPath : null,
    );
  }

  // 경로 불변식: 신규 계약이면 서버 정규화 경로가 이후 모든 조회의 정본이다
  // (앱 경로로 조회하면 정규화 결과와 달라 빗나갈 수 있다). 레거시 계약일
  // 때만 앱 경로를 계속 쓴다.
  final String canonicalPath = registration.storagePath;

  if (registration.needsCanonicalRefetch) {
    // 멱등 히트 — 반환 jsonb 에는 file_name·mime_type·message_id 가 없고 168 은
    // 기존 행을 UPDATE 하지 않는다. 로컬 값으로 조립하면 최초 등록이 다른
    // 파일명·다른 메시지로 돼 있어도 이번 시도의 값을 보여주게 된다.
    // 서버가 돌려준 경로로 1회 재조회해 **DB 행을 정본**으로 삼는다.
    final IqAttachment? canonical;
    try {
      canonical = await findRegistered(canonicalPath);
    } catch (_) {
      // 보상삭제·RPC 재호출 금지 — 경로를 보존한 채 AMBIGUOUS 로 수렴.
      throw IqAttachmentAmbiguousResult(retryObjectPath: canonicalPath);
    }
    if (canonical == null) {
      throw IqAttachmentAmbiguousResult(retryObjectPath: canonicalPath);
    }
    return canonical;
  }

  return IqAttachment(
    id: registration.attachmentId,
    storagePath: canonicalPath,
    messageId: messageId,
    fileName: file.fileName,
    mimeType: file.mimeType,
  );
}

/// 등록 RPC 호출 — `40001` REGISTER_CONFLICT_UNRESOLVED 만 **1회** 재호출한다.
/// 그 외 오류(모호 결과 포함)는 그대로 던진다 — 재호출 금지(§4-3).
/// 재호출은 같은 objectPath 로만 하므로 재업로드·중복 객체가 생기지 않는다.
Future<IqAttachmentRegistration> _registerWithConflictRetry({
  required IqAttachmentRegistrar register,
  required String objectPath,
  required PickedImage file,
  required String? messageId,
  required IqRegisterConflictClassifier isRetriableRegisterConflict,
}) async {
  try {
    return await register(objectPath, file, messageId);
  } catch (e) {
    if (!isRetriableRegisterConflict(e)) rethrow;
    // 응답이 도착한 명시 오류 = 168 적용 증명. 경합 해소 재시도 1회.
    // 두 번째도 실패하면 그대로 전파돼 확정 실패 경로로 간다.
    return register(objectPath, file, messageId);
  }
}

bool _neverRetriable(Object _) => false;

String? _noDescription(Object _) => null;
