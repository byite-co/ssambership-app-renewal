# 기존 모바일 앱(ssambership-app) 아키텍처·구현 패턴 리포트

- 대상 저장소: `/home/user/ssambership-app` (브랜치 `claude/app-rebuild-feature-review-oyewr0`, HEAD `635ae73`)
- 규모(실측): `lib/` Dart 파일 228개. 계층별 줄수 — `app/` 458 · `core/` 4,342 · `design/` 1,348 · `shared/` 640 · `data/` 162 · `features/` 26,351. feature 파일 수 — question_room 42 · community 32 · individual_question 19 · mypage 16 · mentors 15 · notifications 8 · scan_annotation 5 · auth 3 · dev 3 · onboarding 1.
- 테스트: `test/` 아래 `*_test.dart` 173개, `test(`/`testWidgets(` 약 1,470건(grep 근사치). CI 서명 워크플로가 기대하는 정확 수치는 **1,508** (`.github/workflows/android-signed-release-candidate.yml:65`).
- 스택: Flutter ≥3.22 / Dart ≥3.4, `supabase_flutter ^2.5.0`, `go_router ^14.2.0`, `flutter_dotenv`, `url_launcher`, `image_picker`, `file_picker`, `scribble`, `image`, `pdfx`, `video_player`, `package_info_plus`, `webview_flutter(+android/wkwebview)`, `sentry_flutter ^9.26.0`, `shared_preferences` (`pubspec.yaml:10-49`). 상태관리 라이브러리·DI 프레임워크·mock 프레임워크 **없음**(`pubspec.yaml:51-62`).
- 앱 정체성: "웹의 컴패니언 · 읽기 중심 · Commerce-Zero(앱 내 결제 없음)" (`pubspec.yaml:2`, `README.md:6-8`). 맞춤의뢰·관리자·회원가입 폼은 **의도적 제외**(`README.md:8`, `HANDOFF.md:177-181`).
- 이 리포트는 UI 디자인·색·레이아웃을 다루지 않는다. 표기 규칙: `경로:행`. 코드로 확인하지 못한 것은 "(확인 필요)".

---

## §1 계층 구조와 의존 규칙

### 1-1. 최상위 폴더와 역할 (실측)

| 폴더 | 내용 | 근거 |
|---|---|---|
| `lib/app/` | `app.dart`(루트 `MaterialApp.router`), `router.dart`(GoRouter), `entry_guard.dart`(AccessState→redirect), `home_shell.dart`(5탭 셸), `app_tabs.dart`(탭 인덱스 상수 + `TabNavigator` 전역 채널) | `lib/app/*.dart` |
| `lib/core/` | `auth/`(AuthService·AccountStatus·DeletionNoticeController), `config/`(AppConfig), `supabase/`(SupabaseInit), `entitlement/`(구독 자격·주간 사용량), `deeplink/`, `push/`(포트만), `refresh/`(DataRefreshBus), `version_gate/`, `web_bridge/`, `observability/`(Sentry), `commerce/`(정책 플래그), `scan/`(촬영·갤러리·파일·PDF 래스터), `ink/`(필기 코어) | `lib/core/**` |
| `lib/design/` | 토큰(`tokens/color_tokens.dart`·`typography.dart`·`dimens.dart`, `shape_tokens.dart`·`spacing_tokens.dart`·`typography_tokens.dart`), `theme.dart`, `role_accent.dart`, `widgets/` 15종 | `lib/design/**` |
| `lib/shared/` | `constants/`(AppConstants·PlanTier), `errors/`(AppError·friendlyError), `format/`(Formatters), `labels/`(QuestionRoomLabels), `widgets/`(ScreenVisibility·WithdrawalPendingBanner·CommerceNoticeCard), `conversation_ui/`(도메인 무지 말풍선) | `lib/shared/**` |
| `lib/data/` | `mappings/subject_labels.dart` 1개뿐(README 의 `models/`·`repositories/health_repository` 서술은 구식 — 실제 없음) | `lib/data/mappings/subject_labels.dart`, `README.md:51` |
| `lib/features/` | `auth/ community/ dev/ individual_question/ mentors/ mypage/ notifications/ onboarding/ question_room/ scan_annotation/` | `lib/features/*` |

### 1-2. feature 내부 data/ui 분리 규칙

- 규칙 서술: "각 feature: `data/` 모델·레포, `ui/` 화면·위젯 — 한 파일에 안 몰기" (`HANDOFF.md:220`).
- 실제 형태: feature 루트에 **탭 진입 화면 1개**(`question_room_screen.dart`, `community_screen.dart`, `mentors_screen.dart`, `notifications_screen.dart`, `individual_question_tab_screen.dart`, `mypage_screen.dart`) + `data/` + `ui/`.
  - `features/community/data/`: read/write repository, gateway(`comments_gateway.dart`, `board_post_create_gateway.dart`, `board_post_update_gateway.dart`, `board_post_media_gateway.dart`), `community_models.dart`, `model_parse.dart`, `community_paginator.dart`, `community_post_error_mapper.dart`, URL 리졸버 2종, `user_blocks_repository.dart`, `community_labels.dart`. `ui/`는 `board/ shortform/ activity/ blocks/ widgets/` 하위 폴더.
  - `features/question_room/data/`: `models/`(room·question_thread·question_message·question_attachment·connection_note·model_parse), `attachments/`(upload·url_resolver·device_image_picker·trusted_attachment_url), read/write repository, `thread_realtime.dart`, `thread_messages_controller.dart`, `qna_error_mapper.dart`, lookup repo 2종, `room_safety_repository.dart`, `thread_status_counts.dart`, `room_counterparty.dart`. `ui/`는 `mentor/` 하위(멘토 역할 화면)와 `widgets/`.
  - `features/individual_question/data/`: repository, `models/`, `iq_realtime.dart`, `iq_messages_controller.dart`, `iq_error_mapper.dart`, 첨부 5종(`iq_attachment_upload_core.dart` 순수 오케스트레이터 + `iq_attachments_repository.dart` + url_resolver + saver + grouping + policy), `iq_annotation_repository.dart`.
  - `features/mypage/data/`: `mypage_repository.dart`(읽기 전용), `account_deletion_repository.dart`, `profile_edit_repository.dart`, `notification_settings_repository.dart`, `mypage_models.dart`. `ui/sections/` 6 섹션.
  - `features/mentors/data/`: `mentor_directory_repository.dart`(+Gateway), `mentor_favorites_repository.dart`, `free_question_entry.dart`, `mentor_models.dart`, `mentor_sort.dart`, `mentor_subject.dart`, `mentor_directory_view.dart`; `format/mentor_price_format.dart`.
  - `features/notifications/data/`: repository·realtime·badge_controller·`notification_types.dart`(정본 18종)·`app_notification.dart`; `ui/notification_target_opener.dart`.

### 1-3. 의존 방향 — 관례는 있으나 도구로 강제되지 않음

- 린트: `analysis_options.yaml`은 `flutter_lints` + 4개 규칙뿐(`prefer_const_constructors`, `prefer_const_constructors_in_immutables`, `prefer_final_locals`, `avoid_print`) — **import 방향 린트 없음** (`analysis_options.yaml:1-8`).
- 의도된 방향: `features → core/shared/design/data`, `core → shared`. 그러나 **역방향 의존이 다수 실재**한다:
  - `core/deeplink/deep_link_service.dart:3` → `app/app_tabs.dart`; `core/deeplink/notification_deep_link_controller.dart:3-4` → `app/app_tabs.dart`, `features/notifications/data/notification_types.dart`; `core/push/push_payload.dart:3` → `features/notifications/data/notification_types.dart`.
  - `core/auth/deletion_notice_controller.dart:3` → `features/mypage/data/account_deletion_repository.dart`.
  - `core/entitlement/subscription_status_display.dart:1` → `design/widgets/status_pill.dart`.
  - `shared/labels/question_room_labels.dart:1-2` → `features/question_room/data/models/*`; `shared/widgets/withdrawal_pending_banner.dart:8` → `features/mypage/ui/account_delete_screen.dart`.
  - `design/theme.dart:3` → `core/auth/auth_service.dart`(역할별 강조색).
- 계층을 코드로 강제하는 테스트는 부분적: `test/shared/conversation_ui_layering_test.dart`(말풍선 위젯이 도메인을 import 하지 않음 — `lib/shared/conversation_ui/conversation_bubble.dart:1-6` 주석), `test/contracts/iq_create_boundary_test.dart`(IqCreateScreen 을 production 그래프에서 import 0), `test/contracts/outbound_api_manifest_test.dart`(서버 표면 집합 고정).

### 1-4. 상태관리·DI 관례 (프레임워크 없음)

- 전역 싱글턴 + `ChangeNotifier`/`ValueNotifier`: `AuthService.instance`(`lib/core/auth/auth_service.dart:32`), `VersionGateController.instance`(`version_gate_controller.dart:46`), `DeepLinkService.instance`(`deep_link_service.dart:20`), `DeletionNoticeController.instance`(`deletion_notice_controller.dart:25`), `NotificationBadgeController.instance`(`notification_badge_controller.dart:26-27`), `TabNavigator.request`(`app_tabs.dart:30`), `DataRefreshBus.*Generation`(`data_refresh_bus.dart`).
- "DI 프레임워크 없이 생성자 주입 + 프로덕션 기본값(instance) 패턴" 명시(`version_gate_controller.dart:33`). 화면은 `const` 기본 레포를 필드로 갖고(`question_room_screen.dart:91-92`), 테스트는 `xxxOverride` 생성자 파라미터로 주입: `loaderOverride`(23회), `webBridgeOverride`(6), `currentUserIdOverride`(6), `createCtaOverride`(6), `controllerOverride`, `realtimeFactoryOverride`, `signOutOverride`, `roleOverride`, `isMentorOverride` 등(grep 집계).
- 화면 로딩 패턴: `late Future<T> _future; setState(() => _future = _load())` + `FutureBuilder`(`question_room_screen.dart:94,174-177,215`), 또는 세대 토큰(`_loadGeneration`)으로 늦은 응답 폐기(`mypage_screen.dart:75,129-140`, `mentor_detail_screen.dart:80,118-120`).
- "작은 ChangeNotifier 컨트롤러" 규약: `ThreadMessagesController`(`thread_messages_controller.dart:9`), `IqMessagesController`(`iq_messages_controller.dart:11`), `CommunityPaginator<T>`(`community_paginator.dart:5-12`).

