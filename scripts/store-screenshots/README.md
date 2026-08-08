# 스토어 스크린샷 촬영 (Google Play · 폰 1080x1920)

## 실행 순서 (3줄)

1. `avd_setup.ps1` 실행 → `emulator -avd Ssambeship_Store_1080x1920` 부팅 → `flutter build apk --profile` 빌드 후 `adb install -r` 설치 → 로그인·데이터 준비
2. `demo_mode.ps1 on` (상태바 09:30 / 배터리 100% 고정) → `capture.ps1` 로 8장 순회 촬영 (화면은 손으로 이동, Enter 로 촬영)
3. `python verify.py` 로 규격 검증 (알파 채널 발견 시 `--fix`) → 전 장 PASS 확인 후 `demo_mode.ps1 off`

## 참고

- **targetSdk 36** 기준 시스템 이미지(`google_apis`, x86_64)를 사용한다. `google_apis_playstore` 는 adb root 가 막혀 금지.
- **density 는 반드시 420** (1080px ÷ 2.625 = 411dp). 480/320 이면 논리 폭이 360/540dp 로 바뀌어 레이아웃이 달라진다.
- **release 빌드는 `android/key.properties`(업로드 keystore) 없이는 의도적으로 실패**한다 (`build.gradle.kts` 가드). 스크린샷 용도는 `--profile` 빌드로 충분하다. debug 빌드는 디버그 배너가 찍히므로 금지.
- 출력 폴더: `build/store-screenshots/phone/` (git 미추적). 검증 기준: 각 변 320~3840px · 비율 ≤ 2.0 · PNG(알파 없음) · 8MB 이하 · 2~8장 · 추천 노출은 1080px 이상 4장.
- 에뮬레이터가 매우 느리면 Windows 기능에서 '가상 머신 플랫폼'(WHPX)을 켠다.
