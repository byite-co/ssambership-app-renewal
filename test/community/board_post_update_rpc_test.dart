import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/board_post_create_gateway.dart';
import 'package:ssambership_app/features/community/data/board_post_update_gateway.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// 게시판 글 수정 RPC 계약(api_app_v1.community_post_update — 스테이징 실측).
///
/// 운영 DB 는 community_posts 에 authenticated SELECT 만 준다(UPDATE 권한·
/// policy 없음). 수정은 서버 계약 함수 단일 경로이고, 앱은 직접 UPDATE 를
/// 하지 않는다. 운영 RPC 를 실제로 호출하지 않고(전부 주입 seam), 계약
/// 표면만 고정한다.

const String _uid = 'auth-uid-0001';
const String _postId = '3f1a9b2c-1111-4222-8333-444455556666';

/// 수정 시작 시점 행의 updated_at 원문 — 재직렬화 없이 그대로 보내야 한다.
const String _expected = '2026-08-01T11:22:33.123456+00:00';

/// 서버가 확정한 새 updated_at.
const String _newUpdatedAt = '2026-08-02T05:00:00.654321+00:00';

Map<String, dynamic> _row({String id = _postId}) => <String, dynamic>{
      'id': id,
      'title': '오답노트 공유(수정)',
      'content': '이렇게 고쳤어요. 충분히 긴 본문입니다.',
      'category': 'study',
      'author_id': _uid,
      'author_label': '쌤버십 사용자',
      'author_role': 'student',
      'image_urls': <String>['community-post-images/$_uid/1_a.png'],
      'like_count': 0,
      'comment_count': 0,
      'view_count': 0,
      'created_at': '2026-08-01T00:00:00Z',
      'updated_at': _newUpdatedAt,
    };

Map<String, dynamic> _okEnvelope({
  String postId = _postId,
  Object? removed = const <String>[],
}) =>
    <String, dynamic>{
      'ok': true,
      'post_id': postId,
      'updated_at': _newUpdatedAt,
      'removed_image_refs': removed,
      'contract_version': 1,
    };

class _Harness {
  _Harness({
    this.authUserId = _uid,
    this.envelope,
    this.rpcError,
    List<Map<String, dynamic>>? rows,
    this.fetchError,
    this.cleanerError,
  }) : _rows = rows;

  final String? authUserId;
  final Object? envelope;
  final Object? rpcError;
  final List<Map<String, dynamic>>? _rows;
  final Object? fetchError;
  final Object? cleanerError;

  int rpcCalls = 0;
  int fetchCalls = 0;
  int cleanerCalls = 0;
  Map<String, dynamic>? lastParams;
  String? fetchedId;
  List<String>? lastRemovedRefs;

  /// cleaner 가 호출된 시점의 누적 RPC 성공 여부 확인용 — 호출 순서 고정.
  bool cleanerCalledBeforeRpcReturn = false;

  Future<BoardPost> run({
    String expectedUpdatedAt = _expected,
    List<String> imageRefs = const <String>[],
    String postId = _postId,
  }) {
    bool rpcReturned = false;
    return updateBoardPostViaRpc(
      authUserId: authUserId,
      postId: postId,
      title: '오답노트 공유(수정)',
      body: '이렇게 고쳤어요. 충분히 긴 본문입니다.',
      category: 'study',
      expectedUpdatedAt: expectedUpdatedAt,
      imageRefs: imageRefs,
      callRpc: (Map<String, dynamic> params) async {
        rpcCalls++;
        lastParams = params;
        if (rpcError != null) throw rpcError!;
        rpcReturned = true;
        return envelope ?? _okEnvelope();
      },
      fetchPostById: (String id) async {
        fetchCalls++;
        fetchedId = id;
        if (fetchError != null) throw fetchError!;
        return _rows ?? <Map<String, dynamic>>[_row()];
      },
      removeImageRefs: (List<String> refs) async {
        cleanerCalls++;
        lastRemovedRefs = List<String>.of(refs);
        if (!rpcReturned) cleanerCalledBeforeRpcReturn = true;
        if (cleanerError != null) throw cleanerError!;
      },
    );
  }
}

Future<Object?> _catch(Future<void> Function() run) async {
  try {
    await run();
    return null;
  } catch (e) {
    return e;
  }
}

