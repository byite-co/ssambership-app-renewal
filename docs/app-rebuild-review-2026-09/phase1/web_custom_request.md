# 웹 맞춤의뢰(Custom Request, CR) 도메인 리포트 — 앱 신설 설계용 (Phase 1)

- 대상 저장소: 웹 `/home/user/ssambership_web` (Next.js 16 + Supabase) · 앱 `/home/user/ssambership-app` (Flutter, CR 게이트 OFF)
- 작성 기준: 2026-09-03 저장소 스냅샷. 모든 사실은 파일:행 근거. 코드로 확인 못 한 것은 **(확인 필요)**.
- 범위: 프론트 구조 · 백엔드(RPC/RLS/Storage/Realtime/트리거) · DB. UI/디자인 언급 없음.
- 경로 표기: 웹 파일은 저장소 루트 상대경로. SQL은 `supabase/sql/…`, 마이그레이션은 `supabase/migrations/…`.

---

## §0. 한 줄 결론 (설계 에이전트용)

1. CR 백엔드(테이블 9종 + RPC 11종 + 버킷 4종 + 트리거)는 **DB에 이미 라이브**이며, 웹의 기능 게이트 `NEXT_PUBLIC_FEATURE_CUSTOM_REQUEST`는 **네비 노출·랜딩 배너만** 제어한다(라우트·server action은 게이트 없음) → `lib/shell/featureFlags.ts:5-10`, `lib/shell/mainNavItems.ts:121-135`, `app/(public)/custom-request/page.tsx:51-58`.
2. "학생이 멘토 선택 → 주문 생성 + 에스크로 hold"는 **한 DB 트랜잭션이 아니다.** TS 오케스트레이션 3단계(세션 클라이언트 insert → service_role RPC hold → service_role update `payment_status='escrowed'`) + 실패 시 보상 삭제 → `lib/customRequest/customOrderEscrowService.ts:132-172`. 따라서 "주문 행 생성"과 "hold"는 코드 상 분리 가능하지만, hold 없는 `unpaid` 주문은 웹 흐름에서 **"이미 주문 있음"으로 취급되어 갇힌다**(`customRequestQueries.ts:20,153-173` + `customRequestOrderActions.ts:49-52`).
3. 결제 실행 지점(앱 제외·웹 위임 대상)은 정확히 4곳: **hold**(`record_custom_order_escrow_hold`), **수락→정산+즉시지급**(`accept_custom_order_deliverable_atomic` 현 DB 실측 본문은 `record_custom_order_escrow_payout`을 **즉시 호출**), **학생 직접취소→전액환불**(`record_custom_order_escrow_refund`), **분쟁 분배/관리자 환불**(`record_custom_order_dispute_split`, `approve_refund_request_admin`). 모두 `service_role` 전용 EXECUTE.
4. 그 외(의뢰 작성/임시저장, 첨부 업로드·다운로드, 지원, 지원 비교, 멘토 작업 시작, 납품 등록, 수정 요청, 메시지+첨부, 분쟁 제기, 상태·이벤트·정산 조회)는 **authenticated RLS/RPC/Storage 정책만으로 앱에서 직접 가능**하다. 단 하나의 예외: **임시저장 삭제**가 service_role DELETE를 쓴다(posts에 DELETE 정책 없음).
5. 자동 수락은 **존재하지 않는다.** 검토 카운트다운(납품 시각 + 3일)은 화면 표시 전용이며 cron·SQL 어디에도 자동 수락/자동 지급 로직이 없다 → `components/customRequest/OrderRoomView.tsx:68-75`, `app/api/cron/*` 5종에 CR 없음.

---

## §1. CR 전체 수명주기 상태도 (텍스트)

### 1.1 상태 컬럼 규약 (정본: `lib/customRequest/orderLifecycleConstants.ts`)

- `custom_request_orders`는 다중 상태 열 `status` / `state` / `order_status` / `stage` + `payment_status`를 가진다(`003_p0_custom_request_draft.sql:196-237`). 웹은 **primary = `status`→`state`→`order_status`→`stage` 순 첫 비어 있지 않은 열**로 판정한다(`orderLifecycleConstants.ts:19-54`). DB RPC도 동일 규칙(`088_custom_order_status_transition_rpcs.sql:13-54`, `043:16-28 _order_primary_status_norm`).
- 주문 insert 리터럴: `status='pending'`, `state='pending'`, `order_status='open'`, `payment_status='unpaid'` (`customRequestMutations.ts:268-271`; 상수 `ORDER_INSERT_*` `orderLifecycleConstants.ts:23-27`).
- 종료(terminal) 집합: `completed, accepted, closed, finished, cancelled, canceled, refunded, rejected, done, resolved, dispute_resolved` + `completed_at/closed_at/finished_at` 非NULL (`orderLifecycleConstants.ts:141-184`).
- 학생 수락 허용(legacy 집합): `delivered, delivered_pending_review, waiting_review, pending_review, redelivered, delivery_submitted, in_review` (`:88-100`). RPC도 동일 집합(`20260804100002_as_applied_function_bodies.sql` accept 본문, `088:341-345`).
- 결제 확정 토큰(멘토 작업 가능): `paid, succeeded, escrowed, completed, complete, success, captured, paid_out` (`:362-392`; `orderPaymentPolicy.ts:27-36`; DB `088:83-97 _cro_transition_payment_confirmed`).
- 학생 수락 결제 게이트: `payment_status ∈ {paid, escrowed}` (`orderPaymentPolicy.ts:85-99`; RPC `p_require_payment`).
- `payment_status` 관측값: `unpaid → escrowed → paid` / `refunded` / `dispute_resolved` (`054/055/056/057` + `orderLifecycleConstants.ts:301-314` 라벨맵).
- 의뢰 글 `custom_request_posts.status` CHECK: `open, closed, cancelled, canceled, fulfilled, pending, draft, archived, in_review, in_progress` (`003:118-124`). **주문 생성·완료 시 글 status를 바꾸는 코드/트리거 없음**(lib 전체 `custom_request_posts.update` 0건 — grep 실측; DB 트리거 grep 0건). 글은 `open`으로 남는다 **(확인 필요: 운영 데이터에서 다른 값이 있는지)**.
- 지원 `custom_request_applications.status`: insert `'submitted'`/`state='submitted'`(`customRequestMutations.ts:223-224`), CHECK 없음(`003:176`). **선정 시 지원 status 갱신 코드 없음**(grep 0건).
- 분쟁 `disputes.status` CHECK: `open, under_review, resolved, dismissed, escalated`(`004:90`). 웹 관리자 액션은 `sanction_7d/30d/permanent`도 다룬다(`lib/admin/adminDisputeActions.ts:132-138` allowed-from 목록) **(확인 필요: CHECK 확장 마이그레이션 존재 여부 — 본 조사 범위 밖)**. 활성 분쟁 = `open | under_review | escalated` (`orderDisputeHelpers.ts:140`; DB `015`, `088:129-141`).

### 1.2 전이표

