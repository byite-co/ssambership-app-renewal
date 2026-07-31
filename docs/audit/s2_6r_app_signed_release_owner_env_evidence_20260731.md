# S2-6R — Android Signed Release Candidate 오너 환경 실행 증거 (2026-07-31, PASS)

> 본 문서는 S2-6R 세션의 **PASS 경로 증거 산출물**이다. 직전 S2-6R blocker 문서(`s2_6r_app_signed_release_owner_env_20260731.md` @ `cd66918`)가 기록한 원격 컨테이너 blocker가 **오너 통제 로컬 머신**에서 해소되어, signed AAB/APK 생성·서명·metadata·에뮬레이터 native smoke를 전건 통과했다.
>
> 검증 환경: **오너 통제 로컬 Windows 머신** (win32 · 원격 Claude Code 컨테이너 아님) · 검증일 2026-07-31 (오너 로컬 세션)
>
> 정본 승계: 기존 blocker 문서(`cd66918`)·S2-6 blocker(`03495f0`)는 **수정·삭제·squash하지 않았다** (과제 §5 준수). 본 세션은 그 위에 Commit A(RC)·Commit B(본 문서)만 추가한다.
>
> **이번 세션 금지 준수:** M16 미적용 · `min_supported_build` 변경 0 · `latest_build` 변경 0 · Play Console 업로드 0 · 스토어 release 생성 0 · Supabase migration 0.

---

## 0. 커밋 구조

| 커밋 | SHA | 내용 |
|------|-----|------|
| S2-6 blocker | `03495f045630f0eb321a1f9f391e24a436dc41bb` | 최초 blocker 문서 (불변) |
| S2-6R 원격 blocker | `cd66918d06fe634bc4c51415828f34caea56d7fe` | 원격환경 blocker 문서 (불변) |
| **Commit A (RC)** | **`28eaf7dbf2512d0ff8e0cf8e3a03a3ae0dec3f2a`** | pubspec.yaml 단독 — `version: 0.1.0+9` |
| **Commit B (증거)** | (본 문서 커밋) | 감사 문서 1건만 추가 — branch tip |

```
APP_RELEASE_CANDIDATE_SHA: 28eaf7dbf2512d0ff8e0cf8e3a03a3ae0dec3f2a   (정본 signed artifact 기준 커밋 = Commit A)
BRANCH_TIP:                Commit B (본 문서)
```

## 1. Scope and Repository Ownership

| 항목 | 값 |
|------|-----|
| 주 작업 저장소 | **APP** — `byite-co/ssambership-app` (origin 실측 일치 — G0 PASS) |
| 브랜치 | `claude/s2-6r-android-signed-release-owner-0rd6q7` (신규 생성 0 · force push 0) |
| 제품 기준 commit | `1c5d6c0190534d8d17381c95cc701b2f87342c0d` |
| 시작 HEAD | `cd66918d06fe634bc4c51415828f34caea56d7fe` (요구 HEAD 정확 일치) |
| 원격 DB (Supabase) | READ-ONLY (앱 startup RPC 읽기만 · `min_supported_build`/`latest_build` 쓰기 0 · migration 0) |
| Play Console | READ-ONLY (오너가 최고 versionCode 실측 제공 · 업로드 0) |
| 스토어 업로드 / release / PR / master 병합 / tag | 전건 0 |

## 2. Base Product and Git Hard Gates (G0~G4)

| 게이트 | 항목 | 기대값 | 실측값 | 판정 |
|--------|------|--------|--------|------|
| G0 | origin | `byite-co/ssambership-app` | 일치 | PASS |
| G1 | 기준 브랜치 tip (`claude/s2-6-android-signed-release-8yym8y`) | `03495f0…` | 일치 (`git ls-remote`) | PASS |
| G2 | ancestor(1c5d6c0 → 03495f0) | YES | `merge-base --is-ancestor` YES | PASS |
| G2 | 1c5d6c0→03495f0 diff | 문서 1건만 | `A docs/audit/s2_6_..._20260731.md` | PASS |
| G3 | origin/master | `b0ea4051…` | 일치 | PASS |
| G3 | divergence (master…HEAD) | master 이동 없음 | **0 / 15** (rebase 불요) | PASS |
| G4 | pubspec @ 시작 HEAD | `0.1.0+4` | `version: 0.1.0+4` | PASS |
| — | pubspec.lock | 불변 | `ef1433aff7b08c4010bbe14bda50ac3be62b882d` (Commit A 후에도 동일) | PASS |

