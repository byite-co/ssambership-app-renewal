# Phase 2 설계 — 멘토 콘솔 (Flutter 앱 · 웹 파리티, 결제 제외)

- 담당 범위: 멘토 마이페이지/대시보드 KPI · 프로필 편집(9필드·과목·아바타) · 플랜 가격 설정 · 개별질문 단가 · 구독 열림 토글 · 학교 인증 서류/학생증/학적 변경 · 정산 조회(월 요약·라인·계좌 등록) · 받은 리뷰·답글 · 활동 관리(일시중단/휴식/종료/복귀) · 멘토 측 분쟁 목록. 질문방·개별질문·맞춤의뢰의 멘토 화면은 제외(타 에이전트).
- 입력: Phase 1 리포트 4종(`web_mentor_console.md`, `web_db_surface_payment_boundary.md`, `app_architecture.md`, `app_features.md`). 설계에 결정적인 주장(RPC GRANT·RLS·버킷 정책·트리거)은 웹 저장소 SQL/코드로 재확인했다. 재확인하지 못한 항목은 **(확인 필요)** 로 표기.
- 표기: 웹 = `/home/user/ssambership_web` 상대경로, 앱 = `/home/user/ssambership-app` 상대경로. UI 디자인은 다루지 않는다(화면은 이름·역할·데이터 의존만).

---

## 1. 범위·전제

### 1.1 결제 경계 판정 (정본 `docs/policy/app-web-payment-separation.md` §1·§3·§4, DB 리포트 §4)

| 기능 | 판정 | 근거 |
|---|---|---|
| 정산 월 요약·라인 조회 | **상태 읽기 — 앱 허용** | 정책 §3 "멘토 정산 내역 조회 ✅ (읽기 전용)"(`docs/policy/app-web-payment-separation.md:18`). RPC `mentor_settlement_summary/lines` 는 SECDEF + `auth.uid()` 고정, authenticated 만 EXECUTE(`supabase/migrations/20260827100300_mentor_settlement_rpc_v2_due_payouts_parity.sql:204-207`). 자금 이동 없음 |
| 정산 계좌 등록(F13) | **계좌 정보 UPDATE — 결제 실행 아님(모호 → 오너 결정)** | 함수 본문은 `UPDATE mentor_profiles SET payout_bank_name, payout_account_number` 두 컬럼뿐, PG·원장·자금 이동 없음(`supabase/sql/20260730112531_api_web_v1_payout_account_rpc.sql:97-100`). 지급 실행은 service_role `pay_due_payouts_for_run` 으로 멘토 콘솔 호출 경로 없음. 앱은 현재 정산 관리 링크를 "결제 인접"으로 보고 숨김(`lib/core/commerce/commerce_policy.dart:29-33`) — 정책 재판정 필요 |
| 플랜 가격 설정(F8)·개별질문 단가 | **판매자 콘솔 행위 — 결제 아님(모호 → 오너 결정)** | F8 은 `mentor_plans` upsert 만(`supabase/sql/20260730112528_api_web_v1_mentor_rpc.sql:154-238`), `set_individual_question_price` 는 `mentor_individual_question_pricing` upsert 만(`supabase/sql/094_individual_question_pricing_rpc.sql:41-88`). 소비자 구매·캐시 차감 없음. DB 리포트 §4 #21 권고 "멘토 전용 화면으로 앱 포함 가능" |
| 학생 대상 가격 표시 | **범위 밖(멘토 찾기 리더)** — 본 도메인은 멘토 본인의 설정값만 다룬다 | DB 리포트 §4 #22 |
| 활동 관리(일시중단/복귀/종료 신청) | **자금 이동 없음 — 단 결제 인접(구독 기간 연장·종료 후 환불 배치)** → 오너 결정 | 일시중단은 `subscriptions.current_period_end/next_billing_at` 연장(`lib/mentor/mentorActivityService.ts:262-275`), 종료 **신청**은 상태 전이 + 플랜 비활성만(`:98-132`), 잔여 환불 생성은 배치용 `finalizeMentorTermination`(`:138-225`, 멘토 콘솔 호출 없음) |
| 수익 차트(cash_ledger 인입) | **상태 읽기 — 허용** | 본인 행 SELECT(`supabase/sql/004_p0_cash_disputes_admin_draft.sql:171-173`). 단 "충전 유도"로 읽히지 않게 정산 인입만 표시 |

### 1.2 Play/Apple 정책 주의(설계 제약)
- 가격 설정 화면은 **멘토 역할에만** 노출하고, 학생용 가격표·구매 CTA 와 화면·라우트를 분리한다(정책 §4 "가격표+구매 유도 조합" 금지, `docs/policy/app-web-payment-separation.md:22`). 밴드 안내(min/max)는 F8 오류 envelope 의 `min_cash_krw/max_cash_krw` 를 그대로 표시하고 앱에 상수 사본을 두지 않는다.
- 정산 화면은 "지급 예정/지급 완료" 상태 표시로 한정하고 충전·결제 URL 딥링크·문구를 넣지 않는다. 알림 `subscription_renewal_failed_insufficient_cash` 의 `/wallet/charge` 링크는 앱에서 억제(DB 리포트 §3.3).
- 잔액 관련 문구는 "상태 표시"만 허용(정책 §4 괄호). 멘토 콘솔에는 캐시 잔액 표시 자체를 두지 않는 것을 권고(웹도 멘토는 `/wallet/ledger` 차단 — `lib/shell/mainNavItems.ts:140`).
- 스토어 데이터 안전 항목: 학생증·재학증명 업로드를 앱에 넣으면 iOS `PrivacyInfo.xcprivacy` 수집 유형과 계약 테스트(`test/contracts/ios_release_config_contract_test.dart:44-47`)를 함께 갱신해야 한다(앱 리포트 §8-2).

### 1.3 공통 전제
- 앱은 anon key + 사용자 JWT 만 사용(`HANDOFF.md` §5 지뢰 5). 웹 service_role 전용 경로는 앱에서 구조적으로 불가 → 신규 SECDEF RPC 필요(§3(b)).
- DB 변경은 웹 저장소 pack 에만(`ssambership-app/supabase/SCHEMA_SOURCE_OF_TRUTH.md`), 절차는 DB 리포트 §5.2.
- 앱 정본 스키마는 `api_app_v1`(schema USAGE authenticated 만, service_role 없음 — `supabase/sql/20260730112525_api_app_v1_surface.sql:85-88`). 웹 `api_web_v1` 함수도 authenticated GRANT 가 있어 기술적으로 호출 가능하며 앱이 이미 `weekly_question_usage_self(_batch)`·`mentor_directory_v1`·`my_wallet_v1` 을 교차 호출 중(앱 리포트 §3-4). 계약상 원칙은 B-07 "앱이 멘토 프로필 쓰기를 원하면 전용 `api_app_v1` RPC 로 여는 원칙"(`docs/contracts/api_web_v1_contract_v1_1.md:2729`) → §3(a) 판단.
- 멘토 승인 판정 정본 = `individual_question_user_is_approved_mentor(uuid)`(approved/verified/active, `supabase/sql/070_individual_question_schema_escrow.sql:163-176`, GRANT authenticated `:876-877`) 또는 뷰 `mentor_directory_v1` 본인 행 존재. 미승인 멘토도 `mentor_profiles` 본인 행은 읽힌다(`mentor_select_own`, `supabase/sql/001_initial_auth_profile.sql:212`).

---

## 2. 갭 매트릭스

목표 열 값: **포함** / **웹 위임** / **제외** / **오너 결정**(§7 권고 병기).

