# Ssambership `api_app_v1` 접합부 계약 v1.0

- 확정일: 2026-07-28
- 대상 DB: Supabase project ref `lbeqxarxothkmzqvpudy`
- 성격: **S2 구현 전 고정 계약**. 이 문서는 SQL·앱 코드 적용 결과가 아니라 구현·검수 기준이다.
- Gate 판정 범위: Gate 4(`api_app_v1`)와 Gate 5(탈퇴 allowlist)

## 1. 확정 원칙

1. Production 데이터 정본은 하나이며 웹·앱 DB를 복제하지 않는다.
2. `api_app_v1`은 앱에서 허용할 최소 조회·명령만 노출한다.
3. 앱에서는 신규 회원가입, 신규 구독, 결제·충전, 구독 변경·해지, 신규 개별질문 결제를 제공하지 않는다.
4. 커뮤니티 게시판은 웹·앱에서 글·댓글·반응뿐 아니라 **이미지 읽기와 쓰기까지 사용자 관점에서 동등**해야 한다.
5. 사용자 ID는 함수 내부에서 `auth.uid()`로 도출한다. 앱이 `p_user_id`를 보내는 계약은 만들지 않는다.
6. 모든 신규 쓰기 함수는 `SECURITY DEFINER`, 빈 `search_path`, 완전 수식 객체명, 고정 반환 형상 및 멱등 규약을 사용한다.
7. 현재 `public` 객체는 구버전 앱 종료 전 삭제·이동하지 않는다. S2는 추가형 스트랭글러로 시작한다.

## 2. AS-IS 실측 기준

2026-07-28 라이브 DB 기준:

- `api_app_v1`, `api_web_v1`, `private/core_private` 스키마는 아직 없다.
- 앱이 호출하는 `public` RPC 27종은 모두 실재하며 `authenticated` 실행 가능하다.
- 앱은 `public` 테이블 24종을 직접 사용한다.
- `mentor_student_rooms`는 참가자 SELECT만 허용하고 앱의 INSERT/UPDATE는 닫혀 있다.
- `qna_create_free_question_thread(...)`는 자격·한도·당사자를 재검사하고 스레드를 원자 생성하지만, **방 생성은 하지 않는다**.
- `community_posts.image_urls`는 `text[]`이며 신규 정본 값은 `community-post-images/{uid}/{object}` 형식의 Storage 참조다.
- `community-post-images`는 private bucket, 장당 5 MiB, MIME은 JPEG/PNG/WebP/GIF이며 본인 UID 첫 경로 세그먼트에만 쓰기 가능하다.
- `account_deletion_request_self(...)`는 잔액이 있으면 `{ok:false, code:"FORFEIT_CONSENT_REQUIRED", balance_cents}`를 반환하고 job을 만들지 않는다.
- `account_deletion_request_self_consented(...)`는 현재 `authenticated` 실행 가능하지만 앱 코드 사용처는 0건이다.

## 3. S2 신규 객체 목록

### 3.1 외부 노출 스키마

```sql
api_app_v1
```

Supabase Data API exposed schema에 추가하되 다음 기본 권한을 적용한다.

```sql
REVOKE ALL ON SCHEMA api_app_v1 FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA api_app_v1 TO authenticated;
```

로그인 전 동작이 필요한 버전 정책·멘토 공개 조회는 §8의 기존 `public` 호환 경로를 유지한다. 신규 `api_app_v1` v1에는 anon 쓰기를 만들지 않는다.

### 3.2 View

#### `api_app_v1.community_posts_v1`

목적: 앱 게시판 목록·상세·내 글이 동일한 필드 계약으로 `image_refs`를 읽게 한다.

```text
id uuid
author_id uuid
title text
body text
category text
image_refs text[]
author_label text
author_role text
like_count integer
comment_count integer
view_count integer
status text
created_at timestamptz
updated_at timestamptz
```

규약:

