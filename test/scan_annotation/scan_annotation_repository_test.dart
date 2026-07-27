import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/ink/ink_document.dart';
import 'package:ssambership_app/core/ink/ink_input_mode.dart';
import 'package:ssambership_app/features/question_room/data/attachments/attachment_upload.dart';
import 'package:ssambership_app/features/question_room/data/models/question_attachment.dart';
import 'package:ssambership_app/features/scan_annotation/data/scan_annotation_repository.dart';

/// scan-annotations 원본 저장 fake.
class _FakeDocStore implements AnnotationDocStore {
  final Map<String, Uint8List> uploaded = <String, Uint8List>{};
  Uint8List? downloadBytes;
  String? lastUpsertPath;

  @override
  Future<void> upsertDocument({
    required String path,
    required Uint8List bytes,
  }) async {
    lastUpsertPath = path;
    uploaded[path] = bytes;
  }

  @override
  Future<Uint8List> downloadDocument({required String path}) async =>
      downloadBytes ?? Uint8List(0);
}

/// 기존 첨부 업로더 파이프라인 fake — 호출 인자만 기록.
class _FakeUploader implements AttachmentUploaderPort {
  bool called = false;
  String? roomId;
  String? threadId;
  PickedImage? image;

  @override
  bool get isReady => true;

  @override
  Future<AttachmentUploadResult> upload({
    required String roomId,
    required String threadId,
    String? messageId,
    required PickedImage image,
  }) async {
    called = true;
    this.roomId = roomId;
    this.threadId = threadId;
    this.image = image;
    return AttachmentUploadResult(
      attachment: QuestionAttachment(
        id: 'att-1',
        threadId: threadId,
        storagePath: '$roomId/$threadId/x.png',
        createdAt: DateTime(2026, 7, 1),
      ),
      answeredTransition: false,
    );
  }
}

InkDocument _doc() => const InkDocument(
      canvasWidth: 400,
      canvasHeight: 300,
      sketch: <String, dynamic>{
        'lines': <dynamic>[
          <String, dynamic>{
            'points': <dynamic>[
              <String, dynamic>{'x': 0.5, 'y': 0.5, 'pressure': 0.5},
            ],
            'color': 0xFF000000,
            'width': 0.02,
          },
        ],
      },
      inputMode: InkInputMode.penOnly,
    );

void main() {
  test('submit: 평탄화 PNG는 기존 첨부 파이프라인으로, 원본은 첨부 id 경로에 upsert', () async {
    final _FakeDocStore ds = _FakeDocStore();
    final _FakeUploader up = _FakeUploader();
    final ScanAnnotationRepository repo =
        ScanAnnotationRepository(docStore: ds, uploader: up);

    final QuestionAttachment att = await repo.submit(
      roomId: 'room-1',
      threadId: 'thread-1',
      document: _doc(),
      flattenedPng: Uint8List.fromList(<int>[1, 2, 3]),
    );

    // 전송: 기존 업로더로, PNG 이미지로.
    expect(up.called, isTrue);
    expect(up.roomId, 'room-1');
    expect(up.threadId, 'thread-1');
    expect(up.image!.mimeType, 'image/png');
    expect(up.image!.bytes, <int>[1, 2, 3]);
    expect(att.id, 'att-1');

    // 저장: 전송된 첨부 id 기준 scan-annotations 경로(첫 세그먼트=roomId).
    expect(ds.lastUpsertPath, 'room-1/att-1/ink.json');
    final InkDocument saved = InkDocument.fromJsonString(
        utf8.decode(ds.uploaded['room-1/att-1/ink.json']!));
    expect(saved.canvasWidth, 400);
    expect(saved.isEmpty, isFalse);
  });

  test('loadDocument: 경로에서 내려받아 InkDocument 복원', () async {
    final _FakeDocStore ds = _FakeDocStore()
      ..downloadBytes = Uint8List.fromList(utf8.encode(_doc().toJsonString()));
    final ScanAnnotationRepository repo =
        ScanAnnotationRepository(docStore: ds, uploader: _FakeUploader());

    final InkDocument loaded =
        await repo.loadDocument(roomId: 'room-1', attachmentId: 'att-1');

    expect(loaded.canvasWidth, 400);
    expect(loaded.inputMode, InkInputMode.penOnly);
    expect(loaded.isEmpty, isFalse);
  });
}