| # | 웹 기능 | 웹 라우트 | 앱 현재 | 앱 목표 | 근거 |
|---|---|---|---|---|---|
| 1 | 멘토 홈 KPI(답변 대기·활성 구독자·이번 달 수익·평점/리뷰 수) | `/mentor/mypage` | `MentorDashboardSection` 3값(구독 학생=방 수, 답변 대기, 최근 정산 1건 — `lib/features/mypage/data/mypage_repository.dart:183-219`) | **포함**(확장) | 웹 KPI 정본 `lib/mentor/dashboard/mentorHubDashboardQueries.ts:192-280`. 전부 세션 RLS 읽기. 수익은 `mentor_settlement_summary` 로 대체(§3(c)) |
| 2 | 5개월 수익 차트(cash_ledger 양수 인입 월합) | `/mentor/mypage` | 없음 | **포함** | `app/(mentor)/mentor/mypage/page.tsx:83-87`, RLS `cled_select`. 앱은 기존 `api_web_v1.my_cash_ledger_v1`(매니페스트 포함) 재사용 가능 |
| 3 | 구독 수용량(cap used/limit/가중치) | `/mentor/mypage` | 없음 | **포함** | RPC 3종 anon/authenticated EXECUTE(`supabase/sql/050_mentor_subscription_cap.sql:90-92`, `190_cap_structure_limit_50_weights.sql:93-116`). 웹의 service_role 은 "경로 통일" 목적(`lib/subscribe/mentorCapService.ts:15-21`) |
| 4 | 구독 열림 토글 | `/mentor/mypage` | 없음 | **포함** | F7 로 현재 행 + `p_is_open_for_subscriptions` 만 변경(`lib/mentor/mentorSubscribeOpen.ts:65-96`) |
| 5 | 최근 후기 3건 | `/mentor/mypage` | 없음 | **포함**(#20 과 동일 레포) | `listMentorReceivedReviews(…,3)` |
| 6 | 인증 상태 배지·승인 전 배너·학교 인증/학적 현황 조회 | `/mentor/mypage`, `/mentor/verification`, `/mentor/academic-record-change` | 없음 | **포함** | 본인 `mentor_profiles.verification_status` + `mentor_school_verifications`(`msv_select_own`, `supabase/sql/077_mentor_school_verification.sql:124-128`) + `mentor_academic_record_change_requests`(`macc_select_own`, `089…:99-104`) |
| 7 | 프로필 편집(대학·학과·고교·과목·한줄소개·소개·구독공개 — F7 9필드) | `/mentor/profile/edit` | 웹 브릿지(`/mentor/profile`, `lib/core/web_bridge/web_bridge_config.dart:28`) | **포함** | F7 authenticated GRANT(`20260730112528…:242-245`). 대학·학과는 UI 잠금(현재 값 그대로 전달) |
| 8 | 닉네임 | `/mentor/profile/edit`(입력만, 저장 경로 없음 — 웹 리포트 §3.1) | `api_app_v1.user_profile_update_self` (`lib/features/mypage/data/profile_edit_repository.dart:22-39`) | **포함**(기존 유지) | 멘토는 `p_grade_level` 미전송 |
| 9 | 아바타 업로드/교체 | `/mentor/profile/edit` | 없음(웹 전용 결정 `docs/RELEASE_SCOPE_DECISIONS_2026-07.md` §1) | **오너 결정**(권고 포함) | 버킷 `profile-avatars` public·own-folder 정책(`supabase/sql/097_mentor_profile_avatar.sql:24-70`) + F7 `p_profile_image_url`. 출시 결정 번복 필요 |
| 10 | 플랜 가격 설정(3 tier, 밴드 강제) | `/mentor/profile/edit` | 없음 | **오너 결정**(권고 포함) | F8 authenticated GRANT; §1.1 |
| 11 | 개별질문 단가 | `/mentor/profile/edit` | 없음(단가는 읽기만) | **오너 결정**(권고 포함, #10 과 동일 판정) | `set_individual_question_price` authenticated GRANT(`094…:81-84`) |
| 12 | 학교·전공 인증 서류 제출(append-only INSERT) | `/mentor/verification` | 없음(웹 전용 결정) | **오너 결정**(권고 포함) | RLS `msv_insert_own_pending`(`077…:130-150`) + Storage `student_id_images_insert_own`(`001…:256-262`) 로 직접 가능. pending 이면 재제출 잠금(`app/(mentor)/mentor/verification/page.tsx:127`) |
| 13 | 학생증 사후 제출 → `mentor_profiles.student_id_image_url` 반영 | `/mentor/verification` | 없음 | **오너 결정**(권고 포함 · **신규 RPC 필수**) | 컬럼 반영이 service_role UPDATE(`lib/mentor/mentorStudentIdActions.ts:74-79`) — M11 로 세션 UPDATE 불가, F7 allowlist 밖 |
| 14 | 학적 변경 요청 | `/mentor/academic-record-change` | 없음 | **오너 결정**(권고 포함, #12 와 동일 판정) | RLS `macc_insert_own_pending`(`089…:106-124`) 직접 INSERT 가능 |
| 15 | 정산 월 요약(확정/적립/보류/지급합계·run_date·계좌 등록 여부) | `/mentor/payouts` | 없음(`subscription_settlement_items` 최신 1건) | **포함** | `mentor_settlement_summary(p_month)` authenticated(`20260827100300…:117-207`) |
| 16 | 정산 라인/상세(월·유형 필터) | `/mentor/payouts`, `/mentor/payouts/detail`, `GET /api/mentor/payouts/detail` | 없음 | **포함** | `mentor_settlement_lines(p_from,p_to)` 직접 호출(API route 는 얇은 래퍼 — 웹 리포트 §6.4). 유형 필터는 클라 |
| 17 | 정산 계좌 조회(마스킹) | `/mentor/payouts` | 없음 | **포함**(#18 과 결합) | 본인 행 SELECT 후 마스킹(`lib/mentor/mentorPayoutsService.ts:297-320`) |
| 18 | 정산 계좌 등록/변경 | `/mentor/payouts` | 없음(링크 숨김) | **오너 결정**(권고 조건부 포함) | F13(§1.1). 은행 allowlist 17종은 DB 정본(`20260730112531…:82-86` + `189_payout_bank_allowlist_add_im_bank.sql`) |
| 19 | 정산 엑셀 다운로드 | `/mentor/payouts/detail` | 없음 | **제외** | 클라이언트 `xlsx` 생성(웹 리포트 §6.4). 앱 필요성 낮음 |
| 20 | 받은 리뷰 목록(공개 가시 행) | `/mentor/reviews` | 웹 브릿지(`reviewsPath`, `web_bridge_config.dart:37`) | **포함** | `reviews_select_public_visible`(`supabase/sql/20260803162808_domain_contract_convergence.sql:115-121`) + `get_mentor_review_stats`(`:124-140`) |
| 21 | 리뷰 답글(1회·2~500자) | `PATCH /api/reviews/[id]/reply` | 없음 | **포함** | RLS `reviews_update_mentor`(`supabase/sql/126_reviews_rls_hardening.sql:61-64`) + 트리거 멘토 분기(`173…:123-138`) 로 직접 UPDATE 가능. 길이 규칙은 웹 코드에만(`lib/reviews/reviewQueries.ts:292-297`) → §3(b) RPC 권고 |
| 22 | 리뷰 숨김 | `PATCH /api/reviews/[id]/hide` | 없음 | **제외** | admin 전용(웹 리포트 §7) |
| 23 | 일시중단(1~7일, rest 6개월 1회 / illness) | `/mentor/mypage` | 없음 | **오너 결정**(권고 포함 · **신규 RPC 필수**) | 전부 service_role(`lib/mentor/mentorActivityActions.ts:46`) → `mentorActivityService.ts:228-288` |
| 24 | 조기 복귀 | `/mentor/mypage` | 없음 | **오너 결정**(#23 묶음) | `:291-308` |
| 25 | 활동 종료 신청(2주 공지 시작) | `/mentor/mypage` | 없음 | **오너 결정**(#23 묶음) | `:98-132`. 환불 생성은 배치 `finalizeMentorTermination` — 앱 비대상 |
| 26 | 무단 이탈(즉시 종료) | 액션만 존재, UI 미연결 | 없음 | **제외** | `mentorActivityActions.ts:74-86`, 컴포넌트 미연결(웹 리포트 §8.2) |
| 27 | 멘토 본인 활동 이력 조회 | (웹도 없음 — 관리자만) | 없음 | **오너 결정**(권고 최소 노출 또는 보류) | `mentor_activity_events` RLS 활성·정책 0(`supabase/sql/103_mentor_activity_suspension.sql:60`) → 신규 정책/RPC 필요 |
| 28 | 멘토 측 분쟁 목록 | `/mentor/support/disputes` | 없음 | **포함** | `dispute_select`: `auth.uid() in (student_id, mentor_id) or is_admin()`(`supabase/sql/004_p0_cash_disputes_admin_draft.sql:195-199`) — 직접 SELECT 가능(웹 `lib/disputes/disputeListQueries.ts:209-234`) |
| 29 | 분쟁 상세(조회 전용) | `/mentor/support/disputes/[id]` | 없음 | **포함**(조회 전용; 주문 번들은 맞춤의뢰 에이전트와 모델 공유) | 당사자 검사 `canPartyViewDispute`(웹 리포트 §1). 멘토 측 쓰기 액션 0 |
| 30 | 제출 서류 원본 열람(서명 URL) | `/mentor/verification` 는 저장 참조만 표시 | 없음 | **제외** | 출시 결정 "민감 서류 URL 을 앱 표면에 노출하지 않는다"(`docs/RELEASE_SCOPE_DECISIONS_2026-07.md` §1). 제출 상태·파일명만 표시 |
| 31 | 본인인증(NICE) 게이트 | `app/(mentor)/layout.tsx` env 플래그 | 없음 | **웹 위임**(상태 표시만) | `IDENTITY_GATE_ENABLED` 서버 env(`lib/identity/identityGateFlag.ts:13`), `users.identity_verified_at` 읽기 가능(`supabase/migrations/20260820100200_identity_verifications.sql:80`) |
| 32 | 계정 삭제 진입 | `/mentor/mypage` 링크 | `AccountDeleteScreen`(v2 RPC) | **포함**(기존 유지) | 앱 리포트 §1.10 |
| 33 | `/mentor/dashboard`, `/mentor/channel` | 라우트 부재(`loading.tsx` 만) | — | **제외** | 웹 리포트 §1·§8.1 |
| 34 | `/mentor/community/new`, `/mentor/questions*`, `/mentor/profile` redirect | redirect 전용 | — | **제외** | 웹 리포트 §1 |
| 35 | 정산 지급 배치·종료 확정(환불 생성)·정산 보류 | cron/관리자 | — | **제외** | service_role 전용(DB 리포트 §1.6) |

집계: 포함 16 · 웹 위임 1 · 제외 7 · 오너 결정 11.

---

## 3. 서버 표면 설계

### 3(a) 기존 사용 가능 객체와 스키마·GRANT

| 객체 | 스키마 | 시그니처 → 반환 | GRANT(authenticated) | 근거 | 앱 호출 판단 |
|---|---|---|---|---|---|
| F7 `mentor_profile_update_self` | `api_web_v1` | `(p_university_name, p_department_name, p_high_school_name text, p_teaching_subjects text[], p_intro_line, p_bio, p_answer_style, p_profile_image_url text, p_is_open_for_subscriptions boolean) → jsonb` envelope. 9컬럼 전면 교체. 코드 `AUTH_REQUIRED/ROLE_NOT_MENTOR/ACCOUNT_BANNED/ACCOUNT_SUSPENDED/ACCOUNT_DELETION_IN_PROGRESS/MENTOR_PROFILE_NOT_FOUND/UNIVERSITY_NAME_REQUIRED/DEPARTMENT_NAME_REQUIRED/PROFILE_IMAGE_REF_INVALID` | `authenticated, service_role` | `supabase/sql/20260730112528_api_web_v1_mentor_rpc.sql:65-149, 242-245` | 기술적 호출 가능. **권고: `api_app_v1` 동명 wrapper 신설 후 그쪽 호출**(B-07 원칙) |
| F8 `mentor_plan_prices_set_self` | `api_web_v1` | `(p_limited_cash_krw, p_standard_cash_krw, p_premium_cash_krw integer) → jsonb {ok, updated[], unchanged[]}`; 밴드 밖 `PLAN_PRICE_OUT_OF_BAND{tier,min_cash_krw,max_cash_krw,given_cash_krw}`, `<1` → `PLAN_PRICE_INVALID`; `cap_weight = subscription_cap_weight(tier)` | `authenticated, service_role` | `:154-238`, 190 재정의 `190_cap_structure_limit_50_weights.sql:206-211` | 동일 |
| F13 `mentor_payout_account_update_self` | `api_web_v1` | `(p_bank_name, p_account_number text) → jsonb {ok, updated_at, account_masked}`; 코드 + `MENTOR_NOT_APPROVED/PAYOUT_BANK_NAME_INVALID/PAYOUT_ACCOUNT_NUMBER_INVALID(^[0-9]{8,24}$)` | `authenticated, service_role` | `20260730112531…:52-118` | 동일(오너 결정 #18 후) |
| V7 `mentor_settlement_self()` | `api_web_v1` | `TABLE(item_id, subscription_id, student_label, event_type, billing_at, period_start, period_end, gross_cents, platform_fee_cents, mentor_amount_cents, fee_rate, status, hold_reason, paid_at, created_at)` | `authenticated, service_role` | `supabase/sql/20260730105248_api_web_v1_self_rpc.sql:316,323` | 읽기 뷰형 RPC — 앱 교차 호출 관행(`weekly_question_usage_self`)과 같은 성격 → 직접 호출 허용 권고. 단 `mentor_settlement_lines` 가 3소스 통합이라 **V7 은 선택**(학생 라벨이 필요할 때만) |
| `set_individual_question_price` | `public` | `(p_amount_cents int) → SETOF mentor_individual_question_pricing`; **raise 스타일**(`AUTH_REQUIRED` 28000, `INVALID_INPUT` 22023). 승인 게이트 미적용(주석) | `authenticated` | `094_individual_question_pricing_rpc.sql:41-88` | 직접 호출(raise 매퍼 사용) |
| `mentor_settlement_summary(p_month date)` | `public` | jsonb: `month, run_date, cutoff, payout_account_registered, confirmed{count,gross_cents,platform_fee_cents,mentor_amount_cents,withholding_cents,net_cents}, accruing{count,mentor_amount_cents,withholding_cents,net_cents,last_period_end,expected_run_date}, held{count,mentor_amount_cents}, paid_total{count,mentor_amount_cents,net_cents}, by_source_this_month{source_type:{mentor_amount_cents,count}}, withholding_rule` | `authenticated` 만 | `20260827100300…:117-207` | 직접 호출. `p_month` 는 `'YYYY-MM-01'`(`lib/mentor/mentorSettlementService.ts:38`) |
| `mentor_settlement_lines(p_from, p_to timestamptz)` | `public` | `TABLE(source_type, source_id, occurred_at, period_start, period_end, gross_cents, platform_fee_cents, mentor_amount_cents, fee_rate, withholding_cents, net_cents, status(accruing|pending|hold|paid|canceled), hold_reason, completion_ts, expected_run_date, paid_run_date, paid_at)` | `authenticated` 만 | `:8-31, 204-207` | 직접 호출. KST 월 반개구간(`kstMonthBounds`) 을 Dart 로 재현 |
| `calc_withholding_cents(bigint)` | `public` | bigint(캐시 단위 3.3% 절사) | `authenticated, service_role` | `20260827100200…:7-21` | 사용 불필요(라인·요약이 이미 포함) |
| `mentor_cap_used(uuid)` / `mentor_cap_limit(uuid)` / `subscription_cap_weight(text)` | `public` | numeric | `anon, authenticated, service_role` | `050…:90-92`, `190…:93-116` | 직접 호출 5회(used, limit, weight×3). 활성 구독 수는 `subscriptions` 당사자 SELECT 로 count |
| `get_mentor_review_stats(p_mentor_id, p_include_hidden)` | `public` | `TABLE(review_count, avg_rating, d1..d5)` | `a,u,s` | `20260803162808…:124-140` | 직접 호출(`mentor_profiles.avg_rating/review_count` 컬럼은 부재 — 웹 리포트 부록 A-6) |
| `get_mentor_student_nicknames(p_student_ids uuid[])` | `public` | `TABLE(id, nickname, full_name)` — 활성 구독 또는 방 관계 학생만 | `authenticated`(앱 매니페스트 포함) | `supabase/sql/140_p3_9_student_nickname_subscription_room_scope.sql:14-39` | 리뷰 작성자 표시명 해소용(§3(c)) |
| `individual_question_user_is_approved_mentor(uuid)` | `public` | boolean | `authenticated, service_role` | `070…:163-176, 876-877` | 승인 게이트 표시용(선택 — 본인 행 `verification_status` 로 대체 가능) |
| `reviews` UPDATE(답글) | `public` | RLS `reviews_update_mentor` + `trg_reviews_enforce_update` 멘토 분기(1회·`mentor_replied_at` 서버 강제·`updated_at` 불변) | DIRSTTU | `126…:61-64`, `173…:123-138` | 직접 UPDATE 가능하나 길이 규칙·0행 판정 부재 → §3(b) #7 RPC 권고 |
| `mentor_school_verifications` INSERT/SELECT | `public` | `msv_insert_own_pending`(role mentor, status pending, 관리자 필드 NULL) · 가드 트리거가 관리자 필드 NULL 강제 | 정책 | `077…:82-112, 124-150` | 직접 INSERT 가능(웹과 동일 shape `{mentor_id, status:'pending', document_storage_ref}`, `lib/mentor/mentorSchoolVerificationActions.ts:67-71`) |
| `mentor_academic_record_change_requests` INSERT/SELECT | `public` | `macc_insert_own_pending` | 정책 | `089…:99-124` | 직접 INSERT 가능(`{mentor_id, status, requested_university_name, change_reason, document_storage_ref}`, `lib/mentor/mentorAcademicRecordChangeActions.ts:67-73`) |
| `disputes` SELECT | `public` | `dispute_select`(당사자 or admin) | 정책 | `004…:195-199` | 직접 SELECT `where mentor_id = auth.uid()` |
| `school_tier_catalog` / `major_category_catalog` SELECT | `public` | `select_active_or_admin` 정책 + GRANT anon/authenticated | GRANT | `079_b_classification_catalog.sql:149-165, 190-191` | 라벨 표시용(선택) |
| Storage `profile-avatars` | — | public=true, 5MiB, jpeg/png/webp, own-folder INSERT/UPDATE/DELETE | 정책 | `097…:24-70` | 직접 업로드 `{uid}/{uuid}.{ext}`, `getPublicUrl` 결과를 F7 에 전달(F7 이 `/profile-avatars/` 마커 뒤 첫 세그먼트=uid 검증) |
| Storage `student-id-images` | — | public=false, **크기·MIME 제한 없음**, own-folder 4정책 + admin SELECT | 정책 | `001…:242-282`, DB 리포트 §3.1 | 직접 업로드. 경로 3종: `{uid}/{ts}-{rand}.{ext}`(학생증), `{uid}/school-verifications/…`, `{uid}/academic-record-changes/…`(`lib/storage/studentIdImageStorage.ts:44-56`) |

**`api_web_v1` 직접 호출 vs `api_app_v1` wrapper 판단**
- 읽기 성격(V7·뷰)은 이미 관행(앱 리포트 §3-4)이며 계약상 "사실상 관행"으로 기록(DB 리포트 §6 #13) → 그대로 허용, 새 계약 문서에서 정식화.
- **쓰기 RPC(F7/F8/F13)는 `api_app_v1` 동명 wrapper 신설을 권고**한다. 근거: B-07 원칙(`api_web_v1_contract_v1_1.md:2729`), `api_app_v1` 이 service_role 을 배제한 "앱 공개 계약 호출자" 스키마라는 설계 의도(`20260730112525…:6-9`), 앱 매니페스트가 스키마 단위로 표면을 잠그는 구조(`test/contracts/outbound_api_manifest_test.dart:69`). 구현은 `user_profile_update_self` 선례(`supabase/migrations/20260803170552_…:251-264` — `language sql SECDEF search_path=''` 한 줄 위임)와 같은 **얇은 위임**으로 하되, 위임 대상은 (권장) `core_private.mentor_profile_update_self_impl(p_actor uuid, …)` 로 본문을 추출해 `api_web_v1` 함수도 같은 impl 을 호출(계약 §5.2 "판정 로직은 impl 한 곳"), (최소안) 추출 없이 `select api_web_v1.mentor_profile_update_self(...)` 위임. 어느 쪽이든 오류코드·envelope 는 F7/F8/F13 과 동일해야 한다.
- 중간안(오너 결정 #5): wrapper 적용 전까지 앱이 `api_web_v1` 를 직접 호출하는 것을 허용할지.

### 3(b) 새로 필요한 서버 객체

공통 규약(DB 리포트 §5.2·§6 공통 규칙): `api_app_v1.<name>` SECDEF `SET search_path=''`, `auth.uid()` 자체 도출(`p_user_id` 류 인자 금지), envelope `{ok, contract_version:1, …}`/`{ok:false, contract_version:1, code}`, 계정 게이트(`users.role='mentor'`, banned/suspended, `account_deletion_write_blocked(self)`), `REVOKE ALL FROM PUBLIC` + `GRANT EXECUTE TO authenticated`(service_role 부여 안 함), impl 은 `core_private` INVOKER + 외부 EXECUTE 0. 파일은 `supabase/sql/NNN_*.sql` + rollback + `post_ledger_backfills` 등재 + pack 생성기 + `contracts:export/verify` 갱신.

| # | 객체(초안) | 시그니처 → 반환 | 구현부 요지 | 오류코드 | 규모 |
|---|---|---|---|---|---|
| 1 | `api_app_v1.mentor_student_id_document_set_self(p_object_path text) → jsonb` | 성공 `{ok, contract_version, stored_ref, updated_at}` | impl `core_private.mentor_student_id_document_set_impl(p_actor uuid, p_object_path text)`: ① 계정 게이트 ② `split_part(path,'/',1) = p_actor::text` 이고 세그먼트 수 = 2(하위 폴더 `school-verifications/`·`academic-record-changes/` 객체를 학생증으로 가리키지 못하게) ③ `storage.objects` 에 `bucket_id='student-id-images' AND name=path` 실재 + `owner_id = p_actor`(앱은 세션 업로드라 owner 채움 — DB 리포트 §3.1 주의; 174 의 실재 검사 패턴 `supabase/sql/174_mentor_school_verification_approval_canon.sql` 재사용) ④ `UPDATE mentor_profiles SET student_id_image_url = 'student-id-images/'||path WHERE user_id=p_actor`(저장 형식 `formatStudentIdImageStoredRef`, `lib/storage/studentIdImageStorage.ts:15-21`). 특권 컬럼 가드 트리거(`verification_status·cap_limit` 만)에 걸리지 않음 | `AUTH_REQUIRED, ROLE_NOT_MENTOR, ACCOUNT_BANNED, ACCOUNT_SUSPENDED, ACCOUNT_DELETION_IN_PROGRESS, MENTOR_PROFILE_NOT_FOUND, STORAGE_PATH_INVALID, STORAGE_OBJECT_NOT_FOUND, STORAGE_OBJECT_NOT_OWNED` | S |
| 2 | `api_app_v1.mentor_activity_pause_self(p_days integer, p_reason text) → jsonb` | `{ok, contract_version, pause_until, days, subscriptions_extended}` | impl `core_private.mentor_activity_pause_impl(p_actor, p_days, p_reason)`: `mentorActivityService.ts:228-288` 이식 — 상태가 active(=`activity_status='active'` 또는 `paused` 이나 `pause_until<=now()`)가 아니면 거부; `p_reason ∈ {rest, illness}`; rest 는 `last_pause_at` 이 KST 기준 6개월 이내면 거부(`canRequestNormalRest`, `lib/mentor/mentorActivity.ts:47-56`); days clamp 1~7(`:58-62`); `mentor_profiles` SET `activity_status='paused', pause_started_at, pause_until, pause_reason, last_pause_at(rest 만)`; `subscriptions`(status in active,past_due) `current_period_end/next_billing_at += days`(`trg_enforce_mentor_cap` 은 `UPDATE OF status, plan_tier` 라 미발화 — DB 리포트 §2); `mentor_activity_events` INSERT `pause_started`(illness 는 `pending_review`); 158 트리거 `trg_mp_notify_activity` 가 학생 알림 fan-out(`supabase/sql/158…:68-72`) | 공통 + `ACTIVITY_NOT_ACTIVE, PAUSE_REASON_INVALID, PAUSE_DAYS_INVALID, REST_FREQUENCY_LIMIT` | M |
| 3 | `api_app_v1.mentor_activity_resume_self() → jsonb` | `{ok, contract_version}` | `:291-308` 이식 — `activity_status<>'paused'` 면 거부; SET `active, pause_until=null`; `mentor_plans.is_active=true`; 이벤트 `pause_resumed` | 공통 + `ACTIVITY_NOT_PAUSED` | S |
| 4 | `api_app_v1.mentor_activity_terminate_self() → jsonb` | `{ok, contract_version, effective_at, notified_subscribers}` | `:98-132` 이식 — terminating/terminated 면 거부; SET `terminating, termination_requested_at=now(), termination_effective_at=now()+14d`; `mentor_plans.is_active=false`; 이벤트 `termination_requested`. **환불 생성 없음**(finalize 는 배치 유지) | 공통 + `TERMINATION_ALREADY_REQUESTED` | S |
| 5 | (선택) `api_app_v1.mentor_activity_events_self(p_limit integer default 20) → TABLE(id, event_type, reason, status, created_at, pause_until, effective_at)` | 본인 이력 | `mentor_activity_events` 는 정책 0(`103…:60`) 이므로 SECDEF 로 `mentor_id=auth.uid()` 행만, `detail` jsonb 는 키 선별(`pause_until`, `effective_at` 만 — `hold_error` 등 내부 문자열 비노출). 대안 `mae_select_own` 정책 추가는 `detail` 원문 노출 + GRANT 실측 필요 **(확인 필요: 103 이 2026-08-02 default ACL 하드닝 이전이라 authenticated SELECT GRANT 잔존 여부)** | `AUTH_REQUIRED` | S |
| 6 | (선택) `api_app_v1.mentor_cap_usage_self() → jsonb` | `{ok, contract_version, used_cap, cap_limit, weight_by_tier{limited,standard,premium}, active_count, is_full}` | 5회 RPC 왕복 → 1회. `is_full = used + weight.limited > cap_limit`(`lib/subscribe/mentorCapUsageCore.ts:96`). 계산은 기존 DB 함수 호출만(가중치 사본 금지) | — | S |
| 7 | (권장) `api_app_v1.mentor_review_reply_self(p_review_id uuid, p_reply text) → jsonb` | `{ok, contract_version, replied_at}` | 2~500자 검증(웹 `replyToReview` 규칙 `lib/reviews/reviewQueries.ts:292-297` 를 서버로 이동), 행 존재·`mentor_id=auth.uid()`·기존 답글 없음 확인 후 `UPDATE reviews SET mentor_reply` (트리거가 `mentor_replied_at` 강제) + RETURNING 1행 판정(0행 무음 실패 방지 — 웹 리포트 D-MT-5 패턴) | `AUTH_REQUIRED, ROLE_NOT_MENTOR, REVIEW_NOT_FOUND, REVIEW_NOT_MINE, REPLY_ALREADY_SET, REPLY_LENGTH_INVALID` | S |
| 8 | `api_app_v1.mentor_profile_update_self(9인자)` · `mentor_plan_prices_set_self(3인자)` · `mentor_payout_account_update_self(2인자)` | F7/F8/F13 과 동일 envelope | §3(a) 판단대로 얇은 위임(impl 추출 권장). 추가 권고: F7 wrapper 에 `p_expected_updated_at timestamptz default null` 을 두어 `mentor_profiles.updated_at` 낙관적 잠금(`PROFILE_STALE`) — 학적 변경 승인(관리자 service_role `university_name` 갱신, `lib/admin/mentorAcademicRecordChangeReviewActions.ts:116`)과 앱의 9필드 전면 교체가 경합할 때 승인값을 되돌리고 192 B-4 재판정을 유발하는 사고 방지(§3(c)) | F7/F8/F13 동일 + `PROFILE_STALE` | S~M |
| 9 | (선택) `api_app_v1.mentor_school_verification_submit_self(p_object_path text) → jsonb` / `mentor_academic_record_change_submit_self(p_object_path, p_requested_university_name, p_change_reason)` | INSERT 대행 | 직접 INSERT 가 RLS 로 가능하므로 필수는 아니다. 도입 가치: ① 객체 실재·소유 검증(웹의 서버측 매직바이트 검증이 앱에서는 클라이언트로 내려가는 신뢰도 하락 보완 — 웹 리포트 §9.3) ② pending 중복 제출 차단(웹은 UI 잠금만 `verification/page.tsx:127`) ③ 학적 변경 길이 상한(40/100)·크기 상한 서버 강제(웹은 크기 검사 누락 — 웹 리포트 부록 A-4) | `…_PENDING_EXISTS, STORAGE_OBJECT_NOT_FOUND, …` | S each |
| 10 | (선택) `api_app_v1.payout_bank_allowlist() → text[]` | 은행 17종 | F13 본문 리터럴을 함수/카탈로그로 분리하지 않으면 앱이 17종 상수를 복제해야 함(웹 `components/mentor/payouts/MentorPayoutAccountPanel.tsx:8-26` 도 복제 상태). 대안: 앱 상수 + `PAYOUT_BANK_NAME_INVALID` 로 안내 | — | S |

부수 갱신(신규 객체 추가 시 반드시): `docs/contracts/api_web_v1_contract_v1_1.md` §7/§9 오류코드 사전 추가(UPPER_SNAKE, 추가만) · `npm run contracts:export && contracts:verify` 스냅샷 재생성 · 앱 `outbound_api_manifest_test.dart` 집합 갱신(§4.5). `20260730195156_contract_permission_assertions.sql` 의 "api_app_v1 wrapper 5개" 검증은 적용 시점 1회성 DO 블록이라 후속 추가(`user_profile_update_self` 선례)와 충돌하지 않는다(`:222-262`).

### 3(c) 정책 공백·리스크(서버 관점)

1. **프로필 폼 사문 필드**: `nickname` 은 액션이 읽지 않고(웹 리포트 §3.1), `grade`(학번)·`tags` 는 F7 미전달 → 저장 컬럼·경로 없음. 앱은 nickname 만 `api_app_v1.user_profile_update_self` 로, grade/tags 는 **구현하지 않는다**.
2. **대학·학과 변경 트리거**: F7 는 `university_name/department_name` 갱신을 허용(빈 값만 거부)하고, 값이 바뀌면 `trg_school_verification_reassess_on_academic_change` 가 approved/pending 인증 행을 `pending·reviewed_by NULL` 로 되돌린다(`supabase/sql/192_school_verification_provisional_rule.sql:340-390`). 앱은 두 필드를 편집 불가로 두고 **직전 읽은 현재 값을 그대로 전달**해야 하며, 낙관적 잠금(#8) 없이는 관리자 학적 승인과 경합 시 승인값이 되돌아갈 수 있다.
3. **구독 열림 토글도 F7 전면 교체** → 같은 경합 위험. wrapper 에 `p_expected_updated_at` 도입 시 함께 해소.
4. **리뷰 숨김·블라인드 행은 멘토도 못 본다**(별도 멘토 SELECT 정책 없음, `reviews_select_public_visible` 만) → 웹과 동일하게 "공개 가시 리뷰만" 표시. 숨김 기능은 admin 전용.
5. **리뷰 작성자 표시명**: `users` SELECT 는 본인·admin 만 → 멘토 세션에서 타인 행 0행. 앱은 `get_mentor_student_nicknames(author_ids)`(활성 구독 또는 방 관계 학생만 반환, `140…:27-39`)로 해소하고, 미해소 작성자는 '학생' 폴백. 리뷰 자격이 "2회 연속 결제"라 대부분 방 관계가 있으나 구독 만료 후 방이 삭제되는지는 **(확인 필요)**.
6. **`set_individual_question_price` 승인 게이트 미적용** — 미승인 멘토도 단가 저장 가능(웹과 동일 동작). 앱은 승인 전 화면 잠금(UX 게이트)만 두고 서버 게이트 추가는 오너 결정.
7. **정산 라인의 개별질문 요율은 RPC 내부 상수 0.85/0.15**(`20260827100300…:64-70`, 웹 리포트 부록 A-5) — 앱은 표시만, 재계산 금지. `fee_rate` 는 행값 표시(없으면 '요율 미설정').
8. **월 수익 KPI 정의 불일치 위험**: 웹 `monthlyRevenue` 는 레거시 라인 로더(`lib/mentor/mentorPayoutsService.ts`) 의 "이번 달 라인 순액 합(수수료 후·원천징수 전)". 앱은 `mentor_settlement_summary.by_source_this_month` 합(=mentor_amount_cents, 같은 정의)으로 대체 권고. `cash_ledger` 인입(차트)은 "실지급 반영" 시점이라 KPI 와 다른 값이다 — 두 지표를 같은 이름으로 쓰지 않는다.
9. **활동 상태 '자동 복귀'는 DB 에 반영되지 않는다**: `paused` 행은 `pause_until` 경과 후에도 `paused` 로 남고 웹이 읽기 시 `active` 로 해석(`lib/mentor/mentorActivity.ts:19-36`). 앱 모델도 같은 판정식을 구현해야 하며, 복귀 RPC 는 `activity_status='paused'` 문자열만 본다(경과 후 호출도 성공 — 웹과 동일).
10. **`student-id-images` 버킷은 크기·MIME 무제한**(DB 리포트 §3.1) — 앱 클라이언트 검증(20MB·jpg/jpeg/png/pdf·매직바이트)이 유일한 방어. #9 RPC 도입 시 `storage.objects.metadata->>'size'`/`mimetype` 검사로 보강 가능.
11. **`profile-avatars` 는 public 버킷** — 업로드 즉시 URL 이 공개된다. F7 성공 전 구 객체 삭제 금지·실패 시 신규 객체 보상 삭제(`lib/mentor/mentorProfileEditActions.ts:96-126`) 규약을 앱도 따른다.
12. **`api_app_v1` 에 service_role 없음** → 웹이 앱 wrapper 를 재사용할 수 없다. 활동 RPC 를 impl 로 만들면 웹 액션(`mentorActivityActions.ts`)도 `api_web_v1` wrapper 로 전환해 로직 이원화를 없애는 후속 작업이 생긴다(웹 리포트 §9.1 취지).
13. **Realtime 미적용**: `mentor_profiles`·`mentor_school_verifications` 는 publication 7종(DB 리포트 §3.2)에 없다 → 승인·인증 상태 변화는 resume 재조회로만 반영.
14. **분쟁 상세**는 `custom_request_orders` 번들에 의존(웹 `loadDisputeById`) — 컬럼·RLS 정본은 맞춤의뢰 리더 범위 **(확인 필요)**. 본 도메인은 `disputes` 행 자체만 책임진다.

---

## 4. 앱 프론트엔드 설계

### 4.1 feature 배치 — `lib/features/mentor_console/` 신설 + 기존 `mypage` 는 진입만
기존 `mypage` 는 역할 공용 계정 허브(프로필·설정·탈퇴·알림 설정)로 유지하고, 멘토 전용 화면은 새 feature 로 분리한다. 근거: `MyPageRepository` 는 "어떤 mutate 도 하지 않는다"(`lib/features/mypage/data/mypage_repository.dart:14`) 계약이라 F7/F8/F13/활동 RPC 같은 쓰기를 넣을 수 없고, 마이페이지가 push 화면(`AppTab.myPage=100`, `lib/app/app_tabs.dart:17`) 이라 멘토 콘솔 12개 화면을 그 안에 중첩하면 §4-4 병목(pop-int 핸드오프)이 커진다.

```
lib/features/mentor_console/
  data/
    mentor_console_models.dart          # §5 모델 전부(fromMap · enum fromCode/unknown)
    mentor_console_error_mapper.dart    # envelope code + raise code → 한글(공통 계정 문구는 qna/profile 매퍼와 동일 문장)
    mentor_console_rpc_backend.dart     # abstract MentorConsoleRpcBackend { rpc(schema, fn, params) } + Supabase 구현 (ProfileEditBackend 패턴 일반화, profile_edit_repository.dart:22-39)
    mentor_home_repository.dart         # 읽기: KPI·cap·활동상태·인증상태·최근 후기·차트
    mentor_profile_repository.dart      # 읽기 본인 mentor_profiles 행 / 쓰기 F7(전면 교체 병합) · 토글
    mentor_pricing_repository.dart      # mentor_plans 본인 3행 읽기 / F8 / set_individual_question_price / mentor_individual_question_pricing 읽기
    mentor_verification_repository.dart # school_verifications·academic_change 최신 행 읽기 / 서류 INSERT / 학생증 RPC
    mentor_settlement_repository.dart   # mentor_settlement_summary(월·추이 6개월) / mentor_settlement_lines / 계좌 마스킹 읽기 / F13
    mentor_reviews_repository.dart      # reviews 공개 가시 행 + get_mentor_review_stats + 작성자 라벨(get_mentor_student_nicknames) / 답글
    mentor_activity_repository.dart     # 활동 상태 판정(순수 함수) / pause·resume·terminate RPC / (선택) 이력
    mentor_disputes_repository.dart     # disputes where mentor_id=me / 단건
    mentor_document_upload_gateway.dart # student-id-images 업로드 포트(Storage) — 경로 빌더 3종 순수 함수
    mentor_avatar_gateway.dart          # profile-avatars 업로드·publicUrl·보상 삭제 포트
    mentor_document_policy.dart         # 20MB · jpg/jpeg/png/pdf · 매직바이트(sniffIqAttachmentMime 재사용) — 순수 함수
  ui/
    mentor_home_screen.dart             # KPI·차트·cap·활동상태·구독 토글·최근 후기 (웹 /mentor/mypage 대응)
    mentor_profile_edit_screen.dart     # 9필드+과목+아바타(+닉네임은 기존 ProfileEditRepository 호출)
    mentor_pricing_screen.dart          # 플랜 3가격 + 개별질문 단가 (오너 결정 #1·#2 후)
    mentor_verification_screen.dart     # 인증 상태·학교 서류 제출·학생증 제출
    mentor_academic_change_screen.dart  # 학적 변경 요청
    mentor_settlement_screen.dart       # 월 요약·계좌·추이
    mentor_settlement_lines_screen.dart # 월·유형 필터 라인
    mentor_payout_account_screen.dart   # 계좌 등록(오너 결정 #3 후)
    mentor_reviews_screen.dart          # 받은 리뷰 + 답글 입력
    mentor_activity_screen.dart         # 일시중단/복귀/종료 신청(오너 결정 #4 후)
    mentor_disputes_screen.dart / mentor_dispute_detail_screen.dart
```

역할 게이트: 모든 레포는 `AuthService.instance.currentRole == AppRole.mentor` 를 전제하되(`lib/core/auth/auth_service.dart:13,45`), 권한 판정 자체는 RLS/RPC 에 맡긴다(앱 리포트 §3-1 관례). 승인 전(`verification_status ∉ {approved,verified,active}`)에는 가격·계좌·활동 화면을 잠그고 인증 화면으로 유도(웹 `mypage/page.tsx:187-198` 배너 대응) — 판정식은 `MENTOR_ACTIVITY_APPROVED_STATUSES`(`lib/mentor/mentorVerificationGate.ts:4`) 와 동일 3값.

### 4.2 재사용 코어(기존 앱 자산 → 그대로/일반화)
| 코어 | 재사용 방식 | 근거 |
|---|---|---|
| RPC seam `XxxBackend.rpc(fn, params)` + 손코딩 `Fake` | `MentorConsoleRpcBackend.rpc(schema, fn, params)` 로 스키마 인자 추가(`api_app_v1`·`api_web_v1`·`public` 혼용). `schema()` 생략 시 PGRST202 지뢰 유지 | `profile_edit_repository.dart:22-39`, 앱 리포트 §8-2 |
| envelope strict 파서 | `ok==true && contract_version==1` 아니면 실패, `{ok:false,code}` 는 예외가 아닌 거부로 처리, 보조 필드(`tier/min_cash_krw/max_cash_krw`) 보존 — `parseBoardPostCreateEnvelope`/`callApiWebV1Rpc` 규약을 `lib/core/api/envelope.dart` 1벌로 승격(리포트 §9-2 중복 제거 후보) | `board_post_create_gateway.dart:120-135`, 웹 `lib/apiWebV1/rpc.ts:39-59` |
| raise 스타일 코드 추출 | `set_individual_question_price`(`AUTH_REQUIRED`/`INVALID_INPUT`)·직접 UPDATE 트리거 예외(`reviews: …` 문장형 — 코드 아님 → 일반 문구) | `profile_edit_repository.dart:73-78` |
| 업로드 파이프라인 | `PickedImage`·`ScanSourcePort`(카메라/갤러리/파일) → `downscaleIfOversized`(아바타 5MB, 장변 2560·JPEG85) → `uploadBinary(upsert:false)` → 등록(F7 또는 학생증 RPC/INSERT) → 실패 시 보상 `remove` | `lib/core/scan/image_downscaler.dart:18`, `attachment_upload.dart:331-360`, `board_post_media_gateway.dart` |
| 매직바이트 | `sniffIqAttachmentMime`(png/jpeg/pdf 판별) 재사용, 서류 정책은 `{image/jpeg,image/png,application/pdf}` ∧ 20MB(웹 `STUDENT_ID_IMAGE_MAX_BYTES`, `lib/storage/studentIdImageStorage.ts:7`) | `iq_attachment_policy.dart:29` |
| 서명 URL 리졸버 | 제출 서류 원본 열람은 **제외**(§2 #30) 라 `student-id-images` 리졸버 불필요. 아바타는 public URL(`getPublicUrl`) — 리졸버 없음 | 출시 결정 §1 |
| 교차 화면 무효화 | `DataRefreshBus` 에 `mentorProfileGeneration`(F7/F8/토글/아바타 성공)·`mentorSettlementGeneration`(계좌 등록 성공) 추가; 구독 기간 연장(일시중단) 성공 시 기존 `bumpSubscription()` 호출(현재 생산자 0 — 의도된 대기, `lib/core/refresh/data_refresh_bus.dart`) | 앱 리포트 §3-9 |
| resume 재조회 | `ResumeVisibilityGate` 로 인증 상태·정산 요약 재조회(Realtime 없음 — §3(c) 13) | 앱 리포트 §3-9 |
| 세대 토큰·single-flight | 홈 로더(Future.wait 병렬, `mypage_repository.dart` N17 패턴) | §3-1 |
| 과목 코드 | `subjectCodeForDb()` 통과값만 F7 `p_teaching_subjects` 로 전송(정본 밖 값은 서버가 조용히 제거) | `lib/data/mappings/subject_labels.dart:107-113` |
| 문구 규약 | 원문 코드·UUID·테이블명 비노출(`friendlyError`), 계좌 원문·서명 URL 로그 금지 | §8-2 |

### 4.3 라우트 추가(타입드 라우트 테이블 전제 — 앱 리포트 §9-2 교체 후보)
현 구조(명명 라우트 4 + 모델 인자 push)로도 구현은 가능하지만, 알림 딥링크·복원을 위해 id 파라미터 라우트를 권고한다. `EntryGuard.redirect` 가 `full` 상태를 `/home` 으로 수렴시키므로(`lib/app/entry_guard.dart:38-51`) 경로 패턴·역할 매트릭스 재정의가 선행돼야 한다(셸 담당 에이전트와 공유 전제).

| 경로 | 화면 | 데이터 의존 | 가드 |
|---|---|---|---|
| `/mentor` | MentorHome | §5 홈 모델 | role=mentor |
| `/mentor/profile/edit` | MentorProfileEdit | 본인 `mentor_profiles` 행 + `subjects` 카탈로그 | role=mentor |
| `/mentor/pricing` | MentorPricing | `mentor_plans` 본인 3행, `mentor_individual_question_pricing` | role=mentor ∧ 승인(권고) |
| `/mentor/verification` | MentorVerification | 최신 `mentor_school_verifications` 1건, `student_id_image_url` 존재 여부 | role=mentor |
| `/mentor/verification/academic-change` | MentorAcademicChange | 최신 요청 1건, 현재 `university_name` | role=mentor |
| `/mentor/settlement` | MentorSettlement | summary(당월)+추이 6개월, 계좌 마스킹 | role=mentor |
| `/mentor/settlement/lines?month=YYYY-MM&type=` | MentorSettlementLines | lines(KST 월) | role=mentor |
| `/mentor/settlement/account` | MentorPayoutAccount | 은행 allowlist, 계좌 마스킹 | role=mentor ∧ 승인(F13 `MENTOR_NOT_APPROVED`) |
| `/mentor/reviews` | MentorReviews | reviews + stats + 작성자 라벨 | role=mentor |
| `/mentor/activity` | MentorActivity | 활동 상태 + (선택) 이력 | role=mentor |
| `/mentor/disputes`, `/mentor/disputes/:id` | MentorDisputes / Detail | disputes 행(+주문 번들은 CR 모델) | role=mentor |

### 4.4 멘토 전용 셸/네비 진입
- 웹 멘토 네비 잠금값은 질문방·개별 질문·맞춤의뢰·커뮤니티·정산·내 프로필·마이페이지(`lib/shell/mainNavItems.ts:67-75`). 앱 셸 구성은 셸 에이전트 소관이며, 본 도메인의 요구는 두 가지: ① 멘토 역할일 때 우측 상단 프로필 진입(`HomeShell._openMyPage`, `lib/app/home_shell.dart:115-133`)이 `MyPage` 대신 **`/mentor`(멘토 홈)** 또는 MyPage 내 "멘토 콘솔" 섹션으로 이어져야 한다 ② 정산·프로필은 탭이 아니라 멘토 홈의 하위 진입으로 두어 학생/멘토 탭 구성 차이를 최소화.
- 기존 `MentorDashboardSection` 은 `MentorHomeScreen` 으로 대체(3값 → §5 KPI). `kPayoutManageLinkEnabled` 분기(`mentor_dashboard_section.dart:77-85`)와 `openPayoutManageWeb`/`openProfileEditWeb`/`openReviewsWeb` 브릿지(`web_bridge_config.dart:26-37`)는 해당 화면이 네이티브로 들어오면 제거(오너 결정 #3 결과에 따라 정산 링크만 잔존 가능).
- 알림 딥링크: 멘토 수신 유형 중 본 도메인 목적지는 없다(`mentor_pause_notice` 는 학생 수신). 향후 관리자 승인/반려 알림이 생기면 `NotificationDestination` 에 `mentorVerification` 추가(exhaustive switch 4곳 — 앱 리포트 §9-1 #4).

### 4.5 매니페스트 갱신 항목 (`test/contracts/outbound_api_manifest_test.dart`, 집합 동일성)
- `kExpectedRpcNames`(`:15`) 추가: `mentor_profile_update_self`, `mentor_plan_prices_set_self`, `mentor_payout_account_update_self`, `set_individual_question_price`, `mentor_settlement_summary`, `mentor_settlement_lines`, `mentor_cap_used`, `mentor_cap_limit`, `subscription_cap_weight`(또는 `mentor_cap_usage_self` 1개), `get_mentor_review_stats`, `mentor_student_id_document_set_self`, `mentor_activity_pause_self`, `mentor_activity_resume_self`, `mentor_activity_terminate_self`, (채택 시) `mentor_review_reply_self`, `mentor_activity_events_self`, `mentor_settlement_self`, `payout_bank_allowlist`. 이미 있음: `user_profile_update_self`, `get_mentor_student_nicknames`.
- `kExpectedTables`(`:77`) 추가: `reviews`, `mentor_school_verifications`, `mentor_academic_record_change_requests`, `disputes`, (라벨용 채택 시) `school_tier_catalog`, `major_category_catalog`, (F7 병합 읽기용) `mentor_profiles` 는 이미 포함, `subjects`(과목 카탈로그를 서버에서 읽을 경우). 수익 차트는 기존 `my_cash_ledger_v1` 로 처리해 `cash_ledger` 리터럴을 추가하지 않는다.
- `kExpectedBucketIdentifiers`/`kExpectedBucketNames`(`:120-137`): `MentorDocumentUploadGateway.bucket = 'student-id-images'`, `MentorAvatarGateway.bucket = 'profile-avatars'` 상수 경유(리터럴 금지).
- `kExpectedSchemas` 는 `{api_app_v1, api_web_v1}` 유지(스키마 인자를 식별자로 넘기면 `kExpectedSchemaIdentifiers` 에 `schema` 가 이미 있음).
- iOS: 서류 업로드 도입 시 `kExpectedCollectedDataTypes`(`test/contracts/ios_release_config_contract_test.dart:44-47`)와 `PrivacyInfo.xcprivacy` 에 수집 유형 추가(사진 이미 포함 · 학생증/재학증명은 별도 유형 판단 — **(확인 필요: Apple 분류)**).

---

## 5. 데이터 모델 (테이블/뷰/RPC 반환 → Dart)

| Dart 모델 | 원천 | 필드(컬럼 → Dart) | 비고 |
|---|---|---|---|
| `MentorProfileSelf` | `mentor_profiles` 본인 행 | `user_id→userId`, `university_name`, `department_name`, `high_school_name?`, `teaching_subjects text[]→List<String>`, `intro_line?`, `bio?`, `answer_style?`(폼 없음·F7 보존용), `profile_image_url?`, `verification_status`, `is_open_for_subscriptions bool`, `cap_limit num`, `student_id_image_url?`(존재 여부만 사용), `payout_bank_name?`, `payout_account_number?`(마스킹 후 폐기), `activity_status`, `pause_started_at?`, `pause_until?`, `pause_reason?`, `last_pause_at?`, `termination_requested_at?`, `termination_effective_at?`, `abandonment_flagged_at?`, `updated_at` | 컬럼 출처 `001…:45-56`, 041, 050, 060, 097, 103, 131(`is_open_for_subscriptions`), 134. 쓰기는 F7/F13/RPC 만 |
| `MentorPlanSelf` | `mentor_plans` where `mentor_id=me` | `plan_tier(limited/standard/premium)`, `amount_cents→cashKrw = ÷100`, `cap_weight`, `is_active`, `price_updated_at?`, `label?` | 기존 `MentorPlan`(`lib/features/mentors/data/mentor_models.dart:19-50`) 확장 가능 |
| `IndividualQuestionPricing` | `mentor_individual_question_pricing` | `mentor_id`, `amount_cents`, `updated_at` | RPC 반환 SETOF 도 같은 shape |
| `PlanPriceBandError` | F8 envelope | `code`, `tier`, `minCashKrw`, `maxCashKrw`, `givenCashKrw` | 앱 상수 사본 금지 |
| `SchoolVerification` | `mentor_school_verifications` 최신 1건 | `id`, `status(pending/approved/rejected/resubmit_required/superseded → enum+unknown)`, `verified_university_name?`, `verified_department_name?`, `verified_major_category?`, `school_tier?`, `document_storage_ref?`(파일명 표시만), `reviewed_by?`(null=잠정), `reviewed_at?`, `reject_reason?`, `created_at`, `updated_at` | 웹 select 컬럼 `lib/mentor/mentorSchoolVerification.ts:20-37`. `reviewed_by IS NULL` = 잠정(192) |
| `AcademicRecordChangeRequest` | `mentor_academic_record_change_requests` 최신 1건 | `id`, `status(4값)`, `requested_university_name`, `change_reason?`, `document_storage_ref?`, `approved_university_name?`, `reviewed_at?`, `reject_reason?`, `created_at` | `089…:14-36` |
| `SettlementSummary` | `mentor_settlement_summary` jsonb | `month`, `runDate`, `cutoff`, `payoutAccountRegistered`, `confirmed{count,grossCents,platformFeeCents,mentorAmountCents,withholdingCents,netCents}`, `accruing{count,mentorAmountCents,withholdingCents,netCents,lastPeriodEnd?,expectedRunDate?}`, `held{count,mentorAmountCents}`, `paidTotal{count,mentorAmountCents,netCents}`, `bySourceThisMonth: Map<String,{mentorAmountCents,count}>`, `withholdingRule` | 웹 타입 `lib/mentor/mentorSettlementSchema.ts:51-80`; cents 정수 강제·스키마 위반은 오류 상태(0 렌더 금지) |
| `SettlementLine` | `mentor_settlement_lines` | 17열 그대로(`sourceType(subscription/custom_request/individual_question)`, `sourceId`, `occurredAt`, `periodStart?`, `periodEnd?`, `grossCents`, `platformFeeCents`, `mentorAmountCents`, `feeRate?`, `withholdingCents`, `netCents`, `status(5종+unknown 보존)`, `holdReason?`, `completionTs?`, `expectedRunDate?`, `paidRunDate?`, `paidAt?`) | 상태 5종 외 값은 그대로 보존해 오류 칩(웹 규약) |
| `PayoutAccountView` | `mentor_profiles.payout_*` → 마스킹 | `bankName?`, `accountMasked?`(끝 4자리) | 원문은 모델에 두지 않는다 |
| `PayoutAccountUpdateResult` | F13 envelope | `updatedAt`, `accountMasked` | |
| `ReceivedReview` | `reviews`(공개 가시) | `id`, `author_id`, `rating`, `body`, `mentor_reply?`, `mentor_replied_at?`, `created_at`, `authorLabel`(RPC 조인, 폴백 '학생') | `is_hidden/is_blinded/moderation_state` 는 서버 필터라 모델 불필요 |
| `ReviewStats` | `get_mentor_review_stats` | `reviewCount`, `avgRating?`, `d1..d5` | |
| `CapUsage` | RPC 3종(+`subscriptions` count) 또는 `mentor_cap_usage_self` | `usedCap?`, `capLimit?`, `weightByTier{limited,standard,premium}?`, `activeCount?`, `pct`, `isFull`, `indeterminate` | 판정식 `mentorCapUsageCore.ts:85-97` |
| `MentorActivityInfo` + `enum MentorActivityState {active, paused, terminating, terminated}` | `mentor_profiles` 활동 컬럼 | `state(now 기준 판정 — paused∧pause_until<=now → active)`, `pauseUntil?`, `terminationEffectiveAt?`, `lastPauseAt?`, `canRequestRest`(KST 6개월) | `lib/mentor/mentorActivity.ts:19-56` 이식 |
| `MentorActivityEvent`(선택) | `mentor_activity_events_self` | `id`, `eventType`, `reason?`, `status`, `createdAt`, `pauseUntil?`, `effectiveAt?` | |
| `MonthlyRevenuePoint` | `my_cash_ledger_v1`(delta_cents>0, KST 5개월) | `yearMonth`, `totalCashKrw` | 웹 `mypage/page.tsx:67-111` 규칙(빈 달 0) |
| `MentorHomeKpis` | 합성 | `pendingAnswers`(기존 `ThreadStatusCounts.pending`), `activeSubscribers`(`subscriptions` status='active' count), `thisMonthMentorAmountCents`(summary by_source 합), `avgRating?`, `reviewCount` | 웹 KPI 대응(`mentorHubDashboardQueries.ts:256-266`) — 맞춤의뢰 KPI 는 CR 에이전트 모델 |
| `DisputeListItem` | `disputes` | `id`, `status`, `custom_request_order_id?`, `student_id?`, `mentor_id?`, `created_at`, 사유/요약 컬럼 **(확인 필요: 정확 컬럼명 — 웹 `mapRowToListItem` 은 select * 후 매핑)** | RLS `dispute_select` |
| `SchoolTierCatalogItem` / `MajorCategoryItem`(선택) | 카탈로그 2표 | `code`, `label`, `display_order`, `is_active` | `079_b…:76-98` |

---

## 6. 구현 순서·의존성·규모

규모: S(≤1일) · M(2~4일) · L(1~2주) · XL(2주+). **서버 변경(S단계)은 웹 저장소 pack 절차(DB 리포트 §5.2)로 앱 구현보다 선행**한다 — 앱 저장소에는 SQL 을 두지 않는다.

| 단계 | 내용 | 의존 | 규모 |
|---|---|---|---|
| S1 (서버) | `api_app_v1` wrapper 3종(F7/F8/F13 위임, F7 에 `p_expected_updated_at` 선택) + 계약 §7/§9 갱신 + `contracts:export/verify` | 오너 결정 #5 | S~M |
| S2 (서버) | `mentor_student_id_document_set_self` (+ 선택 `mentor_school_verification_submit_self`, `mentor_academic_record_change_submit_self`) | 오너 결정 #3(서류) | S(+S+S) |
| S3 (서버) | 활동 RPC 3종(`pause/resume/terminate_self`) + `core_private` impl + (선택) `mentor_activity_events_self` | 오너 결정 #4 | M |
| S4 (서버) | `mentor_review_reply_self`, (선택) `mentor_cap_usage_self`, `payout_bank_allowlist` | 오너 결정 #7 | S |
| A0 (앱 코어) | envelope 파서 1벌·`MentorConsoleRpcBackend`(schema 인자)·매니페스트 갱신·`DataRefreshBus` 세대 2종·서류 정책 순수 함수 | 없음(앱 재구축 코어와 병행) | M |
| A1 | 멘토 홈: KPI(요약 RPC)·cap(RPC 3종 직접)·활동 상태 판정·인증 배지·최근 후기·수익 차트(`my_cash_ledger_v1`)·구독 토글(F7) | A0, (토글은 S1 wrapper 또는 api_web_v1 직접) | M |
| A2 | 프로필 편집(F7 병합 저장·과목·아바타 업로드/보상 삭제) + 닉네임(기존 RPC) | A0, S1(권고) | M |
| A3 | 가격 설정(F8·IQ 단가) | 오너 결정 #1·#2, S1 | S |
| A4 | 정산: 월 요약·추이 6개월·라인(월/유형)·계좌 마스킹 | A0 | M |
| A5 | 정산 계좌 등록(F13) | 오너 결정 #3(계좌), S1 | S |
| A6 | 받은 리뷰·통계·작성자 라벨·답글 | A0, S4(권고) | S~M |
| A7 | 인증 화면: 학교 서류 제출·학생증 제출·학적 변경 요청·현황 조회 | 오너 결정 #3(서류), S2, iOS privacy 갱신 | M |
| A8 | 활동 관리 3종 | S3 | S |
| A9 | 분쟁 목록/상세(조회 전용) | CR 에이전트의 주문 번들 모델 | S |
| 총계 | 서버 S~M×4 · 앱 M×5 + S×5 | | **L**(오너 결정 전부 포함 시 L~XL) |

권장 착수 순서: A0 → A1 → A4 → A6 → A2 (결정 불요·읽기 중심) → 결정 후 S1~S4 → A3/A5/A7/A8 → A9.

---

## 7. 오너 결정 필요 항목

| # | 질문 | 권고 | 근거 |
|---|---|---|---|
| 1 | 플랜 가격 설정(F8)을 앱에 넣는가 | **포함** — 멘토 전용 라우트, 학생 가격표·구매 CTA 와 화면 분리, 밴드 안내는 서버 envelope 값만 표시 | §1.1; DB 리포트 §4 #21 "판매자 콘솔 행위" |
| 2 | 개별질문 단가 설정을 앱에 넣는가 | **포함**(#1 과 동일 판정). 승인 게이트 서버 추가 여부는 별도(현행 미적용 유지 권고 — 웹과 동일) | `094…:60-63` 주석 |
| 3 | 민감 서류(학생증·학교 서류·학적 서류) 앱 업로드 — 2026-07 "웹 전용" 출시 결정 번복 여부 · 정산 계좌 등록(F13) 앱 포함 여부 | **서류: 포함**(제출·상태만, 원본 열람 제외, iOS 수집 유형 갱신) · **계좌: 조건부 포함**(구매 유도 아님, `kPayoutManageLinkEnabled` 정책 문서 갱신) | `docs/RELEASE_SCOPE_DECISIONS_2026-07.md` §1; `commerce_policy.dart:25-33`; DB 리포트 §4 #19 |
| 4 | 활동 관리(일시중단·복귀·종료 신청) 앱 포함 여부 — DB 리포트 §6 #7 은 1차 "웹 위임" 권고 | **포함 3종**(자금 이동 없음 · 환불은 배치 `finalize` 로 분리돼 있음) · 무단 이탈 제외 · 웹 액션도 같은 impl 로 전환하는 후속 작업 승인 | `mentorActivityService.ts:98-132, 228-308`; §3(c) 12 |
| 5 | 앱이 `api_web_v1` 쓰기 RPC(F7/F8/F13)를 직접 호출해도 되는가, 아니면 `api_app_v1` wrapper 를 먼저 만드는가 | **wrapper 선행**(B-07 원칙·스키마 단위 매니페스트 잠금). 단 wrapper 적용 전 개발 편의로 `api_web_v1` 직접 호출을 **임시 허용**할지 결정 | `api_web_v1_contract_v1_1.md:2729`; `20260730112525…:6-9` |
| 6 | 아바타 업로드 앱 포함 | **포함**(public 버킷·F7 참조 검증 존재 · 5MB 사전 축소 재사용) | `097…`, `image_downscaler.dart:18` |
| 7 | 리뷰 답글을 직접 UPDATE 로 두는가, RPC 로 서버 규칙(2~500자·0행 판정)을 올리는가 | **RPC**(`mentor_review_reply_self`) | §3(b) #7 |
| 8 | 멘토 본인 활동 이력 노출 | **보류 또는 최소**(최근 N건, `detail` 키 선별 RPC) — 웹도 미노출 | `103…:60` |
| 9 | 홈 "이번 달 수익" 정의 | `mentor_settlement_summary.by_source_this_month` 합(mentor_amount_cents)로 통일, 차트는 `cash_ledger` 인입으로 별도 라벨 | §3(c) 8 |
| 10 | 정산 엑셀 다운로드 | **제외** | 웹 리포트 §6.4 |
| 11 | 정산 라인에 학생 라벨(V7 `student_label`, 닉네임) 노출 여부 | **미노출**(라인 RPC 만 사용, V7 미채택 → 매니페스트 최소화) | §3(a) V7 |
| 12 | 은행 allowlist 앱 상수 복제 vs 서버 RPC | **서버 RPC**(`payout_bank_allowlist`) 또는 카탈로그 표; 상수 복제 시 189 류 변경마다 앱 릴리즈 필요 | `189_payout_bank_allowlist_add_im_bank.sql` |
| 13 | F7 낙관적 잠금(`p_expected_updated_at`) 도입 | **도입**(학적 승인과 경합 방지) | §3(c) 2·3 |

---

## 8. 리스크·지뢰

1. **F7 전면 교체 경합**: 앱이 읽은 뒤 저장하는 사이 관리자 학적 승인(service_role `university_name` 갱신, `lib/admin/mentorAcademicRecordChangeReviewActions.ts:116`)이 끼면 승인값이 되돌아가고 192 B-4 트리거가 학교 인증을 pending 으로 되돌린다(`192…:340-390`). 낙관적 잠금 없으면 "저장 직전 재조회" 를 최소 방어로.
2. **가격 밴드 이중 정본**: DB(F8 리터럴 `29900/84900/174900 ~ 69900/149900/329900`)와 TS(`lib/subscribe/mentorPlanPricing.ts`) 두 곳 — 앱에 3번째 사본을 만들지 말고 envelope `min/max` 만 표시.
3. **cap 가중치 사본 금지**: 1.0/2.25/4.75·한도 50 은 DB 함수 정본(CLAUDE.md DB-1) — 앱은 RPC 결과만 사용.
4. **`api_app_v1` ↔ `api_web_v1` 로직 이원화**: 활동 RPC 를 impl 로 만들고 웹 액션을 전환하지 않으면 웹(service_role TS)과 앱(SQL impl)의 규칙이 갈라진다. 구독 기간 연장 계산(`addDaysIso`)·KST 6개월 판정(`addMonthsClampedKst`)을 SQL 로 옮길 때 시간대 처리 검증 필요.
5. **자동 복귀 미반영**: `paused` 행이 `pause_until` 경과 후에도 DB 에 남는다 → 앱 판정식 불일치 시 잘못된 상태 표시. 웹 `mentorActivityState` 와 같은 규칙을 순수 함수로 두고 테스트.
6. **`student-id-images` 무제한 버킷** + 클라이언트 검증 의존. 앱 우회 업로드 방지는 RLS(own-folder)만. RPC #9 로 크기·MIME 서버 검사 보강 권고.
7. **`profile-avatars` public**: 업로드 즉시 공개. 실패 시 보상 삭제 누락 → 고아 공개 객체. 탈퇴 수집기는 owner_id 기준(앱 세션 업로드는 채워짐).
8. **매니페스트 집합 동일성**: RPC/테이블/버킷 추가마다 `outbound_api_manifest_test.dart` 갱신 없으면 CI 실패(`:196,250,271`). 버킷 리터럴 금지.
9. **iOS 계약 테스트**: 학생증 업로드 도입 시 `PrivacyInfo` 수집 유형·`kExpectedCollectedDataTypes` 갱신 없으면 실패(`ios_release_config_contract_test.dart:44-47`). `PaymentInfo` 는 금지 집합 유지(정산 계좌는 "결제정보" 로 분류되는지 **(확인 필요: Apple/Play 데이터 안전 분류)**).
10. **정산 화면의 스토어 리젝 표면**: 계좌 등록·지급 예정 금액·원천징수 표기는 허용 범위지만, "캐시 부족" 이나 충전 링크 문구가 섞이면 정책 §4 위반. 알림 `subscription_renewal_failed_insufficient_cash` 링크 억제 유지.
11. **리뷰 작성자 라벨 공백**: `users` RLS 로 타인 행 0행 → `get_mentor_student_nicknames` 범위(활성 구독 또는 방 관계) 밖 작성자는 '학생' 폴백. 구독 만료 후 방 삭제 여부 **(확인 필요)**.
12. **`mentor_activity_events` GRANT 실측 필요**: 정책 추가안(`mae_select_own`)은 authenticated SELECT GRANT 가 남아 있어야 동작(2026-08-02 default ACL 하드닝 이전 테이블이라 잔존 추정 — **(확인 필요)**). RPC 안이 안전.
13. **정산 RPC 는 세션 JWT 필수**: service_role 로 호출하면 `auth.uid()` NULL 로 빈 결과(`lib/mentor/mentorSettlementService.ts:23-26`) — 앱은 항상 사용자 세션이라 문제 없음. 요약 스키마 위반은 0 렌더 대신 오류 상태(웹 fail-closed 규약).
14. **KST 월 경계**: `kstMonthBounds`(월 반개구간)·`expected_run_date`(익월 23일)·원천징수 3.3% 는 서버 값 그대로 표시, Dart 재계산 금지. 라인 조회 `p_from/p_to` 만 KST 경계로 만들어 보낸다.
15. **`set_individual_question_price` 반환이 SETOF·raise 스타일**: envelope 파서를 태우면 실패로 오판 — 별도 경로.
16. **분쟁 상세 의존성**: 주문 번들(`custom_request_orders` 등) 컬럼·RLS 는 CR 에이전트 정본 — 본 도메인은 `disputes` 행만 보장.
17. **Realtime 부재**: 승인·인증·정산 상태는 resume 재조회에 의존. IndexedStack 상주 화면은 `ResumeVisibilityGate` 로 보이는 화면만 재조회(전역 폴링 금지).
18. **계좌 원문 취급**: F13 응답·`mentor_profiles` 읽기 모두 마스킹 후 즉시 폐기, Sentry(`sendDefaultPii=false`)·로그·SharedPreferences 에 싣지 않는다.
19. **20260730195156 검증 블록과 계약 스냅샷**: 1회성 DO 블록이라 재실행 충돌은 없지만 `contracts:verify` 스냅샷(`scripts/contracts/*.mjs`)은 wrapper 추가 후 `contracts:export` 로 재생성해야 CI green.
20. **웹 `/mentor/dashboard`·`/mentor/channel` 부재**: CLAUDE.md 라우트 표와 코드 불일치(웹 리포트 부록 A-1) — 앱은 웹 `/mentor/mypage` 를 정본으로 삼는다.