| # | 전이 | 행위자 | 트리거(server action → RPC/테이블) | 상태값 변화 | 결제 접촉 |
|---|---|---|---|---|---|
| P1 | 의뢰 글 작성(공개) | 학생 | `submitCustomRequestNew(formData)` `lib/customRequest/customRequestComposeActions.ts:40-188` → `insertCustomRequestPost` `customRequestMutations.ts:60-75` (세션 클라이언트, RLS `crp_insert`) | posts `status='open', state='open'` | 없음 |
| P1' | 임시저장 / 임시저장 이어쓰기 | 학생 | 동일 액션 `intent='draft'` → `insertCustomRequestPost(status:'draft')` 또는 `updateCustomRequestDraftPost` `:77-94` | posts `status='draft'` | 없음 |
| P1'' | 임시저장 삭제 | 학생 | `deleteCustomRequestDraftAction` `customRequestComposeActions.ts:190-224` → **`createServiceRoleClient()` DELETE** `.eq("status","draft")` `customRequestMutations.ts:96-116` | 행 삭제 | 없음 (**service_role**) |
| P2 | 의뢰 첨부 업로드 | 학생(작성자) | P1 액션 내부: Storage `custom-request-post-attachments` upload + `custom_request_post_attachments` insert `customRequestComposeActions.ts:146-180` | — | 없음 |
| A1 | 멘토 지원 | 멘토(승인+본인인증) | `submitMentorCustomRequestApplication` `customRequestApplicationActions.ts:44-179` → `insertMentorApplication` `customRequestMutations.ts:181-236` (RLS `cra_insert`) + 첨부(`custom-request-application-attachments`) | applications `status='submitted', state='submitted'` | 없음 |
| A1n | 지원 알림 | DB 트리거 | `trg_cra_notify_new_application` `159_p1_11…sql:21-45` → `record_domain_notification` (`new_application`) | — | 없음 |
| S1 | 학생 선택 → 주문 생성 + hold | 학생(작성자+본인인증) | `selectMentorApplicationForOrder` `customRequestOrderActions.ts:32-113` → `createCustomRequestOrderWithEscrowHold` `customOrderEscrowService.ts:132-172`: ① `insertCustomRequestOrder`(세션, RLS `cro_insert`) `customRequestMutations.ts:250-280` ② `record_custom_order_escrow_hold(p_student_id, p_order_id, p_amount_cents)` **service_role** `:45-85` ③ `update payment_status='escrowed'` **service_role** `:87-107`; ②실패 시 ① 행 삭제 `:110-126` | orders `status/state='pending'`, `order_status='open'`, `payment_status: 'unpaid'→'escrowed'`, `agreed_price` 스냅샷 | **결제 실행(캐시 차감·cash_ledger `cr_hold_{order_id}`)** |
| S1x | 중복 방지 | DB | 부분 유니크 `ux_cro_active_application_once` `062:29-37`; 코드 `ORDER_DUPLICATE` 매핑 `customOrderEscrowService.ts:37-39,137-144` | — | — |
| M1 | 멘토 작업 시작 | 멘토(배정) | `startCustomOrderWorkAction` `orderMentorActions.ts:52-123` → RPC `custom_order_mentor_start(p_order_id uuid)` `088:165-232` (authenticated) | primary 열 `'pending'→'open'`, `started_at` | 상태 읽기(결제 확정 필수 `088:199-201`) |
| M1e | 이벤트 | 멘토 | `recordOrderEventBestEffort(…,"order_started")` `orderRoomMutations.ts:270-286` | order_events 행 | 없음 |
| M2 | 납품 등록(버전) | 멘토 | `submitMentorOrderDeliverableAction` `orderMentorActions.ts:137-336`: Storage `custom-order-deliverables` upload(`{orderId}/{version}/{ts}-{8hex}.{ext}`) + `custom_order_deliverables` insert(`version = max+1` 재시도 최대 5회 `:241-311`, RLS `cdel_insert`) → RPC `custom_order_mentor_deliver(p_order_id)` `088:235-285` | deliverables `status='submitted'`, orders `order_status='delivered'` + primary 열 `'delivered'` | 상태 읽기(결제 확정 필수 `:197-199`) |
| R1 | 수정 요청 | 학생 | `submitCustomOrderRevisionRequestAction` `orderRevisionActions.ts:37-128` → RPC `custom_order_student_request_revision(p_order_id, p_note)` `088:287-400` (revisions insert + `order_status='revision_requested' where order_status='delivered'`) | revisions 행(`status='open'`), orders **`order_status`만** `'revision_requested'` | 없음 |
| R1x | 횟수 상한 | 웹+DB | 최대 2회: `orderRevisionActions.ts:24,100-109`; `088:352-354 REVISION_LIMIT_EXCEEDED` | — | — |
| M2' | 재납품 | 멘토 | M2 동일(허용 norm: `open` / `delivered` / `revision_requested` `orderMentorActions.ts:211-217`) | version+1, `order_status='delivered'` | 상태 읽기 |
| C1 | 검토 카운트다운 | — | 표시 전용: 최신 납품 `submitted_at/created_at` + 3일 `OrderRoomView.tsx:68-75,404-409`, `DeliveryReviewCountdown.tsx:31-47` | **상태 변화 없음(자동 수락 없음)** | 없음 |
| S2 | 납품 수락 → 완료 + 정산 + 지급 | 학생 | `acceptCustomOrderDeliverableAction` `orderStudentActions.ts:66-192` → `acceptCustomOrderDeliverableAtomic` **service_role** `orderSettlementService.ts:80-118` → RPC `accept_custom_order_deliverable_atomic(p_order_id, p_student_id, p_require_payment)`; 현 DB 실측 본문(`20260804100002_as_applied_function_bodies.sql:4-204`)은 `custom_order_settlement_items` insert(`fee_rate 0.05`, `status 'pending'`) → orders `status/state/order_status='completed'`, `accepted_at`, `completed_at` → **`perform record_custom_order_escrow_payout(p_order_id)` 즉시 호출** → settlement `paid`, `payment_status='paid'`(`055:118-146`) | orders `'completed'`, `payment_status 'escrowed'→'paid'` | **결제 실행(멘토 지급, cash_ledger `cr_payout_{order_id}`)** |
| S2e | 이벤트 | 학생 | `deliverable_accepted`, `settlement_item_created` `orderStudentActions.ts:159-185` | order_events | 없음 |
| S2p | 완료 화면·리뷰 | 학생 | `/custom-request/orders/[orderId]/complete` `app/(student)/…/complete/page.tsx:141-192` — 리뷰 자격은 `checkReviewEligibility`(구독/개별질문 기준, **CR 이력은 자격에 미포함** — `lib/reviews/*` grep `custom` 0건) | — | 상태 읽기 |
| X1 | 학생 직접 취소(작업 시작 전) | 학생 | `cancelCustomOrderByStudentAction` `orderStudentActions.ts:198-269` (norm `pending` + `payment_status='escrowed'`만 `:240-252`) → `recordCustomOrderEscrowRefundRpc` **service_role** → RPC `record_custom_order_escrow_refund(p_order_id)` `056:12-172` | orders `status/state/order_status='cancelled'`, `payment_status='refunded'`, settlement `cancelled` | **결제 실행(전액 환불, `cr_refund_{order_id}`)** |
| D1 | 분쟁 제기 | 학생 또는 배정 멘토 | `submitCustomOrderDisputeAction` `orderDisputeActions.ts:88-193` → `disputes` insert(세션, RLS `dispute_ins` `008:5-27`) `{custom_request_order_id, student_id, mentor_id, submitted_by, body, status:'open'}` `:53-79` | disputes `open` | 없음 |
| D1g | 분쟁 제기 조건 | — | 종료 주문 불가 `:144-147`; 멘토는 납품 이후(또는 학생 검토 단계)만 `:149-163`; 활성 분쟁 1건 유니크 `009:30-32 disputes_order_active_unique` | — | — |
| D1b | 활성 분쟁 잠금 | 웹+DB | 시작/납품/수정/수락/취소 차단 `getActiveDisputeBlockMessage` `orderDisputeHelpers.ts:217-230`; DB `088:195-197,328-330`, accept RPC 분쟁 카운트, 정산 insert 트리거 `015/047 trg_cosi_prevent_active_dispute` | — | — |
| D2 | 운영 검토/해결/기각/메모 | 관리자 | `setDisputeUnderReviewAction`(:80) / `resolveDisputeAction`(:114) / `dismissDisputeAction`(:159) / `saveDisputeAdminNoteAction`(:207) `lib/admin/adminDisputeActions.ts` — service_role UPDATE `disputes` (`resolved_at/resolved_by/admin_note` `034:11-17`) | disputes `under_review → resolved | dismissed` | 없음 |
| D3 | 분쟁 예치 분배 | 관리자 | `applyCustomOrderDisputeSplitAdminAction` `adminDisputeActions.ts:258-340` → `recordCustomOrderDisputeSplitRpc` **service_role** `customOrderDisputeSplitService.ts:88-130` → RPC `record_custom_order_dispute_split(p_order_id, p_mentor_gross_won, p_student_refund_won, p_admin_id)` `191:45-339` (요율은 정산 행 `fee_rate` 사용, 없으면 `SETTLEMENT_FEE_RATE_MISSING`) | orders `payment_status/status/state/order_status='dispute_resolved'`, settlement `cancelled`, disputes `resolved` | **결제 실행(멘토 지급 + 학생 환불, `cr_dispute_payout_/cr_dispute_refund_{order_id}`)** |
| D4 | 관리자 환불 승인(CR 분기) | 관리자 | `approve_refund_request_admin(p_refund_id, p_admin_id, p_admin_note)` `128:20-161` → 내부 `record_custom_order_escrow_refund` 위임 | X1과 동일 | **결제 실행** |
| N1 | 주문 메시지 | 학생·멘토 | `submitCustomOrderRoomMessageAction` `orderMessageActions.ts:45-240` → `custom_order_messages` insert(RLS `cmsg_ins`) + 선택 첨부(`custom-order-message-attachments` + `custom_order_message_attachments`) | — | 없음 |
| N1n | 메시지 알림 | DB 트리거 | `trg_com_notify_new_order_message` `159:48-82` (`new_order_message`) | — | 없음 |

### 1.3 텍스트 상태도

```
[posts.draft] --(submit)--> [posts.open] --(멘토 지원 N건: applications.submitted)-->
   |
   +--(학생 1건 선택: S1)--> [orders: primary 'pending' / payment 'unpaid']
                                  |-- hold RPC 성공 --> payment 'escrowed'      (S1 ②③ — 결제 실행)
                                  |-- hold 실패 --> 행 삭제(보상)                 (S1 실패)
   [pending/escrowed] --(학생 취소 X1)--> [cancelled / refunded]                 (결제 실행: 환불)
   [pending/escrowed] --(멘토 작업 시작 M1: custom_order_mentor_start)--> [primary 'open']
   [open] --(납품 M2: deliverables v1 + custom_order_mentor_deliver)--> [primary 'delivered', order_status 'delivered']
   [delivered] --(수정 요청 R1 ≤2회: custom_order_student_request_revision)--> [order_status 'revision_requested' (primary 열은 'delivered' 유지 — §1.4 참조)]
   [revision_requested|delivered] --(재납품 M2': v+1)--> [delivered]
   [delivered 계열] --(학생 수락 S2: accept_custom_order_deliverable_atomic)--> [completed / payment 'paid'] (정산 행 생성 + 즉시 지급)
   [completed] --> 완료 화면(S2p)  (리뷰 자격은 CR 무관)
   임의 비종료 단계 --(분쟁 D1)--> disputes.open  ==> 진행 액션 전부 잠금(D1b)
        --(관리자 D2)--> under_review / resolved / dismissed
        --(관리자 D3 분배)--> orders 'dispute_resolved' + disputes 'resolved'  (결제 실행)
```

### 1.4 관측된 상태 정합 이슈 (설계 시 주의)

- **수정 요청 후 primary 열 불일치**: `custom_order_student_request_revision`은 `order_status`만 `'revision_requested'`로 바꾸고(`088:378-381`) `status/state`는 건드리지 않는다. 반면 `custom_order_mentor_deliver`는 `order_status`와 primary 열 모두 `'delivered'`로 세팅(`088:275-281`). 웹의 primary는 `status` 우선이므로 수정 요청 후에도 `normalizedPrimaryOrderStatus === 'delivered'`가 유지되어, 라벨맵의 `revision_requested`(`orderLifecycleConstants.ts:230`)·탭 분류 `revision`(`mentorOrderBrowseTabClassify.ts:631-633`)은 **primary가 `order_status`인 행에서만** 도달 가능하다. 학생 수락 허용 판정(`isOrderStatusAllowingStudentAccept('delivered')`)도 수정 요청 중 계속 참이다 **(확인 필요: 의도된 정책인지)**. 앱은 `order_status` 열을 별도로 읽어 "수정 요청 중"을 표시하는 편이 안전하다.
- **즉시 지급 vs 후불 초안**: `110_custom_request_remove_immediate_payout.sql:1-21`은 "즉시지급 제거·23일 배치 후불" **DRAFT(실행 금지)** 표기이고 baseline apply_order에 등재(`supabase/baseline/apply_order.txt:46`)되었으나, 그 뒤의 as-applied 실측 본문(`20260804100002_as_applied_function_bodies.sql:4-204`, "저장소 파일과 불일치하는 실측 정본")은 `perform public.record_custom_order_escrow_payout(p_order_id)`를 2회(정상·23505 수리 경로) 포함한다. 2026-08-04 이후 이 함수를 재정의한 마이그레이션은 없다(grep 0건). → **현 운영 DB = 수락 시 즉시 지급** 으로 판단하나 **(확인 필요: `select prosrc from pg_proc where proname='accept_custom_order_deliverable_atomic'` 실측)**. 한편 `20260827100300_mentor_settlement_rpc_v2_due_payouts_parity.sql:45-60`의 due_payouts CR 브랜치는 `custom_order_settlement_items` × `orders.accepted_at`을 후보로 잡되 `raw_status='paid'`면 `paid`로 분류하므로 두 모델이 공존해도 이중 지급은 없다(멱등키 `cr_payout_{order_id}` `055:23`).
- **cro_update RLS가 넓다**: `003:437-460 cro_update`는 학생·멘토 당사자에게 주문 행 **모든 컬럼 UPDATE**를 허용한다(`payment_status` 포함). `088` 헤더(:3-7)는 "RLS lockdown 전 단계(M-1 step 1)"라고 명시하며, 이후 마이그레이션에서 `cro_update`를 좁힌 흔적이 없다(`supabase/migrations` grep `cro_update` — baseline 1건만). 웹은 이 정책을 쓰지 않고 RPC를 쓰지만, **앱이 세션 클라이언트로 `custom_request_orders`를 직접 UPDATE하면 hold 없이 `payment_status='escrowed'`를 만들 수 있다** → 앱 설계에서는 주문 행 직접 UPDATE를 금지하고 RPC만 쓸 것 **(확인 필요: 운영 DB의 실제 정책 본문)**.

