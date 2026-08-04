import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/ink/ink_document.dart';
import '../../../core/ink/ink_storage_paths.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import 'individual_question_repository.dart';

/// IQ 첨삭 원본(ink.json)·원본 첨부 바이트를 넣고 빼는 최소 포트(S18).
///
/// ★ 버킷은 기존 `individual-question-attachments` 하나다 — 첨삭 JSON 도
///   `{questionId}/annotations/{원본첨부id}.json` 으로 같은 버킷에 넣는다
///   (첫 세그먼트=질문 uuid 규약 동일). 같은 경로 재저장(upsert)은
///   `annotations/` 프리픽스 한정 UPDATE 정책이 허용한다 — 원본 첨부는
///   덮어쓰기 불가(supabase/migrations/20260707T1130_... 기록 참고).
abstract class IqAnnotationStore {
  /// 같은 경로 덮어쓰기(upsert) — 이어 그리기 저장.
  Future<void> upsertDocument({required String path, required Uint8List bytes});

  /// 첨삭 원본 다운로드. 파일이 없으면 null(새로 시작 분기).
  Future<Uint8List?> downloadDocumentOrNull({required String path});

  /// 원본 첨부(배경 이미지) 다운로드.
  Future<Uint8List> downloadAttachment({required String storagePath});
}

/// 개별질문 첨삭 레포지토리(S18).
///
/// 담당 범위: 첨삭 원본(ink.json)의 저장·복원과 배경(원본 첨부) 다운로드.
/// ★ 평탄화 PNG 의 서버 등록은 여기서 하지 않는다 — 완료 즉시 미연결 첨부를
///   만들던 이전 방식은 폐기됐고, 첨삭본은 멘토 작성 영역의 대기 첨부로 들어가
///   답변/추가 답글 메시지 생성 후 그 message_id 로 등록된다(§4-3).
class IqAnnotationRepository {
  const IqAnnotationRepository({required IqAnnotationStore store})
      : _store = store;

  /// 운영 기본 구현(기존 IQ 버킷).
  factory IqAnnotationRepository.supabase() =>
      const IqAnnotationRepository(store: SupabaseIqAnnotationStore());

  final IqAnnotationStore _store;

  /// 첨삭 원본(ink.json)을 [sourceAttachmentId] 기준 경로에 upsert 한다
  /// (이어 그리기용 — 첨부 행 등록 없음·목록 비노출·원본 불변).
  Future<void> saveDocument({
    required String questionId,
    required String sourceAttachmentId,
    required InkDocument document,
  }) async {
    await _store.upsertDocument(
      path: InkStoragePaths.iqAnnotationDocument(questionId, sourceAttachmentId),
      bytes: Uint8List.fromList(utf8.encode(document.toJsonString())),
    );
  }

  /// 같은 원본에 대한 기존 첨삭 원본을 복원한다(이어 그리기 제안용).
  /// 없거나 읽을 수 없으면 null — 호출부는 '새로 시작'으로 진행한다.
  Future<InkDocument?> loadAnnotation({
    required String questionId,
    required String sourceAttachmentId,
  }) async {
    final Uint8List? bytes = await _store.downloadDocumentOrNull(
      path: InkStoragePaths.iqAnnotationDocument(questionId, sourceAttachmentId),
    );
    if (bytes == null) return null;
    try {
      return InkDocument.fromJsonString(utf8.decode(bytes));
    } on FormatException {
      return null; // 깨진 파일 → 새로 시작(완료 시 어차피 새 첨부라 안전).
    }
  }

  /// 첨삭 배경으로 쓸 원본 첨부 바이트.
  Future<Uint8List> downloadAttachment(String storagePath) =>
      _store.downloadAttachment(storagePath: storagePath);
}

/// Supabase Storage(기존 IQ 첨부 버킷) 구현.
class SupabaseIqAnnotationStore implements IqAnnotationStore {
  const SupabaseIqAnnotationStore();

  static const String bucket = IndividualQuestionRepository.attachmentBucket;

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) throw const AppError('백엔드에 연결되어 있지 않아요.');
    return c;
  }

  @override
  Future<void> upsertDocument({
    required String path,
    required Uint8List bytes,
  }) async {
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'application/json',
            upsert: true,
          ),
        );
  }

  @override
  Future<Uint8List?> downloadDocumentOrNull({required String path}) async {
    try {
      return await _client.storage.from(bucket).download(path);
    } on StorageException catch (e) {
      // 부재(404)만 null — 그 외(권한·네트워크)는 그대로 올려 호출부가 안내.
      if (e.statusCode == '404' || e.error == 'not_found') return null;
      rethrow;
    }
  }

  @override
  Future<Uint8List> downloadAttachment({required String storagePath}) =>
      _client.storage.from(bucket).download(storagePath);
}
