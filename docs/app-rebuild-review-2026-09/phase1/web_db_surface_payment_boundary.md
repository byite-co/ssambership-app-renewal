# 웹·앱 공유 Supabase — DB 표면 정본과 결제 경계 (Phase 1 리포트)

- 작성일: 2026-09-03 · 기준: 웹 저장소 `/home/user/ssambership_web` (migrations 112본, 마지막 `20260903230300`) · 앱 저장소 `/home/user/ssambership-app` (pubspec `version: 1.0.0+19`)
- 성격: **읽기 전용 실측 요약**. 코드·마이그레이션·계약 문서에서 확인된 사실만 적고, 확인하지 못한 것은 `(확인 필요)`로 표시한다.
- 라이브 DB 카탈로그는 직접 조회하지 않았다. 권한(ACL)·정책은 ① `docs/audit/remote_db_inventory_20260804/*.json`(2026-08-04 원격 실측 스냅샷) ② 그 이후 적용된 migration 파일(2026-08-05~2026-09-03) 을 순서대로 겹쳐 재구성했다. 따라서 "현재 라이브"는 **(스냅샷 + 이후 pack)** 의 합성이며, pack 과 원장이 1:1 이라는 규율(§5)이 전제다.
- 용어: `a/u/s` = anon / authenticated / service_role 의 EXECUTE(또는 SELECT) 보유 여부. `SECDEF` = SECURITY DEFINER.

---

## 0. 한 장 요약 (설계 에이전트용 판정 규칙)

1. **앱이 부를 수 있는 것** = (a) Data API 에 노출된 스키마(`public`·`api_web_v1`·`api_app_v1`) 안에서 (b) `authenticated`(로그인 전이면 `anon`) 에 EXECUTE/SELECT 가 있는 객체. `core_private`·`rls_private` 는 노출되지 않으며 외부 EXECUTE 도 0 이다 → **앱 직접 호출 불가**.
2. **service_role 전용 RPC 는 앱에서 절대 도달 불가**(service_role 키는 웹 서버 `lib/supabase/admin.ts` 에만 존재, `import "server-only"`). 앱이 그 기능을 쓰려면 ① `api_app_v1` 에 `auth.uid()` 자체 도출형 SECDEF thin wrapper 를 새로 만들거나 ② 웹 API route(앱 세션 부트스트랩) 를 경유해야 한다(§6).
3. **결제 경계**: `docs/policy/app-web-payment-separation.md` §1·§3 이 정본 — 캐시는 웹에서만 충전, 구독·IQ·맞춤의뢰의 **캐시 차감(결제 실행)** 은 웹 전용, 앱은 **잔액·원장·구독·정산 "읽기"** 만. 이 경계는 DB 권한과 정확히 일치한다: 자금 이동 RPC(충전·차감·hold·payout·refund·renewal·dispute split)는 전부 `service_role` 전용(§1.5, §4).
   - 예외적으로 DB 가 `authenticated` 에 열어 둔 **자금 인접 RPC 4종**이 있다 — IQ `create_individual_question_as_student` / `release_individual_question` / `refund_individual_question`(에스크로 hold·release·refund) 와 F13 정산계좌 RPC. "DB 가 허용" ≠ "정책이 허용"이며, 앱 포함 여부는 오너 결정(§4 판정표).
4. **DB 변경은 웹 저장소 pack 에만 쓴다**(`ssambership-app/supabase/SCHEMA_SOURCE_OF_TRUTH.md`). 앱 저장소에는 SQL 이 없고, 앱이 부르는 표면은 `test/contracts/outbound_api_manifest_test.dart` 가 잠근다(§5).

---

## §1 스키마 지도

### 1.1 Data API 노출 스키마

| 스키마 | 노출 | 근거 |
|---|---|---|
| `public` | 노출(유지) | 계약 §5.4 "public 은 레거시 호환 때문에 계속 노출" (`docs/contracts/api_web_v1_contract_v1_1.md:612-620`) |
| `api_web_v1` | 노출(D-API-W) | 계약 §20.6 (`:2463-2510`). 노출 목록은 플랫폼 설정이라 SQL 로 판정 불가(§20.6.1). **앱이 실제로 `.schema('api_web_v1')` 로 호출 중**(`ssambership-app/lib/features/mypage/data/mypage_repository.dart:139,159` 등 15 파일) → 사실상 노출. 대시보드 실측은 (확인 필요) |
| `api_app_v1` | 노출(D-API-A) | 위와 동일. 앱 `lib/features/mentors/data/free_question_entry.dart:170`, `lib/features/community/data/board_post_create_gateway.dart:27` 가 호출 |
| `core_private` | **절대 미노출** · 스키마 USAGE 를 anon/authenticated/service_role 어디에도 부여하지 않음 | `supabase/migrations/20260731100313_20260730095435_api_web_v1_schemas.sql:48-49,66-67`; 계약 §10.1 |
| `rls_private` | 미노출(정책 평가 전용) · USAGE authenticated, service_role | `supabase/migrations/20260806075316_report_target_content_valid_rpc_unexposed.sql:8-10` |

기본 권한 방어: `ALTER DEFAULT PRIVILEGES IN SCHEMA api_web_v1|core_private|api_app_v1 REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` (`20260731100313…:66-67`, `20260731114120…:88`). `public` 스키마도 2026-08-02 이후 새 테이블/시퀀스에 anon/authenticated/service_role 기본 CRUD 가 붙지 않는다(`20260802000000_public_defacl_hardening.sql:10-13`) — **신규 public 테이블은 GRANT 를 명시하지 않으면 service_role 도 못 읽는다.**

### 1.2 `api_app_v1` 소유 객체 전부 (schema 1 + view 1 + function 6)

| 객체 | 시그니처 → 반환 | 보안 | EXECUTE/SELECT | 구현부 | 근거 |
|---|---|---|---|---|---|
| schema `api_app_v1` | — | `REVOKE ALL FROM PUBLIC, anon` · `GRANT USAGE TO authenticated` (**service_role 없음** — 웹 `api_web_v1` 과의 의도적 차이) | — | — | `20260731114120_20260730112525_api_app_v1_surface.sql:85-88` |
| view `community_posts_v1` | 웹 V1 과 동일 14 컬럼 (`body=coalesce(content,body)`, `image_refs=coalesce(image_urls,'{}')`, `deleted_at IS NULL AND (published OR 본인)`) | `security_invoker=true` | SELECT → authenticated 만 | `public.community_posts` | `:93-118, 253-254` |
| `ensure_free_question_room(p_mentor_id uuid) → jsonb` | SECDEF, `search_path=''` | u | `core_private.ensure_student_mentor_room(auth.uid(), p_mentor_id, NULL, NULL, true)` | `:120-140, 257` |
| `qna_create_question_thread(p_room_id uuid, p_title text, p_subject text, p_topic text, p_first_message_body text) → jsonb` | SECDEF | u | `public.qna_create_question_thread` 호출 + raise→envelope 변환 + `FREE_QUESTION_*`→`FREE_QUOTA_*` 수렴 | `:142-190, 258` |
| `community_post_create(p_title text, p_body text, p_category text, p_idempotency_key uuid, p_image_refs text[] DEFAULT '{}', p_status text DEFAULT 'published') → jsonb` | SECDEF | u | `core_private.community_post_create_impl` | `:192-211, 259` |
| `community_post_update(p_post_id uuid, p_title text, p_body text, p_category text, p_expected_updated_at timestamptz, p_image_refs text[] DEFAULT '{}', p_status text DEFAULT 'published') → jsonb` | SECDEF | u | `core_private.community_post_update_impl` | `:213-232, 260` |
| `community_post_soft_delete(p_post_id uuid) → jsonb` | SECDEF | u | `core_private.community_post_soft_delete_impl` | `:234-251, 261` |
| `user_profile_update_self(p_nickname text, p_grade_level text) → jsonb` | SECDEF, `search_path=''` | u (`revoke … from public, anon`) | `core_private.user_profile_update_self_impl(auth.uid(), …)` | `20260803170552_20260803162257_security_identity_profile_lockdown.sql:251-264` |

**오류코드 envelope(앱·웹 공통)**: 성공 `{ "ok": true, "contract_version": 1, …도메인 필드 }` / 실패 `{ "ok": false, "code": "UPPER_SNAKE", "contract_version": 1 }` — 계약 §8.1 (`api_web_v1_contract_v1_1.md:1375-1400`). 게시판 create 의 `p_idempotency_key` NULL·`p_status` ∉ {draft,published} 는 envelope 이 아니라 SQL 예외로 전파(`docs/contracts/s3_c_build13_db_contract_20260802.md` §1.4 각주). 사전에 없는 예외는 삼키지 않고 전파(§8.2).

**커뮤니티 wrapper 의 현행 자격 규칙** (계약 v1.1 §7 F4 의 "승인 멘토 전용"은 **S3-C 로 폐지**): active student + active mentor 허용, admin/unknown → `ROLE_NOT_ALLOWED`, `deleted`·unknown·NULL status → `ACCOUNT_NOT_ACTIVE`(positive allowlist, fail-closed) — `s3_c_build13_db_contract_20260802.md` §1.3-1.4, 구현 `20260802054930_20260802024641_build13_db_contract_convergence.sql:358-627`.

### 1.3 `api_web_v1` — 뷰 V1~V5 · 함수 17종

| 객체 | 종류·시그니처 | 권한 (a/u/s) | 비고 · 근거 |
|---|---|---|---|
| V1 `community_posts_v1` | invoker 뷰 | S: a,u,s | `20260731100708_20260730095441_api_web_v1_read_views.sql:125,261` |
| V2 `community_comments_v1` | invoker 뷰(원천 `public.comments` 만; 라벨 = `comments.author_label/author_role` 비정규화) | S: a,u,s | 재정의 `20260903200200_community_soft_delete_deleted_at.sql:365` — `is_deleted=false AND deleted_at IS NULL` |
| V3 `mentor_directory_v1` | **SECDEF 뷰(유일한 의도적 예외)** — `users.role='mentor'` AND `status active` AND `verification_status IN (approved,verified,active)`; nickname 만(PII 0); 리뷰 집계 `moderation_state='visible' AND NOT hidden AND NOT blinded`; 삭제 진행 계정 제외 | S: a,u,s | 최초 `:173`, 재정의 `20260803170916_20260803162808_domain_contract_convergence.sql:153` |
| V4 `my_wallet_v1` | invoker 뷰 `(user_id, balance_cents, balance_krw=balance_cents/100)` | S: u,s | `:227, 264` — service_role 조회 시 전 사용자 행(BYPASSRLS, 계약 §10.2 주의) |
| V5 `my_cash_ledger_v1` | invoker 뷰 `(id, delta_cents, delta_krw, reason, ref_type, ref_id, order_ref, created_at)` — `order_ref = idempotency_key WHEN ref_type='topup'` | S: u,s | `:241, 264` |
| F1 `weekly_question_usage_self(p_mentor_id uuid) → jsonb` | SECDEF | u,s | `20260731102007_20260730105248_api_web_v1_self_rpc.sql:84,318` — 내부에서 `public.get_weekly_question_usage(auth.uid(), p_mentor_id)` |
| `weekly_question_usage_self_batch(p_mentor_ids uuid[]) → jsonb` | SECDEF | **u 만** | `20260806041547_weekly_question_usage_self_batch.sql:7-37` (앱이 사용 — manifest) |
| F2 `ensure_free_question_room(p_mentor_id uuid) → jsonb` | SECDEF | u,s | `:108, 319` |
| F3 `qna_create_question_thread(uuid,text,text,text,text) → jsonb` | SECDEF | u,s | `:131, 320` — 웹이 `supabase.schema("api_web_v1").rpc(...)` 로 호출 (`lib/qna/questionRoomRpc.ts:101`) |
| F9 `account_deletion_status_self() → jsonb` | SECDEF | u,s | `:184, 321` |
| V6 `my_subscriptions_self() → TABLE(subscription_id, mentor_id, mentor_label, plan_id, plan_tier, current_plan_amount_cents, status, started_at, current_period_start, current_period_end, next_billing_at, cancel_at_period_end, grace_until, created_at)` | STABLE SECDEF | u,s | `:208-225, 322` |
| V7 `mentor_settlement_self() → TABLE(item_id, subscription_id, student_label, event_type, billing_at, period_start, period_end, gross_cents, platform_fee_cents, mentor_amount_cents, fee_rate, status, hold_reason, paid_at, created_at)` | STABLE SECDEF | u,s | `:259-277, 323` — `idempotency_key/ledger_id/payment_id` 비노출 |
| F4/F5/F6 `community_post_create / _update / _soft_delete` | SECDEF (앱 동명 함수와 identity args 동일) | u,s | `20260731113927_20260730105252_api_web_v1_community_rpc.sql:423-495` |
| F7 `mentor_profile_update_self(p_university_name text, p_department_name text, p_high_school_name text, p_teaching_subjects text[], p_intro_line text, p_bio text, p_answer_style text, p_profile_image_url text, p_is_open_for_subscriptions boolean) → jsonb` | SECDEF — 9 컬럼 allowlist; `verification_status/cap_limit/payout_*/activity_status` 절대 갱신 안 함 | u,s | `20260731125643_20260730112528_api_web_v1_mentor_rpc.sql:65-71, 244` |
| F8 `mentor_plan_prices_set_self(p_limited_cash_krw integer, p_standard_cash_krw integer, p_premium_cash_krw integer) → jsonb` | SECDEF — 밴드 강제(29,900~69,900 / 84,900~149,900 / 174,900~329,900, 밴드 밖 `PLAN_PRICE_OUT_OF_BAND`), `cap_weight = public.subscription_cap_weight(tier)` | u,s | 최초 `:154`, 재정의 `20260903100100_cap_structure_limit_50_weights.sql:206-211` |
| F13 `mentor_payout_account_update_self(p_bank_name text, p_account_number text) → jsonb` | SECDEF — 승인 멘토만, 은행 allowlist 17종, `^[0-9]{8,24}$`, 응답은 `account_masked` | u,s | `20260731125802_…_payout_account_rpc.sql:52-118`, 재정의 `20260831100100_payout_bank_allowlist_add_im_bank.sql:45-110` |
| F11 `record_cash_topup_v2(p_user_id uuid, p_amount_cents bigint, p_order_ref text) → jsonb` | SECDEF — `^cash-(.+)-([0-9]+)$` 강제, 소유자 재검증, duplicate 6필드 NULL-safe 대조 | **s 만** | `20260731134000_20260730120103_money_rpc.sql:255-260, 630-632` |
| F12 `subscription_checkout_confirm_v2(p_payment_id uuid, p_plan_id uuid, p_expected_amount_cents integer, p_idempotency_key text DEFAULT NULL) → jsonb` | SECDEF — 잠금 payments→advisory→mentor_plans, 3자 일치(`PLAN_AMOUNT_CHANGED`), 재생 Phase1/2, `room_id` 반환 | **s 만** | `:332-338, 631-633` |
| `user_profile_update_self(p_nickname text, p_grade_level text) → jsonb` | SECDEF | u,s | `20260803170552…:269-282` |
| `user_marketing_consent_set_self(p_agreed boolean) → jsonb` | SECDEF — `user_consent_records` append + `users.marketing_agreed` 단일 트랜잭션 | u,s | `:287-330` |

