# Phase 2 설계 — 학생 채널 정합(parity): 질문방 · 개별질문 · 멘토찾기 · 구독 조회 · 리뷰 · 마이페이지

> 대상: 웹 `/home/user/ssambership_web` ↔ 앱 `/home/user/ssambership-app`(같은 Supabase). 기준일 2026-09-03.
> 작성 방식: 이 문서는 1단계 리포트(`phase1/web_student_channels.md`, `phase1/app_features.md`, `phase1/web_db_surface_payment_boundary.md`, `phase1/app_architecture.md`)에 기록된 코드·SQL 근거를 통합해 작성했다(설계 에이전트 반복 타임아웃으로 종합 단계에서 직접 작성). 근거 표기는 1단계 리포트의 파일:행을 그대로 옮겼고, 1단계에서 확인하지 못한 항목은 **(확인 필요)** 로 남겼다.
> 성격: 설계 문서(저장소 무수정). UI 디자인 불포함.

---

## 1. 범위·전제

### 1.1 담당 범위
기존 앱에 이미 있는 학생 채널(질문방·개별질문·멘토찾기·마이페이지)을 웹 수준으로 끌어올리는 갭. 신규 도메인(맞춤의뢰·멘토 콘솔·계정)은 별도 문서.

### 1.2 결제 경계 판정(정본 `docs/policy/app-web-payment-separation.md` · DB 리포트 §4)

| 기능 | DB 권한 | 판정 | 근거 |
|---|---|---|---|
| 개별질문 생성(캐시 hold) | 웹 코어 `create_individual_question_with_hold_v2` s만; 앱용 `create_individual_question_as_student` u(자격조건·subject·topic 인자 없음) | **현행 웹 위임 유지**(앱 `kIndividualQuestionCreateEnabled` 기본 off, on 이어도 웹 페이지) | DB §4 #9; `app:lib/features/individual_question/iq_flags.dart:10-19`; `supabase/sql/092:1-153` |
| 개별질문 release(학생 해결완료 → 멘토 85%) | `release_individual_question(uuid)` u | **허용 유지**(에스크로 확정, 새 결제 아님 — 앱 이미 호출) | DB §4 #11; `091:34-78` |
| 개별질문 refund(학생 취소) | `refund_individual_question(uuid)` u | **허용** | DB §4 #12; `091:95-129` |
| 구독 해지 예약 / 예약 취소 | 웹 service_role UPDATE(전용 RPC 없음, 028 잠금) | **[모호] 조건부 포함** — 해지 예약은 결제 중단 행위. 예약 취소(재개)는 웹 위임 권고 | DB §4 #5; `lib/subscribe/subscriptionCancelActions.ts:93-166` |
| 구독 잔여 환불 신청 | `refunds` INSERT admin만 | **[모호] 오너 결정** — 커뮤니티/지원 도메인 결정 C 와 동일 객체(`refund_request_subscription_self`) | DB §4 #7 |
| 재구독(`/subscribe?mentorId=`) | 결제 실행 | **제외** | 정책 §3 |
| 가격 표시(플랜·IQ 단가)·가격대 필터 | `mentor_plans`·`mentor_individual_question_pricing` SELECT | **비표시 유지 권고** — 가격대 필터(priceBand)는 가격 표시가 전제라 앱에서 제외 권고(오너 결정) | DB §4 #22; `PLAY_STORE_REVIEW_PLAN.md` 재기준화 `5002c1d` |
| 캐시 잔액·원장·구독 상태·정산 읽기 | u | **허용**(앱 이미 사용) | DB §4 #4·#23 |