- `body = coalesce(content, body)`로 과도기 컬럼을 한 번만 수렴한다.
- `image_refs = coalesce(image_urls, '{}')`; 필드명으로 영구 URL이라는 오해를 제거한다.
- `deleted_at is null`이고 `status='published'`이거나 호출자 본인 글만 반환한다.
- `author_id`는 차단 필터·본인 글 판정에만 사용하고 UI에 직접 표시하지 않는다.
- `WITH (security_invoker=true)`로 만들고 기반 RLS를 그대로 적용한다.
- DML은 금지한다. 쓰기는 아래 RPC만 사용한다.

권한:

```sql
REVOKE ALL ON api_app_v1.community_posts_v1 FROM PUBLIC, anon;
GRANT SELECT ON api_app_v1.community_posts_v1 TO authenticated;
```

### 3.3 Function

| 함수 | 시그니처 | 반환 | 역할 |
|---|---|---|---|
| `api_app_v1.ensure_free_question_room` | `(p_mentor_id uuid)` | `jsonb` | 무료질문 또는 활성 구독 자격을 검사하고 학생–멘토 방을 원자적으로 조회·생성 |
| `api_app_v1.qna_create_question_thread` | `(p_room_id uuid, p_title text, p_subject text default null, p_topic text default null, p_first_message_body text default null)` | `jsonb` | 기존 정본 `public.qna_create_question_thread`의 안정된 앱 래퍼 |
| `api_app_v1.community_post_create` | `(p_title text, p_body text, p_category text, p_image_refs text[] default '{}', p_status text default 'published', p_idempotency_key uuid)` | `jsonb` | 게시글·이미지 ref를 함께 finalize |
| `api_app_v1.community_post_update` | `(p_post_id uuid, p_title text, p_body text, p_category text, p_image_refs text[] default '{}', p_status text default 'published', p_expected_updated_at timestamptz)` | `jsonb` | 본인 글 수정, 낙관적 충돌 검사, 제거 이미지 ref 반환 |
| `api_app_v1.community_post_soft_delete` | `(p_post_id uuid)` | `jsonb` | 본인 글 soft-delete; hard delete 금지 |

공통 권한:

```sql
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA api_app_v1 FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION api_app_v1.ensure_free_question_room(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION api_app_v1.qna_create_question_thread(uuid,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION api_app_v1.community_post_create(text,text,text,text[],text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION api_app_v1.community_post_update(uuid,text,text,text,text[],text,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION api_app_v1.community_post_soft_delete(uuid) TO authenticated;
```

`service_role`은 앱 공개 계약의 호출자에 포함하지 않는다. DB 소유자·마이그레이션 역할의 권한은 별도 운영 영역에서 관리한다.

공통 반환 envelope:

```json
{"ok": true, "contract_version": 1, "...": "..."}
{"ok": false, "contract_version": 1, "code": "STABLE_DOMAIN_CODE", "...": "..."}
```

예상 가능한 도메인 거부는 위 envelope로 반환한다. 연결 실패·timeout·예상 밖 SQL 오류는 성공으로 바꾸지 않고 오류로 전파한다.

## 4. 무료질문 방 확보 계약

### 4.1 성공 반환

```json
{
  "ok": true,
  "contract_version": 1,
  "room_id": "uuid",
  "created": true,
  "entitlement": "free"
}
```

`created`는 이번 호출이 방을 만들었는지 표시한다. `entitlement`는 `free|subscription`이다.

### 4.2 원자성

함수는 다음을 한 트랜잭션에서 수행한다.

1. `auth.uid()` 및 학생 역할 확인
2. 계정 상태·탈퇴 write-block 확인
3. 승인된 멘토·상호 차단 여부 확인
4. 학생 행 잠금 및 활성 구독/무료질문 자격 확인
5. `(student_id, mentor_id)` 기존 방 조회
6. 없으면 `INSERT ... ON CONFLICT (student_id, mentor_id) DO NOTHING`
7. 최종 방을 재조회해 반환

