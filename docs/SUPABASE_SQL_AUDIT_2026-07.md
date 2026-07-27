# Supabase ↔ 앱 상호작용 전수조사 (2026-07-27)

앱(`lib/`) 코드와 **운영 Supabase DB 실물**을 양쪽에서 대조한 전수조사 결과.
경로(어느 파일이 어떤 테이블/RPC/버킷/채널을 통해 서버와 오가는지)를 빠짐없이 수집했다.

조사 방법:
- 코드 쪽: `lib/` 전체에서 `.from('…')`, `.rpc('…')`, `storage.from(…)`, `channel(…)/onPostgresChanges`, `auth.*` 호출 전수 grep.
- DB 쪽: 운영 DB에서 `pg_proc`(함수 187개 중 public 전체), `pg_policies`(RLS 전체), `information_schema.triggers`, `pg_publication_tables`(Realtime), `storage.buckets`, 함수 EXECUTE grant(`anon`/`authenticated`) 를 직접 조회.

---

## 1. 앱이 직접 접근하는 테이블 (PostgREST `.from()`)

앱 코드가 REST 로 직접 읽고/쓰는 테이블 22개. (RPC 경유 접근은 §2)

| 테이블 | 앱에서의 작업 | 호출 위치 (lib/) |
|---|---|---|
| `users` | SELECT, UPDATE(프로필), upsert | `core/auth/auth_service.dart:223,246`, `core/auth/account_status.dart:143`, `features/mypage/data/mypage_repository.dart:65`, `features/mypage/data/profile_edit_repository.dart:30`, `features/community/data/user_blocks_repository.dart:78`, `features/community/data/community_write_repository.dart:188` |
| `subscriptions` | SELECT | `core/entitlement/entitlement.dart:44`, `core/entitlement/subscription_summary.dart:51` |
| `mentor_student_rooms` | SELECT | `features/question_room/data/question_room_read_repository.dart:31`, `features/mentors/data/free_question_entry.dart:129` |
| `question_threads` | SELECT | `question_room/data/question_room_read_repository.dart:41,53,109` |
| `question_messages` | SELECT | `question_room/data/question_room_read_repository.dart:119` |
| `question_attachments` | SELECT | `question_room/data/question_room_read_repository.dart:140`, `question_room/data/attachments/attachment_upload.dart:408` |
| `connection_notes` | SELECT, INSERT, UPDATE | `question_room/data/question_room_write_repository.dart:182,190,202`, `question_room_read_repository.dart:130` |
| `mentor_profiles` | SELECT | `question_room/data/question_room_read_repository.dart:67` |
| `mentor_plans` | SELECT | `features/mentors/data/mentor_directory_repository.dart:175` |
| `reviews` | SELECT | `features/mentors/data/mentor_directory_repository.dart:126` |
| `favorites` | SELECT, INSERT, DELETE | `features/mentors/data/mentor_favorites_repository.dart` (`_table = 'favorites'`) |
| `free_question_usage` | SELECT | `features/mentors/data/free_question_entry.dart:136` |
| `community_posts` | SELECT, INSERT, UPDATE(soft-delete) | `community/data/community_read_repository.dart:64,162,179`, `community_write_repository.dart:192,205` |
| `shortform_posts` | SELECT | `community/data/community_read_repository.dart:83` |
| `post_reactions` | SELECT, INSERT, DELETE | `community_read_repository.dart:131`, `community_write_repository.dart:47,54` |
| `shortform_reactions` | SELECT, INSERT, DELETE | `community_read_repository.dart:146`, `community_write_repository.dart:70,77` |
| `comments` (게시판 댓글 정본) | SELECT, INSERT | `community/data/comments_gateway.dart` 경유 — 테이블명은 `community_models.dart:204` 에서 결정 |
| `community_comments` (숏폼 댓글) | SELECT, INSERT | 위와 동일 (`CommentsGateway`) |
| `content_reports` | INSERT | `community_write_repository.dart:223` |
| `notifications` | SELECT, UPDATE(read 처리) | `features/notifications/data/notifications_repository.dart:108,136` |
| `notification_settings` | SELECT, UPSERT | `features/mypage/data/notification_settings_repository.dart:102-125` |
| `individual_questions` / `individual_question_messages` / `individual_question_attachments` / `mentor_individual_question_pricing` | SELECT (쓰기는 전부 RPC) | `features/individual_question/data/individual_question_repository.dart:45-136`, `iq_attachments_repository.dart:133` |
| `cash_wallets` / `cash_ledger` | SELECT | `individual_question_repository.dart:136`, `mypage/data/mypage_repository.dart:121,135` |
| `subscription_settlement_items` | SELECT | `mypage/data/mypage_repository.dart:168` |
| `user_blocks` | SELECT, INSERT, DELETE | `community/data/user_blocks_repository.dart` (`_table = 'user_blocks'`) |

