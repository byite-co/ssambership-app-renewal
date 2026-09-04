# A-3 라우팅 기준선 및 경로 설계 — 2026-09-05

대상은 `byite-co/ssambership-app-renewal`의 `master` `36656057442c1f9162cc645351762fae93bd228d`에서 분기한 `codex/a3-routing-replacement-20260905`다. 이 문서는 A-3 1단계의 **현황 측정**과 2단계의 **경로 설계**만 기록한다. 이 측정 단계에서는 화면·라우터 코드를 고치지 않았다.

## 0. 실행 환경과 기준선

### OS·Git 줄바꿈

| 항목 | 실측값 |
|---|---|
| 호스트 | Microsoft Windows `10.0.26200` x64 · PowerShell `7.6.5` |
| Windows Git `core.autocrlf` | `file:C:/Program Files/Git/etc/gitconfig true` (global/local 설정 없음) |
| Linux 실행 환경 | WSL2 Ubuntu · `Linux 6.18.33.2-microsoft-standard-WSL2 x86_64 GNU/Linux` |
| Linux Git | `2.53.0` |
| 기준 작업 트리의 `core.autocrlf` | `file:.git/config false` |
| 기준 작업 트리 줄바꿈 표본 | `ios/Runner/Info.plist`, `test/contracts/outbound_api_manifest_test.dart` 모두 `i/lf w/lf` |

처음 Windows에서 실행한 `flutter analyze`는 error 0 · warning 0 · info 79였지만, `flutter test`는 **1,504 통과 · 20 실패**였다. 실패는 Linux 기준 골든과 다른 Windows 렌더링 14건, CRLF를 전제로 하지 않은 iOS XML 계약 4건, CRLF에서 주석 제거가 되지 않은 소스 문자열 검사 2건이었다. 따라서 Windows 결과는 A-3 회귀 기준선으로 쓰지 않고, 공식 Linux SDK와 LF 체크아웃으로 다시 측정했다.

`.env.example`은 로컬에서 `.env`로 복사했다. `git check-ignore -v .env`는 `.gitignore:21:.env`를 반환하므로 커밋 대상이 아니다. 이 준비 순서는 이미 `docs/renewal/baseline-2026-09-04.md`에 적혀 있다.

### Flutter SDK

공식 Linux Flutter 3.44.6 stable 아카이브를 `/var/tmp/codex-a3/flutter`에 설치했고, 별도 pub cache `/var/tmp/codex-a3/pub-cache`를 사용했다.

```text
Flutter 3.44.6 • channel stable • https://github.com/flutter/flutter.git
Framework • revision ee80f08bbf (8 weeks ago) • 2026-07-08 15:02:06 -0700
Engine • hash d3a3293399556a85388faf8c6f0723a7a5597aa8 (revision 83675ed276) (2 months ago) • 2026-06-30 16:59:03.000Z
Tools • Dart 3.12.2 • DevTools 2.57.0
```

### 세 기준 명령

모두 WSL2의 LF 작업 트리에서 실행했다.

```bash
export PUB_CACHE=/var/tmp/codex-a3/pub-cache
cd /mnt/c/Users/testos_01/Documents/Codex/2026-09-05/files-mentioned-by-the-user-codex/work/linux/ssambership-app-renewal
/var/tmp/codex-a3/flutter/bin/flutter pub get
/var/tmp/codex-a3/flutter/bin/flutter analyze
/var/tmp/codex-a3/flutter/bin/flutter test
```

판정에 사용한 실제 출력은 다음과 같다.

```text
$ flutter pub get
Resolving dependencies...
Downloading packages...
Got dependencies!
63 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.

$ flutter analyze
Analyzing ssambership-app-renewal...
79 issues found. (ran in 20.9s)

$ flutter test
00:56 +1524: All tests passed!
```

`flutter analyze`의 79건은 모두 info이고 **error 0 · warning 0 · info 79**다. `flutter pub get` 성공, analyze 기대값 일치, 테스트 **1,524건 통과**로 A-3 진행 조건을 충족한다. Linux 골든 14장도 전부 일치했다.

