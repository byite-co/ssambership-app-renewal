import 'version_policy.dart';

/// 버전 정책 조회 포트. 실패는 예외로 던진다(컨트롤러가 '재시도' 상태로 변환).
abstract class VersionPolicyPort {
  /// [platform] 은 'android' | 'ios' 만 온다 — 게이트가 그 외 플랫폼에서는
  /// 아예 호출하지 않는다(gate_platform.dart).
  Future<VersionPolicy> fetch(String platform);
}

/// 현재 앱의 정수 빌드번호 제공자(테스트 주입용).
/// null = 알 수 없음(파싱 실패 등) → 게이트는 차단하지 않는다(fail-open).
typedef BuildNumberProvider = Future<int?> Function();

/// 게이트 대상 플랫폼 결정자(테스트 주입용).
/// 'android' | 'ios' 를 반환하고, 그 외(web/desktop)는 null = 게이트 건너뜀.
typedef GatePlatformResolver = String? Function();

/// G1: 마지막 게이트 통과 빌드 저장소(오프라인 콜드스타트 완화).
///
/// 통과(pass/recommend)한 빌드를 기억해 두고, 정책 조회 실패 시 같은 빌드면
/// 재시도 화면 대신 입장을 허용한다. forceUpdate 판정이 나오면 지운다 —
/// 강제 업데이트 대상 빌드가 오프라인 재시작으로 우회하는 것을 막는다.
/// 모든 구현은 실패를 안에서 흡수한다(캐시는 보조 수단 — 게이트를 못 막는다).
abstract class GatePassCache {
  Future<int?> readLastPassBuild();
  Future<void> writeLastPassBuild(int build);
  Future<void> clear();
}
