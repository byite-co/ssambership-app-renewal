# Ssambership `api_app_v1` 접합부 계약 v1.1

- 확정일: 2026-07-29
- 대상 DB: Supabase project ref `lbeqxarxothkmzqvpudy`
- 성격: **S2 구현 전 고정 계약** — v1.0(2026-07-28 확정)의 rev 8 동기 개정본. 이 문서는 SQL·앱 코드 적용 결과가 아니라 구현·검수 기준이다.
- Gate 판정 범위: Gate 4(`api_app_v1`)와 Gate 5(탈퇴 allowlist)
- 원문: `docs/contracts/api_app_v1_contract_v1_0.md` (내용 무변경 보존본, 382행 / 19,814바이트 / SHA-256 `59b37c42d5b4ca81e3cc2c775a4760396fa484299d99d3b78a179facd5ae6c77`)
- 공용 계약 정본(웹 최종 계약 v1.1): `byite-co/ssambership_web` 브랜치 `claude/api-web-v1-1-contract-20260729-v2` 최종 커밋 `53120d026508f8f75d5eb00dfaee4bde278deb1c`의 `docs/contracts/api_web_v1_contract_v1_1.md` (2,826행 / 293,982바이트 / SHA-256 `0df3a98d2fce896df329b0f423dddedcf9d2455142a8b1b5d04fba2bb2a3511a`) — 공용 함수·시그니처·오류코드·GRANT·envelope·공용 테스트 기대값의 정본은 이 문서다(웹 §19.5). *(v1.1 재동기: 구 정본 커밋 위에 F4 replay-first 판정 우선순위·§14.4 보상 삭제 규약 정정·T-CONC-10이 추가된 최신 정본으로 교체.)*
- 개정 지시 근거: 앱 rev 8 동기화 지시서 `docs/audit/S2_API_APP_V1_1_SYNC_DIRECTIVE_20260729.md` @ `02e1f7a5` 항목 1~10 · 웹 rev 8 정본 지시서 `docs/audit/s2_api_contract_v1_1_revision_directive_20260729.md` @ `7ec3b269`(웹 저장소) A~G.
- 판정: v1.0 Gate 4의 "문서 게이트 PASS"는 rev 8 A-1로 **소급 무효** — 본 문서 §10에서 재게이트. **S2-2 SQL 구현은 임시 NO-GO 유지**(본 계약은 문서 계약이며 이번 세션은 SQL을 작성하지 않는다).

**v1.0 → v1.1 개정 요약** (각 항목의 rev 8 절 번호 역기입):

1. F4/F5 시그니처 재배열 — 필수 인자 선행·DEFAULT 후행, named notation 의무 (A-1, 앱 동기화 1) → §3.3
2. `SUBSCRIPTION_REFUND_PENDING` 오류코드 정합화 (앱 동기화 2, 웹 §9.3) → §4.3
3. 응답 envelope를 웹 §8과 동일 구조로 재기술 — "정본 `public` 함수가 envelope를 반환한다"는 v1.0의 가정 정정 (앱 동기화 3) → §3.3
4. 주간 사용량 조회 NULL-safe pair-party 가드 반영 — 앱 영향 없음 명기 (A-8, 앱 동기화 4) → §4.4
5. `HD-1` 커뮤니티 직접 쓰기 전면 잠금 게이트·앱 보상 DB DELETE 폐기·동일 멱등키 재시도·Storage 이미지 보상 삭제 유지 (C, 앱 동기화 5) → §6.3·§6.6
6. B-04 동결 — 금지어 검사 폐지, `POLICY_RESTRICTED` 예약 코드 (D, 앱 동기화 6) → §6.2·§6.4
7. B-07 blocker 해제 — 앱의 `mentor_profiles` 쓰기 없음 실측 (D, 앱 동기화 7) → §9
8. 공용 커뮤니티 내부 함수 대조표 추가 (B, 앱 동기화 8) → §12
9. 커뮤니티 작성 승인 멘토 전용·기존 학생 글 보존·숏폼 정책 정합화 (A-10, 앱 동기화 9) → §6.4·§6.5
10. F12 재생 계약 rev 8 동기 — 오류코드·room 의미론·테스트 A~H (A-5, 앱 동기화 10) → §11

## 1. 확정 원칙

1. Production 데이터 정본은 하나이며 웹·앱 DB를 복제하지 않는다.
2. `api_app_v1`은 앱에서 허용할 최소 조회·명령만 노출한다.
3. 앱에서는 신규 회원가입, 신규 구독, 결제·충전, 구독 변경·해지, 신규 개별질문 결제를 제공하지 않는다.
4. 커뮤니티 게시판은 웹·앱에서 글·댓글·반응뿐 아니라 **이미지 읽기와 쓰기까지 사용자 관점에서 동등**해야 한다.
5. 사용자 ID는 함수 내부에서 `auth.uid()`로 도출한다. 앱이 `p_user_id`를 보내는 계약은 만들지 않는다.
6. **(v1.1 범위 정정)** 외부 호출 가능한 `api_app_v1` 쓰기 wrapper는 `SECURITY DEFINER`, 빈 `search_path`, 완전 수식 객체명, 고정 반환 형상 및 멱등 규약을 사용한다. `core_private` 공용 구현부 B-1~B-4는 **의도적으로 `SECURITY INVOKER`** 이며(SECDEF wrapper의 소유자 권한 문맥에서 실행 — §3.4), 외부 EXECUTE 0·빈 `search_path`·완전 수식 객체명을 따른다. F10(`ensure_student_mentor_room`)은 내부 `SECURITY DEFINER`이나 외부 EXECUTE 0이다.
7. 현재 `public` 객체는 구버전 앱 종료 전 삭제·이동하지 않는다. S2는 추가형 스트랭글러로 시작한다.
8. **(v1.1 신설, rev 8 B)** 웹·앱이 공유하는 기능(커뮤니티 글 쓰기, 질문방 확보)의 판정 로직은 `core_private` 공용 구현부 한 곳에만 둔다. 웹 wrapper와 앱 wrapper는 같은 구현부를 호출하는 얇은 껍데기이며, 검증 규칙을 각자 복제하지 않는다. `core_private`는 Data API로 도달 불가하므로 **앱이 `core_private` 함수를 직접 `.rpc()`로 호출하는 계약은 존재하지 않는다.**
9. **(v1.1 신설, rev 8 A-10)** 커뮤니티 글 **작성 자격은 승인 멘토 전용**이다(웹·앱 동일). v1.0 원칙 4의 "사용자 관점 동등"은 유지되며, 작성 자격 규칙 자체가 웹·앱 동일하므로 동등성은 공용 구현부가 구조적으로 보장한다.

## 2. AS-IS 실측 기준

2026-07-28 라이브 DB 기준(v1.0 확정 시점 — 역사적 기준 보존):

- `api_app_v1`, `api_web_v1`, `private/core_private` 스키마는 아직 없다.
- 앱이 호출하는 `public` RPC 27종은 모두 실재하며 `authenticated` 실행 가능하다.
- 앱은 `public` 테이블 24종을 직접 사용한다.
- `mentor_student_rooms`는 참가자 SELECT만 허용하고 앱의 INSERT/UPDATE는 닫혀 있다.
- `qna_create_free_question_thread(...)`는 자격·한도·당사자를 재검사하고 스레드를 원자 생성하지만, **방 생성은 하지 않는다**.
- `community_posts.image_urls`는 `text[]`이며 신규 정본 값은 `community-post-images/{uid}/{object}` 형식의 Storage 참조다.
- `community-post-images`는 private bucket, 장당 5 MiB, MIME은 JPEG/PNG/WebP/GIF이며 본인 UID 첫 경로 세그먼트에만 쓰기 가능하다.
- `account_deletion_request_self(...)`는 잔액이 있으면 `{ok:false, code:"FORFEIT_CONSENT_REQUIRED", balance_cents}`를 반환하고 job을 만들지 않는다.
- `account_deletion_request_self_consented(...)`는 현재 `authenticated` 실행 가능하지만 앱 코드 사용처는 0건이다.

**v1.1 추가 실측(2026-07-29, 웹 정본 §19.4 — 읽기 전용):**

- 앱 RPC 27종 목록은 웹 정본 재실측과 **27/27 일치**, 직접 테이블 24종은 **24/24 일치**한다(웹 §19.4-A·B).
- `mentor_profiles`·`mentor_plans`에 대한 앱 접근은 총 2곳이며 **전부 SELECT**다(웹 §19.4-B — B-02 해소).
- 앱 커뮤니티 쓰기의 직접 테이블 경로 실측: `lib/features/community/data/community_write_repository.dart:204-210`(게시글 hard DELETE 보상), `board_author_gate.dart:183`(`deleteOwnPostForCompensation`) — §6.6 `HD-1` 전환 대상.
- 앱 프로필 수정은 `lib/features/mypage/data/profile_edit_repository.dart:30`의 `users` UPDATE 단일 호출뿐 — `mentor_profiles` 쓰기 없음(rev 8 D, B-07 해제 — §9).
- 숏폼 INSERT 정책 실측: `shortform_posts` INSERT 정책 `sf_insert_mentor` 1건, Storage INSERT 정책 `sfv_mentor_insert` 1건이 `shortform-videos`·`shortform-thumbnails` 2버킷을 함께 포괄(웹 §14.8 — §6.5).

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

**(v1.1 추가, rev 8 A-2·B)** `core_private` 스키마는 Data API에 노출하지 않으며 `anon`·`authenticated`·`service_role` 어느 역할에도 USAGE를 부여하지 않는다(웹 §10.1과 동일). 앱은 `core_private` 객체에 도달할 수 없고, 도달하는 계약을 만들지 않는다.

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

**(v1.1 개정 — rev 8 A-1, 앱 동기화 1·웹 §19.5-1)** v1.0의 F4/F5 시그니처는 DEFAULT 인자 뒤에 필수 인자(`p_idempotency_key uuid`, `p_expected_updated_at timestamptz`)를 배치해 PostgreSQL 42P13으로 `CREATE FUNCTION` 자체가 실패하는 **생성 불가 시그니처**였다(본 계약 §3.3이 그 원출처). v1.1은 필수 인자를 전부 선행, DEFAULT 인자를 전부 후행으로 재배열한다. 이 결함으로 v1.0 Gate 4의 "문서 게이트 PASS"는 소급 무효이며 §10에서 재게이트한다.

