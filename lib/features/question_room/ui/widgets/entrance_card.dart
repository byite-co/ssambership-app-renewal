import 'package:flutter/material.dart';

import '../../../../design/role_theme.dart';
import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/glass_card.dart';

/// 방 홈(2뎁스)의 동등한 '큰 입구' 카드. 학생·멘토 홈이 함께 쓴다.
/// 아이콘 + 제목 (+ 선택 trailing) / 미리보기 child / 우측 chevron.
class EntranceCard extends StatelessWidget {
  const EntranceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final VoidCallback onTap;

  /// 제목 우측의 선택적 위젯(예: 답변 대기 건수 칩).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 22, color: RoleTheme.of(context).color),
              const SizedBox(width: 8),
              Text(title, style: AppTypography.section),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 8),
                trailing!,
              ],
              const Spacer(),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: child),
        ],
      ),
    );
  }
}