## 3. Owner Environment Toolchain (실측)

과제 §2 전제 — "오너가 통제하는 로컬 또는 신뢰 가능한 빌드 환경" — **충족.**

| 항목 | 정본 요구 | 실측 | 판정 |
|------|-----------|------|------|
| Flutter | 3.44.8 | **3.44.6** (오너 승인 — 실측값 그대로 기록, 3.44.8로 위장 기록 안 함) | PASS (오너 승인) |
| Dart | ≥3.12.2 | 3.12.2 | PASS |
| JDK | 17 | OpenJDK 17.0.19 (Temurin) | PASS |
| Android SDK platform | 36 | 34/35/36/36.1 설치 (36 포함) | PASS |
| Build Tools | 설치 | 36.0.0 | PASS |
| platform-tools (adb) | 설치 | r37.0.1 (SDK) | PASS |
| Android 기기 / emulator | 1대 이상 | **API 36 emulator** `s26r_api36` (`google_apis;x86_64`) 생성·부팅 (`emulator-5556`, `sys.boot_completed=1`) | PASS |
| dl.google.com 접근 | 필요 | HTTP 200 (직전 원격 세션 403과 대비) | PASS |
| production `.env` | 필요 | 존재 · 승인 ref `lbeqxarxothkmzqvpudy` + Supabase 키 포함 (존재/매칭 boolean만 확인 · 값 비노출) | PASS |
| `android/key.properties` | 필요 | 존재 · 키 4종(storePassword/keyPassword/keyAlias/storeFile) · storeFile → 실존 keystore(2728B) | PASS |
| release/upload keystore | 필요 | 존재 (파일 원문·경로 비노출) | PASS |

```
APP_RELEASE_TOOLCHAIN:  PASS
FLUTTER_VERSION_ACTUAL: 3.44.6   (owner-approved; NOT recorded as 3.44.8)
DART_VERSION_ACTUAL:    3.12.2
```

## 4. Analyze and Test

오너 로컬 머신에서 **재실행**. `flutter pub get`은 `pubspec.lock`을 변경하지 않았다(`ef1433a` 전후 동일).

```
FLUTTER_ANALYZE:          PASS   (error 0 / warning 0 / info 71)
FLUTTER_TEST:             PASS   (922 pass / 0 fail / 1 skip · error 이벤트 0 · testDone 1053 중 hidden 130 제외)
PUBSPEC_LOCK_UNCHANGED:   PASS   (ef1433aff7b08c4010bbe14bda50ac3be62b882d)
```

## 5. VersionCode Decision

Play Console 최고 사용 versionCode를 **오너가 실측 제공** (추정 0 — 숫자 미제공 시 BLOCKED 규정 하에 대기 후 확정치 수신):

```
HIGHEST_USED_VERSION_CODE:     4        (오너 Play Console 실측 · 스크린샷상 vc4 활성 / vc2·vc3 비활성)
TARGET_BUILD_NUMBER:           max(9, 4 + 1) = 9
BASE_VERSION:                  0.1.0+4  (시작 HEAD)
TARGET_VERSION:                0.1.0+9
versionName:                   0.1.0    (유지 — 별도 승인 없음)
STORE_VERSION_CODE_UNIQUENESS: VERIFIED (9 > 4 — 기존 사용 코드와 충돌 없음)
```

트랙 종류(internal/closed/open/production)는 오너 지시에 따라 **확정하지 않는다** (스크린샷만으로 단정 불가).