---

## §2 부팅·세션·역할·계정상태 흐름

### 2-1. main() 순서 (`lib/main.dart:19-58`)

1. `WidgetsFlutterBinding.ensureInitialized()` → `dotenv.load('.env')`(실패 무시, `:22-27`).
2. `bootstrapCrashReporting(appRunner: …)` — Sentry 를 **가장 먼저** 기동, DSN 없으면 appRunner 만 실행(`:33`, `lib/core/observability/crash_reporting.dart:29-85`). fail-open 계약: init 실패 시 runner 1회 fallback, runner 오류는 rethrow, runner 는 정확히 1회(`crash_reporting.dart:13-23,39-54`).
3. `SupabaseInit.ensureInitialized()` — `AppConfig.hasCredentials` 거짓이면 초기화를 건너뛰고 빈 앱 구동(`lib/core/supabase/supabase_client.dart:11-19`). 이후 모든 레포는 `SupabaseInit.clientOrNull`(`:24-25`)을 통해 클라이언트를 얻는다.
4. `WebSessionHygiene.register(() => WebViewCookieManager().clearCookies())`(`main.dart:39-41`).
5. `AuthService.instance.bootstrap()`(`:44`) — 세션 복원 + 프로필 로드 + `onAuthStateChange` 구독.
6. `DeepLinkService.instance.initialize()`(`:49`) — 인자 없이 호출 → payload 스트림 구독 0개(OS 푸시 없음).
7. `unawaited(VersionGateController.instance.start())`(`:55`) — await 하지 않음(첫 프레임을 네트워크에 묶지 않음).
8. `runApp(const SsambershipApp())`.

### 2-2. 루트 앱·라우터 (`lib/app/app.dart`, `router.dart`)

- `ListenableBuilder(listenable: AuthService.instance)` 아래 `MaterialApp.router`, `theme: AppTheme.build(AuthService.instance.currentRole)`(역할 변화 시 테마 재빌드, `app.dart:20-26`), `locale: ko` 단일(`:29-30`), `routerConfig: AppRouter.router`, `builder: VersionGateShell(controller: VersionGateController.instance, child)`(`:40-43`) — 게이트는 Navigator **위**에 얹혀 통과 전에는 어떤 라우트도 진입 불가.
- `GoRouter(initialLocation: '/splash', refreshListenable: AuthService.instance, redirect: EntryGuard.redirect(access: AuthService.instance.access, location: state.matchedLocation))` (`router.dart:18-24`).

### 2-3. AuthService (`lib/core/auth/auth_service.dart`)

- `enum AppRole { student, mentor, admin, guest }`(`:13`), `enum AccessState { loading, loggedOut, guest, full, blocked }`(`:22`).
- 내부 상태: `_bootstrapping`, `_guest`, `_role`, `_roleFetchFailed`, `_displayName`, `_account: AccountState`(`:34-39`). 게터: `isBootstrapping`, `isGuest`, `currentRole`, `accountState`, `displayName`(nickname → full_name → ''), `roleLabel`('학생'/'멘토'/'' — `:53-63`), `isSignedIn`(=Supabase `currentSession != null`, `:69`), `access`(`:72-79`).
- **`computeAccess` 판정 순서**(`:88-112`): `bootstrapping → loading`; signedIn 이면 `account.isRetryable || roleFetchFailed → blocked`(재시도 가능 차단) → `!account.allowsAppUse → blocked` → `role == admin → blocked` → `student|mentor → full` → 그 외 role 불명 → blocked; signedIn 아니면 `guest → guest` else `loggedOut`.
- 프로필 로드(`_loadProfileOnce`, `:207-262`): `users` 본인 행 1회 통합 SELECT `'role, nickname, full_name, status, suspended_until'`(`:221-225`) → `_parseRole`('student'|'mentor'|'admin'|그외 guest, `:275-286`) → `AccountStatusReader.resolve(PrefetchedUserRowGateway(...))`(`:231-238`). single-flight(`_profileLoad`, `:190-200`). N32: 같은 사용자의 백그라운드 재로드가 **일시 실패**하면 마지막 정상 프로필 유지(`:243-248,267-271`).
- auth 이벤트(`_onAuthChange`, `:165-185`): `signedOut` → `DeepLinkService.onSignedOut()` + `WebSessionHygiene.clear()` + `_resetProfile()`; `signedIn|initialSession` → `DeepLinkService.onSignedIn(uid)`; 모든 이벤트 후 `_loadProfile()`.
- 로그인 API: **이메일+비밀번호만** `signInWithPassword`(`:304-320`); `enterAsGuest()`(`:323-327`); `signOut()`(`:330-342`: DeepLink pending 폐기 → `DeletionNoticeController.clear()` → `WebSessionHygiene.clear()` → `auth.signOut()` → `_resetProfile`); `reloadProfile()`(`:345-348`). 회원가입 API 없음(`lib/features/auth/login_screen.dart:19,151` "회원가입은 웹에서").
- `blockedMessage`/`isRecoverableBlock`(`:115-148`) — BlockedScreen 이 재시도 버튼 노출 여부에 사용(`lib/features/auth/blocked_screen.dart:19,50,56`).

### 2-4. AccountStatus (`lib/core/auth/account_status.dart`)

- `enum AccountStatusKind { active, suspended, banned, deletionPending, deletionLocked, deleted, fetchFailed }`(`:14-37`). `AccountState.allowsAppUse = active || deletionPending`(`:58-60`), `isRetryable = fetchFailed`(`:63`), `isBlocked = !allowsAppUse`(`:65`).
- 게이트웨이 포트 `AccountStatusGateway { fetchUserRow(userId); fetchWriteBlocked(userId); fetchDeletionSelfStatus() }`(`:110-131`). Supabase 구현: `users.select('status, suspended_until').eq('id',uid).maybeSingle()`(`:140-147`), RPC `account_deletion_write_blocked(p_user_id)` → bool(`:150-158`), RPC `account_deletion_status_self()` → `{ok, exists, state, write_blocked, can_cancel}`(`:161-168`). 주의: `account_deletion_jobs` 직접 SELECT 는 테이블 GRANT 부재로 403(`:127-129`).
- 판정 본체 `AccountStatusReader.resolve`(`:226-312`): ① users 행 실패/없음 → fetchFailed ② write_blocked RPC 실패 → fetchFailed, true → deletionLocked ③ status_self 실패 → fetchFailed; exists 면 state ∈ {locked,purging,storage_purged,finalized,auth_soft_deleted} 또는 write_blocked → deletionLocked; completed → deleted; pending 기록 ④ `lower(status)=='banned'` → banned; `'suspended'` 이고 `suspended_until` NULL 또는 미래 → suspended(과거면 active 취급) ⑤ jobPending → deletionPending, 아니면 active. 전부 **fail-closed**.

### 2-5. EntryGuard·HomeShell (`lib/app/entry_guard.dart`, `home_shell.dart`)

- 경로 상수: `/splash /login /home /blocked /dev/gallery /dev/s3`(`entry_guard.dart:14-19`). `guestAllowedTabs = {1, 2}`(커뮤니티·멘토찾기, `:25`).
- `redirect`(`:31-52`): `/dev/*` 는 가드 제외; loading→`/splash`, loggedOut→`/login`, guest→`/home`|`/login` 만 허용, full→`/home` 고정, blocked→`/blocked` 고정. 전수표 테스트 `test/screens/entry_guard_redirect_test.dart`.
- HomeShell: 초기 탭 = 게스트면 2(멘토찾기) 아니면 0(`home_shell.dart:68`); 게스트가 비허용 탭 선택 시 `context.go('/login?notice=login_required')`(`:101-104`); 로그인 사용자면 `NotificationBadgeController.instance.refresh()`(`:73-75`); dispose 시 배지 clear(`:83`).
- 탈퇴 예약 배너 `WithdrawalPendingBanner` 를 셸 레벨 body 최상단에 상시 배치(`:150-153`), 정본은 `DeletionNoticeController`(서버 `account_deletion_status_self` single-flight, 세대 토큰, 로컬 캐시 금지 — `lib/core/auth/deletion_notice_controller.dart:5-18,80-97`).

### 2-6. 역할별 테마·화면 분기

- `AppTheme.build(AppRole)` → `RoleAccent.forRole(role)`: mentor 면 mentor 강조, 그 외 student(`lib/design/theme.dart:15-16`, `lib/design/role_accent.dart:51-52`).
- 탭 화면 내부에서 `AuthService.instance.currentRole` switch 로 역할 분기: 질문방(`question_room_screen.dart:41-54`: mentor→`MentorInboxScreen`, student→`_StudentRoomList`, admin/guest→EmptyState), 개별질문(`individual_question_tab_screen.dart:30-34`), 마이페이지 레포(`mypage_repository.dart:41-64`), 연결노트 author_role(`question_room_write_repository.dart:252-262`), 알림 상세 열기(`notification_target_opener.dart:64-65,89`). `AuthService.instance` 참조 파일 19개, `currentRole` 비교 12곳(grep).

---

## §3 데이터 계층 패턴

### 3-1. Repository 관례

- `const` 클래스, `SupabaseClient get _client { c = SupabaseInit.clientOrNull; if null throw AppError('백엔드에 연결되어 있지 않아요.') }`, `String get _uid { … throw AppError('로그인이 필요해요.') }` 정형(`community_write_repository.dart:27-39`, `question_room_write_repository.dart:49-64`, `individual_question_repository.dart:38-52`, `mypage_repository.dart:22-34`).
- 읽기/쓰기 분리: `QuestionRoomReadRepository`/`QuestionRoomWriteRepository`, `CommunityReadRepository`/`CommunityWriteRepository`; `MyPageRepository` 는 "어떤 mutate 도 하지 않는다"(`mypage_repository.dart:14`).
- 권한 필터는 앱 코드로 만들지 않고 RLS 에 의존("myRooms()는 별도 where 없이도 RLS가 내 방만" — `question_room_read_repository.dart:28-30,43-49`).
- 실패 처리 두 갈래: (a) 핵심 경로는 예외 전파 + 매퍼로 한글화, (b) 비핵심(조회수·통계·차단 목록·잔액 보강)은 `try { } catch (_) { 폴백 }` 로 삼킴(`community_write_repository.dart:101-116`, `mentor_directory_repository.dart:207-233`, `user_blocks_repository.dart:92-108`).