모든 대상 테이블은 RLS 활성화 상태(운영 DB 전 테이블 `rls_enabled=true` 확인).

## 2. 앱이 호출하는 RPC (26개, 전부 DB에 실존 확인)

DB 쪽 대조: 아래 26개 모두 운영 DB `public` 스키마에 존재하며, 표기한 함수 전부 **SECURITY DEFINER, owner=postgres**.

| RPC | 호출 위치 (lib/) | EXECUTE grant |
|---|---|---|
| `get_mobile_app_version_policy` | `core/version_gate/supabase_version_policy_port.dart:21` | anon, authenticated |
| `account_deletion_write_blocked` | `core/auth/account_status.dart:151` | authenticated |
| `account_deletion_status_self` | `core/auth/account_status.dart:162`, `mypage/data/account_deletion_repository.dart:183` | authenticated |
| `account_deletion_request_self` | `mypage/data/account_deletion_repository.dart:136` | authenticated |
| `account_deletion_cancel_self` | `mypage/data/account_deletion_repository.dart:162` | authenticated |
| `qna_create_question_thread` | `question_room/data/question_room_write_repository.dart:82` | authenticated |
| `qna_append_message` | 〃 `:120` | authenticated |
| `qna_confirm_thread` | 〃 `:146` | authenticated |
| `qna_flag_wrong_answer` | 〃 `:159` | authenticated |
| `qna_register_attachment` | `question_room/data/attachments/attachment_upload.dart:386` | authenticated |
| `get_weekly_question_usage` | `question_room/data/question_room_read_repository.dart:93` | anon, authenticated |
| `mentor_user_public_v2` | `question_room/data/mentor_lookup_repository.dart:47` | anon, authenticated |
| `get_mentor_student_nicknames` | `question_room/data/student_lookup_repository.dart:54` | authenticated |
| `mentor_directory_list_v2` | `mentors/data/mentor_directory_repository.dart:34` | anon, authenticated |
| `mentor_profiles_for_directory_v2` | 〃 `:158` | anon, authenticated |
| `get_mentor_avg_response_hours` | 〃 `:78` | anon, authenticated |
| `list_open_individual_questions_for_mentor` | `individual_question/data/individual_question_repository.dart:68` | authenticated |
| `create_individual_question_as_student` | 〃 `:160` | authenticated |
| `claim_individual_question_as_mentor` | 〃 `:180` | authenticated |
| `answer_individual_question` | 〃 `:189` | authenticated |
| `release_individual_question` | 〃 `:204` | authenticated |
| `refund_individual_question` | 〃 `:213` | authenticated |
| `add_individual_question_attachment` | `individual_question/data/iq_attachments_repository.dart:82` | authenticated |
| `increment_community_post_view` | `community/data/community_write_repository.dart:88` | anon, authenticated |
| `increment_shortform_post_view` | 〃 `:98` | anon, authenticated |
| `mark_all_notifications_read` | `notifications/data/notifications_repository.dart:154` | authenticated |

참고: `mypage/data/account_deletion_repository.dart:112-113` 은 함수명을 인자로 받는 범용 `rpc(fn, params)` seam — 실제 전달되는 이름은 위 account_deletion 3종.

## 3. Storage 버킷

### 앱 코드가 사용하는 버킷 (5개)

