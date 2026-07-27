import 'version_policy.dart';

/// 버전 게이트 순수 판정 결과.
/// - [GatePass]: 정상 진입.
/// - [GateForceUpdate]: 최소 지원 빌드 미만 — 진입 차단 + 스토어 유도.
/// - [GateRecommendUpdate]: 최소는 충족하지만 최신 빌드가 더 높음 — 닫을 수 있는 권장 안내.
///
/// 조회 실패(네트워크/클라이언트 없음)는 판정이 아니라 별도 상태(재시도)로
/// 다룬다 — 컨트롤러(version_gate_controller.dart) 참고.
sealed class VersionGateDecision {
  const VersionGateDecision();
}

class GatePass extends VersionGateDecision {
  const GatePass();
}

class GateForceUpdate extends VersionGateDecision {
  const GateForceUpdate(this.policy);
  final VersionPolicy policy;
}

class GateRecommendUpdate extends VersionGateDecision {
  const GateRecommendUpdate(this.policy);
  final VersionPolicy policy;
}

/// 순수 판정 함수 — **정수 빌드번호만** 비교한다(버전명 문자열 비교 금지).
///
/// [currentBuild] == null(빌드번호 파싱 실패 등 '알 수 없음')이면 통과(fail-open):
/// 로컬 buildNumber 가 깨졌다고 앱을 벽돌로 만들면 안 된다. 서버 게이트의 목적은
/// '알려진 구버전' 차단이지, 식별 불가 빌드의 차단이 아니다.
VersionGateDecision decide({
  required int? currentBuild,
  required VersionPolicy policy,
}) {
  if (currentBuild == null) return const GatePass();
  if (currentBuild < policy.minSupportedBuild) return GateForceUpdate(policy);
  if (policy.latestBuild > currentBuild) return GateRecommendUpdate(policy);
  return const GatePass();
}
