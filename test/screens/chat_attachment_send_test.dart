import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/scan/scan_source_picker.dart';
import 'package:ssambership_app/features/question_room/data/attachments/attachment_upload.dart';
import 'package:ssambership_app/features/question_room/data/models/question_attachment.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/ui/chat_screen.dart';
import 'package:ssambership_app/features/question_room/ui/mentor/mentor_answer_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// P2-19 첨부 전송 UX: 성공 시에만 pending 정리, 실패는 삼키지 않고 노출.
/// 첨부만 보내는 경로(본문 없음)라 appendMessage(RPC)는 타지 않는다 — fake 업로더로 검증.
class _FakeScanPort implements ScanSourcePort {
  _FakeScanPort(this.result);

  final PickedImage result;

  @override
  bool get isAvailable => true;

  @override
  Future<PickedImage?> pick(ScanSource source) async => result;
}

class _FakeUploader implements AttachmentUploaderPort {
  _FakeUploader({this.error, this.answeredTransition = false});

  final Object? error;
  final bool answeredTransition;
  int calls = 0;

  @override
  bool get isReady => true;

  @override
  Future<AttachmentUploadResult> upload({
    required String roomId,
    required String threadId,
    String? messageId,
    required PickedImage image,
  }) async {
    calls += 1;
    final Object? e = error;
    if (e != null) throw e;
    return AttachmentUploadResult(
      attachment: QuestionAttachment(
        id: 'att-1',
        threadId: threadId,
        storagePath: '$roomId/$threadId/x.png',
        createdAt: DateTime(2026, 7, 1),
      ),
      answeredTransition: answeredTransition,
    );
  }
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
    isWrongAnswer: false,
    masteryStatus: MasteryStatus.unknown,
    createdAt: now,
    updatedAt: now,
  );
}

/// 첨부 미리보기 세팅(시트 → 촬영 → fake 픽커) 후 전송 탭.
Future<void> _attachAndSend(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.attach_file));
  await tester.pumpAndSettle();
  await tester.tap(find.text('촬영'));
  await tester.pumpAndSettle();
  expect(find.textContaining('photo.png'), findsOneWidget); // 미리보기 준비.
  await tester.tap(find.byIcon(Icons.send_rounded));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('학생 채팅: 첨부 업로드 실패 → pending 유지 + 실패 문구(전체 성공 위장 금지)',
      (WidgetTester tester) async {
    final _FakeUploader uploader =
        _FakeUploader(error: const AppError('첨부 파일을 등록하지 못했어요. 다시 시도해 주세요.'));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: ChatScreen(
        thread: _thread(),
        mentorName: '김선생',
        scanPicker: _FakeScanPort(_img()),
        uploader: uploader,
      ),
    ));
    await tester.pump();
    await _attachAndSend(tester);

    expect(uploader.calls, 1);
    expect(find.textContaining('이미지 첨부에 실패했어요'), findsOneWidget);
    // 실패한 첨부는 pending 미리보기에 그대로 남는다(재시도 가능).
    expect(find.textContaining('photo.png'), findsOneWidget);
  });

  testWidgets('학생 채팅: 첨부 업로드 성공 → pending 정리', (WidgetTester tester) async {
    final _FakeUploader uploader = _FakeUploader();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: ChatScreen(
        thread: _thread(),
        mentorName: '김선생',
        scanPicker: _FakeScanPort(_img()),
        uploader: uploader,
      ),
    ));
    await tester.pump();
    await _attachAndSend(tester);

    expect(uploader.calls, 1);
    expect(find.textContaining('photo.png'), findsNothing); // 성공 시에만 clear.
  });

  testWidgets('멘토 답변: 첫 첨부 answered 전이 신호 → 상태칩 "진행 중"(별도 UPDATE 없음)',
      (WidgetTester tester) async {
    final _FakeUploader uploader = _FakeUploader(answeredTransition: true);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: MentorAnswerScreen(
        thread: _thread(),
        studentName: '로컬학생',
        scanPicker: _FakeScanPort(_img()),
        uploader: uploader,
      ),
    ));
    await tester.pump();
    expect(find.text('답변 대기'), findsOneWidget);

    await _attachAndSend(tester);

    expect(uploader.calls, 1);
    expect(find.text('진행 중'), findsOneWidget); // 서버 전이 신호만 반영.
    expect(find.text('답변 대기'), findsNothing);
  });

  testWidgets('멘토 답변: 첨부 실패 → 상태 전이 없음 + pending 유지',
      (WidgetTester tester) async {
    final _FakeUploader uploader = _FakeUploader(error: const AppError('실패'));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: MentorAnswerScreen(
        thread: _thread(),
        studentName: '로컬학생',
        scanPicker: _FakeScanPort(_img()),
        uploader: uploader,
      ),
    ));
    await tester.pump();
    await _attachAndSend(tester);

    expect(find.text('답변 대기'), findsOneWidget); // 전이 없음.
    expect(find.textContaining('photo.png'), findsOneWidget);
  });
}