void main() {
  group('계약 표면 — schema · 함수명 · 파라미터', () {
    test('스키마는 작성과 같은 api_app_v1, 함수명은 community_post_update', () {
      expect(kBoardPostCreateSchema, 'api_app_v1');
      expect(kBoardPostUpdateFunction, 'community_post_update');
    });

    test('params 키 집합이 서버 signature 와 정확히 일치한다', () {
      final Map<String, dynamic> p = buildBoardPostUpdateParams(
        postId: _postId,
        title: 't',
        body: 'b',
        category: 'study',
        expectedUpdatedAt: _expected,
        imageRefs: const <String>[],
      );
      // 이름이 하나라도 다르면 PostgREST 가 함수를 찾지 못한다(PGRST202).
      expect(
          p.keys.toSet(),
          <String>{
            'p_post_id',
            'p_title',
            'p_body',
            'p_category',
            'p_expected_updated_at',
            'p_image_refs',
            'p_status',
          });
      expect(p['p_status'], 'published');
    });

    test('p_expected_updated_at 은 행의 updated_at 원문이 그대로 나간다', () async {
      final _Harness h = _Harness();
      await h.run();
      expect(h.rpcCalls, 1);
      // 재직렬화·재포맷 없이 exact 문자열 — 서버가 IS DISTINCT FROM 비교.
      expect(h.lastParams!['p_expected_updated_at'], _expected);
      expect(h.lastParams!['p_post_id'], _postId);
    });

    test('p_image_refs 는 유지+추가 최종 집합이 순서대로 나간다', () async {
      final _Harness h = _Harness();
      const List<String> refs = <String>[
        'community-post-images/$_uid/1_a.png',
        'community-post-images/$_uid/2_b.jpg',
      ];
      await h.run(imageRefs: refs);
      expect(h.lastParams!['p_image_refs'], refs);
    });
  });

  group('봉투 파싱 — fail-closed', () {
    test('성공 봉투에서 post_id·updated_at·removed_image_refs 를 읽는다', () {
      final BoardPostUpdateResult r = parseBoardPostUpdateEnvelope(_okEnvelope(
          removed: <String>['community-post-images/$_uid/0_old.png']));
      expect(r.postId, _postId);
      expect(r.updatedAt, _newUpdatedAt);
      expect(r.removedImageRefs,
          <String>['community-post-images/$_uid/0_old.png']);
    });

    test('removed_image_refs 는 필수 — 빈 배열 [] 만 정상, null·부재는 계약 밖', () {
      // 빈 배열은 '제거된 이미지 없음'으로 정상 성공.
      expect(
          parseBoardPostUpdateEnvelope(_okEnvelope(removed: const <String>[]))
              .removedImageRefs,
          isEmpty);
      // 부재·null 은 삭제 대상을 확정할 수 없다 — 성공으로 처리하지 않는다.
      final Map<String, dynamic> missing = _okEnvelope();
      missing.remove('removed_image_refs');
      expect(() => parseBoardPostUpdateEnvelope(missing),
          throwsA(same(kBoardPostUpdateMalformed)));
      expect(() => parseBoardPostUpdateEnvelope(_okEnvelope(removed: null)),
          throwsA(same(kBoardPostUpdateMalformed)));
    });

    test('contract_version 은 정수 1 strict — 누락·null·2·"1" 전부 계약 밖', () {
      for (final Object? version in <Object?>[null, 2, '1', 1.5, true]) {
        final Map<String, dynamic> env = _okEnvelope();
        if (version == null) {
          env.remove('contract_version');
        } else {
          env['contract_version'] = version;
        }
        expect(() => parseBoardPostUpdateEnvelope(env),
            throwsA(same(kBoardPostUpdateMalformed)),
            reason: 'contract_version=$version');
        // null 값 자체도 확인(누락과 별개).
        env['contract_version'] = null;
        expect(() => parseBoardPostUpdateEnvelope(env),
            throwsA(same(kBoardPostUpdateMalformed)));
      }
      // 정수 1 은 통과.
      expect(parseBoardPostUpdateEnvelope(_okEnvelope()).postId, _postId);
    });

    test('실패 봉투는 contract_version 을 게이트하지 않는다(공용 규칙 — code 매핑이 정본)',
        () {
      // 버전이 빠져도 실제 오류 코드의 사용자 안내가 가려지지 않는다.
      expect(
          () => parseBoardPostUpdateEnvelope(<String, dynamic>{
                'ok': false,
                'code': 'UPDATE_CONFLICT',
              }),
          throwsA(predicate((Object? e) =>
              e is AppError &&
              e.userMessage == '다른 곳에서 글이 수정됐어요. 새로고침 후 다시 시도해 주세요.')));
    });

    test('계약 밖 응답은 전부 실패(성공으로 처리하지 않는다)', () {
      final List<Object?> malformed = <Object?>[
        null,
        'ok',
        <String, dynamic>{},
        <String, dynamic>{'ok': 'true'},
        <String, dynamic>{'ok': true}, // 전 필드 없음
        <String, dynamic>{..._okEnvelope(), 'post_id': ''},
        <String, dynamic>{..._okEnvelope(), 'post_id': null},
        <String, dynamic>{..._okEnvelope(), 'updated_at': ''},
        <String, dynamic>{..._okEnvelope(), 'updated_at': null},
        <String, dynamic>{..._okEnvelope(), 'removed_image_refs': 'not-a-list'},
        // 혼합 타입 원소 — 하나라도 문자열이 아니면 거부.
        <String, dynamic>{
          ..._okEnvelope(),
          'removed_image_refs': <Object?>['community-post-images/u/a.png', 2],
        },
        <String, dynamic>{
          ..._okEnvelope(),
          'removed_image_refs': <Object?>[null],
        },
      ];
      for (final Object? raw in malformed) {
        expect(() => parseBoardPostUpdateEnvelope(raw),
            throwsA(same(kBoardPostUpdateMalformed)),
            reason: '$raw');
      }
    });
  });

  group('서버 오류 코드 → 한글 문구', () {
    test('ACCOUNT_NOT_ACTIVE — 수정(update) 표면 명시 문구(공통 fallback 아님)', () {
      final AppError e = boardPostUpdateError('ACCOUNT_NOT_ACTIVE');
      expect(e.userMessage, '현재 계정 상태에서는 이 기능을 사용할 수 없어요.');
      expect(e.userMessage, isNot(kBoardPostUpdateMalformed.userMessage));
    });

    test('UPDATE_CONFLICT — 다른 곳에서 수정됨 → 새로고침 후 재시도 안내', () {
      expect(boardPostUpdateError('UPDATE_CONFLICT').userMessage,
          '다른 곳에서 글이 수정됐어요. 새로고침 후 다시 시도해 주세요.');
    });

    test('POST_NOT_FOUND_OR_NOT_OWNED — 글 없음/권한 없음 안내', () {
      expect(boardPostUpdateError('POST_NOT_FOUND_OR_NOT_OWNED').userMessage,
          '글이 없거나 수정 권한이 없어요. 새로고침 후 다시 확인해 주세요.');
    });

    test('작성과 공용인 계정 상태·역할 코드는 같은 문구를 준다(단일 매퍼)', () {
      for (final String code in <String>[
        'AUTH_REQUIRED',
        'ROLE_NOT_ALLOWED',
        'ROLE_NOT_MENTOR',
        'MENTOR_NOT_APPROVED',
        'ACCOUNT_BANNED',
        'ACCOUNT_SUSPENDED',
        'ACCOUNT_DELETION_IN_PROGRESS',
        'ACCOUNT_NOT_ACTIVE',
        'TITLE_REQUIRED',
        'CATEGORY_INVALID',
        'BODY_TOO_SHORT',
        'IMAGE_COUNT_EXCEEDED',
        'IMAGE_REF_INVALID',
      ]) {
        expect(boardPostUpdateError(code).userMessage,
            boardPostCreateError(code).userMessage,
            reason: code);
      }
    });

    test('기존 계정 상태 문구 회귀 없음(BANNED/SUSPENDED/DELETION_IN_PROGRESS)', () {
      expect(boardPostUpdateError('ACCOUNT_BANNED').userMessage,
          '이용이 제한된 계정이에요. 고객센터로 문의해 주세요.');
      expect(boardPostUpdateError('ACCOUNT_SUSPENDED').userMessage,
          '일시 정지된 계정이에요. 정지 기간이 끝난 뒤 다시 시도해 주세요.');
      expect(boardPostUpdateError('ACCOUNT_DELETION_IN_PROGRESS').userMessage,
          '탈퇴 처리 중에는 글을 쓸 수 없어요.');
    });

    test('미지의 코드·비문자 코드는 수정용 공통 문구(fail-closed)', () {
      expect(boardPostUpdateError('WAT').userMessage,
          kBoardPostUpdateMalformed.userMessage);
      expect(boardPostUpdateError(null).userMessage,
          kBoardPostUpdateMalformed.userMessage);
      expect(boardPostUpdateError(42).userMessage,
          kBoardPostUpdateMalformed.userMessage);
    });

    test('문구에 코드꼴 토큰·내부 식별자가 노출되지 않는다', () {
      for (final String code in <String>[
        'ACCOUNT_NOT_ACTIVE',
        'UPDATE_CONFLICT',
        'POST_NOT_FOUND_OR_NOT_OWNED',
      ]) {
        final String msg = boardPostUpdateError(code).userMessage;
        expect(msg.contains(code), isFalse, reason: code);
        expect(RegExp(r'[A-Z]{2,}_[A-Z_]+').hasMatch(msg), isFalse,
            reason: code);
      }
    });
  });

  group('오케스트레이터 — 호출 순서·fail-closed', () {
    test('미로그인은 RPC 호출조차 하지 않는다', () async {
      final _Harness h = _Harness(authUserId: null);
      final Object? e = await _catch(() => h.run());
      expect(e, isA<AppError>());
      expect(h.rpcCalls, 0);
      expect(h.cleanerCalls, 0);
    });

    test('expected_updated_at 이 비면 보내지 않는다(충돌 검사 미성립)', () async {
      final _Harness h = _Harness();
      final Object? e = await _catch(() => h.run(expectedUpdatedAt: '  '));
      expect(e, same(kBoardPostUpdateMalformed));
      expect(h.rpcCalls, 0);
    });

    test('성공 → 정본 행 재조회로 BoardPost 를 만든다', () async {
      final _Harness h = _Harness();
      final BoardPost post = await h.run();
      expect(h.rpcCalls, 1);
      expect(h.fetchCalls, 1);
      expect(h.fetchedId, _postId);
      expect(post.id, _postId);
      expect(post.updatedAtRaw, _newUpdatedAt);
    });

    test('removed_image_refs 는 RPC 성공 후에만 서버 목록 그대로 정리한다',
        () async {
      const List<String> removed = <String>[
        'community-post-images/$_uid/0_old.png',
      ];
      final _Harness h = _Harness(envelope: _okEnvelope(removed: removed));
      await h.run();
      expect(h.cleanerCalls, 1);
      expect(h.lastRemovedRefs, removed);
      expect(h.cleanerCalledBeforeRpcReturn, isFalse); // DB 반영 확정 후
    });

    test('제거된 이미지가 없으면 정리를 호출하지 않는다', () async {
      final _Harness h = _Harness();
      await h.run();
      expect(h.cleanerCalls, 0);
    });

    test('RPC 실패(예외) → 기존 이미지 삭제 0회·재조회 0회', () async {
      final _Harness h = _Harness(rpcError: Exception('network down'));
      expect(await _catch(() => h.run()), isNotNull);
      expect(h.cleanerCalls, 0);
      expect(h.fetchCalls, 0);
    });

    test('실패 봉투(ok:false) → 기존 이미지 삭제 0회·매핑 문구', () async {
      final _Harness h = _Harness(envelope: <String, dynamic>{
        'ok': false,
        'code': 'UPDATE_CONFLICT',
        'contract_version': 1,
      });
      final Object? e = await _catch(() => h.run());
      expect(e, isA<AppError>());
      expect((e as AppError).userMessage,
          '다른 곳에서 글이 수정됐어요. 새로고침 후 다시 시도해 주세요.');
      expect(h.cleanerCalls, 0);
      expect(h.fetchCalls, 0);
    });

    test('malformed 성공 봉투(버전·삭제목록 계약 밖) → Storage 삭제 0회', () async {
      final List<Map<String, dynamic>> malformed = <Map<String, dynamic>>[
        <String, dynamic>{..._okEnvelope(), 'contract_version': 2},
        (() {
          final Map<String, dynamic> e = _okEnvelope();
          e.remove('contract_version');
          return e;
        })(),
        <String, dynamic>{..._okEnvelope(), 'removed_image_refs': null},
        <String, dynamic>{
          ..._okEnvelope(),
          'removed_image_refs': <Object?>['x', 1],
        },
      ];
      for (final Map<String, dynamic> env in malformed) {
        final _Harness h = _Harness(envelope: env);
        expect(await _catch(() => h.run()), same(kBoardPostUpdateMalformed),
            reason: '$env');
        expect(h.cleanerCalls, 0, reason: '$env');
        expect(h.fetchCalls, 0, reason: '$env');
      }
    });

    test('봉투 post_id 불일치 → 삭제도 재조회도 하지 않는다(fail-closed)', () async {
      final _Harness h = _Harness(
          envelope: _okEnvelope(
              postId: 'another-post',
              removed: <String>['community-post-images/$_uid/0_old.png']));
      final Object? e = await _catch(() => h.run());
      expect(e, same(kBoardPostUpdatedButUnverified));
      expect(h.cleanerCalls, 0);
      expect(h.fetchCalls, 0);
    });

    test('정리 실패는 수정 성공을 뒤집지 않는다(best-effort)', () async {
      final _Harness h = _Harness(
        envelope: _okEnvelope(
            removed: <String>['community-post-images/$_uid/0_old.png']),
        cleanerError: Exception('storage down'),
      );
      final BoardPost post = await h.run();
      expect(post.id, _postId);
      expect(h.cleanerCalls, 1);
    });

    test('재조회 실패·0행·id 불일치 → 수정됨-미확인 오류(fail-closed)', () async {
      for (final _Harness h in <_Harness>[
        _Harness(fetchError: Exception('fetch down')),
        _Harness(rows: <Map<String, dynamic>>[]),
        _Harness(rows: <Map<String, dynamic>>[_row(id: 'other')]),
      ]) {
        final Object? e = await _catch(() => h.run());
        expect(e, same(kBoardPostUpdatedButUnverified));
        expect(h.rpcCalls, 1);
      }
    });
  });

  group('역할 동등 — 학생·멘토·미승인 멘토 자기 글 수정', () {
    // 앱은 역할·승인 상태로 수정을 막지 않는다 — 오케스트레이터에 역할 입력
    // 자체가 없고, 판정은 서버(community_post_update)가 한다. 세 역할 모두
    // 같은 경로로 성공 봉투를 받으면 같은 결과가 나온다.
    test('학생/멘토/미승인 멘토 모두 같은 경로로 수정에 성공한다', () async {
      for (final String role in <String>[
        'student',
        'mentor',
        'mentor-unapproved',
      ]) {
        final _Harness h = _Harness(rows: <Map<String, dynamic>>[
          <String, dynamic>{
            ..._row(),
            'author_role': role == 'mentor-unapproved' ? 'mentor' : role,
          }
        ]);
        final BoardPost post = await h.run();
        expect(post.id, _postId, reason: role);
        expect(h.rpcCalls, 1, reason: role);
      }
    });
  });

  group('production 소스 가드', () {
    const String writeRepo =
        'lib/features/community/data/community_write_repository.dart';
    const String gateway =
        'lib/features/community/data/board_post_update_gateway.dart';

    List<String> productionDart() {
      return Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .map((File f) => f.path)
          .toList();
    }

    test('community_posts 직접 UPDATE 가 production 코드에 0건', () {
      final RegExp update =
          RegExp(r"from\(\s*'community_posts'\s*\)\s*\.\s*update");
      for (final String path in productionDart()) {
        expect(update.hasMatch(File(path).readAsStringSync()), isFalse,
            reason: '$path 에 community_posts 직접 UPDATE 가 남아 있다');
      }
    });

    test('updatePost 는 schema(api_app_v1).rpc 로만 나간다', () {
      final String src = File(writeRepo).readAsStringSync();
      expect(src.contains('rpc(kBoardPostUpdateFunction'), isTrue);
      // 스키마를 생략하면 public 으로 나가 함수를 찾지 못한다.
      expect(RegExp(r"_client\.rpc\(\s*'community_post_update'").hasMatch(src),
          isFalse);
    });

    test('수정 게이트웨이가 public wrapper 를 임의로 만들지 않는다', () {
      final String src = File(gateway).readAsStringSync();
      expect(src.contains('public.community_post_update'), isFalse);
    });

    test('수정 경로에 역할/승인 분기가 없다(판정은 서버)', () {
      final String src = File(gateway).readAsStringSync();
      // 오케스트레이터 코드가 role/approved 입력·분기를 갖지 않는다.
      expect(RegExp(r'\brole\b|isApproved|authorRole').hasMatch(src), isFalse);
    });
  });
}
