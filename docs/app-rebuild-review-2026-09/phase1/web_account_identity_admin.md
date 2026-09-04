# 웹 계정·본인인증·관리자 콘솔 인벤토리 (Phase 1 리딩 리포트)

- 대상 저장소: 웹 `/home/user/ssambership_web` (Next.js 16 + Supabase), 기존 앱 `/home/user/ssambership-app` (Flutter, 같은 Supabase)
- 범위: 계정(가입·로그인·비밀번호·본인인증·보호자 동의·온보딩·탈퇴·상태) + 관리자 콘솔 인벤토리. UI/디자인 제외. 프론트 구조·백엔드(RPC/RLS/Storage/Realtime)·DB 관점만.
- 표기 규칙: 모든 사실은 `파일:행` 근거. 코드로 확인하지 못한 것은 **(확인 필요)**.
- 약어: SR = `createServiceRoleClient()` (`lib/supabase/admin.ts:12-23`, `SUPABASE_SERVICE_ROLE_KEY`, `server-only`). 세션 클라이언트 = `lib/supabase/server.ts`의 `createClient()`(쿠키 세션, anon 키).

---

## §1 계정 라우트별 기능 표

공통 표 형식: 라우트 | 목적 | 역할 | 사용자 액션(읽기/쓰기) | 서버 표면(RPC 시그니처 / 테이블·뷰 / SR 사용 / API route) | 결제 접촉 | 플래그·게이트 | 앱 이식 메모

| 라우트 | 목적 | 역할 | 사용자 액션 | 서버 표면 | 결제 접촉 | 플래그·게이트 | 앱 이식 메모 |
|---|---|---|---|---|---|---|---|
| `/login` (`app/login/page.tsx`) | 학생·멘토 듀얼 로그인 카드(역할 선택) | 비로그인 | 읽기 없음 / 쓰기 = 로그인 | 서버 컴포넌트가 `getServerUserWithProfile()`로 이미 로그인이면 `resolvePostLoginPath(next, role)`로 redirect (`app/login/page.tsx:17-20`). 폼 자체는 클라이언트 `RoleLoginForm` (아래) | 없음 | 없음 | 앱은 역할 선택 없이 단일 이메일 로그인 → 로그인 후 `users.role`로 분기하면 동일 결과 |
| `/login/student`, `/login/mentor` (`app/login/{student,mentor}/page.tsx`) | 역할 전용 로그인 | 비로그인 | 쓰기 = `supabase.auth.signInWithPassword` (브라우저, `components/auth/RoleLoginForm.tsx:97`) → `getUserProfileById(users select)` (`:125`) → 역할 불일치 시 `signOut` + 안내 (`:162-181`) → `window.location.assign(resolvePostLoginPath)` (`:211`) | 서버 액션 없음 · SR 없음 · `public.users` SELECT(RLS `users_select_own`, `supabase/sql/001_initial_auth_profile.sql:195-197`) | 없음 | 이메일 인증 여부는 클라이언트에서 재검사하지 않음(`RoleLoginForm.tsx:109-111`, Supabase가 `Email not confirmed`로 실패시키는 환경에만 의존) | 앱 `AuthService.signInWithPassword` (`ssambership-app/lib/core/auth/auth_service.dart:304-320`)와 동일 API. 역할 불일치 거부 로직만 웹 고유 |
| `/signup` (`app/signup/page.tsx`, `"use client"`) | 학생/멘토 3단계 가입 | 비로그인 | 쓰기 = `supabase.auth.signUp({email,password, options:{data: meta, emailRedirectTo: origin}})` (`:335-339`) → 세션 있으면 `syncAfterSignUpWithSession` (users 행 **검증만**, 직접 쓰기 0 — `lib/auth/syncAfterSignUpSession.ts:31-54`) → 멘토 학생증은 서버 액션 `uploadMentorStudentIdAfterSignUpAction` (`:419`, `:444`) → 세션 없으면 `/login/{role}?message=signup-check-email` (`:454-461`) | DB 트리거 `on_auth_user_created` → `handle_new_auth_user()` (SECURITY DEFINER) + `zz_on_auth_user_created_consent_records` → `handle_new_auth_user_consent_records()` · 학생증 액션은 **SR** (`lib/auth/mentorSignupStudentIdAction.ts:3,66`) | 없음 | 만 14세 미만도 가입 허용(`:292-295`, 동의는 사후 NICE 체인) | 가입 자체(`auth.signUp` + 메타 키)는 앱이 직접 가능. 학생증 저장만 서버 경로 필요(§6) |
| `/forgot-password` (`app/forgot-password/page.tsx`) | 재설정 메일 발송 | 비로그인 | 쓰기 = 서버 액션 `requestPasswordResetAction(formData)` (`lib/auth/passwordResetActions.ts:21-48`) | `supabase.auth.resetPasswordForEmail(email, { redirectTo: `${NEXT_PUBLIC_SITE_URL or host}/auth/update-password` })` (`:36-38`) · 세션 클라이언트 · SR 없음 · 오류는 코드(`?error=empty_email|missing_site_url|reset_failed`)로만 반사 (`:24,33,44`) | 없음 | 없음 | 앱은 `auth.resetPasswordForEmail` 직접 호출 가능. `redirectTo`는 Supabase Redirect allowlist 등록 필요(주석 `:19`) |
| `/auth/update-password` (`app/auth/update-password/page.tsx`) | 재설정 링크 세션에서 새 비밀번호 | 재설정(recovery) 세션 | 쓰기 = `supabase.auth.updateUser({ password })` (`components/auth/UpdatePasswordClient.tsx:30`) → `users.role` 조회로 역할별 로그인 경로 결정 (`:43-54`) → `signOut` (`:59`) → 이동 | 클라이언트 전용 · SR 없음 · 최소 8자 (`:19`) | 없음 | 없음 | 앱은 딥링크로 recovery 세션을 받으면 `updateUser` 직접 가능, 아니면 웹 페이지 위임 |
| `/logout` (`app/logout/route.ts`) | 로그아웃 | 로그인 | POST 전용(GET 미export → 405, `:4-6`) | `handleLogoutPost` → `supabase.auth.signOut()` → 303 `/` (`lib/auth/logoutRoute.ts:16-31`) · 실패 시 `/?logout=error` | 없음 | 없음 | 앱은 `client.auth.signOut()` (`auth_service.dart:330-342`) — WebView 쿠키 정리 `WebSessionHygiene.clear()`까지 이미 있음 |
| `/onboarding/verify` (`app/onboarding/verify/page.tsx`) | 본인(self) NICE 인증 온보딩 | 학생·멘토(관리자는 `/admin`으로, `:35-37`) | 읽기 = 서버가 `getIdentityOnboardingState(admin, uid)` (`:39-40`) → verified면 홈, guardian_required면 `/onboarding/guardian` (`:41-46`) | **SR** (`createServiceRoleClient`, `:8,39`) · `identity_verifications`·`users.identity_verified_at` 판독 및 부분실패 자가치유 UPDATE (`lib/identity/service.ts:645-707`) | 없음 | 플로우 자체는 플래그 무관 상시 활성 (`lib/identity/identityGateFlag.ts:7-8`) | 앱 직접 구현 불가(테이블 SR 전용) → §3 |
| `/onboarding/guardian` (`app/onboarding/guardian/page.tsx`) | 보호자(법정대리인) NICE 인증 | 학생·멘토 | 위와 동일, self_required면 `/onboarding/verify`로 (`:45-47`) | **SR** (`:8,40`) | 없음 | 상동 | 상동 |
| `POST /api/identity/start` (`app/api/identity/start/route.ts`) | NICE 인증 URL 발급 + pending 행 | 로그인 학생·멘토만 (`:23-41`) | 쓰기: body `{kind:"self"|"guardian"}` (`:52-58`) → `startIdentityVerification(admin,{userId,kind,appUrl})` (`:60-62`) → 응답 `{ok, vid, authUrl}` + httpOnly 쿠키 `nice_identity_vid` (path `/api/identity`, 30분, `:71-77`) | **SR** · `nice_auth_tokens` 캐시 · `identity_verifications` INSERT · 외부 NICE API(Gabia 프록시 `NICE_API_BASE`) | 없음 | 스로틀 10분 5회 (`lib/identity/service.ts:58-60`) | 쿠키 세션 기반(`getServerUserWithProfile`) → 앱은 세션 부트스트랩 또는 Bearer 수용 API 필요 |
| `GET/POST /api/identity/return` (`app/api/identity/return/route.ts`) | NICE 표준창 복귀·결과 확정 | 인증 창 세션 = 행 소유자여야 함 (`:153-171`) | `web_transaction_id`(query/body) + `vid`(query 또는 쿠키) → pending 30분 만료 처리 → CAS `pending→processing` → `completeIdentityVerification` → 결과 HTML(postMessage `{type:"nice-identity",status,code}` → opener, 없으면 `/onboarding/verify?status=&code=`) (`:50-104`, `:173-213`) | **SR** · NICE `auth/result` · AES-GCM 복호 · `identity_verifications`/`users`/`user_consent_records` UPDATE/UPSERT | 없음 | 없음 | NICE 복귀 URL은 웹 도메인(`ssambership.com`/`www`, `start/route.ts:14-16`)이어야 함 → 앱은 WebView 위임이 현실적(§3) |
| `/account/delete` (`app/(student)/account/delete/page.tsx`) | 회원 탈퇴 요청·취소 | 학생·멘토(관리자 → `/admin`, `:26`) | 읽기 = 사전조건·잔액·활성 job / 쓰기 = `requestAccountDeletion`, `cancelAccountDeletion` | 페이지: **SR** `checkAccountDeletionPreconditions` (`:29-30`) + `account_deletion_jobs` SELECT (`:41-48`) · 액션: 비밀번호 재인증(일회용 bare client `signInWithPassword`, `lib/account/accountDeletionActions.ts:62-68`) → **SR** `rpc("account_deletion_request_consented",{p_user_id,p_cancelable_minutes:30,p_dry_run:false,p_forfeit_consent,p_acknowledged_balance_cents})` (`:81-87`) · 취소 **SR** `rpc("account_deletion_cancel",{p_user_id})` (`:109`) | 상태 읽기(지갑 잔액 `cash_wallets.balance_cents`, `lib/account/accountDeletionPreconditions.ts:176-183`) | `NEXT_PUBLIC_FEATURE_ACCOUNT_DELETION` 기본 ON(off/0/false/no로 킬, `lib/shell/featureFlags.ts:17-22`) · identity 게이트 **예외 경로** (`app/(student)/layout.tsx:64-68`) | 앱은 self v2 RPC로 이미 자체 구현(§4). 웹 고유 관문(비밀번호 재인증·사전조건 5종)은 앱에 없음 |
| `/admin/login` (`app/(admin)/admin/login/page.tsx`) | 관리자 전용 로그인(2단계 골격) | 관리자 | 서버 액션 `adminEmailLoginAction` (`lib/auth/adminLoginActions.ts:17-51`): `signInWithPassword` → `email_confirmed_at` 필수 (`:33-36`) → `users.role==='admin'` 아니면 signOut (`:38-42`) → `mfa.getAuthenticatorAssuranceLevel()` nextLevel aal2면 코드 단계 (`:45-48`, 검증은 PR-12b 미구현 `lib/auth/adminLoginConsole.ts:7-10`) | 세션 클라이언트 · SR 없음 | 없음 | `(admin)/layout.tsx`에서 `/admin/login`만 가드 제외 (`app/(admin)/layout.tsx:9-13`) | 앱은 관리자 차단(`auth_service.dart:102-103`) |
| `POST /api/app-session/bootstrap` (`app/api/app-session/bootstrap/route.ts`) | 앱 → 웹 WebView 세션 부트스트랩 | 앱 로그인 멘토만 | body `{access_token, refresh_token, target}`; target enum = `shortform_create` 하나 (`lib/appSession/appSessionBootstrapCore.ts:17-18`) | `createServerClient.setSession` → `getUser` → `assertAppSurfaceAccountActiveStrict` → `strictMentorRoleDecision`(멘토 아니면 `mentor_only`) (`:101-119`) · SR 없음 | 없음 | 계정 strict 게이트(fail-closed) | 본인인증·탈퇴 등을 WebView로 위임하려면 이 라우트에 학생 허용 + 새 target 추가가 필요(§3, §6) |
| `GET/POST /api/cron/account-deletion` (`app/api/cron/account-deletion/route.ts`) | 탈퇴 saga 워커 | 내부(`CRON_SECRET`) | — | **SR** · `account_deletion_claim/reclaim_expired` 등 service_role 전용 RPC · env `ACCOUNT_DELETION_WORKER_ENABLED`, `ACCOUNT_DELETION_SCHEDULED_REAL_RUN` (`:29-36`) | 잔액 몰수 원장 append(`account_deletion_forfeit_and_anonymize`) | 킬스위치 기본 OFF(dry-run) | 앱 무관(서버 내부) |