| 버킷 | 코드 상수 | 작업 |
|---|---|---|
| `question-room-attachments` | `question_room/data/attachments/attachment_upload.dart:131` | uploadBinary, download/signedUrl(`attachment_url_resolver.dart`), 등록은 `qna_register_attachment` RPC |
| `individual-question-attachments` | `individual_question/data/individual_question_repository.dart:20` | uploadBinary, remove(보상삭제), download(`iq_attachments_repository.dart`, `iq_annotation_repository.dart`, `iq_attachment_url_resolver.dart`) |
| `connection-note-ink` | `core/ink/ink_storage_paths.dart:21` | (경로 정본; 노트 잉크 저장) |
| `scan-annotations` | `core/ink/ink_storage_paths.dart:24` | uploadBinary, download (`scan_annotation/data/scan_annotation_repository.dart:113,125`) |
| `shortform-videos` | `community/data/shortform_media_url_resolver.dart:98` | signedUrl/재생 경로 해석 |

### DB에 실존하는 버킷 (13개) — 전부 private(단, `profile-avatars` 만 public)

`community-post-images`, `connection-note-ink`, `custom-order-deliverables`, `custom-order-message-attachments`, `custom-request-application-attachments`, `custom-request-post-attachments`, `individual-question-attachments`, `profile-avatars`(**public**), `question-room-attachments`, `scan-annotations`, `shortform-thumbnails`, `shortform-videos`, `student-id-images`.

`storage.objects` 에는 버킷별 경로검증 RLS 42개가 걸려 있고, 검증 로직은 §5의 `*_from_path`/`user_is_*` 계열 SECURITY DEFINER 함수로 위임된다 (예: `qra_storage_insert_party` → `qra_path_upload_eligible`, `iqa_storage_*` → `user_is_party_for_individual_question_storage_path`).

## 4. Realtime / Auth / Edge Functions

**Realtime** — `question_room/data/thread_realtime.dart:44` 이 채널 `question_thread_$threadId` 를 열고 `onPostgresChanges` 로 3개 테이블을 구독: `question_messages`(:49), `question_threads`(:68), `question_attachments`(:82). 운영 DB `supabase_realtime` publication 등록 테이블도 정확히 이 3개 — **코드↔DB 일치 확인됨**.

**Auth** — `core/auth/auth_service.dart` 가 로그인/세션 정본(29개 파일이 `auth.currentUser` 등 세션 참조). DB 쪽에는 `auth.users` INSERT 트리거 2개가 앱 가입 흐름과 상호작용: `on_auth_user_created → handle_new_auth_user()`(public.users 1줄 동기화), `zz_on_auth_user_created_consent_records → handle_new_auth_user_consent_records()`(동의 원장 기록).

**Edge Functions** — 앱 코드에 `functions.invoke` 호출 **없음**. 앱↔서버 상호작용은 전부 PostgREST/RPC/Storage/Realtime/Auth 경유.

## 5. 앱 쓰기 경로에 개입하는 DB 트리거 (간접 상호작용)

앱이 직접 호출하지 않아도 앱의 INSERT/UPDATE 에 반응해 동작이 바뀌는 트리거들 (운영 DB 84개 중 앱 경로 관련만):

- **쓰기 가드**: `question_threads/question_messages/question_attachments` 의 `*_direct_write_guard`(직접 쓰기 차단 → RPC 강제), `comments`/`community_comments` 의 `comments_write_guard`/`cc_write_guard`, `users` 의 role 승격 차단(`enforce_users_role_guard`, `enforce_users_role_insert_guard`), 계정삭제 중 쓰기 차단 `account_deletion_write_guard`(cash_ledger, cash_wallets, community_posts, payments, question_messages, shortform_posts).
- **파생값 갱신**: `post_reactions`/`shortform_reactions` → like_count 재계산, `comments` → comment_count 재계산, `community_posts` → 해시태그 동기화, 다수 테이블 `set_updated_at`.
- **댓글 이중화 브리지**: `comments` ↔ `community_comments` 양방향 미러(`comments_mirror_to_legacy`, `cc_sync_board_to_canonical`) — 앱의 v16 댓글 정본 전환(`comments_gateway.dart` 주석)과 대응.
- **무료질문 한도**: `free_question_usage` INSERT 시 `check_free_question_usage_limits`(전체 15회·멘토당 3회), `question_threads` INSERT 시 `qt_direct_consume_free_usage`.
- **알림 생성**: `individual_questions`(`iq_notify_assigned`, `iq_notify_status_transition`), `individual_question_messages`(`iqm_notify_message`), `mentor_plans` 가격변경, `subscriptions` 만료, `refunds`, `subscription_billing_events` 등 → `notifications`/`notification_outbox` 로 적재되어 앱 알림함(§1 `notifications`)에 도달.
- **구독 상한**: `subscriptions` INSERT/UPDATE 시 `enforce_mentor_cap`.

