import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/version_gate/gate_platform.dart';

/// resolveGatePlatform — android/ios 만 게이트 대상. 그 외는 null(건너뜀)이라
/// 서버에 INVALID_PLATFORM 을 유발할 값이 애초에 전송되지 않는다.
/// (kIsWeb 은 컴파일 상수라 VM 테스트에서 직접 못 바꾼다 — 웹 건너뜀 자체는
///  컨트롤러 테스트에서 resolver=null 주입으로 검증한다.)
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('android → "android"', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(resolveGatePlatform(), 'android');
  });

  test('iOS → "ios"', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(resolveGatePlatform(), 'ios');
  });

  test('데스크톱(macOS/linux/windows) → null(게이트 건너뜀)', () {
    for (final TargetPlatform p in <TargetPlatform>[
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.fuchsia,
    ]) {
      debugDefaultTargetPlatformOverride = p;
      expect(resolveGatePlatform(), isNull, reason: '$p 는 게이트 대상이 아니다');
    }
  });
}
