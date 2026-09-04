# Phase 2 — 플랫폼 공통 아키텍처 · 새 저장소 부트스트랩 전략

- 대상: 기존 앱 `/home/user/ssambership-app`(HEAD `635ae73`, `pubspec.yaml:4` `version: 1.0.0+19`) → "웹 수준(결제 제외)" 신규 앱. 웹 `/home/user/ssambership_web` 은 DB 정본·WebView 표면 제공자.
- 범위: 프론트 구조·백엔드·DB·CI 만. UI/UX·디자인은 다루지 않는다.
- 표기: `경로:행`. 웹 저장소는 `web:` 접두. 코드로 확정하지 못한 것은 **(확인 필요)**. Phase 1 리포트(`review/phase1/*.md`)에서 인용한 사실은 `[P1-arch §n]` 등으로 표시하고, 결정적 주장은 코드로 재확인했다.
- 실측 요약(이번 세션 grep): `lib/` 에서 `Navigator.of(context).push` 46곳(26파일) · `context.go(` 7곳 · `xxxOverride` 생성자 seam 30종(`loaderOverride` 23회 최다) · `AuthService.instance` 참조 19파일 · `currentRole` 비교 14곳(12파일) · `static final … instance` 싱글턴 5개(AuthService·DeepLinkService·DeletionNoticeController·NotificationBadgeController·VersionGateController) · 테스트 파일 173개 / `test(`·`testWidgets(` 약 1,470건(CI 기대값 **1,508** — `.github/workflows/android-signed-release-candidate.yml:65`). HANDOFF 의 "250개 테스트"(`HANDOFF.md:199`)는 구식이다.

---

## 1. 라우팅·셸 재설계

### 1-1. 현행(근거)

- 명명 라우트 4개 + dev 2개: `/splash /login /home /blocked` (+`/dev/gallery /dev/s3` — `kDevToolsEnabled` 일 때만) — `lib/app/router.dart:25-53`, 상수 `lib/app/entry_guard.dart:14-19`. `GoRouter(initialLocation: '/splash', refreshListenable: AuthService.instance, redirect: EntryGuard.redirect(...))` — `router.dart:18-24`. go_router 는 `14.8.1`(`pubspec.lock:314-320`).
- `EntryGuard.redirect` 는 AccessState 5종 × 고정 경로 매트릭스. `full` 은 `/home` 이외 어디든 `/home` 으로 되돌린다(`entry_guard.dart:47-48`), `guest` 는 `/home`·`/login` 만(`:43-46`). `/dev/*` 는 가드 제외(`:36`). 전수표 테스트 `test/screens/entry_guard_redirect_test.dart:8-56`.
- 5탭 셸 `HomeShell`: `_pages`(5 const 위젯, `home_shell.dart:47-53`)·`_icons`(`:56-62`)·`AppConstants.bottomTabLabels`·`AppTab` 정수(`app_tabs.dart:10-14`)·`EntryGuard.guestAllowedTabs={1,2}`(`entry_guard.dart:25`) 다섯 곳이 **인덱스로 암묵 결합**. `IndexedStack` + 방문 탭만 빌드(`_built`, `:45,69,111,161-165`), `ScreenVisibility(visible: i==_index)`(`:162-165`).
- 탭 전환 채널 `TabNavigator.request: ValueNotifier<int>`(`app_tabs.dart:26-33`), 마이페이지는 가상 인덱스 100 → push 로 변환(`:19`, `home_shell.dart:89-98,120-133`). 마이페이지 내부의 탭 이동은 **pop 반환값(int)** 으로 셸에 전달(`:251-268`).
- 게스트 가드는 셸 안에서 `context.go('/login?notice=login_required')`(`:100-104,121-124`).
- 상세 화면은 전부 로드된 모델을 생성자 인자로 받는 명령형 push(46곳). 알림 상세 이동은 sealed `NotificationDeepLinkRoute` 6종(`lib/core/deeplink/notification_deep_link_controller.dart:8-17,54-60` — UUID 검증 후에만 상세) → `NotificationTargetOpener.open` 이 역할별 사전 조회 후 push(`lib/features/notifications/ui/notification_target_opener.dart:36-56`; 방 열기 `_openRoom` `:62-…`). `NotificationDestination` 주석 자체가 "현 라우터는 탭 단위 이동만 지원하므로 목적지도 탭 수준으로 고정"(`lib/features/notifications/data/notification_types.dart:125-135`).
- 프로덕션 딥링크 생산자 0: `DeepLinkService.initialize()` 는 payload 스트림을 주지 않으면 구독 0(`lib/core/deeplink/deep_link_service.dart:25-31`). OS 푸시 없음(App-F0, `lib/core/push/push_ports.dart:1-10`). 앱 URL 스킴·App Links 없음 — Android 매니페스트의 `https` VIEW 는 url_launcher 패키지 가시성용 `<queries>` 다(`android/app/src/main/AndroidManifest.xml:49-54`), iOS `LSApplicationQueriesSchemes` 는 `https` 단독(`test/contracts/ios_release_config_contract_test.dart:128-152`).
- `OnboardingScreen`(`lib/features/onboarding/onboarding_screen.dart`)은 참조 0 (grep 실측).
- 역방향 의존: `core/deeplink/deep_link_service.dart:3` → `app/app_tabs.dart`, `core/deeplink/notification_deep_link_controller.dart:3-4` → `app/`·`features/notifications` [P1-arch §1-3].
- 웹 네비 잠금값: 학생 7·멘토 4(`web:CLAUDE.md` "절대 잠금값"). 웹 로그인 후 홈은 역할별(`web:lib/auth/getPostLoginPath.ts:26-31`: student `/mypage`, mentor `/mentor/mypage`, admin `/admin`).

### 1-2. 문제

1. **주소 없는 상세**: 화면이 3~4배(맞춤의뢰 목록/상세/작성/지원/주문, 멘토 콘솔 대시보드/프로필/요금/정산계좌/리뷰, 계정/온보딩, 지원)로 늘면 목적지마다 `_openRoom` 류 사전 조회 어댑터가 증식한다. 푸시 재도입 시 `PushPayload{type, room_id, thread_id, question_id}`(`lib/core/push/push_payload.dart`)를 화면으로 잇는 경로가 opener 하나뿐.
2. **셸 5곳 동시 수정** + 역할별 탭 구성 표현 불가 → 같은 5탭 안에서 화면 내부 `currentRole` switch 로 갈림(`lib/features/question_room/question_room_screen.dart:41-54`, `individual_question_tab_screen.dart:30-34`).
3. **`full → /home` 고정 규칙**이 명명 상세 라우트·복원·웹뷰 복귀를 원천 차단(`entry_guard.dart:47-48`).
4. **정수 채널**: `TabNavigator` 페이로드가 int 하나. `myPage=100` 가상 목적지·pop-int 핸드오프는 라우팅 부재의 우회.
5. **IndexedStack 상주**: 탭이 늘면 상주 Realtime 채널·리스너 팬아웃이 커진다(알림 채널은 알림 탭 생존 동안 유지 — [P1-arch §4-4-6]).
6. `/dev/*` 가드 제외가 경로 접두 문자열 비교라 라우트 메타 부재의 징후.

### 1-3. 대안 비교

| 안 | 내용 | 장점 | 단점 |
|---|---|---|---|
| A. 현행 유지 + opener 확장 | 4라우트·5탭 유지, 상세는 push, opener 에 목적지 추가 | 이식 비용 0 | 문제 1~5 그대로 확대. 멘토 콘솔·CR 은 탭 5개에 못 담김 |
| B. 평면 명명 라우트 전면 전환 | 모든 화면을 `GoRoute(path)` 로, 탭 없이 스택만 | 딥링크 단순 | 탭 상태 유지·배지·복귀 재조회 계약(`ScreenVisibility`) 재작성 필요 |
| **C. StatefulShellRoute + 역할별 브랜치 테이블 + id 파라미터 상세 라우트** | `StatefulShellRoute.indexedStack` 브랜치를 **역할별 탭 스펙 테이블**에서 생성, 상세는 `/…/:id` 로 등록해 화면 내부에서 조회, `redirect` 는 라우트 메타(역할·게스트·온보딩 요구) 기반 | 딥링크·복원·역할별 네비를 한 구조로, IndexedStack 상태 유지 계약 승계 | `home_shell_test.dart` 류 7파일 재작성, opener 폐기 |
| D. 역할별 라우터 인스턴스 2개 | 학생/멘토 각각 GoRouter | 분기 명확 | 로그인/로그아웃 시 라우터 교체·공통 화면 중복 |

### 1-4. 권고 (C)

1. **라우트 테이블을 데이터로**: `lib/app/routes/app_routes.dart` 에 경로 상수 + 빌더 + 메타(`roles`, `guestAllowed`, `requiresOnboardingDone`, `tab`) 를 갖는 `AppRouteSpec` 목록. `EntryGuard.redirect(access, location)` 는 유지하되 입력을 "경로 문자열 매칭" 에서 "매칭된 spec 의 메타" 로 바꾼다(순수 함수·전수표 테스트 승계). 개발 라우트는 `startsWith('/dev/')` 대신 `meta.devOnly`.
2. **셸**: `StatefulShellRoute.indexedStack`(go_router 14.x 제공) 브랜치를 `RoleTabSpec` 테이블(학생: 웹 잠금 7 네비 중 결제·충전 제외 집합, 멘토: 질문방·맞춤의뢰·커뮤니티 — 캐시충전 제외)에서 생성. `AppTab` 정수·`bottomTabLabels`·`_icons`·`guestAllowedTabs` 5곳 결합을 spec 1곳으로 흡수. `ScreenVisibility`/`ResumeVisibilityGate`(`lib/shared/widgets/screen_visibility.dart:11-68`)는 브랜치 활성 여부(`navigationShell.currentIndex`)로 그대로 공급.
3. **상세 라우트는 id 파라미터**: `/question-room/:roomId`, `/question-room/:roomId/threads/:threadId`, `/iq/:questionId`, `/community/board/:postId`, `/community/shortform/:id`, `/mentors/:mentorId`, `/custom-request/:postId`, `/custom-request/orders/:orderId` … 화면이 id 로 자체 조회(RLS 정본). 기존 모델-인자 화면은 `XxxScreen.fromId(id)` 진입 생성자를 추가해 점진 이식(모델 인자 생성자는 유지 → 46곳 push 를 한 번에 안 바꿔도 컴파일 유지).
4. **딥링크 경로 스킴**: 웹 라우트(`web:CLAUDE.md` 라우트 구조)와 **경로 문자열을 맞춘다**(`/mentors/[mentorId]`, `/question-room/[roomId]`, `/community/board/[id]`, `/community/shortform/[id]`). 이렇게 두면 (a) 푸시 `type+ids → 경로` 변환이 `resolveNotificationDeepLink` 결과를 `GoRouter.go(path)` 로 바꾸는 한 줄이 되고, (b) 향후 App Links/Universal Links(웹 도메인) 도입 시 `assetlinks.json`·AASA 만 웹에 두면 된다(웹 선행 과제·오너 결정 §9-3). 멘토 전용 경로는 웹처럼 `/mentor/...` 접두.
5. **TabNavigator 계약 흡수**: `TabNavigator.go(int)` 를 `AppNavigator.go(AppRouteTarget)`(sealed: `Tab(spec)`, `Path(String)`) 로 교체하고, `NotificationDeepLinkController(navigate:)` 콜백 타입만 바꾼다(순수 판정 로직·dedup·pending TTL 은 무변경 — `notification_deep_link_controller.dart`). `core → app` 역방향 import 는 콜백 주입으로 끊는다.
6. **게스트·온보딩 중간 상태**: 라우트 메타 `guestAllowed` 로 게스트 판정을 셸 밖(redirect)으로 올린다. `/onboarding/*`(본인인증 필요·보호자 동의·멘토 승인 대기·프로필 미완성) 은 `AccessState.onboarding` 에서만 도달 가능한 라우트 그룹으로 등록(§2 참조). `/login?notice=` 쿼리 계약은 유지.
7. **상주 팬아웃 억제**: 브랜치 lazy 빌드(현 `_built` 계약)는 `StatefulShellBranch` 가 기본 제공. Realtime 채널은 §5 의 공통 포트에서 "보이는 브랜치만 구독, 가려지면 해제·재조회" 규약을 넣어 탭 수 증가에 대비.

