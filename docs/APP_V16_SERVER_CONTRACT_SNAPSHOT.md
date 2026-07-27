# 쌤버십 v16 서버 계약 스냅샷 (staging 실조회)

> 조회 일자: 2026-07-21
> 대상 프로젝트: staging `lbeqxarxothkmzqvpudy` (읽기 전용 조회, DDL/DML 없음)
> 조회 방법: `pg_proc` / `pg_get_functiondef` / `pg_policies` / `pg_constraint` / `information_schema` /
> `storage.buckets` 실정의 조회. 이 문서가 `APP_REMEDIATION_v16_PLAN.md`의 "작성 시점 미배포" 표를 대체한다.
> 웹·DB 계약: SQL 160까지 적용된 staging 실정의가 정본.

---

## 1. 질문방 RPC — 전부 배포 확인 (트랙 B 게이트 충족)

모든 함수는 `public` 스키마, `SECURITY DEFINER`, `SET search_path TO 'public'`,
`authenticated` 역할에 EXECUTE 부여 확인. 반환은 모두 `jsonb`.
오류는 `raise exception '<CODE>'` 방식 → 클라이언트에는 PostgrestException `message`에 코드 문자열이 들어온다
(별도 SQLSTATE 구조화 아님, hint/details 없음).

### 1.1 `qna_create_question_thread(p_room_id uuid, p_title text, p_subject text = null, p_topic text = null, p_first_message_body text = null)`

- **구독·무료 경로를 서버가 내부 분기** (active subscription 존재 여부로 판단).
  - 구독 경로: 활성 구독 행 `FOR UPDATE` 잠금 → live refund 검사 → `get_weekly_question_usage`의
    `can_ask` 검사 → thread+첫 메시지 INSERT.
  - 무료 경로: 가입 7일 이내 + 총 7회 + 멘토당 3회 검사 → thread+첫 메시지 INSERT +
    `free_question_usage` INSERT — **한 트랜잭션**.
- 신규 thread 초기 상태: **`pending`** (앱이 status를 보내지 않음).
- `p_subject`: `subjects.code`에 없으면 **서버가 조용히 NULL 처리** (오류 아님).
- 반환: `{"ok":true, "thread_id":uuid, "message_id":uuid|null, "path":"subscription"|"free", "used_free_quota":bool}`
  - `p_first_message_body`가 공백/NULL이면 `message_id`는 null (메시지 INSERT 생략).
- 오류 코드(발생 순서대로):
  `AUTH_REQUIRED`, `TITLE_REQUIRED`, `ROOM_NOT_FOUND`, `MENTOR_CANNOT_CREATE_THREAD`, `NOT_ROOM_PARTY`,
  `ACCOUNT_BANNED`, `ACCOUNT_SUSPENDED`(suspended_until 미도래), `BLOCKED`, `MENTOR_NOT_APPROVED`,
  `SUBSCRIPTION_REFUND_PENDING`, `WEEKLY_LIMIT_EXHAUSTED`,
  `FREE_QUOTA_EXPIRED`(가입 7일 경과), `FREE_QUOTA_TOTAL_EXHAUSTED`(총 7회), `FREE_QUOTA_MENTOR_EXHAUSTED`(멘토당 3회).

### 1.2 `qna_create_free_question_thread(...)` — 동일 인자

- **단순 위임 래퍼**: `return qna_create_question_thread(...)`. 신규 코드는 `qna_create_question_thread`
  하나만 쓰면 된다(무료/구독 분기는 서버 몫).

### 1.3 `qna_append_message(p_thread_id uuid, p_body text)`

- thread `FOR UPDATE` 잠금 → 당사자 판정(학생/멘토) → 계정/잠금/멘토승인/환불 검사 → 메시지 INSERT.
- **첫 멘토 메시지에서만** `status='answered', first_answered_at=now()` 전이 +
  `question_answered` 도메인 알림 기록(`record_domain_notification`) — **전부 서버 담당**.
  이후 멘토 메시지는 재전이·재알림 없음 (`first_answered_at is null` 조건).