## 1. 현재 라우트 전수

`lib/app/router.dart`의 등록 라우트는 운영 4개, 개발 빌드 조건부 2개다. `/` 자체는 등록되어 있지 않다.

| 구분 | 경로 | 화면 | 경로 상수 | `GoRoute` 정의 |
|---|---|---|---|---|
| 운영 | `/splash` | `SplashScreen` | `lib/app/entry_guard.dart:14` | `lib/app/router.dart:26` |
| 운영 | `/login` | `LoginScreen` | `lib/app/entry_guard.dart:15` | `lib/app/router.dart:30` |
| 운영 | `/home` | `HomeShell` | `lib/app/entry_guard.dart:16` | `lib/app/router.dart:34` |
| 운영 | `/blocked` | `BlockedScreen` | `lib/app/entry_guard.dart:17` | `lib/app/router.dart:38` |
| 개발 조건부 | `/dev/gallery` | `WidgetGallery` | `lib/app/entry_guard.dart:18` | `lib/app/router.dart:44` |
| 개발 조건부 | `/dev/s3` | `S3DataInspector` | `lib/app/entry_guard.dart:19` | `lib/app/router.dart:49` |

`AppRouter.router`는 정적 단일 인스턴스이고 `refreshListenable`과 redirect의 access 입력에서 `AuthService.instance`를 각각 한 번 직접 읽는다(`lib/app/router.dart:18-22`). `EntryGuard.redirect`는 full/guest 사용자가 정확히 `/home`에 있을 때만 현재 위치를 허용하므로, 상세 URL을 추가할 때 보호 경로 prefix와 역할을 이해하도록 함께 바꿔야 한다.

## 2. 현재 탭 구성과 전환

현재 탭은 역할과 무관하게 다음 한 배열로 고정되어 있다.

| 현재 표시 인덱스 | `AppTab` | 라벨 | 화면 |
|---:|---|---|---|
| 0 | `questionRoom` | 질문방 | `QuestionRoomScreen` |
| 1 | `community` | 커뮤니티 | `CommunityScreen` |
| 2 | `mentors` | 멘토 찾기 | `MentorsScreen` |
| 3 | `notifications` | 알림 | `NotificationsScreen` |
| 4 | `individualQuestion` | 개별질문 | `IndividualQuestionTabScreen` |

- 인덱스 상수: `lib/app/app_tabs.dart:10-14`
- 라벨 배열: `lib/shared/constants/app_constants.dart:24-30`
- 화면 배열: `lib/app/home_shell.dart:50-56`
- 전환: `NavigationBar.onDestinationSelected` → `_onSelect` → `_index` 변경(`lib/app/home_shell.dart:100-116,175-186`)
- 렌더링: 방문 탭만 처음 만들고 `IndexedStack`에 유지한다(`lib/app/home_shell.dart:44-55,158-170`).
- 게스트는 현재 인덱스 2(멘토 찾기)에서 시작하고, `{1, 2}` 즉 커뮤니티·멘토 찾기만 허용한다(`lib/app/home_shell.dart:72`, `lib/app/entry_guard.dart:25-28`).
- 마이페이지는 하단 탭이 아니라 `AppTab.myPage = 100` 가상 목적지와 AppBar 프로필 버튼이 여는 `MaterialPageRoute`다.
- `TabNavigator.request` 정적 `ValueNotifier<int>`가 알림 딥링크 등의 숫자 인덱스를 셸에 전달한다. URL이 아니라 표시 순서에 결합되어 있어 역할별 탭 순서와 함께 경로 기반 요청으로 바꿀 대상이다.

A-3 목표 표시 순서는 학생 `질문방 · 개별질문 · 멘토찾기 · 커뮤니티 · 알림`, 멘토 `질문방 · 개별질문 · 정산 · 커뮤니티 · 알림`이다. 화면 상태 보존(lazy build + 살아 있는 탭)은 그대로 유지하되, 선택 상태의 정본은 숫자 위치가 아니라 현재 URL이어야 한다.

