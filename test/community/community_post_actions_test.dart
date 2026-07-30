import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/community_post_actions.dart';
import 'package:ssambership_app/features/community/data/community_post_envelope.dart';
import 'package:ssambership_app/features/community/data/community_post_images.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// F4/F5/F6 오케스트레이터 계약(앱 계약 v1.1 §3.3·§6.3·§6.6) — Gate 4 단위 고정.
///
/// 핵심 고정 대상:
/// - F4 재호출 전 Storage DELETE 0회(replay-first — T-CONC-10 의 앱 코드 계약)
/// - 응답 불명확 시 같은 멱등키 재호출·새 키 금지
/// - 보상 삭제 4분기(업로드 실패/확정 실패/불명확/성공)
/// - author_id·author_role·author_label 미전송(서버 auth.uid 도출)

class _FakeStorage implements CommunityPostImageBackend {
  final List<String> uploaded = <String>[];
  final List<List<String>> removeCalls = <List<String>>[];
  int failUploadAtIndex = -1; // n번째 업로드에서 throw
  bool failRemove = false;
  int _uploads = 0;

  @override
  Future<void> uploadObject({
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (_uploads == failUploadAtIndex) {
      _uploads++;
      throw Exception('upload failed');
    }
    _uploads++;
    uploaded.add(objectPath);
  }

  @override
  Future<void> removeObjects(List<String> objectPaths) async {
    removeCalls.add(List<String>.of(objectPaths));
    if (failRemove) throw Exception('remove failed');
  }

  @override
  Future<String> createSignedUrl(String objectPath, int ttlSeconds) async =>
      'https://signed.example/$objectPath?ttl=$ttlSeconds';
}

ValidatedPostImage _img([int n = 1]) {
  // 유효 PNG magic bytes.
  final Uint8List bytes = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, n,
  ]);
  return ValidatedPostImage(
      bytes: bytes, contentType: 'image/png', ext: 'png', safeName: 'img$n');
}

typedef _Responder = Future<Object?> Function(Map<String, dynamic> params);

class _RpcLog {
  final List<Map<String, dynamic>> calls = <Map<String, dynamic>>[];
  late List<_Responder> script;
  int _i = 0;

  Future<Object?> call(Map<String, dynamic> params) {
    calls.add(Map<String, dynamic>.of(params));
    final _Responder r = script[_i < script.length ? _i : script.length - 1];
    _i++;
    return r(params);
  }
}

Map<String, dynamic> _okCreate(String postId, {bool replay = false}) =>
    <String, dynamic>{
      'ok': true,
      'contract_version': 1,
      'post_id': postId,
      'idempotent_replay': replay,
    };

