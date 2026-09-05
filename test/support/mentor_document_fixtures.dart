import 'dart:typed_data';

import 'package:ssambership_app/core/scan/picked_image.dart';

/// 매직바이트가 맞는 서류 픽스처(JPG/PNG/PDF) + 형식 밖(WEBP) + 20MB 초과.
PickedImage jpgDocument({String name = 'certificate.jpg', int size = 4096}) =>
    PickedImage(
      bytes: _withHeader(const <int>[0xFF, 0xD8, 0xFF, 0xE0], size),
      fileName: name,
      mimeType: 'image/jpeg',
    );

PickedImage pngDocument({String name = 'certificate.png'}) => PickedImage(
      bytes: _withHeader(
        const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        2048,
      ),
      fileName: name,
      mimeType: 'image/png',
    );

PickedImage pdfDocument({String name = 'enrollment.pdf'}) => PickedImage(
      bytes: _withHeader(const <int>[0x25, 0x50, 0x44, 0x46, 0x2D], 3 * 1024),
      fileName: name,
      mimeType: 'application/pdf',
    );

/// WEBP(RIFF) — 형식 밖.
PickedImage webpDocument() => PickedImage(
      bytes: _withHeader(const <int>[0x52, 0x49, 0x46, 0x46], 1024),
      fileName: 'photo.webp',
      mimeType: 'image/webp',
    );

/// 20MB + 1 바이트 JPG — 크기 초과.
PickedImage oversizedDocument() => PickedImage(
      bytes: _withHeader(
        const <int>[0xFF, 0xD8, 0xFF, 0xE0],
        20 * 1024 * 1024 + 1,
      ),
      fileName: 'huge.jpg',
      mimeType: 'image/jpeg',
    );

Uint8List _withHeader(List<int> header, int size) {
  final Uint8List bytes = Uint8List(size);
  bytes.setRange(0, header.length, header);
  return bytes;
}
