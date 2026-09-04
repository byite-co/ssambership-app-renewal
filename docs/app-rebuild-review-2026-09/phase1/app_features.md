# 기존 Flutter 앱 기능 인벤토리 · 서버 표면 리포트 (Phase 1)

- 대상 저장소: `/home/user/ssambership-app` (앱) · `/home/user/ssambership_web` (웹 · DB 정본)
- 작성 기준일: 2026-09-03 · 읽기 전용 조사(저장소 파일 수정 없음)
- 범위: 프론트 구조 · Supabase RPC/RLS/Storage/Realtime · DB 표면. **UI 디자인·색·레이아웃은 다루지 않는다.**
- 표기: 경로는 앱 저장소 루트 상대(`lib/...`, `test/...`, `docs/...`). 웹 저장소는 `web:` 접두. 코드로 확인하지 못한 항목은 **(확인 필요)**.
- 스키마 표기: 별도 표기가 없으면 `public`. `api_web_v1` = 읽기 뷰·self RPC, `api_app_v1` = 앱 전용 쓰기 RPC.

## 0. 전제·아키텍처 요약(사실만)

| 항목 | 사실 | 근거 |
|---|---|---|
| DB 정본 | 앱 저장소에 SQL 없음. 웹 저장소 `supabase/migrations/` pack 이 정본. staging 프로젝트 ref `lbeqxarxothkmzqvpudy` | `supabase/SCHEMA_SOURCE_OF_TRUTH.md` |
| 아웃바운드 표면 잠금 | 앱이 호출 가능한 RPC/테이블/뷰/스키마/버킷 이름 집합을 테스트로 고정(집합 불일치 시 실패). `firebase` 문자열 0건, `community_posts` 베이스 테이블 직접 접근 0건, `from('users')` 체인에 `.update(`/`.insert(` 금지 | `test/contracts/outbound_api_manifest_test.dart:15-149`, `:298-326` |
| 결제 Commerce-Zero | 인앱 결제·구독·충전 없음. `Entitlement.inAppPurchaseEnabled=false`, `kInAppPaymentSteeringEnabled=false`. 관리 링크는 dart-define 기본 OFF | `lib/core/entitlement/entitlement.dart:23`, `lib/core/commerce/commerce_policy.dart:10,17-18,29-30` |
| 부팅 순서 | dotenv → Sentry → `SupabaseInit.ensureInitialized` → `WebSessionHygiene.register` → `AuthService.bootstrap` → `DeepLinkService.initialize` → `VersionGateController.start` | `lib/main.dart:24,29-35,39,44,49,55` |
| 접근 상태 | `AppRole {student, mentor, admin, guest}` · `AccessState {loading, loggedOut, guest, full, blocked}` · admin → blocked · role 불명 → blocked · users 조회 실패 → 재시도 가능 blocked(fail-closed) | `lib/core/auth/auth_service.dart` (users 조회 `:221-225`: `select('role, nickname, full_name, status, suspended_until').eq('id', uid)`) |
| 라우팅 | `/splash` `/login` `/home` `/blocked` `/dev/gallery` `/dev/s3`; 게스트 허용 탭 `{1,2}`(커뮤니티·멘토 찾기) | `lib/app/entry_guard.dart:14-19,25` |
| 탭 | questionRoom=0 · community=1 · mentors=2 · notifications=3 · individualQuestion=4 · myPage=100(가상, push) | `lib/app/app_tabs.dart:10-19` |
| 실시간 | postgres_changes 채널 3종(질문방 스레드·개별질문·알림). 보조 수단이며 정본은 서버 재조회 | `lib/features/question_room/data/thread_realtime.dart:44-85`, `lib/features/individual_question/data/iq_realtime.dart:54-95`, `lib/features/notifications/data/notifications_realtime.dart:47-55` |
| 푸시 | OS 푸시 없음(App-F0). FCM·`register_device_token` 제거. `DisabledPushPermission` 만 존재 | `lib/core/push/HANDOFF.md:1-4,17-22`, `lib/core/push/push_ports.dart` |
| 관측 | Sentry(`SENTRY_DSN`, `SENTRY_ENVIRONMENT` 기본 `staging`), `sendDefaultPii=false`, tracing off | `lib/core/observability/crash_reporting.dart` |
| 환경 | `.env`: `SUPABASE_URL` / `SUPABASE_URL_LAN` / `SUPABASE_ANON_KEY` | `lib/core/config/app_config.dart` |

---

## 1. 기능별 인벤토리

상태 범례: **완전** = 앱에서 E2E 동작 · **부분** = 일부 경로만 · **스텁** = 코드는 있으나 프로덕션 그래프 밖 · **제외** = 의도적 미제공(웹 위임).

### 1.1 인증 · 게스트

| 기능 | 화면 클래스 | 사용자 액션 | 서버 표면 | 게이트/플래그 | 상태 | 알려진 갭 |
|---|---|---|---|---|---|---|
| 이메일/비밀번호 로그인 | `LoginScreen` (`lib/features/auth/login_screen.dart:20`) | signInWithPassword | Supabase Auth · `users` SELECT(`role, nickname, full_name, status, suspended_until`) | — | 완전 | 회원가입은 안내 문구만(링크 없음) — `docs/RELEASE_SCOPE_DECISIONS_2026-07.md:15-21` |
| 둘러보기(게스트) | `LoginScreen` → `enterAsGuest` | 탭 1·2만 접근 | 없음 | `EntryGuard.guestAllowedTabs={1,2}` (`lib/app/entry_guard.dart:25`) | 완전 | — |
| 계정 상태 판정 | `AuthService.computeAccess` · `AccountStatus` | 자동 | `users.status`(banned/suspended + `suspended_until`) · RPC `account_deletion_write_blocked(p_user_id)`→bool (`lib/core/auth/account_status.dart:151-152`) · RPC `account_deletion_status_self()` (`:162`) | admin 은 항상 blocked | 완전 | — |
| 탈퇴 대기 배너 | `WithdrawalPendingBanner` (`lib/shared/widgets/withdrawal_pending_banner.dart`), `DeletionNoticeController` (`lib/core/auth/deletion_notice_controller.dart`) | 취소 버튼 | `account_deletion_status_self` → `{ok, exists, state, cancelable_until, write_blocked, can_cancel}` · job state `pending|locked|purging|storage_purged|finalized|auth_soft_deleted|completed|canceled|failed` | canCancel = 서버 `can_cancel && !write_blocked && state=='pending'` | 완전 | — |
| 차단 화면 | `BlockedScreen` (`lib/features/auth/blocked_screen.dart:13`) | 로그아웃 | — | — | 완전 | — |
| 온보딩 | `OnboardingScreen` (`lib/features/onboarding/onboarding_screen.dart:9`) | — | — | 라우트 미등록 | 스텁 | `docs/RELEASE_SCOPE_DECISIONS_2026-07.md:15-21` 온보딩 미제공 결정 |
| 소셜 로그인 · 회원가입 · 비밀번호 재설정 | — | — | — | — | 제외 | 웹 위임(§4) |

### 1.2 질문방 — 학생

| 기능 | 화면 클래스 | 사용자 액션 | 서버 표면 | 게이트/플래그 | 상태 | 알려진 갭 |
|---|---|---|---|---|---|---|
| 내 방 목록 | `QuestionRoomScreen` (`lib/features/question_room/question_room_screen.dart:36`) `_StudentRoomList` | 조회 | `mentor_student_rooms` select * (RLS) (`question_room_read_repository.dart:45,55`) · `subscriptions(mentor_id, status, plan_tier, current_period_end, next_billing_at)` (`lib/core/entitlement/subscription_summary.dart:51`) · `api_web_v1.mentor_directory_v1(mentor_id, nickname)` (`mentor_lookup_repository.dart:47-48`) · `api_web_v1.rpc weekly_question_usage_self_batch(p_mentor_ids)` → `{ok, contract_version:1, items:[{mentor_id, used, limit, remaining, can_ask, ...}]}` (`question_room_read_repository.dart:171-172`) · `question_threads(mentor_student_room_id, status, updated_at)` (`:87`) | — | 완전 | 방 INSERT 는 앱에 없음(구독/무료질문 RPC 가 서버에서 생성) |
| 방 홈 | `MentorRoomHomeScreen` (`ui/mentor_room_home_screen.dart:19`) | 질문 목록 · 연결노트 진입 | `mentor_profiles.teaching_subjects` by user_id (`question_room_read_repository.dart:121`) | — | 완전 | — |
| 질문 목록 | `QuestionListScreen` (`ui/question_list_screen.dart:25`) | 목록 · 확인(confirm) | `question_threads` by room order updated_at desc (`:65,75`) · `api_web_v1.rpc weekly_question_usage_self(p_mentor_id)` → `{used, limit, remaining, can_ask, plan_tier, week_start, week_end}` (`:148-149`; 모델 `lib/core/entitlement/weekly_question_usage.dart`, `limit>=999` = 무제한) · RPC `qna_confirm_thread(p_thread_id)` (`question_room_write_repository.dart:176-177`) | canAsk = `usage.canAsk ?? subscription.canAsk` | 완전 | — |
| 새 질문 | `NewQuestionScreen` (`ui/new_question_screen.dart:18`) | 제목·과목·본문 입력 | RPC `qna_create_question_thread(p_room_id, p_title, p_subject, p_topic, p_first_message_body)` → `{thread_id, message_id, path, used_free_quota}` (`question_room_write_repository.dart:82-83`) | A1 과목 제한 `restrictQuestionSubjectCodes(멘토 teaching_subjects)` (`new_question_screen.dart:172-176`) · A2 사전 체크 `usage.canAsk` fail-closed (`:81-92`) | 완전 | `p_topic` 은 앱이 보내지 않음(`docs/FEATURE_AUDIT.md` A4) · A2 서버 강제는 `docs/FEATURE_AUDIT.md:51` "부분해결(앱 계층)" — 서버 측 RPC 가 WEEKLY_LIMIT_EXHAUSTED 를 던지는지 **(확인 필요)** |
| 대화(채팅) | `ChatScreen` (`ui/chat_screen.dart:39`), `LiveMessageList`, `ChatInputBar` | 메시지 전송 · 첨부 · 주석 · 차단/신고 | `question_messages` recent(limit, order created_at desc, id desc) (`question_room_read_repository.dart:225`) · `messagesBefore` 키셋 `created_at.lt."ts",and(created_at.eq."ts",id.lt."id")` (`:246`) · RPC `qna_append_message(p_thread_id, p_body)` → `{ok, message_id, answered_transition}` (`question_room_write_repository.dart:129-130`) · `question_attachments` by thread (`:270`) · Realtime 채널 `question_thread_<id>` (INSERT question_messages(thread_id=) · UPDATE question_threads(id=) · INSERT question_attachments(thread_id=)) (`thread_realtime.dart:44-85`) | THREAD_LOCKED 등 서버 코드(§1.2 하단) | 완전 | Realtime 은 `supabase_realtime` publication 에 세 테이블 포함이 전제(`docs/APP_FEATURE_STATUS.md`; 웹 117 migration) — 실환경 publication 멤버십 **(확인 필요)** |
| 첨부 업로드 | `SupabaseAttachmentUploader` (`data/attachments/attachment_upload.dart:131`) | 카메라/갤러리/파일/PDF | 버킷 `question-room-attachments` · path `{roomId}/{threadId}/{ts}_{safeName}` · 5MB (`:27`) · MIME jpeg/png/webp/heic (`:20`) · `uploadBinary(upsert:false)` (`:374`) → RPC `qna_register_attachment(p_thread_id, p_storage_path, p_file_name, p_mime_type, p_message_id)` → `{attachment_id, answered_transition}` (`:386-387`) · 실패 시 보상 `remove` (`:400-402`) · 23505 멱등 수용(`question_attachments` select by storage_path `:408`) | Storage INSERT 정책 `qra_storage_insert_party` · 미등록 객체 삭제 정책 `qra_storage_delete_unregistered_owner` (주석 기준 · **확인 필요**) | 완전 | — |
| 첨부 보기 | `AttachmentViewerScreen` (`ui/attachment_viewer_screen.dart:18`), `AttachmentUrlResolver` (`data/attachments/attachment_url_resolver.dart:94-99`) | 확대 · 주석 진입 | `createSignedUrl` TTL 1h · 캐시 키 `{uid}::{path}` · `download` | `trusted_attachment_url.dart` host == Supabase host | 완전 | — |
| 차단/신고(방 상대) | `RoomSafetyMenu`/`RoomSafetyActions` (`ui/widgets/`), `RoomSafetyRepository` (`data/room_safety_repository.dart:56`) | 상대 차단 · 신고 | `content_reports` insert `{reporter_id, target_type:'user', target_id, reason, description?, status:'pending'}` (`:73-75`) · `user_blocks` (§1.7) | qna RPC 는 차단 시 `BLOCKED` 반환(`docs/S3E_QUESTION_ROOM_SAFETY_CONTRACT.md`) | 완전 | — |

