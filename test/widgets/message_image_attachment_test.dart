import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/attachments/attachment_url_resolver.dart';
import 'package:ssambership_app/features/question_room/data/models/question_attachment.dart';
import 'package:ssambership_app/features/question_room/ui/widgets/message_image_attachment.dart';

/// 항상 같은(테스트) URL 을 돌려주는 fake 백엔드.
class _FakeBackend implements AttachmentUrlBackend {
  @override
  String? get currentUserId => userId;

  String? userId;

  @override
  Future<String> createSignedUrl(String storagePath, int expiresInSeconds) async =>
      'https://example.test/$storagePath';

  @override
  Future<Uint8List> download(String storagePath) async => Uint8List(0);
}

QuestionAttachment _att() => QuestionAttachment(
      id: 'a1',
      threadId: 't1',
      messageId: 'm1',
      storagePath: 'r1/t1/x.png',
      fileName: 'x.png',
      mimeType: 'image/png',
      createdAt: DateTime(2026, 7, 1),
    );

Widget _app(Widget child) => MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('렌더 + 네트워크 실패 시 플레이스홀더(깨진 이미지 아이콘)',
      (WidgetTester tester) async {
    final AttachmentUrlResolver resolver =
        AttachmentUrlResolver(_FakeBackend());

    await tester.pumpWidget(_app(MessageImageAttachment(
      attachment: _att(),
      resolver: resolver,
      onOpen: () {},
    )));
    await tester.pumpAndSettle();

    // 테스트 환경에선 실제 네트워크가 없어 errorBuilder → 플레이스홀더가 뜬다.
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byType(MessageImageAttachment), findsOneWidget);
  });

  testWidgets('탭하면 onOpen 콜백 호출', (WidgetTester tester) async {
    int opened = 0;
    final AttachmentUrlResolver resolver =
        AttachmentUrlResolver(_FakeBackend());

    await tester.pumpWidget(_app(MessageImageAttachment(
      attachment: _att(),
      resolver: resolver,
      onOpen: () => opened++,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MessageImageAttachment));
    await tester.pump();
    expect(opened, 1);
  });
}
