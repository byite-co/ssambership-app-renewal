import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as pkg;
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/scan/image_downscaler.dart';
import 'package:ssambership_app/core/scan/scan_source_picker.dart';
import 'package:ssambership_app/features/question_room/data/attachments/attachment_upload.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/ui/chat_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// S16 스캔 소스 흐름 — 바텀시트 3택 · 소스별 포트 호출 · PDF 거부 · 취소 무동작 ·
/// 초과 리사이즈. 전부 fake 포트 주입(플러그인·DB 비접촉).
class _FakeScanPort implements ScanSourcePort {
  _FakeScanPort({this.result, this.error});

  final PickedImage? result;
  final Object? error;
  final List<ScanSource> calls = <ScanSource>[];

  @override
  bool get isAvailable => true;

  @override
  Future<PickedImage?> pick(ScanSource source) async {
    calls.add(source);
    if (error != null) throw error!;
    return result;
  }
}

class _FakeGalleryPort implements ImagePickerPort {
  _FakeGalleryPort({this.result});

  final PickedImage? result;
  int calls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<PickedImage?> pickImage() async {
    calls++;
    return result;
  }
}

PickedImage _img(String name) => PickedImage(
      bytes: Uint8List.fromList(List<int>.filled(64, 7)),
      fileName: name,
      mimeType: 'image/png',
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

Widget _chat({ScanSourcePort? scan, ImagePickerPort? gallery}) => MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: ChatScreen(
        thread: _thread(),
        mentorName: '김선생',
        scanPicker: scan ?? _FakeScanPort(),
        imagePicker: gallery ?? _FakeGalleryPort(),
      ),
    );

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.attach_file));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('첨부 탭 → 바텀시트 3택(촬영·갤러리·파일) 렌더',
      (WidgetTester tester) async {
    await tester.pumpWidget(_chat());
    await tester.pump();
    await _openSheet(tester);

    expect(find.text('촬영'), findsOneWidget);
    expect(find.text('갤러리'), findsOneWidget);
    expect(find.text('파일'), findsOneWidget);
  });

  testWidgets('촬영 선택 → scanPicker.pick(camera) + 미리보기(파일명)',
      (WidgetTester tester) async {
    final _FakeScanPort scan = _FakeScanPort(result: _img('camera.png'));
    await tester.pumpWidget(_chat(scan: scan));
    await tester.pump();
    await _openSheet(tester);

    await tester.tap(find.text('촬영'));
    await tester.pumpAndSettle();

    expect(scan.calls, <ScanSource>[ScanSource.camera]);
    expect(find.textContaining('camera.png'), findsOneWidget); // 미리보기
  });

  testWidgets('파일 선택 → scanPicker.pick(file)', (WidgetTester tester) async {
    final _FakeScanPort scan = _FakeScanPort(result: _img('scan.png'));
    await tester.pumpWidget(_chat(scan: scan));
    await tester.pump();
    await _openSheet(tester);

    await tester.tap(find.text('파일'));
    await tester.pumpAndSettle();

    expect(scan.calls, <ScanSource>[ScanSource.file]);
    expect(find.textContaining('scan.png'), findsOneWidget);
  });

  testWidgets('갤러리 선택 → 기존 imagePicker 포트 호출(하위호환 주입 지점)',
      (WidgetTester tester) async {
    final _FakeScanPort scan = _FakeScanPort();
    final _FakeGalleryPort gallery = _FakeGalleryPort(result: _img('g.png'));
    await tester.pumpWidget(_chat(scan: scan, gallery: gallery));
    await tester.pump();
    await _openSheet(tester);

    await tester.tap(find.text('갤러리'));
    await tester.pumpAndSettle();

    expect(gallery.calls, 1);
    expect(scan.calls, isEmpty); // 갤러리는 scanPicker 를 타지 않는다.
    expect(find.textContaining('g.png'), findsOneWidget);
  });

  testWidgets('미지원 확장자 거부: AppError 폴백 안내가 원문 비노출 규약으로 표시',
      (WidgetTester tester) async {
    // S19 이후 PDF 는 지원 — 소스 포트의 '미지원 확장자' 일반 방어만 남는다.
    final _FakeScanPort scan = _FakeScanPort(
        error: const AppError('이미지(JPG·PNG·WEBP·HEIC)나 PDF 파일만 올릴 수 있어요.'));
    await tester.pumpWidget(_chat(scan: scan));
    await tester.pump();
    await _openSheet(tester);

    await tester.tap(find.text('파일'));
    await tester.pumpAndSettle();

    expect(find.text('이미지(JPG·PNG·WEBP·HEIC)나 PDF 파일만 올릴 수 있어요.'),
        findsOneWidget);
  });

  testWidgets('시트 취소(바깥 탭) → 아무 포트도 호출되지 않는다(무동작)',
      (WidgetTester tester) async {
    final _FakeScanPort scan = _FakeScanPort(result: _img('x.png'));
    final _FakeGalleryPort gallery = _FakeGalleryPort(result: _img('x.png'));
    await tester.pumpWidget(_chat(scan: scan, gallery: gallery));
    await tester.pump();
    await _openSheet(tester);

    await tester.tapAt(const Offset(10, 10)); // 바깥 탭으로 dismiss.
    await tester.pumpAndSettle();

    expect(scan.calls, isEmpty);
    expect(gallery.calls, 0);
    expect(find.textContaining('x.png'), findsNothing);
  });

  group('downscaleIfOversized (§6-4 초과 리사이즈 — S17: JPEG 재인코딩)', () {
    Uint8List opaquePng(int w, int h) {
      final pkg.Image im = pkg.Image(width: w, height: h);
      int seed = 42; // 결정적 LCG 노이즈 — PNG 압축이 안 먹혀 원본이 충분히 커진다.
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
          im.setPixelRgba(
              x, y, seed & 0xFF, (seed >> 8) & 0xFF, (seed >> 16) & 0xFF, 255);
        }
      }
      return Uint8List.fromList(pkg.encodePng(im));
    }

    Uint8List transparentPng(int w, int h) {
      final pkg.Image im = pkg.Image(width: w, height: h, numChannels: 4);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          im.setPixelRgba(x, y, 200, 40, 90, x.isEven ? 0 : 255); // 실제 투명 픽셀
        }
      }
      return Uint8List.fromList(pkg.encodePng(im));
    }

    test('초과 사진류 → 장변 캡 + JPEG(품질85) 재인코딩으로 한도 안', () async {
      final Uint8List big = opaquePng(400, 300);
      final PickedImage src = PickedImage(
          bytes: big, fileName: 'big.png', mimeType: 'image/png');
      final PickedImage out = await downscaleIfOversized(src,
          maxBytes: big.length - 1, maxLongSide: 40);

      expect(out.sizeBytes, lessThanOrEqualTo(big.length - 1));
      expect(out.mimeType, 'image/jpeg'); // 사진류(불투명)는 JPEG.
      expect(out.fileName, 'big.jpg');
      final pkg.Image? decoded = pkg.decodeImage(out.bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(40)); // 장변 캡 적용.
    });

    test('투명 픽셀이 있으면 PNG 유지(알파 보존)', () async {
      final Uint8List big = transparentPng(240, 200);
      final PickedImage src = PickedImage(
          bytes: big, fileName: 'sticker.png', mimeType: 'image/png');
      final PickedImage out = await downscaleIfOversized(src,
          maxBytes: big.length - 1, maxLongSide: 40);

      expect(out.mimeType, 'image/png');
      expect(out.fileName, 'sticker.png');
      final pkg.Image? decoded = pkg.decodeImage(out.bytes);
      expect(decoded!.width, lessThanOrEqualTo(40));
    });

    test('한도 이하면 원본 그대로(무손실 통과)', () async {
      final PickedImage src = _img('small.png');
      expect(identical(await downscaleIfOversized(src), src), isTrue);
    });

    test('디코드 불가 바이트는 원본 반환 → 하류 검증이 기존 문구로 거부', () async {
      final PickedImage bad = PickedImage(
        bytes: Uint8List.fromList(List<int>.filled(64, 1)),
        fileName: 'broken.jpg',
        mimeType: 'image/jpeg',
      );
      final PickedImage out =
          await downscaleIfOversized(bad, maxBytes: 10, maxLongSide: 40);
      expect(identical(out, bad), isTrue);
      expect(validatePickedImage(out), isNull); // 64B<5MB — 실전 하류 통과 예시.
    });
  });
}