- 허용 thread 상태: `confirmed/closed/archived` **이외 전부** → 레거시 `open` thread 후속대화 허용됨.
- 반환: `{"ok":true, "message_id":uuid, "answered_transition":bool}`
- 오류: `AUTH_REQUIRED`, `BODY_REQUIRED`, `THREAD_NOT_FOUND`, `NOT_ROOM_PARTY`, `ACCOUNT_BANNED`,
  `THREAD_LOCKED`(confirmed/closed/archived), `MENTOR_NOT_APPROVED`,
  `SUBSCRIPTION_REFUND_PENDING`(학생 발신 && 활성 구독에 live refund).

### 1.4 `qna_confirm_thread(p_thread_id uuid)`

- 학생 전용. `confirmed` 상태면 **멱등 성공** 반환. `answered`가 아니면 `NOT_ANSWERED`.
- 반환: `{"ok":true, "thread_id":uuid}`
- 오류: `AUTH_REQUIRED`, `THREAD_NOT_FOUND`, `STUDENT_ONLY`, `NOT_ANSWERED`.

### 1.5 `qna_flag_wrong_answer(p_thread_id uuid, p_is_wrong boolean = true)`

- 학생 전용. `is_wrong_answer` + `mastery_status`(`wrong`/`unknown`) 갱신. 상태 제한 없음.
- 반환: `{"ok":true, "thread_id":uuid, "is_wrong_answer":bool}`
- 오류: `AUTH_REQUIRED`, `THREAD_NOT_FOUND`, `STUDENT_ONLY`.

### 1.6 `qna_register_attachment(p_thread_id uuid, p_storage_path text, p_file_name text = null, p_mime_type text = null, p_message_id uuid = null)`

- 경로 강제: `p_storage_path`는 반드시 `{room_id}/{thread_id}/...` — 아니면 `STORAGE_PATH_MISMATCH`.
- 소유 강제: `storage.objects`에 `bucket_id='question-room-attachments' AND name=path AND owner_id=auth.uid()`
  없으면 `STORAGE_OBJECT_NOT_OWNED` → **업로드가 먼저, 등록이 나중** 순서 고정.
- `p_message_id`가 주어지면 해당 thread 소속 검증 — 불일치 시 `MESSAGE_THREAD_MISMATCH`.
- **멘토 첫 첨부도 answered 전이 + `question_answered` 알림** (append와 동일 로직, 파일 문구).
- 반환: `{"ok":true, "attachment_id":uuid, "answered_transition":bool}`
- 오류: `AUTH_REQUIRED`, `STORAGE_PATH_REQUIRED`, `THREAD_NOT_FOUND`, `NOT_ROOM_PARTY`,
  `THREAD_LOCKED`, `STORAGE_PATH_MISMATCH`, `STORAGE_OBJECT_NOT_OWNED`, `MESSAGE_THREAD_MISMATCH`,
  `SUBSCRIPTION_REFUND_PENDING`.

### 1.7 사용량 조회 `get_weekly_question_usage(p_student_id uuid, p_mentor_id uuid)` → json

- plan_tier 별 limit: limited=4, standard=9, premium=999, 구독없음=0.
- 반환: `{used, limit, plan_tier, remaining, can_ask, week_start, week_end}` — 기존 배포와 동일. UX 사전검사용.

### 1.8 직접 write 전환 상태 (게이트 확인)