### 1.3 전제(사실)
- 질문방 쓰기 정본은 `public.qna_create_question_thread / qna_append_message / qna_confirm_thread / qna_flag_wrong_answer / qna_register_attachment`(SECDEF, authenticated·service_role) — `supabase/sql/136:381-394`. 앱은 이 중 **오답 표시를 제외한 4종** + `api_app_v1.qna_create_question_thread`·`ensure_free_question_room` 을 사용 중(앱 매니페스트).
- `qna_append_message` 는 **구독 만료·무료 스레드 여부를 검사하지 않는다**(웹은 server action `assertThreadCreationSubscriptionAllowed` 로만 차단) — `136:194-265`, `lib/qna/questionThreadSubscriptionGuard.ts:8-86`. 앱 직접 호출 시 정책 공백.
- 연결노트는 웹이 **매 저장 append INSERT**(upsert 아님, `rows[0]` 표시), 수정·삭제는 작성자 RLS(`cn_update/cn_delete`), 구독 가드는 웹 앱 계층 전용 — `lib/qna/questionRoomMutations.ts:42-69`, `085:27-80`, `lib/qna/connectionNoteSubscriptionGuard.ts:25-82`. 앱은 upsert 의미(`upsertMyNote`)로 구현.
- 주간 한도 정본 `get_weekly_question_usage`(limited 4 / standard 9 / premium 999, `started_at` 앵커 7일 롤링) + self/batch RPC(authenticated) — `098:33-96`, `20260806041547`. 앱은 self·batch 사용, **마이페이지 잔여 표시는 null**, RPC 실패 클라 폴백 없음(`CANON_SYNC_TODO.md` 2-a·2-b).
- Realtime publication: `question_messages`·`question_threads`·`question_attachments` 포함(baseline `20260701000000:16492,18559,18562`), 알림 `20260803171053`. IQ 테이블(`individual_question_messages`·`individual_question_attachments`·`individual_questions`) 포함 여부 **(확인 필요)** — 앱은 폴백(재조회) 계약으로 동작.
- 리뷰 자격 정본은 SQL 170 `check_review_eligibility(p_mentor_id, p_student_id)`(구독 `active/expired/cancel_scheduled` OR IQ `answered/released`)이며 **INSERT 정책 `reviews_insert_student` 가 이를 호출** → DB 가 자격을 강제한다. 웹 `CLAUDE.md` "동일 멘토 2회 연속 결제 성공 후"는 구 기준(066). 길이·평점·마스킹·모더레이션 잠금 검증은 TS(API route)에만 있다 — `lib/reviews/reviewQueries.ts:177-282`.
- 멘토 디렉터리 정본 뷰 `api_web_v1.mentor_directory_v1`(anon 읽기); 웹 목록은 뷰 전량 순회 후 **인메모리** 필터·정렬·페이지 12 — `lib/mentor/publicMentorsListQueries.ts:65-116,329-473`. 앱도 전량 로드(100행×최대 50페이지) 후 로컬 검색.

---

## 2. 갭 매트릭스

