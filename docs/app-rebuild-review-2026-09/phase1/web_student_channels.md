# 웹 학생 채널 리포트 — 구독질문방 · 개별질문 · 멘토찾기 · 구독조회 · 마이페이지 · 홈 · 노트

- 대상 저장소: `/home/user/ssambership_web` (Next.js 16 App Router + Supabase). 앱 저장소(`/home/user/ssambership-app`, Flutter)는 "앱 이식 메모" 판단에 필요한 범위에서만 데이터 계층을 grep 했다(경로 앞에 `app:` 접두).
- 표기 규칙: `파일:행` 은 웹 저장소 루트 기준. SQL 은 `supabase/sql/…` 또는 `supabase/migrations/…`. 코드로 확인하지 못한 항목은 **(확인 필요)** 로 표시.
- 결제(캐시 충전·구독 결제 실행·토스)는 다른 리더 범위이며, 이 문서에서는 학생 채널이 결제와 접촉하는 지점만 "결제 접촉" 열에 분류한다. UI 디자인·레이아웃은 기술하지 않는다.

## §0 공통 인프라 (학생 채널 전체가 의존)

| 항목 | 정본 | 근거 |
|---|---|---|
| 학생 레이아웃 가드 | `app/(student)/layout.tsx` — 기본 `requireRole("student")` + 본인인증 게이트 `needsIdentityOnboarding(profile)` → `/onboarding/verify`. 예외 경로: `/individual-questions` 는 비로그인 열람 허용, `/account/delete`·`/settings/blocks` 는 플래그 게이트, `/wallet*` 은 `requireWalletChargeAccess`(학생·멘토) | `app/(student)/layout.tsx:12-107` |
| 역할 가드 | `requireRole(role)` — 미로그인/프로필 없음 → 로그인 redirect, 역할 불일치 → `getPostLoginPath`. `requireQnaActor()` — `public.users.role ∈ {student, mentor}` 만 신뢰(폼의 actor 값 무시) | `lib/auth/routeGuard.ts:41-59`, `:80-99` |
| 본인인증 게이트 플래그 | `IDENTITY_GATE_ENABLED === "true"` 일 때만 `identity_verified_at IS NULL` 유저를 온보딩으로 보냄(서버 전용 env) | `lib/identity/identityGateFlag.ts:12-24` |
| 기능 플래그 | `NEXT_PUBLIC_FEATURE_USER_BLOCKS`, `NEXT_PUBLIC_FEATURE_ACCOUNT_DELETION` (둘 다 기본 ON, off/0/false/no 로 킬), `NEXT_PUBLIC_FEATURE_CUSTOM_REQUEST`(기본 OFF) | `lib/shell/featureFlags.ts:5-34` |
| `api_web_v1` envelope 호출부 | `callApiWebV1Rpc(supabase, fn, args)` — `supabase.schema("api_web_v1").rpc(fn)`; 성공 `{ok:true, contract_version:1, …}`, 거부 `{ok:false, code}`; `ok` 부재는 성공 아님; 사전 밖 예외는 PostgREST 오류로 전파(코드 `[A-Z][A-Z0-9_]{3,}` 추출) | `lib/apiWebV1/rpc.ts:15-59` |
| service_role 클라이언트 | `createServiceRoleClient()` — `SUPABASE_SERVICE_ROLE_KEY` 필수, `server-only`. 이 클라이언트를 쓰는 server action 은 앱이 그대로 재현 불가(§7) | `lib/supabase/admin.ts:12-23` |
| 공개 멘토 읽기 정본 | `api_web_v1.mentor_directory_v1` 뷰(security_invoker=false, anon+authenticated SELECT). 행 존재 = 승인·활성 멘토. PII 는 `nickname` 만 | `lib/auth/mentorPublicRead.ts:6-18`, `supabase/sql/20260730095441_api_web_v1_read_views.sql:171-219` |
| 실시간 | 웹 학생 표면(질문방·개별질문·마이페이지)은 Realtime 을 쓰지 않는다(폼 제출 후 `redirect`/`router.refresh`). grep 결과 0건 | `lib/qna`, `components/qna`, `app/(student)` 전체 grep |

## §1 라우트별 기능 표

열: 라우트 | 목적 | 역할 | 사용자 액션(읽기/쓰기) | 서버 표면(RPC·시그니처 / 테이블·뷰 / service_role 여부 / API route) | 결제 접촉 | 플래그·게이트 | 앱 이식 메모

### 1-1. 레거시 redirect (한 줄씩)

| 라우트 | 동작 | 근거 |
|---|---|---|
| `/home` | `redirect("/mypage")` — 구 학생 대시보드 폐기 | `app/(student)/home/page.tsx:3-6` |
| `/notes` | `redirect("/question-room")` — 연결노트 독립 뷰 미구현(질문방 내 패널) | `app/(student)/notes/page.tsx:3-7` |
| `/questions` · `/questions/[roomId]` | `/question-room`, `/question-room/[roomId]` 로 redirect | `app/(student)/questions/page.tsx:3-5`, `app/(student)/questions/[roomId]/page.tsx:7-10` |
| `/cash-history` | `redirect("/wallet/ledger")` | `app/(student)/cash-history/page.tsx:6-8` |
| `/individual-questions/direct` | `redirect("/individual-questions#direct-mentor-board")` | `app/(student)/individual-questions/direct/page.tsx:4-6` |

### 1-2. 페이지 라우트

| 라우트 | 목적 | 역할 | 사용자 액션 | 서버 표면 | 결제 접촉 | 플래그·게이트 | 앱 이식 메모 |
|---|---|---|---|---|---|---|---|
| `/mypage` | 학생 허브(프로필·질문방 수·구독 수·개별질문 수·결제 수·캐시 잔액·최근 원장 5행·알림/지원 링크) | student | 읽기 | 세션 클라이언트: `mentor_student_rooms`(student_id), count `subscriptions.student_id`·`payments.user_id`·`notifications.user_id`·`reviews.author_id`·`content_reports.reporter_id`, `individual_questions.student_id` count, `api_web_v1.my_wallet_v1`, `api_web_v1.my_cash_ledger_v1`(5행), 클라이언트 카드가 `GET /api/mypage/active-subscriptions` → `api_web_v1.my_subscriptions_self()`. service_role 없음 | 상태 읽기(잔액·원장·결제 건수) | `requireRole("student")`; 차단관리·탈퇴 링크는 플래그 ON 시만 | 전부 RLS·뷰·SECDEF RPC 로 앱 세션 직접 가능 (`app/(student)/mypage/page.tsx:36-56`, `lib/mypage/mypageQueries.ts:96-110`, `lib/mypage/studentActiveSubscriptions.ts:34-43`) |
| `/question-room` | 질문방 목록. `?mentorId=` 진입 시 해당 멘토 방으로 redirect, 없으면 무료 질문방 확보 후 redirect. 방 있으면 첫 방으로 redirect | student | 읽기 + (무료 방 생성 쓰기) | `loadQuestionRoomListBundle` → `mentor_student_rooms`·`question_threads`·`question_messages`(세션 RLS); `ensureFreeQuestionRoomForStudent` → `api_web_v1.ensure_free_question_room(p_mentor_id)`. service_role 없음 | 없음 | requireRole student | F2 는 `api_app_v1.ensure_free_question_room` 동명 wrapper 로 앱에 이미 노출(§2-1) (`app/(student)/question-room/page.tsx:19-47`) |
| `/question-room/[roomId]` | 방 상세(스레드 목록·주간 한도 바·새 질문 모달·연결노트 패널). `?thread=` 는 `/thread/[threadId]` 로 승격 redirect | student | 읽기 + 쓰기(스레드 생성·메시지·첨부·노트) | 읽기: `mentor_student_rooms`, `question_threads`(mentor_student_room_id), `question_messages`(thread_id), `connection_notes`(mentor_student_room_id), `question_attachments`(+서명 URL 1h), `subscriptions`(플랜 컨텍스트), `api_web_v1.weekly_question_usage_self` 멘토별. 쓰기: §2 참조. service_role 없음(무료 스레드 판정 내부 읽기만 service_role, §2-4) | 없음(구독 플랜 라벨 표시만) | requireRole student + `userCanAccessMentorStudentRoom`(당사자 검사) | 페이지 로더는 전부 세션 RLS. 쓰기는 server action/API route 이지만 내부 RPC 는 authenticated 실행 가능(§7) (`app/(student)/question-room/[roomId]/page.tsx:71-113`) |
| `/question-room/[roomId]/thread/[threadId]` | 스레드 상세(채팅·확인·첨부) | student | 읽기 + 쓰기 | 위와 동일 + `resolvedThreadId` 없으면 404 | 없음 | 동일 | 동일 (`app/(student)/question-room/[roomId]/thread/[threadId]/page.tsx:52-97`) |
| `/individual-questions` | 내 개별질문 목록 + 지정형 멘토 게시판(공개 디렉터리 재사용) | student(비로그인 열람 허용) | 읽기 | `individual_questions`(student_id, limit 100), `users`(RLS 본인만)+`mentor_directory_v1` 닉네임 보강, `mentor_individual_question_pricing`(로그인 시 배치), `loadDirectMentorBoard` → `loadPublicMentorsList`. service_role 없음 | 상태 읽기(단가 표시) | 레이아웃 예외: 비로그인 허용, 멘토/관리자는 본인 영역 redirect | 전부 RLS 직접 가능 (`app/(student)/individual-questions/page.tsx:14-30`, `lib/individualQuestion/directMentorBoard.ts:65-118`) |
| `/individual-questions/new` | 공개형 개별질문 등록(캐시 에스크로 hold) | student | 쓰기 | server action `createOpenIndividualQuestionAction` → **service_role** `create_individual_question_with_hold_v2(...)`, 첨부 업로드도 service_role | **결제 실행(캐시 hold)** | requireRole student + `requireVerifiedIdentity` + `assertAccountActive` | 앱 제외 후보(오너 방침). 필요 시 앱용 authenticated wrapper `create_individual_question_as_student` 존재(자격조건·과목 인자 없음, §3-2) |
| `/individual-questions/direct/[mentorId]` | 지정형 개별질문 등록(탭 내 경로, `origin=iq-tab`) | student | 쓰기 | `createDirectIndividualQuestionAction` → service_role `create_individual_question_with_hold_v2` (가격은 `mentor_individual_question_pricing.amount_cents` 서버 재조회) | **결제 실행(캐시 hold)** | 동일 + 멘토 승인 검사 | 동일 (`app/(student)/individual-questions/direct/[mentorId]/page.tsx:32-50`) |
| `/mentors/[mentorId]/individual-question/new` | 지정형 개별질문 등록(멘토 상세 진입 경로) | student | 쓰기 | 동일 폼 `DirectIndividualQuestionFormSection` → 동일 action | **결제 실행** | 동일 | 동일 (`app/(student)/mentors/[mentorId]/individual-question/new/page.tsx:24-43`) |
| `/individual-questions/[questionId]` | 개별질문 상세(대화·첨부·상태·해결완료·구독방 이전 링크) | student(본인 질문만, 아니면 목록 redirect) | 읽기 + 쓰기(메시지·첨부·해결완료) | 읽기: `individual_questions`·`individual_question_messages`·`individual_question_attachments`(서명 URL 10분)·`individual_question_transfers`(RLS). 쓰기: `sendIndividualQuestionMessageAction`(service_role INSERT), `confirmIndividualQuestionAnswerAction` → service_role `release_individual_question_payout(p_question_id)` | **정산 실행(해결완료 = 에스크로 → 멘토 지급)**, 메시지는 없음 | requireRole student + `assertAccountActive` | 메시지/첨부/해결완료 모두 앱용 authenticated SECDEF RPC(`iq_append_message`, `add_individual_question_attachment`, `release_individual_question`)가 이미 존재(§3) |
| `/mentors` (public) | 멘토 찾기(필터·정렬·페이징·찜/최근 스코프) | 누구나 | 읽기 (+찜 쓰기는 API) | `api_web_v1.mentor_directory_v1` 전량 순회, `reviews`, `mentor_plans`, `school_tier_catalog`·`major_category_catalog`, `favorites`(로그인 시); cap 배지만 **service_role** `mentor_cap_used/mentor_cap_limit` | 없음(가격 표시만) | 없음 | 디렉터리·플랜·리뷰집계는 anon/authenticated 직접 읽기 가능. 인메모리 필터·정렬은 앱이 미러링해야 함(§4-1) |
| `/mentors/[mentorId]` (public) | 멘토 상세(프로필·리뷰 통계·플랜 가격·평균 응답시간·구독/무료질문/개별질문 CTA·찜·리뷰 작성) | 누구나(미승인 멘토는 본인/관리자만) | 읽기 + (찜·리뷰 쓰기는 API) | `loadPublicMentorBundle`(디렉터리 + `get_mentor_review_stats` + `mentor_plans`), `checkReviewEligibility`(학생), `favorites`, `free_question_usage`(잔여 무료질문), `get_mentor_avg_response_hours`, `mentor_individual_question_pricing`; cap 은 service_role | 상태 읽기(플랜 가격·개별질문 단가) | 미승인 멘토 숨김(`mentorVerificationStatusAllowsActivity`) | §4-2. 클라이언트에서 `localStorage` 최근본 기록 (`app/(public)/mentors/[mentorId]/page.tsx:27-103`) |
| `/subscribe` | 구독 체크아웃(플랜 선택·캐시 잔액·cap 마감 tier) | student | 쓰기(결제) | `loadStudentSubscribePage`(디렉터리+`mentor_plans`), `my_wallet_v1`, `loadMentorCapUsage`(service_role); 클라이언트 `POST /api/subscribe/checkout` | **결제 실행** | requireRole student + 멘토 승인 | 앱 제외(결제). 참고만 (`app/(student)/subscribe/page.tsx:26-121`) |
| `/subscribe/success` · `/fail` · `/cancelled` | 결제 결과 표시. success 는 `findActiveSubscriptionForPair` 로 활성 구독 재확인 | student | 읽기 | `subscriptions`(RLS) | 상태 읽기 | requireRole student | 앱 제외(결제 후속) (`app/(student)/subscribe/success/page.tsx:17-41`) |
| `/subscriptions` | 구독 현황·해지 예약/취소·환불 예상액·재구독 링크 | 로그인 사용자(학생 로그인으로 유도) | 읽기 + 쓰기(해지 예약/취소) | `loadStudentSubscriptionManagementList`: `subscriptions`, `subscription_billing_events`, `refunds`(pending), `mentor_plans`, 디렉터리, `mentor_student_rooms`+`question_threads`(이용개시 판정). 쓰기: `requestSubscriptionCancelAtPeriodEndAction`/`undo…` → **service_role** UPDATE `subscriptions` | 상태 읽기(결제 이력) + **상태 변경(cancel_at_period_end)** — 결제 실행 아님 | `getServerUserWithProfile` 로그인 필수 | 해지 예약/취소는 service_role UPDATE → 앱은 새 SECDEF RPC 필요(§5, §7) |
| `/wallet/ledger` | 캐시 원장(기간 필터) | 학생(멘토는 `/wallet/charge` 로 redirect) | 읽기 | `api_web_v1.my_wallet_v1`, `api_web_v1.my_cash_ledger_v1`(range 1000 배치·상한 3000·KST 경계); `PaysyncPendingLedgerSection` 은 **service_role** | 상태 읽기(진행 중 무통장 주문 포함) | 로그인 | 뷰는 앱 세션 직접 읽기 가능(앱이 이미 `my_wallet_v1`·`my_cash_ledger_v1` 사용). 무통장 pending 섹션만 service_role(§7) (`app/(student)/wallet/ledger/page.tsx:14-64`, `lib/cash/cashQueries.ts:24-102`) |