| 함수 | 시그니처 (v1.1 — 웹 §7 F2~F6과 동일) | 반환 | 역할 |
|---|---|---|---|
| `api_app_v1.ensure_free_question_room` | `(p_mentor_id uuid)` | `jsonb` | 무료질문 또는 활성 구독 자격을 검사하고 학생–멘토 방을 원자적으로 조회·생성. 웹 F2와 이름·시그니처·반환·오류코드 완전 동일 — 동일한 `core_private.ensure_student_mentor_room`(F10)을 호출하는 얇은 wrapper |
| `api_app_v1.qna_create_question_thread` | `(p_room_id uuid, p_title text, p_subject text DEFAULT NULL, p_topic text DEFAULT NULL, p_first_message_body text DEFAULT NULL)` | `jsonb` | 기존 정본 `public.qna_create_question_thread`의 안정된 앱 래퍼 — 정본 raise를 envelope로 변환(웹 F3과 동일 계약) |
| `api_app_v1.community_post_create` | `(p_title text, p_body text, p_category text, p_idempotency_key uuid, p_image_refs text[] DEFAULT '{}', p_status text DEFAULT 'published')` | `jsonb` | 게시글·이미지 ref를 함께 finalize — **rev 8 A-1 재배열** |
| `api_app_v1.community_post_update` | `(p_post_id uuid, p_title text, p_body text, p_category text, p_expected_updated_at timestamptz, p_image_refs text[] DEFAULT '{}', p_status text DEFAULT 'published')` | `jsonb` | 본인 글 수정, 낙관적 충돌 검사, 제거 이미지 ref 반환 — **rev 8 A-1 재배열** |
| `api_app_v1.community_post_soft_delete` | `(p_post_id uuid)` | `jsonb` | 본인 글 soft-delete; hard delete 금지 |

**호출 규약(rev 8 A-1):** 호출부는 위치 인자가 아니라 **named notation**(`p_title => …, p_idempotency_key => …`)을 사용한다. Supabase 클라이언트의 `.rpc()` 객체 인자는 named 호출이므로 이 규약과 자연 일치한다 — 계약으로 명시하는 이유는 SQL 직접 호출·테스트 코드에서 인자 순서 의존을 금지하기 위해서다.

**공용 구현부 위임(rev 8 B — 웹 §7 F4·F5·F6과 동일 구조):** 앱 F4/F5/F6(`community_post_create/update/soft_delete`)과 웹 동명 함수는 **같은 `core_private` 구현부**(§3.4)를 호출하는 얇은 `SECURITY DEFINER` wrapper다. 역할·승인·계정 상태·본문 검증은 구현부에서 수행하고, wrapper는 `auth.uid()` 도출 + envelope 전달만 한다 — 판정이 wrapper마다 갈라질 수 없다. 클라이언트가 보낸 `author_id`·`author_role`·`author_label`은 받지 않는다.

**F4 멱등 재생 판정 우선순위(replay-first — 웹 §7 F4와 동일, v1.1 재동기):** 재생 판정은 신규 쓰기 검증보다 **먼저**다. 웹·앱 wrapper가 동일한 B-1 구현부를 호출하므로 판정 순서도 동일하다.

1. `auth.uid()` 확인 및 author binding(`p_author_id = auth.uid()` 도출) **직후**, 역할·승인·계정 write-block·본문·이미지 ref 등 **신규 쓰기 검증보다 먼저** `(author_id, create_idempotency_key)`로 **기존 커밋 행을 조회**한다.
2. 기존 행이 있으면 — 새 쓰기와 Storage 삭제 **없이** — 기존 `post_id` + `idempotent_replay:true`를 반환한다(재생 성공은 현재 시점의 역할·승인·본문 재검증 결과에 좌우되지 않는다 — 이미 커밋된 사실의 멱등 확인이기 때문).
3. 기존 행이 **없을 때만** 신규 쓰기 검증(작성 자격·계정 상태·본문·이미지 ref)과 INSERT를 수행한다.
4. **단순 재호출 오류(연결 실패·timeout·예상 밖 SQL 예외 전파)는 "미커밋 확인"으로 간주하지 않는다** — 성공도 확정 실패도 아니므로 §6.3대로 객체를 보존한 채 재시도한다. "미커밋 확인"은 이 replay-first 조회가 기존 행 없음을 판정하고 신규 경로가 **확정 실패 envelope**(`ok:false` 도메인 거부) 또는 rollback으로 종결된 경우만이다. **별도 조회 RPC는 신설하지 않는다**(F4 재호출 자체가 조회를 겸한다).

공통 권한:

```sql
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA api_app_v1 FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION api_app_v1.ensure_free_question_room(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION api_app_v1.qna_create_question_thread(uuid,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION api_app_v1.community_post_create(text,text,text,uuid,text[],text) TO authenticated;
GRANT EXECUTE ON FUNCTION api_app_v1.community_post_update(uuid,text,text,text,timestamptz,text[],text) TO authenticated;
GRANT EXECUTE ON FUNCTION api_app_v1.community_post_soft_delete(uuid) TO authenticated;
```

`service_role`은 앱 공개 계약의 호출자에 포함하지 않는다. DB 소유자·마이그레이션 역할의 권한은 별도 운영 영역에서 관리한다. *(v1.1 주석: 웹 `api_web_v1` T2 함수는 웹 서버 코드 경로를 위해 `service_role` EXECUTE를 함께 부여하지만(웹 §10.3), 앱 `api_app_v1`은 앱 세션(`authenticated`)만이 호출자이므로 이 차이는 wrapper 객체별 호출자 계약의 의도적 차이다. 공용 내부 구현부의 GRANT는 §12에서 웹과 동일(외부 EXECUTE 0)함을 대조한다.)*

**공통 반환 envelope (v1.1 재기술 — 앱 동기화 3·웹 §19.5-3, 웹 §8과 동일 구조):**

```json
{"ok": true,  "contract_version": 1, "<도메인 필드>": "..."}
{"ok": false, "contract_version": 1, "code": "STABLE_DOMAIN_CODE", "<보조 필드>": "..."}
```

- `contract_version`은 **정수 `1`** 로 시작한다. 필드 추가는 버전을 올리지 않고, **필드 제거·의미 변경은 버전을 올린다.**
- `ok:false`에는 항상 `code`가 있다. `message`는 **선택**이며 사용자 노출 문구로 쓰지 않는다(디버깅용). 사용자 문구는 앱이 코드→문구 매핑으로 만든다.
- **정정(v1.0 가정 폐기):** 기존 정본 `public` 함수는 도메인 거부를 envelope가 아니라 `raise exception`으로 던진다(웹 §3.3 실측). envelope는 **`api_app_v1` wrapper가 정본의 raise를 잡아 변환**해 만든다. 정본이 이미 envelope를 반환한다고 가정하지 않는다.
- **오류를 성공으로 바꾸지 않는다(웹 §8.2):** 예상 가능한 도메인 거부만 `{ok:false, code}`로 반환한다. 사전에 없는 SQL 예외·statement/lock timeout·연결 실패는 삼키지 않고 **그대로 전파**한다. 멱등 재생(정상)은 `ok:true`에 `idempotent_replay:true` 등 재생 표시를 반드시 동반한다. 앱은 `ok` 필드가 없는 응답을 **성공으로 간주해서는 안 된다.**
- 웹 `api_web_v1` envelope와 **동일 형상**이다(웹 §8.1) → 공용 기능에서 클라이언트 분기 로직이 갈라지지 않는다.

**함수별 성공 반환 필드(웹 §8.3과 동일):**

| 함수 | 성공 필드 | 멱등·특수 |
|---|---|---|
| `ensure_free_question_room` | `room_id, created, entitlement` | `created:false` = 기존 방 재사용 |
| `qna_create_question_thread` | `thread_id, message_id, path, used_free_quota` | — |
| `community_post_create` | `post_id, idempotent_replay` | `idempotent_replay:true` = 멱등 재생 |
| `community_post_update` | `post_id, updated_at, removed_image_refs` | `UPDATE_CONFLICT` |
| `community_post_soft_delete` | `post_id, deleted_at` | 이미 삭제면 `ok:true` + `already_deleted:true` |

### 3.4 공용 내부 구현부 (v1.1 신설 — rev 8 B, 웹 §7 B-1~B-4·F10)

웹·앱 wrapper가 공유하는 `core_private` 구현부. **앱이 직접 호출하는 객체가 아니라**, 앱 wrapper의 `SECURITY DEFINER` 소유자 권한 문맥에서만 호출된다. 이름·시그니처·오류코드·GRANT는 웹 정본과 동일해야 하며 §12 대조표로 증명한다.

| # | 함수 (identity argument) | 반환 | 역할 |
|---|---|---|---|
| B-1 | `core_private.community_post_create_impl(p_author_id uuid, p_title text, p_body text, p_category text, p_image_refs text[], p_status text, p_idempotency_key uuid)` | `jsonb` | 게시글 생성 원자 구현부 — **replay-first 판정 수행**(author binding 직후·신규 쓰기 검증보다 먼저 `(author_id, create_idempotency_key)` 기존 커밋 행 조회, §3.3 — 웹 §7 F4와 판정 순서 동일) |
| B-2 | `core_private.community_post_update_impl(p_author_id uuid, p_post_id uuid, p_title text, p_body text, p_category text, p_image_refs text[], p_status text, p_expected_updated_at timestamptz)` | `jsonb` | 게시글 수정 원자 구현부 |
| B-3 | `core_private.community_post_soft_delete_impl(p_author_id uuid, p_post_id uuid)` | `jsonb` | soft-delete 구현부 |
| B-4 | `core_private.community_image_refs_validate(p_owner_id uuid, p_image_refs text[])` | `jsonb` | 공용 이미지 ref 검증기(§6.2의 검증 5종 수행, 실패 시 `{ok:false, code}`) |
| F10 | `core_private.ensure_student_mentor_room(p_student_id uuid, p_mentor_id uuid, p_payment_id uuid DEFAULT NULL, p_subscription_id uuid DEFAULT NULL, p_require_entitlement boolean DEFAULT true)` | `jsonb` | 방 확보 공용 구현부 — 웹 F2·앱 `ensure_free_question_room`·웹 F12 내부 경로가 전부 수렴 |

보안 속성(웹 §7·§10.3과 동일 — §12 대조 대상):

