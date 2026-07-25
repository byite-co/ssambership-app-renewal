import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/scan/picked_image.dart';
import 'package:ssambership_app/core/scan/scan_source_picker.dart';
import 'package:ssambership_app/features/individual_question/data/iq_attachments_repository.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_create_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// S17 개별질문 첨부 — 경로 규약(순수 함수) + 작성 화면 첨부 흐름
/// (추가/삭제/최대 5장/부분 실패 재시도). 전부 fake 주입(DB·플러그인 비접촉).
class _FakeScanPort implements ScanSourcePort {
  int counter = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<PickedImage?> pick(ScanSource source) async {
    counter++;
    return PickedImage(
      bytes: Uint8List.fromList(List<int>.filled(32, counter)),
      fileName: 'scan$counter.png',
      mimeType: 'image/png',
    );
  }
}

/// 스크립트형 업로드 포트 — 파일명 단위로 실패를 지정하고, 재시도 시 해제 가능.
class _FakeIqAttachments implements IqAttachmentsPort {
  _FakeIqAttachments({Set<String>? failNames}) : failNames = failNames ?? {};

  Set<String> failNames;
  final List<String> uploaded = <String>[]; // 성공한 파일명 기록.
  final List<String> questionIds = <String>[];

  @override
  bool get isReady => true;

  @override
  Future<IqAttachment> upload({
    required String questionId,
    required PickedImage image,
    String? messageId,
    String? existingObjectPath,
  }) async {
    questionIds.add(questionId);
    if (failNames.contains(image.fileName)) {
      throw const AppError('업로드 실패');
    }
    uploaded.add(image.fileName);
    return IqAttachment(
      id: 'att-${uploaded.length}',
      storagePath: '$questionId/${image.fileName}',
      fileName: image.fileName,
      mimeType: image.mimeType,
    );
  }
}

IndividualQuestion _question() => IndividualQuestion(
      id: 'q-1',
      studentId: 's1',
      type: IndividualQuestionType.open,
      status: IndividualQuestionStatus.open,
      title: '수열 질문',
      body: '본문',
      priceCents: 500000,
      createdAt: DateTime(2026, 7, 1),
    );

Widget _screen({
  required _FakeScanPort scan,
  required _FakeIqAttachments attachments,
}) =>
    MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: IqCreateScreen(
        prefillOverride: () async =>
            const IqCreatePrefill(balanceCents: 10000000),
        submitOverride: ({
          required IndividualQuestionType type,
          required String title,
          required String body,
          int? amountCents,
          String? designatedMentorId,
          String? idempotencyKey,
        }) async =>
            _question(),
        scanPicker: scan,
        attachments: attachments,
      ),
    );

/// 시트를 열고 '촬영'으로 이미지 1장 추가.
Future<void> _addOne(WidgetTester tester) async {
  await tester.ensureVisible(find.text('사진 첨부'));
  await tester.tap(find.text('사진 첨부'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('촬영'));
  await tester.pumpAndSettle();
}

/// 폼 채우고 등록(확인 다이얼로그 포함).
Future<void> _fillAndSubmit(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, '질문 금액 (캐시)'), '5000');
  await tester.enterText(find.widgetWithText(TextField, '제목'), '제목이에요');
  await tester.enterText(find.widgetWithText(TextField, '질문 내용'), '내용이에요');
  // ensureVisible 은 상단 모서리만 걸치게 스크롤할 수 있어 추가로 끌어올린다.
  await tester.ensureVisible(find.text('질문 등록'));
  await tester.drag(find.byType(ListView), const Offset(0, -160));
  await tester.pumpAndSettle();
  await tester.tap(find.text('질문 등록'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('등록')); // 확인 다이얼로그.
  await tester.pumpAndSettle();
}

