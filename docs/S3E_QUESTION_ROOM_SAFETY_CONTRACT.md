# S3-E — 질문방 신고·차단 계약 현행본

> 이 문서는 **과거 초안이 아니라 현행 정본**이다.
> Build 13 DB 계약 수렴(staging ledger `20260802054930` 및 후속 수렴 M1~M3
> `20260803170552`/`170916`/`171053`) 적용 **후**의 상태를 기록한다.
> 앱·웹·DB 공통 계약이며, SQL 소유 저장소는 웹(`ssambership_web`)이지만
> 앱(`ssambership-app`)도 동일 계약을 **소비**한다.
> staging 함수 정의 재검증 기준: 전 기능 계약 수렴 세션(2026-08-04, staging
> `lbeqxarxothkmzqvpudy`에서 `qna_append_message`·`qna_register_attachment`
> 본문 read-only 재조회).

---

## 1. 신고(사용자) — 지원됨 ✅

앱은 질문방 상대(멘토↔학생)를 `content_reports` 테이블로 신고한다.

| 컬럼 | 앱이 넣는 값 |
| --- | --- |
| `reporter_id` | `auth.uid()` (현재 사용자) |
| `target_type` | **`'user'`** |
| `target_id` | 상대 user id (`mentor_student_rooms` 참여자에서 도출) |
| `reason` | 공용 신고 시트 code |
| `description` | 선택(비었으면 컬럼 자체를 생략) |
| `status` | `'pending'` |

서버 강제(현행 `content_reports_insert_reporter` INSERT 정책):

- `reporter_id = auth.uid()` · `status = 'pending'` · `admin_note`/`resolved_by`/
  `resolved_at` 는 모두 NULL 이어야 한다(앱은 관리자 필드를 보내지 않는다).
- `target_type` 은 아래 **정본 5종 allowlist** 안에서만 허용된다.
- `target_type='user'` 이면 `report_target_user_valid(target_id)` 를 통과해야 한다
  → 실재하는 **다른** 사용자만 신고 가능(자기 신고·미존재 UUID·NULL target 거부).

---

## 2. 신고 target 정본 어휘

| 대상 | `target_type` |
| --- | --- |
| 게시판 글 | `community_post` |
| 숏폼 글 | `shortform_post` |
| 게시판 댓글 | `board_comment` |
| 숏폼 댓글 | `community_comment` |
| 질문방 상대 사용자 | `user` |

규칙:

- **`comment` 신규 사용 금지** (과거 게시판 댓글 신고가 `comment` 를 보내 서버
  allowlist 밖에서 거부되던 실사용 버그 — `board_comment` 로 교정됨).
- **`shortform` 신규 사용 금지** (숏폼 글은 `shortform_post`).
- `user` 신고는 실재하는 **다른** 사용자만 가능(자기 신고·미존재 UUID·NULL 거부, 서버 강제).
- 앱은 `admin_note`/`resolved_*` 등 **관리자 필드를 보내지 않는다**.
- 웹 관리자 화면의 legacy `comment` normalizer 는 **과거 데이터 호환 조회 전용**이며
  **신규 쓰기 계약이 아니다** — 신규 INSERT 경로에서 모호한 값을 생성하지 않는다.

---

## 3. 질문방 차단 계약 — 서버 양방향 강제됨 ✅

`user_blocks` 실측:

- PK `(blocker_id, blocked_id)` → 중복 차단은 `unique_violation(23505)` = **멱등 성공**.
- CHECK `user_blocks_check`: `blocker_id <> blocked_id` → 자기 차단은 DB 가 거부.
- FK 두 컬럼 모두 `users(id) ON DELETE CASCADE`.
- RLS: `ub_insert_own`/`ub_delete_own`/`ub_select_own` 모두 `blocker_id = auth.uid()`.

앱은 차단 후 해당 질문방을 **읽기 전용**으로 만든다(composer 비활성, append·첨부 호출 0).
차단 해제는 설정 > 차단 사용자 관리(`blocked_users_screen`)에서 동작한다.