- B-1~B-4: **`SECURITY INVOKER`**(SECDEF wrapper의 소유자 권한 문맥에서 실행), `SET search_path = ''`, 모든 객체 참조 완전 수식, owner = migration 실행 역할. **GRANT: 없음** — `PUBLIC`·`anon`·`authenticated`·`service_role` 전부 EXECUTE 미부여. 함수 생성과 권한 회수는 같은 마이그레이션에서 수행한다.
- F10: **`SECURITY DEFINER`**, `SET search_path = ''`, 완전 수식 객체명, owner = migration 실행 역할. **EXECUTE: `PUBLIC`·`anon`·`authenticated`·`service_role` 전부 미부여** — 호출자는 SECDEF wrapper(웹 F2·웹 F12·앱 wrapper)의 소유자 권한 문맥뿐이다.
- F10이 `p_student_id`를 인자로 받는 이유(웹 §7 F10): 구독 확정(웹 F12 내부)은 학생 세션이 아닌 서버 컨텍스트에서 실행되므로 `auth.uid()`를 쓸 수 없다. 앱 경로에서는 **앱 wrapper가 `auth.uid()`를 넣어 호출**하며, 외부 역할 EXECUTE가 0이므로 클라이언트가 임의 `p_student_id`를 넣을 경로가 없다.
- `p_require_entitlement=true`(앱 wrapper·웹 F2 경로): 무료질문 자격 또는 활성 구독을 검사한다. `false`는 웹 F12 구독 확정 경로 전용이다.

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

함수는 다음을 한 트랜잭션에서 수행한다. **(v1.1 명시 — rev 8 B)** 아래 1~7은 앱 wrapper가 아니라 공용 구현부 `core_private.ensure_student_mentor_room`(F10, §3.4)이 수행하며, 웹 F2와 동일하다.

1. `auth.uid()` 및 학생 역할 확인
2. 계정 상태·탈퇴 write-block 확인
3. 승인된 멘토·상호 차단 여부 확인
4. 학생 행 잠금 및 활성 구독/무료질문 자격 확인
5. `(student_id, mentor_id)` 기존 방 조회
6. 없으면 `INSERT ... ON CONFLICT (student_id, mentor_id) DO NOTHING`
7. 최종 방을 재조회해 반환

방 확보는 무료질문권을 소비하지 않는다. 실제 소비는 이어지는 `api_app_v1.qna_create_question_thread`가 기존 정본과 동일하게 스레드 생성과 `free_question_usage.thread_id` 기록을 한 트랜잭션에서 처리한다. 따라서 방 확보 후 자격이 바뀌어도 최종 생성 RPC가 다시 거부한다. (웹 §13.2와 동일한 2단 구조.)

원자성 근거(웹 §13.1): `uq_msr_pair(student_id, mentor_id)` UNIQUE INDEX 실측. 동시 호출에서 방은 정확히 1개만 존재해야 한다(웹 T-CONC-01). `mentor_student_rooms`의 컬럼은 `id, student_id, mentor_id, payment_id, subscription_id, created_at, updated_at`으로 확정 — 컬럼 프로빙을 하지 않는다.

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

스레드 생성 래퍼(`api_app_v1.qna_create_question_thread`)는 기존 정본 오류인 `TITLE_REQUIRED`, `ROOM_NOT_FOUND`, `NOT_ROOM_PARTY`, `MENTOR_CANNOT_CREATE_THREAD`, `WEEKLY_LIMIT_EXHAUSTED`, **`SUBSCRIPTION_REFUND_PENDING`(v1.1 추가 — 앱 동기화 2·웹 §19.5-2: 구독 환불 진행 중. v1.0 목록에 누락돼 있던 정본 raise 동일명 코드, 웹 §9.3)** 및 위 자격 오류를 그대로 안정 코드로 전달한다.

**트리거 코드 수렴(v1.1 추가 — 웹 §9.8, XW-08):** 동시성 경합에서 트리거가 던지는 `FREE_QUESTION_EXPIRED`/`FREE_QUESTION_TOTAL_LIMIT`/`FREE_QUESTION_PER_MENTOR_LIMIT`/`FREE_QUESTION_STUDENT_NOT_FOUND`는 각각 `FREE_QUOTA_EXPIRED`/`FREE_QUOTA_TOTAL_EXHAUSTED`/`FREE_QUOTA_MENTOR_EXHAUSTED`/`FREE_QUOTA_STUDENT_NOT_FOUND`로 wrapper가 수렴시킨다 — 같은 상황에서 웹·앱이 같은 코드를 받는다.

### 4.4 주간 사용량 조회 하드닝 (v1.1 신설 — rev 8 A-8, 앱 동기화 4·웹 §19.5-5)

레거시 `public.get_weekly_question_usage(p_student_id, p_mentor_id)`는 웹 정본 §7 F1(M15)에 따라 첫머리에 **NULL-safe pair-party 가드**가 추가된다:

```sql
IF (auth.jwt() ->> 'role') IS DISTINCT FROM 'service_role'
   AND auth.uid() IS DISTINCT FROM p_student_id
   AND auth.uid() IS DISTINCT FROM p_mentor_id
THEN
  RAISE EXCEPTION 'NOT_PAIR_PARTY'
    USING ERRCODE = '42501';
END IF;
```

- `IN`·일반 `<>`는 NULL로 인해 예기치 않게 통과할 수 있으므로 금지 — **`IS DISTINCT FROM`만 사용**한다(웹 F1과 동일 형태 고정).
- **앱 영향 없음(계약 명기):** 앱의 이 RPC 호출은 전부 **로그인 학생 본인 ID**(`auth.uid() = p_student_id`)를 전달하므로 가드를 통과한다. `NOT_PAIR_PENDING` 같은 오기가 아니라 정확히 `NOT_PAIR_PARTY`/`42501`이며, 제3자 조합 호출만 차단된다. service_role은 통과한다.
- 앱은 이 함수의 `limit`/`week_start`/`week_end` 반환을 신뢰하고 한도를 재하드코딩하지 않는다(현행 유지). 한도 매핑 정본: `limited`=4, `standard`=9, `premium`=999, 주 경계는 `coalesce(subscriptions.started_at, created_at)` 기준 7일 롤링(웹 §7 F1).

## 5. 커뮤니티 이미지 읽기 계약

1. View의 `image_refs`를 순서대로 읽는다.
2. 정상 신규 ref는 반드시 `community-post-images/{uid}/{object}` 형식이다.
3. 앱은 ref를 `{bucket, path}`로 분해하고 Supabase Storage `createSignedUrl(path, 3600)`로 표시 시점 URL을 만든다.
4. 서명 URL은 메모리 캐시에만 두고 DB·로컬 영구 저장소에 다시 저장하지 않는다.
5. URL 만료·서명 실패 시 해당 이미지만 재서명하며 글 본문은 계속 표시한다.
6. 과거 `https://.../object/sign/community-post-images/...` 값은 path를 추출해 다시 서명하는 읽기 호환을 유지한다.
7. 파싱 불가 ref는 이미지 하나만 숨기고 구조화 로그를 남긴다.

(웹 §14.1·§14.2와 동일 — 동일 필드명·동일 형식·동일 TTL 3600초. 웹 §14.5 동등성 표 참조.)

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

각 ref에 대해 다음을 모두 확인한다. **(v1.1 명시 — rev 8 B)** 이 검증 5종은 공용 검증기 `core_private.community_image_refs_validate`(B-4, §3.4)가 수행하며 웹 F4/F5와 동일하다.

- 허용 버킷인지
- path 첫 세그먼트가 `auth.uid()`(= 호출 wrapper가 전달한 `p_owner_id`)인지
- `storage.objects`에 실제 객체가 있는지
- 소유자·MIME·크기가 계약과 맞는지
- ref 수가 5 이하인지

**본문 검증(v1.1 개정 — rev 8 D, B-04 동결, 앱 동기화 6):** 제목·본문·카테고리 검증과 **연락처 마스킹**은 웹과 같은 단일 검증 규칙(공용 구현부)을 사용한다. 앱 전용으로 약한 규칙을 만들지 않는다. **금지어 검사는 폐지가 확정**됐고(웹 실측 `lib/safety/trustSafetyText.ts` — 의도적 폐지), 공용 검증부는 **마스킹만 수행**한다. `POLICY_RESTRICTED`는 **예약 코드이며 발생하지 않는다**(§6.4). 오너가 금지어를 복원하면 additive 개정으로 처리한다.

### 6.3 멱등·보상

