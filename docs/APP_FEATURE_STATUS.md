# APP_FEATURE_STATUS — 앱 전 기능 실제 작동 점검 (실코드 근거)

> 목적: 앱(C:\dev\ssambership_app) 하단 5탭의 모든 기능이 **실제로 구현·작동하는지** 코드로 판정.
> 판정: **완전작동 / 부분구현 / 미완·스텁 / 깨짐**. 근거는 실제 파일:라인(Supabase 쿼리 연결·버튼 배선·스텁 마커).
> 이번 턴 **코드 수정 0**(점검·문서만). 색 토큰 미터치. 작성일: 2026-07-02.
> 방법: 탭별 read-only 코드 탐색 5건 + 스텁 마커 grep + 기존 docs(FEATURE_AUDIT·CANON_SYNC_TODO) 대조.

---

## 🆕 2026-07-06 하단 탭 개편 + 연결노트 필기 제거 (PR #12)

- **하단 5탭 개편**: `질문방 · 커뮤니티 · 멘토찾기 · 알림 · 개별질문`. **마이페이지는 하단 탭에서 빠져 AppBar 우측 상단 원형 프로필 아이콘(push)** 으로 진입한다(`home_shell.dart`). 알림 딥링크의 `AppTab.myPage` 는 가상 목적지(=100)로 유지 — HomeShell 이 탭 전환 대신 push 처리.
- **개별질문 탭 승격**: `IndividualQuestionTabScreen` 신설(role 따라 기존 학생/멘토 목록 embedded 재사용). 마이페이지의 중복 진입 섹션 제거. 개별질문 알림 딥링크는 개별질문 탭(`AppTab.individualQuestion`)으로 향한다.
- **연결노트 필기 제거**: 아래 표들의 "연결노트 필기 완전작동" 판정은 이 시점부로 **제거됨** — 자유 캔버스 필기는 오구현 판단, 필기는 '문제 스캔 위 첨삭'으로 질문방·개별질문에 배치 예정(**docs/SCAN_INK_PLAN.md** 참고). `ink_note/` 모듈 삭제, 공용 `InkToolbar` 는 `lib/core/ink/widgets/` 로 이동(S15 주석이 계속 사용). 버킷 `connection-note-ink` 는 신규 쓰기 중단(기존 객체 보존), `connection_notes.ink_path/ink_thumb_path` 컬럼·모델 필드는 웹 호환 위해 유지(UI 미참조).

---

## 🆕 2026-07-06(2차) 실태 정정 — 웹 브릿지 확정 + 컴플라이언스 반영 (QA-05 처리)

QA 감사(docs/QA_REPORT_2026-07.md QA-05)에서 이 문서의 스테일 판정이 확인되어 아래를 정정한다. **아래 표들의 취소선/정정 표기가 우선한다.**

- **웹 브릿지 동작**: `baseUrl` 은 더 이상 미설정이 아니다 — **운영 도메인 확정(2026-07, `https://ssambership-web.vercel.app`)**. `web_bridge_config.dart` 는 `String.fromEnvironment('WEB_BASE_URL', defaultValue: <운영 도메인>)` 구조로, 릴리즈는 주입 없이 동작하고 스테이징 테스트는 dart-define 오버라이드. 구독관리·정산·약관·개인정보·지원 버튼은 **실제 웹을 연다**.
- **가격 표시·구독하기 버튼**: 컴플라이언스 커밋 `5002c1d` 로 **앱 내 가격 UI·구매 유도 CTA 가 제거**됨(멘토 카드·상세는 `CommerceNoticeCard` 안내만). "가격 표시 완전작동"/"구독하기 버튼 부분구현" 판정은 폐기.
- **숏폼 좋아요/스크랩**: 초기 상태 로드가 **이미 구현**됨(`shortform_detail_screen.dart:46-61` `_loadReactionState`). "항상 꺼져 보임" 판정은 폐기(과소 서술).
- **설정 약관·개인정보**: `openTermsWeb`/`openPrivacyWeb` 배선 완료(`settings_section.dart:87-92`) + 도메인 확정 → **열람 가능**.
- **설정 알림 토글**: 순수 "로컬 상태만"이 아니라 `NotificationSettingsRepository` 배선 존재. **[정정 2026-07-26]** 정본 테이블 `notification_settings`(`push_enabled` bool · `groups` jsonb)에서 로드/저장하는 **구현 완료** 상태다 — 서버 컬럼 대기가 아니다. 로드 실패는 기본값(전부 ON)으로 위장하지 않고 '다시 시도'를, 저장 실패는 원복 + 재시도 스낵바를 노출한다(`settings_section.dart:64-111`, `notification_settings_repository.dart:6-16`).
- **개별질문 작성 스위치(A안, 2026-07 확정)**: `kIndividualQuestionCreateEnabled` 는 컴파일 타임 주입(`--dart-define=IQ_CREATE_ENABLED=true`)으로 전환, **스토어 빌드 기본 off**. 목록·상세·답변 확인은 유지. 게이트: docs/PLAY_STORE_REVIEW_PLAN.md.