### 1-3. 학생 채널 API route

| 라우트 | 메서드·입력 | 역할 게이트 | 서버 표면 | service_role | 앱 이식 메모 |
|---|---|---|---|---|---|
| `/api/question-room/threads` | POST `{roomId, title\|threadTitle, subject\|subjectTag, topic}` | student(`getQnaApiSession`) | `createStudentQuestionThread` → 빈 제목이면 `질문 N`(room 스레드 수+1) → `api_web_v1.qna_create_question_thread(p_room_id,p_title,p_subject,p_topic,p_first_message_body)`; 429 시 `code:"weekly_limit_exceeded"` | 없음 | 앱은 `api_app_v1.qna_create_question_thread` 동일 시그니처 직접 호출(`app:lib/features/question_room/data/question_room_write_repository.dart:83`). "질문 N" 자동 제목은 TS 로직 → 앱 미러링 필요 (`app/api/question-room/threads/route.ts:5-67`, `lib/qna/questionRoomThreadService.ts:39-68`) |
| `/api/question-room/threads/[threadId]/confirm` | PATCH `{roomId}` | student | `public.qna_confirm_thread(p_thread_id uuid)` | 없음 | 앱 이미 사용(`…write_repository.dart:177`) (`app/api/question-room/threads/[threadId]/confirm/route.ts:7-47`) |
| `/api/question-room/threads/[threadId]/wrong-answer` | PATCH `{roomId, isWrongAnswer}` | student | `public.qna_flag_wrong_answer(p_thread_id uuid, p_is_wrong boolean default true)` | 없음 | 웹 학생 UI 에선 토글이 주석 처리됨(라우트·컬럼은 유지) `components/qna/QuestionRoomStudentDesignWorkspace.tsx:36,762` (`app/api/question-room/threads/[threadId]/wrong-answer/route.ts:7-49`) |
| `/api/question-room/weekly-usage` | GET `?mentorId=` | student | `fetchWeeklyQuestionUsageSelf` → `api_web_v1.weekly_question_usage_self(p_mentor_id)`; 응답 `{ok, usage:{used,limit,remaining,canAsk,limitLabel,planTier,freeQuota,weekStart,weekEnd}}` | 없음 | 앱은 F1·`weekly_question_usage_self_batch` 직접 호출 중(`app:…question_room_read_repository.dart:149,172`) (`app/api/question-room/weekly-usage/route.ts:15-51`) |
| `/api/mentors/favorites` | GET / POST `{mentorId}` / DELETE `?mentorId=` | 로그인(역할 무관) | `favorites`(user_id, mentor_id) select/insert/delete — RLS `favorites_select_own/insert_own/delete_own` | 없음 | 앱은 테이블 직접 접근 가능 (`app/api/mentors/favorites/route.ts:6-58`, `lib/mentor/mentorFavorites.ts:3-50`, `supabase/sql/034_mentor_favorites.sql:4-28`) |
| `/api/mentors/scoped` | POST `{ids: uuid[]}`(최대 30) | 없음(공개) | `loadScopedMentorsList`(디렉터리 전량 → id 필터·순서 보존) — 최근 본 멘토 카드용 | 없음 | 앱은 `mentor_directory_v1 .in('mentor_id', ids)` 로 대체 가능 (`app/api/mentors/scoped/route.ts:12-45`) |
| `/api/mypage/active-subscriptions` | GET | student | `loadActiveSubscriptionsForStudent` → `api_web_v1.my_subscriptions_self()` + `mentor_plans` 배치 + 디렉터리 닉네임 | 없음 | RPC 직접 호출 가능 (`app/api/mypage/active-subscriptions/route.ts:6-34`) |
| `/api/reviews` | GET `?mentorId&page&limit(≤50)` / POST `{mentorId, rating, body\|content}` | GET 공개 / POST student | `listMentorReviews`·`createReview`(§4-5) — 세션 클라이언트, RLS `reviews_insert_student` 가 `check_review_eligibility` 강제 | 없음 | 앱 직접 INSERT 가능하나 길이·중복·마스킹 검증은 TS 에만 있음(§7) (`app/api/reviews/route.ts:6-61`) |
| `/api/reviews/[id]` | GET(본인 후기 prefill) / PATCH `{rating, body}` | student | `updateReview` — 작성자·비모더레이션만, RETURNING 1행 판정 | 없음 | 동일 (`app/api/reviews/[id]/route.ts:9-87`) |
| `/api/reviews/eligibility` | GET `?mentorId=` | student(아니면 `eligible:false`) | `checkReviewEligibility` → `{eligible, mode, existingReviewId, canEdit, reason}` | 없음 | 정본은 DB `check_review_eligibility(p_mentor_id, p_student_id)`(§4-5) (`app/api/reviews/eligibility/route.ts:6-28`) |
| `/api/reviews/[id]/reply` · `/hide` | PATCH | mentor / admin | 멘토 답글·관리자 숨김 — 학생 채널 아님 | 없음 | 제외 |
| `/api/admin/question-export` | — | admin | 관리자 전용 질문 내보내기 — 학생 채널 아님 | — | 제외 |

## §2 질문방 상세

### 2-1. 방(room) 생성 경로