보조 라우트: `/mentor/verification` (`app/(mentor)/mentor/verification/page.tsx`) — 학생증 사후 제출 `submitMentorStudentIdImageAction` (**SR**, `lib/mentor/mentorStudentIdActions.ts:6,29-30`) 및 학교 증빙 제출 `submitMentorSchoolVerificationAction` (세션 클라이언트, `lib/mentor/mentorSchoolVerificationActions.ts:5,26`). `lib/validations/index.ts`는 한 줄 주석(`// 추후 zod 추가 예정`)뿐인 빈 모듈(`:1`).

---

## §2 회원가입 상세

### 2-1 폼 필드·검증 (`lib/auth/signupValidation.ts`)

| 역할 | 필드 | 검증 |
|---|---|---|
| 공통 | `email`, `password`, `passwordConfirm`, `termsAgree`, `privacyAgree`, `marketingAgree`(선택) | 이메일 정규식 (`:26`), 비밀번호 ≥ 8자 `SIGNUP_PASSWORD_MIN_LENGTH` (`:29`), 확인 일치 (`:42`, `:71`), 필수 약관 2종 (`:55-57`, `:93-95`) |
| 학생 (`StudentSignupFormValues`, `components/auth/StudentSignupForm.tsx:3-9`) | `fullName`(폼 값 존재하나 실제 메타는 nickname을 full_name에도 넣음 — `app/signup/page.tsx:302,308-309`), `nickname`(필수 `:52-54`), `gradeLevel`(자유 텍스트, placeholder "예: 고1, 고2, 고3, 재수" `StudentSignupForm.tsx:119`), `studentStatus`(값 타입에 있으나 입력 컨트롤 확인 못함 — **(확인 필요)**), `birthDate`(`type="date"` `:92`; 필수·형식·미래 금지 `signupValidation.ts:45-51`, `lib/auth/minorAgeGate.ts:11-25,43-50`) | — |
| 멘토 (`MentorSignupFormValues`, `components/auth/MentorSignupForm.tsx:6-14`) | `nickname`, `universityName`, `departmentName`, `teachingSubjectsCsv`, `highSchoolName`(모두 필수 `signupValidation.ts:75-89`), `introLine`(선택), `studentIdFile`(필수 `:90-92`; `.jpg/.jpeg/.png/.pdf` `MentorSignupForm.tsx:246`, 최대 20MB `lib/storage/studentIdImageStorage.ts:6-8`) | 매직바이트 검증 `validateJpgPngPdfMagicBytes` (`lib/auth/mentorSignupStudentIdAction.ts:99`) |

### 2-2 auth 메타데이터 키 (`lib/auth/buildSignupUserMetadata.ts:29-53`) — DB 트리거와 키를 맞춘 계약

`app_role`, `full_name`, `nickname`, `grade_level`, `student_status`, `birth_date`, `terms_agreed`, `privacy_agreed`, `marketing_agreed`("true"/"false" 문자열), `university_name`, `department_name`, `teaching_subjects_csv`, `high_school_name`, `intro_line`, `is_minor`, `guardian_consent`, `consent_version`, `guardian_ref`, `age_gate_checked_at`, `guardian_verification_method`.
웹 가입 시 값: `isMinor = role==='student' && isUnderMinimumSignupAge(birthDate)` (`app/signup/page.tsx:295`, 만 14세 KST 기준 `lib/auth/minorAgeGate.ts:3,52-55`), `guardianConsent=false`, `guardianConsentVersion='legal-placeholder-2026-06-20'` (`lib/auth/minorConsentPlaceholders.ts:2`), `guardianVerificationMethod='nice_guardian_chain_post_signup'` (`:27`).

### 2-3 생성되는 행 (모두 DB 트리거 — 클라이언트 직접 쓰기 0)

