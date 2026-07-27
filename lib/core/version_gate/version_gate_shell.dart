import 'package:flutter/material.dart';

import 'version_gate_controller.dart';
import 'version_gate_screens.dart';
import 'version_policy.dart';

/// 버전 게이트 셸 — 라우터(Navigator) 위에 얹혀 진입 전 게이트를 그린다.
///
/// MaterialApp.router 의 `builder:` 로 배선한다(app.dart). 라우터/EntryGuard 를
/// 건드리지 않는 최소 배선: 게이트가 통과(pass/skipped/idle)면 자식(라우터 화면)을
/// 그대로 보여주고, 아니면 게이트 화면이 자식을 '대체'한다 — 강제 업데이트/조회
/// 실패 중에는 앱 내부로 들어갈 길이 없다(로그인 전·후 무관).
class VersionGateShell extends StatelessWidget {
  const VersionGateShell({
    super.key,
    required this.controller,
    required this.child,
    this.storeLauncher,
  });

  final VersionGateController controller;
  final Widget child;

  /// 테스트 주입용(실 배선에서는 null → url_launcher 기본).
  final StoreLauncher? storeLauncher;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        switch (controller.status) {
          // idle: start() 미호출(위젯테스트 등) — 게이트 미개입.
          case VersionGateStatus.idle:
          case VersionGateStatus.skipped:
          case VersionGateStatus.pass:
            return child;
          case VersionGateStatus.checking:
            return const VersionGateLoading();
          case VersionGateStatus.forceUpdate:
            return ForceUpdateScreen(
              policy: controller.policy ?? _emptyPolicy,
              launcher: storeLauncher,
            );
          case VersionGateStatus.fetchFailed:
            return VersionGateRetryScreen(onRetry: controller.retry);
          case VersionGateStatus.recommend:
            // 권장은 차단이 아니다 — 자식 위에 닫을 수 있는 배너만 얹는다.
            return Stack(
              children: <Widget>[
                child,
                RecommendUpdateBanner(
                  policy: controller.policy ?? _emptyPolicy,
                  onDismiss: controller.dismissRecommend,
                  launcher: storeLauncher,
                ),
              ],
            );
        }
      },
    );
  }

  /// 방어용 빈 정책(policy 없이 force/recommend 상태가 될 일은 없지만 !를 피한다).
  static const VersionPolicy _emptyPolicy = VersionPolicy(
    platform: '',
    minSupportedBuild: 1,
    latestBuild: 1,
  );
}
