# 앱–Supabase 접합부 집중 학습 보고서 (2026-07-27)

> 목적: 웹을 전부 배제하고 **앱의 위치·위상(topology)·기능·구조**를 학습한 뒤,
> Supabase 와 연결된 **PR·브랜치·SQL 이 앱과 영향을 주고받는 모든 접합부**를 집중 정리한다.
> 나머지 기능은 접합부로 오가는 **신호를 명확히 검토할 수 있는 수준**으로만 기술한다.
> 방법: `lib/` 전수 코드 탐색(터치포인트 카탈로그 + 구조/신호 맵) + 운영 DB 실측
> (`lbeqxarxothkmzqvpudy` — pg_publication·pg_policies·pg_proc·storage.buckets 읽기 전용 조회,
> DDL/DML 없음) + PR #1~#35 이력 대조. 기준 커밋: `b0ea405`(master).
> 계약 정본은 `docs/APP_V16_SERVER_CONTRACT_SNAPSHOT.md`, 인수인계는 `HANDOFF.md` — 본 문서는
> 그 둘과 실코드·실서버를 **교차 대조한 학습 결과**이며 계약 원문을 복제하지 않는다.

---

## 1. 앱의 위치와 위상 (한 장 요약)

- **위치**: 웹(Next.js, 별도 저장소)의 컴패니언 모바일 앱. 새 백엔드 없이 **웹과 같은 Supabase 1개**를
  anon key + RLS 로만 사용(읽기 중심, Commerce-Zero). Edge Function 호출 0, FCM/OS 푸시 제거(App-F0).
- **부팅 위상**(`lib/main.dart:18-52`, 전부 fail-soft):
  `dotenv → SupabaseInit.ensureInitialized(자격 없으면 skip) → WebSessionHygiene 등록 →
  AuthService.bootstrap(세션복원+onAuthStateChange 구독) → DeepLinkService.initialize(프로덕션 발행자 없음) →
  VersionGateController.start(await 안 함) → runApp`.
- **이중 게이트**: ① **버전 게이트**가 Navigator **위**에 겹침(`app.dart:30-33` → `VersionGateShell`) —
  `forceUpdate/fetchFailed/checking` 은 전 라우트 차단, `recommend` 는 배너만.
  ② **진입 가드**는 라우터 내부(`router.dart:20-24`, `EntryGuard.redirect` 순수함수) —
  `AccessState` 5종 분기, 역할조회 실패는 **fail-closed(blocked)**, admin 차단, `/dev/` 우회.
- **5탭 위상**(`home_shell.dart:38-53`): 질문방(0)·커뮤니티(1, 게스트○)·멘토찾기(2, 게스트○)·
  알림(3)·개별질문(4). 마이페이지는 가상 목적지(=100)로 **push** 진입, pop 시 int 탭 인덱스 반환.
  셸 상시 위젯: `WithdrawalPendingBanner`(탈퇴 예약 배너).
- **신호 체계**(전부 "데이터 없는 세대 카운터 + 각자 재조회" 원칙):
  `TabNavigator.request`(탭 딥링크 채널) · `DataRefreshBus.wallet/subscriptionGeneration` ·
  `AuthService`(ChangeNotifier→라우터 재평가) · Supabase auth 이벤트 팬아웃(signedOut→딥링크 폐기·쿠키 클리어,
  signedIn→pending 딥링크 1건 재생) · 스레드 realtime 콜백 3종 · `AppLifecycleState.resumed`(웹 다녀온 뒤 재조회).
  전역 폴링·페이로드 이벤트버스 없음. 늦은 응답은 세대 토큰으로 폐기.

---

## 2. 접합부 층위 모델 (앱 ↔ Supabase 의 전 접촉면)

앱이 Supabase 를 만지는 길은 아래 **6층이 전부**다. (grep 전수 확인: `functions.invoke` 0건,
`channel(` 1패턴, web_bridge/commerce/push/deeplink/refresh/scan 코어는 Supabase 참조 0)

