# S2-6R — Android Signed Release Candidate 오너 환경 재실행 (2026-07-31)

> 본 문서는 S2-6R 세션의 유일한 tracked 산출물이다(BLOCKED 경로 — 과제 §26·§27). 이번 세션에서 signed AAB/APK는 생성되지 않았고 versionCode bump도 수행하지 않았다. 사유: 과제 §2가 요구하는 "오너가 통제하는 로컬 또는 신뢰 가능한 빌드 환경"이 아닌 **Claude Code 원격 컨테이너**에서 세션이 실행되었으며, 오너 보유 secret(release/upload keystore·`android/key.properties`·production `.env`)·Android SDK 36·adb 대상 기기·Play Console 접근 수단이 전부 부재하다. 과제 §2 규정("조건이 준비되지 않았다면 파일을 수정하지 말고 즉시 BLOCKED로 종료한다")과 §26 부분 RC 금지 규정을 적용했다.
>
> 검증 시각: 2026-07-31T05:56Z (UTC) · 검증 환경: Claude Code 원격 세션 (linux)
>
> S2-6(`03495f0…`) blocker와의 차이: S2-6은 secret 부재 + SDK 네트워크 차단을 최초 실측했고, 본 S2-6R은 **오너 환경 재실행 지시에도 불구하고 동일 계열 원격 컨테이너에서 기동**되어 동일 blocker가 재현됨을 재실측·확정한다. 기존 S2-6 blocker 문서는 수정하지 않았다(과제 §5 금지 준수).

---

## 1. Scope and Repository Ownership

| 항목 | 값 |
|------|-----|
| 주 작업 저장소 | **APP** — `byite-co/ssambership-app` (origin 실측 일치 — G0 PASS) |
| 참고 저장소 (READ ONLY) | `byite-co/ssambership_web` — GitHub API 읽기 2건(S2-8 commit 메타데이터·오너 게이트 문서)만 수행. clone·checkout·수정·commit·push·PR·병합 0건 |
| 제품 기준 commit | `1c5d6c0190534d8d17381c95cc701b2f87342c0d` (APP_PRODUCT_BASE_SHA) |
| S2-6 blocker 기준 commit | `03495f045630f0eb321a1f9f391e24a436dc41bb` (S2_6_BLOCKER_SHA) |
| 신규 작업 브랜치 (실제) | `claude/s2-6r-android-signed-release-owner-0rd6q7` |
| 권고 브랜치명 (과제 명세) | `claude/s2-6r-app-signed-release-owner-env-20260731` |
| 원격 DB | NOT_ACCESSED (Supabase 도구 호출 0 · `min_supported_build`/`latest_build` 변경 0) |
| Play Console | BLOCKED (접근 수단 없음 — 자격증명·API 도구 부재) |
| 스토어 업로드 | 0 |
| PR 생성 | 0 |
| master 병합 | 0 · tag 0 · GitHub Release 0 · squash/rebase/force push 0 |

**브랜치명 매핑 기록:** 하네스가 세션 브랜치명 `claude/s2-6r-android-signed-release-owner-0rd6q7`를 강제하므로 과제 §0·§7의 이름 매핑 허용 조항에 따라 해당 이름을 사용한다. 하네스가 세션 시작 시 master(`b0ea4051…`)에 만들어 둔 동명 포인터는 고유 커밋 0건 상태였으며, 과제 §0 요구대로 `git checkout -B`로 기준 커밋 `03495f04…`에 재지정해 생성했다(`git rev-parse HEAD` 일치 실측 · 유실 커밋 0 · force push 0. `03495f0…`는 `b0ea4051…`의 후손이므로 push는 fast-forward).

## 2. Base Product and Blocker Ancestry

시작 하드게이트 실측 (2026-07-31 05:4x~05:5x UTC):