- 테이블 RLS 자체는 아직 room-party 직접 INSERT/UPDATE를 허용하지만, **BEFORE 트리거 가드가 배포됨**:
  - `trg_qt_direct_write_guard`: 직접 INSERT는 학생만·status `pending|open`만·workflow 필드 금지, RPC와
    동일한 계정/차단/승인/사용량 검사 수행. 직접 UPDATE에서 `answered` 전이 금지
    (`DIRECT_ANSWERED_VIA_CONTENT_ONLY`), `first_answered_at` 직접 변경 금지, confirm/오답은 학생만.
  - `trg_qm_direct_write_guard` / `trg_qa_direct_write_guard`: 잠긴 thread 거부, 첨부 경로/소유 위조 거부.
  - `qna_is_direct_untrusted_writer()` = `current_user in ('authenticated','anon')` → 앱 직접 write는 전부 가드 대상.
  - `trg_qm_direct_answered_after`/`trg_qa_direct_answered_after`/`trg_qt_direct_consume_free_usage`:
    레거시 직접 write에도 서버가 answered 전이·무료 사용량 소비를 보정.
- 결론: **직접 write는 서버가 이미 통제하지만, 앱은 RPC로 전환하는 것이 정본 계약.**

---

## 2. 첨부 Storage (`question-room-attachments`) — 게이트 충족

- 버킷: private(`public=false`), **file_size_limit=20MB(20971520)**,
  allowed_mime: `image/png, image/jpeg, image/webp, image/gif, application/pdf, application/zip, docx, pptx`.
- INSERT 정책 `qra_storage_insert_party`: room 당사자 + thread writable + 업로더 자격 + 경로 적격 +
  `NOT account_deletion_write_blocked(auth.uid())`.
- **DELETE 정책 `qra_storage_delete_unregistered_owner` 배포됨**:
  `owner_id = auth.uid()` **AND `question_attachments.storage_path`에 미등록**인 객체만 삭제 가능
  → 보상 삭제 설계와 정확히 일치. **등록 성공한 객체는 서버가 삭제를 거부**한다.
- SELECT: room 당사자 또는 admin.
- `question_attachments.storage_path` **UNIQUE 제약 확인** (`question_attachments_storage_path_key`)
  → 동일 경로 재등록 시 23505 → 앱은 중복 메타행 걱정 없이 재시도 가능하나 unique violation을
  "이미 등록됨(성공 취급)"으로 처리해야 함.
- `question_attachments` 직접 INSERT는 RLS상 아직 허용되나 `qa_direct_write_guard`가 경로/소유/잠금 검증.

## 3. 질문방 테이블 제약

- `question_threads.status` CHECK: `pending | answered | confirmed | open | closed | archived`.
  (`open`은 레거시. 신규 생성은 서버가 `pending` 고정.)
- `question_threads.mastery_status` CHECK: `unknown | wrong | review | mastered`.

---

## 4. 후속 세션 게이트 판정용 조회 결과

### 4.1 알림 (트랙 C) — 2026-07-21 세션 2 재조회로 전체 계약 확정

#### 토큰 (앱 사용 대상)

- `device_tokens(id uuid PK, user_id uuid NOT NULL FK users ON DELETE CASCADE, token text NOT NULL UNIQUE,
  platform text CHECK(ios|android|web|unknown), revoked_at, created_at, updated_at)`.
  RLS: select_own / modify_own(ALL, user_id=auth.uid()).
- **`register_device_token(p_token text, p_platform text='unknown') → jsonb`** (SECURITY DEFINER):
  `ON CONFLICT (token) DO UPDATE SET user_id=auth.uid(), platform, revoked_at=null` —
  **계정 전환 시 원자 재소유까지 서버가 수행**(WAITING_SERVER_API 아님 · 게이트 충족).
  반환 `{ok:true, device_token_id}`. 오류: `AUTH_REQUIRED`, `TOKEN_REQUIRED`.
  잘못된 platform 은 'unknown' 으로 정규화.
- **`revoke_device_token(p_device_token_id uuid) → boolean`**: `revoked_at=now()` 세팅(멱등 —
  이미 revoke 면 null 반환). 앱은 등록 때 받은 `device_token_id` 를 저장해 로그아웃 시 사용한다.

