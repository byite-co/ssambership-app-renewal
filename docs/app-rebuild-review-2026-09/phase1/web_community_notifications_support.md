# 웹 리포트 — 커뮤니티 · 공지 · 알림 · 지원(분쟁/신고/환불) · 차단 · 설정

> 대상: 웹 `/home/user/ssambership_web` (Next.js 16 + Supabase), 대조: 앱 `/home/user/ssambership-app` (Flutter, 같은 Supabase).
> 범위: 프론트 구조·서버 표면(RPC/RLS/Storage/Realtime)·DB. UI 디자인 제외. 읽기 전용 검토(저장소 무수정).
> 표기: 경로는 저장소 루트 기준. `(확인 필요)` = 코드로 확정하지 못한 항목. 날짜 기준 2026-09-03.

---

## §0 한 줄 요약

- 게시판 글 쓰기는 **RPC 단일 경로**(`api_web_v1.community_post_create/update/soft_delete` ↔ 앱 동명 `api_app_v1` wrapper, 공용 구현부 `core_private.*`)이고 `community_posts` 직접 쓰기는 anon/authenticated 에게 전면 회수됐다(HD-1). 숏폼은 여전히 **직접 INSERT/UPDATE**(RLS `sf_insert_mentor`/`sf_update_own` + 보호 트리거) + Storage 직접 업로드다.
- 댓글·반응·신고·차단은 웹·앱 모두 **테이블 직접 쓰기**(RLS)이며, 본인 삭제만 `soft_delete_own_content(p_kind, p_id)`(웹) / `community_comment_soft_delete_self`(앱) SECURITY DEFINER RPC 다. 하드 DELETE 는 트리거로 차단된다(198).
- 알림은 `record_domain_notification`(service_role 전용) 이 `notifications`(+ `notification_outbox`, push 게이트 OFF 기본) 에 원자 기록 → 웹은 목록/읽음/설정만, 실시간·푸시 수신은 없음. 앱은 목록/읽음/unread RPC/Realtime INSERT 구독을 갖되 **FCM 미도입(App-F0)**. 웹 워커(`/api/cron/notification-outbox`)는 플래그 OFF 상태로 배포돼 있고 `register_device_token` GRANT 는 라이브 미적용.
- 공지(`app_notices`)는 웹 `/notices` 목록만 있고 팝업(`display_mode=popup`)·대상(`target`)·`promotion_campaigns` 는 공개 표면에서 미소비. 앱은 공지 화면 자체가 없다.
- 지원: 분쟁 목록/상세(학생·멘토, 읽기 전용), 환불 신청(학생, **service_role 로 `refunds` INSERT** — RLS 는 admin 전용), 내 신고 내역(`content_reports` 본인 행). 앱에는 셋 다 없다.

---

## §1 라우트별 기능 표

공통 표 형식: 라우트 | 목적 | 역할 | 사용자 액션(읽기/쓰기) | 서버 표면 | 결제 접촉 | 플래그·게이트 | 앱 이식 메모

### 1.1 커뮤니티 (`app/(public)/community/**`)

| 라우트 | 목적 | 역할 | 사용자 액션 | 서버 표면 | 결제 접촉 | 플래그·게이트 | 앱 이식 메모 |
|---|---|---|---|---|---|---|---|
| `/community` (`app/(public)/community/page.tsx`) | 커뮤니티 홈: 추천 숏폼 6개(최신) + 인기 게시글 5개(like_count desc, created_at desc) | 공개(anon 가능) | 읽기 | `shortform_posts` 직접 SELECT (`lib/community/communityShortformQueries.ts:124-146`), `api_web_v1.community_posts_v1` view (`lib/community/communityBoardQueries.ts:267-283`), `user_blocks` SELECT(`lib/blocks/userBlocksQueries.ts:11-23`) | 없음 | `isUserBlocksEnabled()` 기본 ON(`lib/shell/featureFlags.ts:29-34`) + 로그인 시 차단 작성자 JS 필터(`page.tsx:31-35`) | 앱은 홈 섹션 없음(탭 3개). 동일 뷰·테이블 쿼리로 재현 가능 |
| `/community/board` (`board/page.tsx`) | 게시판 목록(카테고리·정렬 탭 all/latest/popular) | 공개 | 읽기 | `api_web_v1.community_posts_v1` (`listCommunityBoardPosts` — `communityBoardQueries.ts:200-260`), 더보기는 `GET /api/community/posts` | 없음 | 차단 필터(`board/page.tsx:34-40`) | 앱은 latest 만(`community_read_repository.dart:78`); popular 정렬은 뷰 order 로 가능 |
| `/community/board/[id]` (`board/[id]/page.tsx`) | 글 상세 + 댓글(2-depth) + 반응 + 신고 + 차단 + 조회수 | 공개 읽기 / 로그인 쓰기 | 읽기: 글·댓글·반응 플래그·찜; 쓰기: 댓글 작성/삭제, 좋아요/스크랩 토글, 글 삭제(작성자), 신고, 차단 | 읽기 `community_posts_v1` view, `api_web_v1.community_comments_v1` view(`communityBoardQueries.ts:404-458`), `post_reactions` SELECT(본인)(`:460-474`); 쓰기 `comments` INSERT 직접(`communityBoardMutations.ts:201-207`), `soft_delete_own_content('board_comment')`(`:219-228`), `post_reactions` upsert/delete(`:154-180`), `api_web_v1.community_post_soft_delete`(`:100-112`), `content_reports` INSERT(`lib/community/communityReportActions.ts:70-76`), `user_blocks` INSERT(`lib/blocks/userBlocksActions.ts:35-37`); 조회수 `POST /api/community/board/view` → `community_post_view_record_v2` | 없음 | 로그인 필요(쓰기) · `assertAccountActive`(댓글, `communityBoardActions.ts:269-274`) · 차단 버튼 조건(`page.tsx:82-83`) | 앱은 글 삭제(api_app_v1 F6)·반응·댓글 작성·신고·차단 있음. **게시판 댓글 본인 삭제 없음**, 답글(parent_id) UI 없음 |
| `/community/board/[id]/edit` (`board/[id]/edit/page.tsx`) | 작성자 편집(발행/임시 모두) | 로그인 + 본인 | 쓰기: `community_post_update` | `getCommunityBoardPostForEdit`(view, author_id eq — `communityBoardQueries.ts:354-382`) → `api_web_v1.community_post_update(p_post_id, p_title, p_body, p_category, p_expected_updated_at, p_image_refs, p_status)` | 없음 | 비소유는 상세로 redirect(`edit/page.tsx:24-27`) | 앱 있음(`board_post_update_gateway.dart` — `p_expected_updated_at` 동일) |
| `/community/new` (`new/page.tsx`) | 글 작성/임시저장(draft) | 로그인(페이지) / **RPC 는 승인 멘토 전용** | 쓰기: `community_post_create` (draft/publish) | `api_web_v1.community_post_create(p_title, p_body, p_category, p_idempotency_key, p_image_refs, p_status)`; 이미지는 브라우저→Storage 직접(`lib/community/communityImageClientUpload.ts:42-67`) | 없음 | 학생은 RPC `ROLE_NOT_MENTOR`→`role` 오류(`communityBoardMutations.ts:36-42`; 마이그레이션 `20260731113927_…community_rpc.sql:170-175`) · `assertAccountActive`(`communityBoardActions.ts:77-81`) | 앱 있음(published 고정 — `board_post_create_gateway.dart:33`). **임시저장(draft) 없음** |
| `/community/me` (`me/page.tsx`) | 내 활동(overview/posts/drafts/scraps) + 관리자 숨김·삭제 배지 | 로그인 | 읽기 | view(author_id eq)·`shortform_posts`(author_id eq)·count·`post_reactions`(scrap)→view(`communityQueries.ts:65-116`, `communityBoardQueries.ts:476-502`) | 없음 | — | 앱 `MyActivityView`(내 글·좋아요·스크랩). **임시저장 탭·모더레이션 배지 없음** |
| `/community/shortform` (`shortform/page.tsx`) | 숏폼 목록(카테고리·정렬 탭) + 업로드 FAB | 공개 | 읽기 | `shortform_posts` 직접(`status published or null`, `deleted_at null`, limit 48) — 썸네일만 서명(`communityShortformQueries.ts:114-175`) | 없음 | FAB 는 클라 `isMentor` 게이트(`components/community/CommunityShortformUploadFab.tsx:19-29`) | 앱 있음(피드 + 멘토만 WebView 작성 진입 `shortform_feed_view.dart:89`) |
| `/community/shortform/[id]` (`shortform/[id]/page.tsx`) | 숏폼 상세: 재생(서명 URL)·좋아요·댓글·신고·차단·조회수 | 공개 읽기 / 로그인 쓰기 | 쓰기: 좋아요 토글, 댓글 작성/본인 삭제, 신고, 차단 | `shortform_posts` 직접, `community_comments`(post_type=shortform, status=visible, deleted_at null — `communityQueries.ts:185-218`), `shortform_reactions`(like 만 — `communityShortformMutations.ts:115-139`), `soft_delete_own_content('shortform_comment')`(`lib/community/commentActions.ts:106`), `content_reports`(target_type `shortform_post`), `shortform_view_record_v2`(SSR 시 서버 파생 event_key — `page.tsx:56-62`) | 없음 | `assertAccountActive`(댓글, `commentActions.ts:57-60`) · 숨김 숏폼은 작성자만(`communityShortformQueries.ts:188-194`) | 앱 있음(좋아요+스크랩·댓글·본인 댓글 삭제(`community_comment_soft_delete_self`)·신고·차단). 웹은 **숏폼 스크랩 UI 없음** |
| `/community/shortform/new` (`shortform/new/page.tsx`) | 숏폼 작성(웹 표면) | 로그인 + `role==='mentor'`(`:13-14`) | 쓰기: 서명 티켓 발급→브라우저 업로드→썸네일 업로드→finalize(직접 INSERT/UPDATE) | `createShortformVideoUploadTicketAction`(**service_role signer 우선, 실패 시 사용자 클라 폴백** — `lib/community/communityShortformActions.ts:288-295`), `uploadShortformThumbnailAction`(dataURL ≤512KB magic-byte — `lib/community/shortformThumbnailRef.ts:16-38`), `submitShortformUploadAction` → `shortform_posts` INSERT/UPDATE 직접(`communityShortformMutations.ts:52, 96-102`) | 없음 | `assertAccountActive` · `profile.role==='mentor'`(`communityShortformActions.ts:105-114`) · 발행 시 `rightsAck` 필수(`:127`) | 앱은 네이티브 작성 없음 → `/app/community/shortform/new` WebView |
| `/community/posts`, `/community/write`, `/community/shorts`, `/community/shorts/[id]` | 레거시 permanentRedirect 스텁 | — | — | — | 없음 | — | 무시 |

