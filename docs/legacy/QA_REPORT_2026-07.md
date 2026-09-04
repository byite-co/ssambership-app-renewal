# QA_REPORT — 앱 전체 QA 감사 (2026-07)

> 수행일: 2026-07-06 · 기준: master `9f9ee27`(PR #12 머지 후) · 환경: Flutter 3.44.4 stable, 헤드리스 컨테이너
> 방법: 정적 감사(전수 grep·의존성·시크릿) + 문서-코드 교차검증 + 신규 위젯 테스트 33케이스(전부 mock/fake, DB 비접촉) + 테스트 3회 반복(flaky 검출) + 커버리지 산출.
> **QA 원칙: 발견·재현·문서화. 본 감사에서 제품 코드는 수정하지 않았고, 검증용 테스트만 추가했다.** 각 발견의 '수정안'은 제안일 뿐 미적용.

---

## 심각도 요약

| 심각도 | 정의 | 건수 | ID |
|---|---|---|---|
| **P0** 출시 차단 (후보) | 스토어 리젝·정책 위반 가능 | **1** | QA-01 |
| **P1** 출시 전 수정 권고 | 정보 노출·핵심 문서 자기모순·보안 확인 | **3** | QA-02 ~ QA-04 |
| **P2** 다음 마일스톤 | 문서 스테일·데드코드·설계 결정·커버리지 공백 | **9** | QA-05 ~ QA-14 (QA-10 은 오탐 철회) |
| **P3** 사소 | 린트·미세 드리프트·의도된 TODO | **4** | QA-15 ~ QA-18 |

**베이스라인(전부 양호)**: analyze `lib/`+`test/` **에러 0·경고 0**(info 린트 67건, 전부 lib/의 `prefer_const` 류) · `flutter test` 3회 연속 250/250 통과 — **flaky 0건** · 신규 테스트 포함 최종 **283/283 통과** · 라인 커버리지 **54.6%**(2,644/4,840) · 시크릿 커밋 0건 · `print`/`debugPrint` 0건 · 미사용 의존성/에셋 0건 · 320×568 소형 뷰포트 오버플로 **0건**.

---

## P0 — 출시 차단 (후보)

### QA-01 · 개별질문 '앱 내 캐시 예치' 활성 — Google Play 결제 정책 리스크 — **✅ 결정·이행 완료(2026-07, A안)**

> **처리(2026-07)**: **A안 확정** — `kIndividualQuestionCreateEnabled = bool.fromEnvironment('IQ_CREATE_ENABLED', defaultValue: false)` 로 전환(`chore/release-config`). 첫 스토어 제출 빌드는 작성 진입점 기본 off, dev/내부 테스트는 dart-define 주입으로 on. on 전환 게이트·의사결정 기록은 docs/PLAY_STORE_REVIEW_PLAN.md 참고. 아래 원문은 감사 시점 기록으로 보존.
- **위치**: `lib/features/individual_question/iq_flags.dart:14` (`kIndividualQuestionCreateEnabled = true`), 작성 진입점 `lib/features/individual_question/ui/student_iq_list_screen.dart:120-141`, `lib/features/mentors/ui/mentor_detail_screen.dart:153-155`, 예치 안내문 `lib/features/individual_question/ui/iq_create_screen.dart:121`("…캐시가 안전 보관(예치)돼요")
- **근거**: 결제 실행 자체는 서버 SECURITY DEFINER RPC(`create_individual_question_as_student`)로만 수행되고 앱은 SDK·차감 계산이 없다(Commerce-Zero 준수). 그러나 **기충전 캐시를 앱 안에서 디지털 재화(개별질문)에 소비하는 UX**가 활성 상태이며, `iq_flags.dart:1-14` 스스로 "Play 결제 정책 검토 대상"으로 경고하고 있다. `iq_create_screen.dart:121`의 예치 확인문은 사실상 **개별 상품 단가 노출**이기도 하다(커밋 `5002c1d` 가격표시 제거 취지와 긴장).
- **사용자 영향**: 정책 위반 판정 시 스토어 리젝/앱 제거. 기능 자체는 정상 동작.
- **수정안**: 출시 전 스토어 정책 판단을 확정하고, 보수적으로 갈 경우 `kIndividualQuestionCreateEnabled = false`(작성만 잠금 — 목록·상세·답변 확인은 `kIndividualQuestionEnabled`로 유지됨을 스위치 off 스모크로 검증 완료). **사람 판단 필요.**

---

## P1 — 출시 전 수정 권고

### QA-02 · raw `$e` 예외 원문이 사용자에게 노출 (13개 화면)
- **위치**: `chat_screen.dart:173,199` · `mentor_answer_screen.dart:177,202` · `question_list_screen.dart:219` · `connection_notes_screen.dart:100` · `new_question_screen.dart:101` · `attachment_viewer_screen.dart:68` · `scan_annotation_screen.dart:167` · `notifications_screen.dart:114,129` · `profile_edit_screen.dart:67` · `board_write_screen.dart:56` · `board_detail_screen.dart:97,114,129,174` · `shortform_detail_screen.dart:97,114,129,174` (dev 전용 `s3_data_inspector.dart:109`는 릴리즈 미포함이라 제외)
- **근거**: `SnackBar(content: Text('…실패했어요. ($e)'))` 패턴. catch가 전 예외를 잡으므로 `PostgrestException`/`StorageException` 원문(테이블·컬럼·RLS 정책명·내부 URL)이 그대로 화면에 노출될 수 있다. `lib/shared/errors/app_error.dart:1-10`의 "내부 코드/DB명 노출 금지" 원칙과 코드가 어긋난다.
- **재현**: Supabase 미초기화 상태에서 노트 저장 → "저장에 실패했어요. (AppError: …)" 노출. RLS 거부 시엔 정책명 포함 원문 노출.
- **사용자 영향**: 내부 스키마 정보 노출(보안) + 원문 영어 에러 노출(UX·"영문 코드 비노출" 규약 위반).
- **수정안**: `login_screen.dart:52`의 `_friendly(...)` 패턴을 공용화 — 예: `String friendlyError(Object e) => e is AppError ? e.userMessage : '요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.'` 를 `shared/errors/`에 두고 13개 지점의 `($e)`를 일괄 교체.

### QA-03 · 핵심 문서가 개별질문(IQ) 범위를 정반대로 서술 (문서 자기모순)
- **위치**: `README.md:8` "제외(흔적 없이): …개별질문(IQ)…" · `HANDOFF.md:150` "CR·IQ·관리자·회원가입 폼: 앱 범위 밖 … 노출하지 않음" ↔ `HANDOFF.md:19`(5탭에 '개별질문' 포함) · `app_tabs.dart:14`(individualQuestion=4, 실제 1급 탭) · `docs/APP_FEATURE_STATUS.md` 2026-07-06 블록
- **근거**: IQ는 PR #12로 하단 5번째 탭으로 승격됐는데, README와 HANDOFF §4는 여전히 "흔적 없이 제외"로 서술. HANDOFF는 §1과 §4가 **한 문서 안에서 자기모순**. 인수인계 문서가 신뢰 기준(정본) 역할을 못 하게 되는 상태.
- **사용자 영향**: 개발자 온보딩·다음 세션 작업자가 잘못된 전제로 작업할 위험.
- **수정안**: HANDOFF §4(line 150)와 README 범위 문단을 "IQ = 1급 탭(스위치 지배)"으로 갱신. README는 S0 시점 서술 전반(§QA-05)과 함께 일괄 정비.

### QA-04 · 알림 읽음 처리에 owner 필터 부재 — RLS 단독 의존 (서버 정책 확인 필요)
- **위치**: `lib/features/notifications/data/notifications_repository.dart:56-72` (`markRead(id)`/`markAllRead(ids)`)
- **근거**: 호출자가 넘긴 id를 `.eq('user_id', uid)` 같은 본인 필터 없이 update. 앱의 다른 쓰기 레포(연결노트 `:104-142`, 커뮤니티 차단/신고, 프로필)는 전부 세션 uid를 강제하는데 이 두 메서드만 RLS('본인 알림만')에 전적으로 의존(주석 `:25`).
- **사용자 영향**: RLS 정책이 실서버에 없거나 느슨하면 임의 알림 읽음 처리 가능. 앱 계층 단독 결함은 아님.
- **수정안**: (1) 서버에서 `notifications` update RLS 존재를 확인(우선), (2) 방어적으로 `.eq('user_id', _uid)`를 쿼리에 추가(코드 2줄).

---

## P2 — 다음 마일스톤

### QA-05 · APP_FEATURE_STATUS.md 스테일 다수 — baseUrl 관련 판정 전면 재검토 필요 — **✅ 처리(2026-07)**

> **처리(2026-07)**: 아래 나열 항목(①~⑤ 및 baseUrl 계열 판정) 전부 APP_FEATURE_STATUS.md 의 "🆕 2026-07-06(2차) 실태 정정" 블록 + 해당 표 행 정정으로 반영 완료(`chore/release-config`). 아래 원문은 감사 시점 기록으로 보존.
- **위치**: `docs/APP_FEATURE_STATUS.md:81, 98, 152, 171, 182` 등 ↔ `lib/core/web_bridge/web_bridge_config.dart:15`
- **근거**: 문서는 "`baseUrl=''` → 구독·충전·결제 전부 '준비 중', 가장 크리티컬한 출시 차단"으로 반복 서술하나, 실제 `baseUrl = 'https://ssambership-web.vercel.app'`로 설정돼 `isConfigured`(`:36`)=true — 웹이 실제로 열린다. 그 밖의 스테일: ① 멘토 "가격 표시 완전작동"(`:151`) — 실제로는 컴플라이언스로 UI 제거됨(`mentor_card.dart:109`), ② "구독하기 버튼 부분구현"(`:152`) — 버튼 자체가 `CommerceNoticeCard`로 대체·삭제, `openSubscribeWeb` 호출부 0건, ③ 숏폼 반응 "초기 로드 없음"(`:84,137`) — 이미 구현됨(`shortform_detail_screen.dart:46-61`, 과소 서술), ④ 약관·개인정보 "미완 스텁"(`:174`) — `openTermsWeb`/`openPrivacyWeb` 배선 완료(`settings_section.dart:87-92`), ⑤ 라인 드리프트 다수(`_storageReady` 96→97, 회원가입 76→78, priceSummary 143-147→150-151, 알림토글 25-46→32-58 등).
- **수정안**: STATUS 문서 재감사(2026-07-06 블록처럼 날짜 블록 추가 방식 권장). 라인 앵커는 심볼명 병기로 드리프트 내성 확보.

### QA-06 · web_bridge baseUrl 하드코딩이 파일 자체 규약과 불일치 — **✅ 결정·이행 완료(2026-07, 도메인 확정)**

> **처리(2026-07)**: 현행 vercel 도메인이 **출시용 운영 웹으로 확정**됨. `baseUrl = String.fromEnvironment('WEB_BASE_URL', defaultValue: <운영 도메인>)` 구조로 전환(`chore/release-config`) — 규약 주석도 "확정 기본값 + 오버라이드"로 교체돼 모순 해소. 빈 값 주입 시 "준비 중" 폴백 유지. 아래 원문은 감사 시점 기록으로 보존.
- **위치**: `lib/core/web_bridge/web_bridge_config.dart:15` ↔ 같은 파일 주석 `:5-7`("미확정이면 비워두고 앱은 웹을 열지 않음", "가짜 URL 하드코딩 금지")
- **근거**: vercel 스테이징 도메인이 채워져 있어 폴백 안내("준비 중")가 절대 표시되지 않음. 운영 도메인 확정 전 출시 시 스테이징 웹으로 결제 동선이 열린다.
- **수정안**: 운영 도메인 확정 시 교체 또는 규약대로 비움. **이 값이 의도된 스테이징 연결인지 사람 판단 필요.**

### QA-07 · HANDOFF billingManagePath 불일치
- **위치**: `HANDOFF.md:104` `billingManagePath='/account/billing'` ↔ `web_bridge_config.dart:21` `'/subscriptions'`
- **수정안**: HANDOFF 갱신(경로 상수 블록 18-33행으로 이동, terms/privacy/support 등 신규 경로 추가분 반영).

### QA-08 · 테스트 개수 문서 불일치 (3중)
- **위치**: `HANDOFF.md:19,169` "250개" ↔ `APP_FEATURE_STATUS.md:64` "192개" ↔ 실측(본 감사 후) **283개**
- **수정안**: 문서에 고정 숫자 대신 "전체 통과" + 갱신일 표기 권장. 최소한 STATUS의 192는 스테일이므로 갱신.

### QA-09 · dead code 4파일 + 재노출 위험 데드 헬퍼
- **위치**: ① `lib/data/repositories/health_repository.dart`(+전이적 `lib/data/models/health_probe.dart`) — 어디서도 import 안 됨, ② `lib/design/widgets/empty_screen.dart` — 실사용은 `empty_state.dart`, ③ `lib/features/onboarding/onboarding_screen.dart` — 라우터 미연결(도달 불가), ④ `openSubscribeWeb`/`openRechargeWeb`(`web_bridge_actions.dart`) 호출부 0건, ⑤ `mentor_price_format.dart:16`('…원' 포맷터)·`mentor_models.dart:150-151`(`priceSummary`) — 가격표시 제거 후 미사용이나 코드 잔존 → **실수 재배선 시 컴플라이언스 재위반 위험**
- **수정안**: ①~③ 삭제(또는 onboarding은 라우터 연결 결정), ④~⑤는 컴플라이언스 관점에서 삭제 권장(주석으로 사유 남김).

### ~~QA-10 · 게스트 초기 탭이 보호 탭(질문방)~~ — **오탐(철회, 2026-07-06 재검증)**
- **재검증 결과**: 실제 코드는 `lib/app/home_shell.dart:54` `initState` 에서 `_index = AuthService.instance.isGuest ? 2 : 0;` — **게스트는 허용 탭인 멘토찾기(2)에서 시작한다.** 최초 감사가 필드 선언(`late int _index`, `:31`)만 보고 initState 초기화를 놓친 오탐. 발견 철회, P2 집계 10→9. QA-11(IndexedStack eager build)은 별개 사안으로 유지.

### QA-11 · IndexedStack 이 게스트에게도 5탭 전부 eager build
- **위치**: `lib/app/home_shell.dart:33-39, 110`
- **근거**: 질문방·알림·IQ 화면이 게스트 상태에서도 build되어 fetch가 트리거됨(세션 부재로 실패·빈 상태, RLS 보호로 노출 없음). 낭비 요청 + 불필요한 에러 로그.
- **수정안**: 비허용 탭은 게스트일 때 placeholder로 지연 build.

### QA-12 · 커버리지 공백 — 사용자 동선 화면
- **근거**: 전체 54.6%. 동선상 화면 중 공백: `shortform_detail_screen.dart` **0%**(153줄 — 좋아요/스크랩/신고/차단 흐름 포함), `profile_edit_screen.dart` **0%**(52줄), `block_author_action.dart` **0%**(17줄 — 차단 UX), `iq_create_screen.dart` **1%**(103줄 — P0 대상 화면인데 미검증), `app_config.dart` **0%**(플랫폼 URL 분기). ※ `*_repository.dart` 1%대는 Supabase 구현부라 의도된 미커버(주입 포트 설계).
- **수정안**: 위 4개 화면에 loaderOverride/fake 주입 테스트 추가(특히 iq_create의 스위치·예치 문구·제출 흐름).

### QA-13 · 의존성 메이저 뒤처짐
- **근거**: `flutter pub outdated` — go_router 14.8.1→17.3.0, flutter_dotenv 5.2.1→6.0.1, flutter_lints 4→6, flutter_launcher_icons 0.13→0.14. 보안 이슈는 아니나 마이그레이션 부채 누적.
- **수정안**: go_router 메이저 업은 별도 마일스톤으로(라우팅 API 변경 큼).

### QA-14 · deprecated withOpacity 잔존 5곳
- **위치**: `initial_avatar.dart:37` · `app_badge.dart:27` · `status_pill.dart:70` · `skeleton.dart:44` · `cash_section.dart:95`
- **수정안**: `.withValues(alpha: …)` 일괄 교체(PR #12에서 home_shell 1곳은 처리됨). 동작 동일.

---

## P3 — 사소

### QA-15 · info 린트 67건
전부 lib/의 `prefer_const_constructors`/`prefer_final_locals` 류. test/는 0건. 기능 영향 없음 — 일괄 정리는 diff 노이즈 대비 효익 판단.

### QA-16 · 파일 내부 스테일 주석
`notifications_screen.dart:18` 헤더 "CR·환불·개별질문(IQ)은 제외" ↔ 같은 파일 `:152-153`은 IQ를 전용 종류로 라우팅. `HANDOFF.md:150`의 "IQ를 other로 숨김" 서술도 동일하게 스테일(현재 `NotificationKind.individualQuestion` 전용 종류 존재).

### QA-17 · ink 경로 헬퍼의 production 미사용
`ink_storage_paths.dart`의 `noteDocument`/`noteThumbnail`/`bucket`(connection-note-ink)은 필기 제거 후 테스트에서만 사용(의도된 deprecated — SCAN_INK_PLAN §7-3에 문서화됨). `annotationFlattened`(`:41`)는 평탄화가 첨부 파이프라인으로 나가므로 미사용. **삭제 금지**(core/ink API 시그니처 동결 규약) — 주석으로 deprecated 표기만 권장.

### QA-18 · TODO 8건 (전수)
`deep_link_service.dart:12`(딥링크 라우팅 미구현 — STATUS와 일치), `app_constants.dart:17`(package_info), `plan_constants.dart:11-30`(요금제 미확정 — "키만 두고 값 비움" 규약 **준수**), `mentors_screen.dart:1`(S10 라우트), `mypage_screen.dart:37`(S11 탭 연결). FIXME/HACK/XXX 0건.

---

## 검증 통과 항목 (발견 없음 — 근거 포함)

| 영역 | 결과 |
|---|---|
| **Commerce-Zero** | 결제 SDK 의존성 0(pubspec 전수) · `launchUrl` 호출 단일 지점(`web_bridge.dart:26`) · 캐시/구독 레포 전부 select 전용, 잔액 변동은 서버 RPC만 · URL 조립 단일 경로(`buildUri`), 사용자 입력 미혼입, 웹뷰 미사용 |
| **권한 경계** | 전 쓰기 레포가 세션 uid 내부 파생(임의 userId 파라미터 레포 0건) · 연결노트 upsert 본인 강제(`:115,135`) · 신고 reporter_id·차단 blocker_id 강제, 자기차단 방지 · IQ 수락/답변/정산/환불 전부 서버 RPC 위임 (예외: QA-04) |
| **역할 가드** | admin 차단(`auth_service.dart:76`) · blocked/상태불명 차단(`:74,81`) · 게스트 라우트 우회 없음(상세 화면은 허용 탭에서만 push 도달 가능) · dev 라우트 릴리즈 미등록 |
| **시크릿·로그** | 하드코딩 키/JWT/URL 0건 · `.env` gitignore·미추적, `.env.example` 실키 없음 · print/debugPrint 0건 |
| **스토리지 규약** | HANDOFF 표의 버킷명·경로 5종 모두 코드와 문자열 수준 일치 |
| **SCAN_INK §9** | 선행 변경 4건 전부 반영 확인(4/4). '주석 달기'→'필기하기' 라벨은 계획대로 미변경 상태(모순 아님) |
| **기능 스위치** | `kIndividualQuestionEnabled=false` / `kIndividualQuestionCreateEnabled=false` 각각 스모크: analyze 에러 0 + 관련 테스트 녹색, 작성 진입 3곳 모두 스위치 지배 확인. **검증 후 원복 완료**(git 무변경 확인). 단 스위치가 컴파일 상수라 off 분기는 위젯 테스트로 상시 검증 불가 — CI 매트릭스 또는 수동 스모크 항목으로 유지 |
| **안정성** | 3회 반복 flaky 0 · 셰이더 캐시 위양성(ink_sparkle) 재발 없음 · 320×568 소형 뷰포트에서 셸+5탭+주요 화면 상태 3종(로딩/빈/에러) 오버플로 0 |
| **입력 경계** | 연결노트 빈/공백 저장 차단·trim 동작·10k자/이모지/특수문자 렌더 정상 · 포맷터 미래시각/자정/연경계 정상(전부 신규 테스트로 고정) |

---

## 신규 테스트 (본 감사에서 추가 — 총 5파일 33케이스)

| 파일 | 케이스 | 검증 |
|---|---|---|
| `test/screens/home_shell_test.dart` | 8 | 5탭 구성 · 게스트 가드(보호 탭/허용 탭/프로필) · 프로필 push · 딥링크 100=push/4=탭전환/-1 리셋/재요청 · 320×568 전 탭 스모크 |
| `test/screens/small_viewport_states_test.dart` | 8 | IQ 목록(학생·멘토)/IQ 상세/알림/마이페이지/연결노트 — 로딩·빈·에러 × 320×568 오버플로 |
| `test/screens/entry_guard_redirect_test.dart` | 7 | AccessState×위치 분기 전수 + 게스트 허용 탭 표 (커버리지 0% 보강) |
| `test/screens/connection_notes_boundary_test.dart` | 3 | 빈/공백 저장 차단 · trim · 초장문/이모지/특수문자 |
| `test/data/formatters_boundary_test.dart` | 7 | 상대시간 경계(60초/7일/연) · 미래시각 음수 미노출 · 자정 패딩 |

---

## 사람 판단이 필요한 항목

1. ~~**QA-01**: 개별질문 예치 흐름의 스토어 정책 판단~~ **✅ 결정 완료(2026-07, A안)** — 스토어 빌드 기본 off + dart-define 주입, 게이트는 PLAY_STORE_REVIEW_PLAN.md
2. ~~**QA-06**: `baseUrl`의 vercel 스테이징 도메인~~ **✅ 결정 완료(2026-07)** — 해당 도메인이 운영 웹으로 확정, fromEnvironment 구조로 이행
3. **QA-03/05**: README·HANDOFF·STATUS 문서 정비 범위(부분 패치 vs README 재작성) — QA-05 지적분은 처리 완료, README 전면 재작성 여부만 잔여
4. ~~**QA-04**: 실서버 `notifications` 테이블 RLS 정책 존재 확인~~ **✅ 확인 완료(2026-07-06)** — 스테이징(=운영) 실사: UPDATE RLS `notif_update_recipient_read` 존재, `user_id` 27/27 행 사용(PR #14 리뷰에서 검증)

> 갱신(2026-07-06): QA-10 은 재검증 결과 **오탐으로 철회**(`home_shell.dart:54` 가 게스트를 멘토찾기 탭에서 시작시킴 — 상세는 P2 절). QA-02(raw `$e`)·QA-03(문서 모순)·QA-04(알림 uid 필터)는 `fix/qa-p1-batch` 브랜치에서 수정 적용됨.