---

## 🆕 2026-07-02 구현 배치(부족 기능 12건) — 결과

무인 배치로 아래를 구현·커밋(각 독립 커밋, 각 커밋 전 flutter test·analyze 통과). **DB·Storage 변경 0, color_tokens 미터치.**

| # | 작업 | 상태 | 비고(인프라 의존) |
|---|---|---|---|
| 1 | 질문 이미지 첨부 | ✅ 선택 동작 / 업로드 graceful | **버킷 필요**: `question-attachments`(+방참여자 정책) 생성 후 `attachment_upload.dart:96 _storageReady=true` |
| 2 | 알림 설정 토글 저장 | ✅ 완료 | **[정정 2026-07-26]** 정본 테이블 `notification_settings`(`user_id` PK·`push_enabled` bool·`groups` jsonb·`updated_at`) + RLS `select_own`/`modify_own` **기존재** — 추가 컬럼·인프라 대기 없음 |
| 3 | 프로필 수정 | ✅ 동작 | `users.nickname`·`grade_level` update(본인 RLS) — 이미 있으면 즉시 작동 |
| 4 | 멘토찾기→질문방 탭 전환 | ✅ 동작 | TabNavigator 사용, 인프라 불필요 |
| 5 | 커뮤니티 조회수 증분 | ✅ graceful | **RPC 필요/확인**: `increment_community_post_view`·`increment_shortform_post_view`(웹 사용중) |
| 6 | 커뮤니티 페이징·무한스크롤 | ✅ 동작 | 게시판·숏폼 완성. 댓글은 repo 파라미터만 준비(UI는 기존) |
| 7 | 숏폼 반응 초기 로드 | ✅ 동작 | `shortform_reactions` 조회 |
| 8 | 질문방 목록 주간 잔여 표시 | ✅ 동작 | RPC `get_weekly_question_usage` |
| 9 | 연결노트 진입 위치 | ✅ 이미 충족 | 오너 체크포인트(AppBar 라벨 버튼)+허브 EntranceCard. 별도 커밋 없음 |
| 10 | 구독 status 세분화 | ✅ 동작 | 정본 라벨(이용 중/결제 확인 필요/해지됨/만료됨/환불됨/대기 중). 표시만 |
| 11 | 커뮤니티 라벨·순서 정본 | ✅ 동작 | study='학습법', 순서 study·school·career·college·free |
| 12 | 알림 딥링크·분류 정본 | ✅ 동작(분류) | 정본 키워드 관대 매칭. 딥링크는 탭 라우팅(푸시 인프라 미접촉) |

### ★ 오너가 Supabase에서 만들어야 할 인프라(아침에 바로) — 이 배치가 '준비되면 자동 작동'하도록 짜둠
1. **[작업1] Storage 버킷 `question-attachments`** + '방 참여자만 read/write' 정책 → 생성 후 `lib/features/question_room/data/attachments/attachment_upload.dart:96` 의 `_storageReady=false→true`. (버킷명은 웹과 통일할 것 — 다르면 같은 파일 `bucket` 상수도 수정.)
2. **[작업5] 조회수 증분 RPC 존재 확인**: `increment_community_post_view(p_post_id)`·`increment_shortform_post_view(p_post_id)`. 웹이 이미 사용 중이라 있을 가능성 높음 — 없으면 조회수만 안 오름(앱은 조용히 무시, 안 죽음).
3. **[작업8·A2] RPC `get_weekly_question_usage(p_student_id,p_mentor_id)`** 존재·정상 동작(이미 A2에서 사용). + (선택)서버측 한도 강제 트리거는 별건.
4. **[참고] 프로필/첨부는 graceful** — 위 인프라가 없어도 앱은 죽지 않고 "준비 중"/로컬 유지로 동작한다.

