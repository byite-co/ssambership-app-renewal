# 안드로이드 플레이스토어 심사제출 준비도 검증 (2026-07-16)

> 질문: "지금 안드로이드 빌드를 만들어 Google Play 심사에 제출하는 것이 적절한가?"
> 방법: 7개 차원 준비도 감사(빌드가능성·서명·매니페스트/권한·버전/SDK·스토어정책·개인정보/데이터안전·문서교차검증) → 블로커 후보 적대적 2중 검증. 정본 계획서 `docs/PLAY_STORE_REVIEW_PLAN.md`의 "해소(✅)" 주장을 현재 실제 코드와 대조.
> 환경 업데이트(2026-07-16 추가 검증): 이후 컨테이너에 **Flutter 3.44.6 stable을 설치해 `flutter pub get`·`flutter analyze`·`flutter test`를 실제로 실행했다**(전부 통과 — 부록 B). 다만 **`flutter build appbundle`은 Android SDK가 없고, Android SDK 배포처 `dl.google.com`이 이 세션의 egress 정책으로 차단(403)되어 설치가 불가능해 실행하지 못했다.** 즉 AAB 실산출·서명·정렬 확인은 여전히 Android SDK가 갖춰진 오너 PC/CI에서 수행해야 한다.

---

## 결론: 🟡 NO-GO(지금 당장 빌드→제출은 부적절) — 단, **앱 코드는 제출 준비 완료**

- **코드 결함(BLOCKER_CODE): 0건.** 앱 소스·빌드 설정은 구조적으로 온전하며, 계획서가 해소했다고 주장한 항목(targetSdk 36, 라벨, INTERNET, Commerce-Zero, 죽은 UI 제거, admin 차단, 약관/개인정보/탈퇴 링크)이 현재 코드에서 **모두 참(CONFIRMED)**으로 확인됐고, 2026-07-06 이후 커밋으로 되돌아간 회귀도 없다.
- **막는 것은 전부 "사람/콘솔 선행작업"(BLOCKER_HUMAN).** 지금 이 상태로 만든 AAB는 (a) `.env` 부재로 빌드 자체가 실패하거나, (b) 빌드돼도 debug 서명이라 Play Console 업로드가 거부된다. 게다가 심사관 테스트 계정·Data safety 폼이 없으면 업로드해도 보류/리젝이 확실하다.
- **요약**: "제출 부적절"의 원인은 앱 완성도가 아니라 **키·환경 프로비저닝과 콘솔 등록이 아직 안 됐기 때문**이다. 아래 4개(실질 2개 뿌리) 사람작업을 마치면 제출 가능한 체질이다.

---

## 🚦 제출 전 반드시 처리해야 할 것 (BLOCKER_HUMAN — 코드로 못 고침)

우선순위 순. 이 중 하나라도 빠지면 "빌드 실패" 또는 "업로드 거부" 또는 "심사 보류/리젝".