## 3. `GoRouterState.of(context)` 전수

운영 `lib/`에서 **1곳**이다.

| 위치 | 읽는 값 | 영향 | A-3 방향 |
|---|---|---|---|
| `lib/features/auth/login_screen.dart:71` | `uri.queryParameters['notice']` | `build`가 라우터 조상에 의존해, 일반 `MaterialApp` 골든 하네스에서는 예외가 난다 | `/login?notice=...` 계약은 유지하고 최소 GoRouter 골든 하네스로 렌더한다 |

## 4. `MaterialPageRoute` 전수와 ID 전환 판정

현재 커밋에서 `rg -n --glob '*.dart' MaterialPageRoute lib`를 다시 실행한 결과는 **44곳 / 26파일**이다. A-3 지시문의 46곳과 **2건 불일치**한다. 46을 맞추기 위해 주석·테스트·`context.go`를 더하지 않았으며, 이 커밋에서 재현 가능한 raw 호출 수 44를 기준으로 아래에 전수 기록한다.

44곳의 전달값 성격을 상호배타적으로 세면 영속 도메인 모델 25곳, 로컬·일시 객체 8곳, 이미 ID-only 4곳, 모델 없음 또는 scalar+DI 객체만 7곳이다. 판정 기준은 다음과 같다.

- **가능**: URL에는 안정 ID만 넣고, 화면 진입 어댑터가 `AppScope`의 레포에서 모델·이름·권한·찜 상태를 다시 읽을 수 있다. 인자가 없거나 이미 ID만 받는 화면도 포함한다.
- **조건부**: 원본 ID는 있지만 결과가 부모 화면의 미저장 상태/callback으로 돌아가므로, ID 조회만 바꾸면 동작 계약이 완성되지 않는다. A-3에서 억지로 분리하지 않고 workflow 예외로 남긴다.
- **불가**: 파일 선택 직후의 메모리 bytes, 열린 `PdfDocument`, 아직 저장되지 않은 ink처럼 현재 서버 ID가 없는 세션 내부 편집 단계다. 이는 사용자에게 독립 URL을 약속할 영속 화면이 아니라 부모 흐름에 결과를 돌려주는 modal workflow다.

