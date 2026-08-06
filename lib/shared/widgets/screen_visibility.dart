import 'package:flutter/material.dart';

/// N12: 앱 복귀(resumed) 재조회의 가시성 게이트.
///
/// HomeShell 같은 컨테이너가 [ScreenVisibility]로 '지금 보이는 자식인지'를
/// 알려주면, 화면은 resumed 분기에서 [ResumeVisibilityGate.handleResumed]만
/// 호출한다 — 보이는 화면은 즉시 재조회하고, 가려진 화면(비활성 탭·위에
/// 다른 라우트가 덮인 화면)은 '놓친 복귀'로 기록해 다시 보일 때 1회만
/// 재조회한다. 복귀 순간 살아 있는 화면 전부가 동시에 팬아웃하던 것을
/// 보이는 화면 1개로 줄인다.
class ScreenVisibility extends InheritedWidget {
  const ScreenVisibility({
    super.key,
    required this.visible,
    required super.child,
  });

  final bool visible;

  /// 감싸는 스코프가 없으면 보이는 것으로 취급한다(단독 라우트 화면).
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ScreenVisibility>()
          ?.visible ??
      true;

  @override
  bool updateShouldNotify(ScreenVisibility oldWidget) =>
      visible != oldWidget.visible;
}

/// resumed 재조회 화면용 믹스인. 화면은 [onResumeRefresh]를 구현하고
/// didChangeAppLifecycleState 의 resumed 분기에서 [handleResumed]를 부른다.
///
/// 가시성 판정 = [ScreenVisibility] 스코프(탭) ∧ ModalRoute.isCurrent(스택).
/// 두 신호 모두 InheritedWidget 의존이라 값이 바뀌면 didChangeDependencies 가
/// 다시 불려 놓친 복귀를 그때 처리한다(중복 없이 1회).
mixin ResumeVisibilityGate<T extends StatefulWidget> on State<T> {
  bool _resumePending = false;

  /// 실제 재조회 — 화면이 구현한다.
  void onResumeRefresh();

  /// didChangeAppLifecycleState(AppLifecycleState.resumed) 에서 호출.
  void handleResumed() {
    if (_visibleNow()) {
      onResumeRefresh();
    } else {
      _resumePending = true;
    }
  }

  bool _visibleNow() =>
      ScreenVisibility.of(context) &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ★ 조건 밖에서 항상 읽는다 — 첫 호출부터 두 신호를 구독해 두어야
    //   가시성 변화가 이 콜백을 다시 부른다.
    final bool visible = _visibleNow();
    if (_resumePending && visible) {
      _resumePending = false;
      onResumeRefresh();
    }
  }
}