### 3-2. Port / Gateway / Backend (주입 seam) 관례

- 이름 규약: 추상 `XxxPort` 또는 `XxxBackend`/`XxxGateway` + 운영 `SupabaseXxx` + 테스트 손코딩 `Fake`/`Recording` 구현(mock 프레임워크 금지 — `comments_gateway.dart:10-12`, `account_status.dart:109`).
- 실재 포트(발췌): `AccountStatusGateway`, `ThreadRealtimePort`(`thread_realtime.dart:10-21`), `IqRealtimePort`(`iq_realtime.dart:12-26`), `NotificationsRealtimePort`(`notifications_realtime.dart:11-22`), `NotificationsRepository`(추상, `notifications_repository.dart:44-54`), `RoomSafetyPort`(`room_safety_repository.dart:22-35`), `AccountDeletionPort`+`AccountDeletionBackend.rpc(fn, params)`(`account_deletion_repository.dart:141-166`), `ProfileEditBackend.rpc(fn, params)`(`profile_edit_repository.dart:22-24`), `NotificationSettingsPort`+`NotificationSettingsBackend`(`notification_settings_repository.dart:77-95`), `FreeQuestionEntryPort`(`free_question_entry.dart:102-115`), `AttachmentUploaderPort`+`QnaAttachmentBackend`(`attachment_upload.dart:104-114,331-353`), `AttachmentUrlBackend`(`attachment_url_resolver.dart:13-23`), `ShortformMediaBackend`, `CommunityPostImageReadBackend`, `ImagePickerPort`, `ScanSourcePort`(`scan_source_picker.dart:31-37`), `PdfRasterizerPort`(`pdf_rasterizer.dart:41-47`), `AnnotationDocStore`(`scan_annotation_repository.dart:18-27`), `IqAnnotationStore`, `IqAttachmentsPort`, `VersionPolicyPort`·`GatePassCache`·`BuildNumberProvider`·`GatePlatformResolver`(`version_gate_ports.dart`), `PushPermissionPort`(`push_ports.dart:27-30`), `CommentsGateway`(`comments_gateway.dart:13-66`: `selectComments(table, filters, limit, offset, schema)`, `insertComment(table, values)`, `softDeleteShortformComment(id)`), `MentorDirectoryGateway`(`mentor_directory_repository.dart:14-69`).
- 순수 오케스트레이터 함수(의존 전부 클로저 주입): `createBoardPostViaRpc({authUserId, callRpc, fetchPostById, …})`(`board_post_create_gateway.dart:140-185`), `updateBoardPostViaRpc`(`community_write_repository.dart:369-389` 호출부), `uploadIqAttachmentCore(...)` + typedef 7종(`iq_attachment_upload_core.dart:46-70,294`).

### 3-3. RPC 봉투(envelope) 처리 방식 — 서버 스타일 2종

1. **`raise exception 'CODE'` 스타일** → `PostgrestException.message` 선두가 코드. 매퍼: `qnaErrorCode` 정규식 `^[A-Z][A-Z0-9_]+$`(`qna_error_mapper.dart:85-90`), `iqErrorCode` 선두 토큰 `^[A-Z][A-Z0-9_]+`(`NOT_ANSWERABLE_STATUS:answered` 허용, `iq_error_mapper.dart:69-74`), `profileUpdateErrorCode`(`profile_edit_repository.dart:73-78`). 호출부는 `throw mapQnaError(e)` / `mapIqError` / `mapProfileUpdateError` 한 줄(미지 코드는 원본 예외 그대로 → `friendlyError` 일반 문구).
2. **jsonb 봉투 `{ok, code, contract_version, …}` 스타일** → strict 파싱, `ok==true && contract_version==1` 아니면 실패로 던짐(성공 위장 금지): `parseBoardPostCreateEnvelope`(`board_post_create_gateway.dart:120-135`), `ensurePostSoftDeleteOk`(`community_write_repository.dart:245-255`), `deleteMyShortformComment`(`:199-218`), `ProfileEditRepository.updateProfile`(`profile_edit_repository.dart:114-118`), `parseUnreadCountEnvelope`/`isMarkNotificationReadSuccess`(`notifications_repository.dart:90-106`), `_parseRequestOutcome`(sealed `DeletionRequestOutcome` 3분기, `account_deletion_repository.dart:233-269`), `weeklyUsage`(`ok:true` 만 파싱, `question_room_read_repository.dart:154-155`), `ensureRoom`(`free_question_entry.dart:177-183`), `appendMessage` IQ(`individual_question_repository.dart:219-228`).
- 공통 매퍼: `communityPostWriteContractError(code)`(`community_post_error_mapper.dart:11-50`), `shortformCommentDeleteError`/`postDeleteError`/`commentContractError`(`community_write_repository.dart:257-310`), `qnaMessageForCode`(예외·봉투 공용 문구 정본, `qna_error_mapper.dart:20-82`). 계정 상태 문구는 매퍼 간 통일 카피(`ACCOUNT_NOT_ACTIVE` 등).

### 3-4. 스키마 호출 방식(api_app_v1 / api_web_v1)

- `api_app_v1` (쓰기 RPC, authenticated 전용): `client.schema('api_app_v1').rpc('community_post_create'|'community_post_update'|'community_post_soft_delete'|'user_profile_update_self'|'ensure_free_question_room')`(`community_write_repository.dart:233-235,339-341,379-381`, `profile_edit_repository.dart:39`, `free_question_entry.dart:170-173`). **`schema()` 생략 시 public 으로 나가 PGRST202**(반복 경고 주석).
- `api_web_v1` (읽기 뷰·self RPC, anon 허용 포함): 뷰 `community_posts_v1`(`community_read_repository.dart:70-74`), `community_comments_v1`(`:128-129`), `mentor_directory_v1`(`mentor_directory_repository.dart:38-46`, `mentor_lookup_repository.dart:46-51`), `my_wallet_v1`, `my_cash_ledger_v1`(`mypage_repository.dart:138-143,158-163`); RPC `weekly_question_usage_self(p_mentor_id)`, `weekly_question_usage_self_batch(p_mentor_ids)`(`question_room_read_repository.dart:148-151,171-174`).
- 나머지 RPC 는 public(스키마 미지정): `qna_*`, `iq_*`, `account_deletion_*`, `notification_*`, `get_mobile_app_version_policy` 등(§7-1 매니페스트 참조).

### 3-5. 모델 파싱 관례

- `model_parse.dart` 가 feature 마다 **중복** 존재: `community/data/model_parse.dart`(`parseTime`→`toLocal()`·epoch 폴백, `parseInt`), `question_room/data/models/model_parse.dart`(`parseTime`, `parseTimeOrNull`).
- 모델: `const` 클래스 + `factory fromMap(Map)` + (`toMap`) (`room.dart:8-48`, `question_thread.dart:66-126`); enum 은 `fromCode()` 와 `unknown` 폴백("DB 로 다시 쓰지 않는다", `question_thread.dart:6-39`).
- 화면 노출 금지 규칙: 영문 코드·UUID·테이블명 미노출 → `QuestionRoomLabels`(`shared/labels/question_room_labels.dart`), `subjectLabel`/`subjectCodeForDb`(`data/mappings/subject_labels.dart:107-128`), `subscriptionStatusDisplay`(`core/entitlement/subscription_status_display.dart`).

### 3-6. 서명 URL 리졸버·캐시 (4벌, 동일 패턴 반복)

| 리졸버 | 버킷 | TTL/마진 | 캐시 | 특이점 |
|---|---|---|---|---|
| `AttachmentUrlResolver`(`question_room/data/attachments/attachment_url_resolver.dart:29-71`) | `question-room-attachments` | 1h / 없음 | 프로세스 전역 `_shared` 싱글턴(`:42-45`), 키 `uid::path` | download 도 제공 |
| `IqAttachmentUrlResolver`(`individual_question/data/iq_attachment_url_resolver.dart:30-56`) | `individual-question-attachments` | 1h / 60s | 프로세스 전역 `_shared` 싱글턴(`:42-45`), 키 `uid::path` | 실패 미캐시 |
| `ShortformMediaUrlResolver`(`community/data/shortform_media_url_resolver.dart:83-255`) | `shortform-videos` | 10m / 60s | 키 `uid::raw`, single-flight, `forceRefresh` 세대 | 결과 타입 `ShortformMediaResolution{absent,resolved,failed,invalidReference}`; legacy 절대 URL 통과; 참조 형상 `shortform-videos/{uuid}/{name}` 엄격 검증 |
| `CommunityPostImageUrlResolver`(`community/data/community_post_image_url_resolver.dart:41-126`) | `community-post-images` | 10m / 60s | 전역 `sharedCommunityPostImageUrlResolver`(`:159-160`) | 실패는 null(throw 금지) |

- 원칙: 서명 URL·토큰을 로그/예외/DB/SharedPreferences 에 싣지 않는다(`shortform_media_url_resolver.dart:81-82`).

### 3-7. Realtime 구독 패턴 (postgres_changes, 보조 채널)

- 공통 구조: `client.channel(name)` → `onPostgresChanges(event, schema:'public', table, filter: eq)` → `subscribe()`; `dispose()` 에서 `removeChannel`. 클라이언트 없으면 조용히 무시.
  - 질문방: 채널 `question_thread_$threadId`; insert `question_messages`(thread_id), update `question_threads`(id), insert `question_attachments`(thread_id)(`thread_realtime.dart:44-93`).
  - IQ: 채널 `iq_$questionId`; insert `individual_question_messages`, insert `individual_question_attachments`, update `individual_questions`; `subscribe((status,_){…})` 로 재구독 시 `onReconnected` 1회(`iq_realtime.dart:54-110`).
  - 알림: 채널 `notifications_$userId`; insert `notifications` filter `recipient_user_id`; 재연결 콜백(`notifications_realtime.dart:47-75`).
- 폴백 계약: publication 미포함이면 콜백이 오지 않고 "전송 후 재조회 + 수동 새로고침"으로 동작(`thread_realtime.dart:25-28`, `HANDOFF.md:145-149`). 정본은 언제나 서버 재조회(`iq_realtime.dart:10-11`).
- 병합: `ThreadMessagesController.add/upsertFromServer/upsertAllFromServer/resetTo`, 정렬 `(created_at, id)`(`thread_messages_controller.dart:26-95`).

