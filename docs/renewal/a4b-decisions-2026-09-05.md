# A-4b 1단계 — 결정 정리 (2026-09-05)

> 읽기 전용 단계. 코드 변경 0 · DB 변경 0. 입력: 웹 `docs/renewal/db4-report-2026-09-05.md`(§2·§3·§6·§7) ·
> 웹 `supabase/sql/199~204_*.sql` · 앱 `docs/renewal/design-v3.html` §5-3·§5-8·§5-9 · 앱 `docs/renewal/a6b-report-2026-09-05.md` §9·§11.
> 운영 DB(`lbeqxarxothkmzqvpudy`)는 카탈로그 SELECT 만 했다(pg_proc · 컬럼 권한 · `subjects.code`). 쓰기 0.

## 0. 기준선

| 항목 | 기대 | 실측 |
|---|---|---|
| `flutter analyze` | error 0 · warning 0 · info 27 | error 0 · warning 0 · info 27 ✔ (Flutter 3.44.6 stable) |
| `flutter test` | 1,647 통과 | 1,647 통과 ✔ (All tests passed) |
| 골든 | 38 + 갤러리 10 | `test/goldens/images` 38 · `test/goldens/design_system/images` 10 = 48 ✔ |

## 1-1. DB-4 §6 오너 결정 — 미결 6건

**이미 정해진 둘(반영 전제)**
- §6-1 본인인증 게이트 → 웹과 같은 플래그를 앱이 읽어 같은 방식으로 게이트. DB 가드 없음.
  구현 전제: 웹 플래그 `IDENTITY_GATE_ENABLED` 는 **서버 전용 env**(`lib/identity/identityGateFlag.ts` — `NEXT_PUBLIC_` 승격 금지)라 앱이 원격으로 읽을 수 없다.
  앱은 같은 이름의 `--dart-define=IDENTITY_GATE_ENABLED=true` 를 두고(`'true'` 만 ON — 웹 판정식 동일) ON 이면 `users.identity_verified_at`(authenticated SELECT 가능 — 실측)이 NULL 인 학생을 시트 대신 `본인인증 후 구독할 수 있어요` + WebView `/onboarding/verify` 로 보낸다. **웹 배포값과 앱 빌드값을 오너가 같이 맞춘다.**
- §6-2 released 개별질문 → 구독방 이전 → **하지 않는다.** 구독하면 방만 새로 열린다.

**나머지 6건 — 오너 답변 필요**

| # | 항목 | 무엇을 정해야 하는가 | 선택지 | CC 권고 + 이유 | 안 정하면 |
|---|---|---|---|---|---|
| 3 | 환불 계산 정본 이원화 | 앱은 SQL `refund_estimate` 를 쓰고 웹은 TS 를 그대로 쓰는 상태를 이번에 허용할지 | (a) 허용 — 웹이 SQL impl 을 호출하는 별도 웹 PR 은 나중에 · (b) 웹 PR 을 A-4b 배포 전에 먼저 | **(a)** — 경계 8/8 일치 실측(DB-4 §4)이라 지금 수치 차이 없음. 웹 PR 은 이 트랙 밖 | (a)로 진행. 이후 규칙이 바뀌면 두 곳을 같이 고쳐야 한다 |
| 4 | 해지 예약 취소(undo) | 앱 구독 카드에 `해지 취소` 버튼을 둘지(판정표 α9 는 "재개 = 다음 결제 재동의" 로 웹 위임 권고) | (a) 둔다 — 확인 시트에 `다음 결제(9월 13일 · 84,900원)가 다시 진행돼요` 명시 · (b) 안 둔다 — 카드에 `9월 13일에 해지돼요` 만 | **(a)** — 래퍼가 이미 있고 지시서 §2-3 이 명시. 재동의 우려는 확인 시트의 금액·날짜 문장으로 해소 | (a)로 진행 |
| 5 | 복귀 시 요금제 전부 재활성 | 일시중지 → 활동 중 복귀 때 202 토글로 꺼둔 요금제까지 다시 켜지는 것(웹 `resumeMentorActivity` 동일)을 그대로 둘지 | (a) 그대로 — 복귀 시트에 `꺼둔 요금제도 모두 다시 켜져요` 안내 · (b) DB-5 후속(복귀 시 토글 보존) 대기 · (c) 앱이 복귀 뒤 꺼둔 tier 를 다시 끈다(비원자 2회 호출) | **(a)** — DB 변경 0 원칙. (c) 는 중간 실패 시 켜진 채 남고, 토글은 복귀 직후 한 번 더 누르면 된다 | (a)로 진행. DB-5 후보로 기록 |
| 6 | 개별질문 v2 만료 미설정 | 앱 등록 개별질문의 `expires_at` 이 NULL 로 남는 것(v1 도 지금 같음)을 두고 갈지 | (a) 그대로 — 웹 만료 배치의 NULL 폴백(D-IQ-1: `created_at`+상태별 env 시간)이 처리 · (b) DB-5 에서 래퍼가 만료를 설정 | **(a)** — 오늘 v1 과 동작 동일, 웹 배치가 NULL 행도 만료·환불한다. DB 변경 0 | (a)로 진행. 앱 화면에는 만료 시각을 표시하지 않는다(값 없음) |
| 7 | 종료 효력일 | 종료 예정 UI 를 웹처럼 고정 +14일로 할지, 래퍼가 허용하는 14~90일 날짜 선택으로 할지 | (a) 날짜 선택(기본 +14일 · 최소 14 · 최대 90) · (b) 고정 +14일(날짜 인자 null) | **(a)** — 지시서 §2-5 "종료 예정(날짜)". 14일 미만은 서버가 +14일로 올리므로 위험 없음 | (a)로 진행 |
| 8 | 환불 사유 상한 2000자 | 앱 입력을 서버 상한(2000자)에 맞춰 막을지(웹엔 상한 없음) | (a) 입력 2000자 제한 + 카운터 + `REASON_TOO_LONG` 매핑 · (b) 제한 없이 오류 매핑만 | **(a)** — 서버 위생 상한과 같아야 사용자가 잘린 사유를 보내지 않는다 | (a)로 진행 |

