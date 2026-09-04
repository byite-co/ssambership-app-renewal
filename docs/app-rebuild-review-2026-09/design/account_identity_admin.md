# Phase 2 설계 — 계정·본인인증·온보딩 + 관리자 콘솔 포함 여부

- 대상: 웹 `/home/user/ssambership_web`(Next.js 16 · DB 정본), 앱 `/home/user/ssambership-app`(Flutter · 같은 Supabase, 브랜치 `claude/app-rebuild-feature-review-oyewr0` HEAD `635ae73`)
- 입력: Phase 1 리포트 4종(`web_account_identity_admin.md`, `web_db_surface_payment_boundary.md`, `app_architecture.md`, `app_features.md`) + 결정적 주장 코드/SQL 재확인(아래 §1-3)
- 표기: `web:경로:행` / `app:경로:행`. 코드로 판정하지 못한 것은 **(확인 필요)**. UI 디자인은 다루지 않는다.

---

## 1. 범위·전제

### 1-1 범위

| 포함 | 제외(다른 도메인·범위 밖) |
|---|---|
| 회원가입(학생/멘토 · 메타 20키 · 트리거 행 생성 · 멘토 학생증 가입 시/사후 제출) | 결제 실행 전체(충전·구독 체결·IQ 예치·CR 홀드) — `web:docs/policy/app-web-payment-separation.md` §1·§3 |
| 로그인(역할 전용 카드 · 이메일 인증 정책) · 비밀번호 재설정 · 로그아웃 | 멘토 프로필 편집 F7·요금제 F8·정산계좌 F13(멘토 콘솔 도메인) |
| NICE 본인인증 self/guardian · 보호자 동의 · IDENTITY_GATE · `IDENTITY_REQUIRED` | 학교·전공 증빙(`mentor_school_verifications`) 심사 규칙(멘토 콘솔 도메인 — 제출 진입만 §2 에서 언급) |
| 온보딩 상태 ↔ `AccessState` · 계정 상태 판정 정합 | 아바타 업로드(웹 전용 결정 `app:docs/RELEASE_SCOPE_DECISIONS_2026-07.md:10-12`) |
| 탈퇴 정합(비밀번호 재인증 · 사전조건 5종 · 30일 취소 문구) | 커뮤니티·질문방·알림 도메인 자체(알림 **설정**만 포함) |
| 설정 항목(마케팅 동의 · 알림 설정 · 차단 관리 · 약관/개인정보) | 소셜 로그인(웹·앱 모두 0건 → §7 (iv)) |
| **관리자 콘솔 앱 포함 여부 결정**(35 페이지 인벤토리 기준) | — |

### 1-2 설계 전제(불변)

1. **DB 변경은 웹 저장소 pack 에만** — `app:supabase/SCHEMA_SOURCE_OF_TRUTH.md`, 절차는 `web_db_surface_payment_boundary.md` §5.2(계약 → `api_app_v1` SECDEF thin wrapper + `core_private` INVOKER impl → 같은 트랜잭션 GRANT → sql/rollback/backfill 3중 사본 → `db-apply-pending`).
2. **앱이 부를 수 있는 것** = Data API 노출 스키마(`public`·`api_web_v1`·`api_app_v1`) 안의 authenticated(비로그인이면 anon) EXECUTE/SELECT 객체만. service_role 전용 객체는 앱에서 도달 불가(`web:lib/supabase/admin.ts` `server-only`).
3. `api_app_v1` 스키마는 **authenticated 만 USAGE**(service_role 없음 — `web:supabase/migrations/20260731114120_20260730112525_api_app_v1_surface.sql:85-88`). 앱 wrapper 는 `auth.uid()` 자체 도출, `p_user_id` 류 인자 금지.
4. 앱 매니페스트 테스트(`app:test/contracts/outbound_api_manifest_test.dart`)가 RPC/테이블/스키마/버킷 **집합 동일성**을 잠근다 — 새 표면은 반드시 집합 갱신과 함께.
5. 웹 결제 경계(앱 안에 결제 화면·버튼·유도 문구 0)는 이 도메인에서도 유지 — WebView allowlist 에 `/subscribe`·`/wallet/*` 를 넣지 않는다.

### 1-3 결정적 주장 재확인 결과(코드/SQL 직접 확인)

| 주장 | 판정 | 근거 |
|---|---|---|
| 가입 시 `users`·`mentor_profiles`·`verification_logs` 행은 **DB 트리거**가 만든다(클라이언트 직접 쓰기 0) | **확인** | `handle_new_auth_user()` SECURITY DEFINER — `web:supabase/migrations/20260717044250_fix_xv01_signup_admin_provisioning.sql:13-108`(users upsert `:52-79`, mentor_profiles upsert `:82-104`, verification_logs `:106-107`); 동의 원장 트리거 `handle_new_auth_user_consent_records()` `web:supabase/migrations/20260829100300_tz_fix_consent_minor_age_kst.sql:25-107` |
| `app_role` 은 `student\|mentor` 만 유효, 그 외·`admin` → `student` 폴백 | **확인** | `20260717044250:29-33` |
| `users` 의 authenticated **UPDATE/DELETE GRANT 회수**(SELECT·INSERT 유지) + 보호 컬럼 트리거 + `status` CHECK 4종 | **확인** | `web:supabase/migrations/20260803170552_20260803162257_security_identity_profile_lockdown.sql:92-93`(REVOKE), `:100-138`(`users_protected_columns_guard`), `:143-146`(CHECK `active/suspended/banned/deleted`) |
| 앱 세션 bootstrap 은 **멘토 전용 · target 1종**(`shortform_create`) | **확인** | `web:lib/appSession/appSessionBootstrapCore.ts:17-19`(target map 1키), `web:app/api/app-session/bootstrap/route.ts:110-119`(`assertAppSurfaceAccountActiveStrict` → `strictMentorRoleDecision` → `mentor_only`), `web:lib/appSession/appSurfacePaths.ts:8-25`(kinds `['shortform']`, results `['draft','published']`, error codes 5종) |
| `identity_verifications`·`nice_auth_tokens` 는 **service_role 전용**(RLS on·정책 0·anon/authenticated GRANT 0) | **확인** | `web:supabase/migrations/20260820100200_identity_verifications.sql:64-66`, `web:supabase/migrations/20260820100100_nice_auth_tokens.sql:34-36`; `users.identity_verified_at` 는 authenticated SELECT 범위(`20260820100200:80-83`, 헤더 `:15-19`) |
| `/api/identity/start`·`/return` 은 **쿠키 세션** 기반, return_url 호스트 허용목록 `ssambership.com`/`www.` | **확인** | `web:app/api/identity/start/route.ts:23-41,60-62`, `web:app/api/identity/return/route.ts:153-171`, `web:lib/http/requestOrigin.ts:10` |
| IDENTITY_GATE 는 서버 env `'true'` 일 때만 ON, DB/RPC 레벨 가드 0 | **확인** | `web:lib/identity/identityGateFlag.ts:12-24`, `web:lib/identity/identityGate.ts:6-8,30-54`; 호출부 5곳(`app/api/subscribe/checkout/route.ts:72-74`, `lib/individualQuestion/individualQuestionActions.ts:124,220`, `lib/customRequest/customRequestApplicationActions.ts:47`, `lib/customRequest/customRequestOrderActions.ts:35`) |
| 앱에 `IDENTITY_REQUIRED`·`identity_verified_at`·`signUp(`·`resetPasswordForEmail`·`signInWithOAuth` 참조 0건 | **확인** | `grep -rn` 0건(`app:lib`, `app:test`) |
| 탈퇴 취소 유예는 DB 정본 **30일**(`p_cancelable_minutes` 무시) | **확인** | `web:supabase/migrations/20260808092007_account_deletion_server_cancel_window_30d.sql:56-57,69-70,72-76`; 웹 코드 상수 `CANCELABLE_MINUTES = 30`(`web:lib/account/accountDeletionActions.ts:39`)은 무시되는 인자 |
| 마케팅 동의 RPC 는 `api_web_v1` 에만 존재하며 **웹 UI 호출 0건** | **확인** | 정의 `20260803170552…:287-330`; `grep user_marketing_consent_set_self` 가 `web:app`·`lib`·`components` 에서 0건(정의 파일 제외) — 웹도 현재 토글 UI 없음 |
| 앱 `AccessState` 5종 · `AccountStatusKind` 7종 · admin → blocked | **확인** | `app:lib/core/auth/auth_service.dart:13,22,88-112`, `app:lib/core/auth/account_status.dart:14-37,58-65,226-312` |
| 앱에 딥링크 스킴(커스텀 scheme·App Links·`CFBundleURLTypes`) 없음 | **확인** | `app:android/app/src/main/AndroidManifest.xml:28-31`(LAUNCHER 만; `:49-55` 는 `<queries>`), `app:ios/Runner/Info.plist:33-36`(`LSApplicationQueriesSchemes=https` 만) |

---

## 2. 갭 매트릭스

