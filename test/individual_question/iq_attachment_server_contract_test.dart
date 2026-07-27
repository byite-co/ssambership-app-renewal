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
        return parseIqAttachmentRegistration(next,
            requestedPath: path, expectedQuestionId: 'q-1');
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
        () => parseIqAttachmentRegistration('   ',
            requestedPath: 'q-1/a.png', expectedQuestionId: 'q-1'),
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
            requestedPath: 'q-1/a.png',
            expectedQuestionId: 'q-1'),
        throwsA(isA<AppError>().having((AppError e) => e.userMessage,
            'userMessage', kIqRegisterResultUnreadable)),
      );
      expect(
        () => parseIqAttachmentRegistration(42,
            requestedPath: 'q-1/a.png', expectedQuestionId: 'q-1'),
        throwsA(isA<AppError>().having((AppError e) => e.userMessage,
            'userMessage', kIqRegisterResultUnreadable)),
      );
    });

    test('파서: 형태별 idempotentContract 판정(String=false · Map=true)', () {
      final IqAttachmentRegistration legacy = parseIqAttachmentRegistration(
          'att-1',
          requestedPath: 'q-1/a.png',
          expectedQuestionId: 'q-1');
      expect(legacy.idempotentContract, isFalse);
      expect(legacy.needsCanonicalRefetch, isFalse);
      expect(legacy.storagePath, 'q-1/a.png');

      final IqAttachmentRegistration fresh = parseIqAttachmentRegistration(
          ok(status: kIqRegisterStatusExisting, idempotentHit: true),
          requestedPath: 'q-1/a.png',
          expectedQuestionId: 'q-1');
      expect(fresh.idempotentContract, isTrue);
      expect(fresh.idempotentHit, isTrue);
      expect(fresh.needsCanonicalRefetch, isTrue);
    });
  });

  // ────────── 파서 fail-closed(v22) — question_id · storage_path 대조 ──────────
  //
  // 168 성공 payload 는 question_id·storage_path 를 **항상** 채워 보낸다.
  // 그러므로 누락·불일치는 정상 계약이 아니라 응답 뒤바뀜·오라우팅 신호다.
  // 전 거부는 기존 kIqRegisterResultUnreadable 재사용(새 문구 0건).
  group('파서 fail-closed — 응답 귀속 대조', () {
    /// 168 성공 payload 원형. [extra] 로 개별 키를 덮어쓰거나(값 지정),
    /// [drop] 으로 키 자체를 제거해 '누락' 상황을 만든다.
    Map<String, dynamic> payload({
      Map<String, dynamic> extra = const <String, dynamic>{},
      List<String> drop = const <String>[],
    }) {
      final Map<String, dynamic> m = <String, dynamic>{
        'ok': true,
        'status': kIqRegisterStatusCreated,
        'idempotent_hit': false,
        'attachment_id': 'att-new',
        'question_id': 'q-1',
        'storage_path': 'q-1/1-abc.png',
        'message_id_mismatch': false,
        ...extra,
      };
      for (final String k in drop) {
        m.remove(k);
      }
      return m;
    }

    Matcher throwsUnreadable() => throwsA(isA<AppError>().having(
        (AppError e) => e.userMessage,
        'userMessage',
        kIqRegisterResultUnreadable));

    // ① question_id 가 다른 질문의 uuid — 응답 뒤바뀜/오라우팅.
    test('① question_id 불일치(다른 uuid) → 거부·성공 반환 0', () {
      IqAttachmentRegistration? returned;
      expect(
        () => returned = parseIqAttachmentRegistration(
          payload(extra: <String, dynamic>{'question_id': 'q-2'}),
          requestedPath: 'q-1/1-abc.png',
          expectedQuestionId: 'q-1',
        ),
        throwsUnreadable(),
      );
      expect(returned, isNull, reason: '거부된 응답으로 등록 결과를 만들지 않는다');
    });

    // ② 키 자체가 없다 — 168 은 항상 채우므로 누락이 곧 이상 신호다.
    test('② question_id 누락(null) → 거부', () {
      expect(
        () => parseIqAttachmentRegistration(
          payload(drop: <String>['question_id']),
          requestedPath: 'q-1/1-abc.png',
          expectedQuestionId: 'q-1',
        ),
        throwsUnreadable(),
      );
      // 명시적 null 도 동일하게 거부한다.
      expect(
        () => parseIqAttachmentRegistration(
          payload(extra: <String, dynamic>{'question_id': null}),
          requestedPath: 'q-1/1-abc.png',
          expectedQuestionId: 'q-1',
        ),
        throwsUnreadable(),
      );
    });

    // ③ 타입 오염 — 숫자로 오면 toString 비교로 통과시키지 않는다.
    test('③ question_id 가 비-String(정수) → 거부', () {
      expect(
        () => parseIqAttachmentRegistration(
          payload(extra: <String, dynamic>{'question_id': 1}),
          requestedPath: 'q-1/1-abc.png',
          expectedQuestionId: 'q-1',
        ),
        throwsUnreadable(),
      );
    });

    // ④ 폴백 제거의 핵심 — 예전이라면 requestedPath 로 조용히 성공했다.
    test('④ storage_path 누락 → 거부(requestedPath 폴백 0)', () {
      IqAttachmentRegistration? returned;
      expect(
        () => returned = parseIqAttachmentRegistration(
          payload(drop: <String>['storage_path']),
          requestedPath: 'q-1/1-abc.png',
          expectedQuestionId: 'q-1',
        ),
        throwsUnreadable(),
      );
      expect(returned, isNull,
          reason: '앱 추정 경로를 정본으로 승격하지 않는다 — 폴백 성공 0건');
    });

    // ⑤ 빈 문자열·공백도 '값 없음'과 같다.
    test('⑤ storage_path 가 빈 문자열/공백 → 거부', () {
      for (final String bad in <String>['', '   ']) {
        expect(
          () => parseIqAttachmentRegistration(
            payload(extra: <String, dynamic>{'storage_path': bad}),
            requestedPath: 'q-1/1-abc.png',
            expectedQuestionId: 'q-1',
          ),
          throwsUnreadable(),
          reason: 'storage_path=${bad.isEmpty ? '빈 문자열' : '공백'} 은 값 없음과 같다',
        );
      }
    });

    // ⑥ 자기모순 응답 — question_id 는 맞는데 경로가 다른 질문을 가리킨다.
    //    168 서버도 split_part(v_path,'/',1) <> p_question_id 로 막는 조합이라
    //    앱 검사는 순수 이중 방어다.
    test('⑥ question_id 일치 + storage_path 첫 세그먼트 불일치 → 거부', () {
      expect(
        () => parseIqAttachmentRegistration(
          payload(extra: <String, dynamic>{'storage_path': 'q-2/file.png'}),
          requestedPath: 'q-1/1-abc.png',
          expectedQuestionId: 'q-1',
        ),
        throwsUnreadable(),
      );
    });

    // ⑦ 정상 계약은 언제나 통과한다 + 서버 경로가 정본이다.
    //    ★ requestedPath 와의 **완전 일치는 요구하지 않는다** — 서버 정규화
    //      (현행 168 은 btrim)를 앱이 거부하면 정상 계약이 깨진다.
    test('⑦ 정상 Map(첫 세그먼트 일치) → 성공·서버 경로가 정본·완전 일치 불요', () {
      const String requested = '  q-1/normalized.png  '; // 앱이 보낸 원값
      final IqAttachmentRegistration r = parseIqAttachmentRegistration(
        payload(extra: <String, dynamic>{
          'storage_path': 'q-1/normalized.png', // 서버 btrim 결과
        }),
        requestedPath: requested,
        expectedQuestionId: 'q-1',
      );
      expect(r.idempotentContract, isTrue);
      expect(r.storagePath, 'q-1/normalized.png', reason: '서버 값이 경로 정본');
      expect(r.storagePath, isNot(requested),
          reason: 'requestedPath 와 달라도 통과 — 서버 정규화 여지를 남긴다');
      expect(r.attachmentId, 'att-new');
      expect(r.status, kIqRegisterStatusCreated);
      expect(r.needsCanonicalRefetch, isFalse);
    });

    // ⑧ 레거시(String) 분기 회귀 0 — 168 미적용 배포엔 question_id 가 없다.
    test('⑧ 레거시 String 반환 → 회귀 0(성공·앱 경로가 정본)', () {
      final IqAttachmentRegistration r = parseIqAttachmentRegistration(
        'att-legacy',
        requestedPath: 'q-1/1-abc.png',
        expectedQuestionId: 'q-1',
      );
      expect(r.attachmentId, 'att-legacy');
      expect(r.storagePath, 'q-1/1-abc.png', reason: '레거시는 앱 경로가 정본');
      expect(r.idempotentContract, isFalse);
      expect(r.needsCanonicalRefetch, isFalse);
      // expectedQuestionId 가 달라도 레거시 분기는 대조하지 않는다(무변경 증명).
      final IqAttachmentRegistration other = parseIqAttachmentRegistration(
        'att-legacy',
        requestedPath: 'q-1/1-abc.png',
        expectedQuestionId: 'q-9',
      );
      expect(other.attachmentId, 'att-legacy');
      expect(other.storagePath, 'q-1/1-abc.png');
    });

    // ⑨ 수렴 동작 불변 — 파서 거부는 AppError(≠PostgrestException)라
    //    코어의 모호 결과 경로를 타 SELECT 선행 확인으로 수렴한다.
    //    RPC 재호출 0·자동삭제 0 을 호출 카운터로 증명한다.
    test('⑨ 파서 거부 → 코어가 SELECT 선행 확인으로 성공 수렴(RPC 1회·삭제 0회)', () async {
      final _Harness h = _Harness(
        // question_id 가 뒤바뀐 응답 → 파서 거부 → 모호 결과 경로.
        registerResults: <Object?>[
          payload(extra: <String, dynamic>{'question_id': 'q-2'}),
        ],
        rows: <String, List<dynamic>>{
          'q-1/1-abc.png': _dbRows(path: 'q-1/1-abc.png'),
        },
      );
      final IqAttachment a = await h.run();
      expect(h.registers, 1, reason: '등록 RPC 재호출 0');
      expect(h.removes, 0, reason: '자동 삭제(보상삭제) 0');
      expect(h.finds, 1, reason: 'SELECT 선행 확인 1회');
      expect(a.id, 'att-db', reason: 'DB 행이 등록 정본');
    });
  });

  // ───────────────────────── 오류 코드 계약 ─────────────────────────
  group('168 오류 코드 계약 — 재시도 정책', () {
    // 168 성공 payload 는 question_id 를 **항상** 채운다 — 픽스처도 실계약과
    // 같은 형태여야 파서 fail-closed 검사를 정상 통과한다(기대값은 불변).
    Map<String, dynamic> okCreated() => <String, dynamic>{
          'ok': true,
          'status': kIqRegisterStatusCreated,
          'idempotent_hit': false,
          'attachment_id': 'att-new',
          'question_id': 'q-1',
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
