import 'dart:ui' as ui;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as pkg;
import 'package:ssambership_app/core/ink/ink_document.dart';
import 'package:ssambership_app/core/ink/ink_input_mode.dart';
import 'package:ssambership_app/core/scan/image_downscaler.dart';
import 'package:ssambership_app/features/question_room/data/attachments/attachment_upload.dart';
import 'package:ssambership_app/features/question_room/data/models/question_attachment.dart';
import 'package:ssambership_app/features/scan_annotation/annotation_flattener.dart';
import 'package:ssambership_app/features/scan_annotation/data/scan_annotation_repository.dart';

/// P2-20 — 평탄화 경로의 크기 규약: ① 배경은 합성 '전에' 장변 캡(2560 규약을
/// 작은 수치로 재현) ② 평탄화 결과는 submit 에서 §6-4(5MB) 규약을 통과하며
/// 파일명 확장자·MIME 이 함께 바뀐다.

/// 결정적 노이즈 불투명 PNG(압축 불가 → 원하는 크기로 커진다).
Uint8List _noisePng(int w, int h) {
  final pkg.Image im = pkg.Image(width: w, height: h);
  int seed = 7;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      im.setPixelRgba(
          x, y, seed & 0xFF, (seed >> 8) & 0xFF, (seed >> 16) & 0xFF, 255);
    }
  }
  return Uint8List.fromList(pkg.encodePng(im));
}

Map<String, dynamic> _sketch() => <String, dynamic>{
      'lines': <dynamic>[
        <String, dynamic>{
          'points': <dynamic>[
            <String, dynamic>{'x': 0.1, 'y': 0.1, 'pressure': 0.5},
            <String, dynamic>{'x': 0.9, 'y': 0.9, 'pressure': 0.5},
          ],
          'color': 0xFFFF0000,
          'width': 0.05,
        },
      ],
    };

InkDocument _doc() => InkDocument(
      canvasWidth: 100,
      canvasHeight: 50,
      sketch: _sketch(),
      inputMode: InkInputMode.penOnly,
    );

/// 저장 fake(관심 밖 — 호출만 받는다).
class _FakeDocStore implements AnnotationDocStore {
  @override
  Future<void> upsertDocument({
    required String path,
    required Uint8List bytes,
  }) async {}

  @override
  Future<Uint8List> downloadDocument({required String path}) async =>
      Uint8List(0);
}

/// 업로더 fake — 업로드된 PickedImage 를 기록한다.
class _FakeUploader implements AttachmentUploaderPort {
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

void main() {
  testWidgets('배경 사전 축소 → 평탄화 출력 해상도가 캡을 따른다(비율 유지)',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      // 100x50 배경을 장변 40 으로 캡(실전 2560 규약의 축소 재현).
      final Uint8List capped = await downscaleFlattenBackground(
        _noisePng(100, 50),
        maxLongSide: 40,
      );
      final ui.Image bg = await AnnotationFlattener.decodeImage(capped);
      expect(bg.width, 40);
      expect(bg.height, 20);

      // 캡된 배경 위 합성 — 출력도 캡된 해상도(초과 픽셀 출력 없음).
      final Uint8List png = await AnnotationFlattener.flatten(
        background: bg,
        normalizedSketch: _sketch(),
      );
      final ui.Image out = await AnnotationFlattener.decodeImage(png);
      expect(out.width, 40);
      expect(out.height, 20);
    });
  });

  test('submit: 5MB 초과 평탄화 PNG 는 축소 후 업로드 — 확장자·MIME 이 함께 JPEG 로', () async {
    // 노이즈 PNG 는 압축이 안 돼 5MB 를 넘는다(불투명 → JPEG 재인코딩 대상).
    final Uint8List oversized = _noisePng(1500, 1250);
    expect(oversized.length, greaterThan(5 * 1024 * 1024),
        reason: '테스트 전제: 평탄화 결과가 §6-4 한도를 초과해야 한다');

    final _FakeUploader up = _FakeUploader();
    final ScanAnnotationRepository repo =
        ScanAnnotationRepository(docStore: _FakeDocStore(), uploader: up);

    await repo.submit(
      roomId: 'room-1',
      threadId: 'thread-1',
      document: _doc(),
      flattenedPng: oversized,
    );

    // §6-4 통과 + 파일명(.jpg)과 MIME(image/jpeg)이 '함께' 바뀐다(P2-20).
    expect(up.image, isNotNull);
    expect(up.image!.sizeBytes, lessThanOrEqualTo(5 * 1024 * 1024));
    expect(up.image!.fileName, 'annotation.jpg');
    expect(up.image!.mimeType, 'image/jpeg');
  });

  test('submit: 한도 이하 평탄화 PNG 는 바이트·이름·MIME 그대로 업로드', () async {
    final Uint8List small = _noisePng(60, 40);
    final _FakeUploader up = _FakeUploader();
    final ScanAnnotationRepository repo =
        ScanAnnotationRepository(docStore: _FakeDocStore(), uploader: up);

    await repo.submit(
      roomId: 'room-1',
      threadId: 'thread-1',
      document: _doc(),
      flattenedPng: small,
    );

    expect(up.image!.bytes, small);
    expect(up.image!.fileName, 'annotation.png');
    expect(up.image!.mimeType, 'image/png');
  });
}
