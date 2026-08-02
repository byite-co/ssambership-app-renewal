import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/attachments/attachment_upload.dart';
import 'package:ssambership_app/features/question_room/ui/widgets/chat_input_bar.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('첨부 버튼 탭 → onAttach 콜백 연결', (WidgetTester tester) async {
    int attach = 0;
    await tester.pumpWidget(_wrap(ChatInputBar(
      controller: TextEditingController(),
      hintText: '메시지 입력',
      sending: false,
      onSend: () {},
      onAttach: () => attach++,
    )));
    await tester.tap(find.byIcon(Icons.attach_file));
    await tester.pump();
    expect(attach, 1);
  });

  testWidgets('전송 버튼 탭 → onSend 콜백', (WidgetTester tester) async {
    int send = 0;
    await tester.pumpWidget(_wrap(ChatInputBar(
      controller: TextEditingController(),
      hintText: '메시지 입력',
      sending: false,
      onSend: () => send++,
      onAttach: () {},
    )));
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(send, 1);
  });

  testWidgets('선택 이미지 → 미리보기(파일명)·업로드 제한문구·제거 버튼',
      (WidgetTester tester) async {
    int removed = 0;
    final PickedImage img = PickedImage(
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      fileName: '문제사진.png',
      mimeType: 'image/png',
    );
    await tester.pumpWidget(_wrap(ChatInputBar(
      controller: TextEditingController(),
      hintText: '메시지 입력',
      sending: false,
      onSend: () {},
      onAttach: () {},
      pendingImage: img,
      onRemovePending: () => removed++,
    )));
    await tester.pump();

    expect(find.text('문제사진.png'), findsOneWidget);
    expect(find.textContaining('저작권'), findsOneWidget); // 업로드 제한 문구
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(removed, 1);
  });

  testWidgets('전송 중이면 전송 버튼 비활성(onSend 미호출)',
      (WidgetTester tester) async {
    int send = 0;
    await tester.pumpWidget(_wrap(ChatInputBar(
      controller: TextEditingController(),
      hintText: '메시지 입력',
      sending: true,
      onSend: () => send++,
      onAttach: () {},
    )));
    await tester.tap(find.byIcon(Icons.send_rounded), warnIfMissed: false);
    await tester.pump();
    expect(send, 0);
  });

  // S3-E §6: 차단한 상대의 질문방은 읽기 전용 — composer 만 꺼진다.
  testWidgets('enabled=false + 안내문구 → 입력·첨부·전송 위젯 자체가 사라진다',
      (WidgetTester tester) async {
    int send = 0;
    int attach = 0;
    await tester.pumpWidget(_wrap(ChatInputBar(
      controller: TextEditingController(),
      hintText: '메시지 입력',
      sending: false,
      onSend: () => send++,
      onAttach: () => attach++,
      enabled: false,
      disabledNotice: '차단한 사용자예요.',
    )));

    expect(find.text('차단한 사용자예요.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.send_rounded), findsNothing);
    expect(find.byIcon(Icons.attach_file), findsNothing);
    expect(send, 0);
    expect(attach, 0);
  });

  testWidgets('enabled=false(안내문구 없음) → 버튼·입력창 비활성(콜백 미호출)',
      (WidgetTester tester) async {
    int send = 0;
    int attach = 0;
    await tester.pumpWidget(_wrap(ChatInputBar(
      controller: TextEditingController(),
      hintText: '메시지 입력',
      sending: false,
      onSend: () => send++,
      onAttach: () => attach++,
      enabled: false,
    )));

    await tester.tap(find.byIcon(Icons.send_rounded), warnIfMissed: false);
    await tester.tap(find.byIcon(Icons.attach_file), warnIfMissed: false);
    await tester.pump();
    expect(send, 0);
    expect(attach, 0);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });
}