### 1.2 공지·알림·설정·지원 (`app/(public)/notices`, `notifications`, `settings`, `support`, `app/(student)/…`)

| 라우트 | 목적 | 역할 | 사용자 액션 | 서버 표면 | 결제 접촉 | 플래그·게이트 | 앱 이식 메모 |
|---|---|---|---|---|---|---|---|
| `/notices` (`app/(public)/notices/page.tsx`) | 공개 공지 목록(50건) | 공개 | 읽기 | `app_notices` SELECT `id,title,body,type,created_at,is_active` where `is_active=true` (`lib/notices/publicNoticesQueries.ts:54-59`; RLS 가 노출 기간 강제 `supabase/sql/031_p1_admin_notices_promotions.sql:88-102`) | 없음 | — | **앱에 공지 화면 없음**(`grep app_notices` 0건). RLS anon/authenticated 읽기 가능 → 직접 조회로 이식 가능 |
| `/notifications` (`app/(public)/notifications/page.tsx`) | 알림 허브: 키셋 페이지·미읽음 필터·카테고리 6종·읽음/모두읽음 | 로그인(모든 role) | 읽기 + 읽음 처리 | `notifications` 직접 SELECT(`lib/notifications/notificationsHubQueries.ts:122-217`), 미읽음 count 직접(`:168-179`), `mark_notification_read(p_notification_id)`·`mark_all_notifications_read()`(`lib/notifications/notificationReadActions.ts:20, 69`) | 없음 | — | 앱 있음(+Realtime, unread RPC). 웹은 Realtime 없음 |
| `/settings/notifications` (`app/(public)/settings/notifications/page.tsx`) | 알림 설정(푸시 전역 + 그룹 5) | 로그인 | 읽기/쓰기 | `notification_settings` SELECT/UPSERT(`lib/notifications/notificationSettingsActions.ts:34-38, 70-75`) | 없음 | — | 앱 있음(`mypage/data/notification_settings_repository.dart`) |
| `/support` (`app/(public)/support/page.tsx`) | 고객센터 FAQ(정적) + 연락처 | 공개 | 없음 | 없음 | FAQ 문구에 결제 안내 링크만 | — | 앱은 `WebBridgeConfig.supportPath='/support'` 로 웹 열기(`lib/core/web_bridge/web_bridge_config.dart:35-36`) |
| `/settings/blocks` (`app/(student)/settings/blocks/page.tsx`) | 차단 목록·해제(학생·멘토 공용) | 로그인(레이아웃 예외 `app/(student)/layout.tsx:16-19, 52-79`) | 읽기/쓰기(해제) | `user_blocks` SELECT own + `users` SELECT(닉네임)(`page.tsx:25-41`), `unblockUserAction` → `user_blocks` DELETE(`userBlocksActions.ts:57`) | 없음 | `isUserBlocksEnabled()` OFF 면 `/mypage`(`page.tsx:18`) | 앱 있음(`blocked_users_screen.dart`, `my_blocked_users` RPC). 웹은 RPC 미사용 — `users` RLS(본인+admin) 때문에 타인 닉네임이 0건→"회원" 폴백일 가능성 (확인 필요, 근거: `supabase/migrations/20260807020000_my_blocked_users_rpc.sql:7-8`) |
| `/support/disputes` (`app/(student)/support/disputes/page.tsx`) | 학생 분쟁 목록 | `requireRole("student")` | 읽기 | `disputes` SELECT `student_id = uid`(`lib/disputes/disputeListQueries.ts:209-234`; RLS `dispute_select` `supabase/sql/004_p0_cash_disputes_admin_draft.sql:195-199`) | 상태 읽기(주문/결제 id 요약) | — | 앱 없음. RLS 당사자 읽기 가능 |
| `/support/disputes/[id]` (`…/[id]/page.tsx`) | 분쟁 상세 번들(환불·결제·구독·주문·처리 이력) | 학생 당사자(`canPartyViewDispute` `lib/disputes/disputeQueries.ts:272-285`) | 읽기 | `disputes`, `refunds`(공유키 역참조 `:63-83`), `payments`, `subscriptions`, `custom_request_orders`, `order_payments`, `admin_action_logs`(admin RLS → 학생 0건 `:90-106`) | 상태 읽기 | — | 앱 없음. 결제 행 읽기는 `payments` RLS 에 좌우 (확인 필요) |
| `/support/refunds` (`app/(student)/support/refunds/page.tsx`) | 구독 잔여기간 환불 **신청** | 로그인(페이지) / 액션 `requireRole("student")` | 읽기(환불 가능 구독·pending 환불) + 쓰기(신청) | `loadStudentSubscriptionManagementList`(세션; `refunds` SELECT pending `lib/subscribe/studentSubscriptionManagement.ts:131-153`), `requestSubscriptionProratedRefundAction` — **`createServiceRoleClient()` 로 `refunds` INSERT**(`lib/subscribe/subscriptionCancelActions.ts:180, 242-251`) | **상태 읽기(구독·billing event·예상액 계산) — 결제 실행 없음** | 활성 구독·pending 중복 금지·예상액 0 이면 거부(`:186-237`) | 앱 없음. `refund_ins` RLS 가 admin 전용(`supabase/sql/021_p0_refund_ins_admin_only.sql:6-8`)이라 **앱은 직접 INSERT 불가 → 새 SECURITY DEFINER RPC 필요** |
| `/support/reports` (`app/(student)/support/reports/page.tsx`) | 내 신고 내역 | `requireRole("student")` | 읽기 | `content_reports` SELECT `reporter_id = uid`(`lib/support/studentReportsQueries.ts:29-34`; RLS `content_reports_select_reporter` `supabase/sql/032_p1_admin_content_reports.sql:56-60`) | 없음 | — | 앱 없음. 테이블은 앱 manifest 에 이미 있음 |
| `/mentor/support/disputes`, `/mentor/support/disputes/[id]` (`app/(mentor)/mentor/support/disputes/**`) | 멘토 분쟁 목록/상세 | `requireRole("mentor")` | 읽기 | 동일(`mentor_id = uid`) | 상태 읽기 | — | 앱 없음 |

### 1.3 앱 WebView 표면·API 라우트 (`app/app/**`, `app/api/**`)