| 게이트 | 항목 | 기대값 | 실측값 | 판정 |
|--------|------|--------|--------|------|
| G0 | 저장소 | `byite-co/ssambership-app` | origin = `…/byite-co/ssambership-app` | PASS |
| G1 | 기준 브랜치 tip (`claude/s2-6-android-signed-release-8yym8y`) | `03495f045630f0eb321a1f9f391e24a436dc41bb` | 동일 (`git rev-parse origin/claude/s2-6-android-signed-release-8yym8y`) | PASS |
| G1 | working tree | clean | clean | PASS |
| G2 | ancestor(1c5d6c0 → 03495f0) | PASS | `git merge-base --is-ancestor` PASS | PASS |
| G2 | 1c5d6c0→03495f0 diff | S2-6 blocker 문서 1건만 추가 | `A docs/audit/s2_6_app_signed_release_version_gate_20260731.md` 1건 · 제품 코드 변경 0 | PASS |
| G3 | `origin/master` | `b0ea4051baf9993dcbad5e94a8b26c51c7d6de43` | 동일 | PASS |
| G3 | merge-base(master, 1c5d6c0) | `b0ea4051…` | 동일 | PASS |
| G3 | left/right count | 0 / 13 | 0 / 13 — master 이동·divergence 없음, rebase 불요 | PASS |
| G4 | pubspec version @ 03495f0 | `0.1.0+4` | `version: 0.1.0+4` | PASS |
| G5 | 외부 환경 (§3~§5) | 전건 준비 | **전건 부재** | **BLOCKED** |

`APP_MASTER_TO_PRODUCT_BASE: AHEAD_13_BEHIND_0` — 계보 불변. **FINAL_STATE_VERIFIER_CANON: PASS** (Git 계보·정본 승계 전건 재확증. G5만 외부 환경 사유로 BLOCKED).

## 3. Owner Environment Identity

과제 §2 전제 — "이번 세션은 오너가 통제하는 로컬 또는 신뢰 가능한 빌드 환경에서 실행한다" — 가 **충족되지 않았다.** 실행 환경은 ephemeral 원격 컨테이너(Claude Code 원격 세션)이며 오너 로컬 자산이 주입되지 않았다.

| 항목 | 정본 요구 | 실측 | 판정 |
|------|-----------|------|------|
| Flutter | 3.44.8 | **미설치** (PATH 부재) | FAIL |
| Dart | ≥3.12.2 | **미설치** | FAIL |
| JDK | 17 | OpenJDK **21.0.10** 기설치 (17 부재) | PARTIAL |
| Android SDK platform | 36 | **부재** — `dl.google.com/android/repository/*` HTTP **403 Forbidden** (세션 네트워크 정책 · 2026-07-31T05:5x UTC 재실측, S2-6과 동일) → 설치 불가 | **BLOCKED** |
| Android Build Tools / Platform Tools (adb) | 설치 | **부재** (`which adb` 0건) | BLOCKED |
| Android 기기 / emulator | 1대 이상 | **NONE** (adb 대상 없음 · KVM 가상화 기기 없음) | BLOCKED |
| compileSdk / targetSdk / minSdk | 36 / 36 / 24 | `android/app/build.gradle.kts` 선언값 일치 (소스 기준 — S2-6 실측 승계, 제품 코드 불변) | PASS(소스) |
| Play Console 읽기 접근 | 필요 | **없음** (자격증명·도구 부재) | BLOCKED |

Flutter는 원리상 세션 내 설치 가능하나(S2-6 전례), 결정적 blocker(keystore·`.env`·SDK 36·기기·Play Console)가 전부 해소 불능이므로 §2 규정에 따라 부분 진행 없이 즉시 BLOCKED 처리했다.

```
APP_RELEASE_TOOLCHAIN: BLOCKED
```

## 4. Secret and Keystore Safety

