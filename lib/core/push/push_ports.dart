// 알림 권한 '포트'(추상 경계) — **OS 푸시는 이번 출시 범위가 아니다**.
//
// App-F0 에서 Firebase/FCM SDK·초기화·디바이스 토큰·OS 알림 권한 요청을 전부
// 제거했다. 남은 것은 설정 화면이 참조하는 최소 추상뿐이며, 기본 구현은
// 아무 것도 하지 않는 [DisabledPushPermission] 다.
//
// ★ 앱 내 알림함(서버 notifications 조회·읽음·페이지네이션·18종 라우팅)은
//   그대로 유지된다 — 그것은 OS 푸시가 아니라 인앱 데이터다.
// ★ 여기에 어떤 구현도 '사용 가능한 것처럼' 두지 않는다. 권한을 요청하는
//   경로가 없으므로 [PushPermissionStatus.granted] 는 이 빌드에서 발생하지 않는다.

// 알림 권한 상태(플랫폼 무관 추상).
enum PushPermissionStatus {
  /// 아직 물어보지 않음 — OS 푸시 미도입 빌드의 고정값.
  notDetermined,

  /// 허용됨. 이 빌드에서는 발생하지 않는다(요청 경로 없음).
  granted,

  /// 거부됨. 이 빌드에서는 발생하지 않는다(요청 경로 없음).
  denied;

  bool get isGranted => this == PushPermissionStatus.granted;
}

/// OS 알림 권한 조회 포트. 이 빌드에는 실제 구현이 없다(요청하지 않는다).
abstract class PushPermissionPort {
  Future<PushPermissionStatus> current();
  Future<PushPermissionStatus> request();
}

/// 기본이자 유일한 구현 — 조회는 항상 미결정, 요청은 no-op.
/// 권한 팝업을 띄우지 않고 OS 푸시를 약속하지도 않는다.
class DisabledPushPermission implements PushPermissionPort {
  const DisabledPushPermission();

  @override
  Future<PushPermissionStatus> current() async =>
      PushPermissionStatus.notDetermined;

  @override
  Future<PushPermissionStatus> request() async =>
      PushPermissionStatus.notDetermined;
}