1. `auth.users` INSERT → 트리거 `on_auth_user_created` → `public.handle_new_auth_user()` (SECURITY DEFINER; 원본 `supabase/sql/001_initial_auth_profile.sql`, 최신 본문 `supabase/migrations/20260717044250_fix_xv01_signup_admin_provisioning.sql:13-`, 저장소 정합본 `supabase/sql/122_signup_role_no_admin.sql:15-`):
   - `public.users` upsert: `role` = `app_role` 중 `student|mentor`만(그 외·admin → `student`, `20260717044250:29-33`), `status='active'`, `full_name/nickname/email/grade_level/student_status/birth_date`, `terms_agreed_at/privacy_agreed_at = now()`(값 'true'일 때), `marketing_agreed` (`001:120-147`).
   - 멘토면 `public.mentor_profiles` upsert: `university_name/department_name/high_school_name`(빈 값은 `'(미입력)'`), `teaching_subjects`(CSV→text[]), `intro_line`, **`verification_status='pending'`**, `student_id_image_url=null` (`001:149-172`) + `verification_logs(log_type='mentor_verification', status='pending', memo='sign-up')` (`001:174-175`).
2. 트리거 `zz_on_auth_user_created_consent_records` → `handle_new_auth_user_consent_records()` (`supabase/sql/087_user_consent_records.sql:149-150`, 최신 본문 `supabase/migrations/20260829100300_tz_fix_consent_minor_age_kst.sql:25-107`):
   - `user_consent_records` 행: `terms`/`privacy`/`marketing`(각각 메타가 'true'일 때) — `consent_actor='user'`, `is_minor` = 메타 `is_minor` 또는 폴백 `(now() at time zone 'Asia/Seoul')::date < birth_date + 14y` (`:50-55`, KST 정정), `consent_version` 기본 `'legal-placeholder-2026-06-20'`, `source='signup'`, `metadata{role, birth_date, age_gate_checked_at, verification_method}`, `idempotency_key='signup:{uid}:{type}:{version}'` (`:64-92`).
   - `minor_guardian_consent` 행은 `is_minor && guardian_consent='true'`일 때만 (`:94-103`) — 웹은 `guardian_consent=false`를 보내므로 **가입 시점에는 생성되지 않고** NICE 보호자 체인이 기록한다(§3).
   - 테이블 정의: `user_consent_records(id, user_id, consent_type CHECK terms|privacy|marketing|minor_guardian_consent, consent_actor CHECK user|guardian, is_minor, guardian_consent, consent_version, guardian_ref, agreed_at, source, metadata, idempotency_key UNIQUE …)` (`087:14-`). RLS: authenticated는 본인 SELECT만(`ucr_select_own`), INSERT/UPDATE/DELETE 회수, service_role 전권 (`087:42-56`).
3. `public.users` 권한: RLS `users_select_own`/`users_insert_own`/`users_update_own` 정책은 존재(`001:195-208`)하나, 수렴 M1에서 **authenticated의 테이블 UPDATE/DELETE 권한 회수**, INSERT·SELECT는 유지 (`supabase/sql/20260803162257_security_identity_profile_lockdown.sql:92-93`, 자가검증 `:338-348`). 보호 컬럼 트리거 `users_protected_columns_guard`(id/role/status/suspended_until/status_reason/status_changed_*/terms·privacy_agreed_at/marketing_agreed/created_at, `:100-138`), role 승격 가드 `enforce_users_role_guard`(`supabase/sql/119_users_role_guard.sql`) 및 INSERT 가드 `enforce_users_role_insert_guard`(role='admin' 직접 INSERT 차단, `20260717044250`) 존재. `users.status` CHECK `active|suspended|banned|deleted` (`20260803162257:143-146`).
4. `mentor_profiles`: anon/authenticated **테이블 쓰기 전면 회수, SELECT만** (`supabase/migrations/20260731135324_20260730195147_revoke_mentor_profiles_write.sql:4-10`). 셀프 수정은 `api_web_v1.mentor_profile_update_self`(F7) RPC 경유(헤더 `:15-17`; 함수 본문은 이번 리딩 범위 밖 — **(확인 필요)**).

### 2-4 가입 직후 상태

- `users.status='active'`, `users.identity_verified_at=NULL`(NICE 미인증; 컬럼 `20260820100200:80`), 학생: 바로 이용(단 identity 게이트 ON이면 `/onboarding/verify`로 리다이렉트).
- 멘토: `mentor_profiles.verification_status='pending'` → 관리자 승인 전까지 활동 차단(`lib/mentor/mentorVerificationGate.ts:4-9,35-40`: `approved|verified|active`만 허용). 가입 완료 화면은 `/mentor/profile/edit` 유도 (`app/signup/page.tsx:521-528`).

### 2-5 이메일 인증 여부

- 코드는 두 경우를 모두 처리: `signUp` 결과에 `session`이 있으면 즉시 완료(`app/signup/page.tsx:360-431`), 없으면 "메일 확인" 안내로 로그인 페이지 이동(`:433-464`). 로그인 폼은 `email_confirmed_at`을 재검사하지 않음(`RoleLoginForm.tsx:109-111`); 관리자 로그인만 필수(`adminLoginActions.ts:33`).
- 로컬 `supabase/config.toml`은 `[auth.email] enable_confirmations = false` (`:226`), `enable_signup = true` (`:176,221`), `enable_anonymous_sign_ins = false` (`:178`). **운영 프로젝트의 Confirm email 설정은 코드로 확인 불가 (확인 필요)**.

### 2-6 소셜 로그인

- `signInWithOAuth|signInWithIdToken|provider: google/kakao/apple/naver` grep 0건(app/lib/components). 이메일+비밀번호 단일. 앱도 `signUp(|signInWithOAuth|signInAnonymously` 0건.

### 2-7 역할별 로그인 분기·리다이렉트 (`lib/auth/getPostLoginPath.ts`)

- `safeInternalNextPath`: 같은 오리진 상대 경로만 (`:6-17`).
- `getPostLoginPath(role)`: student `/mypage`, mentor `/mentor/mypage`, admin `/admin` (`:26-31`).
- `resolvePostLoginPath(next, role)`: `/login*`·`/signup*`은 홈으로; 학생은 `/mentor*`·`/admin*` 거부; 멘토는 `/admin*`·학생 전용 경로(`/home`, `/mypage`, `/subscribe`, `/question-room`, `/wallet`, `/cash*`, `/support/*`) 거부; 관리자는 `/admin*`·`/notifications*`만 허용 (`:36-88`).
- 가입 성공 기본 목적지 `getSignUpSuccessPath`: 멘토 `/mentor/profile/edit`, 학생 `/mypage` (`:95-104`).
- 가드 `requireRole(role)` (`lib/auth/routeGuard.ts:41-59`): 비로그인 → 역할별 로그인 경로(`/login/student`, `/login/mentor`, `/admin/login`) + `next`(미들웨어가 `x-return-to`/`x-pathname` 헤더로 전달, `middleware.ts:7-16`).

### 2-8 비밀번호 재설정·로그아웃

- 재설정: `requestPasswordResetAction` → `resetPasswordForEmail(email, {redirectTo: origin + "/auth/update-password"})` (`lib/auth/passwordResetActions.ts:36-38`) → `/auth/update-password`에서 `updateUser({password})` → 역할별 로그인으로 (`UpdatePasswordClient.tsx:30-67`).
- 로그아웃: `POST /logout` → `signOut` → 303 `/` (`lib/auth/logoutRoute.ts:18-31`). 온보딩 페이지도 `<form action="/logout" method="post">` 사용 (`app/onboarding/verify/page.tsx:89-93`).

---

## §3 본인인증(NICE PASS)·보호자 동의

### 3-1 플래그·게이트