> **[정정 2026-07-26]** 구 목록의 **[작업2] `users.notification_enabled` 컬럼 추가**는 **폐기**했다. 알림 설정 정본은 `notification_settings` 테이블이고 RLS `select_own`/`modify_own` 과 함께 이미 존재하므로 오너가 만들 인프라가 없다. 해당 항목이 지시하던 "`notification_settings_repository.dart:16 column` 상수와 일치시킬 것"은 그 `column` 상수 자체가 존재하지 않아 **실행 불가능한 지시**였다. 알림 토글은 graceful 대기가 아니라 **DB 정본 저장**이다(위 §2026-07-06(2차) 정정 참조).

---

## 🆕 2026-07-02 필기·주석 시리즈(S13~S15·퀵윈·이미지 뷰어) — 완료

Supabase 실사(스테이징 `lbeqxarxothkmzqvpudy`, 마이그레이션 2건 적용)로 인프라를 확인·정정하고 아래를 **완료**했다. 모두 `master` squash 머지.

| 기능 | 상태 | 커밋 | 저장 규약 |
|---|---|---|---|
| ~~**연결노트 필기**(캔버스·P0 툴바·저장·재편집)~~ | ❌ **제거됨**(2026-07-06, docs/SCAN_INK_PLAN.md 참고) | S13 `2cdb650`·S14-1 `b089e98`·S14-2 `8000006` (S13 코어는 존치, S14 화면·저장만 삭제) | 버킷 `connection-note-ink` 신규 쓰기 중단(기존 객체 보존). `connection_notes.ink_path`·`ink_thumb_path` 컬럼은 웹 호환 위해 유지 |
| **질문방 이미지 첨부 업로드** | ✅ 완전작동 | 퀵윈 `c32d53f` | 버킷 `question-room-attachments`(실존), `{roomId}/{threadId}/{ts}_{name}`, `_storageReady=true` |
| **첨부 이미지 주석**(그리기·평탄화 전송·재편집 저장) | ✅ 완전작동 | S15 `20840dc` | 원본 `scan-annotations` `{roomId}/{attachmentId}/ink.json`, 평탄화 PNG는 기존 첨부 파이프라인으로 전송 |
| **이미지 뷰어**(말풍선 썸네일·전체화면 줌·팬) + **전송 후 주석 진입점** | ✅ 완전작동 | PR #8 `b1fb61a` | 서명 URL `createSignedUrl`(만료 1h·메모리 캐시), 뷰어 '주석 달기' → S15 화면 재사용 |

### 인프라 실사 정정 (기존 문서의 오기 바로잡음)
- **[정정]** 기존 "`question-attachments` 버킷 없음, 오너 생성 필요"는 **오기** — 실제 버킷 **`question-room-attachments`** 가 방 참여자 정책(insert/select)과 함께 **이미 존재**했고 퀵윈으로 앱 연결 완료. 정책 `user_is_room_party_for_qra_path` 상 **경로 첫 세그먼트 = room UUID** 요건.
- **신설**: 버킷 `connection-note-ink`(비공개) + 방 참여자 insert/select/update 정책.
- **기존재 확인**: 버킷 `scan-annotations` + insert/select/update 정책 — S15가 재편집용 원본 저장에 사용.
- **DB**: `connection_notes` 에 `ink_path`·`ink_thumb_path`(nullable, 코멘트 포함) 추가 — **웹 기존 코드 무영향**.

### 테스트
- `flutter test` 전체 **192개 통과**(mock/fake 주입). `flutter analyze` 에러 0.
- 과거 한때 실패하던 12건(community·mypage 등)은 코드 결함이 아니라 **헤드리스 컨테이너의 셰이더 캐시 미워밍 아티팩트**(`ink_sparkle.frag`/`FragmentProgram.fromAsset` — "Unsupported runtime stages format version. Expected 2, got 0")로 판명됐고 **현재 해소되어 전부 통과**(Flutter 3.44.4 불변 상태 확인).

