# Phase 2 설계 — 맞춤의뢰(Custom Request, CR) 도메인 · Flutter 앱 신설

- 대상: 웹 `/home/user/ssambership_web`(Next.js, DB 정본) · 앱 `/home/user/ssambership-app`(Flutter, 같은 Supabase)
- 입력: Phase 1 리포트 4종(`web_custom_request.md`, `web_db_surface_payment_boundary.md`, `app_architecture.md`, `app_features.md`). 설계에 결정적인 주장은 코드·SQL·2026-08-04 원격 인벤토리(`docs/audit/remote_db_inventory_20260804/*.json`)로 재확인했다.
- 표기: 웹 파일은 웹 저장소 루트 상대, 앱 파일은 `app:` 접두. SQL 정본은 `supabase/sql/NNN_*.sql`, pack 은 `supabase/migrations/*.sql`. 확인 못 한 것은 **(확인 필요)**. UI 디자인은 다루지 않는다(화면은 이름·역할·데이터 의존만).

---

## 1. 범위·전제

### 1.1 결제 경계 판정(정본 `docs/policy/app-web-payment-separation.md:16`)

정책 원문: "개별질문·맞춤의뢰 결제(escrow) — 웹 ✅ / 앱 ❌ **결제 실행 금지 · 진행 상태 조회/소통은 허용**". DB 권한이 이 경계와 정확히 일치한다 — 자금 이동 RPC 5종(`record_custom_order_escrow_hold/payout/refund`, `accept_custom_order_deliverable_atomic`, `record_custom_order_dispute_split`)은 라이브 ACL 이 `postgres, service_role` EXECUTE 만이다(`docs/audit/remote_db_inventory_20260804/functions.json` 실측; 정의 `054:71-75`, `055:154-158`, `056:168-172`, `043:246-247`, `191:335-341`).

| 판정 | CR 기능 | 근거 |
|---|---|---|
| **앱에 넣는다** | 의뢰 글 작성·임시저장·이어쓰기, 의뢰 첨부, 내 의뢰 목록, 공개 의뢰 상세, 멘토 오픈 풀, 멘토 지원+첨부, 학생 지원 비교(읽기), 멘토 작업 시작, 납품 등록(버전), 수정 요청(≤2회), 주문 메시지+첨부, 분쟁 제기, 주문·이벤트·정산·분쟁 조회, 납품/첨부 서명 URL | RLS/RPC 가 `authenticated` 에 열려 있음 — §3.1 표. 정책 §3 "진행 상태 조회/소통 허용" |
| **웹 위임(결제 실행)** | ① 학생 선정 → 주문 생성 + 에스크로 hold(`customOrderEscrowService.ts:132-172`) ② 납품 수락 → 정산 행 + **즉시 지급**(`20260804100002_as_applied_function_bodies.sql:157,187` `perform record_custom_order_escrow_payout`) ③ 학생 직접 취소 → 전액 환불(`orderStudentActions.ts:198-269` → `record_custom_order_escrow_refund`) | 셋 모두 캐시 이동. service_role 전용 RPC 라 앱 도달 불가. 오너가 앱 내 실행을 원하면 §3(b) W-1~W-3 wrapper 신설 = **결제 실행이 앱에 들어오는 결정**(§7) |
| **제외(관리자)** | 분쟁 검토·해결·기각·메모, 분쟁 예치 분배, 관리자 환불 승인 | `lib/admin/adminDisputeActions.ts`, `191`, `128` — 관리자 콘솔 전용 |
| **제외(앱 정체성)** | 임시저장 삭제의 웹 방식(service_role DELETE) | posts 에 DELETE 정책 없음(`003:348-388` SELECT/INSERT/UPDATE 만) → §3(b) W-0 wrapper 로 대체 |

핵심 함의: 앱의 학생 흐름은 **작성 → 지원 받기 → [선정: 웹] → 진행·납품·수정·메시지·분쟁 → [수락/취소: 웹] → 완료 조회** 가 된다. 웹의 "선정" 과 "수락" 화면으로 앱이 딥링크를 걸어도 되는지는 별개의 정책 문제다 — 정책 §4 는 "웹 결제 URL 로의 딥링크·외부 브라우저 링크" 를 금지하고, 앱은 같은 성격의 IQ 등록 링크를 `kIndividualQuestionCreateEnabled`(기본 false, `app:lib/features/individual_question/iq_flags.dart:10-19`) 뒤에 두고 있다. CR 선정/수락 딥링크도 같은 플래그 패턴(기본 OFF) 을 권고한다(§7 Q3).

### 1.2 CR 웹 게이트 기본 OFF 전제와 함의

- `isCustomRequestFeatureEnabled()` 는 `NEXT_PUBLIC_FEATURE_CUSTOM_REQUEST ∈ {on,1,true,yes}` 일 때만 true, 기본 OFF(`lib/shell/featureFlags.ts:5-10`). 효과는 **네비 숨김**(`lib/shell/mainNavItems.ts:121-125,128-136`)과 랜딩 배너뿐 — 라우트·server action·DB 는 게이트 없이 라이브다(`web_custom_request.md` §5).
- 앱 측 게이트 흔적: 알림 2종 exact 제외 `kGatedNotificationTypeCodes`(`app:lib/features/notifications/data/notification_types.dart:15-18`), 목록 쿼리 `not.in`(`app:…/notifications_repository.dart:123-137`), 목적지 `stay`(`notification_types.dart:165-168`), 설정 라벨 `'order': '개별질문 알림'`(`app:…/notification_settings_repository.dart:32-38`), 배포 결정 `docs/RELEASE_SCOPE_DECISIONS_2026-07.md` §4.
- **서버 측 게이트 1건(중요)**: `notification_unread_count_self()` 가 `new_order_message`·`new_application` 을 count 에서 제외한다(`supabase/migrations/20260803171053_20260803163322_realtime_notification_convergence.sql:243`, 이후 재정의 없음). 앱이 CR 을 열면 배지 카운트가 CR 알림을 세지 않으므로 **서버 변경(§3(b) S-6)이 필요**하다.
- 함의: 백엔드는 이미 열려 있으므로 **앱 노출 = 사실상 CR 출시**다. 앱 출시 시 웹 게이트를 동시 ON 하지 않으면 (a) 앱 사용자가 만든 의뢰에 웹 멘토는 네비로 도달하지 못하고(URL 직접 접근·알림 링크만), (b) 앱이 "선정은 웹에서" 로 보내는 웹 페이지가 네비 없는 반쯤 숨겨진 상태가 된다. → **웹 게이트 동시 ON 필요**(권고, §7 Q1). 알림 트리거(`159`)는 게이트 무관하게 이미 발행 중이므로 양 표면 동시 오픈이 일관적이다.
- 추가 전제: `IDENTITY_GATE_ENABLED` 값(현재 `.env.example:46` 빈 값 = OFF), 즉시지급 모델 확정(§1.1 ②), `cro_update` 잠금(§3(c)), 수정요청 primary 불일치 정책(§7 Q9).

---

## 2. 갭 매트릭스

앱 현재: 전부 **없음**(CR 표면 0 — `app:test/contracts/outbound_api_manifest_test.dart:15-137` 에 CR RPC/테이블/버킷 0건, `README.md:8` "제외(흔적 없이)"). 따라서 "앱 현재" 열은 알림 게이트 흔적이 있는 행만 "부분", 나머지 "없음".

