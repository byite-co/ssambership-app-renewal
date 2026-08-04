# iOS 출시 오너 결정·게이트 감사 (2026-08-04, PR #43)

> PR #43(`claude/ios-release-config-convergence-h5j6j8`, head `93def1a`) 의 정적 수렴 이후
> 남은 게이트를 실제 코드·공식 문서로 재검증한 기록. 절차 정본은
> `docs/IOS_RELEASE_RUNBOOK.md`, 설정 가드는 `test/contracts/ios_release_config_contract_test.dart`.
> **미결정 항목은 `OWNER_DECISION_REQUIRED` 로 명시한다 — PASS 위장 없음.**

---

## D1. Bundle ID

```text
CURRENT: com.ssambership.app
ANDROID_MEASURED: com.ssambership.edu   (android/app/build.gradle.kts — applicationId·namespace 실측)
RECOMMENDATION: Apple 등록 이력이 없음이 확인되면 com.ssambership.edu 정렬 검토,
                등록 여부 불명확 시 com.ssambership.app 유지
ALTERNATIVE: com.ssambership.edu (iOS 형식 유효 — 영숫자·마침표만)
APP_STORE_ALREADY_REGISTERED: UNKNOWN — 저장소 내 App Store Connect 앱 생성/App ID 등록 증거 없음
                              (docs 전수 검색: 등록 '지시'만 있고 '완료' 기록 없음). 오너 콘솔 확인 필요.
OWNER_DECISION: OWNER_DECISION_REQUIRED
IMPLEMENTED: NO (현행 유지 — 계약 테스트가 임의 변경 차단)
```

**변경 비용 실측** (변경 결정 시): pbxproj `PRODUCT_BUNDLE_IDENTIFIER` 6곳 + 계약 테스트
`kIosBundleId` 1곳. **그 외 결합 없음** — Firebase iOS 설정 파일 없음, OAuth redirect 미사용
(`signInWithOAuth` 0건 — 이메일/비밀번호 로그인만), Universal Links/Associated Domains 없음,
push entitlement 없음(App-F0), `CFBundleURLTypes` 없음, Supabase redirect URL 의존 없음.
→ 변경은 현시점에 저비용이나 **App Store Connect 첫 업로드 후 불변**이므로 업로드 전 확정 필수.

## D2. App Privacy

```text
DATA_INVENTORY_COMPLETE: PASS (아래 표 — 전 행 코드 경로 근거)
APP_STORE_QUESTIONNAIRE_VALUES: 아래 표의 '설문 제안값' 열 (오너 확정 필요)
NSPRIVACY_COLLECTED_DATA_TYPES: UNRESOLVED — 빈 배열 유지(아래 판정 근거), 오너 설문 확정
                                + macOS privacy report 후 동기화
TRACKING: false (광고·추적 SDK 0건 실측 — ATT 불필요)
OWNER_APPROVED: OWNER_DECISION_REQUIRED
```

### 데이터 인벤토리 (코드 전수 근거)

| 데이터 범주 | 실제 필드 | 앱에서 수집 | 사용자 연결 | 추적 | 목적 | 근거(코드 경로) |
|---|---|---|---|---|---|---|
| Contact Info — 이메일 | 로그인 이메일 | **YES** | YES | NO | 앱 기능(인증) | `auth_service.dart:268 signInWithPassword` → Supabase Auth |
| Identifiers — User ID | Supabase user id·닉네임(스크린네임 → Apple 'User ID' 범주) | **YES** | YES | NO | 앱 기능 | 전 RPC self 계열, `user_profile_update_self(p_nickname)` |
| User Content — 질문·답변·댓글 | 질문방/IQ 메시지, 커뮤니티 글·댓글 | **YES** | YES | NO | 앱 기능 | `qna_append_message`·`iq_append_message`·`community_*` RPC |
| Photos or Videos | 질문 첨부 이미지·카메라 촬영본 | **YES** | YES | NO | 앱 기능 | image_picker → Storage 업로드(`iq_create_screen`·첨부 repo) |
| Other User Content | PDF·파일·필기(ink.json)·첨삭 PNG | **YES** | YES | NO | 앱 기능 | file_picker/pdfx/`scan_annotation_repository` |
| Other Data Types | 학년(gradeLevel, 선택 입력) | **YES** | YES | NO | 앱 기능 | `profile_edit_screen.dart:62` → `user_profile_update_self(p_grade_level)` |
| Purchases | 구독·캐시 상태 | NO — **서버 보유값 조회만**(결제·수집은 웹에서) | — | — | — | Commerce-Zero, entitlement 조회 RPC(읽기) |
| Financial Info | 결제수단 원문 | NO | — | — | — | 해당 코드 0건 |
| Usage Data | 화면·기능 사용 분석 | NO — 분석 SDK 0건 | — | — | — | pubspec·lib 전수 grep(analytics/mixpanel/amplitude 0) |
| Diagnostics | crash·성능 | NO — crash SDK 0건(Firebase 제거됨 App-F0) | — | — | — | pubspec 실측 |
| Location | 위치 | NO | — | — | — | 권한·플러그인 0건 |
| Contacts | 주소록 | NO | — | — | — | 권한·플러그인 0건 |
| Sensitive Info | 민감정보(인종·성적지향 등 Apple 정의) | NO — 학년은 이 범주 아님 | — | — | — | Apple 범주 정의 기준 |