| # | 호출 위치 → 대상 | 현재 전달값 | ID만으로 대체 | 제안 키/비고 |
|---:|---|---|---|---|
| 1 | `lib/app/home_shell.dart:130` → `_MyPagePage` | 테스트용 `loaderOverride` callback(운영은 null) | 가능 | `/me`; 데이터는 `AppScope.myPage` |
| 2 | `lib/core/scan/widgets/scan_pick_expander.dart:49` → `PdfPageSelectScreen` | 열린 `PdfDocument`, `baseName`, 선택 한도 | **불가** | 파일 picker 세션에 귀속된 PDF handle |
| 3 | `lib/features/community/community_screen.dart:87` → `BoardWriteScreen` | write repository | 가능 | `/community/boards/new`; repository는 `AppScope` |
| 4 | `lib/features/community/ui/activity/my_activity_view.dart:139` → `BoardDetailScreen` | `BoardPost post`, read/write repositories | 가능 | `post.id` |
| 5 | `lib/features/community/ui/board/board_detail_screen.dart:251` → `BoardWriteScreen` | write repository, `editing: BoardPost` | 가능 | `post.id` + `/edit` |
| 6 | `lib/features/community/ui/board/board_list_view.dart:156` → `BoardDetailScreen` | `BoardPost post`, read/write repositories | 가능 | `post.id` |
| 7 | `lib/features/community/ui/shortform/shortform_feed_view.dart:166` → `ShortformComposeScreen` | 없음 | 가능 | `/community/shortforms/new` |
| 8 | `lib/features/community/ui/shortform/shortform_feed_view.dart:183` → `ShortformDetailScreen` | shortform post, read/write repositories | 가능 | `post.id` |
| 9 | `lib/features/individual_question/ui/iq_create_screen.dart:233` → `ScanAnnotationScreen` | 로컬 image bytes, `InkDocument`, `AnnotationTarget` | **불가** | 업로드 전 로컬 초안; `IqCreateScreen` 자체도 운영 진입 금지 계약 |
| 10 | `lib/features/individual_question/ui/iq_detail_screen.dart:586` → `ScanAnnotationScreen` | 다운로드한 bytes, 기존 ink, 로컬 결과 target | **조건부** | 원본은 `questionId` + attachment ID로 복원 가능하나 결과가 부모 pending-upload 메모리로 돌아감 |
| 11 | `lib/features/individual_question/ui/iq_detail_screen.dart:635` → `ScanAnnotationScreen` | 업로드 전 bytes, 기존 ink, 로컬 결과 target | **불가** | 아직 영속 ID가 없는 첨부 초안 |
| 12 | `lib/features/individual_question/ui/iq_detail_screen.dart:1499` → `_IqAttachmentViewer` | signed URL, 제목, annotate callback | **조건부** | `IqAttachment.id`는 있으나 callback을 부모 상태에서 분리해야 독립 URL 진입 가능 |
| 13 | `lib/features/individual_question/ui/mentor_iq_list_screen.dart:137` → `IqDetailScreen` | `questionId` | 가능(이미 ID) | `questionId` |
| 14 | `lib/features/individual_question/ui/mentor_iq_list_screen.dart:154` → `IqDetailScreen` | `questionId` | 가능(이미 ID) | `questionId` |
| 15 | `lib/features/individual_question/ui/student_iq_list_screen.dart:105` → `IqDetailScreen` | `questionId` | 가능(이미 ID) | `questionId` |
| 16 | `lib/features/mentors/mentors_screen.dart:350` → `MentorDetailScreen` | `MentorListItem`, `initialFavorited` | 가능 | `mentorId`; 상세·찜 상태 재조회 |
| 17 | `lib/features/mentors/ui/widgets/free_question_entry_section.dart:141` → `FreeQuestionComposeScreen` | `roomId`, `mentorName`, port | 가능 | `roomId`; 이름 재조회, port는 `AppScope` |
| 18 | `lib/features/mypage/mypage_screen.dart:188` → `ProfileEditScreen` | `MyProfile profile` | 가능 | 로그인 사용자 정본; `/me/profile` |
| 19 | `lib/features/mypage/ui/sections/settings_section.dart:117` → `AccountDeleteScreen` | 없음 | 가능 | `/me/account-deletion` |
| 20 | `lib/features/mypage/ui/sections/settings_section.dart:254` → `BlockedUsersScreen` | 없음 | 가능 | `/me/blocked-users` |
| 21 | `lib/features/notifications/ui/notification_target_opener.dart:108` → `MentorAnswerScreen` | `QuestionThread`, `Room`, 학생 이름 | 가능 | `roomId` + `threadId` |
| 22 | `lib/features/notifications/ui/notification_target_opener.dart:115` → `StudentRoomHomeScreen` | `Room`, 학생 이름 | 가능 | `roomId` |
| 23 | `lib/features/notifications/ui/notification_target_opener.dart:138` → `ChatScreen` | `QuestionThread`, `Room`, 멘토 이름 | 가능 | `roomId` + `threadId` |
| 24 | `lib/features/notifications/ui/notification_target_opener.dart:145` → `MentorRoomHomeScreen` | `Room`, 멘토 이름 | 가능 | `roomId` |
| 25 | `lib/features/notifications/ui/notification_target_opener.dart:160` → `IqDetailScreen` | `questionId` | 가능(이미 ID) | `questionId` |
| 26 | `lib/features/notifications/ui/notification_target_opener.dart:172` → `BoardDetailScreen` | 조회한 `BoardPost`, read/write repositories | 가능 | 알림의 `postId`; 중복 선조회 제거 |
| 27 | `lib/features/notifications/ui/notification_target_opener.dart:188` → `ShortformDetailScreen` | 조회한 shortform post, read/write repositories | 가능 | 알림의 `postId`; 중복 선조회 제거 |
| 28 | `lib/features/notifications/ui/notification_target_opener.dart:204` → `MentorDetailScreen` | 조회한 `MentorListItem` | 가능 | 알림의 `mentorId` |
| 29 | `lib/features/question_room/question_room_screen.dart:286` → `MentorRoomHomeScreen` | `Room`, 멘토 이름, `SubscriptionSummary` | 가능 | `roomId`; 나머지는 병렬 재조회 |
| 30 | `lib/features/question_room/ui/attachment_viewer_screen.dart:54` → `ScanAnnotationScreen` | 다운로드한 bytes, `roomId`, `threadId` | **조건부** | attachment ID로 원본은 복원 가능하나 결과 bool을 뷰어→채팅으로 연쇄 반환 |
| 31 | `lib/features/question_room/ui/chat_screen.dart:295` → `AttachmentViewerScreen` | `QuestionAttachment`, room/thread IDs, URL resolver | 가능 | `roomId` + `threadId` + `attachmentId` |
| 32 | `lib/features/question_room/ui/chat_screen.dart:460` → `ScanAnnotationScreen` | 전송 전 `PickedImage.bytes`, room/thread IDs | **불가** | 아직 영속 ID가 없는 대기 첨부 |
| 33 | `lib/features/question_room/ui/mentor_room_home_screen.dart:159` → `QuestionListScreen` | `Room`, 멘토 이름, `SubscriptionSummary` | 가능 | `roomId` |
| 34 | `lib/features/question_room/ui/mentor_room_home_screen.dart:172` → `ConnectionNotesScreen` | `Room`, 멘토 이름 | 가능 | `roomId` |
| 35 | `lib/features/question_room/ui/question_list_screen.dart:195` → `NewQuestionScreen` | `Room` | 가능 | `roomId` + `/threads/new` |
| 36 | `lib/features/question_room/ui/question_list_screen.dart:204` → `ChatScreen` | `QuestionThread`, `Room`, 멘토 이름 | 가능 | `roomId` + `threadId` |
| 37 | `lib/features/question_room/ui/question_list_screen.dart:217` → `ConnectionNotesScreen` | `Room`, 멘토 이름 | 가능 | `roomId` |
| 38 | `lib/features/question_room/ui/mentor/mentor_answer_screen.dart:280` → `AttachmentViewerScreen` | `QuestionAttachment`, room/thread IDs, URL resolver | 가능 | `roomId` + `threadId` + `attachmentId` |
| 39 | `lib/features/question_room/ui/mentor/mentor_answer_screen.dart:447` → `ScanAnnotationScreen` | 전송 전 `PickedImage.bytes`, room/thread IDs | **불가** | 아직 영속 ID가 없는 대기 첨부 |
| 40 | `lib/features/question_room/ui/mentor/mentor_inbox_screen.dart:219` → `StudentRoomHomeScreen` | `Room`, 학생 이름 | 가능 | `roomId` |
| 41 | `lib/features/question_room/ui/mentor/mentor_question_list_screen.dart:224` → `MentorAnswerScreen` | `QuestionThread`, `Room`, 학생 이름 | 가능 | `roomId` + `threadId` |
| 42 | `lib/features/question_room/ui/mentor/student_room_home_screen.dart:208` → `MentorQuestionListScreen` | `Room`, 학생 이름 | 가능 | `roomId` |
| 43 | `lib/features/question_room/ui/mentor/student_room_home_screen.dart:222` → `ConnectionNotesScreen` | `Room`, 학생 이름 | 가능 | `roomId` |
| 44 | `lib/shared/widgets/withdrawal_pending_banner.dart:94` → `AccountDeleteScreen` | 없음 | 가능 | `/me/account-deletion` |