- `IDENTITY_GATE_ENABLED` (서버 env, 정확히 `'true'`일 때만 ON, `lib/identity/identityGateFlag.ts:12-14`). `needsIdentityOnboarding(profile)` = 플래그 ON && profile && `identity_verified_at == null` (`:20-24`). `.env.example:46`에 빈 값. S-C 보고서는 "기본 OFF → 실측 후 ON" (`docs/sprint-pay/S-C-REPORT.md:18,97-98`) — **운영 ON 여부 (확인 필요)**.
- 레이아웃 게이트(ON 시 `/onboarding/verify`로 redirect): `app/(student)/layout.tsx:41,66,83,99` (게스트 열람 IQ 목록·`/settings/blocks`·지갑 충전·일반 학생 경로), `app/(mentor)/layout.tsx:17`. **예외: `/account/delete`** (`app/(student)/layout.tsx:64-68` — 탈퇴권 보장).
- 머니패스 서버 가드 `requireVerifiedIdentity(userId)` (`lib/identity/identityGate.ts:30-54`; SR로 `users.identity_verified_at` 판독, 판독 실패 fail-closed):
  - `app/api/subscribe/checkout/route.ts:72-74` → `identityRequiredJsonResponse()` = HTTP 403 `{ok:false,error:"IDENTITY_REQUIRED",message:"IDENTITY_REQUIRED: 본인인증 후 이용할 수 있어요. 웹에서 본인인증을 완료해 주세요."}` (`identityGate.ts:17-20,57-62`).
  - `lib/individualQuestion/individualQuestionActions.ts:124,220`, `lib/customRequest/customRequestApplicationActions.ts:47`, `lib/customRequest/customRequestOrderActions.ts:35` (서버 액션 → `/onboarding/verify` redirect, `S-C-REPORT.md:91-94`).
  - DB/RPC 레벨 가드는 **의도적으로 0** (`identityGate.ts:6-8`; 앱 재배포 없음 전제). 즉 앱이 직접 쓰는 RPC/뷰 경로는 identity 게이트에 걸리지 않는다.
- 기존 앱에는 `IDENTITY_REQUIRED` 처리 코드가 없다(`ssambership-app/lib` grep 0건) — 웹 주석의 "앱 에러 매퍼 선두 토큰 계약"은 현재 앱 코드에 미구현 **(확인 필요: 다른 브랜치 여부)**.

### 3-2 흐름 (`lib/identity/service.ts`, `lib/nice/client.ts`, `lib/nice/crypto.ts`)

1. **start** `startIdentityVerification(admin, {userId, kind, appUrl?})` (`service.ts:160-280`):
   - 전이 규칙: `users.identity_verified_at` 있으면 `ALREADY_VERIFIED`(403); self는 verified self 행 없을 때만; guardian은 verified self 존재 + self 생년월일이 만 14세 미만(KST) + verified guardian 없음일 때만 (`:184-208`).
   - 스로틀: 최근 10분 내 행 생성 5건 (`:210-228`).
   - `return_url = {appUrl}/api/identity/return?vid={uuid}`, `close_url = …&close=1`, 250byte 제한 (`:238-243`). appUrl은 요청 호스트 허용목록(ssambership.com/www) 우선, 폴백 `APP_URL`→`NEXT_PUBLIC_SITE_URL` (`start/route.ts:14-16,61`, `service.ts:77-83`).
   - NICE: `requestNiceAuthUrl` → `POST {NICE_API_BASE}/ido/intc/v1.0/auth/url` (svc_types ["M"], method_type GET) with Bearer 기관토큰 (`client.ts:230-263`); 토큰은 `nice_auth_tokens` 캐시(만료 5분 버퍼, 1003/1004면 폐기·재발급 1회, `:184-198,246-251`).
   - `identity_verifications` INSERT `{id:vid, user_id, kind, status:'pending', request_no, transaction_id, token_id}` (`service.ts:265-273`).
2. **return** (`app/api/identity/return/route.ts:121-214`): `web_transaction_id` 필수(없고 `close=1`이면 CLOSED) → `vid`(query 또는 쿠키) → **웹 세션 사용자 == 행 소유자** 검증 → pending 30분 초과 `expired/PENDING_TIMEOUT` → CAS `pending→processing`(실패 시 현재 status만 반환, result 재호출 금지: NICE 3033 1회성) → `completeIdentityVerification`:
   - `requestNiceAuthResult`(`auth/result`, 행에 바인딩된 토큰 우선) → `deriveNiceSymmetricKeys(ticket, transaction_id, iterators)`(PBKDF2-SHA256 64B → base64url; symKey=[0:32], hmacKey=[48:80]) → `verifyNiceIntegrity`(HMAC-SHA256 timing-safe) → `decryptNiceResult`(AES-256-GCM, iv 16B, tag 16B) → `{name, birthdate(yyyymmdd), gender, national_info, ci, di, mobile_co, mobile_no}` (`crypto.ts:45-135`).
   - `finalizeSelf` (`service.ts:358-430`): `di_hash = base64url(HMAC-SHA256(di, IDENTITY_HASH_KEY))` (`lib/identity/identityCrypto.ts:54-62`) 로 **타 계정 verified self 중복 검사 → `DI_CONFLICT`**; 행 UPDATE(`status='verified'`, `verified_name`, `birthdate`, `gender`, `national_info`, `mobile_co`, `ci_enc/di_enc/mobile_no_enc` = `'v1:'+base64(iv‖cipher‖tag)` AES-256-GCM with `IDENTITY_DATA_KEY`, `di_hash`); `users` UPDATE `birth_date`, `full_name`(NICE 실명 덮어씀), **만 14세 이상일 때만 `identity_verified_at=now()`**, 미만이면 `GUARDIAN_REQUIRED`.
   - `finalizeGuardian` (`:458-530`): verified self 행+`di_hash` 필요(`GUARDIAN_NOT_APPLICABLE`) → 보호자 만 19세 이상(`GUARDIAN_NOT_ADULT`) → 보호자 DI ≠ 자녀 DI(`GUARDIAN_SELF`) → 행 verified → `user_consent_records` upsert `{consent_type:'minor_guardian_consent', consent_actor:'guardian', is_minor:true, guardian_consent:true, consent_version:'legal-placeholder-2026-06-20', guardian_ref: vid, source:'identity_verification', metadata:{verification_method:'nice_standard_m', verification_id}, idempotency_key: vid}` (`:433-455`) → `users.identity_verified_at=now()` (자녀 이름·생일은 덮지 않음).
3. **온보딩 상태 판정** `getIdentityOnboardingState` (`:645-707`): `verified` / `guardian_required` / `self_required`; verified 행은 있는데 users 미반영이면 멱등 재적용(자가치유).
4. **클라이언트 런처** `components/onboarding/IdentityVerificationLauncher.tsx`: 클릭 시 동기 `window.open('about:blank','authNiceWeb')` → `POST /api/identity/start` → `popup.location.replace(authUrl)`; 팝업 차단 시 동일창 (`:85-127`); `message` 이벤트는 `event.origin === window.location.origin`만 수용, verified면 `router.refresh()`로 서버 재판정 (`:54-83`). 결과 코드→문구 매핑은 `components/onboarding/identityResultMessages.ts`.

### 3-3 테이블·키·서버 전용 이유

| 객체 | 정의 | 접근 |
|---|---|---|
| `public.nice_auth_tokens(id, access_token, ticket, iterators, expires_at, created_at)` | `supabase/migrations/20260820100100_nice_auth_tokens.sql:22-29` | RLS on·정책 0·anon/authenticated 권한 0·service_role 전용 (`:34-36`); pg_cron `nice_auth_token_sweep_daily` 16:20 UTC (`:49-60`) |
| `public.identity_verifications(id, user_id FK users, request_no UNIQUE, transaction_id, token_id FK nice_auth_tokens, status CHECK pending|processing|verified|failed|expired, kind CHECK self|guardian DEFAULT 'self', verified_name, birthdate date, gender, national_info, mobile_co, ci_enc, di_enc, mobile_no_enc, di_hash, failure_code, verified_at, created_at, updated_at)` | `20260820100200_identity_verifications.sql:32-53`, `20260821100100_identity_verifications_kind_guardian.sql:38-51` | service_role 전용 (`20260820100200:65-67`); 부분 유니크 `identity_verifications_di_hash_verified_uniq (di_hash) WHERE status='verified' AND di_hash IS NOT NULL AND kind='self'` (`20260821100100:56-59`); 탈퇴 진행 유저 INSERT 차단 트리거 `adg_identity_verifications` (`20260820100200:75-77`); 탈퇴 시 `account_deletion_purge_identity_payment_artifacts(p_user_id)`가 전행 DELETE (`20260820100700:27-63`, service_role 전용) |
| `users.identity_verified_at timestamptz` | `20260820100200:80-83` | authenticated SELECT 범위에 포함(민감도 낮음 허용 결정, `:15-19`); UPDATE는 service_role 경로만 |
| 환경변수 | `NICE_CLIENT_ID`, `NICE_CLIENT_SECRET`, `NICE_API_BASE`(Gabia 고정IP 프록시, 그 외 도메인 직접 호출 금지 `client.ts:3-4`), `NICE_PROXY_KEY`, `IDENTITY_DATA_KEY`(32B base64), `IDENTITY_HASH_KEY`(≥16B utf8), `APP_URL` (`.env.example:30-46`, `lib/identity/encryption.ts:16-43`) | 전부 서버 전용·`server-only` 부착(`encryption.ts:1`, `service.ts:1`, `client.ts:1`); 클라 번들 0건 검증 (`S-C-REPORT.md:132`) |

