# S3-E — 질문방 신고·차단 계약 (앱 기준 2026-08-02)

기준 스키마·함수 실측: Supabase `ssambership-staging`(2026-08-02).
이 문서는 **앱 저장소 관점의 계약 기록**이다. SQL 은 웹 저장소 소유이므로 여기서 바꾸지 않는다.

---

## 1. 신고(사용자) — 지원됨 ✅

앱은 질문방 상대(멘토↔학생)를 기존 `content_reports` 테이블로 신고한다.

| 컬럼 | 앱이 넣는 값 |
| --- | --- |
| `reporter_id` | `auth.uid()` (현재 사용자) |
| `target_type` | **`'user'`** |
| `target_id` | 상대 user id (`mentor_student_rooms` 참여자에서 도출) |
| `reason` | 공용 신고 시트 code (`inappropriate`/`spam`/`external_contact`/`copyright`/`etc`) |
| `description` | 선택(비었으면 컬럼 자체를 생략) |
| `status` | `'pending'` |

실측 제약:

- `content_reports.target_type` 은 `text NOT NULL` + CHECK `char_length(btrim(target_type)) > 0` **뿐**이다.
  허용값 enum/CHECK 이 없으므로 `'user'` 가 그대로 통과한다 → **DB 변경 불필요**.
- `content_reports.target_id` 는 `uuid` 이며 FK 가 없다 → 사용자 id 를 그대로 넣을 수 있다.
- RLS `content_reports_insert_reporter`: `WITH CHECK (reporter_id = auth.uid())`.
  조회는 `content_reports_select_reporter`(본인) / `content_reports_select_admin`(관리자)뿐이다.

기존 앱 target_type 값(웹 관리자 검수와 정합): `community_post`, `comment`,
`community_comment`, `shortform`. 여기에 **`user`** 가 추가된다.

> 운영/웹 요청: 관리자 검수 화면에서 `target_type='user'` 행을 "사용자 신고"로 렌더하고,
> `target_id` 를 `users.id` 로 조인해 표시할 것. (앱은 이미 적재 중)

**REPORT_CONTRACT_BLOCKED: NO**

---

## 2. 차단(사용자) — 앱 계층만 강제됨 ⚠️

`user_blocks` 실측:

- PK `(blocker_id, blocked_id)` → 중복 차단은 `unique_violation(23505)` = **멱등 성공**으로 처리.
- CHECK `user_blocks_check`: `blocker_id <> blocked_id` → **자기 차단은 DB 가 거부**한다.
- FK 두 컬럼 모두 `users(id) ON DELETE CASCADE`.
- RLS: `ub_insert_own` / `ub_delete_own` / `ub_select_own` 모두 `blocker_id = auth.uid()`.

앱은 차단 후 해당 질문방을 **읽기 전용**으로 만든다(composer 비활성, append·첨부 호출 0회).
차단 해제는 기존 `blocked_users_screen`(설정 > 차단 사용자 관리)에서 그대로 동작한다 —
같은 테이블·같은 레포를 쓴다.

### 2-1. 서버가 아직 막지 않는 지점 — `SERVER_BLOCK_CONTRACT_MISSING`

실측 함수 본문 기준:

| RPC | 차단 관계 검사 |
| --- | --- |
| `qna_create_question_thread` | ✅ 있음 — `BLOCKED` raise |
| `qna_append_message` | ❌ **없음** |
| `qna_register_attachment` | ❌ **없음** |

즉 **이미 만들어진 스레드에서는**, 차단 관계가 있어도 서버가 메시지·첨부를 받아준다.
앱이 composer 를 막고 있을 뿐이라, 구버전 앱·웹·직접 RPC 호출은 여전히 통과한다.

`qna_create_question_thread` 가 이미 쓰고 있는 검사와 **동일한 형태**를 두 함수에도
넣어야 계약이 닫힌다(웹 저장소 SQL 마이그레이션 필요):

```sql
-- qna_append_message / qna_register_attachment 공통.
-- 위치: 당사자 판정(v_student/v_mentor 확정) 직후, INSERT 이전.
-- 방향 무관(양쪽 차단 모두 거부) — create 경로와 동일.
if exists (
  select 1 from public.user_blocks
  where (blocker_id = v_student and blocked_id = v_mentor)
     or (blocker_id = v_mentor  and blocked_id = v_student)
) then
  raise exception 'BLOCKED';
end if;
```

수용 기준:

1. 차단 관계가 있는 방에서 `qna_append_message` 호출 → `BLOCKED` (행 0건 삽입).
2. 차단 관계가 있는 방에서 `qna_register_attachment` 호출 → `BLOCKED` (행 0건 삽입).
3. 차단이 없으면 기존 동작 그대로(회귀 없음) — answered 전이·알림 트리거 포함.
4. 반환/오류 형식은 `qna_create_question_thread` 와 동일(`raise exception 'BLOCKED'`).

앱 측 준비는 이미 끝나 있다 — `qna_error_mapper` 가 `BLOCKED` 를
"차단 상태의 상대와는 질문을 주고받을 수 없어요."로 매핑한다. 서버가 던지기만 하면
추가 앱 변경 없이 사용자 문구가 나온다.

**SERVER_BLOCK_CONTRACT_MISSING: YES** (앱 계층 강제는 완료, 서버 강제는 미배포)

---

## 3. 상대(counterparty) id 정본

`RoomCounterparty.of(room, currentUid:)` — `mentor_student_rooms.student_id` /
`mentor_id` 에서만 도출한다.

금지(코드로 강제됨): 메시지 첫 작성자 추정 · 화면 문자열 파싱 · 닉네임 조회 ·
UUID 하드코딩 · current user 와 동일한 id 허용.

도출 실패(방 정보 없음 / 당사자 아님 / 세션 없음)면 앱바 안전 메뉴를 **비활성화**한다.
raw UUID 는 화면 어디에도 표시하지 않는다 — 표시는 멘토명/학생명만.