- create의 `p_idempotency_key`는 필수이며 `(author_id, create_idempotency_key)` 기준으로 멱등이다(UNIQUE INDEX `community_posts_author_idem_key` 실측 — 웹 §14.4).
- 멱등 재생 성공은 기존 `post_id`와 `idempotent_replay=true`를 반환한다.
- **(v1.1 전면 정정 — 웹 §14.4 재호출 선행·보상 삭제 후행, 웹 §19.5 #8) 응답 불명확·응답 유실은 실패 확정이 아니다.** 보상 삭제는 다음 4분기로 고정한다. v1.0의 "글 목록에서 idempotency key를 재조회" 방식과 v1.1 구판의 "불명확 시 선삭제" 순서는 모두 이 규약으로 대체한다.
  - **업로드 단계 실패:** 이미 업로드한 이번 요청 신규 Storage 객체를 **즉시 보상 삭제**한다(Storage 보상 삭제 — **유지**).
  - **DB finalize의 확정 실패·rollback 확인:** 신규 Storage 객체를 보상 삭제한다(트랜잭션 롤백이므로 지울 DB 행은 없다).
  - **DB finalize 응답 불명확·응답 유실:** Storage 객체를 **삭제하지 말고**, **동일 멱등키로 `community_post_create`(F4)를 먼저 재호출**한다 — 이것이 생성 복구의 **정본 경로**다(rev 8 C).
    - 재호출 성공 또는 기존 `post_id` 반환(멱등 재생): 게시글이 커밋된 것이므로 **객체를 유지**한다(먼저 지우면 커밋된 글의 image ref가 깨진다).
    - 확정 실패 및 게시물 미커밋 확인: **그때** 신규 객체를 보상 삭제한다. **"미커밋 확인"의 판정 주체는 §3.3 F4의 replay-first 판정이다** — 재호출이 `(author_id, create_idempotency_key)` 기존 행 없음을 판정하고 신규 경로에서 확정 실패 envelope(`ok:false` 도메인 거부) 또는 rollback으로 종결된 경우만 해당한다. **단순 재호출 오류(연결 실패·timeout·예상 밖 예외)는 미커밋 확인이 아니다** — 객체를 보존한 채 재시도한다. **별도 조회 RPC는 신설하지 않는다**(F4 재호출 자체가 조회를 겸한다).
  - **DB 게시글을 hard DELETE하는 보상 RPC·직접 DELETE 경로는 계속 금지한다**(보상 삭제 대체 RPC 신설도 하지 않는다 — 오너 확정).
- update 성공은 `removed_image_refs`를 반환한다. 앱은 commit 이후 제거된 구객체를 best-effort 삭제한다.
- 보상 삭제 실패는 사용자 성공을 뒤집지 않고 orphan 정리 대상으로 기록한다.
- soft delete는 게시글 행과 이미지 참조를 감사 목적으로 보존한다. 실제 객체 purge는 계정삭제·보존정책 작업이 담당한다.

### 6.4 안정 오류코드

**(v1.1 개정 — rev 8 A-10, 앱 동기화 9·웹 §19.5-7)** v1.0의 `ROLE_NOT_ALLOWED`(= 학생·멘토가 아님 — 학생·멘토 모두 작성 허용) 정의는 **폐기한다.** 커뮤니티 작성은 승인 멘토 전용이며(§6.5), 역할 위반은 `ROLE_NOT_MENTOR`, 미승인 멘토는 `MENTOR_NOT_APPROVED`를 사용한다(웹 §9.2·§9.3·§9.4와 동일). `ROLE_NOT_ALLOWED` 코드 자체는 웹 §9.2 공통 사전에 존재하지만, **커뮤니티 작성 경로의 현행 허용 오류로는 더 이상 사용하지 않는다.**

| code | 의미 |
|---|---|
| `AUTH_REQUIRED` | 세션 없음 |
| `ROLE_NOT_MENTOR` | 멘토가 아님 (v1.1 — 구 `ROLE_NOT_ALLOWED` 정의 폐기·대체) |
| `MENTOR_NOT_APPROVED` | 멘토지만 미승인 (승인 판정은 `individual_question_user_is_approved_mentor(auth.uid())` 동일 헬퍼) |
| `ACCOUNT_BANNED` / `ACCOUNT_SUSPENDED` / `ACCOUNT_DELETION_IN_PROGRESS` | 계정 쓰기 차단 |
| `TITLE_REQUIRED` | 제목 없음 |
| `BODY_TOO_SHORT` | 공개 글 본문 10자 미만 |
| `CATEGORY_INVALID` | `study|school|career|college|free` 이외 |
| `POLICY_RESTRICTED` | **예약 코드 — v1.1에서 발생하지 않음**(금지어 검사 폐지, rev 8 D). 코드 사전에서 삭제하지 않는 이유는 웹 §9.4와의 코드 집합 동일성 유지와 금지어 복원 시 additive 재활성화 |
| `IMAGE_COUNT_EXCEEDED` | 5장 초과 |
| `IMAGE_REF_INVALID` | ref 파싱 실패·타 버킷 |
| `IMAGE_NOT_OWNED` | UID prefix·소유자 불일치 |
| `IMAGE_OBJECT_NOT_FOUND` | Storage 객체 없음 |
| `IMAGE_MIME_NOT_ALLOWED` | 허용 MIME 아님 |
| `IMAGE_SIZE_EXCEEDED` | 5 MiB 초과 |
| `POST_NOT_FOUND_OR_NOT_OWNED` | 비존재·타인 글·삭제 글 |
| `UPDATE_CONFLICT` | `updated_at` 불일치 |

### 6.5 커뮤니티 작성 자격 — 승인 멘토 전용 (v1.1 신설 — rev 8 A-10, 앱 동기화 9)

- F4 create는 **`users.role = 'mentor'`만 허용**한다. 위반 시 `ROLE_NOT_MENTOR`.
- 멘토지만 미승인이면 `MENTOR_NOT_APPROVED`. 승인 판정은 기존 헬퍼 **`individual_question_user_is_approved_mentor(auth.uid())`** 를 사용한다(정본 checkout과 동일 기준 — 판정식 이원화 금지).
- **관리자도 일반 작성 경로에서는 거부**한다(관리자 공지 경로는 별도 계약).
- **기존 학생 글 보존:** 열람 유지 · 수정(F5) 금지 · 작성자 본인의 F6 soft-delete 허용 · 관리자 moderation은 별도 경로(service_role) 유지. 파괴적 정리(일괄 삭제·비공개화)는 금지한다. 학생은 수정 대상 글을 신규 생성할 수 없으므로 기존 글 수정도 거부된다(`ROLE_NOT_MENTOR`).
- **앱 UI:** 학생 작성 CTA를 제거한다(앱 동기화 9).
- **숏폼(웹 §14.8 — rev 8 A-10, rev 7 실측 정정):** 숏폼 INSERT는 이미 멘토 전용이다 — `shortform_posts` INSERT 정책 **`sf_insert_mentor` 1건**과 Storage INSERT 정책 **`sfv_mentor_insert` 1건(2버킷 `shortform-videos`·`shortform-thumbnails` 포괄 — 버킷별 2개 정책으로 분해해 기술하지 않는다)** 을 커뮤니티 작성과 동일 승인 헬퍼로 정합화하되, `sfv_mentor_insert`의 기존 조건 4종을 **반드시 보존**한다: ① 대상 버킷 제한 ② 사용자 폴더 소유권(`storage.foldername(name)[1] = auth.uid()`) ③ `NOT account_deletion_write_blocked(auth.uid())` ④ authenticated 역할 범위.

### 6.6 `HD-1` — 커뮤니티 직접 쓰기 전면 잠금 게이트 (v1.1 신설 — rev 8 C, 앱 동기화 5, 웹 §14.7 M16)

`HD-1`은 `public.community_posts`에 대해 `REVOKE ALL ... FROM anon, authenticated` + `GRANT SELECT` 재부여, 쓰기 정책 6종(INSERT: `cp_write_self`·`로그인 유저 게시글 작성` / UPDATE: `cp_update_own`·`cp_update_self`·`본인 게시글 수정` / DELETE: `cp_delete_own`) 제거를 **M8에 얹지 않는 별도 마이그레이션(M16)** 으로 적용하는 전면 잠금이다. 적용 전 **웹·앱의 anon/authenticated 세션 경로에서 `community_posts` 직접 INSERT/UPDATE/DELETE 전부 0건**을 확인한다(전환 대상: 웹 = 직접 INSERT·UPDATE, 앱 = 직접 INSERT·보상 DELETE).

**앱 측 의무(순서 고정 — 웹 §14.7 확대 게이트 7단계와 동일):**

1. F4/F5/F6 전환 (직접 INSERT → `community_post_create`, 직접 UPDATE → `community_post_update`, 보상 DELETE → 폐기)
2. F4 응답 불명확 시 **동일 멱등키 재시도** 구현 — **재호출 전 Storage DELETE 0회** · **replay-first 판정**(§3.3) · **성공 재생 시 기존 객체 유지** · **확정 미커밋 판정 시에만 보상 삭제**(§6.3 4분기 규약) 포함
3. `deleteOwnPostForCompensation`(`board_author_gate.dart:183`) 제거
4. DB 게시글 hard DELETE 코드(`community_write_repository.dart:204-210`) 제거 — **Storage 신규 이미지 보상 삭제는 유지**
5. 직접 INSERT/UPDATE/DELETE 0건 실측
6. **service_role 예외 목록화:** 웹 `lib/admin/communityModerationCore.ts`의 관리자 moderation 직접 UPDATE는 의도된 예외로 유지(회수 대상 아님) — "저장소 전체 write 0건" 게이트 사용 금지
7. `HD-1` 적용 (M16)

보상 삭제 대체 RPC는 **만들지 않는다**(오너 확정 — F4가 트랜잭션 RPC + 멱등키 필수이므로, 응답 불명확 시 같은 멱등키 재호출이 정본 복구 경로다).

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

결제·충전·신규 구독·구독 변경·해지·환불 확정·관리자·worker RPC도 전부 앱 allowlist 밖이다. **(v1.1 추가 — rev 8 A-2)** 신규 자금 진입점 `api_web_v1.record_cash_topup_v2`(F11)·`api_web_v1.subscription_checkout_confirm_v2`(F12)는 **service_role 전용 EXECUTE**이므로 앱 anon 키·authenticated로 도달 불가하다 — 앱 금지 경계가 GRANT 수준에서 강제된다(웹 §19.1·§19.2).

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

`FORFEIT_CONSENT_STALE`은 현 앱 호출 경로에서 도달하지 않지만 방어적으로 같은 웹 유도를 한다. 앱이 acknowledged balance를 재전송하는 흐름은 만들지 않는다. (웹 §15.3: `/account/delete`는 `src=app`을 받아도 동일 관문을 적용한다.)

### 7.4 2단 기술 차단 일정

| 시점 | 조건 | 조치 |
|---|---|---|
| T0 | 본 계약 확정 | consented RPC를 신규 allowlist에서 제외. 현재 `public` authenticated GRANT는 구버전 안전을 위해 유지 |
| T1 | `FORFEIT_CONSENT_REQUIRED` 웹 유도 분기가 포함된 앱 버전 `V_fix`가 스토어에 100% 배포 | `get_mobile_app_version_policy`의 권장 버전을 `V_fix` 이상으로 설정 |
| T2 | T1 후 14일 이상, 치명 결함 없음 | 최소 지원 버전을 `V_fix`로 올려 구버전 앱을 강제 업데이트 |
| T3 | T2 후 7일 유예, 구버전 진입 차단 확인 | `authenticated`의 `account_deletion_request_self_consented(integer,boolean,bigint)` EXECUTE 회수 후 함수를 `core_private`로 이동 |

T3 실행 전 웹·앱 저장소 전체 호출 0건과 DB 감사 로그를 다시 확인한다. rollback은 함수를 원래 스키마로 복귀하고 `authenticated` GRANT를 복원하는 별도 migration으로만 수행한다.

## 8. 기존 앱 RPC 호환표

아래 27종은 라이브 DB와 앱 코드에서 확인한 현재 표면이다. S2 동안 삭제·시그니처 교체를 금지한다. 신규 앱은 단계적으로 `api_app_v1` wrapper로 이동한다. **(v1.1 확인 — 웹 §19.4-A: 2026-07-29 재실측에서 27/27 일치. S2 신규 계약은 이 표면을 건드리지 않는다.)**

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
| `get_weekly_question_usage` | `(uuid, uuid)` | `json` | 임시 허용·향후 student self 도출. **v1.1: M15 NULL-safe pair-party 가드 하드닝 — 앱 본인 ID 호출은 영향 없음(§4.4)** |
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

구버전 앱이 사용하는 24종은 S2에서 즉시 revoke하지 않는다. **(v1.1 확인 — 웹 §19.4-B: 2026-07-29 재실측에서 24/24 일치.)**

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

**v1.1 추가 — 조건부 회수의 앱 영향(웹 §10.6·§14.7):**

- **M11·M12(`mentor_profiles`·`mentor_plans` 테이블 단위 `REVOKE ALL` + `GRANT SELECT` 재부여):** 앱 접근은 2곳 모두 SELECT(`mentor_directory_repository.dart:175`, `question_room_read_repository.dart:67`)이므로 **앱을 깨뜨리지 않는다**(B-02 해소 — 웹 §19.4-B). 컬럼 단위 REVOKE는 무효라는 rev 8 A-3 확정에 따라 테이블 단위 전면 회수로 확정됐다.
- **M16(`HD-1` — `community_posts` `REVOKE ALL` + `GRANT SELECT`):** §6.6 게이트 7단계 완료 후에만 적용된다. 적용 후 앱 쓰기는 F4/F5/F6만 통과한다(SELECT·View 읽기는 유지).
- **B-07 해제(rev 8 D, 앱 동기화 7):** 앱 프로필 수정은 `lib/features/mypage/data/profile_edit_repository.dart:30`의 `users` UPDATE 단일 호출뿐 — **`mentor_profiles` 쓰기 없음**(실측). 웹 F7/F13 및 M11 회수는 앱 프로필 수정 경로와 충돌하지 않는다.

## 10. 구현·검수 완료 조건

### Gate 4

**v1.1 재게이트 선언(rev 8 A-1, 웹 §19.5-1·4):** v1.0 §3.3의 F4/F5는 DEFAULT 인자 뒤 필수 인자 배치로 `CREATE FUNCTION`이 42P13으로 실패하는 생성 불가 시그니처였다. 따라서 **v1.0 기준의 Gate 4 "문서 게이트 PASS" 판정은 소급 무효다.** v1.1 문서 게이트는 다음 근거로 재평가한다:

| 재게이트 항목 | v1.1 결과 | 근거 절 |
|---|---|---|
| F4/F5 시그니처 생성 가능성 (필수 선행·DEFAULT 후행) | **PASS** | §3.3 (웹 §7 F4·F5와 동일 재배열) |
| named notation 호출 규약 명시 | **PASS** | §3.3 |
| envelope 웹 정본 동일 구조 | **PASS** | §3.3 (웹 §8) |
| 오류코드 웹 정본 대조 (커뮤니티·질문방·`SUBSCRIPTION_REFUND_PENDING`) | **PASS** | §4.3·§6.4 (웹 §9.2~9.4) |
| GRANT·REVOKE identity argument 정합 | **PASS** | §3.3·§3.4 (웹 §10.3) |
| 공용 내부 함수 대조표 전건 일치 | **PASS** | §12 |
| 웹·앱 공용 계약 대조표 전건 일치 | **PASS** | §14 |

**v1.1 문서 게이트: PASS.** 아래 체크박스는 문서 게이트가 아니라 **S2-2 구현·검수 게이트**이며, SQL 구현(임시 NO-GO — 별도 승인 필요) 이후에만 체크할 수 있다.

- [ ] 위 스키마·view·5개 함수가 timestamp migration으로 생성됨 (v1.1 재배열 시그니처 기준)
- [ ] 함수 시그니처·JSON envelope·오류코드 contract test 통과 (시그니처·오류코드·GRANT contract test는 v1.1 기준으로 재수행 — 웹 §19.5-4)
- [ ] `PUBLIC`/`anon` revoke와 `authenticated` 최소 GRANT 실측
- [ ] 방 없는 학생이 앱에서 방을 확보하고 무료질문 스레드를 만들 수 있음
- [ ] 동일 학생–멘토 동시 호출에서 방이 1개만 존재
- [ ] 웹 이미지 글이 앱 목록·상세에 표시됨
- [ ] 앱 이미지 작성 0장·1장·5장, MIME/크기/타인 ref 공격, DB 실패 보상 삭제(Storage 한정) 통과
- [ ] **F4 응답 유실 복구(웹 T-CONC-10과 동일 — v1.1 추가):** 이미지 객체 업로드 → F4가 DB commit에 성공했으나 응답을 유실한 것으로 모사 → **재호출 전에 Storage DELETE가 0회인지 확인** → 동일 멱등키로 F4 재호출. 기대: 동일 `post_id` + `idempotent_replay:true` / 게시글 **1건** / 원래 `image_refs` **불변** / 참조 객체 **전부 존재**(서명 URL 발급 가능) / **확정 rollback·미커밋 분기(replay-first가 기존 행 없음 + 확정 실패 envelope로 종결)에서만** 신규 객체 보상 삭제 (§3.3·§6.3)
- [ ] 커뮤니티 작성 승인 멘토 전용 판정(`ROLE_NOT_MENTOR`·`MENTOR_NOT_APPROVED`) 통과 (§6.5)
- [ ] Realtime 미수신 시 기존 재조회 fallback 유지

### Gate 5

- [ ] 앱이 `FORFEIT_CONSENT_REQUIRED` payload를 버리지 않고 웹 유도로 분기
- [ ] `FORFEIT_CONSENT_STALE` 방어 fallback도 웹 유도
- [ ] 앱 코드·`api_app_v1`에 consented RPC 참조 0건
- [ ] 앱에서 잔액 소멸 동의·결제·구독 변경/해지 UI 0건
- [ ] `V_fix`와 T1~T3 운영 일정을 release checklist에 기록

이 문서가 Gate 4·5의 **설계 증거**이며, 체크박스는 S2/S3 구현·릴리스 검수 게이트다.

## 11. 공용 서버 자금 계약(F11·F12)의 앱 수용 경계 (v1.1 신설 — rev 8 A-5·A-6, 앱 동기화 10·웹 §19.5 동기화 의무)

앱은 F11(캐시 충전)·F12(구독 확정)를 **호출하지 않는다**(§7.2 — service_role 전용, 앱 도달 불가). 그러나 두 계약은 앱이 공유하는 객체(질문방 `mentor_student_rooms`, 공용 구현부 F10)와 오류코드 사전에 직접 영향을 주므로, 앱 계약은 아래 항목을 웹 정본과 **동일하게** 수용·기록한다. 이 절은 앱에 자금 기능을 추가하는 계약이 아니다.

### 11.1 F11 3층 구조 (rev 8 A-6 — 웹 §7 F11, 확인 기록)

- 공용 원자 구현부: `core_private.record_cash_topup_impl(p_user_id uuid, p_amount_cents bigint, p_idempotency_key text)` — `SECURITY INVOKER`, `search_path=''`, **외부 EXECUTE 0**.
- 레거시 `public.record_cash_topup(uuid,bigint,text)` void wrapper: duplicate 무음 반환 유지, service_role 전용.
- 신규 `api_web_v1.record_cash_topup_v2(uuid,bigint,text)` strict wrapper: 기존 6필드 NULL-safe 전건 대조, service_role 전용.
- topup 정본: 주문 참조는 `idempotency_key` 단독, `ref_id IS NULL`, `ref_type='topup'`, `ref_text` 컬럼·M2·4인자 F11 없음.
- **앱 경계:** 셋 모두 앱 호출자 계약 밖이다. 앱은 `cash_ledger`·`cash_wallets`를 SELECT 전용으로만 사용한다(§9).

### 11.2 F12 재생 계약 동기 (rev 8 A-5 — 웹 §7 F12)

**정본 기호·원칙:**

```text
P = 이번 호출에서 재생하려는 succeeded payment
C = 잠근 subscription.last_payment_id가 가리키는 최신 성공 payment
```

- **최신 결제 정본은 오직 `subscription.last_payment_id`다.** 생성시각·수정시각·UUID 순서 등으로 최신 결제를 추론하지 않는다.
- `P = C`면 일반 멱등 재생, `P ≠ C`면 과거 성공 결제의 늦은 재생 후보. 늦은 재생은 P가 succeeded이고 동일 학생·멘토 pair이며 동일 subscription의 정당한 결제인 경우에만 성공으로 흡수하며, **성공에서도 자금·원장·구독·결제 상태를 반복 처리하지 않는다**(늦은 과거 재생의 무자금부작용 멱등 성공).

**검증 선행·쓰기 후행(실행 단계 분리):**

```text
검증 선행·쓰기 후행: room 보정 INSERT/UPDATE는 모든 Phase 1 검증을 통과한 뒤에만 수행한다.
```

- **Phase 1 — 검증 전용:** payment·subscription·ledger·room 행 조회·잠금, 금액·플랜·당사자·원장·최신 결제 C·room 참조 정합성 검증. business-state 쓰기 0건(오류 시 허용되는 쓰기는 감사용 anomaly INSERT뿐). 오류 시 자금·원장·구독·결제·room 상태 변경은 모두 0건.
- **Phase 2 — room 확보·보정:** Phase 1 전부 통과 시에만 실행. room이 없으면 **F12 내부 `core_private.ensure_student_mentor_room` 호출**로 확보(확보한 room의 pair는 subscription pair와 일치해야 함). room nullable 참조는 검증 통과 후 Phase 2에서만 복구한다.

**오류코드 우선순위 — 9단계 단일 목록 (구 7단계 완전 교체):**

```text
1. SUCCEEDED_NO_SUBSCRIPTION
2. SUCCEEDED_NO_LEDGER
3. PLAN_BINDING_MISMATCH
4. PARTY_BINDING_MISMATCH — P의 학생·멘토 관계 불일치
5. LEDGER_BINDING_MISMATCH
6. LEDGER_FIELD_MISMATCH
7. SUBSCRIPTION_REF_INVALID — C가 NULL이거나 유효한 succeeded payment를 가리키지 않음
8. PARTY_BINDING_MISMATCH — C가 가리키는 payment의 학생·멘토가 subscription pair와 불일치
9. ROOM_REF_MISMATCH
```

- 상위 조건이 성립하면 하위 코드로 덮어쓰지 않는다. 기존 안정 코드 3종(`SUCCEEDED_NO_SUBSCRIPTION`·`SUCCEEDED_NO_LEDGER`·`LEDGER_FIELD_MISMATCH`)을 새 코드로 치환하지 않는다. 새 관계 오류코드는 행이 존재하지만 관계가 다른 경우에만 사용한다. 오류 경로는 기존 anomaly 계약에 따라 안정 코드·detail·`anomaly_id`를 반환하고, 오류 시 business-state 부작용은 0건이다.
- `ROOM_ENSURE_FAILED`는 9단계 관계 검증을 통과한 후 Phase 2의 room 확보·복구가 실패했을 때 사용하는 **운영 오류**이므로 9단계 관계 오류 우선순위와 별도로 둔다(재시도 가능 — §4.3의 동일 코드와 같은 의미).

**`SUBSCRIPTION_REF_INVALID` + anomaly detail 3종:**

| 조건 | anomaly detail |
|---|---|
| `subscription.last_payment_id IS NULL` | `LAST_PAYMENT_ID_NULL` |
| C가 가리키는 payment 행이 없음 | `LAST_PAYMENT_NOT_FOUND` |
| C가 가리키는 payment가 `succeeded`가 아님 | `LAST_PAYMENT_NOT_SUCCEEDED` |

detail은 내부 감사 정보이며 클라이언트 분기용 안정 코드는 `SUBSCRIPTION_REF_INVALID` 하나로 고정한다. **C 당사자 불일치:** C가 가리키는 payment가 존재하고 succeeded지만 학생·멘토가 현재 subscription pair와 다르면 `SUBSCRIPTION_REF_INVALID`가 아니라 8단계의 `PARTY_BINDING_MISMATCH`를 사용한다.

**room 참조 규칙 — 컬럼별 정본 의미(rev 8 동결, 웹 §7 F12 표와 동일):**

| 컬럼 | 정본 의미 | 신규 결제 | 멱등 재생 |
|---|---|---|---|
| `student_id, mentor_id` | 방의 불변 정본 | 변경 금지 | 일치 필수 |
| `subscription_id` | pair에 대응하는 구독 | NULL이면 채움, 다른 값이면 거부 | 재생 판정 규칙 적용 — NULL이면 Phase 2에서 현재 `subscription_id`로 보정, 동일하면 유지, 다른 값이면 `ROOM_REF_MISMATCH` |
| `payment_id` | **가장 최근 성공 checkout** | 현재 결제로 갱신 | 재생 판정 규칙 적용 — C와 동일 → 유지 / NULL → Phase 2에서 C로 보정 / P와 동일이고 `P ≠ C` → stale 참조로 판정, Phase 2에서 C로 보정 / C도 P도 아닌 제3 결제 → `ROOM_REF_MISMATCH` |

`payment_id`의 의미는 "가장 최근 성공 checkout"으로 유지한다. 과거 결제의 불변 참조로 해석하지 않는다.

**앱 수용 결과:**

- **구독 성공 시 질문방 존재는 필수 불변조건**이다(웹 §13.1 — F12가 성공 응답에 `room_id`를 포함). 앱 질문방 진입은 구독 성공 후 방 존재를 전제할 수 있으며, 방 부재를 앱이 자체 생성으로 보정하는 계약은 없다(방 생성은 클라이언트에서 불가능 — RLS INSERT 정책 부재 유지).
- room의 `payment_id`·`subscription_id`는 앱이 쓰지 않는 참조 컬럼이며, 위 재생 판정·보정 의미론은 서버(F12) 소관이다. 앱은 room 참조 컬럼 값을 화면 판정에 사용하지 않는다.

### 11.3 F12 재생 회귀 테스트 A~H (웹 §21.8 T-REP — 기대값 동일)

P1→P2 시나리오는 라이브에 실제 다중 succeeded pair가 존재한다는 주장이 아니라, **재구독·늦은 재생을 검증하는 테스트 fixture 기반 회귀 계약**이다.

| ID | 시나리오 | 기대 결과 |
|---|---|---|
| A (T-REP-A) | P1 성공 → P2 성공, room=`P2` → P1 늦은 재생 | `ok:true, idempotent:true` / room 변경 0 / 자금 부작용 0, anomaly 0 |
| B (T-REP-B) | P1 성공 → P2 성공 뒤 room=`P1`(stale) → P1 재생 | `ok:true, idempotent:true` / 검증 완료 후 room을 C=`P2`로 복구 / 자금 부작용 0, anomaly 0 |
| C (T-REP-C) | P1 성공 → P2 성공 뒤 `room.payment_id`=NULL → P1 재생 | `ok:true, idempotent:true` / 검증 완료 후 `room.payment_id`를 C=`P2`로 복구 / 자금 부작용 0, anomaly 0 |
| D (T-REP-D) | `room.payment_id`가 C도 P도 아닌 제3 결제 참조 | `ROOM_REF_MISMATCH` + `anomaly_id` / business-state 쓰기 0 |
| E (T-REP-E) | `subscription.last_payment_id IS NULL` | `SUBSCRIPTION_REF_INVALID`, detail=`LAST_PAYMENT_ID_NULL` + `anomaly_id` / room 변경 0 |
| F (T-REP-F) | C 행이 없거나 succeeded가 아님 | `SUBSCRIPTION_REF_INVALID`, detail=`LAST_PAYMENT_NOT_FOUND` 또는 `LAST_PAYMENT_NOT_SUCCEEDED` + `anomaly_id` / room 변경 0 |
| G (T-REP-G) | C는 succeeded이나 subscription과 당사자가 다름 | `PARTY_BINDING_MISMATCH` + `anomaly_id` / room 변경 0 |
| H (T-REP-H) | room 참조가 NULL 또는 stale 후보지만 P·ledger·관계 검증이 실패 | 해당 상위 안정 오류 반환(9단계 우선순위) / 후보였던 room 보정은 실행되지 않음 / room 변경 0 |

### 11.4 V6 조회 계약 필드명 동기 (rev 8 §6.4 — 확인 기록)

웹 V6(`api_web_v1.my_subscriptions_self()`)의 현재 플랜 가격 필드명은 **`current_plan_amount_cents`로 단일 확정**됐다(값의 실질 의미가 "현재 플랜 가격" — 라이브 `mentor_plans`를 `plan_id`로 join해 읽는다). `next_renewal_amount_cents`는 실제 다음 결제 금액을 별도 고정·스냅샷하는 계약이 생겼을 때 additive 필드로만 검토하며 v1.1에서는 사용하지 않는다. **앱 경계:** V6·V7은 `api_web_v1`의 웹 전용 조회 RPC이며 앱은 호출하지 않는다(앱 구독 표시는 기존 직접 테이블 SELECT 경로 유지 — §9). 앱이 향후 동일 정보를 조회하는 객체를 받을 경우 필드명은 이 확정을 따른다.

## 12. 공용 커뮤니티 내부 함수 대조표 (v1.1 신설 — rev 8 B, 앱 동기화 8·웹 §19.5-6)

웹·앱 계약이 공유하는 `core_private` 내부 함수 5종의 이름·시그니처·보안 속성·GRANT·오류코드가 웹 계약 v1.1과 동일함을 증명한다. 대조 기준은 웹 §7(F4·F5·F6·F10, B-1~B-4)·§10.3.

| 객체 (identity argument) | SECURITY | search_path | owner | 외부 EXECUTE | wrapper/구현부 경계 | 안정 오류코드 | 웹 절 | 앱 절 | 판정 |
|---|---|---|---|---|---|---|---|---|---|
| `core_private.community_post_create_impl(uuid,text,text,text,text[],text,uuid)` | INVOKER | `''` | migration 실행 역할 | **0** (PUBLIC·anon·authenticated·service_role 전부 미부여) | wrapper(웹 F4·앱 `community_post_create`, SECDEF)가 `auth.uid()` 도출 후 `p_author_id`로 전달. replay-first 판정(§3.3)과 역할·승인·상태·본문 검증은 구현부 수행 | `AUTH_REQUIRED`(wrapper 선행) · `ROLE_NOT_MENTOR` · `MENTOR_NOT_APPROVED` · `ACCOUNT_BANNED` · `ACCOUNT_SUSPENDED` · `ACCOUNT_DELETION_IN_PROGRESS` · `TITLE_REQUIRED` · `BODY_TOO_SHORT` · `CATEGORY_INVALID` · B-4 위임 이미지 코드 6종. 수정·삭제 전용 코드는 발생하지 않는다. 멱등 재생은 오류가 아니라 `idempotent_replay:true` 성공 | 웹 §7 F4·§10.3 | §3.3·§3.4 B-1·§6.4 | **PASS** |
| `core_private.community_post_update_impl(uuid,uuid,text,text,text,text[],text,timestamptz)` | INVOKER | `''` | migration 실행 역할 | **0** | wrapper(웹 F5·앱 `community_post_update`, SECDEF)가 `auth.uid()` 도출 후 `p_author_id`로 전달 | `AUTH_REQUIRED`(wrapper 선행) · `ROLE_NOT_MENTOR`(학생 작성 글 수정 거부 포함 — §6.5) · `MENTOR_NOT_APPROVED` · `ACCOUNT_BANNED` · `ACCOUNT_SUSPENDED` · `ACCOUNT_DELETION_IN_PROGRESS` · `TITLE_REQUIRED` · `BODY_TOO_SHORT` · `CATEGORY_INVALID` · `POST_NOT_FOUND_OR_NOT_OWNED` · `UPDATE_CONFLICT` · B-4 위임 이미지 코드 6종 | 웹 §7 F5·§10.3 | §3.4 B-2·§6.4 | **PASS** |
| `core_private.community_post_soft_delete_impl(uuid,uuid)` | INVOKER | `''` | migration 실행 역할 | **0** | wrapper(웹 F6·앱 `community_post_soft_delete`, SECDEF)가 `auth.uid()` 도출 후 `p_author_id`로 전달 | `AUTH_REQUIRED`(wrapper 선행) · `ACCOUNT_BANNED` · `ACCOUNT_SUSPENDED` · `ACCOUNT_DELETION_IN_PROGRESS` · `POST_NOT_FOUND_OR_NOT_OWNED`. 제목·본문·카테고리·이미지·낙관적 충돌 등 생성·수정 전용 코드는 발생하지 않는다. 이미 삭제된 본인 글은 오류가 아니라 `ok:true` + `already_deleted:true` | 웹 §7 F6·§8.3·§10.3 | §3.3·§3.4 B-3 | **PASS** |
| `core_private.community_image_refs_validate(uuid,text[])` | INVOKER | `''` | migration 실행 역할 | **0** | 구현부 내부에서 호출되는 공용 검증기 — 검증 5종(§6.2), 실패 시 `{ok:false, code}` | 정확히 다음 6종만: `IMAGE_COUNT_EXCEEDED` · `IMAGE_REF_INVALID` · `IMAGE_NOT_OWNED` · `IMAGE_OBJECT_NOT_FOUND` · `IMAGE_MIME_NOT_ALLOWED` · `IMAGE_SIZE_EXCEEDED` | 웹 §7 B-4·§10.3 | §3.4 B-4·§6.2·§6.4 | **PASS** |
| `core_private.ensure_student_mentor_room(uuid,uuid,uuid,uuid,boolean)` | **DEFINER** | `''` | migration 실행 역할 | **0** | wrapper(웹 F2·앱 `ensure_free_question_room`, SECDEF)가 `auth.uid()`를 `p_student_id`로 전달. 웹 F12는 내부 호출(`p_require_entitlement=false`) | `AUTH_REQUIRED` · `ROLE_NOT_STUDENT` · `ACCOUNT_BANNED` · `ACCOUNT_SUSPENDED` · `ACCOUNT_DELETION_IN_PROGRESS` · `MENTOR_NOT_FOUND` · `MENTOR_NOT_APPROVED` · `BLOCKED` · `FREE_QUOTA_EXPIRED` · `FREE_QUOTA_TOTAL_EXHAUSTED` · `FREE_QUOTA_MENTOR_EXHAUSTED` · `ROOM_ENSURE_FAILED` (§4.3의 12종) | 웹 §7 F10·§10.3 | §3.4 F10·§4.2·§4.3 | **PASS** |

- 커뮤니티 내부 구현부 4종(B-1~B-4)은 `SECURITY INVOKER`, `search_path=''`, 외부 EXECUTE 0으로 웹 정본과 동일하다. F10만 `SECURITY DEFINER`다(웹 §7 F10 — RLS 우회가 필요한 방 확보 원자 연산, 웹 §11.6 화이트리스트 등재).
- `core_private`를 앱이 직접 Data API RPC로 호출하는 계약은 없다(§1 원칙 8, §3.1).

## 13. rev 8 반영 추적표 (v1.1 필수 — 역기입)

### 13.1 앱 동기화 지시서 항목 1~10

| 지시 항목 | 내용 요약 | 앱 v1.1 반영 절 | 상태 |
|---|---|---|---|
| 1 (A-1) | F4/F5 시그니처 재배열·named notation·Gate 4 소급 무효 | §3.3·§10 | 반영 완료 |
| 2 | `SUBSCRIPTION_REFUND_PENDING` 정합화 | §4.3 | 반영 완료 |
| 3 | envelope 웹 v1.1 동일 구조 재기술 | §3.3 | 반영 완료 |
| 4 (A-8) | 주간 사용량 NULL-safe pair-party 가드·앱 영향 없음 | §4.4·§8 | 반영 완료 |
| 5 (C) | `HD-1` 전면 잠금 게이트·보상 DELETE 폐기·동일 멱등키 재시도(**재호출 선행·보상 삭제 후행 — replay-first 복구 순서**)·Storage 보상 유지 | §3.3·§6.3·§6.6·§9 | 반영 완료 |
| 6 (D, B-04) | 금지어 검사 폐지·`POLICY_RESTRICTED` 예약 코드 동결 | §6.2·§6.4 | 반영 완료 |
| 7 (D, B-07) | 앱 `mentor_profiles` 쓰기 없음 실측·blocker 해제 | §2·§9 | 반영 완료 |
| 8 (B) | 공용 커뮤니티 내부 함수 대조표 | §12 | 반영 완료 |
| 9 (A-10) | 작성 승인 멘토 전용·`ROLE_NOT_MENTOR`/`MENTOR_NOT_APPROVED`·학생 글 보존·숏폼 정합화 | §6.4·§6.5 | 반영 완료 |
| 10 (A-5) | F12 재생 계약 rev 8 동기·테스트 A~H | §11.2·§11.3 | 반영 완료 |

### 13.2 웹 §19.5 동기화 기준 1~8

| 항목 | 앱 v1.1 반영 절 | 상태 |
|---|---|---|
| 1. F4/F5 재배열·named notation·Gate 4 소급 무효 | §3.3·§10 | 반영 완료 |
| 2. `SUBSCRIPTION_REFUND_PENDING` 추가 | §4.3 | 반영 완료 |
| 3. envelope `ok`/`contract_version`/`code` 재기술 | §3.3 | 반영 완료 |
| 4. Gate 4 재게이트(시그니처·오류코드·GRANT contract test 재수행) | §10 | 반영 완료 |
| 5. 주간 사용량 pair-party 가드·앱 영향 없음 명기 | §4.4 | 반영 완료 |
| 6. 공용 커뮤니티 내부 함수 대조표 | §12 | 반영 완료 |
| 7. `ROLE_NOT_ALLOWED` 재정의(멘토 전용 기준) | §6.4·§6.5 | 반영 완료 |
| 8. 보상 삭제 순서 정정(재호출 선행·보상 삭제 후행)·F4 replay-first 판정 우선순위·응답 유실 복구 테스트(웹 T-CONC-10) 동기화 | §3.3·§6.3·§6.6·§10 | 반영 완료 |

### 13.3 웹 rev 8 정본 지시서 관련 절

| rev 8 절 | 내용 | 앱 v1.1 반영 절 | 상태 |
|---|---|---|---|
| A-1 | F4/F5 생성 불가 → 재배열 | §3.3 | 반영 완료 |
| A-5 | F12 멱등 재생 최종 계약 | §11.2·§11.3 | 반영 완료 |
| A-8 | XW-01 NULL-safe pair-party | §4.4 | 반영 완료 |
| A-10 | 커뮤니티 작성 멘토 전용·숏폼 | §6.5 | 반영 완료 |
| B | 공용 구현부 명세 의무 | §3.4·§12 | 반영 완료 |
| C | `HD-1` 전면 잠금·보상 RPC 폐기 | §6.3·§6.6 | 반영 완료 |
| F | 앱 계약 v1.1 동기화 항목 | §13.2 (전건) | 반영 완료 |
| G | 다음 세션 지시(산출물 = 계약 문서, SQL 금지) | 문서 헤더 판정·§10 | 반영 완료 |

## 14. 웹·앱 공용 계약 대조표 (v1.1 하드게이트)

정본 = 웹 계약 v1.1(`53120d026508f8f75d5eb00dfaee4bde278deb1c`, 2,826행 / 293,982바이트, SHA-256 `0df3a98d2fce896df329b0f423dddedcf9d2455142a8b1b5d04fba2bb2a3511a` — 원격 실측 일치 확인). 판정은 PASS/FAIL만 사용하며, 한 행이라도 FAIL이면 S2-1 PASS를 선언하지 않는다. *(v1.1 재동기: 아래 전 행을 새 정본 기준으로 재판정했다 — 특히 멱등·보상 삭제·replay-first·Gate 4 테스트 행은 새 정본의 §7 F4·§14.4·§21.3 T-CONC-10 개정을 반영해 앱 절을 함께 개정한 뒤 판정했다.)*

| 분류 | 웹 정본 | 앱 v1.1 | 일치 여부 | 근거 절 (웹 / 앱) |
|---|---|---|---|---|
| 웹 정본 정체성 | 커밋 `53120d02…78deb1c` · 2,826행 · 293,982B · SHA-256 `0df3a98d…a3511a` | 문서 헤더·본 표 서문이 동일 정체성 참조(구 정본 참조 0건) | **PASS** | 웹 파일 실측 / 앱 헤더·§14 |
| F4 함수명·전체 인자 순서 | `community_post_create(p_title text, p_body text, p_category text, p_idempotency_key uuid, p_image_refs text[] DEFAULT '{}', p_status text DEFAULT 'published')` | 동일 (스키마만 `api_app_v1`) | **PASS** | 웹 §7 F4 / 앱 §3.3 |
| F5 함수명·전체 인자 순서 | `community_post_update(p_post_id uuid, p_title text, p_body text, p_category text, p_expected_updated_at timestamptz, p_image_refs text[] DEFAULT '{}', p_status text DEFAULT 'published')` | 동일 (스키마만 `api_app_v1`) | **PASS** | 웹 §7 F5 / 앱 §3.3 |
| F6 함수명·인자 | `community_post_soft_delete(p_post_id uuid)` | 동일 | **PASS** | 웹 §7 F6 / 앱 §3.3 |
| F2/방 확보 wrapper | `ensure_free_question_room(p_mentor_id uuid)` — F10 호출 얇은 wrapper | 동일 (이름·시그니처·반환·오류코드 완전 동일) | **PASS** | 웹 §7 F2 / 앱 §3.3·§4 |
| F3/스레드 wrapper | `qna_create_question_thread(uuid,text,text,text,text)` — 정본 raise → envelope 변환 | 동일 | **PASS** | 웹 §7 F3 / 앱 §3.3·§4.3 |
| 입력 타입·DEFAULT | 필수 선행·DEFAULT 후행 (`p_image_refs text[] DEFAULT '{}'`, `p_status text DEFAULT 'published'`) · named notation 의무 | 동일 | **PASS** | 웹 §7 F4·F5 / 앱 §3.3 |
| 응답 envelope | `{ok, contract_version:1, …}` / `{ok:false, contract_version:1, code}` · 필드 추가는 버전 유지·제거/의미 변경은 상승 · 예상 밖 예외 전파 · 멱등 재생 표시 의무 | 동일 | **PASS** | 웹 §8.1~8.3 / 앱 §3.3 |
| 공용 내부 함수명·스키마·identity | `core_private` 5종: `community_post_create_impl(uuid,text,text,text,text[],text,uuid)` · `community_post_update_impl(uuid,uuid,text,text,text,text[],text,timestamptz)` · `community_post_soft_delete_impl(uuid,uuid)` · `community_image_refs_validate(uuid,text[])` · `ensure_student_mentor_room(uuid,uuid,uuid,uuid,boolean)` | 동일 (같은 객체를 공유 — 앱이 별도 구현부를 만들지 않음) | **PASS** | 웹 §7·§10.3 / 앱 §3.4·§12 |
| SECURITY INVOKER/DEFINER 경계 | 외부 호출 wrapper = DEFINER · 구현부 4종(B-1~B-4) = 의도적 INVOKER(외부 EXECUTE 0) · F10 = 내부 DEFINER(외부 EXECUTE 0) | 동일 (§1 원칙 6을 wrapper/구현부 범위로 정정해 충돌 제거) | **PASS** | 웹 §7 F4~F6·F10·§11.1 / 앱 §1 원칙 6·§3.4·§12 |
| owner·search_path | owner = migration 실행 역할 · `SET search_path = ''` · 완전 수식 객체명 | 동일 | **PASS** | 웹 §7·§11.1 / 앱 §3.4·§12 |
| GRANT·REVOKE (공용 내부 함수) | `core_private` 5종 외부 EXECUTE 0 — PUBLIC·anon·authenticated·service_role 전부 미부여, 생성과 같은 마이그레이션에서 REVOKE 명시 | 동일 | **PASS** | 웹 §10.1·§10.3 / 앱 §3.1·§3.4·§12 |
| GRANT·REVOKE (앱 wrapper) | 웹 T2 패턴: PUBLIC REVOKE·anon 미부여·authenticated EXECUTE (웹은 service_role 병행 부여 — 웹 서버 경로용) | PUBLIC·anon REVOKE + authenticated EXECUTE. `service_role`은 앱 호출자 계약에서 제외(§3.3 주석 — wrapper 객체별 호출자 계약의 의도적 차이, 공용 계약 아님) | **PASS** | 웹 §10.3 / 앱 §3.3 |
| 커뮤니티 오류코드 (코드 집합) | §9.4 12종 + `ROLE_NOT_MENTOR`·`MENTOR_NOT_APPROVED` (작성 자격) · `POLICY_RESTRICTED` 예약 코드(발생 안 함) · `CATEGORY_INVALID` 허용값 `study|school|career|college|free` · `BODY_TOO_SHORT` 10자 | 동일 | **PASS** | 웹 §9.2~9.4 / 앱 §6.4 |
| 함수별 오류코드 분리 | 함수 경계별 실제 발생 가능 코드만 귀속(create ≠ update ≠ soft_delete ≠ image validator — 예: 낙관적 충돌·소유권 코드는 update/soft_delete 계열에만, image validator는 6종만) | 동일 (§12 대조표 오류코드 열을 함수별로 분리 명세) | **PASS** | 웹 §7 F4~F6·B-4·§8.3 / 앱 §12 |
| `SUBSCRIPTION_REFUND_PENDING` | §9.3 — 정본 raise 동일명, 앱 계약 처리 의무 | §4.3에 추가 완료 | **PASS** | 웹 §9.3·§19.5-2 / 앱 §4.3 |
| `ROLE_NOT_MENTOR` | 멘토 아님 — F4 작성 자격 위반 | 동일 정의 | **PASS** | 웹 §9.2·§7 F4 / 앱 §6.4·§6.5 |
| `MENTOR_NOT_APPROVED` | 미승인 멘토 — `individual_question_user_is_approved_mentor(auth.uid())` 동일 헬퍼 | 동일 정의·동일 헬퍼 | **PASS** | 웹 §9.3·§7 F4 / 앱 §6.4·§6.5 |
| `SUBSCRIPTION_REF_INVALID` detail 3종 | `LAST_PAYMENT_ID_NULL` / `LAST_PAYMENT_NOT_FOUND` / `LAST_PAYMENT_NOT_SUCCEEDED` — 안정 코드는 1개, detail은 anomaly 감사 정보 | 동일 | **PASS** | 웹 §7 F12·§9.6 / 앱 §11.2 |
| C 당사자 불일치 | 8단계 `PARTY_BINDING_MISMATCH` (`SUBSCRIPTION_REF_INVALID` 아님) | 동일 | **PASS** | 웹 §7 F12 / 앱 §11.2 |
| 9단계 오류 우선순위 | 1 `SUCCEEDED_NO_SUBSCRIPTION` … 9 `ROOM_REF_MISMATCH` (7단계 목록 부재·병존 없음, `ROOM_ENSURE_FAILED` 별도 운영 오류) | 동일 (목록 전문 전사) | **PASS** | 웹 §7 F12 / 앱 §11.2 |
| 검증 선행·쓰기 후행 | Phase 1 검증 전용(business-state 쓰기 0) / Phase 2 room 확보·보정, 문장 명시 | 동일 (문장 동일 전사) | **PASS** | 웹 §7 F12 / 앱 §11.2 |
| room 참조 의미론 | pair 불변 정본 · `subscription_id` NULL 보정/동일 유지/다른 값 거부 · `payment_id` = 가장 최근 성공 checkout(C 유지/NULL→C/stale→C/제3→`ROOM_REF_MISMATCH`) | 동일 (컬럼별 표 동일 전사) | **PASS** | 웹 §7 F12·§13.1 / 앱 §11.2 |
| 늦은 과거 재생 | P≠C 조건 충족 시 무자금부작용 멱등 성공(`ok:true, idempotent:true`, anomaly 0) | 동일 | **PASS** | 웹 §7 F12 / 앱 §11.2 |
| 멱등성·동시성 계약 | F4 멱등키 필수·`(author_id, create_idempotency_key)` · 같은 멱등키 재호출 = 정본 복구 · **응답 불명확·유실은 실패 확정 아님(재호출 전 Storage 객체 보존)** · 방 확보 `ON CONFLICT DO NOTHING`+재조회·동시 1방(T-CONC-01) · F4 응답 유실 복구(T-CONC-10) | 동일 (§6.3 4분기 규약·§10 테스트로 재동기) | **PASS** | 웹 §7 F4·§14.4·§13.1·§21.3 / 앱 §3.3·§4.2·§6.3·§10 |
| F4 공용 구현부 판정 순서(replay-first) | author binding 직후·신규 쓰기 검증보다 먼저 `(author_id, create_idempotency_key)` 기존 커밋 행 조회 → 있으면 새 쓰기·Storage 삭제 없이 기존 `post_id`+`idempotent_replay:true` → 없을 때만 신규 검증·INSERT · 단순 재호출 오류 ≠ 미커밋 확인 · 별도 조회 RPC 신설 없음 | 동일 (동일 B-1 구현부 호출 — 판정 순서 동일 전사) | **PASS** | 웹 §7 F4 / 앱 §3.3·§3.4 B-1 |
| 커뮤니티 이미지 보상 삭제 규약 | 4분기: 업로드 실패 즉시 삭제 / 확정 실패·rollback 확인 시 삭제 / 응답 불명확·유실은 **삭제 없이 동일 멱등키 F4 선재호출**(성공·기존 `post_id` → 객체 유지, replay-first 미커밋 확인+확정 실패 종결 시에만 삭제) / DB hard DELETE 보상 계속 금지 | 동일 (§6.3 4분기 전사 — 웹 §14.5 보상 삭제 행의 "앱 v1.1 동기화 시 충족" 조건 해소) | **PASS** | 웹 §14.4·§14.5·§19.5-8 / 앱 §6.3·§6.6 |
| 테스트 A~H | T-REP-A~H 8건 — fixture 명시 포함, 기대값 표 | 동일 (기대값 전건 전사) | **PASS** | 웹 §21.8 / 앱 §11.3 |
| `HD-1` | `community_posts` REVOKE ALL+GRANT SELECT·쓰기 정책 6종 제거·M16 별도·확대 게이트 7단계·service_role moderation 예외·보상 RPC 폐기 | 동일 + 앱 측 의무 ①~⑦ | **PASS** | 웹 §14.7 / 앱 §6.6 |
| Storage 정책 조건 | `sf_insert_mentor` 1건 · `sfv_mentor_insert` 1정책/2버킷 · 기존 조건 4종 보존 · 동일 승인 헬퍼 | 동일 | **PASS** | 웹 §14.8 / 앱 §6.5 |
| 커뮤니티 이미지 계약 | ref 형식·TTL 3600·5장/5MiB/4MIME·UID 경로·soft delete·레거시 URL 호환 (보상 삭제 행은 웹 §14.5에서 "앱 계약 v1.1 동기화 시 충족(⚠→✅)"로 표기 — 본 문서 §6.3 재동기로 조건 충족) | 동일 | **PASS** | 웹 §14.1~14.5 / 앱 §5·§6.3 |
| V6 `current_plan_amount_cents` | 필드명 단일 확정(현재 플랜 가격) — 대체 이름 사용 금지 | 동일 확정 수용 (앱 비호출 경계 명시) | **PASS** | 웹 §6 V6·rev 8 §6.4 / 앱 §11.4 |
| F11 3층 구조 | `record_cash_topup_impl`(INVOKER·EXECUTE 0) / 레거시 void wrapper / strict wrapper(service_role 전용) · topup 정본 `idempotency_key`·`ref_id NULL`·`ref_type='topup'` | 동일 확인 기록 (앱 비호출 경계) | **PASS** | 웹 §7 F11 / 앱 §11.1 |
| 앱 금지 기능 경계 | F11·F12 service_role 전용 → 앱 도달 불가 · consented RPC allowlist 밖 · 결제·신규 구독·캐시 결제·개별질문 등록 앱 미노출 | 동일 (신규 앱 전용 기능 0건·금지 기능 추가 0건) | **PASS** | 웹 §19.1·§19.2 / 앱 §1·§7 |
| Gate 4 (테스트 기대값 포함) | v1.0 문서 게이트 PASS 소급 무효 → v1.1 재게이트 · 구현 게이트에 T-CONC-10 동일 시나리오(응답 유실 모사 → 재호출 전 Storage DELETE 0회 → 동일 `post_id`·`idempotent_replay:true`·글 1건·`image_refs` 불변·참조 객체 전부 존재·확정 rollback/미커밋 분기에서만 삭제) | 재게이트 PASS (근거 표) + T-CONC-10 동일 항목 추가 | **PASS** | 웹 §19.5-1·4·§21.3 T-CONC-10 / 앱 §10 |

**대조 결과: 35행 전건 PASS · FAIL 0건.** (새 웹 정본 `53120d02…` 기준 재판정)

---

**S2-1/S2-2 판정 관계(웹 rev 8 G·§24 동기):** 본 문서로 `api_web_v1` 계약 v1.1·`api_app_v1` 계약 v1.1 문서 2건과 공용 계약 교차대조가 완성됐다. S2-1 PASS 재심사가 가능하다. **S2-2 SQL 구현은 임시 NO-GO를 유지**하며, 본 계약의 어떤 절도 이번 세션에서 SQL·마이그레이션·제품 코드 작성을 승인하지 않는다.