---

## §2. 라우트별 기능 표

공통 형식: 라우트 | 목적 | 역할 | 사용자 액션(읽기/쓰기) | 서버 표면 | 결제 접촉 | 플래그·게이트 | 앱 이식 메모

### 2.1 공개(public) 라우트 — `app/(public)/custom-request/**`

| 라우트 | 목적 | 역할 | 액션 | 서버 표면 | 결제 접촉 | 플래그·게이트 | 앱 이식 메모 |
|---|---|---|---|---|---|---|---|
| `/custom-request` (`page.tsx:18-115`) | CR 랜딩 + 최근 공개 의뢰 3건 | 비로그인/학생/멘토 | 읽기 | `loadRecentCustomRequestPosts` `customRequestQueries.ts:66-83` → `custom_request_posts` 직접 SELECT(RLS `crp_select` = 작성자·admin만 → 비작성자는 0행) | 없음 | `isCustomRequestFeatureEnabled()` OFF면 "오픈 예정" 배너만 표시(`:51-58`), 접근 자체는 허용 | 앱 홈 카드는 RPC `list_open_custom_request_posts_for_mentor_browse`(anon/authenticated 허용)로 대체 |
| `/custom-request/[postId]` (`[postId]/page.tsx:27-145`) | 의뢰 공개 상세 + 지원 폼 진입 + 첨부 | 로그인 사용자 | 읽기(+멘토 지원 쓰기 폼) | `loadCustomPostForPublicDetail` `customRequestQueries.ts:287-303` (직접 SELECT → 0행이면 RPC `get_public_custom_request_post_for_browse(p_post_id)` `006`) · `loadApplicationsForPost` `:324-340` (RLS `cra_select`) · `loadPostAttachments` `:200-226` (RLS `crpa_select_authorized`) · 첨부 다운로드 server action `downloadCustomRequestPostAttachmentAction` `postAttachmentDownloadActions.ts:120-176` (signed URL 600s) | 없음 | draft면 작성자만 `/custom-request/new?draftId=`로 redirect, 그 외 404(`:80-85`) | RPC 반환 23열은 작성자 uuid·연락처 미포함(`006:12-34`). 첨부 signed URL은 앱이 Storage RLS(`012:149-156`)로 직접 생성 가능 |
| `/custom-request/orders` (`orders/page.tsx:16-86`) | 학생 내 주문 목록 | 학생 | 읽기 | `fetchStudentCustomRequestOrdersFromPrimaryTable` `studentCustomRequestOrdersQueries.ts:150-178` (`custom_request_orders.student_id`) · `fetchActiveOpenDisputeOrderIdSet` `orderDisputeHelpers.ts:169-195` · 멘토 표시 `loadMentorProfilesForDirectory`/`getMentorUserPublic` | 상태 읽기(`payment_status` 라벨) | `requireRole("student")` | 전부 RLS SELECT — 앱 직접 가능 |
| `/custom-request/orders/[orderId]` (`orders/[orderId]/page.tsx:28-120`) | **주문방(학생·멘토 공용)** — 진행 단계·납품·메시지·수정요청·분쟁·정산 배너·액션 | 학생/멘토/admin | 읽기 + 쓰기(하위 §2.4 액션 전부) | `loadOrderBundle` `customRequestQueries.ts:346-399`(orders/deliverables/disputes) · `loadOrderDetailPageData` `orderDetailQueries.ts:268-362`(post/application/mentor profile/order_events/messages/revisions/settlement item/message attachments signed) · 학생 뷰는 미완료 시 storage_path 제거 `hideStudentPreCompletionDeliverableStoragePaths` `:148-167` · 멘토 뷰 학생 표시명 RPC `get_mentor_student_nicknames` `mentorDashboardOrderEnrichment.ts:426-452` | 상태 읽기 + (액션 통해) 결제 실행 | 로그인 필수, `canAccessOrder` `orderAccess.ts:108-128`; 멘토 시작 버튼은 `orderSchemaGate` 마커(`orderSchemaGate.ts:12-23`; 파일 `002_custom_request_orders_status.sql` 존재 → 웹에서는 통과) | 읽기 전부 RLS. 액션은 §4 분리표대로 |
| `/custom-request/orders/[orderId]/review` (`review/page.tsx:10-13`) | 레거시 → 주문방 redirect | — | — | — | — | — | 앱 딥링크 호환용 |

### 2.2 학생 라우트 — `app/(student)/custom-request/**`

| 라우트 | 목적 | 역할 | 액션 | 서버 표면 | 결제 접촉 | 플래그·게이트 | 앱 이식 메모 |
|---|---|---|---|---|---|---|---|
| `/custom-request/new` (`new/page.tsx:48-85`) | 의뢰 작성/임시저장 이어쓰기 | 학생 | 쓰기 | `submitCustomRequestNew` `customRequestComposeActions.ts:40-188`: 필수(카테고리·제목·본문·마감 `:65-70`), 예산 1,000~200,000 `:83`, 연락처 마스킹 `:89-92`, 첨부 최대 40개·각 50MB `:94-121` → `insertCustomRequestPost`/`updateCustomRequestDraftPost` + Storage `custom-request-post-attachments` upload + `custom_request_post_attachments` insert | 없음 | `requireRole("student")` + `profile.role==='student'` `:49-52` | 세션 insert/update(RLS `crp_insert/crp_update`) + Storage insert 정책 `crpa_storage_insert_author`(`012:158-167`) → 앱 직접 가능. **웹 상수 50MB vs 버킷 `file_size_limit 20971520`(20 MiB, `012:71-78`) 불일치 → 앱은 20 MiB 기준 권장 (확인 필요: 운영 버킷 값)** |
| `/custom-request/posts` (`posts/page.tsx:12-53`) | 내 의뢰 목록(임시저장 포함) + 임시저장 삭제 | 학생 | 읽기 + 삭제 | `loadStudentCustomRequestPosts` `customRequestQueries.ts:86-102` (`author_id`) · `deleteCustomRequestDraftAction` `customRequestComposeActions.ts:190-224` (**service_role DELETE**) | 없음 | 멘토는 `/mentor/custom-request/posts`로 redirect(`:15`) | 읽기 RLS 가능. **삭제는 posts에 DELETE 정책이 없어 앱 직접 불가 → §6 wrapper 필요** |
| `/custom-request/[postId]/applications` (`applications/page.tsx:30-117`) | 지원 0건 대기 화면 / 1건 이상 비교·선정 | 학생(작성자) | 읽기 + 선정(쓰기) | `loadApplicationsForPost`, `enrichApplicationRows` `customRequestQueries.ts:828-849`(프로필 배치 + `api_web_v1.mentor_directory_v1` 닉네임 `:802-822`) · `loadApplicationAttachments` `:232-267` · 썸네일 `batchSignApplicationAttachmentImageThumbUrls` `applicationAttachmentAccess.ts:248-268`(**선정 후에만** 학생 미리보기 `:83-100`) · 선정 폼 → `selectMentorApplicationForOrder` | **결제 실행(hold)** — 선정 버튼 | `requireRole("student")`; 비작성자는 안내만(`:90-93`); `requireVerifiedIdentity`(`IDENTITY_GATE_ENABLED=true`일 때 `users.identity_verified_at` 검사, `lib/identity/identityGate.ts:30-42` service_role 읽기) | 비교 화면 읽기는 RLS 가능(`cra_select`=글 작성자, `craa_select_authorized`=작성자). 지원 첨부 Storage 읽기 정책(`059:162-170`)은 선정 전에도 작성자 허용 — "선정 후 미리보기" 제한은 **웹 코드 정책**(`applicationAttachmentAccess.ts:83-100`)이라 앱이 재구현해야 함. 닉네임은 `api_web_v1.mentor_directory_v1` 뷰 → 앱용 뷰 필요 (확인 필요: `api_app_v1`에 동등 뷰 존재 여부) |
| `/custom-request/[postId]/applications/waiting` (`waiting/page.tsx:8-13`) | 레거시 → applications redirect | — | — | — | — | — | 알림 딥링크 대상 URL(`159:36`) |
| `/custom-request/orders/[orderId]/complete` (`complete/page.tsx:141-192`) | 완료 요약(납품·결제·리뷰 진입) | 학생 | 읽기 | `loadOrderBundle`/`loadOrderDetailPageData` · `checkReviewEligibility` `lib/reviews/checkReviewEligibility` · 납품 다운로드 `downloadCustomOrderDeliverableAction` | 상태 읽기(`paid_at` 등) | `requireRole("student")`, `canAccessOrder` | RLS 읽기 가능. 리뷰 자격은 CR 무관 |

### 2.3 멘토 라우트 — `app/(mentor)/mentor/custom-request/**` (레이아웃 `requireRole("mentor")` + 페이지별 중복 호출)