| 경로 | 구현 | 근거 |
|---|---|---|
| 무료 질문권 진입 | 멘토 상세 "무료 질문권 사용하기" → `/question-room?mentorId=` → 기존 방 있으면 redirect, 없으면 `ensureFreeQuestionRoomForStudent(supabase, mentorId)` → `api_web_v1.ensure_free_question_room(p_mentor_id uuid) returns jsonb` (F2) → `core_private.ensure_student_mentor_room(auth.uid(), p_mentor_id, NULL, NULL, true)` | `app/(student)/question-room/page.tsx:27-40`, `lib/qna/freeQuestionRoom.ts:55-76`, `supabase/sql/20260730105248_api_web_v1_self_rpc.sql:104-124` |
| F10 정본 | `core_private.ensure_student_mentor_room(p_student_id, p_mentor_id, p_payment_id default null, p_subscription_id default null, p_require_entitlement default true) returns jsonb` — ① 학생 role ② 계정상태(banned/suspended)·탈퇴 write-block ③ 멘토 role·승인·상호 차단 ④ 학생 행 `FOR UPDATE` 후 자격(활성 구독 → `subscription`, 아니면 가입 7일·전역 7회·멘토별 3회 무료 자격 → `free`; `p_require_entitlement=false` 면 검사 생략) ⑤ 기존 방 조회 ⑥ `INSERT … ON CONFLICT (student_id, mentor_id) DO NOTHING` ⑦ 재조회. 반환 `{ok, room_id, created, entitlement}`. 외부 EXECUTE 0 | `supabase/migrations/20260731101845_20260730105244_core_private_room_ensure.sql:75-186` |
| F2 오류코드 | `AUTH_REQUIRED, ROLE_NOT_STUDENT, ACCOUNT_BANNED, ACCOUNT_SUSPENDED, ACCOUNT_DELETION_IN_PROGRESS, MENTOR_NOT_FOUND, MENTOR_NOT_APPROVED, BLOCKED, FREE_QUOTA_EXPIRED, FREE_QUOTA_TOTAL_EXHAUSTED, FREE_QUOTA_MENTOR_EXHAUSTED, ROOM_ENSURE_FAILED` (12종) — 웹 문구 매핑 `f2CodeToUserMessage` | `docs/contracts/api_web_v1_contract_v1_1.md:944`, `lib/qna/freeQuestionRoom.ts:14-41` |
| 구독 결제 시 | 구독 확정 RPC(F12 `api_web_v1.subscription_checkout_confirm_v2`)가 F10 을 `p_require_entitlement=false` 로 호출해 방을 확보(계약 §7 F10) — 결제 리더 범위 **(확인 필요: `lib/subscribe/subscribeCheckoutService.ts` 미열람)** | `docs/contracts/api_web_v1_contract_v1_1.md:859,1081`, F10 본문 `:145-147` |
| 레거시 직접 INSERT | RLS `msr_insert_with_active_subscription`(026) 가 활성 구독 보유 시 직접 INSERT 허용 — 앱 직접 INSERT 경로 존재 여부 **(확인 필요)** | `supabase/sql/026_p0_msr_insert_subscription_check.sql:4` |
| 앱 현황 | 앱은 `api_app_v1.ensure_free_question_room` + 레거시 `public.qna_create_free_question_thread` 를 호출 | `app:lib/features/mentors/data/free_question_entry.dart:170-198` |

`mentor_student_rooms` 컬럼: `id, student_id, mentor_id, payment_id, subscription_id, created_at, updated_at` (uq `(student_id, mentor_id)`) — `…core_private_room_ensure.sql:47-52`. 당사자 판정은 `student_id`/`mentor_id` 만(별칭 열 없음) `lib/qna/questionRoomQueries.ts:10-21`.

### 2-2. 스레드·메시지·확인·오답·첨부 RPC (정본 SQL 136, 웹 래퍼 `lib/qna/questionRoomRpc.ts`)

| RPC | 시그니처 | 반환 | 검사·부수효과 | 근거 |
|---|---|---|---|---|
| 스레드 생성 | `api_web_v1.qna_create_question_thread(p_room_id uuid, p_title text, p_subject text=null, p_topic text=null, p_first_message_body text=null)` → 내부 `public.qna_create_question_thread(동일)` | `{ok, contract_version, thread_id, message_id, path:'free'\|'subscription', used_free_quota}` | AUTH → 제목 필수 → 방 존재 → 호출자=학생(멘토면 `MENTOR_CANNOT_CREATE_THREAD`) → 학생 행 `FOR UPDATE` → banned/suspended → `user_blocks` 상호 차단 → 멘토 승인(`individual_question_user_is_approved_mentor`) → 활성 구독이면 `get_weekly_question_usage.can_ask` 아니면 `WEEKLY_LIMIT_EXHAUSTED`; 없으면 무료 자격(가입 7일/전역 7/멘토별 3) → `subject` 는 `public.subjects.code` 존재 검증(아니면 null) → `question_threads` INSERT `status='pending'` → 첫 메시지 선택 INSERT → free 면 `free_question_usage(student_id, mentor_id, thread_id)` INSERT | `supabase/sql/136_p1_8a_question_room_atomic_rpc.sql:65-176`, `lib/qna/questionRoomRpc.ts:98-127` |
| 메시지 append | `public.qna_append_message(p_thread_id uuid, p_body text)` | `{ok, message_id, answered_transition}` | AUTH → 본문 필수 → 스레드 존재 → 당사자 → banned → `THREAD_LOCKED`(status ∈ confirmed/closed/archived) → 멘토면 승인 → INSERT `question_messages(thread_id, author_id, body)` → 멘토 첫 답변(`first_answered_at IS NULL`)이면 `status='answered', first_answered_at=now()` + `record_domain_notification('question_answered:'||thread_id, …, '/question-room/{room}?thread={thread}')` exactly-once. **구독 만료·무료 스레드 여부는 RPC 가 검사하지 않음**(웹은 server action 사전 게이트로 보강, §2-4) | `…136…:194-265`, `lib/qna/questionRoomRpc.ts:135-153` |
| 학생 확인 | `public.qna_confirm_thread(p_thread_id uuid)` | `{ok}` | AUTH → 스레드 → 호출자=학생(`STUDENT_ONLY`) → status='answered' 아니면 `NOT_ANSWERED` → `confirmed` 전이 | `…136…:266-285` |
| 오답 표시 | `public.qna_flag_wrong_answer(p_thread_id uuid, p_is_wrong boolean default true)` | `{ok}` | AUTH → 학생만 → `question_threads.is_wrong_answer` 갱신 | `…136…:286-305`, 컬럼 `supabase/sql/060_ai_readiness_question_schema.sql:42-53` |
| 첨부 등록 | `public.qna_register_attachment(p_thread_id uuid, p_storage_path text, p_file_name text=null, p_mime_type text=null, p_message_id uuid=null)` | `{ok, attachment_id, answered_transition}` | AUTH → 경로 필수 → 스레드 `FOR UPDATE` → 당사자 → `THREAD_LOCKED` → 경로의 room uuid 가 스레드 room 과 일치(`STORAGE_PATH_MISMATCH`) → storage 객체 존재+bucket 일치+`owner_id=auth.uid()` → `p_message_id` 있으면 같은 스레드 메시지(`MESSAGE_THREAD_MISMATCH`) → `question_attachments(thread_id, message_id, author_id, storage_path, file_name, mime_type)` INSERT → 멘토 첫 첨부면 answered 전이 + 알림 | `supabase/sql/139_p1_8a_attachment_storage_contract.sql:52-93` |
| 권한 | 위 5종 모두 SECURITY DEFINER, `revoke from public, anon`, `grant execute to authenticated, service_role` | `…136…:381-394`, `…139…:92-93`, `…20260730105248…:311-323` |

오류코드 → 사용자 문구 사전(도메인 thread/message/confirm/wrong/attachment): `AUTH_REQUIRED, TITLE_REQUIRED, BODY_REQUIRED, STORAGE_PATH_REQUIRED, ROOM_NOT_FOUND, THREAD_NOT_FOUND, MENTOR_CANNOT_CREATE_THREAD, NOT_ROOM_PARTY, STUDENT_ONLY, ACCOUNT_BANNED, ACCOUNT_SUSPENDED, BLOCKED, MENTOR_NOT_APPROVED, THREAD_LOCKED, NOT_ANSWERED, STORAGE_PATH_MISMATCH, MESSAGE_THREAD_MISMATCH, FREE_QUOTA_EXPIRED, FREE_QUOTA_TOTAL_EXHAUSTED, FREE_QUOTA_MENTOR_EXHAUSTED, WEEKLY_LIMIT_EXHAUSTED` — `lib/qna/questionRoomRpc.ts:30-83`. F3 wrapper 가 추가로 envelope 화하는 코드: `ACCOUNT_DELETION_IN_PROGRESS, SUBSCRIPTION_REFUND_PENDING, FREE_QUOTA_STUDENT_NOT_FOUND`, 트리거 코드 수렴 `FREE_QUESTION_EXPIRED→FREE_QUOTA_EXPIRED, FREE_QUESTION_TOTAL_LIMIT→FREE_QUOTA_TOTAL_EXHAUSTED, FREE_QUESTION_PER_MENTOR_LIMIT→FREE_QUOTA_MENTOR_EXHAUSTED` — `supabase/sql/20260730105248_api_web_v1_self_rpc.sql:148-176`. API HTTP 매핑: 404(ROOM/THREAD_NOT_FOUND), 429(WEEKLY_LIMIT_EXHAUSTED), 400(NOT_ANSWERED), 403(권한·계정·차단·승인·무료한도), 500 기타 — `lib/qna/questionRoomThreadService.ts:10-34`.

직접 테이블 write 우회 방어: 141/144 트리거가 `current_user='authenticated'` 직접 INSERT/UPDATE 에 대해 스레드 생성 자격(BEFORE)·무료 usage 원자 소비(AFTER)·콘텐츠 없는 answered 직접 UPDATE 거부를 강제 — `supabase/sql/141_p1_8a_direct_write_guards.sql:1-12`, `supabase/sql/144_p1_8a_direct_write_eligibility.sql:1-17`. RLS: `qt_select_via_room/qt_write_via_room/qt_update_via_room`, `qm_select/qm_insert`(002:179-237), `question_attachments_select_via_room/insert_via_room`(060:126-147, 117:25).

### 2-3. 웹 server action 계층(폼 → RPC 전 사전 게이트)

| 액션 | 폼 필드 | 사전 게이트 순서 | RPC | 근거 |
|---|---|---|---|---|
| `createQuestionThreadAction` | `roomId, threadTitle, contextThreadId` | `requireQnaActor` → `assertAccountActive` → 멘토면 거부 → 방 당사자 → RPC | F3 | `lib/qna/questionRoomActions.ts:167-237` |
| `createQuestionMessageAction`(=`sendQuestionMessageAction`) | `roomId, threadId, messageBody, contextThreadId` | account → 방 당사자 → 멘토 승인 → `assertThreadCreationSubscriptionAllowed(isNewThread:false, threadId)` → 스레드 소속 → 잠금(fail-closed) → RPC | `qna_append_message` | `:239-354` |
| `sendQuestionAttachmentAction` | `roomId, threadId, attachment(File)` | 파일·스레드 필수 → 당사자 → 멘토 승인 → 소속 → 잠금 → 구독 게이트 → 업로드(세션 클라이언트) → 등록 RPC → 실패 시 객체 보상 삭제 | `qna_register_attachment` | `:362-487` |
| `saveConnectionNoteAction` / `updateConnectionNoteAction` / `deleteConnectionNoteAction` | `roomId, noteBody, contextThreadId` / `+noteId` | account → 방 당사자 → `assertConnectionNoteWriteAllowed` → (수정·삭제는 author 본인 확인) → 테이블 직접 write | 없음(RLS) | `:489-655` |

redirect 계약: 학생은 `/question-room/{roomId}?thread=&ok=&error=&kind=thread|message|note&dThread|dMessage|dNote(base64url 초안)&t=` — `lib/qna/questionRoomRedirect.ts:16-84`, `lib/qna/draftQuery.ts:6-18`.

### 2-4. 주간 한도

