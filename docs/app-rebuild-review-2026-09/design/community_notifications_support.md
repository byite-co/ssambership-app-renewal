# Phase 2 설계 — 커뮤니티 · 공지 · 알림 · 지원 정합(parity)

> 대상: 웹 `/home/user/ssambership_web`(DB 정본) ↔ 앱 `/home/user/ssambership-app`(Flutter, 같은 Supabase). 기준일 2026-09-03.
> 성격: 설계 문서(저장소 무수정). 프론트 구조·서버 표면(RPC/RLS/Storage/Realtime)·DB 관점만 — UI 디자인 불포함.
> 표기: 경로는 각 저장소 루트 기준(웹은 `web:` 접두 생략 시 문맥으로 구분, 앱 파일은 `lib/...`). `(확인 필요)` = 코드로 확정하지 못한 항목. 라이브 DB 카탈로그는 직접 조회하지 않았다 — 마이그레이션 pack + `docs/audit/remote_db_inventory_20260804/*` + `docs/sprint-push/PUSH-APPLY.md` 로 재구성.

---

## 1. 범위·전제

### 1.1 담당 범위

| 영역 | 포함 기능 |
|---|---|
| 게시판 | 목록·정렬·페이징, 작성/임시저장/수정(`p_expected_updated_at`)/본인 삭제, 이미지, 댓글 2-depth·`author_label`, 반응, 조회수 v2, 해시태그, 소프트 삭제 RPC 전환(DB-2/DB-3 대조) |
| 숏폼 | 목록·카테고리·정렬, 상세·재생·썸네일, 작성(WebView 브릿지 vs 네이티브 업로드+finalize), 댓글·반응·본인 삭제, 조회수 v2 |
| 신고·차단 | `content_reports`(사유 세트·target 검증·멱등), `user_blocks`, 내 신고 내역 |
| 공지 | `app_notices`(`target`·`display_mode`), `promotion_campaigns` |
| 알림 | 18종 유형·딥링크 정밀도, `notification_settings` groups, unread/읽음 RPC, Realtime, **OS 푸시 재도입**(FCM 수신·`register_device_token`·철회·outbox worker 계약·Data Safety) |
| 지원 | 분쟁 목록/상세(학생·멘토), 내 신고 내역, 환불 신청(결제 경계 판정), 고객지원/약관(웹 위임 vs 앱 내 렌더) |

### 1.2 전제(사실)

1. **DB 정본은 웹 저장소 pack** — 앱 저장소에 SQL 없음(`ssambership-app/supabase/SCHEMA_SOURCE_OF_TRUTH.md`). 새 서버 객체는 `supabase/baseline/post_ledger_backfills/<version>_<name>.sql` 등재 → `build_native_migration_pack.py` 재생성 → `db-apply-pending` 경로(웹 `CLAUDE.md` "마이그레이션 hotfix 역수입 규칙").
2. **앱 호출 가능 표면** = Data API 노출 스키마(`public`·`api_web_v1`·`api_app_v1`) 중 `authenticated`(비로그인은 `anon`) EXECUTE/SELECT 보유 객체. `core_private`·`rls_private` 는 도달 불가. `api_app_v1` 는 `authenticated` 만 USAGE(`supabase/migrations/20260731114120_20260730112525_api_app_v1_surface.sql:85-88`) → 비로그인 읽기는 `api_web_v1` 뷰 유지(`lib/features/community/data/community_read_repository.dart:65-67` N4 주석).
3. **앱 표면 잠금**: `test/contracts/outbound_api_manifest_test.dart` 가 RPC·테이블·스키마·버킷 집합을 정확 일치로 고정(`:15-149`), `'firebase'` 문자열 0건 강제(`:321-326`). 본 설계의 모든 앱 추가는 이 매니페스트 갱신을 동반한다(§4.6).
4. **결제 제외**: `docs/policy/app-web-payment-separation.md` §1·§3·§4 — 자금 이동 RPC 는 전부 service_role(DB 표면 리포트 §4). 본 도메인에서 결제 인접은 **환불 신청**(§3 경계표 "원칙 ❌ — 신청서가 결제 유도 없이 성립하면 추후 재검토", `:19`)과 `subscription_renewal_failed_insufficient_cash` 알림의 `/wallet/charge` 링크뿐.
5. **DB-2/DB-3(2026-09-03) 정본**: 소프트 삭제 컬럼 `deleted_at/deleted_by`(`supabase/sql/194_community_soft_delete_deleted_at.sql`), 작성자 본인 삭제 단일 RPC `soft_delete_own_content(p_kind, p_id) returns void`(`196`), 하드 DELETE 차단 트리거(`198`). 앱 현행 경로와의 대조 판정은 §2 #7·#12·#23 및 §3(c).
6. 맞춤의뢰(CR) 도메인은 별도 에이전트 담당. 분쟁(`disputes`)은 `dispute_ins` 가 `custom_request_order_id is not null` 을 강제(`supabase/sql/036_p1_prelaunch_rls_tightening.sql:56-71`)하는 **CR 주문 전용** 객체이므로, 본 문서는 분쟁 "열람" 만 다루고 제기·처리는 CR 도메인 경계로 표시한다.

---

## 2. 갭 매트릭스

분류: **포함**(앱 네이티브 구현) / **웹 위임**(외부 브라우저·WebView) / **제외** / **오너 결정**(권고는 §7).