#### 기록·발송 (앱 호출 금지 — 서버 전용)

- `record_domain_notification(p_recipient_user_id, p_event_key, p_dedup_key, p_event_type, p_title,
  p_body, p_link, p_metadata, p_payload)` — notifications + notification_outbox upsert.
  **DB 트리거(com_notify_*, iq_notify_*, sbe_notify_* 등)가 호출하는 서버 내부 경로.
  앱은 절대 호출하지 않는다(발송은 서버 outbox worker: notification_outbox_claim/mark_sent/
  mark_failed + notification_deliveries + notification_delivery_allowed).**

#### notifications 정본 컬럼 (record_domain_notification 이 쓰는 것)

- 수신자 정본: **`recipient_user_id`** (+ `user_id` 미러). UNIQUE `(recipient_user_id, event_key)`.
- 읽음 정본: **`is_read`** (+`read_at`). RLS: 다중 수신자 컬럼 OR 매칭으로 select/update 허용
  (레거시 recipient_id/student_id/mentor_id/target_user_id/owner_id 포함).
- 내용: `type`(이벤트 타입), `body`, `data`(`{title, link}`), `metadata`(`{event_key, link, ...타입별 ID}`).
- 커서: `(created_at DESC, id DESC)` — 인덱스 `idx_notif_user_unread(user_id,is_read,created_at DESC)` 등.
- 전체 읽음: **`mark_all_notifications_read()`** (인자 없음 → integer, AUTH_REQUIRED errcode 28000).

#### 17종 이벤트 type (트리거 소스 실추출로 확정)

| type | 발생 트리거 | link/metadata |
|---|---|---|
| `question_answered` | qna_append_message / qna_register_attachment | link `/question-room/{roomId}?thread={threadId}`, metadata `{room_id, thread_id}` |
| `new_order_message` | com_notify_new_order_message | link `/custom-request/orders/{id}` |
| `new_application` | cra_notify_new_application | link `/applications/waiting`, `/custom-request/...` |
| `mentor_subscription_price_changed` | mplan_notify_price_changed | link `/mentors/{id}` |
| `mentor_pause_notice` / `mentor_termination_notice` | mp_notify_activity_transition | link `/subscriptions` |
| `mentor_termination_refund` | refund_notify_mentor_termination | link `/support/refunds` |
| `individual_question_assigned` | iq_notify_assigned | **link 없음(null)**, metadata `{question_id}` |
| `individual_question_claimed` / `individual_question_answered` / `individual_question_released` / `individual_question_expired_refunded` | iq_notify_status_transition | **link 없음(null)**, metadata `{question_id, status}` |
| `individual_question_message` | iqm_notify_message | metadata `{question_id}` |
| `subscription_renewal_upcoming` / `subscription_renewal_succeeded` / `subscription_renewal_failed_insufficient_cash` | sbe_notify_billing_event | link `/subscriptions`, `/wallet/charge` (충전 링크는 앱에서 결제 화면 금지 — Commerce-Zero 처리 필요) |
| `subscription_expired` | sub_notify_expired | link `/subscriptions` |

→ IQ 계열은 link 가 없으므로 **딥링크는 metadata 의 ID 필드(question_id/room_id/thread_id)가 정본**,
`link` 는 보조. staging notifications 실데이터는 현재 0행.

#### 설정

- `notification_settings(user_id PK, push_enabled bool, groups jsonb, updated_at)`;
  RLS select_own/modify_own. **`users.notification_enabled` 아님.**
- 그룹 판정 정본 `notification_event_group(type)`:
  `question_*|qna_*|connection_note*`→**qna**, `custom_*|order_*|individual_question*`→**order**,
  `%subscription%`→**subscription**, `%refund%`→**refund**, 그 외→**system**.
  (`individual_question_expired_refunded` 은 case 순서상 **order**.)