| # | 웹 기능 | 웹 라우트 | 앱 현재 | 앱 목표 | 근거 |
|---|---|---|---|---|---|
| 1 | 질문 스레드 생성(과목·topic·첫 메시지) | `/question-room/[roomId]` | 있음 — `api_app_v1.qna_create_question_thread`; topic 입력 유무 (확인 필요 — FEATURE_AUDIT [A4] "topic 필드 없음") | **포함(보강)** — `p_topic` 전달 | `136:65-176`; `app:new_question_screen.dart` |
| 2 | 메시지·첨부·확인 | 동일 | 있음 | **포함(기존)** | 앱 매니페스트 |
| 3 | **오답 표시**(`is_wrong_answer`) | 동일 | 없음 | **포함** — `qna_flag_wrong_answer(p_thread_id, p_is_wrong)` u | `136:286-305`, `060:42-53` |
| 4 | 스레드 목록 탭(all/waiting/needReview/done)·안읽음=answered 수 | 동일 | 부분(상태 pill·카운트 — 탭 분류 규칙 정합 (확인 필요)) | **포함(정합)** — `questionRoomUiLabels.ts:48-105` 규칙을 순수 함수로 이식 | `lib/qna/questionRoomStudentContext.ts:150-169` |
| 5 | 주간 잔여 표시(질문 영역 + **마이페이지 구독 카드**) | `/question-room`, `/mypage` | 질문 영역만, 마이페이지 null | **포함** — `weekly_question_usage_self_batch(uuid[])`(≤50) 로 활성 구독별 잔여 | `20260806041547:7-37`; `app:subscription_summary.dart:57` |
| 6 | 주간 한도 RPC 실패 시 폴백 표시(`{used:0,limit:0,canAsk:false}` + error) | — | 없음(보수적 통과) | **포함** — 웹과 동일하게 fail-closed 표시(로컬 재계산 금지) | `lib/qna/weeklyQuestionUsage.ts:76-126` |
| 7 | 무료 질문권 잔여 표시·방 확보·소비 | 멘토 상세·질문방 | 있음(`ensure_free_question_room`, 잔여 계산) | **포함(기존)** | `app:free_question_entry.dart:82,170,198` |
| 8 | 무료 스레드 우선 답변 배지(멘토) | 멘토 질문방 | (확인 필요) | **포함(정합)** — `free_question_usage.thread_id` 링크는 멘토 세션 RLS 로 못 읽음 → 스레드 `path` 표시용 컬럼 또는 RPC 필요 **(서버 확인)** | `lib/qna/freeTrialPriority.ts:13-49` |
| 9 | 메시지 전송 시 구독 만료 게이트 | server action | 없음(RPC 가 미검사) | **포함(서버 선행 S-1)** | `questionThreadSubscriptionGuard.ts:8-86` |
| 10 | 연결노트 저장·수정·삭제 | 동일 | 있음(upsert 의미) | **포함(정합)** — 의미·구독 가드 §7 D-3 | `questionRoomMutations.ts:42-69` |
| 11 | 첨부 업로드·뷰어·주석·PDF | 동일 | 있음(웹보다 넓음) | **포함(기존)** | 앱 S15~S19 |
| 12 | 학생 표시명(멘토 화면) | 멘토 질문방 | 있음(`get_mentor_student_nicknames`) | **포함(기존)** | `140:14-43` |
| 13 | 개별질문 생성(direct/open, hold) | `/individual-questions/new`, `/mentors/[id]/individual-question/new` | 웹 페이지 링크(플래그 off) | **웹 위임 유지**(§1.2) | DB §4 #9 |
| 14 | **direct 멘토 보드**(디렉터리 + 단가 배치) | `/individual-questions/direct` | 없음 | **포함(읽기)** — `mentor_directory_v1` + `mentor_individual_question_pricing`(둘 다 매니페스트 등재); 가격 비표시 정책 하에서는 "단가 있음" 여부만 | `lib/individualQuestion/directMentorBoard.ts:19-118` |
| 15 | IQ 목록·상세·메시지·첨부·claim(멘토)·release·refund | `/individual-questions/**`, `/mentor/individual-questions/**` | 있음 | **포함(기존)** | 앱 매니페스트 |
| 16 | 멘토 **답변 확정** 의미 | 멘토 상세 | 앱: `iq_append_message` 첫 메시지 = answered 자동 전이 | **오너 결정(§7 D-5)** — 웹은 명시 UPDATE(answered_at), RPC 는 자동 전이. `answer_individual_question` u 존재 | `individualQuestionActions.ts:430-486`; `20260803142534:4-67`; DB §4 #10 |
| 17 | IQ → 구독방 이전 링크(`individual_question_transfers`) | 학생 상세 | 없음 | **포함** — `iqt_select_student` RLS 직접 SELECT → 스레드 딥링크 | `075:34`; `individualQuestionQueries.ts:310-322` |
| 18 | IQ `expires_at` 설정 | 생성 후 SR UPDATE | 앱 wrapper 미설정 가능 (확인 필요) | **포함(서버 확인)** — NULL 이어도 배치 폴백 만료 | `ExpiryScan.ts:7-64` |
| 19 | 멘토찾기 필터 8종(q·과목 대/소분류·학교등급·대학·인증전용·학년·계열·가격대) | `/mentors` | 부분(과목·검색·정렬 일부) | **포함(가격대 제외 권고)** — 웹 매칭 규칙을 순수 함수 `MentorDirectoryFilter` 로 이식 + 단위 테스트; 학교등급·계열 카탈로그는 `school_tier_catalog`·`major_category_catalog` SELECT(폴백 상수) | `mentorsListSearchParams.ts:11-233`, `publicMentorsListQueries.ts:329-413`, `schoolClassificationCatalog.ts:70-125` |
| 20 | 정렬 6종(popular 복합·review·rating·price_asc/desc·new) | 동일 | 부분 | **포함(price 정렬 제외 권고)** — popular = 학교인증 그룹 랭크 → 한줄소개 → bio 길이 → `reviewCount*10+avgRating` | `publicMentorsListQueries.ts:421-473` |
| 21 | 카드 게이트(승인 + 과목 ≥1) | 동일 | 뷰 결과 그대로(과목 0 필터 (확인 필요)) | **포함(정합)** | `publicMentorsListQueries.ts:504-660` |
| 22 | 최근 본 멘토(localStorage 20) + scope=recent | 동일 | 없음 | **포함** — SharedPreferences id 목록 + 디렉터리 `.in` 조회(API route 불필요) | `recentMentorsStorage.ts:1-42` |
| 23 | 찜·scope=favorite | 동일 | 있음(`favorites`) | **포함(기존)** | `034:4` |
| 24 | 상세 번들: 리뷰 통계·평균 응답시간·플랜·구독 열림·cap 마감·무료질문 잔여·IQ 단가 | `/mentors/[id]` | 부분(응답시간·무료질문·플랜 읽기) | **포함** — `get_mentor_review_stats(p_mentor_id, false)`(a/u), cap RPC 3종(a/u) 로 "구독 마감" 배지(웹은 service_role 이나 필수 아님), `is_open_for_subscriptions`(뷰) | `publicMentorBundle.ts:50-150`; `050:90-92`, `190:93-116` |
| 25 | 상세 CTA 구독 | 동일 | 없음(Commerce-Zero) | **제외** | 정책 §3 |
| 26 | 리뷰 목록(공개 가시 행·작성자 마스킹·답글) | 멘토 상세 | 없음 | **포함** — `reviews` 공개 predicate + `get_mentor_review_stats`; 작성자 `users` 는 RLS 로 0행 → "학*" 마스킹 폴백 | `reviewQueries.ts:36-175` |
| 27 | **리뷰 작성·수정**(자격·20~500자·1~5·마스킹·1인 1후기·모더레이션 잠금) | 멘토 상세 모달 | 없음 | **포함(서버 선행 S-2 권장)** — 자격은 DB 정책이 강제, 검증은 RPC 로 서버화 | `170:1-88`, `126:53-55`, `reviewQueries.ts:177-282` |
| 28 | 리뷰 삭제 | 없음(웹도 없음) | 없음 | **제외** | `reviewQueries.ts` |
| 29 | 구독 목록·7종 status 라벨·다음 결제·환불 추정 | `/subscriptions` | 부분(`isActive` 2분기 → 6라벨; `cancel_scheduled` 누락) | **포함(정합)** — `my_subscriptions_self()` + `subscriptions` 직접, 라벨 7종(`subscriptionDisplay.ts:3-98`), 이용개시 판정(`question_threads.created_at >= current_period_start`) | `studentSubscriptionManagement.ts:178-310` |
| 30 | 구독 해지 예약 | 동일 | 없음(안내문) | **오너 결정(조건부 포함, S-3)** | DB §4 #5 |
| 31 | 해지 예약 취소(undo) | 동일 | 없음 | **웹 위임 권고** | DB §4 #5 |
| 32 | 잔여 환불 신청 | `/support/refunds` | 없음 | **오너 결정**(커뮤니티/지원 도메인 결정 C 와 동일 RPC) | DB §4 #7 |
| 33 | 재구독 | 동일 | 없음 | **제외** | 정책 §3 |
| 34 | 마이페이지 집계(질문방·구독·알림·리뷰·신고·IQ 수) | `/mypage` | 부분 | **포함(정합)** — `payments` 건수는 결제 인접·매니페스트 미등재 → 제외 | `mypageQueries.ts:30-110` |
| 35 | 캐시 잔액·원장(기간 필터·truncated) | `/wallet/ledger` | 있음(5건) | **포함(확장)** — `my_cash_ledger_v1` 기간 필터·페이징; 페이싱크 pending 섹션은 제외 | `cashQueries.ts:46-102`; DB §4 #2 |
| 36 | 홈·노트·레거시 redirect | `/home`, `/notes`, `/questions*`, `/cash-history` | — | **제외**(웹도 redirect) | 웹 리포트 §6 |

