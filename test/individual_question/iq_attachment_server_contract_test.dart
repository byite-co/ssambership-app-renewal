import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ssambership_app/core/scan/picked_image.dart';
import 'package:ssambership_app/features/individual_question/data/iq_attachment_upload_core.dart';
import 'package:ssambership_app/features/individual_question/data/iq_attachments_repository.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// SQL 168·169 서버 계약 배선 — **전환기 이중 형태 리더**(dual-shape reader).
///
/// 앱은 168 의 적용 시점을 모른 채 동작해야 한다. 그래서 서버에 "적용됐냐"고
/// 묻지 않고 **응답의 형태**(String=레거시 / Map=신규)로만 분기한다. 이 파일은
/// 두 형태를 각각 고정하고, 형태를 한 테스트 안에서 섞지 않는다.
///
/// fail-closed 의 핵심: 계약 형태는 그 호출의 응답에서만 읽는 1회성 값이라
/// 모호 결과(응답 없음)에서는 언제나 '알 수 없음' → 등록 RPC 재호출 0.

Uint8List _png([int size = 64]) {
  final Uint8List b = Uint8List(size);
  b[0] = 0x89;
  b[1] = 0x50;
  b[2] = 0x4E;
  b[3] = 0x47;
  return b;
}

PickedImage _file({String name = 'local.png'}) =>
    PickedImage(bytes: _png(), fileName: name, mimeType: 'image/png');

/// 전송·응답 계층 실패(서버 성공 여부 미상) — PostgrestException 이 아니다.
class _Timeout implements Exception {}

PostgrestException _pg(String code) =>
    PostgrestException(message: 'server says $code', code: code);

/// 코어 호출 하네스. [registerResults] 는 등록 RPC 호출 순서대로 소비된다
/// (값이면 그 raw 응답을 파서에 태우고, Exception 이면 던진다).
class _Harness {
  _Harness({
    required this.registerResults,
    this.rows = const <String, List<dynamic>>{},
    this.findError,
    this.removeError,
  });

  final List<Object?> registerResults;

  /// 앱이 만드는 경로(buildPath 결과). 서버 정규화 경로와 다를 수 있다.
  final String appPath = 'q-1/1-abc.png';

  /// storage_path → SELECT 응답 행들. 없는 키는 0건(미등록 확정).
  final Map<String, List<dynamic>> rows;
  final Object? findError;
  final Object? removeError;

  int registers = 0;
  int finds = 0;
  int removes = 0;
  int uploads = 0;
  final List<String> findPaths = <String>[];

  Future<IqAttachment> run({String? existingObjectPath, PickedImage? file}) {
    return uploadIqAttachmentCore(
      questionId: 'q-1',
      file: file ?? _file(),
      existingObjectPath: existingObjectPath,
      buildPath: () => appPath,
      uploadBinary: (String path, PickedImage f) async => uploads++,
      register: (String path, PickedImage f, String? m) async {
        final Object? next = registerResults[registers];
        registers++;
        if (next is Exception) throw next;
        // 레포와 동일한 파서를 태운다 — 형태 분기를 테스트가 흉내내지 않는다.
        return parseIqAttachmentRegistration(next, requestedPath: path);
      },
      removeObject: (String path) async {
        removes++;
        if (removeError != null) throw removeError!;
      },
      findRegistered: (String path) async {
        finds++;
        findPaths.add(path);
        if (findError != null) throw findError!;
        return canonicalRegisteredAttachment(
          rows[path] ?? const <dynamic>[],
          questionId: 'q-1',
          objectPath: path,
        );
      },
      // ★ 실 프로덕션 술어를 그대로 쓴다(미러 금지).
      isDefiniteRegisterFailure:
          SupabaseIqAttachmentsRepository.isDefiniteRegisterFailure,
      isRetriableRegisterConflict:
          SupabaseIqAttachmentsRepository.isRetriableRegisterConflict,
    );
  }
}

/// 서버 DB 행(SELECT 응답 모사) — file_name 을 로컬과 다르게 둘 수 있다.
List<dynamic> _dbRows({
  required String path,
  String id = 'att-db',
  String fileName = 'server-original.png',
  String? messageId,
}) =>
    <dynamic>[
      <String, dynamic>{
        'id': id,
        'question_id': 'q-1',
        'storage_path': path,
        'message_id': messageId,
        'file_name': fileName,
        'mime_type': 'image/png',
      },
    ];

