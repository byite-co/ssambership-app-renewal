# 웹 멘토 콘솔 리포트 (질문방·맞춤의뢰 제외)

- 대상 저장소: `/home/user/ssambership_web` (Next.js 16 App Router + Supabase). 비교 대상 앱: `/home/user/ssambership-app` (Flutter).
- 범위: `app/(mentor)/**` 중 질문방(`question-room`)·맞춤의뢰(`custom-request`) 제외. 프로필 편집·학교 인증·학적 변경·정산·리뷰·채널·마이페이지·community/new·support/disputes·레거시 questions·individual-questions(표만).
- 근거 표기는 `파일:행`. 코드로 확인하지 못한 항목은 **(확인 필요)**.
- 읽은 것: `app/(mentor)/layout.tsx`, 위 라우트 page/loading 전부, `app/api/mentor/payouts/detail/route.ts`, `lib/mentor/**` 47개(테스트 12개 헤더 포함), `lib/home/mentorDashboardQueries.ts`, `lib/reviews/**`, `lib/payout/**`, `lib/subscribe/mentorCapService.ts·mentorCapUsageCore.ts·mentorPlanPricing.ts`, `components/mentor/**`(목록 + 주요 클라이언트 컴포넌트 액션 호출), `supabase/sql` 041·050·077·089·190~193, `20260729211929`·`20260730112528`·`20260730112531`·`20260730195147`·`20260730195150`(sql/ 아래에 있음 — migrations/ 에는 `2026073112xxxx_…` 사본), `supabase/migrations` 20260827100200·20260827100300·20260830150838·20260903100300·20260903200100, 보조로 001·070·094·097·103·106·120·126·171·173·174·079_b·086·013·20260803162808·20260730105248·20260730095441.

---

## §0 공통 전제 (전 라우트에 걸리는 게이트·권한)

| 항목 | 사실 | 근거 |
|---|---|---|
| 그룹 레이아웃 게이트 | `x-pathname` 헤더로 `mentorBlockedCashPath()`(`/cash`, `/wallet/ledger`)면 `/mentor/mypage` 로 redirect → `requireRole("mentor")` → `needsIdentityOnboarding(profile)` 이면 `/onboarding/verify` | `app/(mentor)/layout.tsx:10-19`, `lib/shell/mainNavItems.ts:12,140-142`, `lib/identity/identityGateFlag.ts:12-24` |
| 본인인증 게이트 플래그 | 서버 env `IDENTITY_GATE_ENABLED === "true"` 일 때만 `profile.identity_verified_at == null` 검사. 기본 OFF | `lib/identity/identityGateFlag.ts:12-24` |
| `requireRole` | 쿠키 세션 → `public.users` 프로필 role 대조. 미로그인 → `/login/mentor?next=…`, 역할 불일치 → `getPostLoginPath(role)`(mentor 홈 = `/mentor/mypage`) | `lib/auth/routeGuard.ts:41-59`, `lib/auth/getPostLoginPath.ts:26-31` |
| 멘토 헤더 네비 잠금값 | 질문방·개별 질문·맞춤의뢰(플래그 OFF 시 숨김)·커뮤니티·정산·내 프로필·마이페이지 | `lib/shell/mainNavItems.ts:67-75,115-126` |
| `mentor_profiles` 직접 쓰기 | anon·authenticated 테이블 권한 `REVOKE ALL` + `GRANT SELECT` 만(M11). 쓰기는 SECDEF RPC(F7/F8/F13) 또는 service_role 경유만 | `supabase/sql/20260730195147_revoke_mentor_profiles_write.sql:80-81` |
| `mentor_plans` 직접 쓰기 | 동일하게 SELECT 만(M12). 쓰기는 F8 또는 service_role | `supabase/sql/20260730195150_revoke_mentor_plans_write.sql:63-64` |
| `mentor_profiles` SELECT RLS | `mentor_select_own`(본인) + `mp_admin_select_all`(관리자). 타인 행은 0행 — 공개 읽기는 뷰 `api_web_v1.mentor_directory_v1` | `supabase/sql/001_initial_auth_profile.sql:212`, `120_admin_console_fixes.sql:48-50`, `lib/auth/mentorPublicRead.ts:6-18` |
| 특권 컬럼 가드 | `verification_status`·`cap_limit` 변경은 service_role / JWT 없음 / admin 만 — 위반 시 `MENTOR_PROFILE_PRIVILEGED_COLUMN_FORBIDDEN`(42501). 190 에서 INSERT 기본값 판정 28→50 갱신 | `supabase/sql/20260729211929_mentor_profile_privileged_column_guard.sql:21-47`, `190_cap_structure_limit_50_weights.sql:138-175` |
| `api_web_v1` envelope | 명령 RPC 는 `{ok:true, contract_version, …}` / `{ok:false, contract_version, code}`. 웹 공통 호출부 `callApiWebV1Rpc(supabase, fn, args)` 가 `supabase.schema("api_web_v1").rpc()` 호출 | `lib/apiWebV1/rpc.ts:15-59` |
| service_role 클라이언트 | `createServiceRoleClient()` — `SUPABASE_SERVICE_ROLE_KEY`, `server-only` | `lib/supabase/admin.ts:12-23` |

---

## §1 라우트별 기능 표

열: 라우트 | 목적 | 역할 | 사용자 액션(읽기/쓰기) | 서버 표면 | 결제 접촉 | 플래그·게이트 | 앱 이식 메모