| # | 웹 기능 | 웹 라우트 | 앱 현재 | 앱 목표 | 근거(파일:행) |
|---|---|---|---|---|---|
| 1 | CR 랜딩(최근 공개 의뢰 3건) | `/custom-request` | 없음 | **포함**(멘토: RPC 018 풀 요약 / 학생: 내 의뢰·주문 요약으로 대체) | `app/(public)/custom-request/page.tsx:18-115`; 직접 SELECT 는 비작성자 0행(`003:348-356`) |
| 2 | 의뢰 작성·임시저장·이어쓰기 | `/custom-request/new` | 없음 | **포함** | `lib/customRequest/customRequestComposeActions.ts:40-188`; RLS `crp_insert/crp_update`(`003:359-388`) |
| 3 | 의뢰 첨부 업로드 | `/custom-request/new` | 없음 | **포함**(버킷 20 MiB 기준) | `customRequestComposeActions.ts:94-121`; 버킷 `012:71-95`(20971520) vs 웹 상수 50MB(`postAttachmentConstants.ts:5`) |
| 4 | 임시저장 삭제 | `/custom-request/posts` | 없음 | **포함 — 신규 wrapper W-0 필요** | `customRequestComposeActions.ts:190-224` service_role DELETE; posts DELETE 정책 없음(`003`) |
| 5 | 내 의뢰 목록(임시 포함) | `/custom-request/posts` | 없음 | **포함** | `customRequestQueries.ts` `loadStudentCustomRequestPosts`; `crp_select` 작성자 |
| 6 | 공개 의뢰 상세 + 첨부 | `/custom-request/[postId]` | 없음 | **포함** | `loadCustomPostForPublicDetail` `customRequestQueries.ts:287-303`(직접→RPC 006 폴백); 첨부 `crpa_select_authorized`(`012:29-49` 모든 멘토 허용) |
| 7 | 지원 비교(학생, 프로필·닉네임·첨부) | `/custom-request/[postId]/applications` | 없음 | **포함(읽기)** | `cra_select`(`003:391-397`); 닉네임 `api_web_v1.mentor_directory_v1`(`customRequestQueries.ts:809-812`) — 앱 매니페스트에 이미 등재(`outbound_api_manifest_test.dart:93`) |
| 8 | 지원 첨부 미리보기(학생, 선정 후만) | 동일 | 없음 | **포함 — 웹 코드 정책을 앱 재구현** | `applicationAttachmentAccess.ts:79-95` `assertStudentCanPreviewAfterSelection`; DB 정책은 선정 전에도 작성자 허용(`059:82-90,163-170`) |
| 9 | 멘토 선정 → 주문 + hold | 동일(선정 폼) | 없음 | **웹 위임**(오너 결정 시 W-1) | `customOrderEscrowService.ts:132-172`; hold RPC service_role(`054:71-75`) |
| 10 | 학생 주문 목록(탭) | `/custom-request/orders` | 없음 | **포함** | `studentCustomRequestOrdersQueries.ts:150-178`; 탭 `studentOrderBrowseTabClassify.ts:9-21` |
| 11 | 주문방(공용) — 진행 단계·납품·메시지·수정요청·분쟁·정산 배너 | `/custom-request/orders/[orderId]` | 없음 | **포함**(수락·취소 버튼만 웹 위임) | `orderDetailQueries.ts:268-362` 번들; RLS 전부 당사자 SELECT(`003:484-575`, `013:47-55`, `004:195-199`) |
| 12 | 멘토 작업 시작 | 주문방 | 없음 | **포함** | RPC `custom_order_mentor_start` u,s(`088:165-232,418`; 라이브 ACL 동일) |
| 13 | 납품 등록(버전, 파일+메모) | 주문방 | 없음 | **포함 — wrapper W-8 권장** | `orderMentorActions.ts:137-336`(read-max+1 재시도 5회 `:241-311`); `cdel_insert`(`003:500-504`); RPC deliver(`088:235-285`) |
| 14 | 납품 다운로드 | 주문방·완료 | 없음 | **포함**(세션 서명 URL; 학생은 완료 후만 — DB 강제) | Storage 읽기 `063:105-112` → `user_can_read_cro_deliverable_storage_path`(`063:76-100`) + `cro_student_can_read_deliverable_storage`(`063:44-72`) |
| 15 | 수정 요청(≤2회) | 주문방 | 없음 | **포함** | RPC `custom_order_student_request_revision`(`088:287-400`, `REVISION_LIMIT_EXCEEDED`) |
| 16 | 납품 수락 → 완료 + 정산 + 즉시 지급 | 주문방 | 없음 | **웹 위임**(오너 결정 시 W-2) | `orderSettlementService.ts:80-118`; 실측 본문 `20260804100002:4-204`(payout 즉시 호출 `:157,187`) |
| 17 | 학생 직접 취소(전액 환불) | 주문방 | 없음 | **웹 위임**(오너 결정 시 W-3) | `orderStudentActions.ts:198-269`; `056:168-172` service_role |
| 18 | 주문 메시지 + 첨부 | 주문방 | 없음 | **포함 — wrapper W-7 권장(마스킹·종료 차단 DB 이전)** | `orderMessageActions.ts:126-128`(종료 차단 웹 전용), `:177-184`(마스킹); `cmsg_ins`(`003:544-556`); 첨부 `083:43-70,147-196` |
| 19 | 분쟁 제기(학생·멘토) | 주문방 | 없음 | **포함**(웹 조건 앱 재구현) | `orderDisputeActions.ts:107-193`; `dispute_ins`(`008:5-27`); 활성 1건 유니크(`009:30-32`) |
| 20 | 내 분쟁 목록·상세 | `/support/disputes`, `/mentor/support/disputes` | 없음 | **포함(읽기)** | `dispute_select`(`004:195-199`); `refund_select` 본인 |
| 21 | 완료 화면(납품·결제 요약·리뷰 진입) | `/custom-request/orders/[orderId]/complete` | 없음 | **포함(읽기)**; 리뷰 진입은 CR 자격 미포함 그대로 | `complete/page.tsx:141-192`; `lib/reviews/*` grep `custom` 0건(Phase 1) |
| 22 | 멘토 대시보드 KPI | `/mentor/custom-request/dashboard` | 없음 | **포함** | `mentorCounts.ts:23-95`; 정산 읽기 `cosi_select_parties`(`013:47-55`) |
| 23 | 멘토 오픈 풀(카테고리 탭) + 제안한 의뢰 | `/mentor/custom-request/posts` | 없음 | **포함** | RPC 018(`018:6-81`, 멘토 role 필수 `:63-73`); 휴리스틱 `mentorOpenPostCategory.ts:19-33` |
| 24 | 멘토용 의뢰 상세(+내 지원) | `/mentor/custom-request/posts/[postId]` | 없음 | **포함** | RPC 006 + `cra_select` |
| 25 | 멘토 지원서 작성 + 첨부 | `/mentor/custom-request/posts/[postId]/apply` | 없음 | **포함 — wrapper W-9 권장(승인·중복·마스킹 DB 이전)** | `customRequestApplicationActions.ts:44-179`; `cra_insert` 는 `mentor_id=auth.uid()` 만(`003:400-401`, 라이브 동일); (post_id, mentor_id) 유니크 없음(baseline `:967-968` 일반 인덱스만) |
| 26 | 멘토 주문 목록(탭 7종) | `/mentor/custom-request/orders` | 없음 | **포함** | `mentorOrderBrowseTabClassify.ts:9-35` |
| 27 | 학생 표시명(멘토 화면) | 주문방·대시보드 | 있음(질문방에서 사용 중) | **포함(재사용)** | `get_mentor_student_nicknames` u,s(`058:39`); 앱 `student_lookup_repository.dart:54` |
| 28 | 알림 2종(`new_application`, `new_order_message`) 표시·이동 | 웹 알림 링크 | **부분**(정본 enum 유지, 목록 제외·목적지 stay) | **포함**(게이트 해제 + 목적지·opener 추가) + **서버 S-6** | `notification_types.dart:15-18,165-168`; 트리거 `159:21-82`; count 제외 `20260803171053:243` |
| 29 | 본인인증 게이트(지원·선정) | server action | 없음 | **오너 결정**(현재 웹 OFF; 앱 직접 INSERT 는 게이트 없음) | `lib/identity/identityGate.ts:30-57`(DB 게이트 금지 원칙 `:4-6`), `identityGateFlag.ts:12-13`; 앱은 자기 행 `identity_verified_at` 읽기 가능(`users_select_own` baseline `:271-273`, 컬럼 `20260820100200:80`) |
| 30 | 관리자 분쟁 처리·분배·환불 승인 | `/admin/disputes`, `/admin/refunds` | 없음 | **제외** | service_role/관리자 JWT 전용 |
| 31 | 검토 카운트다운(납품+3일) | 주문방 | 없음 | **포함(표시 전용)** — 만료 정책은 오너 결정 | `components/customRequest/OrderRoomView.tsx:68-75`; cron 없음 |
| 32 | 실시간 갱신 | (웹 없음) | 없음 | **오너 결정** — 도입 시 publication 추가(S-5) | publication 에 CR 테이블 0건(`20260803171053:77-84` 목록 4종만; baseline `question_*` 3종) |