**qna 에러 코드(서버 `raise exception 'CODE'` → 한국어 매핑, `lib/features/question_room/data/qna_error_mapper.dart`):** WEEKLY_LIMIT_EXHAUSTED · FREE_QUOTA_TOTAL_EXHAUSTED · FREE_QUOTA_MENTOR_EXHAUSTED · FREE_QUOTA_EXPIRED · SUBSCRIPTION_REFUND_PENDING · THREAD_LOCKED · NOT_ANSWERED · ACCOUNT_BANNED/SUSPENDED/NOT_ACTIVE/DELETION_IN_PROGRESS · ROLE_NOT_STUDENT · MENTOR_NOT_APPROVED · MENTOR_NOT_FOUND · ROOM_ENSURE_FAILED · NOT_ROOM_PARTY · STUDENT_ONLY · MENTOR_CANNOT_CREATE_THREAD · BLOCKED · STORAGE_PATH_REQUIRED/MISMATCH · STORAGE_OBJECT_NOT_OWNED · MESSAGE_THREAD_MISMATCH · THREAD_NOT_FOUND · ROOM_NOT_FOUND · AUTH_REQUIRED · TITLE_REQUIRED · BODY_REQUIRED.

### 1.3 질문방 — 멘토

| 기능 | 화면 클래스 | 사용자 액션 | 서버 표면 | 게이트/플래그 | 상태 | 알려진 갭 |
|---|---|---|---|---|---|---|
| 받은 질문함 | `MentorInboxScreen` (`ui/mentor/mentor_inbox_screen.dart:25`) | 학생별 방 목록 | `mentor_student_rooms` · `question_threads` (threadsForRooms/threadStatusRowsForRooms) · RPC `get_mentor_student_nicknames(p_student_ids)` → `[{id, nickname, full_name}]` (`data/student_lookup_repository.dart:54-55`) | — | 완전 | — |
| 학생 방 홈 | `StudentRoomHomeScreen` (`ui/mentor/student_room_home_screen.dart:26`) | 질문 목록 · 연결노트 | 위와 동일 | — | 완전 | — |
| 질문 목록(상태 탭) | `MentorQuestionListScreen` (`ui/mentor/mentor_question_list_screen.dart:20`) | 전체/대기/진행/완료 탭 · 과목 필터 | `question_threads` | — | 완전 | — |
| 답변 | `MentorAnswerScreen` (`ui/mentor/mentor_answer_screen.dart:42`) | 메시지·첨부·주석 | `qna_append_message` (answered_transition 로 pending→answered 전이 감지) · `qna_register_attachment` · Realtime 동일 | 서버가 `MENTOR_CANNOT_CREATE_THREAD` 로 멘토 스레드 생성 차단 | 완전 | — |

### 1.4 연결노트

| 기능 | 화면 클래스 | 사용자 액션 | 서버 표면 | 상태 | 알려진 갭 |
|---|---|---|---|---|---|
| 노트 열람·작성(양측) | `ConnectionNotesScreen` (`ui/connection_notes_screen.dart:23`) | 내 노트 upsert | `connection_notes` select by `mentor_student_room_id` (`question_room_read_repository.dart:260`) · 직접 select/update(`body, updated_at`)/insert(`{mentor_student_room_id, author_id, author_role, body}`)/중복 행 delete (`question_room_write_repository.dart:203-238`) | 완전 | 필기(ink) 기능은 2026-07-06 제거 — `ink_path`·`ink_thumb_path` 컬럼과 버킷 `connection-note-ink` 경로 규약(`lib/core/ink/ink_storage_paths.dart:11-12,21`)은 남아 있으나 쓰기 없음(`docs/APP_FEATURE_STATUS.md`). RPC 없이 직접 테이블 쓰기(웹 정본 RPC 존재 여부 **확인 필요**) |

### 1.5 첨부 · 스캔 · 주석 · PDF

| 기능 | 화면/클래스 | 서버 표면 | 상태 | 알려진 갭 |
|---|---|---|---|---|
| 스캔 소스 선택 | `ScanSourcePicker` (`lib/core/scan/scan_source_picker.dart`) `ScanSource {camera, gallery, file}` · image_picker quality 85 · max 4096px · file_picker ext jpg/jpeg/png/webp/heic/pdf | — | 완전 | — |
| PDF 래스터화 | `PdfRasterizer` (`lib/core/scan/pdf_rasterizer.dart`, pdfx) 긴 변 2560 · 썸네일 320 · 1회 최대 5쪽 · `PdfPageSelectScreen` (`lib/core/scan/widgets/pdf_page_select_screen.dart:16`) | — | 완전 | 다중 페이지는 순차 전송(`chat_screen.dart`) |
| 다운스케일 | `image_downscaler.dart` >5MB → 2560 JPEG q85 (compute) | — | 완전 | — |
| 스캔 주석 | `ScanAnnotationScreen(background, roomId?, threadId?, target?, initial?, title?, initialPenColor)` (`lib/features/scan_annotation/scan_annotation_screen.dart:30`) · 포트 `AnnotationTarget` · `QuestionRoomAnnotationTarget` → `ScanAnnotationRepository.submit` | 평탄화 PNG 는 `SupabaseAttachmentUploader` 로 질문방 첨부 등록 → ink.json 을 버킷 `scan-annotations` `{roomId}/{attachmentId}/ink.json` upsert (`scan_annotation_repository.dart:113`; 경로 `ink_storage_paths.dart:13-14,24`) | 완전(질문방) | IQ 첨삭은 닫힘(§1.6) |
| Ink 문서 포맷 | `lib/core/ink/ink_document.dart` JSON 봉투 `format:'ssambership.ink'`, v1, engine `scribble`, canvas w/h, `input_mode pen_only|pen_and_touch`, sketch | — | 완전 | — |

### 1.6 개별질문(IQ) — 학생 / 멘토