void main() {
  group('F4 createBoardPostV1', () {
    test('성공: named 인자 정확·author_* 미전송·보상 삭제 0회', () async {
      final _FakeStorage storage = _FakeStorage();
      final _RpcLog rpc = _RpcLog()
        ..script = <_Responder>[(_) async => _okCreate('p-1')];
      final CreatedBoardPostV1 res = await createBoardPostV1(
        uid: 'u-1',
        title: '제목',
        body: '본문은 열 자 이상입니다',
        category: 'free',
        idempotencyKey: 'key-1',
        images: <ValidatedPostImage>[_img()],
        storage: storage,
        callCreate: rpc.call,
      );
      expect(res.postId, 'p-1');
      expect(res.idempotentReplay, isFalse);
      expect(rpc.calls, hasLength(1));
      final Map<String, dynamic> p = rpc.calls.single;
      expect(
          p.keys.toSet(),
          <String>{
            'p_title', 'p_body', 'p_category', 'p_idempotency_key',
            'p_image_refs', 'p_status',
          });
      expect(p['p_idempotency_key'], 'key-1');
      expect(p['p_status'], 'published');
      // author 계열 필드 전송 금지(서버 auth.uid 도출 — §3.3).
      expect(p.keys.where((String k) => k.contains('author')), isEmpty);
      // 신규 ref 는 정본 형식.
      final List<dynamic> refs = p['p_image_refs'] as List<dynamic>;
      expect(refs, hasLength(1));
      expect(refs.single, startsWith('community-post-images/u-1/'));
      expect(storage.removeCalls, isEmpty); // ④ 성공 — 객체 유지.
    });

    test('분기① 업로드 실패: 기업로드 신규 객체만 즉시 삭제 + F4 호출 0회', () async {
      final _FakeStorage storage = _FakeStorage()..failUploadAtIndex = 2;
      final _RpcLog rpc = _RpcLog()
        ..script = <_Responder>[(_) async => _okCreate('p-x')];
      await expectLater(
        createBoardPostV1(
          uid: 'u-1',
          title: 't',
          body: 'b',
          category: 'free',
          idempotencyKey: 'key-1',
          images: <ValidatedPostImage>[_img(1), _img(2), _img(3)],
          storage: storage,
          callCreate: rpc.call,
        ),
        throwsA(isA<AppError>()),
      );
      expect(rpc.calls, isEmpty); // finalize 미도달.
      expect(storage.removeCalls, hasLength(1));
      expect(storage.removeCalls.single, storage.uploaded); // 이번 요청 신규분만.
    });

    test('분기② 확정 실패(ok:false): 신규 객체 보상 삭제 + 안정 코드 전파', () async {
      final _FakeStorage storage = _FakeStorage();
      final _RpcLog rpc = _RpcLog()
        ..script = <_Responder>[
          (_) async => <String, dynamic>{
                'ok': false,
                'contract_version': 1,
                'code': 'ROLE_NOT_MENTOR',
              },
        ];
      await expectLater(
        createBoardPostV1(
          uid: 'u-1',
          title: 't',
          body: 'b',
          category: 'free',
          idempotencyKey: 'key-1',
          images: <ValidatedPostImage>[_img()],
          storage: storage,
          callCreate: rpc.call,
        ),
        throwsA(isA<CommunityWriteRejected>()
            .having((CommunityWriteRejected e) => e.code, 'code',
                'ROLE_NOT_MENTOR')),
      );
      expect(rpc.calls, hasLength(1)); // 확정 실패 — 재호출 없음.
      expect(storage.removeCalls, hasLength(1));
    });

    test('분기③→④ 응답 불명확 후 재호출: 재호출 전 DELETE 0회·같은 키·replay 성공 시 객체 유지',
        () async {
      final _FakeStorage storage = _FakeStorage();
      final List<int> removesAtCall = <int>[];
      final _RpcLog rpc = _RpcLog();
      rpc.script = <_Responder>[
        (_) async {
          removesAtCall.add(storage.removeCalls.length);
          throw Exception('socket closed'); // 전송 오류 — 성공/실패 불명확.
        },
        (_) async {
          // ★ T-CONC-10 핵심: 재호출 시점까지 Storage DELETE 0회.
          removesAtCall.add(storage.removeCalls.length);
          return _okCreate('p-1', replay: true);
        },
      ];
      final CreatedBoardPostV1 res = await createBoardPostV1(
        uid: 'u-1',
        title: 't',
        body: 'b',
        category: 'free',
        idempotencyKey: 'key-fixed',
        images: <ValidatedPostImage>[_img()],
        storage: storage,
        callCreate: rpc.call,
      );
      expect(res.idempotentReplay, isTrue); // 멱등 재생 = 정상 성공.
      expect(rpc.calls, hasLength(2));
      // 두 호출 모두 같은 멱등키(새 키 생성 금지).
      expect(rpc.calls[0]['p_idempotency_key'], 'key-fixed');
      expect(rpc.calls[1]['p_idempotency_key'], 'key-fixed');
      expect(removesAtCall, <int>[0, 0]); // 재호출 전 DELETE 0회.
      expect(storage.removeCalls, isEmpty); // 성공 재생 — 객체 유지.
    });

    test('분기③ 재호출이 확정 실패로 종결: 그때만 보상 삭제', () async {
      final _FakeStorage storage = _FakeStorage();
      final _RpcLog rpc = _RpcLog();
      rpc.script = <_Responder>[
        (_) async => throw Exception('timeout'),
        (_) async => <String, dynamic>{
              'ok': false,
              'contract_version': 1,
              'code': 'BODY_TOO_SHORT',
            },
      ];
      await expectLater(
        createBoardPostV1(
          uid: 'u-1',
          title: 't',
          body: 'b',
          category: 'free',
          idempotencyKey: 'k',
          images: <ValidatedPostImage>[_img()],
          storage: storage,
          callCreate: rpc.call,
        ),
        throwsA(isA<CommunityWriteRejected>()),
      );
      expect(rpc.calls, hasLength(2));
      expect(storage.removeCalls, hasLength(1)); // 미커밋 확인 후에만 삭제.
    });

    test('분기③ 재호출도 불명확: 객체 보존 + CommunityCreateUnclear(키 유지 신호)',
        () async {
      final _FakeStorage storage = _FakeStorage();
      final _RpcLog rpc = _RpcLog();
      rpc.script = <_Responder>[
        (_) async => throw Exception('net down'),
        (_) async => throw Exception('net down again'),
      ];
      await expectLater(
        createBoardPostV1(
          uid: 'u-1',
          title: 't',
          body: 'b',
          category: 'free',
          idempotencyKey: 'k',
          images: <ValidatedPostImage>[_img()],
          storage: storage,
          callCreate: rpc.call,
        ),
        throwsA(isA<CommunityCreateUnclear>()),
      );
      expect(rpc.calls, hasLength(2)); // 세션 내 자동 재호출은 1회로 제한.
      expect(storage.removeCalls, isEmpty); // 불명확 — 선삭제 금지.
    });

    test("`ok` 필드 없는 응답은 성공이 아니다(불명확 취급 — 재생 성공으로 수렴)", () async {
      final _FakeStorage storage = _FakeStorage();
      final _RpcLog rpc = _RpcLog();
      rpc.script = <_Responder>[
        (_) async => <String, dynamic>{'post_id': 'p-9'}, // ok 없음.
        (_) async => _okCreate('p-9', replay: true),
      ];
      final CreatedBoardPostV1 res = await createBoardPostV1(
        uid: 'u-1',
        title: 't',
        body: 'b',
        category: 'free',
        idempotencyKey: 'k',
        images: const <ValidatedPostImage>[],
        storage: storage,
        callCreate: rpc.call,
      );
      expect(res.postId, 'p-9');
      expect(rpc.calls, hasLength(2));
      expect(storage.removeCalls, isEmpty);
    });

    test('보상 삭제 실패는 원 결과(확정 실패)를 은폐하지 않는다', () async {
      final _FakeStorage storage = _FakeStorage()..failRemove = true;
      final _RpcLog rpc = _RpcLog()
        ..script = <_Responder>[
          (_) async => <String, dynamic>{
                'ok': false,
                'contract_version': 1,
                'code': 'CATEGORY_INVALID',
              },
        ];
      await expectLater(
        createBoardPostV1(
          uid: 'u-1',
          title: 't',
          body: 'b',
          category: 'nope',
          idempotencyKey: 'k',
          images: <ValidatedPostImage>[_img()],
          storage: storage,
          callCreate: rpc.call,
        ),
        throwsA(isA<CommunityWriteRejected>()
            .having((CommunityWriteRejected e) => e.code, 'code',
                'CATEGORY_INVALID')),
      );
    });
  });

  group('F5 updateBoardPostV1', () {
    test('성공: expected_updated_at 원문 전달 + removed_image_refs 만 사후 삭제',
        () async {
      final _FakeStorage storage = _FakeStorage();
      final _RpcLog rpc = _RpcLog()
        ..script = <_Responder>[
          (_) async => <String, dynamic>{
                'ok': true,
                'contract_version': 1,
                'post_id': 'p-1',
                'updated_at': '2026-07-30T12:00:00.123456+00:00',
                'removed_image_refs': <String>[
                  'community-post-images/u-1/old-a.png',
                  'not-a-valid-ref', // 파싱 불가 — 삭제 대상에서 제외.
                ],
              },
        ];
      final UpdatedBoardPostV1 res = await updateBoardPostV1(
        postId: 'p-1',
        title: 't2',
        body: 'b2',
        category: 'free',
        expectedUpdatedAt: '2026-07-30T11:00:00.000001+00:00',
        imageRefs: const <String>[],
        storage: storage,
        callUpdate: rpc.call,
      );
      expect(res.removedImageRefs, hasLength(2));
      expect(rpc.calls.single['p_expected_updated_at'],
          '2026-07-30T11:00:00.000001+00:00');
      expect(storage.removeCalls, hasLength(1));
      expect(storage.removeCalls.single, <String>['u-1/old-a.png']);
    });

    test('UPDATE_CONFLICT: 자동 덮어쓰기 없음 — 코드 그대로 전파·Storage 무접촉', () async {
      final _FakeStorage storage = _FakeStorage();
      final _RpcLog rpc = _RpcLog()
        ..script = <_Responder>[
          (_) async => <String, dynamic>{
                'ok': false,
                'contract_version': 1,
                'code': 'UPDATE_CONFLICT',
              },
        ];
      await expectLater(
        updateBoardPostV1(
          postId: 'p-1',
          title: 't',
          body: 'b',
          category: 'free',
          expectedUpdatedAt: 'stale',
          imageRefs: const <String>[],
          storage: storage,
          callUpdate: rpc.call,
        ),
        throwsA(isA<CommunityWriteRejected>()
            .having((CommunityWriteRejected e) => e.code, 'code',
                'UPDATE_CONFLICT')),
      );
      expect(rpc.calls, hasLength(1)); // 재시도(덮어쓰기) 없음.
      expect(storage.removeCalls, isEmpty);
    });

    test('사후 Storage 삭제 실패가 수정 성공을 뒤집지 않는다', () async {
      final _FakeStorage storage = _FakeStorage()..failRemove = true;
      final _RpcLog rpc = _RpcLog()
        ..script = <_Responder>[
          (_) async => <String, dynamic>{
                'ok': true,
                'contract_version': 1,
                'post_id': 'p-1',
                'removed_image_refs': <String>[
                  'community-post-images/u-1/old.png'
                ],
              },
        ];
      final UpdatedBoardPostV1 res = await updateBoardPostV1(
        postId: 'p-1',
        title: 't',
        body: 'b',
        category: 'free',
        expectedUpdatedAt: 'x',
        imageRefs: const <String>[],
        storage: storage,
        callUpdate: rpc.call,
      );
      expect(res.postId, 'p-1'); // 성공 유지.
    });
  });

  group('F6 softDeleteBoardPostV1', () {
    test('성공 + already_deleted:true 도 정상 성공', () async {
      final _RpcLog rpc = _RpcLog()
        ..script = <_Responder>[
          (_) async => <String, dynamic>{
                'ok': true,
                'contract_version': 1,
                'post_id': 'p-1',
                'already_deleted': true,
              },
        ];
      final SoftDeletedBoardPostV1 res =
          await softDeleteBoardPostV1(postId: 'p-1', callSoftDelete: rpc.call);
      expect(res.alreadyDeleted, isTrue);
      expect(rpc.calls.single.keys.toSet(), <String>{'p_post_id'});
    });

    test('타인·비존재 글: POST_NOT_FOUND_OR_NOT_OWNED 전파', () async {
      final _RpcLog rpc = _RpcLog()
        ..script = <_Responder>[
          (_) async => <String, dynamic>{
                'ok': false,
                'contract_version': 1,
                'code': 'POST_NOT_FOUND_OR_NOT_OWNED',
              },
        ];
      await expectLater(
        softDeleteBoardPostV1(postId: 'p-x', callSoftDelete: rpc.call),
        throwsA(isA<CommunityWriteRejected>()),
      );
    });
  });
}