서버 전용인 이유: (a) NICE 기관토큰·ticket이 복호화 키 재료이고 결과는 1회성(3033) — 토큰 캐시 테이블은 service_role 전용; (b) CI/DI/전화번호 평문은 어떤 컬럼·로그에도 두지 않고 AES 키(`IDENTITY_DATA_KEY`)와 HMAC 키(`IDENTITY_HASH_KEY`)는 서버 env; (c) `identity_verifications`·`users.identity_verified_at` 갱신이 service_role 경로로만 열려 있음 (`service.ts:3-6`).

### 3-4 나이 계산

- NICE 결과 `yyyymmdd` → KST 달력 기준 만나이 (`lib/identity/age.ts:12,41-60`): `isUnderFourteenKst` (임계 14, `:8,63-67`), `isAdultGuardianKst` (임계 19, `:10,70-74`), `isUnderFourteenFromIsoDateKst` (users.birth_date ISO용, `:80-83`). 판정 불가(null)는 fail-closed(보호자 체인으로, `service.ts:419-422`).
- 가입 시 만 14세 판정 `isUnderMinimumSignupAge` (`lib/auth/minorAgeGate.ts:3,52-55`, `kstTodayParts` 위임 `:27-31`).

### 3-5 앱에서 이 흐름을 재현하려면

**전제 사실**: (1) `/api/identity/start`·`/return` 모두 **쿠키 세션**(`getServerUserWithProfile` / `createClient().auth.getUser()`)으로 사용자를 식별한다 (`start/route.ts:23`, `return/route.ts:154-156`); (2) NICE `return_url`은 웹 도메인이어야 하며 복귀 요청에 같은 사용자의 세션 쿠키가 실려야 한다 (`start/route.ts:14-16`); (3) 인증 테이블·키·NICE 클라이언트는 전부 서버 전용이라 앱이 Supabase 클라이언트로 직접 수행할 수 없다; (4) 앱은 `users.identity_verified_at`을 SELECT로 읽을 수는 있다(`20260820100200:15-19`).

- **방식 A — WebView 위임(권장)**: 앱이 `/api/app-session/bootstrap`류로 웹 세션 쿠키를 만든 뒤 `/onboarding/verify`를 WebView로 연다. 현재 bootstrap은 **멘토 전용·target `shortform_create` 하나**이므로(`bootstrap/route.ts:117-119`, `appSessionBootstrapCore.ts:17-18`, `lib/appSession/appSurfacePaths.ts:8-16`), 학생 허용 + `identity_onboarding` target + 앱 WebView allowlist에 `/onboarding/*`·`/api/identity/*`·NICE 도메인 추가가 필요하다. NICE 표준창은 팝업(`window.open`) 또는 동일창 진행(`IdentityVerificationLauncher.tsx:110-115`) — WebView는 팝업을 막을 수 있으므로 동일창 경로가 정식 지원됨(`return/route.ts:21-22`)을 활용. 완료 판정은 WebView 종료 후 앱이 `users.identity_verified_at` 재조회.
- **방식 B — 앱 네이티브**: `POST /api/identity/start`를 Bearer(access_token) 수용으로 확장 + `authUrl`을 앱 브라우저(Custom Tab/ASWebAuthenticationSession)로 열고, `/api/identity/return`이 **세션 쿠키 없이도** vid 소유자를 검증할 수 있도록(예: start 시 발급한 서명 티켓을 return_url에 포함) 재설계 + 결과 조회용 self RPC/API 신설(현재 `identity_verifications`는 authenticated GRANT 0). 서버 변경 규모가 크고 NICE 복귀 URL 계약(250byte)도 고려해야 한다.
- 두 방식 모두 보호자 체인(guardian)은 같은 런처를 `kind:"guardian"`으로 호출하면 되며, 앱은 `GUARDIAN_REQUIRED` 코드 시 보호자 단계로 유도해야 한다.

---

## §4 계정 상태

### 4-1 웹 판정 규칙

| 함수 | 위치 | 규칙 |
|---|---|---|
| `effectiveAccountStatus(info)` → `active|suspended|banned` (표시용) | `lib/auth/accountStatus.ts:25-42` | `banned`→banned; `suspended`는 `suspended_until` 경과 시 active(lazy 해제); 그 외/미지 값→active |
| `assertAccountActive(supabase, userId)` (서버 액션 쓰기 가드, fail-closed) | `:194-210` → `assertAccountActiveCore` `:129-168` | `users(status, suspended_until)` 본인 행 + `rpc("account_deletion_status_self")`; 거부 reason: `banned`·`suspended`·`deleted`(status='deleted')·`status_unknown`(CHECK 밖)·`deletion_blocked`(write_blocked=true)·`row_missing`·`unverifiable`. NULL/'' status는 `active`로 정규화(뷰 `COALESCE` 정합, `:112-117`) |
| 앱 표면 strict 게이트 `strictAccountStatusDecision` / `strictDeletionDecision` | `lib/appSession/appSurfaceAccountGate.ts:44-82` | allowlist: `active` 또는 만료된 `suspended`만 통과; `suspended_until` 부재 = 유효 정지; NULL/미지 status 거부; deletion payload `ok===true && write_blocked===false`만 통과 |
| `resolveEffectiveAccountStatus` (P2-22, 순수) → `active|suspended|banned|deleted|deletion_in_progress|error` + `canLogin`·`retryable` | `lib/account/effectiveAccountStatus.ts:49-90` | 우선순위: (1) `deletionState ∈ {auth_soft_deleted, completed}` 또는 `status='deleted'` → deleted; (2) `{locked,purging,storage_purged,finalized}` → deletion_in_progress; (3) banned; (4) `roleResolved=false` → error(retryable); (5) suspended(`suspended_until` 미래 또는 파싱불가) / 만료→active |
| DB 정본 게이트 (셀프 프로필 RPC) | `supabase/sql/20260803162257_…lockdown.sql:189-203` | `banned`→`ACCOUNT_BANNED`; `suspended && (until null or future)`→`ACCOUNT_SUSPENDED`; not in (`active`,`suspended`)→`ACCOUNT_NOT_ACTIVE`; `account_deletion_write_blocked(uid)`→`ACCOUNT_DELETION_IN_PROGRESS` |

컬럼 정본: `users.status`(CHECK 4종), `suspended_until`, `status_reason`, `status_changed_at`, `status_changed_by` (`supabase/sql/102_account_status_management.sql:13-24`). 관리자 정지/차단은 SR로 `users` UPDATE + `admin_action_logs` (`lib/admin/accountStatusActions.ts:31-`, `lib/admin/accountStatusCore.ts:30-54`).

### 4-2 앱 `AccessState`/`AccountStatusKind`와의 대응

앱 정본: `AccountStatusKind {active, suspended, banned, deletionPending, deletionLocked, deleted, fetchFailed}` (`ssambership-app/lib/core/auth/account_status.dart:14-37`), `AccessState {loading, loggedOut, guest, full, blocked}` (`lib/core/auth/auth_service.dart:22`), `computeAccess` (`:88-112`): 조회 실패·role 실패 → blocked(재시도 가능), `allowsAppUse`(active|deletionPending)만 통과, **admin → blocked**, role 불명 → blocked. 앱 판정 입력: `users(status, suspended_until)` 1회 SELECT(`:221-225`) + `rpc('account_deletion_write_blocked',{p_user_id})` + `rpc('account_deletion_status_self')` (`account_status.dart:149-168, 242-285`).

| 웹 (`effectiveAccountStatus.ts`) | 앱 `AccountStatusKind` | 앱 `AccessState` | 비고 |
|---|---|---|---|
| `active` | `active` | `full` | 동일 |
| `active` + job `pending` (웹은 job pending을 별도 표시하지 않고 write-block 아님) | `deletionPending` | `full` (취소 배너 `DeletionNoticeController`) | 앱만 세분 |
| `suspended` | `suspended` (`suspended_until` null=무기한) | `blocked` | 동일 규칙(`account_status.dart:293-306`) |
| `banned` | `banned` | `blocked` | 동일 |
| `deletion_in_progress` (locked~finalized) | `deletionLocked` (locked~auth_soft_deleted) | `blocked` | 앱은 `auth_soft_deleted`도 locked로, 웹은 deleted로 분류 |
| `deleted` (auth_soft_deleted/completed/status deleted) | `deleted` (completed) | `blocked` | 앱은 `status='deleted'` 문자열을 별도 처리하지 않음(그 외 값 active 취급 `:287-289`) — CHECK 도입 후 `deleted` 계정이 auth soft-delete로 로그인 불가이므로 실무상 무해 **(확인 필요)** |
| `error` (role 미해결, retryable) | `fetchFailed` | `blocked` + 재시도 | 동일 의도 |
| 관리자 | — | `blocked` (`auth_service.dart:102-103`) | 웹은 `/admin` |

