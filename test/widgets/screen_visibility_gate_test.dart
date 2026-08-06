import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/shared/widgets/screen_visibility.dart';

/// N12: 복귀(resumed) 재조회 가시성 게이트 — 보이는 화면만 즉시, 가려진
/// 화면은 다시 보일 때 1회.
class _Probe extends StatefulWidget {
  const _Probe({super.key});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with ResumeVisibilityGate {
  int refreshCount = 0;

  @override
  void onResumeRefresh() => refreshCount++;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Widget _host({required bool visible, required GlobalKey key}) => MaterialApp(
      home: ScreenVisibility(visible: visible, child: _Probe(key: key)),
    );

void main() {
  testWidgets('보이는 화면 → 즉시 재조회', (WidgetTester tester) async {
    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(_host(visible: true, key: key));

    final _ProbeState s = key.currentState! as _ProbeState;
    s.handleResumed();
    expect(s.refreshCount, 1);
  });

  testWidgets('가려진 화면 → 보류, 다시 보일 때 1회만', (WidgetTester tester) async {
    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(_host(visible: false, key: key));

    final _ProbeState s = key.currentState! as _ProbeState;
    s.handleResumed();
    s.handleResumed(); // 백그라운드 왕복 2회여도
    expect(s.refreshCount, 0); // 가려진 동안엔 0

    await tester.pumpWidget(_host(visible: true, key: key));
    expect(s.refreshCount, 1); // 재노출 시 1회로 합쳐진다

    // 가시성이 다시 바뀌어도 보류분이 없으면 재조회하지 않는다.
    await tester.pumpWidget(_host(visible: false, key: key));
    await tester.pumpWidget(_host(visible: true, key: key));
    expect(s.refreshCount, 1);
  });

  testWidgets('스코프가 없으면 보이는 것으로 취급(단독 라우트)', (WidgetTester tester) async {
    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: _Probe(key: key)));

    final _ProbeState s = key.currentState! as _ProbeState;
    s.handleResumed();
    expect(s.refreshCount, 1);
  });

  testWidgets('위에 라우트가 덮이면 보류 — pop 되면 1회', (WidgetTester tester) async {
    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: _Probe(key: key)));
    final _ProbeState s = key.currentState! as _ProbeState;

    final NavigatorState nav =
        tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SizedBox())));
    await tester.pumpAndSettle();

    s.handleResumed();
    expect(s.refreshCount, 0); // 덮여 있는 동안엔 보류

    nav.pop();
    await tester.pumpAndSettle();
    expect(s.refreshCount, 1); // 재노출 시 1회
  });
}