합계는 **바로 ID/URL 전환 가능 36 · 조건부 3 · 현재 불가 5 = 44**다. 조건부와 불가를 합친 workflow 예외 8곳은 URL identity를 가진 도메인 모델을 넘기는 일반 상세 전환이 아니라 열린 파일/bytes/ink와 callback을 주고받는 편집 modal이다. 이 8곳도 의존성 객체는 `AppScope`에서 받도록 정리하되, 영속 draft ID와 반환 계약이 생기기 전까지는 `MaterialPageRoute`를 억지로 URL화하지 않는다. 반면 영속 도메인 모델 전달 25곳은 기존 조회 API만으로 전부 ID 전환 가능하다.

## 5. A-3 경로 체계

### 설계 원칙

1. URL에는 `Room`, `QuestionThread`, post, mentor 등의 객체나 `$extra`를 넣지 않는다. 안정 ID는 path parameter, 화면 표시 상태처럼 identity가 아닌 값은 제한적으로 query parameter를 쓴다.
2. 라우트 builder/loader는 `AppScope`에서 레포를 받아 ID로 정본을 읽은 뒤 기존 presentation widget을 그린다. 이름·구독·찜 여부도 전달된 snapshot이 아니라 진입 시점 정본을 쓴다.
3. 최상위 탭은 role-aware shell 아래 독립 URL을 갖는다. URL prefix가 선택 탭의 정본이고, 역할별 배열은 표시 순서만 결정한다.
4. 상세 화면은 root navigator에 쌓아 현재와 같은 전체 화면 push/뒤로가기를 유지한다. 완료 결과로 돌려주는 `bool`·작은 enum은 모델 객체가 아니므로 허용한다.
5. `/home`은 기존 호출·외부 링크 호환을 위한 redirect alias로만 남기고 새 canonical URL을 만들지 않는다.
6. 보호·게스트·역할 redirect는 exact `/home` 비교가 아니라 route metadata/prefix를 기준으로 판정한다. 잘못된 ID, 조회 권한 없음, 없는 행은 다른 모델을 추측하지 않고 명시적 오류/목록 복귀로 처리한다.

