import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/core/ink/ink_document.dart';
import 'package:ssambership_app/core/scan/picked_image.dart';
import 'package:ssambership_app/core/scan/scan_source_picker.dart';
import 'package:ssambership_app/features/individual_question/data/individual_question_repository.dart';
import 'package:ssambership_app/features/individual_question/data/iq_attachments_repository.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_create_screen.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_detail_screen.dart';
import 'package:ssambership_app/features/scan_annotation/annotation_target.dart';

/// S18·§4 첨삭 흐름 — 학생(전송 전 필기 = 첨부 대체·이어 그리기)과 멘토
/// (첨삭하기 노출·ink.json 분기·완료 = **대기 첨부 추가**, 즉시 등록 0,
/// 전송 시 멘토 message_id 로 연결). 전부 fake 주입.
class _FakeScanPort implements ScanSourcePort {
  int counter = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<PickedImage?> pick(ScanSource source) async {
    counter++;
    final Uint8List bytes = Uint8List.fromList(List<int>.filled(32, counter));
    bytes[0] = 0x89; // PNG 매직(정책 검증 통과)
    bytes[1] = 0x50;
    bytes[2] = 0x4E;
    bytes[3] = 0x47;
    return PickedImage(
      bytes: bytes,
      fileName: 'scan$counter.png',
      mimeType: 'image/png',
    );
  }
}

class _FakeIqAttachments implements IqAttachmentsPort {
  final List<PickedImage> uploaded = <PickedImage>[];
  final List<String?> messageIds = <String?>[];

  @override
  bool get isReady => true;

  @override
  Future<IqAttachment> upload({
    required String questionId,
    required PickedImage image,
    String? messageId,
    String? existingObjectPath,
  }) async {
    uploaded.add(image);
    messageIds.add(messageId);
    return IqAttachment(
      id: 'att-${uploaded.length}',
      storagePath: '$questionId/${image.fileName}',
      fileName: image.fileName,
      mimeType: image.mimeType,
    );
  }
}

class _AppendRepo extends IndividualQuestionRepository {
  const _AppendRepo(this.log);

  final List<(String, String)> log;

  @override
  Future<IqAppendResult> appendMessage(String questionId, String body) async {
    log.add((questionId, body));
    return IqAppendResult(
      messageId: 'srv-msg-${log.length}',
      answeredTransition: true,
    );
  }
}

InkDocument _doc({double width = 40}) => InkDocument(
      canvasWidth: width,
      canvasHeight: 20,
      sketch: <String, dynamic>{
        'lines': <Map<String, dynamic>>[
          <String, dynamic>{
            'points': <Map<String, dynamic>>[
              <String, dynamic>{'x': 0.1, 'y': 0.1},
            ],
            'color': 0xFFFF0000,
            'width': 0.01,
          },
        ],
      },
    );

Uint8List _flatPng([int fill = 200]) {
  final Uint8List b = Uint8List.fromList(List<int>.filled(64, fill));
  b[0] = 0x89;
  b[1] = 0x50;
  b[2] = 0x4E;
  b[3] = 0x47;
  return b;
}

IndividualQuestion _question({
  IndividualQuestionStatus status = IndividualQuestionStatus.claimed,
}) =>
    IndividualQuestion(
      id: 'q-1',
      studentId: 's1',
      type: IndividualQuestionType.open,
      status: status,
      title: '수열 질문',
      body: '본문',
      priceCents: 500000,
      claimedMentorId: 'm1',
      createdAt: DateTime(2026, 7, 1),
    );

/// 학생 작성 이미지 첨부(author_id 정본 — 첨삭 대상).
const IqAttachment _studentImage = IqAttachment(
  id: 'src-1',
  storagePath: 'q-1/1-000001.png',
  authorId: 's1',
  fileName: '문제.png',
  mimeType: 'image/png',
);

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: child,
    );

