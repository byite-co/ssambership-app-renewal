import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// test/goldens/ 전용 테스트 설정(가장 가까운 flutter_test_config.dart 가 적용된다 —
/// 다른 테스트 디렉터리에는 영향이 없다).
///
/// 골든(PNG) 렌더 전에 pubspec `fonts:` 에 선언된 폰트(Pretendard 4종)와
/// MaterialIcons 를 실제로 로드한다. 기본 테스트 환경은 글리프를 사각형
/// 자리표시(FlutterTest 폰트)로 그리므로, 폰트를 로드하지 않으면 골든이
/// '디자인을 눈으로 보는' 용도로 쓸 수 없다.
///
/// 폰트 목록은 하드코딩하지 않고 빌드 산출물 FontManifest.json 을 읽는다 —
/// pubspec 에 폰트를 추가하면 골든에도 그대로 반영된다.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadAppFonts();
  await testMain();
}

Future<void> loadAppFonts() async {
  final String manifest = await rootBundle.loadString('FontManifest.json');
  final List<dynamic> families = json.decode(manifest) as List<dynamic>;
  for (final dynamic raw in families) {
    final Map<String, dynamic> family = raw as Map<String, dynamic>;
    final String name = family['family'] as String;
    final FontLoader loader = FontLoader(name);
    for (final dynamic font in family['fonts'] as List<dynamic>) {
      final String asset = (font as Map<String, dynamic>)['asset'] as String;
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
}