목표 범례: **포함** = 앱 네이티브 구현 · **웹 위임** = WebView(세션 부트스트랩) 또는 외부 브라우저 · **제외** · **오너 결정**.

| # | 웹 기능 | 웹 라우트 | 앱 현재 | 앱 목표 | 근거 |
|---|---|---|---|---|---|
| 1 | 학생 회원가입(이메일/비번·닉네임·학년·생년월일·약관 3종) | `/signup` | 없음(로그인 화면 안내문만 `app:lib/features/auth/login_screen.dart:19,148-157`) | **포함** | `auth.signUp` + 메타 20키만으로 트리거가 행 생성(§1-3). 웹 계약 §19.1 "가입 앱 ❌"(`web:docs/contracts/api_web_v1_contract_v1_1.md:2159`)는 컴패니언 시절 결정 → 오너 요구("웹 수준")로 재정의. 최종 확정은 §7 (ii) |
| 2 | 멘토 회원가입(대학·학과·과목 CSV·고교·소개) | `/signup` | 없음 | **포함** | 같은 트리거가 `mentor_profiles(verification_status='pending')`·`verification_logs` 생성(`20260717044250:82-107`) |
| 3 | 멘토 학생증 **가입 시** 첨부(세션 없이 SR 15분 창) | `/signup` → `uploadMentorStudentIdAfterSignUpAction` | 없음 | **포함(경로 변경)** | 웹 액션은 `admin.auth.admin.getUserById` + 15분 창 + `app_role=mentor` + 빈 칸만(`web:lib/auth/mentorSignupStudentIdAction.ts:20,73-96`) — 서버 액션이라 앱 도달 불가. 앱은 (a) signUp 이 세션을 돌려주면 즉시 Storage 업로드 + 신설 RPC(§3-b-2), (b) 세션 없으면(이메일 인증 ON) 첫 로그인 후 #4 경로 |
| 4 | 멘토 학생증 **사후 제출** | `/mentor/verification` | 없음(웹 전용 결정 `app:docs/RELEASE_SCOPE_DECISIONS_2026-07.md:11`) | **포함** | Storage `student-id-images` insert_own(첫 세그먼트 = uid, `web:supabase/migrations/20260701000000_pre_ledger_baseline.sql:331-337`)은 세션으로 가능. `mentor_profiles.student_id_image_url` 반영은 M11 회수로 불가(`web:lib/mentor/mentorStudentIdActions.ts:60-76` SR 사용) → **신설 RPC** 필요 |
| 5 | 멘토 학교·전공 증빙 제출 | `/mentor/verification` | 없음 | **포함(멘토 콘솔 도메인에서 확정)** | 세션 클라이언트 직접 INSERT(`web:lib/mentor/mentorSchoolVerificationActions.ts:66-70`, 정책 `msv_insert_own_pending` baseline `:10305`) → 앱 직접 가능. 심사 규칙(DB-1/2)은 멘토 콘솔 도메인 |
| 6 | 로그인(이메일/비번) — 역할 전용 카드 | `/login/{student,mentor}` | 완전(`app:lib/core/auth/auth_service.dart:304-320`) | **포함(유지)** | 웹 역할 불일치 거부(`web:components/auth/RoleLoginForm.tsx:162-181`)는 화면 분리 때문 — 앱은 로그인 후 `users.role` 분기로 동일 결과 |
| 7 | 이메일 인증(Confirm email) 정책 | Supabase Auth 설정 | `friendlyAuthError` 가 `email not confirmed` 문구만(`app:lib/shared/errors/friendly_error.dart:21`) | **오너 결정/확인** | 로컬 `enable_confirmations=false`(`web:supabase/config.toml:226`), 운영값 **(확인 필요)**. ON 이면 #3 경로·가입 완료 화면·재발송이 달라진다 |
| 8 | 비로그인 열람(게스트) | 각 공개 라우트 | 완전(`guestAllowedTabs={1,2}` `app:lib/app/entry_guard.dart:25`) | **포함(유지)** | 이 도메인에서 변경 없음 |
| 9 | 비밀번호 재설정 **메일 발송** | `/forgot-password` | 없음(제외) | **포함** | `auth.resetPasswordForEmail(email, redirectTo)` 직접 호출 가능(`web:lib/auth/passwordResetActions.ts:36-38` 와 동일 API). `redirectTo` 는 Supabase Redirect allowlist 등록값 사용 |
| 10 | **새 비밀번호 설정**(recovery 세션) | `/auth/update-password` | 없음 | **웹 위임(1차)** · 딥링크는 오너 결정 | 웹은 `updateUser({password})` 후 signOut(`web:components/auth/UpdatePasswordClient.tsx:30-59`). 앱은 딥링크 스킴이 0(§1-3)이라 recovery 세션을 받을 수 없음 → 메일 링크가 웹에서 완료 → 앱에서 재로그인. 딥링크 도입은 §7 (vi) |
| 11 | 로그아웃 | `POST /logout` | 완전(`auth_service.dart:330-342` — WebView 쿠키 정리 포함) | **포함(유지)** | — |
| 12 | 본인(self) NICE 인증 온보딩 | `/onboarding/verify` + `/api/identity/start`·`/return` | 없음 | **웹 위임(WebView · bootstrap 확장)** | 테이블·키·NICE 클라이언트 전부 서버 전용, 쿠키 세션 기반, return_url 웹 도메인(§1-3) → 네이티브 재현 불가. bootstrap 학생 허용 + 새 target 필요(§3-b-1) |
| 13 | 보호자(guardian) NICE 인증·동의 기록 | `/onboarding/guardian` | 없음 | **웹 위임(동일 WebView)** | `startIdentityVerification(kind='guardian')` 전이 규칙(`web:lib/identity/service.ts:184-208`)·`user_consent_records` upsert(`:433-455`)는 서버가 수행. 앱은 `/onboarding/verify` 진입만 하면 서버가 guardian 페이지로 redirect(`web:app/onboarding/verify/page.tsx:39-46`) |
| 14 | IDENTITY_GATE(레이아웃 redirect) | `(student)/layout.tsx:41,66,83,99`, `(mentor)/layout.tsx:17-19` | 없음 | **오너 결정** | 플래그가 웹 서버 env 라 앱이 읽을 수 없고, DB 게이트는 설계 원칙상 금지(`identityGate.ts:6-8`). 앱 자체 게이트를 두려면 플래그 전달 수단(§3-b-5)이 필요 → §7 (v) |
| 15 | `IDENTITY_REQUIRED` 403 처리(머니패스) | `/api/subscribe/checkout` 등 | 없음(0건) | **포함(매퍼 토큰 예약 · 저우선)** | 게이트 대상 4경로는 전부 결제 경로 = 앱 제외. 앱이 부르는 직접 RPC 는 게이트 밖(`identityGate.ts:6-8`). 향후 웹 API 호출이 생길 때 선두 토큰 계약(`identityGate.ts:17-20`)만 매퍼에 등록 |
| 16 | 계정 상태 판정(active/suspended/banned/deleted/삭제 진행) | `assertAccountActive`·strict 게이트 | 완전(`AccountStatusReader.resolve` fail-closed) | **포함(유지 + `deleted` 명시)** | 앱은 `status='deleted'` 문자열을 별도 처리하지 않음(`app:lib/core/auth/account_status.dart:287-311` — banned/suspended 외 active). CHECK 도입 후 `deleted` 는 auth soft-delete 로 로그인 불가라 실무 무해 **(확인 필요)** → 명시 매핑 추가 권고 |
| 17 | 탈퇴 요청·취소(saga · 잔액 동의) | `/account/delete` | 완전(self v2 RPC 4종 `app:lib/features/mypage/data/account_deletion_repository.dart:201-204,217-223,319-322`) | **포함(유지)** | DB 정본이 동일(`account_deletion_request_consented` 를 v2 self 래퍼가 `(uid,30,false,…)` 로 호출 `web:supabase/migrations/20260803170916_20260803162808_domain_contract_convergence.sql:774-775,795-796`) |
| 18 | 탈퇴 **사전조건 5종**(활성 구독/구독자 · 진행 IQ · 비터미널 CR 주문 · 분쟁 · 잔액) | `/account/delete` (SR 집계) | 없음(잔액 동의만 서버 강제) | **포함(신설 RPC)** · DB 강제 여부 오너 결정 | TS 전용 SR 집계(`web:lib/account/accountDeletionPreconditions.ts:52-54,76-187`), DB RPC 에는 없음 → `account_deletion_preconditions_self()` 신설(§3-b-4). 요청 RPC 자체에 강제할지는 §7 (vii) |
| 19 | 탈퇴 **비밀번호 재인증** + `understood` 체크 | `/account/delete` | 없음 | **포함** | 웹은 bare client `signInWithPassword` 재검증(`web:lib/account/accountDeletionActions.ts:51-68`). 앱은 별도 `SupabaseClient(persistSession:false)` 로 동일 재검증 가능(세션 교체 없음) |
| 20 | 30일 취소 문구 정합 | `/account/delete` | 서버 `cancelable_until` 표시(`app:lib/features/mypage/ui/account_delete_screen.dart:84-93,253-255`) | **포함(유지)** | 웹 문구 "30분"(`web:app/(student)/account/delete/page.tsx:92`, `AccountDeletionForm.tsx:80`)이 오기 — 앱은 서버값만 표시하므로 정합. 앱 주석 "30분"(`account_deletion_repository.dart:12-13`)만 정정 |
| 21 | 프로필(닉네임·학년) 수정 | `/mypage` | 완전(`api_app_v1.user_profile_update_self` `app:lib/features/mypage/data/profile_edit_repository.dart:26-39,110-125`) | **포함(유지)** | — |
| 22 | 마케팅 수신 동의 변경 | (웹 UI 없음 — RPC 만) | 없음 | **포함(신설 `api_app_v1` wrapper)** | `api_web_v1.user_marketing_consent_set_self(boolean)` 존재(`20260803170552…:287-330`)하나 앱 정본 스키마는 `api_app_v1`. 웹도 UI 0건이라 "웹 수준"의 상한선은 오너 판단(§7 (viii)) |
| 23 | 알림 설정(마스터·그룹 5종) | `/settings/notifications` | 완전(`notification_settings` RLS `app:lib/features/mypage/data/notification_settings_repository.dart:6-14`) | **포함(유지)** | 웹도 세션 클라이언트 upsert(`web:lib/notifications/notificationSettingsActions.ts:33-35,69-72`) — 동일 표면 |
| 24 | 차단 관리 | `/settings/blocks` | 완전(`BlockedUsersScreen` — `settings_section.dart:9`) | **포함(유지)** | — |
| 25 | 약관·개인정보 | `/legal/terms`·`/legal/privacy` | 외부 브라우저(`app:lib/core/web_bridge/web_bridge_config.dart:32-35`) | **포함(유지)** | — |
| 26 | 가입 직후 온보딩(가입 완료 → 인증/프로필 유도) | `/signup` 완료 화면 → `/mentor/profile/edit`·`/mypage`(`web:lib/auth/getPostLoginPath.ts:95-104`) | 스텁(`OnboardingScreen` 라우트 미등록 `app:lib/features/onboarding/onboarding_screen.dart:9`) | **포함** | #1~#4·#12 를 잇는 상태 기계(§4-1) |
| 27 | 관리자 로그인(비번 + MFA 판정 골격) | `/admin/login` | admin → blocked(`auth_service.dart:102-103`) | **제외(권고)** | MFA 코드 검증 미구현(`web:lib/auth/adminLoginConsole.ts:7-10`, `adminLoginActions.ts:45-48`), `email_confirmed_at` 필수(`:33-36`) → §7 (i) |
| 28 | 관리자 콘솔 34 페이지(+login 1 = 35) | `/admin/*` | 차단 | **제외(권고)** · WebView 옵션은 오너 결정 | `lib/admin` 106 엔트리 중 SR import 31 실파일, 관리자 JWT 호출 가능 쓰기 RPC 2종만(`admin_issue_user_warning`, `approve_mentor_school_verification_admin`), 쓰기 클라이언트는 SR 실패 시 중단(`web:lib/admin/adminWriteClient.ts:24-43`) → §3-c-3·§7 (i) |
| 29 | 소셜 로그인 | 없음(웹 0건) | 없음 | **제외(범위 밖)** | §7 (iv) |
| 30 | 앱 접근 상태에 온보딩·인증 대기 표현 | (웹은 서버 redirect) | `AccessState` 5종에 표현 불가(`app_architecture.md` §4-4-4) | **포함** | §4-1 |