### 4-3 탈퇴 RPC — 앱이 쓰는 것 vs 웹 전용

| RPC | 시그니처 | ACL | 사용처 |
|---|---|---|---|
| `account_deletion_request_self_v2()` | 파라미터 없음 → `{ok, existing, job_id, state, cancelable_until, dry_run}` 또는 `{ok:false, code:'FORFEIT_CONSENT_REQUIRED', balance_cents}` | authenticated·service_role (`supabase/migrations/20260803170916_…convergence.sql:781-782`) | 앱 `account_deletion_repository.dart:201-204` |
| `account_deletion_request_self_consented_v2(p_acknowledged_balance_cents bigint)` | 위와 동일 성공형 / `FORFEIT_CONSENT_STALE {acknowledged_balance_cents, current_balance_cents}` | authenticated·service_role (`:801-802`) | 앱 `:217-223` |
| `account_deletion_cancel_self()` | `{ok}` / `{ok:false, code: NOT_FOUND|NOT_CANCELABLE|CANCEL_WINDOW_PASSED}` | authenticated·service_role (`supabase/sql/161_…self_rpc.sql:131`) | 앱 `:319-322` |
| `account_deletion_status_self()` | `{ok, exists, state, cancelable_until, write_blocked, can_cancel}` (활성 job 우선, 없으면 최신 이력) | authenticated·service_role (`supabase/sql/175_…job_history.sql:242-286`) | 앱(부팅 게이트·배너) + 웹 `assertAccountActive` (`accountStatus.ts:206`) |
| `account_deletion_write_blocked(p_user_id uuid)` | boolean | authenticated·service_role (`20260701000000_pre_ledger_baseline.sql:19785`) | 앱 부팅 게이트 (`account_status.dart:151-154`) |
| 구 `account_deletion_request_self(int,bool)` / `_consented(int,bool,bigint)` | — | **authenticated REVOKE** (`20260803170916:804-805`) | 미사용 |
| `account_deletion_request_consented(p_user_id uuid, p_cancelable_minutes int=30, p_dry_run bool=true, p_forfeit_consent bool=false, p_acknowledged_balance_cents bigint=null)` | `{ok, existing, job_id, state, forfeit_consent_at, consented_balance_cents}` / `ALREADY_COMPLETED` / `FORFEIT_CONSENT_REQUIRED` / `FORFEIT_CONSENT_STALE` | **service_role 전용** | 웹 서버 액션 (`lib/account/accountDeletionActions.ts:81-87`); v2 self 래퍼가 내부에서 `(v_uid, 30, false, …)`로 호출 (`20260803170916:774-775, 795-796`) |
| `account_deletion_cancel(p_user_id uuid)` | `{ok}`/코드 | service_role 전용 (`baseline:19944`) | 웹 (`accountDeletionActions.ts:109`); `cancel_self`가 위임 (`baseline:21187-21205`) |
| `account_deletion_purge_identity_payment_artifacts(p_user_id)` 등 worker 계열(`claim`, `reclaim_expired`, `begin_locked`, `forfeit_and_anonymize`, `revoke_sessions`, `advance`, `record_error`) | — | service_role 전용 | cron 워커 |

**취소 유예**: DB 정본은 **30일** — `account_deletion_request_consented`가 `p_cancelable_minutes`를 무시하고 `cancelable_until = now() + interval '30 days'`로 고정 (`supabase/migrations/20260808092007_account_deletion_server_cancel_window_30d.sql:56, 69-70`; 기존 pending 행도 30일로 일괄 갱신 `:72-76`). 반면 웹 코드·문구(`CANCELABLE_MINUTES = 30` `accountDeletionActions.ts:39`, "30분의 취소 창" `account/delete/page.tsx:92`, `AccountDeletionForm.tsx:80`)와 앱 주석("취소창 30분 서버 고정" `account_deletion_repository.dart:12-13`)은 구 30분을 인용 — 서버값 `cancelable_until`을 표시하는 앱 동작(`account_delete_screen.dart:84-86,253-255`)이 정합. **문구 정정 필요**.

**웹 고유 관문(앱에 없음)**: 비밀번호 재인증(`accountDeletionActions.ts:61-68`), `understood` 체크(`:54-56`), 사전조건 5종 — 학생: 활성 구독(`active|past_due`) 0·진행 IQ(`open|assigned|claimed|answered`) 0·비터미널 맞춤의뢰 주문 0·분쟁(`open|under_review`) 0; 멘토: 구독자 0·진행 IQ·주문·분쟁 0 (`lib/account/accountDeletionPreconditions.ts:52-54, 76-187`, SR 집계·TS 전용, DB RPC에는 없음). 앱은 잔액 동의만 서버가 강제한다.

---

## §5 관리자 콘솔 인벤토리

### 5-1 공통 구조

- 가드: `app/(admin)/layout.tsx:8-15` (`/admin/login` 제외 `requireRole("admin")`) + `app/(admin)/admin/(console)/layout.tsx:5-8` (이중). `requireRole("admin")`은 `public.users.role`만 신뢰 (`lib/auth/routeGuard.ts:49-54`). 서버 액션도 첫 줄 `requireRole("admin")` (CLAUDE.md 규칙; `lib/admin` 31파일).
- `lib/admin/` 106 엔트리(105 파일 + `__contract__/`). `createServiceRoleClient` import 파일 36개(계약 테스트 5개 제외 **31개 실코드**); `"use server"` 액션 파일 21개. 쓰기 클라이언트는 `resolveAdminWriteClient`로 **service_role 실패 시 중단(폴백 금지)** (`lib/admin/adminWriteClient.ts:24-43`; 이유: `mentor_profiles`에 관리자 UPDATE 정책 없음 `:13-15`).
- 파일명 기준 기능군: 계정(`account*`, `adminActionLog`, `auditLog*`) · 멘토 승인/활동/학적/학교등급(`mentorApproval*`, `mentorActivity*`, `mentorAcademicRecord*`, `mentorSchool*`, `mentorCap*`, `mentorIdentityReview`, `schoolClassification*`) · 신고/분쟁/커뮤니티/리뷰(`contentReport*`, `adminReport*`, `adminDispute*`, `dispute*`, `communityModeration*`, `adminCommunityContent*`, `adminReview*`, `review*`) · 정산/환불/충전(`settlement*`, `refund*`, `topup*`, `adminTopupPackage*`) · 공지(`adminNotices*`, `noticeConsole`) · 질문 드릴다운/내보내기(`questionDrilldown*`, `questionExport*`) · 대시보드/SLA/설정(`adminDashboard*`, `sla*`, `settings*`) · 공용(`adminDataTable`, `adminListParams`, `adminStatusDictionary`, `adminConfirmPolicy`, `adminDisplayError`, `bulkActions`, `documentViewerModel`).
- 관리자 JWT(authenticated + `is_admin()` 내부 게이트)로 호출 가능한 RPC: `approve_mentor_school_verification_admin(uuid, text, text, text, text, text)` (grant authenticated·service_role `supabase/migrations/20260903200100_…:239-242`, 내부 `is_admin()` → `NOT_ADMIN` `supabase/sql/193_…:123-131`; 웹은 세션 클라이언트로 호출 `lib/admin/mentorSchoolVerificationReviewActions.ts:139-141`), `admin_issue_user_warning(p_user_id uuid, p_reason text, p_severity text='normal')` (`20260803170916:666-749`, admin 세션 또는 service_role). `is_admin()` = `users.role='admin'` SECURITY DEFINER (`baseline:1395-1405`). `is_admin()` RLS가 있는 표: `admin_action_logs`(select/insert `supabase/sql/040:21-29`), `app_notices`/`promotion_campaigns`(031), `content_reports`(032), `reviews` 관리자 조회(033), `disputes`(004 `dispute_update_admin`), `verification_logs` 조회(035), `users_admin_select_all`(120), `mp_admin_select_all`(`adminWriteClient.ts:13-14`).
- service_role 전용 RPC(관리자 JWT 불가): `approve_refund_request_admin(uuid,uuid,text)`/`reject_refund_request_admin` (`baseline:17682-17683`), `run_scheduled_payout`·`pay_due_payouts_for_run`·`payout_reconciliation_report` (`lib/admin` rpc 호출 목록), `record_custom_order_dispute_split` (`supabase/sql/191_…` 헤더 ACL service_role 전용), 탈퇴 worker 계열.
- 단일 API route: `GET /api/admin/question-export` (`app/api/admin/question-export/route.ts:36-78`; 세션 admin 확인 → SR 읽기 → `admin_action_logs` 기록 → CSV 스트림).
- 네비 정본: `components/admin/adminConsoleNavConfig.ts:2-24` (대시보드·멘토 승인·계정 관리·탈퇴 요청·멘토 활동·학적변경 요청·등급 분류·콘텐츠 검수·커뮤니티 관리·리뷰 관리·맞춤의뢰 주문·신고·분쟁·충전·환불·정산·SLA·공지·감사 로그·시스템 설정).