- 정본: `public.get_weekly_question_usage(p_student_id uuid, p_mentor_id uuid)` — 활성 구독 `plan_tier` → limit `limited 4 / standard 9 / premium 999 / 기타 0`; 주 경계 = `coalesce(subscriptions.started_at, created_at)` 앵커 7일 롤링; 사용량 = 주 시작 이후 `question_threads.created_at` 건수; 반환 `{used, limit, plan_tier, remaining, can_ask, week_start, week_end}`; pair-party 가드 `NOT_PAIR_PARTY`(42501, service_role 통과) — `supabase/sql/098_weekly_usage_count_on_create.sql:33-96`, `supabase/sql/20260729211941_weekly_usage_pair_party_guard.sql:24-96`, 계약 `docs/contracts/api_web_v1_contract_v1_1.md:885-905`.
- 학생 self: `api_web_v1.weekly_question_usage_self(p_mentor_id uuid)` → 위 정본을 `auth.uid()` 로 호출 + envelope; 사전 검사 `AUTH_REQUIRED`, `MENTOR_ID_REQUIRED` — `supabase/sql/20260730105248_api_web_v1_self_rpc.sql:84-100`.
- 배치: `api_web_v1.weekly_question_usage_self_batch(p_mentor_ids uuid[]) returns jsonb {ok, items:[{…, mentor_id}]}` — 최대 50, 초과 `TOO_MANY_MENTORS`, authenticated — `supabase/baseline/post_ledger_backfills/20260806041547_weekly_question_usage_self_batch.sql:7-37`. **웹은 배치를 쓰지 않고 멘토별 F1 을 `Promise.all`** — `lib/qna/weeklyQuestionUsage.ts:170-183`.
- 폴백 로직: RPC 실패 시 구 JS 집계로 되돌아가지 않고 `{used:0,limit:0,remaining:0,canAsk:false}` + error 반환. 성공했지만 `limit=0 && plan_tier=null`(활성 구독 없음)이면 **무료 질문권 스냅샷**(`freeQuota:true, limit=3(멘토별), remaining=min(멘토별 잔여, 전역 잔여)`)으로 표시 — `lib/qna/weeklyQuestionUsage.ts:76-126`. 표시 라벨: `limit>=999 → "무제한"`, `"주 N개 질문 · 잔여 r/N"`, `"무료 질문권 · 잔여 r/N"` — `lib/qna/weeklyQuestionUsageDisplay.ts:27-40`.
- 멘토 화면·service_role 경로는 레거시 `get_weekly_question_usage` 직접 호출(`fetchWeeklyQuestionUsagePairParty`) — `lib/qna/weeklyQuestionUsage.ts:133-157`.

### 2-5. 무료질문 3층 정책

| 층 | 역할 | 구현 | 근거 |
|---|---|---|---|
| ① 표시(UI) | 멘토 상세·질문방 바의 잔여 무료질문 | `loadFreeQuestionRemainingForMentor`: `users.created_at` 로 만료(가입+7일) 판정 → `free_question_usage` count(student_id, mentor_id) → `max(0, 3 - count)`; 비로그인 null. 전역 카운트 `countFreeQuestionsTotal`(≤7) | `lib/qna/freeQuestionUsage.ts:32-99`, RLS `fqu_select_own/fqu_insert_own`(`supabase/sql/044_free_question_usage.sql:24-35`) |
| ② 방 확보 | 구독 없이 방 열기(소비 없음) | F2/F10 (§2-1) | 위 |
| ③ 소비 | 스레드 생성 시 원자 INSERT `free_question_usage(student_id, mentor_id, thread_id)`; 트리거 `check_free_question_usage_limits`(가입 7일 `FREE_QUESTION_EXPIRED` P0003 / 멘토별 3 `FREE_QUESTION_PER_MENTOR_LIMIT` P0001 / 전역 7 `FREE_QUESTION_TOTAL_LIMIT` P0002) | `…136…:130-170`, `supabase/sql/052_free_question_policy_7_total_7day_expiry.sql:5-57` |
| 보조: 무료 스레드 식별 | 메시지/첨부 게이트에서 "이 스레드가 무료 스레드인가" = `free_question_usage.thread_id` 링크가 room 스레드에 있는지. **usage 행 조회는 service_role**(멘토 세션은 RLS 로 못 읽음) | `lib/qna/freeQuestionUsage.ts:200-282`, `lib/qna/questionThreadSubscriptionGuard.ts:44-62` |
| 보조: 우선 답변 | 멘토 화면에서 무료 스레드 최상단 고정 + 배지 `"무료 체험 · 우선 답변"` | `lib/qna/freeTrialPriority.ts:13-49`, `lib/qna/freeTrialPriorityLabel.ts:6` |
| 구 JS 게이트 | `assertFreeQuestionAllowed`·`recordFreeQuestionUsage`(P0001/2/3 문구)·`assertFreeQuestionAllowedAndRecord` 는 `assertThreadCreationSubscriptionAllowed(isNewThread:true)` 경로에만 남음(현재 스레드 생성은 RPC 가 정본이라 호출부 확인 필요) | `lib/qna/freeQuestionUsage.ts:101-189` **(확인 필요: isNewThread:true 호출자 존재 여부)** |

메시지 구독 게이트(`assertThreadCreationSubscriptionAllowed`): 방의 (student, mentor) 활성 구독 없음 → 무료 스레드면 허용, 아니면 "활성 구독을 찾을 수 없습니다"; 조회 실패는 fail-closed — `lib/qna/questionThreadSubscriptionGuard.ts:8-86`. 활성 구독 판정 `findActiveSubscriptionForPair`(`subscriptions` 최근 20행 중 `isRowSubscriptionActive`) — `lib/subscribe/subscribeCheckoutService.ts:41-63`.

### 2-6. 스레드 상태 enum·전이

- TS: `QuestionThreadWorkflowStatus = "pending" | "answered" | "confirmed"`; DB 레거시 `open→pending`, `closed/archived→confirmed` 매핑; 라벨 `답변 대기 / 진행 중 / 답변 완료` — `lib/qna/questionThreadStatus.ts:1-27`.
- 전이: 생성 `pending`(136:157) → 멘토 첫 메시지/첨부 `answered` + `first_answered_at`(136:240-247, 139:81) → 학생 확인 `confirmed`(136:266-285; `confirmed_at` 컬럼 060:60-62). 잠금: `confirmed/closed/archived` 에 메시지·첨부 불가(`isQuestionThreadLockedForMessages` `lib/qna/questionRoomUiLabels.ts:40-46`, RPC `THREAD_LOCKED`).
- 목록 탭 분류 `all/waiting/needReview/done` 과 칩 라벨 — `lib/qna/questionRoomUiLabels.ts:48-105`. 학생 안읽음 = `answered` 스레드 수 — `lib/qna/questionRoomStudentContext.ts:150-169`.
- 개별질문 이전 스레드는 `status='closed'` 로 생성(§3-7).
- 컬럼(060): `question_threads.subject(→public.subjects.code)`, `topic`, `is_wrong_answer`, `mastery_status`, `first_answered_at`, `confirmed_at` — `supabase/sql/060_ai_readiness_question_schema.sql:35-62`.

### 2-7. 연결노트 (`connection_notes`)

- 컬럼 정본 `mentor_student_room_id, body, author_id, author_role` — 저장은 **매번 새 행 append(upsert 아님)**, room 단위 공유 — `lib/qna/questionRoomMutations.ts:42-69`. 페이지는 `notes.rows[0].body` 를 `initialNoteText` 로 사용 — `app/(student)/question-room/[roomId]/page.tsx:113`.
- 수정/삭제: 작성자 본인만(앱 1차 + RLS `cn_update/cn_delete` `author_id = auth.uid()` AND 방 당사자) — `lib/qna/questionRoomActions.ts:559-655`, `supabase/sql/085_connection_notes_author_rls.sql:27-80`. 읽기 `cn_select` 방 당사자 — `supabase/sql/002_p0_subscriptions_questions_draft.sql:267-275`.
- 쓰기 구독 가드(앱 계층 전용, RLS 아님): 활성 구독 있으면 OK; `subscription_id` 링크 없고 (student, mentor) 구독 이력 0건이면 "진짜 무료 방"으로 허용; 이력은 있는데 활성 없으면 "구독 만료" 차단(읽기는 허용). 조회 실패 fail-closed — `lib/qna/connectionNoteSubscriptionGuard.ts:25-82`.

### 2-8. 첨부 Storage

- 버킷 `question-room-attachments`(private). 객체 경로 `${roomId}/${threadId}/${uuid}-${safeName}`; 허용 MIME `png, jpeg, webp, gif, pdf, zip, docx, pptx`; 20MB; 매직바이트 검증; 업로드는 **사용자 세션 클라이언트**(owner_id=auth.uid() 가 등록 RPC 검증에 필요) — `lib/qna/questionRoomAttachmentStorage.ts:5-61`.
- 표시: 서명 URL 은 렌더 시점 발급 TTL 3600s; `image/(png|jpe?g|webp|gif|avif)` 만 이미지 렌더(앱 HEIC 는 파일 칩 강등); 파일명은 `{uuid}-{name}`(웹)/`{ts}_{name}`(앱) 접두 제거 — `lib/qna/questionRoomAttachmentsQueries.ts:13-34,49-87`. message_id 연결(linked)/단독(standalone) 병합 규칙 — `lib/qna/questionRoomAttachmentView.ts:1-97`.
- 정책: `qra_storage_read_party`(select, 경로 첫 세그먼트 room 의 당사자), `qra_storage_insert_party`(insert, 당사자 + 스레드 writable + 141/149/151 계정·승인·자격 강화), `qra_storage_delete_unregistered_owner`(미등록 객체 본인 삭제), `qra_storage_read_admin` — `supabase/sql/049_question_room_attachments_storage.sql:13-63`, `…139…:29-49`, `supabase/sql/120_admin_console_fixes.sql:80`, `supabase/sql/149_p1_8a_storage_insert_eligibility.sql:62`, `supabase/sql/151_p1_10_account_deletion_saga.sql:87`. 앱은 이미 이 버킷 + `qna_register_attachment` 사용(`app:lib/features/question_room/data/attachments/attachment_upload.dart:387`).

### 2-9. 학생 표시명 RPC

`public.get_mentor_student_nicknames(p_student_ids uuid[]) returns table(id uuid, nickname text, full_name text)` — SECDEF, 호출자(`auth.uid()`)가 해당 학생과 활성 구독 또는 `mentor_student_rooms` 관계가 있을 때만 반환; authenticated·service_role — `supabase/sql/140_p3_9_student_nickname_subscription_room_scope.sql:14-43`. 웹 어댑터는 오류와 빈 결과를 구분(`error:true` → "표시 실패", 정상 빈 → "이름 미설정") — `lib/qna/studentDisplayNames.ts:16-53`. 학생 화면의 멘토 표시명은 디렉터리 뷰(`loadMentorDisplaysForQuestionRooms`) — `lib/qna/questionRoomStudentDisplay.ts:17-41`.

### 2-10. 질문 내보내기
`app/api/admin/question-export/route.ts` 는 관리자 전용 — 학생 채널 제외.