- 발송 판정 `notification_delivery_allowed`: 설정 행 없음 → **허용(true)**,
  `push_enabled AND coalesce(groups->>group, true)` — 그룹 키 부재도 허용.
  → 앱 UI 도 "행 없음/키 없음 = ON" 의미론을 따라야 한다.

### 4.2 계정 라이프사이클 (트랙 D) — 배포 확인

- `account_deletion_jobs.state` CHECK:
  `pending | locked | purging | storage_purged | finalized | auth_soft_deleted | completed | canceled | failed`.
- `account_deletion_request(p_user_id, p_cancelable_minutes=30, p_dry_run=true)` → jsonb
  `{ok, existing, job_id, state}` — **기존 job 있으면 existing:true로 그 상태 반환** (멱등).
  ⚠ 기본값 `p_dry_run=true` — 실삭제 요청은 명시적으로 false를 보내야 함.
- `account_deletion_cancel(p_user_id)` → `{ok:false, code:NOT_FOUND|NOT_CANCELABLE|CANCEL_WINDOW_PASSED}`
  또는 `{ok:true, state:'canceled'}`. `pending` 상태 + cancelable_until 이내에만 취소 가능.
- `account_deletion_write_blocked(p_user_id)` → bool:
  state가 `locked|purging|storage_purged|finalized|auth_soft_deleted`면 true (write 차단 판정 정본).
- `users.status`: CHECK 제약 없음(자유 text). RPC들은 lower() 비교로 `banned`/`suspended`(+`suspended_until`)/
  기타(active 취급)를 사용. staging 실데이터는 현재 `active`만 존재.
- effective-status 전용 조회 RPC는 **없음** — 앱은 `users.status` + `suspended_until` +
  `account_deletion_jobs.state`(본인 행) 조합으로 상태를 모델링해야 함.

### 4.3 댓글·최소버전 (트랙 E) — **게이트 미충족 → WAITING_SERVER_GATE**

- `comments(id, post_id, parent_id, author_id, content, is_deleted, like_count, created_at)` 정본 테이블 존재.
- **최소 앱 버전 API/테이블 없음**: `%version%`/`app_config`/`remote_config` 계열 테이블·함수 조회 결과 0건.
  → 계획 §0-2 "구버전 차단은 서버 최소버전 응답 + 앱 시작 게이트 둘 다 준비된 뒤" 원칙에 따라
  **댓글 정본 전환은 이번 세션에서 착수하지 않는다.**

### 4.4 숏폼 scrap (P2-14) — **게이트 충족**

- `shortform_reactions_type_check`: `type IN ('like','scrap')` CHECK 배포.
- UNIQUE `(user_id, shortform_id, type)` 배포.
- RLS: `insert_own`(user_id=auth.uid() AND type in like/scrap), `delete_own`, `select_own` 배포.
  ⚠ SELECT가 **본인 행만** 허용 → 집계 카운트는 `shortform_posts` 쪽 컬럼/뷰에서 읽어야 함.
- → scrap 토글 활성화 가능.

### 4.5 과목 정본 catalog (P2-23) — 확정

`subjects.code` 35종 (label은 표시용, DB 전송은 code만):

| code | label | code | label |
|---|---|---|---|
| korean | 국어 | social_life_ethics | 생활과윤리 |
| korean_speech_writing | 화법과작문 | social_ethics_thought | 윤리와사상 |
| korean_language_media | 언어와매체 | social_korea_geo | 한국지리 |
| korean_reading | 독서 | social_world_geo | 세계지리 |
| korean_literature | 문학 | social_east_asia_history | 동아시아사 |
| english | 영어 | social_world_history | 세계사 |
| math | 수학 | social_economics | 경제 |
| math_1 | 수학Ⅰ | social_politics_law | 정치와법 |
| math_2 | 수학Ⅱ | social_culture | 사회문화 |
| math_calculus | 미적분 | science | 과학 |
| math_statistics | 확률과통계 | science_physics_1 | 물리학Ⅰ |
| math_geometry | 기하 | science_chemistry_1 | 화학Ⅰ |
| korean_history | 한국사 | science_biology_1 | 생명과학Ⅰ |
| social | 사회 | science_earth_1 | 지구과학Ⅰ |
| essay | 논술·글쓰기 | science_physics_2 | 물리학Ⅱ |
| career | 진로·입시 | science_chemistry_2 | 화학Ⅱ |
| etc | 기타 | science_biology_2 | 생명과학Ⅱ |
| | | science_earth_2 | 지구과학Ⅱ |

