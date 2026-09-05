import 'package:flutter/material.dart';

import '../../../../design/role_theme.dart' show RoleTheme;
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/app_badge.dart';
import '../../../../design/widgets/glass_card.dart';
import '../../../../shared/format/formatters.dart';
import '../../data/app_notification.dart';

/// 알림 카드(design-v3 §5-7) — 읽지 않은 것은 **왼쪽 점 하나**로만 표시한다.
/// 유형 배지 · 상대시간 · 본문(한글) · "읽음" 버튼(이동 없이 읽음 처리만).
/// 탭하면 관련 화면으로 이동(onOpen).
class NotificationCard extends StatelessWidget {
  const NotificationCard({
    super.key,
    required this.notification,
    required this.onOpen,
    required this.onMarkRead,
  });

  final AppNotification notification;
  final VoidCallback onOpen;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final bool unread = !notification.isRead;
    final Color roleColor = RoleTheme.of(context).color;
    return GlassCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(12, 14, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 안 읽음 점 — 왼쪽 한 점(§5-7). 읽은 알림은 같은 폭의 빈 자리.
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: unread ? roleColor : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AppBadge(
                      label: notificationKindLabel(notification.kind),
                      tone: AppBadgeTone.neutral,
                    ),
                    const Spacer(),
                    Text(
                      Formatters.relativeKorean(notification.createdAt),
                      style: AppTypography.meta,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (notification.title != null) ...<Widget>[
                  Text(
                    notification.title!,
                    style: AppTypography.bodyStrong.copyWith(
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  notification.body,
                  style: notification.title == null
                      ? AppTypography.body
                      : AppTypography.captionSecondary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (unread)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onMarkRead,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('읽음'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