## §3 개별질문 상세

### 3-1. 유형·상태·상수
- `INDIVIDUAL_QUESTION_TYPES = ["direct","open"]`; `INDIVIDUAL_QUESTION_STATUSES = ["escrowed","assigned","open","claimed","answered","released","expired","refunded","canceled"]`(DB CHECK 9종 동일); 원장 reason `individual_question_escrow_hold / _payout / _refund`; 가격 자유(0·음수만 차단), placeholder 5,000캐시 — `lib/individualQuestion/individualQuestionTypes.ts:1-42`, `supabase/sql/170_review_eligibility_relationship_based.sql:29-30`.
- 라벨: `escrowed 예치중 / open 공개중 / assigned·claimed 답변중 / answered 답변완료 / released 완료 / refunded 환불 / expired 만료 / canceled 취소`; 대기 상태 = escrowed/open/assigned/claimed; 만료 임박 12h — `lib/individualQuestion/individualQuestionFormat.ts:23-119`. 금액 저장 cents(=캐시×100), 표시 ÷100 — `:2-6`.
- RPC 반환 타입 `public.individual_question_escrow_result(ok, code, message, question_id, status, ledger_id, wallet_balance_cents)` — `supabase/sql/070_individual_question_schema_escrow.sql:362-380`.

### 3-2. 생성(캐시 hold) — 결제 실행, 앱 제외 후보
- 웹: `createDirectIndividualQuestionAction`/`createOpenIndividualQuestionAction`(`lib/individualQuestion/individualQuestionActions.ts:121-301`): `requireRole(student)` → `requireVerifiedIdentity`(본인인증) → `assertAccountActive` → (direct) `assertMentorApprovedForAction` + `mentor_individual_question_pricing.amount_cents` 서버 재조회 / (open) `school_tier_catalog`·`major_category_catalog` 코드 검증 → `maskContactInUserText` → **service_role** `create_individual_question_with_hold_v2(p_student_id, p_question_type, p_mentor_id, p_subject, p_topic, p_title, p_body, p_price_cents, p_idempotency_key, p_required_school_tier, p_required_major_category)`(service_role 전용 grant) → `expires_at` best-effort UPDATE(assigned 72h / open 48h) → 첨부 업로드(service_role) → redirect `?created=1`.
- 결과 코드: `created / already_exists(멱등 재생) / insufficient_cash / mentor_not_approved / invalid_price / invalid_required_school_tier / invalid_required_major_category` — `supabase/sql/080_c_individual_question_qualification.sql:90-259`, 문구 `individualQuestionActions.ts:58-73`. 멱등키 형식 `iq_direct:{uuid}` / `iq_open:{uuid}`(페이지가 생성) — `app/(student)/individual-questions/new/page.tsx:27`, `…direct/[mentorId]/page.tsx:50`.
- 앱용 대안(이미 DB 존재): `public.create_individual_question_as_student(p_question_type text, p_title text, p_body text, p_amount_cents int=null, p_designated_mentor_id uuid=null, p_idempotency_key text=null) returns setof individual_questions` — authenticated SECDEF, 내부에서 v2 호출하되 **자격조건·subject·topic 은 null 고정**, direct 가격은 멘토 가격표에서 조회 — `supabase/sql/092_individual_question_create_claim_wrappers.sql:1-153`. 앱이 이미 사용(`app:lib/features/individual_question/data/individual_question_repository.dart:171`).

### 3-3. claim(멘토) — 참고
`claim_individual_question_v2(p_question_id, p_mentor_id)`(service_role) — 학교인증·자격·과목 게이트 코드 `mentor_not_approved / mentor_school_verification_required / mentor_qualification_not_met`; 앱용 `claim_individual_question_as_mentor(p_question_id)`(authenticated) — `supabase/sql/081_d_claim_gate.sql:18-108`, `…092…:161-196`. 공개 목록 `list_open_individual_questions_for_mentor(p_limit int=50)`(승인 멘토만, `question_type='open' and status='open' and claimed_mentor_id is null and (expires_at is null or > now())`, ≤100) — `…070…:200-245`.

### 3-4. 대화 메시지
- 웹: `sendIndividualQuestionMessageAction`(폼 `questionId, body, attachment`) — 세션 클라이언트로 `individual_questions` 당사자 판정(RLS `iq_select_party`) → 종결(`refunded/expired/canceled` 또는 `refund_ledger_id`)·정산완료(`released`) 차단 → **service_role INSERT** `individual_question_messages(question_id, author_id, body)`(빈 본문+첨부면 `"(첨부 파일)"`) → 첨부는 service_role 업로드+INSERT → `?sent=1`. 상태 전이 없음(멘토 "답변 확정"은 별도 액션) — `lib/individualQuestion/individualQuestionActions.ts:353-427`.
- DB 정본(앱 사용): `public.iq_append_message(p_question_id uuid, p_body text) returns jsonb {ok, message_id, answered_transition}` — 당사자(학생 또는 `coalesce(claimed, designated)` 멘토), 계정 4상태·탈퇴 write-block·상호 차단, `QUESTION_LOCKED`(released/refunded/expired/canceled), `escrowed` 에 멘토 불가(`NOT_ANSWERABLE_STATUS`), 멘토 승인; **멘토 첫 메시지가 claimed/assigned → answered 전이** — `supabase/sql/20260803142534_iq_append_message_v1.sql:4-67`. 코드: `AUTH_REQUIRED, BODY_REQUIRED, QUESTION_NOT_FOUND, NOT_QUESTION_PARTY, ACCOUNT_NOT_ACTIVE, ACCOUNT_BANNED, ACCOUNT_SUSPENDED, ACCOUNT_DELETION_IN_PROGRESS, BLOCKED, QUESTION_LOCKED, NOT_ANSWERABLE_STATUS, MENTOR_NOT_APPROVED`.
- 웹 멘토 답변확정 `confirmIndividualQuestionAnswerByMentorAction` 는 service_role 직접 `status='answered', answered_at` UPDATE(assigned/claimed 에서만) — `:430-486`. **웹(메시지≠전이, 명시 확정)과 RPC(첫 메시지=전이) 의미가 다르다** → 앱 설계 시 하나로 정합 필요.

### 3-5. 첨부
- 버킷 `individual-question-attachments`(private). 경로 `${questionId}/${uuid}-${safe}.${ext}`; **jpg/png/pdf 만**; 20MB; 매직바이트 — `lib/individualQuestion/individualQuestionAttachmentStorage.ts:13-88`. 서명 URL TTL 600s — `:90-96`. 정책 `iqa_storage_read_party / iqa_storage_insert_party`(경로 첫 세그먼트 question id 의 당사자) — `supabase/sql/070_individual_question_schema_escrow.sql:336-353`.
- 웹은 service_role 로 업로드+`individual_question_attachments` INSERT(author_id 명시). DB 정본(앱 사용): `public.add_individual_question_attachment(p_question_id uuid, p_storage_path text, p_file_name text, p_mime_type text, p_message_id uuid=null) returns jsonb` — authenticated·service_role, 멱등 — `supabase/sql/168_iq_attachment_register_rpc_idempotent.sql:78-178`, `supabase/sql/20260804113000_iq_attachment_message_author_guard.sql:53-56`.

### 3-6. release / refund / 만료 배치
- 학생 해결완료 `confirmIndividualQuestionAnswerAction`: 본인·`status='answered'` 만 → **service_role** `release_individual_question_payout(p_question_id)`(멱등 `iq_payout:{id}`, 15% 수수료 정본 096/109) → `?resolved=1` — `lib/individualQuestion/individualQuestionActions.ts:489-547`, `…070…:637-758`. 앱용: `public.release_individual_question(p_question_id)` authenticated·학생 본인 한정 — `supabase/sql/091_individual_question_release_refund_wrappers.sql:34-78`.
- 환불: `refund_individual_question_hold(p_question_id)`(service_role; 코드 `refunded/already_refunded/already_released/hold_missing/not_found`) — 웹 학생 UI 에는 환불 트리거 없음, cron 만료 배치만 호출. 앱용 `refund_individual_question(p_question_id)`(학생 본인) 존재 — `…091…:95-129`.
- 만료 배치 `runIndividualQuestionExpiryBatch`: `status ∈ {open, assigned, claimed}` 이고 `expires_at <= now` (+ `expires_at IS NULL` 행은 `created_at + 상태별 기본시간` 폴백) → 환불 RPC 병렬 5; `hold_missing` 은 `hold_ledger_id IS NULL` 행만 `canceled` 마킹 — `lib/individualQuestion/individualQuestionExpiryBatch.ts:117-215`, `…ExpiryScan.ts:7-64`. env: `IQ_OPEN_EXPIRY_HOURS 48`, `IQ_CLAIMED_ANSWER_HOURS 48`, `IQ_DIRECT_EXPIRY_HOURS 72`, `IQ_EXPIRY_BATCH_LIMIT 100(≤500)`, `INDIVIDUAL_QUESTION_EXPIRY_ENABLED` — `lib/individualQuestion/individualQuestionExpiryConfig.ts:3-44`. 앱 wrapper 가 `expires_at` 을 설정하는지 **(확인 필요)** — NULL 이어도 배치 폴백으로 만료됨.

### 3-7. 구독방 이전(transfer)
`transferReleasedIndividualQuestionsToRoom(admin, {studentId, mentorId, roomId})` — 구독 확정 직후 service_role 로, 같은 멘토의 `released` 질문을 `question_threads(status='closed', subject, first_answered_at, confirmed_at)` + 원본 본문을 학생 첫 메시지로 + 메시지 복사 + 첨부 버킷 간 복제 + `individual_question_transfers(individual_question_id, student_id, mentor_id, room_id, thread_id)` 멱등 기록 — `lib/individualQuestion/transferIndividualQuestionsToRoom.ts:189-241`. 학생 상세는 `fetchIndividualQuestionTransfer` → `/question-room/{room}/thread/{thread}` 링크 — `lib/individualQuestion/individualQuestionQueries.ts:310-322`, `components/individualQuestion/IndividualQuestionViews.tsx:249-256`. RLS `iqt_select_student` — `supabase/sql/075_individual_question_transfers.sql:34`.

### 3-8. 가격 설정·directMentorBoard
- 단가 테이블 `mentor_individual_question_pricing(mentor_id, amount_cents, updated_at)`; RLS `miqp_select_authenticated`(비로그인은 빈 결과) — `lib/individualQuestion/individualQuestionPricing.ts:4-62`, `…070…:272`. 멘토 측 설정 UI 는 멘토 리더 범위.
- `loadDirectMentorBoard`: `loadPublicMentorsList(sort popular, fetchLimit 60, pageSize 36)` + 단가 배치; 카드 필드 `mentorId, name, photoUrl, verified, schoolLine, badgeLabel, chips(≤4), majorCodes(과목 대분류 라벨 부분일치), searchBlob, avgRating, reviewCount, iqPriceCents`; `pricesVisible`(로그인 학생만) — `lib/individualQuestion/directMentorBoard.ts:19-118`.

