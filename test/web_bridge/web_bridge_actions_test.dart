import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/web_bridge/web_bridge.dart';
import 'package:ssambership_app/core/web_bridge/web_bridge_actions.dart';

Widget _button(Future<void> Function(BuildContext context) onTap) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext c) =>
              TextButton(onPressed: () => onTap(c), child: const Text('go')),
        ),
      ),
    );

void main() {
  // baseUrl 미확정(빈 값) 폴백을 명시 주입으로 검증한다.
  // (기본 WebBridgeConfig.baseUrl 은 이제 설정돼 있으므로 빈 브릿지를 주입해야
  //  '준비 중' 폴백 경로가 재현된다.)
  // A-4b ⑩: 결제·구독 관리/정산 관리 헬퍼는 삭제(앱이 직접 처리). 남는 헬퍼로 검증.
  testWidgets('미확정: 본인인증 → "본인인증은 웹에서" 안내', (WidgetTester tester) async {
    await tester.pumpWidget(_button((BuildContext c) =>
        openIdentityVerifyWeb(c, bridge: WebBridge(baseUrl: ''))));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('본인인증은 웹에서'), findsOneWidget);
  });

  testWidgets('미확정: 고객지원 → "고객지원은 웹에서" 안내', (WidgetTester tester) async {
    await tester.pumpWidget(_button((BuildContext c) =>
        openSupportWeb(c, bridge: WebBridge(baseUrl: ''))));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('고객지원은 웹에서'), findsOneWidget);
  });

  testWidgets('설정 완료(주입): 열기 성공 → 안내 없음 + 올바른 URL',
      (WidgetTester tester) async {
    final List<Uri> opened = <Uri>[];
    final WebBridge bridge = WebBridge(
      baseUrl: 'https://web.test',
      launcher: (Uri u) async {
        opened.add(u);
        return true;
      },
    );
    await tester.pumpWidget(
        _button((BuildContext c) => openIdentityVerifyWeb(c, bridge: bridge)));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(opened.length, 1);
    expect(opened.single.queryParameters['src'], 'app');
    // 열렸으므로 안내 스낵바 없음(웹으로 이동).
    expect(find.textContaining('웹에서'), findsNothing);
  });
}