| 라우트 | 목적 | 역할 | 사용자 액션 | 서버 표면 (RPC / 테이블·뷰 / service_role / API route) | 결제 접촉 | 플래그·게이트 | 앱 이식 메모 |
|---|---|---|---|---|---|---|---|
| `/mentor/dashboard` | (라우트 부재) | mentor | — | `app/(mentor)/mentor/dashboard/` 에 `loading.tsx` 만 존재, `page.tsx` 없음. `components/mentor/dashboard/*`(KpiCards·SideNav 등 8개)는 어떤 라우트에서도 import 되지 않음(grep 0건). 로그인 후 홈은 `/mentor/mypage`(`lib/auth/getPostLoginPath.ts:28`) | 없음 | — | 이식 대상 아님. CLAUDE.md 의 `/mentor/dashboard` 표기는 코드와 불일치 **(확인 필요: 런타임 404 여부)** |
| `/mentor/mypage` | 멘토 통합 홈(KPI·수익 차트·활동 관리·구독 열림 토글·최근 후기·cap) | mentor | 읽기: KPI·차트·후기·cap·활동상태. 쓰기: 활동 종료/일시중단/복귀, 구독 열림 토글 | §2 참조. 읽기: `mentor_student_rooms`·`question_threads`·`subscriptions`·`custom_request_orders`·`custom_request_applications`·`disputes`·`reviews`·`mentor_profiles`(본인)·`cash_ledger`·V7 `api_web_v1.mentor_settlement_self()`·`custom_order_settlement_items`·`individual_questions`·`payout_run_items`·RPC `list_open_custom_request_posts_for_mentor_browse(p_limit)`. cap: RPC `mentor_cap_used/mentor_cap_limit/subscription_cap_weight` **service_role 클라이언트로 호출**(`lib/subscribe/mentorCapService.ts:23-43`). 쓰기: 활동 액션 4종 **service_role**(`lib/mentor/mentorActivityActions.ts:27,46,66,76`), 토글은 F7 RPC | 상태 읽기(정산 예상액·cash_ledger 인입) | 승인 전 배너(`verification_status`), 계정삭제 링크 `NEXT_PUBLIC_FEATURE_ACCOUNT_DELETION`(기본 ON) `app/(mentor)/mentor/mypage/page.tsx:486` | 기존 앱 `MentorDashboardSection`(구독 학생·답변 대기·최근 정산) 확장 지점. 활동 액션·cap 은 §9 대체 RPC 필요 |
| `/mentor/profile` | `/mentor/profile/edit` 로 redirect | mentor | — | — | 없음 | — | 불필요 |
| `/mentor/profile/edit` | 프로필 편집(사진·소개·과목·요금제·개별질문 단가·구독 공개) | mentor | 읽기: 본인 `mentor_profiles`·`users`·`mentor_plans`·`mentor_individual_question_pricing`. 쓰기: 아바타 업로드 + F7 + F8 + `set_individual_question_price` | server action `submitMentorProfileEdit`(`lib/mentor/mentorProfileEditActions.ts:35`) → Storage `profile-avatars` 업로드 → `api_web_v1.mentor_profile_update_self(9인자)` → `api_web_v1.mentor_plan_prices_set_self(3인자)` → `public.set_individual_question_price(p_amount_cents)`. service_role 미사용 | 없음(가격 **설정**만, 결제 실행 없음) | 과목 0개면 구독 공개 불가(`lib/mentor/mentorProfileMutations.ts:148-150`), 밴드 밖 가격은 클라 선차단 + DB 거부 | §3. 앱은 동일 RPC 3종 직접 호출 가능(authenticated GRANT) |
| `/mentor/verification` | 학교·전공 인증 서류 제출 + 학생증 사후 제출 | mentor | 읽기: `mentor_profiles`(본인)·`mentor_school_verifications`(본인 최신 1건). 쓰기: Storage 업로드 + `mentor_school_verifications` INSERT / `mentor_profiles.student_id_image_url` UPDATE | server action 2종: `submitMentorSchoolVerificationAction`(세션 클라이언트, `lib/mentor/mentorSchoolVerificationActions.ts:31-79`), `submitMentorStudentIdImageAction`(**service_role** UPDATE, `lib/mentor/mentorStudentIdActions.ts:74-79`) | 없음 | 학교 서류는 `status==='pending'` 이면 재제출 잠금(`app/(mentor)/mentor/verification/page.tsx:127`) | §4. 학생증 컬럼 반영은 service_role 전용 → 대체 RPC 필요 |
| `/mentor/academic-record-change` | 학적 변경 요청(학교명 잠금 우회 경로) | mentor | 읽기: 본인 `mentor_profiles.university_name`, `mentor_academic_record_change_requests` 최신 1건. 쓰기: Storage 업로드 + INSERT | server action `submitMentorAcademicRecordChangeAction`(세션 클라이언트, `lib/mentor/mentorAcademicRecordChangeActions.ts:30-81`) | 없음 | `status==='pending'` 이면 제출 잠금(`page.tsx:64`) | §5. 앱 직접 INSERT 가능(RLS `macc_insert_own_pending`) |
| `/mentor/payouts` | 정산 요약(당월 확정/적립/보류/지급합계·추이·계좌·성과) | mentor | 읽기: RPC 2종 + 계좌 마스킹 + 성과 라인. 쓰기: 정산 계좌 등록/변경 | RPC `public.mentor_settlement_summary(p_month date)`·`public.mentor_settlement_lines(p_from,p_to)`(세션), `mentor_profiles.payout_bank_name/payout_account_number`(본인 SELECT), 성과 라인은 `custom_request_orders`·`custom_order_settlement_items`·V7. 쓰기 F13 `api_web_v1.mentor_payout_account_update_self(p_bank_name, p_account_number)` via server action `updateMentorPayoutAccountAction`(`lib/mentor/mentorPayoutAccountActions.ts:41-69`). service_role 미사용. 월 변경 시 `/api/mentor/payouts/detail?month=` fetch(`components/mentor/payouts/MentorPayoutsMain.tsx:72`) | 상태 읽기(정산). 계좌 등록은 **계좌 정보 저장이지 결제/지급 실행이 아님**(§6) | F13 은 승인 멘토만(`MENTOR_NOT_APPROVED`) | §6. RPC 3종 모두 authenticated GRANT → 앱 직접 호출 가능 |
| `/mentor/payouts/detail` | 정산 상세(월·유형 필터·엑셀) | mentor | 읽기 | 클라이언트 `fetch('/api/mentor/payouts/detail?month=YYYY-MM&type=…')` → `GET app/api/mentor/payouts/detail/route.ts` → RPC `mentor_settlement_lines`. 엑셀은 `xlsx` 클라이언트 생성 | 상태 읽기 | API 인증 `requireMentorApiSession()`(쿠키 세션 + role mentor, 401/403) | API route 는 RPC 얇은 래퍼 — 앱은 RPC 직접 호출 |
| `/mentor/reviews` | 받은 리뷰 목록 + 답글 1회 | mentor | 읽기: `reviews`(본인 mentor_id, 공개 가시 행만). 쓰기: 답글 | `listMentorReceivedReviews`(세션, `lib/reviews/reviewQueries.ts:357-382`), 답글 `PATCH /api/reviews/[id]/reply` → `replyToReview` → `reviews` UPDATE(`mentor_reply`, `mentor_replied_at`) | 없음 | 답글 2~500자·1회(RLS `reviews_update_mentor` + 트리거 `reviews_enforce_update`) | §7. 앱은 동일 UPDATE 직접 가능(RLS 허용) 또는 신규 RPC |
| `/mentor/channel` | (라우트 부재) | mentor | — | `loading.tsx` 만 존재. D-MT-13 으로 미디어 스텁·채널 UI 제거(`lib/mentor/mentorProfileQueries.ts:16-19`). 참조 링크 0건 | 없음 | — | 이식 대상 아님. `MENTOR_CHANNEL_DATA_MODEL` 문자열 상수만 잔존(`lib/mentor/mentorDataModel.ts:9-12`) |
| `/mentor/community/new` | 레거시 작성 진입 → 분리 경로 redirect | mentor | — | `?tab=shortform` → `/community/shortform/new`, 그 외 `/community/new`(+`draftId`) (`app/(mentor)/mentor/community/new/page.tsx:9-14`, `lib/community/communityComposeTab.ts:3-14`) | 없음 | — | 커뮤니티 리더 범위. 코드에 XW-21 식별자 없음 **(확인 필요)** |
| `/mentor/support/disputes` | 멘토 측 분쟁 목록(조회 전용) | mentor | 읽기 | `disputes` where `mentor_id = me` limit 40(`lib/disputes/disputeListQueries.ts:209-234`), 세션 클라이언트 | 상태 읽기(환불·분쟁) | — | 분쟁 RLS(036)는 미열람 **(확인 필요)** |
| `/mentor/support/disputes/[id]` | 분쟁 상세(조회 전용) | mentor | 읽기 | `loadDisputeById` + `canPartyViewDispute(userId,'mentor',row)`(student_id 또는 mentor_id 일치, `lib/disputes/disputeQueries.ts:272-285`). `DisputeMentorPageBody` 는 `DisputeDetailView` 만 렌더(액션 import 0) | 상태 읽기 | — | 읽기 전용이라 앱 직접 SELECT 로 대체 가능 |
| `/mentor/questions`, `/mentor/questions/[roomId]` | 레거시 redirect → `/mentor/question-room[/roomId]` | mentor | — | — | 없음 | — | 불필요 |
| `/mentor/individual-questions` | 나에게 온 개별 질문 + 공개 질문 보드 | mentor | 읽기·쓰기(다른 리더 범위) | `assertMentorApprovedForAction` 게이트 통과 시 `fetchMentorOwnedIndividualQuestions`·`fetchOpenIndividualQuestionsForMentor(80)`. 단가 설정 링크 → `/mentor/profile/edit` | 상태 읽기(예치/정산) | 미승인 멘토는 목록 빈 배열 + 안내(`page.tsx:36-42`) | 개별질문 리더 범위 |
| `/mentor/individual-questions/[questionId]` | 개별 질문 상세 | mentor | (다른 리더 범위) | 미승인 → 목록으로 redirect(`page.tsx:25-26`), 소유 검사 `designated_mentor_id`/`claimed_mentor_id`(`:30-34`) | 상태 읽기 | 승인 게이트 | 개별질문 리더 범위 |

---

## §2 멘토 대시보드(마이페이지) KPI 와 쿼리

라우트 `/mentor/mypage` (`app/(mentor)/mentor/mypage/page.tsx`). 실질 대시보드는 여기이며 `loadMentorHubDashboardData(supabase, mentorId)`(`lib/mentor/dashboard/mentorHubDashboardQueries.ts:192-280`)가 데이터 정본이다. 모두 **세션 클라이언트**(RLS)이며 service_role 은 cap 조회에만 쓴다.

### 2.1 `MentorHubDashboardData` (타입 `lib/mentor/dashboard/mentorHubDashboardTypes.ts:43-71`)

| KPI/블록 | 계산 | 데이터 소스 | 근거 |
|---|---|---|---|
| `kpis.newQuestions` | `threadStats.mentorQueueEstimate`(오류면 0) | `fetchRoomsForUser(supabase,"mentor",id)` → `mentor_student_rooms`(mentor_id, updated_at desc) → `aggregateThreadStatsForRooms(roomIds,{maxRooms:20,mode:"mentor"})` → `question_threads` | `mentorHubDashboardQueries.ts:196-203,256`, `lib/qna/questionRoomQueries.ts:49-58`, `lib/home/threadStats.ts:37-41` |
| `kpis.activeSubscribers` | `count(*)` | `subscriptions` where `mentor_id=me and status='active'` (head count) | `lib/home/mentorDashboardQueries.ts:52-66` |
| `kpis.newRequestsOpen` / `newRequestsToday` | `workspaceCounts.open` / 오늘(KST) 생성분 | RPC `list_open_custom_request_posts_for_mentor_browse(p_limit)`(200) + `custom_request_applications`(지원한 post 제외) | `mentorHubDashboardQueries.ts:207,234-236`, `lib/customRequest/mentorCounts.ts:23-52`, `lib/customRequest/customRequestQueries.ts:584-594` |
| `kpis.monthlyRevenue`, `monthlyRevenueMomPct` | `payoutsData.kpis.total.amount / momPct` — 이번 달(KST) 라인 순액 합(수수료 공제 후, 원천징수 전) | `loadMentorPayoutsPageData` (§6.5 레거시 라인 로더: V7 RPC + `custom_order_settlement_items` + `custom_request_orders` + `individual_questions` + `payout_run_items`) | `mentorHubDashboardQueries.ts:204,240,260-261`, `lib/mentor/mentorPayoutsService.ts:556-621` |
| `kpis.avgRating`, `reviewCount` | `reviews.rating` 평균(소수1)·건수(최대 500행). 0건이면 프로필 행 `avg_rating/review_count` 폴백 — 그러나 `mentor_profiles` 에 두 컬럼이 **없어**(`supabase/sql/20260730095441_api_web_v1_read_views.sql:27` 주석) 폴백은 null/0 | `reviews` where `mentor_id=me`(RLS 로 공개 가시 행만 보임) | `mentorHubDashboardQueries.ts:113-153` |
| `activeOrders`(최대 8) | `custom_request_orders`(mentor_id, updated_at desc 50) 중 work/delivery/revision 탭 분류 + 활성 분쟁 집합 | `custom_request_orders`, `disputes`(`custom_request_order_id in …`) | `mentorHubDashboardQueries.ts:205,215-232`, `lib/customRequest/orderDisputeHelpers.ts:41-50` |
| `openPosts.categories`, `topKeywords` | 카테고리 4종(study/career/essay/other) 비율, 키워드 14종 부분일치 상위 5 | 위 RPC 결과 | `mentorHubDashboardQueries.ts:39-111,237-238` |
| `todaySchedule` | 진행 주문 3건 + 답변 대기 질문 1항목 | 위 | `:246-248` |
| `revenuePanel` | `totalExpected=monthlyRevenue`, `inProgress=`진행 주문 gross×정책요율(맞춤의뢰 0.05 → 0.95) 추정, `completedPending=schedule.expectedPayoutAmount` | 정책 요율 `lib/payout/platformFeePolicy.ts:19-23` | `:155-171,241-244,272-277` |