### 3-8. 페이지네이션·커서

- 커뮤니티: offset 기반, `CommunityPage{items, rawCount, nextOffset=offset+rawCount, hasMore=rawCount==limit}`(`community_read_repository.dart:44-56`) — 차단 필터 후에도 오프셋은 필터 **전** 행 수. `CommunityPaginator<T>{fetch(offset,limit), pageSize=20, refresh(), loadMore(), 세대 토큰}`(`community_paginator.dart:12-82`).
- 알림: keyset `(created_at DESC, id DESC)`, `NotificationCursor{createdAtRaw(원문 문자열), id}`, 필터 문자열 `notificationsAfterFilter`, `pageSize+1` 조회로 hasNext 판정(`notifications_repository.dart:12-100,128-146`).
- 메시지: `recentMessages(limit)` + `messagesBefore(cursor)` 복합 커서 `created_at.lt."TS",and(created_at.eq."TS",id.lt."ID")`(`question_room_read_repository.dart:220-304`).
- 멘토 디렉터리: `range(offset, offset+99)` 100행씩 최대 50페이지 전량 로드 후 로컬 검색/필터(`mentor_directory_repository.dart:100-155`), 상한 도달 시 `incomplete=true`.

### 3-9. 교차 화면 무효화·가시성

- `DataRefreshBus`(`lib/core/refresh/data_refresh_bus.dart`): `walletGeneration`, `subscriptionGeneration`(생산자 0 — 의도된 대기), `notificationsGeneration`, `questionRoomsGeneration` 4종 `ValueNotifier<int>`; 값은 싣지 않고 각 화면이 자기 레포로 재조회. 생산자: `home_shell.dart:106,108`, `iq_create_screen.dart:361`, `iq_detail_screen.dart:466,488`.
- `ScreenVisibility`(InheritedWidget) + `ResumeVisibilityGate` mixin(`shared/widgets/screen_visibility.dart:11-68`): resumed 시 보이는 화면만 `onResumeRefresh()`, 가려진 화면은 재노출 시 1회. IndexedStack 탭·마이페이지·멘토 상세·알림·커뮤니티가 채택.
- 로컬 캐시: `UserBlocksRepository` 의 **static** 차단 목록 캐시 TTL 30s + single-flight(`user_blocks_repository.dart:41-108`); 이외 오프라인 영속 캐시는 없다(SharedPreferences 는 버전 게이트 1키만).

### 3-10. Storage 업로드 패턴

- 경로 규약(버킷 상대): 질문방 `{roomId}/{threadId}/{ts}_{safeName}`(`attachment_upload.dart:319-327`), 게시글 이미지 `{uid}/{ts}_{safeName}` + RPC ref `community-post-images/{uid}/{object}`(`board_post_media_gateway.dart:41-54`), IQ `{questionId}/{ts}-{salt}.{ext}`, 주석 `{roomId}/{attachmentId}/ink.json`·IQ 첨삭 `{questionId}/annotations/{attachmentId}.json`(`core/ink/ink_storage_paths.dart:10-16`, `HANDOFF.md:80-90`).
- 업로드 → 행 등록은 **RPC 단일 경로**(`qna_register_attachment`, `add_individual_question_attachment`), 등록 실패 시 미등록 객체 보상 DELETE, 23505 재시도 시 기존 행 의미 일치 검사 후 멱등 수용(`attachment_upload.dart:194-259`). `FileOptions(upsert:false)`(`:371-375`).
- 사전 축소: `downscaleIfOversized`(5MB 초과 → 장변 2560·JPEG85, `compute` isolate — `core/scan/image_downscaler.dart:6-17`).

---

## §4 라우팅·탭·딥링크

### 4-1. go_router 라우트 전체 (`lib/app/router.dart:25-53`)

| path | 화면 | 비고 |
|---|---|---|
| `/splash` | `SplashScreen` | initialLocation |
| `/login` | `LoginScreen` | `?notice=login_required` 쿼리 사용(`home_shell.dart:102`) |
| `/home` | `HomeShell` | 5탭 |
| `/blocked` | `BlockedScreen` | |
| `/dev/gallery`, `/dev/s3` | `WidgetGallery`, `S3DataInspector` | `kDevToolsEnabled`(= `!kReleaseMode`, `features/dev/dev_flags.dart:5`) 일 때만 등록 |

- `OnboardingScreen`(`features/onboarding/onboarding_screen.dart`)은 라우터에 **등록되지 않은 사문**(참조 0).
- 상세 화면은 전부 `Navigator.of(context).push(MaterialPageRoute(...))` — 46곳; `context.go(` 는 7곳(grep). 즉 **명명 라우트 4개 + 명령형 push 스택** 구조.

### 4-2. HomeShell 5탭·TabNavigator (`lib/app/home_shell.dart`, `app_tabs.dart`)

- `AppTab.questionRoom=0, community=1, mentors=2, notifications=3, individualQuestion=4, myPage=100(가상)`(`app_tabs.dart:10-19`). 라벨 `AppConstants.bottomTabLabels`(`shared/constants/app_constants.dart:24-30`), 아이콘 `_icons`(`home_shell.dart:56-62`), 페이지 `_pages` const 리스트(`:47-53`) — **세 배열이 인덱스로 암묵 결합**.
- `IndexedStack` + 방문 탭만 빌드(`_built`, `:45,69,111,161-165`) — 방문 후 계속 살아 있음(상태·구독 유지).
- `TabNavigator.request: ValueNotifier<int>`(`app_tabs.dart:30`) 전역 채널; HomeShell 이 listener 로 수신 후 -1 복귀(`home_shell.dart:89-98`). `AppTab.myPage` 요청은 push 로 변환.
- 마이페이지: AppBar 우측 버튼 → `Navigator.push<int>(_MyPagePage)`; 마이페이지 내부 탭 이동 액션은 **pop 결과값(탭 index)** 으로 셸에 전달(`:115-133,247-268`).

### 4-3. 딥링크 (`lib/core/deeplink/*`, `features/notifications/ui/notification_target_opener.dart`)

- `NotificationEventType` 18종 정본(`notifications/data/notification_types.dart:21-65`) → `notificationDestinationOf` 4목적지 `{questionRoomTab, individualQuestionTab, myPage, stay}`(`:127-172`); CR 2종(`new_order_message`, `new_application`)은 `kGatedNotificationTypeCodes` 로 목록 쿼리에서 exact 제외(`:15-18`, `notifications_repository.dart:123-137`).
- `resolveNotificationDeepLink(target)` → sealed `NotificationDeepLinkRoute` 6종 `{Tab, Room(roomId?,threadId?), Iq, BoardPost, Shortform, Mentor}`; id 는 UUID 정규식 검증 통과 시에만 상세(`notification_deep_link_controller.dart:8-17,54-155`). `link/url` 필드는 모델에 아예 없음.
- `NotificationDeepLinkController`: eventId LRU dedup 32, 비로그인 pending TTL 15분·사용자 귀속, `openDetail` 미배선이면 탭 폴백(`:167-272`).
- 프로덕션 생산자: OS 푸시 없음 → `DeepLinkService.initialize()` 구독 0(`deep_link_service.dart:12-31`). 실제 상세 이동은 **인앱 알림함 탭** → `NotificationTargetOpener.open(context, route)` 가 역할별로 사전 조회(RLS) 후 push(`notification_target_opener.dart:36-206`: 질문방 학생=`ChatScreen`/`MentorRoomHomeScreen`, 멘토=`MentorAnswerScreen`/`StudentRoomHomeScreen`, IQ=`IqDetailScreen(questionId)`, 게시판=`BoardDetailScreen(post, read, write)`, 숏폼=`ShortformDetailScreen`, 멘토=`MentorDetailScreen(item)`).
- 게스트 허용 탭: `{1,2}`(`entry_guard.dart:25`); 마이페이지·질문방·알림·개별질문은 로그인 유도.

### 4-4. 화면 수가 3~4배로 늘 때의 구조적 병목 (근거 기반)

1. **주소 없는 상세 화면**: 상세는 전부 생성자 인자(`Room`, `QuestionThread`, `BoardPost`, `MentorListItem` 등 로드된 모델)를 요구하는 push 라우트라 URL/딥링크로 직접 도달 불가. 딥링크 하나를 열려면 `NotificationTargetOpener._openRoom` 처럼 60행 가까운 사전 조회 코드가 목적지마다 필요(`notification_target_opener.dart:62-149`). 화면이 늘면 이 어댑터가 목적지 수만큼 증식한다.
2. **셸 하드코딩**: 탭 추가 = `AppTab` 정수 + `_pages` + `_icons` + `bottomTabLabels` + `EntryGuard.guestAllowedTabs` 5곳 동시 수정(`app_tabs.dart`, `home_shell.dart:47-62`, `app_constants.dart:24-30`, `entry_guard.dart:25`). 역할별 탭 구성 차이(웹은 학생 7·멘토 4 네비)를 표현할 수단이 없음 — 현재는 같은 5탭에서 화면 내부가 `currentRole` switch 로 갈린다(`question_room_screen.dart:41-54`).
3. **EntryGuard 의 고정 위치 집합**: `redirect` 가 `/home` 하나로 수렴시키므로 새 top-level 라우트를 추가하면 switch 전부를 손봐야 함(`entry_guard.dart:38-51`). full 상태에서 `/home` 외 어떤 위치도 `/home` 으로 되돌린다(`:47-48`) — 명명 상세 라우트를 추가하려면 이 규칙 자체를 재설계해야 한다.
4. **AccessState 5종**: 회원가입·온보딩·프로필 미완성·학교 인증 대기 같은 중간 상태를 표현할 값이 없다(`auth_service.dart:22`). role 불명은 곧바로 blocked(`:107-108`).
5. **정수 채널 `TabNavigator`**: 목적지 페이로드가 int 하나. 상세 목적지는 별도 sealed route + opener 로 우회 중(위 1).
6. **IndexedStack 상주 탭**: 방문 탭이 계속 살아 있어 각 탭의 Realtime 채널·리스너가 누적(알림 채널 `notifications_$uid` 는 알림 탭 생존 동안 유지, `notifications_screen.dart:105-117`). 탭이 늘면 상주 구독·재조회 팬아웃(N12/N13 주석의 해결 대상)이 다시 커진다.
7. **역할 분기의 산재**: `AuthService.instance.currentRole` 를 화면·레포에서 직접 읽는 곳 12+, 싱글턴 참조 파일 19개. 역할이 늘거나 역할별 화면이 늘면 각 화면의 switch 가 늘어난다.
8. **의존성 주입 지점의 폭발**: 화면마다 `xxxOverride` 생성자 파라미터(30여 종)로 테스트 seam 을 뚫는 방식 → 화면 3배면 seam 도 3배.
9. **마이페이지 pop-int 핸드오프**(`home_shell.dart:115-133`)처럼 셸-화면 간 임시 계약이 이미 존재 — 라우팅 체계 부재의 징후.

