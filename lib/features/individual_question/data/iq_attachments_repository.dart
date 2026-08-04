import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/scan/picked_image.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import 'individual_question_repository.dart';
import 'iq_attachment_upload_core.dart';
import 'iq_error_mapper.dart';
import 'models/individual_question_models.dart';

/// 개별질문 첨부 업로드 포트(S17·세션1 §6). 조회는 기존
/// [IndividualQuestionRepository.listAttachments](당사자 SELECT RLS)가 담당.
///
/// ★ 쓰기 규약: 이 DB 의 IQ 테이블은 SELECT-only — 행 등록은 반드시
///   SECURITY DEFINER RPC `add_individual_question_attachment` 로 한다
///   (staging 실측: 당사자 검증·경로 위조 차단·메시지 소속 검증 내장).
/// ★ 검증·보상삭제·재시도 멱등은 순수 코어(uploadIqAttachmentCore)가 정본.
abstract class IqAttachmentsPort {
  /// 준비 여부(RPC 적용·버킷). false 면 upload 는 안내 에러.
  bool get isReady;

  /// 파일 업로드 + 행 등록(한 메서드 — 경로 규약을 호출부가 다룰 필요 없음).
  /// [existingObjectPath]: 직전 시도에서 업로드까지 성공(등록만 실패·고아)한
  /// 경로 — 재업로드를 생략해 재시도 중복 객체 0 을 보장한다.
  Future<IqAttachment> upload({
    required String questionId,
    required PickedImage image,
    String? messageId,
    String? existingObjectPath,
  });
}

/// Supabase 구현 — 버킷 업로드 → RPC 행 등록.
class SupabaseIqAttachmentsRepository implements IqAttachmentsPort {
  const SupabaseIqAttachmentsRepository();

  /// 실사 확인된 기존 버킷(웹과 공유). 신설 아님.
  static const String bucket = IndividualQuestionRepository.attachmentBucket;