| 층 | 단일 관문 | 실측 대조 |
|---|---|---|
| L0 환경/클라이언트 | `app_config.dart:16-43`(.env, 플랫폼 분기) → `supabase_client.dart:11-25`(`clientOrNull` 유일 접근점, 자격 없으면 전 레포지토리 AppError) | 운영 = `ssambership-staging`(이름만 스테이징) |
| L1 Auth | `AuthService`(싱글턴): `signInWithPassword`·`signOut`·`onAuthStateChange`(`auth_service.dart:162,268,294`) | `users` 트리거 `handle_new_auth_user` 실존 |
| L2 PostgREST 읽기 | 각 feature `data/` 레포지토리 — RLS 의존 select (아래 §3 표) | 대상 테이블 전부 RLS on·정책 실존 |
| L3 PostgREST 쓰기 | **허용목록 12테이블만**(아래 §3.8) — 질문방·IQ 워크플로 직접 write 금지 | 서버 BEFORE 트리거 가드(qt/qm/qa_direct_write_guard)와 이중 방어 |
| L4 RPC | **27종**(아래 §4) — 워크플로 mutation 은 전부 SECURITY DEFINER RPC | 27종 전부 운영 pg_proc 실존 확인 |
| L5 Storage | 4버킷 실사용 + 1버킷 상수만 잔존(아래 §5) | 버킷·mime·정책 실존 확인 |
| L6 Realtime | 채널 1패턴 `question_thread_{threadId}` × postgres_changes 3바인딩 | **publication 포함 실측 확인**(§6) |

**부재가 곧 설계인 것**: Edge Function 호출 없음(알림 발송은 서버 outbox worker 단독 —
`record_domain_notification`→`notification_outbox`→deliveries, 앱은 절대 호출 금지),
FCM 토큰 등록 경로 제거(App-F0 — `register_device_token`/`revoke_device_token` RPC 는 서버에 실존하나
앱 호출부 0, `device_tokens` 신규 행 없음이 정상), 결제/구매 write 없음(Commerce-Zero).

---

## 3. 접합부 상세 — feature 별 터치포인트

파일 경로는 `lib/` 기준. 행 계약(컬럼)은 각 모델 파일이 정본.

### 3.1 core/auth — 세션·역할·계정상태
- `users` select: `role`(`auth_service.dart:222`), `nickname,full_name`(:245), `status,suspended_until`(`account_status.dart:142`).
  역할조회 예외 → `roleFetchFailed` → **blocked(복구가능)** — active 로 통과시키지 않는다.
- RPC: `account_deletion_write_blocked(p_user_id)`→bool(비bool이면 fail-closed),
  `account_deletion_status_self()`(`account_status.dart:151-162`).
  `account_deletion_jobs` 직접 SELECT 는 **금지**(테이블 GRANT 없음 — 403 정상).
- 차단 판정 상태셋: `locked|purging|storage_purged|finalized|auth_soft_deleted`=write차단,
  `completed`=deleted, `pending`=deletionPending.

### 3.2 core/entitlement — 구독 읽기 전용
- `subscriptions` select 2형: entitled 판정(`entitlement.dart:43`, status ∈ `{active, cancel_scheduled}`)과
  멘토별 요약(`subscription_summary.dart:50`). 실패는 삼켜 `Entitlement.none`.
- 주간 한도는 RPC `get_weekly_question_usage` 반환이 정본 — 앱은 한도 수치를 재하드코딩하지 않는다
  (`weekly_question_usage.dart:58-87`).