### 5-2 페이지 인벤토리 (`app/(admin)/admin/(console)/**/page.tsx` 34개 + `/admin/login` 1개 = 35)

| 페이지 | 목적 | 읽기/쓰기 | SR 의존 | 관리자 JWT로 호출 가능한 RPC |
|---|---|---|---|---|
| `/admin/login` | 관리자 로그인(비밀번호 + MFA 판정 골격) | 쓰기(로그인) | 없음 | — |
| `/admin` (`page.tsx`) | `/admin/dashboard` redirect | — | — | — |
| `/admin/dashboard` | 오늘 할 일 8칸·현황·최근 활동(조회 전용) | 읽기 | 하위 조회 모듈(`adminDashboardQueries` → 각 화면 건수 함수, 대부분 SR) 경유 — 직접 import 없음 | — |
| `/admin/mentor-approval` | 멘토 승인 작업대(승인·반려·재제출·보류·Presence) | 읽기+쓰기 | 예: `mentorApprovalWorkbenchQueries`(SR), `mentorApprovalActions`(세션 시도 후 RLS 거부 시 SR 폴백 `mentorApprovalActions.ts:52-58`), `mentorProfileStatusTransition`(SR) | Presence는 Realtime `admin:*` 토픽(RLS 관리자만, CLAUDE.md DB-3) |
| `/admin/mentor-approvals`, `/admin/mentor-approvals/[id]`, `/admin/mentors` | 구 라우트 redirect(승인/계정 상세) | — | — | — |
| `/admin/users` | 계정 목록(역할·상태·본인인증 필터) + 차단/탈퇴 로그 | 읽기 | 예 (`accountListQueries`, `accountStatusQueries`) | — |
| `/admin/users/[id]` | 계정 상세(경고·정지·차단·정원 조정·역할별 탭·질문 드릴다운) | 읽기+쓰기 | 예 (`accountDetailQueries`·`accountStatusActions`·`mentorCapAdminActions`·`questionDrilldownQueries`) | `admin_issue_user_warning` (경고) |
| `/admin/deletions`, `/admin/deletions/[id]` | 탈퇴 saga 파이프라인 감시(조회 전용, 조치 없음) | 읽기 | 예 (`accountDeletionQueries`) | — |
| `/admin/mentor-activity` | 승인 멘토 활동(보류 확정·구제·유예 만료 정리) | 읽기+쓰기 | 예 (`mentorActivityQueries`, `mentorActivityAdminActions`) | — |
| `/admin/academic-record-changes` | 학적 변경 요청 심사 | 읽기+쓰기 | 쓰기 예 (`mentorAcademicRecordChangeReviewActions` SR — `mentor_profiles.university_name` 갱신) | — |
| `/admin/school-classifications` | 등급 분류(미분류 정정·분포·LIKE 규칙 표) | 읽기+쓰기 | 쓰기는 세션 RPC(`schoolClassificationActions` 세션, `mentorSchoolVerificationReviewActions` RPC 세션·문서 서명 URL은 SR) | `approve_mentor_school_verification_admin` |
| `/admin/moderation` (+`/admin/reports` redirect) | 콘텐츠 신고 큐 | 읽기 | 아니오(`contentReportQueueQueries` 세션·`content_reports` admin RLS) | — |
| `/admin/reports/[id]` | 신고 상세·증거·조치(콘텐츠 숨김/삭제·대상 계정 제재) | 읽기+쓰기 | 예 (페이지 SR `reports/[id]/page.tsx:8`, `adminReportActions` SR, 제재는 `accountStatusActions` SR) | `admin_issue_user_warning` |
| `/admin/community-content` | 글·숏폼·댓글 관리(숨김·소프트삭제·복원) | 읽기+쓰기 | 조회 세션(`adminCommunityContentQueries`), 액션 세션(`communityModerationActions.ts:82`) + `communityModerationCore` SR | (소프트삭제 컬럼 직접 UPDATE — RLS 관리자 정책 여부 **(확인 필요)**) |
| `/admin/reviews`, `/admin/reviews/[reviewId]` | 리뷰 목록·상세·조치(숨김/블라인드) | 읽기+쓰기 | 예 (`adminReviewQueries`, `adminReviewActions`) | `check_review_eligibility`, `get_mentor_review_stats`(조회) |
| `/admin/custom-request-orders` | 맞춤의뢰 주문 운영 목록 | 읽기 | 예 (페이지 직접 SR `custom-request-orders/page.tsx:15,50`) | — |
| `/admin/disputes`, `/admin/disputes/[id]` | 분쟁 큐·상세(에스크로 분배·제재·메모·납품물) | 읽기+쓰기 | 예 (페이지 SR `disputes/[id]/page.tsx:8`, `adminDisputeActions`·`adminDisputeSanctionActions` SR) | 분배 RPC `record_custom_order_dispute_split`은 service_role 전용 |
| `/admin/topups` | 무통장 충전 주문 현황(조회 전용) | 읽기 | 예 (`topupConsoleQueries`) | — |
| `/admin/refunds`, `/admin/refunds/[id]` (+`/admin/refunds-settlement` redirect) | 환불 큐·승인/거절 | 읽기+쓰기 | 예 (`refundConsoleQueries`, `refundActions` → `approve_refund_request_admin` service_role 전용) | — |
| `/admin/settlements` | 정산 미리보기·실행·지급 이력 | 읽기+쓰기 | 예 (`settlementConsoleQueries`, `settlementActions` → `run_scheduled_payout`, `pay_due_payouts_for_run` service_role 전용) | — |
| `/admin/sla` | SLA KPI·건별 기한(조회 전용) | 읽기 | 예 (`slaDashboard`) | — |
| `/admin/notices` | 공지·프로모션 CRUD·활성 토글 | 읽기+쓰기 | 아니오 (`adminNoticesActions` 세션 클라이언트 `:30,106,157`; `app_notices` admin RLS 031) | 테이블 직접 쓰기(RLS) |
| `/admin/audit-logs` | `admin_action_logs` 조회 | 읽기 | 예 (`auditLogQueries`) | (`admin_action_logs`는 admin RLS select도 있음) |
| `/admin/settings` | 요금제·수수료·정원·정산·앱 버전·관리자 계정(읽기) + 충전 패키지 토글 | 읽기+쓰기(토글 1개) | 조회 예 (`settingsQueries`), 토글은 세션 (`adminTopupPackageActions.ts:27`) | — |
| `/admin/question-rooms/[roomId]`, `/admin/question-threads/[id]`, `/admin/individual-questions/[id]` | 질문방/스레드/개별질문 드릴다운(읽기 전용 + 열람 기록) | 읽기(+열람 로그) | 예 (`questionDrilldownQueries` SR) | — |

### 5-3 "모바일에서 관리자 기능을 제공하려면" 판정