| 라우트 | 목적 | 역할 | 사용자 액션 | 서버 표면 | 결제 접촉 | 플래그·게이트 | 앱 이식 메모 |
|---|---|---|---|---|---|---|---|
| `POST /api/app-session/bootstrap` (`app/api/app-session/bootstrap/route.ts`) | 앱 토큰 → 웹 세션 쿠키 발급 후 303 → `/app/community/shortform/new` | 앱 멘토 | 쓰기(세션) | body(form-urlencoded/json) `access_token`·`refresh_token`·`target='shortform_create'`(`lib/appSession/appSessionBootstrapCore.ts:17-19, 57-91`); 프로젝트 ref 일치(`:131-135`); `setSession`→`getUser`→strict 계정 게이트(`users.status/suspended_until` + `account_deletion_status_self()` `lib/appSession/appSurfaceAccountGate.ts:121-139`)→mentor role; 쿠키 HttpOnly/Secure/Lax/Path=/ 강제(`lib/appSession/appSurfaceCookies.ts:11-16`); GET/PUT/PATCH/DELETE 405 | 없음(target enum 에 결제 없음) | 실패 전부 `/app/bridge/error?code=…` 5종(`lib/appSession/appSurfacePaths.ts:18-25`) | 앱 `ShortformComposeScreen` 이 사용(`lib/features/community/ui/shortform/shortform_compose_screen.dart:106-116`) |
| `/app/community/shortform/new` (`app/app/community/shortform/new/page.tsx`) | 앱 전용 숏폼 작성(전역 셸 없음) | 앱 세션 멘토 | 쓰기 | `createAppSurfaceClient()`; strict 게이트; `CommunityShortformComposeForm surface="app"` → `*FromAppAction` 3종(`communityShortformActions.ts:263, 311, 357`) | 없음 | `account_blocked`/`mentor_only`/`session_expired` enum | 앱 WebView allowlist 4경로(`lib/core/web_bridge/shortform_compose_bridge.dart:58-66`) |
| `/app/bridge/complete?kind=shortform&result=draft\|published`, `/app/bridge/error?code=…` | 완료/오류 브릿지(앱이 intercept) | — | — | enum 검증(`app/app/bridge/complete/page.tsx:18`, `error/page.tsx:13-19`) | 없음 | — | 앱 `completionOf()`(`shortform_compose_bridge.dart:71-82`) |
| `GET /api/community/posts` (`app/api/community/posts/route.ts`) | 게시판 목록 페이지 API(더보기·탭 전환) | 공개 | 읽기 | `listCommunityBoardPosts` + 차단 필터, 오류 500(`:29-31`) | 없음 | — | 앱은 뷰 직접 조회 — 불필요 |
| `POST /api/community/board/view` (`app/api/community/board/view/route.ts`) | 조회수 +1 (세션당 1회 클라 가드) | 공개 | 쓰기(계수) | `community_post_view_record_v2(p_post_id, p_event_key)`; event_key = `viewEventKeyFor(postId, uid \| anonh:sha256(ip\|ua), UTC hour)`(`lib/community/viewEventKey.ts:64-90`) | 없음 | — | 앱은 RPC 직접 호출(UUID v4/화면 1회) |
| `GET /api/cron/notification-outbox` (`app/api/cron/notification-outbox/route.ts`) | 푸시 outbox 워커(매분, `vercel.json:17-18`) | cron(`CRON_SECRET`) | 서버 배치 | service_role: `notification_outbox_reclaim_expired()`, `notification_outbox_claim(p_owner, p_limit, p_lease_seconds)`, `notification_outbox_mark_sent(p_id)`, `notification_create_deliveries(p_outbox_id)`, `notification_deliveries` SELECT join `device_tokens`, `notification_delivery_mark_sent(p_id)`, `notification_delivery_mark_failed(p_id, p_error, p_invalid_token)`, `notification_outbox_mark_failed(p_id, p_error, p_backoff_seconds)` (`route.ts:106-235`) | 없음 | `NOTIFICATION_OUTBOX_WORKER_ENABLED`(기본 no-op), `FCM_TRANSPORT_MODE=live` 만 실발송, `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT_JSON_B64`(`:48-77`, `lib/notifications/fcmTransport.ts:139-159`) | 앱은 수신 측(FCM SDK) 미도입 |

---

## §2 게시판

### 2.1 작성/수정/삭제 RPC (웹 `api_web_v1` · 앱 `api_app_v1` — 동일 시그니처·동일 공용 구현부)

정본 마이그레이션: `supabase/migrations/20260731113927_20260730105252_api_web_v1_community_rpc.sql`, 앱 wrapper: `supabase/sql/20260730112525_api_app_v1_surface.sql`.

| 함수 | 시그니처 | 반환/오류 | 판정 |
|---|---|---|---|
| `api_web_v1.community_post_create` / `api_app_v1.community_post_create` | `(p_title text, p_body text, p_category text, p_idempotency_key uuid, p_image_refs text[] default '{}', p_status text default 'published') returns jsonb` (`…community_rpc.sql:93-97`; app `…api_app_v1_surface.sql:193-195`) | `{ok:true, post_id, idempotent_replay, contract_version:1}` / `{ok:false, code}` — `AUTH_REQUIRED, ROLE_NOT_MENTOR, MENTOR_NOT_APPROVED, ACCOUNT_BANNED, ACCOUNT_SUSPENDED, ACCOUNT_DELETION_IN_PROGRESS, TITLE_REQUIRED, CATEGORY_INVALID, BODY_TOO_SHORT, IMAGE_*` (`:151-219`) | **replay-first**: `(author_id, create_idempotency_key)` 기존 행이 있으면 검증 전에 재생(`:159-164`); UNIQUE 인덱스 `community_posts_author_idem_key`(`supabase/sql/147_p2_2_community_board_idempotency_softdelete.sql:22-23`). 승인 멘토 전용(`users.role='mentor'` + `individual_question_user_is_approved_mentor`). 제목·본문 연락처 마스킹을 SQL 로 이식(`:200-213`). `p_idempotency_key` NULL 은 예외 전파(`:155-157`) |
| `…community_post_update` | `(p_post_id uuid, p_title, p_body, p_category, p_expected_updated_at timestamptz, p_image_refs text[] default '{}', p_status text default 'published')` (`:114-118`) | `{ok:true, post_id, updated_at, removed_image_refs[]}` / `POST_NOT_FOUND_OR_NOT_OWNED, UPDATE_CONFLICT, ROLE_NOT_MENTOR …` (`:269-307`) | 소유 행 `FOR UPDATE` + `deleted_at IS NULL`; `updated_at IS DISTINCT FROM p_expected_updated_at` → `UPDATE_CONFLICT`(자동 재시도 없음 `communityBoardMutations.ts:139-140`); 제거된 ref 차집합을 반환해 클라가 커밋 후 Storage 정리(`:13-26` in part2) |
| `…community_post_soft_delete` | `(p_post_id uuid)` (`:135`) | `{ok:true, post_id, deleted_at[, already_deleted:true]}` / `POST_NOT_FOUND_OR_NOT_OWNED, ACCOUNT_*` | 역할 게이트 없음(작성자면 학생도 삭제 가능); **`deleted_at` 만 세팅, `deleted_by` 미기록**(`part2:80-82`) — 194 가 `community_posts.deleted_by` 를 추가했지만 F6 은 갱신하지 않음 (확인 필요: 관리자 화면 `작성자 삭제` 배지 판정에 영향) |
| GRANT | wrapper 3종 `authenticated, service_role` EXECUTE, `core_private.*` 4종 외부 EXECUTE 0 (`:154-165`) | | `api_app_v1` 스키마 USAGE 는 authenticated 만(service_role·anon 아님 — `…api_app_v1_surface.sql` 헤더 6-9행) |

웹 호출부: `lib/apiWebV1/rpc.ts:39-59`(`supabase.schema("api_web_v1").rpc(fn,args)`, `ok` 필드 없으면 실패). 전송 오류 시 같은 멱등키로 정확히 1회 재호출(`communityBoardMutations.ts:82-87`), 확정 실패에서만 신규 업로드 보상 삭제(`communityBoardActions.ts:158-168`). 멱등키는 폼 `requestId`(브라우저 `crypto.randomUUID`, `components/community/CommunityBoardComposeForm.tsx:129-135, 244-245`).

`community_posts` 직접 쓰기 잠금(HD-1): `REVOKE ALL … FROM anon, authenticated; GRANT SELECT` + 쓰기 정책 6종 DROP (`supabase/sql/20260730195153_community_direct_write_lockdown.sql:123-132`). SELECT 정책은 `cp_select_visible` 하나로 통합: `deleted_at IS NULL AND (published OR author_id=uid) OR is_admin()` (`supabase/migrations/20260806200500_community_posts_select_deleted_filter.sql:39-45`).

### 2.2 이미지 (버킷 `community-post-images`)

- 버킷: `public=false`, 5MB, MIME jpeg/png/webp/gif (`supabase/sql/037_p1_community_board_v2.sql:195-206`). 정책: `cpi_public_read`(SELECT anon+authenticated), `cpi_auth_insert_own`/`update_own`/`delete_own` = `foldername[1] = auth.uid()` (`:208-239`; baseline `supabase/migrations/20260701000000_pre_ledger_baseline.sql:4412-4419`).
- 저장 형식: DB `community_posts.image_urls[]` 에 `community-post-images/{uid}/{uuid}-{safeName}.{ext}` ref (`lib/community/communityImageRef.ts:3, 27-41`). 서명 URL 은 표시 시점 1h (`lib/community/communityImageStorage.ts:23, 33-50`).
- 서버 검증 `core_private.community_image_refs_validate(p_owner_id, p_image_refs)`: 개수 ≤5, 버킷 접두사, 첫 세그먼트=소유자, `storage.objects` 실존, owner 일치, MIME 4종, size ≤5242880 (`…community_rpc.sql:77-128`).
- 클라 업로드: 브라우저 → Storage 직접(413 회피), 실패 시 보상 삭제(`communityImageClientUpload.ts:42-76`). 앱 동일 규약(`lib/features/community/data/board_post_media_gateway.dart:25-65, 104-121`, 경로 `{uid}/{ts}_{safeName}`).

### 2.3 댓글 (`comments` 정본 · `community_comments` 레거시 브리지)

