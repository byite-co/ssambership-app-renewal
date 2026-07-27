import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/scan/pdf_rasterizer.dart';
import 'package:ssambership_app/core/scan/picked_image.dart';
import 'package:ssambership_app/core/scan/scan_source_picker.dart';
import 'package:ssambership_app/core/scan/widgets/pdf_page_select_screen.dart';
import 'package:ssambership_app/core/scan/widgets/scan_pick_expander.dart';
import 'package:ssambership_app/features/individual_question/data/iq_attachments_repository.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_create_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// S19 PDF 스캔 — 수락 경로 전환·페이지 그리드(지연 렌더·선택 상한·슬롯
/// 연동)·페이지당 1첨부·열기 실패 폴백·0페이지 엣지. 전부 fake 래스터라이저
/// 주입(네이티브 렌더 비접촉 — 실렌더 화질은 실기기 QA 항목).
///
/// fake 는 페이지를 1x1 PNG 로 렌더한다(Image.memory 디코드 가능해야 함).
final Uint8List _kTinyPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG 시그니처
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, // IDAT
  0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
  0x0D, 0x0A, 0x2D, 0xB4,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND
  0xAE, 0x42, 0x60, 0x82,
]);

class _FakeHandle implements PdfDocumentHandle {
  _FakeHandle(this.pageCount);

  @override
  final int pageCount;

  /// (pageIndex, longSide) 호출 기록 — 지연 렌더·해상도 검증용.
  final List<(int, double)> renders = <(int, double)>[];
  bool closed = false;

  @override
  Future<Uint8List> renderPage(int pageIndex,
      {required double longSide}) async {
    renders.add((pageIndex, longSide));
    return _kTinyPng;
  }

  @override
  Future<void> close() async => closed = true;
}

class _FakeRasterizer implements PdfRasterizerPort {
  _FakeRasterizer({this.handle, this.error});

  final _FakeHandle? handle;
  final Object? error;
  int opens = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<PdfDocumentHandle> open(Uint8List bytes) async {
    opens++;
    if (error != null) throw error!;
    return handle!;
  }
}

class _FakeScanPort implements ScanSourcePort {
  _FakeScanPort(this.result);
  final PickedImage? result;

  @override
  bool get isAvailable => true;

  @override
  Future<PickedImage?> pick(ScanSource source) async => result;
}

class _FakeIqAttachments implements IqAttachmentsPort {
  final List<String> uploaded = <String>[];

  @override
  bool get isReady => true;

  @override
  Future<IqAttachment> upload({
    required String questionId,
    required PickedImage image,
    String? messageId,
    String? existingObjectPath,
  }) async {
    uploaded.add(image.fileName);
    return IqAttachment(id: 'a${uploaded.length}', storagePath: 'p');
  }
}

PickedImage _pdf(String name) => PickedImage(
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      fileName: name,
      mimeType: 'application/pdf',
    );

PickedImage _image(String name) => PickedImage(
      bytes: _kTinyPng,
      fileName: name,
      mimeType: 'image/png',
    );

Widget _iqCreate({
  required ScanSourcePort scan,
  required PdfRasterizerPort rasterizer,
  IqAttachmentsPort? attachments,
}) =>
    MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: IqCreateScreen(
        prefillOverride: () async =>
            const IqCreatePrefill(balanceCents: 10000000),
        scanPicker: scan,
        pdfRasterizer: rasterizer,
        attachments: attachments ?? _FakeIqAttachments(),
      ),
    );