---

## 2. 세션·역할·상태

### 2-1. 현행(근거)

- `enum AppRole { student, mentor, admin, guest }`(`lib/core/auth/auth_service.dart:13`), `enum AccessState { loading, loggedOut, guest, full, blocked }`(`:22`).
- `computeAccess`(`:88-112`): bootstrapping→loading; signedIn 이면 `account.isRetryable || roleFetchFailed → blocked`(재시도 가능) → `!allowsAppUse → blocked` → `admin → blocked`(`:102-103`) → student|mentor → full → 그 외 blocked. 순수 정적 함수(`@visibleForTesting`).
- 프로필 로드: `users` 본인 행 1회 `select('role, nickname, full_name, status, suspended_until')`(`:221-225`) → `_parseRole`(`:275-286`) + `AccountStatusReader.resolve`(`:231-238`). N32 "마지막 정상 프로필 유지"(`:243-248,264-271`). single-flight(`:190-200`).
- `AccountStatusKind` 7종(`lib/core/auth/account_status.dart:14-37`), `allowsAppUse = active || deletionPending`(`:58-60`). 판정 `resolve`(`:226-312`)는 users 행 → `account_deletion_write_blocked` RPC → `account_deletion_status_self` RPC → status 문자열 순, 전부 fail-closed.
- 로그인 API 는 이메일+비밀번호만(`:303-320`), `signUp` 없음. `identity_verified_at` 참조 0(grep), `mentor_profiles.verification_status` 판정 0(앱은 `teaching_subjects` 만 읽음 — [P1-arch §9-1]).
- 역할 분기 산재(실측 14곳): `app/app.dart:26`(테마), `mentors/ui/mentor_detail_screen.dart:265`, `mentors/ui/widgets/free_question_entry_section.dart:58`, `community/ui/shortform/shortform_feed_view.dart:38`, `notifications/ui/notification_target_opener.dart:64`, `mypage/ui/profile_edit_screen.dart:39`, `mypage/data/mypage_repository.dart:41,59`, `individual_question/ui/iq_detail_screen.dart:839`, `individual_question/individual_question_tab_screen.dart:31`, `question_room/question_room_screen.dart:41`, `question_room/data/question_room_write_repository.dart:253`.
- 웹 온보딩·게이트: `IDENTITY_GATE_ENABLED` 서버 env(`web:lib/identity/identityGateFlag.ts:12-24`), 레이아웃 redirect `/onboarding/verify`(`web:app/(student)/layout.tsx:41,66,83,99`, 예외 `/account/delete` `:64-68`), 머니패스 403 `IDENTITY_REQUIRED: …` 선두 토큰 계약(`web:lib/identity/identityGate.ts:10-20`), **DB/RPC 게이트는 의도적으로 0**(`identityGate.ts:6-8`). 보호자 체인(`GUARDIAN_REQUIRED`) 은 [P1-account §3-2]. `users.identity_verified_at` 은 authenticated SELECT 가능 [P1-account §3-3].
- 웹 가입 직후 멘토 목적지는 `/mentor/profile/edit`(`web:lib/auth/getPostLoginPath.ts:22-24` 주석) — 승인 대기 상태의 존재. 승인 판정은 `mentor_profiles.verification_status`(디렉터리 뷰 `approved|verified|active` 만 노출 — [P1-db §1.3 V3]).
- 웹 앱 표면 게이트(`web:lib/appSession/appSurfaceAccountGate.ts:1-50`)는 status **allowlist**(미지 값 거부) — 앱 `resolve` 는 "banned/suspended 외 전부 active"(`account_status.dart:287-289`) 로 더 느슨하다.

### 2-2. 문제

1. AccessState 에 "로그인은 됐지만 아직 전체 이용 불가(온보딩 필요)" 가 없어 가입 직후·본인인증 필요·보호자 동의 필요·멘토 승인 대기·프로필 미완성이 표현 불가. role 불명(`users` 행 미생성 창)은 곧바로 `blocked`(`auth_service.dart:107-108`) — 가입 직후 트리거 지연이면 차단 화면이 뜬다.
2. 본인인증 게이트가 웹 서버 플래그에 종속이라, 앱이 `identity_verified_at` 로 자체 게이트를 걸면 **웹 플래그와 불일치**(웹 OFF·앱 ON 또는 반대) 가능. 앱 직접 RPC 경로(IQ 에스크로·`cra_insert` 등)는 게이트 밖 [P1-account §3-1].
3. 역할 분기가 화면·레포에 산재 → 멘토 콘솔(대시보드·프로필·요금·정산계좌·리뷰) 추가 시 각 화면 switch 증가. `MyPageRepository.load()` 가 역할로 조회 집합을 갈라(`mypage_repository.dart:41-64`) 데이터 계층까지 역할 의존.
4. `status` 판정 엄격도가 웹 앱 표면(allowlist)과 다름 → WebView 브릿지에서 `account_blocked` 로 튕기는데 앱은 full 인 불일치 가능.
5. 관리자 차단은 유지해야 하나(`computeAccess:102-103`, 웹 bootstrap `strictMentorRoleDecision` `web:app/api/app-session/bootstrap/route.ts:116-119`), 새 bootstrap target 이 학생을 허용해야 하므로 target 별 역할 게이트가 필요.

### 2-3. 대안 비교

| 안 | 내용 | 평가 |
|---|---|---|
| A. AccessState 5종 유지 + 화면 내부 분기 | 온보딩을 `full` 상태의 화면 안에서 처리 | 라우트 가드로 강제 못 함 → 미인증 사용자가 쓰기 화면에 도달. 비권고 |
| **B. AccessState 에 `onboarding` 1종 추가 + `OnboardingNeed` 집합** | `full` 진입 전 단계로 `onboarding(needs)` 를 두고 라우트 메타 `requiresOnboardingDone` 으로 차단 | 기존 5종·`computeAccess` 순서 보존, 단위 테스트 전수표 확장만 |
| C. 상태기계 전면 재설계 | 세션·계정·역할·온보딩을 별도 sealed 계층으로 | 표현력은 높으나 `computeAccess`·`resolve`·`BlockedScreen` 계약·테스트 이식 비용 큼 |

### 2-4. 권고 (B)

1. **`AccessState { loading, loggedOut, guest, onboarding, full, blocked }`** — `computeAccess` 판정 순서를 `… → admin → blocked → (student|mentor) → needs.isEmpty ? full : onboarding → 그 외 blocked` 로 확장. 순수 함수 유지, `entry_guard_redirect_test.dart` 전수표에 onboarding 행 추가.
2. **`OnboardingNeed` 집합**(`Set<OnboardingNeed>`): `profileRowMissing`(users 행 없음 — role 불명을 즉시 blocked 로 보내지 않고 **짧은 재시도 창** 후에만 blocked), `identityRequired`(`users.identity_verified_at == null` ∧ 서버 게이트 ON), `guardianRequired`(웹 `getIdentityOnboardingState` 의 `guardian_required` 와 동치 — 앱은 서버 판정을 읽는다, 나이 계산 로컬 금지), `mentorApprovalPending`(`mentor_profiles.verification_status ∉ {approved,verified,active}` — 컬럼 SELECT 권한 **(확인 필요)**), `mentorProfileIncomplete`(웹 가입 직후 `/mentor/profile/edit` 유도와 동치 — 판정 기준 컬럼 **(확인 필요)**). 각 need 는 **읽기 허용 라우트**를 갖는다(예: 멘토 승인 대기는 커뮤니티·멘토 찾기 열람 가능, 인박스 불가) — 라우트 메타 `allowedDuring: {need…}`.
3. **게이트 플래그의 서버 정본화**: 앱이 `IDENTITY_GATE_ENABLED` 를 알 수 없으므로, (a) `get_mobile_app_version_policy` 응답에 `identity_gate_enabled` 를 싣거나 (b) `get_mobile_app_config()` anon RPC 신설 중 하나를 웹 pack 에 선행(§9 결정). 서버 값 없으면 앱은 **게이트 OFF 가 아니라 "미확인 → 온보딩 유도 없음 + 쓰기 실패 시 `IDENTITY_REQUIRED` 매핑"** 으로 동작(웹 정책과 같은 방향의 안전 폴백).
4. **역할별 기능 등록 표(§1 라우트 메타와 동일 객체)**: `lib/app/feature_registry.dart` 의 `AppFeature{id, roles, guestAllowed, onboardingAllowed, tabSpec?, routes, notificationDestinations, refreshDomains}`. 화면 내부 `switch(currentRole)` 는 (a) 역할별 **별도 라우트**(학생 `/question-room` ↔ 멘토 `/mentor/inbox`)로 분리하고, (b) 남는 데이터 계층 분기(`mypage_repository.dart:41-64`, `question_room_write_repository.dart:253`)는 `AppRole` 을 **생성자/메서드 인자**로 받게 바꿔 `AuthService.instance` 직접 참조를 없앤다. 목표: `currentRole` 읽기는 `app/`(라우터·셸·테마) 3곳으로 수렴. 등록표는 계약 테스트로 "라우터의 모든 GoRoute 가 registry 에 있고 roles 가 비어 있지 않다" 를 강제.
5. **관리자 차단 유지**: `computeAccess` 의 `admin → blocked` 와 `BlockedScreen` 문구(`auth_service.dart:122-124`) 그대로. WebView bootstrap 은 target 별 허용 역할 표(`shortform_create: {mentor}`, `identity_onboarding: {student, mentor}`, …)로 확장하되 admin 은 어떤 target 도 불허(웹 선행 과제).
6. **status 판정 정합**: `AccountStatusReader.resolve` 의 "그 외 값 active" 를 웹 앱 표면 allowlist(`active` 또는 만료 `suspended`)에 맞춰 **`deleted`·미지 값 → 비복구 차단**으로 좁힌다(`users.status` 에 CHECK 4종 존재 — [P1-account §4-1]). `AccountStatusKind` 7종은 유지, `deleted` 분기에 `status='deleted'` 를 추가.
7. **가입**: `AuthService.signUp(email, password, metadata)` 추가 — 메타 키는 웹 `buildSignupUserMetadata`(`web:lib/auth/buildSignupUserMetadata.ts:29-53`) 와 동일(트리거가 `users`·`mentor_profiles`·동의 원장을 만든다 — [P1-account §2-3]). 가입 직후 `_loadProfile` 재시도(행 생성 지연 대비) → `profileRowMissing` need. 이메일 인증 ON/OFF 는 **(확인 필요)** — ON 이면 `emailUnconfirmed` need 추가.
8. **세션 계층 분리**: `AuthService` 를 `SessionController`(Supabase auth 이벤트·토큰) + `ProfileController`(users 행·계정상태·온보딩 need) + `AccessResolver`(순수) 로 나누되, 외부 게터(`access`, `currentRole`, `displayName`, `isGuest`, `blockedMessage`, `isRecoverableBlock`)는 파사드로 유지해 `login_screen`·`blocked_screen`·테스트 호환.