집계: 포함 24 (#1-3,5-8,10-15,18-28,31 중 웹 위임 제외) · 웹 위임 3 (#9,16,17) · 제외 1 (#30) · 오너 결정 3 (#29,32 + #4/#13/#18/#25 의 wrapper 채택 여부는 §7) → JSON 집계는 포함 24 / 웹 위임 3 / 제외 1 / 오너 결정 4(#29, #31 만료 정책, #32, 결제 wrapper 3종을 하나로).

---

## 3. 서버 표면 설계

### 3.1 (a) 그대로 쓸 수 있는 기존 객체 — authenticated 호출 가능 근거

| 종류 | 객체 | 앱 사용 | 권한 근거(정의 → 라이브 인벤토리) |
|---|---|---|---|
| RPC | `public.custom_order_mentor_start(p_order_id uuid) → jsonb` | 멘토 작업 시작 | `088:418` grant authenticated, service_role; `functions.json` acl authenticated·postgres·service_role. SECDEF, `search_path=public`, `auth.uid()` 당사자 검증(`088:171-190`), raise `P0001` 코드 |
| RPC | `public.custom_order_mentor_deliver(p_order_id uuid) → jsonb` | 납품 전이 | `088:419`; 납품 행 ≥1 필수(`088:265-267`), `order_status='delivered'` + primary 열(`088:272-281`) |
| RPC | `public.custom_order_student_request_revision(p_order_id uuid, p_note text) → jsonb` | 수정 요청 | `088:420`; 2회 상한·`order_status='delivered'` 필수·revisions insert 원자(`088:352-395`) |
| RPC | `public.get_public_custom_request_post_for_browse(p_post_id uuid) → TABLE(23열)` | 공개 상세(비작성자) | `20260804100000_post_ledger_acl_convergence.sql:55-57` a,u,s; `functions.json` anon·authenticated |
| RPC | `public.list_open_custom_request_posts_for_mentor_browse(p_limit int=50) → TABLE(23열)` | 멘토 오픈 풀 | `…acl_convergence.sql:64-66` a,u,s; 본문이 `auth.uid() not null` + role mentor/admin 요구(`018:63-73`) → anon 은 0행, 학생도 0행 |
| RPC | `public.get_mentor_student_nicknames(p_student_ids uuid[]) → TABLE(id,nickname,full_name)` | 멘토 화면 학생 표시명 | `058:39` authenticated; CR 주문 연결 학생만 반환(원래 목적) — 앱 매니페스트 등재 |
| 뷰 | `api_web_v1.mentor_directory_v1` | 지원자·배정 멘토 표시(닉네임·대학·학과·평점·`school_verified`) + **멘토 본인 승인 여부 판정**(뷰가 `verification_status ∈ approved/verified/active` 만 노출 `20260803170916:153-191`) | 앱이 이미 `.schema('api_web_v1')` 로 읽음(`app:lib/features/mentors/data/mentor_directory_repository.dart:38-46`) |
| 테이블 SELECT | `custom_request_posts`(작성자) · `custom_request_applications`(지원 멘토/글 작성자) · `custom_request_orders`(당사자) · `custom_order_deliverables` · `custom_order_revisions` · `custom_order_messages` · `custom_order_message_attachments` · `order_events` · `custom_order_settlement_items`(당사자) · `disputes`(당사자) · `custom_request_post_attachments`(작성자/모든 멘토/admin) · `custom_request_application_attachments`(지원 멘토/글 작성자) | 조회 전부 | `003:348-575`, `007`, `012:29-49`, `013:47-55`, `059:82-90`, `083:147-160`, `004:195-199`; 라이브 `policies.json` 동일 정책명 실재 |
| 테이블 INSERT | `custom_request_posts`(`crp_insert`) · `custom_request_post_attachments`(`crpa_insert_author`) · `custom_request_applications`(`cra_insert`) · `custom_request_application_attachments`(`craa_insert_mentor`) · `custom_order_deliverables`(`cdel_insert` 멘토) · `custom_order_messages`(`cmsg_ins`) · `custom_order_message_attachments`(`coma_insert_party`) · `order_events`(`oev_insert` 당사자) · `disputes`(`dispute_ins` 당사자+주문 일치) | 직접 쓰기(wrapper 미채택 시) | `003:359-367,400-401,500-504,544-556`, `012:51-62`, `059:72-79`, `083:155-160`, `007:30-47`, `008:5-27` |
| 테이블 UPDATE | `custom_request_posts`(`crp_update` 작성자 — 임시저장 이어쓰기) | 초안 갱신 | `003:370-388` |
| Storage INSERT | `custom-request-post-attachments`(작성자 `012:158-167`) · `custom-request-application-attachments`(지원 멘토 `059:173-183`) · `custom-order-deliverables`(주문 멘토 `010:119-127`) · `custom-order-message-attachments`(경로 order_id·uploader_id=uid·당사자 `083:187-196`) | 업로드 | 경로 규약 §5 |
| Storage SELECT(서명 URL) | 위 4 버킷 — `crpa_storage_read_authorized`(`012:149-156`), `craa_storage_read_authorized`(`059:163-170`), `custom_order_deliverable_storage_read_party`(`063:105-112`), `…message_attachments_storage_select_party`(`083:174-184`) | `createSignedUrl` 세션 호출 | 학생 납품 읽기는 완료 후만 DB 강제(`063:44-72`) |
| Storage DELETE | `custom-order-message-attachments` 업로더/admin 만(`083:198-`) — **다른 3 버킷은 DELETE 정책 없음** | 보상 삭제 | 고아 객체 리스크 §3.3 |
| 헬퍼 | `public.ugc_write_allowed()` u,s(`20260802054930:295-314`) · `account_deletion_write_blocked(uuid)` self | 신규 wrapper 내부 계정 게이트 | positive allowlist |
| 알림 | 트리거 `trg_cra_notify_new_application`, `trg_com_notify_new_order_message` → `record_domain_notification`(`159:21-82`) | 앱 INSERT 에도 원자 발행 | metadata `post_id/application_id/mentor_id` · `order_id/message_id/sender_role`(`159:39-40,72-74`) |

### 3.2 (b) 새로 필요한 서버 객체

공통 규약(선례 `supabase/migrations/20260731114120_20260730112525_api_app_v1_surface.sql:85-88,120-140,253-261` · DB 리포트 §5.2):
- 이름공간 `api_app_v1.<name>`; `SECURITY DEFINER`, `SET search_path = ''`, 완전 수식, `auth.uid()` 자체 도출(`p_user_id` 류 인자 금지). 판정 로직은 `core_private.<name>_impl(p_actor uuid, …)` SECURITY INVOKER 로 분리(외부 EXECUTE 0, 스키마 USAGE 누구에게도 없음 `20260731100313:48-49`).
- 권한(같은 트랜잭션): `REVOKE ALL ON FUNCTION … FROM PUBLIC, anon` → `GRANT EXECUTE … TO authenticated`(**service_role 없음** — `api_app_v1` 스키마 USAGE 가 authenticated 만). impl 은 GRANT 0. `ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE FROM PUBLIC` 은 저장 no-op 이므로 함수별 명시 REVOKE 필수(`20260731100313:52-64`).
- 반환 envelope(계약 §8.1 `docs/contracts/api_web_v1_contract_v1_1.md:1375-1400`): 성공 `{ok:true, contract_version:1, …}` / 거부 `{ok:false, contract_version:1, code:'UPPER_SNAKE'}`; 사전에 없는 SQL 예외는 전파(§8.2). 기존 `raise` 형 함수(088)를 안에서 부를 때는 `exception when others` 로 잡아 `SQLERRM` 선두 토큰을 `code` 로 변환(선례 `api_app_v1.qna_create_question_thread` `20260731114120:142-190`).
- 계정 게이트: impl 첫 단계에서 `public.ugc_write_allowed()` 판정식과 동일한 positive allowlist(`ACCOUNT_NOT_ACTIVE`, `ACCOUNT_DELETION_IN_PROGRESS`, `ROLE_NOT_ALLOWED`) — 웹 wrapper 관례(`s3_c_build13_db_contract_20260802.md` §1.3-1.4).
- 파일 위치: `supabase/sql/199_<name>.sql`(현재 마지막 198) + `supabase/rollback/<authoringTS>_<stem>_rollback.sql` + `supabase/baseline/post_ledger_backfills/<version>_<name>.sql` → `python3 scripts/verify/baseline/build_native_migration_pack.py` → `validate_native_migration_pack.py`·`validate_replay_manifest.sh` → pack `supabase/migrations/<version>_<name>.sql`(생성기 소유) → 라이브는 `db-apply-pending.yml` 만(MCP `apply_migration` 금지). 머리 주석 양식은 `supabase/migrations/20260903230300_ugc_block_hard_delete.sql:1-33`(Purpose·§0 실측·Apply·pack 등재·Rollback·검증 SQL).
- 계약: CR 은 v1.1 에서 "신규 객체를 만들지 않는 영역(유지)"(`api_web_v1_contract_v1_1.md:871,2086,2093,2132`) → 아래 객체는 **앱 계약 v1.x 증보 + 웹 계약 §19.5 재동기화**가 선행 조건. 적용 후 `npm run contracts:export/verify`, 인벤토리 갱신, 앱 매니페스트 갱신.

#### 필수(앱 CR 출시 전 — Tier A)

| ID | 객체 · 시그니처 초안 | 구현부 | 코드 | 규모 |
|---|---|---|---|---|
| **W-0** | `api_app_v1.custom_request_post_delete_draft(p_post_id uuid) → jsonb` | `core_private.custom_request_post_delete_draft_impl(p_actor, p_post_id)`: `delete from public.custom_request_posts where id=p_post_id and author_id=p_actor and status='draft' returning id`; 첨부 행은 FK `on delete cascade`(`012:10`)로 자동 삭제; Storage 객체는 웹도 지우지 않으므로 동일(고아 허용, §3.3) | `AUTH_REQUIRED`, `POST_NOT_FOUND`, `NOT_DRAFT`(status≠draft 인 작성자 글), 성공 `{deleted:true}` | S |
| **W-8** | `api_app_v1.custom_order_deliverable_register(p_order_id uuid, p_storage_path text, p_original_filename text, p_mime_type text, p_file_size bigint, p_note text) → jsonb` (`p_storage_path` NULL 이면 메모만 납품 — 웹 `file || note` 규칙 `orderMentorActions.ts:146-148`) | impl: ① 주문 잠금 + `mentor_id=p_actor` ② 종료·분쟁·결제확정·상태(open/delivered/revision_requested) 검사(웹 `orderMentorActions.ts:200-217` 동일 — 현재 `cdel_insert` 는 멘토 여부만 봐서 pending/종료 주문에도 행이 들어갈 수 있음) ③ `v_version := coalesce(max(version),0)+1`; `p_storage_path` 가 있으면 경로 `{order}/{version}/{ts}-{hex}.{ext}` 의 2번째 세그먼트 = `v_version` 검증(`DELIVERABLE_VERSION_STALE` → 앱은 재채번·재업로드, 웹 재시도 루프와 동치) + `storage.objects` 실존·`owner_id=p_actor`·bucket 검증(`qna_register_attachment` 패턴, `STORAGE_OBJECT_NOT_FOUND/NOT_OWNED`) ④ deliverables insert(payload = 웹 `buildDeliverableRowPayload` `orderDeliverableFiles.ts:271-296`: FK 4열, version, `status='submitted'`, note, `file_url=null`, storage_path, original_filename(마스킹), mime_type, file_size) ⑤ `perform public.custom_order_mentor_deliver(p_order_id)`(raise → code 변환) ⑥ `order_events` `deliverable_submitted` insert(웹 `orderMentorActions.ts:315` 동치) | 088 코드 전부 + `DELIVERABLE_VERSION_STALE`, `DELIVERABLE_INPUT_REQUIRED`, `MIME_NOT_ALLOWED`, `SIZE_EXCEEDED`, 성공 `{deliverable_id, version, transition:'mentor_deliver'}` | M |
| **W-7** | `api_app_v1.custom_order_message_create(p_order_id uuid, p_body text, p_attachment jsonb default null) → jsonb` (`p_attachment = {storage_path, original_filename, mime_type, file_size_bytes}`) | impl: 당사자 검사 → 종료 주문 차단(`ORDER_TERMINAL` — 웹 `orderMessageActions.ts:126-128` 은 웹 전용이라 DB 로 이전) → **`core_private.mask_contact_text(p_body)`**(S-4) → `custom_order_messages` insert(body 비고 첨부만이면 `'첨부 파일'` 웹 동치 `:196`) → 첨부가 있으면 `storage.objects` 실존·owner·경로 정규식(`083:66-70` CHECK 와 동일) 검증 후 `custom_order_message_attachments` insert(message_id 연결) → `order_events` `message_created` | `AUTH_REQUIRED`, `ORDER_NOT_FOUND`, `NOT_ORDER_PARTY`, `ORDER_TERMINAL`, `BODY_REQUIRED`(본문·첨부 모두 없음), `ATTACHMENT_*`, 성공 `{message_id, attachment_id}` | M |
| **S-4** | `core_private.mask_contact_text(p_text text) → text` IMMUTABLE | `20260731113927_20260730105252_api_web_v1_community_rpc.sql:200-215` 에 인라인된 SQL 정규식 6종(적용 순서 전화→한글전화→난독화 이메일→이메일→메신저 링크→메신저 핸들 = `lib/customRequest/contactMasking.ts:52-61`)을 함수로 추출. 기존 커뮤니티 impl 은 그대로 둔다(선택 리팩터) | — | S |
| **S-5** | Realtime publication: `alter publication supabase_realtime add table public.custom_order_messages, public.custom_order_message_attachments, public.custom_request_orders, public.custom_order_deliverables`(멱등 DO 블록 — `20260803171053:77-84` 양식) | postgres_changes 는 RLS 를 따르므로 `cmsg_all_party` 등 기존 SELECT 정책이 필터. 오너가 Realtime 을 채택할 때만 | — | S |
| **S-6** | `public.notification_unread_count_self()` 재정의 — `not in ('new_order_message','new_application')` 제거(`20260803171053:243`) | 앱 게이트 해제와 **같은 배치**로 적용(앱 목록 쿼리 `not.in` 도 동시 제거). `CREATE OR REPLACE` 는 ACL 보존 | — | S |
| **S-7** | `custom_request_orders` UPDATE 잠금: `drop policy cro_update`(authenticated) 또는 RESTRICTIVE 정책으로 `payment_status/status/state/order_status/stage/*_at` 변경 거부 | 웹 세션 클라이언트의 orders UPDATE 는 0건(grep: `.from("custom_request_orders")`+`.update(` 는 `customOrderEscrowService.ts:92` 만 — service_role) → DROP 안전. 관리자 콘솔 세션 UPDATE 0건 여부 **(확인 필요: lib/admin 동적 테이블명)**. 라이브 `cro_update` 존재 확인(`policies.json`) | — | S |
| **S-8** | `create unique index ux_cra_post_mentor_once on custom_request_applications(post_id, mentor_id)` | 웹 사전조회 `customRequestMutations.ts:190-202` 만이 중복 방지 — 앱 동시 제출 대비. 사전 중복 데이터 검사 DO 블록 선행 | — | S |

#### 권장(Tier B — 채택하지 않으면 앱이 Dart 로 재구현)

| ID | 객체 · 시그니처 초안 | 구현부 | 코드 | 규모 |
|---|---|---|---|---|
| **W-9** | `api_app_v1.custom_request_application_create(p_post_id uuid, p_proposed_price integer, p_delivery_at timestamptz, p_cover_note text, p_extra_answers text) → jsonb` | impl: 계정 게이트 → role mentor + `mentor_profiles.verification_status ∈ (approved,verified,active)`(웹 `mentorVerificationGate.ts:4-9`) → 글 `status='open' or state in ('open','published')`(`018:69-72` 동일) → 중복(`ALREADY_APPLIED`) → 마스킹(S-4) → insert(payload `customRequestMutations.ts:205-225` 동의어 전부) → (선택) `identity_verified_at` 게이트 `IDENTITY_REQUIRED`(§7 Q6) → `{application_id}`. 함께 `cra_insert` 를 `is_mentor()` 로 좁힐지 결정 | `MENTOR_NOT_APPROVED`, `POST_NOT_APPLICABLE`, `ALREADY_APPLIED`, `PRICE_INVALID`, `INPUT_REQUIRED`, `IDENTITY_REQUIRED` | M |
| **W-10** | `api_app_v1.custom_request_post_create(p_category text, p_subject text, p_goal text, p_body text, p_deadline timestamptz, p_budget_min integer, p_budget_max integer, p_deliverable_format text, p_status text default 'open', p_agreed boolean default false) → jsonb` · `…_post_update(p_post_id uuid, …)`(draft 한정) | impl: role student → 필수값·예산 1,000~200,000·동의 2종(`customRequestComposeActions.ts:65-92`) → 마스킹(S-4) → payload `customRequestMutations.ts:35-58` → `{post_id}` | `ROLE_NOT_ALLOWED`, `INPUT_REQUIRED`, `DEADLINE_REQUIRED`, `BUDGET_OUT_OF_RANGE`, `CONSENT_REQUIRED`, `POST_NOT_DRAFT` | M |
| **S-9** | Storage DELETE 정책(미등록 본인 객체만) — 3 버킷(`custom-request-post-attachments`, `custom-request-application-attachments`, `custom-order-deliverables`): `owner_id=auth.uid() and not exists(메타 행 storage_path=name)` (`qra_storage_delete_unregistered_owner` 패턴) | 앱 업로드 파이프라인의 보상 삭제(`attachment_upload.dart:194-259`) 가 실제 동작하게 함 | — | S |

#### 오너 결정(결제 경계 — Tier C, §7 Q2)

| ID | 객체 · 시그니처 초안 | 구현부 | 코드 |
|---|---|---|---|
| **W-1** | `api_app_v1.custom_order_select_application_with_hold(p_post_id uuid, p_application_id uuid) → jsonb` | 단일 트랜잭션: 작성자 검증 → 지원 검증(post 일치, `proposed_price>0`) → 활성 주문 검사(웹 `isActiveCustomRequestOrderRow` `customRequestQueries.ts:20,169`) → orders insert(`customRequestMutations.ts:250-280` payload) → `perform public.record_custom_order_escrow_hold(p_actor, v_order_id, price*100)` → `update payment_status='escrowed'` → `order_events` `payment_confirmed`; 예외 시 전체 롤백(웹 보상 삭제 불필요) | `NOT_POST_AUTHOR`, `APPLICATION_MISMATCH`, `ORDER_DUPLICATE`(23505 `ux_cro_active_application_once` `062:29-37`), `CASH_INSUFFICIENT`(`054:64`), `IDENTITY_REQUIRED` |
| **W-2** | `api_app_v1.custom_order_student_accept(p_order_id uuid) → jsonb` | `public.accept_custom_order_deliverable_atomic(p_order_id, p_actor, true)` 호출 후 `{ok:false,message}` 형 반환(`20260804100002:28-101`)을 code envelope 로 변환 + `order_events` `deliverable_accepted`·`settlement_item_created`(웹 `orderStudentActions.ts:159-185`) | `ORDER_NOT_FOUND`, `NOT_ORDER_STUDENT`, `PAYMENT_NOT_CONFIRMED`, `ORDER_TERMINAL`, `ORDER_STATUS_NOT_ACCEPTABLE`, `ORDER_HAS_ACTIVE_DISPUTE`, `DELIVERABLE_REQUIRED` |
| **W-3** | `api_app_v1.custom_order_student_cancel(p_order_id uuid) → jsonb` | 게이트(학생·primary `pending`·`payment_status='escrowed'`·활성 분쟁 없음 — `orderStudentActions.ts:226-255`) → `perform public.record_custom_order_escrow_refund(p_order_id)` → `order_events` `order_cancelled` | `ORDER_NOT_CANCELLABLE`, `ALREADY_PAID_OUT`, `PAYMENT_NOT_ESCROWED`(`056`) |

### 3.3 (c) 정책 공백·보안 리스크

1. **`cro_update` 광범위 UPDATE(라이브 확인)** — 당사자가 `payment_status='escrowed'` 를 hold 없이 만들 수 있고, 멘토 시작 RPC 는 그 값만 본다(`088:83-97`). 앱 출시 전 S-7 필수. 앱 코드는 어떤 경우에도 `custom_request_orders` 를 직접 UPDATE 하지 않는다(매니페스트 금지 테스트 추가 권고 — `from('users')` 체인 금지 패턴 `outbound_api_manifest_test.dart:298-311` 재사용).
2. **주문 메시징 RLS** — `cmsg_ins`/`coma_insert_party` 는 당사자 검사만 하고 종료 주문·마스킹은 웹 TS 에만 있다(`orderMessageActions.ts:126-128,177-184`). 앱 직접 INSERT 시 종료 주문에도 메시지가 들어가고 연락처가 그대로 저장된다 → W-7 로 DB 이전(권장) 또는 Dart 재구현(정책 우회 가능). Realtime 도입 시 `postgres_changes` 도 `cmsg_all_party` 를 따르므로 추가 정책 불필요.
3. **첨부 다운로드 서명 URL** — 앱은 세션 클라이언트 `createSignedUrl(path, 600)`(웹 TTL 600s 동일 `orderMessageAttachments.ts:16`)를 직접 호출한다. 학생의 납품 읽기는 DB(`063:44-72`)가 완료 전 차단하므로 서명 시도가 실패한다 — 앱은 웹처럼 완료 전 `storage_path` 를 화면 모델에서 제거(`orderDetailQueries.ts:148-167`)하고 실패를 "완료 후 열람" 상태로 매핑한다. 지원 첨부의 "선정 후 미리보기" 는 DB 강제가 없다(`059:163-170` 작성자 상시 허용) → 앱 코드 정책(웹 `applicationAttachmentAccess.ts:79-95`) 재구현 또는 DB 정책 강화(§7 Q15).
4. **연락처 마스킹·금지어 위치** — 금지어는 코드상 폐지(`lib/customRequest/bannedPhrases.ts:1-12`, `lib/safety/trustSafetyText.ts:15-28` → 항상 통과), 계약도 "실효 검증은 마스킹만"(`api_web_v1_contract_v1_1.md:421`). 마스킹은 커뮤니티에서 이미 SQL 로 이식됨 → S-4 로 함수화하고 CR wrapper(W-7/W-9/W-10) 안에서 적용하는 것이 "정책은 서버" 원칙(앱 HANDOFF: 서버 RPC 검증 전제)과 일치. Dart 포트를 택하면 앱 버전별 정규식 드리프트 리스크.
5. **`cra_insert` 역할·승인 미검증** — `mentor_id=auth.uid()` 만(`003:400-401`) → 학생 계정도 지원 행을 넣을 수 있고 트리거가 알림을 쏜다(`159:21-45`). 웹은 server action 이 막지만 DB 공백은 앱 이전과 무관하게 실재. W-9 + `cra_insert` 강화 권고.
6. **본인인증 게이트** — 웹 서버 계층 전용 설계(`identityGate.ts:3-6` "DB/RPC 레벨 가드는 절대 금지" — 근거는 '앱 재배포 없음'). 새 앱을 만드는 지금은 그 전제가 바뀌므로 impl 내부 `users.identity_verified_at` 검사(W-9/W-1)를 허용할지 오너 결정(§7 Q6). 앱은 자기 행 `identity_verified_at` 을 RLS 로 읽어 사전 안내만 할 수 있다.
7. **Storage DELETE 정책 부재(3 버킷)** — 업로드 후 메타 insert 실패 시 고아 객체(웹도 `ORPHAN_STORAGE_OBJECT` 로그로 방치). S-9 로 보상 삭제를 가능하게 하거나 고아 허용 명시.
8. **알림 배지 서버 제외(S-6)** 와 앱 게이트 해제는 반드시 같은 릴리스 창에서 처리(어긋나면 배지 수 ≠ 목록 수).
9. **선정된 글의 오픈 풀 잔류** — 주문 생성·완료 시 `custom_request_posts.status` 를 바꾸는 코드·트리거 없음(Phase 1 grep 0건; 본 조사에서도 CR 테이블 트리거는 알림 2종만). RPC 018 은 `status='open'` 글을 전부 반환하므로 이미 주문된 글에 멘토가 계속 지원한다(활성 주문 유니크는 두 번째 **주문**만 막음). 앱 필터 기준(또는 018 에 `not exists 활성 주문` 추가)은 §7 Q12.
10. **`api_app_v1` 에 service_role USAGE 없음** — 웹 서버가 앱 wrapper 를 호출할 수 없다(의도된 분리). 웹과 공용해야 하는 판정은 `core_private` impl 에 두고 필요하면 `api_web_v1` wrapper 를 같은 impl 로 연다(복제 금지 규약).

---

## 4. 앱 프론트엔드 설계

기존 앱 관례를 그대로 따른다: feature 폴더 `data/ui` 분리, `const` Repository + `_client/_uid` 정형, Port/Gateway/Backend seam + 손코딩 Fake(mock 프레임워크 없음), 봉투 strict 파싱, 코드→한글 매퍼, 원문 비노출(`app_architecture.md` §3-1~3-5; `app:lib/shared/errors/app_error.dart`, `friendly_error.dart:1-14`).

### 4.1 `lib/features/custom_request/` 구조

```
lib/features/custom_request/
  custom_request_flags.dart                 # §4.5 플래그
  data/
    models/                                 # §5 모델(fromMap + enum fromCode/unknown)
      custom_request_post.dart
      custom_request_application.dart
      custom_order.dart                     # + custom_order_lifecycle.dart 의 판정 입력
      custom_order_deliverable.dart
      custom_order_revision.dart
      custom_order_message.dart             # 메시지 + 첨부 뷰
      order_event.dart
      custom_order_settlement_item.dart
      custom_order_dispute.dart
      cr_attachment.dart                    # post/application 첨부 메타 공용
      model_parse.dart                      # 기존 2벌과 동일 시그니처(parseTime/parseInt) — 재구축 시 shared 로 승격 후보
    custom_order_lifecycle.dart             # orderLifecycleConstants.ts 순수 포트: primary 열 선택, 종료·수락허용·결제확정 토큰, 분쟁 활성 집합, 학생/멘토 탭 분류, 검토 마감(+3일) 계산
    custom_request_backend.dart             # 포트: CustomRequestBackend(select/insert/rpc(schema)/storage upload·remove·signedUrl) + SupabaseCustomRequestBackend
    custom_request_read_repository.dart     # 읽기 전용(RLS 의존, where 최소)
    custom_request_write_repository.dart    # 쓰기(RPC 단일 경로 우선)
    custom_request_envelope.dart            # {ok, contract_version==1} strict 파서(board_post_create_gateway.dart:120-135 규약)
    custom_request_error_mapper.dart        # raise 코드(088) + 봉투 코드(W-*) + 23505/23514/42501 → 한글
    custom_request_attachment_policy.dart   # 20 MiB · MIME 7종 · 매직바이트(sniffIqAttachmentMime 재사용) · 파일명 표시 정리(255자)
    custom_request_storage_paths.dart       # 4 버킷 상수 + 경로 빌더/검증(§4.3)
    custom_request_attachment_uploader.dart # 업로드→등록→보상 파이프라인(질문방 SupabaseAttachmentUploader 구조 이식, 버킷·등록 RPC 파라미터화)
    custom_request_url_resolver.dart        # 버킷별 서명 URL 리졸버(IqAttachmentUrlResolver 패턴, TTL 600s·마진 60s·uid 키)
    custom_request_paginator.dart           # CommunityPaginator<T> 재사용(offset) — 목록 4종
    custom_order_realtime.dart              # CustomOrderRealtimePort + SupabaseCustomOrderRealtime(orderId) (S-5 선행)
    contact_masking.dart                    # (Tier B 미채택 시에만) contactMasking.ts 정규식 6종 Dart 포트 — 채택 시 미리보기 전용
  ui/
    student/ …  mentor/ …  shared/ …        # §4.2
```

**Repository 메서드(데이터 의존만)**

읽기 `CustomRequestReadRepository`:
- `myPosts({includeDrafts})` → `custom_request_posts` where author_id=uid(RLS `crp_select`), order created_at desc.
- `openPostsForMentor(limit≤200)` → RPC `list_open_custom_request_posts_for_mentor_browse` (`018`); 앱에서 `appliedPostIds` 제외(웹 `mentorCounts.ts:44-47`).
- `publicPost(postId)` → 직접 SELECT → 0행이면 RPC `get_public_custom_request_post_for_browse`(웹 `customRequestQueries.ts:287-303` 동일 순서). draft 는 작성자 외 숨김(`isDraftCustomRequestPost` 포트).
- `postAttachments(postId)` / `applicationAttachments(applicationIds)` → 메타 테이블 SELECT.
- `applicationsForPost(postId)` + `mentorDisplays(mentorIds)` → `cra_select` + `api_web_v1.mentor_directory_v1 in(mentor_id)`(웹 `customRequestQueries.ts:809-812`).
- `myApplications()`(멘토) → `custom_request_applications` where mentor_id=uid + 글 힌트(RPC 006 N회 또는 `cra_select` 조인 불가 → 글 제목은 RPC 006 배치, 주문 전환분 제외 웹 `:663-670` 재현).
- `myOrders(role, limit=80)` → `custom_request_orders` where student_id|mentor_id=uid(웹 `studentCustomRequestOrdersQueries.ts:150-178`, `mentorDashboardQueries.ts:91-106`) + `activeDisputeOrderIds(ids)`(`disputes in()` → 활성 상태 집합).
- `orderBundle(orderId)` → 병렬: order, deliverables(version desc), revisions(desc), messages(asc)+attachments, events, settlement item(단건), disputes, post, application, mentorDisplay(`mentor_directory_v1`), studentDisplay(`get_mentor_student_nicknames`) — 웹 `orderDetailQueries.ts:268-362` 동일 집합. 학생 뷰는 완료 전 deliverable `storage_path` 제거(`:148-167`).
- `mentorWorkspaceCounts()` → 웹 `mentorCounts.ts:23-95` 집계(applied/orders/open/disputes) 앱 로컬 계산.
- `myDisputes(role)` / `disputeById(id)` → `disputes`(+ `refunds` 본인 행).
- `myIdentityVerified()` → `users.select('identity_verified_at').eq('id', uid)`(RLS 본인; 매니페스트 `users` SELECT 전용 규칙 준수).
- `amIApprovedMentor()` → `mentor_directory_v1.eq('mentor_id', uid)` 1행 존재 여부(뷰가 승인 상태만 노출 `20260803170916:189-191`).

쓰기 `CustomRequestWriteRepository`(각 성공 지점에서 `DataRefreshBus.bumpCustomRequest()`):
- `createPost/updateDraft` → W-10 채택 시 `.schema('api_app_v1').rpc('custom_request_post_create'|'…_update')`; 미채택 시 직접 insert/update(payload `customRequestMutations.ts:35-58`) + Dart 마스킹.
- `deleteDraft(postId)` → W-0.
- `uploadPostAttachment(postId, file)` → Storage `custom-request-post-attachments` upload → `custom_request_post_attachments` insert(`uploaded_by=uid`). (등록 RPC 없음 — 직접 insert; 보상 삭제는 S-9 있을 때만 유효.)
- `applyToPost(...)` → W-9 채택 시 RPC; 미채택 시 사전 중복 조회 + 직접 insert(payload `:205-225`) + `amIApprovedMentor()` 사전 게이트.
- `uploadApplicationAttachment(applicationId, file)` → Storage `custom-request-application-attachments` + 메타 insert.
- `startWork(orderId)` → `rpc('custom_order_mentor_start')` + `order_events` `order_started` insert(웹 `orderMentorActions.ts:52-123` 동치, best-effort).
- `submitDeliverable(orderId, {file?, note})` → 버전 = `max(version)+1` 조회 → 경로 `{orderId}/{version}/{ts}-{8hex}.{ext}` 업로드 → W-8 RPC(`DELIVERABLE_VERSION_STALE` 이면 객체 정리(S-9)·재채번·재시도 ≤5, 웹 `MAX_DELIVERABLE_ATTEMPTS`). W-8 미채택 시: 웹과 동일한 insert → `custom_order_mentor_deliver` → events 3단계.
- `requestRevision(orderId, note)` → `rpc('custom_order_student_request_revision')` + events `revision_requested`.
- `sendMessage(orderId, body, {attachment?})` → 첨부 있으면 먼저 Storage `custom-order-message-attachments` 업로드(`{orderId}/{uid}/{ts}-{12hex}.{ext}` — CHECK 정규식 `083:66-70` 준수) → W-7 RPC(메시지+첨부 행+이벤트 원자). 미채택 시 insert 3회 직접.
- `openDispute(orderId, body)` → 웹 조건(`orderDisputeActions.ts:107-166`: 8,000자, 종료 불가, 멘토는 납품 이후/검토 단계) 앱 판정 → `disputes` insert(`{custom_request_order_id, student_id, mentor_id, submitted_by=uid, body, status:'open'}` `:53-79`) → 23505(`disputes_order_active_unique`) → `DISPUTE_ALREADY_ACTIVE` → events `dispute_opened`.
- `recordEvent(orderId, kind, extra)` → `order_events` insert `{custom_request_order_id, order_id, custom_order_id, request_order_id, event, metadata:{event, actor_id, …}}`(`orderRoomMutations.ts:30-47`; kind 10종 `:10-20`).

### 4.2 화면(이름·역할·데이터 의존)

| 화면 클래스 | 역할 | 데이터 의존(Repository 메서드) | 웹 대응 |
|---|---|---|---|
| `CustomRequestEntryScreen` | 학생·멘토 공용 진입(역할 분기해 아래 대시보드로) | `AuthService.currentRole` | `/custom-request` |
| `StudentCustomRequestHomeScreen` | 학생: 내 의뢰·주문 요약, 작성 진입 | `myPosts`, `myOrders('student')` | `/custom-request`(학생) |
| `CustomRequestPostComposeScreen({draftId?})` | 의뢰 작성·임시저장·이어쓰기 + 첨부(≤40, 20 MiB) | `createPost/updateDraft`, `uploadPostAttachment`, `publicPost(draft)` | `/custom-request/new` |
| `MyCustomRequestPostsScreen` | 내 의뢰 목록(임시 포함) + 임시 삭제 | `myPosts(includeDrafts:true)`, `deleteDraft` | `/custom-request/posts` |
| `CustomRequestPostDetailScreen(postId)` | 공개 상세 + 첨부(멘토: 지원 진입, 학생 작성자: 지원 비교 진입) | `publicPost`, `postAttachments`, 멘토면 `myApplications` 포함 여부 | `/custom-request/[postId]`, `/mentor/custom-request/posts/[postId]` |
| `ApplicationsCompareScreen(postId)` | 학생 작성자: 지원 비교(프로필·가격·납기·제안) · 첨부는 활성 주문 존재 시만 미리보기 · **선정 CTA = 웹 위임 안내/딥링크(플래그)** | `applicationsForPost`, `mentorDisplays`, `applicationAttachments`, `myOrders` 로 활성 주문 판정 | `/custom-request/[postId]/applications` |
| `StudentCustomOrdersScreen` | 학생 주문 목록(탭 all/dispute/waiting/work/review/done — `studentOrderBrowseTabClassify.ts:9-21`) | `myOrders('student')`, `activeDisputeOrderIds` | `/custom-request/orders` |
| `CustomOrderRoomScreen(orderId)` | **공용 주문방**: 헤더·진행 단계·납품 패널·수정요청 패널·메시지 패널·이벤트 로그·분쟁 패널·정산 배너 · 역할별 액션(멘토: 시작/납품 · 학생: 수정요청 · 공용: 메시지/분쟁 · **수락·취소 = 웹 위임 안내**) · 검토 카운트다운(표시) · 활성 분쟁 잠금 | `orderBundle`, `startWork`, `submitDeliverable`, `requestRevision`, `sendMessage`, `openDispute`, `CustomOrderRealtimePort` | `/custom-request/orders/[orderId]` |
| `CustomOrderCompleteScreen(orderId)` | 완료 요약(납품·결제 상태·정산) | `orderBundle` | `…/complete` |
| `MyDisputesScreen` / `DisputeDetailScreen(disputeId)` | 분쟁 목록·상세(연계 주문·환불 읽기) | `myDisputes`, `disputeById` | `/support/disputes[/id]`, `/mentor/support/disputes[/id]` |
| `MentorCustomRequestDashboardScreen` | KPI + 진행 주문 | `mentorWorkspaceCounts`, `myOrders('mentor')`, 정산 `custom_order_settlement_items` | `/mentor/custom-request/dashboard` |
| `MentorOpenPostsScreen` | 오픈 풀(카테고리 4탭 휴리스틱 `mentorOpenPostCategory.ts:19-33`) / 제안한 의뢰 탭 | `openPostsForMentor`, `myApplications` | `/mentor/custom-request/posts` |
| `MentorApplicationComposeScreen(postId)` | 지원서(가격·납기·제안·추가답변·첨부) | `amIApprovedMentor`, `applyToPost`, `uploadApplicationAttachment` | `…/apply` |
| `MentorCustomOrdersScreen` | 멘토 주문 목록(탭 7종 `mentorOrderBrowseTabClassify.ts:9-35`) | `myOrders('mentor')`, `activeDisputeOrderIds` | `/mentor/custom-request/orders` |

역할 분기: 화면 내부 `switch(AuthService.instance.currentRole)`(현 관례 `question_room_screen.dart:41-54`)이 아니라 **진입 화면 1곳**(`CustomRequestEntryScreen`)에서 갈라 학생/멘토 화면을 각각 push 하고, 공용 `CustomOrderRoomScreen` 만 `role` 생성자 인자로 액션 바를 바꾼다(웹 `OrderActionBar.tsx:121-146` 배선과 동일). 관리자·게스트는 진입 차단(게스트 허용 탭 `{1,2}` 밖 — `entry_guard.dart:25`).

### 4.3 재사용할 기존 코어

| 코어 | 위치 | CR 에서의 사용 |
|---|---|---|
| 첨부 업로드 파이프라인(Backend 포트, upsert:false, 등록 RPC, 23505 의미 일치 검사, 보상 삭제) | `app:lib/features/question_room/data/attachments/attachment_upload.dart:104-114,194-259,331-353` | `CustomRequestAttachmentUploader` 로 구조 이식 — 버킷·경로·등록 호출(W-8/W-7 RPC 또는 메타 insert)을 파라미터화. 보상 삭제는 S-9 없으면 no-op(고아 허용 로그) |
| IQ 업로드 순수 오케스트레이터(typedef 주입, 40001 1회 재시도, 등록 불확정 판정) | `app:lib/features/individual_question/data/iq_attachment_upload_core.dart:46-70` | 납품 재시도 루프(`DELIVERABLE_VERSION_STALE`)의 단위 테스트 모델 |
| 첨부 정책·매직바이트 | `app:…/iq_attachment_policy.dart:11-19,25-` | CR MIME 7종(`gif`·`json` 제외)·20 MiB 로 상수만 교체 |
| 서명 URL 리졸버(TTL·마진·uid 키·실패 미캐시·전역 공유) | `app:…/iq_attachment_url_resolver.dart:30-71` | 4 버킷 × 1 인스턴스(제네릭화 권장 — `app_architecture.md` §9-2) |
| Realtime 포트(postgres_changes, 재연결 1회, dispose, 재조회 폴백) | `app:…/iq_realtime.dart:12-110` | `CustomOrderRealtimePort`: 채널 `custom_order_<orderId>` — INSERT `custom_order_messages`(custom_request_order_id=) · INSERT `custom_order_message_attachments`(order_id=) · INSERT `custom_order_deliverables`(custom_request_order_id=) · UPDATE `custom_request_orders`(id=). S-5 미적용이면 콜백 없음 → 폴백만 |
| `DataRefreshBus` | `app:lib/core/refresh/data_refresh_bus.dart` | `customRequestGeneration` + `bumpCustomRequest()` 추가; 목록·대시보드·주문방이 구독 |
| `ResumeVisibilityGate`/`ScreenVisibility` | `app:lib/shared/widgets/screen_visibility.dart:11-68` | 목록·주문방 resume 재조회(웹 선정·수락 후 앱 복귀가 정본 갱신 경로 — `data_refresh_bus.dart` subscription 주석과 같은 이유) |
| 봉투 파서·매퍼 관례 | `app:…/board_post_create_gateway.dart:120-135`, `community_post_error_mapper.dart:11-50`, `iq_error_mapper.dart:69-80`(선두 토큰 `^[A-Z][A-Z0-9_]+`) | `custom_request_envelope.dart`(W-* 봉투) + `custom_request_error_mapper.dart`(088 raise 코드 17종 + `CASH_INSUFFICIENT` 등은 웹 위임이라 미노출) |
| Fake 주입 seam | `app:test/community/fakes.dart:8-40`(`_Unset` 센티넬), `RecordingCommentsGateway` | `FakeCustomRequestBackend`(호출 기록 + 응답 주입) 1개로 read/write 전부 커버 |
| 웹 브릿지 | `app:lib/core/web_bridge/web_bridge.dart`, `web_bridge_config.dart`, `web_bridge_actions.dart` | `WebBridgeConfig.customRequestApplicationsPath(postId)='/custom-request/$postId/applications'`, `customOrderPath(orderId)='/custom-request/orders/$orderId'` + `openCustomRequestSelectionWeb/openCustomOrderRoomWeb` — **플래그 OFF 기본**(§4.5) |
| 학생 표시명 | `app:lib/features/question_room/data/student_lookup_repository.dart:54` | 그대로 사용 |
| 알림 딥링크 정본(`resolveNotificationDeepLink` 순수 함수·UUID 검증·opener) | `app:…/notification_deep_link_controller.dart:8-17,95-155`, `notification_target_opener.dart:36-56` | §4.4 |

### 4.4 라우트·진입·알림 배선

- 현 라우터는 명명 라우트 4개 + 명령형 push(`app:lib/app/router.dart:25-53`, `entry_guard.dart:38-51` 이 `/home` 외 전부 되돌림). CR 화면은 전부 **push 라우트**로 추가한다(생성자 인자 `postId`/`orderId` 만 받고 내부 조회 — 딥링크 어댑터 증식을 막기 위해 모델 객체 인자 금지).
- 진입점(권고): (a) 마이페이지 섹션 행 "맞춤의뢰"(학생: `StudentCustomRequestHomeScreen`, 멘토: `MentorCustomRequestDashboardScreen`) (b) 알림 딥링크. 하단 탭 추가(6번째)는 `AppTab`·`_pages`·`_icons`·`bottomTabLabels`·`guestAllowedTabs` 5곳 동시 수정(`app_tabs.dart:10-19`, `home_shell.dart:47-62`, `app_constants.dart:24-30`, `entry_guard.dart:25`)이라 §7 Q13 오너 결정.
- 알림: `kGatedNotificationTypeCodes` 를 빈 집합으로(목록 `not.in` 제거 — S-6 와 동시), `NotificationDestination` 에 `customRequestOrder`·`customRequestApplications` 추가 → `notificationDestinationOf` 2종 매핑 변경(`notification_types.dart:165-168`), `NotificationDeepLinkTarget` 에 `orderId`·`postId`·`applicationId`(metadata `159:39-40,72-74`) 필드, sealed route `NotificationCustomOrderRoute(orderId)`·`NotificationCustomRequestPostRoute(postId)`, `notificationRouteFallbackTab`(마이페이지 폴백), `NotificationTargetOpener.open` 분기 2종(당사자 사전 조회 RLS 후 push). 설정 라벨 `'order'` 문구는 §7 Q14.
- 라우트 추가 목록(push): `CustomRequestEntryScreen`, `StudentCustomRequestHomeScreen`, `CustomRequestPostComposeScreen`, `MyCustomRequestPostsScreen`, `CustomRequestPostDetailScreen`, `ApplicationsCompareScreen`, `StudentCustomOrdersScreen`, `CustomOrderRoomScreen`, `CustomOrderCompleteScreen`, `MyDisputesScreen`, `DisputeDetailScreen`, `MentorCustomRequestDashboardScreen`, `MentorOpenPostsScreen`, `MentorApplicationComposeScreen`, `MentorCustomOrdersScreen` (15).

### 4.5 플래그(게이트) 설계 — `custom_request_flags.dart`

`iq_flags.dart:10-19` 와 같은 컴파일 타임 `bool.fromEnvironment`:
- `kCustomRequestEnabled`(`CR_ENABLED`, 기본 **false**) — 진입점·알림 게이트 해제·딥링크 목적지 전체.
- `kCustomRequestSelectionWebLinkEnabled`(`CR_SELECTION_WEB_LINK_ENABLED`, 기본 false) — 지원 비교 화면의 "웹에서 선정" 외부 브라우저 링크. OFF 면 `kSubscriptionManageNoticeText` 류 안내 문구만(`commerce_policy.dart:20-21` 패턴).
- `kCustomOrderWebActionLinkEnabled`(`CR_ORDER_WEB_LINK_ENABLED`, 기본 false) — 주문방의 수락·취소 웹 링크.
- `kCustomOrderRealtimeEnabled`(`CR_REALTIME_ENABLED`, 기본 false) — S-5 적용 확인 후 ON.
서버 값 기반 게이트(예: `app_notices`/버전 정책 행)는 두지 않는다 — 현 앱 관례가 전부 dart-define 이며, 서버 게이트는 S-6 한 곳이 이미 "앱 정본과 동일 목록" 을 전제로 하므로 양쪽 동시 변경으로 관리한다.

### 4.6 `outbound_api_manifest_test.dart` 갱신 항목

- `kExpectedRpcNames` 추가: `custom_order_mentor_start`, `custom_order_mentor_deliver`, `custom_order_student_request_revision`, `get_public_custom_request_post_for_browse`, `list_open_custom_request_posts_for_mentor_browse`, `custom_request_post_delete_draft`, `custom_order_deliverable_register`, `custom_order_message_create` (+ Tier B `custom_request_application_create`, `custom_request_post_create`, `custom_request_post_update`; Tier C 채택 시 `custom_order_select_application_with_hold`, `custom_order_student_accept`, `custom_order_student_cancel`).
- `kExpectedTables` 추가: `custom_request_posts`, `custom_request_post_attachments`, `custom_request_applications`, `custom_request_application_attachments`, `custom_request_orders`, `custom_order_deliverables`, `custom_order_revisions`, `custom_order_messages`, `custom_order_message_attachments`, `order_events`, `custom_order_settlement_items`, `disputes`, `refunds`(분쟁 상세 읽기 시).
- 버킷 상수(리터럴 금지): `CustomRequestStoragePaths.postAttachmentsBucket='custom-request-post-attachments'`, `.applicationAttachmentsBucket='custom-request-application-attachments'`, `.deliverablesBucket='custom-order-deliverables'`, `.messageAttachmentsBucket='custom-order-message-attachments'` → `kExpectedBucketIdentifiers`/`kExpectedBucketNames` 4개씩.
- `kForbiddenWords` 추가(회귀 차단): `record_custom_order_escrow_hold`, `record_custom_order_escrow_payout`, `record_custom_order_escrow_refund`, `accept_custom_order_deliverable_atomic`, `record_custom_order_dispute_split`.
- 신규 금지 테스트: `from('custom_request_orders')` 체인에 `.update(`/`.delete(` 0건(`:298-311` 패턴).
- 스키마 집합 `{api_app_v1, api_web_v1}` 변동 없음. Realtime 채널명 `custom_order_` 접두는 문서(§2.6 표)에 추가.

---

## 5. 데이터 모델 (테이블/뷰 → Dart)

공통: `const` 클래스 + `factory fromMap` + enum `fromCode()`·`unknown` 폴백("DB 로 다시 쓰지 않는다" — `question_thread.dart:6-39` 관례). 금액은 **원(캐시) 정수**(`agreed_price numeric`), 원장만 ×100(`customOrderEscrowService.ts:50`).

| Dart 모델 | 소스 | 필드(컬럼) | enum |
|---|---|---|---|
| `CustomRequestPost` | `custom_request_posts`(`003:94-127`) / RPC 006·018 TABLE(23열, 작성자 uuid 미포함 `006:11-34`) | `id`, `authorId?`(RPC 경로엔 null), `title`(title→subject 폴백), `body`, `goal`(goal→subcategory), `category`, `deadline`(due_at→deadline→due_date), `deliverableFormat`(deliverable_format→result_format→deliverable_type→output_format), `budgetMin?`, `budgetMax?`(numeric→int), `status`, `state`, `createdAt`, `updatedAt` | `CustomRequestPostStatus {open, closed, cancelled(canceled 동치), fulfilled, pending, draft, archived, inReview, inProgress, unknown}`(CHECK `003:118-124`) |
| `CrAttachment` | `custom_request_post_attachments`(`012:8-18`) · `custom_request_application_attachments`(`059:9-18`) | `id`, `parentId`(custom_request_post_id / application_id), `uploadedBy`, `storagePath`, `originalFilename`, `mimeType?`, `fileSizeBytes?`, `createdAt`, `kind {post, application}` | — |
| `CustomRequestApplication` | `custom_request_applications`(`003:142-178`) | `id`, `postId`, `mentorId`, `proposedPrice`(proposed_price→price→bid_amount), `deliveryAt`(delivery_at→proposed_due→due_proposed), `coverNote`(cover_letter→message→self_intro), `scope`(scope→offer_scope→services_offered), `extraAnswers`(extra_answers→answers→notes), `status`, `createdAt`; 표시용 `MentorDisplay`(뷰 `mentor_directory_v1`: `nickname, university_name, department_name, school_verified, avg_rating, review_count, profile_image_url`) | `ApplicationStatus {submitted, selected, accepted, rejected, withdrawn, unknown}`(DB 강제 없음; insert 는 submitted 만) |
| `CustomOrder` | `custom_request_orders`(`003:196-237`) | `id`, `postId`, `applicationId`(application_id→custom_request_application_id→selected_application_id), `studentId`, `mentorId`, `status`, `state`, `orderStatus`, `stage`, `paymentStatus`, `agreedPrice`(agreed_price→proposed_price→price→amount), `startedAt`, `acceptedAt`, `completedAt`, `closedAt`, `finishedAt`, `createdAt`, `updatedAt`; 파생 getter `primaryStatus`(status→state→order_status→stage 첫 비공백, `orderLifecycleConstants.ts:36-54` = `088:13-54`), `isTerminal`(4열 중 하나라도 종료값 or `*_at` 非NULL `:141-184`), `isPaymentConfirmed`(`:362-372` 토큰 8종), `allowsStudentAccept`(`:88-100` 7종), `isRevisionRequested`(**`order_status` 열 별도 판독** — §7 Q9) | `CustomOrderPrimaryStatus {pending, open, delivered, revisionRequested, completed, cancelled, disputeResolved, legacyReview(delivered_pending_review/waiting_review/pending_review/redelivered/delivery_submitted/in_review), unknown}` · `CustomOrderPaymentStatus {unpaid, escrowed, paid, refunded, disputeResolved, unknown}`(관측값 `web_custom_request.md` §1.1) |
| `CustomOrderDeliverable` | `custom_order_deliverables`(`003:274-288`, `010:8-26`) | `id`, `orderId`(custom_request_order_id), `version`, `status`, `note?`, `storagePath?`(학생 완료 전 null), `originalFilename?`, `mimeType?`, `fileSize?`(file_size→file_size_bytes), `createdAt`(submitted_at 없음 — created_at 이 검토 마감 기준) | `DeliverableStatus {submitted, unknown}` |
| `CustomOrderRevision` | `custom_order_revisions`(`003:290-302`) | `id`, `orderId`, `authorId`, `requestNote`, `status`, `createdAt` | `{open, unknown}` |
| `CustomOrderMessage` | `custom_order_messages`(`003:304-315`) | `id`, `orderId`, `authorId`, `body`, `createdAt`; 파생 `partyLabel`(author_id = student/mentor → 학생/멘토/참여자 `orderRoomMutations.ts:130-147`) | — |
| `CustomOrderMessageAttachment` | `custom_order_message_attachments`(`083:43-70`) | `id`, `orderId`(order_id), `messageId?`, `uploaderId`, `storagePath`, `originalFilename`, `mimeType`, `fileSizeBytes`, `createdAt`; 뷰 파생 `isImage`, `isPdf`, `signedUrl?`(리졸버) | MIME 7종 CHECK |
| `OrderEvent` | `order_events`(`003:317-329`) | `id`, `orderId`, `event`(kind), `metadata`(jsonb: `event, actor_id, …`), `createdAt` | `OrderEventKind {orderStarted, orderCancelled, deliverableSubmitted, deliverableAccepted, messageCreated, revisionRequested, disputeOpened, disputeSplitApplied, settlementItemCreated, paymentConfirmed, unknown}`(`orderRoomMutations.ts:10-20`) |
| `CustomOrderSettlementItem` | `custom_order_settlement_items`(`013:10-24`, `090:17-18`) | `id`, `orderId`, `mentorId`, `studentId`, `grossAmount`, `platformFeeAmount`, `mentorAmount`, `feeRate`(numeric — 표시만, 재계산 금지), `status`, `reason?`, `paidAt?`, `createdAt` | `SettlementStatus {pending, onHold, payable, paid, cancelled, unknown}`(CHECK `013:19`) |
| `CustomOrderDispute` | `disputes`(`004:83-94`, `009:17-19`, `034`) | `id`, `orderId`(custom_request_order_id), `studentId`, `mentorId`, `submittedBy?`, `status`, `body`, `adminNote?`(관리자 RLS 라 당사자에게 보이는지 **(확인 필요)**), `resolvedAt?`, `createdAt`, `updatedAt?`; 파생 `isActive`(open/under_review/escalated `orderDisputeHelpers.ts:12`) | `DisputeStatus {open, underReview, resolved, dismissed, escalated, onHold, sanction7d, sanction30d, sanctionPermanent, unknown}`(CHECK 확장 `20260717125606_120_admin_console_fixes.sql:17`) |
| `MentorWorkspaceCounts` | 앱 집계 | `open, openByCategory{study,career,essay,other}, applied, billing, work, delivery, revision, done, dispute, ordersTotal`(`mentorCounts.ts:23-95`) | `MentorOpenPostCategory {study, career, essay, other}` · `MentorOrderTab {all, dispute, billing, work, delivery, revision, done}` · `StudentOrderTab {all, dispute, waiting, work, review, done}` |
| `IdentityGateStatus` | `users.identity_verified_at`(`20260820100200:80`) | `verifiedAt?` → `isVerified` | — |

RPC 반환 형(파서):
- 전이 RPC 3종 성공 `{ok:true, transition, from, to[, revision_id]}` / 실패는 PostgrestException message 선두 코드(`088` raise) — `CustomOrderTransitionResult`.
- W-* 봉투 `{ok, contract_version:1, code?, …}` — `CrEnvelope<T>`; `contract_version != 1` 은 실패 처리(성공 위장 금지 규약 `app_architecture.md` §8-2).

---

## 6. 구현 순서·의존성·규모

규모: S ≤ 0.5일 · M 1~2일 · L 3~5일 · XL > 5일(설계·테스트 포함, 1인 기준).

### Phase 0 — 결정·계약(선행)
| # | 항목 | 규모 | 의존 |
|---|---|---|---|
| 0-1 | §7 오너 결정 Q1~Q6(게이트 동시 ON · 결제 wrapper 채택 여부 · 딥링크 · Realtime · 마스킹 위치 · 본인인증) | — | — |
| 0-2 | 앱 계약 v1.x 증보(CR 절 신설: W-0/W-7/W-8(+W-9/W-10) 시그니처·코드 사전) + 웹 계약 §19.5 재동기화 문서 | M | 0-1 |

### Phase 1 — 서버(웹 저장소 pack, 앱 코드보다 먼저 라이브)
| # | 항목 | 규모 | 의존 |
|---|---|---|---|
| 1-1 | S-7 `cro_update` 잠금(+ lib/admin 세션 UPDATE 0건 확인) | S | — |
| 1-2 | S-8 applications (post_id, mentor_id) 유니크(사전 중복 검사 포함) | S | — |
| 1-3 | S-4 `core_private.mask_contact_text` | S | — |
| 1-4 | W-0 draft 삭제 wrapper | S | 0-2 |
| 1-5 | W-8 납품 등록 wrapper | M | 0-2, S-9(선택) |
| 1-6 | W-7 메시지 생성 wrapper | M | 1-3, 0-2 |
| 1-7 | W-9 지원 생성 wrapper(+`cra_insert` 강화) · W-10 글 생성/수정 wrapper (Tier B, 채택 시) | M+M | 1-3, 0-1 Q5/Q6 |
| 1-8 | S-9 Storage DELETE 정책 3 버킷(선택) | S | — |
| 1-9 | S-5 Realtime publication 4 테이블(채택 시) | S | 0-1 Q4 |
| 1-10 | S-6 `notification_unread_count_self` CR 제외 해제 — **앱 게이트 해제 릴리스와 동일 창** | S | 0-1 Q1 |
| 1-11 | Tier C(W-1/W-2/W-3) — 채택 시에만 | M+S+S | 0-1 Q2 |
| 1-12 | pack 등재·rollback·검증 스크립트·`db-apply-pending`·`contracts:export/verify`·인벤토리 갱신 | S/배치 | 위 전부 |

### Phase 2 — 앱 데이터 계층
| # | 항목 | 규모 | 의존 |
|---|---|---|---|
| 2-1 | 모델 12종 + enum + `custom_order_lifecycle.dart` 포트(+단위 테스트: primary 열·종료·탭 분류·검토 마감) | M | — |
| 2-2 | `CustomRequestBackend` 포트 + Supabase 구현 + `FakeCustomRequestBackend` | S | — |
| 2-3 | Read repository(12 메서드) | M | 2-1, 2-2 |
| 2-4 | Write repository(RPC 경로) + 봉투 파서 + 에러 매퍼(088 코드 17종 + W-* 코드) | M | 1-4~1-7 라이브(또는 직접 경로 폴백 분기) |
| 2-5 | 첨부 정책·경로 빌더(4 버킷, CHECK 정규식 일치 테스트)·업로더·서명 URL 리졸버 | M | 2-2 |
| 2-6 | `CustomOrderRealtimePort`(채널·필터·재연결·폴백) | S | 1-9 |
| 2-7 | (Tier B 미채택 시) `contact_masking.dart` Dart 포트 + 정규식 동치 테스트 | S | 0-1 Q5 |
| 2-8 | 플래그 파일 · `DataRefreshBus.customRequestGeneration` · 매니페스트 갱신(RPC/테이블/버킷/금지어/새 금지 테스트) | S | 2-3, 2-4 |

### Phase 3 — 앱 화면(15 push 라우트)
| # | 항목 | 규모 |
|---|---|---|
| 3-1 | `CustomRequestEntryScreen` + 마이페이지 진입 행(역할 분기) | S |
| 3-2 | 학생: `StudentCustomRequestHomeScreen`, `MyCustomRequestPostsScreen`(draft 삭제) | M |
| 3-3 | `CustomRequestPostComposeScreen`(작성·임시저장·이어쓰기·첨부 ≤40) — 문서 파일 선택은 `ScanSourcePort` 가 이미지+PDF 한정(`scan_source_picker.dart:13-25`)이라 `DocumentPickerPort`(zip/docx/pptx) 신설 포함 | L |
| 3-4 | `CustomRequestPostDetailScreen`(공용) + 첨부 열기 | M |
| 3-5 | `ApplicationsCompareScreen`(비교·첨부 게이트·선정 웹 위임 안내/링크) | M |
| 3-6 | `StudentCustomOrdersScreen` / `MentorCustomOrdersScreen`(탭 분류) | M |
| 3-7 | **`CustomOrderRoomScreen`**(패널 6종 + 역할 액션 + 잠금 + 카운트다운 + Realtime 병합 + 첨부 업로드/열기) | XL |
| 3-8 | `CustomOrderCompleteScreen` | S |
| 3-9 | `MyDisputesScreen`, `DisputeDetailScreen`, 분쟁 제기 시트(주문방) | M |
| 3-10 | 멘토: `MentorCustomRequestDashboardScreen`(KPI 집계), `MentorOpenPostsScreen`(카테고리·제안 탭) | M+M |
| 3-11 | `MentorApplicationComposeScreen`(승인 게이트·첨부) | M |

### Phase 4 — 통합·출시
| # | 항목 | 규모 | 의존 |
|---|---|---|---|
| 4-1 | 알림 배선: 게이트 집합 비우기·목적지 2종·route 2종·opener 분기·설정 라벨(Q14) + `resolveNotificationDeepLink` 테스트 | M | 1-10 |
| 4-2 | 위젯·로직 테스트(Fake backend), 계약 테스트 갱신(매니페스트·iOS `PrivacyInfo` — 문서 첨부 업로드는 기존 `OtherUserContent` 로 커버되는지 **(확인 필요)** `ios_release_config_contract_test.dart:44-50`) | L | 전부 |
| 4-3 | 스토어 정책 QA 체크리스트(정책 §7: 결제 유도 문구 0건·웹 URL 전수) — CR 화면의 금액 표시(`agreedPrice`·예산)는 "상태 표시" 범위인지 검토 | S | 3-x |
| 4-4 | 출시 동시 조치: 웹 `NEXT_PUBLIC_FEATURE_CUSTOM_REQUEST=on` · 앱 `CR_ENABLED=true` 빌드 · S-6 적용 · `mobile_app_version_policies` 상향 여부 | S | Q1 |

총량(Tier A+B, Tier C 제외): 서버 ≈ 6~8일, 앱 데이터 ≈ 6~8일, 앱 화면 ≈ 15~20일, 통합 ≈ 5~7일.

---

## 7. 오너 결정 필요 항목

| # | 질문 | 권고안 | 근거 |
|---|---|---|---|
| Q1 | 앱 CR 출시 시 웹 게이트를 동시에 ON 하나? | **동시 ON**. 백엔드·알림 트리거는 이미 라이브라 앱 노출 = 출시. 웹 네비만 숨긴 채 앱을 열면 멘토 웹 동선이 끊기고 "선정은 웹에서" 위임 페이지가 네비 없는 상태가 됨 | `featureFlags.ts:5-10`, `mainNavItems.ts:121-136`, `159:21-82` |
| Q2 | 선정(hold)·수락(payout)·취소(refund)를 앱 wrapper(W-1~3)로 열 것인가? | **1차 출시는 웹 위임**(정책 §3 "결제 실행 금지"에 정확히 부합, DB 권한과 일치). 앱은 상태 표시 + 안내 문구. Play 정책 검토(`docs/PLAY_STORE_REVIEW_PLAN.md`) 결론 후 IQ `release/refund` 와 함께 재판정 | 정책 `:16`; `054/055/056` service_role; DB 리포트 §4 #13-14 |
| Q3 | 앱에서 웹 선정/주문방 페이지로 외부 브라우저 딥링크를 허용하나? | **플래그 기본 OFF**(IQ `kIndividualQuestionCreateEnabled` 동형). 정책 §4 가 "웹 결제 URL 딥링크·우회 문구" 를 금지하므로 법무/스토어 검토 전엔 안내 문구만 | `iq_flags.dart:10-19`, `web_bridge_config.dart:22-24` 주석, 정책 §4 |
| Q4 | 주문방 Realtime 도입(publication 4 테이블)? | **도입(S)**. 앱 질문방·IQ 가 이미 같은 패턴이고 폴백(재조회)이 있어 리스크 낮음. 단 `custom_request_orders` UPDATE 이벤트는 웹 수락 시 앱 즉시 반영에 필요 | `20260803171053:77-84`(CR 미포함), `iq_realtime.dart:30-36` |
| Q5 | 마스킹·종료차단·승인게이트를 DB wrapper(Tier B)로 내리나, Dart 재구현인가? | **DB wrapper**. 커뮤니티가 이미 SQL 마스킹을 이식했고(`20260731113927:200-215`), 앱 쓰기 관례가 RPC 단일 경로. Dart 포트는 버전별 드리프트 | §3.3-2,4,5 |
| Q6 | 본인인증 게이트를 앱 지원(W-9)/선정(W-1)에 어떻게 적용? | 현재 웹도 OFF(`.env.example:46`). **DB impl 내부 검사 + DB 설정 행(또는 함수 상수)으로 ON/OFF** 를 허용하되, ON 전환은 웹 `IDENTITY_GATE_ENABLED` 와 동시. 웹의 "DB 게이트 금지" 원칙은 '앱 재배포 없음' 전제였음 | `identityGate.ts:3-6`, `identityGateFlag.ts:12-13` |
| Q7 | `cro_update` 잠금(S-7) 방식 — DROP vs 컬럼 제한 RESTRICTIVE? | **DROP**(authenticated). 웹 세션 UPDATE 0건 실측, 전이는 전부 SECDEF RPC·service_role | `003:438-460`, `customOrderEscrowService.ts:92`, `policies.json` |
| Q8 | 지원 (post_id, mentor_id) 유니크 인덱스 추가? | **추가**. 지원 철회·재지원 기능이 없으므로 단순 유니크로 충분 | baseline `:967-968`, `customRequestMutations.ts:190-202` |
| Q9 | 수정요청 중 상태 표시·수락 허용 규칙(primary `status`=delivered 유지, `order_status` 만 revision_requested) | 앱은 **`order_status` 우선 판독**으로 "수정 요청 중" 표시하고 수락 CTA(웹 위임 안내)도 숨김. 웹 정합 수정(088 개정) 여부는 별도 | `088:378-381` vs `:272-281`, `orderLifecycleConstants.ts:36-54` |
| Q10 | 즉시지급(현 실측) vs 후불 배치(110 초안) 확정 | 실측 본문(즉시지급) 기준으로 앱 문구·정산 배너 작성. 후불 전환 시 `custom_order_settlement_items.status` 표시만 바뀌므로 모델은 양쪽 수용 | `20260804100002:157,187`, `110_*.sql` DRAFT |
| Q11 | 검토 3일 만료 후 정책(자동 수락/환불/운영 개입) | 앱은 **표시 전용** 유지(웹 동일). 자동 처리는 cron+service_role 신설 과제로 분리 | `OrderRoomView.tsx:68-75`, cron 0건 |
| Q12 | 선정된(활성 주문 있는) 글의 오픈 풀 잔류 | RPC 018 에 `not exists (활성 주문)` 필터 추가(S, 웹도 동일 이득) 또는 주문 생성 시 posts.status 갱신 트리거. 앱 단독 필터는 멘토 RLS 상 주문 조회 불가라 불가능 | `018:63-73`, `062:29-37`, §3.3-9 |
| Q13 | 진입점 — 하단 탭 추가 vs 마이페이지 push | **마이페이지 push + 알림 딥링크**로 시작. 탭 추가는 5곳 결합·게스트 탭 정책·역할별 네비 부재(`app_architecture.md` §4-4-2) 재설계와 함께 | `app_tabs.dart:10-19`, `home_shell.dart:47-62` |
| Q14 | 알림 설정 `'order'` 그룹 라벨('개별질문 알림')과 CR 알림 그룹 | 서버 `notification_event_group` 의 CR 타입 그룹 **(확인 필요)** 후 라벨을 '개별질문·맞춤의뢰 알림' 으로 | `notification_settings_repository.dart:32-38` |
| Q15 | 학생의 지원 첨부 "선정 후 미리보기" 를 DB 정책으로 강제? | 앱·웹 모두 코드 정책이면 우회 가능 → `craa_storage_read_authorized`/`craa_select_authorized` 에 활성 주문 조건 추가(S). 단 웹 SSR 배치 서명 경로 영향 확인 | `059:82-90,163-170`, `applicationAttachmentAccess.ts:79-95` |
| Q16 | CR 완료를 리뷰 자격에 포함? | 웹과 동일하게 **미포함 유지**(앱 완료 화면은 리뷰 진입 없음) | `lib/reviews/*` grep `custom` 0건(Phase 1) |

---

## 8. 리스크·지뢰

1. **결제 상태 위조 경로(`cro_update`)** — 잠금 전 앱 출시 금지. 라이브 정책 실재 확인됨(`policies.json`). 앱 매니페스트에 `custom_request_orders` UPDATE/DELETE 금지 테스트 추가.
2. **배지·목록 불일치** — S-6(서버 count 제외 해제)와 앱 게이트 해제가 다른 릴리스에 가면 미읽음 배지 ≠ 목록. 같은 창에서 처리(`20260803171053:243`).
3. **Realtime 무음 실패** — publication 미등재 시 콜백이 전혀 오지 않는다(`iq_realtime.dart:30-36` 규약). 재조회 폴백 필수, 플래그로 단계 도입.
4. **납품 파일 학생 노출 시점** — DB 가 완료 전 서명 URL 을 거부(`063:44-72`). 앱이 `storage_path` 를 완료 전 노출하면 "권한 오류" 로 보이므로 웹처럼 모델에서 제거(`orderDetailQueries.ts:148-167`).
5. **경로 CHECK 불일치** — 메시지 첨부 `storage_path` 정규식(`083:66-70`: `{uuid}/{uuid}/{digits}-{8~32 alnum}.{ext}`)·납품 3세그먼트(`orderDeliverableFiles.ts:170-197`, 웹 다운로드 검증이 요구) 를 앱 빌더가 정확히 맞춰야 한다. 어긋나면 insert 23514 또는 웹에서 다운로드 불가.
6. **버킷 상한** — 의뢰 첨부 웹 상수 50MB vs 버킷 20 MiB(`012:71-78`) → 앱은 20 MiB. MIME 7종(`gif` 없음 — IQ 정책과 다름).
7. **고아 Storage 객체** — 3 버킷 DELETE 정책 부재로 보상 삭제 실패(웹도 동일). S-9 없이는 고아 허용을 명시하고 로그만.
8. **`cra_insert` 역할 공백**·**posts.status 미갱신** — 이미 주문된 글에 지원이 계속 들어오고, 학생 계정도 지원 행을 넣을 수 있다(DB 레벨). W-9/Q12 로 정리하지 않으면 앱 오픈 풀 품질 저하.
9. **RPC 018 은 멘토 role 필수** — 학생 세션엔 0행. 학생용 "다른 사람 의뢰 보기" 는 존재하지 않는 기능(웹 랜딩도 비작성자 0행 `003:348-356`). 앱에서 학생 공개 목록을 만들지 말 것.
10. **수정요청 상태 이중성**(Q9) — primary 만 보면 "납품 대기"로 보여 학생이 수락 가능 단계로 오해. `order_status` 별도 판독 필수.
11. **분쟁 활성 잠금** — 웹은 시작/납품/수정/수락/취소를 앱 코드+DB(088 `ORDER_HAS_ACTIVE_DISPUTE`, 정산 트리거 `015/047`)로 잠근다. 앱은 메시지·분쟁 제기 외 액션을 `hasActiveDispute` 로 숨기고, 서버 코드 `ORDER_HAS_ACTIVE_DISPUTE` 도 매핑.
12. **`accept` RPC 봉투 형식** — `{ok:false,message}`(코드 없음, `20260804100002:28-101`). W-2 채택 시 wrapper 가 code 로 변환해야 앱 매퍼 규약(코드→한글)에 맞는다.
13. **FCM 트레이 노출** — CR 알림 서버 푸시는 앱 게이트와 무관(`docs/RELEASE_SCOPE_DECISIONS_2026-07.md` §4 한계). 게이트 해제 시 오히려 정합.
14. **`api_app_v1` ↔ `api_web_v1` 교차 사용 관행** — 앱이 `mentor_directory_v1` 등 웹 뷰를 읽는 것은 계약 §19 와 어긋나는 "사실상 관행"(DB 리포트 §6 #13). CR 도 같은 뷰를 쓰므로 새 앱 계약에서 `api_app_v1` 동명 뷰로 정식화할지 함께 결정.
15. **계약 거버넌스** — CR 은 v1.1 "유지" 영역(`api_web_v1_contract_v1_1.md:871`). 신규 객체는 계약 증보 없이는 `contracts:verify` 와 감사 문서가 어긋난다. 또한 `db-apply-pending` 의 remote_only 가드 때문에 MCP 즉석 적용은 전체 DB 경로를 잠근다(CLAUDE.md hotfix 규칙).
16. **iOS 계약 테스트** — 새 데이터 수집 표면(문서 파일 업로드)이 `PrivacyInfo`/`kExpectedCollectedDataTypes` 갱신을 요구할 수 있음(`ios_release_config_contract_test.dart:44-50`) **(확인 필요)**; 외부 브라우저 딥링크는 `LSApplicationQueriesSchemes={https}` 로 충족.
17. **테스트 수 고정** — 서명 워크플로가 테스트 개수 정확 일치(1,508)를 검사(`android-signed-release-candidate.yml:65`) → CR 테스트 추가 시 기대값 갱신.
18. **IndexedStack 상주 + 주문방 채널** — 주문방은 push 라우트라 dispose 로 정리되지만, 목록 화면이 `DataRefreshBus`·Realtime 을 동시에 쓰면 팬아웃 재발(N12/N13). 목록은 신호·resume 재조회만, 채널은 주문방 1개만.