| # | 블로커 | 근거 | 필요 조치 |
|---|---|---|---|
| 1 | **`.env` 파일 부재 → 빌드 하드 실패** | `pubspec.yaml`에서 `.env`를 Flutter 에셋으로 선언(`flutter: assets: - .env`)했는데 저장소에 `.env`가 없음(`.gitignore`가 무시, `.env.example`만 존재). `main.dart`의 `dotenv.load` try/catch는 **런타임** 회복일 뿐, 에셋 번들링(빌드 단계) 실패는 못 막는다 → `flutter build appbundle`이 `No file or variants found for asset: .env`로 중단. | 빌드 머신에서 `.env.example`→`.env` 생성 후 **운영** `SUPABASE_URL=https://<ref>.supabase.co` + `SUPABASE_ANON_KEY` 기입. CI면 시크릿에서 빌드 스텝 이전에 `.env` 기록. |
| 2 | **release keystore·`android/key.properties` 부재 → debug 서명 AAB → Play 업로드 전 트랙 거부** | `android/app/build.gradle.kts:59-63` — `key.properties` 있으면 release, 없으면 `debug` 폴백. 현재 `key.properties` 없음. debug 서명 번들은 내부 테스트 트랙 포함 **모든 트랙**에서 업로드 거부. (서명 스켈레톤 자체는 온전 = 코드 손댈 것 없음.) | `keytool`로 upload keystore 생성(오너 로컬, **키·비밀번호 레포/세션 반입 절대 금지**) → `android/key.properties` 작성 → `flutter build appbundle --release` 후 `keytool -printcert -jarfile .../app-release.aab`로 debug 아님 확인 → 첫 업로드 시 **Play App Signing 등록**. 절차: `PLAY_STORE_REVIEW_PLAN.md` §릴리즈 키 생성. |
| 3 | **Play Console App access 테스트 계정 미등록 → 심사관이 핵심기능 검증 불가** | 인앱 가입 폼 없음(설계) + 게스트는 커뮤니티·멘토찾기만(`lib/app/entry_guard.dart:25`). 질문방 구독 멘토링(핵심)은 로그인 필요 → 계정 없으면 심사관이 못 들어가 **보류/리젝 확실**. | Play Console → App access에 **학생·멘토 각 1개** 테스트 계정 등록(로그인 가능 + 구독·질문 시드 데이터). 콘솔 작업. |
| 4 | **Data safety 폼 미제출 → 등재 불가/사후 제재** | ~~`docs/DATA_SAFETY_FORM.md` 부재~~ → **초안 작성 완료**(PR #28, 2026-07-16 머지 — 수집 항목별 코드 근거 파일:라인·콘솔 입력 체크리스트 포함). 콘솔 설문 제출은 여전히 미완. | `docs/DATA_SAFETY_FORM.md` §2 항목표 기준으로 Play Console Data safety 폼 제출(사람·콘솔 작업 잔여). |

> 추가 환경 사실: 이 컨테이너에 Flutter 3.44.6을 설치해 analyze·test는 실제로 돌렸으나(부록 B), **Android SDK가 없고 그 배포처(dl.google.com)가 egress 정책으로 차단돼 AAB는 이 환경에서 만들 수 없다.** 빌드는 `flutter doctor`의 Android toolchain ✓인 오너 PC 또는 CI에서 수행해야 한다(`docs/ANDROID_BUILD.md`).

---

## ✅ 이미 준비된 것 (계획서 "해소" 주장 = 실코드 CONFIRMED)

감사에서 실제 코드로 재확인한 항목. 계획서 판정이 최신 코드와 일치했다.

| 항목 | 상태 | 근거(실코드) |
|---|---|---|
| targetSdk/compileSdk **36**, minSdk **24** 명시 고정 | ✅ | `android/app/build.gradle.kts:25,36-37` — Play 2026-08-31 target 36 요건 상회 |
| 앱 라벨 = **쌤버십** | ✅ | `res/values/strings.xml` `app_name=쌤버십`, 매니페스트 `@string/app_name` |
| INTERNET 권한 release 포함 · cleartext 격리 · 위험권한 0 | ✅ | `main/AndroidManifest.xml` INTERNET 선언, cleartext는 debug/profile 소스셋에만 |
| **Commerce-Zero** — 스토어 빌드에 구매 진입점 0 | ✅ | 결제 SDK 의존성 0, `kInAppPaymentSteeringEnabled=false`, `openSubscribeWeb/openRechargeWeb` 프로덕션 호출부 0, 구독관리 링크 flag off+안내카드, IQ 작성 게이트 off, 멘토상세 CTA 비상호작용화, 가격표시 제거 |
| 죽은 UI 제거(가입 스텁·숏폼 재생 아이콘) | ✅ | 계획서 P0-4①② 해소가 코드로 확인, 심사관이 밟는 "준비 중" 경로 없음 |
| admin 앱 접근 차단 | ✅ | 역할 게이트에서 관리자 로그인 차단 |
| 약관/개인정보/탈퇴 인앱 링크가 **실페이지**로 열림 | ✅ | `settings_section`→운영 도메인. 웹 레포에 `/legal/terms`·`/legal/privacy` 실문안 + `/account/delete` 서버액션(재인증→익명화→soft-delete) 존재 |
| 계정삭제 익명화 RPC **라이브 적용됨** | ✅ | 적대적 검증: 라이브 DB에 `anonymize_user_for_deletion(p_user_id,p_reason)` RPC·`user_deletion_log`·`user_blocks` 실재. (단 `supabase/sql/115` 헤더의 "라이브 미적용" 주석은 낡음 — 정정 권장) |
| 시크릿 위생 | ✅ | 하드코딩 키 0, `.env`·`key.properties` 미커밋, 토큰 로깅 없음 |
| 서명 스켈레톤(조건 로딩+debug 폴백) | ✅ | `build.gradle.kts:13-18,44-65` — 코드는 옳음, 키 생성만 사람 몫 |
| 툴체인 정합(AGP 9.0.1·Kotlin 2.3.20·Gradle 9.1.0·JDK17) | ✅ | 4개 설정 파일 상호·JDK17·SDK36 일관, 상호 파괴 조합 없음 |
| 이번 세션 `createThread status:'pending'` 수정 | ✅ | `ThreadStatus` enum·`fromMap`·유일 호출부·웹 정본·DB CHECK 전부 정합, 컴파일/모델 무결 |

---

## 🟠 리스크 (블로커 아님 — 완화·마무리 권장)

제출을 막지는 않으나, 사전출시 리포트·심사관 인상·운영 안정성 관점에서 처리 권장.

| 리스크 | 내용 | 권장 조치 |
|---|---|---|
| Gradle `-Xmx8G` | `android/gradle.properties` 힙 8G+메타 4G — 표준 CI 러너(RAM 7GB)/저사양기에서 데몬 OOM/기동 실패 가능 | CI/저사양 대상이면 `-Xmx4G` 등으로 하향 또는 CI 프로파일 오버라이드 |
| ~~'알림 받기' 토글 무동작~~ | 토글은 **인앱 알림 설정**이며 정본 테이블 `notification_settings`(`push_enabled`·`groups`)에 실제로 저장·재로드된다. OS 푸시는 App-F0 에서 출시 범위 제외(FCM 제거)라 토글과 무관 | **해소(2026-07-26)**: 컬럼 추가·RLS 신설 불요 — 테이블과 `select_own`/`modify_own` 정책이 이미 실재(구 `users.notification_enabled` 는 참조 0 고아 컬럼). **토글 라벨 축소도 불요.** 저장 실패는 "준비 중" 위장 없이 원복 + 재시도 안내(`notification_settings_repository.dart:6-16`) |
| 16KB 페이지 정렬 미검증 | Android 15+ 타깃 신규앱 요건. Flutter 엔진이 처리하나 이 환경에서 실산출 검증 불가 | 빌드 머신에서 AAB 산출 후 정렬 확인 또는 Play Console 사전출시 리포트로 확인, 오래된 네이티브 플러그인 `.so` 업데이트 |
| 버전명 `0.1.0` | 리젝 사유는 아니나 베타/미완성 인상 | 정식 프로덕션 트랙이면 `1.0.0+1` 승격 검토. 비공개/내부 테스트면 현행 무방 |
| '정산 관리(웹)' 외부 링크 | `web_bridge_config` baseUrl 운영 확정으로 실제 외부 이동. 멘토 **출금** 관리(소비자 결제 아님)라 방어 가능 | **해소(2026-07-16, PR #28 머지)**: payout 링크도 `kPayoutManageLinkEnabled`(dart-define, 스토어 빌드 기본 off)로 flag화 — off 시 안내 카드 대체. 무주입 빌드에서는 외부 이동 자체가 없음 |
| 세션 토큰 평문 SharedPreferences | 앱 샌드박스라 Data safety 신고·리젝 대상 아님(Supabase 기본 동작) | (선택·출시 후) `flutter_secure_storage` 하드닝 |
| 계획서 내부 스테일 | `PLAY_STORE_REVIEW_PLAN.md` 재판정 총괄표(line 23)가 P0-5를 아직 🔴로 표기하고 존재하지 않는 `:32` debug 라인 인용(최신 배치표는 🔶로 갱신됨) · `supabase/sql/115` 헤더 "라이브 미적용" 주석 낡음 | 두 주석 정정(문서 정합성, 제출 무관) |

---

## 제출까지의 권장 순서

1. **빌드 머신 준비**(Flutter 3.44 계열 + `flutter doctor` Android toolchain ✓) — 이 컨테이너에선 불가.
2. **`.env` 생성**(운영 Supabase URL·anon key) — 없으면 빌드 실패.
3. **release keystore 생성 + `key.properties`** — 없으면 업로드 거부. Play App Signing 등록.
4. `flutter build appbundle --release` → **서명 주체가 debug 아님 확인** + 사전출시 리포트로 16KB 정렬·크래시 점검.
5. **Play Console 등록**: App access 테스트 계정(학생·멘토), Data safety 폼, 개인정보/약관 URL, 계정삭제 URL(`/account/delete`).
6. (선택) `-Xmx` 하향, 알림 토글 문구, 버전명 승격, 스테일 주석 정정.

**한 줄 판정**: 앱 코드는 심사 제출 준비가 됐다(실 툴체인에서 analyze 에러 0·test 331개 통과 — 부록 B). 지금 "부적절"한 이유는 코드가 아니라 **키·`.env`·콘솔 등록이라는 코드 밖 선행작업이 아직 안 됐기 때문**이며, 이 컨테이너에서는 Android SDK 부재+배포처 egress 차단으로 AAB 산출만 불가능하다. 위 4개 사람작업을 마치고 Android SDK가 있는 환경에서 빌드하면 제출 가능하다.

---

### 검증 방법 주석

- 7개 차원 병렬 감사 후, "블로커" 판정만 2개 렌즈(재현성·제출영향)로 적대적 재검증했다. 계정삭제 RPC 미적용 우려는 이 과정에서 **라이브 DB 실조회로 반박(RISK 하향)**됐다.
- 이 저장소만으로 확인 불가한 항목(운영 DB 마이그레이션 실적용, 실제 AAB 서명·정렬)은 "제출 전 확인" 항목으로 남겼다. 코드 소스 정독 기반이라 정적 분석이며, 최종 빌드 검증은 Flutter 툴체인 환경에서 수행해야 한다.

---

## 부록 B: 실제 툴체인 검증 실행 결과 (2026-07-16 · Flutter 3.44.6)

검증 컨테이너에 Flutter stable을 설치해 Dart 레벨 검증을 실제로 돌린 결과. (Android SDK가 필요한 단계만 환경 정책으로 막혔다.)

| 단계 | 결과 | 비고 |
|---|---|---|
| Flutter 설치 | ✅ 3.44.6 stable (Dart 3.12.2) | 프로젝트 기대치(3.44.x, pubspec `>=3.22.0`·Dart `<4.0.0`)와 동일 시리즈 |
| `flutter pub get` | ✅ 성공 | 의존성 정상 해결(18개 상위 버전은 제약상 미상향 — 정상) |
| `flutter analyze lib/` | ✅ **에러 0 · 경고 0** · info 린트 67건 | HANDOFF의 "analyze 에러 0" 주장 실증. 린트는 `prefer_const_constructors` 56 · `deprecated_member_use` 8 등 전부 info(비블로커). 이번에 수정한 `createThread` 파일 관련 이슈 0건 |
| `flutter test` | ✅ **331개 전부 통과** (실패 0) | HANDOFF의 "250개" 상회(스위트 성장). 헤드리스 셰이더 이슈 재현 없음. `createThread status:'pending'` 수정이 어떤 테스트도 깨지 않음 |
| `flutter build appbundle --release` | ⛔ **실행 불가** — `No Android SDK found` | 빌드가 `.env` 에셋·Dart 엔진 단계는 통과 후 Android SDK 탐지에서 중단. Android SDK 배포처 `dl.google.com`이 세션 egress 정책으로 **403 차단**되어 SDK 설치 자체가 불가(정책 거부는 재시도 대상 아님). AAB 실산출은 Android SDK가 있는 환경에서 수행 필요 |

**egress 재점검(2026-07-16, 2차)**: 빌드 관련 호스트를 전수 조사한 결과 **차단된 것은 `dl.google.com`(및 `dl-ssl.google.com`) 단 하나**다. 나머지 빌드 의존성 호스트 — `maven.google.com`(AGP/안드로이드 Gradle 아티팩트)·`services.gradle.org`(Gradle 배포)·`repo.maven.apache.org`/`repo1.maven.org`(Maven Central)·`plugins.gradle.org` — 는 **전부 200 허용**이다. Debian `apt`의 패키지 Android SDK는 platform-**23**·build-tools **29**가 최대라 이 앱의 **API 36** 요건에 무용하고, platform-36·최신 build-tools·NDK는 오직 `dl.google.com`에서만 배포된다. → **이 컨테이너에서 AAB까지 뽑으려면 정확히 `dl.google.com` 한 호스트만 egress 허용하면 된다**(그러면 `sdkmanager`로 platform-36·build-tools·NDK 설치 → `flutter build appbundle` 가능; Gradle 의존성 경로는 이미 열려 있음).

**해석**: 앱의 Dart/Flutter 소스는 실제 툴체인에서 **분석·테스트 모두 그린**이다(코드 품질·기능 무결성 실증 완료). 이번 세션의 `createThread` 수정도 analyze·test로 검증됐다. 남은 미검증은 **네이티브 Android 빌드 산출물(AAB)뿐**이며, 그 이유는 앱 결함이 아니라 (1) 이 환경에 Android SDK 부재 + (2) SDK 배포처 `dl.google.com` egress 차단이다. 제출 전 Android SDK가 갖춰진 오너 PC/CI에서(또는 이 환경에서 `dl.google.com` 허용 후) `flutter build appbundle` 1회 성공 + 서명 주체(debug 아님)·16KB 정렬을 확인하면 된다.