---

## 3. 상태관리·DI

### 3-1. 현행(근거)

- 상태관리·DI·mock 프레임워크 **없음**(`pubspec.yaml:10-62`). 규약 문장: "DI 프레임워크 없이 생성자 주입 + 프로덕션 기본값(instance) 패턴"(`lib/core/version_gate/version_gate_controller.dart:33-46`).
- 전역 싱글턴 5개(`static final … instance`: `auth_service.dart:32`, `deep_link_service.dart:20`, `deletion_notice_controller.dart:25`, `notification_badge_controller.dart`, `version_gate_controller.dart:46`) + static `ValueNotifier` 채널(`TabNavigator.request` `app_tabs.dart:30`, `DataRefreshBus.*Generation` `lib/core/refresh/data_refresh_bus.dart:14,30,39,49`) + static 캐시(`UserBlocksRepository` TTL 30s [P1-arch §3-9]).
- 화면 seam: `xxxOverride` 생성자 파라미터 30종(실측 — `loaderOverride` 23, `webBridgeOverride`·`currentUserIdOverride`·`createCtaOverride` 6, `controllerOverride`·`realtimeFactoryOverride`·`roleOverride`·`isMentorOverride` 등). 테스트에서 `Override:` 를 넘기는 파일 30개.
- 테스트 규율: 손코딩 Fake/Recording(`account_status.dart:109` "mocktail 금지", `comments_gateway.dart:10-12`), `@visibleForTesting static` 순수 함수(`auth_service.dart:87-88,139-140,266-267`, `EntryGuard.redirect`, `decide()`, `resolveNotificationDeepLink` …), `AuthService` 싱글턴은 `tearDown(signOut())` 로 원복(`test/screens/home_shell_test.dart:38-42`; 테스트에서 `AuthService.instance` 직접 참조는 1파일 4곳뿐).
- 작은 `ChangeNotifier` 컨트롤러 규약: `ThreadMessagesController`, `IqMessagesController`, `CommunityPaginator<T>` [P1-arch §1-4]. 교차 화면 상태는 값 없는 세대 신호 + 각 화면 재조회(`data_refresh_bus.dart:3-9`).
- 역방향 의존 실재: `core/auth/deletion_notice_controller.dart:3` → `features/mypage/data/account_deletion_repository.dart`, `core/push/push_payload.dart:3` → `features/notifications/...` [P1-arch §1-3]. import 방향 린트 없음(`analysis_options.yaml` 4규칙).

### 3-2. 문제

1. 화면 3~4배 → seam 도 3~4배(생성자마다 3~6개 `Override`). 같은 의존(웹 브릿지·현재 uid·역할)을 30개 화면이 각자 seam 으로 뚫는다.
2. 싱글턴 직접 참조(19파일) 때문에 위젯 테스트가 프로세스 전역 상태를 공유 → `tearDown` 원복 규약에 의존. 화면이 늘면 오염 위험 증가.
3. 공유 도메인 상태(지갑·구독 요약·차단 목록·멘토 프로필·CR 주문 카운트)를 소유하는 계층이 없어 각 화면이 재조회 — 신설 멘토 콘솔/CR 은 여러 화면이 같은 요약을 본다.
4. `core → features` 역방향 import 는 새 저장소에서 기능 모듈 이식 순서(코어 먼저)를 막는다.

### 3-3. 대안 비교

| 안 | 테스트 250→1,500 이식성 | 손코딩 Fake 규율 | 비용/리스크 |
|---|---|---|---|
| A. 현행 유지(싱글턴 + Override seam) | 100% 그대로 | 유지 | 문제 1~3 확대. 신설 화면마다 seam 설계 |
| **B. 수동 스코프 DI(`AppScope` InheritedWidget + `Deps` 레코드) + 생성자 주입 유지** | 화면 생성자 `Override` 는 **전환기 동안 유지**(우선순위: 생성자 인자 > 스코프 > 프로덕션 기본값) → 기존 위젯 테스트 무수정 통과, 신설 화면은 스코프만 | 유지(Fake 를 `Deps` 에 꽂음) | 새 의존성 0. 스코프 객체 수동 관리. 비동기 캐시는 직접 작성 |
| C. Riverpod | `ProviderScope(overrides:[p.overrideWithValue(Fake())])` 로 손코딩 Fake 와 호환. 그러나 30파일의 `Override:` 위젯 테스트는 ProviderScope 래핑으로 재작성, `@visibleForTesting static` 은 무영향 | 유지 가능(mock 불필요) | 의존성 1개 + 학습 곡선, codegen 없이도 가능. 전역 `.instance` 와 이중 체계 기간 발생 |
| D. Provider | C 와 유사하나 타입 기반 조회·비동기 조합 약함 | 유지 | 큰 이점 없음 |

### 3-4. 권고 (B, 조건부 C)

1. **`lib/core/di/app_scope.dart`**: `AppScope(deps: Deps, child)` InheritedWidget 1개 + `Deps` 불변 레코드(세션/프로필 컨트롤러, 레포 팩토리, `WebBridge`, `AttachmentUploaderPort`, `SignedUrlResolver`, `RealtimeFactory`, `FeatureFlags`, `Clock`). `main()` 이 프로덕션 `Deps.production()` 을 만들고 `runApp(AppScope(...))`. 테스트는 `AppScope(deps: Deps.fake(...))` 로 감싼다 — mock 프레임워크 금지 규율 그대로.
2. **싱글턴 폐기 순서**: `AuthService.instance` → `Deps.session`(파사드 게터 유지); `TabNavigator`/`DataRefreshBus`/`NotificationBadgeController`/`DeletionNoticeController`/`VersionGateController` 는 `Deps` 소유 인스턴스로. `static` 은 순수 함수와 상수만 남긴다. 계약 테스트: `lib/features/**` 에서 `\.instance\b` 0건.
3. **공유 상태 소유자**: `WalletStore`, `SubscriptionSummaryStore`, `BlocksStore`(현 static 캐시 이전), `MentorProfileStore`(멘토 콘솔), `CrCountersStore` 를 `ChangeNotifier` 로 `Deps` 에 두고, `DataRefreshBus` 세대 신호를 이 store 들이 구독해 재조회(화면은 store 만 본다). 규약: store 는 서버 정본 재조회만 하고 로컬 계산·영속 캐시 금지(기존 `deletion_notice_controller.dart:5-18` 원칙 승계).
4. **Override seam 정책**: 기존 이식 화면은 `xxxOverride` 유지(삭제는 별 PR), 신설 화면은 생성자 seam 금지·스코프 조회만. `loaderOverride` 23곳은 "화면이 `Future<T> Function()` 을 받는" 형태라 `Deps` 의 레포 Fake 로 대체 가능 — 전환 시 `test/` 의 해당 30파일을 `AppScope` 래핑으로 바꾸는 기계적 작업.
5. **Riverpod 도입은 보류**: 조건부 재검토 트리거 = (a) 비동기 파생 상태(store 간 조합)가 3개 이상 필요, (b) 화면 수명과 무관한 keep-alive 캐시 요구. 그때도 손코딩 Fake·`@visibleForTesting` 순수 함수 규율은 유지되며, `AppScope` → `ProviderScope` 치환은 국소적.
6. **의존 방향 강제**: `test/contracts/layering_contract_test.dart` 신설 — `lib/core/**` 는 `lib/features/**`·`lib/app/**` import 0, `lib/shared/**` 는 `features` import 0(현 위반 4건은 포트를 `core` 로 이동해 해소: `AccountDeletionPort`·`NotificationEventType`·`AppTab`). `conversation_ui_layering_test.dart`·`iq_create_boundary_test.dart` 의 소스 스캔 방식을 재사용.

---

## 4. DB 계약 확장 원칙

### 4-1. 현행(근거)

- **앱 정본 스키마 `api_app_v1`**: schema 1 + view 1(`community_posts_v1`) + function 6(`ensure_free_question_room`, `qna_create_question_thread`, `community_post_create/_update/_soft_delete`, `user_profile_update_self`) — `web:supabase/migrations/20260731114120_20260730112525_api_app_v1_surface.sql:1-20,85-88,253-262`, `…20260803170552…:251-264`. 스키마 USAGE 는 **authenticated 만**(service_role 없음 — 웹 `api_web_v1` 과의 의도적 차이, `:7-8`).
- **패턴 정본**: 얇은 SECDEF wrapper(`SET search_path=''`, `auth.uid()` 자체 도출) → `core_private.*_impl`(SECURITY INVOKER, 외부 EXECUTE 0, 스키마 USAGE 0) — [P1-db §1.4]. 사용자 ID 인자 금지(T1·T2): `web:docs/contracts/api_web_v1_contract_v1_1.md:1695-1703`.
- **현행 앱의 실태**: 쓰기 5종은 `api_app_v1`(`board_post_create_gateway.dart:27` `kBoardPostCreateSchema='api_app_v1'`, `profile_edit_repository.dart:39`, `free_question_entry.dart:170`). 읽기는 **`api_web_v1`** 을 직접: `community_read_repository.dart:71-72,192-193,224-225`(`community_posts_v1` — **앱 전용 `api_app_v1.community_posts_v1` 이 있는데도 웹 뷰를 읽음**), `mentor_directory_repository.dart:39-40,52-53`(`mentor_directory_v1`), `mypage_repository.dart:139-140,159-160`(`my_wallet_v1`·`my_cash_ledger_v1`), RPC `api_web_v1.weekly_question_usage_self(_batch)`(`question_room_read_repository.dart:148-151,171-174`). 그 외 RPC 27종은 `public` [P1-features §2.1].
- **봉투 2스타일**: ① `raise exception 'CODE'` → `PostgrestException.message` 선두 토큰 파싱(`qna_error_mapper.dart:85-90`, `iq_error_mapper.dart:69-74`, `profile_edit_repository.dart:73-78`); ② jsonb `{ok, code, contract_version}` strict(`ok==true && contract_version==1` 아니면 실패 — `board_post_create_gateway.dart:120-135`, `account_deletion_repository.dart:233-269`, `notifications_repository.dart:90-106`). 웹 계약 §8.1 도 envelope 를 정본으로 규정(`api_web_v1_contract_v1_1.md:898,1010-1012,1040`). 그런데 **DB-3 신설 `soft_delete_own_content` 는 `returns void` + raise**(`web:supabase/sql/196_soft_delete_own_content_rpc.sql:10,78,166`) — 웹 정본 자체가 두 스타일을 계속 생산 중.
- **매니페스트 잠금**: `test/contracts/outbound_api_manifest_test.dart` — RPC 리터럴 32(`:15-59`), 식별자 3(`:63-67`), 스키마 `{api_app_v1, api_web_v1}`(`:69-74`), 테이블/뷰 24 + 식별자 3(`:77-117`), 버킷 상수 6·정의값 6(`:120-137`), 금지어 8(`:140-149`), `from('users')` 체인 `.update/.insert` 금지(`:298-311`), `community_posts` 베이스 0(`:313-319`), `'firebase'` 0(`:321-326`). **한계**: RPC 집합이 이름만이라 `qna_create_question_thread` 처럼 `public`·`api_app_v1`·`api_web_v1` 에 동명 함수가 있으면 어느 스키마를 부르는지 잠기지 않는다.
- **마이그레이션 규율**: 앱 저장소 SQL 금지(`supabase/SCHEMA_SOURCE_OF_TRUTH.md` 규율 1~3), 웹 pack 3중 사본(`sql/NNN` → `baseline/post_ledger_backfills/<version>` → 생성기 소유 `migrations/`), 라이브 적용은 `db-apply-pending.yml`(dispatch·Environment 승인·dry-run 기본·confirmation 문자열, `web:.github/workflows/db-apply-pending.yml:1-40`), hotfix 역수입 규칙(`web:CLAUDE.md`). 정식 절차 9단계 [P1-db §5.2].
- **Data API 노출**: `api_web_v1`·`api_app_v1` 노출은 **플랫폼 설정**(D-API-W/A), SQL 로 판정 불가, `ALTER ROLE authenticator SET pgrst.db_schemas` 금지(`api_web_v1_contract_v1_1.md:2463-2492`). 반면 **로컬 스택 `web:supabase/config.toml:13` 은 `schemas = ["public", "graphql_public"]`** — 로컬 Supabase 로 앱을 띄우면(`app_config.dart:16-17` 기본 `http://127.0.0.1:54321`) `api_*` 스키마 호출이 실패한다 **(확인 필요: 로컬 개발 실사용 여부·실제 오류 코드)**.
- 새 wrapper 공통 게이트: 계정 positive allowlist(`ugc_write_allowed()` 판정식) + `account_deletion_write_blocked(self)` 를 impl 에서 수행 [P1-db §6 공통 규칙].
- `register_device_token` authenticated GRANT: 헤더는 "라이브 미적용"(`web:supabase/migrations/20260827100100_device_token_register_grant.sql:1-3`) 이나 `web:docs/sprint-push/PUSH-APPLY.md:1-8` 에 2026-08-27 적용 증적 — 원장 대조 **(확인 필요)**.