### 2.2 마이페이지가 추가로 읽는 것 (`app/(mentor)/mentor/mypage/page.tsx`)

| 블록 | 소스 | service_role | 근거 |
|---|---|---|---|
| 인증 배지·활동 상태 | `mentor_profiles` 본인 행 `verification_status, activity_status, pause_until, termination_effective_at, pause_reason, last_pause_at` | 아니오 | `:143-158` |
| 5개월 수익 차트 | `cash_ledger` where `user_id=me and delta_cents>0 and created_at>=KST 5개월전`, 월별 `delta_cents/100` 합 | 아니오(RLS `cled_select`, `supabase/sql/004_p0_cash_disputes_admin_draft.sql:171`) | `:67-111` |
| 구독 수용량(cap) | `loadMentorCapUsage(user.id)` → RPC `mentor_cap_used(p_mentor_id)`, `mentor_cap_limit(p_mentor_id)`, `subscription_cap_weight(p_tier)`×3 + `subscriptions`(status ilike active) 카운트 | **예**(`createServiceRoleClient`; 키 부재 시 indeterminate) | `lib/subscribe/mentorCapService.ts:23-50`, `lib/subscribe/mentorCapUsageCore.ts:25-29,197-248` |
| 구독 열림 상태 | `mentor_profiles` 본인 `select *` → `is_open_for_subscriptions/accepts_subscriptions/accept_subscriptions` 중 false 면 닫힘, 실패 시 `{open:false, ok:false}`(fail-closed) | 아니오 | `lib/mentor/mentorSubscribeOpen.ts:34-53` |
| 최근 후기 3건 | `listMentorReceivedReviews(supabase,id,3)` | 아니오 | `:167` |

cap 함수 정본: `subscription_cap_weight` limited 1.0 / standard 2.25 / premium 4.75, `mentor_cap_limit` = `mentor_profiles.cap_limit`(행 없으면 50), `mentor_cap_used` = active 구독 가중치 합(SECDEF). 세 함수 모두 `GRANT EXECUTE … TO anon, authenticated, service_role`(`supabase/sql/050_mentor_subscription_cap.sql:63-92`, `190_cap_structure_limit_50_weights.sql:93-124`) → 앱에서 직접 호출 가능(service_role 불필요). `isFull = used + weight.limited > limit`(`mentorCapUsageCore.ts:96`).

---

## §3 프로필 편집

### 3.1 화면 → 액션 필드 매핑 (`components/mentor/MentorProfileEditForm.tsx` → `lib/mentor/mentorProfileEditActions.ts:35-132`)

| 폼 name | 화면 | 액션에서 읽음 | F7/F8/RPC 로 전달 | 비고 |
|---|---|---|---|---|
| `profileImage` | 파일(jpeg/png/webp, 5MB 클라 검증 `:138-149`) | 예 `:79-91` | `uploadMentorAvatar` → public URL 을 `p_profile_image_url` | 새 파일 없으면 현재 값 유지 |
| `nickname` | 텍스트 `:301-309` | **아니오**(액션이 `nickname` 을 읽지 않음 `:39-47`) | — | 입력만 있고 저장 경로 없음(표시용). 닉네임 정본은 `users.nickname`(앱은 `user_profile_update_self` RPC 사용) |
| `grade` | 텍스트(학번) `:314-323` | 예 `:43` | **아니오**(`updateMentorProfile` 인자에는 있으나 F7 호출에 포함 안 됨 `lib/mentor/mentorProfileMutations.ts:164-176`) | 사실상 저장되지 않음 |
| `university`, `department` | `readOnly` 잠금 `:336-346,384-394` | 예 `:41-42` | `p_university_name`, `p_department_name` — F7 는 **갱신 허용**(빈 값이면 `UNIVERSITY_NAME_REQUIRED`/`DEPARTMENT_NAME_REQUIRED`) | 잠금은 UI 전용. F7 로 값이 바뀌면 192 B-4 트리거가 학교인증을 pending 으로 되돌림(`supabase/sql/192…:453-455` 주석) |
| `highSchool` | 텍스트 | 예 | `p_high_school_name` | |
| `intro`(50자), `bio`(500자) | 텍스트 | 예 | `p_intro_line`, `p_bio` | |
| `subjects` | hidden — 체크박스 code 콤마결합 `:461,469` | 예 | `p_teaching_subjects text[]`(F7 가 `public.subjects.code` 실존값만 보존) | |
| `tags` | hidden(초기값 그대로) `:470` | 예 `:46` | **아니오**(F7 미전달) | 사문 |
| `subscribeOpen` | hidden `on`(subOpen && 과목≥1 일 때만 렌더 `:611-613`) | 예 `:47` | `p_is_open_for_subscriptions` | 과목 0개 + on 이면 액션에서 거부(`mentorProfileMutations.ts:148-150`) |
| `subscriptionPriceKrw_{limited,standard,premium}` | 숫자 캐시 `:508-519` | 예 `:20-25,48-54` | F8 `p_limited_cash_krw/p_standard_cash_krw/p_premium_cash_krw`(정수 캐시) | 3값 모두 필수(`:52-54`), 밴드 밖이면 제출 버튼 비활성(`:118-122`) |
| `individualQuestionPriceCash` | 숫자 캐시 `:557-568` | 예 `:28-33` | `set_individual_question_price(p_amount_cents = cash×100)` | 비우면 변경 없음(비우기 = 삭제 아님) |
| `answer_style` | 폼에 없음 | — | 현재 행 값을 읽어 그대로 전달(`mentorProfileMutations.ts:154-171`) | F7 이 9필드 전면 교체라 보존용 |

순수 payload 빌더 `buildMentorProfilePayloads`(`lib/mentor/mentorProfilePayload.ts:47-84`)는 `student_id_image_url` 을 절대 포함하지 않도록 계약 테스트로 고정(`FORBIDDEN_DOCUMENT_COLUMNS`, `lib/mentor/__contract__/mentorProfilePayload.contract.test.ts`). 다만 현행 저장 경로는 이 빌더가 아니라 `updateMentorProfile`→F7 이다(빌더의 `extras`(tags/grade 계열)는 더 이상 사용되지 않음 — `mentorProfileMutations.ts:13-16` 주석).

### 3.2 저장 RPC

**F7 `api_web_v1.mentor_profile_update_self(p_university_name text, p_department_name text, p_high_school_name text, p_teaching_subjects text[], p_intro_line text, p_bio text, p_answer_style text, p_profile_image_url text, p_is_open_for_subscriptions boolean) RETURNS jsonb`** (`supabase/sql/20260730112528_api_web_v1_mentor_rpc.sql:65-149`)
- SECURITY DEFINER, `search_path=''`, 대상 행 = `auth.uid()`. GRANT EXECUTE `authenticated, service_role`(`:242-245`).
- 오류 코드: `AUTH_REQUIRED`, `ROLE_NOT_MENTOR`, `ACCOUNT_BANNED`, `ACCOUNT_SUSPENDED`, `ACCOUNT_DELETION_IN_PROGRESS`(`account_deletion_write_blocked`), `MENTOR_PROFILE_NOT_FOUND`, `UNIVERSITY_NAME_REQUIRED`, `DEPARTMENT_NAME_REQUIRED`, `PROFILE_IMAGE_REF_INVALID`.
- 아바타 ref 규칙: `/profile-avatars/` 마커 뒤 경로 또는 순수 경로, 첫 세그먼트 = `auth.uid()`.
- 갱신 컬럼 9개만(allowlist). `verification_status`·`cap_limit`·`payout_*`·`activity_status`·`student_id_image_url` 은 불변. 성공 응답 `{ok:true, contract_version:1, updated_at}`.
- 웹 코드 매핑: `lib/mentor/mentorProfileMutations.ts:20-41,141-191`.

**F8 `api_web_v1.mentor_plan_prices_set_self(p_limited_cash_krw integer, p_standard_cash_krw integer, p_premium_cash_krw integer) RETURNS jsonb`** (`:154-238`, 190 에서 재정의 `190_cap_structure_limit_50_weights.sql:206-211`)
- 밴드 DB 강제: min `[29900, 84900, 174900]`, max `[69900, 149900, 329900]`(`:169-171`). 밖이면 clamp 없이 `PLAN_PRICE_OUT_OF_BAND` + `tier/min_cash_krw/max_cash_krw/given_cash_krw`. `<1` 이면 `PLAN_PRICE_INVALID`.
- `amount_cents = cash × 100`, `cap_weight` 는 190 이후 `public.subscription_cap_weight(tier)` 함수값 강제(클라이언트 불가). `INSERT … ON CONFLICT (mentor_id, plan_tier)`(UNIQUE `uq_mentor_plans_mentor_tier`), `is_active=true`, `price_updated_at=now()`. 3 tier 단일 트랜잭션. 응답 `{ok, contract_version, updated[], unchanged[]}`.
- TS 정본 `MENTOR_SUBSCRIPTION_PRICE_RULES`(`lib/subscribe/mentorPlanPricing.ts:13-29`)와 동일값. 웹 매핑 `mentorProfileMutations.ts:62-118`.