void main() {
  // ───────────────────────── 레거시 계약(168 미적용) ─────────────────────────
  group('레거시 계약(String 반환) — 168 미적용 서버', () {
    test('레거시: 등록 성공 → 재조회 0회·앱 경로가 정본·로컬 메타 사용', () async {
      final _Harness h = _Harness(registerResults: <Object?>['att-legacy']);
      final IqAttachment a = await h.run();
      expect(h.registers, 1);
      expect(h.finds, 0, reason: '레거시 계약엔 멱등 히트 개념이 없다 — 재조회 없음');
      expect(h.removes, 0);
      expect(a.id, 'att-legacy');
      expect(a.storagePath, 'q-1/1-abc.png');
      expect(a.fileName, 'local.png');
    });

    test('레거시: 모호 결과(타임아웃) → 등록 RPC 재호출 0·SELECT 로만 수렴', () async {
      final _Harness h = _Harness(
        registerResults: <Object?>[_Timeout()],
        rows: <String, List<dynamic>>{
          'q-1/1-abc.png': _dbRows(path: 'q-1/1-abc.png'),
        },
      );
      final IqAttachment a = await h.run();
      expect(h.registers, 1, reason: '모호 결과에서 재호출 0');
      expect(h.finds, 1);
      expect(h.removes, 0);
      expect(a.id, 'att-db');
    });

    test('레거시: 빈 문자열 반환 → 기존 AppError 문구(사용자 노출 문구 불변)', () {
      expect(
        () => parseIqAttachmentRegistration('   ', requestedPath: 'q-1/a.png'),
        throwsA(isA<AppError>().having((AppError e) => e.userMessage,
            'userMessage', kIqRegisterResultUnreadable)),
      );
    });
  });

  // ───────────────────────── 신규 계약(168 적용) ─────────────────────────
  group('신규 계약(jsonb 반환) — 168 적용 서버', () {
    Map<String, dynamic> ok({
      String status = kIqRegisterStatusCreated,
      String path = 'q-1/1-abc.png',
      String id = 'att-new',
      bool idempotentHit = false,
      bool mismatch = false,
    }) =>
        <String, dynamic>{
          'ok': true,
          'status': status,
          'idempotent_hit': idempotentHit,
          'attachment_id': id,
          'question_id': 'q-1',
          'storage_path': path,
          'message_id_mismatch': mismatch,
        };

    test('created → 재조회 0회(RPC 1회로 끝)·서버 storage_path 를 정본으로 사용', () async {
      final _Harness h = _Harness(
        registerResults: <Object?>[ok(path: 'q-1/normalized.png')],
      );
      final IqAttachment a = await h.run();
      expect(h.registers, 1);
      expect(h.finds, 0, reason: 'created 는 방금 만든 행 — 재조회 금지');
      expect(a.id, 'att-new');
      expect(a.storagePath, 'q-1/normalized.png', reason: '서버 정규화 경로가 정본');
    });

    test('existing(멱등 히트) → SELECT 재조회 1회로 서버 정본 수렴 — 서버 file_name 이 이긴다',
        () async {
      final _Harness h = _Harness(
        registerResults: <Object?>[
          ok(status: kIqRegisterStatusExisting, idempotentHit: true),
        ],
        rows: <String, List<dynamic>>{
          'q-1/1-abc.png': _dbRows(
            path: 'q-1/1-abc.png',
            fileName: 'server-original.png',
          ),
        },
      );
      final IqAttachment a = await h.run(file: _file(name: 'local.png'));
      expect(h.finds, 1, reason: '멱등 히트는 재조회 1회로 서버 정본에 맞춘다');
      expect(h.registers, 1, reason: '재호출 0');
      expect(h.removes, 0);
      // ★ 로컬 값이 아니라 서버 행의 값이 최종 IqAttachment 에 반영된다.
      expect(a.fileName, 'server-original.png');
      expect(a.id, 'att-db');
    });

    test('existing → 재조회는 **서버가 돌려준 경로**로 한다(앱 경로 아님)', () async {
      final _Harness h = _Harness(
        registerResults: <Object?>[
          ok(status: kIqRegisterStatusExisting, path: 'q-1/normalized.png'),
        ],
        rows: <String, List<dynamic>>{
          'q-1/normalized.png': _dbRows(path: 'q-1/normalized.png'),
        },
      );
      final IqAttachment a = await h.run();
      expect(h.findPaths, <String>['q-1/normalized.png']);
      expect(a.storagePath, 'q-1/normalized.png');
    });

    test('existing + 재조회 0건 → AMBIGUOUS_SERVER_RESULT(보상삭제 0·재호출 0)', () async {
      Object? caught;
      final _Harness h = _Harness(
        registerResults: <Object?>[ok(status: kIqRegisterStatusExisting)],
        // rows 비움 → SELECT 정상·0건
      );
      try {
        await h.run();
      } catch (e) {
        caught = e;
      }
      final IqAttachmentAmbiguousResult a =
          caught! as IqAttachmentAmbiguousResult;
      expect(a.retryObjectPath, 'q-1/1-abc.png');
      expect(h.removes, 0, reason: '보상삭제 금지');
      expect(h.registers, 1, reason: 'RPC 재호출 금지');
    });

    test('existing + 재조회 실패 → AMBIGUOUS_SERVER_RESULT(보상삭제 0·재호출 0)', () async {
      final _Harness h = _Harness(
        registerResults: <Object?>[ok(status: kIqRegisterStatusExisting)],
        findError: _Timeout(),
      );
      await expectLater(h.run(), throwsA(isA<IqAttachmentAmbiguousResult>()));
      expect(h.removes, 0);
      expect(h.registers, 1);
    });

    test('message_id_mismatch=true → 오류 아님 + 재조회로 서버 정본 수렴', () async {
      final _Harness h = _Harness(
        registerResults: <Object?>[
          ok(status: kIqRegisterStatusExisting, mismatch: true),
        ],
        rows: <String, List<dynamic>>{
          'q-1/1-abc.png': _dbRows(
            path: 'q-1/1-abc.png',
            messageId: 'msg-first',
          ),
        },
      );
      final IqAttachment a = await h.run();
      expect(h.finds, 1);
      // 서버가 보존한 기존 행의 message_id 가 정본 — 이번 시도 값으로 덮지 않는다.
      expect(a.messageId, 'msg-first');
      expect(a.id, 'att-db');
    });

    test('created + message_id_mismatch=true 도 재조회로 수렴(로컬 값 표시 금지)', () async {
      final _Harness h = _Harness(
        registerResults: <Object?>[ok(mismatch: true)],
        rows: <String, List<dynamic>>{
          'q-1/1-abc.png':
              _dbRows(path: 'q-1/1-abc.png', messageId: 'msg-server'),
        },
      );
      final IqAttachment a = await h.run();
      expect(h.finds, 1);
      expect(a.messageId, 'msg-server');
    });

    test('신규 계약: 모호 결과(타임아웃) → 계약 형태와 무관하게 등록 RPC 재호출 0', () async {
      // 앞선 성공 응답이 jsonb 였더라도, 모호 결과 회차에는 응답 자체가 없어
      // 계약 형태를 알 수 없다 → 재호출 금지(fail-closed).
      final _Harness h = _Harness(
        registerResults: <Object?>[_Timeout()],
        rows: <String, List<dynamic>>{
          'q-1/1-abc.png': _dbRows(path: 'q-1/1-abc.png'),
        },
      );
      final IqAttachment a = await h.run();
      expect(h.registers, 1, reason: '재호출 0');
      expect(a.id, 'att-db');
    });

    test('ok!=true / 미지 형태 → 기존 AppError 문구 유지', () {
      expect(
        () => parseIqAttachmentRegistration(
            <String, dynamic>{'ok': false, 'attachment_id': 'x'},
            requestedPath: 'q-1/a.png'),
        throwsA(isA<AppError>().having((AppError e) => e.userMessage,
            'userMessage', kIqRegisterResultUnreadable)),
      );
      expect(
        () => parseIqAttachmentRegistration(42, requestedPath: 'q-1/a.png'),
        throwsA(isA<AppError>().having((AppError e) => e.userMessage,
            'userMessage', kIqRegisterResultUnreadable)),
      );
    });

    test('파서: 형태별 idempotentContract 판정(String=false · Map=true)', () {
      final IqAttachmentRegistration legacy =
          parseIqAttachmentRegistration('att-1', requestedPath: 'q-1/a.png');
      expect(legacy.idempotentContract, isFalse);
      expect(legacy.needsCanonicalRefetch, isFalse);
      expect(legacy.storagePath, 'q-1/a.png');

      final IqAttachmentRegistration fresh = parseIqAttachmentRegistration(
          ok(status: kIqRegisterStatusExisting, idempotentHit: true),
          requestedPath: 'q-1/a.png');
      expect(fresh.idempotentContract, isTrue);
      expect(fresh.idempotentHit, isTrue);
      expect(fresh.needsCanonicalRefetch, isTrue);
    });
  });

  // ───────────────────────── 오류 코드 계약 ─────────────────────────
  group('168 오류 코드 계약 — 재시도 정책', () {
    Map<String, dynamic> okCreated() => <String, dynamic>{
          'ok': true,
          'status': kIqRegisterStatusCreated,
          'idempotent_hit': false,
          'attachment_id': 'att-new',
          'storage_path': 'q-1/1-abc.png',
          'message_id_mismatch': false,
        };

    test('42P10(167 미적용) → 재시도 0·레거시 폴백 0·즉시 중단', () async {
      final _Harness h = _Harness(registerResults: <Object?>[_pg('42P10')]);
      await expectLater(h.run(), throwsA(isA<IqAttachmentRegisterFailure>()));
      expect(h.registers, 1, reason: '재시도 금지 — 배포 사고 신호를 은폐하지 않는다');
      expect(h.finds, 0, reason: 'INSERT 문 자체가 실패해 행 미생성 확정 — 재조회 불요(항상 0건)');
      expect(h.removes, 1, reason: '업로드 객체를 남기면 고아가 된다');
    });

    test('40001 REGISTER_CONFLICT_UNRESOLVED → 1회 재시도 후 성공', () async {
      final _Harness h = _Harness(
        registerResults: <Object?>[_pg('40001'), okCreated()],
      );
      final IqAttachment a = await h.run();
      expect(h.registers, 2, reason: '1회 재호출 허용');
      expect(h.removes, 0);
      expect(h.uploads, 1, reason: '재호출은 같은 경로 — 재업로드 0');
      expect(a.id, 'att-new');
    });

    test('40001 연속 2회 → 재시도는 1회에서 멈추고 확정 실패(총 2회 호출)', () async {
      final _Harness h = _Harness(
        registerResults: <Object?>[_pg('40001'), _pg('40001')],
      );
      await expectLater(h.run(), throwsA(isA<IqAttachmentRegisterFailure>()));
      expect(h.registers, 2, reason: '재호출은 정확히 1회만');
      expect(h.removes, 1);
    });

    test('42501 NOT_QUESTION_PARTY → 재시도 없이 실패', () async {
      final _Harness h = _Harness(registerResults: <Object?>[_pg('42501')]);
      await expectLater(h.run(), throwsA(isA<IqAttachmentRegisterFailure>()));
      expect(h.registers, 1);
      expect(h.removes, 1);
    });

    test('22023 INVALID_INPUT/STORAGE_PATH_MISMATCH → 재시도 없이 실패', () async {
      final _Harness h = _Harness(registerResults: <Object?>[_pg('22023')]);
      await expectLater(h.run(), throwsA(isA<IqAttachmentRegisterFailure>()));
      expect(h.registers, 1);
      expect(h.removes, 1);
    });

    test('프로덕션 술어: 42P10·42501·22023 은 확정 실패, 40001 만 재호출 대상', () {
      for (final String code in <String>['42P10', '42501', '22023', '40001']) {
        expect(
            SupabaseIqAttachmentsRepository.isDefiniteRegisterFailure(
                _pg(code)),
            isTrue,
            reason: '$code 는 응답이 도착한 명시 거부');
      }
      expect(
          SupabaseIqAttachmentsRepository.isRetriableRegisterConflict(
              _pg('40001')),
          isTrue);
      for (final String code in <String>['42P10', '42501', '22023']) {
        expect(
            SupabaseIqAttachmentsRepository.isRetriableRegisterConflict(
                _pg(code)),
            isFalse,
            reason: '$code 재호출 금지');
      }
      // 모호 결과(전송 계층 실패)는 어느 쪽도 아니다.
      expect(
          SupabaseIqAttachmentsRepository.isDefiniteRegisterFailure(_Timeout()),
          isFalse);
      expect(
          SupabaseIqAttachmentsRepository.isRetriableRegisterConflict(
              _Timeout()),
          isFalse);
    });
  });

  // ───────────────────────── 169(Storage DELETE) 관측 기반 분기 ────────────
  group('169 대응 — DELETE 정책 유무를 추측하지 않는다', () {
    test('DELETE 거부 + 등록 확인 → 성공 수렴(등록된 첨부는 삭제 불가가 정상)', () async {
      final _Harness h = _Harness(
        // 모호 결과 → SELECT 0건(미등록 확정) → 보상삭제 시도 → 거부 →
        // 재조회에서 등록 확인(경합으로 뒤늦게 보임) → 성공 수렴.
        registerResults: <Object?>[_Timeout()],
        removeError: _pg('42501'),
        rows: <String, List<dynamic>>{},
      );
      // 1회차 SELECT 는 0건, DELETE 거부 후 2회차 SELECT 에서 행이 보이도록
      // 응답을 바꾼다.
      final _MutableHarness m = _MutableHarness(h);
      final IqAttachment a = await m.runWithLateRow();
      expect(a.id, 'att-db');
      expect(m.inner.removes, 1);
    });

    test('DELETE 거부 + 미등록 확인 → 기존 고아 처리 유지(성공 표시 0·경로 보존)', () async {
      Object? caught;
      final _Harness h = _Harness(
        registerResults: <Object?>[_pg('42501')],
        removeError: _pg('42501'),
        rows: <String, List<dynamic>>{}, // 미등록
      );
      try {
        await h.run();
      } catch (e) {
        caught = e;
      }
      final IqAttachmentRegisterFailure f =
          caught! as IqAttachmentRegisterFailure;
      expect(f.orphaned, isTrue);
      expect(f.retryObjectPath, 'q-1/1-abc.png');
      expect(f.message, contains('미정리 파일'));
      expect(h.finds, 1, reason: 'DELETE 거부 후 등록 여부를 관측으로 확인');
    });

    test('DELETE 성공(169 미적용·미등록 객체) → 재조회 없이 기존 경로 유지', () async {
      final _Harness h = _Harness(registerResults: <Object?>[_pg('42501')]);
      await expectLater(h.run(), throwsA(isA<IqAttachmentRegisterFailure>()));
      expect(h.removes, 1);
      expect(h.finds, 0, reason: '삭제가 성공하면 추가 관측 불요');
    });
  });

  // ─────────────────── 구버전 앱 안전성(병렬 실행 전제) ───────────────────
  group('회귀 방지 — 구버전 앱이 168 적용 서버를 만나도 안전하다', () {
    test(
        'register 가 AppError(≠PostgrestException) + SELECT 1건 → removeObject 0·성공 수렴',
        () async {
      // 구버전 앱은 jsonb 를 String 으로 읽지 못해 AppError 를 던진다. 그것은
      // PostgrestException 이 아니므로 **모호 결과**로 분류되고, SELECT 선행
      // 확인이 서버가 실제로 등록한 행을 찾아 성공 수렴한다.
      // ★ 이 성질이 W3(서버)와 App-A3(앱)의 병렬 실행 전제다. 깨지면 즉시 보고.
      final _Harness h = _Harness(
        registerResults: <Object?>[const AppError(kIqRegisterResultUnreadable)],
        rows: <String, List<dynamic>>{
          'q-1/1-abc.png': _dbRows(path: 'q-1/1-abc.png'),
        },
      );
      final IqAttachment a = await h.run();
      expect(h.removes, 0, reason: '등록 성공한 객체를 지우면 안 된다');
      expect(h.registers, 1, reason: '모호 결과 — RPC 재호출 0');
      expect(h.finds, 1);
      expect(a.id, 'att-db');
    });
  });
}