## 6. Release Candidate Commit (Commit A)

```
COMMIT_A_SHA:  28eaf7dbf2512d0ff8e0cf8e3a03a3ae0dec3f2a
CHANGED FILES: pubspec.yaml (1 file, 1 insertion, 1 deletion — `version: 0.1.0+4` → `0.1.0+9`)
PUBSPEC_LOCK:  변경 없음 (커밋에 미포함)
```

과제 §12 이중 커밋 구조: Commit A = RC(pubspec 단독) / Commit B = 감사 문서. Commit A 메시지는 정본으로 정리했다.

## 7. Signed AAB / APK Build (Commit A exact SHA)

빌드 시 HEAD = `28eaf7d…` (working tree clean — tracked 변경 0). `flutter build appbundle --release` · `flutter build apk --release`.

```
AAB_PATH:    build/app/outputs/bundle/release/app-release.aab
AAB_SIZE:    66,157,879 bytes (63.1 MB)
AAB_SHA256:  061e4adf2ea1c8742a0bf73f663128b59ec113e4da9eaf530d2af066b8b1fe2d

APK_PATH:    build/app/outputs/flutter-apk/app-release.apk
APK_SIZE:    67,369,774 bytes (64.2 MB)
APK_SHA256:  ce41e1d231b6970975ef066258ba9dbf43ccec95d950a075a56ede0c579dc462

GOOGLE_SERVICES_JSON: ABSENT → 푸시(FCM) 비활성 빌드 = device token 미수집 (Data safety 단순 경로)
```

(artifact 바이너리는 **커밋하지 않는다** — `git check-ignore` 로 `build/…apk` ignore 확인. 위 SHA256/크기만 증거로 기록.)

## 8. Signature and Certificate Evidence

```
APK apksigner verify:  Verifies = TRUE
  APK Signature Scheme v2: TRUE
  APK Signature Scheme v3: FALSE (v2로 검증 성립 — 업로드 유효)
SIGNER_DN:             CN=Ssambership, OU=Mobile, O=Byite, L=Seoul, ST=Seoul, C=KR
DEBUG_CERTIFICATE_ABSENT: PASS  (CN=Android Debug 아님)
UPLOAD_CERT_SHA256:    1AC905DE2C306017496F4C6D29C254D815A3CFFBFB5CE97F29B924E52C07D1F2
  ├ AAB (keytool -printcert):  1AC905DE…D1F2
  └ APK (apksigner):           1ac905de…d1f2   → AAB·APK 동일 upload 키 서명 (일치)
ALLOW_INSECURE_SIGNING: FALSE  (-PallowInsecureSigning 미사용 — 빌드 로그 0건)
```

Play App Signing 대조(`PLAY_CONSOLE_UPLOAD_CERT_MATCH`)는 Play Console 쓰기 접근 밖이므로 이번 세션 대상 아님 — 업로드 시 오너가 콘솔에서 대조.

## 9. Artifact Metadata

```
applicationId:   com.ssambership.edu
versionCode:     9        (= TARGET_BUILD_NUMBER)
versionName:     0.1.0
minSdk:          24       (source `minSdk = 24` · APK `minSdkVersion:'24'`)
targetSdk:       36
compileSdk:      36
application-label: 쌤버십
```

## 10. Native Release Smoke (emulator API 36)

대상: `emulator-5556` (AVD `s26r_api36` · `google_apis;x86_64` · `ro.build.version.sdk=36`). release APK(§7) 설치.

```
SIGNED_RELEASE_INSTALL:       PASS   (adb install -r → "Success")
SIGNED_RELEASE_LAUNCH:        PASS   (am start -W → Status: ok · LaunchState: COLD · TotalTime 1231ms)
SIGNED_RELEASE_STARTUP_SMOKE: PASS   (pid 5082 alive · topResumedActivity = com.ssambership.edu/.MainActivity)
VERSION_POLICY_STARTUP:       PASS   (정상 로그인 화면 도달 — 강제업데이트 벽 아님 → build 9 ≥ min_supported_build)
LOGCAT_FATAL_ERRORS:          0      (crash 버퍼 0 · FATAL EXCEPTION 0 · ANR 0 · libflutter.so 로드 OK · Impeller/OpenGLES)
```