### 3-9. 학생/멘토 화면별 액션(`IndividualQuestionViews.tsx`)
학생: 메시지·첨부 전송(종결 전), `status==='answered'` 일 때 [해결 완료] — `components/individualQuestion/IndividualQuestionViews.tsx:285-295,560,627`. 멘토: assigned/claimed 에서 [답변 확정] — `:287,595`. 이름 표시: 학생 세션은 `users`(RLS 본인만)+디렉터리 nickname 으로 멘토명 해석, 상대 학생명은 멘토 세션에서 `get_mentor_student_nicknames` — `lib/individualQuestion/individualQuestionQueries.ts:119-190`.

## §4 멘토찾기 상세

### 4-1. 디렉터리 뷰·목록 쿼리·필터·정렬·페이징
- 뷰 `api_web_v1.mentor_directory_v1` 필드: `mentor_id, nickname, university_name, department_name, teaching_subjects(text[]), intro_line, profile_image_url, high_school_name, school_verified, school_tier, verified_major_category, verified_university_name, verified_department_name, is_open_for_subscriptions, avg_rating, review_count, created_at`; 조건 `users.role='mentor' AND status active AND mentor_profiles.verification_status ∈ (approved, verified, active)`; 학교 필드는 `mentor_school_verifications.status='approved'` LATERAL; 리뷰 집계 hidden/blinded 제외 — `supabase/sql/20260730095441_api_web_v1_read_views.sql:171-219`. TS 어댑터 `PublicMentorProfileRow` — `lib/auth/mentorPublicRead.ts:20-99`.
- 목록 `loadPublicMentorsList(supabase, filters, opts)`: 디렉터리 전량 range 순회(1000 배치, 상한 10000) → 프로필 청크 500 → `public.reviews(mentor_id, rating) where is_hidden=false and is_blinded=false` 청크 200 집계 → `public.mentor_plans` 청크 200(`assignPlansByTier` by `plan_tier`) → 카드 게이트(승인 + `teaching_subjects` 1개 이상) → 인메모리 필터·정렬 → 페이지 12 → 현재 페이지만 cap RPC(service_role) — `lib/mentor/publicMentorsListQueries.ts:65-116,198-299,504-660`.
- 필터(`MentorsListFilters`): `q`(이름·소개·과목·학교·학과·계열·학년 블롭 부분일치), `subject`(대분류 라벨; 대분류+소분류 라벨 어느 하나가 `teaching_subjects` 텍스트에 포함), `school`(학교등급 ∈ 서연고/서성한/중경외시/건동홍/미분류 — `그외` 는 필터 미노출·`미분류` 로 종속; `schoolVerified` 필수), `university`(학교등급 미지정 시 인증 대학명 부분일치), `verifiedOnly`/`verification`, `grades`(중등/고등/N수 정규식), `mentorTypes`(`verified_major_category` ∈ 메디컬/교육/인문/사회상경/자연/공학/예체능/기타, 인증 필수), `priceBand`(3to5 3만~5만 미만 / 5to10 / 10to20 / over20 — 세 플랜 캐시 중 하나라도 밴드 안), `sort`, `view(list|grid)`, `scope(all|recent|favorite)`, `page` — `lib/mentor/mentorsListSearchParams.ts:11-233`, 매칭 `publicMentorsListQueries.ts:329-413`.
- 정렬: `popular`(기본) = 학교인증 그룹 랭크(서연고&메디컬 0 → 메디컬 1 → 서연고 2 → 기타 인증 3 → 미인증 4) → 한줄소개 직접 작성 우선 → bio 길이 내림차순 → `reviewCount*10 + avgRating`; `review`, `rating`, `price_asc/desc`(`minPriceKrw`), `new`(created_at) — `:421-473`. `sort=response` 는 폐기(기본 폴백) — `mentorsListSearchParams.ts:9-10`.
- 가격 라벨: `mentor_plans.amount_cents`(또는 price/amount 캐시) → 없으면 권장가 — `lib/subscribe/mentorPlanPricing.ts:62-80`; 카드 `tierPrices[3]`, `minPriceKrw`, `priceLabel`(스탠다드 우선) — `publicMentorsListQueries.ts:286-327`.
- 학교분류 카탈로그: `school_tier_catalog`, `major_category_catalog`(code,label,display_order,is_active; 실패 시 상수 폴백) — `lib/mentor/schoolClassificationCatalog.ts:70-125`, 상수 `lib/mentor/schoolVerificationConstants.ts:1-18`.

### 4-2. 상세 페이지 번들
- `loadPublicMentorBundle`: 디렉터리 유저행 → `not_found`/`not_mentor`; 프로필(디렉터리) + `fetchReviewsSummary` → `public.get_mentor_review_stats(p_mentor_id, p_include_hidden=false)` → `{review_count, avg_rating(, d1..d5)}` + `fetchPlansForMentor`(`mentor_plans` by mentor_id ≤12) — `lib/mentor/publicMentorBundle.ts:50-150`.
- 페이지 추가 로드: `checkReviewEligibility`(학생), `favorites`(로그인), `loadFreeQuestionRemainingForMentor`(학생), `loadMentorCapUsage`(service_role → `subscriptionClosed=isFull`), `get_mentor_avg_response_hours(p_mentor_id)` → 버킷 `≤12h "12시간 이내" / ≤24 / ≤48 / >48 "48시간 이상"`, `mentor_individual_question_pricing` — `app/(public)/mentors/[mentorId]/page.tsx:30-101`, `lib/mentor/avgResponseHoursDisplay.ts:4-40`.
- CTA: 구독(`/subscribe?mentorId=`; `subscriptionClosed` 면 "구독 마감"), 무료 질문권(`/question-room?mentorId=`; 라벨 `[잔여 n]`), 개별 질문(단가 있을 때만 `/mentors/{id}/individual-question/new`) — `components/mentor/MentorDetailCTASection.tsx:13-68`. `is_open_for_subscriptions`(멘토 self 토글, F7 `mentor_profile_update_self`)를 학생 CTA 가 반영하는지 **(확인 필요 — 페이지 props 에는 cap 기반 `subscriptionClosed` 만 전달)** — `lib/mentor/mentorSubscribeOpen.ts:8-13`.
- 미승인 멘토: 관리자/본인 외 "표시 불가" — `app/(public)/mentors/[mentorId]/page.tsx:71-78`.

### 4-3. 찜
테이블 `public.favorites(user_id, mentor_id)`; RLS own 3종; API route 는 세션 클라이언트만(service_role 없음); 중복은 성공 처리 — `lib/mentor/mentorFavorites.ts:27-40`. 클라이언트 `MentorFavoriteButton`/`MentorDetailHeaderActions` 가 `/api/mentors/favorites` fetch — `components/mentor/MentorFavoriteButton.tsx:38-47`.

### 4-4. 최근 본 멘토
`localStorage["ssambership_recent_mentors"] = [{mentorId, viewedAt}]` 최대 20, 상세 진입 시 `MentorRecentRecorder` 가 기록 — `lib/mentor/recentMentorsStorage.ts:1-42`, `components/mentor/MentorRecentRecorder.tsx:6-11`. `scope=recent` 는 `RecentMentorsScope` 가 id 를 `POST /api/mentors/scoped` 로 보내 카드 조회(URL 노출 없음) — `components/mentor/RecentMentorsScope.tsx:12-41`.

### 4-5. 리뷰
- 목록 `listMentorReviews(mentorId, {page, limit≤50})`: `reviews` by mentor_id, 공개 predicate `moderation_state='visible' AND is_hidden=false AND is_blinded=false`, `created_at desc`, range; 작성자 `users(id, full_name, nickname, grade_level)`(RLS 로 타 학생 행은 0 → 마스킹 폴백 "학*"), 과목 = 디렉터리 `teaching_subjects[0]`, 통계 = `get_mentor_review_stats` — `lib/reviews/reviewQueries.ts:36-175`. 카드 `{id, rating, content, createdAt, studentInitial, studentMaskedName(이*연), gradeSubject, mentorReply, mentorRepliedAt}` — `:9-19`, `lib/reviews/reviewDisplay.ts:2-14`.
- 자격: DB 정본 `public.check_review_eligibility(p_mentor_id uuid, p_student_id uuid) returns boolean` — (B) `subscriptions.status ∈ {active, expired, cancel_scheduled}` OR (C) `individual_questions.status ∈ {answered, released}` with `coalesce(claimed_mentor_id, designated_mentor_id)=mentor`; INSERT 정책 `reviews_insert_student` 가 `check_review_eligibility(mentor_id, auth.uid())` 호출(인자 순서 고정) — `supabase/sql/170_review_eligibility_relationship_based.sql:1-88`, `supabase/sql/126_reviews_rls_hardening.sql:53-55`. TS 미러 `ELIGIBLE_SUBSCRIPTION_STATUSES`, `ELIGIBLE_INDIVIDUAL_QUESTION_STATUSES`, 판정 순서(본인 후기 있으면 관계 재검사 없이 `edit`; 숨김/블라인드면 `canEdit:false`) — `lib/reviews/reviewEligibilityPolicy.ts:19-160`, `lib/reviews/checkReviewEligibility.ts:113-149`. **CLAUDE.md 의 "동일 멘토 2회 연속 결제 성공 후"는 구 기준(066)이며 170 으로 대체됨.**
- 작성 `createReview`: 자격 → `mode==='edit'` 면 거부 → rating 1~5 정수 → 본문 20~500자 → 연락처 마스킹 → INSERT `reviews(mentor_id, author_id, rating, body)`; unique `uq_reviews_mentor_author` → "이미 리뷰를 작성했습니다" — `lib/reviews/reviewQueries.ts:177-227`. 수정 `updateReview`: 작성자·비모더레이션·동일 길이 규칙·RETURNING 1행 판정(RLS `reviews_update_author` 171/173) — `:238-282`, `lib/reviews/reviewUpdateResult.ts:33-69`. 삭제 API 없음(학생 삭제 경로 없음).
- 클라이언트 `ReviewWriteModal`: 자격 fetch → edit 면 `/api/reviews/[id]` prefill → POST/PATCH → `window.dispatchEvent("reviews-updated")` — `components/reviews/ReviewWriteModal.tsx:57-151`. 목록 `MentorReviewList` limit 5 페이징 — `components/mentor/MentorReviewList.tsx:50-75`.

## §5 구독 조회·해지

### 5-1. 표시 상태 enum·라벨
- DB CHECK 7종: `pending, active, past_due, cancel_scheduled, canceled, expired, refunded` — `supabase/sql/170_review_eligibility_relationship_based.sql:27-28`.
- 톤 `subscriptionStatusTone(status, cancelAtPeriodEnd)`: `cancel_scheduled` 또는 (`cancel_at_period_end` && active/past_due) → `scheduled`; `active`; `past_due→pastDue`; `expired/canceled/cancelled→expired`; `refunded`; 기타 `neutral`. 라벨: `이용 중 / 구독 만료 예정 · {기간말}까지 이용 / 결제 실패 · {grace_until}까지 충전 필요 / 만료됨 · 재구독 가능 / 해지됨 / 환불됨`; 다음 결제 라벨은 `SUBSCRIPTION_RENEWAL_ENABLED` env 로 문구 분기 — `lib/subscribe/subscriptionDisplay.ts:3-98`.
- 컬럼 정본 `SUBSCRIPTIONS_SELECT` = `id, student_id, mentor_id, payment_id, plan_tier, plan_id, status, created_at, updated_at, started_at, current_period_start, current_period_end, next_billing_at, billing_cycle, cancel_at_period_end, cancel_requested_at, canceled_at, expired_at, last_renewed_at, last_billing_event_id, last_payment_id, grace_until` — `lib/subscribe/subscriptionsTable.ts:5-38`. 기간 산술 KST 월말 clamp `addMonthsClampedKst` — `:62-95`.