**개별질문 단가 `public.set_individual_question_price(p_amount_cents int) RETURNS SETOF mentor_individual_question_pricing`** (`supabase/sql/094_individual_question_pricing_rpc.sql:41-88`)
- SECDEF, `auth.uid()` 본인 upsert(`ON CONFLICT (mentor_id)`), `amount_cents<=0` 이면 `INVALID_INPUT`(22023). 승인 멘토 게이트는 주석 처리(미적용). GRANT `authenticated`.
- 테이블 `mentor_individual_question_pricing(mentor_id pk, amount_cents int check >0, updated_at)`(`070…:133-137`), RLS `miqp_select_authenticated`(SELECT 전용, `:271-272`). 조회 `lib/individualQuestion/individualQuestionPricing.ts:42-62`.

### 3.3 구독 열림 토글 (`/mentor/mypage`)
- 읽기 `loadMentorSubscribeOpenState`(본인 행, fail-closed) `lib/mentor/mentorSubscribeOpen.ts:34-53`.
- 쓰기 `setMentorSubscribeOpen` = 본인 8컬럼 읽어 그대로 + `p_is_open_for_subscriptions` 만 바꿔 F7 호출(`:65-96`). 액션 `setMentorSubscribeOpenAction`(hidden `open`="true"/"false") `lib/mentor/mentorSubscribeOpenActions.ts:18-29`. 컴포넌트 `components/mentor/mypage/MentorSubscribeOpenToggle.tsx:48-50`.
- 공개 판정 정본은 뷰 `mentor_directory_v1.is_open_for_subscriptions`(학생 세션은 `mentor_profiles` 0행) — `mentorSubscribeOpen.ts:8-13`.

### 3.4 프로필 이미지 버킷·정책
- 버킷 `profile-avatars`: **public=true**, `file_size_limit 5242880`, mime `image/jpeg,image/png,image/webp` (`supabase/sql/097_mentor_profile_avatar.sql:24-36`).
- 정책: `pa_public_read`(anon/authenticated SELECT), `pa_auth_insert_own/update_own/delete_own` = `(storage.foldername(name))[1] = auth.uid()`(`:40-70`).
- 경로 `{userId}/{uuid}.{jpg|png|webp}`, 매직바이트 검증 후 `getPublicUrl` 영구 URL 저장(`lib/storage/mentorAvatarStorage.ts:6-56`). 교체 시 DB 성공 후 구 객체 삭제, 실패 시 신규 객체 보상 삭제(`mentorProfileEditActions.ts:60-126`).

### 3.5 직접 테이블 쓰기 REVOKE 상태
- `mentor_profiles`: anon/authenticated `REVOKE ALL` → `GRANT SELECT`(`20260730195147…:80-81`). service_role 의도 경로 목록: `mentorActivityService.ts`, `mentorStudentIdActions.ts`, `lib/auth/mentorSignupStudentIdAction.ts`, `lib/admin/mentorAcademicRecordChangeReviewActions.ts`, 관리자 SECDEF RPC(`:22-27` 헤더).
- `mentor_plans`: 동일(`20260730195150…:63-64`). service_role 경로: `subscribeCheckoutService.ts:397`(권장가 seed), `mentorActivityService.ts:90,94`(is_active 토글).
- 결론: 앱도 두 테이블은 SELECT 만 가능하며 쓰기는 F7/F8/F13 로만.

---

## §4 학교 인증·학생증

### 4.1 테이블·상태
- `public.mentor_school_verifications(id, mentor_id→users, status check in ('pending','approved','rejected','resubmit_required') [+ 'superseded' 174 추가], verified_university_name, verified_university_id, verified_major_category check 8종, verified_department_name, school_tier check ('서연고','서성한','중경외시','건동홍','그외','미분류'), document_storage_ref, reviewed_by, reviewed_at, reject_reason, created_at, updated_at)` (`supabase/sql/077_mentor_school_verification.sql:12-40`; 건동홍은 079 에서 추가 — TS `SCHOOL_TIERS`, `lib/mentor/schoolVerificationConstants.ts:14`).
- 카탈로그 `school_tier_catalog(code pk, label, display_order, is_active)`, `major_category_catalog(...)`(`079_b_classification_catalog.sql:76-98`); 웹 로더 `loadSchoolClassificationCatalogs`(`lib/mentor/schoolClassificationCatalog.ts:103-125`). `school_tier_mappings` 는 195 에서 제거.
- 자기 제출 가드 트리거 `mentor_school_verifications_guard_self_review`: admin 아니고 `mentor_id=auth.uid()` 이면 `status='pending'`, verified_*·school_tier·reviewed_*·reject_reason 을 NULL 로 강제(`077:82-112`).
- RLS: `msv_select_own`, `msv_insert_own_pending`(role=mentor, status pending, admin 필드 NULL), `msv_update_own_pending`(pending/resubmit_required 행만), `msv_admin_select_all`, `msv_admin_update_all`(`077:120-185`).
- "잠정" 규칙(192): `reviewed_by IS NULL` = 잠정. `auto_school_verification()` 트리거(`after insert or update of verification_status on mentor_profiles`)가 `verification_status='approved'` 시 pending/approved 행 없으면 `status='pending'`, `school_tier=school_tier_suggest(university_name)`, `verified_major_category=major_category_suggest(department_name)`, `reviewed_by/at NULL` 로 자동 삽입(`192…:206-243`). 20260830150838 의 임시 트리거(`tmp_auto_school_verification`, approved 즉시 생성)를 대체.
- 학적 변경 재판정 트리거 `school_verification_reassess_on_academic_change`(`after update of university_name, department_name`, IS DISTINCT FROM): approved·pending 행을 같은 규칙으로 pending·reviewed_by NULL 로 되돌림, 없으면 신규 pending 행(`192…:340-390`).
- 등급 규칙 `school_tier_suggest(text)`: NULL/공백 → `'미분류'`, LIKE 13패턴(서울대/연세대/고려대→서연고, 서강/성균관/한양→서성한, 중앙/경희/한국외/서울시립→중경외시, 건국/동국/홍익→건동홍) 미매칭 → `'그외'`(`193…:81-104`). `major_category_suggest(text)`: 의예/의학/치의/약학/한의/수의/간호→메디컬, 교육, 인문, 사회상경, 자연, 공학, 예체능, 기타(`192…:163-197`). 두 헬퍼는 anon/authenticated EXECUTE 회수.
- 관리자 확정 RPC `approve_mentor_school_verification_admin(p_verification_id uuid, p_university_name text, p_university_id text, p_department_name text, p_major_category text, p_school_tier text) RETURNS jsonb`: `is_admin()` 아니면 `NOT_ADMIN`(42501), 허용 status = pending/resubmit_required/approved(정정 — `school_tier_corrected` 감사 로그), rejected/superseded 는 `NOT_REVIEWABLE`; 재승인 시 기존 approved → `superseded`; 응답에 `corrected, previous_school_tier, previous_reviewed_by` 추가(`193…:109-241`). anon REVOKE.
- 공개 표시: 뷰 `mentor_directory_v1` 가 approved 최신 1건을 LATERAL 조인해 `school_verified, school_tier, verified_major_category, verified_university_name, verified_department_name` 노출(`20260803162808…:153-181`). 웹은 `그외`→`미분류` 로 표시 정규화(`lib/mentor/mentorDisplayFields.ts:66-67`).

### 4.2 제출 흐름(멘토)
1. 화면 `/mentor/verification`: 학교·전공 서류 폼(`schoolVerificationDocument`) + 학생증 폼(`studentIdDocument`). 학교 서류는 `status==='pending'` 이면 disabled(`page.tsx:127,145,157`).
2. 학교 서류 액션 `submitMentorSchoolVerificationAction`(`lib/mentor/mentorSchoolVerificationActions.ts:31-79`): 크기 ≤ `STUDENT_ID_IMAGE_MAX_BYTES`(20MB), 확장자 jpg/jpeg/png/pdf, 매직바이트 검증(`lib/storage/uploadMagicBytes` `validateJpgPngPdfMagicBytes`) → 세션 클라이언트로 Storage `student-id-images` 에 `{uid}/school-verifications/{ts}-{rand32}.{ext}` 업로드(`lib/storage/studentIdImageStorage.ts:49-51`) → `mentor_school_verifications` INSERT `{mentor_id, status:'pending', document_storage_ref:'student-id-images/{path}'}`(append-only; 실패 시 객체 삭제). **service_role 없음**.
3. 학생증 액션 `submitMentorStudentIdImageAction`(`lib/mentor/mentorStudentIdActions.ts:33-90`): 동일 검증 → `{uid}/{ts}-{rand}.{ext}` 업로드 → **service_role** 로 `mentor_profiles.student_id_image_url = 'student-id-images/{path}'`, `updated_at` UPDATE(`:74-79`; 세션 UPDATE 는 M11 로 불가). 실패 시 객체 삭제.
4. 조회 `fetchLatestMentorSchoolVerification`(mentor_id 최신 1건, `lib/mentor/mentorSchoolVerification.ts:39-56`).

### 4.3 버킷·정책
- `student-id-images`: `public=false`(`001_initial_auth_profile.sql:242-244`). 정책(authenticated): `student_id_images_select_own/insert_own/update_own/delete_own` = `split_part(name,'/',1) = auth.uid()`(`:249-282`), 관리자 SELECT `student_id_images_admin_select`(`120…:53-55`). 서명 URL TTL 300초(`studentIdImageStorage.ts:5`).
- 세 용도가 같은 버킷을 공유: 학생증 `{uid}/…`, 학교 서류 `{uid}/school-verifications/…`, 학적 변경 `{uid}/academic-record-changes/…`(`studentIdImageStorage.ts:43-56`).