void main() {
  group('buildStoragePath (경로 규약 — 순수 함수)', () {
    test('첫 세그먼트 = 질문 uuid + ts-salt 파일명 + 확장자 정규화', () {
      final String path = SupabaseIqAttachmentsRepository.buildStoragePath(
        questionId: 'q-uuid-1',
        fileName: '문제 사진 (1).PNG',
        timestamp: 1234567890,
        salt: 0xABCDEF,
      );
      expect(path, 'q-uuid-1/1234567890-abcdef.png');
      expect(path.split('/').first, 'q-uuid-1'); // RPC·스토리지 RLS 규약.
    });

    test('확장자 없는 파일명은 bin 으로', () {
      expect(
        SupabaseIqAttachmentsRepository.buildStoragePath(
          questionId: 'q',
          fileName: 'noext',
          timestamp: 1,
          salt: 2,
        ),
        'q/1-000002.bin',
      );
    });
  });

  group('작성 화면 첨부 흐름', () {
    testWidgets('추가(1/5 썸네일) → 삭제(0/5)', (WidgetTester tester) async {
      final _FakeScanPort scan = _FakeScanPort();
      await tester
          .pumpWidget(_screen(scan: scan, attachments: _FakeIqAttachments()));
      await tester.pumpAndSettle();

      expect(find.text('문제 스캔 첨부 (0/5)'), findsOneWidget);
      await _addOne(tester);
      expect(find.text('문제 스캔 첨부 (1/5)'), findsOneWidget);

      await tester.ensureVisible(find.byIcon(Icons.close));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('문제 스캔 첨부 (0/5)'), findsOneWidget);
    });

    testWidgets('최대 5장 — 5장이면 추가 버튼 비활성(§6-1)', (WidgetTester tester) async {
      final _FakeScanPort scan = _FakeScanPort();
      await tester
          .pumpWidget(_screen(scan: scan, attachments: _FakeIqAttachments()));
      await tester.pumpAndSettle();

      for (int i = 0; i < 5; i++) {
        await _addOne(tester);
      }
      expect(find.text('문제 스캔 첨부 (5/5)'), findsOneWidget);
      final OutlinedButton btn =
          tester.widget(find.widgetWithText(OutlinedButton, '사진 첨부'));
      expect(btn.onPressed, isNull); // 상한 도달 → 비활성.
    });

    testWidgets('제출: 질문 생성 후 첨부가 질문 id 로 업로드되고 화면 종료',
        (WidgetTester tester) async {
      final _FakeScanPort scan = _FakeScanPort();
      final _FakeIqAttachments attachments = _FakeIqAttachments();
      await tester.pumpWidget(_screen(scan: scan, attachments: attachments));
      await tester.pumpAndSettle();

      await _addOne(tester);
      await _addOne(tester);
      await _fillAndSubmit(tester);

      expect(attachments.uploaded, <String>['scan1.png', 'scan2.png']);
      expect(attachments.questionIds.toSet(), <String>{'q-1'}); // 생성 후 업로드.
      expect(find.byType(IqCreateScreen), findsNothing); // pop 완료.
    });

    testWidgets('부분 실패: 질문은 유지 + 실패분만 재시도 → 성공 시 종료',
        (WidgetTester tester) async {
      final _FakeScanPort scan = _FakeScanPort();
      final _FakeIqAttachments attachments =
          _FakeIqAttachments(failNames: <String>{'scan2.png'});
      await tester.pumpWidget(_screen(scan: scan, attachments: attachments));
      await tester.pumpAndSettle();

      await _addOne(tester);
      await _addOne(tester);
      await _fillAndSubmit(tester);

      // 질문(텍스트)은 등록됨 — 화면은 남아 재시도 UI 로 전환(작업물 유실 금지).
      expect(find.byType(IqCreateScreen), findsOneWidget);
      expect(find.text('첨부 다시 업로드'), findsOneWidget);
      expect(find.text('첨부 없이 완료'), findsOneWidget);
      expect(find.text('문제 스캔 첨부 (1/5)'), findsOneWidget); // 실패분만 잔존.
      expect(attachments.uploaded, <String>['scan1.png']); // 성공분은 1회만.

      // 재시도(이번엔 성공) → 질문 재생성 없이 실패분만 업로드 후 종료.
      attachments.failNames = <String>{};
      await tester.ensureVisible(find.text('첨부 다시 업로드'));
      await tester.drag(find.byType(ListView), const Offset(0, -160));
      await tester.pumpAndSettle();
      await tester.tap(find.text('첨부 다시 업로드'));
      await tester.pumpAndSettle();

      expect(attachments.uploaded, <String>['scan1.png', 'scan2.png']);
      expect(find.byType(IqCreateScreen), findsNothing);
    });
  });
}