### 3-1. 서버 강제 (현행)

세 RPC 모두 **당사자 판정 직후 · INSERT 이전**에 양방향 차단 검사
(`qna_users_blocked(v_student, v_mentor)` → `raise exception 'BLOCKED'`)를 수행한다.

| RPC | 서버 양방향 차단 검사 |
| --- | --- |
| `qna_create_question_thread` | ✅ 적용 |
| `qna_append_message` | ✅ 적용 |
| `qna_register_attachment` | ✅ 적용 |

`qna_append_message`·`qna_register_attachment` 실측 판정 순서(공통):
`AUTH_REQUIRED` → 입력 검증 → thread 조회(FOR UPDATE) → 당사자 판정(NOT_ROOM_PARTY)
→ **계정 상태 4종(BANNED/SUSPENDED/NOT_ACTIVE/DELETION) + `BLOCKED`** → `THREAD_LOCKED`
→ `MENTOR_NOT_APPROVED` → (register: STORAGE 검증) → `SUBSCRIPTION_REFUND_PENDING`
→ INSERT → answered 전이. 차단 검사는 어떤 INSERT·상태 전이·알림보다 앞이다.

`qna_register_attachment` 는 미승인 멘토가 **첨부-only 답변**으로 승인 게이트를
우회하지 못하도록 `MENTOR_NOT_APPROVED` 검사를 attachment INSERT 이전에 둔다.

### 3-2. 차단 상태 부수효과 = 0

차단 관계가 있는 방에서 append/register 호출 시 다음이 모두 **0**이다.

- `question_messages` INSERT
- `question_attachments` INSERT
- `answered` 상태 전이
- `first_answered_at` 변경
- notification 생성 (INSERT 이전에 `BLOCKED` 로 중단 → AFTER INSERT 알림 트리거 미발화)
- outbox 생성

차단 해제 후에는 정상 복귀한다(회귀 없음 — answered 전이·알림 포함).

앱 측: `qna_error_mapper` 가 `BLOCKED` 를 사용자 문구로 매핑하고, 차단 즉시 composer 를
제거한다. 서버 코드 문자열은 화면에 노출하지 않는다.

---

## 4. 상대(counterparty) id 정본

`RoomCounterparty.of(room, currentUid:)` — `mentor_student_rooms.student_id` /
`mentor_id` 에서만 도출한다.

금지(코드로 강제): 메시지 첫 작성자 추정 · 화면 문자열 파싱 · 닉네임 조회 ·
UUID 하드코딩 · current user 와 동일한 id 허용.

도출 실패(방 정보 없음 / 당사자 아님 / 세션 없음)면 앱바 안전 메뉴를 **비활성화**한다.
raw UUID 는 화면 어디에도 표시하지 않는다 — 표시는 멘토명/학생명만.

---

## 5. 최종 플래그 (현행)

```
SERVER_BLOCK_CONTRACT: PASS
APP_BLOCK_UI_CONTRACT: PASS
REPORT_TARGET_CONTRACT: PASS
QUESTION_ROOM_SAFETY_CONVERGENCE: PASS
```

---

## 6. 변경 이력

- **~2026-08-02 (S3-E 초안, superseded)**: 당시 앱 UI 만 차단을 강제했고
  `qna_append_message`·`qna_register_attachment` 서버 검사에 공백이 있었으며
  신고 어휘가 `comment`/`shortform` 이었다. 초안은 이를 `SERVER_BLOCK_CONTRACT_MISSING: YES`
  로 기록했다.
- **2026-08 (Build 13 DB 계약 수렴)**: 두 RPC 모두 당사자 판정 직후 · INSERT 이전에
  양방향 차단 검사 + 계정 상태 게이트가 추가되어 공백이 해소됐다. 신고 어휘도
  `board_comment`/`shortform_post` 정본으로 수렴했다. 위 §3~§5 가 현행 상태다.
  → **과거 공백은 해소된 이력이며 현재 결함이 아니다.**