### 4.4 인증 게이트가 막는 것
- 판정식 `MENTOR_ACTIVITY_APPROVED_STATUSES = {approved, verified, active}`(`lib/mentor/mentorVerificationGate.ts:4-9`) = DB `individual_question_user_is_approved_mentor(p_user_id)`(`070…:163-176`) = 뷰 `mentor_directory_v1` WHERE(`20260803162808…:189-191`).
- `assertMentorApprovedForAction(supabase, mentorId)` 는 뷰 행 존재로 판정(`mentorVerificationGate.ts:17-44`) → 개별질문 목록/상세 차단(`app/(mentor)/mentor/individual-questions/page.tsx:36`, `[questionId]/page.tsx:25-26`).
- 미승인 멘토는: 멘토 찾기 미노출(`lib/mentor/publicMentorsListQueries.ts:578-580`, 과목 0개도 제외 `:582-588`), F13 정산계좌 등록 `MENTOR_NOT_APPROVED`, 마이페이지 배너(`mypage/page.tsx:187-198`). 프로필 편집·학교 서류 제출·리뷰 열람은 게이트 없음. `set_individual_question_price` 의 승인 게이트는 미적용(주석).
- `verification_status` 값 표시 매핑(`approved/verified/complete`→인증 완료, `pending/in_review/…/on_hold`→검토 중, `rejected`→반려): `lib/mentor/mentorDisplayFields.ts:105-129`.

---

## §5 학적 변경 요청

- 테이블 `public.mentor_academic_record_change_requests(id, mentor_id→users, status check ('pending','approved','rejected','resubmit_required'), requested_university_name, change_reason, document_storage_ref, approved_university_name, reviewed_by, reviewed_at, reject_reason, created_at, updated_at)`(`supabase/sql/089_mentor_academic_record_change_requests.sql:14-36`). 자기 제출 가드 트리거 `mentor_acad_change_guard_self_review`(admin 아니면 status pending·admin 필드 NULL 강제, `:63-90`). RLS `macc_select_own`, `macc_insert_own_pending`(role mentor), `macc_update_own_pending`(pending/resubmit_required), `macc_admin_select_all`, `macc_admin_update_all`(`:97-155`).
- 화면 `/mentor/academic-record-change`: 현재 학교명(`mentor_profiles.university_name` 본인 행) 표시, 폼 `requestedUniversityName`(필수, max 40), `changeReason`(선택, max 100), `academicRecordDocument`(필수). `status==='pending'` 이면 제출 잠금(`page.tsx:64`).
- 액션 `submitMentorAcademicRecordChangeAction`(`lib/mentor/mentorAcademicRecordChangeActions.ts:30-81`): 확장자·매직바이트 검증(**크기 상한 검사 없음** — 학교/학생증 액션과 달리 `STUDENT_ID_IMAGE_MAX_BYTES` 미적용 `:37-46`) → `student-id-images/{uid}/academic-record-changes/…` 업로드 → INSERT `{mentor_id, status:'pending', requested_university_name, change_reason|null, document_storage_ref}`. 세션 클라이언트, service_role 없음.
- 조회 `fetchLatestMentorAcademicRecordChange`(`lib/mentor/mentorAcademicRecordChange.ts:41-58`).
- 승인 반영: 관리자 액션 `lib/admin/mentorAcademicRecordChangeReviewActions.ts` 가 service_role 로 `mentor_profiles.university_name = approved_university_name` 갱신(`20260730195147…:26` 목록) **(확인 필요: 파일 미열람)** → 갱신 시 192 B-4 재판정 트리거로 학교인증이 pending 으로 되돌아감.

---

## §6 정산

### 6.1 화면 데이터 (`/mentor/payouts`, `lib/mentor/mentorSettlementService.ts:83-130`)
- `fetchMentorSettlementSummary(ym)` → `supabase.rpc("mentor_settlement_summary", {p_month: 'YYYY-MM-01'})` (`:35-54`), `fetchMentorSettlementLines({ym})` → `rpc("mentor_settlement_lines", {p_from, p_to})` KST 월 반개구간(`:56-79`, `kstMonthBounds` `mentorSettlementSchema.ts:296-301`).
- 페이지 데이터 = 당월 summary + 당월 lines + 계좌 마스킹 + 성과 라인 + 과거 5개월 summary(추이) → 하나라도 실패하면 `{ok:false}` → `MentorSettlementLoadError`(fail-closed, `app/(mentor)/mentor/payouts/page.tsx:12-13`).
- 응답 스키마 검증 `parseMentorSettlementSummary/Lines`(cents 정수 강제, 상태 5종 외 값은 오류 칩) `mentorSettlementSchema.ts:140-239`. 프론트 재계산 금지(×0.15/×0.033 없음).
- 표시: 히어로(확정/적립/보류/지급합계, `run_date`, `payout_account_registered` 미등록 경고), 계좌 패널, 월 표(라인) + 성과 탭, 우측 지급 일정(23일)·6개월 추이 (`components/mentor/payouts/MentorPayoutsPage.tsx:8-46`).

### 6.2 RPC 정본 (migration `20260827100300_mentor_settlement_rpc_v2_due_payouts_parity.sql`)
**`public.mentor_settlement_lines(p_from timestamptz default null, p_to timestamptz default null) RETURNS TABLE(source_type text, source_id uuid, occurred_at timestamptz, period_start timestamptz, period_end timestamptz, gross_cents bigint, platform_fee_cents bigint, mentor_amount_cents bigint, fee_rate numeric, withholding_cents bigint, net_cents bigint, status text, hold_reason text, completion_ts timestamptz, expected_run_date date, paid_run_date date, paid_at timestamptz)`** (`:8-31`) — SQL, STABLE, SECURITY DEFINER, `WHERE mentor_id = auth.uid()`.
- 소스 3종 UNION: `subscription_settlement_items`(billing_at, fee_rate 행값), `custom_order_settlement_items` JOIN `custom_request_orders`(원 단위 ×100, 활성 분쟁 `disputes.status in (open, under_review, escalated)`), `individual_questions`(released_at, **RPC 내부 상수 0.85/0.15 로 계산** `:64-70`).
- 상태 정규화 5종 `accruing | pending | hold | paid | canceled`(`:75-95`): `payout_run_items` 존재 또는 raw paid → paid; `due_payouts` 뷰에 있으면 pending; 구독 raw accruing/hold/pending 그대로, 그 외 canceled; 맞춤의뢰 pending/on_hold/payable 외 또는 주문 환불·취소 → canceled, 활성 분쟁 → hold(`hold_reason='active_dispute'`), `accepted_at` null → accruing.
- `withholding_cents = coalesce(payout_run_items.withholding_cents, calc_withholding_cents(mentor_amount_cents))`, `expected_run_date = (completion_ts KST 월 + 1개월 + 22일)::date`(= 익월 23일), `paid_run_date = payout_runs.run_date`.
- GRANT: `revoke all from public; grant execute to authenticated`(`:204-207`) → 앱 직접 호출 가능(세션 JWT 필수 — service_role 은 `auth.uid()` NULL 이라 빈 결과, `mentorSettlementService.ts:23-26`).

**`public.mentor_settlement_summary(p_month date default null) RETURNS jsonb`** (`:117-200`) — 반환 키:
`month('YYYY-MM'), run_date(익월 23일), cutoff(익월 1일 00:00 KST − 1초), payout_account_registered(bool — mentor_profiles.payout_account_number 비어있지 않음), confirmed{count, gross_cents, platform_fee_cents, mentor_amount_cents, withholding_cents, net_cents}(due_payouts ∩ completion_ts≤cutoff ∩ 미지급 + 해당 월 run 지급분), accruing{count, mentor_amount_cents, withholding_cents, net_cents, last_period_end, expected_run_date}, held{count, mentor_amount_cents}, paid_total{count, mentor_amount_cents, net_cents}, by_source_this_month{source_type:{mentor_amount_cents, count}}, withholding_rule:'calc_withholding_cents'`. TS 타입 `MentorSettlementSummary`(`mentorSettlementSchema.ts:51-80`).

**`public.calc_withholding_cents(p_mentor_amount_cents bigint) RETURNS bigint`** = `floor(floor(cents/100) × 0.033) × 100` — 캐시(원) 단위 절사 3.3%, IMMUTABLE, GRANT authenticated·service_role(`20260827100200…:7-21`). TS 표시 상수 `WITHHOLDING_RATE=0.033`, `PAYOUT_DAY_OF_MONTH=23`, `PAYOUT_DAY_LABEL='매월 23일'`(`lib/payout/payoutComputation.ts:11-25`).

**V7 `api_web_v1.mentor_settlement_self() RETURNS TABLE(item_id uuid, subscription_id uuid, student_label text, event_type text, billing_at, period_start, period_end, gross_cents bigint, platform_fee_cents bigint, mentor_amount_cents bigint, fee_rate numeric, status text, hold_reason text, paid_at, created_at)`** (`supabase/sql/20260730105248_api_web_v1_self_rpc.sql:259-303`) — plpgsql STABLE SECDEF, `auth.uid()` NULL 이면 `AUTH_REQUIRED`(42501), `subscription_settlement_items where mentor_id=auth.uid()` LEFT JOIN users(nickname → `student_label`, 비면 '쌤버십 사용자'). `idempotency_key/ledger_id/payment_id` 비노출. GRANT authenticated·service_role(`:316-323`). 웹 소비 `loadSubscriptionSettlementRowsForMentor`(`item_id`→`id` 정규화, `lib/mentor/subscriptionSettlementItems.ts:94-112`).

