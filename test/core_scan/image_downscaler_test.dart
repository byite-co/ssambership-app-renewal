import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as pkg;
import 'package:ssambership_app/core/scan/image_downscaler.dart';
import 'package:ssambership_app/core/scan/picked_image.dart';

/// P3-5(compute 이관) + P2-20(MIME·확장자 일관성) — downscaleIfOversized 와
/// 평탄화 배경 사전 축소(downscaleFlattenBackground)의 계약 검증.
/// compute 는 실제 isolate 를 쓰지만 순수 함수라 test() 에서 그대로 await 한다.

/// 결정적 LCG 노이즈 불투명 이미지 — PNG 압축이 안 먹혀 원본이 충분히 커진다.
pkg.Image _noiseImage(int w, int h) {
  final pkg.Image im = pkg.Image(width: w, height: h);
  int seed = 42;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      im.setPixelRgba(
          x, y, seed & 0xFF, (seed >> 8) & 0xFF, (seed >> 16) & 0xFF, 255);
    }
  }
  return im;
}

Uint8List _opaquePng(int w, int h) =>
    Uint8List.fromList(pkg.encodePng(_noiseImage(w, h)));

Uint8List _jpeg(int w, int h) =>
    Uint8List.fromList(pkg.encodeJpg(_noiseImage(w, h), quality: 100));

Uint8List _transparentPng(int w, int h) {
  final pkg.Image im = pkg.Image(width: w, height: h, numChannels: 4);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      im.setPixelRgba(x, y, 200, 40, 90, x.isEven ? 0 : 255); // 실제 투명 픽셀.
    }
  }
  return Uint8List.fromList(pkg.encodePng(im));
}

