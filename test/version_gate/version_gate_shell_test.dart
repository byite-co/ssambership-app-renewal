import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/version_gate/version_gate_controller.dart';
import 'package:ssambership_app/core/version_gate/version_gate_shell.dart';

import 'version_gate_fakes.dart';

/// VersionGateShell — 상태별로 자식(앱 내용)을 가리거나 통과시키는 배선 검증.
void main() {
  const Widget appChild = Scaffold(body: Text('앱 내용'));

  Future<bool> neverLaunch(Uri uri) async => false;

  Widget host(VersionGateController controller) {
    return MaterialApp(
      home: VersionGateShell(
        controller: controller,
        storeLauncher: neverLaunch,
        child: appChild,
      ),
    );
  }

  VersionGateController make(FakeVersionPolicyPort port, {int? build = 1}) {
    return VersionGateController(
      port: port,
      buildNumber: () async => build,
      platformResolver: () => 'android',
    );
  }

  testWidgets('통과(pass)면 자식이 그대로 보인다', (WidgetTester tester) async {
    final VersionGateController c =
        make(FakeVersionPolicyPort(policy: policyOf(min: 1, latest: 1)));
    await c.start();

    await tester.pumpWidget(host(c));

    expect(find.text('앱 내용'), findsOneWidget);
  });

  testWidgets('강제 업데이트면 자식이 아예 그려지지 않는다(진입 차단)', (WidgetTester tester) async {
    final VersionGateController c =
        make(FakeVersionPolicyPort(policy: policyOf(min: 5, latest: 5)));
    await c.start();

    await tester.pumpWidget(host(c));

    expect(find.text('업데이트가 필요해요'), findsOneWidget);
    expect(find.text('앱 내용'), findsNothing);
  });

  testWidgets('조회 실패면 재시도 화면(강제 업데이트 아님) → 재시도 성공 시 자식 진입',
      (WidgetTester tester) async {
    final FakeVersionPolicyPort port = FakeVersionPolicyPort(
        policy: policyOf(min: 1, latest: 1), failing: true);
    final VersionGateController c = make(port);
    await c.start();

    await tester.pumpWidget(host(c));

    expect(find.text('재시도'), findsOneWidget);
    expect(find.text('업데이트가 필요해요'), findsNothing); // 강제 업데이트로 오판 금지
    expect(find.text('앱 내용'), findsNothing);

    port.failing = false; // 네트워크 회복 후 재시도
    await tester.tap(find.text('재시도'));
    await tester.pumpAndSettle();

    expect(find.text('앱 내용'), findsOneWidget);
  });

  testWidgets('권장 업데이트: 자식 위 배너 — 닫으면 사라지고 실행당 1회로 끝',
      (WidgetTester tester) async {
    final VersionGateController c =
        make(FakeVersionPolicyPort(policy: policyOf(min: 1, latest: 9)));
    await c.start();

    await tester.pumpWidget(host(c));

    // 차단이 아니다 — 자식과 배너가 함께 보인다.
    expect(find.text('앱 내용'), findsOneWidget);
    expect(find.text('새 버전이 나왔어요.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('새 버전이 나왔어요.'), findsNothing);
    expect(find.text('앱 내용'), findsOneWidget);

    // 같은 실행에서 재검사가 일어나도 배너는 다시 뜨지 않는다.
    await c.start();
    await tester.pumpAndSettle();
    expect(find.text('새 버전이 나왔어요.'), findsNothing);
  });

  testWidgets('검사 중(checking)에는 자식 대신 로딩 — 진입 보류', (WidgetTester tester) async {
    // 빌드번호 조회를 Completer 로 붙잡아 checking 프레임을 고정한다.
    final Completer<int?> buildGate = Completer<int?>();
    final VersionGateController c = VersionGateController(
      port: FakeVersionPolicyPort(policy: policyOf(min: 1, latest: 1)),
      buildNumber: () => buildGate.future,
      platformResolver: () => 'android',
    );

    final Future<void> started = c.start();
    await tester.pumpWidget(host(c));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('앱 내용'), findsNothing);

    buildGate.complete(1); // 조회 완료 → 통과
    await started;
    await tester.pumpAndSettle();
    expect(find.text('앱 내용'), findsOneWidget);
  });

  testWidgets('idle(시작 전)·skipped(웹 등)면 게이트 미개입 — 자식 그대로',
      (WidgetTester tester) async {
    // idle: 위젯테스트 등 start() 가 불리지 않은 환경에서 앱을 잠그지 않는다.
    final VersionGateController idle =
        make(FakeVersionPolicyPort(policy: policyOf(min: 99)));
    await tester.pumpWidget(host(idle));
    expect(find.text('앱 내용'), findsOneWidget);

    // skipped: 미대상 플랫폼(web/desktop) — RPC 자체를 부르지 않는다.
    final FakeVersionPolicyPort port =
        FakeVersionPolicyPort(policy: policyOf(min: 99));
    final VersionGateController skipped = VersionGateController(
      port: port,
      buildNumber: () async => 1,
      platformResolver: () => null, // kIsWeb 등
    );
    await skipped.start();
    await tester.pumpWidget(host(skipped));

    expect(find.text('앱 내용'), findsOneWidget);
    expect(port.fetchCount, 0);
  });
}
