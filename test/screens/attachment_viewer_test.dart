import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/attachments/attachment_url_resolver.dart';
import 'package:ssambership_app/features/question_room/data/models/question_attachment.dart';
import 'package:ssambership_app/features/question_room/ui/attachment_viewer_screen.dart';

class _FakeBackend implements AttachmentUrlBackend {
  @override
  String? get currentUserId => userId;

  String? userId;

  @override
  Future<String> createSignedUrl(String storagePath, int expiresInSeconds) async =>
      'https://example.test/$storagePath';

  @override
  Future<Uint8List> download(String storagePath) async =>
      Uint8List.fromList(<int>[1, 2, 3]);
}

QuestionAttachment _att() => QuestionAttachment(
      id: 'a1',
      threadId: 't1',
      messageId: null,
      storagePath: 'r1/t1/x.png',
      fileName: 'x.png',
      mimeType: 'image/png',
      createdAt: DateTime(2026, 7, 1),
    );

Widget _app(Widget home) => MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: home,
    );

void main() {
  testWidgets('스모크: 전체화면 뷰어에 줌·팬 + 주석 달기 액션',
      (WidgetTester tester) async {
    final AttachmentUrlResolver resolver =
        AttachmentUrlResolver(_FakeBackend());

    await tester.pumpWidget(_app(AttachmentViewerScreen(
      attachment: _att(),
      roomId: 'r1',
      threadId: 't1',
      resolver: resolver,
    )));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('주석 달기'), findsOneWidget);
  });
}