| 라우트 | 목적 | 역할 | 액션 | 서버 표면 | 결제 접촉 | 플래그·게이트 | 앱 이식 메모 |
|---|---|---|---|---|---|---|---|
| `/mentor/custom-request` (`page.tsx:3-5`) | → dashboard redirect | 멘토 | — | — | — | — | — |
| `/mentor/custom-request/dashboard` (`dashboard/page.tsx:26-122`) | KPI(오픈 풀·지원·주문·납품 대기·완료·월 수익·정산 예정/완료) + 진행 주문 | 멘토 | 읽기 | `fetchMentorWorkspaceCounts` `mentorCounts.ts:23-95`(지원 200·주문 200·오픈 200·분쟁) · `fetchMentorCustomRequestOrdersFromPrimaryTable` `lib/home/mentorDashboardQueries.ts:91-106`(`mentor_id`) · `loadMentorPayoutsBundle` · `enrichMentorDashboardOrderRows` `mentorDashboardOrderEnrichment.ts:474-569`(applications/posts in() + RPC `get_mentor_student_nicknames`) | 상태 읽기(정산 예정/완료 캐시) | `requireRole("mentor")` | 읽기 전부 RLS/RPC(authenticated) 가능. 오픈 풀은 RPC `list_open_custom_request_posts_for_mentor_browse(p_limit)` |
| `/mentor/custom-request/posts` (`posts/page.tsx:164-309`) | 모집 중 의뢰 목록(카테고리 탭) / 제안한 의뢰 탭 | 멘토 | 읽기 | RPC `list_open_custom_request_posts_for_mentor_browse(50)` `customRequestQueries.ts:584-594` · `loadMentorRecentApplicationsWithPostHints` `:737-755`(주문 전환분 제외 `:663-670`) · `loadMentorAppliedPostIdSet` `:710-730` | 없음 | — | 카테고리 분류는 문자열 휴리스틱(`mentorOpenPostCategory.ts:588-602`) — 앱 재현 필요 |
| `/mentor/custom-request/posts/[postId]` (`posts/[postId]/page.tsx:336-392`) | 멘토용 의뢰 상세(+이미 지원 여부·내 지원 첨부) | 멘토 | 읽기 | `loadCustomPostForPublicDetail`(RPC fallback) · `mentorHasApplicationForPost` `:601-618` · `loadPostAttachments` · `loadApplicationAttachments` | 없음 | draft 404(`:352-354`) | RLS/RPC 가능 |
| `/mentor/custom-request/posts/[postId]/apply` (`apply/page.tsx:416-489`) | 지원서 작성 | 멘토(승인) | 쓰기 | `submitMentorCustomRequestApplication` `customRequestApplicationActions.ts:44-179`: `requireVerifiedIdentity` `:47-50`, `assertMentorApprovedForAction` `lib/mentor/mentorVerificationGate.ts:17-37`, 필수(가격·납기·제안 `:70-72`), 마스킹 `:76-89`, 첨부 최대 40개·20MB `:91-118`, 중복 지원 `ALREADY_APPLIED` | 없음 | `isMentorApplicablePostStatus`(`customRequestPostMappers.ts:452-465`: open/published 또는 status 공백) | 세션 insert(RLS `cra_insert` = `mentor_id=auth.uid()`) + Storage `craa_storage_insert_mentor`(`059:172-183`) → 앱 직접 가능. 승인 상태 체크는 `mentor_profiles.verification_status` 웹 코드 판정 → 앱 재구현 필요(DB 강제 없음) |
| `/mentor/custom-request/orders` (`orders/page.tsx:20-93`) | 수락된 의뢰 목록(탭: all/dispute/billing/work/delivery/revision/done) | 멘토 | 읽기 | `fetchMentorCustomRequestOrdersFromPrimaryTable(80)` · `enrichMentorDashboardOrderRows` · `fetchActiveOpenDisputeOrderIdSet` · 탭 분류 `classifyMentorOrderBrowseTab` `mentorOrderBrowseTabClassify.ts:619-646` | 상태 읽기(`billing` 탭 = 결제 미확정) | — | RLS 가능 |
| `/mentor/custom-request/orders/[orderId]` · `/files` · `/revision` · `/room` · `/waiting-review` | 전부 공용 주문방으로 redirect (`orders/[orderId]/page.tsx:101-104`, `files/page.tsx:121-124`, `revision/page.tsx:137-140`, `room/page.tsx:146-149`, `waiting-review/page.tsx:162-165`) | — | — | — | — | — | 딥링크 호환만 |

### 2.4 주문방 액션(주문방 URL 하나에 묶인 server action — 컴포넌트→액션 배선 실측)

| 컴포넌트 | server action | 행위자 | 서버 표면 | 결제 접촉 |
|---|---|---|---|---|
| `components/customRequest/order/OrderActionBar.tsx:3-7,121-146` | `startCustomOrderWorkAction`(멘토) · `acceptCustomOrderDeliverableAction`(학생) · `cancelCustomOrderByStudentAction`(학생) | 멘토/학생 | RPC `custom_order_mentor_start`(auth) · `accept_custom_order_deliverable_atomic`(**service_role**) · `record_custom_order_escrow_refund`(**service_role**) | 시작: 읽기 / 수락: **실행** / 취소: **실행** |
| `order/OrderDeliverablesPanel.tsx:2,4` | `submitMentorOrderDeliverableAction`(멘토) · `downloadCustomOrderDeliverableAction`(당사자) | 멘토/학생 | deliverables insert + Storage + RPC `custom_order_mentor_deliver` / signed URL 600s(`orderDeliverableDownloadActions.ts:372,382-457`; 학생은 `studentCanDownloadDeliverable` 완료 후만 `:413-415`) | 없음 |
| `order/OrderRevisionsPanel.tsx:1` | `submitCustomOrderRevisionRequestAction`(학생) | 학생 | RPC `custom_order_student_request_revision` | 없음 |
| `order/OrderProgressSection.tsx:2` | `submitCustomOrderRoomMessageAction`(학생·멘토) | 당사자 | `custom_order_messages` insert + 첨부 | 없음 |
| `order/OrderDisputesPanel.tsx:1` | `submitCustomOrderDisputeAction`(학생·멘토) | 당사자 | `disputes` insert | 없음 |
| `SelectMentorApplicationForm.tsx:5` | `selectMentorApplicationForOrder`(학생) | 학생 | orders insert + hold RPC(**service_role**) | **실행** |
| `MentorApplicationForm.tsx:6` / `CustomRequestNewForm.tsx:6` / `CustomRequestStudentPostsList.tsx:6` | `submitMentorCustomRequestApplication` / `submitCustomRequestNew` / `deleteCustomRequestDraftAction`(**service_role**) | 멘토/학생 | applications·posts | 없음 |
| `ApplicationAttachmentFileListClient.tsx:5`, `CustomRequestApplicationFileChip.tsx:4` | `getApplicationAttachmentPreviewUrlAction(args)` `applicationAttachmentDownloadActions.ts:279-290` | 당사자 | signed URL 600s(`applicationAttachmentAccess.ts:32,186-210`) | 없음 |
| `customRequestDetailLayout.tsx:3` | `downloadCustomRequestPostAttachmentAction` | 작성자/멘토/admin | signed URL 600s | 없음 |

`"use client"` 컴포넌트 23개 목록은 grep 실측(`components/customRequest/*` 20 + `components/disputes/*` 3). **Realtime 구독 없음**(`.channel(`/`postgres_changes` grep 0건).

### 2.5 분쟁 라우트 — 학생/멘토 지원 화면

| 라우트 | 목적 | 역할 | 액션 | 서버 표면 | 결제 접촉 | 게이트 | 앱 이식 메모 |
|---|---|---|---|---|---|---|---|
| `/support/disputes` (`app/(student)/support/disputes/page.tsx:8-36`) | 내 분쟁 목록 | 학생 | 읽기 | `loadDisputesListForUser(…, "student")` `lib/disputes/disputeListQueries.ts:554-579` (`disputes.student_id`) | 없음 | `requireRole("student")` | RLS `dispute_select`(`004:195-199`) 직접 가능 |
| `/support/disputes/[id]` (`[id]/page.tsx:46-75`) | 분쟁 상세(연계 환불·결제·주문·처리 이력) | 학생 | 읽기 | `loadDisputeById` `disputeQueries.ts:127-208`(disputes → refunds 공유키 역참조 `disputeRefundLink.ts:591-607` → payments(`order_payments` 경유 `:37-55`) → `custom_request_orders` → `admin_action_logs`(관리자 RLS라 당사자 0건)) · `canPartyViewDispute` `:286-299` | 상태 읽기 | — | RLS 가능(`refunds` `refund_select` user_id 본인) |
| `/mentor/support/disputes`, `/mentor/support/disputes/[id]` (`app/(mentor)/mentor/support/disputes/*`) | 멘토 동일 | 멘토 | 읽기 | 동일(`mentor_id`) | 상태 읽기 | `requireRole("mentor")` | 동일 |
| (참고) `/admin/disputes`, `/admin/disputes/[id]` | 운영 처리·분배 | admin | 쓰기 | §1.2 D2/D3 | **실행** | `requireRole("admin")` | 앱 대상 아님 |

---

## §3. 서버 표면 전수

### 3.1 RPC — EXECUTE 권한 실측(계약서 §3.3 인용 + SQL GRANT)

| RPC(시그니처) | 정의 파일 | 호출 위치(웹) | EXECUTE | 앱 직접 호출 |
|---|---|---|---|---|
| `custom_order_mentor_start(p_order_id uuid) → jsonb` | `088:165-232` | `orderTransitionRpc.ts:77-86` | `authenticated, service_role` (`088:418`; 계약 `docs/contracts/api_web_v1_contract_v1_1.md:207` `u`,`s`) | **가능**(SECDEF + `auth.uid()` 당사자 검증) |
| `custom_order_mentor_deliver(p_order_id uuid) → jsonb` | `088:235-285` | `orderTransitionRpc.ts:88-97` | 동일(`088:419`; 계약 :208) | 가능 |
| `custom_order_student_request_revision(p_order_id uuid, p_note text) → jsonb` | `088:287-400` | `orderTransitionRpc.ts:99-112` | 동일(`088:420`; 계약 :209) | 가능 |
| `get_public_custom_request_post_for_browse(p_post_id uuid) → TABLE(23열)` | `006:11-86` | `customRequestQueries.ts:295` | `anon, authenticated, service_role` (`20260804100000_post_ledger_acl_convergence.sql:55-57`; 계약 :224) | 가능(비로그인도) |
| `list_open_custom_request_posts_for_mentor_browse(p_limit int default 50) → TABLE(23열)` | `018:6-81` | `customRequestQueries.ts:588` | `anon, authenticated, service_role` (`…acl_convergence.sql:64-66`; 계약 :225) | 가능 |
| `get_mentor_student_nicknames(p_student_ids uuid[]) → TABLE(id, nickname, full_name)` | `058:10-39` | `mentorDashboardOrderEnrichment.ts:435,522` | `authenticated` (`058:39`) — 멘토의 주문 연결 학생만 반환 | 가능 |
| `record_custom_order_escrow_hold(p_student_id uuid, p_order_id uuid, p_amount_cents bigint) → void` | `054:10-75` | `customOrderEscrowService.ts:63-67` (service_role) | **service_role만**(`054:71-75`; 계약 :169) | 불가 |
| `record_custom_order_escrow_payout(p_order_id uuid) → void` | `055:12-158` | accept RPC 내부에서만 | service_role만(`055:154-158`) | 불가 |
| `record_custom_order_escrow_refund(p_order_id uuid) → void` | `056:12-172` | `customOrderEscrowService.ts:193-195` | service_role만(`056:168-172`; 계약 :170) | 불가 |
| `accept_custom_order_deliverable_atomic(p_order_id uuid, p_student_id uuid, p_require_payment boolean default true) → jsonb` | `043:53`, `055:163`, `090:21`, `110:22`(초안), 실측 `20260804100002:4-204` | `orderSettlementService.ts:86-91` | service_role만(`043:246-247`, `055:369-370`; 계약 :171) | 불가 |
| `record_custom_order_dispute_split(p_order_id uuid, p_mentor_gross_won integer, p_student_refund_won integer, p_admin_id uuid) → jsonb` | `057:13`, `125:16`, `191:45` | `customOrderDisputeSplitService.ts:101-107` | service_role만(`191:335-339`; 계약 :172) | 불가(관리자 전용) |
| `approve_refund_request_admin(p_refund_id uuid, p_admin_id uuid, p_admin_note text) → jsonb` | `056:177`, `128:20` | 관리자 환불 액션 | service_role만(`128:160-161`) | 불가 |
| 내부 헬퍼 `_cro_transition_*` 9종, `_order_primary_status_norm`, `_pick_custom_order_gross_won` | `088:13-163`, `043:8-51` | RPC 내부 | service_role만(`…acl_convergence.sql:5-31`) — SECDEF RPC 안에서는 호출 가능 | 직접 불가(불필요) |

