# 최소 앱 버전(강제 업데이트) 서버 계약 요구서 — Track E 게이트

> 상태: **WAITING_SERVER_GATE** (2026-07-21 세션 3 재조회 기준 staging 에
> 버전 관련 테이블·함수 0건). 이 계약이 staging 에 배포되기 전에는
> 앱의 댓글 정본(`comments`) 전환과 구버전 차단 게이트를 착수하지 않는다
> (계획 §0-2: 서버 최소버전 응답 + 앱 시작 게이트가 모두 준비된 뒤에만).

## 왜 필요한가

게시판 댓글을 legacy `community_comments` → 정본 `comments` 로 전환하면
구버전 앱(legacy 에 쓰는)과 신버전 앱(정본에 쓰는)이 서로 다른 테이블에 쓴다.
데이터 갈라짐을 막으려면 전환 배포와 동시에 **구버전 앱을 차단**할 수단이 서버에 있어야 한다.

## 요구 계약 (웹·DB 측 구현 요청)

### 1안(권장): 읽기 전용 RPC

```sql
create or replace function public.get_app_version_policy(p_platform text)
returns jsonb language sql stable security definer set search_path to 'public'
as $$ ... $$;
-- 반환: {"min_supported_build": 12, "latest_build": 15,
--        "store_url": "...", "message": "..." }
grant execute on function public.get_app_version_policy(text) to anon, authenticated;
```

- `p_platform`: 'android' | 'ios'.
- `min_supported_build` 미만의 빌드는 앱이 시작 게이트에서 차단하고 스토어로 안내.
- anon 허용 필수(로그인 전 게이트).

### 2안: 테이블 + RLS(모두 읽기)

`app_version_policies(platform text pk, min_supported_build int, latest_build int, store_url text, message text, updated_at)` + `SELECT to anon, authenticated`.

## 앱 쪽 준비 상태(게이트 충족 시 1세션 내 전환 가능)

- 댓글 어댑터 전환 대상 파일: `community/data/*comment*`, `board_detail_screen.dart`
  (mounted 가드는 세션 1에서 이미 반영).
- `comments` 정본 RLS(visible/own/admin)는 staging 에 이미 배포 확인됨.
- 전환 시 함께 반영할 항목: `body↔content`·`status↔is_deleted` 어댑터, 게시판 hard DELETE 제거,
  parent 다른 post 답글 금지, 최대 2-depth, 신고·차단 대상 `comments`,
  숏폼은 `community_comments(post_type='shortform')` 유지.
- 앱 시작 게이트: 서버 응답 실패 시 안전한 재시도 화면(차단 아님), 최신 앱 정상 진입,
  `min_supported_build` 미만 차단 + 스토어 이동 버튼.

## 함께 요청할 것 (세션 3 발견)

- **계정 탈퇴 인앱 지원**: `account_deletion_request` / `account_deletion_cancel` 에
  `GRANT EXECUTE ... TO authenticated` (현재 service_role 전용이라 앱 직접 호출 불가 —
  앱 UX 는 계약 기준으로 구현·테스트 완료, grant 즉시 활성).