| 항목 | 실측 | 판정 |
|------|------|------|
| `.env` 존재 | **ABSENT** (존재 검사만 수행 · 내용 출력 0) | PRODUCTION_ENV_PRESENT: **NO** |
| `android/key.properties` 존재 | **ABSENT** | — |
| release/upload keystore (`*.jks`/`*.keystore` 파일시스템 전역 탐색) | **ABSENT** (0건) | RELEASE_KEY_PRESENT: **NO** |
| `.env` ignore | `git check-ignore -v` → `.gitignore:21` 매칭 | PASS |
| `android/key.properties` ignore | `android/.gitignore:12` 매칭 | PASS |
| tracked secret/artifact (`git ls-files` — `.env`·`key.properties`·`*.jks`·`*.keystore`·`*.aab`·`*.apk`) | **0건** (`key.properties.example`만 존재 — 허용 항목) | PASS |
| `ORG_GRADLE_PROJECT_allowInsecureSigning` | **미설정** (변수 존재 여부만 검사 · env 덤프 명령 미사용) | INSECURE_SIGNING: **FALSE** |
| `-PallowInsecureSigning=true` 사용 | 0건 (Gradle 실행 자체 없음) | PASS |
| secret 원문 출력 (`cat .env`·`cat key.properties`·`printenv`·`env`·`set`) | 0건 | PASS |

- `android/app/build.gradle.kts:81` taskGraph 가드 재확인(소스 실측): `key.properties` 부재 시 release 산출물 빌드가 즉시 실패한다 — debug 서명 release 산출물은 설계상 생성 불가.
- 기존 upload keystore가 존재하지 않고, 이번 프롬프트에 `FIRST_UPLOAD_KEY_CREATION_APPROVED` 명시 승인이 **없다.** 과제 §2.2 규정에 따라 keystore를 신규 생성하지 않았다.

```
SIGNED_BUILD: BLOCKED_BY_OWNER_KEY
```

## 5. Play Console Baseline

Play Console 접근 수단(콘솔 자격증명·Play Developer API 도구)이 이 세션에 없다. 읽기 전용 확인 자체가 불가하며, 과제 §10 규정("기존 배포본의 version gate 포함 여부는 추정하지 않는다")에 따라 전항 UNKNOWN으로 유지한다.

```
PLAY_CONSOLE_BASELINE:         BLOCKED
PLAY_CONSOLE_APP:              UNKNOWN   (package: com.ssambership.edu)
HIGHEST_USED_VERSION_CODE:     UNKNOWN
ACTIVE_RELEASE:                UNKNOWN
PLAY_APP_SIGNING:              UNKNOWN
PLAY_UPLOAD_CERT_SHA256:       UNKNOWN
APP_SIGNING_CERT_SHA256:       UNKNOWN
OLD_APP_STORE_BASELINE:        UNKNOWN
OLD_APP_VERSION_CODE:          UNKNOWN
OLD_APP_VERSION_GATE_PRESENT:  UNKNOWN
STORE_VERSION_CODE_UNIQUENESS: UNVERIFIED
```

## 6. VersionCode Decision

수행하지 않았다 (BLOCKED 경로 — §26 부분 version bump 금지).

- BASE_VERSION: `0.1.0+4` (pubspec.yaml 불변 — `git status` clean 실측)
- TARGET_BUILD_NUMBER_RULE: `max(9, Play Console 최고 사용 versionCode + 1)` — Play Console 기준선 미확보로 산출 불능. 기존 사용 versionCode가 없다고 확정되는 경우의 후보값은 `0.1.0+9`(과제 §11)이나, 이번 세션에서는 확정하지 않는다.
- versionName: `0.1.0` 유지 (별도 승인 없음)
- PUBSPEC_LOCK_UNCHANGED: PASS (변경 0 — 커밋 자체가 문서 1건뿐)

## 7. Release Candidate Commit

생성하지 않았다. Commit A(pubspec.yaml 단독 변경)는 §26 "Commit A 생성 전 실패" 경로에 따라 0건이다.

