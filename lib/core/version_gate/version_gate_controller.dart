import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'gate_platform.dart';
import 'supabase_version_policy_port.dart';
import 'version_gate_decision.dart';
import 'version_gate_ports.dart';
import 'version_policy.dart';

/// 게이트 표시 상태(셸이 이 상태만 보고 그린다).
/// - idle: start() 전 — 게이트 미개입(자식 그대로 표시. 위젯테스트 등 안전 기본값).
/// - skipped: 대상 플랫폼 아님(web 등) — 게이트 전체 건너뜀.
/// - checking: 정책 조회 중 — 진입 보류(로딩).
/// - pass: 정상 진입.
/// - forceUpdate: 진입 차단 + 스토어 유도(뒤로가기 불가).
/// - recommend: 권장 업데이트 안내(앱 실행당 1회, 닫기 가능).
/// - fetchFailed: 조회 실패 — '재시도' 화면(강제 업데이트로 취급 금지).
enum VersionGateStatus {
  idle,
  skipped,
  checking,
  pass,
  forceUpdate,
  recommend,
  fetchFailed,
}

/// 최소 지원 버전 게이트 컨트롤러.
///
/// main() 이 runApp 직전에 [start] 를 호출하고, 셸(VersionGateShell)이
/// ListenableBuilder 로 구독한다. 로그인 여부와 무관하게 동작한다(anon RPC).
/// DI 프레임워크 없이 생성자 주입 + 프로덕션 기본값(instance) 패턴.
class VersionGateController extends ChangeNotifier {
  VersionGateController({
    VersionPolicyPort? port,
    BuildNumberProvider? buildNumber,
    GatePlatformResolver? platformResolver,
  })  : _port = port ?? const SupabaseVersionPolicyPort(),
        _buildNumber = buildNumber ?? _packageInfoBuildNumber,
        _platformResolver = platformResolver ?? resolveGatePlatform;

  /// 프로덕션 싱글턴(main/app 배선용). 테스트는 생성자로 fake 를 주입한다.
  static final VersionGateController instance = VersionGateController();

  final VersionPolicyPort _port;
  final BuildNumberProvider _buildNumber;
  final GatePlatformResolver _platformResolver;

  VersionGateStatus _status = VersionGateStatus.idle;
  VersionPolicy? _policy;
  bool _recommendDismissed = false;

  VersionGateStatus get status => _status;

  /// forceUpdate/recommend 일 때의 정책(스토어 URL·안내 문구).
  VersionPolicy? get policy => _policy;

  /// 앱 시작 시 1회 호출(재시도 버튼도 이 함수를 다시 부른다).
  Future<void> start() async {
    final String? platform = _platformResolver();
    if (platform == null) {
      // web/desktop — 게이트 대상 아님. RPC 를 아예 호출하지 않는다
      // (서버는 android/ios 외 플랫폼에 INVALID_PLATFORM 을 던진다).
      _set(VersionGateStatus.skipped);
      return;
    }

    _set(VersionGateStatus.checking);

    final int? currentBuild = await _buildNumber();
    if (currentBuild == null) {
      // 빌드번호를 알 수 없음(파싱 실패 등) → 조회 없이 통과(fail-open).
      // 로컬 buildNumber 가 깨졌다고 앱을 벽돌로 만들면 안 된다 — 서버 게이트의
      // 목적은 '알려진 구버전' 차단이다. 로그도 남기지 않는다(개인정보·소음 없음).
      _set(VersionGateStatus.pass);
      return;
    }

    final VersionPolicy fetched;
    try {
      fetched = await _port.fetch(platform);
    } catch (_) {
      // 조회 실패는 강제 업데이트가 아니다 — 재시도 상태로만 표시.
      _set(VersionGateStatus.fetchFailed);
      return;
    }

    switch (decide(currentBuild: currentBuild, policy: fetched)) {
      case GatePass():
        _set(VersionGateStatus.pass);
      case GateForceUpdate(policy: final VersionPolicy p):
        _policy = p;
        _set(VersionGateStatus.forceUpdate);
      case GateRecommendUpdate(policy: final VersionPolicy p):
        if (_recommendDismissed) {
          // 앱 실행당 1회만 안내 — 이미 닫았다면 다시 띄우지 않는다.
          _set(VersionGateStatus.pass);
        } else {
          _policy = p;
          _set(VersionGateStatus.recommend);
        }
    }
  }

  /// 조회 실패 화면의 '재시도'.
  Future<void> retry() => start();

  /// 권장 안내 닫기 — 이번 실행 동안 다시 띄우지 않는다.
  void dismissRecommend() {
    _recommendDismissed = true;
    if (_status == VersionGateStatus.recommend) {
      _set(VersionGateStatus.pass);
    }
  }

  void _set(VersionGateStatus s) {
    _status = s;
    notifyListeners();
  }

  /// 프로덕션 빌드번호 제공자 — PackageInfo.buildNumber(문자열)를 정수로.
  /// 파싱 실패/플러그인 예외는 null(알 수 없음) — start() 가 fail-open 처리.
  static Future<int?> _packageInfoBuildNumber() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber);
    } catch (_) {
      return null;
    }
  }
}
