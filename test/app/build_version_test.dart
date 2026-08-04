import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 내부 테스트 빌드 메타데이터 계약.
///
/// versionCode 는 pubspec `version: x.y.z+N` 의 +N 에서 유래한다
/// (`android/app/build.gradle.kts` 가 flutter.* 로 위임 — HANDOFF §3-1-B).
/// Play 업로드마다 +N 은 반드시 증가해야 하므로(ANDROID_BUILD.md §versionCode),
/// 여기서 '이번 회차가 어떤 빌드인지'를 고정해 둔다 — 재업로드 시 이 테스트가
/// 먼저 깨져서 번호 증가를 강제한다.
///
/// vc14: vc13 과 동일 코드 — Play Console 이 versionCode 13 을 이미 소모한
/// 상태라("13 버전 코드는 이미 사용되었습니다") 번호만 14 로 올린 재패키징.
/// vc15: 전 기능 계약 수렴(2026-08-04) — 프로필/멘토/커뮤니티/IQ/알림/계정삭제
/// 클라이언트 계약 전환 후 릴리즈 후보. versionName 은 그대로 0.1.0.
void main() {
  test('pubspec version = 0.1.0+15 (versionName 0.1.0 / versionCode 15)', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? m = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(m, isNotNull, reason: 'pubspec.yaml 에 version: x.y.z+N 이 없다');
    expect(m!.group(1), '0.1.0', reason: 'versionName 은 이번 통합에서 바꾸지 않는다');
    expect(int.parse(m.group(2)!), 15,
        reason: 'versionCode 14 는 이미 소모된 통합 빌드 번호 — 수렴 릴리즈 후보는 '
            'versionCode 15 이어야 한다(base/기존통합/현재 브랜치 최대값 + 1)');
  });
}