- `comments` (037:38-50): `post_id FK community_posts`, `author_id`, `parent_id`(2-depth), `content`(1~2000), `like_count`, `is_deleted`, `author_label`(비정규화 — `supabase/migrations/20260731100540_20260730095438_comments_author_label_denormalize.sql`), 194 추가 `deleted_at`, `deleted_by`.
- RLS: `comments_select_visible` = `is_deleted=false AND deleted_at IS NULL`(194:396-401), `comments_insert_own`, `comments_update_own`, `comments_delete_own`(037:251-265) — 단 `comments_write_guard` 트리거가 DELETE(비관리자)·보호 컬럼 변경·깊이 초과(`COMMENT_DEPTH_EXCEEDED`)·`legacy_comment_id` 를 거부(194:184-243)하고, 198 이 하드 DELETE 를 트리거로 전면 차단(`supabase/sql/198_ugc_block_hard_delete.sql:83-93`).
- 읽기 뷰 `api_web_v1.community_comments_v1`(security_invoker): `id, post_id, author_id, parent_id, body(=content), like_count, author_label, author_role, created_at` where `is_deleted=false and deleted_at is null` (194:365-377). 앱도 같은 뷰로 읽음(`community_read_repository.dart:127-133`).
- 웹 INSERT: `{post_id, author_id, parent_id, content, author_label}` 직접(`communityBoardMutations.ts:201-207`) — 부모 검증은 웹(`:190-199`)+트리거 이중. 앱 INSERT: `{post_id, author_id, content[, parent_id]}` 만(`community_write_repository.dart:177-189`, 라벨은 서버 트리거).
- 본인 삭제: `soft_delete_own_content('board_comment', id)` (`supabase/sql/196_soft_delete_own_content_rpc.sql:77-159`; 오류 `CONTENT_NOT_FOUND/NOT_OWNED/KIND_MISMATCH/MODERATED, ACCOUNT_*, AUTH_REQUIRED, INVALID_KIND`; GRANT authenticated, service_role; 멱등). 웹 매핑 `lib/community/softDeleteOwnContent.ts:36-42`.
- 댓글 수: 트리거 `community_refresh_post_comment_count`(삭제 제외, 194:173-196). 댓글 좋아요(`like_count`) 토글 표면은 웹·앱 어디에도 없음 (확인 필요: 전용 테이블 부재).
- 레거시 `community_comments`(016): `post_type board|shortform`, `body`(1~1000), `status visible|hidden`, `author_label`, 194 추가 `deleted_at/deleted_by`; 게시판 댓글은 브리지 트리거(`cc_sync_board_to_canonical`, `comments_mirror_to_legacy` 등 194:198-362)로 양방향 동기화. RLS: SELECT `deleted_at null AND (visible OR 본인) OR admin`(194:404-414), INSERT 본인(016:51-60), UPDATE/DELETE admin 전용(`supabase/sql/101_community_comments_admin_moderation.sql:54-68`).

### 2.4 반응 (`post_reactions`)

- 스키마: `(user_id, post_id, type like|scrap)` UNIQUE (037:60-70). RLS: **SELECT 본인만**(`supabase/migrations/20260806033409_post_reactions_select_own_only.sql:12-14`, 종전 전체공개 폐기), INSERT/DELETE 본인(037:277-285). `like_count` 는 트리거(like 만 집계, 037:167-190); 스크랩 수 집계 없음.
- 웹 토글: `upsert(onConflict user_id,post_id,type, ignoreDuplicates)` → 삽입 0행이면 delete (`communityBoardMutations.ts:154-180`). 앱: insert/delete 분기(`community_write_repository.dart:48-68`).

### 2.5 해시태그

- `community_hashtags(tag PK, count)` + 트리거 `community_sync_hashtags`(037:75-127). **F4 INSERT 가 `hashtags '{}'` 고정**(`…community_rpc.sql:222-230`), F5 는 hashtags 를 갱신하지 않음, 웹 payload 도 `hashtags: []`(`communityBoardActions.ts:149`) → 집계가 늘 수 없음. 사이드바 "실시간 인기 주제"(`components/community/CommunityLayoutShell.tsx:18-21`, `listPopularHashtags`)는 사실상 빈 목록. 앱도 미사용. 상수 `COMMUNITY_HASHTAG_MAX=5` 사장(`communityBoardConstants.ts:31`).

### 2.6 조회수 v2

- `community_post_view_record_v2(p_post_id uuid, p_event_key uuid) returns jsonb {ok, contract_version, incremented}`; `community_post_view_events(post_id, event_key) PK`, RLS on·정책 0; `published AND deleted_at IS NULL` 만 계수; GRANT anon, authenticated (`supabase/migrations/20260806033556_community_post_view_record_v2.sql:12-60`). 구 `increment_community_post_view` 는 잔존(호환).
- 웹 event_key: 결정적(글+뷰어+UTC 시간버킷; 비로그인은 `x-forwarded-for` 첫 홉+UA sha256) (`lib/community/viewEventKey.ts:45-90`). 앱: 화면 노출 1회당 UUID v4(`community_write_repository.dart:93-116`). 두 규약 모두 서버가 키 생성을 강제하지 않음(파일 주석 `…view_record_v2.sql:8-11`).

### 2.7 소프트 삭제·하드 DELETE 차단

- `community_posts.deleted_at`(147) + `deleted_by`(194:125-126). `shortform_posts/comments/community_comments` 에 `deleted_at/deleted_by`(194:116-124). `comments.is_deleted` ↔ `deleted_at` 동기화 트리거 `comments_sync_deleted_flag`(194:137-170).
- 쓰기 가드: `shortform_posts_protected_guard`(보호 컬럼·status 전이 draft↔published 만·`deleted_by=auth.uid()`·복원 관리자만, 194:138-182), `comments_write_guard`(194:184-243). 하드 DELETE 차단 `ugc_block_hard_delete`(anon/authenticated 거부, service_role/postgres 통과, 198:62-93). 작성자 복원 RPC 없음(196 헤더 26행).
- 관리자 삭제/숨김/복원은 service_role 직접 UPDATE(`lib/admin/communityModerationCore.ts:97-174`).

### 2.8 카테고리·정렬·페이징

- 게시판 카테고리 정본: `study, school, career, college, free`(+ `all` UI) (`communityBoardConstants.ts:1-8`); RPC CHECK 동일(`…community_rpc.sql:192`). 앱 `community_labels.dart` 동일 5종.
- 정렬: `all/latest` = `created_at desc` **키셋 `lt(created_at)` 단독**(id 타이브레이크 없음 — 동시각 행 누락 가능, `communityBoardQueries.ts:229-233`); `popular` = like_count→view_count→comment_count→created_at, **오프셋 커서 `o:N`**(`:213-217, 252-254`). 페이지 12, API limit ≤24(`app/api/community/posts/route.ts:16-17`). 홈 인기글 = like_count desc, created_at desc (`:271-276`). 앱: `range(offset)` + `status=published`(`community_read_repository.dart:70-79`).

---

## §3 숏폼

### 3.1 작성 흐름 (웹 `/community/shortform/new` · 앱 WebView `/app/community/shortform/new`)

1. 페이지 게이트: 웹 `profile.role==='mentor'`(`shortform/new/page.tsx:14`); 앱 표면은 `createAppSurfaceClient()` + `assertAppSurfaceAccountActiveStrict`(status allowlist `active`·만료 suspended 만 통과, `account_deletion_status_self()` `write_blocked=false` 필수 — `lib/appSession/appSurfaceAccountGate.ts:44-82`) + mentor.
2. 폼(`components/community/CommunityShortformComposeForm.tsx:221-263`): `requestId` UUID → `createShortformVideoUploadTicket[FromApp]Action({contentType})` → `{path, token, ref}`(`shortform-videos/{uid}/{uuid}.{ext}`, MIME mp4/quicktime/webm — `lib/community/shortformVideoRef.ts:8-24`) → 브라우저 `storage.uploadToSignedUrl` → 첫 프레임 canvas dataURL → `uploadShortformThumbnail[FromApp]Action({dataUrl})`(서버 magic-byte 검증 후 `shortform-thumbnails/{uid}/{uuid}-thumb.{ext}` 업로드, `communityShortformStorage.ts:183-202`) → form submit(`submitShortformUpload[FromApp]Action`).
3. finalize(`communityShortformActions.ts:91-255`): 허용 키 11종 문자열만(`lib/community/shortformSubmitFields.ts:9-21`); `rightsAck` 발행 필수; ref 소유 검증(`shortformVideoRefBelongsToUser`/`shortformThumbnailRefBelongsToUser`); INSERT payload `author_id, title(≤100), body(≤500), category('all'→'study'), source, video_url, thumbnail_url, tags(≤5, 항상 []), status, author_role='mentor', author_label, create_idempotency_key`(`communityShortformMutations.ts:35-48`); 23505 시 `(author_id, create_idempotency_key)` 재조회로 멱등 재생(`:53-66`; UNIQUE `shortform_posts_author_idem_key` `supabase/sql/148_p2_3_shortform_idempotency.sql:14-15`). UPDATE 는 `eq(id).eq(author_id)` 0행이면 실패(`:96-107`). 실패 시 신규 video/thumb 보상 삭제, 교체된 구 객체 정리.
4. 앱 표면 완료: `redirect(appBridgeCompletePath("shortform", "draft"|"published"))`(`:249-251`); 웹은 상세/작성화면.
5. 앱 측(`shortform_compose_screen.dart:55-120`): 쿠키 정리(`WebSessionHygiene.clear`) → `loadRequest(POST bootstrapUri, form body)` → allowlist(`https` + host exact + 4경로) → 완료 URL intercept → `pop(ShortformComposeResult)`. Android `<input type=file>` → `FilePicker`(mp4/mov/webm) (`:141-154`).

