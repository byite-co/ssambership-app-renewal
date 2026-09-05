import 'package:flutter/material.dart';

import '../tokens/app_spacing.dart';
import 'app_background.dart';
import 'glass_bars.dart';

/// v3 화면 공통 스캐폴드 — 배경 그라디언트 + 유리 앱바 + (선택) 하단 고정 바.
///
/// 테마·역할색은 앱 루트가 [MaterialApp] 위에 한 번 두른다(A-6b). 이 위젯은
/// 그 아래에서 화면 하나의 껍데기만 만든다. 페이지마다 [AppBackground] 를 다시
/// 그리는 이유는 route 전환 중 투명 Scaffold 두 장이 겹쳐 보이지 않게 하기 위해서다.
///
/// ★ 앱바 뒤 본문 처리(A-6b 2-1 단일 해법): [AppPageBody] 참고.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
    this.leading,
    this.automaticallyImplyLeading = true,
    this.bottom,
    this.resizeToAvoidBottomInset,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;

  /// 앱바 왼쪽. null 이면 push 된 화면에서 자동으로 뒤로 가기가 붙는다.
  final Widget? leading;
  final bool automaticallyImplyLeading;

  /// 하단 고정 영역(저장 버튼 등). 유리 바로 감싸고 본문이 그 뒤까지 스크롤된다.
  final Widget? bottom;

  final bool? resizeToAvoidBottomInset;

  /// 스크롤 본문 기본 패딩 — 좌우 20 · 앱바 아래 [top] · 하단 [bottom] + 하단
  /// 고정 바/탭바 높이(Scaffold 가 본문 MediaQuery.padding.bottom 으로 알려 준다).
  static EdgeInsets contentPadding(
    BuildContext context, {
    double top = 12,
    double bottom = 24,
  }) =>
      EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        top,
        AppSpacing.screenH,
        bottom + MediaQuery.paddingOf(context).bottom,
      );

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        extendBody: bottom != null,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        appBar: GlassAppBar(
          title: Text(title),
          leading: leading,
          automaticallyImplyLeading: automaticallyImplyLeading,
          actions: actions,
        ),
        body: AppPageBody(child: body),
        bottomNavigationBar: bottom == null
            ? null
            : GlassBottomSheet(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: bottom!,
              ),
      ),
    );
  }
}

/// 유리 앱바 아래 본문 배치 — 앱 전체 단일 규칙(A-6b 2-1).
///
/// Scaffold 는 `extendBodyBehindAppBar` 로 본문을 화면 맨 위까지 늘리고, 본문의
/// `MediaQuery.padding.top` 을 앱바 높이(상태바 포함)로 바꿔 준다. 여기서는
/// 그 높이만큼 **본문 바깥에** 상단 패딩을 두어 스크롤 뷰포트가 앱바 아래에서
/// 시작하게 한다 — 항목을 뷰포트 맨 위에 맞추는 `ensureVisible` 기반 테스트에서
/// 앱바가 탭을 가리지 않는다. 스크롤 뷰가 `clipBehavior: Clip.none` 이면 뷰포트
/// 위로 넘어간 항목이 그대로 그려져 유리 앱바 뒤로 비친다(`ClipRect` 가 화면
/// 상단에서 잘라 준다). 자식에게는 상단 패딩을 제거해 넘겨 이중 여백을 막는다.
class AppPageBody extends StatelessWidget {
  const AppPageBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double inset = MediaQuery.paddingOf(context).top;
    return ClipRect(
      child: Padding(
        padding: EdgeInsets.only(top: inset),
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: child,
        ),
      ),
    );
  }
}
