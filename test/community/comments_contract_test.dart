import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/data/community_read_repository.dart';
import 'package:ssambership_app/features/community/data/community_write_repository.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

import 'fakes.dart';

/// v16 정본 전환 계약 — 게시판 댓글은 정본 `comments` 테이블,
/// 숏폼 댓글은 기존 `community_comments`(post_type='shortform') 유지.
/// 실제 DB 없이 기록형 가짜 게이트웨이(RecordingCommentsGateway)로 검증.
void main() {
  group('게시판 댓글 읽기(정본 comments)', () {
    test('comments 테이블에서 post_id 필터만으로 조회(is_deleted 는 서버 RLS)', () async {
      final RecordingCommentsGateway gw = RecordingCommentsGateway(
        selectRows: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'c1',
            'post_id': 'p1',
            'author_id': 'other-user',
            'content': '정본 본문',
            'parent_id': null,
            'created_at': '2026-07-20T00:00:00Z',
          },
        ],
      );
      final CommunityReadRepository read = CommunityReadRepository(gateway: gw);

      final List<CommunityComment> list =
          await read.comments(CommunityPostType.board, 'p1');

      expect(gw.lastSelectTable, 'comments');
      expect(gw.lastSelectFilters, <String, Object>{'post_id': 'p1'});
      expect(list.single.body, '정본 본문'); // content → 모델 body 매핑
      expect(list.single.parentId, isNull);
    });

    test('parent_id 가 모델 parentId 로 실린다(2-depth 답글 표시 대비)', () async {
      final RecordingCommentsGateway gw = RecordingCommentsGateway(
        selectRows: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'c2',
            'post_id': 'p1',
            'content': '답글',
            'parent_id': 'c1',
            'created_at': '2026-07-20T01:00:00Z',
          },
        ],
      );
      final CommunityReadRepository read = CommunityReadRepository(gateway: gw);

      final List<CommunityComment> list =
          await read.comments(CommunityPostType.board, 'p1');
      expect(list.single.parentId, 'c1');
    });

    test('페이징 인자(limit/offset)가 게이트웨이로 전달된다', () async {
      final RecordingCommentsGateway gw = RecordingCommentsGateway();
      final CommunityReadRepository read = CommunityReadRepository(gateway: gw);

      await read.comments(CommunityPostType.board, 'p1', limit: 20, offset: 40);
      expect(gw.lastSelectLimit, 20);
      expect(gw.lastSelectOffset, 40);
    });
  });

  group('숏폼 댓글 읽기(기존 경로 유지)', () {
    test('community_comments + post_type/status 필터 그대로(정본 미전환)', () async {
      final RecordingCommentsGateway gw = RecordingCommentsGateway(
        selectRows: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'sc1',
            'post_id': 's1',
            'body': '숏폼 댓글',
            'created_at': '2026-07-20T00:00:00Z',
          },
        ],
      );
      final CommunityReadRepository read = CommunityReadRepository(gateway: gw);

      final List<CommunityComment> list =
          await read.comments(CommunityPostType.shortform, 's1');

      expect(gw.lastSelectTable, 'community_comments');
      expect(gw.lastSelectFilters, <String, Object>{
        'post_type': 'shortform',
        'post_id': 's1',
        'status': 'visible',
      });
      expect(list.single.body, '숏폼 댓글'); // legacy body 그대로
    });
  });

  group('게시판 댓글 쓰기(정본 comments)', () {
    test('페이로드는 정확히 {post_id, author_id, content} — 보호 필드 미전송', () async {
      final RecordingCommentsGateway gw =
          RecordingCommentsGateway(userId: 'user-1');
      final CommunityWriteRepository write =
          CommunityWriteRepository(gateway: gw);

      final CommunityComment c = await write.addComment(
        postType: CommunityPostType.board,
        postId: 'p1',
        body: '댓글!',
      );

      expect(gw.lastInsertTable, 'comments');
      // ★ 키 집합까지 고정 — status/like_count/legacy_comment_id 등 초과 키 금지.
      expect(gw.lastInsertValues, <String, dynamic>{
        'post_id': 'p1',
        'author_id': 'user-1',
        'content': '댓글!',
      });
      expect(gw.lastInsertValues!.keys.toSet(),
          <String>{'post_id', 'author_id', 'content'});
      expect(c.body, '댓글!'); // 생성 행의 content → 모델 body
    });

    test('parentId 지정 시에만 parent_id 가 추가된다(답글)', () async {
      final RecordingCommentsGateway gw =
          RecordingCommentsGateway(userId: 'user-1');
      final CommunityWriteRepository write =
          CommunityWriteRepository(gateway: gw);

      await write.addComment(
        postType: CommunityPostType.board,
        postId: 'p1',
        body: '답글!',
        parentId: 'c1',
      );
      expect(gw.lastInsertValues!['parent_id'], 'c1');
      expect(gw.lastInsertValues!.keys.toSet(),
          <String>{'post_id', 'author_id', 'content', 'parent_id'});
    });

    test('비로그인 → AppError(로그인 안내), INSERT 미시도', () async {
      final RecordingCommentsGateway gw = RecordingCommentsGateway(); // uid 없음
      final CommunityWriteRepository write =
          CommunityWriteRepository(gateway: gw);

      await expectLater(
        write.addComment(
            postType: CommunityPostType.board, postId: 'p1', body: '댓글'),
        throwsA(isA<AppError>()),
      );
      expect(gw.lastInsertTable, isNull);
    });
  });

  group('숏폼 댓글 쓰기(기존 경로 유지)', () {
    test('community_comments + {post_type, post_id, author_id, body, status}',
        () async {
      final RecordingCommentsGateway gw =
          RecordingCommentsGateway(userId: 'user-1');
      final CommunityWriteRepository write =
          CommunityWriteRepository(gateway: gw);

      await write.addComment(
        postType: CommunityPostType.shortform,
        postId: 's1',
        body: '숏폼 댓글!',
      );

      expect(gw.lastInsertTable, 'community_comments');
      expect(gw.lastInsertValues, <String, dynamic>{
        'post_type': 'shortform',
        'post_id': 's1',
        'author_id': 'user-1',
        'body': '숏폼 댓글!',
        'status': 'visible',
      });
    });
  });

  group('서버 트리거 오류 → 사용자용 한글 문구(코드 비노출)', () {
    test('알려진 코드 3종이 모두 한글 문구로 매핑된다', () {
      const List<String> codes = <String>[
        'COMMENT_DEPTH_EXCEEDED',
        'COMMENT_PARENT_POST_MISMATCH',
        'COMMENT_HARD_DELETE_FORBIDDEN',
      ];
      for (final String code in codes) {
        final AppError? e = CommunityWriteRepository.commentContractError(
            Exception('PostgrestException(message: $code, code: P0001)'));
        expect(e, isNotNull, reason: code);
        expect(e!.userMessage.contains('COMMENT'), isFalse); // 코드 비노출
        expect(e.userMessage.contains('요'), isTrue); // 한글 안내 문구
      }
    });

    test('모르는 오류는 null → 호출부의 일반 문구로 폴백', () {
      expect(
        CommunityWriteRepository.commentContractError(
            Exception('some other failure')),
        isNull,
      );
    });

    test('INSERT 가 깊이 초과로 거부되면 AppError 로 변환되어 던져진다', () async {
      final RecordingCommentsGateway gw = RecordingCommentsGateway(
        userId: 'user-1',
        insertError:
            Exception('PostgrestException(message: COMMENT_DEPTH_EXCEEDED)'),
      );
      final CommunityWriteRepository write =
          CommunityWriteRepository(gateway: gw);

      await expectLater(
        write.addComment(
          postType: CommunityPostType.board,
          postId: 'p1',
          body: '답답글',
          parentId: 'c2',
        ),
        throwsA(isA<AppError>().having(
          (AppError e) => e.userMessage,
          'userMessage',
          '답글에는 다시 답글을 달 수 없어요.',
        )),
      );
    });
  });
}