### 1.4 `core_private` 공용 구현부 (7종 · 외부 EXECUTE 0 · 스키마 USAGE 0)

| 함수 | 보안 | 호출자 | 근거 |
|---|---|---|---|
| `ensure_student_mentor_room(p_student_id uuid, p_mentor_id uuid, p_payment_id uuid DEFAULT NULL, p_subscription_id uuid DEFAULT NULL, p_require_entitlement boolean DEFAULT true) → jsonb` (F10) | SECDEF, `search_path=''`, `REVOKE ALL … FROM PUBLIC` | 웹 F2·앱 `ensure_free_question_room`·F12 | `20260731101845_20260730105244_core_private_room_ensure.sql:75-82, 193` — 자격 판정 7단계(학생 역할→계정 상태·write-block→승인 멘토·상호 차단→학생 행 잠금+활성 구독/무료 자격→기존 방→`INSERT … ON CONFLICT (student_id, mentor_id) DO NOTHING`→재조회). **방 확보는 무료질문권을 소비하지 않는다** |
| `record_cash_topup_impl(uuid, bigint, text) → jsonb` | INVOKER | `public.record_cash_topup`(레거시 2층), F11 | `20260731134000…:155-160, 227` |
| `community_post_create_impl(p_author_id uuid, p_title text, p_body text, p_category text, p_image_refs text[], p_status text, p_idempotency_key uuid) → jsonb` | INVOKER | 웹 F4·앱 동명 | 최초 `20260731113927…:136`, 재정의 `20260802054930…:358` |
| `community_post_update_impl(p_author_id uuid, p_post_id uuid, p_title text, p_body text, p_category text, p_image_refs text[], p_status text, p_expected_updated_at timestamptz) → jsonb` | INVOKER | 웹 F5·앱 동명 | `:253` / `:494` |
| `community_post_soft_delete_impl(p_author_id uuid, p_post_id uuid) → jsonb` | INVOKER | 웹 F6·앱 동명 | `:365` |
| `community_image_refs_validate(p_owner_id uuid, p_image_refs text[]) → jsonb` | INVOKER — 허용 버킷 / 첫 세그먼트=소유자 / `storage.objects` 실존 / 소유자·MIME·크기 / ≤5 | 위 impl 3종 | `:77-80` |
| `user_profile_update_self_impl(p_user_id uuid, p_nickname text, p_grade_level text) → jsonb` | INVOKER | 앱·웹 `user_profile_update_self` | `20260803170552…:151-158, 246` |

**패턴 정본**: 얇은 SECDEF wrapper(스키마별) → `auth.uid()` 도출 → INVOKER 구현부(`core_private`, 소유자 권한 문맥) → 검증·쓰기. 판정 로직은 구현부 한 곳에만 둔다(계약 §5.2, §7 B). `rls_private.report_target_content_valid(p_target_type text, p_target_id uuid) → boolean`(STABLE SECDEF, u,s) 은 `content_reports` INSERT 정책 내부용 헬퍼다(`20260806075316…:12-29`, 재정의 `20260903200200…:469`).

### 1.5 `public` RPC — `authenticated` EXECUTE 가 있는 것(앱 호출 가능 표면)

출처: `docs/audit/remote_db_inventory_20260804/functions.json`(2026-08-04, public 213 함수 중 authenticated EXECUTE 130 — 트리거·정책 헬퍼 포함) + 이후 migration. **트리거 함수·storage 정책 헬퍼(`user_is_*`, `qra_*`, `cro_*` 등)는 EXECUTE 가 있어도 호출 표면이 아니다.** 아래는 사용자가 실제로 부를 만한 것만.

| 도메인 | 함수 (시그니처 → 반환) | 권한 | 용도 · 근거 |
|---|---|---|---|
| 계정 | `account_deletion_request_self_v2() → jsonb` · `account_deletion_request_self_consented_v2(p_acknowledged_balance_cents bigint) → jsonb` · `account_deletion_cancel_self() → jsonb` · `account_deletion_status_self() → jsonb` | u,s | 취소창·dry_run 서버 고정(구 `_self(int,bool)`·`_self_consented(int,bool,bigint)` 는 authenticated 회수 — `20260803170916…:763-805`). 취소 유예 30일(`20260808092007_account_deletion_server_cancel_window_30d.sql`) |
| 계정 | `account_deletion_write_blocked(p_user_id uuid) → boolean` | u,s | **self 전용** — 타인 uuid 면 `ACCOUNT_DELETION_PROBE_FORBIDDEN`(42501). 앱 부팅 프로필 로드가 사용(`20260806200000…:19-20`) |
| 계정 | `ugc_write_allowed() → boolean` | u,s | positive allowlist(active 또는 만료 suspended, role∈{student,mentor}, 삭제 미진행) — `20260802054930…:295-314` |
| 계정 | `admin_issue_user_warning(uuid,text,text)` · `approve_mentor_school_verification_admin(uuid,text,text,text,text,text)` | u,s | **T4b — 관리자 JWT 필수**(`is_admin()` 이 `auth.uid()` 검사) — 앱 비대상 |
| 질문방 | `qna_create_question_thread(p_room_id uuid, p_title text, p_subject text=NULL, p_topic text=NULL, p_first_message_body text=NULL) → jsonb` · `qna_create_free_question_thread(...)`(위임 래퍼) · `qna_append_message(p_thread_id uuid, p_body text) → jsonb` · `qna_confirm_thread(uuid)` · `qna_flag_wrong_answer(uuid, boolean=true)` · `qna_register_attachment(p_thread_id uuid, p_storage_path text, p_file_name text=NULL, p_mime_type text=NULL, p_message_id uuid=NULL) → jsonb` | u,s | 전부 raise 방식(`AUTH_REQUIRED`…`SUBSCRIPTION_REFUND_PENDING`, `ACCOUNT_NOT_ACTIVE`, `BLOCKED`) — `APP_V16_SERVER_CONTRACT_SNAPSHOT.md` §1, `s3_c…` §5. 첨부 경로 `{room_id}/{thread_id}/…`, `storage.objects.owner_id=auth.uid()` 검증 |
| 질문방 | `get_weekly_question_usage(p_student_id uuid, p_mentor_id uuid) → json` | **a,u,s** | pair-party 가드(M15 `20260731095136…:24-31`): service_role 또는 `auth.uid()` = 학생 또는 멘토가 아니면 42501 `NOT_PAIR_PARTY`. anon EXECUTE 는 미회수(U-08) |
| 질문방 | `get_mentor_student_nicknames(p_student_ids uuid[]) → TABLE(id, nickname, full_name)` | u,s | 멘토 화면용 |
| 개별질문 | `create_individual_question_as_student(p_question_type text, p_title text, p_body text, p_amount_cents integer, p_designated_mentor_id uuid, p_idempotency_key text) → individual_questions` | u,s | **캐시 hold 발생**(에스크로) — §4 |
| 개별질문 | `claim_individual_question_as_mentor(p_question_id uuid) → individual_question_escrow_result` · `answer_individual_question(p_question_id uuid, p_body text) → individual_questions` · `iq_append_message(p_question_id uuid, p_body text) → jsonb` · `add_individual_question_attachment(p_question_id uuid, p_storage_path text, p_file_name text, p_mime_type text, p_message_id uuid=NULL) → jsonb` | u,s | 답변·대화·첨부(계정 4종·차단·`MESSAGE_AUTHOR_MISMATCH` 가드 — `20260804113000…:10-12`) |
| 개별질문 | `release_individual_question(p_question_id uuid)` · `refund_individual_question(p_question_id uuid)` → `individual_question_escrow_result` | u,s | 소유자 검사 후 service_role 코어(`release_individual_question_payout` / `refund_individual_question_hold`)에 위임 — **자금 이동** (§4) |
| 개별질문 | `list_open_individual_questions_for_mentor(p_limit integer=50) → TABLE(id, subject, topic, title, price_cents, expires_at, created_at, required_school_tier, required_major_category)` | u,s | 재생성 `20260807010000…:22-85` |
| 개별질문 | `set_individual_question_price(p_amount_cents integer) → SETOF mentor_individual_question_pricing` | u,s | 멘토 IQ 단가(§4 가격 설정) |
| 맞춤의뢰 | `custom_order_mentor_start(uuid)` · `custom_order_mentor_deliver(uuid)` · `custom_order_student_request_revision(uuid, text)` → jsonb | u,s | 상태 전이(자금 없음) |
| 맞춤의뢰 | `get_public_custom_request_post_for_browse(uuid)` · `list_open_custom_request_posts_for_mentor_browse(integer)` → TABLE(23열) | a,u,s | 공개 조회 |
| 커뮤니티 | `community_comment_soft_delete_self(p_comment_id uuid) → jsonb` | **u 만** | 숏폼 댓글 본인 삭제(`20260803170916…:383-435`, 재정의 `20260903200200…:485`) |
| 커뮤니티 | `soft_delete_own_content(p_kind text, p_id uuid) → void` | u,s | **DB-3 신설** — `p_kind ∈ shortform / shortform_comment / board_comment / board_post`; `AUTH_REQUIRED`(28000)·`INVALID_KIND`·`CONTENT_NOT_FOUND`·`CONTENT_NOT_OWNED`(42501)·`CONTENT_KIND_MISMATCH`·`CONTENT_MODERATED`·계정 4종; 멱등 (`20260903230100_soft_delete_own_content_rpc.sql:10-28, 77-166`) |
| 커뮤니티 | `community_post_view_record_v2(p_post_id uuid, p_event_key uuid)` · `shortform_view_record_v2(p_post_id uuid, p_event_key uuid)` → jsonb | **a,u**(service_role 없음) | (post, event_key) 멱등 조회수(`20260806033556…:22-60`, `20260803170916…:319-355`). 구 `increment_community_post_view(uuid)` 는 a,u,s 잔존, `increment_shortform_post_view` 는 service_role 전용으로 회수(`:358`) |
| 커뮤니티 | `my_blocked_users() → TABLE(blocked_id, nickname, created_at)` | **u 만** | 차단 목록 표시명(`20260807020000…:27-53`) |
| 커뮤니티 | `report_target_user_valid(p_target_id uuid) → boolean` | u,s | `content_reports` INSERT 정책 헬퍼(직접 호출 의미 없음) |
| 멘토·리뷰 | `get_mentor_avg_response_hours(uuid) → numeric` · `get_mentor_review_stats(p_mentor_id uuid, p_include_hidden boolean=false) → TABLE(review_count, avg_rating, d1..d5)` | a,u,s | 공개 조회(`get_mentor_review_stats` 재정의 `20260803170916…:124` — visible predicate 단일화) |
| 멘토·리뷰 | `check_review_eligibility(p_mentor_id uuid, p_student_id uuid) → boolean` | u,s | `reviews_insert_student` 정책 내장 |
| 멘토 | `mentor_cap_limit(uuid) → numeric`(SECDEF) · `mentor_cap_used(uuid) → numeric` · `subscription_cap_weight(text) → numeric` | a,u,s | cap 정본(1.0/2.25/4.75 · 한도 50 — `20260903100100…:93-116`) |
| 정산 | `mentor_settlement_lines(p_from timestamptz, p_to timestamptz)` · `mentor_settlement_summary(p_month date=NULL)` · `calc_withholding_cents(p_mentor_amount_cents bigint) → bigint` | **u 만**(lines/summary) · u,s(calc) | SECDEF + `auth.uid()` 고정, `due_payouts` 모집단과 동기화(`20260827100200…:70-212`, `20260827100300…:8-207`) |
| 알림 | `mark_all_notifications_read() → integer` · `mark_notification_read(p_notification_id uuid) → jsonb` · `notification_unread_count_self() → jsonb` | u,s | `20260803171053…:182-249` |
| 알림 | `register_device_token(p_token text, p_platform text='unknown') → jsonb` | u(재부여) | `on conflict(token) do update` 재소유 내장. `20260827100100_device_token_register_grant.sql:8` (헤더: "라이브 미적용 — 오너 승인 후 적용" — **적용 여부 확인 필요**). `revoke_device_token(uuid)` 는 service_role 전용 → 앱은 RLS 로 `device_tokens.revoked_at` 본인 UPDATE |
| 알림 | `notification_delivery_allowed(uuid,text)` · `notification_event_group(text)` | u,s / a,u,s | 설정 판정(행 없음 = 허용) |
| 버전 | `get_mobile_app_version_policy(p_platform text) → jsonb` | **a,u,s** | §7 |