/// 시트를 열고 '파일'로 선택 결과를 흘린다.
Future<void> _pickFile(WidgetTester tester) async {
  await tester.ensureVisible(find.text('사진 첨부'));
  await tester.tap(find.text('사진 첨부'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('파일'));
  await tester.pumpAndSettle();
}

void main() {
  group('expandScanPick (소스 계층 공통 — 화면 무분기 규약)', () {
    testWidgets('이미지는 그리드 없이 그대로 1장', (WidgetTester tester) async {
      final _FakeRasterizer rasterizer = _FakeRasterizer();
      late List<PickedImage> out;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async {
              out = await expandScanPick(context,
                  picked: _image('scan.png'),
                  rasterizer: rasterizer,
                  maxCount: 5);
            },
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(out.single.fileName, 'scan.png');
      expect(rasterizer.opens, 0); // 이미지 경로는 래스터라이저 비접촉.
    });

    testWidgets('1페이지 PDF 는 그리드 없이 본렌더 1장(장변 2560 규약)',
        (WidgetTester tester) async {
      final _FakeHandle handle = _FakeHandle(1);
      final _FakeRasterizer rasterizer = _FakeRasterizer(handle: handle);
      late List<PickedImage> out;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async {
              out = await expandScanPick(context,
                  picked: _pdf('워크북.pdf'), rasterizer: rasterizer, maxCount: 5);
            },
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(out.single.fileName, '워크북-p1.png');
      expect(out.single.mimeType, 'image/png');
      expect(handle.renders.single, (0, kPdfRenderLongSidePx));
      expect(handle.closed, isTrue); // 자원 해제.
      expect(find.byType(PdfPageSelectScreen), findsNothing);
    });

    testWidgets('0페이지 PDF → 열기 실패 폴백(AppError) + 핸들 해제',
        (WidgetTester tester) async {
      final _FakeHandle handle = _FakeHandle(0);
      final _FakeRasterizer rasterizer = _FakeRasterizer(handle: handle);
      Object? caught;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async {
              try {
                await expandScanPick(context,
                    picked: _pdf('빈.pdf'), rasterizer: rasterizer, maxCount: 5);
              } catch (e) {
                caught = e;
              }
            },
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(caught, isA<AppError>());
      expect((caught! as AppError).userMessage, kScanPdfOpenFailedText);
      expect(handle.closed, isTrue);
    });
  });

  group('IQ 작성 — PDF 수락 경로(화면은 PDF 를 모른다)', () {
    testWidgets('다중 페이지 PDF → 그리드 → 3페이지 선택 → 첨부 3장',
        (WidgetTester tester) async {
      final _FakeHandle handle = _FakeHandle(4);
      await tester.pumpWidget(_iqCreate(
        scan: _FakeScanPort(_pdf('문제집.pdf')),
        rasterizer: _FakeRasterizer(handle: handle),
      ));
      await tester.pumpAndSettle();

      await _pickFile(tester);
      expect(find.byType(PdfPageSelectScreen), findsOneWidget);
      expect(find.text('질문할 페이지 선택 (0/5)'), findsOneWidget); // 상한=min(5, 슬롯5).

      await tester.tap(find.text('1'));
      await tester.tap(find.text('2'));
      await tester.tap(find.text('4'));
      await tester.pump();
      expect(find.text('가져오기 (3)'), findsOneWidget);

      await tester.tap(find.text('가져오기 (3)'));
      await tester.pumpAndSettle();

      expect(find.byType(PdfPageSelectScreen), findsNothing);
      expect(find.text('문제 스캔 첨부 (3/5)'), findsOneWidget); // 페이지당 1첨부.
      // 본렌더는 선택 순서대로, 장변 2560 규약.
      final List<(int, double)> full = handle.renders
          .where(((int, double) r) => r.$2 == kPdfRenderLongSidePx)
          .toList();
      expect(full, <(int, double)>[
        (0, kPdfRenderLongSidePx),
        (1, kPdfRenderLongSidePx),
        (3, kPdfRenderLongSidePx),
      ]);
      expect(handle.closed, isTrue);
    });

    testWidgets('썸네일은 보이는 칸만 지연 렌더(50페이지 문제집 보호)', (WidgetTester tester) async {
      final _FakeHandle handle = _FakeHandle(50);
      await tester.pumpWidget(_iqCreate(
        scan: _FakeScanPort(_pdf('두꺼운문제집.pdf')),
        rasterizer: _FakeRasterizer(handle: handle),
      ));
      await tester.pumpAndSettle();
      await _pickFile(tester);

      final Iterable<(int, double)> thumbs = handle.renders
          .where(((int, double) r) => r.$2 == kPdfThumbLongSidePx);
      expect(thumbs.length, greaterThan(0));
      expect(thumbs.length, lessThan(50)); // 전 페이지 선렌더 금지.
    });

    testWidgets('선택 상한 초과 → 즉시 안내 + 선택 유지 안 됨', (WidgetTester tester) async {
      final _FakeHandle handle = _FakeHandle(8);
      await tester.pumpWidget(_iqCreate(
        scan: _FakeScanPort(_pdf('문제집.pdf')),
        rasterizer: _FakeRasterizer(handle: handle),
      ));
      await tester.pumpAndSettle();
      await _pickFile(tester);

      for (final String page in <String>['1', '2', '3', '4', '5', '6']) {
        await tester.tap(find.text(page));
        await tester.pump();
      }
      expect(find.text('페이지는 최대 5장까지 선택할 수 있어요.'), findsOneWidget);
      expect(find.text('가져오기 (5)'), findsOneWidget); // 6번째는 무시.
    });

    testWidgets('남은 슬롯 연동: 기존 4장이면 그리드 상한이 1', (WidgetTester tester) async {
      final _FakeHandle handle = _FakeHandle(3);
      final _MutableScanPort port = _MutableScanPort(_image('img.png'));
      await tester.pumpWidget(_iqCreate(
        scan: port,
        rasterizer: _FakeRasterizer(handle: handle),
      ));
      await tester.pumpAndSettle();

      for (int i = 0; i < 4; i++) {
        await _pickFile(tester); // 이미지 4장 채우기.
      }
      expect(find.text('문제 스캔 첨부 (4/5)'), findsOneWidget);

      port.result = _pdf('문제집.pdf'); // 5번째는 PDF.
      await _pickFile(tester);
      expect(find.text('질문할 페이지 선택 (0/1)'), findsOneWidget); // 슬롯 1 남음.

      await tester.tap(find.text('1'));
      await tester.tap(find.text('2')); // 상한 1 초과 → 안내.
      await tester.pump();
      expect(find.text('페이지는 최대 1장까지 선택할 수 있어요.'), findsOneWidget);

      await tester.tap(find.text('가져오기 (1)'));
      await tester.pumpAndSettle();
      expect(find.text('문제 스캔 첨부 (5/5)'), findsOneWidget);
    });

    testWidgets('암호화/손상 PDF → 폴백 문구 스낵바(§6-4)', (WidgetTester tester) async {
      await tester.pumpWidget(_iqCreate(
        scan: _FakeScanPort(_pdf('잠긴.pdf')),
        rasterizer:
            _FakeRasterizer(error: const AppError(kScanPdfOpenFailedText)),
      ));
      await tester.pumpAndSettle();
      await _pickFile(tester);

      expect(find.text(kScanPdfOpenFailedText), findsOneWidget);
      expect(find.text('문제 스캔 첨부 (0/5)'), findsOneWidget); // 첨부 없음.
    });

    testWidgets('그리드 취소(뒤로) → 무동작(첨부 0)', (WidgetTester tester) async {
      final _FakeHandle handle = _FakeHandle(3);
      await tester.pumpWidget(_iqCreate(
        scan: _FakeScanPort(_pdf('문제집.pdf')),
        rasterizer: _FakeRasterizer(handle: handle),
      ));
      await tester.pumpAndSettle();
      await _pickFile(tester);
      expect(find.byType(PdfPageSelectScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('문제 스캔 첨부 (0/5)'), findsOneWidget);
      expect(handle.closed, isTrue);
    });
  });
}

/// 호출마다 결과를 갈아끼울 수 있는 스캔 포트(슬롯 연동 시나리오용).
class _MutableScanPort implements ScanSourcePort {
  _MutableScanPort(this.result);
  PickedImage? result;

  @override
  bool get isAvailable => true;

  @override
  Future<PickedImage?> pick(ScanSource source) async => result;
}