스크린샷 증거(로컬 보관): 쌤버십 로고 + 이메일/비밀번호 + 로그인/둘러보기 + "회원가입은 웹에서 진행돼요" — Commerce-Zero 컴패니언 로그인 화면. (`W HWUI 101010-2` 경고는 소프트GPU 10bit 미지원, 무해.)

```
APP_NATIVE_RELEASE_GATE: PASS
```

## 11. Store-Safe Feature Flags (소스 재실측)

| 플래그 | 위치 | 기본값 | 판정 |
|--------|------|--------|------|
| `IQ_CREATE_ENABLED` | `lib/features/individual_question/iq_flags.dart:17` | `false` | PASS |
| `SUBS_MANAGE_LINK_ENABLED` | `lib/core/commerce/commerce_policy.dart:18` | `false` | PASS |
| `PAYOUT_MANAGE_LINK_ENABLED` | `lib/core/commerce/commerce_policy.dart:30` | `false` | PASS |
| `kInAppPaymentSteeringEnabled` | `lib/core/commerce/commerce_policy.dart:10` | `false` | PASS |

```
STORE_SAFE_FEATURE_FLAGS: PASS (Commerce-Zero 유지)
```

## 12. Old-App and M16 Cutoff Case (판정만 — 적용 없음)

오너 제공 기준선:

```
OLD_APP_STORE_BASELINE:       VERIFIED_EXISTING_RELEASE
OLD_APP_VERSION_CODE:         4   (활성 · vc2·vc3 비활성)
OLD_APP_VERSION_GATE_PRESENT: UNKNOWN   (업로드된 vc4 ↔ source commit 연결 증거 없음 — 오너 지시로 UNKNOWN 유지)
```

Case 매트릭스(과제 §21 / S2-6 §15):
- A = 기존 출시 없음 → PASS_NOT_APPLICABLE
- B = **gate 있는** 기존 배포 → PASS_CONTRACT_READY
- C = **gate 없는/미확인** 기존 배포 → 오너 결정 필요
- D = 스토어 기준선 미확인 → BLOCKED

판정: 기존 릴리스가 **VERIFIED**(vc4)이므로 A·D 배제. Case B는 version gate 존재의 **확증**을 요구하나 `OLD_APP_VERSION_GATE_PRESENT=UNKNOWN`이라 favorable case를 추정할 수 없다 → 보수적으로 **Case C** 확정.

```
OLD_APP_M16_CUTOFF_CASE: C   (보수적 · gate presence 미확증)
OLD_APP_M16_CUTOFF_GATE: OWNER_DECISION_REQUIRED
  └ 승급 조건: vc4 ↔ version-gate 포함 source commit 연결 증거 확보 시 Case B(PASS_CONTRACT_READY)로 재분류
```

**M16 적용 규정 (이번 세션 금지 준수):**

```
M16_APPLY_THIS_SESSION:   PROHIBITED (미적용)
MIN_SUPPORTED_BUILD:      변경 0 (원격 값 불변)
LATEST_BUILD:             변경 0 (원격 값 불변)
M16_APPLY_BEFORE_NEW_APP: PROHIBITED
READY_FOR_M16:            NO   (신규 앱 배포·cutoff 선행조건 미충족 + gate presence 미확증)
```

최소 버전 정책 정본: 신규 앱 N 설치 가능 확인 → latest=N → cutoff 선행 전건 충족 → min=N → 그 후에만 M16. 이번 세션 원격 값 변경 0.

## 13. App Production Project Binding

```
.env 존재:                     YES (승인 ref lbeqxarxothkmzqvpudy 매칭 · 값 비노출)
APP_PRODUCTION_SUPABASE_REF:   lbeqxarxothkmzqvpudy (boolean 매칭 확인)
APP_PRODUCTION_PROJECT_BINDING: PASS
```