### 4-2. 문제

1. 읽기 표면이 `api_web_v1`(웹 계약상 웹 표면)에 관행적으로 걸려 있어 웹이 뷰 컬럼을 바꾸면 앱이 깨진다(계약 §19 "api_web_v1 = 웹 표면" 과 어긋나는 사실상 관행 — [P1-db §6 #13]).
2. 봉투 2스타일이 서버 쪽에서도 계속 혼재 → 앱 매퍼 5벌이 같은 문장을 반복.
3. 매니페스트가 스키마-무관 이름 집합이라 동명 함수 오호출(`.schema()` 누락 → PGRST202)을 잡지 못한다.
4. 신설 도메인(CR·멘토 콘솔·가입·마케팅 동의·숏폼 네이티브 작성·학생증 반영)은 `api_app_v1` 에 객체가 전무 → 웹 pack 선행 없이는 앱 개발이 시작조차 못 한다.
5. 로컬 스택 노출 스키마 불일치로 "로컬에서 되는데 원격에서 안 되는" 방향이 아니라 그 반대(로컬 불가)가 생겨 개발 루프가 원격 운영 DB(`lbeqxarxothkmzqvpudy` = 실제 운영, `HANDOFF.md:16`) 로 몰린다.

### 4-3. 대안 비교

| 논점 | 안 1 | 안 2 | 권고 |
|---|---|---|---|
| 표준 스키마 | 읽기·쓰기 전부 `api_app_v1` 로 동명 뷰/함수 복제 | 쓰기 = `api_app_v1` 만, 읽기 뷰·self RPC 는 `api_web_v1` 허용을 **앱 계약에 명문화** | **안 2** — 뷰는 invoker·동일 형상이라 복제는 유지비만 늘림. 단 `community_posts_v1` 은 이미 앱 뷰가 있으므로 `api_app_v1` 로 전환. 신설 쓰기 wrapper 는 전부 `api_app_v1`; `api_web_v1` 에만 있는 self RPC(F7 `mentor_profile_update_self`, F8, F13, `user_marketing_consent_set_self`)는 앱이 쓰는 시점에 `api_app_v1` 동명 wrapper 신설(본문은 impl 공유 — 계약 B-07 원칙) |
| 봉투 | 서버를 envelope 로 통일(레거시 raise RPC 재정의) | 앱 쪽에서 단일 정규화 계층 | **둘 다** — 신설 `api_app_v1` wrapper 는 envelope 의무(계약 §8.1), 레거시 `public` raise RPC 는 재정의하지 않음. 앱은 `RpcOutcome` 정규화 1벌: raise → `code = 선두 토큰 정규식`, envelope → `code = payload.code`, `contract_version==1` 검사, 공통 코드 사전(`AUTH_REQUIRED`·`ACCOUNT_*`·`ROLE_NOT_ALLOWED`·`BLOCKED`·`IDENTITY_REQUIRED`) + 도메인 사전 오버레이 |
| 매니페스트 키 | 이름 집합 유지 | `schema.name` 쌍 집합 | **쌍 집합** — `.schema('x').rpc('y')` 를 함께 추출하는 정규식으로 갱신, `public` 은 명시 `public.y`. 뷰도 동일. 신규 리포 첫 PR 에서 도입 |
| 마이그레이션 위치 | 앱 저장소에 앱 전용 SQL | 웹 pack 만 | **웹 pack 만**(변경 없음). 앱 저장소는 `supabase/SCHEMA_SOURCE_OF_TRUTH.md` 와 `outbound_api_manifest_test` 만 |

### 4-4. 권고 절차 (신설 기능 1건당)

1. **계약 문서**: 웹 `docs/contracts/api_web_v1_contract_v1_1.md` §19.5 동기화 규칙에 따라 앱 계약(`api_app_v1_contract`) 항목 추가 — 시그니처·envelope·오류코드(UPPER_SNAKE 추가만)·GRANT.
2. **객체**: `api_app_v1.<name>(…)` SECDEF thin wrapper → `core_private.<name>_impl(p_actor uuid, …)` INVOKER. 웹 동등 기능은 `api_web_v1` wrapper 가 같은 impl 호출(복제 금지). 권한: `REVOKE ALL FROM PUBLIC` → `GRANT EXECUTE TO authenticated`(service_role 부여 금지). 신규 public 테이블은 RLS + 정책 + GRANT 명시(2026-08-02 default ACL 하드닝).
3. **파일**: `web:supabase/sql/NNN_<name>.sql`(헤더 양식: Purpose·Base·변경 없음·Apply 경로·pack 등재·Rollback·검증) + `supabase/rollback/…` + `baseline/post_ledger_backfills/<version>_<name>.sql` → `build_native_migration_pack.py` → `validate_*` PASS → PR(`db-migration-pack-verify.yml`) → 라이브는 `db-apply-pending.yml` 만. MCP `apply_migration`·즉석 SQL 금지(했다면 같은 세션 역수입).
4. **계약 스냅샷**: `npm run contracts:export` → `contracts:verify` green, 인벤토리 갱신.
5. **노출**: 객체 추가만이면 `NOTIFY pgrst, 'reload schema'`; 새 스키마는 플랫폼 단계(만들지 않는 것을 권고).
6. **앱 매니페스트**: 같은 앱 PR 에 `schema.name` 추가, 폐기 표면은 `kForbiddenWords` 로. Realtime 을 쓰는 신설 테이블은 `supabase_realtime` publication 포함 여부를 pack 에서 확인(현재 baseline 은 `question_messages`·`question_threads`·`question_attachments` 포함 — `web:supabase/migrations/20260701000000_pre_ledger_baseline.sql:16492,18559,18562`; 알림은 `20260803171053…`; CR 테이블 포함 여부 **(확인 필요)**).
7. **로컬 개발**: `web:supabase/config.toml` `[api].schemas` 에 `api_web_v1`·`api_app_v1` 추가를 웹 선행 과제로(플랫폼 설정과 무관한 로컬 전용 — 오너 결정 §9-7).
8. **자금 인접 RPC**: `create_individual_question_as_student`·`release/refund_individual_question`·정산계좌 F13·구독 해지 예약·환불 신청·CR 납품 수락은 "DB 허용 ≠ 정책 허용" — 결제 경계 판정(§9-2) 전에는 wrapper 를 만들지 않는다(`web:docs/policy/app-web-payment-separation.md` §3 경계표).

---

## 5. 공통 인프라 이식 목록 — 판정

판정 어휘: **그대로** = API 무변경 이식 / **일반화** = 시그니처·소유 위치를 바꿔 1벌로 / **교체** = 재설계.

| # | 자산 | 현행(근거) | 판정 | 이식 방식·주의 |
|---|---|---|---|---|
| 1 | 첨부 업로드 파이프라인 | `AttachmentUploaderPort`+`SupabaseAttachmentUploader`(`question_room/data/attachments/attachment_upload.dart:104-114`), 경로 `{roomId}/{threadId}/{ts}_{safeName}`(`:319-327`), RPC 단일 등록·미등록 객체 보상 DELETE·23505 멱등 수용(`:194-259`), `upsert:false`(`:371-375`); IQ 는 별도 순수 오케스트레이터 `uploadIqAttachmentCore`(typedef 7종, `iq_attachment_upload_core.dart:46-70`) | **일반화** | 두 구현을 `UploadPipeline{bucket, pathPolicy, registerRpc, compensate}` 코어 1벌 + 도메인 어댑터(질문방·IQ·CR 납품 `custom-order-deliverables`·CR 첨부 `custom-request-post-attachments`·학생증 `student-id-images`·게시판 이미지)로. HANDOFF "SupabaseAttachmentUploader 재구현 금지"(`HANDOFF.md:97`)는 "코어를 복제하지 말라" 로 해석. 보상 삭제 순서는 웹 계약 §14.4(재호출 선행·보상 후행) 준수 |
| 2 | `downscaleIfOversized` | 5MB 초과 → 장변 2560·JPEG85, `compute` isolate(`core/scan/image_downscaler.dart:6-17`) | **그대로** | `core/media/` 로 이동만 |
| 3 | PDF 래스터 | `PdfRasterizerPort.open → PdfDocumentHandle`, `kPdfRenderLongSidePx=2560`·`kPdfThumbLongSidePx=320`·`kPdfMaxPagesPerPick=5`(`pdf_rasterizer.dart:16-111`), `pdfx ^2.9.2` | **그대로** | 포트 뒤 격리 유지 |
| 4 | 서명 URL 리졸버 4벌 | `AttachmentUrlResolver`(1h, 전역 `_shared`), `IqAttachmentUrlResolver`(1h/60s), `ShortformMediaUrlResolver`(10m/60s, single-flight, 결과 sealed 4종), `CommunityPostImageUrlResolver`(10m/60s, null 폴백) — 각각 `attachment_url_resolver.dart:29-71`, `iq_attachment_url_resolver.dart:30-56`, `shortform_media_url_resolver.dart:83-255`, `community_post_image_url_resolver.dart:41-126` | **일반화** | `SignedUrlResolver<Ref>{bucket, ttl, margin, keyOf(uid, ref), validateRef, singleFlight}` 제네릭 1벌 + 결과 타입은 Shortform 의 `{absent, resolved, failed, invalidReference}` 를 공통 채택. 전역 싱글턴 → `Deps` 소유(계정 전환 시 uid 키·clear 규약 유지). 토큰·서명 URL 로그/DB/SharedPreferences 금지 원칙(`shortform_media_url_resolver.dart:81-82`) 승계. CR 납품 버킷용 5벌째를 만들지 않는다 |
| 5 | Realtime 포트 3벌 + 폴백 | `ThreadRealtimePort`(`thread_realtime.dart:10-21`, 폴백 계약 `:25-28`, 채널 `question_thread_$id` `:44-93`), `IqRealtimePort`(`iq_realtime.dart:12-26,54-110`, 재연결 콜백), `NotificationsRealtimePort`(`notifications_realtime.dart:11-22,47-75`) | **일반화** | `PostgresChangesSubscription{channel, specs:[(event, table, filter)], onEvent, onReconnected}` 1벌 + 도메인 포트는 typedef. "정본은 서버 재조회, publication 미포함 시 조용히 폴백" 계약 유지. §1-4-7 의 "보이는 브랜치만 구독" 훅 추가. CR 메시지 테이블의 publication 포함 여부 **(확인 필요)** |
| 6 | `DataRefreshBus` | 세대 `ValueNotifier<int>` 4종(`data_refresh_bus.dart:14,30,39,49`), 값 미탑재 규약(`:3-9`) | **일반화** | 도메인 키 enum(`RefreshDomain{wallet, subscription, notifications, questionRooms, iq, customRequests, mentorProfile, …}`) → `Map<RefreshDomain, ValueNotifier<int>>`. static → `Deps` 소유. 생산자 0 인 `subscriptionGeneration` 의 "의도된 대기" 주석(`:26-28`) 계약 유지 |
| 7 | `ScreenVisibility` + `ResumeVisibilityGate` | `shared/widgets/screen_visibility.dart:11-68` — 스코프 ∧ `ModalRoute.isCurrent` | **그대로** | 공급자만 HomeShell → StatefulShellRoute 브랜치 |
| 8 | 에러 매퍼 + `friendlyError` | 도메인 매퍼 3파일(`qna_error_mapper.dart`, `iq_error_mapper.dart`, `community_post_error_mapper.dart`) + 봉투용 함수들, `AppError{userMessage, cause}`(`shared/errors/app_error.dart`), 원문 비노출(`friendly_error.dart:5-9`) | **일반화** | §4 `RpcOutcome` 정규화 + `ErrorCodeTable`(공통 사전 + 도메인 오버레이). 신규 코드: `IDENTITY_REQUIRED`(웹 403 선두 토큰 — `web:lib/identity/identityGate.ts:10-20`), DB-3 `INVALID_KIND`·`CONTENT_NOT_OWNED`·`CONTENT_MODERATED` 등. `friendlyAuthError`(`friendly_error.dart:16-24`) 그대로 |
| 9 | `web_bridge` | `WebBridgeConfig.baseUrl = fromEnvironment('WEB_BASE_URL', 'https://ssambership.com')`(`web_bridge_config.dart:16-19`), 경로 상수 10종(`:24-52`, 구매 경로 의도적 부재 `:22-23`), `isAllowedUri` https+호스트/서브도메인(`web_bridge.dart:97-106`), 헬퍼 9종 | **그대로** | 경로 표에 CR·멘토 콘솔 웹 폴백 경로 추가만. `HANDOFF.md:111-112` 도메인·`subscribePath` 서술은 구식 — 새 저장소 문서에 복사 금지 |
| 10 | WebView 브릿지(bootstrap 계약) | 앱 `ShortformComposeBridge`(`core/web_bridge/shortform_compose_bridge.dart:20-82`: 4경로 allowlist·호스트 정확 일치·`target='shortform_create'`·완료 `kind=shortform&result=draft\|published`) ↔ 웹 `POST /api/app-session/bootstrap`(`web:app/api/app-session/bootstrap/route.ts:19-32,101-126`), target enum 단일(`web:lib/appSession/appSessionBootstrapCore.ts:17-19`), kinds/results/error codes(`web:lib/appSession/appSurfacePaths.ts:8-25`), 멘토 전용 게이트(`route.ts:116-119`), 앱 표면 전용 클라이언트(`web:lib/supabase/appSurfaceServer.ts`) | **일반화**(양쪽) | 앱: `AppSurfaceBridge{target, allowedPaths, completion(kind, results)}` 표로 일반화, WebView 위생(`WebSessionHygiene.clear` 여닫이) 유지. 웹(선행): target enum 확장(`identity_onboarding`, `mentor_verification`, `account_delete`(선택), `admin` 은 불허) + target 별 역할 게이트 + kind/result 확장 + 계약 테스트(`web:lib/appSession/__contract__/*`) 갱신. 토큰은 POST body 만·URL 금지 원칙 유지 |
| 11 | 버전 게이트 | `get_mobile_app_version_policy` anon RPC, `decide()` 정수 비교(`version_gate_decision.dart:33-41`), G1 캐시, 스토어 URL allowlist(`store_url_policy.dart:10-27`), `VersionGateShell` 이 Navigator 위(`app.dart:40-43`) | **그대로** | 새 앱 출시 = 구 앱 차단 수단이 `min_supported_build` 상향 하나(§7). `docs/APP_V16_MIN_VERSION_SERVER_REQUIREMENT.md` 는 구식 — 복사 금지 |
| 12 | Sentry 부팅 | `bootstrapCrashReporting` fail-open·runner 1회(`crash_reporting.dart:13-23,29-85`), `sendDefaultPii=false`·tracing off(`:99-113`), env 기본 `staging`(`:125-128`) | **그대로** | `validate_release_env.dart` 의 production 강제 유지 |
| 13 | `commerce_policy` | `kInAppPaymentSteeringEnabled=false`(`commerce_policy.dart:10`), 링크 플래그 2종(`:17-18,29-30`), 대체 문구 | **그대로** | §8 플래그 표에 편입. `Entitlement.inAppPurchaseEnabled=false`(`core/entitlement/entitlement.dart:23`) 유지 |
| 14 | scan / ink 코어 | `ScanSourcePort`·`PickedImage`·`kScanMaxLongSidePx`; `InkDocument`(format `ssambership.ink` v1)·`InkStoragePaths`·`InkCoordinateMapper`·`ScribbleInkAdapter` [P1-arch §5-7] | **그대로** | "시그니처 변경 금지·추가만"(`HANDOFF.md:95-96`). `connection-note-ink` 는 deprecated 규약만 잔존 — 새 저장소에서 버킷 상수 유지 여부 결정(§9-8) |
| 15 | 푸시 포트 | `PushPayload.fromRemote`(type 18종·ids·dedup, link/url 폐기), `PushPermissionPort`+`DisabledPushPermission`(`push_ports.dart:27-44`), `'firebase'` 0 강제(`outbound_api_manifest_test.dart:321-326`) | **그대로**(재도입은 별건) | FCM 재도입 시: `register_device_token` GRANT 적용 증적(`web:docs/sprint-push/PUSH-APPLY.md`) 확인 → 매니페스트 RPC 추가·`'firebase'` 0 규칙 해제·`google-services.json` 배치. `core/push/push_payload.dart:3` 의 features 역방향 import 는 타입을 core 로 이동 |
| 16 | 계정 상태·탈퇴 배너 | `AccountStatusReader.resolve`(`account_status.dart:226-312`), `DeletionNoticeController`(`deletion_notice_controller.dart:5-18`: 서버 `can_cancel` 만·로컬 캐시 금지) | **그대로**(+확장) | §2 의 `deleted`·allowlist 정합, `OnboardingNeed` 입력 추가. `AccountDeletionPort` 를 `core` 로 이동(역방향 import 해소) |
| 17 | `AppConfig` / `.env` | `dotenv` 기반, 로컬 URL 플랫폼 분기(`app_config.dart:16-44`), `.env` 는 pubspec 에셋(`pubspec.yaml:75`) | **일반화** | §8 |
| 18 | `model_parse` 2벌·페이지네이터 | `community/data/model_parse.dart`, `question_room/data/models/model_parse.dart`; offset `CommunityPaginator`, keyset 알림 커서, 메시지 복합 커서 [P1-arch §3-5,§3-8] | **일반화** | `core/data/parse.dart` 1벌, `KeysetPaginator<T>` 1벌(알림·메시지·CR 목록 공용). offset 페이저는 커뮤니티 한정 유지 |
| 19 | `subject_labels`·`QuestionRoomLabels`·`subscriptionStatusDisplay` | 코드→한글 정본 매핑 [P1-arch §3-5] | **그대로** | `subjectCodeForDb` 필수 통과 규칙 유지 |
| 20 | 손코딩 Fake 모음 | `test/community/fakes.dart`(`_Unset` 센티넬), `test/version_gate/version_gate_fakes.dart` 등 | **그대로** | 포트 시그니처가 일반화되는 항목(4·5·6·8)은 Fake 도 함께 이동 |

---

## 6. 테스트·CI

### 6-1. 현행(근거)

- contract 테스트 6종(`test/contracts/`): `outbound_api_manifest_test.dart`(§4), `iq_create_boundary_test.dart`(`iq_create_screen.dart` import 0·CTA 는 웹 브릿지, `:24-83`), `s3e_doc_contract_test.dart`(문서 현행 절 어휘 고정 `:10-30`), `android_signed_workflow_contract_test.dart`(SOURCE_SHA 40자 상수 `:125-126`, 외부 action SHA 핀 `:164-180`, 테스트 수 `1508` `:147`, upload-artifact 1개·retention 3 `:248-258`, dart-define 금지 `:293-294`), `ios_release_config_contract_test.dart`(pubspec 버전 핀 `:25`, 번들 ID `com.ssambership.app` `:29`, 수집 유형 5종 정확 집합 `:44-50` + 금지 유형 `:54-62`, `LSApplicationQueriesSchemes` `:128-152`, 배포 타깃 13.0 `:338-340`), `xcode_cloud_bootstrap_contract_test.dart`(`ci_post_clone.sh` `:19`, Flutter `3.44.6` 핀 `:25`, dart-define 금지 `:122`).
- 워크플로 2종: `flutter-ci.yml`(master push/PR/dispatch, Java 17 `:36-39`, Flutter 3.44.6 `:41-45`, `.env` 자리표시 `:50-51`, analyze 출력 파싱 게이트 `:56-69`, test `:71-77`, appbundle 비게이트 `:79-90`, ci-logs 브랜치 `:102-121`, 게이트 판정 `:123-127`); `android-signed-release-candidate.yml`(dispatch 전용·Environment `android-release-candidate`, `SOURCE_SHA`/`EXPECTED_*` 상수 `:52-72`, 사람 확인 입력 2종 `:30-45`, 테스트 1,508 정확 일치, 운영 `.env`+`validate_release_env`, keystore 복원, jarsigner·bundletool·내장 env 검증, artifact 3일, cleanup).
- Xcode Cloud: `ios/ci_scripts/ci_post_clone.sh`(Flutter 핀 `:19`, 운영 URL 정확 일치 `:20,75-78`, `.env` fail-closed `:64-87`, SwiftPM `:62,97`).
- 계약 스냅샷 문서: `docs/APP_V16_SERVER_CONTRACT_SNAPSHOT.md`(2026-07-21 staging 실조회 `:1-8`) — DB-1~3(2026-09-03) 이전 스냅샷. 웹 쪽은 `contracts:export/verify` + `docs/audit/remote_db_inventory_*` [P1-db §5.2 #7]. 앱 `supabase/SCHEMA_SOURCE_OF_TRUTH.md` 가 "앱이 부르는 표면의 정본 목록 = 매니페스트 테스트" 로 지정.
- 테스트 대체 방식: `SupabaseInit` 미초기화 → `clientOrNull==null` → 레포가 `AppError`/빈 결과, 화면은 에러/빈 상태(`test/screens/home_shell_test.dart:10,34-35`) [P1-arch §7-3]. e2e 는 실 staging(=운영) DB 대상, 쓰기 2건만(`integration_test/e2e_staging_test.dart:7-14`).

### 6-2. 문제

1. 서명 워크플로의 `EXPECTED_TEST_COUNT: "1508"` 과 계약 테스트 `:147` 의 정확 일치는 새 저장소에서 테스트 수가 변하는 즉시 깨진다(문서 `HANDOFF.md:199` 250개 ↔ CI 1,508 ↔ grep 1,470 로 이미 3값 혼재).
2. `SOURCE_SHA`·`EXPECTED_PR`·artifact 이름(`:344` `1.0.0-18-35d7b03`) 이 특정 PR 에 묶인 검증 전용 워크플로라 그대로는 재사용 불가(PR 마다 상수 교체 + 계약 테스트 상수 동기 수정).
3. iOS `kExpectedCollectedDataTypes` 는 실명·전화·학생증·결제 없음 전제(`NSPrivacyCollectedDataTypeName` 금지 `:55`) — 가입·본인인증·학생증 업로드가 들어오면 PrivacyInfo·집합·Data safety 를 함께 갱신해야 통과.
4. 앱 쪽 계약 스냅샷 문서가 손으로 쓴 staging 조회 결과라 웹 pack 진화를 따라가지 못한다.
5. 매니페스트가 스키마-무관(§4-2-3).

### 6-3. 대안 비교

| 논점 | 안 | 권고 |
|---|---|---|
| 테스트 수 핀 | (a) 정확 일치 유지 (b) 하한(`>= N`) (c) 핀 제거·"실패 0·스킵 0" 만 | **(c)** + footer 파싱으로 "All tests passed" 와 skip 0 확인. 회귀 감지는 계약 테스트가 담당 |
| 서명 워크플로 | (a) 그대로 복사 (b) `SOURCE_SHA` 를 입력으로 (c) 태그 기반 릴리즈 워크플로로 재작성 | **(c)** — `on: push: tags: v*` + Environment 승인, 빌드 대상 = 태그 커밋(자유 입력 금지 원칙 유지), 검증 단계(analyze·test·validate_release_env·keystore·jarsigner·bundletool·내장 env·artifact·cleanup)는 그대로 이식, `EXPECTED_VERSION*` 은 pubspec 에서 파생 |
| 계약 스냅샷 | (a) 앱 docs 수동 갱신 (b) 웹 `contracts:export` 산출물(카탈로그·grant·hash)을 앱 CI 가 읽어 매니페스트 집합과 대조 | **(b)** — 웹 저장소를 read-only checkout 하거나 산출 JSON 을 release asset 으로 받아 "매니페스트의 모든 `schema.name` 이 인벤토리에 존재하고 authenticated EXECUTE/SELECT 가 있다" 를 검증. 앱 `docs/APP_V16_*` 스냅샷은 새 저장소에 복사하지 않고 링크만 |

### 6-4. 권고

1. **승계(그대로)**: `outbound_api_manifest_test`(키를 `schema.name` 으로 개정), `iq_create_boundary_test`(경계 유지 시), `ios_release_config_contract_test`(상수만 새 값), `xcode_cloud_bootstrap_contract_test`, `android_signed_workflow_contract_test`(재작성된 워크플로 구조에 맞게 기대값 갱신), `s3e_doc_contract_test`(문서 이식 시).
2. **신설 계약 테스트**: `layering_contract_test`(§3-4-6), `feature_registry_contract_test`(§2-4-4: 모든 라우트가 registry 에, roles 비어있지 않음, admin 허용 라우트 0), `flags_contract_test`(§8: 릴리즈 기본값 표와 `bool.fromEnvironment` 기본값 일치), `bridge_targets_contract_test`(앱 target·allowlist 표 ↔ 웹 `appSurfacePaths.ts` 상수 문자열 일치 — 웹 파일을 fixture 로 복사해 대조), `no_singleton_in_features_test`(`lib/features/**` 의 `.instance` 0).
3. **CI**: `flutter-ci.yml` 은 그대로(브랜치명 `master` 유지 여부는 새 저장소 기본 브랜치에 맞춤). analyze 파싱 게이트 유지(Flutter 3.44 의 info exit 1 특성 `:56-58`). Flutter 핀은 **3.44.6**(`flutter-ci.yml:44`·`ci_post_clone.sh:19`·계약 테스트 `:25` 가 정본; `HANDOFF.md:21,61,200` 의 3.44.4 는 구식).
4. **계약 스냅샷 갱신 규율**: 서버 표면을 바꾸는 PR = 웹 pack PR(계약 문서·export/verify) → 앱 PR(매니페스트·매퍼·Fake) 순서로 2건, 앱 PR 본문에 웹 pack version 명시. 앱 `docs/` 에 서버 계약 사본을 두지 않는다(스냅샷은 웹 `docs/audit/remote_db_inventory_*` 링크).
5. **e2e**: 실 운영 DB 대상 규칙(쓰기 2건·가역) 유지, CR·가입 시나리오는 e2e 에 넣지 않는다(비가역 쓰기).

---

## 7. 새 저장소 부트스트랩 전략

### 7-1. 현행(근거)

- 네이티브 폴더는 **git 추적 중**(`git ls-files`: android 21 · ios 45 · web 7). `HANDOFF.md:169` "untracked" 서술은 구식. `README.md:11-24` "S0 스캐폴드·네이티브 폴더 없음" 도 구식.
- Android: `namespace/applicationId = com.ssambership.edu`(`android/app/build.gradle.kts:30,43`), `minSdk 24`·`targetSdk 36`·`compileSdk 36`(`:34,45-46`), `versionCode/Name = pubspec`(`:49-50`), `key.properties` 기반 release 서명·부재 시 debug 폴백은 `allowInsecureSigning` 명시 시만(`:18-25,53-72,78-89`), AGP `9.0.1`·Kotlin `2.3.20`(`android/settings.gradle.kts:21-23`), JDK 17. Firebase: `google-services.json` 삭제(HEAD `635ae73`)·gradle 플러그인 없음(grep 0)·`.gitignore` 차단. Kotlin 패키지 경로 `com/ssambership/edu`.
- iOS: 번들 `com.ssambership.app`(`ios/Runner.xcodeproj/project.pbxproj:389`), 배포 타깃 13.0(`:367`), 자동 서명(`CODE_SIGN_STYLE = Automatic`), SwiftPM(`ci_post_clone.sh:62,97`), `PrivacyInfo.xcprivacy`·`Info.plist` 계약 테스트 잠금. HANDOFF: 번들 ID `.app` 유지 vs `.edu` 정렬은 "첫 업로드 후 변경 불가" 오너 결정 대기(`HANDOFF.md:173`).
- 버전/스토어: `pubspec.yaml:4` `1.0.0+19`; 서명 워크플로 입력 "versionCode 19 미사용 확인"(`android-signed-release-candidate.yml:30-35`); Play 업로드 선행 블로커 문서(`docs/ANDROID_SUBMISSION_READINESS_2026-07.md:12,24`); `mobile_app_version_policies` android `store_url NULL`(2026-08-08, 스토어 등재 전 — [P1-db §7.1]). **스토어 실제 등재·업로드 이력은 (확인 필요)**.
- 의존성: `supabase_flutter ^2.5.0`, `go_router ^14.2.0`(lock 14.8.1), `flutter_dotenv`, `url_launcher`, `image_picker`, `file_picker`, `scribble`, `image`, `pdfx`, `video_player`, `package_info_plus`, `webview_flutter(+android/wkwebview)`, `sentry_flutter ^9.26.0`, `shared_preferences`; dev `integration_test`, `flutter_lints ^4`, `flutter_launcher_icons`, `yaml`(`pubspec.yaml:10-62`). `pubspec.lock` 커밋 정책(`HANDOFF.md:168`). `.env` 에셋(`pubspec.yaml:75`).
- Flutter 핀: **3.44.6**(CI·Xcode Cloud·계약 테스트). SDK 제약 `>=3.4.0 <4.0.0`, `flutter >=3.22.0`(`pubspec.yaml:6-8`).
- 웹 선행 표면: `api_app_v1` 함수 6종만(§4), bootstrap target 1종(`web:lib/appSession/appSessionBootstrapCore.ts:17-19`), 로컬 `config.toml` 노출 스키마 public 만(`web:supabase/config.toml:13`).

### 7-2. 문제

- 화면 3~4배 확장에 `lib/app/`(458줄)·`core/auth` 재설계(§1·§2)·DI 전환(§3)이 필요하지만, **네이티브·서명·CI·계약 테스트·1,470건 테스트·Fake·문서 규율**은 재작성 가치가 없다.
- `flutter create` 신규 프로젝트는 `applicationId`·`minSdk/targetSdk`·서명 스켈레톤·`PrivacyInfo`·`Info.plist` 키(`ITSAppUsesNonExemptEncryption`·`LSApplicationQueriesSchemes`·권한 문구)·SwiftPM 설정·`ci_post_clone.sh`·Kotlin 패키지 경로를 전부 다시 만들어야 하고, 계약 테스트 6종이 그 상태를 정확히 잠그고 있어 처음부터 빨간 CI 로 시작한다.
- Play 업로드 이력이 있다면 `applicationId`·업로드 키·`versionCode` 단조 증가는 어느 안이든 필수 계약이고, 이력이 없어도 `com.ssambership.edu` 패키지·`com.ssambership.app` 번들 계약은 문서·Firebase 앱 등록과 얽혀 있다(`HANDOFF.md:170`).

### 7-3. 대안 비교

| 안 | 내용 | 장점 | 단점 |
|---|---|---|---|
| A. 기존 저장소 브랜치(장기 브랜치 → 병합) | `claude/...` 류 브랜치에서 `lib/app`·`core` 재설계 후 feature 이식 | 이력·CI·서명·계약 테스트·이슈 연속. `flutter-ci` 가 PR 마다 검증 | 장기 브랜치 드리프트, 구 문서(HANDOFF/README/APP_V16_*)가 같은 트리에 남아 "정본 오독" 지뢰 지속 |
| **B. 기존 저장소를 새 저장소로 복제(이력 보존) 후 기본 브랜치에서 코어 재구성** | `git clone --mirror`/import 로 새 저장소 생성(이력·태그 유지), 첫 커밋들이 (1) 구 문서 정리·아카이브 (2) `lib/app`·`core/di`·`core/auth` 재구성 | A 의 장점 + 깨끗한 문서/이슈 공간, 구 저장소는 읽기 전용 아카이브. 네이티브·서명·CI 재사용 100% | GitHub Environment secrets(`android-release-candidate`)·Xcode Cloud 워크플로 재등록 필요. 두 저장소 공존 기간 관리 |
| C. `flutter create` 새 프로젝트 + 모듈 이식 | 빈 프로젝트에 `lib/core/*`·feature 폴더 복사 | 스캐폴드 최신 | 네이티브 설정·서명·CI·계약 테스트 재구축 비용 최대, 버전코드·패키지명 실수 위험, 초기 CI 전면 적색. 얻는 것은 "Flutter 템플릿 최신화" 정도(현재도 3.44 SwiftPM 구조라 이득 미미) |
| D. 모노레포(웹+앱) | 웹 저장소 하위에 앱 | 계약 스냅샷 대조 용이 | 앱 CI(Flutter)·서명 secrets 가 웹 저장소 권한 모델과 섞임, HANDOFF §5 "웹 구조 침범 금지" 정신과 충돌 |

### 7-4. 권고 (B)

1. **저장소**: 이력 보존 복제. 구 저장소는 아카이브(README 상단에 후속 저장소 링크). 기본 브랜치는 `main`(`flutter-ci.yml:15-18` 의 `master` 트리거 갱신).
2. **첫 정리 커밋(코드 무변경)**: `HANDOFF.md`·`README.md` 를 현행 사실로 재작성(위 구식 항목 제거), `docs/APP_V16_*`·`CROSS_VERIFY_*`·`QA_*_2026-07` 은 `docs/archive/` 로 이동(계약 테스트가 읽는 `docs/S3E_QUESTION_ROOM_SAFETY_CONTRACT.md` 는 유지), `lib/core/push/HANDOFF.md` 는 정본으로 승격. `lib/features/onboarding/onboarding_screen.dart`(참조 0) 삭제.
3. **이식 순서**(각 단계마다 analyze·test 그린):
   - ① **코어**: `core/di/app_scope`(§3) → `core/auth` 확장(§2: `AccessState.onboarding`·`OnboardingNeed`·status allowlist) → `core/config/feature_flags`(§8) → 공통 인프라 일반화(§5 #1·4·5·6·8·18) → `app/` 재설계(§1: 라우트 spec·역할 탭 spec·StatefulShellRoute·`AppNavigator`) → 계약 테스트 신설(§6-4-2).
   - ② **기존 feature**(서버 계약 변동 없음 — [P1-features §6.1]): 질문방·연결노트·첨부/스캔/주석 → 알림(딥링크 → 경로) → 커뮤니티(`community_posts_v1` 을 `api_app_v1` 로 전환, 본인 삭제 `soft_delete_own_content` 통일은 §9 결정 후) → 멘토 찾기·찜·무료질문 → 마이페이지·탈퇴·프로필 → IQ. 각 feature 는 `fromId` 라우트 진입 추가, 화면 내부 `currentRole` 제거.
   - ③ **신설 feature**(웹 pack 선행 필수): 가입/온보딩(WebView 위임 target) → 멘토 콘솔(프로필 F7·요금 F8·정산계좌 F13 의 `api_app_v1` twin) → 맞춤의뢰(테이블·RPC 전부 신규 등록, 게이트 코드 집합 해제) → 지원/공지 → 푸시(FCM) → 결제 경계 판정 후속(구독 해지 예약·환불 신청·CR 납품 수락).
4. **네이티브 계약 유지**: `com.ssambership.edu`·`com.ssambership.app` 그대로(변경은 §9-5 결정), `versionCode` 는 `+19` 에서 단조 증가(스토어 미등재여도 낮추지 않음), 업로드 keystore·`key.properties` 는 Environment secret 재등록, Firebase 는 재도입 결정 시에만.
5. **버전 계약 테스트**: `kPinnedPubspecVersion`(`ios_release_config_contract_test.dart:25`)·`test/app/build_version_test.dart`·워크플로 `EXPECTED_VERSION*` 세 곳 동시 갱신 규칙을 스크립트(`tool/bump_version.dart`)로 묶는다.
6. **웹 저장소 선행 작업 목록**(앱 ③ 이전에 pack 적용·contracts:verify green):
   - (a) `api_app_v1` 신설 wrapper: `user_marketing_consent_set_self`, `mentor_profile_update_self`, `mentor_plan_prices_set_self`, `mentor_payout_account_update_self`(결제 인접 — 결정), `mentor_student_id_image_set_self`, `custom_request_post_delete_draft_self`, CR 상태 전이·조회용 self RPC/뷰(웹 CR 리포트 기준), `shortform_post_create`(네이티브 전환 시), 구독 해지 예약·환불 신청(결정 후). 공통 impl 은 `core_private`.
   - (b) bootstrap target 확장: `identity_onboarding`(학생·멘토), `mentor_verification`(멘토), kinds/results/error codes 확장, target 별 역할 게이트(admin 불허), `appSurfacePaths` 계약 테스트 갱신.
   - (c) 게이트 env 의 서버 노출: `identity_gate_enabled` 를 anon RPC 응답에(§2-4-3).
   - (d) `mobile_app_version_policies`: 신규 앱 출시 시 `store_url` 채움 → `min_supported_build` 상향(구 앱 차단), 플랫폼별.
   - (e) Realtime publication: CR 메시지·주문 테이블 포함(앱이 실시간을 쓸 경우).
   - (f) 로컬 `supabase/config.toml` `[api].schemas` 에 `api_web_v1`·`api_app_v1` 추가(개발 루프).
   - (g) App Links/Universal Links 채택 시 `/.well-known/assetlinks.json`·`apple-app-site-association` 배포(§9-3).
   - (h) `docs/contracts/api_web_v1_contract_v1_1.md` §19.5 에 따른 앱 계약 v1.2 동기화(읽기 뷰 허용 명문화 §4-3).

---

## 8. 컴파일 타임 스위치·환경

### 8-1. 현행(근거)

| 종류 | 키 | 기본 | 정의 |
|---|---|---|---|
| dart-define | `IQ_CREATE_ENABLED` | false | `lib/features/individual_question/iq_flags.dart:19-20` |
| dart-define | `SUBS_MANAGE_LINK_ENABLED` / `PAYOUT_MANAGE_LINK_ENABLED` | false | `lib/core/commerce/commerce_policy.dart:17-18,29-30` |
| dart-define | `WEB_BASE_URL` | `https://ssambership.com` | `lib/core/web_bridge/web_bridge_config.dart:16-19` |
| dart-define(테스트) | `E2E_*` 7종 | '' | `integration_test/e2e_staging_test.dart:15-24` |
| 컴파일 상수 | `kInAppPaymentSteeringEnabled=false`, `kIndividualQuestionEnabled=true`, `kDevToolsEnabled=!kReleaseMode` | — | `commerce_policy.dart:10`, `iq_flags.dart:9`, `features/dev/dev_flags.dart:5` |
| .env(에셋) | `SUPABASE_URL`(기본 `http://127.0.0.1:54321`)·`SUPABASE_URL_LAN`·`SUPABASE_ANON_KEY`·`SENTRY_DSN`·`SENTRY_ENVIRONMENT`(기본 staging) | — | `.env.example`, `app_config.dart:16-21`, `crash_reporting.dart:125-128` |
| 서버 원격값 | 버전 정책 6키 | — | `get_mobile_app_version_policy` |

- 릴리즈 계약: **dart-define 을 주입하지 않는 것**(`android_signed_workflow_contract_test.dart:293-294`, `xcode_cloud_bootstrap_contract_test.dart:122`, `ci_post_clone.sh:15-16`). `.env` 는 `validate_release_env.dart` 가 production 강제(`:8-18`). `AppConstants.appVersion='1.0.0'` 하드코딩(`app_constants.dart:20`).
- 게이트 관련 잔존: CR 알림 exact 2종 제외(`notification_types.dart:15-18` `kGatedNotificationTypeCodes`).

### 8-2. 문제

1. 플래그 정의가 4파일에 분산, "릴리즈 기본값 표" 가 코드에 없어 계약 테스트가 dart-define 문자열 부재만 본다.
2. 신설 게이트(CR·푸시·IQ 작성·가입·온보딩·멘토 콘솔·숏폼 네이티브 작성)가 늘면 스토어 심사 민감 플래그(결제 인접)와 롤아웃 플래그(기능 점진 공개)가 섞인다.
3. 서버 원격 플래그 수단이 버전 정책 RPC 하나라, 출시 후 기능을 끄려면 앱 재배포가 필요.
4. `.env` 가 에셋이라 `.env` 없으면 analyze/test 실패(`flutter-ci.yml:47-51`) — 개발 진입 장벽.

### 8-3. 대안 비교

| 안 | 내용 | 권고 |
|---|---|---|
| A. 파일별 `bool.fromEnvironment` 유지 | 현행 | 분산 지속 |
| **B. `lib/core/config/feature_flags.dart` 단일 표 + 두 계층** | 컴파일 타임(심사 민감·기본 OFF·릴리즈 무주입)과 서버 원격(롤아웃·기본 fail-safe) 분리 | **채택** |
| C. 전부 서버 원격 | 모든 게이트를 RPC 로 | 심사 민감 플래그를 서버가 켜면 심사 빌드와 동작이 갈림 — 비권고 |

### 8-4. 권고

1. **컴파일 타임 표(`FeatureFlags`)**: `iqCreate(IQ_CREATE_ENABLED)`, `subsManageLink`, `payoutManageLink`, `crEnabled(CR_ENABLED)`, `pushEnabled(PUSH_ENABLED)`, `signupEnabled(SIGNUP_ENABLED)`, `identityOnboardingEnabled(IDENTITY_ONBOARDING_ENABLED)`, `mentorConsoleEnabled(MENTOR_CONSOLE_ENABLED)`, `shortformNativeCompose(SHORTFORM_NATIVE_COMPOSE_ENABLED)`, `webBaseUrl(WEB_BASE_URL)`, `devTools(!kReleaseMode)`. 각 항목에 `releaseDefault` 를 함께 선언하고 `flags_contract_test` 가 "기본값 == releaseDefault" 를 잠근다. 릴리즈 무주입 계약 유지(기존 3 워크플로/스크립트 검사 승계). **결제 인접(`subsManageLink`·`payoutManageLink`·`iqCreate`) 은 서버 원격으로 절대 올리지 않는다**(`docs/policy/app-web-payment-separation.md` 경계).
2. **서버 원격 표(`RemoteConfig`)**: `get_mobile_app_version_policy` 확장 또는 `get_mobile_app_config(p_platform)` anon RPC 신설(웹 pack) — 키: `identity_gate_enabled`, `cr_enabled`, `push_enabled`, `maintenance_message`. 조회 실패는 **직전 성공값 캐시 없음 → 기능별 fail-safe 기본**(CR 은 숨김, 게이트는 "유도 없음"). 컴파일 플래그 OFF 이면 원격값 무시(AND 결합). 오너 결정 §9-6.
3. **환경 파일**: `.env` 는 Supabase·Sentry 자격값 전용으로 유지(에셋·gitignore·`validate_release_env` 그대로), 새 키 `SUPABASE_ENV=local|production`(URL 로 유추하는 `_isRemote` 문자열 검사(`app_config.dart:24`) 대체). `.env` 부재 시 analyze/test 가 죽는 문제는 `flutter-ci.yml:50-51` 방식(예시 복사)을 `tool/bootstrap_env.dart` 로 표준화. `AppConfig` 는 `Deps` 로 주입되는 `AppEnvironment` 값 객체로 일반화.
4. **버전 표시**: `AppConstants.appVersion` 하드코딩 제거 → `package_info_plus`(버전 게이트가 이미 의존) 단일 소스.
5. **e2e define**: 유지, 릴리즈 무주입 검사 대상에서 제외되는 현행과 동일.

---

## 9. 오너 결정 필요 항목(질문 + 권고)

| # | 질문 | 권고 |
|---|---|---|
| 9-1 | 결제 제외 범위에 **캐시 예치(IQ 생성 hold)·구독 해지 예약·환불 신청·CR 납품 수락(에스크로 release)** 를 포함하는가? | DB 가 authenticated 에 열어 둔 4종이라도 정책 정본(`app-web-payment-separation.md` §3)대로 **1차 제외**. 상태 조회·소통만 앱. 재검토는 스토어 정책 검토 완료 후 |
| 9-2 | 신설 wrapper 중 **자금 인접**(정산계좌 F13, 멘토 활동 상태 변경 — 종료 시 환불 생성)을 앱에 넣는가? | F13 은 지급 관리라 소비자 결제와 성격이 다르지만 `PAYOUT_MANAGE_LINK_ENABLED` 와 같은 기준으로 **웹 위임 유지** 권고 |
| 9-3 | 딥링크 스킴: 커스텀 스킴 vs **웹 도메인 App Links/Universal Links** | 웹 도메인 채택(경로 스킴을 웹과 동일화, 결제 경로는 앱 라우트 표에 없어 자연 차단). 웹에 well-known 파일 배포 필요 |
| 9-4 | 읽기 뷰·self RPC 의 `api_web_v1` 직접 사용을 앱 계약에 **명문화**할지, `api_app_v1` 동명 복제로 갈지 | 명문화(뷰) + 쓰기·self RPC 는 `api_app_v1`(§4-3). `community_posts_v1` 은 앱 뷰로 전환 |
| 9-5 | iOS 번들 ID `com.ssambership.app` 유지 vs `.edu` 정렬 | 첫 업로드 전이면 `.edu` 정렬로 Android 와 통일 권고(계약 테스트 `:29`·Xcode·Firebase 등록 동시 갱신). **첫 업로드 후 변경 불가**. 업로드 이력 (확인 필요) |
| 9-6 | 서버 원격 플래그 RPC(`get_mobile_app_config`) 신설 여부 | 신설 권고(anon, fail-safe). 최소 `identity_gate_enabled` 는 필수 — 없으면 앱 게이트와 웹 게이트 불일치 |
| 9-7 | 로컬 `supabase/config.toml` 노출 스키마 확장(웹 저장소 변경) | 승인 권고 — 앱 개발이 운영 DB 로 몰리는 현 상태 해소 |
| 9-8 | 커뮤니티 본인 삭제를 DB-3 `soft_delete_own_content` 하나로 통일(기존 2 RPC 매니페스트 제거)할지 | 통일 권고(게시판 댓글·숏폼 글 본인 삭제 신규 획득). `community_comment_soft_delete_self`·`api_app_v1.community_post_soft_delete` 는 폐기 시점 웹 결정 |
| 9-9 | 본인인증·보호자 동의를 **WebView 위임(A)** 로 갈지 네이티브(B) | A(bootstrap target `identity_onboarding` + 학생 허용). B 는 NICE 복귀 URL·서버 전용 키 재설계 규모가 크다 |
| 9-10 | 가입을 앱 네이티브(`auth.signUp` + 메타)로 할지 웹 위임할지 | 네이티브 가능(트리거가 행 생성). 단 멘토 학생증 반영 RPC(`mentor_student_id_image_set_self`) 신설과 iOS PrivacyInfo(`Name` 등) 갱신 필요. 이메일 인증 ON/OFF (확인 필요) |
| 9-11 | 상태관리: 수동 스코프 DI(B) vs Riverpod(C) | B. C 는 §3-4-5 조건 충족 시 |
| 9-12 | 저장소 전략: 이력 보존 복제(B) vs `flutter create`(C) | B |
| 9-13 | 관리자 기능: 앱 차단 유지 vs WebView `/admin` 위임 | 차단 유지(`computeAccess` admin→blocked, bootstrap target 도 admin 불허) |
| 9-14 | `connection-note-ink` deprecated 버킷 상수·`connection_notes` 직접 CRUD 를 새 앱에 남길지 | 버킷 상수 제거(매니페스트에서 삭제), 연결노트는 RLS 직접 CRUD 유지 여부를 웹 RPC 존재 확인 후 결정 **(확인 필요)** |

---

## 10. 리스크·지뢰

1. **운영 DB 오인**: `ssambership-staging`(`lbeqxarxothkmzqvpudy`) 이 곧 운영(`HANDOFF.md:16`). 개발 루프가 이 DB 로 몰리는 구조(§4-2-5) — 로컬 노출 스키마 미설정 상태에서 "로컬에서 안 되니 원격으로" 가 반복될 수 있다.
2. **동명 함수 3스키마**: `qna_create_question_thread`·`community_post_*`·`ensure_free_question_room` 이 `public`/`api_app_v1`/`api_web_v1` 에 공존. `.schema()` 누락 → `public` 으로 나가 PGRST202 또는 raise 스타일 응답으로 바뀜. 매니페스트 키 `schema.name` 화 전까지 잡히지 않는다.
3. **봉투 혼재 확대**: DB-3 신설 함수가 `returns void`+raise 라 "신설 = envelope" 가정이 이미 깨져 있다. 앱 정규화 계층 없이 매퍼를 도메인별로 더 만들면 5벌 → 10벌.
4. **게이트 불일치**: `IDENTITY_GATE_ENABLED` 는 웹 서버 env. 앱이 `identity_verified_at` 만 보고 온보딩을 강제하면 웹 OFF 시 앱만 감금(또는 반대). DB/RPC 게이트는 웹 설계 원칙상 금지(`identityGate.ts:6-8`) — 앱 직접 쓰기 경로는 게이트 밖이므로 "앱에서는 인증 없이 CR 지원 가능" 같은 정책 구멍이 생긴다(웹 리포트 §6 #19).
5. **status allowlist 차이**: 앱 `resolve` 는 미지 status 를 active 취급(`account_status.dart:287-289`), 웹 앱 표면은 거부 — WebView 진입에서만 `account_blocked` 로 튕기는 사용자 발생.
6. **테스트 수 정확 일치 핀**(1,508)과 `SOURCE_SHA`·`EXPECTED_PR` 상수 — 워크플로 복사 즉시 실패. 계약 테스트 `:147` 도 함께.
7. **iOS PrivacyInfo 금지 집합**: 가입(실명)·전화·학생증·본인인증 데이터가 들어오면 `NSPrivacyCollectedDataTypeName` 등 금지 유형(`ios_release_config_contract_test.dart:54-62`)과 충돌 — 계약 테스트·매니페스트·Data safety 동시 갱신 없이는 빌드 게이트 실패 또는 심사 불일치.
8. **버전 정책 데이터**: 새 앱 출시 전 `store_url` 없이 `min_supported_build` 상향 시 구 앱이 스토어 안내를 못 한다([P1-db §7.1]). 실측 값 (확인 필요).
9. **구식 문서 지뢰**: `HANDOFF.md`(도메인 `ssambership-web.vercel.app` `:111`, FCM 코드 존재 서술 `:151-160`, 250개 테스트 `:199`, 네이티브 untracked `:169`), `README.md`(S0 스캐폴드), `docs/APP_V16_MIN_VERSION_SERVER_REQUIREMENT.md`(RPC 명), `docs/APP_V16_SERVER_CONTRACT_SNAPSHOT.md`(DB-1~3 이전). 새 저장소에 그대로 복사하면 계약 오독 재발(과거 앱 저장소 SQL 4건 사고와 동형 — `SCHEMA_SOURCE_OF_TRUTH.md`).
10. **역방향 의존 4건**(§3-1) 을 먼저 끊지 않으면 "코어 먼저 이식" 순서가 컴파일에서 막힌다.
11. **IndexedStack 상주 + 탭 증가**: 멘토 콘솔·CR 브랜치가 늘면 Realtime 채널·재조회 팬아웃이 다시 커진다(N12/N13 이 해결한 문제의 재발) — §1-4-7·§5 #5 규약 없이는 회귀.
12. **`register_device_token` GRANT 상태**: 헤더 "라이브 미적용" vs 증적 문서 "적용" 불일치 — 푸시 재도입 전 원장 대조 필수.
13. **자금 인접 RPC 가 authenticated 에 열려 있음**: 앱 코드가 부르지 않더라도 매니페스트 `kForbiddenWords` 에 넣어 회귀 차단(현재 `record_cash_topup`·`subscription_checkout_confirm` 만 금지어; `create_individual_question_as_student`·`release/refund_individual_question` 은 **허용 집합에 존재** — 9-1 결정 결과에 따라 금지어로 이동).
14. **AGP 9.0.1·Kotlin 2.3.20·Flutter 3.44.6 조합**은 현 저장소에서 검증된 상태 — `flutter create` 로 새 스캐폴드를 만들면 다른 버전 조합이 생성돼 검증이 무효화된다(안 C 비권고 근거).

---

## 11. 유지/일반화/교체 판정 총괄표

| 영역 | 자산 | 판정 | 비고 |
|---|---|---|---|
| 라우팅 | `GoRouter` 4라우트·`EntryGuard` 문자열 매트릭스·`HomeShell` 5탭·`AppTab`/`TabNavigator` int 채널·pop-int 핸드오프·`NotificationTargetOpener` | **교체** | 라우트 spec 테이블 + `StatefulShellRoute` + 역할 탭 spec + id 파라미터 상세 + `AppNavigator(sealed)` |
| 라우팅 | `EntryGuard.redirect` 순수 함수·전수표 테스트, `NotificationDeepLinkController`(UUID 검증·dedup·pending TTL), `VersionGateShell` 위치(Navigator 위) | **유지**(입력 형태만 일반화) | |
| 세션 | `computeAccess`/`computeRecoverableBlock`/N32 유지 판정, `AccountStatusReader.resolve` fail-closed, `DeletionNoticeController` 규약, `BlockedScreen` 계약 | **유지 + 확장** | `AccessState.onboarding`, `OnboardingNeed`, status allowlist, `deleted` |
| 세션 | 화면·레포 내부 `currentRole` switch 14곳 | **교체** | 역할별 라우트 + 인자 주입, registry 계약 테스트 |
| 세션 | `AuthService` 단일 클래스 | **일반화** | Session/Profile/AccessResolver 분리 + 파사드 게터 유지 |
| DI | 전역 `.instance` 싱글턴 5 + static 채널 | **교체** | `AppScope`/`Deps` |
| DI | `xxxOverride` 생성자 seam | **유지(전환기) → 축소** | 신설 화면 금지 |
| DI | 손코딩 Fake·`@visibleForTesting` 순수 함수·mock 금지 | **유지** | |
| DB | `api_app_v1` thin wrapper + `core_private` impl 패턴, 앱 저장소 SQL 금지, pack 3중 사본·`db-apply-pending`·hotfix 역수입 | **유지** | |
| DB | 읽기 `api_web_v1` 뷰 직접 사용 | **유지(계약 명문화)** | `community_posts_v1` 만 `api_app_v1` 로 |
| DB | 봉투 2스타일 처리 5벌 매퍼 | **일반화** | `RpcOutcome` + 코드 사전 |
| DB | `outbound_api_manifest_test` | **유지 + 개정** | 키 `schema.name`, 자금 RPC 금지어 |
| 인프라 | 첨부 업로드 코어·서명 URL 리졸버 4벌·Realtime 포트 3벌·`DataRefreshBus`·에러 매퍼·`model_parse` 2벌·페이지네이터·`AppConfig`·WebView 브릿지 표 | **일반화** | §5 #1·4·5·6·8·10·17·18 |
| 인프라 | downscale·PDF 래스터·scan/ink 코어·`ScreenVisibility`·`web_bridge`·버전 게이트·Sentry 부팅·`commerce_policy`·푸시 포트·라벨 매핑·Fake 모음 | **유지** | |
| 테스트·CI | `flutter-ci.yml`, analyze 파싱 게이트, `validate_release_env`, `ci_post_clone.sh`, contract 테스트 6종(상수 갱신) | **유지** | Flutter 3.44.6 핀 |
| 테스트·CI | 서명 워크플로(`SOURCE_SHA`·PR 고정·테스트 수 정확 일치) | **교체** | 태그 기반 릴리즈 워크플로, 검증 단계는 이식 |
| 테스트·CI | 앱 `docs/APP_V16_*` 계약 스냅샷 | **교체** | 웹 `contracts:export` 산출물 대조 |
| 저장소 | 네이티브 폴더·서명 스켈레톤·패키지/번들 계약·`pubspec.lock` 정책·의존성 집합 | **유지** | 이력 보존 복제 |
| 저장소 | HANDOFF/README 구식 절 | **교체** | 첫 커밋에서 재작성·아카이브 |
| 환경 | dart-define 3종·릴리즈 무주입 계약·`.env` 에셋 | **유지 + 일반화** | `FeatureFlags` 단일 표(releaseDefault) + `RemoteConfig`(신설 RPC, 결정) |
