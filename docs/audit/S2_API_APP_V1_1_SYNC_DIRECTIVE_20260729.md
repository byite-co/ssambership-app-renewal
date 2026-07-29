# S2 — `api_app_v1` 계약 v1.1 동기화 지시서

- **작성일:** 2026-07-29 (rev 4 — 웹 정본 지시서 rev 4와 동기. rev 3: `HD-1` 논리 ID 고정·보상 삭제 RPC 대조표 연결. rev 2: 공용 커뮤니티 내부 함수 대조표 의무 추가, hard DELETE는 M8과 무관한 별도 마이그레이션으로 명시. rev 4 동결 사항: topup 정본 `idempotency_key` 단독(`ref_text` 제거), F12 관계 불일치 오류코드 4종, room 참조 정본성 — 상세는 웹 정본 지시서 A-5·A-6 참조)
- **정본:** 웹 저장소 `docs/audit/s2_api_contract_v1_1_revision_directive_20260729.md` (같은 브랜치 `claude/schema-doc-verification-q876xf`). 전체 판정·근거·마이그레이션 정정은 정본을 따른다.
- **판정:** 전체 S2 GO 유지 · S2-1 계약서 REVISE · S2-2 SQL 구현 임시 NO-GO 유지.

## `api_app_v1` 계약 v1.0 → v1.1 필수 반영 항목

1. **F4/F5 시그니처 재배열 (§3.3, 생성 불가 결함):** DEFAULT 인자 뒤 필수 인자(`p_idempotency_key uuid`, `p_expected_updated_at timestamptz`) 배치는 PostgreSQL 42P13으로 `CREATE FUNCTION` 자체가 실패한다. 필수 인자 앞·DEFAULT 인자 뒤로 재배열하고 호출부는 named notation을 명시. 이 결함으로 v1.0의 Gate 4 "문서 게이트 PASS"는 소급 무효 — v1.1에서 재게이트.
2. **`SUBSCRIPTION_REFUND_PENDING` 오류 코드 정합화** (웹 계약과 코드 표기 통일).
3. **응답 envelope 가정 재기술** — 웹 계약 v1.1과 동일 구조로 고정.
4. **주간 사용량 조회 하드닝 반영:** 레거시 `get_weekly_question_usage`는 NULL-safe **pair-party** 가드(`auth.uid() IS DISTINCT FROM p_student_id AND ... p_mentor_id` + service_role 통과, `NOT_PAIR_PARTY`/42501)로 하드닝된다. 앱 호출은 전부 로그인 학생 본인 ID이므로 **영향 없음**을 계약에 명기.
5. **커뮤니티 hard DELETE 단계 게이트:** 앱 `lib/features/community/data/community_write_repository.dart:204-210`의 `community_posts.delete()`(생성 실패 **보상 전용** 내부 경로)가 존재하므로, DELETE 권한·`cp_delete_own` 회수는 ① 대체 RPC 제공 → ② 앱 전환 배포 → ③ 회수 순서를 지킨다. 앱 계약에는 ②단계(보상 삭제의 RPC 전환)를 앱 측 의무로 기재. **이 회수는 M8(F7·F8 멘토 RPC 마이그레이션)에 얹지 않고 별도 마이그레이션 `HD-1`(논리 ID 고정)로 진행한다(오너 확정).** 보상 삭제 대체 RPC의 이름·시그니처·오류코드·GRANT는 v1.1 작성 세션이 확정하며, 8항의 공용 함수 대조표에 포함한다.
6. **B-04 동결:** v1은 "금지어 검사 폐지, `POLICY_RESTRICTED`는 예약 코드이며 발생하지 않음"으로 고정. F4/F5 공용 검증부는 마스킹만 수행.
7. **B-07 blocker 해제(실측):** 앱 프로필 수정은 `lib/features/mypage/data/profile_edit_repository.dart:30`의 `users` UPDATE 단일 호출뿐 — `mentor_profiles` 쓰기 없음.
8. **공용 커뮤니티 내부 함수 대조표(오너 확정):** 웹·앱이 공유하는 커뮤니티 내부 함수에 대해 **이름·시그니처·오류코드·GRANT가 웹 계약 v1.1과 동일**함을 증명하는 대조표를 앱 계약 v1.1에 추가한다.

## 다음 세션 규칙

- 산출물은 `api_app_v1 계약 v1.1` 문서 1건(웹 계약 v1.1과 같은 세션에서 개정). **SQL 작성·적용 금지.**
- 각 반영 항목에 정본 지시서의 절 번호(A-1, A-8, C, D 등)를 역기입해 추적 가능하게 할 것.
