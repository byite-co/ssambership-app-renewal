import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/version_gate/version_gate_controller.dart';

import 'version_gate_fakes.dart';

/// VersionGateController — 시작/재시도/닫기 상태 전이(가짜 포트·주입 빌드번호).
void main() {
  VersionGateController make({
    required FakeVersionPolicyPort port,
    int? build = 1,
    String? platform = 'android',
  }) {
    return VersionGateController(
      port: port,
      buildNumber: () async => build,
      platformResolver: () => platform,
    );
  }

  test('현재 빌드(1)가 시드 정책(min=1)을 통과한다', () async {
    final FakeVersionPolicyPort port =
        FakeVersionPolicyPort(policy: policyOf(min: 1, latest: 1));
    final VersionGateController c = make(port: port, build: 1);

    await c.start();

    expect(c.status, VersionGateStatus.pass);
    expect(port.sentPlatforms, <String>['android']); // 유효 플랫폼만 전송
  });

  test('구버전(min=5, current=1) → 강제 업데이트 + 정책 보존', () async {
    final FakeVersionPolicyPort port = FakeVersionPolicyPort(
        policy: policyOf(min: 5, latest: 5, message: '업데이트 필요'));
    final VersionGateController c = make(port: port, build: 1);

    await c.start();

    expect(c.status, VersionGateStatus.forceUpdate);
    expect(c.policy?.message, '업데이트 필요');
  });

  test('권장(min=1, latest=9, current=1) → recommend, 닫으면 실행당 1회로 끝', () async {
    final FakeVersionPolicyPort port =
        FakeVersionPolicyPort(policy: policyOf(min: 1, latest: 9));
    final VersionGateController c = make(port: port, build: 1);

    await c.start();
    expect(c.status, VersionGateStatus.recommend);

    c.dismissRecommend();
    expect(c.status, VersionGateStatus.pass);

    // 같은 실행에서 재검사가 일어나도 다시 띄우지 않는다(실행당 1회).
    await c.start();
    expect(c.status, VersionGateStatus.pass);
  });

  test('조회 실패 → fetchFailed(강제 업데이트 아님), 재시도 성공 → pass', () async {
    final FakeVersionPolicyPort port = FakeVersionPolicyPort(
        policy: policyOf(min: 1, latest: 1), failing: true);
    final VersionGateController c = make(port: port, build: 1);

    await c.start();
    expect(c.status, VersionGateStatus.fetchFailed);
    expect(c.status, isNot(VersionGateStatus.forceUpdate));

    port.failing = false; // 네트워크 회복
    await c.retry();
    expect(c.status, VersionGateStatus.pass);
  });

  test('웹/미대상 플랫폼(resolver=null) → 게이트 건너뜀 + RPC 미호출', () async {
    // kIsWeb 이거나 android/ios 가 아니면 resolver 가 null 을 돌려준다 —
    // 서버에 INVALID_PLATFORM 을 유발할 값은 아예 전송되지 않는다.
    final FakeVersionPolicyPort port =
        FakeVersionPolicyPort(policy: policyOf(min: 99));
    final VersionGateController c = make(port: port, platform: null);

    await c.start();

    expect(c.status, VersionGateStatus.skipped);
    expect(port.fetchCount, 0);
  });

  test('빌드번호 알 수 없음(null) → 차단 없이 통과(fail-open) + RPC 생략', () async {
    // buildNumber 파싱 실패가 앱을 벽돌로 만들면 안 된다(컨트롤러 주석 참고).
    final FakeVersionPolicyPort port =
        FakeVersionPolicyPort(policy: policyOf(min: 99, latest: 99));
    final VersionGateController c = make(port: port, build: null);

    await c.start();

    expect(c.status, VersionGateStatus.pass);
    expect(port.fetchCount, 0);
  });

  test('시작 전(idle)에는 게이트가 개입하지 않는다(셸이 자식을 그대로 그림)', () {
    final VersionGateController c =
        make(port: FakeVersionPolicyPort(policy: policyOf()));
    expect(c.status, VersionGateStatus.idle);
  });
}
