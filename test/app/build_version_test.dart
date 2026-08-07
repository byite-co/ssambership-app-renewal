import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 내부 테스트 빌드 메타데이터 계약.
///
/// versionCode 는 pubspec `version: x.y.z+N` 의 +N 에서 유래한다
/// (`android/app/build.gradle.kts` 가 flutter.* 로 위임 — HANDOFF §3-1-B).
/// iOS 도 같은 값을 쓴다 — `Info.plist` 의 `CFBundleShortVersionString` /
/// `CFBundleVersion` 이 `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)` 이고,
/// Runner 타깃의 `CURRENT_PROJECT_VERSION` 도 `$(FLUTTER_BUILD_NUMBER)` 다.
/// 즉 pubspec 이 두 플랫폼의 **단일 정본**이다(리터럴 버전은 RunnerTests 전용).
///
/// Play/App Store 업로드마다 +N 은 반드시 증가해야 하므로
/// (ANDROID_BUILD.md §versionCode), 여기서 '이번 회차가 어떤 빌드인지'를 고정해
/// 둔다 — 재업로드 시 이 테스트가 먼저 깨져서 번호 증가를 강제한다.
///
/// vc14: vc13 과 동일 코드 — Play Console 이 versionCode 13 을 이미 소모한
/// 상태라("13 버전 코드는 이미 사용되었습니다") 번호만 14 로 올린 재패키징.
/// vc15: 전 기능 계약 수렴(2026-08-04) — 프로필/멘토/커뮤니티/IQ/알림/계정삭제
/// 클라이언트 계약 전환 후 릴리즈 후보. versionName 은 그대로 0.1.0.
/// vc16: release-prebuild 수렴(2026-08-05) — PR #44(IQ 미디어 귀속·첨삭·브랜딩)와
/// PR #43(iOS 출시 설정)이 master 에 통합된 뒤의 출시 후보.
/// versionName 을 **1.0.0** 으로 올린다(첫 정식 출시 표기).
/// vc18: Play Console 실측(2026-08-06, 오너 확인) — versionCode **16과 17은
/// 이미 사용됨**. 코드 변경 없이 번호만 18 로 올린 release candidate.
/// vc19: 실기기 QA(2026-08-06) 후속 앱 수정 반영(S3) — 상태칩 색 충돌(C4),
/// 개별질문 타임라인 스크롤 수렴(C8·C9), 멘토 첨부 전 주석 배선(C3),
/// 개별질문 요구 조건 표시(B6), 열어둔 글 삭제 감지(C6). 코드가 바뀌었으므로
/// 새 versionCode 로 올린다.
/// vc22: App Store Connect 실측(2026-08-07, 오너 확인) — build 20·21 이 이미
/// 존재한다. 여기에 2026-08-07 앱 수정 2건(커뮤니티 필터 칩 선택 표시 수정,
/// IQ 조건 칩 과목 코드 한글 라벨 변환)을 반영한 iOS 출시 후보로 22 로 올린다.
///
/// ⚠️ 외부 스토어 이력은 이 컨테이너에서 조회할 수 없다 — 위 vc18·vc19 근거는
/// 오너가 Play Console 에서 직접 확인해 전달한 값이다. **이미 19 이상이
/// 업로드돼 있다면 그보다 큰 최소값으로 올리고 이 테스트도 함께 갱신해야
/// 한다** — 확인 책임은 업로드 직전 오너에게 있다.
void main() {
  test('pubspec version = 1.0.0+22 (versionName 1.0.0 / versionCode 22)', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? m = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(m, isNotNull, reason: 'pubspec.yaml 에 version: x.y.z+N 이 없다');
    expect(m!.group(1), '1.0.0',
        reason: 'release-prebuild 수렴에서 versionName 을 1.0.0 으로 올린다');
    expect(int.parse(m.group(2)!), 22,
        reason: 'App Store Connect 실측(2026-08-07)상 build 21 까지 이미 존재하고 '
            '앱 코드가 바뀐(2026-08-07 수정 2건) 이번 후보는 22 다'
            '(재상향 규칙은 파일 상단 주석)');
  });

  test('앱 표시 버전 상수가 pubspec versionName 과 일치한다', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final String? versionName = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$',
      multiLine: true,
    ).firstMatch(pubspec)?.group(1);
    final String constants =
        File('lib/shared/constants/app_constants.dart').readAsStringSync();

    expect(versionName, isNotNull);
    expect(constants, contains("static const String appVersion = '$versionName'"),
        reason: '마이페이지 표시 버전(AppConstants.appVersion)이 pubspec 과 어긋나면 '
            '사용자에게 잘못된 버전이 보인다');
  });
}