RPC 오류 규약: 전이 RPC 3종은 `raise exception '<CODE>' errcode P0001`(`AUTH_REQUIRED, ORDER_NOT_FOUND, ORDER_MENTOR_FORBIDDEN, ORDER_STUDENT_FORBIDDEN, ORDER_HAS_ACTIVE_DISPUTE, ORDER_PAYMENT_NOT_CONFIRMED, ORDER_TERMINAL, ORDER_STATUS_COLUMN_MISSING, ORDER_ALREADY_STARTED, ORDER_STATUS_NOT_STARTABLE, ORDER_DELIVERABLE_REQUIRED, REVISION_NOTE_REQUIRED, REVISION_NOTE_TOO_LONG, ORDER_STATUS_NOT_REVISIONABLE, REVISION_LIMIT_EXCEEDED, ORDER_STATUS_NOT_DELIVERED` — `088` 각 `raise` 행) + 성공 시 `{ok:true, transition, from, to[, revision_id]}`. accept RPC는 **envelope**(`{ok:false,message}`) 방식(실측 본문). 에스크로 RPC는 raise(`CASH_INSUFFICIENT`(코드 매핑 `customOrderEscrowService.ts:71`), `ALREADY_PAID_OUT`, `PAYMENT_NOT_ESCROWED`, `ESCROW_HOLD_MISSING`, `ESCROW_HOLD_AMOUNT_MISMATCH`, `SETTLEMENT_NOT_FOUND`, `SETTLEMENT_NOT_PAYABLE`, `DISPUTE_SPLIT_MISMATCH`, `SETTLEMENT_FEE_RATE_MISSING`, `ADMIN_REQUIRED` — `055/056/191` raise 행).

### 3.2 직접 테이블 접근과 RLS (정본 `003` + 보강)

| 테이블 | 웹 직접 접근(세션) | RLS 정책(정책명: 요지) | 비고 |
|---|---|---|---|
| `custom_request_posts` | SELECT/INSERT/UPDATE(세션), DELETE(service_role) | `crp_select`(`003:348-356`): 작성자 동의어 5열 or admin — **멘토·타인 불가** → 멘토 조회는 RPC 006/018 / `crp_insert`(`:359-367`) / `crp_update`(`:370-388`) / **DELETE 정책 없음** | 2026-08-02 build13에서 "누구나 의뢰 읽기" 정책 DROP(`20260802054930…:839`) |
| `custom_request_applications` | SELECT/INSERT | `cra_select`(`003:391-397`): `mentor_id=uid` or 글 author/user or admin / `cra_insert`(`:400-401`): `mentor_id=uid` / `cra_update`(`:404-410`): 멘토 본인 | (post_id, mentor_id) DB 유니크 **없음** — 중복 방지는 웹 사전조회(`customRequestMutations.ts:190-202`) **(확인 필요)** |
| `custom_request_orders` | SELECT/INSERT(세션), UPDATE/DELETE(service_role) | `cro_select`(`003:413-423`): 학생 동의어 6열 or `mentor_id` or admin / `cro_insert`(`:426-435`): 학생 동의어 or admin / `cro_update`(`:438-460`): **학생·멘토 당사자 전 컬럼** / DELETE 정책 없음 | §1.4 경고 |
| `custom_order_deliverables` | SELECT/INSERT | `cdel_select`(`003:484-497`): 당사자 or admin / `cdel_insert`(`:500-504`): `o.mentor_id=uid` / UPDATE·DELETE 없음 | 유니크 `(custom_request_order_id, version)` `011:7-9` |
| `custom_order_revisions` | SELECT(INSERT는 RPC 내부) | `crev_all_party`(`003:507-520`) / `crev_ins`(`007:8-24`): `author_id=uid` and 학생 당사자 | RPC가 정본 경로 |
| `custom_order_messages` | SELECT/INSERT | `cmsg_all_party`(`003:528-541`) / `cmsg_ins`(`:544-556`): `author_id=uid` and 당사자 | 열: `author_id, body`만(role 열 없음 `orderRoomMutations.ts:262-264`) |
| `custom_order_message_attachments` | SELECT/INSERT | `coma_select_party`/`coma_insert_party`/`coma_delete_uploader_or_admin` (`083:147-168`; `grant select,insert,delete to authenticated`) | CHECK: 경로 정규식·MIME·≤20MB (`083:53-70`) |
| `order_events` | SELECT/INSERT | `oev_select`(`003:560-575`): 당사자 or admin / `oev_insert`(`007:30-47`): 당사자 | 열 `event, kind, metadata`; actor는 `metadata.actor_id`(`orderRoomMutations.ts:277-281`) |
| `custom_request_post_attachments` | SELECT/INSERT | `crpa_select_authorized`(`012:29-49`): admin or **모든 멘토(role='mentor')** or 작성자 / `crpa_insert_author`(`:51-62`) | |
| `custom_request_application_attachments` | SELECT/INSERT | `craa_select_authorized`(`059:82-90`): admin or 지원 멘토 본인 or 글 작성자 / `craa_insert_mentor`(`:72-79`) | |
| `custom_order_settlement_items` | SELECT | `cosi_select_parties`(`013:47-55`): admin/mentor_id/student_id / INSERT 정책 제거(`014:8`) / `cosi_update_admin`(`013:66-70`) | 트리거 `trg_cosi_prevent_active_dispute`(`015:35-38`, `047`), CHECK `cosi_chk_amounts_core`(`014:19-26`), 유니크 주문당 1행(`013:29-30`), `fee_rate default 0.05`(`090:17-18`) |
| `disputes` | SELECT/INSERT | `dispute_select`(`004:195-199`): student/mentor/admin / `dispute_ins`(`008:5-27`): `uid ∈ (student_id, mentor_id)` and 주문 당사자 일치 / `dispute_update_admin`(`004:204-207`) | 활성 1건 유니크 `009:30-32`; 열 추가 `submitted_by`(`009:17-19`), `admin_note/resolved_at/resolved_by`(`034:11-17`) |
| `order_payments` | SELECT(분쟁 상세) | `opay_select`(`003:463-476`) / `opay_insert` admin만(`:479-481`) | CR 흐름에서 **쓰기 없음**(레거시 PG 링크) |
| `refunds` | SELECT(분쟁 상세) | `refund_select`/`refund_ins`(`004:210-215`) | CR 학생 환불 요청 화면은 별도 도메인 |
| `cash_ledger`/`cash_wallets` | RPC 내부만 | append-only, 클라이언트 쓰기 없음(`004:4-6`) | 멱등키 `cr_hold_/cr_payout_/cr_refund_/cr_dispute_payout_/cr_dispute_refund_{order_id}` |

### 3.3 order_events 이벤트 종류(웹이 기록하는 정본)

`OrderRoomEventKind` = `order_started, order_cancelled, deliverable_submitted, deliverable_accepted, message_created, revision_requested, dispute_opened, dispute_split_applied, settlement_item_created, payment_confirmed` (`orderRoomMutations.ts:250-260`). 기록은 best-effort(실패해도 사용자 흐름 유지 `:266-286`). payload: `{custom_request_order_id, order_id, custom_order_id, request_order_id, event, metadata:{event, actor_id, …extra}}`. 라벨맵 `orderLifecycleConstants.ts:394-415`. 앱은 동일 kind 문자열로 insert(RLS `oev_insert` 당사자) 가능.

### 3.4 Storage 버킷 — 4종 (과제는 3종이라 했으나 메시지 첨부 버킷이 추가로 존재)

