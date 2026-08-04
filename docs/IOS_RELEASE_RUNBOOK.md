# iOS App Store 출시 런북 (정본)

> **이 문서가 iOS 출시 문서의 단일 정본이다.** 2026-08-04, 최신 master
> (`08c0caa6d1697d06bd1aeac5dcdf664959408466`, Build 15) 기준으로 초안 PR #23(S20
> `docs/IOS_BUILD_PLAN.md`)·PR #29(`docs/IOS_BUILD.md` 확장판)를 전면 재검증해 수렴했다.
> 두 PR 은 병합·cherry-pick 하지 않았고, 모든 항목의 판정은 §12 처리 매트릭스에 있다.
> `docs/IOS_BUILD.md` 는 이 문서로 안내하는 스텁으로 대체됐다.
> 정적 계약 가드: `test/contracts/ios_release_config_contract_test.dart`.

---

## 1. 기준점 (2026-08-04 실측)

| 항목 | 값 | 확인 방법 |
|---|---|---|
| master | `08c0caa6d1697d06bd1aeac5dcdf664959408466` | `git rev-parse origin/master` |
| 버전 | `0.1.0+15` (versionName 0.1.0 / build number 15) | `pubspec.yaml` |
| Flutter | 3.44.6 stable (CI 기준 버전 — `.github/workflows/flutter-ci.yml`) | `flutter --version` |
| iOS 의존성 관리 | **SwiftPM 기본**(3.44부터 공식 기본) + CocoaPods fallback | pbxproj `FlutterGeneratedPluginSwiftPackage` + `ios/Podfile` |
| 네이티브 iOS 플러그인 | supabase_flutter(2.x)·image_picker·file_picker(11.x)·pdfx(2.9.x)·url_launcher(6.3+)·package_info_plus·shared_preferences(전이)·app_links(전이) | `flutter pub deps` |
| 테스트 | 1296개 전부 통과(analyze 에러·경고 0) | CI 게이트와 동일 절차 |

## 2. iOS 네이티브 설정 정본 (실측표)

| 설정 | 값 | 위치 |
|---|---|---|
| 번들 ID (Runner) | `com.ssambership.app` (3구성 동일) | pbxproj `PRODUCT_BUNDLE_IDENTIFIER` |
| 번들 ID (RunnerTests) | `com.ssambership.app.RunnerTests` | pbxproj |
| 표시명 | `쌤버십` (Android 라벨·스토어 등록명과 일치) | Info.plist `CFBundleDisplayName` |
| `CFBundleName` | `ssambership_app` (내부명 — 변경 금지) | Info.plist |
| 배포 타깃 | **13.0** — Flutter 3.44.6 의 iOS 최소 지원(= SDK 소스 `Version(13,0)`)과 정확히 일치 | pbxproj 전 구성 + `ios/Podfile` |
| 디바이스 | iPhone+iPad (`TARGETED_DEVICE_FAMILY = "1,2"`) — 스타일러스 QA(S13~S19)가 iPad 대상 | pbxproj |
| 방향 | iPhone: 세로+가로 2종 / iPad: 4종 | Info.plist |
| 서명 | `CODE_SIGN_STYLE = Automatic` (팀 선택만 하면 됨) | pbxproj |
| ATS | `NSAllowsLocalNetworking` 만(로컬 Supabase 개발용 — 전면 해제 아님) | Info.plist |
| 권한 문구 | 사진 보관함·카메라(한글) — file_picker/pdfx 는 문서 선택기 방식이라 추가 권한 불필요 | Info.plist |
| 조회 스킴 | `LSApplicationQueriesSchemes = [https]` (§5-1) | Info.plist |
| 수출규정 | `ITSAppUsesNonExemptEncryption = false` (§7) | Info.plist |
| 개인정보 매니페스트 | `ios/Runner/PrivacyInfo.xcprivacy` — Runner Resources 에 정확히 1회 배선 (§6) | pbxproj |
| 앱 아이콘 | 1024px = RGB·alpha 없음(colortype 2 실측 — App Store 요건 충족) | `Assets.xcassets/AppIcon.appiconset` |
| 버전 매핑 | `CFBundleShortVersionString=$(FLUTTER_BUILD_NAME)`, `CFBundleVersion=$(FLUTTER_BUILD_NUMBER)` ← `pubspec.yaml version: x.y.z+N` | Info.plist |

## 3. 번들 ID — 오너 결정 게이트 (첫 업로드 전 확정 필수)

```text
CURRENT_IOS_BUNDLE_ID: com.ssambership.app
BUNDLE_ID_CHANGE_REQUIRED: UNRESOLVED_OWNER_DECISION
```