방 확보는 무료질문권을 소비하지 않는다. 실제 소비는 이어지는 `api_app_v1.qna_create_question_thread`가 기존 정본과 동일하게 스레드 생성과 `free_question_usage.thread_id` 기록을 한 트랜잭션에서 처리한다. 따라서 방 확보 후 자격이 바뀌어도 최종 생성 RPC가 다시 거부한다.

### 4.3 안정 오류코드

| code | 의미 | 앱 처리 |
|---|---|---|
| `AUTH_REQUIRED` | 세션 없음 | 로그인 화면 |
| `ROLE_NOT_STUDENT` | 학생이 아님 | CTA 숨김 |
| `ACCOUNT_BANNED` | 영구 제한 | 차단 화면 |
| `ACCOUNT_SUSPENDED` | 일시 제한 | 차단 화면 |
| `ACCOUNT_DELETION_IN_PROGRESS` | 탈퇴 처리 중 | 차단 화면 |
| `MENTOR_NOT_FOUND` | 멘토 없음 | 상세 새로고침 |
| `MENTOR_NOT_APPROVED` | 미승인 멘토 | CTA 비활성 |
| `BLOCKED` | 상호 차단 | CTA 비활성 |
| `FREE_QUOTA_EXPIRED` | 가입 후 무료 기간 만료 | 안내 |
| `FREE_QUOTA_TOTAL_EXHAUSTED` | 전역 무료 한도 소진 | 안내 |
| `FREE_QUOTA_MENTOR_EXHAUSTED` | 해당 멘토 한도 소진 | 안내 |
| `ROOM_ENSURE_FAILED` | 최종 방 확보 실패 | 재시도 가능 오류 |

스레드 생성 래퍼는 기존 정본 오류인 `TITLE_REQUIRED`, `ROOM_NOT_FOUND`, `NOT_ROOM_PARTY`, `MENTOR_CANNOT_CREATE_THREAD`, `WEEKLY_LIMIT_EXHAUSTED` 및 위 자격 오류를 그대로 안정 코드로 전달한다.

## 5. 커뮤니티 이미지 읽기 계약

1. View의 `image_refs`를 순서대로 읽는다.
2. 정상 신규 ref는 반드시 `community-post-images/{uid}/{object}` 형식이다.
3. 앱은 ref를 `{bucket, path}`로 분해하고 Supabase Storage `createSignedUrl(path, 3600)`로 표시 시점 URL을 만든다.
4. 서명 URL은 메모리 캐시에만 두고 DB·로컬 영구 저장소에 다시 저장하지 않는다.
5. URL 만료·서명 실패 시 해당 이미지만 재서명하며 글 본문은 계속 표시한다.
6. 과거 `https://.../object/sign/community-post-images/...` 값은 path를 추출해 다시 서명하는 읽기 호환을 유지한다.
7. 파싱 불가 ref는 이미지 하나만 숨기고 구조화 로그를 남긴다.

## 6. 커뮤니티 이미지 쓰기 계약

### 6.1 업로드

- 최대 5장
- 장당 최대 5 MiB
- `image/jpeg`, `image/png`, `image/webp`, `image/gif`
- 경로: `{auth.uid()}/{uuid}-{safe_name}.{ext}`
- `upsert=false`
- DB 저장 ref: `community-post-images/{path}`

앱은 로컬 MIME·확장자·magic bytes를 검사하고, Storage bucket 제한을 서버 측 2차 검증으로 사용한다.

### 6.2 Finalize 검증

`community_post_create/update`는 클라이언트가 보낸 `author_id`, `author_role`, `author_label`을 받지 않는다. 함수가 `auth.uid()`와 `public.users`에서 도출한다.

각 ref에 대해 다음을 모두 확인한다.

- 허용 버킷인지
- path 첫 세그먼트가 `auth.uid()`인지
- `storage.objects`에 실제 객체가 있는지
- 소유자·MIME·크기가 계약과 맞는지
- ref 수가 5 이하인지

제목·본문·카테고리·연락처 마스킹·금지 문구는 웹과 같은 단일 검증 규칙을 사용한다. 앱 전용으로 약한 규칙을 만들지 않는다.