| 기능 | 화면 클래스 | 사용자 액션 | 서버 표면 | 게이트/플래그 | 상태 | 알려진 갭 |
|---|---|---|---|---|---|---|
| 탭 진입 | `IndividualQuestionTabScreen` (`lib/features/individual_question/individual_question_tab_screen.dart:14`) | role 분기 | — | `kIndividualQuestionEnabled=true` (`iq_flags.dart:9`) | 완전 | — |
| 학생 목록 | `StudentIqListScreen` (`ui/student_iq_list_screen.dart:22`) | 목록 · 작성 CTA | `individual_questions` eq student_id limit 50 (`data/individual_question_repository.dart:61`) | 작성 CTA → `openIqCreateWeb` (웹) | 완전 | 네이티브 작성 `IqCreateScreen` (`ui/iq_create_screen.dart:42`) 은 `kIndividualQuestionCreateEnabled = bool.fromEnvironment('IQ_CREATE_ENABLED', false)` (`iq_flags.dart:19-20`) 이며 2026-08-05 프로덕션 그래프 제거 → **스텁** |
| 멘토 목록·클레임 | `MentorIqListScreen` (`ui/mentor_iq_list_screen.dart:26`) | 열린 질문 클레임 | `individual_questions.or('designated_mentor_id.eq.uid,claimed_mentor_id.eq.uid')` (`:73`) · RPC `list_open_individual_questions_for_mentor(p_limit)` (`:84-85`) · RPC `claim_individual_question_as_mentor(p_question_id)` (`:190-191`) | — | 완전 | — |
| 상세·대화 | `IqDetailScreen` (`ui/iq_detail_screen.dart:85`, 1618줄) | 메시지 · 첨부 · 환불/정산 · 저장 | `individual_question_messages` by question_id asc (`:112`) · `individual_question_attachments` (`:123`) · RPC `iq_append_message(p_question_id, p_body)` → `{ok, message_id, answered_transition}` (`:209-210`) · RPC `release_individual_question` (`:233-234`) · RPC `refund_individual_question` (`:242-243`) → `IqEscrowResult {ok, code, message, question_id, status, wallet_balance_cents}` · Realtime `iq_<questionId>` (INSERT messages(question_id=) · INSERT attachments(question_id=) · UPDATE individual_questions(id=)) (`iq_realtime.dart:54-95`) | 가드 `iqCanStudentRelease(answered)` · `iqCanStudentRefund(대기)` · `iqCanMentorAnswer(claimed|assigned)` · `iqCanMentorSendFollowUp(answered)` (`models/individual_question_models.dart`) | 완전 | `_canAnnotateGroup` 이 항상 false (`iq_detail_screen.dart:1006`) — IQ 첨삭 UI 닫힘(2026-08). `answer_individual_question` 서버 함수는 더 이상 호출 안 함 |
| 첨부 업로드 | `IqAttachmentsRepository` (`data/iq_attachments_repository.dart:40`), `iq_attachment_upload_core.dart` | 파일 첨부 | 버킷 `individual-question-attachments` (`individual_question_repository.dart:36`) · path `{questionId}/{ts}-{salt}.{ext}` · RPC `add_individual_question_attachment(p_question_id, p_storage_path, p_file_name, p_mime_type, p_message_id?)` 이중 반환(레거시 uuid 문자열 \| jsonb `{ok, attachment_id, question_id, storage_path, status created|existing, idempotent_hit, message_id_mismatch}` — 웹 SQL 168) · 40001 1회 재시도 · 미등록 확정 시만 보상 delete (`:101`) · `individual_question_attachments` select by question_id+storage_path (`:137`) · `download` (`:150`) | 20MB(`iq_attachment_policy.dart:11`, 버킷 20971520) · MIME png/jpeg/webp/gif/pdf/zip/docx/pptx + 매직바이트 검사 | 완전 | — |
| 첨삭 저장 | `IqAnnotationRepository` (`data/iq_annotation_repository.dart:85-121`) | (UI 닫힘) | ink.json upsert `{questionId}/annotations/{attachmentId}.json` (`ink_storage_paths.dart:16,51`) — IQ 버킷 `annotations/` prefix UPDATE 정책 | — | 부분(저장소 계층만) | UI 진입 없음 |
| 파일 저장 | `iq_attachment_saver.dart` FilePicker.saveFile | 기기 저장 | storage download (RLS `iqa_storage_read_party` 주석 기준 · **확인 필요**) | — | 완전 | — |
| 가격·지갑 조회 | `fetchMentorPricing` / `fetchWalletBalanceCents` | 표시 | `mentor_individual_question_pricing` by mentor_id (`:133`) · `api_web_v1.my_wallet_v1(balance_cents)` (`:145-146`) | — | 완전 | — |
| 학생 작성(네이티브) | `IqCreateScreen` | — | RPC `create_individual_question_as_student(p_question_type open|direct, p_title, p_body, p_amount_cents, p_designated_mentor_id, p_idempotency_key)` (`:170-171`) | `IQ_CREATE_ENABLED` OFF | 스텁 | `docs/PLAY_STORE_REVIEW_PLAN.md:304,340` D-1 결정 |

**IQ 상태·모델(`models/individual_question_models.dart`):** type `direct|open` · status `escrowed/assigned/open/claimed/answered/released/expired/refunded/canceled/unknown` · `IndividualQuestion(id, student_id, question_type, status, title, body, price_cents, designated_mentor_id, claimed_mentor_id, subject, topic, required_school_tier, required_major_category, expires_at, answered_at, released_at, refunded_at, created_at)` · `IqMessage(id, question_id, author_id, body, created_at)` · `IqAttachment(id, storage_path, message_id, author_id, file_name, mime_type, created_at)` · `IqPricing(mentor_id, amount_cents)`.
**IQ 에러 코드(`data/iq_error_mapper.dart`):** AUTH_REQUIRED · BODY_REQUIRED · QUESTION_NOT_FOUND · NOT_QUESTION_PARTY · ACCOUNT_* · BLOCKED · QUESTION_LOCKED · NOT_ANSWERABLE_STATUS · MENTOR_NOT_APPROVED · STORAGE_OBJECT_NOT_FOUND/NOT_OWNED · MIME_MISMATCH/NOT_ALLOWED · SIZE_EXCEEDED · MESSAGE_NOT_IN_QUESTION · MESSAGE_AUTHOR_MISMATCH; 레거시 `iqFailureMessage`: CASH_INSUFFICIENT · MENTOR_PRICE_NOT_SET · NOT_QUESTION_OWNER/MENTOR · REFUND_NOT_ALLOWED · already_released/refunded/claimed · CLAIM_FAILED.

### 1.7 커뮤니티 — 게시판 / 숏폼 / 댓글 / 반응 / 신고 / 차단 / 내 활동

| 기능 | 화면 클래스 | 사용자 액션 | 서버 표면 | 게이트/플래그 | 상태 | 알려진 갭 |
|---|---|---|---|---|---|---|
| 허브 | `CommunityScreen` (`lib/features/community/community_screen.dart:20`) 탭 숏폼/게시판/내 활동 | — | — | 게스트 읽기 허용 | 완전 | — |
| 게시판 목록 | `BoardListView` (`ui/board/board_list_view.dart`, 20건 페이지) | 카테고리 필터 | `api_web_v1.community_posts_v1` select * eq status published [eq category] order created_at desc range (`data/community_read_repository.dart:71-72`) · 차단 작성자 클라이언트 필터(author_id) (`:33-38,80-83`) | — | 완전 | 카테고리 `study/school/career/college/free` (`data/community_labels.dart`) |
| 게시판 상세 | `BoardDetailScreen` (`ui/board/board_detail_screen.dart:30`) | 조회수 · 반응 · 댓글 · 신고 · 차단 · 본인 수정/삭제 | RPC `community_post_view_record_v2(p_post_id, p_event_key)` → `{ok, incremented}` (`data/community_write_repository.dart:105`) · `post_reactions{user_id, post_id, type}` insert/delete (`:55-62`) · 댓글 읽기 `api_web_v1.community_comments_v1` filter post_id (`community_read_repository.dart:128`, 100건) · 댓글 쓰기 `comments{post_id, author_id, content[, parent_id]}` insert (`comments_gateway.dart:53`) · 신고 `content_reports` target_type `community_post` (`board_detail_screen.dart:228`) / `board_comment` (`:312`) · 본인 삭제 `api_app_v1.rpc community_post_soft_delete(p_post_id)` → `{ok, contract_version:1, post_id, deleted_at[, already_deleted]}` (`community_write_repository.dart:233-234`) | — | 완전 | **게시판 댓글 본인 삭제 없음**(앱 미구현) — 웹 DB-3 `soft_delete_own_content('board_comment')` 로 채울 수 있음(§6) |
| 게시글 작성 | `BoardWriteScreen` (`ui/board/board_write_screen.dart:25`) | 제목·본문·카테고리·이미지≤5 | `api_app_v1.rpc community_post_create(p_title, p_body, p_category, p_idempotency_key uuidv4, p_image_refs, p_status:'published')` → `{ok, post_id, idempotent_replay, contract_version:1}` (`data/board_post_create_gateway.dart`, 호출 `community_write_repository.dart:340-341`) · 이미지 버킷 `community-post-images` private 5MB MIME jpeg/png/webp/gif · path `{uid}/{ts}_{safeName}` · ref `community-post-images/{uid}/{object}` (`data/board_post_media_gateway.dart:25,110,120`) | `ContentPolicyGate` prefs `content_policy_agreed_v1` (`ui/widgets/content_policy_gate.dart`) | 완전 | RLS `cpi_auth_insert_own`/`cpi_auth_delete_own`/`cpi_public_read` 주석 기준 **(확인 필요)** |
| 게시글 수정 | `BoardWriteScreen`(edit) | — | `api_app_v1.rpc community_post_update(p_post_id, p_title, p_body, p_category, p_expected_updated_at raw, p_image_refs, p_status)` → `{ok, post_id, updated_at, removed_image_refs, contract_version:1}` (`data/board_post_update_gateway.dart`, 호출 `:380-381`) · 코드 POST_NOT_FOUND_OR_NOT_OWNED · UPDATE_CONFLICT | — | 완전 | — |
| 숏폼 피드 | `ShortformFeedView` (`ui/shortform/shortform_feed_view.dart`) | 목록 · 멘토 작성 CTA | `shortform_posts` status published (`community_read_repository.dart:93,242`) · 영상 signed URL `ShortformMediaUrlResolver` 버킷 `shortform-videos` ref `shortform-videos/{uuid}/{objectName}` TTL 10분 · 레거시 http(s) 통과 (`data/shortform_media_url_resolver.dart:98,278`) | 멘토만 작성 CTA | 완전 | `thumbnail_url` 은 웹이 NULL 로 저장(`docs/APP_FEATURE_STATUS.md`) · 정책 `sfv_public_read` 로 anon 서명 URL 실기기 검증 **(확인 필요)** |
| 숏폼 상세 | `ShortformDetailScreen` (`ui/shortform/shortform_detail_screen.dart:31`) | 재생(video_player) · 조회 · 반응 · 댓글 · 신고 · 차단 · 본인 댓글 삭제 | RPC `shortform_view_record_v2(p_post_id, p_event_key)` (`community_write_repository.dart:129`) · `shortform_reactions{user_id, shortform_id, type}` (`:78-85`) · 댓글 읽기 `community_comments` `{post_type:'shortform', post_id, status:'visible'}` (`community_read_repository.dart:122-128`) · 댓글 쓰기 `community_comments{post_type, post_id, author_id, body, status:'visible'}` (`community_write_repository.dart:156-164`) · 본인 댓글 삭제 RPC `community_comment_soft_delete_self(p_comment_id)` → `{ok, contract_version:1, comment_id, idempotent_hit}` (`comments_gateway.dart:61-62`) · 신고 target_type `shortform_post` (`:291`) / `community_comment` (`:307`) · 차단 대상 조회 `shortform_posts`/`community_comments`.author_id (`:321,331`) | — | 완전 | — |
| 숏폼 작성(WebView 브릿지) | `ShortformComposeScreen` (`ui/shortform/shortform_compose_screen.dart:24`), `ShortformComposeBridge` (`lib/core/web_bridge/shortform_compose_bridge.dart:20-23`) | 웹 작성기 | POST `/api/app-session/bootstrap` body `{access_token, refresh_token, target:'shortform_create'}` → `/app/community/shortform/new` → 완료 `/app/bridge/complete?kind=shortform&result=draft|published` / 오류 `/app/bridge/error` · 네비 allowlist = 정확 host + 4 경로 · Android file selector mp4/mov/webm | 멘토만 | 완전 | 종료 시 `WebViewCookieManager().clearCookies()` (`lib/main.dart:39`) |
| 내 활동 | `MyActivityView` (`ui/activity/my_activity_view.dart`) | 내 글/반응 | `post_reactions`/`shortform_reactions` (user_id, type) (`community_read_repository.dart:149,168`) · `community_posts_v1` 본인 글 (`community_write_repository.dart:407-408`) | — | 완전 | — |
| 차단 관리 | `BlockedUsersScreen` (`ui/blocks/blocked_users_screen.dart:13`), `UserBlocksRepository` (`data/user_blocks_repository.dart:35`) | 차단/해제 | `user_blocks(blocker_id, blocked_id)` select (`:95`)/insert (`:187`)/delete (`:207`) · RPC `my_blocked_users()` → `[{blocked_id, nickname, created_at}]` (`:136`) · 30초 캐시 · `blockAuthorOf(table ∈ comments|community_comments|shortform_posts, id)` (`:247`) | RLS `ub_*_own` 주석 기준 **(확인 필요)** | 완전 | — |
| 신고 시트 | `ReportSheet` (`ui/widgets/report_sheet.dart`) | 사유 선택 | `content_reports` insert (`community_write_repository.dart:423-425`) 사유 `inappropriate/spam/external_contact/copyright/etc` | 서버 allowlist target_type `community_post/shortform_post/board_comment/community_comment/user` (`docs/S3E_QUESTION_ROOM_SAFETY_CONTRACT.md`) | 완전 | — |