```
APP_RELEASE_CANDIDATE_SHA: PENDING   (S2-6 상태 유지)
```

본 문서 커밋(Commit — blocker 감사 문서 1건)이 이 브랜치의 유일한 신규 커밋이며, 제품 코드 변경은 0이다.

## 8. Analyze and Test Regression

이번 세션에서는 **미실행** — Flutter/Dart 미설치 + §2 즉시 BLOCKED 규정(파일 수정 금지·부분 진행 금지) 적용. version 변경(§13의 트리거)이 발생하지 않았으므로 재검증 전제 자체가 성립하지 않는다.

정본 승계(S2-6 audit `03495f0…` §7~§8 — 동일 제품 코드 `1c5d6c0…`에서 실측):

| 항목 | S2-6 정본 | 이번 세션 유효성 |
|------|-----------|------------------|
| flutter analyze | error 0 | 제품 코드 불변(1c5d6c0→03495f0 diff = 문서 1건)이므로 정본 유효 |
| flutter test | 922 pass / 0 fail / 1 skip | 동일 |
| version gate 행렬 | 44/44 PASS | 동일 |

```
FLUTTER_ANALYZE:          NOT_RERUN (정본 승계: PASS)
FLUTTER_TEST:             NOT_RERUN (정본 승계: 922/0/1)
VERSION_GATE_TEST_MATRIX: NOT_RERUN (정본 승계: 44/44 PASS)
```

## 9. Store-Safe Feature Flags

이번 세션에서 소스 기준으로 **재실측**했다 (읽기 전용 · @ `03495f0…` working tree = 제품 코드 `1c5d6c0…`와 동일):

| 플래그 | 위치 | 실측 기본값 | 판정 |
|--------|------|-------------|------|
| `IQ_CREATE_ENABLED` | `lib/features/individual_question/iq_flags.dart:17` | `defaultValue: false` (OFF) | PASS |
| `SUBS_MANAGE_LINK_ENABLED` | `lib/core/commerce/commerce_policy.dart:18` | `defaultValue: false` (OFF) | PASS |
| `PAYOUT_MANAGE_LINK_ENABLED` | `lib/core/commerce/commerce_policy.dart:30` | `defaultValue: false` (OFF) | PASS |
| `kInAppPaymentSteeringEnabled` | `lib/core/commerce/commerce_policy.dart:10` | `= false` | PASS |

앱 내 신규 구독·캐시 충전·개별질문 결제: 비활성 (상기 플래그 기본값 체계 — S2-6 Commerce-Zero 정본과 일치).

```
STORE_SAFE_FEATURE_FLAGS: PASS (소스 실측)
```

## 10. Signed AAB Evidence

생성되지 않았다 — BLOCKED (keystore·`.env`·Android SDK·Flutter 부재. §3~§4).

```
AAB_PATH:      N/A
AAB_SHA256:    N/A
AAB_SIGNATURE: BLOCKED
```

## 11. Signed APK Evidence

생성되지 않았다 — BLOCKED (동일 사유).

```
APK_PATH:      N/A
APK_SHA256:    N/A
APK_SIGNATURE: BLOCKED
```

## 12. Certificate Evidence

검증 대상 artifact·keystore가 없다.

```
UPLOAD_CERT_SUBJECT:            N/A
UPLOAD_CERT_SHA256:             N/A
DEBUG_CERTIFICATE_ABSENT:       BLOCKED (검증 대상 없음 — 단 debug 서명 release 산출물은 gradle 가드로 원천 차단, §4)
PLAY_CONSOLE_UPLOAD_CERT_MATCH: BLOCKED (양측 모두 부재)
```

## 13. Artifact Metadata

검증 대상 artifact가 없다. 소스 선언값(참고 — S2-6 승계·제품 코드 불변): applicationId `com.ssambership.edu` · versionName `0.1.0` · minSdk 24 · targetSdk 36 · compileSdk 36.