### 진입·셸·탭

| 경로 | 역할/화면 | 비고 |
|---|---|---|
| `/` | access/role에 따른 진입 redirect | full 학생·멘토 → `/rooms`, guest → `/mentors`; loading/login/blocked는 기존 가드 유지 |
| `/splash` | `SplashScreen` | 기존 경로 유지 |
| `/login?notice=...` | `LoginScreen` | 기존 경로·notice query 유지 |
| `/blocked` | `BlockedScreen` | 기존 경로 유지 |
| `/onboarding` | `OnboardingScreen` | 현재 등록되지 않은 기존 자리 화면을 URL로 노출 |
| `/home` | canonical 탭으로 redirect | 호환 alias; 새 링크에서는 사용하지 않음 |
| `/rooms` | `QuestionRoomScreen` | 학생 탭 1 · 멘토 탭 1 |
| `/iq` | `IndividualQuestionTabScreen` | 학생 탭 2 · 멘토 탭 2 |
| `/mentors` | `MentorsScreen` | 학생 탭 3, guest 허용; 멘토 탭에는 노출하지 않아도 deep URL은 유효 |
| `/settlements` | 멘토 역할의 기존 `MyPageScreen` 정산/답변 요약 | 멘토 탭 3. 새 화면을 만들지 않고 현재 멘토 정산 조회 표면을 재사용 |
| `/community` | `CommunityScreen` | 양 역할 탭 4, guest 허용 |
| `/notifications` | `NotificationsScreen` | 양 역할 탭 5 |

역할별 표시 순서와 URL은 다음으로 고정한다.

| 역할 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| 학생 | `/rooms` | `/iq` | `/mentors` | `/community` | `/notifications` |
| 멘토 | `/rooms` | `/iq` | `/settlements` | `/community` | `/notifications` |

