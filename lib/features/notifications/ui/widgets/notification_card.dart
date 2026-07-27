import 'package:flutter/material.dart';

import '../../../../design/role_accent.dart';
import '../../../../design/typography_tokens.dart';
import '../../../../design/widgets/app_badge.dart';
import '../../../../design/widgets/app_card.dart';
import '../../../../shared/format/formatters.dart';
import '../../data/app_notification.dart';

/// 알림 카드 — 유형칩 · 안읽음 점 · 상대시간 · 본문(한글) · "읽음" 버튼.
/// 탭하면 관련 화면으로 이동(onOpen). "읽음"은 이동 없이 읽음 처리만(onMarkRead).
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
    return AppCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppBadge(
                label: notificationKindLabel(notification.kind),
                tinted: false,
              ),
              if (unread) ...<Widget>[
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppAccent.of(context).accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                Formatters.relativeKorean(notification.createdAt),
                style: AppType.caption,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (notification.title != null) ...<Widget>[
            Text(
              notification.title!,
              style: AppType.cardTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
          ],
          Text(
            notification.body,
            style: AppType.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (unread) ...<Widget>[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onMarkRead,
                child: const Text('읽음'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