### 3.2 thumbnail_url NULL 문제

- 배경: 업로드 헬퍼·Storage 정책은 있었으나 호출자가 없어 finalize 가 항상 `thumbnailUrl=null` 이었음(`lib/community/shortformThumbnailRef.ts:3-8`). QA-C15 로 클라 첫 프레임 캡처→서버 액션 업로드 경로가 추가됐고, 썸네일 실패는 발행을 막지 않고 **조용히 null** 로 둔다(`communityShortformActions.ts:165-176`).
- 앱 모델은 여전히 `thumbnail_url` null 을 전제(`lib/features/community/data/community_models.dart:130-135` 주석). 앱 WebView(Android WebView/WKWebView)에서 `<video>`+canvas 프레임 추출이 동작하는지는 코드로 확인 불가 (확인 필요).

### 3.3 버킷·서명 URL·정책

- 버킷 `shortform-videos`(500MB, mp4/quicktime/webm), `shortform-thumbnails`(5MB, jpeg/png/webp), 둘 다 `public=false`(038:43-64).
- 정책: `sfv_public_read` SELECT anon+authenticated(038:66-68; baseline 4593-4595), `sfv_mentor_insert` = 두 버킷 ∧ `is_mentor()` ∧ `foldername[1]=uid` ∧ `not account_deletion_write_blocked(uid)`(baseline 19840-19847), `sfv_mentor_delete_own`(baseline 4605-4610). `is_mentor()` SECURITY DEFINER SQL(038:38-41).
- 서명 URL: 상세는 영상+썸네일, 목록은 썸네일만(`communityShortformQueries.ts:94-120`), TTL 기본 7일(`lib/storage/signedStorageUrl.ts:3`). 버킷 마커 없는 레거시 http URL 은 Supabase 호스트 allowlist 만 통과(`lib/community/shortformExternalMedia.ts:25-35`).
- 웹 티켓 발급은 service_role 서명을 우선하나 실패 시 사용자 클라로 폴백(`communityShortformActions.ts:288-295`) → **RLS 상 멘토 본인 폴더 직접 업로드가 이미 허용**돼 있어 앱 네이티브 업로드는 서명 티켓 없이 가능.

### 3.4 반응·댓글·카테고리·게이트·조회수

- `shortform_reactions`: `type in ('like','scrap')`(`supabase/sql/130_shortform_scrap_reaction.sql:13-20`), RLS `select_own/insert_own/delete_own`(`supabase/sql/082_community_shortform_likes.sql:65-80`). 웹은 like 토글만(`communityShortformMutations.ts:115-139`), 앱은 like/scrap 모두(`community_write_repository.dart:71-91`).
- 댓글: `community_comments(post_type='shortform', status='visible')` 직접 INSERT(`lib/community/communityMutations.ts:34-40`; 앱 `community_write_repository.dart:155-161`). 본인 삭제: 웹 `soft_delete_own_content('shortform_comment')`, 앱 `community_comment_soft_delete_self(p_comment_id)`(194:85-135; 오류 `COMMENT_NOT_FOUND/TYPE_NOT_SUPPORTED/NOT_OWNED/MODERATED, ACCOUNT_*`; GRANT authenticated 유지 196:193-197).
- 카테고리 4종 `study, school, career, college`(`communityShortformConstants.ts:1-7`) — DB CHECK 존재 여부 미확인 (확인 필요).
- 멘토 전용 작성: RLS `sf_insert_mentor` = `is_mentor() AND (author_id|creator_id = uid)`(038:94-99), `sf_update_own`(038:101-104); status CHECK `draft|published|hidden`(038:21-25); 보호 트리거(194:138-182).
- 읽기 RLS `sf_select_published`: `deleted_at null AND (published OR author_id=uid OR creator_id=uid) OR is_admin()`(194:383-394).
- 조회수 `shortform_view_record_v2(p_post_id uuid, p_event_key uuid)`(194:24-57; anon EXECUTE 유지 194:305); `increment_shortform_post_view` 는 anon 회수·앱 금지어(`outbound_api_manifest_test.dart:144`).
- 숏폼 본인 삭제 UI: 웹·앱 모두 없음(`softDeleteOwnContent.ts:9`; 198 §0 표) — RPC `soft_delete_own_content('shortform')` 은 준비됨.

---

## §4 신고·차단

### 4.1 `content_reports`

- 스키마(032:12-29): `reporter_id, target_type, target_id uuid null, reason, description, status pending|reviewing|resolved|rejected|dismissed, admin_note, resolved_by, resolved_at`.
- INSERT 정책(최종 `supabase/migrations/20260806075316_report_target_content_valid_rpc_unexposed.sql:31-43`): `reporter_id=uid AND status='pending' AND admin_note/resolved_* null AND target_type ∈ {community_post, shortform_post, community_comment, board_comment, user}` + 실존 검증 `rls_private.report_target_content_valid`(194:69-83, 삭제된 콘텐츠 제외) / `public.report_target_user_valid`.
- 멱등: BEFORE INSERT 트리거 `content_reports_dedupe_open` — 본인 신고 중 `(target_type, target_id, reason)` 동일하고 `status in (pending, reviewing)` 인 건이 있으면 description 갱신 후 `return null`(삽입 생략, 클라에는 성공) + advisory lock(`supabase/migrations/20260806201000_content_reports_idempotent_open.sql:44-111`).
- SELECT: admin 전체 / `reporter_id=uid`(032:45-60). UPDATE/DELETE admin.
- 사유 집합 불일치: 웹 한글 5종 `부적절한 내용, 스팸·광고, 욕설·비방, 개인정보 노출, 기타`(`components/reports/ReportDialog.tsx:10`; 허용 외는 `기타` 폴백 `communityReportActions.ts:11-17, 60`) vs 앱 영문 코드 5종 `inappropriate, spam, external_contact, copyright, etc`(`lib/features/community/ui/widgets/report_sheet.dart:9-15`). DB 제약 없음 → 관리자 큐에 두 어휘 혼재 (확인 필요: 관리자 화면 라벨링).
- 대상 범위: 웹은 `community_post`·`shortform_post` 만(`ReportDialog.tsx:25-26`, 그 외 유형은 안내만 `:58-64`); 앱은 `community_post, shortform_post, board_comment, community_comment`(`board_detail_screen.dart:228, 312`; `shortform_detail_screen.dart:291, 307`) + 질문방 `user`(`lib/features/question_room/data/room_safety_repository.dart:53-86`).

### 4.2 `user_blocks`

- `supabase/sql/116_user_blocks.sql`: `(blocker_id, blocked_id) PK, check blocker<>blocked`; RLS `ub_select_own/ub_insert_own/ub_delete_own`(본인), `ub_select_admin`; UPDATE 정책 없음. 플래그 `NEXT_PUBLIC_FEATURE_USER_BLOCKS` 기본 ON, off/0/false/no 만 OFF(`featureFlags.ts:24-34`; 116 라이브 적용 완료 주석 `:25-27`).
- `my_blocked_users() returns table(blocked_id, nickname, created_at)` SECURITY DEFINER, GRANT authenticated(`20260807020000_my_blocked_users_rpc.sql:27-53`) — 앱 사용(`user_blocks_repository.dart:134-153`), 웹 미사용.
- 읽기 영향(스펙 `docs/plans/user-blocks-spec.md` §3): 쿼리 시그니처 무변경, 호출부에서 결과 필터. 웹 적용 지점: 홈(`community/page.tsx:31-35`), 게시판 목록(`board/page.tsx:34-40`), 목록 API(`api/community/posts/route.ts:35-42`), 게시글 상세 댓글 트리(`board/[id]/page.tsx:78-80`, `filterBlockedCommentNodes` 답글 포함), 숏폼 목록(`shortform/page.tsx:32-35`), 숏폼 상세 댓글(`shortform/[id]/page.tsx:69-71`). **차단 필터는 전부 JS 후처리**라 페이지 크기가 줄어드는 성질(앱은 rawCount 로 오프셋 전진 `community_read_repository.dart:42-56`). v1 적용 범위 = 커뮤니티 UGC(질문방·주문방 제외, 스펙 §3) — 앱은 질문방 입장 composer 에도 `isBlockedByMe` 적용(`room_safety_repository.dart:99-104`).
- 차단 진입: 웹은 글/숏폼 작성자만(`BlockUserButton`, `board/[id]/page.tsx:121-125`, `shortform/[id]/page.tsx:138-142`), 댓글 작성자 차단 없음; 앱은 댓글 작성자도(`comment_tile.dart:59, 71`).

---

## §5 공지