### 3.3 core/version_gate — 로그인 전 anon RPC
- RPC `get_mobile_app_version_policy(p_platform)`(`supabase_version_policy_port.dart:21`) — anon EXECUTE.
  클라이언트 없음/실패 → `fetchFailed`(절대 forceUpdate 로 오판 안 함).
  대응 테이블 `mobile_app_version_policies` 는 write=service_role 전용, 읽기 RPC 경유만(SQL 162, PR #33 배선).

### 3.4 question_room — 가장 두꺼운 접합부
- **읽기**(`question_room_read_repository.dart`): `mentor_student_rooms`(필터 없음 — **RLS가 곧 쿼리**),
  `question_threads`(방별/배치 inFilter), `question_messages`(asc), `question_attachments`(desc),
  `connection_notes`, `mentor_profiles.teaching_subjects`, RPC `get_weekly_question_usage`.
- **쓰기 = RPC 6종만**(`question_room_write_repository.dart:41` 헤더에 직접 write 금지 명문):
  `qna_create_question_thread`(무료/구독 분기는 서버 몫 — 래퍼 `qna_create_free_question_thread` 는
  mentors 무료질문 진입부가 사용) · `qna_append_message` · `qna_confirm_thread` ·
  `qna_flag_wrong_answer` · `qna_register_attachment`. 예외: `connection_notes` 만 직접 insert/update.
- **첨부 파이프라인**(`attachments/attachment_upload.dart`): 검증(≤5MB, jpeg/png/webp/heic) →
  `question-room-attachments` 에 `uploadBinary(upsert:false)`, 경로 `{roomId}/{threadId}/{ts}_{name}` →
  RPC `qna_register_attachment` → 실패 시 **보상 삭제**(`remove` — DELETE 정책이 '미등록+본인 소유'만 허용,
  등록된 객체는 서버가 삭제 거부) → 23505 는 `storage_path` select 로 멱등 재확인.
  업로드가 먼저, 등록이 나중 — 순서 고정(`STORAGE_OBJECT_NOT_OWNED`).
- **서명 URL**(`attachment_url_resolver.dart:77`): TTL 1h 메모리 캐시. 열기 전 host 는
  `AppConfig.supabaseUrl` host 와 **정확 일치** 요구(`trusted_attachment_url.dart:9-16`).
- **RLS 우회용 조회 RPC**: `mentor_user_public_v2`(멘토 표시명), `get_mentor_student_nicknames`(uuid[] 배치).
- **오류 계약**: `qna_error_mapper.dart` 가 서버 raise 코드 문자열(P0001 message) 23종을 한글 문구로 매핑.

### 3.5 individual_question(IQ) — 캐시 에스크로 접합부
- 읽기: `individual_questions`(학생 eq / 멘토 or-필터), `individual_question_messages/attachments`,
  `mentor_individual_question_pricing`, `cash_wallets.balance_cents`, 열린질문은 RPC
  `list_open_individual_questions_for_mentor`(본문·학생정보 제거된 위생 목록).
- 쓰기 = RPC 6종: `create_individual_question_as_student`(멱등키 포함) · `claim_individual_question_as_mentor` ·
  `answer_individual_question` · `release_individual_question` · `refund_individual_question`(공개 래퍼 —
  core `_hold` 는 service_role 전용) · `add_individual_question_attachment`(v2 — message_id 소속 검증).
- 첨부(`iq_attachments_repository.dart` + `iq_attachment_upload_core.dart`): 업로드→RPC 등록→보상삭제→
  멱등 재조회를 **순수 함수 코어**로 분리(6개 typedef 주입). `40001`=등록충돌 1회만 재시도,
  `42P10` 은 마이그레이션 167 부재 신호로 폴백 없이 실패(의도).
- 첨삭 원본: 같은 버킷 `{questionId}/annotations/{첨부id}.json` 에 `upsert:true`(테이블 행 미등록 —
  목록은 테이블 기준이라 자연 은닉). 저장소 `supabase/migrations/` 4건이 이 계약의 SQL 근거(§7).
- 서명 URL 캐시 키 = `'{currentUserId}::{storagePath}'` — **계정 전환 누수 방지**(질문방 리졸버와 다른 점).
- 성공 시 `DataRefreshBus.bumpWallet()` 발행(`iq_create_screen.dart:360`, `iq_detail_screen.dart:250,272`)
  → 마이페이지가 지갑 재조회. **캐시 잔액 정합의 유일한 인앱 신호.**

### 3.6 community — 열람 중심 + 소량 직접 write
- 읽기: `community_posts`/`shortform_posts`(status='published', range 페이징),
  댓글은 **정본 분기** — 게시판→`comments`, 숏폼→`community_comments`(`community_models.dart:203`,
  v16 SQL 163 양방향 브리지 전제). 반응 초기상태(`post_reactions`/`shortform_reactions` — 후자는
  RLS 가 본인 행만 select 허용이라 집계는 `shortform_posts` 컬럼에서).
  차단 필터: `user_blocks` 로 클라이언트 필터하되 **nextOffset 은 필터 전 rawCount 로 전진**(P2-21).
- 쓰기: 반응 insert/delete, 댓글 insert(게시판 payload 는 정확히 `{post_id, author_id, content[, parent_id]}` —
  서버 트리거가 보호필드 거부), `community_posts` insert+**보상 delete**(`board_author_gate.dart` 가
  fail-closed 역할 해석과 반환행 재검증 수행), `content_reports` insert, `user_blocks` insert/delete.
- 조회수: RPC `increment_community_post_view`/`increment_shortform_post_view`
  (`community_write_repository.dart:88-99`, 실패 무시) — **운영 DB 에 실존 확인**.
- 숏폼 미디어(App-SF1, PR #35): `shortform_media_url_resolver.dart` — 정본 참조
  `shortform-videos/{userId}/{objectName}` 만 서명(TTL 10분−60s), 경로 위조·중첩·퍼센트 우회 전부
  `invalidReference`(재시도 없는 정직 폴백), legacy 절대 URL 은 서명 0회 통과, 사용자별 캐시 키+single-flight.
- 숏폼 **작성**은 네이티브가 아니라 웹 컴포저 WebView 브릿지(`shortform_compose_screen.dart:56-116`) —
  세션 access/refresh 토큰을 **POST body 로만** 전달(URL 금지). Supabase 접합이 아니라 웹 접합.

### 3.7 mentors / mypage / notifications
- mentors: 디렉터리는 RPC 3종(`mentor_directory_list_v2`(서버 cap 200)·`mentor_profiles_for_directory_v2`·
  `get_mentor_avg_response_hours`) + `reviews`(moderation visible 3중 필터 후 인앱 집계)·`mentor_plans`·
  `favorites`(rw). 무료질문 진입(`free_question_entry.dart`): `mentor_student_rooms`·`free_question_usage`
  select 는 UX 사전검사일 뿐, 강제는 서버(RPC 내부 count).
- mypage: `users`(email,grade_level)·`cash_wallets`·`cash_ledger`(limit 5)·`subscription_settlement_items`
  select + question_room 레포 재사용(교차 feature 집계). `users` update 는 **nickname·grade_level 두 컬럼만**
  (`profile_edit_repository.dart:30`). `notification_settings` upsert(onConflict user_id, groups 정본 5키,
  행 없음=전부 ON — 서버 `notification_delivery_allowed` 와 동일 의미론).
  탈퇴는 self RPC 3종만(`account_deletion_request_self{p_dry_run:false}` 등, SQL 161) —
  42501 → `AccountDeletionUnavailable`(웹 안내 폴백), raw RPC 는 의도적으로 미호출.
- notifications: keyset 커서(`created_at.lt … and(created_at.eq, id.lt)`, created_at 은 **원시 서버 문자열**
  유지 — µs 정밀도), CR 2종은 DB 단계에서 `.not('type','in',…)` 제외, 읽음 update 는
  `{is_read, read, read_at}` + `.eq('user_id', uid)` 방어, 전체읽음은 RPC `mark_all_notifications_read`.
  딥링크는 17종 계약의 metadata ID(question_id/room_id/thread_id)가 정본, **탭 이동만** 수행.

### 3.8 앱의 직접 write 전량 (허용목록 — 이것 외의 PostgREST 쓰기 없음)

| 테이블 | insert | update | upsert | delete | RLS 대응 |
|---|---|---|---|---|---|
| `connection_notes` | ✔ | ✔(body) | — | — | cn_insert/cn_update |
| `post_reactions` / `shortform_reactions` | ✔ | — | — | ✔ | *_own |
| `comments`(게시판 정본) / `community_comments`(숏폼) | ✔ | — | — | — | insert_own + 트리거 가드 |
| `community_posts` | ✔ | — | — | ✔(보상만) | cp_write_self/cp_delete_own |
| `content_reports` | ✔ | — | — | — | insert_reporter |
| `user_blocks` | ✔ | — | — | ✔ | ub_insert_own/ub_delete_own |
| `favorites` | ✔ | — | — | ✔ | *_own |
| `users` | — | ✔(2컬럼) | — | — | users_update_own |
| `notification_settings` | — | — | ✔ | — | modify_own(ALL) |
| `notifications` | — | ✔(읽음 3필드) | — | — | notif_update_recipient_read |

---

## 4. RPC 접합부 27종 — 전부 운영 실존 확인

호출부는 §3 참조. 운영 pg_proc 대조 결과 **27/27 실존**, 전부 SECURITY DEFINER.

- 게이트/계정: `get_mobile_app_version_policy` · `account_deletion_write_blocked` ·
  `account_deletion_status_self` · `account_deletion_request_self` · `account_deletion_cancel_self`
- 질문방: `get_weekly_question_usage` · `qna_create_question_thread` · `qna_create_free_question_thread` ·
  `qna_append_message` · `qna_confirm_thread` · `qna_flag_wrong_answer` · `qna_register_attachment`
- 조회 위생: `mentor_user_public_v2` · `get_mentor_student_nicknames` · `mentor_directory_list_v2` ·
  `mentor_profiles_for_directory_v2` · `get_mentor_avg_response_hours`
- 커뮤니티: `increment_community_post_view` · `increment_shortform_post_view`
- IQ: `list_open_individual_questions_for_mentor` · `create_individual_question_as_student` ·
  `claim_individual_question_as_mentor` · `answer_individual_question` · `release_individual_question` ·
  `refund_individual_question` · `add_individual_question_attachment`
- 알림: `mark_all_notifications_read`

서버에 실존하지만 **앱이 부르지 않는 것도 계약**이다: `record_domain_notification`(서버 전용),
`register_device_token`/`revoke_device_token`(App-F0 로 호출부 제거), raw `account_deletion_request/cancel`
(service_role 전용), `claim_individual_question(_v2)`/`create_individual_question_with_hold(_v2)`(웹/서버측),
`refund_individual_question_hold`(core — 앱은 공개 래퍼만).

## 5. Storage 접합부 — 버킷 5종 (4 실사용 + 1 잔존)

| 버킷 | 앱 작업 | 경로 규약(첫 세그먼트=권한 키) | 실측 |
|---|---|---|---|
| `question-room-attachments` | upload/signedUrl/download/remove | `{roomId}/{threadId}/{ts}_{name}` | private·20MB·이미지+pdf 등, DELETE=미등록+소유자만 |
| `individual-question-attachments` | upload/signedUrl/download/remove + `annotations/*.json` upsert | `{questionId}/{ts}-{salt}.{ext}` · `{questionId}/annotations/{id}.json` | private·20MB·**application/json 포함**(저장소 SQL 로 추가), UPDATE 는 annotations/ 한정 정책 |
| `scan-annotations` | ink.json upsert/download | `{roomId}/{attachmentId}/ink.json` | private, 방 당사자 정책 |
| `shortform-videos` | **signedUrl 만** | `{userId}/{objectName}` | private·500MB·video mime 3종 |
| `connection-note-ink` | (없음 — 상수만 잔존) | — | deprecated, 기존 객체 보존(기능 제거됨) |

앱 mime 검증(≤5MB, 이미지 4종)이 버킷 한도(20MB)보다 좁다 — 클라이언트가 더 보수적, 충돌 없음.

## 6. Realtime 접합부 — 실측으로 해소된 항목

`supabase_realtime` publication 실측: `question_threads`·`question_messages`·`question_attachments`
**3테이블 포함 확인**. HANDOFF §3-3 의 "포함 여부 미확인"은 해소된 스테일 항목이다.
앱 측은 `thread_realtime.dart` 의 채널 1패턴이 전부이며, 미포함이어도 수동 새로고침 폴백으로 동작하도록
설계돼 있다(첨부 바인딩은 PR #27 이 추가 — 웹 마이그레이션 117 과 쌍).

## 7. PR·브랜치·SQL ↔ 접합부 매핑 (이력 학습)

저장소 `supabase/migrations/` 4건 = 앱이 요구해 운영 적용된 SQL 의 기록(전부 2026-07-07 적용 확인):
`20260707T0100`(IQ 첨부 등록 RPC v1) → `20260707T1130`(첨삭 ink.json upsert 용 storage UPDATE 정책,
annotations/ 프리픽스 한정 = 원본 불변의 정책 근거) → `20260707T1500`(RPC v2 — message_id 소속 검증) →
`20260707T1510`(버킷 mime 에 application/json append). 운영 마이그레이션 목록에서 각각
`add_iq_attachment_rpc_s17`·`add_iqa_storage_update_policy_annotations_s18`·`iqa_rpc_message_id_check_v2`·
`iqa_bucket_allow_application_json` 으로 대응 확인.

| PR(브랜치) | 접합부 변화 |
|---|---|
| #5 `claude/quickwin-question-attachments` | 실버킷 `question-room-attachments` 배선, 경로 roomId 접두, `_storageReady=true` |
| #6 `claude/s15-scan-annotation` | `scan-annotations` 버킷 사용 개시(정규화 좌표 ink.json) |
| #8 `claude/image-viewer-annotate` | 서명 URL 리졸버(1h 캐시) + 뷰어 — 읽기 접합 추가 |
| #11 `claude/web-app-service-integration-04wfbf` | IQ 기능 1차 — IQ 테이블/RPC 접합 개시 |
| #19 `feat/s17-iq-attachments` | IQ 첨부 업로드+등록 RPC(위 SQL v1) |
| #20 `claude/s18-iq-annotation` | IQ 첨삭 — AnnotationTarget 포트화, DB 변경 0(정책 1건은 실서버 검토에서 발견·적용) |
| #22 `claude/ssambership-web-app-integration-q90u2r` | RPC v2·버킷 json mime 확정(위 SQL v2·mime) |
| #27 `fix/xv-attach-v2` | 첨부 렌더를 테이블 기준으로 전환 + **question_attachments realtime 구독 추가** |
| #31 `claude/sambership-session-handoff-7z5xdi` | 알림 오분류 차단(CR 2종 DB단 제외)·스레드 정렬 웹 정본 일치 |
| #33 `claude/flutter-app-remediation-0r2k8p` | v16 수렴 — 탈퇴 self RPC 3종 배선(SQL 161), 최소버전 게이트(SQL 162), 댓글 정본 전환(SQL 163), 직접 write→RPC 전환 |
| #35 `claude/app-shortform-media-read-v1-wdwvav` | 숏폼 signed URL 리졸버(App-SF1) — `shortform-videos` 읽기 접합 |
| 열린 PR #23·#29(iOS 빌드) | Supabase 접합 변화 없음 |

## 8. 나머지 기능 — 접합부로 오가는 신호만 (검토 가능 수준)

- **web_bridge / commerce**: Supabase 참조 0. 밖으로 나가는 경계(운영 도메인, https+호스트 allowlist,
  구매 유도 헬퍼 호출부 0). 접합 신호는 단 하나 — 웹에서 돌아온 `resumed` 가 구독/커뮤니티 재조회를 유발.
- **push / deeplink**: 프로덕션 발행자 없음(App-F0). `PushPayload.fromRemote` 는 파싱 단계에서 link/url 폐기,
  딥링크 컨트롤러는 eventId LRU(32)+pending TTL 15분·사용자 스코프. 재도입 시 접합은
  `register_device_token`/`revoke_device_token` RPC 와 `notification_deliveries` 워커 — 서버측은 이미 실존.
- **ink / scan 코어**: 좌표 정규화·래스터화 순수 로직 — Supabase 를 모르고, Storage 경로 규약만
  `ink_storage_paths.dart` 로 공급. `scribble` 를 아는 파일은 어댑터 1개뿐.
- **design / labels / constants**: 표시 규칙(내부 코드값 노출 금지, 과목 한글 매핑 — DB 전송은
  `subjects.code` 35종만, 미등재 code 는 서버가 조용히 NULL 처리하므로 정본 code 전송이 앱 책임).
- **죽은/휴면 코드**: `onboarding_screen.dart`(라우터 미연결), `health_repository.dart`(호출부 0),
  `connection-note-ink` 상수(§5). 접합 검토 시 노이즈로 오인하지 말 것.

## 9. 정합성 소견 (학습 중 발견한 스테일·리스크)

**문서가 코드·DB보다 뒤처진 곳(스테일 — 기능 결함 아님)**
1. HANDOFF §3-3 / FEATURE_STATUS "Realtime publication 미확인·인프라 필요" → 실측 **이미 포함**(§6).
2. FEATURE_STATUS "커뮤니티 조회수 증분 RPC 부재/미완(`incrementView` 부재)" → 현재 코드는
   `community_write_repository.dart:88-99` 에서 호출 중이고 RPC 도 운영 실존. 해당 표기는 구버전 기준.

**접합부 관점의 주의점(동작하지만 알고 있어야 할 것)**
3. `mentor_plans` 조회가 `is_active` 를 필터하지 않는다(`mentor_directory_repository.dart:174-177`) —
   비활성 플랜이 섞여도 표시 로직이 감내하는지 확인 여지.
4. 질문방 서명 URL 캐시는 storagePath 단독 키(1h) — IQ·숏폼처럼 사용자 키가 없다. 같은 기기 계정 전환 시
   이론상 캐시 잔존(방 당사자 간이라 실위험 낮음, 일관성 차원의 여지).
5. 가장 약한 테스트 심: `chat_screen`·`mentor_*`·`connection_notes_screen` 의 read/write 레포가 const
   하드 인스턴스(포트 아님), `EntitlementReader`/`SubscriptionReader` 는 static+클라이언트 인자.
   `MentorDirectory/Favorites/MyPage/IndividualQuestion/Lookup` 레포도 포트 추상 없음 — 접합부 계약
   변경 시 위젯테스트로 못 잡고 통합(e2e_staging)으로만 검증된다.
6. `shortform_reactions` 는 RLS 상 본인 행만 select — 집계는 `shortform_posts` 컬럼이 정본(앱 준수 중).
7. 앱이 부르지 않는 서버 RPC 들(§4 말미)은 "부재가 계약" — 재도입·신규 기능 시 임의 호출 금지 목록으로 취급.

**접합부 변경 검토 체크리스트(요약)** — 어떤 PR/SQL 이 오면 이 순서로 본다:
① 어느 층(L0~L6)인가 → ② 정본 계약(`APP_V16_SERVER_CONTRACT_SNAPSHOT.md`)과 오류코드 문자열이 변했나 →
③ 경로 첫 세그먼트=권한 키 규약이 유지되나 → ④ 직접 write 허용목록(§3.8)이 늘어나는가(늘면 서버 가드 확인) →
⑤ 멱등키·보상삭제·세대토큰 패턴이 깨지지 않나 → ⑥ 실측 대조(pg_proc/pg_policies/publication/buckets).
