import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/core/ink/ink_document.dart';
import 'package:ssambership_app/core/scan/picked_image.dart';
import 'package:ssambership_app/core/scan/scan_source_picker.dart';
import 'package:ssambership_app/features/individual_question/data/iq_annotation_repository.dart';
import 'package:ssambership_app/features/individual_question/data/iq_attachments_repository.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_create_screen.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_detail_screen.dart';
import 'package:ssambership_app/features/scan_annotation/annotation_target.dart';

/// S18 진입점 2곳의 화면 흐름 — 학생(전송 전 첨삭 = 첨부 대체·이어 그리기)과
/// 멘토(첨삭하기 노출·ink.json 분기·완료 후 새로고침). 전부 fake 주입.
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

class _FakeIqAttachments implements IqAttachmentsPort {
  final List<PickedImage> uploaded = <PickedImage>[];

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
    return IqAttachment(
      id: 'att-${uploaded.length}',
      storagePath: '$questionId/${image.fileName}',
      fileName: image.fileName,
      mimeType: image.mimeType,
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

IndividualQuestion _question() => IndividualQuestion(
      id: 'q-1',
      studentId: 's1',
      type: IndividualQuestionType.open,
      status: IndividualQuestionStatus.claimed,
      title: '수열 질문',
      body: '본문',
      priceCents: 500000,
      createdAt: DateTime(2026, 7, 1),
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
      expect(calls[1].$1.bytes, Uint8List.fromList(List<int>.filled(32, 1)));
      expect(identical(calls[1].$2, first), isTrue);
    });
  });

  group('멘토 · 상세 화면 첨삭하기', () {
    IqDetailData data() => IqDetailData(
          question: _question(),
          messages: const <IqMessage>[],
          attachments: const <IqAttachment>[
            IqAttachment(
              id: 'src-1',
              storagePath: 'q-1/1-000001.png',
              fileName: '문제.png',
              mimeType: 'image/png',
            ),
          ],
        );

    testWidgets('멘토에게만 첨삭하기가 보인다(학생은 비노출)', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(IqDetailScreen(
        questionId: 'q-1',
        roleOverride: AppRole.mentor,
        loaderOverride: () async => data(),
      )));
      await tester.pumpAndSettle();
      expect(find.text('첨삭하기'), findsOneWidget);

      await tester.pumpWidget(_wrap(IqDetailScreen(
        questionId: 'q-1',
        roleOverride: AppRole.student,
        loaderOverride: () async => data(),
      )));
      await tester.pumpAndSettle();
      expect(find.text('첨삭하기'), findsNothing);
    });

    testWidgets('기존 ink.json 없음 → 바로 새로 시작으로 진입, 완료 시 새로고침',
        (WidgetTester tester) async {
      final _FakeStore store = _FakeStore();
      int loads = 0;
      IqAnnotateRequest? request;

      await tester.pumpWidget(_wrap(IqDetailScreen(
        questionId: 'q-1',
        roleOverride: AppRole.mentor,
        loaderOverride: () async {
          loads++;
          return data();
        },
        annotationsOverride: IqAnnotationRepository(
            store: store, uploader: _FakeIqAttachments()),
        annotateLauncherOverride: (IqAnnotateRequest r) async {
          request = r;
          return true; // 전송됨.
        },
      )));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('첨삭하기'));
      await tester.tap(find.text('첨삭하기'));
      await tester.pumpAndSettle();

      expect(request, isNotNull);
      expect(request!.initial, isNull); // ink.json 없음 → 새로 시작.
      expect(request!.sourceAttachmentId, 'src-1');
      expect(request!.background, isNotEmpty);
      expect(loads, 2); // 완료(true) → 목록 새로고침.
      expect(find.text('첨삭본을 새 첨부로 등록했어요. 원본은 그대로 있어요.'), findsOneWidget);
    });

    testWidgets('기존 ink.json 있음 → 불러오기/새로 시작 선택 다이얼로그 분기',
        (WidgetTester tester) async {
      final _FakeStore store = _FakeStore();
      store.seedDocument('q-1/annotations/src-1.json', _doc(width: 77));
      final List<InkDocument?> initials = <InkDocument?>[];

      await tester.pumpWidget(_wrap(IqDetailScreen(
        questionId: 'q-1',
        roleOverride: AppRole.mentor,
        loaderOverride: () async => data(),
        annotationsOverride: IqAnnotationRepository(
            store: store, uploader: _FakeIqAttachments()),
        annotateLauncherOverride: (IqAnnotateRequest r) async {
          initials.add(r.initial);
          return null; // 취소로 닫힘(새 첨부 없음).
        },
      )));
      await tester.pumpAndSettle();

      // ① '불러오기' → 기존 스트로크로 이어 그리기.
      await tester.ensureVisible(find.text('첨삭하기'));
      await tester.tap(find.text('첨삭하기'));
      await tester.pumpAndSettle();
      expect(find.text('이전 첨삭이 있어요'), findsOneWidget);
      await tester.tap(find.text('불러오기'));
      await tester.pumpAndSettle();
      expect(initials.single, isNotNull);
      expect(initials.single!.canvasWidth, 77);

      // ② '새로 시작' → 빈 캔버스.
      await tester.ensureVisible(find.text('첨삭하기'));
      await tester.tap(find.text('첨삭하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('새로 시작'));
      await tester.pumpAndSettle();
      expect(initials.length, 2);
      expect(initials.last, isNull);
    });
  });
}

/// 상세 화면용 스토리지 fake — 시드 가능한 인메모리 오브젝트.
class _FakeStore implements IqAnnotationStore {
  final Map<String, Uint8List> objects = <String, Uint8List>{};

  void seedDocument(String path, InkDocument doc) {
    objects[path] = Uint8List.fromList(doc.toJsonString().codeUnits);
  }

  @override
  Future<void> upsertDocument({
    required String path,
    required Uint8List bytes,
  }) async {
    objects[path] = bytes;
  }

  @override
  Future<Uint8List?> downloadDocumentOrNull({required String path}) async =>
      objects[path];

  @override
  Future<Uint8List> downloadAttachment({required String storagePath}) async =>
      Uint8List.fromList(<int>[1, 2, 3]);
}