void main() {
  group('학생 · 작성 화면 필기하기(전송 전 로컬 첨삭)', () {
    /// 시트를 열고 '촬영'으로 이미지 1장 추가.
    Future<void> addOne(WidgetTester tester) async {
      await tester.ensureVisible(find.text('사진 첨부'));
      await tester.tap(find.text('사진 첨부'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('촬영'));
      await tester.pumpAndSettle();
    }

    Future<void> fillAndSubmit(WidgetTester tester) async {
      await tester.enterText(
          find.widgetWithText(TextField, '질문 금액 (캐시)'), '5000');
      await tester.enterText(find.widgetWithText(TextField, '제목'), '제목이에요');
      await tester.enterText(find.widgetWithText(TextField, '질문 내용'), '내용');
      await tester.ensureVisible(find.text('질문 등록'));
      await tester.drag(find.byType(ListView), const Offset(0, -160));
      await tester.pumpAndSettle();
      await tester.tap(find.text('질문 등록'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('등록'));
      await tester.pumpAndSettle();
    }

    testWidgets('필기 완료 → 평탄화본이 슬롯을 대체하고, 제출 시 대체본이 업로드된다',
        (WidgetTester tester) async {
      final _FakeIqAttachments attachments = _FakeIqAttachments();
      final Uint8List flat = Uint8List.fromList(List<int>.filled(16, 200));

      await tester.pumpWidget(_wrap(IqCreateScreen(
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
        scanPicker: _FakeScanPort(),
        attachments: attachments,
        annotateOverride:
            (PickedImage background, InkDocument? initial) async =>
                AnnotationResult(document: _doc(), flattenedPng: flat),
      )));
      await tester.pumpAndSettle();

      await addOne(tester);
      await tester.ensureVisible(find.byIcon(Icons.draw_rounded));
      await tester.tap(find.byIcon(Icons.draw_rounded));
      await tester.pumpAndSettle();

      await fillAndSubmit(tester);

      // 업로드된 것은 원본(scan1.png)이 아니라 평탄화 PNG(-ink 이름 규약).
      expect(attachments.uploaded.single.bytes, flat);
      expect(attachments.uploaded.single.fileName, 'scan1-ink.png');
      expect(attachments.uploaded.single.mimeType, 'image/png');
      expect(find.byType(IqCreateScreen), findsNothing); // 정상 종료.
    });

    testWidgets('재편집: 두 번째 필기하기는 원본 배경 + 직전 스트로크로 진입한다(이어 그리기)',
        (WidgetTester tester) async {
      final List<(PickedImage, InkDocument?)> calls =
          <(PickedImage, InkDocument?)>[];
      final InkDocument first = _doc(width: 111);

      await tester.pumpWidget(_wrap(IqCreateScreen(
        prefillOverride: () async =>
            const IqCreatePrefill(balanceCents: 10000000),
        scanPicker: _FakeScanPort(),
        attachments: _FakeIqAttachments(),
        annotateOverride: (PickedImage background, InkDocument? initial) async {
          calls.add((background, initial));
          return AnnotationResult(
            document: first,
            flattenedPng: Uint8List.fromList(List<int>.filled(16, 250)),
          );
        },
      )));
      await tester.pumpAndSettle();

      await addOne(tester);
      await tester.ensureVisible(find.byIcon(Icons.draw_rounded));
      await tester.tap(find.byIcon(Icons.draw_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.draw_rounded));
      await tester.pumpAndSettle();

      // 1회차: 원본 배경 + 스트로크 없음.
      expect(calls[0].$1.fileName, 'scan1.png');
      expect(calls[0].$2, isNull);
      // 2회차: 배경은 여전히 '원본'(평탄화본 위에 다시 그리지 않는다) +
      //         직전 스트로크 문서로 이어 그리기.
      expect(calls[1].$1.fileName, 'scan1.png');
      expect(calls[1].$1.bytes.sublist(4),
          Uint8List.fromList(List<int>.filled(32, 1)).sublist(4));
      expect(identical(calls[1].$2, first), isTrue);
    });
  });

  group('멘토 · 상세 화면 첨삭하기 — 폐쇄(2026-08)', () {
    // ★ 첨삭 기능이 제품에서 닫혀 있는 동안 진입 버튼을 노출하지 않는다
    //   (버튼만 남고 기능이 막힌 반쪽 상태 금지). 재개 시 _canAnnotateGroup
    //   게이트 원복과 함께 과거 흐름 테스트(git 이력 이 파일 2026-08 이전)를
    //   되살릴 것.
    IqDetailData data({
      IndividualQuestionStatus status = IndividualQuestionStatus.claimed,
      List<IqAttachment> attachments = const <IqAttachment>[_studentImage],
    }) =>
        IqDetailData(
          question: _question(status: status),
          messages: const <IqMessage>[],
          attachments: attachments,
        );

    testWidgets('멘토에게도 첨삭하기가 보이지 않는다(활성 상태·학생 첨부 포함)',
        (WidgetTester tester) async {
      for (final IndividualQuestionStatus status in <IndividualQuestionStatus>[
        IndividualQuestionStatus.claimed,
        IndividualQuestionStatus.answered,
      ]) {
        await tester.pumpWidget(_wrap(IqDetailScreen(
          questionId: 'q-1',
          roleOverride: AppRole.mentor,
          loaderOverride: () async => data(status: status),
        )));
        await tester.pumpAndSettle();
        expect(find.text('첨삭하기'), findsNothing, reason: '$status');
        // 조회·저장(다운로드)은 폐쇄와 무관하게 유지된다.
        expect(find.text('저장'), findsOneWidget, reason: '$status');
      }
    });

    testWidgets('학생에게도 첨삭하기 비노출(기존과 동일)', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(IqDetailScreen(
        questionId: 'q-1',
        roleOverride: AppRole.student,
        loaderOverride: () async => data(),
      )));
      await tester.pumpAndSettle();
      expect(find.text('첨삭하기'), findsNothing);
    });
  });

  group('학생 · 상세 화면 전송 전 필기(§4-2)', () {
    IqDetailData data() => IqDetailData(
          question: _question(status: IndividualQuestionStatus.answered),
          messages: const <IqMessage>[],
          attachments: const <IqAttachment>[],
        );

    testWidgets('첨부 선택 → 필기하기 → 평탄화본 대체 → 전송 시 학생 message_id 로 등록',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final _FakeIqAttachments uploads = _FakeIqAttachments();
      final List<(String, String)> appendLog = <(String, String)>[];
      final Uint8List flat = _flatPng(250);

      await tester.pumpWidget(_wrap(IqDetailScreen(
        questionId: 'q-1',
        roleOverride: AppRole.student,
        loaderOverride: () async => data(),
        repositoryOverride: _AppendRepo(appendLog),
        attachmentsOverride: uploads,
        sourcePickerOverride: _FakeScanPort(),
        pendingAnnotateOverride:
            (PickedImage background, InkDocument? initial) async =>
                AnnotationResult(document: _doc(), flattenedPng: flat),
      )));
      await tester.pumpAndSettle();

      // ① 첨부 선택(대기열 추가 — 업로드 0).
      await tester.tap(find.byTooltip('파일 첨부'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('갤러리'));
      await tester.pumpAndSettle();
      expect(uploads.uploaded, isEmpty);
      expect(find.textContaining('scan1.png'), findsOneWidget);

      // ② 전송 전 필기 → 평탄화본이 대기 항목을 대체.
      await tester.tap(find.byTooltip('필기하기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('scan1-ink.png'), findsOneWidget);
      expect(uploads.uploaded, isEmpty); // 여전히 업로드 0.

      // ③ 메시지 전송 → 반환된 message_id 로 등록.
      await tester.enterText(find.byType(TextField).first, '여기 다시 봐주세요');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(appendLog, <(String, String)>[('q-1', '여기 다시 봐주세요')]);
      expect(uploads.uploaded.single.bytes, flat);
      expect(uploads.uploaded.single.fileName, 'scan1-ink.png');
      expect(uploads.messageIds, <String?>['srv-msg-1']);
    });
  });
}
