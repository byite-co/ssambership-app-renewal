import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'picked_image.dart';

/// 업로드 전 초과 이미지 축소(§6-4: "5MB 초과 스캔은 업로드 전 리사이즈").
///
/// [maxBytes] 이하면 원본 그대로. 초과면 장변을 [maxLongSide] 로 캡해
/// **JPEG(품질 85)** 로 재인코딩한다 — 사진류에서 PNG 재인코딩이 오히려
/// 팽창하던 S16 방식(dart:ui)을 package:image(순수 Dart)로 교체(S17).
/// 투명 픽셀이 있는 이미지만 PNG 를 유지한다(JPEG 는 알파를 잃는다).
/// 재인코딩 결과가 여전히 초과이거나 디코드 실패면 **원본을 그대로 반환**
/// — 하류의 validatePickedImage 가 기존 한글 문구로 거부한다(작업 유실 없이 안내).
///
/// ★ P3-5: decode/copyResize/encode(무거운 순수 Dart 작업)는 [compute] 로
///   별도 isolate 에서 수행한다 — 대형 사진에서 UI isolate 가 멈추지 않는다.
///   isolate 경계는 프리미티브 맵만 넘긴다(PickedImage 미전달).
Future<PickedImage> downscaleIfOversized(
  PickedImage image, {
  int maxBytes = 5 * 1024 * 1024,
  int maxLongSide = 2560,
}) async {
  if (image.sizeBytes <= maxBytes) return image;
  try {
    final Map<String, Object?>? out = await compute(
      _downscaleWorker,
      <String, Object?>{
        'bytes': image.bytes,
        'maxBytes': maxBytes,
        'maxLongSide': maxLongSide,
      },
      debugLabel: 'downscaleIfOversized',
    );
    if (out == null) return image; // 디코드 실패·축소로도 초과 → 하류 거부.

    // P2-20: 포맷이 바뀌면 파일명 확장자와 MIME 을 '함께' 맞춘다(불일치 금지).
    final bool keepPng = out['png']! as bool;
    return PickedImage(
      bytes: out['bytes']! as Uint8List,
      fileName: _withExt(image.fileName, keepPng ? 'png' : 'jpg'),
      mimeType: keepPng ? 'image/png' : 'image/jpeg',
    );
  } catch (_) {
    return image; // 어떤 실패든 원본 유지(하류 검증이 안내).
  }
}

/// 평탄화 배경 사전 축소(P2-20) — 주석 합성 전에 장변을 [maxLongSide] 로 캡한다.
///
/// 초대형 배경을 그대로 dart:ui 로 디코드해 합성하면 메모리 폭증(OOM)과
/// 한도 초과 평탄화 출력이 나온다 → 합성 '전에' 픽셀 크기만 줄인다.
/// 바이트 한도는 보지 않는다(합성 결과의 §6-4 바이트 규약은 기존
/// [downscaleIfOversized] 경로가 담당). 장변이 이미 한도 이하·디코드 실패·
/// 어떤 예외든 원본 바이트를 그대로 반환한다(작업 유실 없음).
Future<Uint8List> downscaleFlattenBackground(
  Uint8List bytes, {
  int maxLongSide = 2560,
}) async {
  try {
    final Map<String, Object?>? out = await compute(
      _downscaleWorker,
      <String, Object?>{
        'bytes': bytes,
        'maxBytes': null, // 배경 캡 모드 — 장변만 본다.
        'maxLongSide': maxLongSide,
      },
      debugLabel: 'downscaleFlattenBackground',
    );
    return out == null ? bytes : out['bytes']! as Uint8List;
  } catch (_) {
    return bytes; // 어떤 실패든 원본 유지.
  }
}

/// compute 진입점(P3-5) — 별도 isolate 에서 decode/resize/encode 를 수행한다.
///
/// 인자·반환 모두 프리미티브 맵(bytes/maxBytes/maxLongSide ↔ bytes/png)만 —
/// PickedImage 는 isolate 경계를 넘기지 않는다.
/// 반환 null = "원본 유지" 신호: ① 디코드 실패, ② maxBytes 지정 시 재인코딩
/// 후에도 초과, ③ maxBytes 미지정(배경 캡 모드)인데 장변이 이미 한도 이하.
Map<String, Object?>? _downscaleWorker(Map<String, Object?> args) {
  final Uint8List src = args['bytes']! as Uint8List;
  final int? maxBytes = args['maxBytes'] as int?;
  final int maxLongSide = args['maxLongSide']! as int;

  final img.Image? decoded = img.decodeImage(src);
  if (decoded == null) return null; // 미지원 포맷 — 하류 검증이 안내.

  final int longSide =
      decoded.width >= decoded.height ? decoded.width : decoded.height;
  if (maxBytes == null && longSide <= maxLongSide) {
    return null; // 배경 캡 모드: 이미 한도 이하 → 재인코딩 불필요.
  }

  final img.Image resized = longSide <= maxLongSide
      ? decoded
      : (decoded.width >= decoded.height
          ? img.copyResize(decoded, width: maxLongSide)
          : img.copyResize(decoded, height: maxLongSide));

  final bool keepPng = _hasTransparency(resized);
  final Uint8List bytes = keepPng
      ? Uint8List.fromList(img.encodePng(resized))
      : Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  if (maxBytes != null && bytes.length > maxBytes) {
    return null; // 축소로도 초과 → 하류 거부.
  }

  return <String, Object?>{'bytes': bytes, 'png': keepPng};
}

/// 알파 채널에 실제 투명 픽셀이 있는지(불투명 알파만이면 JPEG 로 충분).
bool _hasTransparency(img.Image image) {
  if (!image.hasAlpha) return false;
  for (final img.Pixel p in image) {
    if (p.a < p.maxChannelValue) return true;
  }
  return false;
}

String _withExt(String name, String ext) {
  final int dot = name.lastIndexOf('.');
  return dot <= 0 ? '$name.$ext' : '${name.substring(0, dot)}.$ext';
}