- `app_notices`(031:24-42): `title, body, type notice|event|maintenance|update, target(NULL=all; 사전 all/student/mentor — `lib/admin/noticeConsole.ts:57-60`), is_active, starts_at, ends_at`, + `display_mode page|popup`(`supabase/migrations/20260830140804_add_display_mode_to_app_notices.sql`). RLS `app_notices_select`: admin 전체 OR (`is_active AND 기간 내`) to anon/authenticated(031:88-102); 쓰기 admin.
- `promotion_campaigns`(031:55-71): 동일 구조(display_mode 없음), RLS 동일. **공개 소비자 없음**(`lib/subscribe/subscribePageQueries.ts:82-85` 스텁 제거 주석).
- 웹 노출: `/notices` 목록만 — `target`·`display_mode` 미필터/미사용(`publicNoticesQueries.ts:54-59`), 고정 상단 판정은 `type in (maintenance, notice)`(`:43`). 팝업 모달 마운트(PR-10b)는 미머지: `NoticePopupPreview` 는 관리자 편집기에서만 사용(`components/admin/NoticeEditorForm.tsx:13, 171`), 콘솔에 "팝업 노출은 서비스 반영 후 적용됩니다" 문구(`noticeConsole.ts:97`).
- 알림 유형 `notice` 는 웹 카테고리 `system` 에 등재돼 있으나(`lib/notifications/notificationCategories.ts:44`) SQL 에 producer 가 없다(`grep record_domain_notification … 'notice'` 0건) — 공지→알림 연동은 미구현.

---

## §6 알림

### 6.1 정본 유형(producer 실측 18종)과 딥링크

| type | producer(SQL) | 수신자 | 웹 딥링크(`lib/notifications/notificationDeepLink.ts`) |
|---|---|---|---|
| `question_answered` | `qm/qa_answer_notification_after` 트리거(`supabase/sql/20260801040844_qna_answer_notification_per_event.sql`, 메시지/첨부 행 단위 event_key) ← 136/139/142/144 | 학생 | `/question-room/{room}?thread=` (멘토 `/mentor/…`) (`:36-44`) 또는 `metadata.link` |
| `question_received` | `qna_create_question_thread`(path=subscription, `supabase/sql/20260805170000_qna_question_received_notification.sql:86-95`) | 멘토 | `metadata.link='/mentor/question-room/{room}?thread='`; **웹 카테고리 목록에 없음**(`notificationCategories.ts:26-45`) → '전체' 탭에서만 |
| `individual_question_assigned/claimed/answered/message/released/expired_refunded` | `supabase/sql/155_p1_11_iq_notification_atomization.sql:21-83` | 학생/멘토 | `metadata.link` (`data->>link`) |
| `subscription_renewal_upcoming/renewal_succeeded/renewal_failed_insufficient_cash/expired` | `supabase/sql/157_…:73-162` | 학생 | link |
| `mentor_termination_notice/mentor_pause_notice/mentor_termination_refund/mentor_subscription_price_changed` | `supabase/sql/158_…:38-119`, 본문 KST 정정 186 | 학생 | link |
| `new_application`, `new_order_message` | `supabase/sql/159_…:28-70` | 멘토/학생 | `/custom-request/{post}/applications/waiting`, `/custom-request/orders/{order}` (`:45-54`) |

- 웹 `NOTIFICATION_CATEGORY_TYPES`(qna 6 · order 2 · subscription 5 · refund 2 · system 3 = 18 항목)은 producer 18종 중 17종 + producer 없는 `notice` 를 담고 `question_received` 를 빠뜨림. 앱 enum 은 producer 18종 정확 일치(`lib/features/notifications/data/notification_types.dart:21-65`).
- 웹 `resolveNotificationHref` 우선순위: `metadata.link`/`data.link` → 타입 분기 → 레거시 정규식 휴리스틱(`notificationDeepLink.ts:29-144`). 앱은 link 를 **의도적으로 무시**하고 `metadata.room_id/thread_id/question_id/post_id/shortform_id/mentor_id` 만 UUID 검증 후 상세를 연다(`lib/core/deeplink/notification_deep_link_controller.dart:122-155`, `app_notification.dart:114-119`).

### 6.2 `notifications` 테이블·RLS·Realtime

- 컬럼(132·20260803163322 기준): 수신자 7종(`recipient_user_id` 정본 + 레거시 `user_id, recipient_id, student_id, mentor_id, target_user_id, owner_id`), `event_key`, `type`, `body`, `data jsonb {title, link}`, `metadata jsonb {event_key, link, room_id, thread_id, question_id, student_id …}`, `is_read`(정본), `read`(미러 트리거 `notifications_read_state_sync`), `read_at`, `created_at`, `updated_at`. UNIQUE `(recipient_user_id, event_key)` 부분 인덱스(132:29-31).
- writer `record_domain_notification(p_recipient_user_id, p_event_key, p_dedup_key, p_event_type, p_title, p_body, p_link, p_metadata, p_payload)` service_role 전용(132:158-159); outbox 는 `notification_transport_config.push_transport_enabled=true` 일 때만(`…convergence.sql` part2:29-42; 기본 false).
- RLS: `notif_select_recipient`/`notif_update_recipient_read`(authenticated, 7컬럼 OR)(`…convergence.sql:97-130`); anon SELECT/UPDATE 회수, authenticated INSERT/DELETE 회수(N8 `part2:75-76`).
- Realtime: publication `supabase_realtime` 에 `notifications` 포함(N1 `:73-85`). 앱 채널 `notifications_{uid}` postgres_changes INSERT filter `recipient_user_id=eq.{uid}`(공개 채널, 테이블 RLS 적용 — `lib/features/notifications/data/notifications_realtime.dart:47-65`). 웹은 알림 Realtime 없음(웹 Realtime 사용처는 관리자 Presence 1곳). `realtime.messages` RLS 는 `admin:*` 토픽만(197) — 앱 채널에 무영향(197 헤더 11-14행).

### 6.3 커서·읽음·unread·설정

- 웹 커서: base64url(`created_at` + `\x01` + `id`)(`lib/notifications/notificationCursor.ts:23-51`), 키셋 `or(created_at.lt."v",and(created_at.eq."v",id.lt.id))`, 정렬 `(created_at, id) DESC`, 페이지 10(최대 50), prev/next 양방향(`notificationsHubQueries.ts:113-216`). 앱: 같은 키셋 식(따옴표 없음), 페이지 20, next 만(`notifications_repository.dart:83-85, 128-146`), 게이트 2종 `not.in` DB 단계 제외(`:123-137`).
- 미읽음 술어: 웹 `user_id = uid AND is_read is distinct from true` 직접 count(`lib/notifications/notificationUnreadScope.ts:24-26`; 앱 게이트 타입을 제외하지 않음 — D-MT-10 주석). 앱 `notification_unread_count_self() → {ok, contract_version, count}`(게이트 2종 제외, `…convergence.sql:221-249`).
- 읽음 RPC: `mark_notification_read(p_notification_id uuid) → {ok, contract_version, idempotent_hit}`, 예외 `NOTIFICATION_NOT_FOUND`/`NOT_RECIPIENT`, GRANT authenticated(`:182-216`); `mark_all_notifications_read() returns integer`(`supabase/sql/133_mark_all_notifications_read.sql:13-46`).
- `notification_settings(user_id PK, push_enabled bool, groups jsonb, updated_at)`, RLS select_own/modify_own, GRANT select/insert/update authenticated(152:59-72). groups 키 `qna, order, subscription, refund, system`(`lib/notifications/notificationSettingsModel.ts:6`; 앱 동일 `notification_settings_repository.dart:21-27`). DB 그룹 판정 `notification_event_group(p_event_type)` 은 LIKE 패턴(`question_%`/`qna_%`→qna, `custom_%`/`order_%`/`individual_question%`→order, `%subscription%`, `%refund%`, else system — 152:75-84) → `individual_question_*` 는 DB 에서 `order` 그룹인데 웹 UI 카테고리는 `qna`/`refund` 로 분류(`notificationCategories.ts:27-43`) — 표시 분류와 발송 억제 그룹이 다르다 (확인 필요: 의도).
- 발송 허용 `notification_delivery_allowed(p_user_id, p_event_type)` = `push_enabled AND coalesce(groups->>group, true)`; 행 없음 → 허용(152:87-96).

### 6.4 outbox → deliveries → FCM

- `notification_outbox`(132:38-58): `recipient_user_id, notification_id, event_key, dedup_key UNIQUE(recipient,dedup), event_type, payload, status pending|leased|sent|failed|dead|suppressed, attempt_count, max_attempts 8, lease_owner, leased_until, next_attempt_at, last_error`; service_role 전용.
- `notification_deliveries(outbox_id, device_token_id) UNIQUE, status pending|sent|failed|dead|skipped`(152:99-114), service_role 전용.
- 워커(`lib/notifications/outboxWorker.ts:47-98`): reclaim → claim(SKIP LOCKED·lease) → `notification_create_deliveries`(설정 강제 fan-out, `{created, suppressed}`) → 토큰별 transport → delivery sent/failed(invalid token → revoke 경로) → outbox sent/failed(backoff `30·2^(n-1)` cap 3600 `outboxBackoff.ts:6-13`). 라우트가 게이트 2종(`new_order_message`, `new_application`)은 즉시 sent 처리, `notifications` 행 부재 outbox 도 sent 처리(`route.ts:122-169`).
- FCM v1 transport(`fcmTransport.ts:68-100, 189-255`): `google-auth-library` JWT + fetch, 메시지 `notification{title(data.title|'쌤버십'), body}`, `data{type, notification_id, event_key, room_id, thread_id, question_id}`(문자열·부재 생략·link 금지), Android channel `ssambership_default`, APNs priority 10. 실패 분류: 404/UNREGISTERED→invalid, 400 은 "registration token" 문구일 때만 invalid, 401/403 은 revoke 금지(`:116-134`).
- 앱 수신 계약 `PushPayload.fromRemote(data)` 동일 키 6종(`lib/core/push/push_payload.dart:41-60`); **FCM SDK 미도입**(pubspec 에 messaging 없음; `'firebase'` 문자열 0건 계약 `outbound_api_manifest_test.dart:321-326`).

