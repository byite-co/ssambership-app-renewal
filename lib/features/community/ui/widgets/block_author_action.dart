import 'package:flutter/material.dart';

import '../../data/user_blocks_repository.dart';

/// 작성자 차단 확인 다이얼로그 → 차단 실행(공용). 차단 성공 시 true.
///
/// [table]: 'community_posts' | 'comments'(게시판 댓글 — v16 정본) |
/// 'community_comments'(숏폼 댓글) | 'shortform_posts'.
/// author_id 는 [contentId]로 서버에서 조회해 차단하므로 화면에 노출하지 않는다.
Future<bool> confirmAndBlockAuthor(
  BuildContext context, {
  required String table,
  required String contentId,
  UserBlocksRepository repo = const UserBlocksRepository(),
}) async {
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

  final BlockResult r =
      await repo.blockAuthorOf(table: table, contentId: contentId);
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