| # | 웹 기능 | 웹 라우트 | 앱 현재 | 앱 목표 | 근거 |
|---|---|---|---|---|---|
| 1 | 게시판 목록(카테고리 5종) | `/community/board` | 있음 — `api_web_v1.community_posts_v1` published·category·`created_at desc`·range | **포함**(기존) | `lib/features/community/data/community_read_repository.dart:70-86`; 카테고리 정본 `lib/community/communityBoardConstants.ts:1-8` ↔ `lib/features/community/data/community_labels.dart` 일치 |
| 2 | 정렬 탭 all/latest/**popular** + 홈 인기글(like_count desc) | `/community/board?tab=` · `/community` | latest 만 | **포함** — 뷰에 `like_count/view_count/comment_count` 있음 → `order(like_count desc).order(view_count desc).order(comment_count desc).order(created_at desc)` 오프셋 | 웹 `lib/community/communityBoardQueries.ts:213-217, 252-254, 271-276` |
| 3 | 목록 페이징 | 동일 | offset(`range`) + 차단 필터 후 `rawCount` 전진 | **포함(개선)** — latest 는 keyset `(created_at, id)` 복합 커서(`or(created_at.lt.X,and(created_at.eq.X,id.lt.Y))`), popular 는 오프셋 유지 | 웹은 `lt(created_at)` 단독으로 동시각 누락 가능(`communityBoardQueries.ts:229-233`) — 앱은 알림 커서 패턴(`lib/features/notifications/data/notifications_repository.dart:83-85`) 재사용 |
| 4 | 글 작성(학생·멘토 active) | `/community/new` | 있음 — `api_app_v1.community_post_create`(published 고정) | **포함**(기존) | `lib/features/community/data/board_post_create_gateway.dart:26-33`; 자격 규칙 S3-C(`20260802054930…:346-356` ROLE_NOT_ALLOWED) |
| 5 | **임시저장(draft)** 작성·목록·이어쓰기 | `/community/new`(draft) · `/community/me?tab=drafts` | 없음 | **포함** — 같은 wrapper `p_status='draft'`, 수정 시 `p_status` 로 발행 전환; 목록은 뷰 본인 행(`status='draft'`) | wrapper 시그니처 `20260731114120…:192-211`; 뷰 본인 행 status 무관 노출(`20260806200500_community_posts_select_deleted_filter.sql:39-45`) |
| 6 | 글 수정(낙관 충돌) | `/community/board/[id]/edit` | 있음 — `community_post_update(p_expected_updated_at)` UPDATE_CONFLICT | **포함**(기존) | `lib/features/community/data/board_post_update_gateway.dart`; `community_write_repository.dart:379-381` |
| 7 | 글 본인 삭제 | 상세 | 있음 — `api_app_v1.community_post_soft_delete`(F6) | **포함**(유지) — F6 는 `deleted_by` 미기록·hidden 글도 삭제, 196 `board_post` 는 `deleted_by` 기록·hidden 은 `CONTENT_MODERATED`. 경로 선택은 §7-D | F6 impl `20260731113927…:382-405`(deleted_at 만); 196 헤더 "게시판 글의 기존 F6 … 그대로"; 앱 `community_write_repository.dart:229-242` |
| 8 | 이미지 ≤5(ref·5MB·MIME 4) | 작성/수정 | 있음 — `community-post-images/{uid}/…` | **포함**(기존) | `lib/features/community/data/board_post_media_gateway.dart`; 서버 검증 `core_private.community_image_refs_validate` |
| 9 | 조회수 v2 | `POST /api/community/board/view` | 있음 — `community_post_view_record_v2(uuid v4)` 직접 | **포함**(기존) | `community_write_repository.dart:101-116`; `20260806033556…:12-60` |
| 10 | 댓글 작성(`comments` 직접 INSERT) | 상세 | 있음 — `{post_id, author_id, content[, parent_id]}` 평면 | **포함**(기존) | `community_write_repository.dart:177-189`; 라벨은 서버 트리거(`20260731100540…comments_author_label_denormalize.sql`) |
| 11 | **답글 2-depth** | 상세 | 없음(모델에 `parentId` 만, UI 평면) | **포함** — INSERT 에 `parent_id`, 읽기 뷰 `community_comments_v1` 트리 조립(부모가 top 이 아니면 top 승격 — 웹과 동일) | 앱 `community_models.dart` CommunityComment.parentId 주석; 웹 트리 조립 `communityBoardQueries.ts:436-458`; 깊이 초과는 `comments_write_guard` `COMMENT_DEPTH_EXCEEDED`(194:584-) |
| 12 | **게시판 댓글 본인 삭제** | 상세 | 없음 | **포함** — `soft_delete_own_content('board_comment', id)` | 198 §0 표(`supabase/sql/198_ugc_block_hard_delete.sql:7-16`) "앱: 없음"; RPC GRANT authenticated(196 §A-2); 웹 매핑 `lib/community/softDeleteOwnContent.ts:36-42` |
| 13 | 반응 like/scrap 토글 | 상세 | 있음 — `post_reactions` insert/delete | **포함**(기존) | `community_write_repository.dart:48-68`; RLS SELECT 본인만(`20260806033409…:12-14`) |
| 14 | 내 활동(내 글·좋아요·스크랩·**임시저장**) | `/community/me` | 있음(3그룹) | **포함** — drafts 그룹 추가(뷰 본인 행 `status='draft'`) | `lib/features/community/ui/activity/my_activity_view.dart:110-112`; `community_read_repository.dart:150-200` |
| 15 | 작성자 본인 **숨김(hidden) 배지** | `/community/me` | 없음 | **포함** — 뷰가 본인 `hidden` 행을 노출(status 컬럼) → 배지. 삭제(`deleted_at`) 행은 뷰 밖이라 "삭제 배지"는 불가 | 뷰 정의 `20260806200500…:39-45` |
| 16 | 계정 게이트(정지·탈퇴 진행 중 쓰기 차단) — 댓글·반응·신고·차단 직접 INSERT | 웹 `assertAccountActive` | 없음(RPC 경로만 서버 게이트) | **포함(서버 선행)** — §3(b) S-1 트리거 | 웹 `lib/community/commentActions.ts:57-60`; 정책에 게이트 없음(`016_p0_community_comments.sql:51-60`, `037:277-280`, `032:63-66`) |
| 17 | 숏폼 목록 | `/community/shortform` | 있음 — `shortform_posts` published desc | **포함**(기존) | `community_read_repository.dart:90-104` |
| 18 | 숏폼 **카테고리 4종 필터 + 정렬(popular)** | `?category=&tab=` | 없음 | **포함** — `eq(category)`; popular = `like_count desc, view_count desc, created_at desc` | 웹 `lib/community/communityShortformQueries.ts:126-146`; 카테고리 `communityShortformConstants.ts:1-7`(DB CHECK 없음 — `002:532` `category text`, grep 0) |
| 19 | 숏폼 **썸네일 표시** | 목록·상세 | **결함** — `thumbnail_url`(QA-C15 이후 `shortform-thumbnails/{uid}/…` ref)을 `Image.network` 에 raw 전달 → 항상 플레이스홀더 | **포함** — 썸네일 서명 URL 리졸버 + 버킷 상수 `shortform-thumbnails`(manifest 추가) | 앱 `lib/features/community/ui/widgets/shortform_card.dart:35-36`, `thumbnail_view.dart:26-33`; 리졸버는 영상 버킷만(`shortform_media_url_resolver.dart` `videoBucket`); 웹 썸네일 서명 `communityShortformQueries.ts:94-120`; 정책 `sfv_public_read` 두 버킷(038:66-68) |
| 20 | 숏폼 상세·재생·조회수 v2 | `/community/shortform/[id]` | 있음 | **포함**(기존) | `shortform_view_record_v2` a,u(194:424) |
| 21 | 숏폼 좋아요(+앱 스크랩) | 상세 | 있음(like+scrap) | **포함**(기존, 웹보다 넓음) | `shortform_reactions` type CHECK like/scrap(`130_shortform_scrap_reaction.sql:13-20`) |
| 22 | 숏폼 댓글 작성(`community_comments`) | 상세 | 있음 | **포함**(기존) | `community_write_repository.dart:155-164`; INSERT 정책 016:51-60 |
| 23 | 숏폼 댓글 본인 삭제 | 상세 | 있음 — `community_comment_soft_delete_self`(jsonb 봉투) | **포함(통일)** — `soft_delete_own_content('shortform_comment')` 로 전환, 구 RPC 는 전환 완료 후 회수 여부 §7-D | 196 헤더 "기존 community_comment_soft_delete_self(앱 계약)는 그대로 둔다 — 앱은 앱 트랙에서 전환"; 앱 `comments_gateway.dart:57-66`, `community_write_repository.dart:199-218` |
| 24 | 숏폼 작성(영상 500MB·MIME 3·썸네일·draft/publish·`rightsAck`) + 임시저장·수정 | `/community/shortform/new` · 앱 `/app/community/shortform/new` | WebView 브릿지(`POST /api/app-session/bootstrap` → 작성 표면 → 완료 브릿지) | **오너 결정**(§7-A) — 권고: 1차 WebView 유지, 네이티브는 `api_app_v1.shortform_post_create/update` 신설 후 | 앱 `lib/features/community/ui/shortform/shortform_compose_screen.dart:14-23`, `lib/core/web_bridge/shortform_compose_bridge.dart:20-26`; 웹 finalize `lib/community/communityShortformActions.ts:91-255`; `docs/RELEASE_SCOPE_DECISIONS_2026-07.md:22-30` |
| 25 | 숏폼 본인 삭제 | (웹 UI 없음) | 없음 | **오너 결정**(§7-E) — RPC `soft_delete_own_content('shortform')` 준비됨, 웹 parity 밖 | `lib/community/softDeleteOwnContent.ts:9`; 198 §0 표 |
| 26 | 신고(글·숏폼) | 상세 `ReportDialog` | 있음(+댓글·사용자) | **포함**(기존, 앱이 넓음) | 앱 target_type `community_post/board_comment/shortform_post/community_comment/user`(`board_detail_screen.dart:228,312`, `shortform_detail_screen.dart:291,307`, `room_safety_repository.dart:73-75`); 정책 allowlist `20260806075316…:31-43` |
| 27 | 신고 사유 세트 | — | 영문 코드 5종 `inappropriate/spam/external_contact/copyright/etc` | **오너 결정**(§7-F) — 웹 한글 5종과 불일치, DB 제약 없음 → 정본 어휘 확정 후 양측 정합 | 웹 `components/reports/ReportDialog.tsx:10`, `lib/community/communityReportActions.ts:11-17,60`; 앱 `lib/features/community/ui/widgets/report_sheet.dart:9-15`; 컬럼 `reason text null`(032:17) |
| 28 | 신고 멱등(open 중 동일 키 → description 갱신) | 서버 트리거 | 있음(서버) | **포함**(기존) | `20260806201000_content_reports_idempotent_open.sql:44-111` — 키에 `reason` 포함 → 어휘 불일치 시 웹/앱 중복 접수(#27 의존) |
| 29 | **내 신고 내역** | `/support/reports` | 없음 | **포함** — `content_reports` 본인 SELECT(`reporter_id = uid`), 상태 라벨 5종 | 웹 `lib/support/studentReportsQueries.ts:26-58`; RLS `content_reports_select_reporter`(032:56-60); 테이블은 manifest 에 이미 있음 |
| 30 | 차단/해제/목록 | `/settings/blocks` | 있음(`my_blocked_users` RPC) | **포함**(기존) | `lib/features/community/data/user_blocks_repository.dart:134-153`, `ui/blocks/blocked_users_screen.dart` |
| 31 | 댓글 작성자 차단 | (웹 없음) | 있음 | **포함**(기존, 앱이 넓음) | `comment_tile.dart:10-24` onBlock |
| 32 | 공지 목록 | `/notices` | 없음 | **포함** — `app_notices` SELECT `id,title,body,type,target,display_mode,starts_at,ends_at,created_at` where `is_active`; `target`(NULL/all/student/mentor) 은 역할 클라 필터 | RLS `app_notices_select` 기간 강제(031:88-102); GRANT anon/authenticated SELECT(`docs/audit/remote_db_inventory_20260804/grants_tables.json:257-285`); 웹 조회 `lib/notices/publicNoticesQueries.ts:54-59`(target 미필터) |
| 33 | 공지 **팝업**(`display_mode='popup'`) | 웹 미마운트(PR-10b) | 없음 | **오너 결정**(§7-G) — 앱 홈 상단 배너(1회 닫기·prefs) vs 모달 vs 웹과 동시 도입 | `20260830140804_add_display_mode_to_app_notices.sql`; `lib/admin/noticeConsole.ts:83-97` "팝업 노출은 서비스 반영 후 적용" |
| 34 | `promotion_campaigns` 노출 | (웹 공개 소비자 없음) | 없음 | **제외** — 웹도 미소비 | `lib/subscribe/subscribePageQueries.ts:82-85` 스텁 제거; RLS 는 공개(031 `promotion_campaigns_select`) — 도입 시 #32 와 같은 방식 |
| 35 | 공지 → 알림(`type='notice'`) | — | 없음 | **제외** — producer 없음 | 웹 카테고리에 `notice` 등재(`lib/notifications/notificationCategories.ts:44`)되나 `record_domain_notification(… 'notice')` 0건 |
| 36 | 알림 목록·키셋·읽음·모두읽음·unread·Realtime | `/notifications` | 있음(웹보다 넓음 — Realtime·unread RPC) | **포함**(기존) | `notifications_repository.dart:118-178`; `notifications_realtime.dart:47-55`; `notification_unread_count_self`(`20260803171053…:221-249`) |
| 37 | 알림 카테고리 탭(웹 6 · qna/order/subscription/refund/system) | `?category=` | 4 kind(질문방/구독·결제/개별질문/맞춤의뢰 게이트) | **포함(정합)** — kind 테이블에 `refund` 추가(`individual_question_expired_refunded`, `mentor_termination_refund`), `question_received` 는 이미 questionRoom(웹은 누락) | 앱 `lib/features/notifications/data/notification_types.dart` `notificationKindOf`; 웹 `notificationCategories.ts:26-45`; DB 발송 그룹 `notification_event_group`(152) 은 `individual_question%`→`order` — 표시 분류와 별개(앱 설정 라벨 `'order': '개별질문 알림'` 은 DB 의미와 일치 `notification_settings_repository.dart:32-38`) |
| 38 | 딥링크 정밀도(탭 → 스레드/글/주문 ID) | `resolveNotificationHref`(`metadata.link` 우선) | 부분 — `room_id/thread_id/question_id/mentor_id` UUID 검증 후 상세; 구독류 → 마이페이지 push; link 무시(의도) | **포함(보강)** — (a) `mentor_termination_refund` → 환불 내역(#42 포함 시) / 아니면 마이페이지 (b) 구독류에 `subscription_id` 전달(마이페이지 구독 섹션 하이라이트) (c) CR 2종은 CR 도메인 도입 시 `order_id/post_id` 라우트 (d) **푸시 탭은 `notification_id` 로 행을 재조회해 인앱 라우터 재사용**(§4.3) | producer metadata: qna `room_id/thread_id`(`20260801040844…:119-141`, `20260805170000…:86-95`), IQ `question_id`(155:36-86), 구독 `subscription_id`(157:73-168), 멘토 `mentor_id/subscription_id/refund_id`(158:38-125), CR `post_id/application_id`·`order_id/message_id`(159:28-76); 앱 판정 `lib/core/deeplink/notification_deep_link_controller.dart:122-155`; opener `lib/features/notifications/ui/notification_target_opener.dart:36-56`. 커뮤니티 글/숏폼 알림 producer 는 **없음** → 앱 `post_id/shortform_id` 경로는 휴면 |
| 39 | 알림 설정(푸시 전역 + 그룹 5) | `/settings/notifications` | 있음 | **포함**(기존) — 매니페스트에 `notification_settings` 명시 등재 권장 | `notification_settings_repository.dart`; 152:59-72 |
| 40 | **OS 푸시**(FCM 수신·토큰 등록/철회·권한) | 워커 `GET /api/cron/notification-outbox`(플래그 OFF 배포) | 없음(App-F0) — `DisabledPushPermission` 만 | **오너 결정**(§7-B) — 권고: 재도입(서버 GRANT 는 이미 라이브 적용) | `lib/core/push/HANDOFF.md`(재도입 6항); `docs/sprint-push/PUSH-APPLY.md:1-45`(2026-08-27 GRANT 적용·원장 93→94 · `register_device_token` EXECUTE authenticated 실측); `docs/plans/push-outbox-worker.md:24-34` 활성 순서 |
| 41 | 분쟁 목록/상세(학생·멘토, 읽기) | `/support/disputes[/id]`, `/mentor/support/disputes[/id]` | 없음 | **오너 결정**(§7-H) — CR 도메인 포함 여부에 종속. 포함 시 RLS 당사자 읽기로 충분(새 객체 0) | `dispute_select`(004:195-199); 상세 번들 `lib/disputes/disputeQueries.ts:22-110`(`order_payments`→`payments` 단건, `refunds` 공유키, `admin_action_logs` 는 admin RLS → 0건) |
| 42 | **환불 신청**(구독 잔여기간·학원법 별표4) | `/support/refunds` | 없음 | **오너 결정**(§7-C) — 포함 시 **새 SECURITY DEFINER RPC 필수**(`refund_ins` admin 전용) | `supabase/sql/021_p0_refund_ins_admin_only.sql:6-8`; 웹 액션 service_role INSERT `lib/subscribe/subscriptionCancelActions.ts:168-260`; 정책 §3 "원칙 ❌ … 추후 재검토"; DB 표면 리포트 §4 #7 [모호] |
| 43 | 분쟁 제기(주문방) | `/custom-request/orders/[id]` | 없음(CR 표면 0) | **웹 위임 / CR 도메인 경계** — `dispute_ins` 당사자 INSERT 는 열려 있으나 진입점이 CR 주문방 | `lib/customRequest/orderDisputeActions.ts:53-68`; 036:56-71 |
| 44 | 고객센터 FAQ | `/support` | 웹 열기(`openSupportWeb`) | **웹 위임**(조건) — 웹 `/support` 에 `/wallet/charge`·`/subscribe` 링크가 있어 정책 §4 "웹 결제 URL 유도" 회색지대 → `?src=app` 시 결제 링크 비노출 또는 앱 정적 FAQ(§7-I) | `app/(public)/support/page.tsx:16,33`; 앱 `lib/core/web_bridge/web_bridge_config.dart:32-36`, `web_bridge.dart`(`src=app` 쿼리) |
| 45 | 약관·개인정보처리방침(법적 문서 10종) | `/legal/*` | 웹 열기 | **웹 위임**(권고) — 문서가 정적 TSX(`COMPANY` 상수 조립)이고 DB 테이블 없음 → 앱 내 렌더는 본문 중복 관리 필요(§7-J) | `app/(public)/legal/terms/page.tsx:1-13`; `lib/legal/companyInfo.ts`; `legal_documents` 류 테이블 grep 0 |
| 46 | 분쟁 처리 이력(`admin_action_logs`) | 분쟁 상세 하단 | 없음 | **제외** — admin RLS 로 당사자 0건(웹도 빈 목록) | `lib/disputes/disputeQueries.ts:85-106` |
| 47 | 해시태그(`community_hashtags`) | 사이드바 | 없음 | **제외** — 웹 자체가 `hashtags '{}'` 고정으로 사장 | `037:75-127` 트리거; F4 `…community_rpc.sql:222-230` |
| 48 | 댓글 좋아요(`comments.like_count`) | — | 없음 | **제외** — 웹·앱 어디에도 토글 표면 없음(전용 테이블 부재) | 웹 리포트 §2.3 |
| 49 | 댓글 연락처 마스킹 | 웹 클라 `sanitizeTrustSafetyText` | 없음 | **오너 결정**(§7-K) — 서버 트리거(`comments`·`community_comments` BEFORE INSERT)로 정본화 vs 앱 클라 마스킹 이식 | 웹 `lib/community/commentActions.ts:48`; 게시글은 RPC 가 SQL 마스킹(`…community_rpc.sql:200-213`); 댓글 트리거 없음(194 가드는 보호 컬럼·깊이만) |
| 50 | 레거시 redirect 스텁·`GET /api/community/posts`·`POST /api/community/board/view` | — | — | **제외** — 뷰·RPC 직접 사용 | 웹 리포트 §1.3 |

집계(50행): **포함 33**(#1–#16, #17–#23, #26, #28–#32, #36–#39) · **웹 위임 3**(#43·#44·#45) · **제외 6**(#34·#35·#46·#47·#48·#50) · **오너 결정 8**(#24·#25·#27·#33·#40·#41·#42·#49).

---

## 3. 서버 표면 설계

### (a) 기존 그대로 사용 가능한 객체

| 객체 | 용도 | 권한·근거 |
|---|---|---|
| `api_web_v1.community_posts_v1` / `api_web_v1.community_comments_v1` | 게시판·댓글 읽기(비로그인 포함), draft/hidden 본인 행 | SELECT a,u,s; 194:365-377(댓글 뷰 `deleted_at IS NULL`) |
| `api_app_v1.community_post_create/update/soft_delete` | 작성(draft 포함)·수정·글 삭제 | EXECUTE authenticated(`20260731114120…:253-261`) |
| `public.soft_delete_own_content(p_kind text, p_id uuid) returns void` | 게시판 댓글·숏폼 댓글·(숏폼·글) 본인 삭제 단일 경로 | authenticated, service_role(196 §A-2). 예외 코드: `AUTH_REQUIRED`(28000) · `INVALID_KIND`(22023) · `CONTENT_NOT_FOUND`(P0001) · `CONTENT_KIND_MISMATCH`(22023) · `CONTENT_NOT_OWNED`(42501) · `CONTENT_MODERATED`(42501) · `ACCOUNT_BANNED/SUSPENDED/NOT_ACTIVE/DELETION_IN_PROGRESS`; 멱등(이미 삭제면 정상 반환) |
| `public.community_comment_soft_delete_self(uuid) returns jsonb` | (전환 전) 숏폼 댓글 삭제 | authenticated 만(194:485-536 재정의 — `deleted_at/deleted_by` 기록) |
| `comments` INSERT(`comments_insert_own`) / `community_comments` INSERT(`community_comments_insert_authenticated`) | 댓글·답글 | 037:251-265 · 016:51-60; `comments_write_guard` 가 보호 컬럼·`legacy_comment_id`·깊이 초과 거부(194:584-) |
| `post_reactions` · `shortform_reactions` INSERT/DELETE | 반응 | 037:277-285 · 082:65-80 (하드 DELETE 허용 표 — 198 대상 아님) |
| `community_post_view_record_v2` · `shortform_view_record_v2` | 조회수 | a,u(`20260806033556…`, 194:424-457) |
| `content_reports` INSERT(정책 + `content_reports_dedupe_open` 트리거) · SELECT 본인 | 신고·내 신고 내역 | `20260806075316…:31-43`; 032:56-60 |
| `user_blocks` CRUD 본인 · `my_blocked_users()` | 차단 | 116:28-50; `20260807020000…:27-53` |
| `app_notices` SELECT | 공지 목록·팝업 | RLS 031:88-102; GRANT anon/authenticated(grants_tables.json:257-285) |
| `notifications` SELECT/UPDATE 본인 · `mark_notification_read` · `mark_all_notifications_read` · `notification_unread_count_self` · Realtime publication | 알림 | `20260803171053…:97-130, 182-249`; publication 7종(§3.2 DB 리포트) |
| `notification_settings` SELECT/INSERT/UPDATE 본인 | 알림 설정 | 152:59-72 |
| `register_device_token(p_token text, p_platform text default 'unknown') returns jsonb {ok, device_token_id}` | 푸시 토큰 등록(재소유 내장) | **authenticated EXECUTE 라이브 적용 완료**(`docs/sprint-push/PUSH-APPLY.md` §2 — 2026-08-27, 원장 `20260827100100`). 마이그레이션 파일 헤더(`20260827100100_device_token_register_grant.sql:1-3`)의 "라이브 미적용" 문구와 phase-1 리포트의 "미적용" 판정은 **구식** (확인 필요: 라이브 `routine_privileges` 재조회로 최종 확정) |
| `device_tokens` UPDATE 본인(`device_tokens_modify_own`) | 로그아웃 시 `revoked_at` 철회 | 152:24-30; `revoke_device_token` 은 service_role 전용 유지 |
| `disputes` SELECT 당사자 · `refunds` SELECT 본인 · `payments_select_own` · `order_payments`(`opay_select`) · `custom_request_orders`(`cro_select`) · `subscriptions` · `subscription_billing_events_select_parties` | 분쟁 상세 번들·환불 신청 화면 읽기 | 004:195-199·214-217; 027:37-41; 003:413-424, 462-477; 064:176-187 |
| `api_web_v1.my_subscriptions_self()` | 환불 신청 대상 구독 목록(`subscription_id, mentor_label, plan_tier, current_period_start/end, status`) | u,s(DB 리포트 §1.3 V6) |

### (b) 새로 필요한 서버 객체

모든 신설은 웹 pack 절차(§1.2-1) · `api_app_v1` 얇은 SECDEF wrapper(`auth.uid()` 도출) → `core_private` INVOKER impl 패턴(`20260731114120…:192-251`) · 오류 envelope `{ok:false, code, contract_version:1}`(예외 전파는 계약 밖 오류만) · GRANT 블록 `REVOKE ALL … FROM PUBLIC, anon; GRANT EXECUTE … TO authenticated`(`api_app_v1` 는 service_role 미부여가 설계) · impl 은 외부 EXECUTE 0.

#### S-1. UGC 직접 INSERT 계정 게이트 트리거 — **포함(선행)**

- 대상: `public.comments`, `public.community_comments`, `public.post_reactions`, `public.shortform_reactions`, `public.content_reports`, `public.user_blocks` BEFORE INSERT.
- 함수: `public.ugc_account_gate() returns trigger` — **SECURITY INVOKER 필수**(194/198 가드와 같이 `current_user` 가 클라이언트 역할이어야 함), `set search_path = ''`.
  ```sql
  if current_user not in ('anon','authenticated') then return new; end if;   -- service_role/postgres/트리거 미러 통과
  if (select auth.uid()) is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  -- users 본인 행(RLS 본인 SELECT 허용) → banned / 유효 suspended / 미지 status / deletion_write_blocked
  raise exception 'ACCOUNT_BANNED' | 'ACCOUNT_SUSPENDED' | 'ACCOUNT_NOT_ACTIVE' | 'ACCOUNT_DELETION_IN_PROGRESS';
  ```
  판정식은 `community_comment_soft_delete_self`(194:507-514)·`soft_delete_own_content` 와 동일(positive allowlist). 대안: `public.ugc_write_allowed()`(u,s · `20260802054930…:295-314`) 를 부르고 `ACCOUNT_NOT_ACTIVE` 단일 코드 — 코드 세분화가 필요하면 위 방식.
- 트리거 이름 `trg_<table>_account_gate`(이름순으로 기존 `trg_comments_write_guard` 앞에 발화). GRANT: `revoke all on function public.ugc_account_gate() from public, anon, authenticated`.
- 영향: 웹 서버 액션이 이미 `assertAccountActive` 로 거르므로 웹 무영향; 앱은 `PostgrestException.message` 선두 코드 → 기존 `ACCOUNT_*` 매퍼(`community_write_repository.dart:257-310`) 재사용.
- 사전 게이트(194 스타일): 여섯 표 존재·트리거 부재 확인. 롤백 파일: 트리거 6 + 함수 drop.

#### S-2. 숏폼 네이티브 작성 RPC — **오너 결정 A 가 "네이티브" 일 때만**

- `api_app_v1.shortform_post_create(p_idempotency_key uuid, p_video_ref text, p_thumbnail_ref text, p_title text, p_body text, p_category text, p_status text default 'published', p_rights_ack boolean default false) returns jsonb`
  → `core_private.shortform_post_create_impl(p_author_id uuid, …)`.
- `api_app_v1.shortform_post_update(p_post_id uuid, p_video_ref text, p_thumbnail_ref text, p_title text, p_body text, p_category text, p_status text, p_rights_ack boolean, p_expected_updated_at timestamptz) returns jsonb` → impl.
- impl 판정 순서(웹 `submitShortformUploadCore` 이식, `communityShortformActions.ts:91-255`): 계정 게이트(positive allowlist) → `users.role='mentor'`(웹 페이지 게이트와 동일; 승인 여부는 `is_mentor()` 와 같이 미검사 — 승인 강제 여부 §7-A) → replay-first 멱등 `(author_id, create_idempotency_key)`(UNIQUE `shortform_posts_author_idem_key`, 148:14-15) → `TITLE_REQUIRED`(≤100) · `BODY_TOO_LONG`(≤500) · `CATEGORY_INVALID`(4종 — DB CHECK 부재를 impl 이 대신) · `RIGHTS_ACK_REQUIRED`(published) · `RESTRICTED_PHRASE`(웹 `findRestrictedPhraseInText` 목록 이식) → ref 검증: `shortform-videos/{uid}/…` 접두·`storage.objects` 실존·`owner_id = uid`·MIME ∈ {mp4, quicktime, webm}·size ≤ 524288000 → `VIDEO_REF_INVALID | VIDEO_OBJECT_NOT_FOUND | VIDEO_OBJECT_NOT_OWNED | VIDEO_MIME_NOT_ALLOWED | VIDEO_SIZE_EXCEEDED`(썸네일은 `THUMBNAIL_REF_INVALID` 시 NULL 로 강등 — 웹과 동일 "발행 비차단") → 마스킹(게시글 impl 의 SQL 마스킹식 재사용 — 공용 함수 추출 `core_private.mask_contact_text(text)` 권장 (확인 필요: 현재 인라인)) → `author_label` 서버 산출(`users.nickname` → 마스킹 `full_name` → 브랜드 라벨; 웹 `authorStoredLabelFromProfile` `lib/community/communityAuthorLabels.ts:36-44`) → INSERT `{author_id, creator_id, title, body, category, video_url, thumbnail_url, tags '{}', status, author_role 'mentor', author_label, create_idempotency_key}`.
- update: 소유 행 `FOR UPDATE` + `deleted_at IS NULL` → `POST_NOT_FOUND_OR_NOT_OWNED`; `updated_at IS DISTINCT FROM p_expected_updated_at` → `UPDATE_CONFLICT`; status 전이는 `shortform_posts_protected_guard` 규칙(draft↔published 만, hidden 불가 — 194:538-583) 을 impl 에서 선검사 `STATUS_TRANSITION_INVALID`; 교체된 구 video/thumbnail ref 를 `removed_refs[]` 로 반환(게시판 F5 `removed_image_refs` 패턴) — 앱이 커밋 후 Storage 정리(`sfv_mentor_delete_own`).
- 반환: `{ok:true, contract_version:1, post_id, status, idempotent_replay}` / update `{ok:true, post_id, updated_at, removed_refs}`.
- GRANT: wrapper 2종 authenticated; impl 외부 0. 사전 게이트: `shortform_posts` 컬럼(`create_idempotency_key`, `author_label`, `deleted_at`) 존재.
- Storage 업로드는 RPC 무관 — RLS `sfv_mentor_insert`(`is_mentor()` ∧ 본인 폴더 ∧ `NOT account_deletion_write_blocked`, baseline 19840-19847) 로 앱 세션 직접 `uploadBinary`(owner_id 채워짐 — service_role 업로드 함정 회피, DB 리포트 §3.1 주의).

#### S-3. 구독 잔여기간 환불 신청 self RPC — **오너 결정 C 가 "포함" 일 때만**

- `api_app_v1.refund_estimate_subscription_self(p_subscription_id uuid) returns jsonb` — 읽기 전용 미리보기 `{ok, contract_version:1, amount_cents, bracket_reason, remaining_days, total_days, usage_started, can_request, pending_refund_id}`.
- `api_app_v1.refund_request_subscription_self(p_subscription_id uuid, p_reason text) returns jsonb` → `core_private.refund_request_subscription_impl(p_student_id uuid, p_subscription_id uuid, p_reason text, p_dry_run boolean)`(두 wrapper 가 같은 impl 을 `p_dry_run` 로 공유).
- impl(웹 `requestSubscriptionProratedRefundAction` `subscriptionCancelActions.ts:168-260` + `computeProratedRefundEstimate` `subscriptionRefundProration.ts:45-140` + `hasSubscriptionUsageStartedForPair` `subscriptionUsageStarted.ts:12-56` 의 SQL 이식):
  1. 계정 게이트 → `users.role='student'` 아니면 `ROLE_NOT_STUDENT`.
  2. `p_reason` trim 길이 < 5 → `REASON_TOO_SHORT`.
  3. `pg_advisory_xact_lock(hashtext('refund_request:' || p_subscription_id::text))` — 웹의 lookup→INSERT TOCTOU 창을 닫는다.
  4. `subscriptions` 행 `FOR UPDATE`, `student_id = p_student_id` 아니면 `SUBSCRIPTION_NOT_FOUND_OR_NOT_OWNED`; status ∉ 현행(active/cancel_scheduled/past_due — 웹 `isCurrentSubscriptionStatus` 정본 대조 (확인 필요)) → `SUBSCRIPTION_NOT_CURRENT`.
  5. `public.qna_subscription_has_live_refund(p_subscription_id)`(142:19-28, u) 참 → `REFUND_PENDING_EXISTS`(+ `pending_refund_id`).
  6. 최근 성공 billing event: `subscription_billing_events where subscription_id=… and status='succeeded' and event_type in ('initial','renewal') order by billing_at desc limit 1` 없으면 `BILLING_EVENT_NOT_FOUND`.
  7. period = `coalesce(sub.current_period_start, ev.period_start)` / `coalesce(sub.current_period_end, ev.period_end)`; `usage_started = exists(select 1 from question_threads qt join mentor_student_rooms r on r.id = qt.mentor_student_room_id where r.student_id = p_student_id and r.mentor_id = sub.mentor_id and qt.created_at >= period_start)`(mentor_id NULL 이면 true 보수 처리).
  8. 별표4 분기: `usage_started=false` → 전액(`before_usage`); 경과율 < 1/3 → `floor(amount*2/3)`(`lt_1_3`); < 1/2 → `floor(amount/2)`(`lt_1_2`); 그 외 0(`ge_1_2`); 입력 불량 `invalid`. 0 이면 `REFUND_AMOUNT_ZERO` + `bracket_reason`.
  9. `p_dry_run` 아니면 INSERT `refunds {user_id, amount_cents, status 'pending', payment_id = coalesce(ev.payment_id, sub.payment_id), subscription_id, billing_event_id = coalesce(ev.id, sub.last_billing_event_id), request_type 'subscription_prorated', reason}`(069:25-28 · 150:17-26 컬럼) — SECDEF 라 `refund_ins`(admin 전용) 통과.
  10. 반환 `{ok:true, contract_version:1, refund_id, amount_cents, bracket_reason}`.
- 부수효과 고지: pending 환불은 142 로 해당 구독의 새 질문·메시지·첨부를 `SUBSCRIPTION_REFUND_PENDING` 으로 거부 → 앱 질문방이 그 코드를 이미 매핑(`lib/features/question_room/data/qna_error_mapper.dart`)하지만 신청 화면에서 사전 고지 필요.
- GRANT wrapper 2종 authenticated; impl 0. 결제 경계: 캐시 차감·토스 호출 없음(관리자 승인 RPC 는 service_role 그대로). DB 표면 리포트 §6 #2 후보와 동일.

#### S-4. 신고 사유 정본화 — **오너 결정 F 후 선택**

- `alter table content_reports add constraint content_reports_reason_allowed check (reason is null or reason in (<정본 코드 집합>))` 은 기존 행(웹 한글·앱 영문 혼재)이 있으면 실패 → `NOT VALID` 로 추가 후 백필 또는 트리거로 정규화(`reason_code` 컬럼 추가가 더 안전). 최소안: 제약 없이 **양측 클라 어휘만 통일**(서버 변경 0).

#### S-5. 댓글 연락처 마스킹 트리거 — **오너 결정 K 후 선택**

- `comments`·`community_comments` BEFORE INSERT/UPDATE OF content/body 에서 `core_private.mask_contact_text()` 적용. 웹 클라 마스킹과 이중 적용은 멱등(마스킹 결과 재마스킹 무해) — 확인 필요: 웹 `maskContactInUserText` 규칙과 SQL 마스킹식(`…community_rpc.sql:200-213`)의 동치.

#### S-6. 앱 매니페스트(서버 객체 아님, 계약 갱신)

- `kExpectedRpcNames` + `soft_delete_own_content`, `register_device_token`(푸시), 조건부 `refund_request_subscription_self`·`refund_estimate_subscription_self`·`shortform_post_create`·`shortform_post_update`; 전환 완료 후 `community_comment_soft_delete_self` 제거(회수는 웹 결정 — 196 헤더 "그대로 둔다").
- `kExpectedTables` + `app_notices`, `notification_settings`(명시), `device_tokens`(철회 UPDATE), 조건부 `disputes`·`refunds`·`payments`·`order_payments`·`custom_request_orders`·`subscription_billing_events`; `content_reports` 는 SELECT 추가(이미 등재).
- `kExpectedBucketNames` + `shortform-thumbnails`(+ 새 상수 식별자).
- 금지어 유지(`increment_shortform_post_view` 등); `'firebase' 0건` 테스트와 `test/push/firebase_free_test.dart` 는 푸시 재도입 시 대체(§4.3).

### (c) 정책 공백·리스크(서버)

| # | 항목 | 사실 | 판정·대응 |
|---|---|---|---|
| R1 | `sfv_public_read` 가 두 버킷 **전체** SELECT(anon+authenticated) | `038:66-68`, baseline 4593-4595. `storage.objects` SELECT 정책은 서명 발급뿐 아니라 **`list()` 도 허용** → 비로그인이 `{uid}/` prefix 를 나열해 draft/hidden/삭제 숏폼 영상·썸네일 객체명을 얻고 서명 URL 로 재생 가능. `sf_select_published`(194:383-394) 는 행만 가린다 | 앱 네이티브 업로드 여부와 무관한 기존 공백. 대응안: SELECT 정책을 `exists(select 1 from shortform_posts p where p.status='published' and p.deleted_at is null and (p.video_url = 'shortform-videos/'||name or p.thumbnail_url = 'shortform-thumbnails/'||name)) or foldername[1]=uid` 로 좁히기(서명 발급자는 웹 service_role/앱 세션 — 앱은 published 만 재생하므로 무영향). `cpi_public_read`(XW-06) 동형. 오너 결정 대상(§7-L) |
| R2 | `thumbnail_url` NULL·형식 혼재 | QA-C15 이전 행 NULL, 이후 `shortform-thumbnails/{uid}/{uuid}-thumb.{ext}` ref, 레거시 http URL 가능(`lib/community/shortformThumbnailRef.ts`) | 앱 리졸버가 3형태 수용(영상 리졸버와 동일 규칙, `shortform_media_url_resolver.dart` `_legacyPlayableUrl` 패턴). 앱 WebView 작성 시 `<video>`+canvas 첫 프레임 추출이 Android WebView/WKWebView 에서 동작하는지 (확인 필요) — 실패 시 NULL 로 조용히 저장(웹 `:165-176`) |
| R3 | 하드 DELETE 차단 트리거(198) ↔ 앱 코드 | 앱 `.delete()` 는 `post_reactions`(`community_write_repository.dart:63`), `shortform_reactions`(`:86`), `user_blocks`(`user_blocks_repository.dart:208`), `favorites`(`mentor_favorites_repository.dart:87`), `connection_notes`(`question_room_write_repository.dart:223`) 5곳 — 차단 대상 3표(`shortform_posts`·`comments`·`community_comments`) DELETE 0 | **충돌 없음**(198 §0 판정 일치). 재구축에서도 3표 DELETE 금지 규칙을 매니페스트 테스트로 잠글 것(정규식 `from('comments'|'community_comments'|'shortform_posts')…delete(`) |
| R4 | 앱 소프트 삭제 경로 vs 최신 정본 | 숏폼 댓글 `community_comment_soft_delete_self`(194 재정의로 `deleted_at/deleted_by` 기록 — **정본과 어긋나지 않음**, 봉투 jsonb) · 게시글 F6(`deleted_by` 미기록) · 게시판 댓글 삭제 부재 | 통일 대상은 §2 #12·#23. `soft_delete_own_content` 는 `void` 반환 → 앱 봉투 파서(`{ok, contract_version}` strict) 와 형식 상이: 성공 = 예외 없음(응답 null), 실패 = `PostgrestException` 선두 코드. `raise exception` 스타일 매퍼(§3-3 (1)) 로 처리 |
| R5 | `comments` INSERT 통과성 | `comments_write_guard` 는 보호 컬럼·`legacy_comment_id`·깊이만 거부(194:584-) → 앱 payload `{post_id, author_id, content, parent_id}` 통과 예상 | (확인 필요: 라이브 실측) |
| R6 | 숏폼 `category` DB CHECK 부재 | `002:532 category text`; 038·194 CHECK 없음 | 앱 필터는 4 slug 클라 고정; 네이티브 작성 시 S-2 impl 이 검증 |
| R7 | `is_mentor()` 는 `users.role='mentor'` 만(승인 미검사) | 038:38-41 | 웹 페이지 게이트도 role 만 → parity. 승인 강제는 §7-A 부속 결정 |
| R8 | 신고 어휘 불일치 + 멱등 키에 `reason` 포함 | §2 #27·#28 | 같은 대상을 웹·앱이 신고하면 큐 중복. 어휘 통일 전에는 관리자 라벨링 (확인 필요) |
| R9 | `report_target_content_valid` 가 삭제 콘텐츠 제외(194:469-483) | 삭제된 글/댓글 신고 INSERT → RLS 42501 | 앱은 "이미 삭제된 콘텐츠" 문구로 매핑(원문 비노출) |
| R10 | `notification_unread_count_self`·앱 목록이 CR 2종을 **하드코딩 제외** | `20260803171053…:245`; 앱 `kGatedNotificationTypeCodes` | CR 도메인 포함 결정 시 **서버 RPC 재정의**가 선행(앱만 바꾸면 배지·목록 불일치) |
| R11 | `subscription_renewal_failed_insufficient_cash` 링크 `/wallet/charge`(157:81,129) | 앱은 link 무시(정본) — 다만 **본문 문구**가 충전 유도로 읽힐 수 있음 (확인 필요: 157 body 텍스트) | 푸시 재도입 시 이 유형의 OS 알림 본문이 정책 §4 "푸시로 충전 유도" 에 해당하는지 검토 → 필요 시 `notification_create_deliveries` 단계에서 유형 억제(서버) 또는 앱 `notification_settings.groups.subscription` 안내 |
| R12 | FCM data 는 6키(`type, notification_id, event_key, room_id, thread_id, question_id`) | `lib/notifications/fcmTransport.ts:68-100` — `mentor_id/subscription_id/refund_id/order_id` 없음 | 빌더 확장 대신 앱이 `notification_id` 로 `notifications` 행 재조회 → 인앱 라우터 재사용(§4.3). 웹 additive-only 원칙 유지 |
| R13 | `register_device_token` on conflict(token) 재소유 | 152:33-45 | 공용 기기 계정 전환 시 이전 사용자 토큰 행이 새 사용자로 이전(설계 의도). 앱은 로그아웃 시 **본인 행만** `revoked_at` UPDATE(RLS) — 순서: revoke → `auth.signOut()` |
| R14 | outbox 활성 순서 | `docs/plans/push-outbox-worker.md:24-34` — 워커 ON 전에 `push_transport_enabled=true` 면 pending 누적 → 앱 출시 시 폭주 | 앱 토큰 등록은 outbox 생성과 무관(현재 `push_transport_enabled=false` 라 outbox 0) → 앱 선배포 안전. 순서 위반만 금지 |
| R15 | F6 `deleted_by` 미기록 | `20260731113927…:382-405` | 관리자 `작성자 삭제` 배지(=`deleted_by = author_id`) 판정 누락 — 196 `board_post` 전환(§7-D)으로 앱 삭제분은 해소, 웹 F6 분은 웹 과제 |
| R16 | 앱이 `api_web_v1` 뷰·함수를 교차 호출 | `community_posts_v1`, `community_comments_v1` 등 | 계약 §19 "api_web_v1 = 웹 표면" 과 어긋나는 관행(DB 리포트 §6 #13) — 재구축 계약에서 `api_app_v1` 동명 뷰 정식화 여부는 전 도메인 공통 결정(본 문서 범위 밖, 기록만) |
| R17 | 분쟁 상세 `payments`·`order_payments` 읽기 | `payments_select_own`(user_id/student_id/payer_id/mentor_id), `opay_select` 주문 당사자 | 당사자 RLS 로 충분 — 단 결제 행 노출은 "결제 인접 읽기"(허용 범위 §3 "잔액·원장 조회 ✅" 유추) |

---

## 4. 앱 프론트엔드 설계

관례 준수: read/write 레포 분리·`_client/_uid` 정형·Port/Gateway seam·손코딩 fake(§3-1/3-2 아키텍처 리포트), 봉투 strict 파싱, 원문 비노출, `DataRefreshBus` 신호, `ResumeVisibilityGate`.

### 4.1 커뮤니티 (`lib/features/community/`)

| 파일 | 변경 |
|---|---|
| `data/community_read_repository.dart` | `boards({category, sort, cursor})` — `sort ∈ {latest, popular}`; latest 는 `(created_at, id)` keyset(`or(...)` 식은 알림 커서 함수 일반화 `keysetAfterFilter(createdAtRaw, id)` 공용화), popular 는 `order(like_count).order(view_count).order(comment_count).order(created_at)` + range. `shortforms({category, sort, ...})` — `eq('category')`, popular 정렬. `comments()` — 게시판은 트리 조립 함수 `assembleCommentTree(rows)`(순수·테스트) 추가, 차단 필터는 답글 포함. `myDrafts()` — 뷰 `author_id = uid and status = 'draft'`. `myHiddenPostIds()` 또는 `BoardPost.status` 노출로 배지 판정 |
| `data/community_write_repository.dart` | `deleteMyBoardComment(id)` · `deleteMyShortformComment(id)` · (결정 E) `deleteMyShortform(id)` → 공용 `softDeleteOwn(kind, id)`; `addComment(parentId)` 실배선; `report(reasonCode)` 정본 어휘; 오류 매퍼에 `CONTENT_*`·`UGC/ACCOUNT_*`(S-1) 추가 |
| `data/comments_gateway.dart` | seam 추가 `Future<void> softDeleteOwnContent(String kind, String id)` → `_client.rpc('soft_delete_own_content', params: {'p_kind','p_id'})`; 성공 = 예외 없음. 기존 `softDeleteShortformComment` 는 전환 후 제거 |
| `data/community_models.dart` | `BoardPost.status`(draft/published/hidden) 추가; `CommunityComment.replies`(트리) 또는 별도 `CommentNode`; `ShortformPost` 유지(썸네일 ref 는 리졸버로) |
| `data/community_labels.dart` | 숏폼 카테고리 4종 옵션(`study/school/career/college`) 추가 — 라벨은 웹 정본 문자열 |
| `data/shortform_thumbnail_url_resolver.dart`(신설) 또는 리졸버 제네릭화 | 버킷 상수 `thumbnailBucket = 'shortform-thumbnails'`, TTL 10m/마진 60s, 키 `uid::ref`, 3형태 파싱(ref/legacy http/상대). 아키텍처 §9-2 "리졸버 제네릭 1벌" 권고에 맞춰 `SignedUrlResolver(bucket)` 로 4벌+1 통합 후보 |
| `data/board_post_create_gateway.dart` | `status` 인자(`'draft' | 'published'`) — 상수 고정 해제 |
| `data/community_post_error_mapper.dart` | `UPDATE_CONFLICT`·`POST_NOT_FOUND_OR_NOT_OWNED` 기존 + `CONTENT_*`(196) |
| `ui/board/board_detail_screen.dart` | 댓글 트리 렌더(답글 진입·부모 id 전달), 내 댓글 `onDelete`(`comment_tile.dart:10-24` 이미 seam 존재), 신고 사유 코드 |
| `ui/board/board_write_screen.dart` | "임시저장" 액션(`p_status='draft'`), 초안 이어쓰기(수정 경로 `p_status='published'` 전환) |
| `ui/activity/my_activity_view.dart` | `_group('임시저장', drafts)` + hidden 배지 |
| `ui/shortform/shortform_feed_view.dart` | 카테고리 칩·정렬 탭; 작성 CTA 는 결정 A 에 따라 WebView(`ShortformComposeScreen`) 유지 또는 `ShortformComposeNativeScreen` |
| `ui/shortform/shortform_detail_screen.dart` | (결정 E) 내 숏폼 삭제 메뉴 |
| `ui/widgets/report_sheet.dart` | 사유 코드 정본(§7-F) |
| (결정 A=네이티브) `data/shortform_post_gateway.dart`(신설) | RPC `api_app_v1.shortform_post_create/update` 봉투 파서 + 오류 매퍼; `data/shortform_media_upload_gateway.dart`(신설) — `file_picker` 영상 선택 → 크기·MIME 사전 검사(500MB·mp4/mov/webm) → `storage.from('shortform-videos').uploadBinary('{uid}/{uuid}.{ext}', upsert:false)` → 썸네일 프레임 추출(새 의존성 예: `video_thumbnail` (확인 필요: 라이선스·플랫폼)) → `shortform-thumbnails/{uid}/{uuid}-thumb.jpg` 업로드 → RPC finalize → 실패 시 보상 `remove`(질문방 첨부 패턴 `attachment_upload.dart:194-259` 재사용) |

### 4.2 공지 (`lib/features/notices/` 신설)

- `data/notice_models.dart` — `AppNotice{id, title, body, type(notice/event/maintenance/update→라벨), target, displayMode, startsAt, endsAt, createdAt}` (`fromMap` 관대 파싱, `type` 폴백 '공지').
- `data/notices_repository.dart` — `list({limit 50})`: `from('app_notices').select(...).eq('is_active', true).order('created_at', desc)`; 역할 필터 `target in (null,'all', role)` 는 클라(서버 컬럼 값이 사전 3값이므로 `or(target.is.null,target.eq.all,target.eq.<role>)` 서버 필터도 가능). `activePopups()`: `eq('display_mode','popup')` + 같은 필터.
- `ui/notices_screen.dart`(목록·상세 인라인 확장) — 진입: 마이페이지 `SupportSection` 행 '공지사항'(`support_section.dart:40-52` 패턴), 알림 탭 상단 링크(선택).
- `ui/widgets/notice_popup_banner.dart` — 결정 G: `HomeShell` 상단 슬롯 또는 첫 진입 모달. 닫기 상태는 `shared_preferences` 키 `notice_dismissed_<id>`(기기 로컬·서버 미기록). 노출 판정 순수 함수 `visiblePopupNotices(list, dismissedIds, role, now)` 테스트 대상.
- 매니페스트: `app_notices` 등재.

### 4.3 알림·딥링크·푸시 (`lib/features/notifications/`, `lib/core/deeplink/`, `lib/core/push/`)

**알림함**
- `data/notification_types.dart` — `NotificationKind` 에 `refund` 추가, `notificationKindOf` 정합(§2 #37); `NotificationDestination` 에 `supportRefunds`(결정 C 포함 시) 추가; 유형→(kind, destination) 를 **단일 테이블 상수**로 재구성(아키텍처 §9-2 "exhaustive switch 4곳 → 단일 테이블").
- `data/app_notification.dart` — `subscriptionId`(`metadata.subscription_id`), `refundId`, `orderId`, `applicationId` 필드 추가(현재 room/thread/question/post/shortform/mentor 6개).
- `data/notifications_repository.dart` — `fetchById(id)`(푸시 탭용, `notifications` 본인 RLS); 게이트 목록 `kGatedNotificationTypeCodes` 를 CR 도메인 플래그와 연동(서버 RPC 재정의 선행 — R10).
- `notifications_screen.dart` — 칩 6종 정합(`_chipKinds`).
- `lib/core/deeplink/notification_deep_link_controller.dart` — `NotificationRefundRoute(refundId)`, `NotificationSubscriptionRoute(subscriptionId)` 추가; `myPage` 목적지에서 `subscription_id` 를 마이페이지 push 인자로 전달(`HomeShell._openMyPage` 확장, `home_shell.dart:88-98`).
- `ui/notification_target_opener.dart` — 두 route 열기(환불 내역 화면 / 마이페이지 구독 섹션).

**푸시 재도입(결정 B)** — HANDOFF "재도입 6항" 준수(`lib/core/push/HANDOFF.md`).
- `lib/core/push/push_ports.dart` — 기존 `PushPermissionPort/PushPermissionStatus` 시그니처 **불변**(설정 화면 import, `settings_section.dart:3,28,41`). 추가 포트: `abstract class PushTokenPort { Future<String?> currentToken(); Stream<String> get onTokenRefresh; Future<void> deleteToken(); }`, `abstract class PushMessagePort { Stream<PushPayload> get openedPayloads; Future<PushPayload?> initialPayload(); Stream<PushPayload> get foregroundPayloads; }`.
- `lib/core/push/firebase_push_gateway.dart`(신설) — `firebase_core`/`firebase_messaging` 구현: `FirebasePushPermission implements PushPermissionPort`(`requestPermission` → 상태 매핑), `FirebasePushGateway implements PushTokenPort, PushMessagePort`(`getToken`, `onTokenRefresh`, `onMessageOpenedApp`, `getInitialMessage`, `onMessage`); `@pragma('vm:entry-point')` 백그라운드 핸들러는 **no-op**(데이터 처리·발송 금지). 초기화는 플랫폼 설정 파일 존재 시에만(`Firebase.initializeApp` 실패 → 푸시 비활성으로 강등, 앱은 구동).
- `lib/core/push/device_token_registrar.dart`(신설) — `register(token, platform)` → `client.rpc('register_device_token', {'p_token','p_platform'})` 봉투 `{ok, device_token_id}` strict; `revoke(token)` → `from('device_tokens').update({'revoked_at': nowUtc}).eq('token', token).eq('user_id', uid)`(RLS 본인). `platform` 은 `ios|android` 만(그 외 `unknown`).
- `lib/core/push/push_service.dart`(신설) — 수명주기 오케스트레이션: `AuthService._onAuthChange`(`auth_service.dart:165-183`) `signedIn/initialSession` → 권한 상태 확인(요청은 설정 화면 또는 첫 로그인 후 1회 — 정책은 UI 범위 밖) → `currentToken` → `register`; `onTokenRefresh` → `register`; `AuthService.signOut()`(`:330-341`) 에서 `auth.signOut()` **이전**에 `revoke(currentToken)`(세션 필요); 계정 전환은 register 의 재소유로 처리. 실패는 로그(토큰 전문 금지)·재시도 다음 로그인.
- `lib/core/push/push_payload.dart` — 유지(6키). 탭 처리: `DeepLinkService._onOpened`(`deep_link_service.dart:34-45`)에서 `notification_id` 가 있으면 `NotificationsRepository.fetchById` → `AppNotification` → 기존 `resolveNotificationDeepLink`(단일 판정 정본); 조회 실패·비로그인 시 현행 payload id 기반 폴백. `DeepLinkService.initialize(openedPayloads: gateway.openedPayloads)` + `initialPayload()` 콜드스타트 1회 주입(`main.dart:44-49`).
- 플랫폼: Android `POST_NOTIFICATIONS` 선언 + 채널 `ssambership_default`(서버 빌더 `fcmTransport.ts` `channel_id` 와 일치) 생성(`flutter_local_notifications` 없이 FCM notification 파트만 쓰면 채널 자동 생성은 플러그인 기본 채널 — 명시 생성 권고 (확인 필요)); iOS `aps-environment` entitlement, `UIBackgroundModes: remote-notification`, APNs 키(콘솔). `google-services.json`/`GoogleService-Info.plist` 는 **커밋 금지**(`.gitignore` 유지 — HANDOFF 지뢰).
- 테스트·계약: `test/push/firebase_free_test.dart` → `push_contract_test.dart` 로 대체(의존성 존재·가짜 게이트웨이로 register/revoke 순서·`openedPayloads` 주입 → 라우팅). `outbound_api_manifest_test.dart` `'firebase' 0건` 테스트 삭제·`register_device_token` 등재. iOS `test/contracts/ios_release_config_contract_test.dart` `kForbiddenCollectedDataTypes` 의 `NSPrivacyCollectedDataTypeDeviceID` 처리(§7-B Data Safety).
- 문서: `docs/DATA_SAFETY_FORM.md` '기기 또는 기타 ID' → **예**(§2 표 재작성 지시문 그대로), 웹 개인정보처리방침 `PROCESSORS` 에 FCM(처리위탁+국외이전) — `docs/plans/push-outbox-worker.md` TODO O-12(오너 문안).

### 4.4 지원 (`lib/features/support/` 신설 + 마이페이지 진입)

- `data/my_reports_repository.dart` — `content_reports` `select('id,target_type,target_id,reason,description,status,created_at,resolved_at').eq('reporter_id', uid).order(created_at desc).limit(50)`; 상태 라벨 `resolved→처리 완료 / reviewing→검토 중 / rejected|dismissed→반려 / 기타→접수됨`(웹 `studentReportsQueries.ts:52-58`); target_type 라벨은 앱 정본 5종 exact(웹의 관대 매칭 대신).
- `ui/my_reports_screen.dart` — 진입: `SupportSection` 행 '내 신고 내역'.
- (결정 C) `data/refund_request_repository.dart` — `estimate(subscriptionId)`·`request(subscriptionId, reason)` RPC 봉투 파서(`api_app_v1` 스키마 명시 — 생략 시 PGRST202 지뢰) + 오류 매퍼(`REFUND_PENDING_EXISTS`·`REFUND_AMOUNT_ZERO`·`SUBSCRIPTION_NOT_CURRENT`…); 대상 구독 목록은 `api_web_v1.my_subscriptions_self()` 또는 기존 `SubscriptionReader`; pending 환불 표시는 `refunds` 본인 SELECT. `ui/refund_request_screen.dart` — 결제 유도 문구·금액 강조 금지(정책 §4), 예상액은 서버 값만 표시, 142 잠금 사전 고지. 성공 시 `DataRefreshBus.bumpSubscription()`(생산자 0 상태 해소).
- (결정 H) `data/disputes_repository.dart` — `listMine(role)`: `disputes.eq(role=='student' ? 'student_id' : 'mentor_id', uid)`; `bundle(id)`: `disputes` 단건 → `custom_request_orders`(cro_select) → `order_payments`→`payments`(선택) → `refunds` 공유키(`custom_request_order_id`→`payment_id`→`subscription_id`, `lib/disputes/disputeRefundLink.ts:12-16`). `ui/disputes_list_screen.dart`, `ui/dispute_detail_screen.dart` — 주문 링크는 CR 도메인 화면이 있을 때만(없으면 주문 요약만). 상태 라벨 매핑 웹 `disputeListQueries.ts:58-74`.
- `lib/features/mypage/ui/sections/support_section.dart` — 행 추가: 공지사항 · 내 신고 내역 · (환불 신청) · (분쟁 내역, 학생/멘토 공용). 기존 `고객지원`(웹) 은 §7-I 결과에 따라 유지/교체.

### 4.5 라우트·탭

- 현 라우터는 4 라우트 + 명령형 push(`lib/app/router.dart`, `app_tabs.dart`). 본 도메인 최소안은 기존 관례(Navigator.push)로 가능. 다만 푸시 딥링크 목적지가 늘어나므로(환불·공지·분쟁) `NotificationTargetOpener` 증식이 불가피 → 아키텍처 §9-2 "타입드 라우트 테이블" 전환이 채택되면 `/notices`, `/support`, `/support/reports`, `/support/refunds`, `/support/disputes/:id` 를 id 파라미터 라우트로 등록하고 opener 를 라우트 이름 → 조회형 화면으로 단순화한다(전 도메인 공통 결정).
- 게스트: 공지 목록은 게스트 허용 가능(`app_notices` anon SELECT) — `EntryGuard.guestAllowedTabs` 는 탭 단위라 마이페이지 경유 진입은 로그인 필요; 게스트 노출은 커뮤니티 탭 상단 배너로(선택).

### 4.6 매니페스트·플랫폼 갱신 체크리스트

1. `test/contracts/outbound_api_manifest_test.dart` — §3(b) S-6 집합 갱신; 3표 DELETE 금지 테스트 추가(R3).
2. `test/push/*` — 대체 테스트; `test/deeplink/` 에 `fetchById` 경로 케이스.
3. `android/app/src/main/AndroidManifest.xml` — `POST_NOTIFICATIONS`(결정 B); `ios/Runner/Info.plist`·entitlements·`PrivacyInfo.xcprivacy`.
4. `docs/DATA_SAFETY_FORM.md` §2 '기기 또는 기타 ID'·§4 체크리스트 5항 갱신.
5. `pubspec.yaml` — `firebase_core`, `firebase_messaging`(결정 B); `video_thumbnail` 류(결정 A=네이티브).

---

## 5. 데이터 모델 추가/변경

| 계층 | 항목 | 내용 |
|---|---|---|
| DB(신규) | `ugc_account_gate()` 트리거 6종 | §3(b) S-1 — 컬럼 변경 없음 |
| DB(조건부) | `api_app_v1.shortform_post_create/update` + `core_private.shortform_post_*_impl` | 컬럼 변경 없음(기존 `create_idempotency_key`·`author_label`·`deleted_at/by` 사용) |
| DB(조건부) | `api_app_v1.refund_estimate_subscription_self` / `refund_request_subscription_self` + impl | `refunds` 기존 컬럼(`request_type`, `billing_event_id`, `reason`) 사용 |
| DB(선택) | `content_reports.reason` 정본 어휘(CHECK NOT VALID 또는 `reason_code`) | §7-F |
| DB(선택) | `sfv_public_read` 축소 | §3(c) R1 |
| 앱 모델 | `BoardPost.status` · `CommunityComment.replies`/`CommentNode` · `ShortformPost`(변경 없음, 리졸버) | `community_models.dart` |
| 앱 모델 | `AppNotice{id,title,body,type,target,displayMode,startsAt,endsAt,createdAt}` | 신설 |
| 앱 모델 | `AppNotification` + `subscriptionId, refundId, orderId, applicationId` · `NotificationKind.refund` · `NotificationDestination.supportRefunds` · `NotificationRefundRoute`/`NotificationSubscriptionRoute` | 기존 파일 확장 |
| 앱 모델 | `MyContentReport{id,targetType,targetId,reason,description,status,createdAt,resolvedAt}` | 신설 |
| 앱 모델(조건부) | `RefundEstimate{amountCents, bracketReason, remainingDays, totalDays, usageStarted, canRequest, pendingRefundId}` · `RefundRequestResult{refundId, amountCents, bracketReason}` | 신설 |
| 앱 모델(조건부) | `Dispute{id, orderId, studentId, mentorId, body, status, submittedBy, createdAt}` · `DisputeBundle{dispute, order?, payment?, refund?}` | 신설 — 컬럼 정본 `orderDisputeActions.ts:53-68` |
| 앱 모델(조건부) | `ShortformComposeInput{title, body, category, videoRef, thumbnailRef, status, rightsAck, requestId}` | 신설 |
| 앱 상태 | `PushPayload`(불변) · `DeviceTokenState{token, platform, registeredForUserId}`(메모리) | `lib/core/push/` |
| 앱 로컬 | `shared_preferences` 키 `notice_dismissed_<id>` | 공지 팝업 닫기(기기 로컬) |

---

## 6. 구현 순서·의존성·규모

규모: S(≤1일) · M(2~4일) · L(1~2주) · XL(2주+). "서버 선행" = 웹 pack 적용·`contracts:export` 후 앱 착수.

| 단계 | 작업 | 의존 | 규모 |
|---|---|---|---|
| P0 서버 선행 | S-1 계정 게이트 트리거(마이그레이션 1본 + 롤백 + 계약 스냅샷) · 신고 어휘 결정(F) · (선택) R1 `sfv_public_read` 축소 | 오너 결정 F·L | S |
| P1 커뮤니티 정합 | 소프트 삭제 통일(#12·#23, `soft_delete_own_content` 매핑) → 답글 2-depth(#11) → 임시저장·내 활동(#5·#14·#15) → 정렬·keyset(#2·#3) → 숏폼 카테고리/정렬·썸네일 리졸버·버킷 상수(#18·#19) → 매니페스트 갱신 | P0(게이트 오류 매핑), 결정 D·E | M |
| P2 공지 | `features/notices` 레포·화면·(결정 G) 배너 · 매니페스트 `app_notices` | 결정 G | S |
| P3 알림 정합 | kind 테이블·`refund` 분류·`AppNotification` 필드·route 2종·opener·`fetchById` | P2(공지 진입 없음)·결정 C(환불 route) | S–M |
| P4 지원(읽기) | 내 신고 내역(#29) · (결정 H) 분쟁 목록/상세 | CR 도메인 결정 | S(#29) / M(분쟁) |
| P5 환불 신청 | 서버 S-3(impl·wrapper 2종·롤백·계약) → 앱 레포·화면·알림 route | 오너 결정 C(결제 경계) | 서버 M · 앱 M |
| P6 OS 푸시 재도입 | 앱: SDK·게이트웨이·토큰 수명주기·딥링크 주입·플랫폼 설정·테스트 대체·Data Safety(§4.3) → 웹 운영: `NOTIFICATION_OUTBOX_WORKER_ENABLED=true`(dry-run) → postgres `push_transport_enabled=true` → 관측 → `FCM_TRANSPORT_MODE=live`(`docs/plans/push-outbox-worker.md:24-34`, 순서 고정) | 오너 결정 B; GRANT 는 이미 적용(PUSH-APPLY) | 앱 L · 운영 S |
| P7 숏폼 네이티브(선택) | 서버 S-2(impl·wrapper·계약) → 앱 업로드 게이트웨이·썸네일 추출·RPC finalize·보상 삭제·화면 → WebView 브릿지 폐기 여부 | 오너 결정 A; R1 권고 | XL(서버 M + 앱 L) |

의존 요약: P1 은 P0 없이도 가능하나 게이트 오류 매핑 누락 → P0 먼저. P3 의 CR 알림 노출은 R10(서버 RPC 재정의) 선행. P5·P7 은 오너 결정 없이는 서버 객체를 만들지 않는다(DB 리포트 §6 공통 규칙).

---

## 7. 오너 결정 필요 항목 + 권고

| ID | 결정 | 선택지 | 권고 |
|---|---|---|---|
| A | 숏폼 작성: WebView 브릿지 유지 vs 네이티브 업로드+finalize(#24) | (1) WebView 유지(변경 0, `RELEASE_SCOPE_DECISIONS_2026-07.md:22-30` 계약) (2) 네이티브: RLS 직접 INSERT(`sf_insert_mentor`+`sfv_mentor_insert`) (3) 네이티브: `api_app_v1.shortform_post_create/update` 신설(S-2) | **1차 (1) 유지, 2차 (3)**. (2) 는 마스킹·금칙어·rightsAck·author_label·멱등·ref 소유 검증을 앱에 복제해 웹과 이중 정본이 되고 `is_mentor()` 승인 미검사가 그대로 노출된다. 네이티브 전환의 실익(500MB 업로드 안정성·썸네일 NULL 해소)은 (3) 에서만 웹과 계약을 공유한다. 부속: 승인 멘토 강제 여부(현 웹은 role 만) |
| B | OS 푸시 재도입 시점·범위(#40) | (1) 유지(인앱 알림함만) (2) 재도입(FCM 수신·토큰) | **(2) 권고** — 서버 측(outbox·worker·GRANT)은 이미 준비·적용됐고 남은 것은 앱과 운영 순서다. 조건: Data Safety '기기 또는 기타 ID'=예 재제출, iOS 계약 테스트 `kForbiddenCollectedDataTypes` 의 `DeviceID` 항목 재판정(FCM 토큰이 Apple "Device ID" 유형에 해당하는지 (확인 필요) — 플러그인 자체 PrivacyInfo 와 앱 매니페스트 분담), 개인정보처리방침 FCM 처리위탁·국외이전 문안(O-12), R11 충전 유도 문구 검토. 시점: P1~P3 이후(알림 라우팅 정합이 먼저) |
| C | 환불 신청 앱 포함(#42) | (1) 웹 위임(현행 정책 §3) (2) 포함 — S-3 RPC 신설 | **조건부 (2)**. 신청은 구매가 아니고 캐시 차감·PG 호출이 없다(웹 액션도 INSERT 만). 단 화면이 결제액·기간을 노출하므로 "가격표+구매 유도" 조합이 되지 않게 예상액·사유만 표시, `/wallet/charge` 류 안내 0. 정책 문서 §3 행 개정이 선행돼야 한다(문서 우선 규칙). 미포함이면 `mentor_termination_refund` 알림은 마이페이지 폴백 유지 |
| D | 본인 삭제 RPC 통일 범위(#7·#23) | (1) 게시글 F6·숏폼 댓글 구 RPC 유지 + 게시판 댓글만 196 (2) 앱 4종 전부 `soft_delete_own_content` (3) (2)+웹 결정으로 `community_comment_soft_delete_self` authenticated 회수 | **(2) 권고**: `deleted_by` 기록·hidden 보호(`CONTENT_MODERATED`)·멱등이 단일 규약이 되고 매니페스트 RPC 가 2개 줄어든다. 차이 고지: 196 은 관리자 숨김 글을 본인이 지울 수 없다(F6 은 가능) — 사용자 문구 필요. (3) 는 구 앱 버전 호환 기간 후 웹 트랙 |
| E | 숏폼 본인 삭제 UI(#25) | (1) 웹 parity(없음) (2) 앱 추가 | **(2) 권고(저비용)** — RPC 준비됨, 작성자가 자기 영상을 내릴 수 없는 상태는 UGC 운영상 결함에 가깝다. 웹도 동시 추가 권고 |
| F | 신고 사유 정본 어휘(#27) | (1) 앱 영문 코드 5종 `inappropriate/spam/external_contact/copyright/etc` 로 웹 정합 (2) 웹 한글 5종 (3) 신규 코드 집합(+`abuse`,`privacy`) + DB `reason_code` | **(1) 또는 (3)** — 코드 저장·라벨 표시가 앱 규약("영문 코드 비노출")과 맞고 관리자 큐 필터가 가능. (2) 는 코드 대신 표시 문자열을 저장하는 형태라 비권장. 결정 후 멱등 트리거 키 일관성 확보(R8) |
| G | 공지 팝업 앱 노출 방식(#33) | (1) 목록만(팝업 무시) (2) 홈 상단 배너(닫기 1회·기기 로컬) (3) 진입 모달 | **(2) 권고** — 웹 팝업(PR-10b) 미머지 상태에서 앱만 모달을 띄우면 채널 간 노출 정책이 갈린다. 배너는 `display_mode=popup` 의미("접속 시 노출")를 지키면서 차단감이 낮다. 닫기 상태를 서버에 기록할 필요가 생기면 `notice_dismissals(user_id, notice_id)` 신설(현재 불필요) |
| H | 분쟁 목록/상세 앱 포함(#41) | (1) 웹 위임 (2) 읽기 전용 포함(CR 도메인 포함 시) | **CR 도메인 결정에 종속** — CR 미포함이면 분쟁은 앱에 진입점이 없어 (1). CR 포함이면 (2), 새 서버 객체 0. 결제 행(`payments`) 표시는 상태·금액 요약만 |
| I | 고객센터 FAQ 위임 방식(#44) | (1) 현행(외부 브라우저 `/support`) (2) 웹 `/support?src=app` 에서 결제 링크(`/wallet/charge`·`/subscribe`) 비노출 (3) 앱 정적 FAQ 화면 | **(2) 권고(웹 변경 1건)** — 앱에서 여는 페이지에 충전·구독 링크가 있는 현 상태는 정책 §4 회색지대. (3) 은 FAQ 이중 관리 |
| J | 약관·개인정보 앱 내 렌더(#45) | (1) 외부 브라우저(현행) (2) 인앱 WebView (3) 앱 내 렌더(본문 복제 또는 `legal_documents` 테이블 신설) | **(1) 유지** — 문서가 정적 TSX 로 회사 상수를 조립하며 DB 원천이 없다. 스토어 심사에 "앱 내 열람" 이 요구되면 (2)(`/legal/*` allowlist WebView, 결제 경로 차단) |
| K | 댓글 연락처 마스킹 서버화(#49) | (1) 앱 클라 마스킹 이식 (2) 서버 트리거(S-5) | **(2) 권고** — 게시글은 이미 SQL 마스킹(RPC), 댓글만 클라 의존은 웹·앱 이중 구현. 웹 클라 마스킹과 규칙 동치 검증 필요 |
| L | `sfv_public_read`(및 `cpi_public_read`) 축소(R1) | (1) 유지 (2) published 행 참조 객체 + 본인 폴더로 축소 | **(2) 권고** — 비공개 버킷의 목적(`public=false`)과 어긋나는 전체 SELECT·`list()` 노출. 앱 published 재생·본인 업로드 경로 무영향 |

---

## 8. 리스크·지뢰

1. **`soft_delete_own_content` 반환형 void** — 앱 봉투 strict 파서에 넣으면 항상 실패로 오판. 성공 = 예외 없음, 실패 = `PostgrestException` 선두 코드(196). 매퍼 스타일 (1)(`raise exception`) 로 처리해야 한다.
2. **`api_app_v1` RPC 는 `.schema('api_app_v1')` 필수** — 생략 시 PGRST202(`community_write_repository.dart:233-235` 경고). 신설 `refund_*`·`shortform_post_*` 도 동일.
3. **CR 게이트 하드코딩 2중 정본** — 앱 `kGatedNotificationTypeCodes` 와 서버 `notification_unread_count_self` 가 같은 2종을 각자 제외. CR 포함 시 서버 재정의 없이 앱만 바꾸면 배지 ≠ 목록.
4. **GRANT 상태 문서 불일치** — `20260827100100…sql` 헤더·phase-1 리포트는 "미적용", `docs/sprint-push/PUSH-APPLY.md` 는 적용 증적. 설계는 적용 완료 전제이나 착수 전 라이브 `routine_privileges` 재확인(확인 필요).
5. **푸시 활성 순서** — 워커 플래그 ON 전에 `push_transport_enabled=true` 금지(outbox 누적 → 폭주). 앱 토큰 등록 자체는 안전(outbox 미생성).
6. **푸시 탭 딥링크 데이터 부족** — FCM data 6키로는 멘토/환불/구독 상세를 열 수 없다 → `notification_id` 재조회 설계(§4.3). 비로그인 콜드스타트는 `NotificationDeepLinkController` pending(TTL 15분) 유지.
7. **Data Safety·PrivacyInfo 회귀 잠금** — `firebase_free_test.dart`·매니페스트 `'firebase' 0건`·iOS `DeviceID` 금지 집합이 푸시 재도입을 CI 에서 막는다. 의도된 계약 갱신으로 함께 바꿔야 하며, 설문 재제출 전 스토어 빌드 금지.
8. **`sfv_public_read` 목록 노출**(R1) — 네이티브 업로드를 열면 draft 영상이 늘어 위험 표면이 커진다. 결정 A(3) 채택 시 결정 L 동시 적용 권고.
9. **`is_mentor()` 승인 미검사** — 네이티브 RLS 직접 경로(A-(2))는 미승인 멘토 업로드 허용. RPC(S-2)에서만 승인 강제 가능.
10. **썸네일 3형태 혼재**(NULL/ref/legacy http) — 리졸버가 전부 수용해야 하며, WebView 경로의 프레임 추출 동작은 미검증(확인 필요).
11. **신고 어휘 불일치 + 멱등 키** — 결정 F 전에는 웹·앱 교차 중복 접수. 앱 정본 5종을 바꾸면 기존 앱 버전과 신규 버전 사이에도 같은 문제.
12. **삭제 콘텐츠 신고 42501**(R9) — RLS 거부 메시지는 원문 비노출 규칙상 "이미 삭제된 콘텐츠" 로 매핑해야 한다.
13. **환불 신청의 질문방 잠금**(142) — 신청 성공 즉시 해당 구독 질문 작성이 `SUBSCRIPTION_REFUND_PENDING` 으로 막힌다. 신청 화면 사전 고지·성공 후 `DataRefreshBus.bumpSubscription/bumpQuestionRooms` 필요.
14. **환불 예상액 이중 구현** — 웹 TS(`computeProratedRefundEstimate`)와 서버 SQL 이 갈리면 웹·앱 금액 불일치. S-3 도입 시 웹도 같은 RPC(`api_web_v1` 동명 wrapper)로 수렴 권고.
15. **`app_notices.body` 렌더 형식** — 웹은 plain text 로 취급(`publicNoticesQueries.ts` 문자열 trim, 마크다운 렌더 흔적 0 (확인 필요: 관리자 편집기 서식)). 앱도 plain text 로 가정하되 링크 자동 실행 금지(원문 URL 실행 금지 규약).
16. **keyset 전환 시 차단 필터 상호작용** — 차단 작성자 제거로 페이지가 줄어도 커서는 서버 마지막 행 기준(`created_at, id`) 이어야 한다(현 `rawCount` 전진 규칙과 동일 원리).
17. **댓글 트리 + 차단** — 부모가 차단돼 숨겨지면 답글 처리 규칙(함께 숨김 — 웹 `filterBlockedCommentNodes` 답글 포함) 을 순수 함수로 고정·테스트.
18. **`community_comment_soft_delete_self` 회수 타이밍** — 구 앱 버전이 남아 있는 동안 회수하면 삭제 실패. 버전 게이트(`get_mobile_app_version_policy`) 최소 빌드 상향과 동기.
19. **`/support` 외부 브라우저의 결제 링크**(결정 I) — 앱 심사 스크린샷·리뷰어 탐색 시 발견 가능.
20. **문서 구식 지뢰** — 앱 `HANDOFF.md` §3-4(FCM 현행처럼 서술), 웹 GRANT 헤더, phase-1 "미적용" 판정. 코드·증적이 정본.