/// DELETE 거부 후 **재조회 시점에** 행이 보이는 경우를 만들기 위한 얇은 래퍼.
/// (첫 SELECT 는 0건, 보상삭제 거부 뒤 두 번째 SELECT 에서 등록 확인.)
class _MutableHarness {
  _MutableHarness(this.inner);

  final _Harness inner;

  Future<IqAttachment> runWithLateRow() {
    int seen = 0;
    return uploadIqAttachmentCore(
      questionId: 'q-1',
      file: _file(),
      buildPath: () => inner.appPath,
      uploadBinary: (String path, PickedImage f) async => inner.uploads++,
      register: (String path, PickedImage f, String? m) async {
        inner.registers++;
        throw _Timeout();
      },
      removeObject: (String path) async {
        inner.removes++;
        throw _pg('42501'); // 169 정책이 등록 객체 DELETE 를 거부하는 모습
      },
      findRegistered: (String path) async {
        inner.finds++;
        seen++;
        if (seen == 1) return null; // 미등록 확정으로 보임 → 보상삭제 진입
        return canonicalRegisteredAttachment(
          _dbRows(path: path),
          questionId: 'q-1',
          objectPath: path,
        );
      },
      isDefiniteRegisterFailure:
          SupabaseIqAttachmentsRepository.isDefiniteRegisterFailure,
      isRetriableRegisterConflict:
          SupabaseIqAttachmentsRepository.isRetriableRegisterConflict,
    );
  }
}
