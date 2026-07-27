import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/scan/picked_image.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../shared/errors/app_error.dart';
import '../models/question_attachment.dart';
import '../qna_error_mapper.dart';

// PickedImage 는 S16 에서 core/scan 으로 이동 — 기존 import 경로 하위호환.
export '../../../../core/scan/picked_image.dart' show PickedImage;

/// 첨부 업로드 제한 안내(고정 문구). 기획 안전 규칙: 교재 전체 스캔/PDF 등 금지.
const String kAttachmentRestrictionText = '교재 전체 PDF·스캔 등 저작권 침해 자료는 올릴 수 없어요. '
    '문제 사진처럼 꼭 필요한 부분만, 이미지(JPG·PNG) 5MB 이하로 올려주세요.';

/// 허용 이미지 MIME.
const List<String> kAllowedImageMimeTypes = <String>[
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
];

/// 최대 첨부 크기(5MB).
const int kMaxAttachmentBytes = 5 * 1024 * 1024;

/// 선택 이미지 검증. 통과하면 null, 아니면 사용자에게 보여줄 한글 사유.
String? validatePickedImage(PickedImage image) {
  if (image.sizeBytes > kMaxAttachmentBytes) {
    return '이미지가 너무 커요. 5MB 이하로 올려주세요.';
  }
  if (!kAllowedImageMimeTypes.contains(image.mimeType.toLowerCase())) {
    return '이미지(JPG·PNG) 형식만 올릴 수 있어요.';
  }
  return null;
}

/// 이미지 선택 포트. 기본 구현은 '미도입'(image_picker 인수인계) — [isAvailable]=false.
abstract class ImagePickerPort {
  /// 실제 선택 가능한지(패키지·권한 준비 여부).
  bool get isAvailable;

  /// 이미지 1장 선택. 취소/미도입이면 null.
  Future<PickedImage?> pickImage();
}

/// 기본: 아직 image_picker 를 도입하지 않아 선택 불가(인수인계 항목).
class DisabledImagePicker implements ImagePickerPort {
  const DisabledImagePicker();

  @override
  bool get isAvailable => false;

  @override
  Future<PickedImage?> pickImage() async => null;
}

/// 업로드+등록 결과. [answeredTransition]=true 면 이 첨부(멘토 첫 답변)로
/// 서버가 pending→answered 전이(+question_answered 알림)를 수행했다는 뜻.
class AttachmentUploadResult {
  const AttachmentUploadResult({
    required this.attachment,
    required this.answeredTransition,
  });

  final QuestionAttachment attachment;
  final bool answeredTransition;
}

/// 첨부 등록 실패(+보상 결과) — 원래 실패와 보상 삭제 실패를 별도로 보존한다.
///
/// [registrationError] = qna_register_attachment 실패 원인(원래 실패).
/// [compensationError] = 미등록 객체 보상 DELETE 실패 원인(null = 삭제 성공 또는 미시도).
/// [compensated] = 고아 객체 정리 성공 여부. 화면에는 [userMessage] 만 노출한다.
class AttachmentRegistrationFailure extends AppError {
  const AttachmentRegistrationFailure(
    super.userMessage, {
    required this.registrationError,
    this.compensationError,
    required this.compensated,
  }) : super(cause: registrationError);

  final Object registrationError;
  final Object? compensationError;
  final bool compensated;

  @override
  String toString() =>
      'AttachmentRegistrationFailure($userMessage, compensated=$compensated'
      '${compensationError == null ? '' : ', compensationError=$compensationError'})';
}

/// 23505 재시도 수용 실패 — 같은 storage_path 에 '다른 의미'의 등록행이 존재.
///
/// 이미 등록된 객체일 수 있으므로 보상 DELETE 도 하지 않는다(성공 위장 금지).
class AttachmentRegistrationConflict extends AppError {
  const AttachmentRegistrationConflict({super.cause})
      : super('이미 등록된 첨부와 충돌했어요. 새로고침 후 다시 시도해 주세요.');
}

/// 첨부 업로드 포트. Storage 업로드 + 서버 RPC 등록을 담당.
abstract class AttachmentUploaderPort {
  /// 준비 여부(스토리지 버킷·정책). false 면 [upload] 은 안내 에러를 던진다.
  bool get isReady;

  Future<AttachmentUploadResult> upload({
    required String roomId,
    required String threadId,
    String? messageId,
    required PickedImage image,
  });
}

/// Supabase Storage 업로드 구현.
///
/// ★ 인프라(스테이징 정본, 2026-07 실측): Storage 버킷 [bucket] 의 INSERT 정책은
///   `qra_storage_insert_party`(방 당사자 + thread writable + 경로 적격 +
///   탈퇴 write-block 아님), DELETE 정책은 `qra_storage_delete_unregistered_owner`
///   (본인 소유·미등록 객체만 — 보상 삭제 전용). 경로 규약은
///   '{roomId}/{threadId}/...' 로 서버 RPC(STORAGE_PATH_MISMATCH)와 동일하게 강제된다.
class SupabaseAttachmentUploader implements AttachmentUploaderPort {
  const SupabaseAttachmentUploader({
    QnaAttachmentBackend? backend,
    String? Function()? currentUserIdProvider,
  })  : _backendOverride = backend,
        _currentUserIdProvider = currentUserIdProvider;