### 질문방

| 경로 | 화면 | ID loader |
|---|---|---|
| `/rooms/:roomId` | 학생이면 `MentorRoomHomeScreen`, 멘토이면 `StudentRoomHomeScreen` | room, 상대 이름, 구독 요약을 `roomId`로 조회 |
| `/rooms/:roomId/threads` | 학생이면 `QuestionListScreen`, 멘토이면 `MentorQuestionListScreen` | room + threads + 상대 이름 |
| `/rooms/:roomId/threads/new` | `NewQuestionScreen` | room; 학생만 허용 |
| `/rooms/:roomId/threads/:threadId` | 학생이면 `ChatScreen`, 멘토이면 `MentorAnswerScreen` | room + thread를 각각 ID로 조회하고 소속 일치 검증 |
| `/rooms/:roomId/notes` | `ConnectionNotesScreen` | room + 상대 이름 |
| `/rooms/:roomId/threads/:threadId/attachments/:attachmentId` | `AttachmentViewerScreen` | room/thread 소속을 검증한 attachment + resolver |
| `/rooms/:roomId/free-question` | `FreeQuestionComposeScreen` | 진입 전에 확보한 room ID로 room·멘토 이름 조회; student만 허용 |

알림 대상 오프너는 먼저 모델을 읽고 화면을 직접 만들지 않는다. 알림 payload의 검증된 ID로 위 canonical URL을 만들고 router에 넘기며, 실제 조회와 소속/권한 검증은 목적지 loader 한 곳에서 한다.

### 개별질문·멘토

| 경로 | 화면 | ID loader/계약 |
|---|---|---|
| `/iq/:questionId` | `IqDetailScreen` | 이미 `questionId`를 받으므로 그대로 사용 |
| `/mentors/:mentorId` | `MentorDetailScreen` | 목록 item과 현재 사용자의 찜 상태 재조회 |

`IqCreateScreen`은 production 생성자 호출 0과 네이티브 등록 경로 0을 `test/contracts/iq_create_boundary_test.dart`가 잠근 상태다. 따라서 A-3에서 `/iq/new`를 등록하지 않는다. 아래 future slot만 예약하고 실제 개방은 계약을 의도적으로 바꾸는 A-4 이후 작업이다.

### 커뮤니티

| 경로 | 화면 | ID loader |
|---|---|---|
| `/community/boards/new` | `BoardWriteScreen` | ID 없음; write port는 `AppScope` |
| `/community/boards/:postId` | `BoardDetailScreen` | board post + read/write ports |
| `/community/boards/:postId/edit` | `BoardWriteScreen(editing: ...)` | board post를 ID로 조회; 수정 권한 재검증 |
| `/community/shortforms/new` | `ShortformComposeScreen` | ID 없음; 현재 기존 화면/브릿지 계약 유지 |
| `/community/shortforms/:shortformId` | `ShortformDetailScreen` | shortform post + read/write ports |

### 마이페이지·설정

| 경로 | 화면 | loader |
|---|---|---|
| `/me` | 기존 마이페이지 route wrapper + `MyPageScreen` | 로그인 사용자 정본 |
| `/me/profile` | `ProfileEditScreen` | 로그인 사용자 profile 재조회 |
| `/me/account-deletion` | `AccountDeleteScreen` | 로그인 사용자·삭제 예약 정본 |
| `/me/blocked-users` | `BlockedUsersScreen` | 로그인 사용자의 차단 목록 |

### 개발 경로

`/dev/gallery`와 `/dev/s3`는 현재처럼 `kDevToolsEnabled`일 때만 등록하고 가드 예외를 유지한다. release에서 URL로 노출하지 않는다.

## 6. Future slots — 이번에는 등록·구현하지 않음

향후 화면이 추가돼도 기존 resource path와 충돌하지 않도록 다음 자리를 예약한다.