**community_post 에러 코드(`data/community_post_error_mapper.dart`):** AUTH_REQUIRED · ROLE_NOT_ALLOWED/ROLE_NOT_MENTOR · MENTOR_NOT_APPROVED · ACCOUNT_* · TITLE_REQUIRED · CATEGORY_INVALID · BODY_TOO_SHORT(10) · IMAGE_COUNT_EXCEEDED · IMAGE_MIME_NOT_ALLOWED · IMAGE_SIZE_EXCEEDED · IMAGE_*.

### 1.8 멘토 찾기 — 디렉터리 / 상세 / 찜 / 무료질문

| 기능 | 화면 클래스 | 사용자 액션 | 서버 표면 | 게이트/플래그 | 상태 | 알려진 갭 |
|---|---|---|---|---|---|---|
| 디렉터리 | `MentorsScreen` (`lib/features/mentors/mentors_screen.dart:31`) | 검색·필터·정렬(latest/ratingHigh/reviewMany)·범위(전체/찜) | `api_web_v1.mentor_directory_v1(mentor_id, nickname, university_name, department_name, teaching_subjects, intro_line, school_verified, avg_rating, review_count, created_at)` 100건 페이지 × 최대 50 (`data/mentor_directory_repository.dart:39-40,52-53`) · `mentor_plans(mentor_id, plan_tier, amount_cents, label, is_active).eq(is_active,true)` (`:63`) | 게스트 허용 | 완전 | 전량 로드 후 클라이언트 필터(서버 페이징 없음) · 학교/학년/가격대 필터 없음(`docs/FEATURE_AUDIT.md` B4) |
| 상세 | `MentorDetailScreen` (`ui/mentor_detail_screen.dart:36`) | 질문방 이동 / 구독 안내 / 무료질문 / 개별질문 | RPC `get_mentor_avg_response_hours(p_mentor_id)` (`:209-210`) · `SubscriptionReader`(`subscriptions`) · `EntitlementReader`(`subscriptions(status, plan_tier)` in entitled) (`lib/core/entitlement/entitlement.dart:44`) | 구독 중이면 "질문방으로", 아니면 `CommerceNoticeCard`+무료질문 · '개별질문 하기' = `kIndividualQuestionCreateEnabled && student` → `openIqCreateWeb(mentorId)` | 완전 | 구독/결제 CTA 없음(Commerce-Zero) |
| 찜 | `MentorFavoritesRepository` (`data/mentor_favorites_repository.dart:34`) | 토글 | 테이블 **`favorites`**`(user_id, mentor_id)` select (`:49`)/insert (`:65`)/delete (`:86`) · 23505 = 이미 찜 | — | 완전 | 웹 SQL 198 헤더는 앱 DELETE 대상을 `mentor_favorites` 로 기술(`web:supabase/sql/198_ugc_block_hard_delete.sql:12`) — 테이블명 불일치 **(확인 필요)** |
| 무료질문 | `FreeQuestionEntrySection` · `FreeQuestionComposeScreen` (`ui/free_question_compose_screen.dart:16`), `FreeQuestionEntry` (`data/free_question_entry.dart`) | 자격 판정 → 방 보장 → 질문 | `mentor_student_rooms(id)` (`:140`) · `free_question_usage` count(student_id) / count(student_id, mentor_id) (`:146,150`; RLS `fqu_select_own` 주석) · `api_app_v1.rpc ensure_free_question_room(p_mentor_id)` → `{ok, room_id, created, entitlement, contract_version:1}` \| `{ok:false, code}` (`:170-171`) · RPC `qna_create_free_question_thread(p_room_id, p_title, p_subject, p_first_message_body)` → `{ok, thread_id, message_id, path, used_free_quota}` (`:198`) · CTA 결정 `decideFreeQuestionCta` (`:82`) | 자격(가입 7일·전역/멘토별 한도)은 서버 판정 | 완전 | 한도 수치는 서버 정본(앱은 표시만) — 정확한 수치 **(확인 필요)** |

### 1.9 알림 — 센터 / 설정 / 배지 / 실시간

| 기능 | 화면 클래스 | 서버 표면 | 게이트/플래그 | 상태 | 알려진 갭 |
|---|---|---|---|---|---|
| 알림 목록 | `NotificationsScreen` (`lib/features/notifications/notifications_screen.dart:48`) 칩 전체/질문방/구독·결제/개별질문 | `notifications.select('id, type, body, is_read, read, created_at, data, metadata').not('type','in','(new_order_message,new_application)')` 키셋 (created_at, id) desc limit pageSize+1 (`data/notifications_repository.dart:133`) | `kGatedNotificationTypeCodes={'new_order_message','new_application'}` 제외(CR 게이트 OFF) (`data/notification_types.dart:15-16`) | 완전 | — |
| 읽음 처리 | 동일 | RPC `mark_notification_read(p_notification_id)` → `{ok, contract_version:1, idempotent_hit}` (`:153-154`) · RPC `mark_all_notifications_read()` → int (`:167`) | — | 완전 | — |
| 배지 | `NotificationBadgeController` (`data/notification_badge_controller.dart`) | RPC `notification_unread_count_self()` → `{ok, count, contract_version:1}` (`:178`) | — | 완전 | — |
| 실시간 | `NotificationsRealtime` | 채널 `notifications_<userId>` INSERT `notifications` filter `recipient_user_id` (`data/notifications_realtime.dart:47-55`) | — | 완전 | publication 멤버십 **(확인 필요)** |
| 타깃 열기 | `NotificationTargetOpener` (`ui/notification_target_opener.dart`) | metadata `room_id/thread_id/question_id/post_id/shortform_id/mentor_id` (`data/app_notification.dart`) → ChatScreen/MentorAnswerScreen/방 홈/IqDetail/BoardDetail/ShortformDetail/MentorDetail | role 분기 | 완전 | — |
| 딥링크 | `DeepLinkService` · `NotificationDeepLinkController` (`lib/core/deeplink/`) | `resolveNotificationDeepLink` → Tab/Room/Iq/BoardPost/Shortform/Mentor (UUID 검증 · 대기 nav TTL 15분 · dedup LRU 32) | 프로덕션 페이로드 생산자 없음(App-F0) | 부분 | OS 푸시 없음 |
| 알림 설정 | `SettingsSection` (`lib/features/mypage/ui/sections/settings_section.dart`), `NotificationSettingsRepository` | `notification_settings(user_id PK, push_enabled, groups jsonb{qna, order, subscription, refund, system}, updated_at)` select (`data/notification_settings_repository.dart:116`) / upsert onConflict user_id (`:124`) | — | 완전 | 매니페스트 `kExpectedTables` 에는 `notification_settings` 가 없고 식별자 `table`(`kExpectedTableIdentifiers`, `test/contracts/outbound_api_manifest_test.dart:113-117`) 경유로 통과 — 재구축 매니페스트에는 명시 등재 권장 |

**알림 type 18종(`data/notification_types.dart`):** question_answered · question_received · new_order_message · new_application · mentor_subscription_price_changed · mentor_termination_notice · mentor_termination_refund · mentor_pause_notice · individual_question_expired_refunded / assigned / claimed / answered / message / released · subscription_renewal_upcoming / expired / renewal_succeeded / renewal_failed_insufficient_cash. 목적지 `questionRoomTab/individualQuestionTab/myPage/stay`.