```
ARTIFACT_APPLICATION_ID / VERSION_NAME / VERSION_CODE / MIN_SDK / TARGET_SDK: BLOCKED
RELEASE_MANIFEST_SECURITY: BLOCKED (artifact 부재 — 소스 기준 검증은 S2-6 정본 승계)
```

## 14. Native Release Smoke

수행 불가 — 설치할 artifact가 없고 adb 대상 기기/emulator도 없다.

```
SIGNED_RELEASE_INSTALL:          BLOCKED
SIGNED_RELEASE_LAUNCH:           BLOCKED
SIGNED_RELEASE_STARTUP_SMOKE:    BLOCKED
VERSION_POLICY_STARTUP:          BLOCKED (원격 android min/latest = 1/1 정본은 S2-8 웹 audit §4 RPC 실측으로 유지 확인)
REMOTE_API_APP_V1_FEATURE_SMOKE: DEFERRED_TO_R2 (과제 §20 정본)
LOGCAT_FATAL_ERRORS:             BLOCKED
```

## 15. App Production Project Binding

`.env`가 존재하지 않으므로 project ref 대조 대상 자체가 없다. 값 비노출 원칙에 따라 존재 검사만 수행했다.

```
APP_PRODUCTION_SUPABASE_REF:    BLOCKED (.env 부재 — 승인된 후보 ref: lbeqxarxothkmzqvpudy)
APP_PRODUCTION_PROJECT_BINDING: BLOCKED
```

웹 binding PASS(S2-7/S2-8 정본)는 과제 §9 규정에 따라 앱 binding 증거로 대체하지 않는다.

## 16. Old-App and M16 Cutoff Case

Play Console 기준선 확인 불가(§5) → 과제 §21 **Case D** 확정. 추정으로 Case A를 선택하지 않는다.

```
OLD_APP_M16_CUTOFF_CASE:      D
OLD_APP_VERSION_GATE_PRESENT: UNKNOWN
OLD_APP_M16_CUTOFF_GATE:      BLOCKED_UNKNOWN_STORE_BASELINE
```

최소 버전 정책 정본(과제 §22 · S2-6 §16 승계): 신규 앱 출시 전 min/latest 현재값(1/1) 유지 → 신규 앱 N 설치 가능 확인 후 latest=N → cutoff 전제 전건 충족 후 min=N → 그 후에만 M16. 이번 세션 원격 값 변경 0.

```
MIN_VERSION_POLICY_CANON:  PASS
M16_APPLY_BEFORE_NEW_APP:  PROHIBITED
READY_FOR_M16:             NO
```

## 17. Owner Decision #7 and #10

**결정 #7 — Android signed build 환경: UNRESOLVED.** 필수 8항(release keystore · production `.env` · SDK 36 · signed AAB · signed APK · 인증서 검증 · metadata 검증 · native smoke) 중 **0건 충족**. 환경 부재로 착수 불능.

**결정 #10 — 구버전 cutoff: BLOCKED.** Case D(과제 §23 — "Case D라면 BLOCKED") — Play Console 기준선 증거가 확보될 때까지 판정 불능.

**결정 #9 — 최소 버전 정책: RESOLVED** (S2-6 정본 승계 — §16).

웹 오너 게이트 승계 상태 재확인 (READ ONLY — `ssambership_web` `docs/audit/s2_8_r0_owner_gate_closure_20260731.md` @ `0442ce63b6e7f313247f2f107b8da90784ccf6f7`): #2 RESOLVED · #3 BLOCKED(Dashboard 증거 대기) · #4 RESOLVED_APPROVED · #5 RESOLVED_APPROVED · #6 RESOLVED_CONDITIONAL · #11~#14 RESOLVED · #16 RESOLVED_APPROVED(적용은 BACKUP_PITR_GATE PASS 이후) — **과제 §1 승계 선언과 전건 일치 실측.**