| 예약 경로 | 향후 기능 | 이번 A-3 처리 |
|---|---|---|
| `/iq/new` | 네이티브 개별질문 등록 | **미등록** — 현재 IQ create boundary 계약 유지 |
| `/me/subscriptions` | 내 구독 목록/관리 | 미등록 |
| `/me/subscriptions/:subscriptionId/cancel` | 구독 해지 | 미등록 |
| `/me/cash` | 캐시 내역·충전 표면 | 미등록 |
| `/me/refunds/new` | 환불 신청 | 미등록 |
| `/me/refunds/:refundId` | 환불 신청 상태 | 미등록 |
| `/settlements/account` | 멘토 정산 계좌 | 미등록 |
| `/settlements/history` | 멘토 정산 내역 | 미등록 |
| `/profile/plans` | 멘토 요금제 설정 | 미등록 |
| `/profile/education-verification` | 학력 인증 | 미등록 |

예약은 문서상의 namespace 약속일 뿐이다. A-3에서 placeholder route나 새 화면을 만들지 않는다.

## 7. URL 대상에서 제외하는 workflow와 비화면 위젯

다음은 “모든 화면을 URL로”의 대상이 되는 독립 영속 화면과 구분한다.

- `PdfPageSelectScreen`: file picker가 연 `PdfDocument` handle과 부모에게 반환할 `List<PickedImage>`가 필요하다.
- `ScanAnnotationScreen`: 호출마다 아직 업로드되지 않은 bytes/ink 및 `AnnotationTarget`/부모 pending 상태를 입출력한다. 현재 6개 호출(#9, #10, #11, #30, #32, #39)은 독립 cold URL로 복원할 완전한 identity가 없다.
- `_IqAttachmentViewer`: 영속 `IqAttachment.id`는 있지만 만료되는 signed URL과 부모의 `onAnnotate` closure로 구성된 내부 modal이다. callback을 부모 상태에서 분리하기 전에는 `/iq/:questionId` 안의 transient viewer로 유지한다.
- `IqCreateScreen`: 화면 코드는 남아 있지만 계약상 production 진입이 닫힌 dormant 화면이다. `/iq/new`는 예약만 한다.
- `EmptyScreen`: title/subtitle로 조합하는 디자인 공용 위젯이지 route destination이 아니다.

영속 draft/resource ID를 서버나 로컬 저장소에 도입하는 후속 작업이 생기면 `/drafts/:draftId/...` 식으로 workflow URL화를 재검토할 수 있다. A-3에서는 화면 동작과 데이터 계층을 바꾸지 않기 위해 위 예외를 유지한다.

## 8. 구현 순서에 대한 측정 결론

1. `AppRouter`를 `AppDependencies`로 생성해 `router.dart`의 `AuthService.instance` 2곳을 먼저 없앤다.
2. role-aware shell과 위 canonical path 상수를 세우고 `/home`·숫자 기반 `TabNavigator` 호출을 경로로 수렴한다.
3. 표의 바로 전환 가능한 36곳을 화면 단위로 바꾼다. route loader가 ID로 모델을 가져오고 화면에는 기존 표시용 모델을 건네는 중간 adapter는 허용하되, 호출부는 모델 객체를 push하지 않는다.
4. 세션 workflow 예외 8곳(조건부 3 + 불가 5)은 목록을 유지하고, 해당 화면의 repository/resolver/target 기본 생성만 `AppScope` seam으로 정리한다.
5. 탭 순서 변경은 별도 커밋과 별도 골든 갱신으로 격리한다.
6. `GoRouterState.of(context)`가 필요한 로그인은 최소 router harness로 학생·멘토 골든을 추가한다.

각 화면 커밋 뒤 Linux Flutter 3.44.6에서 전체 `flutter test`를 실행한다. 탭 순서 커밋 외 기존 골든 14장은 픽셀 불변이어야 하며, 계약 상수 RPC 32 · 테이블/뷰 24 · 버킷 6도 바꾸지 않는다.
