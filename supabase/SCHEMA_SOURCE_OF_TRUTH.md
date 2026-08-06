# DB 스키마 정본 안내 (G4)

**이 저장소에는 마이그레이션 SQL 을 두지 않는다.** DB 스키마·RPC·RLS 의
정본은 Supabase 프로젝트 **ssambership-staging**(`lbeqxarxothkmzqvpudy`)의
마이그레이션 이력이다.

## 왜 삭제했나

과거 `supabase/migrations/` 에 있던 4건(2026-07-07 자 IQ 첨부 RPC 계열)은
서버에 이미 적용된 뒤 후속 서버 마이그레이션(v2 검증 보강, ACL 하드닝,
api_app_v1/api_web_v1 표면 재편 등)으로 **대체된 낡은 계약**이었다.
저장소 SQL 을 스키마 문서로 오독하면 이미 폐기된 계약(v1 시그니처,
낡은 grant)을 참조하게 되므로 저장소에서 제거했다(스냅샷: 아래 이력).

## 현행 계약을 보는 법

- 적용된 마이그레이션 목록: Supabase 대시보드 → Database → Migrations,
  또는 `supabase migration list --linked`
- 함수 정의 실측: `select pg_get_functiondef(oid) from pg_proc ...`
- 앱이 실제로 부르는 표면의 정본 목록: `test/contracts/outbound_api_manifest_test.dart`
  (신규 RPC/테이블 추가 시 이 매니페스트 갱신이 강제된다)

## 서버 마이그레이션 이력 스냅샷 (2026-08-06 기준, 67+4건)

`pre_ledger_baseline`(2026-07-01)에서 시작해 다음 흐름으로 수렴했다:

1. **2026-07 초**: 연결노트 잉크·IQ 첨부 RPC(v1→v2 검증 보강)·멘토 디렉터리 v2
2. **2026-07 중순**: 계정 상태/탈퇴/차단(102·115·116), 관리자 콘솔, 멱등키
   (게시판·숏폼), 정산·알림 워커 기반
3. **2026-07 말**: `public` defacl 하드닝, **api_web_v1/api_app_v1 스키마 표면
   재편**(뷰·RPC 단일 경로), 직접 쓰기 잠금(community/mentor_profiles/plans),
   권한 계약 assert
4. **2026-08 초**: Build13 계약 수렴, IQ append/attachment v1 확정 + ACL
   하드닝, 신원·프로필 잠금, 실시간 알림 수렴, 원장(ledger) 후 ACL/속성 수렴
5. **2026-08-06 (이 세션)**: `post_reactions` SELECT 본인 한정,
   `connection_notes` (room, author) UNIQUE, `community_post_view_record_v2`
   (게시판 조회수 멱등), `report_target_content_valid`(신고 대상 실존 검증)

전체 버전 목록은 서버 이력이 정본이므로 여기 복사하지 않는다 — 위
"보는 법"의 명령으로 항상 최신을 조회할 것.