### 1.10 마이페이지

| 섹션 | 화면 클래스 | 서버 표면 | 게이트/플래그 | 상태 | 알려진 갭 |
|---|---|---|---|---|---|
| 프로필 헤더 | `MyPageScreen` (`lib/features/mypage/mypage_screen.dart:30`) | `users.select('email, grade_level')` (`data/mypage_repository.dart:71`) + AuthService 캐시(nickname/full_name/role) | — | 완전 | 아바타 없음(웹 전용) |
| 프로필 편집 | `ProfileEditScreen` (`ui/profile_edit_screen.dart:17`) | `api_app_v1.rpc user_profile_update_self(p_nickname?, p_grade_level?)` → `{ok, contract_version:1, nickname, grade_level, updated_at}` (`data/profile_edit_repository.dart:39,110`) · 코드 AUTH_REQUIRED · ROLE_NOT_ALLOWED · ACCOUNT_* · NICKNAME_REQUIRED/TOO_LONG(30) · GRADE_LEVEL_NOT_ALLOWED(멘토)/TOO_LONG(20) | 멘토는 '멘토 프로필 관리 (웹)' → `openProfileEditWeb` | 완전 | `users` 직접 UPDATE 금지(매니페스트) |
| 캐시 | `CashSection` (`ui/sections/cash_section.dart`) | `api_web_v1.my_wallet_v1(balance_cents)` (`mypage_repository.dart:139-140`) · `api_web_v1.my_cash_ledger_v1(delta_cents, created_at, reason)` limit 5 (`:159-160`) · 라벨 `kCashLedgerReasonLabels {cash_topup, subscription_payment, individual_question_escrow_hold, individual_question_refund}` (`data/mypage_models.dart`) | 조회만 · `CommerceNoticeCard` | 완전 | 충전 없음 |
| 학생 구독 | `StudentSubscriptionSection` (`ui/sections/student_subscription_section.dart`) | `subscriptions` (SubscriptionReader) · 상태 `pending/active/past_due/cancel_scheduled/canceled/expired/refunded`, entitled `{active, cancel_scheduled}` (`lib/core/entitlement/subscription_status.dart:15-22`) | '구독 관리 (웹)' = `kSubscriptionManageLinkEnabled`(기본 OFF) | 완전 | `remaining` 항상 null(`subscription_summary.dart`) |
| 멘토 대시보드 | `MentorDashboardSection` (`ui/sections/mentor_dashboard_section.dart`) | `subscription_settlement_items(mentor_amount_cents, created_at).eq(mentor_id)` limit 1 (`mypage_repository.dart:206`) | '정산 관리 (웹)' = `kPayoutManageLinkEnabled`(기본 OFF) | 부분 | KPI 최소(최근 정산 1건) |
| 설정 | `SettingsSection` | 알림 설정(§1.9) · 약관/개인정보 웹 · 앱 버전 상수 `'1.0.0'` (`lib/shared/constants/app_constants.dart`) · 차단 관리 → `BlockedUsersScreen` · 회원 탈퇴 → `AccountDeleteScreen` · 로그아웃 | — | 완전 | 버전 문자열 하드코딩 |
| 지원 | `SupportSection` (`ui/sections/support_section.dart`) | 알림 탭 이동 · 고객지원 웹 · 받은 리뷰 웹(멘토만) | 리뷰 = 멘토 role 게이트(`docs/RELEASE_SCOPE_DECISIONS_2026-07.md:46`) | 완전 | — |
| 회원 탈퇴 | `AccountDeleteScreen` (`ui/account_delete_screen.dart:50`), `AccountDeletionRepository` | `account_deletion_request_self_v2()` → `{ok, existing, job_id, state, cancelable_until}` \| `{ok:false, code:FORFEIT_CONSENT_REQUIRED, balance_cents}` (`data/account_deletion_repository.dart:201-202`) · `account_deletion_request_self_consented_v2(p_acknowledged_balance_cents)` \| `{ok:false, code:FORFEIT_CONSENT_STALE, acknowledged_balance_cents, current_balance_cents}` (`:217-218`) · `account_deletion_cancel_self()` → `{ok}` \| `{ok:false, code:NOT_FOUND|NOT_CANCELABLE|CANCEL_WINDOW_PASSED}` (`:319-320`) · `account_deletion_status_self()` (`:340-341`) · 42501/42883/PGRST202 → `AccountDeletionUnavailable` → 웹 `/account/delete` 폴백 | — | 완전 | 취소 유예 30일(웹 hotfix `20260808092007`) — 앱은 서버 `cancelable_until` 만 표시 |

### 1.11 버전 게이트

| 항목 | 사실 | 근거 |
|---|---|---|
| RPC | `get_mobile_app_version_policy(p_platform)` (anon EXECUTE) → `{platform, min_supported_build, latest_build, minimum_version_name, store_url, message}` | `lib/core/version_gate/supabase_version_policy_port.dart:6,21-23`, `version_policy.dart:42` |
| 판정 | 정수 build 비교만(package_info_plus). 조회 실패 → 재시도 화면, 단 마지막 통과 캐시(shared_prefs `version_gate_last_pass_build`)가 있으면 통과 | `shared_prefs_gate_pass_cache.dart:10`, `version_gate_screens.dart:43,102` (`ForceUpdateScreen`, `VersionGateRetryScreen`) |
| 스토어 URL allowlist | host 정확 일치 `play.google.com` · `apps.apple.com` · `itunes.apple.com` | `store_url_policy.dart:5-12` |
| 플랫폼 | android/ios 외 게이트 스킵(서버는 android/ios 외 플랫폼에 `INVALID_PLATFORM`) | `lib/core/version_gate/version_gate_controller.dart:67` |

### 1.12 웹 브릿지(외부 브라우저) — §3 참조.

---

## 2. 아웃바운드 표면 전체 집합 (매니페스트 기준) → 기능 매핑

근거: `test/contracts/outbound_api_manifest_test.dart:15-137`. 아래 집합은 테스트가 **정확히 일치**를 요구한다(추가·삭제 모두 실패).

### 2.1 RPC (`kExpectedRpcNames`, `:15-59`)

| RPC | 스키마 | 호출 위치 | 기능 |
|---|---|---|---|
| `account_deletion_cancel_self` | public | `mypage/data/account_deletion_repository.dart:319` | 탈퇴 취소 |
| `account_deletion_request_self_v2` | public | `:201` | 탈퇴 요청 |
| `account_deletion_request_self_consented_v2` | public | `:217` | 탈퇴 요청(잔액 포기 동의) |
| `account_deletion_status_self` | public | `:340`, `core/auth/account_status.dart:162` | 탈퇴 상태 |
| `account_deletion_write_blocked` | public | `core/auth/account_status.dart:151` | 쓰기 차단 판정 |
| `user_profile_update_self` | **api_app_v1** | `mypage/data/profile_edit_repository.dart:39,110` | 프로필 편집 |
| `ensure_free_question_room` | **api_app_v1** | `mentors/data/free_question_entry.dart:170` | 무료질문 방 보장 |
| `qna_append_message` | public | `question_room/data/question_room_write_repository.dart:129` | 질문방 메시지 |
| `qna_confirm_thread` | public | `:176` | 질문 확인 |
| `qna_create_free_question_thread` | public | `mentors/data/free_question_entry.dart:198` | 무료 질문 생성 |
| `qna_create_question_thread` | public | `question_room_write_repository.dart:82` | 질문 생성 |
| `qna_register_attachment` | public | `question_room/data/attachments/attachment_upload.dart:386` | 첨부 등록 |
| `weekly_question_usage_self` | **api_web_v1** | `question_room_read_repository.dart:148` | 주간 한도 |
| `weekly_question_usage_self_batch` | **api_web_v1** | `:171` | 주간 한도 일괄 |
| `get_mentor_student_nicknames` | public | `question_room/data/student_lookup_repository.dart:54` | 멘토 → 학생 닉네임 |
| `get_mentor_avg_response_hours` | public | `mentors/data/mentor_directory_repository.dart:209` | 멘토 상세 |
| `add_individual_question_attachment` | public | `individual_question/data/iq_attachments_repository.dart` | IQ 첨부 |
| `claim_individual_question_as_mentor` | public | `individual_question_repository.dart:190` | IQ 클레임 |
| `create_individual_question_as_student` | public | `:170` | IQ 작성(스텁 경로) |
| `iq_append_message` | public | `:209` | IQ 메시지 |
| `list_open_individual_questions_for_mentor` | public | `:84` | IQ 열린 질문 |
| `refund_individual_question` | public | `:242` | IQ 환불 |
| `release_individual_question` | public | `:233` | IQ 정산 확정 |
| `my_blocked_users` | public | `community/data/user_blocks_repository.dart:136` | 차단 목록 |
| `community_comment_soft_delete_self` | public | `community/data/comments_gateway.dart:61` | 숏폼 댓글 본인 삭제 |
| `community_post_soft_delete` | **api_app_v1** | `community_write_repository.dart:233` | 게시글 본인 삭제 |
| `community_post_view_record_v2` | public | `:105` | 게시글 조회 |
| `shortform_view_record_v2` | public | `:129` | 숏폼 조회 |
| `mark_all_notifications_read` | public | `notifications_repository.dart:167` | 알림 |
| `mark_notification_read` | public | `:153` | 알림 |
| `notification_unread_count_self` | public | `:178` | 배지 |
| `get_mobile_app_version_policy` | public(anon) | `core/version_gate/supabase_version_policy_port.dart:21` | 버전 게이트 |
| 식별자 경유(`kExpectedRpcIdentifiers`, `:63-67`): `kBoardPostCreateFunction='community_post_create'` · `kBoardPostUpdateFunction='community_post_update'` (api_app_v1) · `fn`(탈퇴/프로필 헬퍼) | api_app_v1 | `community_write_repository.dart:340-341,380-381` | 게시글 작성/수정 |

### 2.2 스키마 (`kExpectedSchemas`, `:69`) — `api_app_v1` · `api_web_v1` (+식별자 `kBoardPostCreateSchema='api_app_v1'`, `schema` 변수 `comments_gateway.dart:37`).

