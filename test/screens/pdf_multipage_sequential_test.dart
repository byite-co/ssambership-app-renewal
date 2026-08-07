import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/scan/picked_image.dart';
import 'package:ssambership_app/core/scan/pdf_rasterizer.dart';
import 'package:ssambership_app/core/scan/scan_source_picker.dart';
import 'package:ssambership_app/features/question_room/data/attachments/attachment_upload.dart';
import 'package:ssambership_app/features/question_room/data/models/question_attachment.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/ui/chat_screen.dart';

/// [QA-B5] 여러 페이지 PDF 를 골라도 1장만 첨부됐다.
///
/// 미구현이 아니라 파이프라인(PDF 열기 → 페이지 그리드 → List 반환)은 이미
/// 있었고, 채팅 첨부가 expandScanPick(maxCount: 1) 로 호출해 그리드가 1장으로
/// 제한될 뿐이었다. 오너 판단 2026-08-07: **순차 자동 전송**.
///   첫 장 → 기존 미리보기 슬롯(주석·본문 동봉 그대로)
///   나머지 → 한 장씩 이어서 전송
class _FakeScanPort implements ScanSourcePort {
  _FakeScanPort(this.result);

  final PickedImage result;

  @override
  bool get isAvailable => true;

  @override
  Future<PickedImage?> pick(ScanSource source) async => result;
}

/// 페이지 수를 지정할 수 있는 가짜 PDF — 그리드 없이 렌더되는 1페이지와,
/// 그리드를 띄우는 다중 페이지를 모두 만들 수 있다.
class _FakeRasterizer implements PdfRasterizerPort {
  _FakeRasterizer(this.pages);

  final int pages;

  @override
  bool get isAvailable => true;

  @override
  Future<PdfDocumentHandle> open(Uint8List bytes) async =>
      _FakeDocument(pages);
}

class _FakeDocument implements PdfDocumentHandle {
  _FakeDocument(this.pageCount);

  @override
  final int pageCount;

  @override
  Future<Uint8List> renderPage(int pageIndex, {required double longSide}) async =>
      Uint8List.fromList(List<int>.filled(64, pageIndex + 1));

  @override
  Future<void> close() async {}
}

class _RecordingUploader implements AttachmentUploaderPort {
  final List<String> uploaded = <String>[];

  @override
  bool get isReady => true;

  @override
  Future<AttachmentUploadResult> upload({
    required String roomId,
    required String threadId,
    String? messageId,
    required PickedImage image,
  }) async {
    uploaded.add(image.fileName);
    return AttachmentUploadResult(
      attachment: QuestionAttachment(
        id: 'att-${uploaded.length}',
        threadId: threadId,
        storagePath: '$roomId/$threadId/${uploaded.length}.png',
        createdAt: DateTime(2026, 7, 1),
      ),
      answeredTransition: false,
    );
  }
}

PickedImage _pdf() => PickedImage(
      bytes: Uint8List.fromList(List<int>.filled(64, 7)),
      fileName: 'note.pdf',
      mimeType: 'application/pdf',
    );

QuestionThread _thread() {
  final DateTime now = DateTime(2026, 7, 1);
  return QuestionThread(
    id: 't1',
    roomId: 'r1',
    title: '미분 질문',
    status: ThreadStatus.pending,
    masteryStatus: MasteryStatus.unknown,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pump(WidgetTester tester, _RecordingUploader uploader,
    _FakeRasterizer rasterizer) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: ChatScreen(
      thread: _thread(),
      mentorName: '김선생',
      scanPicker: _FakeScanPort(_pdf()),
      uploader: uploader,
      pdfRasterizer: rasterizer,
    ),
  ));
  await tester.pump();
  await tester.tap(find.byIcon(Icons.attach_file));
  await tester.pumpAndSettle();
  await tester.tap(find.text('파일'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('1페이지 PDF: 종전대로 미리보기 슬롯에만 올라간다(전송 없음)',
      (WidgetTester tester) async {
    final _RecordingUploader uploader = _RecordingUploader();
    await _pump(tester, uploader, _FakeRasterizer(1));

    expect(uploader.uploaded, isEmpty, reason: '첫 장은 전송이 아니라 미리보기다');
    expect(find.textContaining('note-p1.png'), findsOneWidget);
  });
}
