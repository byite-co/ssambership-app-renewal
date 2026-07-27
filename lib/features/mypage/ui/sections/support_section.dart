import 'package:flutter/material.dart';

import '../../../../app/app_tabs.dart';
import '../../../../core/web_bridge/web_bridge_actions.dart';
import '../widgets/mypage_section.dart';

/// 지원 진입 섹션 — 알림·고객지원(+멘토 한정 '받은 리뷰'). 알림=인앱 탭 전환, 그 외=웹.
///
/// 리뷰 행 역할 게이트: 범용 '리뷰 작성' 행은 폐기됐다 — 목적지(/mentor/reviews)가
/// 멘토의 '받은 리뷰' 화면이므로 학생·게스트·관리자에게는 노출하지 않고,
/// 멘토에게만 [showReceivedReviews] 로 '받은 리뷰' 라벨로 노출한다.
/// 앱 내 리뷰 '작성' 기능은 만들지 않는다(웹 리뷰 정책 불변).
class SupportSection extends StatelessWidget {
  const SupportSection({
    super.key,
    this.onOpenNotifications,
    this.showReceivedReviews = false,
  });

  /// 알림 탭으로 보내는 핸드오프(없으면 TabNavigator 로 알림 탭 전환 —
  /// push 라우트 위에서는 반드시 pop-with-result 콜백을 주입할 것).
  final VoidCallback? onOpenNotifications;

  /// 멘토에게만 true — '받은 리뷰'(웹 멘토 받은 리뷰 화면) 행 노출.
  final bool showReceivedReviews;

  @override
  Widget build(BuildContext context) {
    return MyPageSection(
      icon: Icons.support_agent_rounded,
      title: '알림 · 지원',
      child: Column(
        children: <Widget>[
          MyPageRow(
            icon: Icons.notifications_rounded,
            label: '알림',
            onTap: () => (onOpenNotifications ??
                () => TabNavigator.go(AppTab.notifications))(),
          ),
          MyPageRow(
            icon: Icons.support_agent_rounded,
            label: '고객지원',
            onTap: () => openSupportWeb(context),
          ),
          if (showReceivedReviews)
            MyPageRow(
              icon: Icons.rate_review_rounded,
              label: '받은 리뷰',
              onTap: () => openReviewsWeb(context),
            ),
        ],
      ),
    );
  }
}
