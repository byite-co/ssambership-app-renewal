import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/scan/picked_image.dart';
import 'package:ssambership_app/core/scan/scan_source_picker.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/ui/chat_screen.dart';
import 'package:ssambership_app/features/question_room/ui/mentor/mentor_answer_screen.dart';
import 'package:ssambership_app/features/question_room/ui/widgets/chat_input_bar.dart';

/// [QA-C3] 멘토 답변 화면에서 이미지 첨부 시 주석 버튼이 나오지 않았다.
///
/// 원인은 위젯 버그가 아니라 **배선 누락**이다 — 학생 화면(chat_screen)에는
/// 전송 전 대기 이미지에 주석을 다는 경로(_annotatePending + onAnnotate 배선)가
/// 있는데, 멘토 답변 화면에는 그 심볼이 0건이었다. 부품(주석 화면·업로드)은
/// 공용이라 화면 배선만 빠져 있었다.
///
/// 두 화면을 **같은 단언으로** 검증한다 — 한쪽만 통과하던 상태가 결함이었으므로.
class _FakeScanPort implements ScanSourcePort {
  _FakeScanPort(this.result);

  final PickedImage result;

  @override
  bool get isAvailable => true;

  @override
  Future<PickedImage?> pick(ScanSource source) async => result;
}

PickedImage _img() => PickedImage(
      bytes: Uint8List.fromList(List<int>.filled(64, 7)),
      fileName: 'photo.png',
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

Future<void> _attach(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.attach_file));
  await tester.pumpAndSettle();
  await tester.tap(find.text('촬영'));
  await tester.pumpAndSettle();
  expect(find.textContaining('photo.png'), findsOneWidget); // 대기 슬롯 준비.
}

ChatInputBar _inputBar(WidgetTester tester) =>
    tester.widget<ChatInputBar>(find.byType(ChatInputBar));

void main() {
  testWidgets('멘토 답변 화면: 대기 이미지에 주석 경로가 배선돼 있다',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: MentorAnswerScreen(
        thread: _thread(),
        studentName: '로컬학생',
        scanPicker: _FakeScanPort(_img()),
      ),
    ));
    await tester.pump();
    await _attach(tester);

    expect(
      _inputBar(tester).onAnnotate,
      isNotNull,
      reason: '멘토도 전송 전 이미지에 주석을 달 수 있어야 한다(학생과 동일 경로)',
    );
  });

  testWidgets('학생 채팅 화면: 종전 배선이 그대로다(회귀 없음)',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: ChatScreen(
        thread: _thread(),
        mentorName: '김선생',
        scanPicker: _FakeScanPort(_img()),
      ),
    ));
    await tester.pump();
    await _attach(tester);

    expect(_inputBar(tester).onAnnotate, isNotNull);
  });
}
