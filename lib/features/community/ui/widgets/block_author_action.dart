import 'package:flutter/material.dart';

import '../../data/user_blocks_repository.dart';

/// 작성자 차단 확인 다이얼로그 → 차단 실행(공용). 차단 성공 시 true.
///
/// 두 진입 방식 중 하나로 호출한다:
/// - [authorId]: 화면이 이미 정본 행에서 작성자 id 를 갖고 있는 경우(게시판
///   글 — 뷰 community_posts_v1 행. C10: 베이스 테이블 재조회 금지).
/// - [table]+[contentId]: 'comments'(게시판 댓글 — v16 정본) |
///   'community_comments'(숏폼 댓글) | 'shortform_posts' — 서버에서 author_id
///   를 조회해 차단(화면에 노출하지 않음).
Future<bool> confirmAndBlockAuthor(
  BuildContext context, {
  String? table,
  String? contentId,
  String? authorId,
  UserBlocksRepository repo = const UserBlocksRepository(),
}) async {
  assert(authorId != null || (table != null && contentId != null),
      'authorId 또는 table+contentId 중 하나는 필요하다');
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('이 사용자를 차단할까요?'),
      content: const Text('이 사용자의 글·댓글·숏폼이 보이지 않아요. 언제든 해제할 수 있어요.'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('차단'),
        ),
      ],
    ),
  );
  if (ok != true) return false;

  final BlockResult r = authorId != null
      ? await repo.blockAuthor(authorId)
      : await repo.blockAuthorOf(table: table!, contentId: contentId!);
  if (!context.mounted) return r == BlockResult.blocked;
  final String msg;
  switch (r) {
    case BlockResult.blocked:
      msg = '차단했어요. 이 사용자의 콘텐츠가 숨겨져요.';
    case BlockResult.self:
      msg = '자기 자신은 차단할 수 없어요.';
    case BlockResult.notLoggedIn:
      msg = '로그인하면 차단할 수 있어요.';
    case BlockResult.failed:
      msg = '차단에 실패했어요. 잠시 후 다시 시도해 주세요.';
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  return r == BlockResult.blocked;
}