---

## §5 플랫폼 인프라

### 5-1. web_bridge (`lib/core/web_bridge/`)

- `WebBridgeConfig.baseUrl = String.fromEnvironment('WEB_BASE_URL', defaultValue: 'https://ssambership.com')`(`web_bridge_config.dart:16-19`, 끝 슬래시 없음). 경로 상수: `billingManagePath='/subscriptions'`, `payoutManagePath='/mentor/payouts'`, `profileEditPath='/mentor/profile'`, `termsPath='/legal/terms'`, `privacyPath='/legal/privacy'`, `supportPath='/support'`, `reviewsPath='/mentor/reviews'`, `accountDeletePath='/account/delete'`, `iqCreatePath='/individual-questions/new'`, `iqCreateForMentorPath(id)='/mentors/{id}/individual-question/new'`(`:24-52`). 구매 유도 경로(`/subscribe`, `/wallet/charge`)는 **의도적으로 없음**(`:22-23`).
  - ※ 문서 불일치: `HANDOFF.md:112-114` 는 운영 도메인을 `https://ssambership-web.vercel.app`, 경로에 `subscribePath`/`rechargePath` 가 있다고 서술 — 코드와 다름(문서 구식).
- `WebBridge({UrlLauncher? launcher, String? baseUrl})`(`web_bridge.dart:19-21`): `_defaultLauncher = canLaunchUrl → launchUrl(externalApplication)`(`:26-29`), `buildUri(path, query)`(`:78-88`), `isAllowedUri`: https 강제 + 호스트 정확 일치 또는 `.$baseHost` 접미(`:97-106`), 결과 `enum WebOpenResult { opened, notConfigured, failed }`(`:7`). 열기 메서드 9종(`openBillingManage/openPayoutManage/openProfileEdit/openTerms/openPrivacy/openSupport/openReviews/openAccountDelete/openIqCreate({mentorId})`, `:34-74`), 모두 `?src=app` 쿼리.
- 화면 헬퍼 `web_bridge_actions.dart`: `openXxxWeb(context, {bridge})` 9종 + 미확정/실패 스낵바 `_showNotice`(`:12-81`). iOS 는 `LSApplicationQueriesSchemes=https` 단독 선언과 짝(`test/contracts/ios_release_config_contract_test.dart:31-33,128-152`).
- `WebSessionHygiene.register/clear/resetForTest`(`web_session_hygiene.dart:7-32`) — 로그아웃 전·계정 전환·숏폼 WebView 여닫이에서 쿠키 정리.

### 5-2. 숏폼 작성 WebView 브릿지 (`shortform_compose_bridge.dart`, `features/community/ui/shortform/shortform_compose_screen.dart`) + 웹 계약

- 앱 측(순수): `bootstrapPath='/api/app-session/bootstrap'`, `composePath='/app/community/shortform/new'`, `bridgeCompletePath='/app/bridge/complete'`, `bridgeErrorPath='/app/bridge/error'`, `bootstrapTarget='shortform_create'`(`shortform_compose_bridge.dart:20-26`). `buildBootstrapBody(accessToken, refreshToken)` → form-urlencoded `access_token&refresh_token&target`(`:39-49`). `isAllowedNavigation`: https + 호스트 **정확 일치**(서브도메인 불허) + 4 경로만(`:58-66`). `completionOf(uri)`: `/app/bridge/complete?kind=shortform&result=draft|published` 만 결과(`:71-82`).
- 화면 흐름(`shortform_compose_screen.dart:55-138`): `currentSession`·`refreshToken` 없으면 `needLogin`; `WebBridgeConfig.isConfigured` 아니면 error; `WebSessionHygiene.clear()` → `WebViewController.loadRequest(bootstrapUri, method: POST, headers: form-urlencoded, body)`; `NavigationDelegate.onNavigationRequest` 에서 완료 브릿지면 `pop(result)`, allowlist 밖은 `prevent`; Android `setOnShowFileSelector` 로 `mp4/mov/webm` 단일 파일(`:97-101,141-154`); dispose 시 쿠키 정리(`:47-53`). 진입점은 숏폼 피드(멘토 한정, `shortform_feed_view.dart:166`).
- 웹 측(`/home/user/ssambership_web`): `app/api/app-session/bootstrap/route.ts` — POST 전용(GET/PUT/PATCH/DELETE 405, `:53-64`), body 파싱 `parseBootstrapBody`(`lib/appSession/appSessionBootstrapCore.ts:57-90`, 상한 16KB, target enum 단일 `shortform_create → /app/community/shortform/new`, `:10-21`), 토큰 프로젝트 ref 일치 검사(`route.ts:83-86`), `setSession` 쿠키는 격리 버퍼에만 → `getUser` 재검증 → `assertAppSurfaceAccountActiveStrict` → `strictMentorRoleDecision`(멘토 아니면 `mentor_only`) 전부 통과한 303 응답에만 부착(`:88-127`), 쿠키 속성 `HttpOnly/Secure/SameSite=Lax/Path=/` 강제(`hardenAppSurfaceCookieWrites`, `:29-32,124-126`), `Cache-Control: no-store`. 브릿지 상수 `APP_BRIDGE_KINDS=['shortform']`, `APP_BRIDGE_RESULTS=['draft','published']`(`lib/appSession/appSurfacePaths.ts:8-16`). 완료·오류 페이지 `app/app/bridge/complete/page.tsx`, `app/app/bridge/error/page.tsx`.
- 숏폼 INSERT·Storage 업로드는 전부 웹 작성기가 수행 — 앱에 숏폼 쓰기 레포 없음(`shortform_compose_screen.dart:20-22`, `community_write_repository.dart:12-13`).

### 5-3. 버전 게이트 (`lib/core/version_gate/`)

- RPC `get_mobile_app_version_policy(p_platform)`(anon EXECUTE, `supabase_version_policy_port.dart:6-31`) → `VersionPolicy{platform, min_supported_build, latest_build, minimum_version_name, store_url, message}`(정수 필드 누락/형 불일치 → 1 폴백, `version_policy.dart:39-56`).
- 판정 `decide(currentBuild, policy)`: null 빌드 → pass(fail-open); `< min` → ForceUpdate; `latest > current` → Recommend; 정수 비교만(`version_gate_decision.dart:33-41`).
- `VersionGateStatus { idle, skipped, checking, pass, forceUpdate, recommend, fetchFailed }`(`version_gate_controller.dart:19-27`). 플랫폼 `resolveGatePlatform`: android/ios 만, web/desktop null → skipped(`gate_platform.dart:10-20`). 빌드번호는 `PackageInfo.buildNumber` 정수 파싱(`:142-149`).
- G1 캐시: `SharedPrefsGatePassCache` 키 `version_gate_last_pass_build`(`shared_prefs_gate_pass_cache.dart:10`); 조회 실패 시 마지막 통과 빌드와 같으면 pass, forceUpdate 수신 시 clear(`version_gate_controller.dart:86-110`). 한계: 판정 전 계속 오프라인이면 차단 불가(`version_gate_ports.dart:23-28`).
- 스토어 URL 재검증 `validatedStoreUri`: https + 호스트 정확 일치 `{play.google.com, apps.apple.com, itunes.apple.com}`(`store_url_policy.dart:10-27`).
- 셸: `VersionGateShell` 이 상태별 `VersionGateLoading / ForceUpdateScreen / VersionGateRetryScreen / RecommendUpdateBanner(Stack 오버레이)` 를 그린다(`version_gate_shell.dart:28-62`, `version_gate_screens.dart:43,102,137,196`).
- ※ `docs/APP_V16_MIN_VERSION_SERVER_REQUIREMENT.md` 는 상태 `WAITING_SERVER_GATE`·RPC 명 `get_app_version_policy` 초안 — **구식**(실제 RPC 명은 `get_mobile_app_version_policy`, 스냅샷 §4.7 "SQL 162 배포" `docs/APP_V16_SERVER_CONTRACT_SNAPSHOT.md:290`).

### 5-4. 푸시 포트 (`lib/core/push/`)

- App-F0: Firebase/FCM SDK·초기화·토큰 등록·OS 권한 요청 **전부 제거**(`push_ports.dart:1-10`, `lib/core/push/HANDOFF.md:1-30`). 남은 것: `PushPayload.fromRemote(data, title, body)`(type 18종 정확 일치, `room_id/thread_id/question_id`, dedup `notification_id`→`event_key`, `link/url` 폐기 — `push_payload.dart:16-69`), `PushPermissionPort`+`DisabledPushPermission`(항상 `notDetermined`, `:27-44`).
- 원칙: 발송은 서버 outbox worker 단독(`record_domain_notification → notification_outbox → deliveries`), 앱은 수신·토큰 등록만(재도입 시). `'firebase'` 문자열은 매니페스트 테스트로 0건 강제(`outbound_api_manifest_test.dart:321-326`).
- ※ `HANDOFF.md:151-160`(§3-4) 는 `FirebasePushGateway`·`register_device_token` 등 제거된 코드를 현행처럼 서술 — 구식. 정본은 `lib/core/push/HANDOFF.md`.

### 5-5. 크래시 리포팅 (`lib/core/observability/crash_reporting.dart`)

- `bootstrapCrashReporting({appRunner, initializerOverride, dsnOverride, environmentOverride})`(`:29-85`). 옵션 정본 `applyCrashReportingOptions`: `sendDefaultPii=false`, `tracesSampleRate=null`, `tracesSampler=null`, `profilesSampleRate=null`, release/dist 는 SDK 자동(`:99-113`). 환경 기본값 `staging`(`:125-128`), production 강제는 `tool/validate_release_env.dart`.

### 5-6. commerce_policy (`lib/core/commerce/commerce_policy.dart`)