- 30개 실페이지 중 조회·쓰기 모두 SR에 의존하지 않는 것은 `moderation`(목록), `notices`, `settings`(토글) 정도이고, 핵심 조치(계정 정지/차단, 멘토 승인 상태 전이, 환불 승인, 정산 실행, 분쟁 분배, 탈퇴 감시, 계정·정산·충전·SLA 조회)는 **SR 서버 액션/조회 모듈**이거나 **service_role 전용 RPC**다. 관리자 JWT로 직접 호출 가능한 쓰기 RPC는 `approve_mentor_school_verification_admin`, `admin_issue_user_warning` 2종과 admin RLS 테이블(`app_notices`, `content_reports`, `disputes`, `reviews` 일부, `admin_action_logs`)뿐이다.
- 따라서 **앱 직접 구현은 불가**(anon 키 + 관리자 JWT로는 대부분 0행/권한 오류). 선택지: (a) 기존 앱처럼 관리자 계정 차단 유지(`auth_service.dart:102-103,122-124`); (b) WebView로 `/admin/*` 위임 — `/api/app-session/bootstrap`이 멘토 전용이라 관리자 허용 target 추가 및 MFA 정책 확인 필요; (c) 관리자용 API/RPC 계층 신설 — 최소 30여 개 SR 서버 액션·조회를 `api_app_v1` SECURITY DEFINER RPC(`is_admin()` 게이트) 또는 Bearer 인증 API로 재구현해야 하므로 **대규모** 서버 변경.

---

## §6 앱이 그대로 못 쓰는 것과 대체안

| 항목 | 웹 구현(근거) | 앱이 그대로 못 쓰는 이유 | 대체안 후보 |
|---|---|---|---|
| **가입** | 브라우저 `auth.signUp` + 메타 (`app/signup/page.tsx:335-339`); 행 생성은 SECURITY DEFINER 트리거 2종(§2-3) | — (직접 가능) | 앱이 `supabase.auth.signUp(email, password, data: {…§2-2 키})` 호출하면 동일하게 `users`·`mentor_profiles`·`verification_logs`·`user_consent_records` 생성. `users_insert_own` 정책·INSERT 권한이 남아 있으나(`20260803162257:89-93`) 트리거가 만들므로 직접 INSERT 불필요. `app_role`은 `student|mentor`만 유효 |
| **가입 시 학생증 저장(멘토)** | SR 서버 액션 `uploadMentorStudentIdAfterSignUpAction` (가입 15분 창·`app_role=mentor`·빈 칸만, `lib/auth/mentorSignupStudentIdAction.ts:20,73-96`) 또는 로그인 후 `submitMentorStudentIdImageAction`(SR, `lib/mentor/mentorStudentIdActions.ts:29`) | `mentor_profiles` authenticated 쓰기 전면 회수(`20260731135324`) → 객체를 올려도 `student_id_image_url`을 못 채움 | Storage `student-id-images`는 `{uid}/…` 경로 insert_own 정책이 001에 있음(`001:255-261`; 037/038/149 재정의 후 최신 정책 **(확인 필요)**) → 파일 업로드는 세션으로 가능하되 컬럼 반영용 **SECURITY DEFINER self RPC(예: `api_app_v1.mentor_student_id_set_self(p_object_path)`) 신설** 또는 웹 `/mentor/verification` WebView 위임 |
| **가입 동의 기록** | 트리거 `handle_new_auth_user_consent_records` (§2-3) | — | 앱도 메타 `terms_agreed/privacy_agreed/marketing_agreed/is_minor/consent_version/age_gate_checked_at/guardian_verification_method`를 동일 키로 보내면 동일 원장 생성. `consent_version`은 `'legal-placeholder-2026-06-20'` 상수 사용 |
| **마케팅 동의 변경** | `api_web_v1.user_marketing_consent_set_self(p_agreed boolean)` (authenticated·service_role, `20260803162257:287-330`) | 스키마가 `api_web_v1`(앱 정본은 `api_app_v1`, `profile_edit_repository.dart:26-39`) — PostgREST 노출 스키마에 `api_web_v1`이 포함되는지 **(확인 필요)** | 노출돼 있으면 `client.schema('api_web_v1').rpc(...)`; 아니면 `api_app_v1` 동형 RPC 추가 |
| **프로필(닉네임·학년) 수정** | `api_web_v1.user_profile_update_self` | — | 앱은 이미 `api_app_v1.user_profile_update_self(p_nickname, p_grade_level)` 사용(`profile_edit_repository.dart:110`) |
| **본인인증(NICE)·보호자 동의** | `/api/identity/start`·`/return` + SR 서비스(§3) | 테이블·키·NICE 클라이언트 전부 서버 전용, 쿠키 세션 기반, 복귀 URL 웹 도메인 | **WebView 위임 권장**(bootstrap 학생 허용 + `identity_onboarding` target + `/onboarding/*`·`/api/identity/*` allowlist). 완료 확인은 `users.identity_verified_at` SELECT. 앱은 웹 머니패스 403 `IDENTITY_REQUIRED` 토큰 매핑 추가(현재 0건) |
| **본인인증 게이트** | 레이아웃 redirect + 서버 가드(플래그 종속) (§3-1) | DB/RPC 레벨 가드가 없어 앱 직접 RPC 경로는 게이트 밖 | 정책 결정 필요: 앱 부팅 시 `identity_verified_at` 판독으로 자체 게이트를 두거나, DB 가드 도입(웹 주석은 "앱 재배포 없음 전제"로 금지 — 새 앱이면 재검토 가능) |
| **비밀번호 재설정** | 서버 액션 `resetPasswordForEmail` + `/auth/update-password` (§2-8) | 서버 액션 자체는 얇음 | 앱에서 `auth.resetPasswordForEmail(email, redirectTo)` 직접 호출 가능(allowlist 등록 필요). 새 비밀번호 입력은 (a) 앱 딥링크 recovery 세션 + `updateUser` 또는 (b) 웹 `/auth/update-password` 그대로 사용 |
| **로그인** | 클라이언트 `signInWithPassword` + `users` SELECT (§1) | — | 앱과 동일. 웹의 "역할 전용 화면" 거부는 앱에선 불필요 |
| **로그아웃** | POST `/logout` | — | `auth.signOut()` + WebView 쿠키 정리(앱 기존 `WebSessionHygiene.clear()`) |
| **계정 상태 판정** | `assertAccountActive`/strict 게이트 (§4-1) | — | 앱 기존 `AccountStatusReader.resolve`가 같은 입력(`users.status/suspended_until`, `account_deletion_write_blocked`, `account_deletion_status_self`)으로 동등 판정. `status='deleted'` 명시 처리만 추가 검토 |
| **탈퇴 요청·취소** | SR `account_deletion_request_consented`/`account_deletion_cancel` + 비밀번호 재인증 + 사전조건 5종 (§4-3) | SR 전용 RPC·TS 전용 사전조건 | 앱은 self v2 RPC 4종으로 이미 동작. 웹 동등성을 원하면 (a) 사전조건을 SECURITY DEFINER self RPC(예: `account_deletion_preconditions_self()`)로 서버화, (b) 비밀번호 재인증은 앱에서 `signInWithPassword` 재호출로 대체 가능. 취소창 문구는 서버 `cancelable_until`(30일) 기준으로 통일 |
| **관리자 콘솔** | SR 서버 액션·조회 + 관리자 세션 (§5) | 대부분 SR | 앱 차단 유지 또는 WebView `/admin` 위임(bootstrap 관리자 target 추가) 또는 대규모 RPC 계층 신설 |
| **Realtime** | 관리자 Presence `admin:*` 토픽(RLS 관리자만) | 관리자 전용 | 계정 도메인에서 앱이 쓸 Realtime 없음 |

---

## 부록 A. 확인 필요 목록(코드로 판정 못 한 것)

1. 운영 Supabase Auth의 Confirm email(가입 이메일 인증) 설정 — 로컬 `config.toml`은 OFF(`:226`).
2. 운영 `IDENTITY_GATE_ENABLED` 값(ON/OFF) 및 NICE 프록시 IP 등록 상태.
3. PostgREST 노출 스키마에 `api_web_v1`이 포함되는지(앱이 `user_marketing_consent_set_self`를 직접 호출 가능한지).
4. `student-id-images` Storage 정책의 최신 정의(037/038/149에서 탈퇴 conjunct 재정의 언급, `151` 헤더).
5. 학생 가입 폼의 `studentStatus` 입력 컨트롤 존재 여부(타입에는 있으나 input 확인 못함).
6. `api_web_v1.mentor_profile_update_self`(F7) 시그니처·앱 노출 여부.
7. `communityModerationActions`(세션 클라이언트)의 소프트삭제 UPDATE가 어느 RLS 정책으로 통과하는지.
8. 앱 저장소에서 `IDENTITY_REQUIRED` 매퍼가 다른 브랜치/미커밋으로 존재하는지(현 HEAD 0건).