### 6.3 수수료율(fee_rate) 취급
- 정책 요율 정본 `PLATFORM_FEE_POLICY = {subscription:0.15, individualQuestion:0.15, customRequest:0.05}`(`lib/payout/platformFeePolicy.ts:19-23`) — 정산 행이 **없는** 미리보기(진행 주문 예상 수익 등)에만 사용.
- 적용 요율은 행 `fee_rate`(`subscription_settlement_items`, `custom_order_settlement_items`, `payout_run_items`) — `parseSettlementFeeRate`, 없으면 `'요율 미설정'` 표시하고 재계산 금지(`lib/payout/settlementFeeRate.ts:18-32`, `lib/mentor/mentorPayoutLinesCore.ts:62-99`).
- 테이블 기본값은 정책과 다름: `subscription_settlement_items.fee_rate default 0.30`(`086…:32`), `custom_order_settlement_items.fee_rate default 0.20`(`013…:18`) — 실제 값은 생성 RPC(`refresh_subscription_settlement_items` 등)가 결정 **(확인 필요: 본문 미열람)**.

### 6.4 정산 상세 API route
- `GET /api/mentor/payouts/detail?month=YYYY-MM&type=all|subscription|custom_request|individual_question`(`app/api/mentor/payouts/detail/route.ts:13-40`): `requireMentorApiSession()`(`lib/mentor/mentorPayoutsApiAuth.ts:4-19` — `getServerUserWithProfile()` 쿠키 세션, 미로그인 401, role≠mentor 403) → 형식 검증(월 400, 유형 400) → `fetchMentorSettlementLines(supabase,{ym})`(세션) → `type` 필터는 JS. 응답 `{ok, lines[]}` / `{ok:false, error}`(500).
- 클라이언트 `MentorPayoutsDetailView`(월 12개 셀렉트·유형·클라 페이지네이션·`xlsx` 엑셀 `components/mentor/MentorPayoutsDetailView.tsx:81-145`).

### 6.5 레거시 라인 로더 (`lib/mentor/mentorPayoutsService.ts`) — 허브 KPI·성과 탭이 사용
- `loadAllPayoutLines` = V7(구독) + `custom_order_settlement_items`(RLS `cosi_select_parties`: admin/mentor_id/student_id, `013…:46-56`) + `custom_request_orders`(완료 주문 보강, 요율 미설정) + `individual_questions`(released, `claimed_mentor_id|designated_mentor_id`) + `payout_run_items`(RLS `pri_select_mentor_own`, `106…:101-107`) — `:124-255`.
- 성과 라인 `loadPerformanceLines`(`:496-554`): 맞춤의뢰 주문 80건 + 구독 40건, 정산 행 있으면 행 `mentor_amount`, 없으면 정책 요율 추정 `amountEstimated=true`.
- 원천징수 per-line `calcPayoutWithholding = floor(net × 0.033)`(`lib/payout/payoutComputation.ts:55-57`), 지급일 산출 `buildPayoutScheduleInfo`(23일 기준, `lib/mentor/mentorPayoutsDisplay.ts:51-72`).

### 6.6 정산 계좌 등록 — 판정: "결제 실행" 아님, "계좌 정보 등록"
- F13 `api_web_v1.mentor_payout_account_update_self(p_bank_name text, p_account_number text) RETURNS jsonb`(`supabase/sql/20260730112531_api_web_v1_payout_account_rpc.sql:52-112`): SECDEF, `auth.uid()`; 코드 `AUTH_REQUIRED/ROLE_NOT_MENTOR/ACCOUNT_BANNED/ACCOUNT_SUSPENDED/ACCOUNT_DELETION_IN_PROGRESS/MENTOR_NOT_APPROVED(individual_question_user_is_approved_mentor)/PAYOUT_BANK_NAME_INVALID/PAYOUT_ACCOUNT_NUMBER_INVALID(^[0-9]{8,24}$)/MENTOR_PROFILE_NOT_FOUND`; 동작은 `UPDATE mentor_profiles SET payout_bank_name, payout_account_number` 두 컬럼뿐(`:97-100`, 041 컬럼 `041_mentor_payout_account.sql:2-4`). 자금 이동·PG·원장 기록 없음. 응답 `{ok, contract_version, updated_at, account_masked}`(끝 4자리 외 `*`). GRANT authenticated·service_role(`:117-118`).
- 은행 allowlist: 원본 16종 + `189_payout_bank_allowlist_add_im_bank.sql`(migration 20260831100100)로 `iM뱅크` 추가 → 17종 = 웹 `BANK_OPTIONS` 17종(`components/mentor/payouts/MentorPayoutAccountPanel.tsx:8-26`) 정합.
- 웹 액션 `updateMentorPayoutAccountAction(formData)`(`bankName`, `accountNumber` 숫자만) `lib/mentor/mentorPayoutAccountActions.ts:41-69`; 원문 계좌는 응답·로그 어디에도 싣지 않음. 조회는 본인 행 SELECT 후 마스킹(`mentorPayoutsService.ts:283-320`).
- 실제 지급은 `pay_due_payouts_for_run`(service_role/cron, `20260827100200…:23-40` 패치) — 멘토 콘솔에서 호출 경로 없음. `payout_runs` 는 authenticated 정책 없음(`106…:108`).

---

## §7 리뷰 관리

- 목록 `listMentorReceivedReviews(supabase, mentorId, limit=50)`(`lib/reviews/reviewQueries.ts:357-382`): `reviews select * where mentor_id=me order created_at desc limit min(limit×3,150)` → `isPubliclyVisibleReview`(`moderation_state='visible' && !is_hidden && !is_blinded`, `lib/reviews/reviewRowMapper.ts:49-51`) 필터 → 작성자 `users(id, full_name, nickname, grade_level)` 조회(`loadAuthorsMap`)로 마스킹 이름(`이*연`) + 첫 과목 라벨. `users` SELECT RLS 는 `users_select_own`·`users_admin_select_all` 뿐(`001…:195`, `120…:43`)이라 멘토 세션에서 타인 행은 0행 → 마스킹 폴백 `'학생'` **(확인 필요: 런타임 실측)**.
- 리뷰 RLS(정본 126·171·173·20260803162808): SELECT `reviews_select_public_visible`(anon/authenticated, visible∧!hidden∧!blinded), `reviews_select_admin`, `reviews_select_author`; INSERT `reviews_insert_student`(`check_review_eligibility(mentor_id, auth.uid())`); UPDATE `reviews_update_mentor`(`auth.uid()=mentor_id`), `reviews_update_admin`, `reviews_update_author`(hidden/blinded 아닌 본인 행)(`126…:44-69`, `171…:59-66`, `173…:159-165`). → 멘토는 숨김/블라인드된 리뷰를 볼 수 없다(별도 mentor SELECT 정책 없음).
- 트리거 `trg_reviews_enforce_update` BEFORE UPDATE → `reviews_enforce_update()`(정본 `173…:51-150`): service_role 통과; 공통 불변 `id/mentor_id/author_id/subscription_count/created_at`; rating·body 는 작성자만; 관리자 분기(`is_hidden/is_blinded/moderation_state` 만, `moderated_at/by` 서버 강제, 답글 변경 금지); 작성자 분기(모더레이션된 행 수정 금지, `updated_at=now()`); **멘토 분기**(`v_uid = old.mentor_id`): moderation 필드 변경 금지, `old.mentor_reply not null` 이면 `'reviews: mentor reply already set (one-time only)'`, `mentor_replied_at := now()` 서버 강제, `updated_at` 불변(`:123-138`); 그 외 `'not permitted'`.
- 답글: 클라 `PATCH /api/reviews/{id}/reply {reply}`(`components/mentor/MentorReviewsManage.tsx:29-33`) → route(`app/api/reviews/[id]/reply/route.ts:8-36`, role mentor 403) → `replyToReview(supabase, mentorId, reviewId, reply)`(`reviewQueries.ts:284-326`: 2~500자, `mentor_id` 일치, 기존 답글 있으면 거부, `UPDATE reviews SET mentor_reply, mentor_replied_at WHERE id AND mentor_id`). 답글 수정·삭제 경로 없음(1회 확정).
- 숨김: `PATCH /api/reviews/{id}/hide {hidden}` 은 **admin 전용**(`app/api/reviews/[id]/hide/route.ts:13-15`) → `hideReview`(`is_hidden` + `moderation_state` hidden/visible, RETURNING 1행 판정 `reviewQueries.ts:328-343`). 멘토 콘솔에는 숨김 기능 없음.
- 통계 RPC `public.get_mentor_review_stats(p_mentor_id uuid, p_include_hidden boolean default false) RETURNS TABLE(review_count int, avg_rating numeric, d1..d5 int)`(SECDEF, include_hidden 은 admin 만 유효, `20260803162808…:126-140`) — 공개 상세·목록에서 사용(`lib/mentor/publicMentorBundle.ts:50-82`).
- 학생 측 자격/작성/수정(`/api/reviews`, `/api/reviews/[id]`, `/api/reviews/eligibility`)은 student 전용 — 참고만(`app/api/reviews/route.ts:31`, `[id]/route.ts:54`).

---

## §8 채널·마이페이지·community/new·support/disputes·활동 관리

### 8.1 채널
- `/mentor/channel` 은 `loading.tsx` 만 남은 빈 라우트. 미디어 소스 스텁(`fetchMentorMediaSample`)과 채널·'대표 콘텐츠' UI 는 D-MT-13 으로 제거(`lib/mentor/mentorProfileQueries.ts:16-19`, `components/mentor/MentorProfileEditForm.tsx:616-617`). 정본 테이블 없음(`mentor_media/mentor_content_links/mentor_link_items` 미생성). 앱 신설 시 새 테이블·버킷 설계 필요.