### 2.3 테이블·뷰 (`kExpectedTables`, `:77-110`)

| 이름 | 종류 · 스키마 | 앱 접근 | 기능 |
|---|---|---|---|
| `users` | table · public | SELECT only (`.update`/`.insert` 금지 테스트 `:298-311`) | 인증·마이페이지 |
| `subscriptions` | table · public | SELECT | 권한(entitlement)·구독 섹션 |
| `subscription_settlement_items` | table · public | SELECT | 멘토 대시보드 |
| `my_wallet_v1` | view · **api_web_v1** | SELECT | 캐시 잔액 |
| `my_cash_ledger_v1` | view · **api_web_v1** | SELECT | 캐시 원장 |
| `notifications` | table · public | SELECT(+Realtime) | 알림 |
| `mentor_student_rooms` | table · public | SELECT (INSERT 없음) | 질문방 |
| `question_threads` | table · public | SELECT(+Realtime UPDATE) | 질문방 |
| `question_messages` | table · public | SELECT(+Realtime INSERT) · 쓰기는 RPC | 질문방 |
| `question_attachments` | table · public | SELECT(+Realtime) · 쓰기는 RPC | 첨부 |
| `connection_notes` | table · public | SELECT/INSERT/UPDATE/DELETE 직접 | 연결노트 |
| `mentor_profiles` | table · public | SELECT(teaching_subjects) | 과목 제한 |
| `mentor_directory_v1` | view · **api_web_v1** | SELECT | 멘토 찾기·방 목록 |
| `mentor_plans` | table · public | SELECT(is_active) | 멘토 가격 |
| `free_question_usage` | table · public | SELECT count | 무료질문 |
| `individual_questions` | table · public | SELECT(+Realtime UPDATE) | IQ |
| `individual_question_messages` | table · public | SELECT(+Realtime) | IQ |
| `individual_question_attachments` | table · public | SELECT | IQ |
| `mentor_individual_question_pricing` | table · public | SELECT | IQ |
| `community_posts_v1` | view · **api_web_v1** | SELECT | 게시판 |
| `shortform_posts` | table · public | SELECT | 숏폼 |
| `post_reactions` | table · public | SELECT/INSERT/DELETE | 게시판 반응 |
| `shortform_reactions` | table · public | SELECT/INSERT/DELETE | 숏폼 반응 |
| `content_reports` | table · public | INSERT | 신고 |
| 식별자 경유(`kExpectedTableIdentifiers`, `:113-117`): `_table` = `user_blocks`(`user_blocks_repository.dart:35`) · `favorites`(`mentor_favorites_repository.dart:34`) ; `_reportsTable` = `content_reports`(`room_safety_repository.dart:56`) ; `table` = `comments`/`community_comments`(`community_models.dart:240-241`) · `community_comments_v1`(api_web_v1, `community_read_repository.dart:128`) · `notification_settings`(`notification_settings_repository.dart:102`) | | | |

### 2.4 Storage 버킷 (`kExpectedBucketNames`, `:130-137`)

| 버킷 | 경로 규약 | 접근 | 기능 |
|---|---|---|---|
| `question-room-attachments` | `{roomId}/{threadId}/{ts}_{safeName}` | upload · signedUrl · download · remove(보상) | 질문방 첨부 (`attachment_upload.dart:131`) |
| `individual-question-attachments` | `{questionId}/{ts}-{salt}.{ext}` · `{questionId}/annotations/{attachmentId}.json` | upload · download · remove(보상) · upsert(annotations) | IQ 첨부·첨삭 (`individual_question_repository.dart:36`, `ink_storage_paths.dart:51`) |
| `scan-annotations` | `{roomId}/{attachmentId}/ink.json` · `flat.png`(규약만) | upload(upsert) · download | 스캔 주석 (`ink_storage_paths.dart:24`, `scan_annotation_repository.dart:113,125`) |
| `connection-note-ink` | `{roomId}/{authorId}/ink.json` · `thumb.png` | **쓰기 없음(잔존 규약)** | 연결노트 필기(제거) (`ink_storage_paths.dart:21`) |
| `shortform-videos` | `{uuid}/{objectName}` | signedUrl(읽기) | 숏폼 재생 (`shortform_media_url_resolver.dart:98`) |
| `community-post-images` | `{uid}/{ts}_{safeName}` | upload · remove · signedUrl | 게시판 이미지 (`board_post_media_gateway.dart:25`) |

### 2.5 금지어 (`kForbiddenWords`, `:140-149`)
`mentor_directory_list_v2` · `mentor_profiles_for_directory_v2` · `mentor_user_public_v2` · `increment_shortform_post_view` · `account_deletion_request_self` · `account_deletion_request_self_consented` · `record_cash_topup` · `subscription_checkout_confirm` — 재구축 시에도 호출 금지 대상(구 API·결제 API).

### 2.6 Realtime 채널

| 채널 | 이벤트 | 근거 |
|---|---|---|
| `question_thread_<threadId>` | INSERT `question_messages`(thread_id=) · UPDATE `question_threads`(id=) · INSERT `question_attachments`(thread_id=) | `thread_realtime.dart:44-85` |
| `iq_<questionId>` | INSERT `individual_question_messages`(question_id=) · INSERT `individual_question_attachments`(question_id=) · UPDATE `individual_questions`(id=) | `iq_realtime.dart:54-95` |
| `notifications_<userId>` | INSERT `notifications`(recipient_user_id=) | `notifications_realtime.dart:47-55` |

---

## 3. 웹 URL 동선 표 (외부 브라우저 · WebView)

기본 host: `WebBridgeConfig.baseUrl = String.fromEnvironment('WEB_BASE_URL', defaultValue: 'https://ssambership.com')` (`lib/core/web_bridge/web_bridge_config.dart:16-19`). 모든 외부 열기는 `src=app` 쿼리를 붙이고(`web_bridge.dart`), https + 정확 host 또는 `.host` 서브도메인만 허용(`isAllowedUri`). `docs/PLAY_STORE_REVIEW_PLAN.md:305` D-2 는 운영 도메인을 `https://ssambership-web.vercel.app` 로 확정 — 코드 기본값과 불일치 **(확인 필요)**.

| 경로 상수 | 값 | 액션 함수 (`web_bridge_actions.dart`) | 호출 화면 | 게이트 |
|---|---|---|---|---|
| `billingManagePath` | `/subscriptions` (`:24`) | `openBillingManageWeb` (`:12`) | `StudentSubscriptionSection` | `kSubscriptionManageLinkEnabled` 기본 OFF |
| `payoutManagePath` | `/mentor/payouts` (`:26`) | `openPayoutManageWeb` (`:19`) | `MentorDashboardSection` | `kPayoutManageLinkEnabled` 기본 OFF |
| `profileEditPath` | `/mentor/profile` (`:28`) | `openProfileEditWeb` (`:26`) | `ProfileEditScreen`(멘토) | 멘토 |
| `termsPath` | `/legal/terms` (`:32`) | `openTermsWeb` (`:33`) | `SettingsSection` | — |
| `privacyPath` | `/legal/privacy` (`:33`) | `openPrivacyWeb` (`:39`) | `SettingsSection` | — |
| `supportPath` | `/support` (`:35`) | `openSupportWeb` (`:45`) | `SupportSection` | — |
| `reviewsPath` | `/mentor/reviews` (`:37`) | `openReviewsWeb` (`:51`) | `SupportSection` | 멘토만 |
| `accountDeletePath` | `/account/delete` (`:41`) | `openAccountDeleteWeb` (`:57`) | `AccountDeleteScreen` 폴백 | RPC 미가용 시 |
| `iqCreatePath` | `/individual-questions/new` (`:46`) | `openIqCreateWeb` (`:66`) | `StudentIqListScreen` | 학생 |
| `iqCreateForMentorPath(mentorId)` | `/mentors/{id}/individual-question/new` (`:50`) | `openIqCreateWeb(mentorId)` | `MentorDetailScreen` | `kIndividualQuestionCreateEnabled && student` |
| (WebView) `bootstrapPath` | `/api/app-session/bootstrap` (`shortform_compose_bridge.dart:20`) POST 토큰 | `ShortformComposeScreen` | 멘토 | — |
| (WebView) `composePath` | `/app/community/shortform/new` (`:21`) | 동일 | 멘토 | — |
| (WebView) `bridgeCompletePath` / `bridgeErrorPath` | `/app/bridge/complete` · `/app/bridge/error` (`:22-23`) | 완료 감지 `kind=shortform&result=draft|published` | 동일 | — |

웹 측 라우트 존재 확인(2026-09-03 · `web:app/`): `(student)/subscriptions` · `(mentor)/mentor/payouts` · `(mentor)/mentor/profile` · `(public)/legal/terms` · `(public)/legal/privacy` · `(public)/support` · `(mentor)/mentor/reviews` · `(student)/account/delete` · `(student)/individual-questions/new` · `(student)/mentors/[mentorId]/individual-question/new` · `app/community/shortform/new` · `app/bridge/complete` · `app/bridge/error` · `api/app-session/bootstrap/route.ts` — 앱 경로 상수 14개 전부 실제 페이지/라우트가 존재한다(웹 CLAUDE.md 라우트 표에는 일부 누락). 구독/충전 경로(`/subscribe`, `/wallet/charge`)는 P0-3 死배선 정리(2026-07-12)로 앱에서 제거됨. 남는 불일치는 도메인 기본값(`ssambership.com` vs D-2 `ssambership-web.vercel.app`)뿐 **(확인 필요)**.

---

## 4. 의도적 제외 목록 + 근거 문서

