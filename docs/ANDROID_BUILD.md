# Android 빌드 가이드 (ssambership_app)

단일 Flutter 코드베이스 — iOS 와 동일한 기능·UI·UX·디자인. 상세 원칙은 README·HANDOFF.md 참고.

## 요구 사항
- Flutter SDK 3.22 이상 (`flutter doctor` 로 Android toolchain ✓ 확인)
- Android Studio (SDK 36 + 에뮬레이터) — JDK 17 은 Android Studio 내장 사용 가능
- gradlew 스크립트는 커밋되지 않음(.gitignore) — Flutter 도구가 자동 생성/관리하므로 별도 조치 불필요

## 1회 셋업
```bash
git clone https://github.com/byite1226-a11y/ssambership-app.git
cd ssambership-app
cp .env.example .env        # SUPABASE_ANON_KEY 등 값 채우기 (README 참고)
flutter pub get
```

## 실행
```bash
flutter emulators --launch <에뮬레이터ID>   # 또는 Android Studio 에서 AVD 실행
flutter run
```

- **에뮬레이터**: `.env` 의 `SUPABASE_URL=http://127.0.0.1:54321` 그대로 두면 코드가
  자동으로 `10.0.2.2` 로 변환한다 (`lib/core/config/app_config.dart`).
- **실기기(개발)**: `.env` 의 `SUPABASE_URL_LAN` 에 PC 의 LAN IP (`http://192.168.x.x:54321`) 입력.
- 로컬 http 통신은 **debug/profile 빌드에서만** 허용된다
  (`android/app/src/debug|profile/AndroidManifest.xml` 의 `usesCleartextTraffic`).
  release 는 cleartext 차단 유지 → 출시는 반드시 원격 `https://<ref>.supabase.co` 사용.

## 릴리즈 서명
1. keystore 생성(1회, 절대 커밋 금지):
   ```bash
   keytool -genkey -v -keystore ~/ssambership-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias ssambership
   ```
2. `android/key.properties.example` → `android/key.properties` 복사 후 값 입력
   (storeFile 경로·비밀번호·alias). `.gitignore` 가 커밋을 차단한다.
3. key.properties 가 없으면 release 산출물(`flutter build appbundle`/`apk`) 빌드가
   **즉시 실패**한다 — debug 서명 AAB 가 실수로 Play 에 첫 업로드돼 잘못된 업로드 인증서가
   등록되는 사고를 원천 차단한다.
   - CI 파이프라인 검증처럼 debug 서명 폴백이 **의도된** 경우에만
     `-PallowInsecureSigning=true` (또는 env `ORG_GRADLE_PROJECT_allowInsecureSigning=true`)
     로 빌드한다. 이 산출물은 스토어 제출 불가(NOT-for-submission).

## 출시 빌드
```bash
flutter build appbundle     # Play Store 업로드용 .aab → build/app/outputs/bundle/release/
flutter build apk           # 직접 배포용 .apk (필요 시)
```
- 업로드마다 `pubspec.yaml` 의 `version: x.y.z+N` 에서 **+N(versionCode) 반드시 증가**.
  (첫 내부 테스트 업로드는 `0.1.0+1` 그대로 사용 가능.)
- targetSdk 36 고정 — Google Play 2026-08-31 신규 앱 요건 충족.
- 업로드 전 **서명 인증서 확인**(debug 아님):
  ```bash
  keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
  ```
  출력의 인증서 소유자에 `CN=Android Debug` 가 **없어야** 한다. 있으면 key.properties
  없이(또는 `-PallowInsecureSigning=true` 로) 빌드된 것 — 업로드 금지, release 키로 재빌드.

## signed release-candidate workflow (CI 수동 검증)

`.github/workflows/android-signed-release-candidate.yml` — **검증 전용** 수동 workflow.
release keystore 로 서명한 AAB 를 만들고 서명·manifest·내장 env 를 검증한다.
**Play Console 업로드는 하지 않는다**(업로드 step 자체가 없다).

- **실행 전제**: `workflow_dispatch` 는 workflow 파일이 **기본 브랜치(master)에
  병합된 이후에만** 실행할 수 있다(GitHub 제약). PR 단계에서는 실행 불가.