### 5-2. 학생 구독 관리 목록(`/subscriptions`)
`loadStudentSubscriptionManagementList`: `subscriptions`(student_id, created_at desc) + `subscription_billing_events`(status succeeded, event_type initial/renewal 최신) + `refunds`(user_id, status pending) + 멘토별 `mentor_plans` + 디렉터리 + `bulkHasSubscriptionUsageStarted`(방의 `question_threads.created_at >= current_period_start` 1건 이상) → 항목 `canCancel = (active|past_due) && !cancel_at_period_end`, `canUndoCancel`, `canRequestRefund = 현재기간 && 추정액>0 && pending 없음`, `nextBillingAmountCents`(플랜 행 → 권장가 폴백), `refundEstimate`, `resubscribeHref=/subscribe?mentorId=&plan=` — `lib/subscribe/studentSubscriptionManagement.ts:178-310`, `lib/subscribe/subscriptionUsageStarted.ts:12-79`.

### 5-3. 해지 예약/취소 판정 — **상태 변경(결제 실행 아님)**
- `requestSubscriptionCancelAtPeriodEndAction(subscriptionId)`: `requireRole(student)` → **service_role** 로 본인 구독 로드 → status ∈ {active, past_due} → `UPDATE subscriptions SET cancel_at_period_end=true, cancel_requested_at=now(), updated_at` (status 불변) → `/subscriptions?ok=`. `undo…`: `cancel_at_period_end=false, cancel_requested_at=null` — `lib/subscribe/subscriptionCancelActions.ts:93-166`. 캐시·결제·환불 이동 없음.
- 환불 신청 `requestSubscriptionProratedRefundAction(subscriptionId, reason≥5자)`: service_role 로 pending 중복 검사 → 최신 billing event → 이용개시 판정 → 추정액 ≤0 이면 거부(`ge_1_2` 문구) → `refunds INSERT(status pending, request_type subscription_prorated, amount_cents, payment_id, billing_event_id)` → `/support/refunds` — `:168-260`. 신청은 상태 행 생성이며 실제 환불(캐시 이동)은 관리자 승인 후(다른 리더 범위).
- RLS: `subscriptions` 쓰기는 028 로 잠금(`028_p0_lock_subscriptions_writes.sql`) → 세션 클라이언트 UPDATE 불가 **(확인 필요: 028 의 update 정책 존재 여부)**.

### 5-4. 환불 비례 계산(표시 + 서버 동일 함수)
`computeProratedRefundEstimate({amountCents, periodStartIso, periodEndIso, usageStarted, mode})`: `student_voluntary` — 이용개시 전 전액(`before_usage`) / 경과율 <1/3 → 2/3(`lt_1_3`) / <1/2 → 1/2(`lt_1_2`) / ≥1/2 → 0(`ge_1_2`); `mentor_suspended` — 잔여 비율 × 결제액(`mentor_remaining`); 입력 부족 `invalid` — `lib/subscribe/subscriptionRefundProration.ts:16-138`. 라벨 `refundBracketLabelKo` — `:158-175`. 목록 카드는 표시용, 신청 액션은 서버에서 재계산.

### 5-5. cap
정본 DB RPC `mentor_cap_used / mentor_cap_limit / subscription_cap_weight`(가중치 라이트 1.0·스탠다드 2.25·프리미엄 4.75, 한도 50 — SQL 190); TS 는 계산하지 않고 **service_role 클라이언트**로 호출(`loadMentorCapUsageBatch`, 서비스키 부재 시 indeterminate fail-closed) — `lib/subscribe/mentorCapService.ts:15-50`. 주석상 cap RPC 셋은 anon/authenticated 도 실행 가능(`:20`) **(확인 필요: 050/190 grant)**. 사용처: 목록 카드 `subscriptionClosed`, 상세 CTA, `/subscribe` 의 `wouldExceedCap(capUsage, tier)` → `closedTiers`.

### 5-6. 마이페이지 활성 구독(V6)
`api_web_v1.my_subscriptions_self() returns table(subscription_id, mentor_id, mentor_label, plan_id, plan_tier, current_plan_amount_cents, status, started_at, current_period_start, current_period_end, next_billing_at, cancel_at_period_end, grace_until, created_at)` — `auth.uid() IN (student_id, mentor_id)`, 미로그인 42501 — `supabase/sql/20260730105248_api_web_v1_self_rpc.sql:205-252`. 웹은 `status='active'` 만 카드화, 주간 한도 라벨은 플랜 정적(`주 4개/9개/무제한 (플랜 기준)`), 리셋 라벨은 `started_at` 앵커 7일 — `lib/mypage/studentActiveSubscriptions.ts:98-103,181-250`.

## §6 마이페이지·홈·노트

- `/mypage` 집계(`loadStudentMypageBundle`): 질문방 수 = `mentor_student_rooms.student_id` 행 수; `subscriptions.student_id`, `payments.user_id`, `notifications.user_id`, `reviews.author_id`, `content_reports.reporter_id` 각 `count exact head`(오류는 `—`/skeleton) — `lib/mypage/mypageQueries.ts:30-110`. 활성 구독 수 `countActiveSubscriptionsForStudent`(V6 active 필터) — `lib/mypage/studentActiveSubscriptions.ts:252-263`. 개별질문 수 `individual_questions.student_id` — `app/(student)/mypage/page.tsx:52-56`. 표시명 `full_name → nickname → email`, 학교줄 `grade_level · student_status` — `:59-62`.
- 캐시: `api_web_v1.my_wallet_v1(user_id, balance_cents, balance_krw)` invoker 뷰(`user_id=auth.uid()` RLS) — `supabase/sql/20260730095441_api_web_v1_read_views.sql:228-236`, `lib/cash/cashQueries.ts:24-37`; 원장 `api_web_v1.my_cash_ledger_v1(id, delta_cents, reason, ref_type, ref_id, order_ref, created_at)` — `:242-255`, `lib/cash/cashQueries.ts:46-102`(기간 필터 `+09:00` 경계, 1000 배치, 상한 3000, `truncated` 플래그). 잔액 파싱 `parseWalletBalanceKrw` **(파일 미열람 — 확인 필요)**.
- 홈: `/home` 은 redirect. `lib/home/threadStats.ts`(`aggregateThreadStatsForRooms(roomIds, {maxRooms, mode})` — 방별 `question_threads` 조회 후 open/mentor-queue 휴리스틱)는 현재 멘토 대시보드(`lib/home/mentorDashboardQueries.ts:6,25`)만 사용 — 학생 홈 소비처 없음.
- 노트: `/notes` redirect; 실기능은 §2-7.

## §7 앱이 그대로 못 쓰는 것 (service_role 전용 server action / 웹 API route 로만 구현) 과 대체안

| # | 웹 기능 | 웹 구현(막히는 이유) | 앱 대체에 필요한 것 | 근거 |
|---|---|---|---|---|
| 1 | 개별질문 생성(direct/open, 캐시 hold) | service_role `create_individual_question_with_hold_v2`(service_role 전용 grant) + `requireVerifiedIdentity` + 첨부 service_role 업로드 | 오너 방침상 결제 실행이라 **앱 제외 후보**. 넣는다면 기존 `create_individual_question_as_student`(authenticated)는 `subject/topic/required_school_tier/required_major_category` 인자가 없어 시그니처 확장 SECDEF RPC 신설 + 본인인증 게이트를 RPC 안에서 강제 필요 | `lib/individualQuestion/individualQuestionActions.ts:121-301`, `…080…:269-273`, `…092…:62-69` |
| 2 | 개별질문 메시지·첨부 | service_role INSERT | DB 에 이미 `iq_append_message`, `add_individual_question_attachment`(authenticated) 존재 — 앱 사용 중. 단 웹의 "명시 답변확정" 의미와 RPC 의 "첫 메시지=answered" 가 상이(§3-4) → 정합 결정 필요 | `…20260803142534_iq_append_message_v1.sql`, `…168…:170-178` |
| 3 | 개별질문 해결완료(정산) | service_role `release_individual_question_payout` | `release_individual_question(p_question_id)`(authenticated·학생 본인) 존재. 자금 이동이므로 포함 여부는 오너 결정 | `…091…:34-78` |
| 4 | 개별질문 `expires_at` 설정 | 생성/claim 후 service_role UPDATE | 앱 wrapper 가 미설정 시 NULL → 만료 배치 폴백(`created_at + 기본시간`)으로 처리됨. 명시하려면 wrapper 수정 **(확인 필요)** | `individualQuestionActions.ts:97-115`, `…ExpiryScan.ts:13-34` |
| 5 | 구독 해지 예약/취소 | service_role `UPDATE subscriptions.cancel_at_period_end`(테이블 쓰기 RLS 잠금) | **새 SECDEF RPC**(예: `api_app_v1.subscription_cancel_at_period_end_self(p_subscription_id)` / `…undo_self`) — 판정식(본인·active/past_due) 은 `subscriptionCancelActions.ts` 를 그대로 옮기면 됨 | `lib/subscribe/subscriptionCancelActions.ts:93-166` |
| 6 | 구독 환불 신청 | service_role `refunds INSERT` + 추정액 서버 계산 | 새 SECDEF RPC(`refunds` 삽입 + 별표4 계산을 SQL 로 이식) — support 리더와 공유 | `:168-260`, `subscriptionRefundProration.ts` |
| 7 | 무통장 pending 원장 섹션 | `PaysyncPendingLedgerSection` service_role | 결제 리더 범위(제외 가능) | `app/(student)/wallet/ledger/page.tsx:56` |
| 8 | cap 마감 배지 | `loadMentorCapUsageBatch` service_role 클라이언트 | cap RPC 3종을 앱 세션에서 직접 호출(grant 확인 필요) 또는 디렉터리 뷰에 `is_full` 컬럼 추가 | `lib/subscribe/mentorCapService.ts:15-44` |
| 9 | 무료 스레드 판정(멘토 세션) | `free_question_usage` service_role 읽기 | 학생 앱은 `fqu_select_own` 으로 본인 행 직접 읽기 가능. 멘토 앱은 SECDEF 조회 RPC 또는 `question_threads` 에 `is_free` 파생 컬럼 필요 | `lib/qna/freeQuestionUsage.ts:200-221` |
| 10 | 메시지 전송 시 구독 만료 차단 | server action 사전 게이트(`assertThreadCreationSubscriptionAllowed(isNewThread:false)`); RPC `qna_append_message` 는 구독 상태를 보지 않음 | 앱이 RPC 직접 호출하면 만료 구독 스레드에도 메시지 가능 → 정책 유지하려면 RPC 에 게이트 추가(또는 `SUBSCRIPTION_REFUND_PENDING` 처럼 트리거) **필요 여부 오너 결정** | `lib/qna/questionRoomActions.ts:281-294`, `…136…:215-236` |
| 11 | 연결노트 쓰기 구독 가드 | 앱 계층 `assertConnectionNoteWriteAllowed`; RLS 는 방 당사자+작성자만 | 앱 직접 INSERT 는 가드 우회 → SECDEF RPC(`connection_note_upsert_self`) 또는 트리거로 이관 | `lib/qna/connectionNoteSubscriptionGuard.ts:30-82`, `…085…:27-80` |
| 12 | 스레드 자동 제목 "질문 N" | API route 의 TS 로직(방 스레드 수+1) | 앱이 동일 규칙 미러링(또는 RPC 에서 빈 제목 허용하도록 변경 — 현재 `TITLE_REQUIRED`) | `lib/qna/questionRoomThreadService.ts:50-55`, `…136…:93` |
| 13 | 리뷰 작성/수정 검증 | API route TS(20~500자, rating 1~5, 중복→edit 유도, 연락처 마스킹, 모더레이션 차단) | RLS 는 자격·unique 만 강제. 앱은 규칙 미러링 또는 `review_create_self/update_self` SECDEF RPC | `lib/reviews/reviewQueries.ts:177-282` |
| 14 | 최근 본 멘토 카드 | `/api/mentors/scoped`(서버 인메모리 필터) | 앱은 로컬 저장 id → `mentor_directory_v1 .in(mentor_id)` + 순서 정렬로 대체 | `lib/mentor/scopedMentorsList.ts:36-76` |
| 15 | 멘토 목록 필터·정렬·페이징 | 전량 인메모리(서버) | 앱은 동일 알고리즘 미러링(§4-1) 또는 DB 측 정렬 RPC/뷰 신설(대량 시 성능) | `publicMentorsListQueries.ts:329-473` |
| 16 | 연락처 마스킹 | `maskContactInUserText`(TS) 를 IQ 본문·리뷰에 저장 전 적용 | 앱 미러링 또는 RPC 내부로 이관 **(질문방 메시지는 RPC 에 마스킹 없음 — 확인 필요)** | `individualQuestionActions.ts:167-168`, `reviewQueries.ts:206` |
| 17 | 앱→웹 세션 브리지 | `/api/app-session/bootstrap` 은 멘토 숏폼 작성 WebView 단일 target 전용 | 학생 채널용 웹 API 재사용 경로는 없음 → 앱은 Supabase 직접(RLS/RPC) 원칙 | `app/api/app-session/bootstrap/route.ts:19-33,114-119` |