- `kInAppPaymentSteeringEnabled = false`(const, `:10`), `kSubscriptionManageLinkEnabled = bool.fromEnvironment('SUBS_MANAGE_LINK_ENABLED', false)`(`:17-18`), `kPayoutManageLinkEnabled = bool.fromEnvironment('PAYOUT_MANAGE_LINK_ENABLED', false)`(`:29-30`), 대체 안내 문구 4종(`:21,33,36,39`). `Entitlement.inAppPurchaseEnabled = false`(`core/entitlement/entitlement.dart:23`). 가격 상수는 전부 null(`shared/constants/plan_constants.dart:19-23`).

### 5-7. scan / ink 코어 API

- `core/scan`: `enum ScanSource { camera, gallery, file }`, `kScanMaxLongSidePx=4096`, `ScanSourcePort { isAvailable; pick(source) → PickedImage? }`, `DeviceScanSourcePicker`(image_picker + file_picker)(`scan_source_picker.dart:7-105`); `PdfRasterizerPort.open(bytes) → PdfDocumentHandle{pageCount, renderPage(i, longSide), close}` + `PdfxRasterizer`, 상수 `kPdfRenderLongSidePx=2560`, `kPdfThumbLongSidePx=320`, `kPdfMaxPagesPerPick=5`(`pdf_rasterizer.dart:16-111`); `downscaleIfOversized`(`image_downscaler.dart`); `PickedImage{bytes, fileName, mimeType, sizeBytes}`, `scanMimeFromName`(`picked_image.dart`); `widgets/pdf_page_select_screen.dart`, `widgets/scan_pick_expander.dart`.
- `core/ink`: `InkDocument{format:'ssambership.ink', version 1, engine 'scribble', canvas, input_mode, updated_at, sketch}` + `fromJson/fromJsonString/copyWith`(`ink_document.dart:5-131`); `InkStoragePaths{bucket='connection-note-ink', annotationBucket='scan-annotations', noteDocument/noteThumbnail/annotationDocument/annotationFlattened/iqAnnotationDocument}`(`ink_storage_paths.dart:17-54`); `InkInputMode{label, code, fromCode}`; `InkCoordinateMapper.contain(...).normalize/denormalize/containsNormalized`(0..1 정규화 좌표, `ink_coordinate_mapper.dart:16-70`); `ScribbleInkAdapter.createNotifier/restoreNotifier/exportDocument/applyInputMode/renderThumbnailPng`(scribble 타입을 아는 유일 파일, `scribble_ink_adapter.dart:9-71`); `widgets/ink_toolbar.dart`. 규약: **기존 API 시그니처 변경 금지·추가만**(`HANDOFF.md:95`).

---

## §6 컴파일 타임 스위치·환경변수

| 종류 | 키 | 기본값 | 정의 위치 | 영향 |
|---|---|---|---|---|
| dart-define | `IQ_CREATE_ENABLED` | `false` | `features/individual_question/iq_flags.dart:19-20` | 학생 '새 개별질문' CTA 노출(켜져도 웹 등록 브릿지로만) |
| dart-define | `SUBS_MANAGE_LINK_ENABLED` | `false` | `core/commerce/commerce_policy.dart:17-18` | 마이페이지 '구독 관리(웹)' 링크 |
| dart-define | `PAYOUT_MANAGE_LINK_ENABLED` | `false` | `commerce_policy.dart:29-30` | 멘토 '정산 관리(웹)' 링크 |
| dart-define | `WEB_BASE_URL` | `https://ssambership.com` | `core/web_bridge/web_bridge_config.dart:16-19` | 웹 브릿지·숏폼 WebView 호스트(빈 값 → 안내 폴백) |
| dart-define(테스트) | `E2E_STUDENT_EMAIL/PW`, `E2E_MENTOR_EMAIL/PW`, `E2E_ADMIN_EMAIL/PW`, `E2E_COMMENT_TAG` | '' | `integration_test/e2e_staging_test.dart:15-24` | e2e 자격증명 |
| 컴파일 상수 | `kInAppPaymentSteeringEnabled=false`, `kIndividualQuestionEnabled=true`, `kDevToolsEnabled=!kReleaseMode` | — | `commerce_policy.dart:10`, `iq_flags.dart:9`, `dev_flags.dart:5` | |
| .env | `SUPABASE_URL`(기본 `http://127.0.0.1:54321`), `SUPABASE_URL_LAN`, `SUPABASE_ANON_KEY`, `SENTRY_DSN`, `SENTRY_ENVIRONMENT`(기본 `staging`) | — | `.env.example`, `core/config/app_config.dart:16-21`, `crash_reporting.dart:35-37` | `.env` 는 pubspec 에셋(`pubspec.yaml:75`)이라 없으면 analyze/test 실패 |

- `AppConfig.supabaseUrl` 플랫폼 분기(`app_config.dart:27-39`): URL 에 `supabase.co` 포함(원격)이면 그대로; web 그대로; Android 는 `SUPABASE_URL_LAN` 우선, 없으면 `127.0.0.1→10.0.2.2` 치환; iOS 는 LAN 지정 시 LAN. `hasCredentials = url∧anonKey 비어있지 않음`(`:42-43`).
- 릴리즈 빌드는 dart-define 을 **주입하지 않는 것**이 계약(`HANDOFF.md:117-135`, 서명 워크플로 `android-signed-release-candidate.yml:280-287`, 계약 테스트 `:285-295`).
- `AppConstants.appVersion='1.0.0'` 은 표시 전용 하드코딩(TODO: package_info, `app_constants.dart:18-20`); `pubspec.yaml:4` `version: 1.0.0+19` 는 계약 테스트로 고정(`ios_release_config_contract_test.dart:25,360-364`).

---

## §7 테스트·CI 규율

### 7-1. `outbound_api_manifest_test.dart` — 서버 표면 잠금 (`test/contracts/outbound_api_manifest_test.dart`)

- 동작: `lib/**/*.dart` 전량을 읽어 라인 주석 제거(`://` 는 URL 로 보존, `:151-158`) 후 정규식으로 추출한 집합이 상수 집합과 **정확히 같아야** 통과(`expect(found, kExpectedRpcNames)` 등).
- 고정 집합:
  - RPC 리터럴 32개(`:15-59`): 계정 5(`account_deletion_cancel_self`, `account_deletion_request_self_v2`, `account_deletion_request_self_consented_v2`, `account_deletion_status_self`, `account_deletion_write_blocked`), 프로필 1(`user_profile_update_self`), 질문방 9(`ensure_free_question_room`, `qna_append_message`, `qna_confirm_thread`, `qna_create_free_question_thread`, `qna_create_question_thread`, `qna_register_attachment`, `weekly_question_usage_self`, `weekly_question_usage_self_batch`, `get_mentor_student_nicknames`), 멘토 1(`get_mentor_avg_response_hours`), IQ 7(`add_individual_question_attachment`, `claim_individual_question_as_mentor`, `create_individual_question_as_student`, `iq_append_message`, `list_open_individual_questions_for_mentor`, `refund_individual_question`, `release_individual_question`), 커뮤니티 5(`my_blocked_users`, `community_comment_soft_delete_self`, `community_post_soft_delete`, `community_post_view_record_v2`, `shortform_view_record_v2`), 알림 3(`mark_all_notifications_read`, `mark_notification_read`, `notification_unread_count_self`), 버전 1(`get_mobile_app_version_policy`).
  - 식별자 경유 RPC `{fn, kBoardPostCreateFunction='community_post_create', kBoardPostUpdateFunction='community_post_update'}`(`:63-67,199-215`).
  - 스키마 `{api_app_v1, api_web_v1}` + 식별자 `{kBoardPostCreateSchema, schema}`(`:69-74`).
  - 테이블/뷰 리터럴 24개(`:77-110`) + 식별자 `{_table(user_blocks·favorites), _reportsTable(content_reports), table(comments/community_comments/community_comments_v1/notification_settings)}`(`:113-117`).
  - Storage 버킷: 리터럴 0건 강제, 상수 식별자 6종·정의값 6종(`individual-question-attachments`, `question-room-attachments`, `connection-note-ink`, `scan-annotations`, `shortform-videos`, `community-post-images`)(`:120-137,237-287`).
  - 금지어 8(`mentor_directory_list_v2`, `mentor_profiles_for_directory_v2`, `mentor_user_public_v2`, `increment_shortform_post_view`, `account_deletion_request_self`, `account_deletion_request_self_consented`, `record_cash_topup`, `subscription_checkout_confirm`)(`:140-149`).
  - `from('users')` 체인에 `.update(`/`.insert(` 금지(`:298-311`), `from('community_posts')` 베이스 테이블 0건(`:313-319`), `'firebase'` 0건(`:321-326`).
- **갱신 절차**: 새 RPC/테이블/버킷을 쓰면 같은 PR 에서 이 파일의 해당 `const Set` 에 이름을 추가(삭제 시 제거)하고, 버킷은 반드시 상수 경유·`='bucket-name'` 정의 형태로 둔다. `supabase/SCHEMA_SOURCE_OF_TRUTH.md:30-31` 도 "신규 RPC/테이블 추가 시 이 매니페스트 갱신이 강제된다"고 명시.

### 7-2. 기타 contract 테스트가 강제하는 것

- `iq_create_boundary_test.dart`: `iq_create_screen.dart` import 0·생성자 호출 0·라우터/딥링크에 `IqCreate` 0 + CTA 는 웹 브릿지 호출(`:24-83,151-227`).
- `s3e_doc_contract_test.dart`: `docs/S3E_QUESTION_ROOM_SAFETY_CONTRACT.md` 의 현행 절 플래그·신고 target 어휘(`board_comment`, `shortform_post`, `community_comment`, `community_post`) 고정.
- `android_signed_workflow_contract_test.dart`: 서명 워크플로 YAML 구조 검증(dispatch 단독, 입력 2종 required/default false, `SOURCE_SHA` 40자 상수, 외부 action 4개 SHA 핀, secret 유출 문자열 금지, upload-artifact 1개·retention 3, cleanup 마지막·always, dart-define 주입 금지, 테스트 수 footer 파싱 등).
- `ios_release_config_contract_test.dart`: Info.plist(표시명·`ITSAppUsesNonExemptEncryption=false`·`LSApplicationQueriesSchemes={https}`·ATS 로컬만·권한 문구 3종), PrivacyInfo(수집 유형 5종 정확 집합·목적 AppFunctionality 만·required-reason 없음), pbxproj(번들 ID `com.ssambership.app`·타깃 13.0), Podfile, pubspec 버전 핀, 비밀 파일 미커밋.
- `xcode_cloud_bootstrap_contract_test.dart`: `ios/ci_scripts/ci_post_clone.sh` 실행권한·Flutter 3.44.6 핀·fail-closed .env·dart-define 금지·ephemeral 미추적.
- `test/app/build_version_test.dart`, `test/shared/conversation_ui_layering_test.dart`, `test/tool/validate_release_env_test.dart`.

