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
/// vc11: 빌드 10 실기기 QA 가 IQ 상세의 카드 스택 잔존을 확인 → 전체 화면
/// 대화방 재설계 교정 빌드. versionName 은 그대로 0.1.0.
void main() {
  test('pubspec version = 0.1.0+11 (versionName 0.1.0 / versionCode 11)', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? m = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(m, isNotNull, reason: 'pubspec.yaml 에 version: x.y.z+N 이 없다');
    expect(m!.group(1), '0.1.0', reason: 'versionName 은 이번 교정에서 바꾸지 않는다');
    expect(int.parse(m.group(2)!), 11,
        reason: '빌드 10 은 이미 내부 테스트에 올라갔다 — 교정 빌드는 11 이어야 한다');
  });
}