- **빌드 대상 고정**: `SOURCE_SHA`(PR #51 head, `1.0.0+18`)가 workflow 안에
  상수로 고정돼 있다 — 임의 SHA 입력 불가. PR #51 head 가 이동하면
  `BLOCKED_APP_PR_HEAD_MOVED` 로 빌드하지 않는다. 대상 SHA 를 바꾸려면
  workflow 파일 수정 → 리뷰 → master 병합을 다시 거친다.
- **수동 확인 입력**(dispatch 시 둘 다 체크해야 job 시작):
  `confirm_version_code_18_unused`(Play Console 에서 versionCode 18 미사용 직접
  확인 — API 검증 대체가 아닌 사람 확인 기록), `confirm_no_store_upload`.
- **GitHub Environment**: `android-release-candidate` — 다음 Environment secrets
  필요(사람이 등록; 저장소·로그에 값이 남지 않는다):
  `SUPABASE_URL` `SUPABASE_ANON_KEY` `SENTRY_DSN` `ANDROID_KEYSTORE_BASE64`
  `ANDROID_KEYSTORE_PASSWORD` `ANDROID_KEY_ALIAS` `ANDROID_KEY_PASSWORD`.
  Environment 에 required reviewers 를 설정하면 승인 전에는 secret 을 쓸 수 없다.
  `SENTRY_ENVIRONMENT` 는 workflow 가 `production` 으로 고정 주입한다.
- **검증 체인**: SOURCE_SHA·PR head 일치 → `.env` 생성(정본 URL 정확 일치) →
  preflight(`tool/validate_release_env.dart`) → analyze·test(1469) →
  `flutter build appbundle --release`(keystore 서명, insecure 폴백 없음) →
  jarsigner + 인증서 fingerprint 대조(debug 인증서 즉시 실패) →
  bundletool(버전·checksum 고정) manifest 대조(applicationId/1.0.0/18/24/36) →
  AAB 내장 `.env` 판정(YES/NO 만) → artifact(AAB+요약+sha256, retention 3일) →
  cleanup(`always()` — .env/key.properties/keystore 제거).
- **secret 규칙**: 로그에는 YES/NO 판정만 남는다. `printenv`·`set -x`·값/길이/
  host 출력 금지. `.env`/`key.properties`/keystore 는 artifact 에 포함하지 않는다.
- 계약 테스트: `test/contracts/android_signed_workflow_contract_test.dart` 가
  위 금지·고정 사항을 YAML 파싱으로 강제한다.

## 알려진 상태 / 후속 작업
- **푸시 알림(FCM)**: 코드·서버 계약 완료, **`WAITING_EXTERNAL_FIREBASE_CONFIG`** — 앱에
  Firebase 설정 파일이 없어서 런타임 비활성 상태로 대기한다(절차: `lib/core/push/HANDOFF.md`).
  - 구현: `firebase_core`/`firebase_messaging`(`pubspec.yaml:40-41`), `FirebasePushGateway`
    (`lib/core/push/firebase_push_gateway.dart`), device token 등록/철회
    (`SupabaseDeviceTokenRegistrar` — RPC `register_device_token`, 스테이징 검증 2026-07-21),
    `POST_NOTIFICATIONS` 권한(`android/app/src/main/AndroidManifest.xml`) 모두 반영됨.
  - **활성화 조건**: `android/app/google-services.json`(+ Gradle `com.google.gms.google-services`
    플러그인)이 있어야 `FirebasePushGateway.initialize()` 가 성공한다. 파일이 없으면
    `initialize()` 가 조용히 실패(`ready=false`)해 토큰을 발급/등록하지 않고 앱은 그대로 동작한다.
  - ⚠️ **Data safety 영향**: 설정 파일 **없이** 빌드한 AAB 는 device token(FCM ID)을 수집하지
    않지만, 설정 파일을 **포함**해 빌드한 AAB 는 로그인 사용자의 device token 을 수집·등록한다.
    푸시 포함 빌드로 제출할 때는 `docs/DATA_SAFETY_FORM.md` §2 '기기 또는 기타 ID = 예' 기준으로
    콘솔 설문을 기입할 것.
- **딥링크**: placeholder. 활성화 시 intent-filter(App Links) 추가.

## 트러블슈팅
- 에뮬레이터에서 Supabase 연결 안 됨 → 로컬 Supabase 실행 여부 확인 (`npx supabase status`)
- Gradle 메모리 오류 → `android/gradle.properties` 의 `-Xmx8G` 를 PC 사양에 맞게 하향
- 서명 오류 `keystore not found` → key.properties 의 storeFile 을 절대경로로 입력