  /// 실제 버킷명(Supabase 실사로 확인 — 웹과 공유).
  static const String bucket = 'question-room-attachments';

  /// 버킷·정책 준비 완료 → 활성.
  static const bool _storageReady = true;

  /// 테스트 주입용 백엔드(없으면 Supabase 구현).
  final QnaAttachmentBackend? _backendOverride;

  /// 현재 사용자 id 공급자(테스트 주입 지점 — 기본은 Supabase 세션).
  final String? Function()? _currentUserIdProvider;

  QnaAttachmentBackend get _backend =>
      _backendOverride ?? const SupabaseQnaAttachmentBackend();

  String? get _currentUserId {
    final String? Function()? provider = _currentUserIdProvider;
    if (provider != null) return provider();
    return SupabaseInit.clientOrNull?.auth.currentUser?.id;
  }

  @override
  bool get isReady => _storageReady;

  @override
  Future<AttachmentUploadResult> upload({
    required String roomId,
    required String threadId,
    String? messageId,
    required PickedImage image,
  }) async {
    final String? invalid = validatePickedImage(image);
    if (invalid != null) throw AppError(invalid);

    if (!_storageReady) {
      throw const AppError('이미지 첨부 저장소가 아직 준비되지 않았어요.');
    }

    // 정책 규약: 경로는 반드시 '{roomId}/{threadId}/...' — Storage INSERT 정책과
    // qna_register_attachment 의 STORAGE_PATH_MISMATCH 검사가 모두 이 형식을 강제한다.
    final String objectPath = buildStoragePath(
      roomId: roomId,
      threadId: threadId,
      fileName: image.fileName,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    await _backend.uploadObject(
      path: objectPath,
      bytes: image.bytes,
      mimeType: image.mimeType,
    );

    // 메타 등록은 직접 INSERT 가 아니라 서버 RPC(P2-19). 멘토 첫 첨부의
    // answered 전이·알림도 이 RPC 가 원자적으로 수행한다.
    return _register(
      threadId: threadId,
      objectPath: objectPath,
      fileName: image.fileName,
      mimeType: image.mimeType,
      messageId: messageId,
    );
  }

  /// RPC 등록 + 실패 시 보상 삭제.
  ///
  /// 실패 시 방금 올린 '본인 소유·미등록' 객체만 DELETE 한다(Storage 정책
  /// qra_storage_delete_unregistered_owner 가 그 이상을 서버에서 거부).
  /// 등록에 성공한 객체는 어떤 경로로도 삭제하지 않는다.
  Future<AttachmentUploadResult> _register({
    required String threadId,
    required String objectPath,
    required String fileName,
    required String mimeType,
    String? messageId,
  }) async {
    final Object? data;
    try {
      data = await _backend.registerAttachment(
        threadId: threadId,
        storagePath: objectPath,
        fileName: fileName,
        mimeType: mimeType,
        messageId: messageId,
      );
    } catch (e) {
      // 동일 storage_path 재시도로 이미 등록된 경우(UNIQUE 23505) — 기존 행이
      // '같은 시도'였음을 의미까지 확인한 뒤에만 멱등 성공으로 수용한다.
      // (백엔드 조회가 필터를 무시하고 엉뚱한 행을 돌려줘도 여기서 걸러진다.)
      if (isUniqueViolation(e)) {
        final QuestionAttachment? existing = await _findRegistered(objectPath);
        if (existing != null) {
          if (_matchesAttempt(
            existing,
            objectPath: objectPath,
            threadId: threadId,
            messageId: messageId,
          )) {
            return AttachmentUploadResult(
                attachment: existing, answeredTransition: false);
          }
          // 의미 불일치: 성공 위장 금지. 이미 등록된 객체일 수 있으므로
          // 보상 DELETE 도 하지 않는다(서버 정책도 등록 객체 삭제를 거부).
          throw AttachmentRegistrationConflict(cause: e);
        }
        // 23505 인데 행 자체가 안 보임 → 기존 실패 흐름(미등록 객체 보상 삭제).
      }
      throw await _compensate(objectPath, registrationError: e);
    }
    if (data is! Map) {
      throw await _compensate(
        objectPath,
        registrationError: const AppError('첨부 등록 결과를 확인하지 못했어요. 다시 시도해 주세요.'),
      );
    }
    final String? authorId = SupabaseInit.clientOrNull?.auth.currentUser?.id;
    return AttachmentUploadResult(
      attachment: QuestionAttachment(
        id: data['attachment_id'] as String,
        threadId: threadId,
        messageId: messageId,
        authorId: authorId,
        storagePath: objectPath,
        fileName: fileName,
        mimeType: mimeType,
        createdAt: DateTime.now().toUtc(),
      ),
      answeredTransition: (data['answered_transition'] as bool?) ?? false,
    );
  }

  /// 등록 실패 보상: 미등록 고아 객체 삭제 시도 후, 원래 실패와 보상 결과를
  /// 함께 담은 오류를 만든다(전체 성공으로 위장 금지 · 이중 실패 별도 보존).
  Future<AttachmentRegistrationFailure> _compensate(
    String objectPath, {
    required Object registrationError,
  }) async {
    final String userMessage = qnaErrorMessage(registrationError) ??
        (registrationError is AppError
            ? registrationError.userMessage
            : '첨부 파일을 등록하지 못했어요. 다시 시도해 주세요.');
    try {
      await _backend.removeObject(objectPath);
      return AttachmentRegistrationFailure(
        userMessage,
        registrationError: registrationError,
        compensated: true,
      );
    } catch (deleteError) {
      return AttachmentRegistrationFailure(
        userMessage,
        registrationError: registrationError,
        compensationError: deleteError,
        compensated: false,
      );
    }
  }

  /// 23505 멱등 수용 판정 — 기존 행이 '이번 시도'와 의미까지 일치해야 한다.
  /// storage_path·thread_id 정확 일치, message_id 동일, author_id 는 기록돼
  /// 있으면 현재 로그인 사용자와 일치(레거시 null 은 판정 불가 → 허용).
  bool _matchesAttempt(
    QuestionAttachment existing, {
    required String objectPath,
    required String threadId,
    String? messageId,
  }) {
    if (existing.storagePath != objectPath) return false;
    if (existing.threadId != threadId) return false;
    if (existing.messageId != messageId) return false;
    final String? author = existing.authorId;
    final String? uid = _currentUserId;
    if (author != null && uid != null && author != uid) return false;
    return true;
  }

  /// storage_path 로 기존 등록 행 조회(UNIQUE 재시도 수용용). 실패하면 null.
  Future<QuestionAttachment?> _findRegistered(String objectPath) async {
    try {
      final Map<String, dynamic>? row =
          await _backend.findRegisteredByPath(objectPath);
      return row == null ? null : QuestionAttachment.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  /// Storage object 경로 조립(순수 함수 — 테스트 가능).
  /// 정책상 첫 세그먼트는 roomId 여야 한다: '{roomId}/{threadId}/{ts}_{safeName}'.
  static String buildStoragePath({
    required String roomId,
    required String threadId,
    required String fileName,
    required int timestamp,
  }) {
    final String safeName = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    return '$roomId/$threadId/${timestamp}_$safeName';
  }
}

/// 첨부 저장/등록의 Supabase 구체 호출을 숨기는 포트(테스트 fake 주입 지점).
abstract class QnaAttachmentBackend {
  /// Storage 업로드(upsert 금지 — 동일 경로 재업로드는 실패해야 정상).
  Future<void> uploadObject({
    required String path,
    required List<int> bytes,
    required String mimeType,
  });

  /// qna_register_attachment RPC 호출 — 반환 jsonb(Map) 그대로.
  Future<Object?> registerAttachment({
    required String threadId,
    required String storagePath,
    required String fileName,
    required String mimeType,
    String? messageId,
  });

  /// 미등록 고아 객체 보상 삭제(서버 정책이 본인 소유·미등록만 허용).
  Future<void> removeObject(String path);

  /// storage_path 로 기존 등록 행 조회(없으면 null).
  Future<Map<String, dynamic>?> findRegisteredByPath(String path);
}

/// 운영 기본 구현(Supabase Storage + RPC).
class SupabaseQnaAttachmentBackend implements QnaAttachmentBackend {
  const SupabaseQnaAttachmentBackend();

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) throw const AppError('백엔드에 연결되어 있지 않아요.');
    return c;
  }

  @override
  Future<void> uploadObject({
    required String path,
    required List<int> bytes,
    required String mimeType,
  }) async {
    await _client.storage.from(SupabaseAttachmentUploader.bucket).uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
  }

  @override
  Future<Object?> registerAttachment({
    required String threadId,
    required String storagePath,
    required String fileName,
    required String mimeType,
    String? messageId,
  }) {
    return _client.rpc(
      'qna_register_attachment',
      params: <String, dynamic>{
        'p_thread_id': threadId,
        'p_storage_path': storagePath,
        'p_file_name': fileName,
        'p_mime_type': mimeType,
        'p_message_id': messageId,
      },
    );
  }

  @override
  Future<void> removeObject(String path) async {
    await _client.storage
        .from(SupabaseAttachmentUploader.bucket)
        .remove(<String>[path]);
  }

  @override
  Future<Map<String, dynamic>?> findRegisteredByPath(String path) {
    return _client
        .from('question_attachments')
        .select('*')
        .eq('storage_path', path)
        .maybeSingle();
  }
}