- 서버 동작: 질문 생성 RPC의 `p_subject`가 catalog에 없으면 **NULL 처리(무시)** — 오류는 아니지만
  사용자가 고른 과목이 조용히 사라지므로 앱은 **정본 code만 전송**해야 함.

---

## 4.6 세션 3 재조회 (2026-07-21)

### 계정 탈퇴 RPC 권한 — ★앱 직접 호출 불가
- `account_deletion_request` / `account_deletion_cancel` ACL:
  **`{postgres, service_role}` 만 EXECUTE — authenticated 없음.**
  → 앱이 직접 호출하면 42501(permission denied). 실탈퇴는 현재 웹(백엔드 service_role) 경유만 가능.
  앱 내 탈퇴 UX 는 포트/fake 로 계약을 고정하고, 라이브 경로는 **WAITING_SERVER_API**
  (`GRANT EXECUTE ... TO authenticated` 필요 — 웹·DB 측 조치).
- `account_deletion_write_blocked` 는 authenticated EXECUTE 유(세션 2 확인과 동일).

### 개별질문 환불 — 공개 wrapper 확정
- **`refund_individual_question(p_question_id)`** → `individual_question_escrow_result`,
  authenticated EXECUTE ✅. core `refund_individual_question_hold` 는 service_role 전용(앱 호출 금지).
- 로직: 소유자 검사(`NOT_QUESTION_OWNER` 42501) → 이미 refunded/refund_ledger 존재 시
  hold 위임(멱등 성공 경로) → 허용 상태 `escrowed|open|assigned|claimed` 외에는
  `REFUND_NOT_ALLOWED: status=<x>`(P0001) → 실패 시 `INDIVIDUAL_QUESTION_REFUND_FAILED:<code>:<msg>`.
  기타: `AUTH_REQUIRED`(28000), `INVALID_INPUT`(22023).

### 리뷰 — 서버 가드 실정의
- RLS: INSERT 는 학생 본인 + `check_review_eligibility`(유료 결제 2회 이상), UPDATE 는
  mentor/admin 만(학생 UPDATE 정책 없음), 공개 SELECT 는 `is_hidden=false AND is_blinded=false`.
- 트리거 `reviews_enforce_update`: 보호 컬럼(id/mentor_id/author_id/rating/body/
  subscription_count/created_at) 불변 · **멘토 답글 1회만**(재수정 서버 거부) ·
  멘토는 moderation 필드 변경 불가 · admin 은 답글 변경 불가.
- → 앱 INSERT payload 정본: `mentor_id, author_id, rating, body` (student_id/content 금지).

### 최소 앱 버전 (Track E) — 재확인 결과 여전히 부재
- `%version%`/`app_config` 테이블·함수 0건 → **WAITING_SERVER_GATE 유지**.
  요구 계약은 `docs/APP_V16_MIN_VERSION_SERVER_REQUIREMENT.md` 참조.
- `comments` 정본 테이블 RLS 는 준비돼 있으나(visible/own/admin 7정책) 버전 게이트 없이는 전환 금지.

## 4.7 최종 수렴 세션 (2026-07-21) — 서버 게이트 3종 staging 배포 완료 (SQL 161~163)