### 6.5 `device_tokens`·등록/철회

- `device_tokens(id, user_id, token UNIQUE, platform ios|android|web|unknown, revoked_at, …)`, RLS `device_tokens_select_own`, `device_tokens_modify_own`(for all), GRANT select/insert/update/delete authenticated(152:12-30).
- `register_device_token(p_token text, p_platform text default 'unknown') returns jsonb {ok, device_token_id}` SECURITY DEFINER, `on conflict(token)` 소유권 이전·revoked 해제(152:33-45). EXECUTE: 152 에서 authenticated 부여 → `20260803163322` N8 에서 회수(`part2:73`) → `supabase/migrations/20260827100100_device_token_register_grant.sql` 재부여 1줄 — **라이브 미적용(O-7 대기)**(파일 헤더 1-3행, `docs/plans/push-outbox-worker.md:14, 27-28`).
- `revoke_device_token(p_device_token_id uuid)` service_role 전용(152:49-55); 앱 철회는 RLS 본인 행 `UPDATE revoked_at`(20260827100100 주석 7행). 앱은 현재 어느 쪽도 호출하지 않음(`grep register_device_token lib` 0건).
- 활성 순서(`docs/plans/push-outbox-worker.md:24-34`): 배포(플래그 OFF) → GRANT 적용 → `NOTIFICATION_OUTBOX_WORKER_ENABLED=true`(dry-run) → postgres 로 `push_transport_enabled=true` → 관측 → `FCM_TRANSPORT_MODE=live`. 순서 위반 시 오래된 알림 폭주 경고.

---

## §7 지원

### 7.1 분쟁

- 테이블 `disputes`(초안 `supabase/sql/002_app_core_schema_draft.sql:481-505`; 실측 정본 컬럼은 `custom_request_order_id, student_id, mentor_id, body, status, submitted_by` — `lib/customRequest/orderDisputeActions.ts:49-50` 주석·payload `:61-68`). 상태값 `open`(제기 시), 웹 표시 매핑 `open/new/submitted→접수됨, pending/under_review→검토 중, escalated, resolved, dismissed/closed, rejected`(`disputeListQueries.ts:58-74`).
- RLS: `dispute_select` = `uid in (student_id, mentor_id) OR is_admin()`(004:195-199); `dispute_ins`(036:58-71) = `custom_request_order_id not null` ∧ 주문 당사자(학생/멘토/admin) ∧ 행의 student/mentor 가 주문과 일치; `dispute_update_admin`.
- 제기 경로: 맞춤의뢰 주문방 `submitCustomOrderDisputeAction`(세션 클라 INSERT, 학생·멘토, 종료 주문 불가, 활성 분쟁 중복 불가 — `orderDisputeActions.ts:53-100`). `/support/disputes*` 는 읽기 전용. 처리 이력은 `admin_action_logs(target_type='dispute')` — admin RLS 라 당사자에겐 빈 목록(`disputeQueries.ts:85-106`). 환불 연계는 `refunds` 공유키 역참조(custom_request_order_id → payment_id → subscription_id, `lib/disputes/disputeRefundLink.ts:12-16`).

### 7.2 신고 내역 (XW-22 재확인)

- `content_reports` 는 032 로 실재하며 `content_reports_select_reporter` 로 본인 행 조회 가능 → `/support/reports` 는 존재하는 테이블을 조회한다(`studentReportsQueries.ts:29-34`). 상태 라벨 `resolved→처리 완료, reviewing→검토 중, rejected/dismissed→반려, 그 외→접수됨`(`:52-58`).

### 7.3 환불 신청

- `/support/refunds` 는 **결제 유도 없이** 환불 신청이 성립: 활성 구독 + `subscription_billing_events` 최근 성공 결제(`latestSucceededBillingEvent`) 로 학원법 별표4 예상액을 계산해 `refunds` 행(`user_id, amount_cents, status='pending', payment_id, subscription_id, billing_event_id, request_type='subscription_prorated', reason`) INSERT(`subscriptionCancelActions.ts:205-251`). 캐시 실차감·토스 호출 없음(관리자 승인 후 처리).
- RLS: `refund_select` = `user_id=uid OR admin`(004:214-217), **`refund_ins` = admin 전용**(021:6-8) → 학생 신청은 `createServiceRoleClient()` 경유(`:180`)로만 가능. 앱 이식 시 동등 RPC(예: `refund_request_self_v1`) 신설 필요.

### 7.4 고객지원

- `/support` 정적 FAQ + `SupportContactSection`; 환불 문의는 `/legal/refund` 안내(`support/page.tsx:74-85`). 학생 허브 탭 3종 `disputes/refunds/reports`(`components/support/StudentSupportTabs.tsx:8-12`).

---

## §8 앱 대조 갭 표

앱 현재 근거: `test/contracts/outbound_api_manifest_test.dart`(RPC 29·테이블 24·스키마 2·버킷 6), `lib/features/community/**`, `lib/features/notifications/**`, `lib/features/mypage/**`.

