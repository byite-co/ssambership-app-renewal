import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/push/push_ports.dart';

/// App-F0 회귀 잠금: 출시 범위에서 Firebase/FCM·디바이스 토큰·OS 알림 권한이
/// **다시 들어오지 않도록** 소스 트리를 직접 검사한다.
///
/// 런타임 mock 이 아니라 소스/설정 검사인 이유: 제거 대상은 '호출'이 아니라
/// '의존성과 선언' 자체다. 코드가 다시 추가되면 여기서 즉시 깨진다.
void main() {
  String read(String path) => File(path).readAsStringSync();

  bool exists(String path) => File(path).existsSync();

  group('App-F0 — Firebase/FCM 미도입 고정', () {
    test('pubspec 에 Firebase 직접 의존성이 없다', () {
      final String pubspec = read('pubspec.yaml');
      expect(pubspec.contains('firebase_core'), isFalse);
      expect(pubspec.contains('firebase_messaging'), isFalse);
    });

    test('Firebase 구현 파일이 존재하지 않는다(게이트웨이·토큰 등록기·서비스)', () {
      expect(exists('lib/core/push/firebase_push_gateway.dart'), isFalse);
      expect(exists('lib/core/push/device_token_registrar.dart'), isFalse);
      expect(exists('lib/core/push/push_service.dart'), isFalse);
    });

    test('앱 시작(main)에서 Firebase 초기화·토큰 등록 호출이 0회다', () {
      final String main = read('lib/main.dart');
      expect(main.contains('Firebase.initializeApp'), isFalse);
      expect(main.contains('FirebaseMessaging'), isFalse);
      expect(main.contains('PushService'), isFalse);
      // 토큰 등록 진입점 자체가 없다.
      expect(main.contains('registerDeviceToken'), isFalse);
      expect(main.contains('getToken'), isFalse);
    });

    test('lib 전체에 Firebase import·백그라운드 핸들러·토큰 RPC 가 0건이다', () {
      final List<File> darts = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
      expect(darts, isNotEmpty);

      for (final File f in darts) {
        final String src = f.readAsStringSync();
        expect(src.contains('package:firebase_core'), isFalse,
            reason: '${f.path} 에 firebase_core import');
        expect(src.contains('package:firebase_messaging'), isFalse,
            reason: '${f.path} 에 firebase_messaging import');
        expect(src.contains('Firebase.initializeApp'), isFalse,
            reason: '${f.path} 에 Firebase 초기화');
        expect(src.contains('FirebaseMessaging'), isFalse,
            reason: '${f.path} 에 FirebaseMessaging 사용');
        expect(src.contains('vm:entry-point'), isFalse,
            reason: '${f.path} 에 백그라운드 핸들러 엔트리포인트');
        expect(src.contains('register_device_token'), isFalse,
            reason: '${f.path} 에 디바이스 토큰 등록 RPC');
      }
    });

    test('Android 매니페스트에 알림 런타임 권한 선언이 없다', () {
      final String manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(manifest.contains('POST_NOTIFICATIONS'), isFalse);
      // 인터넷 권한은 Supabase 통신에 필요하므로 유지되어야 한다(회귀 방지).
      expect(manifest.contains('android.permission.INTERNET'), isTrue);
    });

    test('Google Services plugin·설정 파일이 0건이다', () {
      for (final String path in <String>[
        'android/build.gradle.kts',
        'android/app/build.gradle.kts',
        'android/settings.gradle.kts',
      ]) {
        if (!exists(path)) continue;
        final String gradle = read(path);
        expect(gradle.contains('com.google.gms'), isFalse, reason: path);
        expect(gradle.contains('google-services'), isFalse, reason: path);
      }
      expect(exists('android/app/google-services.json'), isFalse);
      expect(exists('ios/Runner/GoogleService-Info.plist'), isFalse);
    });
  });

  group('App-F0 — 권한 포트는 no-op 으로만 남는다', () {
    test('DisabledPushPermission 은 조회·요청 모두 미결정(권한 팝업 없음)', () async {
      const PushPermissionPort port = DisabledPushPermission();
      expect(await port.current(), PushPermissionStatus.notDetermined);
      expect(await port.request(), PushPermissionStatus.notDetermined);
    });

    test('허용 상태를 만들어내는 구현이 없다 — granted 는 이 빌드에서 발생하지 않는다', () async {
      const PushPermissionPort port = DisabledPushPermission();
      final PushPermissionStatus status = await port.request();
      expect(status.isGranted, isFalse);
    });
  });
}
