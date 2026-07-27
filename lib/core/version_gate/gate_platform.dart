import 'package:flutter/foundation.dart';

/// 게이트 대상 플랫폼 결정 — android/ios 에서만 게이트를 돌린다.
///
/// - kIsWeb → null (게이트 전체 건너뜀)
/// - android/ios 외(데스크톱 등) → null
///
/// 서버 RPC 는 android/ios 외 값에 INVALID_PLATFORM 을 던지므로,
/// 여기서 null 이면 아예 호출하지 않는 것이 계약이다.
String? resolveGatePlatform() {
  if (kIsWeb) return null;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    default:
      return null;
  }
}
