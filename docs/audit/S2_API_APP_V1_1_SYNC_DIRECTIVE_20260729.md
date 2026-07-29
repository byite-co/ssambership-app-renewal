# S2 — `api_app_v1` 계약 v1.1 동기화 지시서

- **작성일:** 2026-07-29 (rev 6 — 웹 정본 지시서 rev 6와 동기: 보상 삭제 RPC 폐기·F4 멱등 재시도 정본화·`deleteOwnPostForCompensation` 제거 의무, `HD-1` 직접 쓰기 전면 잠금, 커뮤니티 승인 멘토 한정·기존 학생 글 보존 동결, 늦은 재생 멱등 흡수, F11 원자적 duplicate 판정. rev 5: 멘토 전용 정책·room 표·오류코드 우선순위·M2 retired. rev 4: topup 정본·6필드 단일 계약. rev 3: `HD-1` 고정. rev 2: 공용 함수 대조표 의무. 상세는 웹 정본 지시서 A-5·A-6·A-9·A-10·C절 참조)
- **정본:** 웹 저장소 `docs/audit/s2_api_contract_v1_1_revision_directive_20260729.md` (같은 브랜치 `claude/schema-doc-verification-q876xf`). 전체 판정·근거·마이그레이션 정정은 정본을 따른다.
- **판정:** 전체 S2 GO 유지 · S2-1 계약서 REVISE · S2-2 SQL 구현 임시 NO-GO 유지.

## `api_app_v1` 계약 v1.0 → v1.1 필수 반영 항목

1. **F4/F5 시그니처 재배열 (§3.3, 생성 불가 결함):** DEFAULT 인자 뒤 필수 인자(`p_idempotency_key uuid`, `p_expected_updated_at timestamptz`) 배치는 PostgreSQL 42P13으로 `CREATE FUNCTION` 자체가 실패한다. 필수 인자 앞·DEFAULT 인자 뒤로 재배열하고 호출부는 named notation을 명시. 이 결함으로 v1.0의 Gate 4 "문서 게이트 PASS"는 소급 무효 — v1.1에서 재게이트.
2. **`SUBSCRIPTION_REFUND_PENDING` 오류 코드 정합화** (웹 계약과 코드 표기 통일).
3. **응답 envelope 가정 재기술** — 웹 계약 v1.1과 동일 구조로 고정.
4. **주간 사용량 조회 하드닝 반영:** 레거시 `get_weekly_question_usage`는 NULL-safe **pair-party** 가드(`auth.uid() IS DISTINCT FROM p_student_id AND ... p_mentor_id` + service_role 통과, `NOT_PAIR_PARTY`/42501)로 하드닝된다. 앱 호출은 전부 로그인 학생 본인 ID이므로 **영향 없음**을 계약에 명기.
5. **커뮤니티 직접 쓰기 전면 잠금 게이트(rev 6 개정):** 보상 삭제 대체 RPC는 **만들지 않는다**(오너 확정 — F4가 트랜잭션 RPC + 멱등키 필수이므로, 응답 불명확 시 같은 멱등키 재호출이 정본 복구 경로). 앱 측 의무: ① F4 전환(같은 멱등키 재시도 로직 포함) ② `deleteOwnPostForCompensation`(`board_author_gate.dart:183`)과 DB 게시글 hard DELETE 코드(`community_write_repository.dart:204-210`) 제거 — **Storage 신규 이미지 보상 삭제는 유지** ③ 직접 DELETE 0건 실측 후 `HD-1`(community_posts `REVOKE ALL`+`GRANT SELECT`, 쓰기 정책 6종 제거, M8에 얹지 않는 별도 마이그레이션) 적용. 상세는 웹 정본 지시서 C절.
6. **B-04 동결:** v1은 "금지어 검사 폐지, `POLICY_RESTRICTED`는 예약 코드이며 발생하지 않음"으로 고정. F4/F5 공용 검증부는 마스킹만 수행.
7. **B-07 blocker 해제(실측):** 앱 프로필 수정은 `lib/features/mypage/data/profile_edit_repository.dart:30`의 `users` UPDATE 단일 호출뿐 — `mentor_profiles` 쓰기 없음.
8. **공용 커뮤니티 내부 함수 대조표(오너 확정):** 웹·앱이 공유하는 커뮤니티 내부 함수에 대해 **이름·시그니처·오류코드·GRANT가 웹 계약 v1.1과 동일**함을 증명하는 대조표를 앱 계약 v1.1에 추가한다.
9. **커뮤니티 작성 = 승인 멘토 전용(rev 6 동결, 웹 정본 A-10):** F4 create는 승인 멘토만 — 역할 불일치 `ROLE_NOT_MENTOR`, 멘토지만 미승인 `MENTOR_NOT_APPROVED`(승인 판정은 `individual_question_user_is_approved_mentor` 동일 헬퍼). 앱 계약 v1.0의 `ROLE_NOT_ALLOWED`(학생·멘토 모두 허용) 정의 폐기, 앱 UI의 학생 작성 CTA 제거. 기존 학생 글은 열람 유지·수정 금지·본인 F6 soft-delete 허용·관리자 moderation 별도 경로(파괴적 정리 금지). 숏폼 `sf_insert_mentor`와 Storage INSERT 정책 2건도 동일 승인 헬퍼로 정합화.

## 다음 세션 규칙

- 산출물은 `api_app_v1 계약 v1.1` 문서 1건(웹 계약 v1.1과 같은 세션에서 개정). **SQL 작성·적용 금지.**
- 각 반영 항목에 정본 지시서의 절 번호(A-1, A-8, C, D 등)를 역기입해 추적 가능하게 할 것.