void main() {
  group('downscaleIfOversized — compute 이관 후에도 기존 계약 유지(P3-5)', () {
    test('초과 JPEG → 장변 캡 + JPEG 재인코딩, MIME·확장자 일치(.jpg/image/jpeg)', () async {
      final Uint8List big = _jpeg(400, 300);
      final PickedImage src = PickedImage(
          bytes: big, fileName: 'photo.jpeg', mimeType: 'image/jpeg');
      final PickedImage out = await downscaleIfOversized(src,
          maxBytes: big.length - 1, maxLongSide: 40);

      expect(out.sizeBytes, lessThanOrEqualTo(big.length - 1));
      expect(out.mimeType, 'image/jpeg');
      expect(out.fileName, 'photo.jpg'); // 확장자와 MIME 이 함께 간다.
      final pkg.Image? decoded = pkg.decodeImage(out.bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(40)); // 장변 캡.
    });

    test('투명 픽셀 있는 PNG → PNG 유지(알파 보존), MIME 도 image/png 유지', () async {
      final Uint8List big = _transparentPng(240, 200);
      final PickedImage src = PickedImage(
          bytes: big, fileName: 'sticker.png', mimeType: 'image/png');
      final PickedImage out = await downscaleIfOversized(src,
          maxBytes: big.length - 1, maxLongSide: 40);

      expect(out.mimeType, 'image/png');
      expect(out.fileName, 'sticker.png');
      final pkg.Image? decoded = pkg.decodeImage(out.bytes);
      expect(decoded!.width, lessThanOrEqualTo(40));
    });

    test('불투명 PNG → JPEG 전환, 확장자(.jpg)와 MIME(image/jpeg) 둘 다 변경(P2-20)',
        () async {
      final Uint8List big = _opaquePng(300, 240);
      final PickedImage src =
          PickedImage(bytes: big, fileName: 'scan.png', mimeType: 'image/png');
      final PickedImage out = await downscaleIfOversized(src,
          maxBytes: big.length - 1, maxLongSide: 60);

      expect(out.fileName, 'scan.jpg');
      expect(out.mimeType, 'image/jpeg');
      expect(out.sizeBytes, lessThanOrEqualTo(big.length - 1));
    });

    test('한도(기본 5MB) 이하면 원본 그대로 — 동일 인스턴스 통과', () async {
      final Uint8List small = _opaquePng(20, 20); // 5MB 에 한참 못 미친다.
      final PickedImage src = PickedImage(
          bytes: small, fileName: 'small.png', mimeType: 'image/png');
      expect(identical(await downscaleIfOversized(src), src), isTrue);
    });

    test('경계: 정확히 maxBytes 면 원본 유지, 1 바이트 초과부터 축소(5MB 경계 규약)', () async {
      final Uint8List bytes = _opaquePng(200, 160);
      final PickedImage src = PickedImage(
          bytes: bytes, fileName: 'edge.png', mimeType: 'image/png');

      // == maxBytes → 초과 아님(원본 인스턴스 그대로).
      final PickedImage same =
          await downscaleIfOversized(src, maxBytes: bytes.length);
      expect(identical(same, src), isTrue);

      // maxBytes 보다 1 바이트 큼 → 축소 경로 진입(JPEG 재인코딩).
      final PickedImage out = await downscaleIfOversized(src,
          maxBytes: bytes.length - 1, maxLongSide: 50);
      expect(identical(out, src), isFalse);
      expect(out.mimeType, 'image/jpeg');
      expect(out.fileName, 'edge.jpg');
    });

    test('디코드 불가 바이트 → 원본 반환(하류 검증이 안내)', () async {
      final PickedImage bad = PickedImage(
        bytes: Uint8List.fromList(List<int>.filled(64, 1)),
        fileName: 'broken.jpg',
        mimeType: 'image/jpeg',
      );
      final PickedImage out =
          await downscaleIfOversized(bad, maxBytes: 10, maxLongSide: 40);
      expect(identical(out, bad), isTrue);
    });

    test('축소해도 maxBytes 초과면 원본 반환(하류 거부 위임)', () async {
      final Uint8List big = _opaquePng(300, 240);
      final PickedImage src =
          PickedImage(bytes: big, fileName: 'huge.png', mimeType: 'image/png');
      // 한도 10B — 어떤 재인코딩도 못 맞춘다 → 원본 유지.
      final PickedImage out =
          await downscaleIfOversized(src, maxBytes: 10, maxLongSide: 40);
      expect(identical(out, src), isTrue);
    });
  });

  group('downscaleFlattenBackground — 평탄화 배경 장변 캡(P2-20)', () {
    test('장변 초과 배경 → maxLongSide 로 축소(바이트 한도와 무관)', () async {
      final Uint8List big = _opaquePng(200, 100);
      final Uint8List out =
          await downscaleFlattenBackground(big, maxLongSide: 40);

      final pkg.Image? decoded = pkg.decodeImage(out);
      expect(decoded, isNotNull);
      expect(decoded!.width, 40); // 장변(가로) 캡.
      expect(decoded.height, 20); // 비율 유지.
    });

    test('투명 배경은 PNG 로 재인코딩돼 알파가 보존된다', () async {
      final Uint8List big = _transparentPng(120, 60);
      final Uint8List out =
          await downscaleFlattenBackground(big, maxLongSide: 40);

      final pkg.Image? decoded = pkg.decodeImage(out);
      expect(decoded!.hasAlpha, isTrue);
      expect(decoded.width, 40);
    });

    test('장변이 이미 한도 이하면 원본 바이트 그대로', () async {
      final Uint8List small = _opaquePng(30, 20);
      final Uint8List out =
          await downscaleFlattenBackground(small, maxLongSide: 40);
      expect(identical(out, small), isTrue); // 재인코딩 없이 통과.
    });

    test('디코드 불가 바이트는 원본 그대로(예외 없이)', () async {
      final Uint8List bad = Uint8List.fromList(List<int>.filled(64, 7));
      final Uint8List out =
          await downscaleFlattenBackground(bad, maxLongSide: 40);
      expect(identical(out, bad), isTrue);
    });
  });
}
