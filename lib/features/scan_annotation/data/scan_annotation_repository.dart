import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/ink/ink_document.dart';
import '../../../core/ink/ink_storage_paths.dart';
import '../../../core/scan/image_downscaler.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import '../../question_room/data/attachments/attachment_upload.dart';
import '../../question_room/data/models/question_attachment.dart';

/// 주석 원본(ink.json)을 scan-annotations 버킷에 넣고 빼는 최소 포트.
///
/// ★ 주입 분리(S14-2 패턴 동일): 저장/로드 흐름은 레포가 갖고, Supabase 구체
///   호출은 이 포트 뒤로 숨긴다 → 테스트는 fake 포트로 실DB 없이 검증한다.
abstract class AnnotationDocStore {
  /// 같은 경로 덮어쓰기(upsert).
  Future<void> upsertDocument({
    required String path,
    required Uint8List bytes,
  });

  /// 원본 다운로드(재편집용).
  Future<Uint8List> downloadDocument({required String path});
}

/// 스캔 주석 저장/전송 레포지토리(S15).
///
/// 저장: 주석 원본(ink.json)을 scan-annotations '{roomId}/{attachmentId}/ink.json'
///       에 upsert(재편집용). 경로는 InkStoragePaths.annotationDocument 규약.
/// 전송: 평탄화 PNG 를 '기존 첨부 파이프라인'(SupabaseAttachmentUploader)으로
///       채팅 첨부 전송한다 — 업로더를 재구현하지 않는다.
class ScanAnnotationRepository {
  const ScanAnnotationRepository({
    required AnnotationDocStore docStore,
    required AttachmentUploaderPort uploader,
  })  : _docStore = docStore,
        _uploader = uploader;

  /// 운영 기본 구현(Supabase 저장소 + 기존 첨부 업로더).
  factory ScanAnnotationRepository.supabase() => const ScanAnnotationRepository(
        docStore: SupabaseAnnotationDocStore(),
        uploader: SupabaseAttachmentUploader(),
      );

  final AnnotationDocStore _docStore;
  final AttachmentUploaderPort _uploader;

  /// 주석 완료: 평탄화 PNG 를 첨부로 전송하고, 그 첨부 id 기준으로 원본(ink.json)을
  /// 저장한다(재편집용). 전송된 첨부를 반환한다.
  Future<QuestionAttachment> submit({
    required String roomId,
    required String threadId,
    required InkDocument document,
    required Uint8List flattenedPng,
    String fileName = 'annotation.png',
  }) async {
    // P2-20: 평탄화 PNG 도 일반 첨부와 같은 크기 규약(§6-4)을 통과시킨다 —
    // 5MB 초과면 축소(불투명 배경이라 대개 JPEG 재인코딩), 파일명·MIME 도 함께 맞춘다
    // (IQ 경로 iq_annotation_repository.submitAnnotation 과 동일 파이프라인).
    final PickedImage image = await downscaleIfOversized(PickedImage(
      bytes: flattenedPng,
      fileName: fileName,
      mimeType: 'image/png',
    ));

    // 1) 평탄화 이미지 → 기존 첨부 파이프라인으로 전송(중복 구현 금지).
    //    등록은 서버 RPC(P2-19) — 실패 시 업로더가 고아 객체를 보상 삭제한다.
    final AttachmentUploadResult uploaded = await _uploader.upload(
      roomId: roomId,
      threadId: threadId,
      image: image,
    );
    final QuestionAttachment attachment = uploaded.attachment;

    // 2) 재편집용 원본(ink.json)을 전송된 첨부 id 기준 경로에 upsert.
    await _docStore.upsertDocument(
      path: InkStoragePaths.annotationDocument(roomId, attachment.id),
      bytes: Uint8List.fromList(utf8.encode(document.toJsonString())),
    );
    return attachment;
  }

  /// 기존 주석 원본을 내려받아 [InkDocument] 로 복원(재편집 진입용).
  Future<InkDocument> loadDocument({
    required String roomId,
    required String attachmentId,
  }) async {
    final Uint8List bytes = await _docStore.downloadDocument(
      path: InkStoragePaths.annotationDocument(roomId, attachmentId),
    );
    return InkDocument.fromJsonString(utf8.decode(bytes));
  }
}

/// Supabase Storage(scan-annotations 버킷) 구현.
class SupabaseAnnotationDocStore implements AnnotationDocStore {
  const SupabaseAnnotationDocStore();

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
    await _client.storage.from(InkStoragePaths.annotationBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'application/json',
            upsert: true,
          ),
        );
  }

  @override
  Future<Uint8List> downloadDocument({required String path}) =>
      _client.storage.from(InkStoragePaths.annotationBucket).download(path);
}
