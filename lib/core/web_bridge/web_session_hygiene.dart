/// WebView 세션(쿠키) 위생 — 로그아웃·계정 전환·작성 화면 여닫이 시 정리한다.
///
/// 사용자 A 의 WebView 쿠키를 사용자 B 가 재사용하지 못하게 하는 안전망이다.
/// 실제 정리 구현(webview_flutter 의 WebViewCookieManager)은 앱 부팅 시
/// [register] 로 주입한다 — 코어(auth)가 플러그인에 직접 의존하지 않게 하고,
/// 단위테스트(플러그인 채널 없음)에서는 자동 no-op 이 되게 한다.
class WebSessionHygiene {
  WebSessionHygiene._();

  static Future<void> Function()? _cleaner;

  /// 실제 쿠키 정리 구현 등록(앱 부팅 시 1회).
  static void register(Future<void> Function() cleaner) {
    _cleaner = cleaner;
  }

  /// 테스트 전용 초기화.
  static void resetForTest() {
    _cleaner = null;
  }

  /// WebView 쿠키/세션 정리. 미등록·실패 시 조용히 통과(앱 흐름을 막지 않는다).
  static Future<void> clear() async {
    final Future<void> Function()? cleaner = _cleaner;
    if (cleaner == null) return;
    try {
      await cleaner();
    } catch (_) {
      // 플러그인 미가용·플랫폼 오류 — 로그아웃/전환 흐름을 막지 않는다.
    }
  }
}