### 잔여(다음 작업)
- **실기기 스타일러스 QA**(에뮬레이터 불가): 필압·팜리젝션·손가락 줌 공존·기기 간 좌표 정합·평탄화 정확도.
- **백로그**: Supabase 어드바이저 기존 경고(예: `payout_runs` RLS 정책 부재 — 웹 소관 추정). (전송된 첨부 이미지 뷰어·전송 후 주석 진입점은 **PR #8로 완료**. 과거 셰이더 12건도 해소.)

---

## ★ 먼저: 미완·깨짐 요약 (출시 전 판단할 것)

**하드 '깨짐(에러·크래시)'은 0건.** 코어 Q&A 루프(질문 작성→답변→확인)와 조회 기능들은 실제 Supabase에 연결되어 작동한다.
문제는 아래 표에서 완료 표기를 제외한 **미해결 기능**과 **인프라 대기 스텁**이다. **[정정 2026-07-26]** 고정 건수는 유지하지 않는다. 각 행의 최신 정정 표기와 실코드 근거를 기준으로 현재 상태를 판정한다.

### 🔴 '보이지만 실제로는 안 되는' 기능 (사용자가 눌렀는데 반응 없음/저장 안 됨)
| # | 기능 | 증상 | 근거 | 종류 |
|---|---|---|---|---|
| 1 | ~~**구독/충전/결제·정산·프로필편집/약관 버튼**~~ **✅ 해소(2026-07)** | 운영 도메인 확정 — 관리·약관·정산 버튼이 실제 웹을 연다(구매 유도 CTA 는 컴플라이언스로 별도 제거) | `web_bridge_config.dart` `baseUrl`(fromEnvironment, 기본=운영 도메인) | 완료 |
| 2 | ~~채팅 이미지 첨부~~ **✅ 해결** | 업로드 + 뷰어 + 주석 진입점 모두 완료 | 퀵윈 `c32d53f`, 뷰어 PR #8 `b1fb61a` | 완료 |
| 3 | **숏폼 영상 재생** | 전체 HTTP(S) URL 은 상세 플레이어에서 재생할 수 있으나, 웹 정본 영상 Storage 참조는 앱에서 signed URL 로 해석하지 못한다. 웹 finalize 는 `thumbnail_url` 도 NULL 로 저장하므로 앱에는 썸네일이 아니라 **중립 배경**만 보인다. 피드 카드는 중립 배경 + 상세 진입만 제공한다 | `shortform_video_port.dart`, `shortform_detail_screen.dart:64,70-93,114,331-352`, `community_read_repository.dart:80-93`, `community_models.dart:128-146` | **부분구현 — 앱 데이터 계층 + Storage 정책 실증** |
| 4 | ~~**숏폼 좋아요/스크랩**~~ **✅ 해소** | 초기 상태 로드 구현됨 | `shortform_detail_screen.dart:46-61`(`_loadReactionState`) | 완료 |
| 5 | **커뮤니티 조회수** | "조회 N" 표시되나 글 진입해도 증가 안 함 | `community_read_repository.dart`(incrementView 부재) | **인프라**(증분 RPC) |
| 6 | **알림 딥링크** | 알림 눌러도 해당 글/스레드로 안 가고 탭만 전환 | `deep_link_service.dart:12`(TODO), `notifications_screen.dart:146-152` | 앱+인프라(푸시) |
| 7 | ~~**설정 알림 토글**~~ **✅ 해소(2026-07-26)** | 정본 테이블 `notification_settings`(`push_enabled`·`groups`)에 저장·재로드된다. 행/키 부재 = ON(서버 판정과 동일), 저장 실패는 원복 + 재시도 안내(기본값 위장 없음) | `settings_section.dart:64-111` + `notification_settings_repository.dart:6-16` | 완료 |
| 8 | **회원가입 링크** | "웹에서 가입" 눌러도 "링크 준비 중" | `login_screen.dart:76` | 오너 설정값 |

### 🟠 미완·스텁 (기능 골격만, 실행 인프라 대기)
- **OS 푸시 — 출시 범위 제외(App-F0)** — OS 푸시는 App-F0 정책에 따라 이번 출시 범위에서 제외됐다. `device_tokens` 테이블은 **기존재**하지만 앱의 FCM SDK·OS 권한·토큰 등록 경로는 제거되어 QA 계정 신규 행이 생기지 않는 것이 정상이다. 재도입은 별도 백로그로 관리하며, 재도입 시 Data Safety 재검토가 필요하다. 인앱 알림 목록·유형 필터·읽음 처리는 정상 작동이므로 함께 미완으로 묶지 않는다. (`lib/core/push/push_ports.dart`(포트만 존치), `lib/core/push/HANDOFF.md`) → **출시 범위 제외**
- **커뮤니티 목록 페이징** — 전체 로드(limit/offset 없음). 데이터 많아지면 성능 저하. (`community_read_repository.dart:23-59`) → 앱만
- **딥링크 라우팅** — 골격만(스트림 구독·경로 매핑 미구현). → 앱+인프라
- **온보딩** — 진입→로그인 골격만(`onboarding_screen.dart:8`). → 앱만
- **요금제 라벨/가격/문항수 상수** — `plan_constants.dart` 전부 비움/TODO(요금제명 미표시). → 오너 확정값

### 실질 출시 판단(핵심)
- ~~**가장 크리티컬(코어 수익 동선)**: #1 `baseUrl` 미설정~~ **✅ 해소(2026-07)** — 운영 도메인 확정으로 웹 동선 전체가 열린다. 결제 관련 잔여 판단은 스토어 정책(docs/PLAY_STORE_REVIEW_PLAN.md P0-3)이며 이 문서 범위 밖.
- **범위 의존**: 숏폼 상세 플레이어 UI는 배선됐지만 웹 정본 영상 Storage 참조의 signed URL 해석이 앱에 없어 실데이터 재생은 아직 **부분구현**이다. 현재 웹 finalize 는 `thumbnail_url` 도 NULL 로 저장하므로 중립 배경만 표시된다. 이번 출시 범위에 포함하려면 영상 URL 해석·만료 재발급, 썸네일 생성/업로드 또는 명시적 대체 UI, 실데이터 기기 QA 를 완료해야 하며, 미완이면 빈 상태 유지 또는 진입 제한을 선택한다. (첨부는 업로드·이미지 뷰어·주석 모두 완료.)
- **UX 저하(비차단)**: 딥링크·조회수·페이징. 숏폼 반응과 알림 토글은 완료됐고, OS 푸시는 App-F0 정책상 출시 범위에서 제외됐다. 숏폼은 `video_player` 와 상세 재생 UI가 배선됐지만 정본 영상 Storage 참조를 signed URL 로 바꾸는 데이터 계층이 없어 웹 업로드 실데이터 재생은 아직 부분구현이다. 현재 웹 finalize 는 `thumbnail_url` 을 NULL 로 저장하므로 앱에는 중립 배경만 보인다. 피드 카드의 직접 재생·재생 어포던스도 앱 UI 잔여다.

---

## 집계

**[정정 2026-07-26]** 변동되는 기능 상태의 고정 건수는 유지하지 않는다. 각 행의 최신 정정 표기와 실코드 근거를 기준으로 현재 상태를 판정한다.

| 판정 | 건수 | 비고 |
|---|---:|---|
| **완전작동** | — | 고정 집계하지 않음. 탭별 상세표의 최신 판정과 실코드 근거로 판단 |
| **부분구현** | — | 고정 집계하지 않음. 탭별 상세표의 최신 판정과 실코드 근거로 판단 |
| **미완·스텁** | — | 고정 집계하지 않음. 탭별 상세표의 최신 판정과 실코드 근거로 판단 |
| **깨짐** | 0 | 크래시·에러 없음 |

---

## 탭별 상세

### 1) 질문방 (question_room)
| 기능 | 판정 | 근거(파일:라인) | 사용자 영향 | 종류 |
|---|---|---|---|---|
| 멘토방 목록+구독상태 | 완전작동 | `question_room_screen.dart:79-96`(myRooms·SubscriptionReader·MentorLookup 실쿼리) | 없음 | 앱 |
| 방 진입 | 완전작동 | `mentor_room_home_screen.dart:43-59`, `student_room_home_screen.dart:50-81` | 없음 | 앱(RLS) |
| 질문 스레드 목록 | 완전작동 | `question_list_screen.dart:50`, `read_repository.dart:38-45` | 없음 | 앱 |
| 질문작성+과목필터(A1)+주간한도(A2) | 완전작동 | `new_question_screen.dart:44-96`(mentorTeachingSubjects·weeklyUsage RPC·createThread INSERT) | 없음 | 앱(단, A2 서버강제는 DB 트리거 필요) |
| 채팅·답변보기·실시간 | 완전작동 | `chat_screen.dart:91-128`, `thread_realtime.dart:27-87`(postgres_changes) | 실시간은 publication 필요, 미포함시 수동새로고침 폴백 | **인프라**(realtime publication) |
| 첨부(이미지) 업로드+뷰어 | 완전작동 | `attachment_upload.dart`(`_storageReady=true`, 버킷 `question-room-attachments`), `DeviceImagePicker`, 뷰어 `attachment_viewer_screen.dart`(PR #8) | 없음 | 앱(퀵윈 `c32d53f`·뷰어 `b1fb61a`) |
| 연결노트(읽기/쓰기) | 완전작동 | `connection_notes_screen.dart:58-97`(notes·upsertMyNote 실쿼리) | 없음 | 앱 |
| ~~연결노트 **필기**(캔버스·P0 툴바·저장·재편집)~~ | **제거됨**(2026-07-06) | `ink_note/` 모듈 삭제 — docs/SCAN_INK_PLAN.md 참고. `InkToolbar` 만 `lib/core/ink/widgets/` 로 이동(S15 주석이 사용) | 필기는 스캔 첨삭으로 대체 예정 | 앱 |
| 첨부 이미지 **주석**(그리기·평탄화 전송·재편집 저장) | 완전작동 | `scan_annotation/`(S15), 진입점=`chat_input_bar` 전송 전 미리보기 '주석 달기' | 없음 | 앱(버킷 `scan-annotations`+기존 첨부 파이프라인) |
| 답변 확인(confirm) | 완전작동 | `question_list_screen.dart:207-221`, `write_repository.dart:76-99`(UPDATE) | 없음 | 앱 |

### 2) 커뮤니티 (community)
| 기능 | 판정 | 근거 | 사용자 영향 | 종류 |
|---|---|---|---|---|
| 게시판 목록+카테고리 | 완전작동 | `board_list_view.dart:25-39`(community_posts 실쿼리, .eq('category')) | 없음 | 앱 |
| 게시글 상세 | 완전작동 | `board_detail_screen.dart:47,59-71,176-184` | 없음 | 앱 |
| 댓글 목록·작성 | 완전작동 | `community_read/write_repository.dart:52-91`(select/insert) | 없음 | 앱 |
| 좋아요/스크랩(게시판) | 완전작동 | `board_detail_screen.dart:57-110`(post_reactions toggle) | 없음 | 앱 |
| 좋아요/스크랩(숏폼) | 완전작동 | `shortform_detail_screen.dart:46-63`(`_loadReactionState` initState 호출), `shortform_reactions` 조회 | 없음 | 앱 |
| 신고 | 완전작동 | `report_sheet.dart:18-78`, `write_repository.dart:105-113`(content_reports insert) | 없음 | 앱 |
| 숏폼 목록(feed) | 완전작동 | `shortform_feed_view.dart:28,38`(shortform_posts 실쿼리) | 없음 | 앱 |
| 숏폼 영상 재생 | 부분구현 | `shortform_video_port.dart` 와 `shortform_detail_screen.dart:70-84,114,331-352` 로 플레이어 UI·폴백·dispose 는 완료. `community_read_repository.dart:80-93`·`community_models.dart:128-146` 에는 영상 Storage 참조→signed URL 해석이 없다. 웹 `communityShortformActions.ts` 는 `thumbnailUrl: null` 을 저장하고 `uploadShortformThumbnail` 호출자는 0건이다 | 웹 업로드 정본 행의 `video_url` 은 Storage 참조라 현재 앱에서 재생되지 않고, `thumbnail_url` 은 NULL 이라 중립 배경만 표시된다. 피드 내 직접 재생·재생 표시도 없고, 전체 HTTP(S) URL 인 경우에만 상세 재생이 가능하다 | 앱 데이터 계층 + Storage 정책 실증 + 앱 UI 보완 |
| 조회수 집계 | 미완 | `community_read_repository.dart`(incrementView 부재) | 🔴 조회수 안 오름 | **인프라**(증분 RPC) |
| 목록 페이징 | 미완 | `community_read_repository.dart:23-59`(전체 로드) | 데이터 많아지면 느림 | 앱만 |

### 3) 멘토찾기 (mentors)
| 기능 | 판정 | 근거 | 사용자 영향 | 종류 |
|---|---|---|---|---|
| 멘토 목록 로드 | 완전작동 | `mentor_directory_repository.dart:29`(rpc mentor_directory_list_v2), :90,:106(프로필·플랜) | 없음 | 앱(RPC) |
| 검색/필터 | 부분구현 | `mentors_screen.dart:177-182`(클라이언트 필터만, 서버 필터 없음) | 정확일치·필드 제한 | 앱만 |
| 정렬(최신/이름) | 완전작동 | `mentors_screen.dart:27,184-196` | 없음(인기순은 지표없어 제외) | 앱 |
| 상세 프로필 | 완전작동 | `mentor_detail_screen.dart:30-69`, `repo.fetchExtras`(get_mentor_avg_response_hours RPC) | 없음 | 앱(RPC) |
| ~~가격 표시~~ | **제거됨(컴플라이언스 `5002c1d`)** | 앱 내 가격 UI 삭제 — 모델 필드는 잔존하나 렌더 안 함(`mentor_card.dart:109` 주석) | 의도된 비노출 | 앱 |
| ~~구독하기 버튼~~ | **제거됨(Commerce-Zero)** | 구매 유도 CTA 삭제 → `CommerceNoticeCard` 비상호작용 안내로 대체(`mentor_detail_screen.dart:148-149`), `openSubscribeWeb` 호출부 0건 | 구독은 웹에서 | 앱 |

### 4) 알림 (notifications)
| 기능 | 판정 | 근거 | 사용자 영향 | 종류 |
|---|---|---|---|---|
| 알림 목록 로드 | 완전작동 | `notifications_repository.dart:38-43`(notifications 실쿼리) | 없음 | 앱 |
| 유형 표시(질문방·구독결제·개별질문+기타) | 완전작동 | `app_notification.dart`(분류), `notification_types.dart`(CR 게이트 2종 exact 제외), `notifications_repository.dart`(DB 단계 제외) | 공지·리뷰 등은 '기타'로 표시. 맞춤의뢰 2종은 출시 게이트 OFF로 미노출(서버 17종 계약 불변) — 2026-07-24 QA4 | 앱 |
| 유형 필터 탭 | 완전작동 | `notifications_screen.dart:177-204` | 없음 | 앱 |
| 읽음/모두읽음 | 완전작동 | `notifications_repository.dart:56-72`(UPDATE) | 없음 | 앱 |
| 딥링크 | 부분구현 | `deep_link_service.dart:12`(TODO), `notifications_screen.dart:146-152`(탭 전환만) | 🔴 특정 글/스레드로 못 감 | 앱+인프라 |
| OS 푸시 | **출시 범위 제외(App-F0)** | OS 푸시는 App-F0 정책에 따라 이번 출시 범위에서 제외됐다. `device_tokens` 테이블은 기존재하지만 앱의 FCM SDK·OS 권한·토큰 등록 경로는 제거되어 QA 계정 신규 행이 생기지 않는 것이 정상이다(`lib/core/push/push_ports.dart` 포트만 존치, `lib/core/push/HANDOFF.md`) | 인앱 알림(목록·유형 필터·읽음)은 정상 작동 — OS 푸시 미수신은 의도된 범위 제외 | 출시 범위 제외 — 재도입은 별도 백로그(재도입 시 Data Safety 재검토) |

### 5) 마이페이지 (mypage) — 2026-07-06부터 하단 탭이 아니라 AppBar 우측 상단 프로필 아이콘(push)으로 진입, 하단 5번째 탭은 개별질문
| 기능 | 판정 | 근거 | 사용자 영향 | 종류 |
|---|---|---|---|---|
| 프로필(이름·이메일·학년) | 완전작동 | `mypage_repository.dart:60-80`(users 실쿼리) | 없음 | 앱 |
| 구독현황+주간잔여 | 완전작동 | `mypage_repository.dart:83-113`(get_weekly_question_usage RPC), `student_subscription_section.dart:93-102` | 없음(직전 수정 반영) | 앱(RPC) |
| 구독 상태 | 완전작동(2분기) | `mypage_models.dart:73-74`(active/만료만) | 만료예정·결제실패 구분 없음(별도 TODO) | 앱만 |
| 캐시 잔액+내역 | 완전작동 | `mypage_repository.dart:116-152`(cash_wallets·cash_ledger 실쿼리) | 없음 | 앱 |
| 구독관리·정산관리 버튼 | 완전작동(2026-07 도메인 확정) | `web_bridge_actions.dart`(`openBillingManageWeb`/`openPayoutManageWeb`) → 운영 웹 열림. 충전 CTA(`openRechargeWeb`)는 컴플라이언스로 미배선 | 없음 | 앱 |
| 설정: 로그아웃 | 완전작동 | `settings_section.dart:65-71`(AuthService.signOut) | 없음 | 앱 |
| 설정: 알림 토글 | 완전작동 | `settings_section.dart:64-111` + `notification_settings_repository.dart:6-16` — 정본 `notification_settings.push_enabled`/`notification_settings.groups`, RLS `select_own`/`modify_own` 기존재. 저장 실패는 원복 + 재시도 안내, 로드 실패는 기본값으로 성공 위장하지 않음 | 없음 | 앱(서버 인프라 잔여 없음) |
| 설정: 약관·개인정보 | 완전작동(2026-07 도메인 확정) | `settings_section.dart:87-92`(`openTermsWeb`/`openPrivacyWeb`) → 운영 웹 열림 | 없음(웹 페이지 법적 문안 게시는 웹 소관) | 앱 |
| 멘토 대시보드 | 완전작동 | `mypage_repository.dart:154-184`(rooms·threads·settlement_items 실쿼리) | 없음 | 앱 |

---

## 인프라 필요 항목 (앱만으로 못 고치는 것)
| 항목 | 필요 인프라 | 영향 기능 | 인수인계 문서 |
|---|---|---|---|
| ~~웹 도메인 확정~~ **✅ 완료(2026-07)** | `WebBridgeConfig.baseUrl` 기본값 = 운영 도메인(오버라이드는 `--dart-define=WEB_BASE_URL`) | 구독관리·정산·약관·개인정보·지원 | `web_bridge_config.dart` 주석 |
| ~~Storage 버킷 + image_picker~~ **✅ 완료** | 버킷 `question-room-attachments` 실존·연결(퀵윈 `c32d53f`), `DeviceImagePicker`, 뷰어 서명 URL(PR #8) | 채팅 첨부·필기·주석·뷰어 | 완료 |
| Realtime publication | question_messages·question_threads를 `supabase_realtime`에 포함 | 실시간 채팅(미포함시 폴백) | (S6) `thread_realtime.dart:23` |
| 숏폼 미디어 정본화 | `video_player ^2.13.0`·상세 플레이어 UI는 **완료**. 영상 잔여는 Storage ref 파싱 → 짧은 TTL signed URL 발급 → 만료 시 재발급 → 실패 폴백 및 authenticated Storage 정책 실증. 썸네일 잔여는 웹 생성/업로드·ref 저장 배선 또는 명시적 대체 UI 확정(웹 `communityShortformActions.ts` 가 `thumbnailUrl: null` 을 저장하고 `uploadShortformThumbnail`(`communityShortformStorage.ts`)은 호출자가 0건) | 웹 업로드 숏폼 영상·썸네일 | `shortform_video_port.dart`, `community_read_repository.dart:80-93`, `thumbnail_view.dart:20-30` |
| 조회수 증분 RPC | `increment_*_view` RPC | 커뮤니티 조회수 | `community_*_repository` |
| ~~푸시 인프라~~ **출시 범위 제외(App-F0)** | 활성 필요 작업 없음 — `device_tokens` 테이블은 기존재하고 앱의 FCM SDK·OS 권한·토큰 등록 경로는 제거됨. 재도입은 별도 백로그(재도입 시 Data Safety 재검토) | OS 푸시(인앱 알림은 정상 작동) | (S7) `lib/core/push/HANDOFF.md` |
| A2 서버강제(선택) | question_threads INSERT 트리거 | 주간한도 우회 방지 | `DB_VERIFY_QUERIES.md` A2-Q3 |
| 요금제 상수 | 요금제명·가격·문항수 확정값 | 요금제 라벨 표시 | `plan_constants.dart` |

## 앱만으로 수정 가능한 것 (인프라 불필요)
- ~~숏폼 좋아요/스크랩 초기 상태 로드~~ ✅ 완료(`shortform_detail_screen.dart:46-61`)
- 커뮤니티 목록 페이징(limit/offset 쿼리) — `community_read_repository.dart`
- ~~알림 토글 저장~~ ✅ 완료 — `notification_settings.push_enabled`/`groups` 에 저장·재로드되고 RLS `select_own`/`modify_own` 이 기존재하므로 서버 인프라 잔여 없음
- 멘토 검색 서버필터/구독상태 다분기 — (표시·정합, CANON_SYNC_TODO 참조)
- ~~`baseUrl` 한 줄 채우기~~ ✅ 완료(2026-07 운영 도메인 확정, fromEnvironment 구조)

---

## 판정 근거 방법
- 탭별 read-only 코드 탐색(질문방·커뮤니티·멘토찾기·알림·마이페이지) + `lib/**/*.dart` 스텁 마커 grep(TODO/골격/준비중/인수인계/미구현) + 기존 `FEATURE_AUDIT.md`·`CANON_SYNC_TODO.md` 대조.
- '완전작동' = 화면이 실제 `.from()/.rpc()`로 데이터를 읽고, 버튼이 실제 write/액션 함수에 연결됨(목데이터·빈 함수 아님).
- '부분/미완' = 일부만 동작하거나 골격·안내만. '깨짐' = 크래시/에러(이번 점검 0건).

---
_(끝) 이번 턴 코드 수정 0. 점검·문서만. color_tokens 미터치, DB 변경 0._