## 18. Artifact-to-Git Identity

성립하지 않았다 — artifact 0건, Commit A 0건.

과제 §12의 이중 커밋 구조(Commit A = RC / Commit B = 감사)는 차기 오너 환경 재실행에서 그대로 적용한다. 본 세션 산출은 blocker 문서 커밋 1건뿐이며 branch tip = 본 문서 커밋, `APP_RELEASE_CANDIDATE_SHA`는 PENDING을 유지한다.

## 19. Final R0~R7 Handoff

S2-6R 완전 PASS가 최종 R0~R7의 선행조건이므로 **인계 정본은 미완성**이다. 차기 세션(진짜 오너 환경)이 충족해야 하는 외부 조건은 §3~§5와 동일하다:

1. 오너 로컬(또는 오너 통제 빌드 머신)에서 세션 실행 — 원격 Claude Code 컨테이너 불가(secret 주입·SDK 다운로드·기기 연결 전부 불가 재확인됨)
2. Flutter 3.44.8 · Dart ≥3.12.2 · JDK 17 · Android SDK platform 36 · build-tools · adb
3. `android/key.properties` + release/upload keystore (저장소 외부 절대경로 권장 · 신규 생성은 `FIRST_UPLOAD_KEY_CREATION_APPROVED` 명시 승인 필요)
4. production `.env` (ref `lbeqxarxothkmzqvpudy` — 값 비노출 대조)
5. Play Console 읽기 접근 (package `com.ssambership.edu` 기준선 — §5의 UNKNOWN 10항 해소)
6. Android 기기 또는 API 36 emulator
7. 실행 절차: 과제 §6~§25 그대로 (기준 브랜치 `claude/s2-6-android-signed-release-8yym8y` @ `03495f0…`에서 신규 브랜치 → G0~G5 → versionCode 결정 → Commit A → exact-SHA 빌드 → 서명·metadata·smoke → Case 판정 → Commit B → 동시 push)

최종 R0~R7 시작 게이트(웹 S2-8 audit §11 정본): #3 해소(Evidence A + `OWNER_RECOVERY_SELECTION`) · Evidence B 캡처 · "R0 실행 승인" 문구 · S2-6R PASS.

## 20. Project Progress and Remaining Work

- 세션 시작 전 완료 실행 단위: **15개** / 진행도 약 96%
- 이번 세션(S2-6R): **차단 (BLOCKED)** — 실행 환경이 오너 환경이 아니어서 signed build 착수 자체가 불능. Git 계보 게이트(G0~G4)·secret 안전·store-safe 플래그·웹 승계 상태 대조는 전건 PASS 재확증
- 세션 완료 후 완료 실행 단위: **15개 유지** (완전 PASS 아님 — 완료로 계상하지 않음)
- 전체 진행도: **약 96% 유지** (기술 조사·게이트 정본은 소진 상태 — 잔여는 오너 물리 환경 의존 작업뿐)
- 최소 잔여 실행 세션: **2개 유지** — ① S2-6R 오너 환경 재실행(APP — 본 과제 §2 외부 조건 충족 환경에서) ② 최종 R0~R7 실행
- 소요시간: 이번 세션 실측 약 25분 (게이트·증거 수집·문서화). 잔여 — S2-6R 재실행 약 2~4시간(+환경·secret 준비 별도) · 최종 R0~R7 약 3~5시간(+monitoring) · 외부 대기(스토어 심사 약 1~7일·단계적 출시 관찰 수일) 별도

잔여 blocker (승계 + 이번 세션 재확정):

