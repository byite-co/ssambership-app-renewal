import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/version_gate/version_gate_screens.dart';

import 'version_gate_fakes.dart';

/// ForceUpdateScreen — 뒤로가기 차단 + 스토어 버튼(열기 전 URL 재검증).
void main() {
  final List<Uri> launched = <Uri>[];
  Future<bool> fakeLauncher(Uri uri) async {
    launched.add(uri);
    return true;
  }

  setUp(launched.clear);

  Widget host({required String storeUrl, String message = ''}) {
    return MaterialApp(
      home: ForceUpdateScreen(
        policy: policyOf(
          min: 5,
          latest: 5,
          storeUrl: storeUrl,
          message: message,
          minimumVersionName: '1.2.0',
        ),
        launcher: fakeLauncher,
      ),
    );
  }

  testWidgets('뒤로가기 차단: PopScope(canPop:false) + maybePop 이 진입을 소비한다',
      (WidgetTester tester) async {
    await tester.pumpWidget(host(storeUrl: 'https://play.google.com/x'));

    // 1) 선언 검증 — canPop:false.
    final PopScope<Object?> popScope = tester.widget<PopScope<Object?>>(
      find.byWidgetPredicate((Widget w) => w is PopScope<Object?>),
    );
    expect(popScope.canPop, isFalse);

    // 2) 동작 검증 — 시스템 뒤로가기(maybePop)가 '처리됨(true)'으로 소비되어
    //    앱 종료/이탈로 새어나가지 않고, 화면도 그대로 남는다.
    final NavigatorState navigator =
        tester.state<NavigatorState>(find.byType(Navigator));
    expect(await navigator.maybePop(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('업데이트가 필요해요'), findsOneWidget);
  });

  testWidgets('앱으로 들어가는 동선이 없다 — 버튼은 스토어 버튼뿐', (WidgetTester tester) async {
    await tester.pumpWidget(host(storeUrl: 'https://play.google.com/x'));

    expect(find.text('스토어에서 업데이트'), findsOneWidget);
    // '닫기/건너뛰기/재시도' 류 우회 동선 없음.
    expect(find.byType(TextButton), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('스토어 버튼: 허용 호스트(https://play.google.com)는 연다',
      (WidgetTester tester) async {
    await tester
        .pumpWidget(host(storeUrl: 'https://play.google.com/store/apps/x'));

    await tester.tap(find.text('스토어에서 업데이트'));
    await tester.pumpAndSettle();

    expect(launched, hasLength(1));
    expect(launched.single.host, 'play.google.com');
  });

  testWidgets('스토어 버튼: 허용 밖 호스트(https://evil.com)는 열지 않고 안내만',
      (WidgetTester tester) async {
    // 서버가 검증해 내려주더라도 앱이 열기 직전 재검증한다(최종 방어선).
    await tester.pumpWidget(host(storeUrl: 'https://evil.com/store'));

    await tester.tap(find.text('스토어에서 업데이트'));
    await tester.pumpAndSettle();

    expect(launched, isEmpty);
    expect(find.text('스토어를 열 수 없어요. 스토어에서 직접 업데이트해 주세요.'), findsOneWidget);
  });

  testWidgets('스토어 버튼: http 스킴(http://play.google.com)도 차단',
      (WidgetTester tester) async {
    await tester.pumpWidget(host(storeUrl: 'http://play.google.com/x'));

    await tester.tap(find.text('스토어에서 업데이트'));
    await tester.pumpAndSettle();

    expect(launched, isEmpty);
    expect(find.text('스토어를 열 수 없어요. 스토어에서 직접 업데이트해 주세요.'), findsOneWidget);
  });

  testWidgets('스토어 URL 누락(빈 문자열) → 열지 않고 안내만', (WidgetTester tester) async {
    await tester.pumpWidget(host(storeUrl: ''));

    await tester.tap(find.text('스토어에서 업데이트'));
    await tester.pumpAndSettle();

    expect(launched, isEmpty);
    expect(find.text('스토어를 열 수 없어요. 스토어에서 직접 업데이트해 주세요.'), findsOneWidget);
  });

  testWidgets('서버 message 가 있으면 그대로, 없으면 기본 문구', (WidgetTester tester) async {
    await tester.pumpWidget(host(
        storeUrl: 'https://play.google.com/x', message: '보안 문제로 업데이트가 필요해요.'));
    expect(find.text('보안 문제로 업데이트가 필요해요.'), findsOneWidget);

    await tester.pumpWidget(host(storeUrl: 'https://play.google.com/x'));
    await tester.pumpAndSettle();
    expect(find.text('새 버전으로 업데이트해야 계속 이용할 수 있어요.'), findsOneWidget);
  });
}
