# Google Play 심사 통과 대비 — 리스크 분석 + 디벨롭 계획안

> 작성일: 2026-07-02 (2026-07-03 노트북 로컬 작업 델타 반영) · 대상: `ssambership_app` v0.1.0+1 (pubspec.yaml:4)
> 관점: 구글플레이 심사관 시선으로 리포지토리를 점검하여, 한 번에 통과를 어렵게 만드는 요소를 유형별로 분석하고 수정방안·로드맵을 제시한다.
> 이 문서는 분석+계획이며, 코드 수정은 아래 Phase A~D로 진행한다.
>
> ⚠️ **분석 기준 시점**: 본문 P0/P1 분석은 원격(origin) 코드 기준이다. 노트북 로컬(미푸시, origin 대비 ahead 6+)의 작업 — 클라우드 전환·디자인 토큰 통일·IQ 병합·웹링크 8경로 배선(baseUrl 주입) — 이 심사 지형을 바꾸므로 하단 **델타 섹션**을 함께 볼 것. 특히 **P0-3은 로컬 작업으로 위반이 '설계'에서 '실동작'으로 활성화**됐다.

---

## 🧭 재기준화 (2026-07-06 · master `3792858` 기준) — 이 표가 현행 정본

> 아래 원문(P0/P1 분석·요약·로드맵)은 **2026-07-02 origin 기준**의 분석 기록으로 보존한다. 이후 약 30커밋(웹링크 배선 `4a87639` · 탈퇴 진입 `ac9a4d7` · 사용자 차단 `d0032a2` · 가격표시 제거 `5002c1d` · 아이콘 `9cda0b5` · PR #12~#15)이 반영된 **현재 실태는 이 절이 정본**이다. 원문과 판정이 다르면 이 절이 우선한다.

### 재판정 총괄

| 항목 | 2026-07-02 판정 | **재판정** | 핵심 근거 (master) | 잔존 작업 · 크기 |
|---|---|---|---|---|
| P0-1 계정 삭제 | 🔴 전무 | 🔶 **부분해소** | 인앱 진입 `settings_section.dart:113-117` '회원 탈퇴' → `openAccountDeleteWeb` → `/account/delete`(운영 도메인) | 웹 삭제 페이지+Edge Function(웹 레포 소유) **중** · Play Console 삭제 URL 등록 **소** · (선택) 인앱 확인 다이얼로그 **소** |
| P0-2 약관·개인정보 | 🔴 스텁 | ✅ **해소(앱측)** | `settings_section.dart:88,93` `openTermsWeb`/`openPrivacyWeb` + `support_section.dart:30,35` 지원/리뷰 — "준비 중" 스텁 제거, 운영 도메인으로 실제 열림 | 웹 페이지 법적 문안 게시 확인 + 콘솔 방침 URL 등록(앱 밖) **소** |
| P0-3 외부 결제 유도 | 🔴 설계 위반 | ⚖️ **정책 판단 필요** | 하단 '현재 노출면' 참고 — 순수 구매 진입점 0(死배선), 관리 링크 2개만 잔존, IQ 작성 스토어 빌드 OFF | 정책 확정 후 관리 링크 2개 유지/제거 결정 · 死헬퍼 정리 **소** |
| P0-4 죽은 기능 | 🔴 다수 | 🔶 **부분해소(잔존 2건)** | ③반응 초기 로드 해소(`shortform_detail_screen.dart:47-72`) · ④결제·약관 버튼 해소(8경로 실배선). **잔존**: ①회원가입 스텁(`login_screen.dart:72` "(링크 준비 중)", `signupPath` 부재) ②숏폼 재생 아이콘(장식뿐, `thumbnail_view.dart:29-32`, video_player 미도입) | ① 가입 URL 배선 또는 버튼 제거 **소** · ② `playable:false` 숨김 **소**(재생 도입은 **중**) |
| P0-5 릴리즈 서명 | 🔴 debug 키 | 🔴 **잔존** | `android/app/build.gradle.kts:32` `signingConfig = signingConfigs.getByName("debug")`, `key.properties` 부재(gitignore 준비만 완료 `:12-14`) | keystore 생성+release signingConfig 배선 — **중**(오너 키 보관 결정 포함) |
| P0-6 SDK·versionCode | 🔴 위임 | 🔴 **잔존** | `build.gradle.kts:9,22-25` 전부 `flutter.*` 위임, `pubspec.yaml:4` `0.1.0+1` | targetSdk 등 명시 고정 + versionCode 정책 — **소** |
| P1-1 아이콘·라벨 | 🟠 기본값 | 🔶 **부분해소** | 아이콘 ✅ 브랜드 교체(`9cda0b5`, mipmap 전 해상도 + `pubspec.yaml:41-46`). 라벨 🔴 `AndroidManifest.xml:3` 여전히 `ssambership_app` | label='쌤버십' 1줄 — **소** (adaptive icon 은 선택) |
| P1-2 사용자 차단 | 🟠 없음 | ✅ **해소** | `d0032a2` — `user_blocks_repository.dart` + 피드 필터(`community_read_repository.dart:28-32`, 3개 읽기 경로) + 차단 액션(`block_author_action.dart`) + 관리 화면(`blocked_users_screen.dart`, settings:109 진입) | 운영 프로세스 문서(`UGC_MODERATION_PROCESS.md`) 작성만 — **소** |
| P1-3 심사관 로그인 | 🟠 불가 | 🔴 **잔존** | 인앱 가입 없음(설계) + 가입 링크 스텁(P0-4①) + 게스트는 커뮤니티·멘토찾기만(`entry_guard.dart:25`) | Play Console App access 테스트 계정(학생·멘토) 등록 — **소**(콘솔 작업) |
| P1-4 INTERNET 권한 | 🟠 release 누락 | 🔴 **잔존 (치명)** | `main/AndroidManifest.xml` 에 `uses-permission INTERNET` 부재 — debug/profile 에만(`:6`). release 빌드 = 전 기능 네트워크 마비 | main 매니페스트 1줄 — **극소** |
| P1-5 Data safety | 🟠 자료 없음 | 🔴 **잔존** | `docs/DATA_SAFETY_FORM.md` 부재. 신규 기능(차단·탈퇴 진입)은 수집 항목 추가 없음 | 폼 문서 작성 — **중** |

### ✅ 2026-07-06 스토어 트랙 배치 처리 결과 (`fix/store-track-p0`)

위 재판정의 앱 저장소 잔존분을 일괄 처리했다. **총괄표의 판정은 아래가 최신.**

| 항목 | 처리 | 근거 |
|---|---|---|
| P1-4 INTERNET | ✅ **해소** | main 매니페스트에 `uses-permission INTERNET` 추가 |
| P0-6 SDK·versionCode | ✅ **해소** | compileSdk·targetSdk **36**(Play 신규 앱 요건: 2026-08-31부터 API 36) · minSdk 24 명시 고정. versionCode 는 pubspec `+N` 유래 + 증가 규약(HANDOFF §3-1-B) |
| P1-1 라벨 | ✅ **해소** | `@string/app_name` = '쌤버십' (아이콘은 기해소) |
| P0-5 릴리즈 서명 | 🔶 **뼈대 완료 / 키 생성 = 사람** | key.properties 조건 로딩 + debug 폴백(빌드 불파괴), example 템플릿 커밋. 키 생성·Play App Signing 은 아래 '사람이 해야 하는 것' §1 |
| P0-3 (옵션1 확정) | ✅ **이행** | '구독 관리 (웹)' 링크 스토어 빌드 숨김(`kSubscriptionManageLinkEnabled`, dart-define 가역) + off 시 안내 카드 대체. 정산 관리 링크는 유지(지급 관리 — 정책 대상 아님) |
| P0-4① 가입 스텁 | ✅ **해소** | 확정 가입 경로 부재 → 죽은 어포던스 제거, 순수 안내 문구로(경로 확정 시 signupPath 승격) |
| P0-4② 숏폼 재생 | ✅ **해소** | 재생 아이콘 오버레이 제거(썸네일로 정리). 재생 도입은 백로그(video_player 도입 시 복원) |
| P0-1 앱측 잔여 | ✅ **해소** | 탈퇴 확인 다이얼로그(되돌릴 수 없음 고지 + 취소/계속) 후 웹 열기 |

## 👤 사람이 해야 하는 것 (코드 밖 — 스토어 제출 전 필수)

1. **릴리즈 키**: 위 '릴리즈 키 생성 절차' 섹션대로 keystore 생성(keytool) → `android/key.properties` 작성 → 첫 AAB 업로드 시 **Play App Signing 등록**. ★ 키·비밀번호는 레포·클라우드 세션·채팅에 절대 반입 금지.
2. **Play Console 등록 3종**: ① **Data safety 폼**(P1-5 — 수집 항목표 초안은 원문 P1-5 절) ② **계정 삭제 URL** 기재(P0-1 웹측 — `https://ssambership-web.vercel.app/account/delete`) ③ **App access 테스트 계정**(P1-3 — 학생·멘토 각 1개, 계정 생성은 코드 밖 작업. 요건: 로그인 가능 + 구독·질문 데이터 시드).
3. **웹 탈퇴 페이지**(웹·앱 통합 검토 묶음): `/account/delete` 실페이지 + delete-account Edge Function(auth.users 삭제 + 데이터 정리) — 웹 레포 소유. 약관(`/legal/terms`)·개인정보(`/legal/privacy`) 페이지에 법적 문안 게시 확인 포함.

---

### ⚖️ P0-3 · 현재 결제성 노출면 (정책 판단용 — 자의 판정 금지)

스토어 빌드(주입 없음 = `IQ_CREATE_ENABLED` off) 기준:

| 노출면 | 위치 | 성격 |
|---|---|---|
| "구독 관리 (웹)" 버튼 | `student_subscription_section.dart:78` → `/subscriptions` | 기구독자의 취소·관리(구매 유도 아님) — **판단 대상 1** |
| "정산 관리 (웹)" 버튼 | `mentor_dashboard_section.dart:77` → `/mentor/payouts` | 멘토 출금 관리(소비자 결제 아님) — **판단 대상 2** |
| `openSubscribeWeb`/`openRechargeWeb` | `web_bridge_actions.dart` — **프로덕션 호출부 0건**(테스트만) | 死배선. 실수 재배선 방지 위해 삭제 권고 |
| CommerceNoticeCard 4곳 | question_room:188 · question_list:174 · mentor_detail:149 · cash_section:51 | 비상호작용 안내('구독 사용자 전용이에요' 등, 웹 언급 없음, `kInAppPaymentSteeringEnabled=false`) |
| 캐시 잔액·정산액 표시 | `cash_section.dart:31-35`('조회만' 배지) · `mentor_dashboard_section.dart:58-63` | 조회 전용 |
| IQ 목록·상세·답변 확인 | `kIndividualQuestionEnabled=true` 상시 | 조회형(소비 아님) |
| (OFF 화면 내부) IQ 작성 화면의 금액·'예치' 문구 | `iq_create_screen.dart:122,263-264,292` | 스토어 빌드 미도달. on 전환 게이트 시 재검토 항목(하단 릴리즈 게이트 체크리스트에 기존재) |

### 🚀 스토어 제출 트랙 백로그 (권장 순서 — 기능 무관·1줄짜리 우선)

| # | 작업 | 항목 | 크기 | 비고 |
|---|---|---|---|---|
| 1 | main 매니페스트에 INTERNET 권한 1줄 | P1-4 | 극소 | 없으면 release 전면 마비 — 최우선 |
| 2 | targetSdk·compileSdk·minSdk·versionCode 명시 고정 | P0-6 | 소 | 기능 무영향 |
| 3 | `android:label="쌤버십"` | P1-1 | 소 | 기능 무영향 |
| 4 | 릴리즈 keystore 생성 + signingConfig 배선 | P0-5 | 중 | **오너 작업 포함**(키 생성·보관 — 레포에 키 커밋 금지) |
| 5 | 회원가입 링크: `signupPath` 배선 또는 버튼 제거 | P0-4① | 소 | 웹 가입 URL 확정 필요 |
| 6 | 숏폼 재생 아이콘 숨김(`playable:false`) | P0-4② | 소 | video_player 도입(중)은 출시 후 선택 |
| 7 | 웹: `/account/delete` 페이지 + delete-account Edge Function | P0-1 | 중 | **웹 레포 소유** — 앱 밖 |
| 8 | `docs/DATA_SAFETY_FORM.md` 작성 | P1-5 | 중 | 수집 항목표는 원문 P1-5 에 초안 존재 |
| 9 | `docs/UGC_MODERATION_PROCESS.md` 작성 | P1-2 | 소 | 코드 완료, 문서만 |
| 10 | Play Console: 테스트 계정·방침 URL·삭제 URL 등록 | P1-3·P0-1·P0-2 | 소 | 콘솔 작업 |
| ⚖️ | 구독·정산 '관리' 링크 2개 유지/제거 + 死헬퍼 정리 | P0-3 | 소 | **정책 판단 선행** — 한국 대체결제 신청 여부 포함 |

**요약**: 2026-07-02 "통과 가능성 0% (P0 6건)" → 현재 앱 저장소 잔존은 **빌드 설정 2건(P0-5·P0-6) + 죽은 UI 2건(P0-4①②) + 매니페스트 2건(P1-1 라벨·P1-4 INTERNET)** 이 전부이고 모두 소~중 공수다. 큰 덩어리는 앱 밖(웹 삭제 페이지, 콘솔 등록, 정책 판단)에 있다.

---

## 요약 — 현재 상태 진단 (2026-07-02 기준 · 스테일 — 위 재기준화 절이 정본)

**현재 상태로 제출 시 통과 가능성: 사실상 0% (P0 블로커 6건).**

- 기술적으로 **업로드 자체가 불가**하다(release가 debug 키 서명).
- 업로드가 되더라도 **정책 리젝이 확실**하다: 계정 삭제 수단 없음, 개인정보처리방침 미접근, 디지털 구독의 외부 결제 유도 설계, "보이지만 안 되는" 죽은 기능 다수.
- 반면 앱의 뼈대는 심사에 유리하다: 위험 권한 0개, 하드코딩 시크릿 없음, WebView 래퍼가 아닌 네이티브 구현, UGC 신고 기능 존재, admin 접근 차단. **P0/P1만 해소하면 통과 가능성이 높은 체질**이다.

| 등급 | 건수 | 성격 |
|------|------|------|
| 🔴 P0 | 6 | 즉시 리젝 또는 업로드 불가 |
| 🟠 P1 | 5 | 리젝/보류 가능성 높음 |
| 🟢 참고 | 6 | 긍정 요소 (감점 아님) |

---

## 🔴 P0 — 정책 블로커 (2026-07-02 기준 분석 원문 — 현행 판정은 재기준화 절)

### P0-1. 계정 삭제 기능 전무

| 항목 | 내용 |
|------|------|
| 문제 유형 | **User Data 정책** — 계정 생성을 제공하는 앱은 계정 삭제 수단을 앱 내와 웹에서 모두 제공해야 함. Data safety 폼에도 삭제 요청 URL 기재가 필수. |
| 근거 | 레포 전체에 탈퇴/`deleteAccount` 코드 없음. `lib/features/mypage/ui/sections/settings_section.dart`는 로그아웃(:100)만 제공. |
| 리젝 사유 | 계정은 만들 수 있는데(웹 가입 + 앱 로그인) 지울 수 없음 → User Data 정책 위반 + Data safety 폼 작성 불가. |

**수정방안**
- **방안 A (권장)**: 마이페이지 설정 섹션에 탈퇴 플로우(경고 → 재확인 → 처리) + Supabase Edge Function으로 삭제 처리(auth.users 삭제 + 관련 데이터 정리·익명화). 공수: 중 (Edge Function + RLS 검토 포함 2~3일).
- 방안 B: 웹에 삭제 페이지를 만들고 앱은 링크 연결 + Play Console에 삭제 URL 등록. 공수: 소 (웹 페이지 별도).
- 방안 C: A+B 병행 — 인앱 진입점 + 웹 처리 페이지. 심사·사용자 모두에게 가장 안전. 공수: 중.

### P0-2. 개인정보처리방침·이용약관 미접근

| 항목 | 내용 |
|------|------|
| 문제 유형 | **Privacy Policy 필수 요건** — 스토어 등재 시 유효한 방침 URL 필수 + 앱 내 접근 요구. |
| 근거 | `lib/features/mypage/ui/sections/settings_section.dart:83-88` — '이용약관'·'개인정보 처리방침' 두 항목 모두 탭 시 "약관·개인정보는 웹에서 확인할 수 있어요. (준비 중)" 스낵바(:112)만 표시하는 스텁. |
| 리젝 사유 | 개인정보(이메일·닉네임·학년·이미지)를 수집하면서 방침 접근 수단이 없음. |

**수정방안**
- **방안 A (권장)**: 웹(`ssambership_web`)에 정책 페이지 게시 → 앱은 `url_launcher`로 연결 + Play Console에 URL 등록. 공수: 소 (웹 페이지 준비 시 앱은 반나절).
- 방안 B: 인앱 정적 화면으로 전문 내장. 공수: 소~중 (개정 시마다 앱 업데이트 필요한 단점).
- 방안 C: A+B — 링크 기본 + 오프라인 대비 내장 사본. 공수: 중.

### P0-3. 디지털 구독의 외부 결제 유도 설계

| 항목 | 내용 |
|------|------|
| 문제 유형 | **Payments 정책** — 디지털 재화·구독은 Google Play Billing 의무, 외부 결제로의 유도(스티어링) 금지. |
| 근거 | `lib/core/web_bridge/web_bridge_actions.dart` — 구독/캐시충전/빌링 버튼이 외부 브라우저의 웹 결제 페이지를 열도록 설계됨(`openSubscribeWeb`, `openRechargeWeb` 등). 현재는 `web_bridge_config.dart`의 `baseUrl = ''` 라 죽은 버튼이지만, 설계 의도 자체가 심사 대상. |
| 리젝 사유 | 디지털 구독 상품의 결제를 앱 밖(웹 토스페이먼츠)으로 유도 → Play Billing 우회. 한국은 대체결제 허용 국가지만 **신청·승인 절차와 병행 제공 요건**이 있어 무단 외부 유도는 동일하게 위반. |

**수정방안**
- **방안 A (권장, v0.1)**: 결제 진입점 제거·조회 전용화 — 구독 상태/캐시 잔액은 보여주되, 버튼·링크·가격 유도 없이 "웹에서 구독을 관리할 수 있어요" 수준의 **안내 문구만** 표시(링크 없음). 공수: 소 (1일).
- 방안 B: Google Play Billing(`in_app_purchase`) 도입 — 캐시 상품을 인앱 상품으로 등록. 공수: 대 (서버 영수증 검증 + 수수료 구조 재설계 필요).
- 방안 C: 한국 **대체결제(Alternative Billing) 프로그램** 신청 후 승인 범위 내에서 병행 제공. 공수: 대 (비즈니스 절차 + 구현, 승인까지 리드타임).

> 개별질문 등 **기충전 캐시를 앱 내에서 디지털 재화에 소비**하는 기능도 동일 정책의 검토 대상이다. 릴리즈 빌드에서 해당 진입점을 끌 수 있는 feature flag를 마련해 정책 결정 전까지 토글 가능하게 한다.

### P0-4. 죽은 기능 다수 — Broken Functionality / 최소 기능 정책

| 항목 | 내용 |
|------|------|
| 문제 유형 | **Broken Functionality·Minimum Functionality 정책** — 보이는데 동작하지 않는 UI는 리젝 사유. |
| 근거 | ① 회원가입 링크 스텁: `lib/features/auth/login_screen.dart:72-76` `_openWebSignUp()` → "(링크 준비 중)" 스낵바 ② 숏폼 재생 버튼이 재생 안 됨(비디오 플레이어 미구현) ③ 좋아요 초기상태 미로딩 ④ 결제·약관 버튼 스텁 — `docs/APP_FEATURE_STATUS.md`에 자체 인정된 목록 존재. |
| 리젝 사유 | 심사관이 몇 번만 탭해도 "준비 중" 스낵바를 연달아 만나게 됨. |

**수정방안**
- **방안 A (권장)**: 미구현 UI 숨김/제거 — 숏폼 재생 아이콘 제거(또는 상세를 이미지 뷰로 전환), 스텁 버튼 삭제, "준비 중" 노출 최소화. 공수: 소 (1~2일).
- 방안 B: 최소 구현 — `video_player` 도입, 가입은 인앱 가입 구현 또는 웹 가입 URL 연결. 공수: 중.
- 방안 C: 기능 플래그로 릴리즈 빌드에서만 비노출(디버그에선 유지). 공수: 소.

### P0-5. release가 debug 키로 서명

| 항목 | 내용 |
|------|------|
| 문제 유형 | **기술 블로커** — debug 서명 AAB는 Play Console 업로드 자체가 거부됨. |
| 근거 | `android/app/build.gradle.kts:32` — `signingConfig = signingConfigs.getByName("debug")` (":30 TODO 주석으로 자체 인지"). |

**수정방안**
- **방안 A (권장)**: upload keystore 생성 → `key.properties` 참조 서명 config 추가(파일은 gitignore) → Play App Signing 등록. 공수: 소 (반나절).
- 방안 B: CI 시크릿 주입 서명 — 로컬 키파일 없이 CI에서 base64 시크릿으로 서명. 공수: 소~중 (CI 구성 포함).

### P0-6. targetSdk/minSdk/versionCode 미고정

| 항목 | 내용 |
|------|------|
| 문제 유형 | **타깃 API 요건** — Play는 최신 안드로이드 타깃 API(현행 35) 이상을 요구. Flutter SDK 기본값 위임은 로컬 SDK 버전에 따라 달라져 미충족 위험. |
| 근거 | `android/app/build.gradle.kts:22-25` — `minSdk`/`targetSdk`/`versionCode`/`versionName` 모두 `flutter.*` 위임. |

**수정방안**
- **방안 A (권장)**: `build.gradle.kts`에 `targetSdk = 35` 등 명시 고정(+ minSdk 결정·문서화). 공수: 소 (1시간 + 회귀 확인).
- 방안 B: Flutter SDK 버전 핀 + CI에서 산출 AAB의 targetSdk 검증 스텝. 공수: 소~중.

---

## 🟠 P1 — 리젝/보류 가능성 높음 (2026-07-02 기준 분석 원문 — 현행 판정은 재기준화 절)

### P1-1. 기본 Flutter 런처 아이콘 + `android:label="ssambership_app"`
- 유형: 스토어 품질/브랜딩 (사칭·저품질 인상).
- 근거: `android/app/src/main/AndroidManifest.xml:3` — label이 패키지명 그대로. 런처 아이콘은 Flutter 기본.
- 방안 A(권장): `flutter_launcher_icons`로 브랜드 아이콘 + adaptive icon 일괄 생성. 방안 B: 수동 mipmap 교체. **공통**: label을 `쌤버십`으로 교체. 공수: 소.

### P1-2. UGC 신고는 있으나 사용자 차단 없음
- 유형: **UGC 정책** — 신고와 차단(또는 뮤트) 수단을 모두 기대.
- 근거: 신고는 구현됨(`lib/features/community/ui/widgets/report_sheet.dart` → `content_reports`). 차단 기능 없음.
- 방안 A: `user_blocks` 테이블 + 피드 조회 필터 (웹 레포 SQL 마이그레이션 필요 — 스키마는 웹 레포 소유 원칙). 방안 B: 클라이언트 로컬 mute. 방안 C(v1 방어): 신고 + 운영 삭제 프로세스 문서화로 대응. 공수: A 중 / B 소 / C 소.

### P1-3. 심사관이 로그인 불가
- 유형: 심사 진행 불가 → 보류·리젝.
- 근거: 인앱 가입 없음 + 가입 링크 스텁(P0-4 ①). 게스트 모드는 있으나 핵심 기능(질문방)은 로그인 필요.
- 방안 A(필수): Play Console **App access**에 테스트 계정(학생·멘토 각 1개) 제공. 방안 B: 게스트 둘러보기 범위 확대. 공수: A 소 / B 중.

### P1-4. INTERNET 권한이 debug/profile 매니페스트에만 존재
- 근거: `android/app/src/debug/AndroidManifest.xml:6`, `android/app/src/profile/AndroidManifest.xml:6`에만 선언, `main/AndroidManifest.xml`에는 없음 → release 빌드가 네트워크 불가로 **전 기능 마비**(Broken Functionality로 직결).
- 방안(단일): main 매니페스트에 `<uses-permission android:name="android.permission.INTERNET"/>` 1줄 추가. 공수: 극소.

### P1-5. Data safety 폼 대비 자료 없음
- 유형: Data safety 미제출/부실 기재 시 등재 불가 또는 사후 제재.
- 수집 항목 정리(현행 코드 기준): 이메일(로그인), 이름·닉네임·학년(프로필), UGC(질문/게시글/댓글), 이미지(질문 첨부·필기), 기기 정보(푸시 도입 시 토큰). 제3자 공유 없음, 판매 없음, 전송 암호화(HTTPS), 삭제 수단은 P0-1 완료 후 URL 기재.
- 방안: 위 표를 `docs/DATA_SAFETY_FORM.md`로 문서화 + 폼 항목별 응답 가이드 작성. 공수: 소.

---

## 🟢 참고 — 긍정 요소 (심사에 유리)

1. 하드코딩 시크릿 없음 — Supabase 키는 `.env` 주입(`lib/core/config/app_config.dart`), `.env` 미커밋.
2. dev 도구 release 제외 — `lib/features/dev/dev_flags.dart`로 릴리즈 빌드에서 차단.
3. 위험 권한 0개 — 카메라/위치/연락처 등 미사용 (이미지는 photo picker 경유).
4. WebView 래퍼 아님 — 전 화면 네이티브 Flutter 구현.
5. UGC 신고 기능 존재 — `content_reports` 연동 완료.
6. admin 앱 접근 차단 — 역할 게이트에서 관리자 로그인 차단(`lib/core/auth/`).

---

## 디벨롭 로드맵

### Phase A — 정책 블로커 해소 (P0-1~4)

| 작업 | 대상 파일 |
|------|-----------|
| 약관/방침 웹 링크 연결 (P0-2 방안 A) | `lib/features/mypage/ui/sections/settings_section.dart` (:83-88 스텁 교체), `lib/core/web_bridge/web_bridge_config.dart` (정책 URL 상수) |
| 계정 삭제 플로우 (P0-1 방안 C) | `settings_section.dart` (진입점), 신규 `lib/features/mypage/ui/screens/account_delete_screen.dart`, Supabase Edge Function `delete-account` (웹 레포 `supabase/functions/` — 스키마·함수는 웹 레포 소유) |
| 결제 진입점 조회 전용화 (P0-3 방안 A) | `lib/core/web_bridge/web_bridge_actions.dart`, `lib/features/mypage/` 구독/캐시 카드 (버튼 제거 → 안내 문구), `lib/features/mentors/` 상세의 구독 버튼 |
| 죽은 UI 정리 (P0-4 방안 A) | `lib/features/auth/login_screen.dart` (:72-76, :159 가입 스텁), 숏폼 재생 아이콘(`lib/features/community/ui/`), 좋아요 초기상태, `docs/APP_FEATURE_STATUS.md` 기준 전수 점검 |

### Phase B — 빌드/기술 (P0-5·6, P1-1·4)

| 작업 | 대상 파일 |
|------|-----------|
| 릴리즈 서명 config | `android/app/build.gradle.kts` (:26-34), 신규 `android/key.properties`(gitignore), `android/.gitignore` |
| targetSdk 35 등 명시 고정 | `android/app/build.gradle.kts` (:22-25) |
| INTERNET 권한 | `android/app/src/main/AndroidManifest.xml` |
| 앱명·아이콘 | `android/app/src/main/AndroidManifest.xml` (:3 label), `pubspec.yaml`(flutter_launcher_icons), `android/app/src/main/res/mipmap-*` |

### Phase C — UGC 보강 (P1-2)

| 작업 | 대상 파일 |
|------|-----------|
| 사용자 차단 | 웹 레포 `supabase/sql/NNN_user_blocks.sql`(테이블+RLS), 앱 `lib/features/community/data/`(차단 필터), 게시글/댓글 액션 시트에 차단 항목 |
| 운영 프로세스 문서화 | `docs/UGC_MODERATION_PROCESS.md` (신고 접수→검수→조치 SLA) |

### Phase D — 출시 준비 (P1-3·5)

| 작업 | 산출물 |
|------|-----------|
| Data safety 폼 | `docs/DATA_SAFETY_FORM.md` (수집 항목표 + 폼 응답 가이드) |
| 테스트 계정 | Play Console App access 등록용 학생·멘토 계정 (스테이징 데이터 시드 포함) |
| 스토어 등록정보 | 스크린샷·그래픽·설명문 체크리스트, 방침 URL·삭제 URL 등록 확인 |

**권장 순서**: B(서명·권한은 모든 테스트의 전제) → A → D → C. 단 P1-4(1줄)와 P0-6은 즉시 처리 가능.

---

## 델타 — 노트북 로컬(미푸시) 작업이 심사 지형에 미친 영향

2026-07-03 기준, 노트북 로컬(origin 대비 ahead 6+, 일부 미커밋)에서 진행된 작업의 심사 관점 반영. **Phase 0 = 이 작업의 커밋·푸시가 모든 Phase의 선행 조건**이다.

| 로컬 작업 | 심사 영향 |
|------|------|
| `.env` 클라우드 전환 + 스키마 정합 4파일 (54f1e89) | ✅ 앱이 실제로 "동작"하게 됨 — Minimum Functionality의 대전제 충족 |
| 디자인 토큰 통일·Pretendard·테마 seed 중립화 (2d735e3 외) | ✅ 품질 인상 개선 (P1-1 아이콘·앱명은 별개로 잔존, 로그인 브랜드 심볼을 아이콘 소스로 재사용 가능) |
| **웹링크 8경로 배선 — baseUrl `https://ssambership-web.vercel.app` 주입** (미커밋) | ✅ 약관 `/legal/terms`·개인정보 `/legal/privacy`·고객지원·리뷰 배선 → **P0-2 해소** (남은 일: 페이지에 실제 법적 문안 게시 확인 + Play Console URL 기재) / ⚠️ **구독·충전·결제관리(`/subscriptions`) 활성화 = P0-3 위반이 '설계'에서 '실동작'으로 전환 → 푸시 전 결제성 경로만 방안 A(조회 전용화)로 되돌릴 것.** 비결제 링크는 유지 무방 |
| IQ(개별질문) 병합 (09b62f8, 스위치 2개 ON) | 🔶 출시 전 `kIndividualQuestionCreateEnabled` OFF 시 진입점이 완전히 숨겨지는지 확인(P0-4 재발 방지) + 캐시 소비형 디지털 재화라 P0-3 검토 대상 + Data safety 수집 항목 반영 |
| 클라우드 `users.notification_enabled` 컬럼 추가 (DB 직접 적용) | 🔶 Data safety 폼 기재 항목 추가. git으로 롤백 불가한 실DB 변경이므로 웹 레포 마이그레이션 SQL로 정본화 필요 |
| 프로필 역할분기·마이페이지 탭 배선·연결노트 버튼 (미커밋) | ✅ 죽은 UI 감소 — P0-4 부분 해소 (잔여: 회원가입 링크 스텁, 숏폼 재생·좋아요 초기상태) |
| 전부 미푸시 | ⚠️ 원격 기준 빌드는 여전히 P0 전건 해당 — **Phase 0: 커밋·푸시 먼저** |

### Phase 0 — 로컬 작업 정리 (선행 필수)
1. 미커밋 3묶음(테마 seed / 웹링크 / 역할분기) 커밋 → origin/master 푸시.
2. **푸시 전 P0-3 결정 반영**: 구독·충전·결제관리 진입점을 조회 전용으로 전환(방안 A) — 위반 상태의 스토어 빌드 생성을 원천 차단. 약관·개인정보·지원·리뷰 등 비결제 링크는 유지.
3. IQ 작성 스위치 출시 정책 확정 — OFF 시 진입점 완전 숨김 검증.

---

## 부록 — 근거 파일 인덱스

| 인용 | 확인 내용 |
|------|-----------|
| `lib/features/mypage/ui/sections/settings_section.dart:83-88, :100, :112` | 약관/방침 항목·로그아웃·"준비 중" 스낵바 |
| `lib/features/auth/login_screen.dart:72-76, :159` | `_openWebSignUp()` 스텁과 호출 버튼 |
| `lib/core/web_bridge/web_bridge_config.dart` / `web_bridge_actions.dart` | `baseUrl = ''`, 외부 결제 유도 설계 |
| `android/app/build.gradle.kts:22-25, :32` | flutter.* 위임, debug 서명 |
| `android/app/src/main/AndroidManifest.xml:3` | `android:label="ssambership_app"`, INTERNET 부재 |
| `android/app/src/{debug,profile}/AndroidManifest.xml:6` | INTERNET이 dev 매니페스트에만 |
| `lib/features/community/ui/widgets/report_sheet.dart` | UGC 신고 구현 |
| `lib/features/dev/dev_flags.dart` | dev 도구 release 차단 |
| `docs/APP_FEATURE_STATUS.md` | 기능별 동작/스텁 자체 감사 |
| `pubspec.yaml:4` | `version: 0.1.0+1` |

---

## 🧭 의사결정 기록 (2026-07 확정)

| # | 결정 | 내용 | 코드 반영 |
|---|---|---|---|
| D-1 | **QA-01 = A안** | 첫 스토어 제출 빌드는 **개별질문 '작성(캐시 예치)' 진입점 off 가 기본**. dev·내부 테스트는 컴파일 타임 주입으로 on. 조회·상세·답변 확인(`kIndividualQuestionEnabled`)은 소비가 아니므로 항상 유지 | `iq_flags.dart` — `kIndividualQuestionCreateEnabled = bool.fromEnvironment('IQ_CREATE_ENABLED', defaultValue: false)` |
| D-2 | **QA-06 = 도메인 확정** | 현행 `https://ssambership-web.vercel.app` 이 **출시용 운영 웹 도메인으로 확정**. P0-2(약관·개인정보 접근)의 앱 측 배선은 이 도메인으로 완결. 스테이징·로컬 웹 테스트는 주입으로 오버라이드 | `web_bridge_config.dart` — `baseUrl = String.fromEnvironment('WEB_BASE_URL', defaultValue: '…vercel.app')` |

**dart-define 사용법**

```bash
# 내부 테스트: IQ 작성 켜기
flutter run --dart-define=IQ_CREATE_ENABLED=true

# 로컬/스테이징 웹으로 브릿지 오버라이드
flutter run --dart-define=WEB_BASE_URL=http://127.0.0.1:3000

# 릴리즈(스토어 제출): 주입 없음 = IQ 작성 off + 운영 도메인
flutter build appbundle
```

## 🔑 릴리즈 키 생성 절차 (사람 작업 — 코드/세션에 키 절대 반입 금지)

앱 코드는 `android/key.properties` 가 **있으면 release(업로드) 키로 서명**한다. **없으면 release 산출물 빌드는 즉시 실패**한다(build.gradle.kts — debug 서명 AAB 의 오업로드를 원천 차단). CI 파이프라인 검증처럼 debug 폴백이 의도된 경우에만 `-PallowInsecureSigning=true`(env `ORG_GRADLE_PROJECT_allowInsecureSigning=true`) 로 빌드하며 그 산출물은 제출 불가다. 스토어 업로드 전 아래 절차로 키를 만들고 채운다.

1. **keystore 생성** (오너 로컬 PC에서 — 클라우드 세션·레포에서 실행 금지):
   ```bash
   keytool -genkey -v -keystore %USERPROFILE%\upload-keystore.jks ^
     -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   # macOS/Linux: -keystore ~/upload-keystore.jks (나머지 동일)
   ```
   묻는 값: keystore 비밀번호(2회) → 이름/조직/지역(스토어 표기와 무관) → key 비밀번호(Enter=keystore와 동일).
2. **key.properties 작성**: `android/key.properties.example` 을 복사해 `android/key.properties` 로 저장하고 실제 값 기입. (gitignore 가 커밋을 차단하지만, 그래도 `git status` 로 미추적 확인 습관화.)
3. **보관 수칙**: keystore(.jks)와 비밀번호는 ① 레포·클라우드 세션·채팅에 절대 올리지 않는다 ② 오프라인 백업 2곳(예: 암호관리자 + 외장매체) ③ 분실 시 Play App Signing 미등록 상태면 앱 업데이트 영구 불가.
4. **Play App Signing 등록(권장)**: Play Console → 설정 → 앱 서명 → 위 keystore 를 **업로드 키**로 등록(구글이 앱 서명 키를 별도 보관 — 업로드 키 분실 시 재발급 가능해짐). 첫 AAB 업로드 시 자동 안내 흐름을 따라도 된다.
5. **검증**: `flutter build appbundle --release` 후 `keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab` 로 서명 주체가 debug 가 아닌지 확인.

---

## 🚦 릴리즈 게이트 — IQ 작성 on 전환 조건

`IQ_CREATE_ENABLED` 를 기본 true 로 되돌리는(또는 스토어 빌드에 주입하는) 조건. **전부 충족 전에는 스토어 제출 빌드에서 off 유지.**

- [ ] 본 문서 P0-3(Payments 정책)의 최종 판단 완료 — "기충전 캐시의 앱 내 디지털 재화 소비"가 (a) Play Billing 도입, (b) 한국 대체결제 승인, (c) 정책 비대상 확인 중 하나로 해소
- [ ] off 빌드에서 작성 진입점 3곳(학생 목록 EmptyState 액션·'새 개별질문' 버튼·멘토 상세 '개별질문 하기') 완전 숨김 확인 — `test/individual_question/iq_create_flag_test.dart` 가 플래그 연동을 상시 검증
- [ ] Data safety 폼에 IQ 관련 수집 항목 반영(Phase D)
- [ ] on 전환 시 예치 확인문(`iq_create_screen.dart` '…캐시가 안전 보관(예치)돼요')의 단가 노출 여부 재검토(QA_REPORT QA-01 참고)