1. **오너 실행 환경 부재 (본 세션 재확정)** — keystore · `.env` · SDK 36(네트워크 403) · adb 기기 · Play Console 전부 원격 컨테이너에서 해소 불능
2. Backup/PITR Dashboard evidence + `OWNER_RECOVERY_SELECTION` (#3 — 웹 S2-8 승계)
3. Data API Settings evidence (Evidence B — 웹 S2-8 승계)
4. 실제 store upload·배포·단계적 출시 관찰 (S2-6R PASS 이후)
5. production `comments.author_label` 활성 결함 (M1→MC→M13→M4 체인으로만 해소 — 웹 승계)

이번 세션 신규 발견 blocker: 없음 (S2-6 blocker의 재현 확정만 추가 — 신규 결함 0).

## 21. Final Verdict

**이번 세션 최종 판정: BLOCKED**

핵심 근거:

1. 과제 §2의 오너 환경 전제 미충족 — 세션이 원격 Claude Code 컨테이너에서 기동됨. keystore·`key.properties`·`.env` 부재(파일시스템 전역 실측 0건), Android SDK 36 설치 불가(`dl.google.com` HTTP 403 재실측), adb 대상 기기 없음, Play Console 접근 수단 없음.
2. §2 규정 적용 — 조건 미비 시 파일 수정 금지·즉시 BLOCKED. `pubspec.yaml`·`pubspec.lock` 불변, versionCode bump 0, Commit A 0.
3. `FIRST_UPLOAD_KEY_CREATION_APPROVED` 부재 — keystore 신규 생성 금지 준수 → `SIGNED_BUILD: BLOCKED_BY_OWNER_KEY`.
4. Git 계보 게이트 전건 PASS — G0~G4 (기준 tip `03495f0…` · ancestry · master 0/13 · version 0.1.0+4). 신규 브랜치는 `03495f0…`에서 생성 실측.
5. Play Console 기준선 전항 UNKNOWN → Case D → `OLD_APP_M16_CUTOFF_GATE: BLOCKED_UNKNOWN_STORE_BASELINE` · OWNER_DECISION_10 BLOCKED. 추정 배제 원칙 준수.
6. store-safe 플래그 4종 소스 재실측 전건 OFF/false — Commerce-Zero 정본 유지.
7. 웹 오너 게이트 승계 상태(S2-8 @ `0442ce63…`) 10건 전건 일치 — READ ONLY 확인, 웹 저장소 변경 0.
8. 원격 시스템 변경 0 — DB 0 · Play Console 쓰기 0 · 스토어 업로드 0 · Vercel 0.
9. tracked 변경은 본 blocker 문서 1건뿐 (§27 BLOCKED 경로 규정 일치) — secret·artifact 커밋 0.

```
FINAL_STATE_VERIFIER_CANON:        PASS
APP_RELEASE_TOOLCHAIN:             BLOCKED
PRODUCTION_ENV_PRESENT:            NO
RELEASE_KEY_PRESENT:               NO
INSECURE_SIGNING:                  FALSE
SIGNED_BUILD:                      BLOCKED_BY_OWNER_KEY
APP_PRODUCTION_PROJECT_BINDING:    BLOCKED
PLAY_CONSOLE_BASELINE:             BLOCKED
STORE_VERSION_CODE_UNIQUENESS:     UNVERIFIED
APP_RELEASE_CANDIDATE_SHA:         PENDING
APP_NATIVE_RELEASE_GATE:           BLOCKED
OLD_APP_M16_CUTOFF_CASE:           D
OLD_APP_M16_CUTOFF_GATE:           BLOCKED_UNKNOWN_STORE_BASELINE
OWNER_DECISION_7:                  UNRESOLVED
OWNER_DECISION_9:                  RESOLVED
OWNER_DECISION_10:                 BLOCKED
READY_FOR_APP_MASTER_PR:           NO
READY_FOR_STORE_UPLOAD:            NO
READY_FOR_M16:                     NO
READY_FOR_FINAL_R0_R7:             NO
READY_FOR_REMOTE_ROLLOUT_APPROVAL: NO
READY_FOR_REMOTE_ROLLOUT:          NO
```