앱 현황 참고: 앱은 `api_web_v1` 뷰(`mentor_directory_v1`, `my_wallet_v1`, `my_cash_ledger_v1`, `community_posts_v1`)를 `.schema('api_web_v1')` 로 13곳에서 직접 읽고 있고, `api_app_v1` 은 `ensure_free_question_room`·`qna_create_question_thread`·커뮤니티 3종 wrapper 만 노출(schema USAGE authenticated 만) — `app:lib` grep, `supabase/migrations/20260731114120_20260730112525_api_app_v1_surface.sql:4-24,254-261`. 앱은 Realtime `postgres_changes` 를 `question_messages/question_threads/question_attachments`, `individual_question_messages/individual_question_attachments/individual_questions` 에 사용 — `app:lib/features/question_room/data/thread_realtime.dart:44-83`, `app:lib/features/individual_question/data/iq_realtime.dart:54-91`(publication·RLS 적용 여부 **확인 필요**).

## §8 앱이 미러링해야 할 정본 상수·정책 파일

| 항목 | 값 | 정본 파일 |
|---|---|---|
| 과목 카탈로그 | 대분류 `korean, english, math, korean_history, social, science, essay, career, etc` + 소분류 code/label(국어 4·수학 5·사회 9·과학 8); 레거시 라벨 매핑(`사회·역사→social`, `미적분→math` 등); DB `public.subjects` 와 1:1 | `lib/subjects/subjectCatalog.ts:12-134`, `supabase/sql/060_ai_readiness_question_schema.sql:8-33` |
| 주간 한도 | limited 4 / standard 9 / premium 999(=무제한 표기) / 기타 0; 앵커 `coalesce(started_at, created_at)` 7일 롤링; 카운트 `question_threads.created_at >= week_start` | SQL 098:67-96, TS 표시 `weeklyQuestionUsageDisplay.ts:27-40`, 카탈로그 `weeklyLabel` |
| 무료질문 정책 | 전역 7회 · 멘토당 3회 · 가입 후 7일; 문구 `FREE_QUESTION_POLICY_SHORT` | `lib/mentor/freeQuestionPolicy.ts:2-8`, SQL 052, 136:136-145 |
| 스레드 상태 | `pending/answered/confirmed`(+`open/closed/archived` 레거시), 잠금 규칙, 라벨·톤 | `lib/qna/questionThreadStatus.ts`, `lib/qna/questionRoomUiLabels.ts:40-105` |
| 한도 초과 문구 | `WEEKLY_QUESTION_LIMIT_MESSAGE = "이번 주 질문 한도를 모두 사용했습니다"` | `lib/qna/questionThreadStatus.ts:37` |
| QnA RPC 오류코드 사전 | §2-2 목록 + F2 12종 + F3 수렴표 | `lib/qna/questionRoomRpc.ts:30-83`, `lib/qna/freeQuestionRoom.ts:14-41`, `…20260730105248…:148-176` |
| 요금제 카탈로그 | tier `limited/standard/premium` = 라이트/스탠다드/프리미엄, 표시가 29,900/84,900/174,900, `weeklyLabel` 주 4개/주 9개/무제한, 추천 standard | `lib/subscribe/subscribePlanCatalog.ts:14-37` |
| 멘토 가격 밴드 | min/권장/max: 29,900/29,900/69,900 · 84,900/84,900/149,900 · 174,900/174,900/329,900; `amount_cents = cash×100`; 실차감 우선순위 `amount_cents → price_cents → monthly_price_cents → amount/price/monthly_price/price_krw(캐시) → 권장가` | `lib/subscribe/mentorPlanPricing.ts:13-85` |
| 가격 밴드 필터 | `3to5 [30,000, 50,000)`, `5to10 [50,000, 100,000)`, `10to20 [100,000, 200,000)`, `over20 ≥200,000` | `lib/mentor/mentorsListSearchParams.ts:90-100`, `publicMentorsListQueries.ts:396-411` |
| 학교등급·계열 | `SCHOOL_TIERS = 서연고, 서성한, 중경외시, 건동홍, 그외, 미분류`(공개 필터는 `그외` 제외·`그외→미분류` 표시), `VERIFIED_MAJOR_CATEGORIES = 메디컬, 교육, 인문, 사회상경, 자연, 공학, 예체능, 기타`; 런타임 라벨은 `school_tier_catalog/major_category_catalog` | `lib/mentor/schoolVerificationConstants.ts:1-18`, `lib/mentor/mentorDisplayFields.ts:65-68` |
| 인기순 정렬 규칙 | 그룹 랭크 → 한줄소개 작성 → bio 길이 → `reviewCount*10+avgRating` | `publicMentorsListQueries.ts:421-456` |
| 멘토 노출 게이트 | 디렉터리 뷰 조건 + `teaching_subjects` ≥1 | `publicMentorsListQueries.ts:578-588` |
| 평균 응답시간 버킷 | ≤12h / ≤24h / ≤48h / >48h | `lib/mentor/avgResponseHoursDisplay.ts:4-12` |
| 리뷰 자격·검증 | 구독 `{active, expired, cancel_scheduled}` OR IQ `{answered, released}`; 본문 20~500자; rating 1~5; 1인 1후기(unique); 모더레이션 시 수정 불가; 이름 마스킹 `이*연` | `lib/reviews/reviewEligibilityPolicy.ts:19-31`, `reviewQueries.ts:192-203`, `reviewDisplay.ts:2-7` |
| 구독 상태·라벨 | 7종 enum, 톤/라벨 규칙, 환불 별표4 분기 | `lib/subscribe/subscriptionDisplay.ts`, `subscriptionRefundProration.ts` |
| 개별질문 상태·라벨·만료 | 9종 enum, 라벨, 만료 임박 12h, 기본 만료 open 48h / direct(assigned) 72h / claimed 48h, jpg/png/pdf·20MB | `individualQuestionTypes.ts`, `individualQuestionFormat.ts`, `individualQuestionExpiryConfig.ts:3-5`, `individualQuestionAttachmentStorage.ts:15,50-56` |
| 질문방 첨부 | MIME 8종·20MB·경로 규약·서명 1h·HEIC 강등·첨부 라벨 `📷 사진 / 📎 {파일명}` | `questionRoomAttachmentStorage.ts:5-26`, `questionRoomAttachmentsQueries.ts:13-34`, `questionRoomAttachmentView.ts:34-36` |
| cap | 가중치 1.0/2.25/4.75 · 한도 50 — **TS 사본 금지, DB RPC 호출만** | CLAUDE.md, SQL 190 |
| 캐시 단위 | 1캐시=1원, `balance_cents/100` | `my_wallet_v1`, `formatCashFromCents` |
| 학생 표시 폴백 | `ANON_STUDENT_LABEL = "이름 미설정"`, 표시 실패 `"표시 실패"` | `lib/qna/studentDisplayNames.ts:19`, `individualQuestionQueries.ts:12` |

## 부록 — 문서/코드 불일치·확인 필요 목록
1. CLAUDE.md "리뷰: 동일 멘토 2회 연속 결제 성공 후" ↔ 코드/SQL 170 은 관계 기반(구독 active/expired/cancel_scheduled 또는 IQ answered/released).
2. SQL 044 주석 "학생당 15회" ↔ 052·136·TS 는 전역 7회.
3. 멘토 `is_open_for_subscriptions` 가 학생 상세 CTA/구독 페이지에서 실제로 차단에 쓰이는지 (확인 필요 — 열람한 페이지 코드는 cap 기반 `subscriptionClosed` 만 전달).
4. `assertThreadCreationSubscriptionAllowed(isNewThread:true)` 의 현재 호출자 존재 여부(스레드 생성은 RPC 정본) (확인 필요).
5. `mentor_cap_used/mentor_cap_limit` 의 anon/authenticated grant, `get_mentor_review_stats`·`get_mentor_avg_response_hours` grant (확인 필요).
6. 구독 확정 시 F10 호출·transfer 호출 지점(`lib/subscribe/subscribeCheckoutService.ts` 미열람) (확인 필요).
7. 028 `subscriptions` 쓰기 잠금 정책의 정확한 범위(update 정책 유무) (확인 필요).
8. 앱 Realtime 대상 테이블의 publication 포함·RLS 적용 여부 (확인 필요).