### 1.6 `public` service_role 전용 RPC 전수 (= 앱 직접 호출 불가)

`functions.json` 실측 73종(2026-08-04) 중 자금·상태 확정·worker·관리자·레거시. 이후 추가: `account_deletion_purge_identity_payment_artifacts(uuid)`(`20260820100700…:68-69`). `record_custom_order_dispute_split` 은 재정의 후에도 service_role 전용(`20260903100200…:335-341`).

| 그룹 | 함수 |
|---|---|
| 캐시 충전 | `record_cash_topup(p_user_id uuid, p_amount_cents bigint, p_idempotency_key text) → void`(2층, duplicate 무음) |
| 구독 자금 | `confirm_subscription_checkout(p_payment_id uuid, p_plan_id uuid, p_idempotency_key text=NULL) → jsonb` · `record_subscription_cash_debit(uuid,uuid,uuid,bigint)` · `record_subscription_cash_rollback(…)`(웹 호출 0) · `process_subscription_renewal(p_subscription_id uuid, p_period_end timestamptz, p_amount_cents bigint, p_idempotency_key text, p_processed_at timestamptz=now()) → TABLE(...)` · `refresh_subscription_settlement_items(p_from, p_to)` · `pay_due_payouts_for_run(p_run_date date, p_idempotency_key text, p_dry_run boolean)` · `run_scheduled_payout(p_run_date date, p_force_dry_run boolean)` · `payout_reconciliation_report(date)` |
| IQ 자금 코어 | `create_individual_question_with_hold(9 args)` · `create_individual_question_with_hold_v2(… + p_required_school_tier text, p_required_major_category text)` · `claim_individual_question(uuid,uuid)` · `claim_individual_question_v2(uuid,uuid)` · `release_individual_question_payout(uuid)` · `refund_individual_question_hold(uuid)` |
| 맞춤의뢰 자금 | `record_custom_order_escrow_hold(p_student_id uuid, p_order_id uuid, p_amount_cents bigint)` · `record_custom_order_escrow_payout(uuid)` · `record_custom_order_escrow_refund(uuid)` · `accept_custom_order_deliverable_atomic(p_order_id uuid, p_student_id uuid, p_require_payment boolean=true) → jsonb` · `record_custom_order_dispute_split(p_order_id uuid, p_mentor_gross_won integer, p_student_refund_won integer, p_admin_id uuid) → jsonb`(요율 = 정산 행 `fee_rate`, 없으면 `SETTLEMENT_FEE_RATE_MISSING`) · `_cro_transition_*` 헬퍼 9종 |
| 환불 관리자 | `approve_refund_request_admin(p_refund_id uuid, p_admin_id uuid, p_admin_note text)` · `reject_refund_request_admin(…)` (T4a — `p_admin_id` 인자) |
| 계정 탈퇴 worker | `account_deletion_request(uuid,int,bool)` · `account_deletion_request_consented(uuid,int,bool,bool,bigint)`(웹 정본) · `account_deletion_cancel(uuid)` · `account_deletion_request_self(int,bool)` · `account_deletion_request_self_consented(int,bool,bigint)` · `account_deletion_claim(text,int,int)` · `_begin_locked` · `_advance` · `_record_error` · `_revoke_sessions` · `_storage_owner_refs` · `_verify_object_owners` · `_forfeit_and_anonymize` · `_reclaim_expired` · `_active_job_id` · `_latest_job_id` · `_self_response` · `anonymize_user_for_deletion(uuid,text)` · `_purge_identity_payment_artifacts(uuid)` |
| 알림 worker | `record_domain_notification(9 args)`(트리거 내부 경로) · `notification_outbox_claim/mark_sent/mark_failed/reclaim_expired` · `notification_create_deliveries(uuid)` · `notification_delivery_mark_sent/failed` · `notification_display_name(uuid)` · `notification_mentor_label(uuid)` · `revoke_device_token(uuid)` |
| 레거시 공개 조회(회수됨) | `mentor_directory_list(_v2)` · `mentor_profiles_for_directory(_v2)` · `mentor_user_public(_v2)` · `increment_shortform_post_view(uuid)` — 앱 manifest 가 **금지어**로 잠금(`outbound_api_manifest_test.dart:129-138`) |
| 기타 | `mp_seed_default_plans_on_approval()` · `enforce_users_role_guard()` · `enforce_users_role_insert_guard()` · `handle_new_auth_user_consent_records()` · `mentor_school_verification_storage_path(text)` |

외부 EXECUTE 0(소유자 전용): `account_deletion_worker_claim(int)`(전면 회수) · `qna_emit_answer_notification(uuid,uuid,uuid)` · `account_deletion_state_blocked(uuid)`(`20260806200000…:51-53`) · DB-1~3 헬퍼 `school_tier_suggest(text)` · `major_category_suggest(text)` · `auto_school_verification()` · `school_verification_reassess_on_academic_change()` · `comments_sync_deleted_flag()` · `ugc_block_hard_delete()` · 라벨/알림 트리거 함수.

---

## §2 직접 테이블 RLS 매트릭스 (authenticated 관점)

표기: ✅ = 정책상 가능(조건), ❌ = 정책 없음 또는 GRANT 회수(=불가). GRANT 열은 `grants_tables.json`(2026-08-04) + 이후 REVOKE. 정책 이름은 `policies.json` + 이후 migration. 트리거는 `pg_trigger` 전수 재집계가 아니라 migration 파일에서 확인된 것만.

