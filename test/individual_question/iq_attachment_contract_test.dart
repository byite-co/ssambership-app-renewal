import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/core/scan/picked_image.dart';
import 'package:ssambership_app/core/scan/scan_source_picker.dart';
import 'package:ssambership_app/features/individual_question/data/iq_attachment_policy.dart';
import 'package:ssambership_app/features/individual_question/data/iq_attachment_saver.dart';
import 'package:ssambership_app/features/individual_question/data/iq_attachment_upload_core.dart';
import 'package:ssambership_app/features/individual_question/data/iq_attachments_repository.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_detail_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// 세션1 §6 — IQ 첨부 계약: 정책(20MB·MIME allowlist·매직바이트), 보상삭제,
/// 재시도 중복 0, 멘토 첨부 UI(선택·취소·차단), 저장 액션.

Uint8List _png([int size = 64]) {
  final Uint8List b = Uint8List(size);
  b[0] = 0x89;
  b[1] = 0x50;
  b[2] = 0x4E;
  b[3] = 0x47;
  return b;
}

Uint8List _pdf([int size = 64]) {
  final Uint8List b = Uint8List(size);
  b[0] = 0x25;
  b[1] = 0x50;
  b[2] = 0x44;
  b[3] = 0x46;
  return b;
}

Uint8List _zip([int size = 64]) {
  final Uint8List b = Uint8List(size);
  b[0] = 0x50;
  b[1] = 0x4B;
  b[2] = 0x03;
  b[3] = 0x04;
  return b;
}

PickedImage _file(String name, String mime, Uint8List bytes) =>
    PickedImage(bytes: bytes, fileName: name, mimeType: mime);