## 6. RLS 정책 전수 요약

운영 DB `public` 스키마 정책 약 170개 + `storage.objects` 42개 전수 확인. 앱이 접근하는 모든 테이블에 `authenticated` 대상 정책 존재. 패턴:

- 본인 행 한정: `users`, `favorites`, `notifications`, `notification_settings`, `device_tokens`, `user_blocks`, `cash_wallets`, `cash_ledger`, `withdrawals`, `free_question_usage`, `content_reports`(신고자), `user_consent_records`.
- 당사자(방/주문/질문) 한정: `mentor_student_rooms`, `question_*`, `connection_notes`, `individual_question*`, `custom_order_*`, `subscriptions`, `subscription_billing_events`, `scan_annotations`.
- 공개 읽기(anon 포함): `community_posts(published)`, `shortform_posts(published)`, `comments/community_comments(visible)`, `mentor_plans`, `reviews(public_visible)`, `subjects`, `app_notices`, `cash_topup_packages`, `promotion_campaigns`, `school_tier_catalog`, `major_category_catalog`, `post_reactions`.
- 관리자 전용: `admin_action_logs`, `admin_case_notes`, `verification_logs(select)`, `school_tier_mappings`.
- service_role 전용: `reviews_quarantine_archive`, `reviews_duplicates_archive` (+ `mobile_app_version_policies` 는 정책 없음 = RPC 경유만).

## 7. 전수조사 중 발견한 특이사항 (조치 제안 아님, 기록)

1. **마이그레이션 drift**: 레포 `supabase/migrations/` 에는 4개 파일뿐이나 운영 DB에는 마이그레이션 31개 적용됨. 레포가 DB 스키마의 정본이 아니다 — DB 형상은 원격에만 존재.
2. **legacy 한국어 정책 중복**: `community_posts`, `custom_order_messages`("누구나 메시지 읽기"), `custom_request_*`, `favorites`, `post_reactions`, `admin_action_logs` 등에 `{public}` role 의 구(舊) 정책이 신규 `authenticated` 정책과 병존. RLS 는 OR 결합이라 구 정책이 실효 접근범위를 넓힌다.
3. **미사용 v1 함수 잔존**: 앱은 `*_v2`(mentor_directory_list_v2 등)를 쓰지만 DB에는 `mentor_directory_list`, `mentor_user_public`, `mentor_profiles_for_directory`, `claim_individual_question(_v2)`, `create_individual_question_with_hold(_v2)`, `qna_create_free_question_thread` 등 구버전이 남아 있다.
4. **`get_weekly_question_usage` 가 anon 에도 EXECUTE grant** — SECURITY DEFINER 이며 인자로 임의 uuid 를 받는다. 내부 가드 여부는 본 조사 범위(경로 수집) 밖.
5. **push 토큰 RPC 미배선**: DB 에 `register_device_token`/`revoke_device_token` + `device_tokens` RLS 가 준비돼 있으나 앱 코드(`lib/core/push/`)에는 HANDOFF 문서와 포트 정의만 있고 실제 호출 코드 없음.
6. **Edge Functions 미사용**: 앱 경로에는 없음(§4). notification_outbox/deliveries, payout 계열 함수는 서버(워커/스케줄러) 전용.