### 8.2 마이페이지(§2 참조) — 활동 관리(휴식·종료)
- 컴포넌트 `components/mentor/mypage/MentorActivityControls.tsx`: 상태 `active|paused|terminating|terminated`(`lib/mentor/mentorActivity.ts:19-36`). active → 일시 중단 폼(`days` 1~7, `reason` rest|illness) + 활동 종료 폼; paused → 복귀 폼. `requestMentorImmediateLeaveAction`(무단 이탈)은 액션 파일에만 있고 UI 미연결(`mentorActivityActions.ts:74-86`, 컴포넌트 import `:1-5`).
- 서버 액션 4종 모두 `createServiceRoleClient()`(`lib/mentor/mentorActivityActions.ts:27,46,66,76`) → `lib/mentor/mentorActivityService.ts`:
  - `startMentorTermination`: `mentor_profiles.activity_status='terminating', termination_requested_at, termination_effective_at=+14일`, `mentor_plans.is_active=false`, `mentor_activity_events` INSERT `termination_requested`(`:98-132`). 상수 `MENTOR_TERMINATION_NOTICE_DAYS=14`.
  - `startMentorPause(days, reason)`: active 만, rest 는 `last_pause_at` 기준 KST 6개월 1회(`canRequestNormalRest`), `activity_status='paused', pause_started_at, pause_until(+1~7일), pause_reason, last_pause_at(rest)`; 활성 구독(`status in active,past_due`)의 `current_period_end/next_billing_at` 을 쉰 일수만큼 연장; 이벤트 `pause_started`(illness 는 `pending_review`)(`:228-288`). 상수 `MENTOR_MAX_PAUSE_DAYS=7`, `MENTOR_REST_FREQUENCY_MONTHS=6`.
  - `resumeMentorActivity`: paused → active, `pause_until=null`, plans 재활성(`:291-308`).
  - `flagMentorAbandonment`: `terminated + abandonment_flagged_at`, plans 비활성, `refresh_subscription_settlement_items` RPC(service_role) 후 `subscription_settlement_items` pending → `hold('mentor_abandonment_suspected')`, 이벤트 `abandonment_suspected(pending_review)`(`:314-351`).
  - `finalizeMentorTermination`(배치/관리자용, 잔여 100% `refunds` 생성 + 구독 canceled)(`:138-225`) — 멘토 콘솔 호출 없음.
- 알림 fan-out 은 DB 트리거 `trg_mp_notify_activity`(`activity_status` → terminating/paused 전이 시 구독 학생 알림, `158_p1_11_mentor_notification_atomization.sql:68-72`).
- `mentor_activity_events` 는 RLS 활성·정책 0(authenticated 잠금, `103…:60-61`). 컬럼 `103…:36-47`.
- 결제 게이트용 `loadMentorActivityForGate(mentorId)`(service_role 읽기, `mentorActivityService.ts:372-390`) — 학생 세션은 `mentor_profiles` 0행이라 뷰/RPC 로 노출되지 않은 `activity_status` 를 서비스 롤로 읽음(활동 상태 공개 RPC 없음).

### 8.3 community/new
- 단순 redirect(§1). 작성 정본은 `/community/new`·`/community/shortform/new` — 커뮤니티 리더 범위.

### 8.4 support/disputes
- 목록: `disputes where mentor_id=me`(세션) → `StudentDisputesFilterableList`(accent green). 상세: `loadDisputeById` 번들 + 당사자 검사; 멘토 측 쓰기 액션 없음(조회 전용). 분쟁 RLS·테이블 컬럼은 맞춤의뢰/분쟁 리더 범위 **(확인 필요)**.

### 8.5 기존 앱 멘토 기능(비교 기준)
- `MentorDashboardSection`: 구독 학생(=`mentor_student_rooms` 수), 답변 대기(`question_threads` 상태 집계), 최근 정산(`subscription_settlement_items` 직접 SELECT 최신 1건 `mentor_amount_cents`, `lib/features/mypage/data/mypage_repository.dart:203-219`), 정산 관리 링크는 `kPayoutManageLinkEnabled`(스토어 기본 off, `lib/core/commerce/commerce_policy.dart:29-33`).
- `ProfileEditScreen`: 멘토는 표시명만(`user_profile_update_self` RPC) — `mentor_profiles` 편집 없음.
- 앱이 읽는 웹 공유 표면: `api_web_v1.mentor_directory_v1`, `mentor_plans`(is_active=true), `mentor_profiles.teaching_subjects`(타인 행 → RLS 0행 → 전체 과목 폴백 `question_room_read_repository.dart:118-135`), `mentor_individual_question_pricing`.

---

## §9 앱이 그대로 못 쓰는 것과 대체안

### 9.1 service_role 전용(세션 JWT 로는 불가)
| 기능 | 웹 경로 | 왜 앱이 못 쓰나 | 대체안(초안) |
|---|---|---|---|
| 학생증 사후 제출 | `submitMentorStudentIdImageAction` → service_role UPDATE `mentor_profiles.student_id_image_url` | M11 로 authenticated UPDATE 불가, F7 allowlist 밖 | 신규 SECDEF RPC `api_app_v1.mentor_student_id_document_set_self(p_object_path text) RETURNS jsonb` — `split_part(path,'/',1)=auth.uid()::text` 검증 + `storage.objects(bucket_id='student-id-images', name=path)` 실재 확인(174 의 소유·실재 검사 재사용) → `student_id_image_url='student-id-images/'||path` UPDATE. 업로드 자체는 앱이 Storage 정책(`insert_own`)으로 직접 |
| 활동 종료/일시중단/복귀/무단이탈 | `mentorActivityActions.ts` 4종 → `mentorActivityService.ts`(mentor_profiles·mentor_plans·subscriptions·mentor_activity_events·subscription_settlement_items 쓰기) | 전부 service_role 쓰기, 특권 컬럼 아님에도 M11/M12·RLS 로 막힘 | SECDEF RPC 3종 `api_app_v1.mentor_activity_pause_self(p_days int, p_reason text)`, `mentor_activity_terminate_self()`, `mentor_activity_resume_self()` RETURNS jsonb(envelope). 본문은 `mentorActivityService.ts` 규칙(7일 상한·6개월 1회·구독 기간 연장·plans is_active·events 로그) 이식. 158 트리거는 그대로 동작. 무단이탈은 UI 미연결이라 보류 |
| cap 사용량 | `loadMentorCapUsage`(service_role 클라이언트) | 서비스 롤은 "판정 경로 통일" 목적이지 필수는 아님 — 3 RPC 는 anon/authenticated EXECUTE | 앱은 `mentor_cap_used/mentor_cap_limit/subscription_cap_weight` 직접 호출(5회). 왕복 절감용 선택안: `api_app_v1.mentor_cap_usage_self() RETURNS jsonb {used_cap, cap_limit, weight_by_tier, active_count}` |
| 결제 게이트용 활동상태 읽기 | `loadMentorActivityForGate` | 결제 경로 — 앱 범위 밖(Commerce-Zero) | 불필요 |

### 9.2 API route 전용(쿠키 세션 기반)
| 기능 | route | 대체안 |
|---|---|---|
| 정산 상세 라인 | `GET /api/mentor/payouts/detail` | RPC `mentor_settlement_lines(p_from,p_to)` 직접 호출(authenticated GRANT). 유형 필터는 클라 |
| 정산 요약 | (서버 컴포넌트 내부 호출) | RPC `mentor_settlement_summary(p_month)` 직접 호출 |
| 리뷰 답글 | `PATCH /api/reviews/[id]/reply` | RLS `reviews_update_mentor` + 트리거로 직접 `UPDATE reviews SET mentor_reply WHERE id=? AND mentor_id=auth.uid()` 가능. 길이(2~500)·1회 규칙을 서버에 두려면 `api_app_v1.mentor_review_reply_self(p_review_id uuid, p_reply text) RETURNS jsonb` 권장(RETURNING 1행 판정 포함) |
| 리뷰 숨김 | `PATCH /api/reviews/[id]/hide` | admin 전용 — 앱 멘토 기능 아님 |
| 엑셀 다운로드 | 클라 `xlsx` | 앱 자체 구현(CSV/공유) 또는 생략 |

### 9.3 server action 이지만 세션 권한으로 대체 가능한 것(직접 호출)
| 기능 | 대체 |
|---|---|
| 프로필 저장 | `api_web_v1.mentor_profile_update_self(9인자)` — 9필드 전면 교체이므로 앱은 현재 행(본인 SELECT)을 먼저 읽어 병합. `p_teaching_subjects` 는 `public.subjects.code` |
| 요금제 | `api_web_v1.mentor_plan_prices_set_self(3인자 정수 캐시)` — `PLAN_PRICE_OUT_OF_BAND` detail 로 안내 |
| 개별질문 단가 | `public.set_individual_question_price(p_amount_cents)` |
| 구독 열림 토글 | F7 (현재 행 + `p_is_open_for_subscriptions`) |
| 정산 계좌 | `api_web_v1.mentor_payout_account_update_self(p_bank_name, p_account_number)` — 은행 allowlist 17종을 앱 상수로 복제하지 말고 실패 코드로 안내 **(권장: 서버 allowlist 조회 RPC 없음 — 확인 필요)** |
| 아바타 | Storage `profile-avatars` `{uid}/{uuid}.{ext}` 직접 업로드(정책 own folder, 5MB·mime 은 버킷 제한) → F7 `p_profile_image_url` 에 public URL |
| 학교 서류 제출 | Storage `student-id-images/{uid}/school-verifications/…` 업로드 → `mentor_school_verifications` INSERT `{mentor_id, status:'pending', document_storage_ref}`(RLS `msv_insert_own_pending`, 가드 트리거가 admin 필드 NULL 강제). 웹의 서버측 매직바이트 검증은 앱 클라이언트 검증으로 대체(신뢰도 하락 — 필요 시 `api_app_v1.mentor_school_verification_submit_self(p_object_path)` 로 객체 실재·소유 검증 후 INSERT) |
| 학적 변경 요청 | 동일 패턴 `mentor_academic_record_change_requests` INSERT(RLS `macc_insert_own_pending`) |
| 받은 리뷰 | `reviews where mentor_id=me`(공개 가시 행만) + `get_mentor_review_stats(me)` |
| 분쟁 목록/상세 | `disputes where mentor_id=me`(RLS 확인 필요) |
| 허브 KPI | 각 테이블 직접(§2) — 왕복 다수. 선택안 `api_app_v1.mentor_hub_dashboard_self() RETURNS jsonb {new_questions, active_subscribers, this_month_revenue(=mentor_settlement_summary by_source 합), rating(get_mentor_review_stats), cap}` |

