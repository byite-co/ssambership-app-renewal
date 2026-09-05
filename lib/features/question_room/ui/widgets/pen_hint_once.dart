import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 사진 첨부 직후 펜(주석) 안내를 **한 번만** 띄우기 위한 기억(design-v3 §3-3).
///
/// 기기 저장(shared_preferences)이 정본이고, 저장소 접근에 실패하면 이번 실행
/// 동안만 기억한다(다음 실행에 다시 한 번 보여도 해가 없다).
class PenHintOnce {
  PenHintOnce._();

  static const String prefsKey = 'question_room_pen_hint_shown_v1';
  static bool _consumedThisRun = false;

  /// 아직 보여준 적 없으면 true 를 돌려주고 '보여줬음'으로 기록한다.
  static Future<bool> consume() async {
    if (_consumedThisRun) return false;
    _consumedThisRun = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(prefsKey) ?? false) return false;
      await prefs.setBool(prefsKey, true);
    } catch (_) {
      // 저장 실패 — 이번 실행은 인메모리로 기억.
    }
    return true;
  }

  @visibleForTesting
  static void reset() => _consumedThisRun = false;
}