**집계**(30행): 포함 **22**(#1·2·3·4·5·6·8·9·11·15·16·17·18·19·20·21·22·23·24·25·26·30 — 이 중 #4·#18·#22 는 신설 RPC 전제) · 웹 위임 **3**(#10·#12·#13) · 제외 **3**(#27·#28·#29) · 오너 결정 **2**(#7·#14). #18/#22/#28 행에 딸린 옵션(DB 강제·토글 노출·WebView 위임)은 각 행의 목표를 유지한 채 §7 에서 확정한다.

---

## 3. 서버 표면 설계

### 3-a 기존 그대로 사용 가능(변경 0)

| 기능 | 표면 | 시그니처/계약 | 근거 |
|---|---|---|---|
| 가입 | `supabase.auth.signUp(email, password, data: meta, emailRedirectTo)` | meta 20키 = `app_role, full_name, nickname, grade_level, student_status, birth_date, terms_agreed, privacy_agreed, marketing_agreed, university_name, department_name, teaching_subjects_csv, high_school_name, intro_line, is_minor, guardian_consent, consent_version, guardian_ref, age_gate_checked_at, guardian_verification_method` — 값은 전부 **문자열**("true"/"false") | `web:lib/auth/buildSignupUserMetadata.ts:29-53`; 소비 트리거 `20260717044250:24-79`, `20260829100300:44-104` |
| 가입 상수 | — | `consent_version='legal-placeholder-2026-06-20'`, `guardian_verification_method='nice_guardian_chain_post_signup'`, `guardian_consent='false'`, `is_minor` = 학생 && KST 만 14세 미만, `age_gate_checked_at` = 생년월일 있을 때 ISO now | `web:lib/auth/minorConsentPlaceholders.ts:2,27`, `web:app/signup/page.tsx:295,299,306-330`, `web:lib/auth/minorAgeGate.ts:3,52-55` |
| 가입 검증(클라이언트 정본) | — | 이메일 정규식, 비밀번호 ≥ 8(`SIGNUP_PASSWORD_MIN_LENGTH`), 확인 일치, 필수 약관 2종, 생년월일 필수·미래 금지(학생), 멘토 5필드 필수 | `web:lib/auth/signupValidation.ts:26,29,42-57,71-95`; Supabase 서버 최소는 6(`web:supabase/config.toml` `minimum_password_length = 6`) → 앱도 8 강제 |
| 로그인/로그아웃 | `auth.signInWithPassword` · `auth.signOut` | 기존 `AuthService` | `app:lib/core/auth/auth_service.dart:304-342` |
| 비밀번호 재설정 요청 | `auth.resetPasswordForEmail(email, {redirectTo: '<SITE>/auth/update-password'})` | Redirect allowlist 등록 필요 | `web:lib/auth/passwordResetActions.ts:19,36-38` |
| 프로필 행 | `users` SELECT own | `role, nickname, full_name, status, suspended_until` + **`identity_verified_at` 추가 선택** | `app:auth_service.dart:221-225`; 컬럼 SELECT 허용 `20260820100200:15-19` |
| 멘토 프로필 자기 행 | `mentor_profiles` SELECT own(`mentor_select_own`) | `verification_status`, `student_id_image_url`(비어 있음 여부만 표시 — 서명 URL 은 노출 금지 결정 `app:docs/RELEASE_SCOPE_DECISIONS_2026-07.md:11`) | `web_db_surface_payment_boundary.md` §2 |
| 프로필 수정 | `api_app_v1.user_profile_update_self(p_nickname, p_grade_level)` | 기존 | `20260803170552…:251-264` |
| 계정 상태 | `account_deletion_write_blocked(uuid)` · `account_deletion_status_self()` | 기존 | `web:supabase/sql/175_…:242-286` |
| 탈퇴 | `account_deletion_request_self_v2()` · `…_consented_v2(bigint)` · `account_deletion_cancel_self()` | 기존 | `20260803170916…:763-805` |
| 알림 설정 | `notification_settings` RLS `notif_settings_modify_own` | 기존 | baseline `:20014-20027` |
| 차단 | `user_blocks` RLS + `my_blocked_users()` | 기존 | — |
| 동의 원장 열람 | `user_consent_records` SELECT own(`ucr_select_own`) | 설정 화면에 "동의 이력" 표시용(선택) | `web:supabase/sql/087_user_consent_records.sql:42-51` |
| 학생증 파일 업로드 | Storage `student-id-images` INSERT own | 경로 `{uid}/{ts-rand}.{ext}`, 저장값 `student-id-images/{path}`, 20MB, jpg/jpeg/png/pdf + 매직바이트 | baseline `:331-337`; `web:lib/storage/studentIdImageStorage.ts:4-8,16-22,44-46`; 매직바이트 `web:lib/storage/uploadMagicBytes.ts`(앱은 `iq_attachment_policy` 의 매직바이트 검증 재사용) |
| 학교 증빙 | `mentor_school_verifications` INSERT own pending(`msv_insert_own_pending`) | 경로 `{uid}/school-verifications/…` | baseline `:10305`; `web:lib/mentor/mentorSchoolVerificationActions.ts:52,66-70` |

### 3-b 새로 필요한 서버 객체

#### 3-b-1 앱 세션 bootstrap 확장 (웹 코드 · DB 변경 없음) — **서버 선행**

현행: target 1종·멘토 전용(§1-3). 변경안:

```ts
// web:lib/appSession/appSessionBootstrapCore.ts
export const APP_SESSION_BOOTSTRAP_TARGETS = Object.freeze({
  shortform_create:    { path: "/app/community/shortform/new", roles: ["mentor"] },
  identity_onboarding: { path: "/app/onboarding/verify",       roles: ["student", "mentor"] },
  // 옵션(오너 결정 §7 (i)) — 기본 미등록:
  // admin_console:    { path: "/admin/dashboard",              roles: ["admin"] },
} as const);
```

- `strictMentorRoleDecision(profile, err)` → `strictRoleDecision(profile, err, allowedRoles)`(`web:lib/appSession/appSurfaceAccountGate.ts:84-96` 일반화). 오류 코드 `mentor_only` 는 유지하고 `role_not_allowed` 추가(`appSurfacePaths.ts:18-25`).
- `APP_BRIDGE_KINDS` → `['shortform','identity']`; `APP_BRIDGE_RESULTS` 는 kind 별 맵 `{shortform:['draft','published'], identity:['verified','cancelled']}`(`appSurfacePaths.ts:12-16`, `app/app/bridge/complete/page.tsx:14-18` 검증 갱신).
- **앱 표면 온보딩 페이지 신설** `web:app/app/onboarding/verify/page.tsx`·`guardian/page.tsx`: `/app/community/shortform/new/page.tsx:24-34` 패턴 그대로 — `createAppSurfaceClient()` → `getUser` → `assertAppSurfaceAccountActiveStrict` → role ∈ {student, mentor} → `getIdentityOnboardingState(admin, uid)`(`web:lib/identity/service.ts:645-707`) → `verified` 면 `appBridgeCompletePath('identity','verified')` 로 redirect, `guardian_required` 면 `/app/onboarding/guardian`, 아니면 `IdentityVerificationLauncher kind="self"|"guardian"` 렌더(전역 셸 없음).
- **복귀 경로 표면 분기**: `/api/identity/return` 의 opener 부재 시 폴백은 `/onboarding/verify?status=&code=`(`return/route.ts:50-60`) — WebView allowlist 밖. 해결: `POST /api/identity/start` body 에 `surface?: 'web'|'app'` 추가 → `nice_identity_vid` 와 같은 속성(httpOnly·path `/api/identity`·30분, `start/route.ts:71-77`)으로 `nice_identity_surface` 쿠키 발급 → return 이 이 쿠키를 읽어 폴백을 `/app/onboarding/verify` 로. DB·NICE 계약 무변경(return_url 250byte 상한 `service.ts:238-243` 영향 없음).
- 세션 쿠키: bootstrap 이 심는 쿠키는 `HttpOnly/Secure/SameSite=Lax/Path=/`(`web:lib/appSession/appSurfaceCookies.ts:12-17`). `/api/identity/*` 는 전역 `createClient()`(`web:lib/supabase/server.ts`)로 읽지만 쿠키 이름이 같아 그대로 인식된다(읽기만). NICE 복귀는 top-level GET/POST(SameSite=Lax 통과 — POST 복귀는 Lax 에서 **차단될 수 있음**: NICE `method_type GET` 로 발급(`web:lib/nice/client.ts:230-263`)이므로 GET 복귀 전제 **(확인 필요: 실측)**).

#### 3-b-2 `api_app_v1.mentor_student_id_image_set_self(p_storage_path text) → jsonb` — **S**

```sql
-- core_private.mentor_student_id_image_set_impl(p_actor uuid, p_storage_path text) SECURITY INVOKER
-- 1) p_actor null → AUTH_REQUIRED(28000)
-- 2) users(role,status,suspended_until) FOR UPDATE; role<>'mentor' → ROLE_NOT_ALLOWED;
--    계정 게이트 = user_profile_update_self_impl 판정식 그대로(ACCOUNT_BANNED/SUSPENDED/NOT_ACTIVE/DELETION_IN_PROGRESS)
--    (web:20260803170552…:186-203)
-- 3) 경로 검증: 'student-id-images/' 접두 제거 → split_part(path,'/',1) = p_actor::text 아니면 STORAGE_PATH_INVALID(22023);
--    확장자 ∈ {jpg,jpeg,png,pdf}
-- 4) storage.objects 실존 + 소유자 = p_actor (coalesce(o.owner, nullif(o.owner_id,'')::uuid) 패턴 —
--    web:20260731113927…:108-116) 아니면 STORAGE_OBJECT_NOT_FOUND / STORAGE_OBJECT_NOT_OWNED(42501);
--    metadata->>'size' ≤ 20MB, mimetype ∈ {image/jpeg,image/png,application/pdf}
-- 5) mentor_profiles 본인 행 FOR UPDATE; 없으면 MENTOR_PROFILE_NOT_FOUND
--    덮어쓰기 규칙: verification_status ∈ ('pending','rejected','resubmit_required')(값 집합 (확인 필요)) 이면 허용,
--    approved/verified/active 이면 STUDENT_ID_LOCKED(42501)
-- 6) update mentor_profiles set student_id_image_url = 'student-id-images/'||path, updated_at=now()
--    (특권 컬럼 가드는 verification_status/cap_limit 만 검사 → 통과, web:20260903100100…:138-175)
-- 7) return {ok:true, contract_version:1, student_id_image_ref, updated_at}
-- api_app_v1 wrapper: select core_private.…_impl((select auth.uid()), p_storage_path)
-- REVOKE ALL … FROM PUBLIC, anon; GRANT EXECUTE TO authenticated (service_role 없음 — api_app_v1 규약)
```
- 오류 봉투: `{ok:false, code}` 가 아니라 **raise**(앱 프로필 RPC 매퍼 규약 `app:profile_edit_repository.dart:72-79` 선두 토큰 파싱 재사용). 계약 §9 사전에 `STORAGE_PATH_INVALID`·`STORAGE_OBJECT_NOT_FOUND`·`STORAGE_OBJECT_NOT_OWNED`·`MENTOR_PROFILE_NOT_FOUND`·`STUDENT_ID_LOCKED` 추가(UPPER_SNAKE·추가만).
- 웹 `/mentor/verification` 액션도 같은 impl 을 호출하도록 전환 가능(SR 의존 1건 감소) — 선택.

#### 3-b-3 `api_app_v1.user_marketing_consent_set_self(p_agreed boolean) → jsonb` — **S**

- 현행 `api_web_v1` 함수는 본문에 판정·쓰기를 직접 담고 있다(`20260803170552…:287-330`) → 규약(판정은 impl 한 곳)에 맞춰 `core_private.user_marketing_consent_set_impl(p_actor uuid, p_agreed boolean)` 로 본문 이동, `api_web_v1`·`api_app_v1` 두 wrapper 가 호출. 반환 `{ok:true, contract_version:1, marketing_agreed}` 동일.
- 주의: 현행 본문의 `consent_version='v1'`, `source='self_rpc'` 는 가입 트리거의 `'legal-placeholder-2026-06-20'`/`'signup'` 과 다르다 — impl 이동 시 버전 정본을 하나로(오너/법무 확정값) 맞출지 **(확인 필요)**.
- GRANT: `api_app_v1` 은 authenticated 만.

#### 3-b-4 `api_app_v1.account_deletion_preconditions_self() → jsonb` — **M**

```sql
-- SECDEF wrapper → core_private.account_deletion_preconditions_impl(p_actor uuid) (INVOKER 는 RLS 에 걸리므로
-- 이 impl 은 예외적으로 SECDEF 또는 wrapper 본문에서 owner 권한으로 집계 — 계약 §5.2 예외 명시 필요)
-- 반환:
-- { ok:true, contract_version:1, role:'student'|'mentor',
--   items:[ {key:'subscriptions'|'subscribers', ok, count},
--           {key:'individual_questions', ok, count},
--           {key:'custom_request_orders', ok, count},
--           {key:'disputes', ok, count} ],
--   blockers_ok, wallet_balance_cents }
-- 집계식(web:lib/account/accountDeletionPreconditions.ts 와 1:1):
--   student: subscriptions.student_id=uid AND status IN ('active','past_due')
--   mentor : subscriptions.mentor_id=uid  AND status IN ('active','past_due')
--   IQ     : student → student_id=uid / mentor → (claimed_mentor_id=uid OR designated_mentor_id=uid), status IN ('open','assigned','claimed','answered')
--   CR 주문: (student_id|mentor_id)=uid AND lower(coalesce(nullif(status,''),nullif(state,''),nullif(order_status,''),nullif(stage,''),'')) NOT IN (터미널 11종)
--            (컬럼 4개 모두 실존 — baseline:1004-1007; 우선순위는 TS orderPrimaryStatus 와 동일)
--   disputes: (student_id=uid OR mentor_id=uid) AND status IN ('open','under_review')  (baseline:1456-1461)
--   wallet : cash_wallets.balance_cents (없으면 0)
-- 오류: AUTH_REQUIRED · ROLE_NOT_ALLOWED(admin)
```
- 읽기 전용(행 수정 0). **요청 RPC 에서의 강제**(`account_deletion_request_consented` 안에 blockers 검사 추가)는 웹·앱 양쪽 동작을 바꾸므로 §7 (vii) 오너 결정 — 결정 전에는 앱이 이 RPC 결과로 **안내·차단 UI 만** 하고 서버는 기존대로 잔액 동의만 강제한다.

#### 3-b-5 (옵션) 앱 런타임 플래그 전달 — **S** · §7 (v) 결정 시에만

- IDENTITY_GATE 를 앱에도 강제하려면 서버 플래그를 앱이 읽어야 한다. 후보: `public.app_runtime_flags(key text pk, value jsonb, updated_at)` service_role 전용 + `get_app_runtime_flags() → jsonb` STABLE SECDEF(anon+authenticated EXECUTE — `get_mobile_app_version_policy` 선례 `web_db_surface_payment_boundary.md` §7.1). 반환 `{identity_gate_enabled:boolean}`. 웹 env 와 이중 정본이 되므로 웹 `isIdentityGateEnabled()` 도 이 테이블을 읽도록 바꿀지 함께 결정.
- 대안(비권장): dart-define 상수 — 플래그 전환에 앱 재배포 필요.

#### 3-b-6 (옵션) `api_app_v1.identity_status_self() → jsonb` — **S** · 우선 불필요

- `users.identity_verified_at` 만으로 verified/미인증 2분법은 가능. `self_required`/`guardian_required` 구분은 웹 앱표면 페이지가 서버 redirect 로 처리하므로 앱이 알 필요 없음. 앱이 "보호자 인증 대기" 배지를 네이티브로 그리길 원할 때만 신설(`identity_verifications` 의 `kind,status` 만 반환 · PII 0).

#### 3-b-7 관리자 콘솔 옵션 B (WebView) 에 필요한 서버 변경 — §7 (i) 채택 시에만

- bootstrap target `admin_console`(roles `['admin']`) + allowlist `/admin/*`, `/api/admin/*`(CSV 내보내기 `web:app/api/admin/question-export/route.ts`), Realtime Presence(`admin:*`) 는 WebView 내 웹 코드가 처리. `(admin)/layout.tsx:8-15` 는 전역 `createClient()` 로 쿠키를 읽으므로 앱 표면 HttpOnly 쿠키로도 동작. 단 MFA 2단계가 미구현(§2 #27)이므로 앱에서 관리자 세션을 여는 것은 보안 후퇴 — 권고하지 않음(§3-c-3).

### 3-c 보안 리스크

1. **bootstrap 학생 허용의 의미**: 지금까지 앱 토큰 → 웹 쿠키 전환은 멘토·숏폼 1종에만 열려 있었다. 학생까지 열면 (a) 대상 경로가 늘수록 WebView allowlist 가 방어선 — 앱 측은 host 정확 일치 + 경로 열거 유지(`app:lib/core/web_bridge/shortform_compose_bridge.dart:58-66` 규칙을 일반화하되 `/subscribe`·`/wallet`·`/cash` 는 절대 불포함), (b) 서버 측은 target 별 role 정책 + strict 계정 게이트(fail-closed) 유지, 실패 응답에 Set-Cookie 0 불변식(`bootstrap/route.ts` 헤더 주석) 유지, (c) 쿠키 위생 — 진입 전·종료 후 `WebSessionHygiene.clear()`(`app:lib/core/web_bridge/web_session_hygiene.dart:7-32`) 유지, 로그아웃 전 정리(`auth_service.dart:338`).
2. **NICE 표준창 외부 호스트**: 인증 WebView 는 웹 호스트 밖(NICE 표준창 URL)으로 이동해야 한다. authUrl 호스트는 코드에 상수로 없고 NICE API 응답값(`web:lib/nice/client.ts:230-263`) → allowlist 에 넣을 정확 호스트 **(확인 필요: 스테이징 실측)**. 확인 전까지는 "start 응답 authUrl 의 host 를 1회 허용" 같은 동적 허용을 두지 말고 상수로 고정한다(피싱 리다이렉트 방지).
3. **이메일 인증 운영 설정**: Confirm email ON/OFF 에 따라 signUp 응답의 `session` 유무가 갈리고(`web:app/signup/page.tsx:360-464` 두 분기), 앱 가입 완료 흐름과 #3 학생증 경로가 달라진다. 운영 대시보드 값 **(확인 필요)**. OFF 라면 관리자 로그인의 `email_confirmed_at` 필수(`adminLoginActions.ts:33-36`)만 예외.
4. **admin 앱 차단 유지 근거**: (a) 관리자 쓰기의 대부분이 SR 서버 액션(31 파일) 또는 service_role 전용 RPC(`approve_refund_request_admin`, `run_scheduled_payout`, `pay_due_payouts_for_run`, `record_custom_order_dispute_split`, 탈퇴 worker) — anon 키 + 관리자 JWT 로는 0행/권한 오류; (b) MFA 미완(PR-12b); (c) Play 심사에서 "관리자 기능 없음"이 긍정 요소(`web_db_surface_payment_boundary.md` §7.2 #2); (d) 앱 `computeAccess` 의 admin→blocked 는 테스트로 고정된 fail-closed 규칙(`auth_service.dart:102-103`). WebView 위임을 열면 (a)는 우회되지만 (b)·(c) 후퇴.
5. **가입 메타 신뢰 경계**: 트리거는 `app_role` 외 값을 student 로 폴백하고 `admin` 을 차단(`20260717044250:29-33`, INSERT 가드 `:111-140`). 앱은 `student|mentor` 만 보낸다. `users_insert_own` 정책·INSERT GRANT 가 남아 있으나(`20260803170552…:87-93`) 앱은 직접 INSERT 금지(매니페스트 테스트 `app:test/contracts/outbound_api_manifest_test.dart:298-311`).
6. **비밀번호 재인증 클라이언트**: 탈퇴 재인증에 기본 클라이언트를 쓰면 세션이 교체·회전된다 → 웹처럼 `persistSession:false`·`autoRefreshToken:false` 의 일회용 클라이언트(`accountDeletionActions.ts:62-66`)로만 검증.
7. **PII**: NICE 결과·CI/DI 는 앱에 절대 도달하지 않는다(서버 전용 유지). `mentor_profiles.student_id_image_url` 은 경로 문자열이지만 앱은 서명 URL 을 만들지 않는다(웹 전용 결정 유지).
8. **Storage 소유자 검증**: 신설 RPC 의 소유자 검증은 `storage.objects.owner`/`owner_id` 이중 컬럼 패턴(`20260731113927…:108`) 재사용 — Storage API 가 authenticated 업로드에 `owner_id=auth.uid()` 를 채우는 동작 전제 **(확인 필요: 앱 SDK 업로드 실측)**.

---

## 4. 앱 프론트엔드 설계

### 4-1 `AccessState` / `AccountStatusKind` 확장안

- `AccountStatusKind`: 기존 7종 유지 + `deleted` 판정에 `users.status='deleted'` 문자열 명시 추가(`account_status.dart:287-311` 의 "그 외 → active" 를 `deleted → deleted` 로 좁힘). CHECK 4종 이후 다른 값은 오지 않으므로 나머지 미지 값은 fail-closed(`fetchFailed` 대신 `blocked` 사유 `status_unknown`)로 바꾸는 것을 권고(웹 strict 게이트 `appSurfaceAccountGate.ts:44-60` 와 정합).
- `AccessState` 확장(5 → 7):

| 값 | 의미 | 입력 |
|---|---|---|
| `loading` / `loggedOut` / `guest` / `blocked` | 기존 그대로 | 기존 |
| `needsIdentity` (신설) | 로그인·계정 정상·role ∈ {student,mentor} · `identity_verified_at IS NULL` · **게이트 강제 ON** | `users.identity_verified_at` + 플래그(§3-b-5) — §7 (v) 미채택 시 이 값은 생성되지 않고 대신 `full` + `IdentityState.required` 배지 |
| `needsMentorDocs` (선택) | 멘토 · `mentor_profiles.student_id_image_url` 비어 있음 | 웹은 이를 게이트로 막지 않음(승인 게이트 `web:lib/mentor/mentorVerificationGate.ts:4-9`) → 접근 상태로 두지 않고 마이페이지 배너로 표현하는 것을 권고(표에서는 대안으로만) |
| `full` | 기존 | 기존 |

- 판정 순서(`computeAccess` 확장): `bootstrapping→loading` → signedIn: `retryable/roleFetchFailed→blocked` → `!allowsAppUse→blocked` → `admin→blocked` → `role∉{student,mentor}→blocked` → **`gateEnabled && identityVerifiedAt==null → needsIdentity`** → `full`; 비로그인은 기존.
- `IdentityState {unknown, verified, required}` 를 `AuthService` 가 `users` 통합 SELECT(`:221-225`)에 `identity_verified_at` 컬럼을 추가해 얻는다(왕복 증가 0). WebView 종료 후 `reloadProfile()` 로 재판정.

### 4-2 `EntryGuard` redirect 표(확장)

현행은 `full → /home` 고정(`app:lib/app/entry_guard.dart:38-51`). 명명 라우트가 늘어나므로 "허용 위치 집합" 방식으로 재정의한다.

| AccessState | 허용 위치 | 그 외 → redirect |
|---|---|---|
| `loading` | `/splash` | `/splash` |
| `loggedOut` | `/login`, `/signup`, `/signup/*`, `/forgot-password` | `/login` |
| `guest` | `/home`, `/login`, `/signup*`, `/forgot-password` | `/home` |
| `needsIdentity` | `/onboarding/identity`, `/account/delete`(탈퇴권 예외 — 웹 `(student)/layout.tsx:64-68` 와 동일), `/blocked` | `/onboarding/identity` |
| `full` | `/home`, `/onboarding/identity`(자발 재진입 — 서버가 verified 면 즉시 complete), `/account/*`, `/settings/*`, `/mentor/verification`(멘토만), 상세 라우트 | `/home` |
| `blocked` | `/blocked` | `/blocked` |

- 가입 직후 상태 기계: `signUp` → (a) 세션 있음 → `_loadProfile` → 트리거 행 확인(`users.role` 존재; 없으면 재시도 1~2회 후 `blocked`(재시도 가능) — 트리거 지연 방어) → 멘토면 `/mentor/verification`(학생증 첨부가 있었으면 즉시 업로드+RPC) → `needsIdentity` 또는 `full`; (b) 세션 없음(Confirm email ON) → `/login?notice=signup-check-email`(웹 `?message=signup-check-email` 대응 `web:app/signup/page.tsx:454-461`) → 첨부 파일은 로컬 폐기(세션 없이 업로드 불가) 후 첫 로그인 시 `/mentor/verification` 유도.

### 4-3 디렉터리 구조(기존 규약 `app_architecture.md` §9-1 준수)

```
lib/features/auth/
  data/auth_repository.dart          signUp(meta)·signIn·signOut·resetPasswordForEmail·reauthenticate(일회용 client)
  data/signup_metadata.dart          buildSignupUserMetadata 1:1 포팅(20키·"true"/"false"·상수 2종)
  data/signup_validation.dart        signupValidation.ts 1:1(≥8·정규식·약관·생년월일·멘토 5필드)
  data/age_gate.dart                 isUnderMinimumSignupAge(KST 만 14) — web:lib/auth/minorAgeGate.ts 포팅
  ui/login_screen.dart (기존) · signup_role_screen · signup_student_screen · signup_mentor_screen · forgot_password_screen
lib/features/onboarding/
  identity_state.dart                IdentityState 파생(users.identity_verified_at)
  ui/identity_gate_screen.dart       needsIdentity 안내 + WebView 진입 + '나중에'(게이트 OFF 시) + 로그아웃
  ui/identity_webview_screen.dart    AppSurfaceWebViewScreen(target: identity_onboarding)
lib/features/account/
  data/account_deletion_repository.dart (기존 · 주석 30분 → 서버값 정정)
  data/deletion_preconditions_repository.dart   account_deletion_preconditions_self 파서
  data/marketing_consent_repository.dart        api_app_v1.user_marketing_consent_set_self
  data/mentor_student_id_repository.dart        Storage 업로드 + mentor_student_id_image_set_self (+ 실패 시 객체 삭제 보상 — web:mentorStudentIdActions.ts:77-80 패턴)
  ui/account_delete_screen.dart (기존 + 사전조건 리스트 + 비밀번호 재인증 단계)
  ui/mentor_verification_screen.dart  학생증(+학교 증빙 — 멘토 콘솔 도메인 합의 후)
lib/core/auth/                       AuthService·AccountStatus 확장(§4-1)
lib/core/web_bridge/
  app_surface_bridge.dart            ShortformComposeBridge 일반화(아래)
  shortform_compose_bridge.dart      AppSurfaceBridge.shortform() 팩토리로 축소(호환 유지)
```

### 4-4 WebView 브릿지 일반화 — `AppSurfaceBridge`

```dart
class AppSurfaceBridge {
  AppSurfaceBridge({required String baseUrl, required this.target, required this.entryPath,
                    required this.allowedPaths, this.allowedExternalHosts = const {}, required this.kind});
  static const bootstrapPath = '/api/app-session/bootstrap';
  static const bridgeCompletePath = '/app/bridge/complete';
  static const bridgeErrorPath = '/app/bridge/error';
  final String target;            // 'shortform_create' | 'identity_onboarding'
  final String entryPath;         // '/app/community/shortform/new' | '/app/onboarding/verify'
  final Set<String> allowedPaths; // 정확 일치 + prefix 허용 목록(예: '/app/onboarding/', '/api/identity/')
  final Set<String> allowedExternalHosts; // identity 만: NICE 표준창 host (확인 필요) — 정확 일치
  final String kind;              // 'shortform' | 'identity'
  Uint8List buildBootstrapBody(access, refresh) // 기존 :39-49 와 동일(target 만 주입)
  bool isAllowedNavigation(Uri)   // https 강제 · host == baseHost(또는 allowedExternalHosts 정확 일치) · 경로 allowlist
  AppSurfaceOutcome? completionOf(Uri) // /app/bridge/complete?kind=<kind>&result=<r> → (kind, result)
  factory AppSurfaceBridge.shortform(baseUrl) / .identity(baseUrl)
}
```
- 화면 `AppSurfaceWebViewScreen` 은 `shortform_compose_screen.dart:55-138` 흐름(세션 확인 → 쿠키 정리 → POST bootstrap → allowlist 탐색 → complete 인터셉트 → pop → dispose 시 쿠키 정리)을 그대로 일반화. identity 변형은 (i) `window.open` 이 동일창 폴백으로 흐르도록 다중 창 미지원 유지(런처 `IdentityVerificationLauncher.tsx:90,110-115` 폴백 활용), (ii) 오류 브릿지 `code=role_not_allowed|account_blocked|session_expired` 처리, (iii) 완료 결과 `verified` 수신 시 `AuthService.reloadProfile()`.
- 단위 테스트: 기존 `shortform_compose_bridge` 테스트를 팩토리 기반으로 이전 + identity allowlist 표 테스트(결제 경로 차단 케이스 포함).

### 4-5 매니페스트 갱신(`app:test/contracts/outbound_api_manifest_test.dart`)

| 집합 | 추가 | 비고 |
|---|---|---|
| `kExpectedRpcNames` | `mentor_student_id_image_set_self`, `user_marketing_consent_set_self`, `account_deletion_preconditions_self`, (옵션) `get_app_runtime_flags`, (옵션) `identity_status_self` | `api_app_v1` 스키마 경유(`schema('api_app_v1')`) |
| `kExpectedTables` | (선택) `user_consent_records`, (멘토 콘솔 합의 시) `mentor_school_verifications` | `users` 는 SELECT 전용 유지(`identity_verified_at` 컬럼 추가는 리터럴 집합 무관) |
| `kExpectedBucketNames` / `kExpectedBucketIdentifiers` | `student-id-images` / `MentorStudentIdRepository.bucket` | 리터럴 0건 규칙 유지 |
| `kForbiddenWords` | 변경 없음 | `account_deletion_request_self`(구) 금지 유지 |
| 별도 테스트 | `auth.signUp` 호출은 `AuthRepository` 1곳만(다중 정의 방지), `.from('users')` 체인 `.insert(`/`.update(` 0건 유지 |

- iOS `PrivacyInfo.xcprivacy`(`app:ios/Runner/PrivacyInfo.xcprivacy:39-89` 현재 Email·UserID·Photos·OtherUserContent·Other) — 가입으로 이름·생년월일·학교 정보 수집이 추가되면 항목 갱신 + 계약 테스트 갱신 **(확인 필요: 분류)**.

---

## 5. 데이터 모델

### 5-1 앱 모델(신설·확장)

| 모델 | 필드 | 원천 |
|---|---|---|
| `SignupDraft` | `role(student\|mentor)`, `email`, `password`, `passwordConfirm`, `nickname`, `gradeLevel`, `studentStatus`(입력 컨트롤 유무 웹 (확인 필요) — 빈 문자열 허용), `birthDate(yyyy-MM-dd)`, `termsAgree`, `privacyAgree`, `marketingAgree`, 멘토: `universityName`, `departmentName`, `teachingSubjectsCsv`, `highSchoolName`, `introLine`, `studentIdFile?` | 웹 폼 값 타입(`web:components/auth/StudentSignupForm.tsx:3-9`, `MentorSignupForm.tsx:6-14`) |
| `SignupMetadata.toMap()` | 20키 `Map<String,String>` — `full_name` = `nickname`(웹 동일 `app/signup/page.tsx:302,308-309`), `is_minor` KST 판정, `guardian_consent='false'`, `consent_version='legal-placeholder-2026-06-20'`, `guardian_verification_method='nice_guardian_chain_post_signup'`, `age_gate_checked_at` ISO | `buildSignupUserMetadata.ts:29-53` |
| `UserProfileRow` 확장 | + `identity_verified_at: DateTime?` | `users` SELECT own |
| `IdentityState` | `unknown \| verified \| required` | 파생 |
| `MentorSelfProfile` | `verification_status`, `hasStudentIdDoc`(bool — 경로 문자열 자체는 보관하지 않음) | `mentor_profiles` SELECT own |
| `DeletionPreconditions` | `role`, `items[{key, ok, count}]`, `blockersOk`, `walletBalanceCents` | RPC §3-b-4 |
| `MarketingConsent` | `agreed: bool` (`users.marketing_agreed` 읽기 → RPC 쓰기) | `users` SELECT own · RPC §3-b-3 |
| `ConsentRecord`(선택) | `consent_type`, `consent_actor`, `consent_version`, `agreed_at`, `source` | `user_consent_records` SELECT own(`metadata` 는 표시 금지 — 087 코멘트 "Do not expose publicly") |
| `AppSurfaceOutcome` | `kind`, `result` | 브릿지 |

### 5-2 DB — 신규 테이블 없음(옵션 1개)

- 신설 함수 5종(§3-b-2·3·4, 옵션 5·6)만. 테이블 신설은 옵션 `app_runtime_flags` 1개(§3-b-5 채택 시 · RLS on·정책 0·service_role 전용 + 읽기 RPC).
- 기존 컬럼 활용: `users.identity_verified_at`(2026-08-20 추가), `users.marketing_agreed`, `mentor_profiles.student_id_image_url`(baseline `:129`), `user_consent_records.*`.
- RPC 봉투: 성공 `{ok:true, contract_version:1, …}`, 실패는 raise(선두 UPPER_SNAKE 토큰) — 앱 기존 매퍼 규약(`profile_edit_repository.dart:72-79`) 재사용. 계약 문서 §9 오류코드 사전에 추가만.

---

## 6. 구현 순서·의존성·규모

| 단계 | 작업 | 규모 | 선행/의존 | 저장소 |
|---|---|---|---|---|
| **0-A (서버 선행)** | bootstrap 확장(target 맵·role 정책·`role_not_allowed`·kind/result 맵) + `/app/onboarding/verify`·`/guardian` 앱표면 페이지 + start `surface` 쿠키·return 폴백 분기 + 계약 테스트 갱신 | **M** | 없음(웹 코드만) | 웹 |
| **0-B (서버 선행)** | `api_app_v1.mentor_student_id_image_set_self` + impl · sql/rollback/backfill · 계약 §9 | **S** | 없음 | 웹 pack |
| **0-C (서버 선행)** | `user_marketing_consent_set_self` impl 분리 + `api_app_v1` wrapper | **S** | `consent_version` 정본 결정(§3-b-3) | 웹 pack |
| **0-D (서버 선행)** | `account_deletion_preconditions_self` | **M** | 없음(읽기 전용) | 웹 pack |
| **0-E (옵션)** | `app_runtime_flags` + `get_app_runtime_flags` | **S** | §7 (v) 채택 | 웹 pack |
| **1** | 앱 코어: `AuthService`(identity 컬럼·`IdentityState`)·`AccountStatusKind.deleted` 명시·`AccessState.needsIdentity`·`EntryGuard` 허용집합 재정의·명명 라우트 추가 | **M** | 라우팅 재설계(다른 도메인과 공통 — `app_architecture.md` §9-2)와 병행 | 앱 |
| **2** | `AppSurfaceBridge` 일반화 + `AppSurfaceWebViewScreen` + 숏폼 팩토리 이전 + 테스트 | **M** | 0-A 계약 확정(경로·kind 상수) | 앱 |
| **3** | 회원가입 네이티브(역할 선택·학생/멘토 폼·검증·메타 20키·가입 후 상태 기계·이메일 인증 분기) | **L** | §7 (ii)·(iii-1 이메일 인증) 확정 · 1 | 앱 |
| **4** | 비밀번호 재설정 요청 화면(`resetPasswordForEmail`) · 로그인 화면 가입/재설정 진입 | **S** | 3 | 앱 |
| **5** | 본인인증 WebView(`identity_onboarding`) · 게이트 화면 · 완료 후 재판정 | **M** | 0-A · 2 · NICE host 확인 | 앱 |
| **6** | 멘토 학생증 업로드 + RPC(가입 직후·사후) | **M** | 0-B · 3 | 앱 |
| **7** | 설정: 마케팅 동의 · (선택) 동의 이력 | **S** | 0-C | 앱 |
| **8** | 탈퇴 정합: 사전조건 리스트 · 비밀번호 재인증 · 30일 문구 정정 | **M** | 0-D | 앱 |
| **9** | 매니페스트·iOS PrivacyInfo·계약 테스트 갱신, 계약 문서 §19.1 앱 열 갱신(가입 ✅ · 본인인증 "WebView 위임") | **S** | 3~8 | 앱·웹 문서 |
| 관리자 | 권고안(제외) 채택 시 작업 0 · 옵션 B 채택 시 0-A 에 `admin_console` target + 앱 allowlist(`/admin/*`,`/api/admin/*`) **M** · 옵션 C(최소 표면) **XL** | — | §7 (i) | — |

서버 선행 총량 ≈ M+S+S+M(+S) · 앱 총량 ≈ L + 5M + 3S.

---

## 7. 오너 결정 필요 항목

| # | 항목 | 선택지 | 권고 | 근거 |
|---|---|---|---|---|
| (i) | **관리자 콘솔 앱 포함** | A 제외(admin→blocked 유지) / B WebView `/admin` 위임(bootstrap `admin_console` target) / C 최소 관리자 표면 네이티브 | **A 제외** | 35 페이지 중 SR 비의존은 `moderation` 목록·`notices`·`settings` 토글 정도(`web_account_identity_admin.md` §5-3); 핵심 조치(정지/차단·승인 전이·환불·정산·분쟁 분배)는 SR 액션 또는 service_role 전용 RPC → C 는 30여 개 `is_admin()` SECDEF RPC 신설(XL) + 권한 모델 재설계. B 는 구현 M 이지만 MFA 미완(`adminLoginConsole.ts:7-10`) 상태에서 모바일 관리자 세션을 여는 보안 후퇴 + Play 긍정요소 상실. **재검토 시점: PR-12b(MFA) 완료 후** |
| (ii) | **회원가입 앱 네이티브** | A 네이티브(권고) / B 웹 위임(외부 브라우저 `/signup` — 가입 후 앱 재로그인) / C WebView 위임(비로그인 표면이라 bootstrap 불필요 · allowlist `/signup*`) | **A** | 가입은 `auth.signUp` + 트리거만으로 완결(§1-3) — 서버 객체 신설 0. 유일한 서버 의존(학생증)은 0-B 로 해소. B/C 는 "웹 수준" 요구에 미달하며 가입 후 앱 재로그인 UX 단절 |
| (iii) | **본인인증 WebView 위임** | A WebView(bootstrap 확장, 권고) / B 네이티브(Bearer 수용 start + 서명 티켓 return + 결과 조회 RPC 재설계 — `web_account_identity_admin.md` §3-5 방식 B) / C 외부 브라우저(`/onboarding/verify` — 웹 로그인 재수행 필요) | **A** | 테이블·키·NICE 클라이언트 서버 전용 + 쿠키 세션 + return_url 웹 도메인 계약. B 는 NICE 복귀 계약 재설계(L~XL)·PII 경계 재검토. A 는 기존 숏폼 브릿지 선례 재사용(M) |
| (iii-1) | **이메일 인증(Confirm email) 운영값** | ON / OFF | **확인 후 확정** — 코드는 양쪽 지원 | 가입 직후 세션 유무·학생증 즉시 업로드 가능 여부·"메일 확인" 화면 필요 여부가 갈림(§4-2). 운영값 **(확인 필요)** |
| (iv) | **소셜 로그인** | 도입 / 미도입 | **미도입(범위 밖)** | 웹·앱 모두 0건(`signInWithOAuth` grep 0). 도입 시 트리거 메타 계약(20키 · `app_role`)을 OAuth 첫 로그인에서 채울 수 없어 별도 "역할 선택·약관 동의" 후처리 RPC 가 필요 → 계정 도메인 재설계 |
| (v) | **IDENTITY_GATE 앱 강제** | A 앱도 강제(`needsIdentity` + 플래그 RPC §3-b-5) / B 비강제(배지·안내만, 웹 결제 경로에서만 막힘) / C DB 게이트(설계 원칙 위반 — 비권고) | **B(1차) → 운영 ON 확정 후 A** | 웹 운영 플래그 현재값 **(확인 필요)**(S-C 보고서 "기본 OFF → 실측 후 ON" `web:docs/sprint-pay/S-C-REPORT.md:18`). 앱이 부르는 직접 RPC 는 게이트 밖이라 강제해도 웹과 동일 의미가 아님. A 채택 시 플래그 이중 정본(env vs 테이블) 정리 필요 |
| (vi) | 비밀번호 재설정 **딥링크** | A 웹 완료(권고) / B 앱 딥링크(커스텀 scheme 또는 App Links + Supabase Redirect allowlist + PKCE 세션 수신) | **A** | 앱에 스킴 0(§1-3). B 는 Android/iOS 설정 + 계약 테스트(iOS `LSApplicationQueriesSchemes` 계약 `app:test/contracts/ios_release_config_contract_test.dart:31-33`) 변경 (M) |
| (vii) | 탈퇴 **사전조건 DB 강제** | A 조회 RPC 만(앱·웹 UI 안내) / B `account_deletion_request_consented` 안에 blockers 강제(웹·앱·구앱 동시 영향) | **A(1차)** | 웹은 TS 에서 강제하고 앱은 안내만 하게 되어 "웹 고유 관문" 차이가 남지만, B 는 hotfix 급 동작 변경 + 구 앱(v2 RPC 호출 중) 회귀 |
| (viii) | 마케팅 동의 **토글 노출** | A 앱 노출(웹은 UI 없음 — 앱이 웹보다 앞섬) / B 미노출(가입 시 1회만) | **A** | RPC 는 존재·동의 원장 append 규약 준수. 웹도 같은 impl 로 토글을 추가하면 정합 |
| (ix) | `AccountStatusKind` 미지 status 처리 | A `deleted` 만 명시 추가 / B 미지 값 fail-closed 차단 | **B** | CHECK 4종이라 미지 값 = 스키마 불일치 신호. 웹 strict 게이트와 정합 |
| (x) | 멘토 학교 증빙 제출 앱 포함 | 포함 / 웹 위임 | 멘토 콘솔 도메인과 합의 | RLS 직접 INSERT 가능(§3-a) — 서버 객체 0 |

---

## 8. 리스크·지뢰

1. **트리거 지연·실패 = role 불명 → blocked**: `signUp` 직후 `users` 행이 늦으면 `_parseRole → guest → blocked`(`auth_service.dart:107-108,275-286`). 가입 흐름은 최초 로드 실패를 "재시도 가능" 으로 다루고 1~2회 재조회 후 판정한다(N32 유지 규칙과 충돌 없음 — 최초 로드이므로 `_lastGoodProfileUid` 없음).
2. **`app_role` 오타 = 학생 계정 생성**: 트리거가 미지 값을 student 로 폴백(`20260717044250:29-33`) — 멘토 가입이 조용히 학생으로 만들어질 수 있다. 앱은 enum 직렬화 1곳 + 계약 테스트로 문자열 고정.
3. **비밀번호 최소 길이 이중 기준**: 서버 6(`config.toml`) vs 웹 8 — 앱이 8 을 강제하지 않으면 웹 로그인 재설정 문구(≥8, `UpdatePasswordClient.tsx:19`)와 어긋난다.
4. **Confirm email ON 일 때 학생증 유실**: 세션 없는 가입 직후 업로드 불가. 웹은 SR 15분 창으로 구제하지만(`mentorSignupStudentIdAction.ts:20`) 앱은 그 경로가 없다 → 첫 로그인 유도 화면이 필수. 사용자가 로그인 전 파일을 잃는 UX 를 사전 고지.
5. **NICE 복귀와 WebView**: (a) return_url 호스트 = 시작 호스트(`ALLOWED_APP_HOSTS`)여야 쿠키가 실림 — 앱 `WEB_BASE_URL` 기본값 `https://ssambership.com`(`web_bridge_config.dart:16-19`)은 허용목록 안. 스테이징 도메인(`vercel.app` 등)은 `APP_URL` 폴백으로 갈려 실측 필요. (b) NICE 결과 1회성(3033) — WebView 새로고침이 CAS 락에 걸리면 `IN_PROGRESS`/`ALREADY_DONE` 토큰 처리(`return/route.ts:173-210`) 를 앱표면 페이지가 그대로 보여줘야 함. (c) NICE 표준창 host 미확정(§3-c-2).
6. **bootstrap 학생 허용 후 allowlist 누락**: 앱표면 온보딩 페이지가 로그아웃 링크(`/logout` POST)나 `/legal/*` 링크를 포함하면 WebView 가 차단 → 앱표면 페이지는 링크 0 로 작성(브릿지 페이지 규약 `app/app/bridge/*` 와 동일).
7. **HttpOnly 앱표면 쿠키 vs 일반 웹 클라이언트**: `/api/identity/*` 는 전역 `createClient()`(httpOnly=false 기본) 로 쿠키를 **쓸 수도** 있다(refresh 회전). 회전 시 속성이 일반값으로 내려가는 구조(`bootstrap/route.ts` 헤더 주석이 경고한 바로 그 구조) → identity 라우트에서 앱표면 요청이면 `createAppSurfaceClient()` 를 쓰도록 분기하거나, 앱표면 페이지가 `/api/identity/*` 를 호출하는 동안 회전이 일어나지 않게 만료 여유를 확인 **(확인 필요)**.
8. **`consent_version` 불일치**: 가입 `'legal-placeholder-2026-06-20'` vs 마케팅 RPC `'v1'` — impl 분리 시 정본 확정 없으면 원장에 두 체계가 섞인다.
9. **30일/30분 문구**: 웹 화면 문구가 오기(§2 #20). 앱은 서버값만 쓰되, 웹 정정은 별도 이슈.
10. **`status='deleted'` 계정 로그인**: auth soft-delete 로 로그인 불가가 전제 **(확인 필요)** — 아니라면 현 앱은 active 로 통과(§7 (ix) B 로 차단).
11. **매니페스트 집합 테스트**: RPC 추가·버킷 추가 없이 코드만 넣으면 CI 실패(의도된 잠금). `student-id-images` 버킷은 상수 경유만.
12. **PostgREST 스키마 캐시**: 새 함수 추가 후 `NOTIFY pgrst, 'reload schema'` 없으면 PGRST202 — 앱 매퍼는 이를 `AccountDeletionUnavailable` 류 폴백으로 오인할 수 있음(기존 42883/PGRST202 폴백 `account_deletion_repository.dart:22-24`).
13. **`api_app_v1` 에 service_role 없음**: 웹 서버가 앱 wrapper 를 호출하지 못한다 — 웹 동등 기능은 `api_web_v1` wrapper 를 같은 impl 위에 따로 둔다(3-b-3 방식).
14. **관리자 WebView 옵션의 세션 위험**: 채택 시 관리자 JWT 가 모바일 WebView 쿠키로 존재 · MFA 없음 · 기기 분실 시 노출. 옵션 A 권고의 핵심 근거.
15. **iOS/Play 심사**: 가입 폼(이름·생년월일·학교)·14세 미만 가입 허용은 앱스토어 연령/개인정보 고지 항목에 영향 — 법무 검토 사항(이 문서는 판단하지 않음).
16. **Storage 업로드 소유자 컬럼**: 신설 RPC 의 소유자 검증은 `owner`/`owner_id` 이중 패턴을 쓰되, 앱 SDK 업로드가 `owner_id` 를 채우는지 스테이징 실측 **(확인 필요)** — 실패 시 RPC 가 `STORAGE_OBJECT_NOT_OWNED` 로 전부 거절한다(fail-closed 라 데이터 오염은 없음).
17. **AccessState 확장과 라우팅 재설계의 결합**: `EntryGuard` 가 `/home` 단일 수렴 구조(`entry_guard.dart:47-48`)라 명명 라우트 추가는 다른 도메인(질문방·CR 등)의 라우팅 재설계와 같은 PR 에서 정리해야 충돌이 없다.

---

## 부록 A. 이번 설계에서 새로 남긴 (확인 필요)

1. 운영 Supabase Auth Confirm email ON/OFF · Redirect allowlist 현재 목록.
2. 운영 `IDENTITY_GATE_ENABLED` 값 · NICE 표준창 authUrl 호스트(정확 도메인).
3. NICE 복귀 방식이 GET 인지(SameSite=Lax 쿠키 전달) — `svc_types ["M"], method_type GET` 발급값 실측.
4. `mentor_profiles.verification_status` 값 집합(`pending/approved/verified/active/rejected/resubmit_required` 여부) — 학생증 덮어쓰기 규칙에 필요.
5. 학생 가입 폼 `studentStatus` 입력 컨트롤 존재 여부(Phase 1 미확인 승계).
6. `status='deleted'` 계정의 auth soft-delete 상태(로그인 가능 여부).
7. Storage 업로드 시 `storage.objects.owner_id` 채움 여부(앱 SDK).
8. 앱표면 `/api/identity/*` 호출 중 쿠키 회전 발생 여부(HttpOnly 속성 유지).
9. iOS PrivacyInfo 수집 유형 분류(이름·생년월일·학교).
10. `consent_version` 정본(법무 확정값) — 가입 트리거·마케팅 RPC 통일.