**추가 확인 1건(§6 밖 · DB-4 §7 H)** — 학생증 사후 제출(⑦): 승인 시 만들어지는 "서류 없는 잠정 `pending` 행" 이 있을 때 웹 UI 는 제출을 잠그지만 DB 는 허용한다. DB-4 는 앱이 **잠그지 않고** `서류 없음 · 관리자 확정 대기` 로 표시하길 권고. **권고대로 진행**(반대면 알려주세요 — 웹과 같이 잠근다).

## 1-2. 채팅 확인 바 — 웹 대조

**있다 → 2단계 ⑨ 포함.** 웹 학생 질문방 대화 화면 `components/qna/QuestionRoomStudentDesignWorkspace.tsx:762-780` 에
`threadWorkflow === "answered"` 일 때 대화 하단에 `멘토 답변이 도착했어요. 확인하면 완료로 표시돼요.` + `QuestionThreadConfirmButton`(`/api/question-room/threads/{id}/confirm` → `qna_confirm_thread`) · 확인 뒤 `답변을 확인했어요` 배지.
앱은 같은 RPC(`qna_confirm_thread`)를 이미 질문 목록 카드(`question_list_screen.dart:295` '답변 확인 완료')에서 부른다. 2단계는 **새 RPC 0** — 대화 화면(§3-2) 하단에 같은 동작을 두고, 확인 뒤 입력창을 `완료된 질문이에요` 로 잠근다(웹 `threadLocked` 동일). 목록 카드 버튼은 유지.

## 1-3. 계약표 — `api_app_v1` 10 함수 (2단계 정본)

호출: `client.schema('api_app_v1').rpc(name, params: {...})`. envelope 함수는 `data['ok'] == true` 일 때만 성공(`ok` 없음 = 실패). raise 함수 2종은 `PostgrestException.message` 선두 대문자 토큰.
**보고서 §2·§3 ↔ 마이그레이션 SQL ↔ 운영 DB(pg_proc 실측) — 시그니처·반환형·SECDEF·EXECUTE(authenticated 만) 10/10 일치. 차이 없음.**