### 7-3. 테스트에서 Supabase 를 대체하는 방식

- `SupabaseInit` 은 테스트에서 초기화되지 않으므로 `clientOrNull==null` → 레포는 `AppError` 를 던지거나 빈 결과를 돌려주고, 화면은 에러/빈 상태로 정착(`test/screens/home_shell_test.dart:10,34-35`). `AuthService` 싱글턴은 `tearDown` 에서 `signOut()` 으로 원복(`:38-42`).
- 손코딩 fake(mock 프레임워크 금지 관례): `FakeCommunityRead extends CommunityReadRepository`, `FakeCommunityWrite`, `RecordingCommentsGateway extends CommentsGateway`(호출 기록 + 응답 주입, `_Unset` 센티넬로 "미지정 vs 명시적 null" 구분)(`test/community/fakes.dart:8-370`); `FakeVersionPolicyPort`, `FakeGatePassCache`(`test/version_gate/version_gate_fakes.dart`); `_FakeBackend implements ProfileEditBackend`(`test/mypage/profile_edit_repository_test.dart:17-41`); `_FakeGateway implements AccountStatusGateway`(`test/auth/account_status_test.dart:6-40`).
- 순수 로직 진입점을 `@visibleForTesting static` 으로 분리해 단위 검증: `AuthService.computeAccess/computeRecoverableBlock/shouldRetainLastGoodProfile`, `EntryGuard.redirect`, `decide()`, `resolveNotificationDeepLink`, `assembleNotificationsPage`, `parseBoardPostCreateEnvelope`, `messageCursorBeforeFilter` 등.
- e2e: `integration_test/e2e_staging_test.dart` — 실 staging DB, 웹 렌더러+chromedriver, 쓰기는 댓글 1건·알림 설정 토글만(`:7-14`).

### 7-4. CI 워크플로 게이트

- `flutter-ci.yml`(master push/PR/dispatch): Java 17, Flutter **3.44.6**, `cp .env.example .env`, `flutter analyze` 출력 파싱으로 error/warning 0 게이트(info 비차단, `:56-69`), `flutter test`, `flutter build appbundle --release` 는 게이트 아님(`ORG_GRADLE_PROJECT_allowInsecureSigning=true`, `:79-90`), 로그를 `ci-logs` 브랜치로 force-push(`:102-121`), 최종 게이트 = analyze ∧ test(`:123-127`).
- `android-signed-release-candidate.yml`(dispatch 전용, Environment `android-release-candidate` 승인): `SOURCE_SHA` 고정 체크아웃·PR head 이동 검사 → analyze/test(**1,508건 정확 일치**) → 운영 `.env` 생성 + `dart run tool/validate_release_env.dart` → keystore 복원 → `flutter build appbundle --release` → jarsigner/인증서 fingerprint 대조 → bundletool validate + manifest(`com.ssambership.edu`, versionCode 19, minSdk 24, targetSdk 36) → AAB 내장 `.env` 검증(운영 URL 정확 일치·localhost 0) → artifact(3일) → cleanup.
- `tool/validate_release_env.dart`: `SENTRY_DSN` 존재, `SENTRY_ENVIRONMENT=='production'`, `SUPABASE_URL` 이 `https://lbeqxarxothkmzqvpudy.supabase.co` 와 문자열 정확 일치(단일 trailing slash 만 정규화), `SUPABASE_ANON_KEY` 존재 — YES/NO 판정만 출력(`:8-18,70-89`).
- DB 스키마 정본은 **웹 저장소 migration pack**, 앱 저장소에 SQL 없음(`supabase/SCHEMA_SOURCE_OF_TRUTH.md:3-38`).

---

## §8 확장 시 지켜야 할 규칙·지뢰

### 8-1. HANDOFF §5 명시 지뢰 (`HANDOFF.md:186-194`)

1. `color_tokens.dart` 통째 교체 금지(역할 구조 유지). 2. 미확정 가격·URL 하드코딩(날조) 금지. 3. 앱 안에 결제/구매/가격입력 화면 금지 — 웹 브릿지만. 4. 메시지·첨부는 append 전용(수정/삭제 기능·컬럼 없음). 5. service_role 키를 앱에 넣지 말 것(anon + RLS). 6. 웹 저장소 구조를 앱에서 복제/침범 금지(DB 만 공유).
- 2-B 재사용 원칙(`HANDOFF.md:94-97`): `lib/core/ink/` API 시그니처 변경 금지, `InkToolbar` 옵션 추가만, `SupabaseAttachmentUploader` 재구현 금지.

### 8-2. 코드에서 확인한 규칙·지뢰

- **서버 표면 매니페스트**: 새 RPC/테이블/뷰/버킷은 `outbound_api_manifest_test.dart` 갱신 없이는 CI 실패(§7-1). 버킷은 리터럴 금지·상수 경유.
- **users 테이블 직접 UPDATE/INSERT 금지** — 프로필 변경은 `api_app_v1.user_profile_update_self` 단일 경로(`profile_edit_repository.dart:6-10`); `community_posts` 베이스 테이블 접근 0(뷰/RPC 단일 경로, `board_post_create_gateway.dart:7-13`); `question_threads/question_messages` 직접 INSERT/UPDATE 금지, `mentor_student_rooms` INSERT 정책 없음(`question_room_write_repository.dart:41-45`, `room.dart:7`).
- **api_app_v1 RPC 는 `.schema('api_app_v1')` 필수**(생략 시 PGRST202).
- **봉투 strict**: `ok==true && contract_version==1` 아니면 실패(성공 위장 금지); 실패 봉투 `{ok:false,code}` 를 예외로 오인하지 말 것(`account_deletion_repository.dart:28-36`).
- **과목 코드**: DB 전송값은 반드시 `subjectCodeForDb()` 통과(정본 밖 값은 서버가 조용히 NULL, `subject_labels.dart:107-113`); `teaching_subjects` 는 코드·한글 라벨·레거시 혼재(`:3-8`).
- **`users.status` 는 자유 텍스트** → `lower()` 비교, `suspended_until` 존재(`account_status.dart:5-9`). `account_deletion_jobs` 직접 SELECT 403(`:127-129`).
- **fail-closed 원칙**: 계정 상태·역할 조회 실패는 full 로 통과 금지(`auth_service.dart:81-86`); 탈퇴 배너·취소 가능 판정은 서버 `can_cancel` 만, 로컬 시계·로컬 캐시 금지(`deletion_notice_controller.dart:9-15`); 알림 배지는 서버 개수만(`notification_badge_controller.dart:5-6`).
- **역할별 파라미터 계약**: 멘토는 `p_grade_level` 을 아예 보내지 않음(보내면 `GRADE_LEVEL_NOT_ALLOWED`, `profile_edit_repository.dart:18-21`); 탈퇴 v2 RPC 는 파라미터 없음(`p_cancelable_minutes/p_dry_run` 보내면 PGRST202, `account_deletion_repository.dart:12-16,198-204`).
- **원문 비노출**: PostgrestException/StorageException 원문·테이블·컬럼·정책명·UUID 를 화면에 내지 않는다(`shared/errors/friendly_error.dart:5-9`); 서명 URL·토큰 로그 금지.
- **동시성 관례**: 세대 토큰으로 늦은 응답 폐기(`CommunityPaginator`, `MyPageScreen`, `MentorDetailScreen`, `DeletionNoticeController`, `NotificationBadgeController`), `mounted` 가드, single-flight(`AuthService._loadProfile`, `DeletionNoticeController.refresh`, `UserBlocksRepository`), id dedup(`ThreadMessagesController`).
- **Realtime 은 보조**: publication 미포함 가능성을 전제로 재조회 폴백 유지(`thread_realtime.dart:25-28`); 채널 dispose 필수(계정 전환 시 uid 채널 재구독, `notifications_realtime.dart:32-33`).
- **IndexedStack 상주** → 교차 화면 갱신은 `DataRefreshBus` + `ResumeVisibilityGate` 로만(전역 폴링 금지, `data_refresh_bus.dart:5-9`).
- **WebView 위생**: 로그아웃 전·계정 전환·작성 화면 여닫이에 `WebSessionHygiene.clear()`; 토큰은 POST body 로만(`shortform_compose_bridge.dart:11-12`).
- **iOS 계약 테스트**: 새 데이터 수집 표면(예: 회원가입 실명·전화·학생증)은 `PrivacyInfo.xcprivacy` + `kExpectedCollectedDataTypes` 를 함께 갱신해야 통과(`ios_release_config_contract_test.dart:41-62`); 현재 `NSPrivacyCollectedDataTypeName`·`PaymentInfo` 는 금지 집합. 새 URL 스킴은 `LSApplicationQueriesSchemes` allowlist 갱신.
- **buildNumber/버전**: `pubspec version` 은 계약 테스트로 고정 — 상향 시 `ios_release_config_contract_test.dart:25`, `test/app/build_version_test.dart`, 서명 워크플로 기대값을 함께 수정.
- **DB 변경은 웹 저장소 pack 에만**(`SCHEMA_SOURCE_OF_TRUTH.md:33-38`); 앱 저장소에 SQL 을 두지 않는다.
- `connection_notes` 에 (room, author) UNIQUE 가 없어 중복 행 내성 코드가 존재(`question_room_write_repository.dart:189-233`).
- **문서 구식 지뢰**(코드가 정본): `HANDOFF.md` §3-1 도메인/경로, §3-4 FCM, §6 "250개 테스트", §7 `features/web_bridge`; `README.md` "S0 스캐폴드"·폴더 구조; `docs/APP_V16_MIN_VERSION_SERVER_REQUIREMENT.md` WAITING 상태·RPC 명.

---

## §9 확장 포인트 평가