| 제외 항목 | 근거 | 재구축 시 함의 |
|---|---|---|
| 인앱 결제 · 구독 체결 · 캐시 충전 · 결제 유도 CTA | `lib/core/commerce/commerce_policy.dart:10` (`kInAppPaymentSteeringEnabled=false`), `lib/core/entitlement/entitlement.dart:23`, 매니페스트 금지어 `record_cash_topup`/`subscription_checkout_confirm` (`:140-149`), `docs/RELEASE_SCOPE_DECISIONS_2026-07.md:7-14` | 오너 요구("결제 제외")와 일치 — 유지 |
| 구독 관리 · 정산 관리 링크(웹) | dart-define `SUBS_MANAGE_LINK_ENABLED` / `PAYOUT_MANAGE_LINK_ENABLED` 기본 false (`commerce_policy.dart:17-18,29-30`) | 링크 노출 정책 결정 필요 |
| 회원가입 · 소셜 로그인 · 비밀번호 재설정 · 온보딩 | `docs/RELEASE_SCOPE_DECISIONS_2026-07.md:15-21` (이메일/비밀번호+게스트만) · `OnboardingScreen` 미라우팅 | 웹 재구축 수준이면 재검토 대상 |
| 아바타 · 멘토 서류(학생증/재학증명) 업로드 | `docs/RELEASE_SCOPE_DECISIONS_2026-07.md:7-14` (웹 전용) · 버킷 `student-id-images` 앱 미사용 | 웹 위임 유지 여부 결정 |
| 맞춤의뢰(CR) 전체 | `docs/RELEASE_SCOPE_DECISIONS_2026-07.md:31-45` 게이트 OFF · 알림 `new_order_message`/`new_application` 목록 제외 (`notification_types.dart:15-16`) | **웹 기능 수준 재구축이면 신규 구현 필요**(서버 계약은 존재 · 앱 표면 0) |
| 개별질문 네이티브 작성(캐시 예치) | `iq_flags.dart:19-20` · `docs/PLAY_STORE_REVIEW_PLAN.md:304,311,340` (D-1) | 예치=캐시 차감이므로 "결제 제외" 경계 판단 필요 |
| IQ 첨삭(annotation) UI | `iq_detail_screen.dart:1006` (`_canAnnotateGroup` false) · `docs/APP_FEATURE_STATUS.md` | 저장소 계층은 남아 있음 |
| 연결노트 필기(ink) | `docs/APP_FEATURE_STATUS.md` (2026-07-06 제거) · `ink_storage_paths.dart:11-12` 규약 잔존 | 컬럼 `ink_path`/`ink_thumb_path` 미사용 |
| 숏폼 네이티브 작성 | `docs/RELEASE_SCOPE_DECISIONS_2026-07.md:22-30` (WebView 브릿지만) | 업로드 파이프라인(트랜스코딩 등)은 웹 소유 |
| 게시판 댓글 본인 삭제 | 앱 미구현(`community_write_repository.dart` 에 없음) | 웹 DB-3 RPC 로 신규 구현 가능(§6) |
| OS 푸시(FCM) · 디바이스 토큰 | `lib/core/push/HANDOFF.md:1-4,17-22` (App-F0) · 매니페스트 `firebase` 0건 테스트 (`:321-326`) | 알림은 인앱 알림함 + Realtime 만 |
| 관리자 콘솔 · 멘토 승인 · 검수 · 환불 · 공지 | `AuthService.computeAccess` admin → blocked (`lib/core/auth/auth_service.dart`) | 앱 범위 밖(웹 콘솔) |
| 리뷰 작성(학생) | `docs/RELEASE_SCOPE_DECISIONS_2026-07.md:46-52` (멘토 '받은 리뷰' 웹 링크만) | 웹 정본(2회 연속 결제 조건) |
| 멘토 대시보드 KPI · 수익 차트 · 프로필 편집(멘토) | `mypage_repository.dart:206` 최근 정산 1건만 · 멘토 프로필은 웹 링크 | 웹 위임 |
| 학생 마이페이지 세부(구독 원장 · 환불 요청) | `remaining` null · 원장 5건 | — |

---

## 5. 데이터 모델 목록 (앱 모델 → 테이블/뷰 컬럼)

| 앱 모델(파일) | 테이블/뷰 | 매핑 컬럼 | 쓰기 특성 |
|---|---|---|---|
| `Room` (`question_room/models/room.dart`) | `mentor_student_rooms` | id, student_id, mentor_id, subscription_id, payment_id, created_at, updated_at · `(student_id, mentor_id)` UNIQUE | 앱 INSERT 없음 |
| `QuestionThread` (`models/question_thread.dart`) | `question_threads` | id, mentor_student_room_id, title, status(`pending/answered/confirmed/open/closed/archived`), topic, subject, mastery_status(`wrong/review/mastered`), first_answered_at, confirmed_at, created_at, updated_at · `autoQuestionTitle(n)='{n+1}번 질문'` | RPC 전용 |
| `QuestionMessage` (`models/question_message.dart`) | `question_messages` | id, thread_id, author_id, body, created_at | **append-only**(RPC) |
| `QuestionAttachment` (`models/question_attachment.dart`) | `question_attachments` | id, thread_id, message_id?, author_id?, storage_path, file_name, mime_type, created_at · storage_path UNIQUE(23505) | RPC 전용 |
| `ConnectionNote` (`models/connection_note.dart`) | `connection_notes` | id, mentor_student_room_id, body, author_id, author_role(student\|mentor), created_at, updated_at, ink_path(미사용), ink_thumb_path(미사용) | 직접 CRUD(작성자 1행 규약) |
| `WeeklyQuestionUsage` (`core/entitlement/weekly_question_usage.dart`) | RPC 결과 | used, limit, remaining, can_ask, plan_tier, week_start, week_end | 읽기 |
| `SubscriptionSummary` / `Entitlement` (`core/entitlement/*`) | `subscriptions` | mentor_id, status, plan_tier, current_period_end, next_billing_at | 읽기 |
| `IndividualQuestion` 등 (`individual_question/models/individual_question_models.dart`) | `individual_questions` · `individual_question_messages` · `individual_question_attachments` · `mentor_individual_question_pricing` | §1.6 참조 | 메시지 append-only(RPC) · 첨부 RPC · 상태 전이 RPC |
| `MentorListItem.fromDirectoryViewMap` / `MentorPlan` (`mentors/data/mentor_models.dart`) | `api_web_v1.mentor_directory_v1` · `mentor_plans` | mentor_id, nickname, university_name, department_name, teaching_subjects, intro_line, school_verified, avg_rating, review_count, created_at · mentor_id, plan_tier(`limited/standard/premium`), amount_cents, label, is_active | 읽기 |
| `BoardPost` (`community/data/community_models.dart`) | `api_web_v1.community_posts_v1` | id, title, body\|content, category, author_label, author_role, author_id, updated_at(raw · 낙관적 잠금), image_refs\|image_urls, like_count, comment_count, view_count, created_at | 베이스 `community_posts` 직접 접근 0(`community_direct_write_lockdown`) · 삭제는 소프트(`community_post_soft_delete`) |
| `ShortformPost` | `shortform_posts` | id, title, body\|content\|description, category, author_label, author_role, thumbnail_url, video_url, like_count, view_count, created_at | 읽기(작성은 웹) |
| `CommunityComment` | 게시판 `comments` / `api_web_v1.community_comments_v1` · 숏폼 `community_comments` | id, content\|body, parent_id, author_label, author_id, created_at · 숏폼 `post_type='shortform'`, `status='visible'` | 게시판 INSERT 직접 · 숏폼 INSERT 직접 + 본인 삭제 RPC |
| 반응 | `post_reactions(user_id, post_id, type)` · `shortform_reactions(user_id, shortform_id, type)` | — | INSERT/DELETE 직접(하드 DELETE 허용 테이블) |
| 신고 | `content_reports(reporter_id, target_type, target_id, reason, description, status)` | target_type ∈ `community_post/shortform_post/board_comment/community_comment/user` | INSERT only |
| 차단 | `user_blocks(blocker_id, blocked_id)` PK · CHECK self | RPC `my_blocked_users` 닉네임 조인 | INSERT/DELETE 직접 |
| 찜 | `favorites(user_id, mentor_id)` | — | INSERT/DELETE 직접 (`mentor_favorites` 명칭 불일치 **확인 필요**) |
| `AppNotification` (`notifications/data/app_notification.dart`) | `notifications` | id, type, body, is_read(+legacy read), created_at, data.title, metadata{room_id, thread_id, question_id, post_id, shortform_id, mentor_id}, recipient_user_id(필터) | 읽음 RPC |
| `NotificationSettings` | `notification_settings(user_id PK, push_enabled, groups jsonb, updated_at)` | groups 키 qna/order/subscription/refund/system | upsert 직접 |
| 마이페이지 | `users(email, grade_level)` · `api_web_v1.my_wallet_v1(balance_cents)` · `api_web_v1.my_cash_ledger_v1(delta_cents, created_at, reason)` · `subscription_settlement_items(mentor_amount_cents, created_at)` | 1캐시=1원 · `balance_cents ÷ 100` | 읽기 · 프로필은 RPC |
| 과목 카탈로그 (`lib/data/mappings/subject_labels.dart`) | — | 35 코드(웹과 1:1) | 상수 |
| 요금제 (`lib/shared/constants/plan_constants.dart`) | — | 라벨 라이트/스탠다드/프리미엄 · 가격 null · 주간 4/9/null | 상수(가격 표시는 `mentor_plans` 행) |

소프트 삭제·append-only 요약: `question_messages`·`individual_question_messages`·`content_reports`·`cash_ledger`(원장 뷰) = append-only; `community_posts`(`community_post_soft_delete`) · `community_comments`(`community_comment_soft_delete_self`) = 소프트 삭제; 하드 DELETE 는 `post_reactions`·`shortform_reactions`·`favorites`·`user_blocks`·`connection_notes`(중복 정리) 5곳만.

---

## 6. 재구축 시 분류 — 그대로 이식 가능 vs 웹 정본 변경으로 재검토 필요

대조 기준: `web:CLAUDE.md` 개정 2026-09-03 (DB-1 · DB-2 · DB-3) 및 `web:supabase/sql/190~198`.

### 6.1 그대로 이식 가능(서버 계약 변동 없음)