- 현행 `com.ssambership.app` 은 HANDOFF §3-6 패키지 계약(2026-07-22)의 iOS 값 그대로다.
  (과거 초안 PR #23 이 문제 삼던 `com.ssambership.ssambershipApp` 은 이미 master 에서 정리됨.)
- **Android 는 Play 요구로 `com.ssambership.edu` 로 수렴**했다. iOS 를 Android 와 맞출지
  (`com.ssambership.edu`), 현행 유지할지는 **오너만 결정**한다.
  - 현행 유지: 작업 0. 플랫폼 간 ID 는 달라도 기능 문제 없음(딥링크/Universal Links 도입 시 각자 등록).
  - `.edu` 로 변경: pbxproj `PRODUCT_BUNDLE_IDENTIFIER` 6곳(Runner 3 + RunnerTests 3) + 계약 테스트
    `kIosBundleId` 갱신. Firebase iOS 앱 등록(후속) 시에도 동일 ID 사용.
- **App Store Connect 에 첫 업로드하면 변경 불가.** 업로드 전이 마지막 변경 기회다.
- Apple 규칙: 영숫자·하이픈·마침표만(밑줄 불가 — Android 의 `ssambership_app` 형태 불가).

## 4. `.env` 준비와 feature flag 주입 정책

`.env` 는 pubspec 필수 에셋 — 없으면 빌드 자체가 실패한다.

```bash
cp .env.example .env    # 그리고 반드시 '운영 값'으로 교체
# SUPABASE_URL=https://<project-ref>.supabase.co
# SUPABASE_ANON_KEY=<remote-anon-key>
```

> ⚠️ 가장 흔한 실수: 로컬 기본값(`http://127.0.0.1:54321`)을 그대로 두면 릴리스 빌드는
> **성공**하지만 스토어 앱이 localhost 를 바라봐 "빈 앱"이 된다(크래시 없음 — graceful 처리).
> `SUPABASE_URL` 이 `supabase.co` 를 포함하면 플랫폼 분기 없이 그대로 사용된다.

**스토어 제출 빌드는 `--dart-define` 을 아무것도 주입하지 않는다** (Android 와 동일 규약):

| 플래그 | 기본값 | 스토어 빌드 |
|---|---|---|
| `IQ_CREATE_ENABLED` | false | 무주입(off) |
| `SUBS_MANAGE_LINK_ENABLED` | false | **무주입(off) — iOS 필수.** Apple 3.1.1 은 구독 관리 외부 링크도 문제 삼을 수 있음(§8-4) |
| `PAYOUT_MANAGE_LINK_ENABLED` | false | 무주입(off) |

## 5. 빌드 절차 (macOS + Xcode 전용)

Linux/CI 에서는 §9 의 정적 검증까지만 가능하다. 이하 macOS 에서:

```bash
flutter clean && flutter pub get
open -a Simulator && flutter run    # 시뮬레이터 스모크
flutter build ios --release --no-codesign   # 서명 없이 릴리스 빌드 완주 확인
```

- SwiftPM 이 기본 경로다(Flutter 3.44+). CocoaPods 는 SwiftPM 미지원 플러그인(예: pdfx)용
  fallback 으로 자동 병용 — `ios/Podfile` 은 그대로 두고 `pod install` 을 수동 실행할 필요 없음
  (flutter 도구가 필요 시 실행). CocoaPods 레지스트리는 2026-12-02 read-only 전환 예정 —
  이후 플러그인 업데이트는 SwiftPM 지원 버전을 우선한다.
- 서명 오류와 설정 오류를 구분할 것: `--no-codesign` 에서 실패하면 설정 문제,
  서명 단계에서만 실패하면 Team/인증서 문제다.

### 5-1. 웹 링크 런타임 확인 (시뮬레이터 스모크 항목)

`web_bridge` 는 `canLaunchUrl` 로 사전 확인하는데, iOS `canOpenURL` 은
**Info.plist `LSApplicationQueriesSchemes` 에 미선언인 스킴에 대해 항상 false 다**
(Apple UIApplication.canOpenURL 공식 문서 — 기기에 처리 앱이 있어도 false).
`https` 를 선언해 해결했다. `http` 는 선언하지 않는다 — `isAllowedUri` 가 https 를
강제해 http 는 `canLaunchUrl` 에 도달할 수 없다(계약 테스트가 이 정합을 고정).
선언 한도(iOS 15+ 링크: 50개, iOS 27+ 링크: 25개)와도 무관한 최소 구성이다.

시뮬레이터에서 실확인: 마이페이지 → 약관/개인정보/지원 → Safari 로 열리는지.
(2026-08-04 세션은 Linux — `IOS_WEB_LINK_RUNTIME: NOT_RUN_DEVICE`.)

### 5-2. 서명 아카이브 및 업로드

```bash
open ios/Runner.xcworkspace   # ⚠️ .xcodeproj 아님
# Runner ▸ Signing & Capabilities ▸ Team 선택(Automatic signing)
flutter build ipa --release   # build/ios/ipa/*.ipa (+ Xcode archive)
```

업로드(택1):
1. **Xcode Organizer**(권장): Product ▸ Archive → Distribute App ▸ App Store Connect ▸ Upload
2. **Transporter 앱**(Mac App Store 무료): ipa 드래그
3. CLI: `xcrun altool --upload-package` — ⚠️ 과거 문서의 `altool --upload-app` 은
   **deprecated**(altool man page)이니 새 스크립트에 쓰지 말 것. 자동화가 필요해지면
   App Store Connect API 키 기반으로 구성.

업로드 후 처리 완료(수 분~수십 분)되면 TestFlight/심사 제출 가능.

## 6. 개인정보 매니페스트 (PrivacyInfo.xcprivacy)

앱 수준 매니페스트는 **실측 근거로만** 선언한다 (2026-08-04, Flutter 3.44.6):

| 선언 주체 | 내용 | 근거 |
|---|---|---|
| 앱(`ios/Runner/PrivacyInfo.xcprivacy`) | 추적 없음·**수집 데이터 5종 선언(§6-1)**·**required-reason 선언 없음(빈 배열)** | 수집: 코드 인벤토리(감사 문서 D2) / required-reason: 1st-party 코드(lib/**·Swift 2파일) 전수 스캔 — 직접 사용 0건 |
| Flutter 엔진(Flutter.framework 동봉) | FileTimestamp(0A2A.1, C617.1) + SystemBootTime(35F9.1) | 3.44.6 엔진 아티팩트에서 실측 |
| shared_preferences_foundation(동봉) | UserDefaults(1C8F.1) | pub 캐시 2.5.6 실측 — supabase 세션 보존 경로 |
| image_picker/url_launcher/file_picker/package_info_plus/app_links(동봉) | required-reason 선언 없음 | pub 캐시 실측 |
| pdfx | 매니페스트 미동봉(플러그인 갭) | pub 캐시 실측 — 아래 ITMS-91053 절차로 대응 |

### 6-1. 수집 데이터 선언 (`NSPrivacyCollectedDataTypes` — 2026-08-04 교정)

**앱의 실제 코드·데이터 흐름이 privacy manifest 의 정본 근거다.** App Store Connect 설문과
`PrivacyInfo.xcprivacy` 는 동일 인벤토리(감사 문서 D2)에 맞춰 일치시킨다 — **설문 미작성은
manifest 수집 선언을 비워 둘 이유가 아니다**(TN3184: 수집하는 앱은 데이터 유형별 dictionary
필수 — Type/Linked/Tracking/Purposes 4키). 계약 테스트가 아래 표와 매니페스트를 1:1 로 고정한다.

| Apple 데이터 유형 | 실제 앱 데이터 | Linked | Tracking | Purpose | 코드 근거 |
|---|---|---:|---:|---|---|
| `…EmailAddress` | 로그인 이메일 | true | false | AppFunctionality | `auth_service.dart signInWithPassword` |
| `…UserID` | Supabase user id·닉네임(스크린네임 — Apple UserID 정의 포함) | true | false | AppFunctionality | self 계열 RPC·`user_profile_update_self(p_nickname)` |
| `…PhotosorVideos` | 질문 첨부 사진·카메라 촬영본 | true | false | AppFunctionality | image_picker → Storage 업로드 |
| `…OtherUserContent` | 질문·답변·댓글·PDF/파일 래스터본·필기·첨삭 | true | false | AppFunctionality | qna/iq/community RPC·`scan_annotation_repository` |
| `…OtherDataTypes` | 학년(선택 입력) | true | false | AppFunctionality | `profile_edit_screen` → `p_grade_level` |

**선언하지 않는 유형(근거)**: `PaymentInfo` — 결제수단 입력은 웹 전용, 앱은 원문 미접근.
`PurchaseHistory` — 앱은 서버 보유 구독 상태 조회만. `Name` — 실명 수집 없음(닉네임은 UserID
범주, 중복 선언 금지). 위치·주소록·기기ID·광고데이터 — 해당 코드·SDK 0건. 멘토 상세
프로필(대학·학과)은 웹에서만 입력(앱은 표시만) — 미선언.

### 6-2. required-reason API 선언 원칙

- 원칙(Apple 공식): 각 바이너리/SDK 는 자기 사용분을 자기 매니페스트에 선언한다.
  앱 매니페스트에 엔진·플러그인 사용분을 **중복 선언하지 않는다**. 과거 초안의 reason
  목록(#23: C617.1+35F9.1 = 엔진 선언과 중복 / #29: CA92.1 = 앱 미사용·플러그인은 1C8F.1 로
  자체 선언)은 이 실측으로 대체됐다.
- **ITMS-91053 대응 절차**: 업로드 후 Apple 메일이 특정 카테고리를 지목하면 ① 지목된
  카테고리·바이너리 확인 → ② 해당 플러그인 업데이트로 해소 가능한지 먼저 확인 → ③ 불가할
  때만 앱 매니페스트에 지목 카테고리를 Apple 공식 reason 정의에 맞춰 추가하고 계약 테스트
  allowlist 를 함께 갱신. 예방용 선제 추가 금지.
- **macOS 검증(§9)**: Xcode ▸ Product ▸ Archive → Organizer 에서 **Generate Privacy Report** 로
  앱+SDK 매니페스트 병합 결과를 확인하고, Build Phases ▸ Copy Bundle Resources 에
  PrivacyInfo.xcprivacy 가 1회만 있는지 본다(계약 테스트가 pbxproj 수준에서 이미 고정).

## 7. 수출규정(export compliance)과 버전 규약

**`ITSAppUsesNonExemptEncryption=false` 근거 (2026-08-04 전수 확인):**
- 네트워크: OS 제공 TLS(HTTPS, Supabase `*.supabase.co`) — 표준 프로토콜 면제.
- 의존성 트리의 자체 암호 구현은 `pointycastle` 하나(supabase→gotrue→dart_jsonwebtoken 경유),
  용도는 **JWT 서명 검증 = 인증·전자서명** — 면제 범주. `crypto` 패키지는 해시(SHA) 전용.
- VPN·E2E 암호화·독자 암호화 프로토콜·콘텐츠 암호화: 없음.
- **재검토 트리거**: 비면제 암호화(독자 프로토콜, 콘텐츠 암호화 등) 도입 시 이 키와
  App Store Connect 수출규정 답변을 함께 재검토(연례 self-classification 보고 대상 여부 포함).

**버전 규약** (`pubspec.yaml version: x.y.z+N` 이 유일한 소스):
- 이번 수렴 PR 은 `0.1.0+15` **불변**(계약 테스트로 고정).
- App Store Connect 는 같은 마케팅 버전 안에서 **빌드 번호 재사용을 거부** — 업로드마다 +N 증가.
  증가는 실제 업로드 직전 별도 release 커밋으로만(계약 테스트 상수 동시 갱신).
- 첫 공개 출시에서 `0.1.0`→`1.0.0` 상향 여부: **오너 결정**(§11).

## 8. App Store Connect (오너 작업)

1. **Apple Developer Program** 가입(연 $99) → Xcode Team 로그인(서명 Automatic).
2. **번들 ID 확정(§3)** → App Store Connect 앱 생성(이름 '쌤버십', 기본 언어 ko).
3. **App Privacy 설문**: §6-1 의 동일 인벤토리로 작성한다 — 매니페스트 정적 선언(완료)과
   설문(오너 작업)은 서로 독립된 항목이 아니라 **같은 사실관계를 두 표면에 일치시키는 작업**이다.
   실제 수집: 이메일·User ID/닉네임·사용자 콘텐츠(질문·첨부·필기)·학년. 추적(ATT) 없음.
   Play Data safety(`docs/DATA_SAFETY_FORM.md`)와 같은 항목표 기준으로 작성.
4. **외부 결제·구독 링크(3.1.1)**: 앱은 Commerce-Zero(구매 유도 진입점 0, IAP 미탑재).
   `SUBS_MANAGE_LINK_ENABLED` 는 iOS 스토어 빌드에서 **주입 금지 유지**(§4). 미국 스토어프런트의
   외부 링크 완화(2025~)는 별도 수수료·약정 조건이 있으므로, 링크 활성화는 최신 3.1.1 재확인 후
   오너 결정으로만. 정산 관리(멘토 지급 관리) 링크는 소비자 결제가 아니므로 대체로 허용 —
   심사 노트에 성격 명시 권장.
5. **계정 삭제(5.1.1(v))**: 앱 내에서 삭제를 **개시**할 수 있어야 한다 — 현행 구현이 충족:
   앱 내 탈퇴 흐름(RPC `account_deletion_request_self_consented_v2` 계열, 동의·상태 조회 포함)
   + 웹 완료 페이지 링크(`/account/delete`). Apple 은 웹에서 완료하는 방식도 "완료 페이지로의
   직접 링크"면 허용한다. (과거 초안의 "웹 링크 단독" 서술은 구식 — 현행이 더 강한 충족.)
6. **심사관용 데모 계정**: 학생·멘토 각 1개(로그인 가능 + 구독·질문 데이터 시드)를 App Review
   정보에 기재. 인앱 가입이 없으므로 리뷰 노트에 "계정은 웹 서비스에서 생성"을 명시.
7. **스크린샷·메타데이터**: 필수 기기 크기(iPhone 6.7"/6.5"/5.5" + iPad 13") 스크린샷,
   지원 URL(`/support`), 개인정보처리방침 URL(`/legal/privacy`).
8. **TestFlight 내부 테스트** 1회 이상 후 심사 제출.

## 9. 검증 상태 (2026-08-04 수렴 세션 실측 — Linux)

```text
IOS_STATIC_CONFIGURATION: PASS   (plist·매니페스트 python plistlib 파싱 + 계약 테스트)
FLUTTER_ANALYZE: PASS            (에러 0·경고 0 — info 75건은 CI 게이트 비차단)
FLUTTER_TEST: PASS               (전 스위트 + iOS 계약 테스트)
PRIVACY_MANIFEST_STATIC: PASS
PRIVACY_REPORT_RUNTIME: BLOCKED_MACOS   (Xcode Generate Privacy Report 필요)
IOS_NO_CODESIGN_BUILD: BLOCKED_MACOS    (flutter build ios --release --no-codesign)
IOS_SIMULATOR_RUNTIME: NOT_RUN_DEVICE   (§5-1 웹 링크 스모크 포함)
IOS_ARCHIVE: BLOCKED_MACOS
IOS_SIGNING_VERIFIED: NO
APP_STORE_UPLOAD: NO
```

macOS 확보 시 첫 작업 = §5 절차 완주(스모크 → no-codesign → archive → Privacy Report).

## 10. Rollback

- 이 수렴 PR 의 변경은 전부 정적 설정·문서·테스트 — 문제가 있으면 **PR revert 한 번**으로
  완전 복구된다(DB·서명키·스토어 상태와 무관).
- 업로드 후 롤백: App Store Connect 는 업로드된 빌드 삭제 불가 — 잘못된 빌드는 심사 제출을
  취소하고 **빌드 번호를 올려 재업로드**한다(§7). 심사 통과 후엔 단계적 출시 중단/새 버전 제출.
- 번들 ID 는 첫 업로드 전까지만 롤백(변경) 가능(§3).

## 11. 오너 체크리스트 (코드 밖 결정·작업)

> 각 결정의 상세 근거·데이터 인벤토리·암호화 인벤토리·required-reason 정적 인벤토리는
> **`docs/audit/ios_release_owner_decisions_20260804.md`** (D1~D5 + 부록)에 있다.

- [ ] 번들 ID 확정: `com.ssambership.app` 유지 vs `com.ssambership.edu` 정렬 (§3 — 첫 업로드 전)
- [ ] 마케팅 버전: 첫 공개 출시를 `0.1.0` 으로 갈지 `1.0.0` 상향할지 (§7)
- [ ] Apple Developer Program 가입 + Xcode 서명 팀 구성 (§8-1)
- [ ] App Privacy 설문 작성 → 매니페스트 `NSPrivacyCollectedDataTypes` 동기화 (§8-3)
- [ ] 데모 계정 2종 시드 (§8-6)
- [ ] 웹 레포 소유 페이지 실게시 확인: 약관·개인정보·지원·`/account/delete` (§8-5·8-7)
- [ ] macOS 검증 완주 (§9) → 이후에만 TestFlight/제출

---

## 12. PR #23·#29 처리 매트릭스

판정 규칙: `ADOPTED`(그대로 채택) / `REPLACED`(의도는 수용, 내용은 재구성·최신화) /
`REJECTED`(기각 — 불필요·오류·구식) / `OWNER_DECISION_REQUIRED`.

### 요약표

| ID | 원본 PR | 항목 | 현재 master 상태(수렴 전) | 판정 |
|---|---|---|---|---|
| IOS-01 | #23 | `LSApplicationQueriesSchemes` | 없음 | **REPLACED** (https 만 채택, http 기각) |
| IOS-02 | #23 | `ios/Podfile` 신설 | 이미 존재(13.0 + post_install 정렬 — #23 안보다 상위호환) | **REJECTED** (불필요 — master 기존 유지) |
| IOS-03 | #23 | 표시명 `쌤버십` | 이미 반영 | **REJECTED** (불필요 — 계약 가드만 신설) |
| IOS-04 | #23·#29 | `ITSAppUsesNonExemptEncryption=false` | 없음 | **ADOPTED** (근거 전수조사로 보강) |
| IOS-05 | #23·#29 | `PrivacyInfo.xcprivacy` | 없음 | **REPLACED** (파일·배선 수용, reason 목록은 실측으로 재구성) |
| IOS-06 | #23·#29 | pbxproj Resources 배선 | 없음 | **ADOPTED** (신규 UUID 로 현 master 구조에 재구현) |
| IOS-07 | #23·#29 | 출시 문서 | 구판 `IOS_BUILD.md` 만 | **REPLACED** (본 런북 단일 정본) |
| IOS-08 | #23 | HANDOFF 반영 | iOS 항목 1줄 | **REPLACED** (포인터 최소 갱신) |
| IOS-09 | 공통 | 번들 ID | `com.ssambership.app` (이미 정리됨) | **OWNER_DECISION_REQUIRED** (§3) |
| IOS-10 | 공통 | 배포 타깃 13.0 | 13.0 | **ADOPTED** (Flutter 3.44.6 최소값과 일치 재확인 — 변경 0) |

### 상세 기록

```text
SOURCE_PR: #23
SOURCE_FILE: ios/Runner/Info.plist
SOURCE_CHANGE: LSApplicationQueriesSchemes 에 https·http 선언 ("canLaunchUrl 이 iOS 에서 항상 false" P0 주장)
DECISION: REPLACED
CURRENT_IMPLEMENTATION: https 단독 선언 + 계약 테스트가 web_bridge 의 https 강제·canLaunchUrl 사용과 plist 를 상호 고정
RATIONALE: 주장 자체는 공식 문서로 확인됨(미선언 스킴은 canOpenURL 항상 false). 단 http 는
  isAllowedUri 가 차단해 canLaunchUrl 에 도달 불가 — 최소 구성 원칙으로 기각. 다른 launchUrl
  호출부(chat/mentor_answer/version_gate)는 canLaunchUrl 미사용이라 무관.
OFFICIAL_REFERENCE: Apple UIApplication.canOpenURL(_:) 문서(미선언 스킴 항상 false, iOS15+ 50개
  /iOS27+ 25개 한도); url_launcher README("otherwise it will return false")
VERIFICATION: 정적 계약 테스트 PASS. 런타임 재현은 NOT_RUN_DEVICE(§5-1 스모크 항목으로 이관 —
  P0 단정은 코드 경로 분석 기준)
```

```text
SOURCE_PR: #23
SOURCE_FILE: ios/Podfile
SOURCE_CHANGE: 표준 Flutter Podfile 신설(platform :ios, '13.0')
DECISION: REJECTED (불필요 — 이미 해결됨)
CURRENT_IMPLEMENTATION: master 기존 Podfile 유지(동일 platform 13.0 + post_install 에서 전체 Pod
  배포 타깃 13.0 정렬 — #23 안에는 없는 개선). 계약 테스트로 platform 13.0 고정.
RATIONALE: #23 작성 시점(구 base)에는 Podfile 이 없었으나 현재 master 에 상위호환 버전이 존재.
  새 파일 생성 불요. Flutter 3.44 는 SwiftPM 기본 + CocoaPods fallback(pdfx 등 미지원 플러그인)
  이므로 Podfile 은 유지가 정답 — 삭제도 재생성도 하지 않음.
OFFICIAL_REFERENCE: Flutter 공식 발표 "SwiftPM is the default in 3.44"(CocoaPods 는 fallback,
  레지스트리 2026-12-02 read-only); Flutter 3.44.6 SDK 소스 deploymentTarget=13.0
VERIFICATION: 계약 테스트 PASS(Podfile 13.0 = pbxproj 13.0 정합)
```

```text
SOURCE_PR: #23
SOURCE_FILE: ios/Runner/Info.plist
SOURCE_CHANGE: CFBundleDisplayName "Ssambership App" → 쌤버십
DECISION: REJECTED (불필요 — 이미 반영됨)
CURRENT_IMPLEMENTATION: master 가 이미 쌤버십. 계약 테스트로 고정만 신설.
RATIONALE: #23 의 판단은 옳았고 master 에 별도로 반영 완료 — 이 PR 에서 채택할 변경이 없음.
OFFICIAL_REFERENCE: — (제품 정본: Android 라벨·스토어 등록명 일치)
VERIFICATION: 계약 테스트 PASS
```

```text
SOURCE_PR: #23 + #29 (동일 제안)
SOURCE_FILE: ios/Runner/Info.plist
SOURCE_CHANGE: ITSAppUsesNonExemptEncryption=false
DECISION: ADOPTED
CURRENT_IMPLEMENTATION: 동일 키/값 반영. 근거를 의존성 전수조사로 보강(§7): OS TLS 외 자체 암호
  구현은 pointycastle(JWT 서명 검증 = 인증·전자서명 면제)뿐임을 실측 — 두 PR 모두 이 조사 없이
  "표준 HTTPS 만 사용"이라고만 서술했음.
RATIONALE: Apple 정의 그대로 — "앱과 링크된 서드파티 라이브러리 포함, 면제 암호화만 사용" 시 false.
OFFICIAL_REFERENCE: Apple ITSAppUsesNonExemptEncryption 문서 + App Store Connect
  "Overview of export compliance"
VERIFICATION: 계약 테스트 PASS(키 1회·false). 재검토 트리거 §7 명문화
```

```text
SOURCE_PR: #23 + #29 (내용 상충)
SOURCE_FILE: ios/Runner/PrivacyInfo.xcprivacy
SOURCE_CHANGE: #23 = FileTimestamp C617.1 + SystemBootTime 35F9.1 ("Flutter 표준 템플릿과 동일").
  #29 = UserDefaults CA92.1 + FileTimestamp C617.1 (supabase 세션·파일 플러그인 근거 주장)
DECISION: REPLACED (파일 신설·취지 수용, reason 목록은 양쪽 모두 기각하고 실측으로 재구성)
CURRENT_IMPLEMENTATION: 추적 없음·수집 데이터 5종 선언(§6-1 — TN3184 기준, 2026-08-04 교정으로
  초기 빈 배열 상태 폐기)·required-reason 빈 배열(§6-2). 계약 테스트가 수집 선언을 코드
  인벤토리와 1:1 고정하고, required-reason allowlist(현재 공집합)·reason 형식을 고정.
RATIONALE: ① Flutter 3.44.6 앱 템플릿에는 앱 수준 PrivacyInfo 가 없음(#23 의 "표준 템플릿" 근거
  소멸 — 플러그인 템플릿에만 존재). ② 엔진이 FileTimestamp(0A2A.1,C617.1)+SystemBootTime(35F9.1)
  을 Flutter.framework 매니페스트로 자체 선언(실측) — #23 목록은 전부 중복. ③ UserDefaults 는
  shared_preferences_foundation 이 1C8F.1 로 자체 선언(실측) — #29 의 CA92.1(앱 단독 접근용
  reason)은 주체도 코드도 틀림(앱 1st-party 코드는 UserDefaults 미사용). ④ Apple 원칙: 자기
  사용분만 자기 매니페스트에 선언. 예방용 추가 금지 — ITMS-91053 대응 절차로 대체(§6).
OFFICIAL_REFERENCE: Apple "Describing use of required reason API"(C617.1/0A2A.1/CA92.1/1C8F.1/
  35F9.1 정의) + "Adding a privacy manifest to your app or third-party SDK"
VERIFICATION: python plistlib 파싱 PASS + 계약 테스트 PASS. 병합 결과 확인은
  PRIVACY_REPORT_RUNTIME: BLOCKED_MACOS(§9)
```

```text
SOURCE_PR: #23 + #29 (동일 취지, UUID·파일타입만 상이)
SOURCE_FILE: ios/Runner.xcodeproj/project.pbxproj
SOURCE_CHANGE: PrivacyInfo.xcprivacy 를 PBXBuildFile/PBXFileReference/Runner 그룹/Resources 4곳 배선
DECISION: ADOPTED (신규 UUID 로 재구현)
CURRENT_IMPLEMENTATION: 5C9E4D7A2F1B4E8090A1B2C3(fileRef)/…C4(buildFile) — 현 master pbxproj
  (SwiftPM 통합 구조)에 직접 배선. lastKnownFileType 은 text.plist.xml(#29 방식 — .xcprivacy 는
  plist XML이므로 #23 의 text.xml 보다 정확).
RATIONALE: 두 PR 의 patch 는 구 base pbxproj 기준이라 그대로 적용 불가(충돌) — 의미만 수용.
OFFICIAL_REFERENCE: Apple 매니페스트 배치 규칙(번들 리소스 최상위)
VERIFICATION: 계약 테스트 PASS(정확히 1회 배선·fileRef 정합·괄호 균형)
```

```text
SOURCE_PR: #23(docs/IOS_BUILD_PLAN.md 신설) + #29(docs/IOS_BUILD.md 확장)
SOURCE_FILE: docs/IOS_BUILD_PLAN.md, docs/IOS_BUILD.md
SOURCE_CHANGE: 각자 별도의 출시 절차·심사 리스크 문서
DECISION: REPLACED (본 런북 docs/IOS_RELEASE_RUNBOOK.md 단일 정본으로 수렴)
CURRENT_IMPLEMENTATION: IOS_BUILD_PLAN.md 는 생성하지 않음. IOS_BUILD.md 는 스텁으로 대체.
  두 초안의 유효 내용(.env footgun, 빌드번호 유일성, 업로드 경로, 심사 리스크 평가, 오너 작업)은
  재검증 후 본 런북에 흡수.
RATIONALE: 문서 2본 병존은 충돌 원인. 개별 기각 사항 — #29 의 `xcrun altool --upload-app` 은
  deprecated(→ --upload-package / Organizer / Transporter)로 교체. #29 의 "PrivacyInfo 에
  UserDefaults·FileTimestamp 선언됨" 서술은 매니페스트 재구성에 따라 폐기. #23 의 "계정 삭제 =
  웹 링크 방식" 서술은 구식 — 현행은 앱 내 RPC 개시 + 웹 완료(§8-5)로 더 강하게 충족.
  #23 의 Apple 심사 리스크 표(3.1.1 엄격·정산 링크 허용·게스트 열람 유리)는 유효해 §8 에 흡수.
  #29 의 "1.0.0 상향 권장"은 권장이 아닌 OWNER_DECISION 으로 강등(§11).
OFFICIAL_REFERENCE: altool man page(--upload-app deprecated); Apple 계정 삭제 요구사항 문서;
  App Review Guidelines 3.1.1/5.1.1(v)
VERIFICATION: 계약 테스트 PASS(정본 존재·필수 절·구식 문서 스텁화·IOS_BUILD_PLAN 부재)
```

```text
SOURCE_PR: #23
SOURCE_FILE: HANDOFF.md
SOURCE_CHANGE: S20 세션 행 추가 + §3-6 iOS 상세 서술 + 인수인계 요약 갱신
DECISION: REPLACED (최소 갱신)
CURRENT_IMPLEMENTATION: §3-6 의 iOS 항목을 본 런북 포인터로 1줄 갱신만. 세션 행 추가는 하지 않음
  (#23 의 행 내용은 구 base 전제 — Podfile 신설·표시명 변경 등 — 라 사실과 불일치).
RATIONALE: HANDOFF 는 현행 유지가 정본 — 장문 중복 서술 대신 정본 문서 포인터가 원칙.
OFFICIAL_REFERENCE: —
VERIFICATION: HANDOFF diff 최소(1줄) 확인
```

```text
SOURCE_PR: #23 + #29 (공통 전제)
SOURCE_FILE: ios/Runner.xcodeproj/project.pbxproj (PRODUCT_BUNDLE_IDENTIFIER)
SOURCE_CHANGE: #23 "현재 com.ssambership.ssambershipApp — 밑줄 불가로 Android 와 불일치, 확정 필요"
DECISION: OWNER_DECISION_REQUIRED (전제 사실은 구식)
CURRENT_IMPLEMENTATION: 변경 0 — 현행 com.ssambership.app 유지 + 계약 테스트로 임의 변경 차단.
  결정 자료·변경 대상 파일·운영 게이트는 §3.
RATIONALE: 두 PR 의 "ssambershipApp" 전제는 이미 master 에서 해소. 남은 결정은 Android
  com.ssambership.edu 와의 정렬 여부이며 첫 업로드 전 오너만 확정 가능.
OFFICIAL_REFERENCE: Apple App ID 규칙(영숫자·하이픈·마침표); App Store Connect 첫 업로드 후 변경 불가
VERIFICATION: CURRENT_IOS_BUNDLE_ID 실측 기록(§3) + 계약 테스트 PASS
```

```text
SOURCE_PR: #23 + #29 (공통 전제)
SOURCE_FILE: ios/Runner.xcodeproj/project.pbxproj, ios/Podfile (IPHONEOS_DEPLOYMENT_TARGET)
SOURCE_CHANGE: 13.0 유지 전제
DECISION: ADOPTED (변경 0 — 재검증만)
CURRENT_IMPLEMENTATION: 13.0 전 구성 유지. 계약 테스트가 pbxproj 전 구성=13.0·Podfile 정합 고정.
RATIONALE: Flutter 3.44.6 의 iOS 최소 지원이 13.0(SDK 소스 실측 Version(13,0)) — 상향 강제 없음.
  supabase_flutter 2.x 등 사용 플러그인 요건도 충족.
OFFICIAL_REFERENCE: Flutter 3.44.6 flutter_tools 소스(darwin.dart deploymentTarget)
VERIFICATION: 계약 테스트 PASS
```