### 9-1. 새 기능 도메인 추가 시 계층별 추가 위치(현 구조 기준)

공통 절차(모든 도메인):
1. `lib/features/<domain>/data/` — `<domain>_models.dart`(fromMap + enum fromCode/unknown), `<domain>_repository.dart`(read/write 분리, `_client`/`_uid` 정형, `XxxBackend`/`XxxGateway` seam), `<domain>_error_mapper.dart`(코드→한글, `map<Domain>Error`), 필요 시 `<domain>_realtime.dart`(Port + Supabase 구현), 파일이면 `<domain>_url_resolver.dart`(포트+TTL 캐시).
2. `lib/features/<domain>/ui/` — 화면(push 라우트, 생성자 인자 + `xxxOverride` seam), `widgets/`.
3. 진입: (a) 탭이면 `AppTab`·`HomeShell._pages/_icons`·`AppConstants.bottomTabLabels`·`EntryGuard.guestAllowedTabs` 5곳, (b) push 면 기존 화면(마이페이지 섹션·멘토 상세 CTA 등)에 진입 버튼.
4. 알림 연동: `NotificationEventType`(18종 enum) 추가·`notificationKindOf`·`notificationDestinationOf`(exhaustive switch 3곳, `notification_types.dart:96-172`) → `NotificationDestination` 신설 시 `resolveNotificationDeepLink`·`notificationRouteFallbackTab`(`notification_deep_link_controller.dart:98-155`)·`NotificationTargetOpener.open`(`notification_target_opener.dart:36-56`)·`AppNotification` 분류 갱신.
5. `DataRefreshBus` 에 도메인 세대 추가(교차 화면 무효화 필요 시).
6. `test/contracts/outbound_api_manifest_test.dart` 의 RPC/테이블/버킷 집합 갱신 + `test/<domain>/fakes.dart` 손코딩 fake + 위젯/로직 테스트.
7. iOS: 새 권한·수집 데이터·스킴이면 `Info.plist`/`PrivacyInfo.xcprivacy` + 계약 테스트 갱신.

도메인별 구체 포인트:

- **맞춤의뢰(CR)** — 현재 "흔적 없이 제외"(`README.md:8`). 존재하는 흔적: `NotificationKind.customRequest`·`NotificationEventType.newOrderMessage/newApplication`·`NotificationDestination.stay`(`notification_types.dart:27-28,73,165-168`), `kGatedNotificationTypeCodes`(`:15-18`), `NotificationGroups.labels['order']`(`notification_settings_repository.dart:32-38`). 추가 시: `features/custom_request/{data,ui}` 신설; `custom_request_orders` 등 테이블/RPC 는 매니페스트에 전무 → 전부 신규 등록; 게이트 코드 집합 비우기; `NotificationDestination.customRequestTab|Detail` 추가 + 위 exhaustive switch 4곳; 납품 파일 버킷(`custom-order-deliverables`, `custom-request-post-attachments` — 웹 CLAUDE.md 정본) 상수 등록 + 서명 URL 리졸버 5벌째; 금지어 필터(`["대필","대신 써줘",…]`, 웹 CLAUDE.md)는 서버 RPC 검증을 전제로 앱은 사전 안내만.
- **멘토 프로필 편집** — 현재 웹 브릿지(`openProfileEditWeb → /mentor/profile`, `web_bridge_config.dart:28-29`) + 앱 내 `ProfileEditRepository` 는 `user_profile_update_self(p_nickname, p_grade_level)` 만(`profile_edit_repository.dart:12-16`). `mentor_profiles` 는 앱에서 `teaching_subjects` 읽기만(`question_room_read_repository.dart:118-136`, 매니페스트 테이블 포함). 추가 시: 서버에 `api_app_v1.mentor_profile_update_self(...)` 류 RPC 신설(확인 필요 — 앱·웹 어디에도 앱용 멘토 프로필 쓰기 RPC 없음), `ProfileEditBackend` 와 같은 `rpc(fn, params)` seam 재사용, 과목은 `subjectCodeForDb` 정본 코드 배열로 전송, 매니페스트 갱신, 마이페이지 `settings_section`/`profile_section` 진입 추가, `WebBridge.openProfileEdit` 폐기 여부 결정.
- **회원가입** — `AuthService` 에 `signUp` 없음(`auth_service.dart:304-320` 로그인만), 로그인 화면은 "회원가입은 웹에서"(`login_screen.dart:151`). 추가 시: `AuthService.signUp(email,password,…)` + `users` 행 생성은 서버 트리거/RPC 의존(role 없으면 `_parseRole → guest → blocked`, `auth_service.dart:107-108,273-286`); `AccessState` 에 `onboarding`/`profileIncomplete` 류 상태와 `EntryGuard` 경로 추가 필요(현 5종으로는 표현 불가); 학교 인증 업로드는 버킷 `student-id-images`(웹 정본, 앱 매니페스트 미등록) + 서명 URL 리졸버; iOS `PrivacyInfo` 수집 유형(`Name`, 학교 등) 계약 테스트 갱신; `users` 직접 INSERT 는 매니페스트가 금지 → RPC 경로.
- **리뷰 작성** — 앱에 리뷰 쓰기 없음. 멘토용 웹 열람만(`openReviewsWeb → /mentor/reviews`). 자격 판정("동일 멘토 2회 연속 결제 성공 후")은 "웹·서버 소관, 앱에 두지 않는다"(`core/entitlement/subscription_status.dart:10-11`), 서버 가드 실정의 언급(`docs/APP_V16_SERVER_CONTRACT_SNAPSHOT.md:265`). 추가 시: 리뷰 테이블/RPC(`reviews` 등 — 매니페스트 미등록, 서버 계약 확인 필요) + `features/reviews/` 또는 `mentors/data/review_repository.dart`, 멘토 상세에 진입, 자격 조회는 서버 RPC 응답만 사용(로컬 계산 금지).
- **결제 제외 유지** — `kInAppPaymentSteeringEnabled`, `Entitlement.inAppPurchaseEnabled`, `WebBridgeConfig` 에 구매 경로 부재, `ShortformComposeBridge` allowlist, 금지어 `record_cash_topup`/`subscription_checkout_confirm` 로 이미 다층 방어.

### 9-2. 현 구조의 한계와 재구축 시 유지/교체 후보

**한계(요약)**
- 고정 5탭 셸 + 정수 탭 인덱스 5곳 결합, 역할별 네비 구성 불가(§4-4-2).
- 명명 라우트 4개, 상세는 모델 인자 push → 딥링크/복원/웹 링크 불가, 목적지별 opener 증식(§4-4-1).
- `AccessState` 5종·`AppRole` 4종 — 가입/온보딩/인증 대기 상태 부재(§4-4-4).
- 역할 분기가 화면·레포 내부 switch 로 산재(§2-6).
- 상태관리 부재: 전역 싱글턴 + ChangeNotifier + FutureBuilder + `xxxOverride` seam 30여 종; 화면 간 공유 상태(구독 요약·차단 목록·지갑)는 각 화면이 재조회(`DataRefreshBus` 는 값 없는 신호).
- 동일 패턴 중복: `model_parse.dart` 2벌, 서명 URL 리졸버 4벌, 실시간 포트 3벌, 에러 매퍼 5벌(코드 표는 같은 문장을 반복).
- static 캐시(`UserBlocksRepository`), 프로세스 전역 리졸버 — 테스트 격리·계정 전환 안전을 uid 키로 우회.
- import 방향 린트 없음, 역방향 의존 실재(§1-3).
- 문서 다수 구식(§8-2 말미).

**유지 후보(그대로 이식 가치가 높음)**
- `core/auth`: `AccountStatusReader.resolve` 판정·`AccountStatusKind`·`computeAccess` fail-closed 규칙과 RPC 계약(`account_deletion_write_blocked`, `account_deletion_status_self`), `DeletionNoticeController` 규약.
- RPC 봉투 strict 파싱·에러 매퍼(코드→한글 문구 정본), `AppError`/`friendlyError` 원문 비노출 규약.
- 서명 URL 리졸버 계약(TTL·마진·single-flight·uid 키·상태 타입) — 단, 1개 제네릭으로 통합.
- Realtime 포트 계약(postgres_changes + 재조회 폴백 + 재연결 콜백), 메시지 dedup/정렬 컨트롤러, 키셋 커서(알림·메시지).
- Storage 업로드 파이프라인(경로 규약·RPC 등록·보상 삭제·23505 멱등 수용), `core/scan`·`core/ink` 코어.
- `web_bridge`(URL 검증)·`ShortformComposeBridge`/웹 `app-session/bootstrap` 계약, `WebSessionHygiene`.
- 버전 게이트 전체, Sentry 부팅 계약, `commerce_policy`, `subject_labels` 정본 매핑.
- 테스트 규율: 손코딩 fake, `@visibleForTesting` 순수 함수, contract 테스트(특히 outbound manifest·iOS/Android 워크플로 계약), CI 워크플로 2종, `validate_release_env`.

**교체·재설계 후보**
- 라우팅: `GoRouter` 4라우트 + 명령형 push → 타입드 라우트 테이블(StatefulShellRoute/ShellRoute, id 파라미터 상세 라우트가 내부에서 조회), `EntryGuard` 를 경로 패턴·역할·AccessState 매트릭스로 재정의, `TabNavigator` int 채널 폐기.
- `HomeShell`: 역할별 탭 구성(학생/멘토 네비 차이)을 데이터로, 게스트 허용을 라우트 메타로.
- `AccessState`/`AppRole`: 가입·온보딩·프로필 미완성·학교 인증 상태 추가, 역할 분기를 라우트 가드로 상향.
- 상태관리/DI: 전역 싱글턴·`xxxOverride` seam → 스코프형 주입 컨테이너(생성자 주입 유지 가능)로 통일; 공유 도메인 상태(구독 요약·차단·지갑)는 캐시 소유자를 둠.
- 중복 제거: `model_parse` 1벌, 리졸버 제네릭 1벌, 실시간 포트 제네릭 1벌, 에러 매퍼 공통 코드 테이블 + 도메인 확장.
- `AppConstants.appVersion` 하드코딩 → package_info; 문서(README/HANDOFF) 정본화; import 방향 린트(또는 계층 계약 테스트) 도입.
- 알림 유형/목적지 exhaustive switch 4곳 → 유형→(kind, destination, opener) 단일 테이블.
