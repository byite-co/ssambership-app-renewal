# DB 스키마 정본 안내 (G4 — 2026-08-06 교정)

**이 저장소(앱)에는 마이그레이션 SQL 을 두지 않는다.** DB 스키마·RPC·RLS 의
정본은 **웹 저장소 `byite-co/ssambership_web` 의 `supabase/migrations/`
마이그레이션 팩**이며, Supabase 프로젝트 **ssambership-staging**
(`lbeqxarxothkmzqvpudy`)의 적용 원장과 1:1 로 유지된다.

> 초판(2026-08-06 오전)은 "서버 이력이 정본"이라고 적었으나, 재현 가능한
> 정본은 웹 저장소의 migration pack 이 맞다 — 서버 원장은 '적용된 사실'의
> 기록이고, pack 은 그것을 클린 DB 에서 재생하는 소스다. 리뷰 지적에 따라
> 교정하고, staging 직접 적용분 8건을 pack 에 backfill 했다
> (웹 저장소 브랜치 `claude/db-migration-backfill-20260806`).

## 왜 앱 저장소의 SQL 을 삭제했나

과거 `supabase/migrations/` 에 있던 4건(2026-07-07 자 IQ 첨부 RPC 계열)은
서버에 이미 적용된 뒤 후속 마이그레이션(v2 검증 보강, ACL 하드닝,
api_app_v1/api_web_v1 표면 재편 등)으로 **대체된 낡은 계약**이었다.
앱 저장소 SQL 을 스키마 문서로 오독하면 폐기된 계약을 참조하게 되므로
제거했다. 두 저장소에 SQL 이 이원화되면 같은 사고가 재발한다 — 앞으로의
모든 DB 변경은 웹 저장소 pack 에만 쓴다.

## 현행 계약을 보는 법

- **정본 SQL**: `ssambership_web/supabase/migrations/` (버전 정렬 순서 = 적용 순서)
- 적용 원장 대조: Supabase 대시보드 → Database → Migrations,
  또는 `supabase migration list --linked` — pack 버전 집합과 원장이
  일치해야 한다(2026-08-06 기준 **72건 == 72건** 검증 완료)
- 함수 정의 실측: `select pg_get_functiondef(oid) from pg_proc ...`
- 앱이 실제로 부르는 표면의 정본 목록: `test/contracts/outbound_api_manifest_test.dart`
  (신규 RPC/테이블 추가 시 이 매니페스트 갱신이 강제된다)

## 규율 (2026-08-06 재발 방지)

1. DB 변경은 **웹 저장소 pack 에 파일을 먼저 쓰고** 적용한다 —
   콘솔/MCP 직접 적용을 했다면 같은 날 pack 에 backfill 한다.
2. 데이터 보정도 가능하면 멱등 데이터 마이그레이션으로 원장에 남긴다.
3. pack 버전 집합 vs 원장 불일치는 그 자체가 결함이다.