| 테이블 | SELECT | INSERT | UPDATE | DELETE | GRANT(auth) | 트리거·제약 가드 | 근거 |
|---|---|---|---|---|---|---|---|
| `users` | ✅ 본인(`users_select_own`) / admin 전체 | ✅ 본인(`users_insert_own` — 가입 self-insert) | ❌ **GRANT UPDATE 회수**(정책 `users_update_own` 은 남아 있으나 실효 없음) | ❌ | S,I | `trg_users_role_guard`, `trg_users_role_insert_guard`, `trg_users_protected_columns`(status/suspended_until/동의시각 등 클라이언트 변경 거부), `users.status` CHECK(active/suspended/banned/deleted) | `20260803170552…:92-136`; 프로필 수정은 `user_profile_update_self` RPC |
| `mentor_profiles` | ✅ 본인(`mentor_select_own`) / admin(`mp_admin_select_all`) — 타인 행은 V3 뷰로만 | ❌ | ❌ | ❌ | **S 만**(M11) | `trg_mentor_profile_privileged_guard_ins/upd`(verification_status·cap_limit 특권 컬럼, 기본값 50 대비), `trg_mp_seed_default_plans`, `trg_auto_school_verification`(승인 시 pending 인증행 자동 생성), `trg_school_verification_reassess_on_academic_change`, `cap_limit` 기본 50 | `20260731135324…:80-81`; `20260903100100…:138-175`; `20260903100300…:203-241, 340-384` |
| `mentor_plans` | ✅ 전체(`mplan_select` USING true, anon 포함) | ❌ | ❌ | ❌ | **S 만**(M12) | `mplan_notify_price_changed`, `uq_mentor_plans_mentor_tier(mentor_id, plan_tier)`, `cap_weight` 는 함수값 참조 컬럼 | `20260731135445…:63-64` |
| `mentor_individual_question_pricing` | ✅ 전체(`miqp_select_authenticated` true) | ❌(정책 없음) | ❌ | ❌ | DIRSTTU(잉여) | PK(mentor_id) · 쓰기는 `set_individual_question_price` | policies.json |
| `subscriptions` | ✅ 당사자(`subscriptions_select_parties`) | ❌ | ❌ | ❌ | **S 만** | `trg_enforce_mentor_cap`(UPDATE OF status, plan_tier), `trg_subscriptions_keep_refunded_status`, `trg_sub_notify_expired`, `funding_source` CHECK(cash/pg, NULL=cash) | `20260803170916…:643-661`; `20260820100600…` |
| `subscription_billing_events` | ✅ 당사자/admin | ❌ | ❌ | ❌ | S 만 | `trg_sbe_notify_*` | 동상 |
| `subscription_settlement_items` | ✅ 멘토 본인(`ssi_select_mentor_own`) | ❌ | ❌ | ❌ | R,S,T,T | `trg_block_settlement_on_active_dispute` | — (권장: V7/`mentor_settlement_lines`) |
| `cash_wallets` / `cash_ledger` | ✅ 본인(`cwal_select`/`cled_select`) | ❌ | ❌ | ❌ | **S 만** | `adg_cash_wallets`(AFTER INSERT/UPDATE), `adg_cash_ledger`(AFTER INSERT) — `account_deletion_state_blocked` 검사; `cash_ledger_idempotency_key_key` UNIQUE | `20260806200000…:102-107`; 권장 V4/V5 |
| `payments` | ✅ 당사자(`payments_select_own`) | ✅ 본인 pending/processing intent(`payments_insert_intent`) | ❌ | ❌ | I,S | `adg_payments`; `pg_*` 컬럼은 서버가 덮어씀(클라이언트 선입력 불신 — `20260820100400…:13-17`) | policies.json |
| `refunds` | ✅ 본인/admin(`refund_select`) | ❌ **admin 만**(`refund_ins`) | ❌ | ❌ | I,S | `set_refunds_updated_at`, `sync_subscription_refunded_from_refund`, `refund_notify_mentor_termination` | 학생 환불 신청은 웹 service_role INSERT(§4) |
| `mentor_student_rooms` | ✅ 당사자(`msr_select`) | ❌ **정책 없음** | ❌ | ❌ | DIRSTTU(잉여) | `uq_msr_pair(student_id, mentor_id)` | 방 생성은 F10 경유만 |
| `question_threads` | ✅ 방 당사자(`qt_select_via_room`) | ✅ 방 당사자(`qt_write_via_room`) | ✅ 방 당사자(`qt_update_via_room`) | ❌ | DIRSTTU | `trg_qt_direct_write_guard`(직접 INSERT 는 학생·status pending/open·workflow 필드 금지, RPC 와 동일 검사; UPDATE 에서 answered 전이 금지 `DIRECT_ANSWERED_VIA_CONTENT_ONLY`), `trg_qt_direct_consume_free_usage`, status CHECK(pending/answered/confirmed/open/closed/archived) | SNAPSHOT §1.8, §3 — **정본은 RPC** |
| `question_messages` | ✅ 당사자(`qm_select`) | ✅ 당사자+`author_id=auth.uid()`(`qm_insert`) | ❌ | ❌ | DIRSTTU | `trg_qm_direct_write_guard`, `trg_qm_direct_answered_after`, `trg_qm_answer_notification_after`(멘토→학생 `question_answered`, 학생→멘토 `question_received`), `adg_question_messages` | `20260801054636…`, `20260806201500…` |
| `question_attachments` | ✅ 당사자(`question_attachments_select_via_room`) | ✅ 당사자(`…_insert_via_room`) | ❌ | ❌ | DIRSTTU | `trg_qa_direct_write_guard`, `trg_qa_direct_answered_after`, `trg_qa_answer_notification_after`, `question_attachments_storage_path_key` UNIQUE | SNAPSHOT §2 |
| `connection_notes` | ✅ 방 당사자(`cn_select`) | ✅ 작성자=본인 AND 방 당사자(`cn_insert`) | ✅ 동일(`cn_update`) | ✅ 동일(`cn_delete`) | DIRSTTU | UNIQUE(room, author)(`20260806033452…`); FK 컬럼명 `mentor_student_room_id` | policies.json |
| `free_question_usage` | ✅ 본인(`fqu_select_own`) | ✅ 본인(`fqu_insert_own`) | ❌ | ❌ | DIRSTTU | `check_free_question_usage_limits`(7일/총 7/멘토별 3 — `FREE_QUESTION_*` P0001~P0003), UNIQUE(thread_id) | 계약 §3.4 |
| `individual_questions` | ✅ 당사자(`iq_select_party`) | ❌ | ❌ | ❌ | DIRSTTU(잉여) | `iq_notify_assigned`, `iq_notify_status_transition` | RPC 전용 |
| `individual_question_messages` | ✅ 당사자(`iqm_select_party`) | ❌ | ❌ | ❌ | DIRSTTU(잉여) | `iqm_notify_message` | `iq_append_message` |
| `individual_question_attachments` | ✅ 당사자(`iqa_select_party`) | ❌ | ❌ | ❌ | **S 만** | — | `20260808075345…:33-34`; `add_individual_question_attachment` |
| `individual_question_transfers` | ✅ 학생 본인 | ❌ | ❌ | ❌ | DIRSTTU(잉여) | — | policies.json |
| `community_posts` | ✅ `cp_select_visible`: `deleted_at IS NULL AND (published OR 본인)` / admin 전체 | ❌ | ❌ | ❌ | **S 만**(M16) | `adg_community_posts`, `community_posts_author_idem_key` UNIQUE(author_id, create_idempotency_key), `deleted_by` 컬럼(194) | `20260731170632…:23-30`; `20260806200500…:31-39` |
| `comments`(게시판 댓글 정본) | ✅ `comments_select_visible`: `is_deleted=false AND deleted_at IS NULL` / admin | ✅ 본인 AND `ugc_write_allowed()`(`comments_insert_own`) | ✅ 본인 AND ugc(`comments_update_own`) — 단 새 행이 SELECT 정책을 통과해야 하므로 삭제 플래그 UPDATE 는 실패 → `soft_delete_own_content` | ❌ **트리거 차단**(`trg_comments_no_delete`, 정책 `comments_delete_own` 무력) | DIRSTTU | `comments_write_guard`(2-depth, `COMMENT_PARENT_POST_MISMATCH`, `COMMENT_PROTECTED_FIELDS_IMMUTABLE`), `trg_comments_set_author_label_ins/upd`(라벨 서버 덮어쓰기·snapshot 보호), `trg_comments_sync_deleted_flag`, `trg_comments_refresh_count`, 163/164 브리지(`cc_sync_*`/`comments_mirror_*`) | `20260903200200…:396-402`; `20260903230100…:4-8`; `20260903230300…:87` |
| `community_comments`(숏폼 댓글·레거시 board) | ✅ `deleted_at IS NULL AND (status='visible' OR 본인)` / admin | ✅ 본인 + 본문 길이 + ugc(`community_comments_insert_authenticated`) | ❌(admin 만) | ❌ 트리거 차단(`trg_community_comments_no_delete`) | DIRSTTU | `cc_write_guard`, 라벨 트리거(board·shortform), status CHECK(+deleted) | `20260903200200…:404-412` |
| `post_reactions` | ✅ **본인 행만**(`post_reactions_select_own`; 전체 공개 정책 제거) | ✅ 본인+ugc | ❌ | ✅ 본인+ugc | DIRSTTU | `community_refresh_post_like_count` — 카운트는 `community_posts.like_count` 로 읽는다 | `20260806033409…:9-12` |
| `shortform_posts` | ✅ `deleted_at IS NULL AND (published OR 본인)` / admin | ✅ `is_mentor()` AND 본인 AND ugc(`sf_insert_mentor`) | ✅ 본인+ugc(`sf_update_own`) / admin | ❌ 트리거 차단(`trg_shortform_posts_no_delete`; 정책 `sf_delete_own` 무력) | DIRSTTU | `trg_shortform_posts_protected`(보호 컬럼 클라이언트 변경 거부), `adg_shortform_posts`, `deleted_at/deleted_by`(194) | `20260903200200…:383-394`; `20260903230300…:83` |
| `shortform_reactions` | ✅ 본인만 | ✅ 본인, type∈{like,scrap}, ugc | ❌ | ✅ 본인+ugc | DIRSTTU | UNIQUE(user_id, shortform_id, type) | SNAPSHOT §4.4 |
| `content_reports` | ✅ 본인 신고(`content_reports_select_reporter`) / admin | ✅ `reporter_id=auth.uid() AND status='pending' AND admin_note/resolved_* IS NULL AND target_type ∈ {community_post, shortform_post, board_comment, community_comment, user} AND (user→`report_target_user_valid`, 콘텐츠→`rls_private.report_target_content_valid`)` | ❌(admin) | ❌(admin) | DIRSTTU | `content_reports_dedupe_open_before_insert`(pending·reviewing 중복 신고는 멱등 갱신) | `s3_c…` §3; `20260806075316…:31-44`; `20260806201000…:44-109` |
| `user_blocks` | ✅ 본인(`ub_select_own`)/admin | ✅ 본인 | ❌ | ✅ 본인 | DIRSTTU | — | policies.json |
| `favorites` | ✅ 본인 | ✅ 본인 | ❌ | ✅ 본인 | DIRSTTU | (정책 role=public 3종; 한글명 중복 제거 `20260803170916…:754-756`). 198 헤더는 `mentor_favorites` 로 표기 — 실제 테이블명은 `favorites`(확인 필요: 앱 `_table` 상수) | policies.json |
| `reviews` | ✅ 공개 visible / 작성자 / admin | ✅ `author_id=auth.uid() AND check_review_eligibility(mentor_id, auth.uid())` | ✅ 작성자(미모더레이션)/멘토/admin — **컬럼별 인가는 `trg_reviews_enforce_update`**(rating·body 작성자만, 멘토는 `mentor_reply` 1회) | ❌ | DIRSTTU | 위 트리거 | 계약 XW-N1 |
| `notifications` | ✅ 수신자(`notif_select_recipient`: `recipient_user_id` + 레거시 컬럼 OR) | ❌ | ✅ 수신자(읽음 — `notif_update_recipient_read`) | ❌ | **S,U 만** | `trg_notifications_read_state_sync`(is_read↔read 미러), UNIQUE(recipient_user_id, event_key) | `20260803171053…:97-168, 335-336` |
| `notification_settings` | ✅ 본인 | ✅ 본인 | ✅ 본인 | ✅ 본인(`notif_settings_modify_own` ALL) | S,I,U | — | baseline `20260701000000…:20014-20027` |
| `device_tokens` | ✅ 본인 | ✅ 본인(ALL) | ✅ 본인 | ✅ 본인 | DIRSTTU(anon 0) | `token` UNIQUE, platform CHECK | baseline `:19967-19983` |
| `notification_outbox` / `notification_deliveries` / `notification_transport_config` | ❌ | ❌ | ❌ | ❌ | **없음**(service_role/postgres 전용) | — | `:17903`, `:20054-20069`, `20260803171053…:254-260, 334` |
| `app_notices` | ✅ 활성·기간 내 / admin (`app_notices_select`, anon 포함) | admin | admin | admin | DIRSTTU | `display_mode` 컬럼 추가(`20260830140804…`) | policies.json |
| `subjects` | ✅ 전체(anon 포함) | ❌ | ❌ | ❌ | DIRSTTU | 35 code 정본 | SNAPSHOT §4.5 |
| `custom_request_posts` | ✅ 작성자/admin/(멘토 browse 는 RPC) — 공개 `누구나 의뢰 읽기` 제거 | ✅ 작성자(`crp_insert`) | ✅ 작성자(`crp_update`) | ❌ | DIRSTTU | — | `20260802054930…:836-839` |
| `custom_request_applications` | ✅ 지원 멘토/글 작성자/admin | ✅ 멘토 본인(`cra_insert`) | ✅ 멘토 본인 | ❌ | DIRSTTU | `cra_notify_new_application`; **웹은 멘토 지원 전 `requireVerifiedIdentity` 서버 게이트**(`lib/identity/identityGate.ts:3-4`, 호출 `lib/customRequest/customRequestApplicationActions.ts`) — DB 게이트 없음 | policies.json |
| `custom_request_orders` | ✅ 당사자(student/buyer/client/user/mentor)/admin | ✅ 학생 본인(`cro_insert`) | ✅ 당사자(`cro_update`) | ❌ | DIRSTTU | 상태 전이는 RPC(`custom_order_*`, `_cro_transition_*` service_role) | 주문 생성은 웹 `createCustomRequestOrderWithEscrowHold`(service_role) |
| `custom_order_messages` / `_deliverables` / `_revisions` / `order_events` | ✅ 당사자/admin | ✅ 당사자(멘토 납품·학생 수정요청·당사자 메시지·이벤트) | ❌ | ❌ | DIRSTTU | — | policies.json |
| `custom_order_message_attachments` | ✅ 당사자 | ✅ 업로더=본인 AND 당사자 | ❌ | ✅ 업로더/admin | DIRSTTU | — | policies.json |
| `custom_order_settlement_items` | ✅ 당사자/admin(`cosi_select_parties`) | ❌ | admin | ❌ | DIRSTTU | `trg_block_settlement_on_active_dispute`; `fee_rate` NOT NULL default 0.05 | `20260903100200…:19` |
| `disputes` | ✅ 당사자/admin | ✅ 당사자(주문 분쟁, `custom_request_order_id` 필수) | admin | ❌ | DIRSTTU | active 분쟁 1건 UNIQUE(009) | policies.json |
| `mentor_school_verifications` | ✅ 본인/admin | ✅ 본인 pending(`msv_insert_own_pending`) | ✅ 본인 pending/resubmit_required(제한 컬럼) / admin | ❌ | DIRSTTU | `mentor_school_verifications_guard_self_review`; 자동 판정 = pending·`reviewed_by IS NULL`(잠정), 관리자 확정 RPC 로 approved | `20260903100300…`, `20260903200100…` |
| `mentor_academic_record_change_requests` | ✅ 본인/admin | ✅ 본인 pending | ✅ 본인 pending | ❌ | DIRSTTU | `mentor_acad_change_guard_self_review` | policies.json |
| `user_consent_records` | ✅ 본인 | ❌ | ❌ | ❌ | R,S,T,T | — | policies.json |
| `paysync_invoices` | ✅ 본인(`paysync_invoices_select_own`) | ❌ | ❌ | ❌ | **S 만** | `adg_paysync_invoices`, `paysync_invoices_ledger_ref_shape` CHECK | `20260830100100…:104-117` |
| `identity_verifications` / `billing_keys` / `nice_auth_tokens` / `portone_webhook_events` / `account_deletion_jobs` / `mobile_app_version_policies` / `payout_runs` / `payout_settings` / `subscription_checkout_anomalies` / `user_deletion_log` / `shortform_view_events` / `community_post_view_events` | ❌ 전부 | ❌ | ❌ | ❌ | 없음(service_role 전용, RLS on·정책 0) | `adg_identity_verifications`, `adg_billing_keys` | `20260820100100…:34-36`, `…100200:65-67`, `…100300:48-50`, `…100500:32-34`; baseline `:21324-21325` |

### 2.1 2026-07-30 lockdown 이후 REVOKE 된 직접 쓰기(시간순)

| 적용 | 대상 | 내용 |
|---|---|---|
| 2026-07-31 (M11) | `mentor_profiles` | `REVOKE ALL FROM anon, authenticated; GRANT SELECT` — 컬럼 단위 REVOKE 는 무효(A-3)라 테이블 단위. `20260731135324…:80-81` |
| 2026-07-31 (M12) | `mentor_plans` | 동일. `20260731135445…:63-64` |
| 2026-07-31 (M16 HD-1) | `community_posts` | `REVOKE ALL` + `GRANT SELECT` + 쓰기 정책 6종 DROP(`cp_write_self`, `로그인 유저 게시글 작성`, `cp_update_own`, `cp_update_self`, `본인 게시글 수정`, `cp_delete_own`). `20260731170632…:23-30` |
| 2026-08-02 | `public` default ACL | 신규 테이블/시퀀스의 anon·authenticated·service_role 기본 권한 회수. `20260802000000…:10-13` |
| 2026-08-03 | `users` | anon: I/U/D/T/R/TRIGGER 회수 · authenticated: U/D/T/R/TRIGGER 회수(SELECT·INSERT 유지). `20260803170552…:92-93` |
| 2026-08-03 | 금융 테이블 10종 | `cash_wallets, cash_ledger, subscriptions, cash_topup_packages, subscription_billing_events, order_payments, payments, refunds, withdrawals, user_warnings`: anon 전 write 회수 · authenticated U/D/T/R/TRIGGER 회수 · 6종 INSERT 회수(`payments`·`refunds`·`withdrawals` INSERT 는 정책상 필요해 유지). `20260803170916…:643-661` |
| 2026-08-03 | 레거시 RPC | `mentor_directory_list_v2 / mentor_profiles_for_directory_v2 / mentor_user_public_v2` anon·authenticated 회수(`:203-205`), `increment_shortform_post_view` 회수(`:358`), `account_deletion_request_self(int,bool)`·`_self_consented(int,bool,bigint)` authenticated 회수(`:804-805`) |
| 2026-08-03 | `notifications` / `notification_outbox` | notifications: anon SELECT/UPDATE + 양 역할 I/D/T/R/TRIGGER 회수 · outbox: anon/authenticated ALL 회수 · `register_device_token` 회수(`20260803171053…:333-336`) → 2026-08-27 authenticated 재부여(`20260827100100…:8`, 라이브 적용 여부 확인 필요) |
| 2026-08-06 | `report_target_content_valid` | public 노출 헬퍼 DROP → `rls_private` 이동. `20260806075316…:45` |
| 2026-08-08 | `individual_question_attachments` | `REVOKE ALL FROM anon, authenticated; GRANT SELECT`. `20260808075345…:33-34` |
| 2026-09-03 (DB-3) | `shortform_posts`, `comments`, `community_comments` | 하드 DELETE 트리거 차단(`ugc_block_hard_delete`, `current_user ∈ {anon, authenticated}` → `UGC_HARD_DELETE_FORBIDDEN` 42501; service_role/postgres/supabase_auth_admin 통과). GRANT 는 회수하지 않음. `20260903230300…:62-91` |

