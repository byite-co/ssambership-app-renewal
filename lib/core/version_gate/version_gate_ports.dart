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