| 웹 기능 | 앱 현재 | 근거 | 앱 추가 시 필요한 서버 표면 |
|---|---|---|---|
| 게시판 목록/상세/카테고리 | 있음 | `community_read_repository.dart:68-86` (`api_web_v1.community_posts_v1`) | 기존 사용 가능 |
| 게시판 정렬 탭(all/latest/**popular**) + 홈 인기글 | 부분(latest 만) | `:78` order created_at 만 | 기존(뷰에 like_count/view_count/comment_count 있음) |
| 게시판 작성(승인 멘토) | 있음(published 고정) | `board_post_create_gateway.dart:26-33` | 기존 `api_app_v1.community_post_create` |
| 게시판 **임시저장(draft)** 목록·이어쓰기 | 없음 | `kBoardPostCreateStatus='published'`; `my_activity_view.dart:110-112`(내 글/좋아요/스크랩만) | 기존 wrapper `p_status='draft'` + 뷰(본인 행 status 무관 노출) — 새 wrapper 불필요 |
| 게시판 수정(낙관 충돌) | 있음 | `board_post_update_gateway.dart:78-93` | 기존 |
| 게시글 본인 삭제 | 있음 | `community_write_repository.dart:229-242`(api_app_v1 F6) | 기존 |
| 게시판 댓글 작성 | 있음(평면) | `:144-172` | 기존(`comments` INSERT) |
| 게시판 **답글(2-depth)** | 없음(UI 평면) | `:143` 주석 | 기존(트리거가 깊이 검증) |
| 게시판 **댓글 본인 삭제** | 없음 | 198 §0 표(`supabase/sql/198_ugc_block_hard_delete.sql:11`) | 기존 `soft_delete_own_content('board_comment', id)`(GRANT authenticated) — manifest 추가 |
| 게시판 좋아요/스크랩 | 있음 | `:48-68` | 기존 |
| 이미지 업로드(5장·ref) | 있음 | `board_post_media_gateway.dart` | 기존 |
| 조회수 v2 | 있음 | `:101-116` | 기존 |
| 숏폼 목록/상세/재생 | 있음 | `community_read_repository.dart:90-104`, `shortform_media_url_resolver.dart` | 기존 |
| 숏폼 **네이티브 작성**(영상·썸네일 업로드·draft) | 없음(WebView 만) | `shortform_compose_screen.dart:14-23` | 서버 wrapper 없음. RLS 로 직접 경로 가능: Storage `sfv_mentor_insert`(두 버킷 본인 폴더) + `shortform_posts` INSERT(`sf_insert_mentor`, `create_idempotency_key`, 보호 트리거) — 또는 새 `api_app_v1.shortform_post_create/update` 신설(웹과 계약 공유) |
| 숏폼 **임시저장·수정** | 없음 | 위 | 위와 동일(`sf_update_own`, status 전이 draft↔published 만 허용 194:163-167) |
| 숏폼 본인 삭제 | 없음(웹도 없음) | `softDeleteOwnContent.ts:9` | 기존 `soft_delete_own_content('shortform')` |
| 숏폼 좋아요 | 있음(+스크랩) | `community_write_repository.dart:71-91` | 기존(웹이 오히려 스크랩 없음) |
| 숏폼 댓글 작성/본인 삭제 | 있음 | `:144-172, 199-218`(`community_comment_soft_delete_self`) | 기존(웹은 `soft_delete_own_content` 로 통일 — 앱 전환은 별도 트랙 196 헤더 27행) |
| 내 활동(내 글·좋아요·스크랩) | 있음 | `my_activity_view.dart` | 기존 |
| 작성자 본인 **모더레이션 배지(숨김/삭제 사유)** | 없음 | grep `hidden` 배지 없음 (확인 필요) | 기존(뷰가 본인 hidden 행 노출, `deleted_at` 행은 뷰 밖 → 삭제 배지는 불가) |
| 신고(글·숏폼) | 있음(+댓글·사용자) | `board_detail_screen.dart:223-232`, `room_safety_repository.dart` | 기존. 사유 어휘 통일 필요(§4.1) |
| 내 **신고 내역** | 없음 | grep 0 | 기존(`content_reports` 본인 SELECT) |
| 차단/해제/목록 | 있음 | `user_blocks_repository.dart`, `blocked_users_screen.dart` | 기존(`my_blocked_users`) |
| 공지 목록(`/notices`) | 없음 | grep `app_notices` 0 | 기존(`app_notices` RLS anon/authenticated) — manifest 테이블 추가. `target`/`display_mode` 는 클라 필터 |
| 공지 팝업(`display_mode=popup`) | 없음(웹도 미마운트) | `noticeConsole.ts:97` | 기존 컬럼 |
| 알림 목록/키셋/읽음/모두읽음 | 있음 | `notifications_repository.dart` | 기존 |
| 알림 unread 배지 | 있음(RPC) | `notification_badge_controller.dart` | 기존 |
| 알림 Realtime | 있음(웹 없음) | `notifications_realtime.dart` | 기존 |
| 알림 카테고리 탭(6종·맞춤의뢰·환불) | 부분(4 kind + 게이트 2종 제외) | `notifications_screen.dart:84-88`, `notification_types.dart:15-18` | 기존(타입 목록만 클라) |
| 알림 딥링크(link 기반) | 대체(메타 id 기반) | `notification_deep_link_controller.dart` | 기존 metadata 키 |
| 알림 설정(푸시·그룹 5) | 있음 | `notification_settings_repository.dart` | 기존 |
| **푸시 수신(FCM)·토큰 등록** | 없음(App-F0) | pubspec/manifest | `register_device_token` GRANT 적용(20260827100100, 라이브 미적용) + 앱 FCM SDK; 철회는 `device_tokens` 본인 UPDATE |
| 분쟁 목록/상세(학생·멘토) | 없음 | grep `disputes` 0 | 기존(`dispute_select` 당사자 RLS; 연계 `refunds` 본인 RLS; `payments` RLS (확인 필요)) |
| 분쟁 제기 | 없음(맞춤의뢰 자체 없음) | CR 게이트 OFF | 기존(`dispute_ins` 당사자 INSERT) — 맞춤의뢰 도입 전제 |
| **환불 신청(구독 잔여기간)** | 없음 | grep `refunds` 0 | **새 RPC 필요**(`refund_ins` admin 전용 → SECURITY DEFINER `refund_request_self` 신설; 예상액 산정 `computeProratedRefundEstimate`·`hasSubscriptionUsageStartedForPair` 를 SQL 로 이식) |
| 고객센터 FAQ | 웹 열기 | `web_bridge_config.dart:35-36` | 정적 |
| 차단 관리 진입(마이페이지) | 있음 | `settings_section.dart:247-255` | 기존 |
| 계정 게이트(정지/탈퇴 중 쓰기 차단) — 댓글/반응/신고 직접 INSERT | 없음(RPC 경로만 서버 게이트) | 웹 `assertAccountActive`(`commentActions.ts:57-60`); `comments_write_guard`·`community_comments_insert_authenticated`·`post_reactions_insert_own` 에 계정 상태 검사 없음(194:184-243, 016:51-60, 037:277-280) | 서버 보강 필요 (확인 필요: 다른 트리거 존재 여부) — 예: INSERT 정책에 `not account_deletion_write_blocked(auth.uid())` |
| 댓글 연락처 마스킹 | 없음 | 웹 `sanitizeTrustSafetyText`(`commentActions.ts:48`, 클라 측) vs 앱 직접 INSERT | 서버 트리거 없음 (확인 필요) — 게시글은 RPC 가 마스킹(`…community_rpc.sql:200-213`) |

---

## §9 앱이 그대로 못 쓰는 것과 대체안

| 웹 표면 | 못 쓰는 이유 | 대체안 후보 |
|---|---|---|
| `requestSubscriptionProratedRefundAction`(`lib/subscribe/subscriptionCancelActions.ts:168-260`) | Next server action + `createServiceRoleClient()`; `refunds` INSERT RLS admin 전용(021) | SECURITY DEFINER RPC `refund_request_self(p_subscription_id, p_reason)` 신설(중복 pending·활성 구독·예상액 산정 서버화, `request_type='subscription_prorated'`), GRANT authenticated |
| `createShortformVideoUploadTicket[FromApp]Action`(service_role signer) | server action | 불필요 — RLS `sfv_mentor_insert` 로 멘토 본인 폴더 직접 업로드 가능(baseline 19840-19847); 파일 크기 상한은 버킷 500MB |
| `uploadShortformThumbnail[FromApp]Action`(서버 magic-byte 검증) | server action | 앱 네이티브 프레임 추출 후 Storage 직접 업로드(정책 동일); 서버 검증은 없음 |
| `submitShortformUpload[FromApp]Action`(finalize·보상 삭제) | server action, 직접 INSERT/UPDATE | 앱 직접 INSERT(`sf_insert_mentor`)·UPDATE(`sf_update_own`) + `create_idempotency_key`; 또는 새 `api_app_v1.shortform_post_create/update` wrapper(권장: 마스킹·게이트·멱등 공용화) |
| `POST /api/app-session/bootstrap`, `/app/**` | WebView 전용(쿠키 세션) | 네이티브 작성 시 불필요 |
| `GET /api/community/posts`, `POST /api/community/board/view` | 뷰·RPC 의 얇은 래퍼 | 앱은 `community_posts_v1` 뷰·`community_post_view_record_v2` 직접(이미 사용) |
| `GET /api/cron/notification-outbox` | 서버 배치(service_role) | 해당 없음(수신만) |
| `loadDisputeById(adminBypassClient)` | admin 전용 | 당사자 RLS 조회로 충분 |
| 웹 `assertAccountActive`·연락처 마스킹·차단 JS 필터 | Next 서버 코드 | 마스킹/게이트는 RPC 로 서버화 or 트리거 보강; 차단 필터는 앱이 이미 클라에서 수행 |
| `notificationDeepLink.ts` `metadata.link` 라우팅 | 웹 URL 체계 | 앱은 metadata id 키 유지(`room_id/thread_id/question_id/post_id/shortform_id/mentor_id`) — producer 가 id 를 항상 싣는지 유형별 확인 (확인 필요) |
| `soft_delete_own_content` vs `community_comment_soft_delete_self` | 둘 다 사용 가능(GRANT authenticated) | 앱 manifest 에 `soft_delete_own_content` 추가 후 통일(196 헤더 27행: 앱 트랙 별도) |
| `api_app_v1` 스키마 | USAGE authenticated 만·anon 불가(`…api_app_v1_surface.sql` 헤더) | 비로그인 읽기는 `api_web_v1` 뷰 유지(앱 N4 주석 `community_read_repository.dart:65-67`); Data API 노출 상태(D-API-A) (확인 필요) |

---

## 부록 A — 앱 매니페스트 대비 추가가 필요한 표면(안)

- RPC: `soft_delete_own_content`(댓글/숏폼 본인 삭제 통일), `register_device_token`(푸시), 신설 `refund_request_self`(환불), (선택) `api_app_v1.shortform_post_create/update`.
- 테이블/뷰: `app_notices`(공지), `disputes`/`refunds`/`payments`/`subscriptions`/`custom_request_orders`/`order_payments`(분쟁 상세 — RLS 는 기존), `device_tokens`(철회 UPDATE), `community_post_view_events` 접근 없음(RPC 만).
- 버킷: `shortform-thumbnails`(현재 manifest 는 `shortform-videos` 만 — `outbound_api_manifest_test.dart:130-137`).

## 부록 B — 웹 자체 결함·불일치 메모(후속 설계 참고)

1. 게시판 키셋 커서가 `created_at` 단독(`communityBoardQueries.ts:229-233`) — 동시각 행 누락 가능.
2. `/settings/blocks` 가 `users` 를 직접 조회해 닉네임을 붙이지만 `users` SELECT 정책이 본인+admin 이라 타인 행 0건 → "회원" 폴백 가능성(`20260807020000_my_blocked_users_rpc.sql:7-8`) (확인 필요). `my_blocked_users()` 로 교체 대상.
3. F6 `community_post_soft_delete` 가 `deleted_by` 를 남기지 않음(part2:80-82) — 관리자 `작성자 삭제` 배지 기준(`deleted_by=author_id`)과 불일치 (확인 필요).
4. 해시태그 집계 경로 사장(§2.5).
5. 알림 UI 카테고리 ≠ DB 발송 그룹(§6.3), `question_received` 카테고리 누락, `notice` producer 부재(§5).
6. 신고 사유 어휘 웹(한글)/앱(영문 코드) 불일치(§4.1).
7. 숏폼 서명 URL TTL 7일(`signedStorageUrl.ts:3`) vs 게시판 이미지 1h — 캐시/재검증 정책 상이.
8. 숏폼 상세 SSR 마다 `shortform_view_record_v2` 호출(시간버킷으로 접히나 프리페치·재검증 포함).
