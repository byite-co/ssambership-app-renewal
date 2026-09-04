# UGC 신고·검수 프로세스 (앱 심사 증빙용) — 2026-07

> 목적: Apple App Store 가이드라인 1.2 및 Google Play UGC 정책이 요구하는
> "사용자 생성 콘텐츠(UGC)에 대한 (a)필터 (b)신고 (c)차단 (d)게시 전 동의 (e)신고에 대한 조치"
> 다섯 요건을, 앱 코드와 백엔드 운영이 각각 어디까지 담당하는지 근거와 함께 문서화한다.
> 심사관/운영자가 이 문서 하나로 신고~조치 전체 경로를 확인할 수 있게 한다.
>
> 근거 기준: 앱 `master`(2026-07 머지본) · 운영 DB `content_reports`(실측 스키마·RLS, 2026-07-17).

## 1. 요건 대응 요약

| Play/Apple UGC 요건 | 상태 | 담당 | 근거 |
|---|---|---|---|
| (a) 사전 필터/노출 통제 | 🟢 | 앱 | 차단 사용자 콘텐츠 피드 필터(`user_blocks` 기반 숨김), 게시 시 클라이언트 최소 검증 |
| (b) 신고 경로 | 🟢 | 앱 | 게시글·숏폼·**댓글** 신고 → `content_reports` INSERT (사유 선택 시트) |
| (c) 차단 | 🟢 | 앱 | 작성자 차단(`user_blocks`) → 차단자 뷰에서 해당 UGC 숨김(불변 쌍) |
| (d) 게시 전 동의(EULA/규정) | 🟢 | 앱 | `ContentPolicyGate` — 최초 게시 전 커뮤니티 이용 규정 능동 동의 1회 |
| (e) 신고에 대한 조치 | 🟢 | 백엔드/운영 | `content_reports` 관리자 처리(status·admin_note·resolved_by/at) + `user_warnings`·계정 상태 관리 |

## 2. 앱이 하는 일 (클라이언트)

- **신고 접수**: `community_write_repository.report(targetType, targetId, reason, description?)`
  → `content_reports` INSERT (`reporter_id=본인`, `status='pending'`).
  - 신고 대상 3종: `community_post`(게시글), `shortform`(숏폼), **`community_comment`(댓글 — 2026-07 #30에서 추가)**.
  - 사유(`report_sheet.dart`): 부적절/스팸/외부연락처 유도/저작권/기타.
- **차단**: `user_blocks_repository` → `user_blocks` INSERT. 차단자 피드·상세에서 차단 작성자 UGC 숨김.
- **게시 전 동의 게이트**: `content_policy_gate.dart` — 게시글·댓글 최초 작성 진입 시 1회 규정 동의(미동의 시 게시 중단). 세션 스코프 저장(앱 실행마다 최초 1회 노출).
- **표시 규칙**: 내부 id·UUID·DB명 비노출.

## 3. 백엔드/운영이 하는 일 (서버·관리자 콘솔)

운영 DB `content_reports`(실측): `status`, `admin_note`, `resolved_by`, `resolved_at` 컬럼 보유. RLS 정책:
- `content_reports_insert_reporter` (authenticated: 본인 신고 삽입)
- `content_reports_select_reporter` (authenticated: 본인 신고 조회)
- `content_reports_select_admin` / `content_reports_update_admin` / `content_reports_delete_admin` (관리자: 전체 조회·처리·삭제)

처리 흐름(운영): 신고 `pending` → 관리자 검토 → 조치(콘텐츠 삭제/숨김, 작성자 경고·정지) → `status` 갱신(`resolved`/`rejected` 등)·`admin_note`·`resolved_by`·`resolved_at` 기록. 연계 테이블: `user_warnings`(경고 누적 — 활성 3회 도달 시 앱 자동 일시정지), `admin_case_notes`(운영 메모 타임라인), `admin_action_logs`(관리자 액션 감사).

## 4. 처리 기준·SLA (운영 정책 — 콘솔/운영팀 확정 대상)

> 아래는 심사 노트에 기재할 권장 기준선. 실제 수치·담당은 운영팀이 확정한다(이 문서는 앱 저장소 근거이며, 운영 SLA 는 콘솔/내부 문서로 관리).

- **접수→1차 검토**: 24시간 이내 목표(음란·아동·폭력 등 중대 신고는 우선).
- **조치**: 위반 확인 시 콘텐츠 삭제/숨김 + 작성자 경고, 반복·중대 위반은 계정 정지(`user_warnings`/계정 상태).
- **재신고/이의**: 신고자·피신고자 문의 경로는 웹 `/support`.

## 5. 심사 노트에 넣을 한 줄

> "커뮤니티 UGC는 게시 전 규정 동의(앱)→신고/차단(앱, 댓글 포함)→관리자 검수·조치(`content_reports` 상태 처리 + 경고/정지)로 이어지는 완결된 신고-조치 파이프라인을 갖추고 있습니다. 신고 데이터는 관리자만 열람·처리합니다."

## 6. 남은 권장(비차단)

- 신고 즉시 로컬 숨김(신고자 뷰에서 해당 콘텐츠 즉시 가림) — Apple '신고에 대한 조치' 신호 강화(선택).
- 운영 SLA·에스컬레이션 표를 콘솔/내부 위키로 정식화(수치 확정).

---
_근거: 앱 `community_write_repository`·`content_policy_gate`·`user_blocks` / 운영 DB `content_reports`(스키마·RLS 실측 2026-07-17). 이 문서는 앱 저장소 관점의 증빙이며, 실제 운영 SLA·담당자 배정은 운영팀 소관이다._