| 버킷 | 정의 | 경로 규약 | 크기/MIME | INSERT 정책 | SELECT 정책 | 웹 다운로드 방식 |
|---|---|---|---|---|---|---|
| `custom-request-post-attachments` | `012:71-95` (private, 20 MiB) | `{postId}/{ts}-{8hex}.{ext}` (`postAttachmentFiles.ts:49-62`, 검증 `:27-47`) | 웹 상수 50MB·40개(`postAttachmentConstants.ts:3-6`) vs 버킷 20 MiB **(불일치)**; MIME pdf/png/jpeg/webp/zip/docx/pptx | `crpa_storage_insert_author`(`012:158-167`): 글 작성자 | `crpa_storage_read_authorized`(`:149-156`): admin/작성자/**모든 멘토** | server action → `createSignedUrl(path, 600)` redirect (`postAttachmentDownloadActions.ts:109,165-175`) |
| `custom-request-application-attachments` | `059:96-118` (private, 20 MiB) | `{applicationId}/{ts}-{8hex}.{ext}` (`applicationAttachmentFiles.ts:336-349`) | 20MB·40개(`applicationAttachmentConstants.ts:3-6`) | `craa_storage_insert_mentor`(`059:173-183`) | `craa_storage_read_authorized`(`:163-170`): admin/지원 멘토/글 작성자 | server action(URL 반환) `getApplicationAttachmentPreviewUrlAction` + SSR 배치 서명; 학생은 **선정 후만**(웹 코드 `applicationAttachmentAccess.ts:83-100`) |
| `custom-order-deliverables` | `010:34-45` (private, 20 MiB) | `{orderId}/{version}/{ts}-{8hex}.{ext}` (`orderDeliverableFiles.ts:199-214`, 검증 `:170-197`) | 20MB(`:12`), MIME 7종(`:14-24`), magic bytes(`:105-162`) | `custom_order_deliverable_storage_insert_mentor`(`010:119-127`): 주문 멘토 | `custom_order_deliverable_storage_read_party` **063 재정의**(`063:105-112` → `user_can_read_cro_deliverable_storage_path`): admin/멘토/학생은 **주문 완료(completed/accepted/finished 또는 completed_at/accepted_at) 후만**(`063:44-72`) | server action → signed URL 600s(`orderDeliverableDownloadActions.ts:372,448-456`); 학생 미완료 시 storage_path 자체를 응답에서 제거(`orderDetailQueries.ts:132-167`) |
| `custom-order-message-attachments` | `083:15-41` (private, 20 MiB) | `{orderId}/{uploaderId}/{ts}-{12hex}.{ext}` (`orderMessageAttachments.ts:522-536`) | 20MB(`:403`), MIME 7종 | `custom_order_message_attachments_storage_insert_party`(`083:187-196`): 경로 order_id·uploader_id 일치 + 당사자 | `…_storage_select_party`(`:174-184`): 등록 행 기준 당사자 | SSR에서 행마다 `createSignedStorageUrl(…, 600)` (`orderMessageAttachments.ts:668-700`) |

파일명 정책: `original_filename`은 표시 전용(한글 유지, 제어문자 제거, 연락처 마스킹, 255자) — storage key에는 절대 사용 안 함(`orderDeliverableFiles.ts:71-91`). 업로드 실패/메타 insert 실패 시 객체 삭제(best-effort, `ORPHAN_STORAGE_OBJECT` 로그).

### 3.5 금지어·연락처 마스킹·스키마 게이트

- **금지어(bannedPhrases)**: 정책 폐지. `CUSTOM_REQUEST_BANNED_PHRASES = []`, `findBannedPhrase → null` (`lib/customRequest/bannedPhrases.ts:1-12`); `findRestrictedPhraseInText → null`, `sanitizeTrustSafetyText → {ok:true, text:masked}` (`lib/safety/trustSafetyText.ts:15-28`). 즉 CLAUDE.md의 "맞춤의뢰 금지어 7종"은 **코드상 비활성**이며 호출부의 차단 분기(`customRequestComposeActions.ts:72-76` 등)는 도달 불가. 계약서도 "실효 검증은 연락처 마스킹만"(`api_web_v1_contract_v1_1.md:421`).
- **연락처 마스킹(contactMasking.ts:23-61)**: 이메일, 난독화 이메일 `(at)/[dot]`, 메신저 도메인(`open.kakao.com, kakaotalk.com, t.me, telegram.me, instagram.com, instagr.am, linktr.ee`), 한국어 메신저 키워드+아이디(카카오톡/카톡/오픈채팅/텔레그램/인스타그램/인스타/디엠 + 4자 이상), 전화(국내·+82·`_`구분자), 한글 전화(공일공/영일영) → `[연락처 비공개]`. 적용 지점: 의뢰 제목/목표/본문/납품형식(`customRequestComposeActions.ts:89-92`), 지원 제안/추가답변(`customRequestApplicationActions.ts:76-88`), 납품 메모(`orderMentorActions.ts:151-161`), 수정요청(`orderRevisionActions.ts:113-117`), 메시지(`orderMessageActions.ts:177-184`), 분쟁 사유(마스킹만 `orderDisputeActions.ts:179-182`), 표시 파일명(`orderDeliverableFiles.ts:81-89`). **DB 측 마스킹 없음(웹 코드 전용)** — 커뮤니티는 `api_web_v1` RPC로 이식됐으나(`20260730105252_api_web_v1_community_rpc.sql:20,200`) CR은 미이식 → 앱은 동일 정규식을 재구현하거나 SQL 이식 필요.
- **orderSchemaGate 런타임 프로빙**: `fs.existsSync(supabase/sql/002_custom_request_orders_status.sql)`(`orderSchemaGate.ts:12-19`) — 파일은 `select 1;` 마커(`002:1-6`). 존재하므로 웹에서 멘토 작업 시작 허용. 앱과 무관(DB RPC가 실제 게이트). 그 외 테이블/컬럼 프로빙은 W4(C10)에서 제거되어 정본 테이블 고정(`customRequestQueries.ts:35-53` 등 주석).
- **결제 우회 env**: `CUSTOM_ORDER_ALLOW_UNPAID_ACCEPT==="true"`면 미결제 수락 허용, production에서 true면 throw (`orderPaymentPolicy.ts:11-25`).
- **본인인증 게이트**: `IDENTITY_GATE_ENABLED==="true"`일 때만 `requireVerifiedIdentity` 활성(`lib/identity/identityGateFlag.ts:12-13`); 적용 지점 = 멘토 지원(`customRequestApplicationActions.ts:47`)·학생 선정(`customRequestOrderActions.ts:35`). 판정은 service_role로 `users.identity_verified_at` 읽기(`identityGate.ts:37-42`) **(확인 필요: 앱이 자기 행 `identity_verified_at`을 RLS로 읽을 수 있는지 — `users_select_own` 존재는 `058:3` 주석으로만 확인)**.
- **알림**: 159 트리거 2종(`new_application`, `new_order_message`)이 도메인 INSERT와 원자적으로 발행(`159:21-45,48-82`), 웹 best-effort 알림 제거. 딥링크 `/custom-request/{post_id}/applications/waiting`(`159:36`).
- **Realtime**: CR 웹 코드에 구독 없음. `admin:*` 토픽 RLS(CLAUDE.md DB-3)는 CR과 무관.

---

## §4. 결제 접촉점 분리 판정

### 4.1 "결제 실행" — 앱에서 제외 / 웹 위임 필수

| 지점 | 근거 | 왜 분리 불가/위험 |
|---|---|---|
| **S1 학생 선정 → 주문 생성 + hold** | `customOrderEscrowService.ts:132-172` (insert 세션 → `record_custom_order_escrow_hold` service_role → escrowed update service_role) | hold RPC는 service_role 전용. 주문 insert만 앱이 세션으로 할 수는 있으나(`cro_insert`), 그러면 `payment_status='unpaid'` 주문이 남고 웹 선정 흐름은 이를 "이미 주문 있음"으로 보고 주문방으로 redirect(`customRequestOrderActions.ts:49-52`; 활성 판정은 cancelled/canceled/refunded/rejected만 제외 `customRequestQueries.ts:20,169`) → **결제 못 한 주문에 갇힘**. 웹에는 "기존 unpaid 주문에 사후 hold" 경로가 없다(hold는 생성 직후 한 번만). 따라서 앱은 **선정 자체를 웹으로 위임**해야 한다(딥링크 `/custom-request/{postId}/applications`). |
| **S2 납품 수락** | `acceptCustomOrderDeliverableAtomic` service_role(`orderSettlementService.ts:86-91`); 실측 RPC 본문은 정산 행 생성 + **즉시 지급**(§1.4) | 수락 = 지급 트리거(캐시 이동). 상태만 바꾸는 분리 경로 없음(정산 생성과 완료 전이가 한 트랜잭션). 웹 위임 대상(주문방 URL). |
| **X1 학생 직접 취소** | `record_custom_order_escrow_refund` service_role(`customOrderEscrowService.ts:185-225`) | 전액 환불 = 캐시 이동. 웹 위임. |
| **D3/D4 분쟁 분배·관리자 환불** | `record_custom_order_dispute_split`, `approve_refund_request_admin` service_role | 관리자 콘솔 전용. 앱 무관. |

### 4.2 "결제 접촉 없음/상태 읽기" — 앱에서 직접 가능(authenticated 세션)

| 기능 | 서버 표면 | 앱 직접 가능 근거 | 재구현해야 할 웹 코드 정책 |
|---|---|---|---|
| 의뢰 작성/임시저장/이어쓰기 | `custom_request_posts` insert/update | RLS `crp_insert/crp_update` 작성자 | 필수값·예산 1,000~200,000·마감 필수·마스킹·동의 2종(`customRequestComposeActions.ts:65-92`); payload 컬럼 세트(`customRequestMutations.ts:35-58`: `subject, body, category, subcategory=goal, goal, title=subject, due_at/deadline/due_date, deliverable_type/deliverable_format/result_format, budget_min/max, status/state, author_id`) |
| 의뢰 첨부 | Storage insert + `custom_request_post_attachments` insert | `crpa_storage_insert_author`, `crpa_insert_author` | 경로 `{postId}/{ts}-{8hex}.{ext}`, MIME 7종, magic bytes, 20 MiB(버킷) |
| 의뢰 목록/상세/오픈 풀 조회 | RLS SELECT + RPC 006/018 | anon/authenticated | draft 숨김(`isDraftCustomRequestPost`), 모집 가능 판정(`isMentorApplicablePostStatus`) |
| 멘토 지원 + 첨부 | `custom_request_applications` insert + Storage | `cra_insert`, `craa_storage_insert_mentor`, `craa_insert_mentor` | 멘토 승인(`verification_status`) 판정, 본인인증 게이트, 중복 지원 사전조회, 마스킹, payload(`customRequestMutations.ts:205-225`: `post_id, mentor_id, proposed_price/price/bid_amount, delivery_at/proposed_due/due_proposed, scope/offer_scope/services_offered, cover_letter/message/self_intro, extra_answers/answers/notes, status/state='submitted'`) |
| 지원 비교(학생) | `cra_select`, `craa_select_authorized`, 프로필 RPC `mentor_profiles_for_directory_v2`(a/u/s) | 가능 | 닉네임 소스 `api_web_v1.mentor_directory_v1`는 웹 스키마 → 앱용 뷰 (확인 필요); "지원 첨부는 선정 후 미리보기" 웹 정책 |
| 멘토 작업 시작 | RPC `custom_order_mentor_start` | authenticated | 없음(DB가 결제 확정·분쟁·상태 검증) |
| 납품 등록 | deliverables insert + Storage + RPC `custom_order_mentor_deliver` | `cdel_insert`, storage insert 멘토, RPC authenticated | version 채번(max+1 재시도, 유니크 23505 처리), 경로 규약, payload(`orderDeliverableFiles.ts:271-296`: `custom_request_order_id + 미러 3열, version, status='submitted', note, file_url=null, storage_path, original_filename, mime_type, file_size`), 허용 norm(open/delivered/revision_requested), 결제 확정 확인(`isCustomOrderPaymentConfirmed`) |
| 수정 요청 | RPC `custom_order_student_request_revision` | authenticated | 없음(DB가 2회·상태·분쟁 검증) |
| 메시지 + 첨부 | `custom_order_messages` insert, `custom_order_message_attachments` insert + Storage | `cmsg_ins`, `coma_insert_party`, storage insert 당사자 | 종료 주문 차단(웹 정책 `orderMessageActions.ts:126-128` — DB 강제 없음), 마스킹, 경로 `{orderId}/{uploaderId}/{ts}-{12hex}.{ext}` |
| 분쟁 제기 | `disputes` insert | `dispute_ins` | 종료 주문 불가, 멘토는 납품 이후만, 8,000자, 마스킹만(`orderDisputeActions.ts:107-182`) |
| 상태·이벤트·정산·분쟁 조회 | `cro_select, cdel_select, crev_all_party, cmsg_all_party, oev_select, cosi_select_parties, dispute_select` | 가능 | primary 상태 규약(§1.1) + `order_status` 별도 판독(§1.4) |
| 납품/첨부 다운로드 | Storage signed URL | 세션으로 `createSignedUrl` 가능 — Storage RLS(063)가 학생의 완료 전 읽기를 DB 레벨에서 차단 | 웹의 "미완료 시 storage_path 숨김"은 표시 정책 |
| order_events 기록 | `order_events` insert | `oev_insert` 당사자 | kind 문자열·metadata 규약(§3.3) |

### 4.3 "학생이 멘토를 선택 → 주문 생성 + hold" 트랜잭션 판정 (요청 항목)

- **한 트랜잭션 아님.** 코드 실측: `insertCustomRequestOrder`(세션, `customRequestMutations.ts:278`) → `recordCustomOrderEscrowHoldRpc`(service_role, `customOrderEscrowService.ts:156`) → `setOrderPaymentStatusEscrowed`(service_role, `:162`). hold RPC 내부(원장 insert + 지갑 차감)만 단일 트랜잭션(`054:38-70`).
- 실패 처리: hold 실패 → `deleteUnpaidOrderBestEffort`(service_role DELETE `payment_status='unpaid'` 조건, `:110-126`); escrowed 갱신 실패 → `ORDER_STATUS` 코드 반환하고 주문은 hold 완료·`unpaid` 상태로 남음(CRITICAL 로그 `:163-168`) **(운영 수리 절차 확인 필요)**.
- 분리 가능성: DB 스키마상 주문 행과 hold는 독립(FK 없음; 연결은 `cash_ledger.ref_id/idempotency_key='cr_hold_'||order_id` `054:9,38-46`). 그러나 웹 흐름·멘토 시작 RPC(`ORDER_PAYMENT_NOT_CONFIRMED`)·유니크 인덱스(`062`: unpaid도 "활성"으로 계산)가 모두 "주문=hold 완료"를 전제한다. **앱이 hold 없이 주문만 만드는 설계는 금지**해야 한다.
- 대안: (a) 선정을 웹 위임(권장, 결제 제외 원칙 부합) (b) 오너가 앱 내 선정을 원하면 DB에 원자 wrapper 신설(§6 초안 W-1) — 이 경우 "결제 실행"이 앱에 들어오므로 오너 결정 사항.

---

## §5. CR 게이트(featureFlags) 현재 값과 의미

- 정의: `isCustomRequestFeatureEnabled()` — `NEXT_PUBLIC_FEATURE_CUSTOM_REQUEST ∈ {on,1,true,yes}`일 때만 true, **기본 OFF** (`lib/shell/featureFlags.ts:1-10`). 저장소 내 `.env*`·문서에 값 설정 없음(grep: `mainNavItems.ts:122` 주석, `docs/architecture/purpose-report/01-shell-landing-common.md:381`만).
- 효과(실측 3곳): ① admin 외 전 역할 메인 네비에서 CR 항목 제거(`mainNavItems.ts:121-125`), 랜딩 게스트 네비도 제거(`:128-136`) ② `/custom-request` 랜딩에 "곧 오픈 예정" 배너(`page.tsx:51-58`) — 랜딩 자체·하위 라우트·server action은 **게이트 검사 없음**. 즉 URL 직접 접근·딥링크·알림 링크로 CR 전 기능이 동작한다("이미 진행 중인 주문은 그대로 이용" 문구 `:55`).
- DB: CR 테이블·RPC·트리거·버킷 전부 baseline/마이그레이션에 포함되어 라이브(`20260701000000_pre_ledger_baseline.sql` 1135행 이하 정책, `20260804100000` ACL, `20260903100200` 분쟁 분배 요율). 운영 데이터는 "분쟁 0건·정산 행 0건"(`191:20`, 2026-09-03 기준) **(확인 필요: 주문·글 건수)**.
- 앱 측 게이트: Flutter 앱은 CR 화면 없음. 알림 목록 쿼리에서 `new_order_message`, `new_application` 2종을 제외(`ssambership-app/lib/features/notifications/data/notification_types.dart:15-18 kGatedNotificationTypeCodes`, `notifications_repository.dart:125`), 분류 enum은 유지(`:73,86-90`). 앱 RPC 사용 7종에 CR 없음(grep 실측). `commerce_policy.dart:10-39`는 결제 유도·구독·정산·충전 안내 상수만(CR 플래그 없음).
- **앱 신설 시 전제 조건**: (1) 오너의 CR 정식 오픈 결정(웹 `NEXT_PUBLIC_FEATURE_CUSTOM_REQUEST=on` + 앱 알림 게이트 해제 동시) — 백엔드는 이미 열려 있으므로 앱 노출 = 사실상 출시. (2) `IDENTITY_GATE_ENABLED` 값 확정(선정·지원 게이트). (3) §1.4의 `cro_update` 잠금 및 수정요청 primary 불일치 정리 여부. (4) 즉시지급 vs 후불(110) 확정 — 앱 UI 문구("수락하면 정산돼요" `OrderActionBar.tsx:140`)에 영향.

---

## §6. 앱이 그대로 못 쓰는 것(service_role 전용) 목록과 대체안 후보

| # | 웹 경로 | service_role 사용 지점 | 결제 실행? | 대체안 | wrapper 시그니처 초안(`api_app_v1`, 기존 패턴 `20260730112525_api_app_v1_surface.sql:120-140` — SECDEF, `search_path=''`, `auth.uid()` 자체 도출, `{ok, contract_version:1, code}` envelope) |
|---|---|---|---|---|---|
| W-0 | 임시저장 삭제 `deleteCustomRequestDraftAction` | `createServiceRoleClient()` DELETE (`customRequestComposeActions.ts:206-215`; posts DELETE 정책 없음) | 아니오 | **wrapper 신설(권장)** 또는 RLS `crp_delete_draft_own`(`status='draft' and author_id=auth.uid()`) 추가 | `api_app_v1.custom_request_post_delete_draft(p_post_id uuid) → jsonb` — 내부: `delete from public.custom_request_posts where id=p_post_id and author_id=auth.uid() and status='draft'`; 코드 `AUTH_REQUIRED / POST_NOT_FOUND / NOT_DRAFT` |
| W-1 | 학생 선정 → 주문 + hold | `record_custom_order_escrow_hold` + escrowed update + 보상 삭제 (`customOrderEscrowService.ts:45-172`) | **예** | 기본: **웹 위임**(앱은 `/custom-request/{postId}/applications` 딥링크). 오너가 앱 내 선정 허용 시에만 원자 wrapper | `api_app_v1.custom_order_select_application_with_hold(p_post_id uuid, p_application_id uuid) → jsonb` — 내부 단일 트랜잭션: 작성자 검증(`posts.author_id=auth.uid()`) → 지원 검증(post 일치, `proposed_price>0`) → 기존 활성 주문 검사 → `insert custom_request_orders(status/state 'pending', order_status 'open', payment_status 'unpaid', agreed_price)` → `perform public.record_custom_order_escrow_hold(auth.uid(), v_order_id, price*100)` → `update payment_status='escrowed'`; 코드 `ORDER_DUPLICATE / CASH_INSUFFICIENT / NOT_POST_AUTHOR / APPLICATION_MISMATCH / IDENTITY_REQUIRED`; 예외 시 전체 롤백(웹의 보상 삭제 불필요) |
| W-2 | 납품 수락 `acceptCustomOrderDeliverableAtomic` | service_role RPC (`orderSettlementService.ts:86-91`) | **예**(즉시 지급) | 기본: **웹 위임**(주문방 URL). 허용 시 얇은 wrapper | `api_app_v1.custom_order_student_accept(p_order_id uuid) → jsonb` — `return public.accept_custom_order_deliverable_atomic(p_order_id, auth.uid(), true) || {contract_version:1}`; 추가로 `order_events` `deliverable_accepted`·`settlement_item_created` insert를 wrapper 내부에서 수행(웹은 TS에서 별도 insert `orderStudentActions.ts:159-185`) |
| W-3 | 학생 직접 취소 `recordCustomOrderEscrowRefundRpc` | service_role RPC | **예** | **웹 위임** | (허용 시) `api_app_v1.custom_order_student_cancel(p_order_id uuid) → jsonb` — 게이트: `student_id=auth.uid()`, primary `'pending'`, `payment_status='escrowed'`, 활성 분쟁 없음 → `perform public.record_custom_order_escrow_refund(p_order_id)` + `order_events 'order_cancelled'` |
| W-4 | 본인인증 판정 `requireVerifiedIdentity` | service_role `users.identity_verified_at` 읽기 (`identityGate.ts:37-42`) | 아니오 | 앱은 자기 행 RLS 읽기(`users_select_own` (확인 필요)) 또는 W-1 내부 판정 | (선택) `api_app_v1.identity_status_self() → jsonb {verified:boolean}` |
| W-5 | 지원자 닉네임 배치 `api_web_v1.mentor_directory_v1` | 웹 스키마 뷰(`customRequestQueries.ts:809-812`) | 아니오 | `api_app_v1`에 동등 뷰(존재 여부 확인 필요) 또는 `mentor_user_public_v2(p_mentor_id)` RPC(a/u/s, 계약 :138) N회 호출 | `api_app_v1.mentor_directory_v1` (security_invoker 뷰) |
| W-6 | 관리자 분쟁 처리/분배/환불 | service_role | 예(분배·환불) | 앱 대상 아님 | — |
| W-7 | 연락처 마스킹·금지어 | 웹 TS 전용(`contactMasking.ts`) | 아니오 | 앱 Dart 재구현(정규식 6종 동일) 또는 커뮤니티처럼 SQL 이식(`20260730105252…:200`) 후 wrapper 내부 적용 | (선택) `api_app_v1.custom_order_message_create(p_order_id uuid, p_body text, p_attachment jsonb default null) → jsonb` — 마스킹 SQL + 종료 주문 차단 + `order_events` 기록을 DB로 이전 |
| W-8 | 납품 등록 오케스트레이션(버전 채번 재시도 + 업로드 + RPC) | 세션 클라이언트(service_role 아님)이나 TS 다단계 | 아니오 | 앱 직접 가능. 원자성 개선 원하면 wrapper | (선택) `api_app_v1.custom_order_deliverable_register(p_order_id uuid, p_note text, p_storage_path text, p_original_filename text, p_mime_type text, p_file_size bigint) → jsonb` — `version = coalesce(max)+1` 원자 채번 + `custom_order_mentor_deliver` 호출(주석 D-CR-1 `orderMentorActions.ts:237-240`가 DB 함수 채번을 권고) |
| W-9 | orderSchemaGate(fs 마커) | Node fs | 아니오 | 앱 불필요(DB RPC가 게이트) | — |

주의: 계약서는 CR 영역을 "S2에서 신규 객체를 만들지 않는 영역(유지)"으로 못 박았다(`api_web_v1_contract_v1_1.md:871, 2086, 2093, 2132`) — 위 wrapper는 **앱 계약(api_app_v1) 신규 항목**으로 오너·계약 갱신이 선행되어야 한다.

---

## §7. 앱 이식 시 필요한 데이터 모델 (테이블·컬럼·enum)

### 7.1 테이블·주요 컬럼 (정본 DDL 근거)

| 테이블 | 앱이 읽/쓰는 컬럼 | 근거 |
|---|---|---|
| `custom_request_posts` | `id, author_id(NOT NULL), title, subject, body, content, description, goal, subcategory, category, due_at, deadline, due_date, deliverable_type, deliverable_format, result_format, output_format, budget_min numeric, budget_max numeric, state, status, created_at, updated_at` (+ 동의어 `student_id,user_id,requester_id,client_id`; 레거시 `file_urls text[]` `039:8-11`) | `003:94-127` |
| `custom_request_post_attachments` | `id, custom_request_post_id, uploaded_by, storage_path, original_filename, mime_type, file_size_bytes, created_at` | `012:8-18` |
| `custom_request_applications` | `id, post_id(NOT NULL), mentor_id(NOT NULL), proposed_price/price/bid_amount numeric, delivery_at/proposed_due/due_proposed timestamptz, scope/offer_scope/services_offered, cover_letter/message/self_intro/content, extra_answers/answers/notes, school/university/university_name/major/department/field, status(default 'submitted'), state, created_at, updated_at` (+ `estimated_days int, portfolio_urls text[]` `039:13-15`) | `003:142-178` |
| `custom_request_application_attachments` | `id, application_id, uploaded_by, storage_path, original_filename, mime_type, file_size_bytes, created_at` | `059:9-18` |
| `custom_request_orders` | `id, post_id, application_id, custom_request_application_id, selected_application_id, student_id, mentor_id, status, state, order_status, stage, payment_status, agreed_price/proposed_price/price/amount numeric, started_at, work_started_at, in_progress_at, mentor_started_at, completed_at, accepted_at, closed_at, finished_at, created_at, updated_at` (+ 동의어 FK 다수) | `003:196-237` |
| `custom_order_deliverables` | `id, custom_request_order_id(NOT NULL), order_id/custom_order_id/request_order_id(미러), file_url, note, version int(default 1), status, created_at, updated_at, storage_path, original_filename, mime_type, file_size, file_size_bytes, file_name` | `003:274-288`, `010:8-26`, `039:17-19` |
| `custom_order_revisions` | `id, custom_request_order_id, 미러 3열, author_id, request_note, status, created_at` | `003:290-302` |
| `custom_order_messages` | `id, custom_request_order_id, 미러 3열, author_id, body(NOT NULL), created_at` | `003:304-315` |
| `custom_order_message_attachments` | `id, order_id, message_id, uploader_id, storage_path(UNIQUE, 정규식 CHECK), original_filename, mime_type(CHECK 7종), file_size_bytes(1..20971520), created_at` | `083:43-70` |
| `order_events` | `id, custom_request_order_id, 미러 3열, event, kind, metadata jsonb, created_at` | `003:317-329` |
| `custom_order_settlement_items` | `id, custom_request_order_id(UNIQUE), mentor_id, student_id, gross_amount int, platform_fee_amount int, mentor_amount int, fee_rate numeric(default 0.05), status, reason, paid_at, created_at, updated_at` | `013:10-24`, `090:17-18` |
| `disputes` | `id, student_id, mentor_id, custom_request_order_id, payment_id, subscription_id, status, body, created_at, updated_at, submitted_by, admin_note, resolved_at, resolved_by` | `004:83-94`, `009:17-19`, `034:11-17` |
| `order_payments` | `custom_request_order_id, payment_id` (읽기 전용·CR 흐름 미사용) | `003:260-269` |
| `cash_ledger` | `user_id, delta_cents, reason, ref_type('custom_request_orders'), ref_id(order id), idempotency_key` — 학생 원장 화면용 읽기 | `054:38-46`, `lib/cash/ledgerRowDisplay.ts:118` |
| `notifications` | type `new_application`, `new_order_message` | `159` |

### 7.2 enum/토큰 사전

- `posts.status`: `open | closed | cancelled | canceled | fulfilled | pending | draft | archived | in_review | in_progress` (CHECK, `003:118-124`). 웹 표시 토큰 추가: `published, submitted, selected, complete, completed` (`mentorCustomRequestDisplay.ts:349-362`).
- `applications.status`: `submitted`(insert). 표시 사전: `submitted, pending, selected, accepted, rejected, withdrawn, open, in_review, review` (`:389-406`) — DB 강제 없음.
- `orders` primary/`order_status`: `pending → open → delivered → (revision_requested) → completed`; 종료 `cancelled | dispute_resolved`; legacy 수락 허용 7종(§1.1).
- `orders.payment_status`: `unpaid → escrowed → paid | refunded | dispute_resolved` (+ 라벨 사전 `pending, completed, failed, partial_refund, cancelled, canceled, succeeded` `orderLifecycleConstants.ts:301-314`).
- `deliverables.status`: `submitted` (`orderDeliverableFiles.ts:285`).
- `revisions.status`: `open` (`088:373`).
- `settlement_items.status`: `pending | on_hold | payable | paid | cancelled` (CHECK `013:19`).
- `disputes.status`: `open | under_review | resolved | dismissed | escalated` (CHECK `004:90`) + 웹 관리자 `sanction_7d | sanction_30d | sanction_permanent` (확인 필요).
- `order_events.event`: §3.3 10종.
- 카테고리: 정적 상수(`CustomRequestCategoryGrid`, D-CR-8 주석 `customRequestQueries.ts:104-106`) — DB 카테고리 테이블 없음. 멘토 탭 분류는 문자열 휴리스틱 4종 `study | career | essay | other` (`mentorOpenPostCategory.ts:572-602`).
- 수수료: CR 5%(`lib/payout/platformFeePolicy.ts:22`, DB `fee_rate 0.05`); 적용 요율 정본은 정산 행 `fee_rate`(분배 RPC `191`).
- 금액 단위: 의뢰/지원/주문 금액은 **원(캐시) 정수**(`agreed_price numeric`), 원장은 ×100 minor(`krwWonToCents`, `customOrderEscrowService.ts:50`).

### 7.3 앱 데이터 접근 클라이언트 요약

- 읽기: 전부 authenticated RLS(SELECT) 또는 anon/authenticated RPC 2종.
- 쓰기(앱 직접): posts insert/update, post/application/deliverable/message 첨부(Storage + 메타), applications insert, deliverables insert, messages insert, disputes insert, order_events insert, RPC 3종(start/deliver/revision).
- 쓰기(웹 위임 또는 신규 wrapper): 임시저장 삭제(W-0), 선정+hold(W-1), 수락(W-2), 직접 취소(W-3).
- 금지: `custom_request_orders` 직접 UPDATE(`cro_update`가 넓어 기술적으로 가능하지만 결제 상태 위조 위험 — §1.4).

---

## §8. 미해결 질문 (Open Questions)

1. 현 운영 DB의 `accept_custom_order_deliverable_atomic` 본문이 즉시 지급(as-applied 0804)인지 후불(110 초안)인지 — `pg_proc.prosrc` 실측 필요. 앱 수락 문구·정산 안내가 달라진다.
2. `cro_update` RLS(당사자 전 컬럼 UPDATE) 잠금(M-1 step 2) 진행 여부. 앱 출시 전 `payment_status`·상태 열 직접 UPDATE 차단(컬럼 제한 정책 또는 RESTRICTIVE 가드)이 필요하다.
3. 수정 요청 RPC가 `order_status`만 갱신하는 것이 의도인지(primary `status`는 `delivered` 유지) — 앱 상태 표시·수락 허용 판정 규칙 확정 필요.
4. `custom_request_applications (post_id, mentor_id)` DB 유니크 부재 — 앱 동시 제출 시 중복 지원 가능. 인덱스 추가 여부.
5. 의뢰 첨부 크기: 웹 상수 50MB vs 버킷 20 MiB — 운영 버킷 `file_size_limit` 실측 후 앱 기준 확정.
6. `IDENTITY_GATE_ENABLED` 운영 값, 앱에서 `users.identity_verified_at` 자기 행 읽기 가능 여부(`users_select_own` 정책 본문 미확인).
7. `api_app_v1`에 멘토 디렉터리 뷰(닉네임)가 있는지; 없으면 W-5 신설.
8. 분쟁 `sanction_*` 상태가 DB CHECK에 반영됐는지(004 CHECK 5종 외).
9. 검토 기간 3일 카운트다운 만료 후 정책(자동 수락/자동 환불/운영 개입) — 현재 코드상 아무 일도 일어나지 않음. 오너 결정 필요.
10. 주문 생성·완료 시 `custom_request_posts.status`를 갱신하지 않아 글이 영구 `open`으로 오픈 풀에 남는 문제(멘토 풀은 지원한 글만 제외 `mentorCounts.ts:44-47`) — 앱에서 "선정됨" 글을 숨길 기준 필요.
11. CR 완료가 리뷰 자격에 미포함(구독/개별질문만) — CR 리뷰 정책 확정.
12. 계약서가 CR을 "신규 객체 미생성·유지" 영역으로 고정 — 앱 wrapper(W-0~W-3, W-7, W-8) 신설은 앱 계약 v1.x 갱신 항목으로 등재 필요.