| # | 함수(인자) | 반환(성공) | 오류 코드 | 앱 화면 |
|---|---|---|---|---|
| 1 | `subscribe_with_cash(p_mentor_id uuid, p_tier text, p_idempotency_key text)` → jsonb | `subscription_id, room_id, payment_id, plan_id, plan_tier, debited_cents, balance_after_cents, reactivated, idempotent, current_period_start, current_period_end, next_billing_at` | `AUTH_REQUIRED` · `MENTOR_NOT_FOUND` · `PLAN_TIER_INVALID` · `IDEMPOTENCY_KEY_INVALID`(빈 값·128자 초과) · `IDEMPOTENCY_KEY_CONFLICT`(`payment_id`) · `ROLE_NOT_STUDENT` · `ACCOUNT_BANNED/SUSPENDED/NOT_ACTIVE/DELETION_IN_PROGRESS` · `MENTOR_NOT_APPROVED` · `MENTOR_TERMINATED` · `MENTOR_PAUSED`(`pause_until`) · `MENTOR_NOT_OPEN_FOR_SUBSCRIPTIONS` · `BLOCKED` · `ALREADY_SUBSCRIBED`(`subscription_id`) · `PLAN_NOT_FOUND/INACTIVE/AMOUNT_INVALID`(`plan_tier`) · `MENTOR_CAP_EXCEEDED`(`cap_used, cap_weight, cap_limit`) · `CASH_INSUFFICIENT`(`required_cents, balance_cents, shortfall_cents`) · F12 계열(`PLAN_AMOUNT_CHANGED`·`ROOM_ENSURE_FAILED`·`FINANCIAL_WRITE_ERROR`·`LEDGER_*`·`PAYMENT_*`, 이상 계열은 `anomaly_id`) | ① 멘토 상세 시트. tier = `limited`/`standard`/`premium`. 키 = 시트 열 때 uuid v4 1개 → 재시도 재사용 · 성공/`IDEMPOTENCY_KEY_CONFLICT` 후 폐기. cents = 원×100 |
| 2 | `subscription_cancel_at_period_end(p_subscription_id uuid)` → jsonb | `subscription_id, cancel_at_period_end:true, already_scheduled, cancel_requested_at, current_period_end` | `AUTH_REQUIRED` · `ROLE_NOT_STUDENT` · `SUBSCRIPTION_NOT_FOUND` · `NOT_SUBSCRIPTION_OWNER` · `SUBSCRIPTION_NOT_CURRENT`(`status`) | ② 구독 카드. 멱등 |
| 3 | `subscription_cancel_undo(p_subscription_id uuid)` → jsonb | `subscription_id, cancel_at_period_end:false, was_scheduled, current_period_end, next_billing_at` | 2 와 동일 | ② (결정 4) |
| 4 | `refund_estimate(p_subscription_id uuid)` → jsonb | `refundable_cents, amount_cents, rule, bracket_reason, usage_started, elapsed_days, period_days, remaining_days, remaining_ratio, elapsed_ratio, period_start, period_end, billing_event_id, billing_payment_id, as_of` — `rule` ∈ `이용 개시 전`·`1/3 전`·`1/2 전`·`1/2 후`·`계산 불가` / `bracket_reason` ∈ `before_usage`·`lt_1_3`·`lt_1_2`·`ge_1_2`·`invalid` | `AUTH_REQUIRED` · `SUBSCRIPTION_NOT_FOUND` · `NOT_SUBSCRIPTION_OWNER` | ③ 예상액 화면(`rule` 문구 그대로 표시 · 0원이면 `기준상 환불액이 0원이에요`) |
| 5 | `refund_request_create(p_subscription_id uuid, p_reason text)` → jsonb | `refund_id, subscription_id, amount_cents, rule, bracket_reason, status:'pending'` | `AUTH_REQUIRED` · `ROLE_NOT_STUDENT` · 계정 4종 · `REASON_TOO_SHORT`(`min_length` 5) · `REASON_TOO_LONG`(2000) · `SUBSCRIPTION_NOT_FOUND` · `NOT_SUBSCRIPTION_OWNER` · `SUBSCRIPTION_NOT_CURRENT` · `ALREADY_REQUESTED`(`refund_id`) · `REFUND_NOT_AVAILABLE`(`rule, bracket_reason`) | ③ 신청 폼. 접수 뒤 그 구독의 질문 작성은 `SUBSCRIPTION_REFUND_PENDING`(앱 매퍼 기존재) |
| 6 | `mentor_activity_set(p_status text, p_pause_until timestamptz = null, p_termination_effective_at timestamptz = null, p_reason text = 'rest')` → jsonb | paused: `activity_status, pause_until, pause_days, pause_reason, subscriptions_extended, event_status, event_id` / active: `activity_status, plans_reactivated, event_id` / terminating: `activity_status, termination_effective_at, notified_subscribers, plans_deactivated, event_id` | 공통 `AUTH_REQUIRED` · `ROLE_NOT_MENTOR` · 계정 4종 · `ACTIVITY_STATUS_INVALID` · `MENTOR_PROFILE_NOT_FOUND` / paused: `ACTIVITY_STATE_INVALID`(`current_state`) · `PAUSE_UNTIL_REQUIRED` · `PAUSE_UNTIL_INVALID` · `PAUSE_TOO_LONG`(`max_days` 7) · `PAUSE_REASON_INVALID` · `REST_FREQUENCY_LIMIT`(`last_pause_at, next_available_at`) / active: `ACTIVITY_STATE_INVALID` / terminating: `ACTIVITY_STATE_INVALID` · `TERMINATION_DATE_TOO_FAR`(`max_days` 90) | ④ 마이페이지(멘토). `p_reason` ∈ `rest`/`illness`. 효력일 < now+14일은 서버가 +14일로 올림 |
| 7 | `mentor_plan_active_set(p_tier text, p_is_active boolean)` → jsonb | `plan_tier, is_active, changed, active_tiers[]` | `AUTH_REQUIRED` · `ROLE_NOT_MENTOR` · 계정 4종 · `PLAN_TIER_INVALID` · `PLAN_ACTIVE_VALUE_REQUIRED` · `MENTOR_PROFILE_NOT_FOUND` · `MENTOR_TERMINATED` · `PLAN_NOT_FOUND` · `LAST_ACTIVE_PLAN` | ⑤ 요금제 설정(C3) 토글 |
| 8 | `user_profile_update_self_v2(p_nickname text = null, p_grade_level text = null, p_student_status text = null)` → jsonb **(raise 규약)** | v1 envelope + `student_status`. null=유지 · ''=제거 | v1 사전(`AUTH_REQUIRED` 28000 · `ACCOUNT_*` · `NICKNAME_*` · `GRADE_LEVEL_*` 22023) + `STUDENT_STATUS_NOT_ALLOWED` · `STUDENT_STATUS_TOO_LONG`(20자) | ⑥ 프로필 편집(학생). v1 호출을 v2 로 교체(`profile_edit_repository.dart:110`). 어휘 정본 없음(자유 텍스트 20자) |
| 9 | `mentor_student_id_document_set_self(p_object_path text)` → jsonb | `stored_ref('student-id-images/{uid}/…'), updated_at` | `AUTH_REQUIRED` · `ROLE_NOT_MENTOR` · 계정 4종 · `MENTOR_PROFILE_NOT_FOUND` · `STORAGE_PATH_REQUIRED` · `STORAGE_PATH_INVALID` · `STORAGE_FILE_TYPE_INVALID`(jpg/jpeg/png/pdf) · `STORAGE_OBJECT_NOT_OWNED` | ⑦ 마이페이지(멘토). 앱이 버킷 `student-id-images/{uid}/{file}` 에 user JWT 업로드(RLS) → RPC. 크기 20MB 는 클라이언트 검증 |
| 10 | `create_individual_question_as_student_v2(p_question_type text, p_title text, p_body text, p_amount_cents int = null, p_designated_mentor_id uuid = null, p_idempotency_key text = null, p_subject text = null)` → setof `individual_questions` **(raise 규약)** | `individual_questions` 행 | v1 사전(`AUTH_REQUIRED` 28000 · `INVALID_INPUT: …` 22023 · `MENTOR_PRICE_NOT_SET` · `INDIVIDUAL_QUESTION_CREATE_FAILED:<code>:<msg>` — `CASH_INSUFFICIENT` 등) + `INVALID_SUBJECT` · `SUBJECT_REQUIRED`(open 필수 · direct 선택) | ⑧ C8 화면 + 과목 칩. **스키마 주의**: v1 은 `public`(앱 `individual_question_repository.dart:172` 가 스키마 없이 호출), v2 는 `api_app_v1` — `.schema('api_app_v1')` 필수. `p_subject` 정본 `public.subjects.code` 35개 = 앱 `lib/data/mappings/subject_labels.dart` 집합과 **동일**(실측) |

**차이·주의(보고서 ↔ SQL)**: 시그니처 차이 0. 보고서 §3 표의 cancel 반환은 요약이며 SQL 실제 키는 위 표(`already_scheduled` 는 예약, `was_scheduled`·`next_billing_at` 은 undo 만). `user_profile_update_self_v2` 는 v1 과 다른 함수명이라 PostgREST 오버로드 문제 없음. 매니페스트 예상 증가분: `kExpectedRpcNames` +10(위 함수명) · 스키마 집합 불변 · 테이블 +1 후보(`subjects` — 앱 상수와 동일하므로 읽지 않으면 0) · 버킷 +1(`student-id-images` 업로드).

**2단계에서 만들지 않는 것(래퍼 없음)**: §5-8 목업의 `라이트로 낮추기`(요금제 변경 RPC 없음) · 캐시 충전 · 종료 확정·환불(관리자).

## 4. 기준선 실측

- `flutter analyze`: 27 issues — error 0 · warning 0 · info 27 (기대와 일치).
- `flutter test`: 1,647 통과 — All tests passed (기대와 일치).
