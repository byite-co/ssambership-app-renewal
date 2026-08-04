import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/core/scan/picked_image.dart';
import 'package:ssambership_app/core/scan/scan_source_picker.dart';
import 'package:ssambership_app/features/individual_question/data/individual_question_repository.dart';
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

  group('업로드 코어 — 보상삭제·모호 결과 SELECT 수렴(v18 보정1)', () {
    late int uploads;
    late int registers;
    late int removes;
    late int finds;

    const IqAttachment dbRow = IqAttachment(
      id: 'att-db',
      storagePath: 'q-1/1-abc.png',
      fileName: 'a.png',
      mimeType: 'image/png',
    );

    Future<IqAttachment> run({
      PickedImage? file,
      String? existingObjectPath,
      Object? registerError,
      Object? removeError,
      Object? uploadError,
      IqAttachment? found,
      Object? findError,
      List<dynamic>? foundRows,
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
          // ★ 이 그룹은 **레거시 계약(String 반환 = 168 미적용)** 전용이다.
          //   신규 jsonb 계약은 별도 그룹에서 다룬다(형태 혼합 금지).
          return parseIqAttachmentRegistration('att-1',
              requestedPath: path, expectedQuestionId: 'q-1');
        },
        removeObject: (String path) async {
          removes++;
          if (removeError != null) throw removeError;
        },
        findRegistered: (String path) async {
          finds++;
          if (findError != null) throw findError;
          if (foundRows != null) {
            // v20 정정2: 실제 canonical 검증을 finder 에 배선(레포와 동일 경로).
            return canonicalRegisteredAttachment(foundRows,
                questionId: 'q-1', objectPath: path);
          }
          return found;
        },
        // 실계약 미러: StateError = 서버 명시 거부(미등록 확정),
        // _Ambiguous = 전송·응답 계층 실패(성공 여부 미상).
        isDefiniteRegisterFailure: (Object e) => e is StateError,
      );
    }

    setUp(() {
      uploads = 0;
      registers = 0;
      removes = 0;
      finds = 0;
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

    test('명시적 등록 거부(미등록 확정) → SELECT 0회·보상삭제 1회', () async {
      await expectLater(run(registerError: StateError('rpc')),
          throwsA(isA<IqAttachmentRegisterFailure>()));
      expect(finds, 0); // 확정 거부엔 정본 확인 불요
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

    test('모호 결과 → RPC 재호출 0(총 1회)·SELECT 1회·행 확인 → DB 행으로 성공 수렴·삭제 0',
        () async {
      final IqAttachment a =
          await run(registerError: _Ambiguous(), found: dbRow);
      expect(registers, 1, reason: '재호출 0 — 최초 1회뿐');
      expect(finds, 1);
      expect(removes, 0, reason: '등록 행 확인 시 보상삭제 0');
      expect(a.id, 'att-db'); // 서버 DB 행이 등록 정본
    });

    test('모호 결과 + SELECT 정상·0건(미등록 확정) → 그때만 보상삭제 1회', () async {
      await expectLater(run(registerError: _Ambiguous(), found: null),
          throwsA(isA<IqAttachmentRegisterFailure>()));
      expect(finds, 1);
      expect(removes, 1);
    });

    test('모호 결과 + SELECT 실패 → AMBIGUOUS_SERVER_RESULT·자동삭제 0·성공 0', () async {
      Object? caught;
      try {
        await run(registerError: _Ambiguous(), findError: _Ambiguous());
      } catch (e) {
        caught = e;
      }
      final IqAttachmentAmbiguousResult a =
          caught! as IqAttachmentAmbiguousResult;
      expect(a.retryObjectPath, 'q-1/1-abc.png');
      expect(removes, 0);
      expect(a.message.contains('http'), isFalse);
    });

    test('수동 재시도: SELECT 선행 — 기존 행 확인 시 등록 RPC 0회 성공 수렴', () async {
      final IqAttachment a =
          await run(existingObjectPath: 'q-1/1-abc.png', found: dbRow);
      expect(finds, 1);
      expect(registers, 0, reason: 'SELECT 정본 확인이 RPC 보다 선행');
      expect(uploads, 0);
      expect(a.id, 'att-db');
    });

    test('수동 재시도: SELECT 정상·0건 확정 → 등록 RPC 1회(재업로드 0·중복 객체 0)', () async {
      final IqAttachment a =
          await run(existingObjectPath: 'q-1/1-abc.png', found: null);
      expect(finds, 1);
      expect(uploads, 0);
      expect(registers, 1);
      expect(a.storagePath, 'q-1/1-abc.png');
    });

    test('수동 재시도: SELECT 실패 → AMBIGUOUS·등록 RPC 0회', () async {
      await expectLater(
          run(existingObjectPath: 'q-1/1-abc.png', findError: _Ambiguous()),
          throwsA(isA<IqAttachmentAmbiguousResult>()));
      expect(registers, 0);
      expect(removes, 0);
    });

    test('성공: 업로드 1·등록 1·삭제 0·SELECT 0', () async {
      await run();
      expect(uploads, 1);
      expect(registers, 1);
      expect(removes, 0);
      expect(finds, 0);
    });

    test('v19 보정3: finder 가 비정상 행으로 throw → AMBIGUOUS·삭제 0·RPC 재호출 0',
        () async {
      // 모호 등록 오류 후 SELECT 가 손상 행으로 throw(canonical 검증 실패 모사).
      await expectLater(
          run(
              registerError: _Ambiguous(),
              findError: const FormatException('IQ_ATTACHMENT_ROW_BAD_ID')),
          throwsA(isA<IqAttachmentAmbiguousResult>()));
      expect(removes, 0, reason: '손상 행을 미등록 확정으로 오해석 금지');
      expect(registers, 1, reason: 'RPC 재호출 0');
    });

    // v20 정정2: question_id 키 자체가 없는 행 — projection 이 명시 선택하므로
    // 비정상 response shape. finder throw → AMBIGUOUS 수렴.
    List<dynamic> rowsWithoutQuestionKey() => <dynamic>[
          <String, dynamic>{
            'id': 'att-db',
            'storage_path': 'q-1/1-abc.png',
            'file_name': 'a.png',
            'mime_type': 'image/png',
          },
        ];

    test('v20 정정2: finder 행에 question_id 키 누락 → AMBIGUOUS·삭제 0·RPC 재호출 0',
        () async {
      await expectLater(
          run(registerError: _Ambiguous(), foundRows: rowsWithoutQuestionKey()),
          throwsA(isA<IqAttachmentAmbiguousResult>()));
      expect(removes, 0, reason: '키 누락 행을 미등록 확정으로 오해석 금지');
      expect(registers, 1, reason: '재호출 0 — 최초 1회뿐');
    });

    test('v20 정정2: 수동 재시도 SELECT 행에 question_id 키 누락 → 등록 RPC 0·삭제 0·AMBIGUOUS',
        () async {
      await expectLater(
          run(
              existingObjectPath: 'q-1/1-abc.png',
              foundRows: rowsWithoutQuestionKey()),
          throwsA(isA<IqAttachmentAmbiguousResult>()));
      expect(registers, 0, reason: '정본 미확정 상태에서 등록 RPC 금지');
      expect(removes, 0);
      expect(uploads, 0);
    });
  });

  group('v19 보정3 — canonicalRegisteredAttachment(0행 vs 비정상 행)', () {
    Map<String, dynamic> row({
      Object? id = 'att-1',
      Object? path = 'q-1/1.png',
      Object? question = 'q-1',
    }) =>
        <String, dynamic>{
          'id': id,
          'storage_path': path,
          'question_id': question,
          'file_name': 'a.png',
          'mime_type': 'image/png',
        };

    IqAttachment? call(List<dynamic> rows) =>
        canonicalRegisteredAttachment(rows,
            questionId: 'q-1', objectPath: 'q-1/1.png');

    test('실제 0행 → null(미등록 확정은 이 경우뿐)', () {
      expect(call(<dynamic>[]), isNull);
    });

    test('정상 행 → DB 행 정본 생성', () {
      final IqAttachment a = call(<dynamic>[row()])!;
      expect(a.id, 'att-1');
      expect(a.storagePath, 'q-1/1.png');
    });

    test('행 존재·id null → throw(AMBIGUOUS 수렴)', () {
      expect(() => call(<dynamic>[row(id: null)]), throwsFormatException);
    });

    test('행 존재·id 비문자·빈 문자열 → throw', () {
      expect(() => call(<dynamic>[row(id: 7)]), throwsFormatException);
      expect(() => call(<dynamic>[row(id: '  ')]), throwsFormatException);
    });

    test('행 존재·storage_path 불일치 → throw', () {
      expect(() => call(<dynamic>[row(path: 'q-1/other.png')]),
          throwsFormatException);
    });

    test('행 존재·question_id 불일치 → throw', () {
      expect(
          () => call(<dynamic>[row(question: 'q-2')]), throwsFormatException);
    });

    test('행 존재·비정상 shape(맵 아님) → throw', () {
      expect(() => call(<dynamic>['not-a-map']), throwsFormatException);
    });
  });

  group('v20 정정2 — question_id 는 필수 검증 필드(키 누락도 비정상 shape)', () {
    Map<String, dynamic> base() => <String, dynamic>{
          'id': 'att-1',
          'storage_path': 'q-1/1.png',
          'file_name': 'a.png',
          'mime_type': 'image/png',
        };

    IqAttachment? call(List<dynamic> rows) =>
        canonicalRegisteredAttachment(rows,
            questionId: 'q-1', objectPath: 'q-1/1.png');

    test('question_id 키 자체 누락 → throw(검증 생략 금지)', () {
      expect(() => call(<dynamic>[base()]), throwsFormatException);
    });

    test('question_id null → throw', () {
      expect(() => call(<dynamic>[base()..['question_id'] = null]),
          throwsFormatException);
    });

    test('question_id 비문자 → throw', () {
      expect(() => call(<dynamic>[base()..['question_id'] = 7]),
          throwsFormatException);
    });

    test('question_id 빈 문자열·공백 → throw', () {
      expect(() => call(<dynamic>[base()..['question_id'] = '']),
          throwsFormatException);
      expect(() => call(<dynamic>[base()..['question_id'] = '  ']),
          throwsFormatException);
    });

    test('question_id 불일치 → throw', () {
      expect(() => call(<dynamic>[base()..['question_id'] = 'q-2']),
          throwsFormatException);
    });

    test('question_id 정확 일치만 통과', () {
      final IqAttachment a = call(<dynamic>[base()..['question_id'] = 'q-1'])!;
      expect(a.id, 'att-1');
      expect(a.storagePath, 'q-1/1.png');
    });
  });

  group('멘토 첨부 UI(iq_detail) — §2-2 message_id 연결', () {
    IqDetailData data() => IqDetailData(
          question: IndividualQuestion(
            id: 'q-1',
            studentId: 's1',
            type: IndividualQuestionType.open,
            status: IndividualQuestionStatus.claimed,
            title: '수열 질문',
            body: '본문',
            priceCents: 500000,
            claimedMentorId: 'm1',
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
      List<(String, String)>? appendLog,
    }) =>
        MaterialApp(
          home: IqDetailScreen(
            questionId: 'q-1',
            loaderOverride: () async => data(),
            roleOverride: AppRole.mentor,
            repositoryOverride: _AppendRepo(appendLog ?? <(String, String)>[]),
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

    /// 답변 본문 입력 + 등록(확인 다이얼로그 포함) — 메시지 생성 경로.
    Future<void> submitAnswer(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField).first, '이렇게 풀어요');
      await tester.ensureVisible(find.text('답변 등록'));
      await tester.tap(find.text('답변 등록'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('답변 등록').last); // 확인 다이얼로그.
      await tester.pumpAndSettle();
    }

    testWidgets('갤러리 선택 → 대기열 추가·업로드 0 (message_id 없이 선등록 금지)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final _FakeSource source =
          _FakeSource(_file('풀이.png', 'image/png', _png()));
      final _FakeUploads uploads = _FakeUploads();
      await tester.pumpWidget(screen(source: source, uploads: uploads));
      await tester.pumpAndSettle();

      await pick(tester, '갤러리');
      expect(uploads.calls, 0); // 선택 시점 업로드 금지 — 대기열만.
      expect(find.text('풀이.png (64B)'), findsOneWidget);
    });

    testWidgets('답변 등록 → 메시지 생성 후 반환된 message_id 로 업로드·대기열 제거',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final _FakeSource source =
          _FakeSource(_file('풀이.png', 'image/png', _png()));
      final _FakeUploads uploads = _FakeUploads();
      final List<(String, String)> log = <(String, String)>[];
      await tester.pumpWidget(
          screen(source: source, uploads: uploads, appendLog: log));
      await tester.pumpAndSettle();

      await pick(tester, '갤러리');
      await submitAnswer(tester);

      expect(log, <(String, String)>[('q-1', '이렇게 풀어요')]); // 메시지 1회.
      expect(uploads.calls, 1);
      expect(uploads.lastMessageId, 'srv-msg-1'); // 반환 id 정본 — 조회 금지.
      expect(uploads.lastExistingPath, isNull);
      expect(find.text('풀이.png (64B)'), findsNothing); // 성공 → 대기열 제거
    });

    testWidgets('선택 취소(null) → 대기열 0·업로드 0·안전', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final _FakeSource source = _FakeSource(null);
      final _FakeUploads uploads = _FakeUploads();
      await tester.pumpWidget(screen(source: source, uploads: uploads));
      await tester.pumpAndSettle();
      await pick(tester, '촬영');
      expect(uploads.calls, 0);
      expect(find.textContaining('(64B)'), findsNothing);
    });

    testWidgets('허용 밖 파일(초과 크기) → 대기열 0 + 안내', (WidgetTester tester) async {
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

    testWidgets('등록 실패(고아) → 재시도 시 같은 경로 + 같은 message_id 재사용·메시지 재생성 0',
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
      final List<(String, String)> log = <(String, String)>[];
      await tester.pumpWidget(
          screen(source: source, uploads: uploads, appendLog: log));
      await tester.pumpAndSettle();

      await pick(tester, '갤러리');
      await submitAnswer(tester);
      expect(log.length, 1); // 메시지 1회 생성.
      expect(uploads.calls, 1);
      expect(find.textContaining('미정리 파일'), findsOneWidget);

      await tester.tap(find.text('재시도'));
      await tester.pumpAndSettle();
      expect(uploads.calls, 2);
      expect(uploads.lastExistingPath, 'q-1/keep-this.png'); // 경로 재사용
      expect(uploads.lastMessageId, 'srv-msg-1'); // 같은 message_id 유지
      expect(log.length, 1, reason: '첨부 재시도가 메시지를 다시 만들면 안 된다');
    });

    testWidgets('AMBIGUOUS_SERVER_RESULT — 성공 표시·임시 삽입 0, 재시도는 같은 경로 전달',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final _FakeSource source =
          _FakeSource(_file('풀이.png', 'image/png', _png()));
      final _FakeUploads uploads = _FakeUploads(
        failFirst: const IqAttachmentAmbiguousResult(
            retryObjectPath: 'q-1/ambiguous.png'),
      );
      final List<(String, String)> log = <(String, String)>[];
      await tester.pumpWidget(
          screen(source: source, uploads: uploads, appendLog: log));
      await tester.pumpAndSettle();

      await pick(tester, '갤러리');
      await submitAnswer(tester);
      expect(uploads.calls, 1);
      // 성공 표시·임시 성공 삽입 없음 — 대기열에 오류 상태로 남는다.
      expect(find.text('첨부를 등록했어요.'), findsNothing);
      expect(find.textContaining('등록 여부를 확인하지 못했어요'), findsOneWidget);

      // 수동 재시도 — 같은 경로가 전달돼 코어의 SELECT 선행 수렴을 밟는다.
      await tester.tap(find.text('재시도'));
      await tester.pumpAndSettle();
      expect(uploads.calls, 2);
      expect(uploads.lastExistingPath, 'q-1/ambiguous.png');
      expect(uploads.lastMessageId, 'srv-msg-1');
      expect(log.length, 1, reason: '첨부 재시도가 메시지를 다시 만들면 안 된다');
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

/// iq_append_message fake — 반환된 message_id 가 첨부 연결의 정본임을 검증.
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

  final Object? failFirst;
  int calls = 0;
  String? lastExistingPath;
  String? lastMessageId;

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
    lastMessageId = messageId;
    if (calls == 1 && failFirst != null) throw failFirst!;
    return IqAttachment(
      id: 'att-$calls',
      storagePath: existingObjectPath ?? 'q-1/new-$calls.png',
      fileName: image.fileName,
      mimeType: image.mimeType,
    );
  }
}

/// 전송·응답 계층 실패 흉내(서버 성공 여부 미상) — StateError(명시 거부)와 구분.
class _Ambiguous implements Exception {}

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