## 14. Secret and Artifact Safety

```
TRACKED_SECRETS/ARTIFACTS:     0   (git ls-files: .env / key.properties / *.jks / *.keystore / *.aab / *.apk 커밋 0 — *.example만 존재)
.env / key.properties / build APK: 전건 git-ignored (check-ignore 확인)
비노출 준수:                    .env 원문·SUPABASE_ANON_KEY·key.properties 원문·keystore 비밀번호·keystore 파일·AAB/APK 바이너리·기기 serial — 출력·커밋 0
INSECURE_SIGNING:              FALSE
```

작업 트리의 untracked 잔여물(`.env.local.bak` · `android/key.properties]`)은 tracked 아님 — Commit A/B 어느 쪽에도 포함되지 않았다.

## 15. Final Verdict

**이번 세션 최종 판정: PASS** (S2-6R 오너 환경 signed release candidate 증거 확립)

```
FINAL_STATE_VERIFIER_CANON:        PASS
APP_RELEASE_TOOLCHAIN:             PASS   (Flutter 3.44.6 owner-approved)
FLUTTER_ANALYZE:                   PASS   (error 0)
FLUTTER_TEST:                      PASS   (922/0/1)
PRODUCTION_ENV_PRESENT:            YES
RELEASE_KEY_PRESENT:               YES
INSECURE_SIGNING:                  FALSE
SIGNED_BUILD:                      PASS   (AAB + APK · upload 키 서명 · CN=Ssambership)
UPLOAD_CERT_SHA256:                1AC905DE2C306017496F4C6D29C254D815A3CFFBFB5CE97F29B924E52C07D1F2
APP_RELEASE_CANDIDATE_SHA:         28eaf7dbf2512d0ff8e0cf8e3a03a3ae0dec3f2a
TARGET_VERSION:                    0.1.0+9
STORE_VERSION_CODE_UNIQUENESS:     VERIFIED
APP_NATIVE_RELEASE_GATE:           PASS
VERSION_POLICY_STARTUP:            PASS
STORE_SAFE_FEATURE_FLAGS:          PASS
APP_PRODUCTION_PROJECT_BINDING:    PASS
OLD_APP_M16_CUTOFF_CASE:           C
OLD_APP_M16_CUTOFF_GATE:           OWNER_DECISION_REQUIRED
M16_APPLY_THIS_SESSION:            PROHIBITED (미적용)
PLAY_CONSOLE_UPLOAD:               0
STORE_RELEASE_CREATED:             0
SUPABASE_MIGRATION:                0
READY_FOR_STORE_UPLOAD:            YES (오너 콘솔 업로드 대기 — 자동화 대상 아님)
READY_FOR_M16:                     NO
```

## 16. Handoff — 다음 단계 (오너 수동)

1. **Play Console 업로드** — Commit A(`28eaf7d`) 산출 AAB(`app-release.aab`, versionCode 9)를 오너가 콘솔에 업로드. 업로드 시 Play App Signing upload 인증서와 `UPLOAD_CERT_SHA256`(1AC905DE…D1F2) 대조.
2. **신규 앱 startup smoke (스토어 경로)** → **필수 기능 smoke** → **스토어 배포 상태 확인** → **rollback/중단 연락선** → **구버전 기준선 재확인** → **오너 cutoff 승인** 전건 충족 후에만 `latest_build=9` → (조건 충족 시) `min_supported_build=9`.
3. **M16** — 위 2 전건 충족 + `OLD_APP_VERSION_GATE_PRESENT` 확증(Case B 승급) 이후에만. 본 세션은 판정만 수행, 적용 0.
4. Data safety: 본 빌드는 `google-services.json` 미포함 = device token 미수집. 푸시 포함 빌드로 전환 시 `docs/DATA_SAFETY_FORM.md` §2 재기입.