### 6.3 멱등·보상

- create의 `p_idempotency_key`는 필수이며 `(author_id, create_idempotency_key)` 기준으로 멱등이다.
- 멱등 재생 성공은 기존 `post_id`와 `idempotent_replay=true`를 반환한다.
- 업로드 중 하나가 실패하면 그 요청에서 이미 올린 객체를 즉시 삭제한다.
- DB finalize 실패·응답 불명확이면 이번 요청 신규 객체를 보상 삭제하고, 글 목록에서 idempotency key를 재조회해 성공 여부를 확정한다.
- update 성공은 `removed_image_refs`를 반환한다. 앱은 commit 이후 제거된 구객체를 best-effort 삭제한다.
- 보상 삭제 실패는 사용자 성공을 뒤집지 않고 orphan 정리 대상으로 기록한다.
- soft delete는 게시글 행과 이미지 참조를 감사 목적으로 보존한다. 실제 객체 purge는 계정삭제·보존정책 작업이 담당한다.

### 6.4 안정 오류코드

| code | 의미 |
|---|---|
| `AUTH_REQUIRED` | 세션 없음 |
| `ROLE_NOT_ALLOWED` | 학생·멘토가 아님 |
| `ACCOUNT_BANNED` / `ACCOUNT_SUSPENDED` / `ACCOUNT_DELETION_IN_PROGRESS` | 계정 쓰기 차단 |
| `TITLE_REQUIRED` | 제목 없음 |
| `BODY_TOO_SHORT` | 공개 글 본문 10자 미만 |
| `CATEGORY_INVALID` | `study|school|career|college|free` 이외 |
| `POLICY_RESTRICTED` | 금지 문구·정책 위반 |
| `IMAGE_COUNT_EXCEEDED` | 5장 초과 |
| `IMAGE_REF_INVALID` | ref 파싱 실패·타 버킷 |
| `IMAGE_NOT_OWNED` | UID prefix·소유자 불일치 |
| `IMAGE_OBJECT_NOT_FOUND` | Storage 객체 없음 |
| `IMAGE_MIME_NOT_ALLOWED` | 허용 MIME 아님 |
| `IMAGE_SIZE_EXCEEDED` | 5 MiB 초과 |
| `POST_NOT_FOUND_OR_NOT_OWNED` | 비존재·타인 글·삭제 글 |
| `UPDATE_CONFLICT` | `updated_at` 불일치 |

## 7. 탈퇴 allowlist 고정

### 7.1 앱에서 허용

| 객체 | 상태 | 계약 |
|---|---|---|
| `public.account_deletion_request_self(integer, boolean)` | 호환 허용 | 잔액 0일 때만 앱에서 job 접수 가능. `auth.uid()` 자체 도출 |
| `public.account_deletion_status_self()` | 호환 허용 | 본인 상태 조회 |
| `public.account_deletion_cancel_self()` | 호환 허용 | 취소창 내 본인 요청 취소 |
| `public.account_deletion_write_blocked(uuid)` | 호환 허용 | 현재 앱 계정상태 게이트. S2 후 self/no-argument wrapper로 교체 |

### 7.2 앱에서 명시적으로 제외

```text
public.account_deletion_request_self_consented(
  p_cancelable_minutes integer,
  p_dry_run boolean,
  p_acknowledged_balance_cents bigint
)
```

- `api_app_v1` wrapper를 만들지 않는다.
- 앱 코드에서 호출하지 않는다.
- 앱에서 잔액 소멸 동의·몰수 금액 확정 UI를 만들지 않는다.
- 웹은 현재처럼 service-role 전용 `public.account_deletion_request_consented(...)`를 사용한다.

결제·충전·신규 구독·구독 변경·해지·환불 확정·관리자·worker RPC도 전부 앱 allowlist 밖이다.

### 7.3 `FORFEIT_CONSENT_REQUIRED` 앱 처리

`account_deletion_request_self` 응답이 다음과 같으면:

```json
{"ok": false, "code": "FORFEIT_CONSENT_REQUIRED", "balance_cents": 12345}
```

앱은 다음 순서만 수행한다.

1. 로컬 성공·pending 상태를 만들지 않는다.
2. 로그아웃하지 않는다.
3. 잔액이 있어 웹에서 환불 또는 소멸 동의가 필요하다고 안내한다.
4. 기존 `WebBridge.openAccountDelete()`로 `https://ssambership.com/account/delete?src=app`을 외부 브라우저에서 연다.

`FORFEIT_CONSENT_STALE`은 현 앱 호출 경로에서 도달하지 않지만 방어적으로 같은 웹 유도를 한다. 앱이 acknowledged balance를 재전송하는 흐름은 만들지 않는다.

### 7.4 2단 기술 차단 일정

| 시점 | 조건 | 조치 |
|---|---|---|
| T0 | 본 계약 확정 | consented RPC를 신규 allowlist에서 제외. 현재 `public` authenticated GRANT는 구버전 안전을 위해 유지 |
| T1 | `FORFEIT_CONSENT_REQUIRED` 웹 유도 분기가 포함된 앱 버전 `V_fix`가 스토어에 100% 배포 | `get_mobile_app_version_policy`의 권장 버전을 `V_fix` 이상으로 설정 |
| T2 | T1 후 14일 이상, 치명 결함 없음 | 최소 지원 버전을 `V_fix`로 올려 구버전 앱을 강제 업데이트 |
| T3 | T2 후 7일 유예, 구버전 진입 차단 확인 | `authenticated`의 `account_deletion_request_self_consented(integer,boolean,bigint)` EXECUTE 회수 후 함수를 `core_private`로 이동 |

T3 실행 전 웹·앱 저장소 전체 호출 0건과 DB 감사 로그를 다시 확인한다. rollback은 함수를 원래 스키마로 복귀하고 `authenticated` GRANT를 복원하는 별도 migration으로만 수행한다.

## 8. 기존 앱 RPC 호환표

아래 27종은 라이브 DB와 앱 코드에서 확인한 현재 표면이다. S2 동안 삭제·시그니처 교체를 금지한다. 신규 앱은 단계적으로 `api_app_v1` wrapper로 이동한다.

| 기존 `public` 함수 | 현재 시그니처 | 반환 | S2 판정 |
|---|---|---|---|
| `account_deletion_cancel_self` | `()` | `jsonb` | 허용·유지 |
| `account_deletion_request_self` | `(integer, boolean)` | `jsonb` | 허용·FORFEIT 웹 유도 필수 |
| `account_deletion_status_self` | `()` | `jsonb` | 허용·유지 |
| `account_deletion_write_blocked` | `(uuid)` | `boolean` | 임시 허용·향후 self wrapper |
| `add_individual_question_attachment` | `(uuid, text, text, text, uuid)` | `jsonb` | 허용 |
| `answer_individual_question` | `(uuid, text)` | `SETOF individual_questions` | 허용 |
| `claim_individual_question_as_mentor` | `(uuid)` | `individual_question_escrow_result` | 허용 |
| `create_individual_question_as_student` | `(text, text, text, integer, uuid, text)` | `SETOF individual_questions` | **신규 계약 제외**·구버전 호환만 유지 |
| `get_mentor_avg_response_hours` | `(uuid)` | `numeric` | 공개 읽기 호환 |
| `get_mentor_student_nicknames` | `(uuid[])` | `TABLE(...)` | 허용 |
| `get_mobile_app_version_policy` | `(text)` | `jsonb` | 로그인 전 버전 게이트 유지 |
| `get_weekly_question_usage` | `(uuid, uuid)` | `json` | 임시 허용·향후 student self 도출 |
| `increment_community_post_view` | `(uuid)` | `void` | 공개 읽기 보조 유지 |
| `increment_shortform_post_view` | `(uuid)` | `void` | 공개 읽기 보조 유지 |
| `list_open_individual_questions_for_mentor` | `(integer)` | `TABLE(...)` | 허용 |
| `mark_all_notifications_read` | `()` | `integer` | 허용 |
| `mentor_directory_list_v2` | `(integer)` | `TABLE(...)` | 공개 읽기 호환 |
| `mentor_profiles_for_directory_v2` | `(uuid[])` | `TABLE(...)` | 공개 읽기 호환 |
| `mentor_user_public_v2` | `(uuid)` | `TABLE(...)` | 공개 읽기 호환 |
| `qna_append_message` | `(uuid, text)` | `jsonb` | 허용 |
| `qna_confirm_thread` | `(uuid)` | `jsonb` | 허용 |
| `qna_create_free_question_thread` | `(uuid, text, text, text, text)` | `jsonb` | 허용·신규 방 ensure와 결합 |
| `qna_create_question_thread` | `(uuid, text, text, text, text)` | `jsonb` | 허용·target wrapper |
| `qna_flag_wrong_answer` | `(uuid, boolean)` | `jsonb` | 허용 |
| `qna_register_attachment` | `(uuid, text, text, text, uuid)` | `jsonb` | 허용 |
| `refund_individual_question` | `(uuid)` | `individual_question_escrow_result` | 기존 질문 lifecycle만 허용 |
| `release_individual_question` | `(uuid)` | `individual_question_escrow_result` | 기존 질문 lifecycle만 허용 |