집계(36행): **포함 25**(#1~12 중 13 제외 = 11 ··· 정정: #1·2·3·4·5·6·7·8·9·10·11·12(12) + #14·15·17·18(4) + #19·20·21·22·23·24·26·27(8) + #29·34·35(3) = **27**) · **웹 위임 2**(#13·#31) · **제외 4**(#25·#28·#33·#36) · **오너 결정 3**(#16·#30·#32).

---

## 3. 서버 표면 설계

### (a) 기존 그대로 사용 가능(authenticated 근거)
| 객체 | 스키마 | 권한 | 용도 |
|---|---|---|---|
| `qna_flag_wrong_answer(uuid, boolean)` | public | u,s (`136:381-394`) | #3 |
| `weekly_question_usage_self(uuid)` / `_batch(uuid[])` | api_web_v1 | u | #5·#6 (앱 이미 사용) |
| `get_mentor_review_stats(uuid, boolean)` | public | a,u,s (계약 §3.3 D) | #24·#26 — `p_include_hidden=false` 고정 |
| `mentor_cap_used / mentor_cap_limit / subscription_cap_weight` | public | a,u (`050:90-92`, `190:93-116`) | #24 구독 마감 배지 |
| `get_mentor_avg_response_hours(uuid)` | public | a,u,s | #24 (앱 이미 사용) |
| `mentor_directory_v1` | api_web_v1 뷰 | anon 읽기 | #14·#19~#22 |
| `school_tier_catalog`, `major_category_catalog` | public 테이블 | SELECT (확인 필요 — 웹은 세션 클라이언트로 읽고 실패 시 상수 폴백) | #19 |
| `mentor_individual_question_pricing` | public | `miqp_select_authenticated` | #14 |
| `reviews` SELECT(공개 predicate) · INSERT `reviews_insert_student`(자격 RLS 내장) · UPDATE `reviews_update_author` + 트리거 `trg_reviews_enforce_update` | public | u | #26·#27 |
| `individual_question_transfers` | public | `iqt_select_student` (`075:34`) | #17 |
| `answer_individual_question(uuid)` | public | u (DB §4 #10) | #16 (결정 시) |
| `my_subscriptions_self()` · `subscriptions` SELECT 당사자 · `refunds` SELECT 본인 | api_web_v1 / public | u | #29 |
| `subscription_billing_events` SELECT | public | authenticated 정책 **(확인 필요)** — 없으면 `my_subscriptions_self()` 의 `current_plan_amount_cents` 로 대체 | #29 다음 결제액 |
| `my_wallet_v1` · `my_cash_ledger_v1` | api_web_v1 뷰 | u | #35 |

### (b) 새로 필요한 서버 객체(웹 pack · `api_app_v1` SECDEF + `core_private` impl · envelope · GRANT authenticated)

| ID | 객체·시그니처 초안 | 구현부 요지 | 코드 | 조건 | 규모 |
|---|---|---|---|---|---|
| **S-1** | `public.qna_append_message` 내부 게이트 보강(또는 `question_messages` BEFORE INSERT 트리거) — 방 (student, mentor) 활성 구독 없음 ∧ 스레드가 무료 스레드(`free_question_usage.thread_id`) 아님 → `SUBSCRIPTION_REQUIRED` | 웹 `assertThreadCreationSubscriptionAllowed(isNewThread:false)` 규칙 이식(`questionThreadSubscriptionGuard.ts:8-86`); 웹은 이미 TS 로 막고 있어 동작 변화 없음, 앱 직접 호출 공백만 닫힘 | `SUBSCRIPTION_REQUIRED` | 포함(선행) | S |
| **S-2** | `api_app_v1.review_eligibility_self(p_mentor_id uuid) → jsonb {ok, eligible, mode:'create'\|'edit'\|'none', review_id, can_edit}` · `review_create_self(p_mentor_id uuid, p_rating int, p_body text) → jsonb {ok, review_id}` · `review_update_self(p_review_id uuid, p_rating int, p_body text) → jsonb` | impl: 계정 게이트 → `check_review_eligibility(mentor, actor)` → 본인 후기 존재 시 `create` 거부(`REVIEW_EXISTS` → edit 유도) → rating 1~5 정수 → 본문 20~500자 → `core_private.mask_contact_text`(CR 도메인 S-4 와 공유) → INSERT/UPDATE(모더레이션 상태면 `REVIEW_MODERATED`) → RETURNING 1행 판정. 웹 TS 규칙(`reviewQueries.ts:177-282`, `reviewEligibilityPolicy.ts:19-160`)을 서버로 이동해 웹·앱 단일 정본 | `AUTH_REQUIRED, ROLE_NOT_STUDENT, NOT_ELIGIBLE, REVIEW_EXISTS, REVIEW_NOT_FOUND, REVIEW_NOT_MINE, REVIEW_MODERATED, RATING_INVALID, BODY_LENGTH_INVALID` | 권장(미채택 시 Dart 미러 + 23505 처리) | M |
| **S-3** | `api_app_v1.subscription_cancel_at_period_end_self(p_subscription_id uuid) → jsonb {ok, cancel_at_period_end, current_period_end}` | impl: `student_id=auth.uid()` ∧ status ∈ {active, past_due} ∧ `cancel_at_period_end=false` → UPDATE `cancel_at_period_end=true, cancel_requested_at=now()`(웹 `subscriptionCancelActions.ts:93-166` 동치). undo 는 만들지 않음(웹 위임) | `SUBSCRIPTION_NOT_FOUND, SUBSCRIPTION_NOT_CANCELLABLE, ALREADY_SCHEDULED` | 오너 결정(§7 D-1) | S |
| **S-4** | `api_app_v1.connection_note_save_self(p_room_id uuid, p_body text) → jsonb {ok, note_id}` (+ `…_update_self(p_note_id, p_body)`, `…_delete_self(p_note_id)`) | impl: 방 당사자 → 구독 가드(활성 구독 OR 구독 이력 0건인 진짜 무료 방 허용, 이력 있고 활성 없으면 `SUBSCRIPTION_EXPIRED` — `connectionNoteSubscriptionGuard.ts:25-82` 이식) → append INSERT(`author_id`, `author_role`). 웹 액션도 같은 impl 로 전환 권고 | `NOT_ROOM_PARTY, SUBSCRIPTION_EXPIRED, BODY_REQUIRED, NOTE_NOT_MINE` | 권장(§7 D-3) | S~M |
| **S-5** | (선택) `api_app_v1.mentor_directory_search_v1(p_filters jsonb, p_sort text, p_page int, p_page_size int) → jsonb {ok, items, total, page}` | 웹·앱 모두 뷰 전량 인메모리 처리(웹 상한 10,000행)라 멘토 수 증가 시 양쪽이 같이 무너짐. 필터·정렬 규칙을 SQL 로 이식해 서버 페이징 | — | 선택(규모 확대 시) | M |
| **S-6** | (선택) `question_threads` 에 `entitlement_path text`(free/subscription) 또는 `api_app_v1.free_thread_ids_for_room(p_room_id)` | 멘토 화면 "무료 체험 · 우선 답변" 배지는 `free_question_usage` 를 멘토가 못 읽어 웹은 service_role 로 판정(`freeQuestionUsage.ts:200-282`) → 앱은 서버 객체 없이는 표시 불가 | — | 선택(#8) | S |
| **S-7** | Realtime publication 에 IQ 3 테이블 포함 확인·추가(멱등 DO) | 앱 `iq_realtime.dart` 가 구독 중 — 미포함이면 무음 폴백 | — | 확인 필요 | S |

### (c) 정책 공백·리스크(서버)
1. `qna_append_message` 구독 게이트 부재(S-1) — 현재 앱도 같은 공백을 가진 채 배포 중.
2. 리뷰 검증 TS 전용 — 앱 직접 INSERT 는 자격만 DB 강제, 길이·마스킹 미강제(S-2 전까지 Dart 미러 필수).
3. 연결노트 구독 가드 앱 계층 전용(S-4) — 앱은 현재 `Entitlement.isActive` 로만 판정.
4. `weekly_question_usage_self` 실패 시 앱이 "보수적 통과"로 질문 생성을 허용 — RPC 정본 `qna_create_question_thread` 가 `WEEKLY_LIMIT_EXHAUSTED` 로 막으므로 실제 초과는 없지만 표시 불일치.
5. `is_open_for_subscriptions` 가 학생 CTA 에 반영되는지 **(확인 필요)** — 앱은 뷰 컬럼을 그대로 표시.

---

## 4. 앱 프론트엔드 설계(기존 feature 확장 지점)

| feature | 확장 파일(현행) | 추가·변경 |
|---|---|---|
| `question_room/data` | `question_room_write_repository.dart` | `flagWrongAnswer(threadId, isWrong)` → `qna_flag_wrong_answer`; `createThread` 에 `topic` 전달 |
| | `question_room_read_repository.dart:148-172` | 배치 사용량 결과를 `SubscriptionSummary.remaining` 에 주입(마이페이지 공유 store — 플랫폼 §3 `SubscriptionSummaryStore`); RPC 실패 → `WeeklyUsage.failed` 상태(fail-closed 표시) |
| | `thread_status_counts.dart`, `ui/widgets/thread_status_pill.dart` | 탭 분류(all/waiting/needReview/done) 순수 함수 + 테스트 |
| | `connection_notes_screen.dart`·write repo | S-4 채택 시 RPC 경로로 전환, 미채택 시 append 의미 정합(최신 행 표시) + 구독 가드를 서버 응답(`my_subscriptions_self`)으로 |
| `individual_question/ui` | 신설 `direct_mentor_board_screen.dart` | 디렉터리 + 단가 배치 → 카드(가격 비표시 정책 하 "개별질문 가능" 배지); 진입 = 웹 위임 링크(플래그) |
| | `iq_detail_screen.dart` | transfer 링크(`individual_question_transfers` 조회 → 스레드 라우트), 답변 확정 의미(D-5 결정 반영) |
| `mentors/data` | `mentor_directory_view.dart`, `mentor_sort.dart`, `mentor_subject.dart` | `MentorDirectoryFilter`(8종 중 가격대 제외 7종)·`MentorSort`(6종 중 price 제외 4종) 순수 함수 + 웹 규칙 동치 테스트; 카탈로그 레포(`school_tier_catalog`·`major_category_catalog`, 폴백 상수); `RecentMentorsStore`(SharedPreferences ≤20) |
| `mentors/ui` | `mentor_detail_screen.dart` | 리뷰 통계·목록·작성 진입, cap 배지(RPC 3종), `is_open_for_subscriptions` 표시 |
| 신설 `features/reviews/` | `data/review_repository.dart`, `data/review_models.dart`, `data/review_error_mapper.dart`, `ui/review_list_screen.dart`, `ui/review_compose_screen.dart` | S-2 RPC 경로(미채택 시 직접 INSERT/UPDATE + Dart 검증 + 23505→"이미 작성") |
| `mypage` | `student_subscription_section.dart`, 신설 `subscriptions_screen.dart` | 7종 status 라벨(`subscriptionStatusDisplay` 확장: `cancel_scheduled`·`past_due grace_until`), 이용개시 판정, 해지 예약(S-3 채택 시), 환불 신청 진입(결정 C), 재구독 CTA 없음 |
| | `mypage_repository.dart` | 집계 count 정합(`payments` 제외), IQ 수 |
| | `cash_section.dart` | 원장 기간 필터·페이징(`my_cash_ledger_v1`), 충전 유도 문구 0 |
| 공통 | 매니페스트 | RPC: `qna_flag_wrong_answer`, `get_mentor_review_stats`, `mentor_cap_used`, `mentor_cap_limit`, `subscription_cap_weight`(, `review_*_self`, `subscription_cancel_at_period_end_self`, `connection_note_*_self`, `answer_individual_question`); 테이블: `reviews`, `individual_question_transfers`, `school_tier_catalog`, `major_category_catalog`(, `subscription_billing_events`, `refunds`) |

재사용 코어: 봉투 파서(S-1~S-4 envelope), raise 스타일 매퍼(`qna_flag_wrong_answer`·cap RPC), `DataRefreshBus`(subscription 세대 — 현재 생산자 0 → 해지 예약·환불 신청이 첫 생산자), `ResumeVisibilityGate`, 디렉터리 페이지 로더(`incomplete` 플래그 유지).

---

## 5. 데이터 모델 추가/변경
- `QuestionThread`: `isWrongAnswer`, `topic`, `firstAnsweredAt`, `confirmedAt`(060 컬럼) — 탭 분류 입력.
- `WeeklyUsage`: `{used, limit, remaining, canAsk, weekStart, weekEnd, planTier, failed}` + 무료 스냅샷 변형(`freeQuota:true, limit 3`).
- `SubscriptionItem`(관리 목록): `SUBSCRIPTIONS_SELECT` 22컬럼 중 `id, mentor_id, plan_tier, status, started_at, current_period_start/end, next_billing_at, cancel_at_period_end, cancel_requested_at, grace_until` + 파생 `tone(7)`, `canCancel`, `usageStarted`, `refundEstimate`(표시용 — 별표4 계산은 서버 RPC 채택 시 서버값).
- `MentorDirectoryEntry`: 뷰 17필드 + 파생 `schoolGroupRank`, `hasDirectPricing`, `capFull`(RPC).
- `Review`: `id, mentorId, rating, body, createdAt, authorMaskedName, mentorReply, mentorRepliedAt, moderationState, isHidden, isBlinded`; `ReviewEligibility {eligible, mode, reviewId, canEdit}`.
- `IndividualQuestionTransfer`: `individual_question_id, room_id, thread_id`.
- `SchoolTierCatalog`/`MajorCategoryCatalog`: `code, label, display_order, is_active`(폴백 상수 — `그외` 포함).

---

## 6. 구현 순서·의존성·규모
| 단계 | 작업 | 의존 | 규모 |
|---|---|---|---|
| P0 서버 | S-1 append_message 게이트 · S-7 IQ publication 확인 · (결정 후) S-2 리뷰 RPC · S-3 해지 예약 · S-4 연결노트 | 오너 결정 D-1·D-3·D-4 | S+S+M+S+M |
| P1 질문방 정합 | 오답 표시·topic·탭 분류·마이페이지 잔여(batch)·실패 표시 | 없음 | S~M |
| P2 멘토찾기 정합 | 필터 7종·정렬 4종 순수 함수 + 테스트 · 카탈로그 · 최근 본 멘토 · 카드 게이트 · 상세 cap 배지·통계 | 없음 | M |
| P3 리뷰 | 열람(S) → 작성·수정(S-2 후) | S-2 | S + M |
| P4 구독 관리 | 7종 라벨·이용개시·목록 화면 → 해지 예약(S-3 후) → 환불 신청 진입(결정 C) | S-3, 지원 도메인 S-3 | M + S |
| P5 IQ 정합 | direct 보드(읽기)·transfer 링크·확정 의미(D-5)·expires_at 확인 | D-5 | M |
| P6 연결노트 | S-4 채택 시 RPC 전환, 아니면 의미 정합 | D-3 | S |
총량: 서버 S×3 + M×2 · 앱 M×4 + S×4 ≈ **L**.

---

## 7. 오너 결정 필요 항목
| ID | 결정 | 권고 |
|---|---|---|
| D-1 | 구독 해지 예약 앱 포함(S-3) | **조건부 포함** — 결제 중단 행위, 가격·재유도 문구 0. undo 는 웹 위임 |
| D-2 | 잔여 환불 신청 앱 포함 | 지원 도메인 결정 C 와 동일(조건부 포함, 정책 문서 §3 개정 선행) |
| D-3 | 연결노트 의미(append 유지 vs upsert 전환)·구독 가드 서버화(S-4) | **append 유지(웹 정본) + S-4 RPC** — 웹 액션도 같은 impl 로 전환 |
| D-4 | `qna_append_message` 구독 게이트 서버화(S-1) | **포함(선행)** — 웹 동작 변화 없음 |
| D-5 | IQ 답변 확정 의미 | **RPC 자동 전이(첫 멘토 메시지 = answered)를 정본으로** 하고 웹 명시 확정은 `answer_individual_question` 호출로 수렴(멘토가 메시지 없이 확정하는 경우만) — 웹 코드 변경 1건 |
| D-6 | 가격대 필터·가격 정렬·가격 표시 | **앱 제외 유지**(정책 §4 "가격표+구매 유도" 회피) |
| D-7 | 리뷰 검증 RPC(S-2) vs Dart 미러 | **RPC** — 웹 API route 도 같은 impl 로 전환하면 단일 정본 |
| D-8 | 멘토 디렉터리 서버측 검색 RPC(S-5) 도입 시점 | 멘토 수 1,000 미만이면 보류, 초과 전 도입 |
| D-9 | 무료 스레드 배지용 서버 객체(S-6) | 보류 가능(멘토 화면 배지만 영향) |
| D-10 | 웹 `CLAUDE.md` 리뷰 조건 문구("2회 연속 결제") → SQL 170 기준으로 정정 | 문서 정정(웹 저장소) |

---

## 8. 리스크·지뢰
1. 리뷰 작성자 `users` 행은 RLS 로 0행 → 앱도 웹처럼 "학*" 마스킹 폴백(닉네임 노출 기대 금지).
2. `check_review_eligibility` 의 authenticated EXECUTE 여부 **(확인 필요)** — RLS 정책 내부 호출은 정책 컨텍스트로 실행되므로 앱이 사전 자격 조회를 하려면 S-2 `review_eligibility_self` 가 필요.
3. `subscription_billing_events` 당사자 SELECT 정책 **(확인 필요)** — 없으면 다음 결제액은 `my_subscriptions_self().current_plan_amount_cents` 로 대체(표시 정책상 금액 비노출이면 무관).
4. IQ `expires_at` NULL 가능 — 만료 표시는 `expires_at ?? created_at + 기본시간` 폴백 규칙을 앱에도 동일 적용(`ExpiryScan.ts:7-64`).
5. 멘토 디렉터리 전량 로드(앱 100×50, 웹 10,000 상한) — 필터 규칙 이식 시 성능 동일 한계, S-5 트리거 기준 명시.
6. `cancel_scheduled` 상태를 현행 앱이 '만료'로 뭉침 — 새 라벨 도입 전까지 표시 오류.
7. `weekly_question_usage_self_batch` 최대 50 — 활성 구독 50개 초과 학생은 분할 호출.
8. Realtime IQ 테이블 publication 미확인 — 구독 코드가 무음 폴백으로 동작하므로 기능 결함은 아니나 "실시간" 문구는 붙이지 말 것.
9. 학교등급 카탈로그에 `그외`(193) 포함 — 필터 UI 는 웹처럼 `그외` 비노출·`미분류` 종속 규칙을 따를지 별도 확인.
