import 'package:flutter/material.dart';

import '../../../../app/app_scope.dart';
import '../../../../design/tokens/app_spacing.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/app_empty_state.dart';
import '../../../../design/widgets/app_page.dart';
import '../../../../design/widgets/app_secondary_button.dart';
import '../../../../design/widgets/glass_card.dart';
import '../../../../design/widgets/initial_avatar.dart';
import '../../data/user_blocks_repository.dart';

/// 차단 관리 — 내가 차단한 사용자 목록 + 해제. 없으면 EmptyState.
/// 앱 공통 스타일(학생 파랑 역할색). 콘텐츠 필터는 커뮤니티 read 에서 처리된다.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({
    super.key,
    this.repository,
  });

  /// Optional test seam. Production resolves the repository from [AppScope].
  final UserBlocksRepository? repository;

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  late final UserBlocksRepository _repository;
  late Future<List<BlockedUser>> _future;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? AppScope.of(context).userBlocks;
    _future = _repository.myBlockedUsers();
  }

  void _reload() {
    setState(() {
      _future = _repository.myBlockedUsers();
    });
  }

  Future<void> _unblock(BlockedUser u) async {
    final bool ok = await _repository.unblock(u.userId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            ok ? '${u.displayName} 차단을 해제했어요.' : '해제에 실패했어요. 잠시 후 다시 시도해 주세요.'),
      ),
    );
    if (ok) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: '차단 관리',
      body: FutureBuilder<List<BlockedUser>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<List<BlockedUser>> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<BlockedUser> users = snap.data ?? <BlockedUser>[];
          if (users.isEmpty) {
            return const AppEmptyState(
              icon: Icons.block_rounded,
              title: '차단한 사용자가 없어요',
              description: '커뮤니티 글·댓글·숏폼의 ⋯ 메뉴에서 사용자를 차단할 수 있어요.',
            );
          }
          return ListView.separated(
            clipBehavior: Clip.none,
            padding: AppPage.contentPadding(context),
            itemCount: users.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpacing.listGap),
            itemBuilder: (BuildContext context, int i) => _BlockedRow(
              user: users[i],
              onUnblock: () => _unblock(users[i]),
            ),
          );
        },
      ),
    );
  }
}

class _BlockedRow extends StatelessWidget {
  const _BlockedRow({required this.user, required this.onUnblock});
  final BlockedUser user;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: <Widget>[
          InitialAvatar(name: user.displayName, size: 40, tinted: false),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              user.displayName,
              style: AppTypography.bodyStrong,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          AppSecondaryButton(
            label: '차단 해제',
            expand: false,
            onPressed: onUnblock,
          ),
        ],
      ),
    );
  }
}