구분 명시: 위 YES 항목은 전부 **앱이 직접 Supabase 로 전송**하는 값. 구독·정산·결제는
**외부 웹에서만 수집**(앱은 조회). 푸시 토큰 수집 코드는 존재하나 **런타임 미연결**
(Firebase 설정 파일 없음 — App-F0 로 출시 범위 제외).

### NSPrivacyCollectedDataTypes 판정 (빈 배열 유지 근거)

1. Apple 공식 문서(Privacy manifest files): 수집 데이터 기술은 앱에도 기대되나, **심사·공개의
   구속력 있는 정본은 App Store Connect App Privacy 설문**이며 매니페스트 자동 강제는
   required-reason API·지정 서드파티 SDK 목록에 적용된다.
2. 설문이 미작성 상태에서 매니페스트를 먼저 채우면 '설문과 일치' 규칙을 코드가 아닌 추측으로
   선점하게 된다(예: 닉네임의 User ID vs Name 범주는 오너 설문 답변이 정본) — 금지사항
   "설문값 추측" 위반. → 설문 확정(OWNER) 후 위 표대로 채우고 계약 테스트를 함께 갱신한다.
3. 빈 배열은 형식상 유효하며 현재 앱의 required-reason·추적 선언과 모순 없음.
4. Xcode privacy report 로 병합 결과를 확인하기 전까지 최종 PASS 로 닫지 않는다(BLOCKED_MACOS).

## D3. Export compliance

```text
STATIC_ASSESSMENT: EXEMPT_LIKELY
ITSAppUsesNonExemptEncryption: false (Info.plist 반영 — PR #43)
APP_STORE_QUESTIONNAIRE_COMPLETED: NO → OWNER_ACTION_REQUIRED
OWNER_APPROVED: OWNER_DECISION_REQUIRED
IOS_EXPORT_COMPLIANCE: OWNER_REVIEW_REQUIRED (설문 미완료 상태에서 PASS 표기 금지)
```

### 암호화 인벤토리 (실행 경로 기준)

| 라이브러리·기능 | 실제 실행 경로 | 성격 | OS 제공 | 면제 근거 | 추가 확인 |
|---|---|---|---|---|---|
| HTTPS/TLS (Supabase) | 전 네트워크 호출 | 전송 암호화 | **YES** | 표준 프로토콜(OS TLS) | — |
| `crypto` 3.0.7 | gotrue PKCE 등 해시(SHA) | 해시(암호화 아님) | n/a | 해시는 규제 대상 아님 | — |
| `pointycastle` 4.0.0 (gotrue→dart_jsonwebtoken) | `gotrue_client.dart:1691 JWT.verify(token, publicKey)` — `getClaims()` 내부 | 공개키 서명 **검증** | NO(순수 Dart) | 인증·전자서명 용도 = 면제 범주 | 앱은 `getClaims` **미호출**(lib 전수 grep 0건) — AOT 트리셰이킹으로 바이너리 미포함 가능성 높음. 포함되더라도 면제 판정 불변 |
| 자체 암호화/복호화·키 생성·E2E·VPN·TLS pinning | 코드 0건 | — | — | — | — |
| OS Keychain | 직접 사용 0건(세션은 shared_preferences) | — | — | — | — |

