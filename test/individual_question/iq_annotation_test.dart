import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/ink/ink_document.dart';
import 'package:ssambership_app/core/ink/ink_storage_paths.dart';
import 'package:ssambership_app/core/scan/picked_image.dart';
import 'package:ssambership_app/features/individual_question/data/iq_annotation_repository.dart';
import 'package:ssambership_app/features/individual_question/data/iq_attachments_repository.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/scan_annotation/annotation_target.dart';

/// S18 개별질문 첨삭 — 완료 파이프라인(새 첨부 + ink.json)과 이어 그리기
/// 복원 분기를 전부 fake 주입으로 검증한다(DB·스토리지 비접촉).
class _FakeStore implements IqAnnotationStore {
  final Map<String, Uint8List> objects = <String, Uint8List>{};
  String? lastUpsertPath;
  final List<String> downloadedAttachments = <String>[];

  @override
  Future<void> upsertDocument({
    required String path,
    required Uint8List bytes,
  }) async {
    lastUpsertPath = path;
    objects[path] = bytes;
  }

  @override
  Future<Uint8List?> downloadDocumentOrNull({required String path}) async =>
      objects[path];

  @override
  Future<Uint8List> downloadAttachment({required String storagePath}) async {
    downloadedAttachments.add(storagePath);
    return Uint8List.fromList(<int>[1, 2, 3]);
  }
}

/// S17 업로더 fake — 업로드 인자 기록 + 새 첨부 반환(원본 비접촉).
class _FakeUploader implements IqAttachmentsPort {
  final List<PickedImage> uploaded = <PickedImage>[];
  final List<String> questionIds = <String>[];
  final List<String?> messageIds = <String?>[];

  @override
  bool get isReady => true;

  @override
  Future<IqAttachment> upload({
    required String questionId,
    required PickedImage image,
    String? messageId,
    String? existingObjectPath,
  }) async {
    questionIds.add(questionId);
    uploaded.add(image);
    messageIds.add(messageId);
    return IqAttachment(
      id: 'new-att-${uploaded.length}',
      storagePath: '$questionId/${image.fileName}',
      fileName: image.fileName,
      mimeType: image.mimeType,
    );
  }
}

InkDocument _doc() => const InkDocument(
      canvasWidth: 40,
      canvasHeight: 20,
      sketch: <String, dynamic>{
        'lines': <Map<String, dynamic>>[
          <String, dynamic>{
            'points': <Map<String, dynamic>>[
              <String, dynamic>{'x': 0.5, 'y': 0.5},
            ],
            'color': 0xFFFF0000,
            'width': 0.01,
          },
        ],
      },
    );

void main() {
  group('InkStoragePaths.iqAnnotationDocument (경로 규약)', () {
    test('첫 세그먼트=질문 uuid + annotations/ 프리픽스 — 기존 버킷 정책 그대로 통과', () {
      expect(
        InkStoragePaths.iqAnnotationDocument('q-uuid-1', 'att-1'),
        'q-uuid-1/annotations/att-1.json',
      );
    });

    test('구분자 포함 세그먼트는 거부(호출부 버그 방어)', () {
      expect(
        () => InkStoragePaths.iqAnnotationDocument('a/b', 'att'),
        throwsArgumentError,
      );
    });
  });

  group('IqAnnotationRepository', () {
    test('완료: 평탄화본이 새 첨부로 등록되고(원본 비접촉) ink.json 이 원본첨부 id 경로에 저장', () async {
      final _FakeStore store = _FakeStore();
      final _FakeUploader uploader = _FakeUploader();
      final IqAnnotationRepository repo =
          IqAnnotationRepository(store: store, uploader: uploader);
      final Uint8List png = Uint8List.fromList(<int>[9, 9, 9]);

      final IqAttachment created = await repo.submitAnnotation(
        questionId: 'q-1',
        sourceAttachmentId: 'src-att-1',
        result: AnnotationResult(document: _doc(), flattenedPng: png),
      );

      // ① 새 첨부: S17 업로더 경유, p_message_id 는 null 유지(후속 연동).
      expect(uploader.questionIds, <String>['q-1']);
      expect(uploader.uploaded.single.bytes, png);
      expect(uploader.uploaded.single.mimeType, 'image/png');
      expect(uploader.messageIds, <String?>[null]);
      expect(created.id, 'new-att-1'); // 원본(src-att-1)과 다른 새 행.

      // ② ink.json: 원본 첨부 id 기준 경로(새 첨부 id 가 아님 — 재편집 키).
      expect(store.lastUpsertPath, 'q-1/annotations/src-att-1.json');
      final InkDocument saved = InkDocument.fromJsonString(
          utf8.decode(store.objects[store.lastUpsertPath]!));
      expect(saved.isEmpty, isFalse);
    });

    test('재첨삭: 같은 원본에 다시 완료하면 첨부가 하나 더 생긴다(덮어쓰기 금지)', () async {
      final _FakeStore store = _FakeStore();
      final _FakeUploader uploader = _FakeUploader();
      final IqAnnotationRepository repo =
          IqAnnotationRepository(store: store, uploader: uploader);
      final AnnotationResult result = AnnotationResult(
        document: _doc(),
        flattenedPng: Uint8List.fromList(<int>[1]),
      );

      await repo.submitAnnotation(
          questionId: 'q-1', sourceAttachmentId: 'src', result: result);
      await repo.submitAnnotation(
          questionId: 'q-1', sourceAttachmentId: 'src', result: result);

      expect(uploader.uploaded.length, 2); // 새 첨부 2개.
      expect(store.objects.length, 1); // ink.json 은 같은 경로 upsert.
    });

    test('loadAnnotation: 없으면 null(새로 시작), 있으면 문서 복원(이어 그리기)', () async {
      final _FakeStore store = _FakeStore();
      final IqAnnotationRepository repo =
          IqAnnotationRepository(store: store, uploader: _FakeUploader());

      expect(
        await repo.loadAnnotation(questionId: 'q-1', sourceAttachmentId: 'a'),
        isNull,
      );

      store.objects['q-1/annotations/a.json'] =
          Uint8List.fromList(utf8.encode(_doc().toJsonString()));
      final InkDocument? restored =
          await repo.loadAnnotation(questionId: 'q-1', sourceAttachmentId: 'a');
      expect(restored, isNotNull);
      expect(restored!.canvasWidth, 40);
    });

    test('loadAnnotation: 깨진 파일은 null — 새로 시작으로 안전 폴백', () async {
      final _FakeStore store = _FakeStore();
      store.objects['q-1/annotations/a.json'] =
          Uint8List.fromList(utf8.encode('{"broken": true}'));
      final IqAnnotationRepository repo =
          IqAnnotationRepository(store: store, uploader: _FakeUploader());

      expect(
        await repo.loadAnnotation(questionId: 'q-1', sourceAttachmentId: 'a'),
        isNull,
      );
    });
  });

  test('IqAnnotationTarget: 화면 완료 결과를 S18 파이프라인으로 위임한다', () async {
    final _FakeStore store = _FakeStore();
    final _FakeUploader uploader = _FakeUploader();
    final IqAnnotationTarget target = IqAnnotationTarget(
      repository: IqAnnotationRepository(store: store, uploader: uploader),
      questionId: 'q-9',
      sourceAttachmentId: 'src-9',
    );

    await target.submit(AnnotationResult(
      document: _doc(),
      flattenedPng: Uint8List.fromList(<int>[7]),
    ));

    expect(uploader.questionIds, <String>['q-9']);
    expect(store.lastUpsertPath, 'q-9/annotations/src-9.json');
  });
}