| 자산 | 근거 |
|---|---|
| 질문방 RPC 계층(`qna_create_question_thread` · `qna_append_message` · `qna_confirm_thread` · `qna_register_attachment` · `qna_create_free_question_thread`) + 에러 매퍼 + 첨부 보상 삭제/23505 멱등 | `question_room_write_repository.dart:82-177`, `attachment_upload.dart:216-402`; SQL 190~198 은 qna 함수 미변경 |
| 주간 한도 RPC(`api_web_v1.weekly_question_usage_self[_batch]`) 봉투 파서 | `question_room_read_repository.dart:148-172` |
| IQ RPC 계층·첨부 코어(`iq_attachment_upload_core.dart` 이중 반환 처리·40001 재시도)·정책(20MB·매직바이트) | `iq_attachments_repository.dart`, `iq_attachment_policy.dart:11-19` |
| 알림 키셋 페이징 + `mark_notification_read` / `mark_all_notifications_read` / `notification_unread_count_self` + Realtime | `notifications_repository.dart:133-178`, `notifications_realtime.dart:47-55` (SQL 197 은 `admin:*` 토픽만 제한 — postgres_changes 채널 무영향) |
| `api_web_v1` 읽기 뷰 소비(`mentor_directory_v1` · `my_wallet_v1` · `my_cash_ledger_v1` · `community_posts_v1` · `community_comments_v1`) | `web:supabase/sql/20260730095441_api_web_v1_read_views.sql` · SQL 194 가 `community_comments_v1` 에 `deleted_at IS NULL` 필터를 추가해 앱 변경 없이 삭제 댓글이 사라짐 |
| 탈퇴 v2 RPC 4종 + `FORFEIT_CONSENT_*` 흐름 + 웹 폴백 | `account_deletion_repository.dart:180-341` |
| 프로필 편집 `api_app_v1.user_profile_update_self` | `profile_edit_repository.dart:39,110` |
| 무료질문 `api_app_v1.ensure_free_question_room` + CTA 판정 | `free_question_entry.dart:82,170,198` |
| 웹 브릿지 allowlist·`src=app`·WebView 쿠키 위생·숏폼 bootstrap 브릿지 | `lib/core/web_bridge/*`, `lib/main.dart:39` |
| 버전 게이트(RPC·캐시·스토어 URL allowlist) | `lib/core/version_gate/*` |
| 접근 상태 fail-closed 판정(`computeAccess`, `AccountStatus`) | `lib/core/auth/*` |
| 차단(`user_blocks` + `my_blocked_users`) · 신고(`content_reports` target_type allowlist) · 찜 | `user_blocks_repository.dart`, `room_safety_repository.dart:54-75`, `mentor_favorites_repository.dart:34` (찜은 6.2 명칭 확인 항목 병행) |
| 스캔·PDF·주석 파이프라인(질문방) · Ink 문서 포맷 | `lib/core/scan/*`, `lib/core/ink/*`, `lib/features/scan_annotation/*` |
| 아웃바운드 매니페스트 테스트 패턴 | `test/contracts/outbound_api_manifest_test.dart` — 재구축 시 집합만 갱신 |

### 6.2 웹 정본 변경으로 재검토 필요

| 항목 | 웹 변경(정본) | 앱 현재 | 재검토 내용 |
|---|---|---|---|
| **커뮤니티 본인 삭제 RPC 통일(DB-3)** | `public.soft_delete_own_content(p_kind text, p_id uuid) returns void` SECURITY DEFINER · `p_kind ∈ shortform \| shortform_comment \| board_comment \| board_post` · 코드 AUTH_REQUIRED(28000) · INVALID_KIND(22023) · CONTENT_NOT_FOUND(P0001) · CONTENT_KIND_MISMATCH(22023) · CONTENT_NOT_OWNED(42501) · ACCOUNT_* · CONTENT_MODERATED(42501) · 멱등 · GRANT authenticated (`web:supabase/sql/196_soft_delete_own_content_rpc.sql:11-15,97,122,166`) · `community_comment_soft_delete_self` 는 앱용으로 유지 (`web:CLAUDE.md` DB-3) | 숏폼 댓글 `community_comment_soft_delete_self` (`comments_gateway.dart:61-62`) · 게시글 `api_app_v1.community_post_soft_delete` (`community_write_repository.dart:233-234`) · **게시판 댓글·숏폼 글 본인 삭제 없음** | 재구축은 4종 모두 `soft_delete_own_content` 하나로 통일 가능(게시판 댓글 본인 삭제 신규 · 숏폼 글 본인 삭제 신규). 기존 2개 RPC 는 매니페스트에서 제거 가능(웹 결정 필요). 반환 void 이므로 앱 봉투 파서(`{ok, contract_version}`) 와 형식 상이 |
| **소프트 삭제 컬럼(DB-2)** | `shortform_posts`·`comments`·`community_comments` 에 `deleted_at`·`deleted_by` 추가, 읽기 정책 `sf_select_published`/`comments_select_visible`/`community_comments_select_visible` 에 `deleted_at IS NULL` (`web:supabase/sql/194_community_soft_delete_deleted_at.sql:117-126`) · `community_comment_soft_delete_self` 가 `deleted_at/deleted_by` 를 쓰도록 수정 (`:27`) | 숏폼 댓글 읽기에 `status='visible'` 필터 (`community_read_repository.dart:124`) · 모델에 `deleted_at` 없음 | 서버 정책이 걸러주므로 즉시 깨지진 않음. 재구축 모델은 `deleted_at`/`deleted_by` 를 읽고 '작성자 삭제/관리자 삭제' 구분 가능(관리자 화면 배지 규약). `status='visible'` 필터 유지 여부는 웹 정본 확인 **(확인 필요)** |
| **하드 DELETE 차단 트리거(DB-3)** | `ugc_block_hard_delete` BEFORE DELETE on `shortform_posts`·`comments`·`community_comments` · anon/authenticated 거부(`UGC_HARD_DELETE_FORBIDDEN` 42501) (`web:supabase/sql/198_ugc_block_hard_delete.sql`) | 세 테이블 `.delete()` 0건(매니페스트·`:12` 헤더 확인) | 이식 영향 없음. 단, 헤더가 앱 DELETE 대상을 `mentor_favorites` 로 기술 — 앱은 `favorites` (`mentor_favorites_repository.dart:34`) → **테이블명 정본 확인 필요** |
| **캡 구조(DB-1)** | `subscription_cap_weight()` 1.0/2.25/4.75 · `mentor_cap_limit()` 폴백 50 · `mentor_plans.cap_weight` 참조 컬럼 (`web:supabase/sql/190_cap_structure_limit_50_weights.sql:5-7`) · TS/앱 사본 금지 | 앱은 cap 을 계산하지 않음. `mentor_plans` 에서 `plan_tier, amount_cents, label, is_active` 만 읽음 (`mentor_directory_repository.dart:63`) | 영향 없음. 재구축 시에도 앱에서 가중치 상수 두지 말 것(정본 = DB 함수). 멘토 정원 초과 표시가 필요하면 서버 RPC/뷰 신설 필요 **(확인 필요)** |
| **학교 인증 규칙(DB-1/DB-2)** | 자동 판정 = `pending` 잠정, 관리자 확정 = `reviewed_by` · `school_tier_suggest()` 폴백 `미분류`→`그외`(`미분류` 는 대학명 NULL/공백만) · 확정 등급 정정 RPC (`web:supabase/sql/192:140-246`, `193:4-7`) | `mentor_directory_v1.school_verified` bool 만 표시 · IQ `required_school_tier` 문자열 표시 | 디렉터리 뷰의 `school_verified` 산출 조건(pending 잠정 포함 여부)이 바뀌었는지 **(확인 필요)**. `required_school_tier` 라벨 집합에 `그외` 포함 필요 |
| **Realtime admin 토픽(DB-3)** | `realtime.messages` RLS 로 `admin:*` 만 관리자 (`web:supabase/sql/197`) | 앱은 postgres_changes 3채널 | 영향 없음 · 단 publication 멤버십은 별도 확인 |
| 요금제 표기/가격 밴드(2026-07-12·07-18 개정) | 카탈로그 표시가 29,900/84,900/174,900 · 멘토 밴드 · 실차감 = `mentor_plans` 행 → 권장가 | `plan_constants.dart` 가격 null · `mentor_plans.amount_cents` 표시 · `planTierLabel limited→라이트` | 일치. 권장가 폴백 표시가 필요하면 서버 값 조회 경로 필요(앱 상수 금지) |
| 연결노트 직접 CRUD | 웹 정본에 연결노트 RPC 존재 여부 미확인 | `connection_notes` 직접 insert/update/delete (`question_room_write_repository.dart:203-238`) | RLS 만으로 충분한지·웹이 RPC 화했는지 **(확인 필요)** |
| 게시판 댓글 직접 INSERT | SQL 194 `comments_write_guard()` 트리거(`web:supabase/sql/194_community_soft_delete_deleted_at.sql:584`, 헤더 `:35,40`: `deleted_by` 단독 변경 금지 · `deleted_by = auth.uid()` 만 · 비관리자 DELETE 거부) | `comments` 직접 insert (`comments_gateway.dart:53`) | 가드는 deleted_* 컬럼과 DELETE 를 겨냥하므로 본문 INSERT 는 통과할 것으로 보이나 실환경 검증 **(확인 필요)** |
| 맞춤의뢰(CR) | 웹 정본 기능(`custom_request_orders` 등) | 앱 표면 0(§4) | "웹 수준" 재구축이면 **신규 설계** — 서버 계약(`docs/RELEASE_SCOPE_DECISIONS_2026-07.md:31-45`) 재조사 필요 |
| IQ 작성(예치) · 결제 경계 | 웹은 캐시 예치 = 지갑 차감 | `IQ_CREATE_ENABLED` OFF · 웹 링크 | "결제 제외" 범위에 예치 포함 여부 오너 결정 필요 |
| 웹 브릿지 도메인 | 라우트 14개는 웹 `app/` 에 실재(§3) | `WEB_BASE_URL` 기본 `https://ssambership.com` vs `docs/PLAY_STORE_REVIEW_PLAN.md:305` D-2 `ssambership-web.vercel.app` | 운영 도메인 정본 확정 **(확인 필요)** |
