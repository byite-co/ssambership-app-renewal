import 'package:shared_preferences/shared_preferences.dart';

import 'version_gate_ports.dart';

/// G1: 마지막 통과 빌드를 shared_preferences 에 저장하는 운영 구현.
/// 저장소 실패는 전부 안에서 흡수한다(읽기 실패 = 캐시 없음).
class SharedPrefsGatePassCache implements GatePassCache {
  const SharedPrefsGatePassCache();

  static const String prefsKey = 'version_gate_last_pass_build';

  @override
  Future<int?> readLastPassBuild() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getInt(prefsKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeLastPassBuild(int build) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(prefsKey, build);
    } catch (_) {
      // 기록 실패 → 다음 오프라인 콜드스타트가 재시도 화면일 뿐(치명 아님).
    }
  }

  @override
  Future<void> clear() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey);
    } catch (_) {
      // 제거 실패 — 다음 성공 경로에서 다시 시도된다.
    }
  }
}