### 9.4 앱 게이트 재현 포인트
- 승인 판정: `individual_question_user_is_approved_mentor(auth.uid())` 또는 뷰 `mentor_directory_v1` 본인 행 존재.
- 본인인증 게이트(`IDENTITY_GATE_ENABLED`, `users.identity_verified_at`)는 웹 레이아웃 전용 — 앱 정책 별도 결정 **(확인 필요: 컬럼 정의 SQL 미확인)**.
- 캐시 원장 차단(`/wallet/ledger`)은 웹 네비 정책 — 앱은 Commerce-Zero 라 무관.

---

## §10 앱 이식 시 필요한 데이터 모델

| 테이블/뷰/RPC | 컬럼·enum | 접근 | 근거 |
|---|---|---|---|
| `mentor_profiles` | `user_id pk, university_name, department_name, teaching_subjects text[], high_school_name, intro_line, bio, answer_style, profile_image_url, verification_status('pending'…, 승인 = approved/verified/active), student_id_image_url, is_open_for_subscriptions bool default true, cap_limit numeric default 50, payout_bank_name, payout_account_number, activity_status('active'|'terminating'|'terminated'|'paused'), termination_requested_at, termination_effective_at, pause_started_at, pause_until, pause_reason, last_pause_at, abandonment_flagged_at, created_at, updated_at` | 본인 SELECT 만(쓰기 F7/F13/RPC) | `001…:45-56`, 041·050·060·097·103·131·134 add column, `20260730195147` |
| `mentor_plans` | `id, mentor_id, plan_tier('limited'|'standard'|'premium'), amount_cents, cap_weight(=subscription_cap_weight), is_active, price_updated_at, label, …` UNIQUE(mentor_id, plan_tier) | SELECT(쓰기 F8) | `004…:135-138`, 050, 103, F8 |
| `mentor_individual_question_pricing` | `mentor_id pk, amount_cents int >0, updated_at` | SELECT(authenticated) / `set_individual_question_price` | `070…:133-137,271` |
| `mentor_school_verifications` | §4.1 (status 5값 incl. superseded, school_tier 6값, verified_major_category 8값) | 본인 SELECT/INSERT(pending)/UPDATE(pending·resubmit_required) | 077·174·192·193 |
| `school_tier_catalog`, `major_category_catalog` | `code pk, label, display_order, is_active` | SELECT **(확인 필요: RLS)** | `079_b…:76-98` |
| `mentor_academic_record_change_requests` | §5 | 본인 SELECT/INSERT/UPDATE(pending) | 089 |
| Storage `student-id-images`(private), `profile-avatars`(public) | 경로 규약 §3.4·§4.3 | own-folder 정책 | 001·097·120 |
| `subscription_settlement_items` | `id, billing_event_id, subscription_id, mentor_id, student_id, payment_id, ledger_id, event_type('initial'|'renewal'), billing_at, period_start, period_end, gross_cents, platform_fee_cents, mentor_amount_cents, fee_rate, status('accruing'|'pending'|'paid'|'hold'|'canceled'), hold_reason, paid_at, idempotency_key, created_at, updated_at` | 본인 SELECT(`ssi_select_mentor_own`) 또는 V7 | `086…:17-43,90-95` |
| `custom_order_settlement_items` | `id, custom_request_order_id, mentor_id, student_id, gross_amount int(원), platform_fee_amount, mentor_amount, fee_rate, status('pending'|'on_hold'|'payable'|'paid'|'cancelled'), reason, paid_at, …` | 당사자 SELECT | `013…:10-24,46-56` |
| `payout_run_items` / `payout_runs` | `payout_run_id, mentor_id, source_type('subscription'|'custom_request'|'individual_question'), source_id, gross_cents, platform_fee_cents, mentor_amount_cents, fee_rate, ledger_id, withholding_cents, net_paid_cents(114)` / runs `run_date` | items 본인 SELECT, runs 접근 불가 | `106…:44-58,101-108` |
| `reviews` | `id, mentor_id, author_id, rating(1~5), body, subscription_count(사문), mentor_reply, mentor_replied_at, is_hidden, is_blinded, moderation_state('visible'|'hidden'…), moderated_at, moderated_by, created_at, updated_at` | 공개 가시 SELECT, 멘토 UPDATE(답글) | `lib/reviews/reviewRowMapper.ts:2-15`, 126·171·173 |
| `subscriptions` | `mentor_id, student_id, status('active'|'past_due'|'expired'|'cancel_scheduled'|'canceled'|'pending'|'refunded'), current_period_end, next_billing_at, plan_tier…` | 당사자 SELECT(`subscriptions_select_parties`) | `lib/reviews/reviewEligibilityPolicy.ts:19-20`, `028…:30` |
| `cash_ledger` | `user_id, delta_cents, ref_type, created_at` | 본인 SELECT | `mypage/page.tsx:82-87` |
| `mentor_activity_events` | `id, mentor_id, event_type, reason, detail jsonb, status('logged'|'pending_review'|'approved'|'released'), reviewed_by, reviewed_at, created_at` | authenticated 불가(RPC 로만 기록) | `103…:36-61` |
| `disputes` | `mentor_id, student_id, custom_request_order_id, status(open|under_review|escalated|resolved|…)` | 당사자 SELECT **(확인 필요)** | `disputeListQueries.ts:209-234` |
| 뷰 `api_web_v1.mentor_directory_v1` | `mentor_id, nickname, university_name, department_name, teaching_subjects, intro_line, profile_image_url, high_school_name, school_verified, school_tier, verified_major_category, verified_university_name, verified_department_name, is_open_for_subscriptions, avg_rating, review_count, created_at`(definer, 승인·active·삭제진행 아님만) | anon/authenticated SELECT | `20260803162808…:153-199` |
| RPC(authenticated 호출 가능) | `api_web_v1.mentor_profile_update_self`, `mentor_plan_prices_set_self`, `mentor_payout_account_update_self`, `mentor_settlement_self()`; `public.mentor_settlement_summary(date)`, `mentor_settlement_lines(tstz,tstz)`, `calc_withholding_cents(bigint)`, `set_individual_question_price(int)`, `mentor_cap_used(uuid)`, `mentor_cap_limit(uuid)`, `subscription_cap_weight(text)`, `get_mentor_review_stats(uuid,bool)`, `get_mentor_avg_response_hours(uuid)`, `individual_question_user_is_approved_mentor(uuid)`, `list_open_custom_request_posts_for_mentor_browse(int)` | GRANT 확인 근거 §3·§6·§2·`061…:75-90` | |
| 잠금값(TS/DB 정본) | 가격 밴드 `lib/subscribe/mentorPlanPricing.ts:13-29` = F8; cap 가중치/한도 DB 함수; 수수료 정책 `platformFeePolicy.ts:19-23`; 원천징수 0.033·지급일 23 `payoutComputation.ts:11-22`; 학교 등급/계열 `schoolVerificationConstants.ts:1-18`; 휴식 상수 `mentorActivity.ts:8-10` | | |

---

## 부록 A. 발견된 불일치·주의점(설계 입력)
1. `/mentor/dashboard`·`/mentor/channel` 은 page 없이 `loading.tsx` 만 존재하고 `components/mentor/dashboard/*` 는 미사용 — 실질 홈은 `/mentor/mypage`.
2. 프로필 편집 폼의 `nickname`·`grade`·`tags` 입력은 저장 경로가 없다(nickname 미판독, grade/tags 는 F7 미전달). 학번(grade) 저장 컬럼도 F7 allowlist 에 없다.
3. 대학·학과 입력은 UI `readOnly` 이지만 F7 는 갱신을 허용한다(빈 값만 거부). 앱에서 잠금을 유지하려면 현재 값을 그대로 전달해야 하며, 바꾸면 192 B-4 트리거로 학교인증이 잠정(pending)으로 되돌아간다.
4. 학적 변경 액션만 파일 크기 상한(20MB) 검사가 없다.
5. `mentor_settlement_lines` 의 개별질문 라인은 RPC 내부 상수 0.85/0.15 로 계산된다(행 요율 아님) — CLAUDE.md "정책 요율 리터럴은 `platformFeePolicy.ts` 에만" 원칙과 DB 측 상수가 공존.
6. 허브 KPI `avgRating` 폴백이 참조하는 `mentor_profiles.avg_rating/review_count` 컬럼은 존재하지 않는다(뷰 주석 실측).
7. 멘토 받은 리뷰의 작성자 이름 마스킹은 `users` RLS(본인·admin) 때문에 멘토 세션에서 타인 행이 0행일 가능성이 높다(확인 필요).
8. `mentor_activity_events` 는 authenticated 정책이 없어 앱에서 멘토 본인 이력 조회 불가 — 필요 시 `mae_select_own` 정책 또는 RPC.
9. 무단 이탈(`requestMentorImmediateLeaveAction`)은 액션만 있고 UI 미연결.