### 계정 탈퇴 self RPC (SQL 161) — WAITING_SERVER_API 해소
- `account_deletion_request_self(p_cancelable_minutes=30, p_dry_run=false)` →
  `{ok, existing, job_id, state, cancelable_until, dry_run}` — 사용자 ID 는 서버가
  auth.uid() 로만 도출(p_user_id 인자 없음), advisory xact lock 으로 동시 요청 직렬화.
- `account_deletion_cancel_self()` → raw cancel 위임(NOT_FOUND|NOT_CANCELABLE|CANCEL_WINDOW_PASSED).
- `account_deletion_status_self()` → `{ok, exists, state, cancelable_until, write_blocked, can_cancel}`
  (worker 내부 정보 미반환).
- ACL: self 3종 authenticated/service_role. **raw request/cancel 은 service_role 전용 불변**
  (호출자–p_user_id 일치 검사가 없어 GRANT 금지 — 타인 job 조작 방지).

### 모바일 최소버전 정책 (SQL 162) — Track E 게이트 1 충족
- `mobile_app_version_policies(platform PK, min_supported_build int, latest_build int,
  minimum_version_name, store_url CHECK(HTTPS+Play/AppStore 호스트), message, updated_at)` —
  write 는 service_role 전용(RLS on·정책 0·테이블 권한 revoke).
- `get_mobile_app_version_policy(p_platform)` → jsonb, **anon+authenticated**(로그인 전 게이트),
  platform allowlist(INVALID_PLATFORM), 행 부재 시 비차단 기본값(min=1).
- seed: android/ios min=1/latest=1 — 현재 앱 비차단(실상향은 운영 절차로만).

### 게시판 댓글 정본 브리지 (SQL 163) — Track E 게이트 2 충족
- 실측: 웹·구 앱 모두 board 댓글을 `community_comments` 에 write, 양 테이블 0행(백필 불필요).
- **양방향 멱등 동기화**: legacy(board)↔`comments` (body↔content, status↔is_deleted,
  매핑 `comments.legacy_comment_id`/`community_comments.canonical_comment_id` 부분 UNIQUE,
  GUC 재귀 방지). DELETE 는 양방향 모두 soft 처리(자동 삭제 없음). 숏폼은 동기화 제외.
- 정본 write 가드: 최대 2-depth(`COMMENT_DEPTH_EXCEEDED`), 타 post 부모
  (`COMMENT_PARENT_POST_MISMATCH`), 보호필드 불변(`COMMENT_PROTECTED_FIELDS_IMMUTABLE` —
  content/is_deleted 만 수정 가능), 비관리자 hard DELETE 거부(`COMMENT_HARD_DELETE_FORBIDDEN`),
  legacy_comment_id 위조 거부.
- comment_count 는 기존 `trg_comments_refresh_count`(comments 기준)로 웹·신구 앱 일치.

## 5. 게이트 판정 요약

| 트랙 | 게이트 | 판정 |
|---|---|---|
| B. 질문방 원자 RPC + 첨부 보상 | 생성/append/confirm/오답/첨부 RPC + Storage DELETE 정책 | ✅ 충족 — 이번 세션 진행 |
| C. 알림·푸시 | device_tokens·deliveries·settings·전체읽음·토큰 등록/재소유/revoke RPC | ✅ **전부 충족**(register_device_token 이 계정 전환 원자 재소유 포함) — 세션 2 진행 |
| D. 계정 라이프사이클 | deletion jobs·request/cancel RPC·write_blocked | ✅ 충족 — 상태 모델링 이번 세션 |
| E. 댓글 정본·최소버전 | 최소버전 API | ❌ **미충족 → WAITING_SERVER_GATE** |
| F. 숏폼 scrap | CHECK + RLS | ✅ 충족 — 이번 세션 진행 |
| G. 과목 FK | 정본 catalog 확정 | ✅ catalog 확보 — code만 전송 정책으로 진행 |