**남아 있는 잉여 GRANT**: `mentor_student_rooms`, `individual_questions`, `individual_question_messages`, `mentor_individual_question_pricing`, `subjects`, `app_notices` 등은 authenticated 에 DIRSTTU 7종 GRANT 가 남아 있으나 쓰기 정책이 없어 RLS 가 거부한다(deny-by-default). 앱 설계 시 "GRANT 가 있다"를 "쓸 수 있다"로 읽지 말 것.

---

## §3 Storage · Realtime · 알림

### 3.1 Storage 버킷 13종 (`buckets.json` 2026-08-04 + baseline 정의)

| 버킷 | public | 크기 | MIME | INSERT 정책 (authenticated) | SELECT 정책 | UPDATE/DELETE | 경로 규약 |
|---|---|---|---|---|---|---|---|
| `community-post-images` | false | 5 MiB | jpeg/png/webp/gif | `cpi_auth_insert_own`: 첫 폴더 = `auth.uid()` AND NOT write_blocked | `cpi_public_read`: **버킷 전체**(anon+auth) — XW-06 미해소(U-02) | `cpi_auth_update_own`/`cpi_auth_delete_own`(본인 폴더) | `{uid}/{uuid}-{safe_name}.{ext}`; DB ref `community-post-images/{uid}/{object}`; 서명 TTL 3600s (계약 §14.1-14.3) |
| `question-room-attachments` | false | 20 MiB | png/jpeg/webp/gif/pdf/zip/docx/pptx | `qra_storage_insert_party`: `user_is_room_party_for_qra_path AND qra_thread_writable_for_path AND qra_uploader_allowed_for_path AND qra_path_upload_eligible AND NOT write_blocked` | 방 당사자(`qra_storage_read_party`) / admin | DELETE `qra_storage_delete_unregistered_owner`: `owner_id=auth.uid()` AND `question_attachments.storage_path` 미등록 객체만 | `{room_id}/{thread_id}/…`; 등록은 `qna_register_attachment`(업로드 선행); TTL 3600s |
| `individual-question-attachments` | false | 20 MiB | 위 + `application/json` | `iqa_storage_insert_party`: 질문 당사자(경로 첫 세그먼트 = question uuid) | 당사자(`iqa_storage_read_party`) | UPDATE `iqa_storage_update_party_annotations`: `split_part(name,'/',2)='annotations'` 만 · DELETE 미등록 소유 객체 | `{question_id}/…`, 첨삭 `{question_id}/annotations/…`; 등록 `add_individual_question_attachment`; TTL 600s; 업로더 컬럼 `author_id`(2026-08-03 추가) |
| `profile-avatars` | **true** | 5 MiB | jpeg/png/webp | `pa_auth_insert_own`(본인 폴더) | `pa_public_read`(버킷 전체) | own | `{uid}/…`; F7 은 `/profile-avatars/` marker 또는 순수 경로에서 첫 세그먼트=uid 검증(`PROFILE_IMAGE_REF_INVALID`) |
| `student-id-images` | false | 무제한 | 무제한 | `student_id_images_insert_own`: `split_part(name,'/',1)=uid` | 본인 + admin | own U/D | `{uid}/…`; `mentor_profiles.student_id_image_url` 갱신은 service_role(웹 `lib/mentor/mentorStudentIdActions.ts:74-76`) |
| `shortform-videos` / `shortform-thumbnails` | false | 500 MiB / 5 MiB | mp4/quicktime/webm · jpeg/png/webp | `sfv_mentor_insert`(1정책·2버킷): `is_mentor()` AND 본인 폴더 AND NOT write_blocked | `sfv_public_read`: 버킷 전체(anon+auth) | `sfv_mentor_delete_own` | `{uid}/…`; 썸네일 쓰기 경로 부재(XW-19) |
| `connection-note-ink` | false | 무제한 | 무제한 | `connection_note_ink_obj_insert`: 첫 폴더 = room uuid 이고 방 당사자 | 방 당사자 | UPDATE 당사자 | `{room_id}/…` (앱 사용, 웹 미배선) |
| `scan-annotations` | false | 무제한 | 무제한 | `scan_annotations_obj_insert`: 방 당사자 | 방 당사자 + admin | UPDATE 당사자 | `{room_id}/…` (앱 사용) |
| `custom-order-deliverables` | false | 20 MiB | pdf/이미지/zip/docx/pptx | 주문 멘토(`user_is_mentor_of_cro_storage_path`) | 당사자(`user_can_read_cro_deliverable_storage_path`) | — | 경로에서 order uuid 추출(`cro_uuid_from_deliverable_storage_path`) |
| `custom-order-message-attachments` | false | 20 MiB | 동일 | 경로의 order_id·uploader_id 일치 AND 당사자 | 등록 행 기준 당사자 | DELETE 업로더/admin | `…/{order_id}/…/{uploader_id}/…` (헬퍼 `custom_order_message_attachment_order_id_from_path`, `_uploader_id_from_path`) |
| `custom-request-post-attachments` | false | 20 MiB | 동일 | 글 작성자(`user_is_post_author_for_crpa_path`) | 권한 함수(admin/멘토/작성자) | — | `crp_uuid_from_post_attachment_path` |
| `custom-request-application-attachments` | false | 20 MiB | 동일 | 지원 멘토(`user_is_application_mentor_for_craa_path`) | 권한 함수 | — | `craa_application_uuid_from_path` |

전역 RESTRICTIVE 가드 2종: `adg_storage_block_insert_when_deleting`(INSERT) · `adg_storage_block_update_when_deleting`(UPDATE) — `NOT account_deletion_write_blocked(auth.uid())` 가 모든 버킷 정책과 AND 결합(policies.json; 계약 §3.5). 서명 URL 기본 TTL 7일은 신규 도메인에서 사용 금지, 도메인별 명시(계약 §14.2). 앱 manifest 가 고정한 앱 사용 버킷 6종: `individual-question-attachments, question-room-attachments, connection-note-ink, scan-annotations, shortform-videos, community-post-images`(`outbound_api_manifest_test.dart:118-126`).

**주의(소유자 기록)**: service_role 로 업로드한 객체는 `storage.objects.owner_id` 가 NULL 로 남아 탈퇴 삭제 수집기(`account_deletion_storage_owner_refs`)에 잡히지 않는다(`20260806202500…:10-25`). 앱은 사용자 세션으로 업로드하므로 owner_id 가 채워진다 — 신규 서버 경로를 만들 때 이 함정을 반복하지 말 것.

### 3.2 Realtime

- publication `supabase_realtime` 테이블 7종: `question_threads, question_messages, question_attachments`(구) + `notifications, individual_questions, individual_question_messages, individual_question_attachments`(수렴 M3 `20260803171053…:82`; `publications.json`).
- 앱 채널(전부 `postgres_changes` · public 채널 · 테이블 RLS 로 필터): `question_thread_<threadId>`(`lib/features/question_room/data/thread_realtime.dart:44`), `iq_<questionId>`(`lib/features/individual_question/data/iq_realtime.dart:54`), `notifications_<userId>`(`lib/features/notifications/data/notifications_realtime.dart:47`). 웹은 질문방·IQ·알림 Realtime 을 쓰지 않는다(계약 §13.5).
- `realtime.messages` 정책(DB-3, `20260903230200…:56-70`): `realtime_admin_topic_select` / `realtime_admin_topic_insert` — `realtime.topic() LIKE 'admin:%' AND is_admin()` 인 authenticated 만. 그 외 토픽은 정책 0 = private 채널 join 전부 거부(현행 유지). 웹 PR-2b Presence 채널 `admin:mentor-approval` 은 `config.private=true` 로 전환 예정(PR-W3). **앱이 Broadcast/Presence private 채널을 새로 쓰려면 토픽별 `realtime.messages` 정책을 먼저 추가해야 한다.**
- 신규 뷰는 publication 대상이 될 수 없다(계약 §13.5) — Realtime 은 기존 7 테이블 구독 + RLS 유지가 정본.

### 3.3 알림 outbox / deliveries / device_tokens

| 객체 | 정의 | 앱 접촉 |
|---|---|---|
| `notifications` | 수신자 정본 `recipient_user_id`(+`user_id` 미러, 레거시 `recipient_id/student_id/mentor_id/target_user_id/owner_id` OR), 읽음 정본 `is_read`+`read_at`(`read` 미러 트리거), `type`, `body`, `data{title,link}`, `metadata{event_key, link, …id}`, UNIQUE(recipient_user_id, event_key), 커서 `(created_at DESC, id DESC)` | SELECT/UPDATE 본인 + Realtime `notifications_<uid>` + `mark_notification_read`/`mark_all_notifications_read`/`notification_unread_count_self` |
| `notification_outbox` | `(id, recipient_user_id, notification_id, event_key, dedup_key, event_type, payload, status, attempt_count, max_attempts, lease_owner, leased_until, next_attempt_at, last_error, …)` — baseline `:17903-17919`. `record_domain_notification` 이 인앱 행은 항상 생성, outbox 는 `notification_transport_config.push_transport_enabled=true` 일 때만(`20260803171053…:19-23`) | 없음(service_role) |
| `notification_deliveries` | `(outbox_id FK, device_token_id FK, status pending/sent/failed/dead/skipped, attempt_count, last_error, sent_at)` UNIQUE(outbox_id, device_token_id) — `:20054-20069` | 없음 |
| `device_tokens` | `(id, user_id, token UNIQUE, platform ios/android/web/unknown, revoked_at, …)`; RLS own — `:19967-19983` | `register_device_token(token, platform)`(authenticated — 재소유 원자) · 로그아웃 시 `revoked_at` 본인 UPDATE(RLS) — `20260827100100…:6-7` |
| `notification_settings` | `(user_id PK, push_enabled bool, groups jsonb)`; 행 없음/키 없음 = ON 의미론 | 본인 RLS |
| 발송 worker | `app/api/cron/notification-outbox/route.ts`(GET, `CRON_SECRET`, 플래그 `NOTIFICATION_OUTBOX_WORKER_ENABLED` → `FCM_TRANSPORT_MODE` 기본 dry-run; `notification_outbox_reclaim_expired/claim/mark_sent/mark_failed`, `notification_create_deliveries`, `notification_delivery_mark_sent/failed`) | 없음 |
| 이벤트 type | 17종(SNAPSHOT §4.1) + `question_received`(학생→멘토 메시지·무료질문 — `20260806201500…`, `20260806203000…`). IQ 계열은 `link` NULL → `metadata.question_id` 가 딥링크 정본. `subscription_renewal_failed_insufficient_cash` 의 link `/wallet/charge` 는 **앱에서 결제 화면 금지(Commerce-Zero)** 처리 필요 | — |

---

## §4 결제 경계 판정표

정본: `docs/policy/app-web-payment-separation.md` §1(한 줄 원칙) · §3(경계표) · §4(앱 금지 유형: 충전·결제 화면/버튼, 웹 결제 URL 딥링크, "웹에서 충전" 류 우회 문구, 가격표+구매 유도 조합, 잔액 0 충전 권유, 푸시로 충전 유도; **허용: "캐시가 부족합니다" 상태 표시 자체**). 앱 현행 정책 상수: `kInAppPaymentSteeringEnabled=false`, `kSubscriptionManageLinkEnabled`(기본 false), `kPayoutManageLinkEnabled`(기본 false), `kIndividualQuestionCreateEnabled`(기본 false, 켜져도 웹 등록 페이지로만) — `ssambership-app/lib/core/commerce/commerce_policy.dart:10-39`, `lib/features/individual_question/iq_flags.dart:10-19`.