  @override
  bool get isReady => true;

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) throw const AppError('백엔드에 연결되어 있지 않아요.');
    return c;
  }

  @override
  Future<IqAttachment> upload({
    required String questionId,
    required PickedImage image,
    String? messageId,
    String? existingObjectPath,
  }) {
    final SupabaseClient client = _client;
    return uploadIqAttachmentCore(
      questionId: questionId,
      file: image,
      messageId: messageId,
      existingObjectPath: existingObjectPath,
      // 규약: 첫 세그먼트 = 질문 uuid (스토리지 RLS·RPC 위조 검증과 동일).
      buildPath: () => buildStoragePath(
        questionId: questionId,
        fileName: image.fileName,
        timestamp: DateTime.now().microsecondsSinceEpoch,
        salt: Random().nextInt(0xFFFFFF),
      ),
      uploadBinary: (String path, PickedImage file) => client.storage
          .from(bucket)
          .uploadBinary(
            path,
            file.bytes,
            fileOptions: FileOptions(contentType: file.mimeType, upsert: false),
          ),
      // 행 등록은 RPC 만(테이블 INSERT 정책 없음 — SELECT-only 규약).
      // ★ 시그니처는 불변, 반환형만 uuid → jsonb 로 바뀐다(SQL 168). 앱은
      //   적용 시점을 모른 채 **응답 형태로만** 분기한다(이중 형태 리더).
      register: (String path, PickedImage file, String? msgId) async {
        final dynamic result = await client.rpc<dynamic>(
          'add_individual_question_attachment',
          params: <String, dynamic>{
            'p_question_id': questionId,
            'p_storage_path': path,
            'p_file_name': file.fileName,
            'p_mime_type': file.mimeType,
            if (msgId != null) 'p_message_id': msgId,
          },
        );
        // expectedQuestionId = RPC 에 보낸 p_question_id 와 동일한 값 —
        // 응답이 그 질문의 것인지 파서가 fail-closed 로 대조한다.
        return parseIqAttachmentRegistration(
          result,
          requestedPath: path,
          expectedQuestionId: questionId,
        );
      },
      removeObject: (String path) =>
          client.storage.from(bucket).remove(<String>[path]),
      // 보정1: 등록 정본 확인 — 당사자 SELECT(iqa_select_party).
      findRegistered: (String path) =>
          _findRegistered(client, questionId, path),
      isDefiniteRegisterFailure: isDefiniteRegisterFailure,
      isRetriableRegisterConflict: isRetriableRegisterConflict,
      // 계약 7 신규 거부 코드(STORAGE_*·MIME_*·SIZE_EXCEEDED·ACCOUNT_*) →
      // 한글 문구(iq_error_mapper 정본 — 코드 원문 비노출).
      describeRegisterFailure: iqErrorMessage,
    );
  }

  /// REGISTER_CONFLICT_UNRESOLVED(SQL 168) — 유일한 등록 RPC 재호출 사유.
  static const String registerConflictCode = '40001';

  /// 서버가 '응답으로' 거부한 경우만 미등록 확정(PostgrestException).
  /// 그 외(타임아웃·연결 끊김·파싱 실패 등)는 전부 모호 결과로 취급한다.
  ///
  /// ★ 168 의 `42P10` 은 167(on conflict 대상 인덱스) 미적용 배포 사고 신호다.
  ///   인덱스가 없어 INSERT 문 자체가 실패한 것이므로 행이 생성되지 않았음이
  ///   확정 — 여기서 확정 실패로 분류되는 것이 **정상**이다. 재시도도,
  ///   레거시 RPC 폴백도 하지 않는다(폴백하면 배포 순서 사고를 은폐한다).
  static bool isDefiniteRegisterFailure(Object e) => e is PostgrestException;

  /// 경합이 풀리지 않은 등록(`40001`)만 1회 재호출 — 모호 결과가 아니라
  /// 응답이 도착한 명시 오류이며, 그 도착 자체가 168 적용을 증명한다.
  static bool isRetriableRegisterConflict(Object e) =>
      e is PostgrestException && e.code == registerConflictCode;

  /// 동일 question_id + storage_path 행 SELECT(당사자 RLS).
  /// v19 보정3: null 은 '실제 0건(미등록 확정)'일 때만. 행이 존재하는데
  /// shape 가 손상됐거나 필터와 모순이면 throw — 코어가 AMBIGUOUS 로 수렴
  /// (보상삭제·RPC 재호출로 진행하지 않는다). SELECT 자체 실패도 throw.
  Future<IqAttachment?> _findRegistered(
      SupabaseClient client, String questionId, String path) async {
    final List<dynamic> rows = await client
        .from('individual_question_attachments')
        .select(
            'id, question_id, storage_path, message_id, file_name, mime_type')
        .eq('question_id', questionId)
        .eq('storage_path', path)
        .limit(1);
    return canonicalRegisteredAttachment(rows,
        questionId: questionId, objectPath: path);
  }

  /// 당사자 다운로드(저장용) — RLS(iqa_storage_read_party) 경유 바이트 수신.
  /// signed URL 을 만들지도, 저장하지도 않는다(위생 규약).
  Future<List<int>> downloadBytes(String storagePath) async {
    return _client.storage.from(bucket).download(storagePath);
  }

  /// 경로 조립(순수 함수 — 테스트 가능):
  /// '{questionId}/{ts}-{salt}.{ext}' — 첫 세그먼트 = 질문 uuid 규약,
  /// ts+salt 로 파일명 충돌 방지(별도 uuid 의존성 없이).
  static String buildStoragePath({
    required String questionId,
    required String fileName,
    required int timestamp,
    required int salt,
  }) {
    final int dot = fileName.lastIndexOf('.');
    final String ext = dot <= 0
        ? 'bin'
        : fileName
            .substring(dot + 1)
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
    final String saltHex = salt.toRadixString(16).padLeft(6, '0');
    return '$questionId/$timestamp-$saltHex.${ext.isEmpty ? 'bin' : ext}';
  }
}