현재 27종 중 로그인 전 호환 함수는 별도 anon GRANT를 유지할 수 있으나, 신규 쓰기 함수에는 anon을 허용하지 않는다.

## 9. 직접 테이블 호환표

구버전 앱이 사용하는 24종은 S2에서 즉시 revoke하지 않는다.

```text
cash_ledger
cash_wallets
community_posts
connection_notes
content_reports
free_question_usage
individual_question_attachments
individual_question_messages
individual_questions
mentor_individual_question_pricing
mentor_plans
mentor_profiles
mentor_student_rooms
notifications
post_reactions
question_attachments
question_messages
question_threads
reviews
shortform_posts
shortform_reactions
subscription_settlement_items
subscriptions
users
```

`cash_ledger`, `cash_wallets`, `subscriptions`, `subscription_settlement_items`는 앱에서 **SELECT 전용**이다. S2는 새 GRANT를 추가하지 않고, S3에서 신규 앱 호출을 view/RPC로 옮긴 뒤 구버전 cutoff 이후 direct 권한을 기능 단위로 회수한다.

## 10. 구현·검수 완료 조건

### Gate 4

- [ ] 위 스키마·view·5개 함수가 timestamp migration으로 생성됨
- [ ] 함수 시그니처·JSON envelope·오류코드 contract test 통과
- [ ] `PUBLIC`/`anon` revoke와 `authenticated` 최소 GRANT 실측
- [ ] 방 없는 학생이 앱에서 방을 확보하고 무료질문 스레드를 만들 수 있음
- [ ] 동일 학생–멘토 동시 호출에서 방이 1개만 존재
- [ ] 웹 이미지 글이 앱 목록·상세에 표시됨
- [ ] 앱 이미지 작성 0장·1장·5장, MIME/크기/타인 ref 공격, DB 실패 보상 삭제 통과
- [ ] Realtime 미수신 시 기존 재조회 fallback 유지

### Gate 5

- [ ] 앱이 `FORFEIT_CONSENT_REQUIRED` payload를 버리지 않고 웹 유도로 분기
- [ ] `FORFEIT_CONSENT_STALE` 방어 fallback도 웹 유도
- [ ] 앱 코드·`api_app_v1`에 consented RPC 참조 0건
- [ ] 앱에서 잔액 소멸 동의·결제·구독 변경/해지 UI 0건
- [ ] `V_fix`와 T1~T3 운영 일정을 release checklist에 기록

이 문서가 Gate 4·5의 **설계 증거**이며, 체크박스는 S2/S3 구현·릴리스 검수 게이트다.