void main() {
  group('정책(validateIqAttachmentFile) — 서버 버킷 계약 상한', () {
    test('허용: png·pdf·zip·docx(매직=PK) 통과', () {
      expect(validateIqAttachmentFile(_file('a.png', 'image/png', _png())),
          isNull);
      expect(
          validateIqAttachmentFile(_file('a.pdf', 'application/pdf', _pdf())),
          isNull);
      expect(
          validateIqAttachmentFile(_file('a.zip', 'application/zip', _zip())),
          isNull);
      expect(
          validateIqAttachmentFile(_file(
              'a.docx',
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
              _zip())),
          isNull);
    });

    test('차단: 비허용 MIME(text/plain 등)', () {
      expect(validateIqAttachmentFile(_file('a.txt', 'text/plain', _png())),
          isNotNull);
      expect(
          validateIqAttachmentFile(_file('a.json', 'application/json', _zip())),
          isNotNull); // json 은 첨삭 내부용 — 사용자 선택 미허용
    });

    test('차단: 20MB 초과(버킷 20971520 실측 상한)', () {
      final Uint8List big = _png(kIqAttachmentMaxBytes + 1);
      expect(validateIqAttachmentFile(_file('a.png', 'image/png', big)),
          isNotNull);
      expect(
          validateIqAttachmentFile(
              _file('ok.png', 'image/png', _png(kIqAttachmentMaxBytes))),
          isNull);
    });

    test('차단: 주장 MIME 과 매직 바이트 모순(파일명 신뢰 금지)', () {
      expect(validateIqAttachmentFile(_file('a.png', 'image/png', _pdf())),
          isNotNull);
      expect(
          validateIqAttachmentFile(_file('a.pdf', 'application/pdf', _png())),
          isNotNull);
    });

    test('차단: 빈 파일', () {
      expect(
          validateIqAttachmentFile(_file('a.png', 'image/png', Uint8List(0))),
          isNotNull);
    });
  });

  group('업로드 코어 — 보상삭제·재시도 멱등', () {
    late int uploads;
    late int registers;
    late int removes;

    Future<IqAttachment> run({
      PickedImage? file,
      String? existingObjectPath,
      Object? registerError,
      Object? removeError,
      Object? uploadError,
    }) {
      return uploadIqAttachmentCore(
        questionId: 'q-1',
        file: file ?? _file('a.png', 'image/png', _png()),
        existingObjectPath: existingObjectPath,
        buildPath: () => 'q-1/1-abc.png',
        uploadBinary: (String path, PickedImage f) async {
          uploads++;
          if (uploadError != null) throw uploadError;
        },
        register: (String path, PickedImage f, String? m) async {
          registers++;
          if (registerError != null) throw registerError;
          return 'att-1';
        },
        removeObject: (String path) async {
          removes++;
          if (removeError != null) throw removeError;
        },
      );
    }

    setUp(() {
      uploads = 0;
      registers = 0;
      removes = 0;
    });

    test('검증 실패 → 업로드 0·등록 0', () async {
      await expectLater(run(file: _file('a.txt', 'text/plain', _png())),
          throwsA(isA<AppError>()));
      expect(uploads, 0);
      expect(registers, 0);
    });

    test('업로드 실패 → 등록 0', () async {
      await expectLater(
          run(uploadError: StateError('net')), throwsA(isA<StateError>()));
      expect(registers, 0);
    });

    test('등록(RPC) 실패 → 보상삭제 1회, 성공 표시 없음', () async {
      await expectLater(run(registerError: StateError('rpc')),
          throwsA(isA<IqAttachmentRegisterFailure>()));
      expect(removes, 1);
    });

    test('보상삭제도 실패(IQA 버킷 DELETE 정책 부재) → 고아 보고 + 경로 보존', () async {
      Object? caught;
      try {
        await run(
            registerError: StateError('rpc'), removeError: StateError('rls'));
      } catch (e) {
        caught = e;
      }
      final IqAttachmentRegisterFailure f =
          caught! as IqAttachmentRegisterFailure;
      expect(f.orphaned, isTrue);
      expect(f.retryObjectPath, 'q-1/1-abc.png');
      expect(f.message, contains('미정리 파일'));
      expect(f.message.contains('http'), isFalse); // URL·토큰 미포함
    });

    test('재시도(existingObjectPath) → 재업로드 0·등록 1(중복 객체 0)', () async {
      final IqAttachment a = await run(existingObjectPath: 'q-1/1-abc.png');
      expect(uploads, 0);
      expect(registers, 1);
      expect(a.storagePath, 'q-1/1-abc.png');
      expect(a.id, 'att-1');
    });

    test('성공: 업로드 1·등록 1·삭제 0', () async {
      await run();
      expect(uploads, 1);
      expect(registers, 1);
      expect(removes, 0);
    });
  });

  group('멘토 첨부 UI(iq_detail)', () {
    IqDetailData data() => IqDetailData(
          question: IndividualQuestion(
            id: 'q-1',
            studentId: 's1',
            type: IndividualQuestionType.open,
            status: IndividualQuestionStatus.claimed,
            title: '수열 질문',
            body: '본문',
            priceCents: 500000,
            createdAt: DateTime(2026, 7, 1),
          ),
          messages: const <IqMessage>[],
          attachments: const <IqAttachment>[
            IqAttachment(
              id: 'src-1',
              storagePath: 'q-1/1-000001.bin',
              fileName: '자료.pdf',
              mimeType: 'application/pdf',
            ),
          ],
        );

    Widget screen({
      required _FakeSource source,
      required _FakeUploads uploads,
      _FakeSaver? saver,
    }) =>
        MaterialApp(
          home: IqDetailScreen(
            questionId: 'q-1',
            loaderOverride: () async => data(),
            roleOverride: AppRole.mentor,
            sourcePickerOverride: source,
            attachmentsOverride: uploads,
            fileSaverOverride: saver ?? _FakeSaver(),
          ),
        );

    Future<void> pick(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text('파일 첨부'));
      await tester.tap(find.text('파일 첨부'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('갤러리 선택 → 업로드 1회·성공 시 대기열 제거', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final _FakeSource source =
          _FakeSource(_file('풀이.png', 'image/png', _png()));
      final _FakeUploads uploads = _FakeUploads();
      await tester.pumpWidget(screen(source: source, uploads: uploads));
      await tester.pumpAndSettle();

      await pick(tester, '갤러리');
      expect(uploads.calls, 1);
      expect(uploads.lastExistingPath, isNull);
      expect(find.text('풀이.png (64B)'), findsNothing); // 성공 → 대기열 제거
    });

    testWidgets('선택 취소(null) → 업로드 0·안전', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final _FakeSource source = _FakeSource(null);
      final _FakeUploads uploads = _FakeUploads();
      await tester.pumpWidget(screen(source: source, uploads: uploads));
      await tester.pumpAndSettle();
      await pick(tester, '촬영');
      expect(uploads.calls, 0);
    });

    testWidgets('허용 밖 파일(초과 크기) → 업로드 0 + 안내', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final _FakeSource source = _FakeSource(
          _file('big.png', 'image/png', _png(kIqAttachmentMaxBytes + 1)));
      final _FakeUploads uploads = _FakeUploads();
      await tester.pumpWidget(screen(source: source, uploads: uploads));
      await tester.pumpAndSettle();
      await pick(tester, '파일');
      expect(uploads.calls, 0);
      expect(find.textContaining('20MB'), findsOneWidget);
    });

    testWidgets('등록 실패(고아) → 재시도 시 같은 경로 재사용(재업로드 0·중복 0)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final _FakeSource source =
          _FakeSource(_file('풀이.png', 'image/png', _png()));
      final _FakeUploads uploads = _FakeUploads(
        failFirst: const IqAttachmentRegisterFailure(
          message: '첨부 등록이 완료되지 않았어요. 다시 시도해 주세요. (미정리 파일 1건: 풀이.png)',
          orphaned: true,
          retryObjectPath: 'q-1/keep-this.png',
        ),
      );
      await tester.pumpWidget(screen(source: source, uploads: uploads));
      await tester.pumpAndSettle();

      await pick(tester, '갤러리');
      expect(uploads.calls, 1);
      expect(find.textContaining('미정리 파일'), findsOneWidget);

      await tester.tap(find.text('재시도'));
      await tester.pumpAndSettle();
      expect(uploads.calls, 2);
      expect(uploads.lastExistingPath, 'q-1/keep-this.png'); // 경로 재사용
    });

    testWidgets('저장 액션 — 당사자 저장 포트 호출(비이미지 행)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final _FakeSaver saver = _FakeSaver();
      await tester.pumpWidget(screen(
          source: _FakeSource(null), uploads: _FakeUploads(), saver: saver));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('저장'));
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(saver.calls, 1);
      expect(saver.lastFileName, '자료.pdf');
      expect(find.text('파일을 저장했어요.'), findsOneWidget);
    });
  });
}

class _FakeSource implements ScanSourcePort {
  _FakeSource(this.result);
  final PickedImage? result;

  @override
  bool get isAvailable => true;

  @override
  Future<PickedImage?> pick(ScanSource source) async => result;
}

class _FakeUploads implements IqAttachmentsPort {
  _FakeUploads({this.failFirst});

  final IqAttachmentRegisterFailure? failFirst;
  int calls = 0;
  String? lastExistingPath;

  @override
  bool get isReady => true;

  @override
  Future<IqAttachment> upload({
    required String questionId,
    required PickedImage image,
    String? messageId,
    String? existingObjectPath,
  }) async {
    calls++;
    lastExistingPath = existingObjectPath;
    if (calls == 1 && failFirst != null) throw failFirst!;
    return IqAttachment(
      id: 'att-$calls',
      storagePath: existingObjectPath ?? 'q-1/new-$calls.png',
      fileName: image.fileName,
      mimeType: image.mimeType,
    );
  }
}

class _FakeSaver implements IqAttachmentSaverPort {
  int calls = 0;
  String? lastFileName;

  @override
  Future<bool> save(
      {required String storagePath, required String fileName}) async {
    calls++;
    lastFileName = fileName;
    return true;
  }
}