분류: **[실행·앱 제외]** = 결제(캐시 충전/차감·hold·payout) 실행 / **[읽기·앱 허용]** / **[모호]** = 자금 인접이지만 소비자 결제가 아닌 행위 — 권고안을 제시하되 최종 결정은 오너.

| # | 웹 기능 | 라우트·서버 표면 | DB 권한(a/u/s) | 판정 | 근거·권고 |
|---|---|---|---|---|---|
| 1 | **캐시 충전(Toss 카드)** | `/wallet/charge` · `app/api/toss/confirm`(금액 검증·멱등·webhook 서명) · `lib/toss/confirmCashTopupServer.ts:84-86` → `api_web_v1.record_cash_topup_v2`(F11) · `app/api/toss/webhook/route.ts` | F11 **s 만**; `record_cash_topup` s 만 | **[실행·앱 제외]** | 정책 §3 "✅ `/wallet/charge` 유일 진입 · 앱 ❌ 화면·버튼·링크·문구 전면 금지" |
| 2 | **캐시 충전(페이싱크 무통장)** | `lib/paysync/paysyncChargeActions.ts:21-70`(request/cancel/refresh, service_role) · `app/api/paysync/webhook/route.ts` · `app/api/cron/paysync-reconcile/route.ts` · `paysync_invoices`(ledger_order_ref = F11 형식) | `paysync_invoices` SELECT 본인(u) · 쓰기 s | **[실행·앱 제외]** — pending 주문 조회도 "충전 화면"에 해당하므로 **앱 비표시 권고** | `20260830100100…:8-27, 104-111`; 정책 §4 |
| 3 | **구독 시작(캐시 차감)** | `app/api/subscribe/checkout/route.ts`(`requireVerifiedIdentity` 게이트) · `lib/subscribe/subscribeCheckoutService.ts:439-545` → `api_web_v1.subscription_checkout_confirm_v2`(F12) / `public.confirm_subscription_checkout` | **s 만** | **[실행·앱 제외]** | 정책 §3 "구독 결제(캐시 차감) 앱 ❌ · 상태 조회만"; 계약 §19.1 |
| 4 | **구독 상태·목록 조회** | `api_web_v1.my_subscriptions_self()` · `subscriptions` SELECT 당사자 | u,s | **[읽기·앱 허용]** | 앱 manifest 가 `subscriptions` 를 이미 읽음 |
| 5 | **구독 해지 예약 / 예약 취소(undo)** | `lib/subscribe/subscriptionCancelActions.ts:93-165` — `requireRole("student")` 후 **service_role 로 `subscriptions.cancel_at_period_end/cancel_requested_at` UPDATE**(authenticated 는 UPDATE GRANT·정책 없음) · 사용자 화면 `/subscriptions` | 전용 RPC **없음**; 직접 UPDATE 불가 | **[모호]** | 정책 §3 및 계약 §19.1 은 "구독 변경·해지 = 웹 ✅ 앱 ❌", 앱은 링크 숨김 + 안내문 "구독 변경·해지는 웹 계정에서 관리돼요"(`commerce_policy.dart:18-23`). **권고**: 해지 예약은 결제 유도가 아니라 *결제 중단* 행위이며 Play 결제 정책의 "외부 결제 유도" 유형(정책 §4)에 해당하지 않는다 → **조건부 앱 포함 가능**(가격·갱신 재유도 문구 없이 "다음 갱신 중단"만). 이를 위해선 `api_app_v1.subscription_cancel_at_period_end_self(p_subscription_id uuid)` 류 SECDEF RPC 신설 필요(§6 #1). undo(재개)는 "다음 결제에 다시 동의"에 가까워 **웹 위임 유지 권고**. 최종 결정: 오너 |
| 6 | **구독 갱신(자동 차감)** | `app/api/cron/subscription-renewal/route.ts`(GET, `CRON_SECRET`, `SUBSCRIPTION_RENEWAL_ENABLED`) → `process_subscription_renewal` | s 만 | **[실행·앱 제외]** | 앱은 `subscription_renewal_*` 알림 읽기만; `/wallet/charge` 링크 억제 |
| 7 | **환불 신청(구독 잔여기간 환불)** | `subscriptionCancelActions.ts:168-260 requestSubscriptionProratedRefundAction` — 사유 5자 이상, 서버 산정 금액, **service_role 로 `refunds` INSERT**(`refund_ins` 는 admin 만) · `/support/refunds` | `refunds` SELECT 본인(u); INSERT 정책 admin 만 | **[모호]** | 정책 §3 "원칙 ❌(웹 안내) — 신청서가 결제 유도 없이 성립하면 추후 재검토". **권고**: 환불 *신청* 은 구매가 아니며 Play/Apple 정책이 금지하는 유형이 아니다(Apple 은 IAP 환불을 Apple 경유로 요구하지만 본 앱은 IAP 0). 다만 신청 화면이 결제내역·금액을 노출하므로 결제 인접. 포함 시 `refund_request_subscription_self(p_subscription_id, p_reason)` SECDEF 신설(금액 서버 산정) 필요. 오너 결정 |
| 8 | 환불 승인·거절 | `lib/admin/refundActions.ts` → `approve/reject_refund_request_admin`(T4a) | s 만 | **[관리자·앱 제외]** | 계약 §3.3(A) |
| 9 | **개별질문 생성(캐시 hold)** | `lib/individualQuestion/individualQuestionActions.ts:121-300` — `requireVerifiedIdentity` + 계정 게이트 후 service_role `create_individual_question_with_hold_v2` (subject/topic/required_school_tier/major 포함) · 앱 등록 CTA 는 웹 페이지로만 | 웹 코어 s 만; **DB 에는 `create_individual_question_as_student(text,text,text,integer,uuid,text)` 가 u 로 열려 있음**(subject/tier 인자 없음) | **[모호 → 현행은 실행·앱 제외]** | 앱 `iq_flags.dart:13-19`(A안: 스토어 빌드 off, on 전환 게이트 = Play 결제 정책 검토 완료 — `PLAY_STORE_REVIEW_PLAN.md` D-1, 릴리즈 게이트). "기충전 캐시를 앱 내 디지털 재화에 소비"가 Play Billing 대상인지가 쟁점. Apple 3.1.3(b) 다중플랫폼 조항은 타 플랫폼 구매분 사용을 허용하되 IAP 병행 제공 조건이 있다(**법무 확인 필요**). **권고: 웹 위임 유지**(현행). 포함하려면 tier/major 인자를 받는 `_v2` authenticated wrapper 도 필요 |
| 10 | IQ claim(멘토 선점) · answer · message · 첨부 | 웹: service_role `claim_individual_question_v2` / admin UPDATE / admin INSERT(`:303-430`); DB: `claim_individual_question_as_mentor`, `answer_individual_question`, `iq_append_message`, `add_individual_question_attachment` | u,s | **[상태 전이·앱 허용]** | 자금 이동 없음(hold 유지). 앱이 이미 사용(manifest). 정책 §3 "진행 상태 조회/소통 허용" |
| 11 | **IQ release(학생 해결완료 → 멘토 85% 지급)** | 웹 `:489-532` service_role `release_individual_question_payout` · DB `release_individual_question(uuid)`(소유자 검사 후 코어 위임) | u,s | **[모호]** | hold→payout 은 자금 이동이지만 **소비자의 새 결제가 아니라 에스크로 확정**. 앱이 이미 호출(2026-08-06 QA-A1 403 수정 `20260806200000…`). **권고: 앱 허용 유지**(금액 표시 최소화). 오너 확인 |
| 12 | **IQ refund(학생 취소 환불)** · 만료 환불 배치 | DB `refund_individual_question(uuid)`(u) · 배치 `app/api/cron/individual-question-expiry` → `refund_individual_question_hold`(s) | u,s / s | **[앱 허용(환불) / 앱 제외(배치)]** | 지갑으로 되돌리는 행위 — 구매 아님. 앱 manifest 포함 |
| 13 | **맞춤의뢰 주문 생성(에스크로 hold)** | `lib/customRequest/customOrderEscrowService.ts:132-185 createCustomRequestOrderWithEscrowHold` → `record_custom_order_escrow_hold`(s) · `requireVerifiedIdentity`(`lib/customRequest/customRequestOrderActions.ts`) | s 만 | **[실행·앱 제외]** | 정책 §3 "맞춤의뢰 결제(escrow) 앱 ❌ · 진행 상태 조회/소통 허용" |
| 14 | **맞춤의뢰 납품 수락(에스크로 → 멘토 지급 95%)** | `lib/customRequest/orderSettlementService.ts:80-87` → `accept_custom_order_deliverable_atomic(p_order_id, p_student_id, p_require_payment)`(s 만, `p_student_id` 인자) | s 만 | **[모호]** | #11 과 동형(에스크로 확정)이나 현재 앱 도달 불가. 포함 시 `custom_order_accept_deliverable_self(p_order_id)` SECDEF(auth.uid()) 신설(§6 #4). 오너 결정 |
| 15 | 맞춤의뢰 분쟁 분배 | `lib/customRequest/customOrderDisputeSplitService.ts` → `record_custom_order_dispute_split`(요율 = 정산 행 `fee_rate`) | s 만 | **[관리자·앱 제외]** | `20260903100200…` |
| 16 | 맞춤의뢰 진행(작업 시작·납품·수정요청·메시지·이벤트·분쟁 제기) | `custom_order_mentor_start/deliver/student_request_revision`(u), `custom_order_messages`/`order_events`/`disputes` INSERT RLS | u | **[앱 허용]** | 자금 없음 |
| 17 | 맞춤의뢰 글 등록 / 멘토 지원 | `custom_request_posts` crp_insert · `custom_request_applications` cra_insert (RLS) · 웹은 멘토 지원 전 **본인인증 서버 게이트**(`identityGate.ts:3-4`, `IDENTITY_GATE_ENABLED` env) | u | **[앱 허용 — 단 게이트 공백]** | DB 레벨 본인인증 게이트는 "절대 금지"로 설계됨(`identityGate.ts:4-6`) → 앱이 직접 INSERT 하면 본인인증 없이 지원 가능. 앱 포함 시 서버 게이트 재현 방법(웹 API route 경유 또는 정책 변경) 결정 필요 |
| 18 | **정산 조회(멘토)** | `api_web_v1.mentor_settlement_self()` · `public.mentor_settlement_lines/summary` · `subscription_settlement_items`/`custom_order_settlement_items` SELECT | u | **[읽기·앱 허용]** | 정책 §3 "멘토 정산 내역 조회 ✅ 읽기 전용". 앱은 `/mentor/payouts` 링크를 숨김(`commerce_policy.dart:25-33`) |
| 19 | **정산 계좌 등록** | F13 `api_web_v1.mentor_payout_account_update_self(text,text)` — 승인 멘토·allowlist 17종·마스킹 반환 | u,s | **[모호]** | 지급 수취 계좌(소비자 결제 아님). 앱은 "정산 관리 링크"를 결제 인접으로 보고 숨김 중(2026-07-12 재판정). **권고: 조건부 앱 포함**(스토어 정책 비대상으로 보이나 오너 판단) — DB 추가 객체 불필요 |
| 20 | 정산 지급 배치 | `run_scheduled_payout`, `pay_due_payouts_for_run`, `payout_runs/payout_settings`(service_role) | s | **[앱 제외]** | — |
| 21 | **가격 설정(멘토 플랜 F8 · IQ 단가)** | F8 `mentor_plan_prices_set_self(int,int,int)` · `set_individual_question_price(integer)` | u,s | **[모호]** | 판매자 콘솔 행위(소비자 구매 아님). 학생 화면에 가격+구매 유도가 노출되지 않는 한 정책 §4 유형이 아님. **권고: 멘토 전용 화면으로 앱 포함 가능** — 오너 판단 |
| 22 | **가격 표시(학생 대상)** | `mentor_plans` SELECT(anon 포함) · `mentor_directory_v1` · `mentor_individual_question_pricing` SELECT | a/u | **[모호]** | 정책 §4 "가격표+구매 유도 조합" 금지. 앱은 가격 표시를 제거했음(`PLAY_STORE_REVIEW_PLAN.md` 재기준화 `5002c1d`). **권고: 앱 비표시 유지**(오너 결정) |
| 23 | **캐시 잔액·원장 조회** | `api_web_v1.my_wallet_v1` / `my_cash_ledger_v1`; 웹 `/wallet/ledger`(service_role 로 페이싱크 pending 섹션 추가 조회 `app/(student)/wallet/ledger/page.tsx:56`) | u,s | **[읽기·앱 허용]** | 정책 §3 ✅; 앱 manifest 포함. 원장 `order_ref`(Toss orderId) 노출은 허용 범위지만 "충전 내역" 화면이 충전 유도로 읽히지 않게 |
| 24 | 잔액 부족 상태 표시 | 없음(클라이언트 판단) | — | **[읽기·앱 허용]** | 정책 §4 허용 예외: "캐시가 부족합니다" 사실만, 해결 방법 안내 금지 |
| 25 | 본인인증(NICE PASS) | `app/api/identity/start`·`return`(service_role, `identity_verifications`·`nice_auth_tokens`), `users.identity_verified_at`(authenticated SELECT 가능) | 테이블 s 만; `users.identity_verified_at` 읽기 u | **[웹 전용(결제 게이트)]** | 계약 §19.1 "NICE PASS 웹 전용". 앱은 `identity_verified_at` 을 읽어 상태 표시만 가능 |
| 26 | 탈퇴 시 잔액 소멸 동의 | 웹 `account_deletion_request_consented`(s) · 앱 `account_deletion_request_self_consented_v2(bigint)`(u) | s / u | **[앱 허용]** | 앱용 consented v2 RPC 가 이미 authenticated 에 열려 있음(`20260803170916…:784-802`) — 계약 v1.1 §15.1 "앱용 consented wrapper 만들지 않는다"는 **이후 M2 수렴으로 변경됨** |

**요약**: 자금 이동 RPC 는 전부 service_role 이므로 앱은 구조적으로 결제를 실행할 수 없다. 예외 4종(IQ 생성·release·refund wrapper, F13)은 DB 가 열어 두었으나 정책 판단이 필요하며, 이 중 IQ 생성만 "소비자 캐시 차감"에 해당한다.

---

## §5 DB 변경 규율

### 5.1 정본 위치와 3중 사본

| 사본 | 경로 | 소유 |
|---|---|---|
| 작성 원문(번호 체계) | `supabase/sql/NNN_<name>.sql` (188~198 = 2026-08-30~09-03 배치; 그 이전 20260730~ 는 `supabase/sql/<authoringTS>_<name>.sql`) | 사람이 작성 |
| pack 소스 | `supabase/baseline/post_ledger_backfills/<원장version>_<name>.sql` (현재 48본; 첫 `20260805162500`) | 사람이 등재(원장 바이트 그대로 + 말미 개행) |
| 적용 pack | `supabase/migrations/<원장version>_<name>.sql` (112본) | **생성기 소유 — 직접 편집 금지**(`scripts/verify/baseline/build_native_migration_pack.py:1-24`) |

실측: `sql/190…` = `post_ledger_backfills/20260903100100…` = `migrations/20260903100100…` (md5 `7982143fdff8` 동일); `sql/196…` = `…/20260903230100…` (md5 `7cf228b9a1a7`). 반면 S2 기(`sql/20260730105248_api_web_v1_self_rpc.sql`)는 `migrations/20260731102007_20260730105248_…` 와 md5 가 다르다(원장 적용본은 `ledger_replay/` 에 원장 version 접두로 보관 — 파일명이 `<원장TS>_<작성TS>_<name>` 형태). **원장 version(라이브 적용 시각)과 작성 timestamp 가 다를 수 있다.**

pack 구성(`build_native_migration_pack.py:3-15`): baseline 1(`20260701000000_pre_ledger_baseline.sql`, 188 source part → 114 stage, `build_native_baseline_migration.py`) + ledger_replay 56 + interleaves 6 + post_ledger_backfills N(현재 48) + PR60 1(`20260804113000`). manifest `supabase/baseline/native_migration_pack_manifest.tsv`(112행) 에 source/output sha256.

### 5.2 새 앱 호출용 RPC 를 추가하는 정식 절차

1. **계약 먼저**: `docs/contracts/api_web_v1_contract_v1_1.md` §19.5 — 웹 계약이 공용 계약의 정본, 앱 계약(`api_app_v1_contract_v1_1`, 앱 저장소 외부 문서)은 웹 정본 SHA 기준으로 재동기화. 신규 객체는 §4.1 호출자 계층(T1~T5) 중 하나에 배정하고 §8 envelope·§9 오류코드 사전을 따른다(UPPER_SNAKE, 추가만).
2. **객체 형태**: `api_app_v1.<name>(...)` SECDEF thin wrapper(`SET search_path=''`, 완전 수식, `auth.uid()` 자체 도출 — `p_user_id` 류 인자 금지 §11.3) → `core_private.<name>_impl(p_actor uuid, …)` SECURITY INVOKER 구현부(외부 EXECUTE 0). 웹 동등 기능이 있으면 `api_web_v1` wrapper 도 같은 impl 을 호출(복제 금지). 판정 로직은 impl 한 곳(§5.2, §7 B). 선례: `20260731114120…:120-140`(wrapper) ↔ `20260731101845…:75-193`(impl).
3. **권한 규약(같은 마이그레이션·같은 트랜잭션)**: `REVOKE ALL ON FUNCTION … FROM PUBLIC`(default privilege 와 이중 방어) → `GRANT EXECUTE … TO authenticated`(api_app_v1 은 service_role 을 주지 않는다 — `20260731114120…:7-8, 256-261`); impl 은 GRANT 0. 신규 public 테이블은 RLS enable + 정책 + 필요한 GRANT 를 명시(2026-08-02 default ACL 하드닝 때문).
4. **파일**: `supabase/sql/NNN_<name>.sql` 작성(머리 주석: Purpose · Base · 변경 없음 목록 · Apply 경로 · pack 등재 경로 · Rollback 경로 · 검증 SQL — `20260903100200…:1-24` 양식) + `supabase/rollback/<authoringTS>_<stem>_rollback.sql`(§5.4) + `supabase/baseline/post_ledger_backfills/<version>_<name>.sql` 등재 → `python3 scripts/verify/baseline/build_native_migration_pack.py` → `validate_native_migration_pack.py`(파일 수·version 순서·checksum·금지 패턴(psql meta, CREATE DATABASE, 토큰/JWT/접속문자열)·transaction 경고) · `validate_replay_manifest.sh`(114/56/6/62/188 카디널리티) PASS.
5. **CI**: PR 에서 `.github/workflows/db-migration-pack-verify.yml`(정적 검증 + PG17 + Supabase CLI 2.111.0 replay, secret 0) · `web-contract-tests.yml`. 라이브 적용은 **오직** `db-apply-pending.yml`(workflow_dispatch · Environment 승인 · mode 기본 dry-run · confirmation `APPLY_PENDING_MIGRATIONS_TO_lbeqxarxothkmzqvpudy` · `supabase db push --db-url` · 사후 원장 증가분 = 사전 pending 일치 검증 — `:1-40, 96-127, 140-190`). MCP `apply_migration`/즉석 `execute_sql` 금지(각 migration 헤더 "Apply: 저장소 표준 경로(db-apply-pending) — 즉석 실행 금지").
6. **원장 대조**: `remote_only` 가드 — 원장에는 있는데 pack 에 없는 version 이 1건이라도 있으면 hard fail(`db-apply-pending.yml:124-127`).
7. **계약 스냅샷 갱신**: `npm run contracts:export`(`scripts/contracts/export_remote_contract.mjs` — 읽기 전용 트랜잭션, 카탈로그·grant·hash 만) → `contracts:verify`(`verify_remote_contract.mjs`) green (`20260827100100…:2-3` 절차 인용). 인벤토리(`docs/audit/remote_db_inventory_*`) 갱신.
8. **앱 매니페스트 갱신**: `ssambership-app/test/contracts/outbound_api_manifest_test.dart` 의 `kExpectedRpcNames` / `kExpectedSchemas` / `kExpectedTables` / 버킷 상수 집합에 추가(집합 동일성 테스트라 누락·과잉 모두 실패) — `:5-13`. 금지어(`kForbiddenWords`)에 폐기 표면을 넣어 회귀 차단.
9. **Data API 노출**: 새 스키마를 만들면 Exposed schemas 추가는 플랫폼 단계(D-API-*, 계약 §20.6) — SQL 로 하지 않으며 `ALTER ROLE authenticator SET pgrst.db_schemas` 금지. 객체 추가만이면 schema cache reload(`NOTIFY pgrst, 'reload schema'`)로 충분.

### 5.3 hotfix 역수입 규칙 (CLAUDE.md "마이그레이션 hotfix 역수입 규칙")

MCP `apply_migration` 등으로 라이브에 먼저 적용했다면 **같은 세션에서**: `select statements from supabase_migrations.schema_migrations where version='<v>'` → `post_ledger_backfills/<v>_<name>.sql`(바이트 동일 + 말미 개행, md5 대조) → 생성기 재실행 → validate PASS → 커밋. 사례: `20260808092007_account_deletion_server_cancel_window_30d`(원장에만 있던 4본으로 `db-apply-pending` 이 hard fail → 2026-08-09 화해 PR). 앱 저장소 `SCHEMA_SOURCE_OF_TRUTH.md` 규율 1~3 도 동일("콘솔/MCP 직접 적용을 했다면 같은 날 pack 에 backfill", "pack ≠ 원장 = 결함").

### 5.4 롤백 파일 규약

- 경로 `supabase/rollback/<FORWARD_FILE_TS>_<STEM>_rollback.sql`(34본) · `apply_migration name` `<TS>_<STEM>_rollback` (`docs/audit/s2_2_migration_physical_policy_20260730.md:67-71, 133-150`). forward clean-install 과 구조적으로 분리(`supabase/sql`·pack glob 에 포함 금지), 정규 파일 수에 미포함, 장애 시 오너 승인 후 파일 1개를 명시 선택해 실행, **롤백도 원장에 새 행 append**(forward 행 삭제·수정 금지), Management API `rollback` 필드 미사용.
- 상태 rollback 순서는 선행조건 그래프 역방향(계약 §22 #2; `api_app_v1` 은 앱 호출부 복원 → 호출 0건 → Exposed schemas 제거 → config 반영 → wrapper→View→schema DROP → schema cache reload). 웹/앱 **코드 롤백이 DB 롤백보다 먼저**(§22 #4). 데이터 롤백 없음(§22 #8; M13 라벨 백필 forward-only).
- 일부 rollback 은 "위 Base md5 라이브 원문 재적용"으로 대신함(`20260829100200…:23`) — 파일이 없는 항목이 있다(34/78).

### 5.5 앱 저장소에 SQL 을 두지 않는 이유

`ssambership-app/supabase/SCHEMA_SOURCE_OF_TRUTH.md`: 과거 앱 저장소의 IQ 첨부 RPC SQL 4건이 이후 마이그레이션(v2 검증·ACL 하드닝·api_* 표면 재편)으로 대체된 **낡은 계약**이었고, 두 저장소에 SQL 이 이원화되면 폐기 계약을 참조하는 사고가 재발하므로 삭제·금지(2026-08-06). 재현 가능한 정본은 웹 pack 이며 서버 원장은 '적용된 사실'의 기록일 뿐. 계약 §19.5 #9 도 "앱 저장소는 S2 공용 DB migration SQL 정본을 만들지 않는다". 저장소에 Supabase Edge Function 은 **0건**(`supabase/functions` 부재).

---

## §6 앱 정합(parity)을 위해 새로 필요할 서버 객체 후보

기준: 웹에서 `createServiceRoleClient()`(`lib/supabase/admin.ts`) 로만 구현된 **사용자 기능(결제 실행 제외)**. 관리자 콘솔(`lib/admin/*` 다수)·cron·webhook 은 앱 비대상이라 제외. 형태 판정: **A** = `api_app_v1` SECDEF wrapper(+`core_private` impl) / **B** = 웹 API route + 앱 세션 부트스트랩(`POST /api/app-session/bootstrap` + `createAppSurfaceClient` — `lib/supabase/appSurfaceServer.ts`, 계약 §3.2; 숏폼 업로드 웹뷰 선례) / **C** = Edge Function(현재 0건 — 새 운영 표면이라 비권장) / **없음** = 이미 앱 호출 가능한 객체 존재.

| # | 웹 기능 (service_role 지점) | 왜 service_role 인가 | 앱 대응 현황 | 1차 판정 |
|---|---|---|---|---|
| 1 | 구독 해지 예약 / 예약 취소 — `lib/subscribe/subscriptionCancelActions.ts:93-165` (`subscriptions` UPDATE) | `subscriptions` authenticated UPDATE GRANT·정책 없음(028/M2 잠금) | 없음(웹 안내문) | **A(조건부)** — `api_app_v1.subscription_cancel_at_period_end_self(p_subscription_id uuid)` / `…_undo_self` SECDEF; 당사자=`student_id=auth.uid()`, 상태 검사 동일. 결제 경계 판정(§4 #5) 선행 |
| 2 | 구독 잔여 환불 신청 — `:168-260` (`refunds` INSERT, 금액 서버 산정) | `refund_ins` 가 admin 만 | 없음 | **A(조건부)** — `refund_request_subscription_self(p_subscription_id uuid, p_reason text)`; 오너 결정(§4 #7) |
| 3 | IQ 학생 해결완료(payout) — `individualQuestionActions.ts:489-532` | 코어 `release_individual_question_payout` s 만 | `release_individual_question(uuid)` u — **있음** | 없음(경계 판정만) |
| 4 | 맞춤의뢰 납품 수락 — `orderSettlementService.ts:80-87` (`accept_custom_order_deliverable_atomic(p_order_id, p_student_id, …)`) | `p_student_id` 인자형 T4a | 없음 | **A(조건부)** — `custom_order_accept_deliverable_self(p_order_id uuid)` SECDEF: `auth.uid()` 를 `p_student_id` 로 넘겨 기존 RPC 호출(thin). 경계 판정 §4 #14 |
| 5 | IQ 메시지·멘토 답변 확정 — `:353-487`(admin INSERT/UPDATE) | 웹 구현 선택 | `iq_append_message`, `answer_individual_question` u — **있음** | 없음 |
| 6 | IQ 생성(hold) — `:121-300` | 자금 실행 | `create_individual_question_as_student` u 있으나 subject/topic/required tier·major 인자 없음 | 경계상 웹 위임(§4 #9). 포함 결정 시 `_v2` wrapper 필요 |
| 7 | 멘토 활동 상태(휴식·종료·복귀·즉시 탈퇴) — `lib/mentor/mentorActivityActions.ts:25-76` + `mentorActivityService.ts`(`mentor_profiles.activity_status/pause_*`, `mentor_activity_events` INSERT, `mentor_plans.is_active` 토글, `subscriptions` 갱신, **종료 시 `refunds` INSERT**) | M11 로 mentor_profiles 쓰기 회수 + 자금 인접(환불 생성) | 없음 | **웹 위임 권고**(1차). 포함 시 A — `mentor_activity_request_self(p_kind text, p_pause_until timestamptz)`; 환불 생성 분기는 결제 경계 판정 필요 |
| 8 | 멘토 학생증 업로드 후 `mentor_profiles.student_id_image_url` 반영 — `lib/mentor/mentorStudentIdActions.ts:74-76` (업로드 자체는 세션 클라이언트 + `student_id_images_insert_own`) | M11 | 없음 | **A** — `mentor_student_id_image_set_self(p_storage_path text)`: `storage.objects.owner_id=auth.uid()` 검증(`qna_register_attachment` 패턴) 후 컬럼 갱신 |
| 9 | 가입 직후 학생증 — `lib/auth/mentorSignupStudentIdAction.ts` | 가입 경로 | 가입은 웹 전용(계약 §19.1) | 없음 |
| 10 | 맞춤의뢰 초안 삭제 — `lib/customRequest/customRequestComposeActions.ts:190-208` (`custom_request_posts` DELETE + 첨부 정리) | `custom_request_posts` DELETE 정책 없음 | 없음 | **A** — `custom_request_post_delete_draft_self(p_post_id uuid)`(draft 한정, 첨부 행·객체 정리) 또는 소프트 삭제 컬럼 도입 |
| 11 | 숏폼 업로드·발행 — `lib/community/communityShortformActions.ts:258-363` (`*FromAppAction` + service_role signer, 티켓 발급, finalize INSERT) | 서명 업로드 티켓 + 앱 표면 wrapper | 앱은 웹뷰(`/app/community/shortform/new`) + `/api/app-session/bootstrap` 경유(계약 §3.2) | **B 유지 또는 A** — DB 는 직접 경로가 이미 열려 있다(`sfv_mentor_insert` + `sf_insert_mentor` + `shortform_posts_protected_guard`). 네이티브 전환 시 F4 패턴의 `api_app_v1.shortform_post_create(p_idempotency_key uuid, p_video_ref text, p_thumbnail_ref text, p_title text, p_body text, p_tags text[])` + `core_private` impl(ref 검증기 재사용) 권고 |
| 12 | 탈퇴 요청(잔액 동의) — `lib/account/accountDeletionActions.ts:41-109` | 웹 정본 consented | `account_deletion_request_self_v2()`, `…_consented_v2(bigint)`, `cancel_self()`, `status_self()` u — **있음**(30일 취소창) | 없음 |
| 13 | 무료질문 방 확보·사용량 — `lib/qna/freeQuestionUsage.ts:205`(service_role fallback) | 레거시 JS 경로 | `api_app_v1.ensure_free_question_room`, `api_web_v1.weekly_question_usage_self(_batch)` — **있음**(앱은 api_web_v1 함수를 교차 호출 중) | 없음. 단 `weekly_question_usage_self(_batch)`·`my_wallet_v1`·`my_cash_ledger_v1`·`mentor_directory_v1`·`community_posts_v1(api_web_v1)` 을 앱이 직접 쓰는 것은 계약 §19 "api_web_v1 = 웹 표면" 과 어긋나는 **사실상 관행** → 새 앱 계약에서 `api_app_v1` 동명 객체로 정식화할지 결정 필요 |
| 14 | 프로필(닉네임·학년) / 마케팅 동의 | — | `api_app_v1.user_profile_update_self` 있음 · `user_marketing_consent_set_self` 는 `api_web_v1` 에만 | 마케팅 동의: **A** — `api_app_v1.user_marketing_consent_set_self(boolean)` thin wrapper(동일 impl 없음 → wrapper 본문 공유 방식 결정) |
| 15 | 멘토 프로필 편집·요금제·정산계좌 | F7/F8/F13 은 `api_web_v1`(u 로 호출 가능) | 앱은 mentor_profiles 읽기만(계약 B-07) | 앱 포함 시 **A** — `api_app_v1` 동명 wrapper(내부는 `api_web_v1` 함수와 같은 본문 또는 impl 분리). 계약 B-07 "전용 api_app_v1 RPC 로 여는 원칙" |
| 16 | 게시판 댓글·숏폼·숏폼 댓글 본인 삭제 | — | `soft_delete_own_content(text,uuid)`, `community_comment_soft_delete_self` — **있음** | 없음 |
| 17 | 사용자 차단·찜·연결노트·리뷰·신고·알림 설정·디바이스 토큰 | — | RLS 직접 + `my_blocked_users`, `register_device_token` — **있음** | 없음 |
| 18 | 관리자 승인·모더레이션·환불 승인·분쟁·정산 배치 | 관리자 | 앱 제외 | 없음 |
| 19 | 본인인증 게이트(구독·IQ·맞춤형 주문·멘토 지원) — `lib/identity/identityGate.ts:30-57` | 웹 서버 계층 한정 설계(DB 게이트 금지) | 앱 직접 경로(예: `cra_insert`)는 게이트 없음 | **정책 결정 필요** — 앱에서 멘토 지원을 허용하면 B(웹 API route) 또는 impl 내 `users.identity_verified_at` 검사(A) 중 선택. 현 설계 원칙은 DB 게이트 금지 |

**공통 규칙**: 새 wrapper 는 계정 상태 게이트(positive allowlist — `ugc_write_allowed()` 판정식, `20260802054930…:295-314`)와 `account_deletion_write_blocked(self)` 를 impl 에서 수행하고, 오류는 envelope 로. 자금을 만지는 후보(#1, #2, #4, #7)는 §4 오너 결정 전에는 만들지 않는다.

---

## §7 앱 부트스트랩 · 버전 정책

### 7.1 `mobile_app_version_policies` · `get_mobile_app_version_policy`

- 테이블(baseline `supabase/migrations/20260701000000_pre_ledger_baseline.sql:21302-21327`): `platform text PK CHECK(android|ios)`, `min_supported_build int NOT NULL DEFAULT 1 CHECK ≥1`, `latest_build int NOT NULL DEFAULT 1`, `minimum_version_name text`, `store_url text` CHECK(`mavp_store_url_chk`: https + play.google.com/apps.apple.com/itunes.apple.com), `message text`, `updated_at`, CHECK `latest_build >= min_supported_build`; **RLS on · 정책 0 · anon/authenticated GRANT 0 → 쓰기·읽기 모두 service_role 전용**. 추가 CHECK `mavp_store_url_platform_chk`(platform↔host 일치, `20260808080056…`).
- RPC `public.get_mobile_app_version_policy(p_platform text) → jsonb` STABLE SECDEF, EXECUTE **anon+authenticated+service_role**(로그인 전 게이트): `p_platform ∉ {android, ios}` → `INVALID_PLATFORM`(22023); 행 없음 → `{platform, min_supported_build:1, latest_build:1, minimum_version_name:null, store_url:null, message:null}`(비차단 기본값); 있으면 6 키 그대로(`20260804100002_as_applied_function_bodies.sql:1048-1082`).
- 데이터 이력: 2026-08-06 `latest_build ≥ 16`, `minimum_version_name '1.0.0'` 멱등 UPDATE(`20260806075353…`); 2026-08-08 실측 android `min_supported_build=9`, `store_url NULL`(스토어 등재 전)(`20260808080056…:8-11`). 현재 값은 (확인 필요 — 운영 데이터). "min>1 이면 store_url NOT NULL" 제약은 제안 상태로 미적용.
- 앱 측: `lib/core/version_gate/supabase_version_policy_port.dart:22`(RPC 호출), `store_url_policy.dart`(서버 URL 검증 재확인), 현재 앱 `1.0.0+19`(`pubspec.yaml:4`). `docs/APP_V16_MIN_VERSION_SERVER_REQUIREMENT.md` 의 `WAITING_SERVER_GATE` 표기는 stale — SQL 162 로 충족됨(`APP_V16_SERVER_CONTRACT_SNAPSHOT.md` §4.7).
- 운영 절차: 강제 업데이트는 service_role UPDATE(멱등 데이터 migration 권장 — `20260806075353` 선례) 로 `min_supported_build` 상향. **새 앱 출시 시 구 앱 차단**은 이 값 상향이 유일한 서버 수단이며, 상향 전 해당 platform 의 `store_url` 을 채워야 앱이 스토어로 안내할 수 있다.

### 7.2 최소 부트스트랩 시퀀스(서버 요구)

1. (로그인 전) `get_mobile_app_version_policy(platform)` → `min_supported_build` 미만이면 차단 + `store_url`; 응답 실패 시 재시도 화면(차단 아님 — `APP_V16_MIN_VERSION_SERVER_REQUIREMENT.md` "앱 쪽 준비 상태").
2. Auth 세션 → `users` 본인 행 SELECT(`users_select_own`): `role`(admin 은 앱 접근 차단 — Play plan 긍정요소 6), `status`(active/suspended/banned/deleted) + `suspended_until`, `identity_verified_at`(결제 게이트 표시용, 2026-08-20 추가).
3. `account_deletion_status_self()` → `{ok, exists, state, cancelable_until, write_blocked, can_cancel}` 또는 `account_deletion_write_blocked(자기 uuid)`(타인 uuid 금지).
4. 알림: `register_device_token(token, platform)` → `device_token_id` 저장; `notification_settings` 본인 행(없음=ON); Realtime `notifications_<uid>` 구독; `notification_unread_count_self()`.
5. 역할별: 학생 — `my_subscriptions_self()`, `my_wallet_v1`; 멘토 — `mentor_profiles` 본인 행(`verification_status`, `activity_status`), `mentor_settlement_summary()`.
6. 계약 상수: 게시판 create/update 는 named 인자, `contract_version=1`; `ACCOUNT_NOT_ACTIVE`·`ROLE_NOT_ALLOWED` 매핑 필수(`s3_c…` §8.1).

---

## 부록 A. 계약 v1.0 → v1.1 차이(요약)

`api_web_v1_contract_v1_1.md:14-31` "v1.1 개정 요약(rev 8 A~G)": F4/F5 시그니처 재배열(필수 선행·DEFAULT 후행) · `core_private` Data API 도달 불가 실측 → F11/F12 진입점을 `api_web_v1`(service_role 전용)로 이동 · 컬럼 단위 REVOKE 무효 → M11/M12 테이블 단위 · F13 정산계좌 RPC 신설 · F12 재생 계약 전면 재작성(9단계 오류 우선순위, Phase 1/2) · topup 정본 = `idempotency_key`(`ref_text` 폐기, 3층 구조) · M0 필수화 · `get_weekly_question_usage` pair-party 가드(M15) · F0 라벨 함수 폐기(V2 비정규화, V6/V7 SECDEF RPC) · 커뮤니티 작성 승인 멘토 전용(A-10 — 이후 S3-C 에서 학생 허용으로 재변경) · HD-1 직접 쓰기 전면 잠금(M16) · M17 `api_app_v1` 표면 신설(부록 C-1). 이 문서 자체는 SQL 을 포함하지 않으며(§1.2), 실제 적용본은 §1~§2 의 migration 들이다.

## 부록 B. 확인하지 못한 항목

1. Data API Exposed schemas 의 실제 목록(대시보드/Management API) — 앱 실호출로 간접 확인만.
2. `20260827100100_device_token_register_grant.sql`(헤더 "라이브 미적용 — 오너 승인 후 적용")의 라이브 적용 여부.
3. `mobile_app_version_policies` 현재 행 값(min/latest/store_url).
4. `favorites` vs `mentor_favorites` 명칭(198 헤더 표기) — 앱 `_table` 상수 정의값.
5. Apple 3.1.1/3.1.3(b) 해석(기충전 캐시의 앱 내 소비, 다중플랫폼 IAP 병행 조건) — 법무 검토 필요.
6. 2026-08-04 이후 `pg_trigger`·`pg_policies` 전수(이 문서는 migration 파일 기반 합성).