## D4. Marketing version

```text
CURRENT: 0.1.0 (+15)
CANDIDATE: 1.0.0 (첫 공개 출시 시)
OWNER_DECISION: OWNER_DECISION_REQUIRED
IMPLEMENTED_THIS_PR: NO (계약 테스트가 0.1.0+15 고정)
```

## D5. Signing·upload

```text
APPLE_DEVELOPER_TEAM: OWNER_DECISION_REQUIRED (가입 증거 저장소에 없음)
SIGNING_READY: NO (CODE_SIGN_STYLE=Automatic — 팀 로그인만 필요)
APP_STORE_CONNECT_APP_CREATED: UNKNOWN (D1 참조 — 증거 없음)
TESTFLIGHT_UPLOAD_APPROVED: OWNER_DECISION_REQUIRED
```

---

## 부록 A. Required-reason API 정적 인벤토리 (Flutter 3.44.6 실측)

| SDK | manifest 존재 | API category | reason | archive 포함 확인 |
|---|---|---|---|---|
| Runner 앱(`ios/Runner/PrivacyInfo.xcprivacy`) | YES | (없음 — 빈 배열) | — | BLOCKED_MACOS |
| Flutter engine(Flutter.framework 동봉) | YES | FileTimestamp / SystemBootTime | 0A2A.1·C617.1 / 35F9.1 | BLOCKED_MACOS |
| shared_preferences_foundation 2.5.6 | YES | UserDefaults | 1C8F.1 | BLOCKED_MACOS |
| image_picker_ios 0.8.13+6 | YES | (required-reason 없음) | — | BLOCKED_MACOS |
| url_launcher_ios 6.4.1 | YES | (required-reason 없음) | — | BLOCKED_MACOS |
| file_picker 11.0.2 | YES | (required-reason 없음) | — | BLOCKED_MACOS |
| package_info_plus 9.0.1 | YES | (required-reason 없음) | — | BLOCKED_MACOS |
| app_links 7.2.0 | YES | (required-reason 없음) | — | BLOCKED_MACOS |
| path_provider_foundation 2.6.0 | **NO**(패키지 전수 검색 0건) | — | — | BLOCKED_MACOS |
| pdfx 2.9.2 (ios 네이티브 있음) | **NO** | — | — | BLOCKED_MACOS |
| supabase_flutter 계열 | 순수 Dart(ios 네이티브 없음) | — | — | n/a |
| scribble | 순수 Dart | — | — | n/a |

```text
REQUIRED_REASON_STATIC_INVENTORY: PASS
REQUIRED_REASON_ARCHIVE_INVENTORY: BLOCKED_MACOS
```

미동봉 2건(path_provider_foundation·pdfx)은 **플러그인 소관** — 앱 매니페스트 선제 대필 금지
(런북 §6 ITMS-91053 절차로만 대응). macOS archive 시 privacy report 에서 누락 경고 여부 확인.

## 부록 B. macOS 게이트 (이 세션: Linux — 실행 불가 명시)

```text
MACOS_AVAILABLE: NO (uname: Linux)
IOS_NO_CODESIGN_BUILD: BLOCKED_MACOS
IOS_PRIVACY_REPORT: BLOCKED_MACOS
IOS_SIMULATOR_RUNTIME: NOT_RUN_DEVICE
IOS_WEB_LINK_RUNTIME: NOT_RUN_DEVICE
IOS_MEDIA_PLUGIN_SMOKE: NOT_RUN_DEVICE
```

macOS 확보 시 실행 절차·판정 기준은 런북 §5·§9 그대로(clean clone → analyze/test →
no-codesign build → 산출물 검사 → archive privacy report → 시뮬레이터 스모크).

## 부록 C. GitHub CI

- flutter-ci(`analyze · test · appbundle`)가 PR #43 head(`93def1a`)에서 **자동 실행됨**
  (check run 등록 확인 — combined status contexts 는 이 저장소가 사용하지 않아 0이 정상).
- 게이트: analyze(에러·경고 0) + test 필수 그린. appbundle 은 파이프라인 확인용(비게이트).
- 결과는 PR 갱신 시점 플래그로 기록한다.
