# 쌤버십 앱(ssambership-app) 코드 리뷰 보고서

> 작성일: 2026-07-15 · 브랜치: `claude/code-review-markdown-repos-g18cv7`
>
> 다중 에이전트 코드 리뷰: 영역별 병렬 정독 후 발견사항마다 적대적 3중 검증(재현성·악용영향·설계의도)을 거쳐, 반박(REFUTED)된 항목은 제외했습니다. 아래는 CONFIRMED/PLAUSIBLE로 살아남은 발견만 담습니다.

## 요약

| 심각도 | 건수 |
|---|---|
| 🔴 치명(critical) | 0 |
| 🟠 높음(high) | 1 |
| 🟡 중간(medium) | 17 |
| ⚪ 낮음(low) | 16 |
| **합계** | **34** |

## 아키텍처 개요

## 앱 저장소 아키텍처 개요 (/home/user/ssambership-app)

쌤버십 Flutter 앱은 웹(Next.js)의 **컴패니언 앱**으로, 자체 백엔드 없이 웹과 동일한 Supabase 1개를 anon key + RLS로만 사용하는 **읽기 중심** 구조다. 코드는 5개 계층으로 나뉜다: `lib/app/`(GoRouter 라우팅·`EntryGuard` 진입 분기·`HomeShell` 5탭 셸), `lib/core/`(Supabase 초기화, `AuthService` 인증/역할, `Entitlement` 구독 읽기, `web_bridge/` 결제 동선, `commerce/` 정책 플래그, push 골격, ink/scan 코어), `lib/design/`(색·타이포 토큰 + 공통 위젯), `lib/features/`(auth·question_room·individual_question·community·mentors·notifications·mypage·scan_annotation — 각 feature가 `data/`(모델·레포)와 `ui/`(화면·위젯)로 분리), `lib/shared/`(상수·포맷터·라벨·에러).

진입 제어는 `AuthService.access`가 5상태(`loading/loggedOut/guest/full/blocked`)를 단일 소스로 산출하고 `EntryGuard.redirect`가 GoRouter `refreshListenable`로 소비하는 구조다. 관리자 계정과 상태 불명 계정은 보수적으로 차단된다(`auth_service.dart:70-85`). 데이터 계층 레포지토리는 클라이언트 측 권한 필터를 의도적으로 두지 않고 RLS에 위임하며(`question_room_read_repository.dart:14` 주석에 명시), 쓰기 레포는 DB 제약을 그대로 반영한다 — 방 생성 메서드 없음, 메시지 append 전용, quota 검증은 서버 책임(`question_room_write_repository.dart:12-15`).

**Commerce-Zero는 3중 구조로 구현**돼 있다. (1) `pubspec.yaml`에 결제 SDK 자체가 없다(토스·인앱결제 의존성 0). (2) 결제성 동선은 전부 `WebBridge`(`lib/core/web_bridge/web_bridge.dart`)가 외부 브라우저로 웹 URL을 여는 것뿐이며, URL은 `WebBridgeConfig` 한 곳에서만 조립되고 baseUrl 미확정 시 URL을 날조하지 않고 `notConfigured` 폴백을 돌려준다. (3) `commerce_policy.dart`의 `kInAppPaymentSteeringEnabled=false`로 구매 유도 자체를 끄고 있어, 구매 유도 헬퍼(`openSubscribeWeb`/`openRechargeWeb`)는 정의만 있고 **호출부가 0곳**임을 grep으로 확인했다. 캐시를 소비하는 개별질문 작성(`kIndividualQuestionCreateEnabled`)과 구독 관리 링크(`kSubscriptionManageLinkEnabled`)는 dart-define 컴파일 타임 스위치로 스토어 빌드 기본 off다. `Entitlement`는 구독 상태를 읽기만 한다.

아직 켜지 못하는 인프라(FCM 푸시, PDF 렌더, 스캔 소스)는 **포트/어댑터 패턴**으로 격리돼 있다 — `push_ports.dart`의 4개 추상 포트에 Disabled/Noop 기본 구현이 붙어 Firebase 없이도 컴파일·테스트가 되고, 활성화 지점(`_tableExists`/`_deployed` 플래그)이 HANDOFF에 문서화돼 있다. 테스트는 78개 파일에 `test(` 180건 + `testWidgets(` 148건이 등록돼 있고(HANDOFF 표기 "250개 전부 통과"), 전부 DB·네트워크 없이 화면 생성자에 레포지토리/브릿지를 주입하는 방식이다(feature 구조를 거울처럼 반영한 test/ 폴더).

### 잘 된 점

- Commerce-Zero가 문구가 아니라 구조로 강제됨 — 결제 SDK 의존성 0(pubspec.yaml), URL 단일 소스(web_bridge_config.dart), 구매 유도 플래그 off(commerce_policy.dart:9) + 구매 유도 헬퍼 호출부 0곳(grep 확인), 캐시 소비 기능(IQ 작성)은 스토어 빌드 기본 off(iq_flags.dart:16-17), Entitlement는 읽기 전용. 어느 한 층이 뚫려도 다른 층이 막는 다중 방어다.
- 웹 브릿지 설계가 절제돼 있음 — WebBridge.buildUri는 baseUrl 미확정 시 null을 돌려 URL 날조를 원천 차단하고(web_bridge.dart:76-84), launcher가 주입 가능해 테스트되며, 모든 화면이 web_bridge_actions.dart 헬퍼만 호출해 결제 동선 UX(열기/준비중 안내/실패 안내)가 앱 전체에서 통일된다.
- 미완 인프라의 포트/어댑터 격리 — push_ports.dart의 4개 추상 포트 + Disabled/Noop 기본 구현으로 Firebase·Edge Function 없이 전체가 컴파일·테스트되고, 활성화 스위치(_tableExists/_deployed)와 절차가 HANDOFF 3-4에 정확한 파일:줄 단위로 문서화돼 인수인계 비용이 낮다. scan(ScanSourcePort·PdfRasterizer)·ink(scribble 어댑터)·AnnotationTarget도 같은 규율을 따른다.
- RLS 단일 권한 모델의 일관성 — 레포지토리가 클라이언트 측 권한 필터를 의도적으로 두지 않아(question_room_read_repository.dart:14 주석) 웹과 앱의 권한 로직이 갈라질 여지가 없고, 쓰기 레포는 DB에 정책이 없는 동작(방 생성, 메시지 수정/삭제)을 메서드 수준에서 아예 노출하지 않는다.
- 진입 분기의 보수적 기본값 — AccessState 5상태 단일 소스에서 role 불명·계정 상태 불명은 전부 blocked로 수렴하고(auth_service.dart:74-81), 관리자는 앱 접근이 차단되며, 게스트 허용 탭이 EntryGuard.guestAllowedTabs 상수 한 곳으로 관리된다.
- 테스트가 구조를 거울처럼 반영하고 헤르메틱함 — test/ 폴더가 feature 구조와 1:1 대응하고(78개 파일, test 180 + testWidgets 148 등록), 화면이 생성자 주입(repository·bridge 파라미터)을 받아 실제 DB·네트워크 없이 전부 돌아간다. 컴파일 타임 플래그(IQ 작성 on/off)까지 dart-define 주입으로 양쪽 상태를 테스트한다.
- 부팅 내결함성 — .env 부재, Supabase 키 부재, 초기화 실패 어느 경우에도 앱은 구동되고(main.dart:11-31, SupabaseInit.clientOrNull null 가드) 게스트/안내 폴백으로 강등된다.

### 구조적 리스크

- 스키마 계약의 암묵성 — 앱 모델은 실제 DB 컬럼명을 손으로 매핑하는데(예: question_threads의 mentor_student_room_id, question_room_read_repository.dart:42) 스키마·RLS·마이그레이션의 소유권은 웹 저장소에 있고, 앱 테스트 250개는 전부 mock 기반이라 실스키마 대조 계약 테스트가 없다. 웹 쪽 마이그레이션 하나가 앱을 소리 없이 깨뜨릴 수 있으며, 이미 웹 CLAUDE.md(room_id 표기)와 앱 코드(mentor_student_room_id) 사이에 문서 표기 드리프트가 존재한다.
- DI 패턴 비일관 — notifications_screen.dart:24는 레포지토리 주입을 받지만 mentors_screen.dart:34-35·chat_screen.dart:71-73은 const 레포를 하드 인스턴스화하고, 레포지토리 내부는 SupabaseInit.clientOrNull 정적 싱글턴에 직접 결합돼 있다(AuthService/PushService/DeepLinkService도 전역 싱글턴). 테스트 주입 지점이 화면마다 달라, 캐싱 도입이나 백엔드 접근 계층 교체 시 파일 다수를 가로지르는 수정이 필요하다.
- 광범위한 에러 삼킴에 의한 조용한 강등 — EntitlementReader.fetchForStudent(entitlement.dart:50-52)·_readRole(auth_service.dart:168-170)·mentorTeachingSubjects 등이 catch-all로 기본값을 반환해, 일시적 네트워크 오류가 '구독 중 학생을 무구독으로', 'role 조회 실패를 차단 화면으로' 바꾼다. 차단 쪽은 재시도 경로(isRecoverableBlock)가 있지만 entitlement 쪽은 오류와 '실제 무구독'을 구분할 신호 자체가 없다.
- 기능 게이트가 전부 컴파일 타임 — IQ 작성·구독 관리 링크·WEB_BASE_URL이 dart-define 상수라 스토어 정책 판단이 뒤집히거나 긴급 차단이 필요할 때 바이너리 재출시 없이는 대응할 수 없다(런타임 kill switch·원격 구성 부재). Commerce-Zero 컴플라이언스가 걸린 스위치임을 감안하면 단일 릴리즈 실수의 파급이 크다.
- 웹 브릿지가 단방향 — 결제 완료 후 앱 복귀 딥링크·콜백이 없어(HANDOFF 3-1 '미구현' 명시) 웹에서 구독을 마친 사용자가 앱으로 돌아와도 구독 상태가 화면 재진입 전까지 낡은 채로 남는다. Entitlement 갱신이 auth 이벤트·화면 리로드에만 묶여 있어 결제 직후 UX 공백이 구조적으로 남아 있다.
- 알림 파이프라인의 절반이 미가동 상태로 1급 탭 — 알림이 하단 5탭의 하나지만 푸시 트리거는 메서드만 있고 미연결, device_tokens 테이블 미존재, realtime publication 미확인(HANDOFF 3-3·3-4). 폴백(수동 새로고침)은 있으나 활성화 절차가 코드가 아닌 HANDOFF 산문에만 존재해, 인수인계 과정에서 순서 누락 시 반쯤 죽은 탭이 출시될 운영 리스크가 있다.
- 정본 문서(HANDOFF.md)의 진행성 드리프트 — '원격 저장소 없음'(HANDOFF 2장) 표기와 달리 실제로는 origin이 존재하고 PR #27까지 머지돼 있는 등, 단일 인수인계 문서가 이미 일부 낡았다. 이 문서가 활성화 플래그·버킷 규약·컴플라이언스 게이트의 유일한 기록이라는 점에서, 문서-코드 불일치가 누적되면 잠금값 훼손으로 이어질 수 있다.

## 영역별 총평

**인증·세션·역할** — 인증·세션 골격(AuthService 단일 소스 + EntryGuard 리다이렉트)은 보수적 차단 원칙이 잘 지켜져 권한 우회류 구멍은 발견되지 않았다. 다만 계정 정지 처리에서 웹 정본(suspended_until 경과 시 자동 해제)을 앱이 무시해 정지 만료 사용자가 앱에서만 무기한 차단되는 정합성 결함이 가장 크고, 로그아웃과 경쟁하는 미대기 프로필 로드, 일시적 조회 실패를 계정 차단으로 취급하는 문제, 세션 토큰의 평문 SharedPreferences 저장 등 세션 수명주기 관리에 중간 수준 결함이 있다. 게스트 모드의 보호 탭 사전 빌드로 인한 불필요 인증 쿼리, entitlement 캐시의 사장(死藏) 등 저수준 이슈도 확인됐다.

**데이터 계층** — 앱 데이터 계층은 전반적으로 null 안전 파싱(폴백 enum·tryParse)과 RLS 의존 설계가 잘 지켜져 있고 모델 컬럼명도 웹 스키마와 대부분 일치한다. 그러나 웹 스키마·RPC와의 계약 불일치 3건이 심각하다: 앱발 질문 스레드가 status 'open'으로 생성돼 주간 질문 한도(라이트 주4/스탠다드 주9)가 전혀 소모되지 않고 답변→확인 워크플로가 끊기며, 숏폼 스크랩은 DB CHECK/RLS(type='like'만 허용)에 막혀 항상 실패하고, 멘토 화면의 학생 이름 조회는 맞춤의뢰 전용 RPC를 써서 구독 학생 이름이 전부 '학생' 폴백으로 나온다. 그 외 mentor_plans is_active 필터 누락, 차단 필터와 페이지네이션의 offset 드리프트, 과목 자유 라벨의 FK 위반, 멘토 이름 N+1 조회 등 중간 등급 결함이 확인됐다. realtime 구독 해제는 LiveMessageList가 dispose에서 정리해 누수 경로는 현재 코드 흐름상 발견되지 않았다.

**웹 브릿지·딥링크·푸시·정책** — 담당 영역(웹 브릿지·딥링크·푸시·커머스 정책·설정)은 Commerce-Zero 원칙이 전반적으로 충실히 구현돼 있다 — 구매 유도 헬퍼(openSubscribeWeb/openRechargeWeb)는 호출부가 없고, IQ 작성·구독 관리 링크는 컴파일 타임 기본 off이며, 매니페스트의 cleartext는 debug/profile 소스셋에 격리되고 URL에 토큰 노출도 없다. 다만 웹 브릿지의 구독 쿼리 키('mentor')가 웹 실제 구현('mentorId')과 불일치해 동선을 켜는 순간 깨지고, 스토어 빌드에 노출되는 구독 관리 안내 문구가 자체 '웹 언급 금지' 의도와 모순돼 심사 리스크가 있다. 푸시 골격은 저장소에 문서화된 활성화 절차를 그대로 따를 경우 재로그인 시 토큰 정합성이 깨져 이전 계정 알림이 오배송되는 잠복 결함을 안고 있다. 딥링크는 아직 스텁(파싱 없음)이라 임의 경로 내비게이션 위험은 현재 없다.

**화면·상태 관리** — 앱 화면 계층은 전반적으로 mounted 체크·포트 주입·컨트롤러 dispose가 잘 지켜져 있으나, 필기·주석 파이프라인에 기능을 실제로 깨뜨리는 결함 2건(질문방 주석 평탄화 PNG의 5MB 초과 업로드 거부, 뷰포트 변경 시 좌표 정합 오염)이 있습니다. 또한 프로젝트가 스스로 버그로 규정하고 3곳에서 수정한 setState 화살표-Future 패턴이 아직 9곳에 남아 있고, 게시판 무한스크롤의 카테고리 전환 경합, 댓글 전송 후 mounted 미확인 setState, 첨부 썸네일의 원본 해상도 디코딩(메모리) 등 중간 심각도 문제가 다수 확인됐습니다. Commerce-Zero·append 전용 메시지 등 의도된 설계는 결함으로 취급하지 않았습니다.

## 발견사항 목록

| # | 심각도 | 제목 | 위치 |
|---|---|---|---|
| 1 | 🟠 높음 | createThread가 status를 보내지 않아 DB 기본값 'open'으로 생성 — 주간 질문 한도 우회 + 상태 워크플로 전면 붕괴 | `lib/features/question_room/data/question_room_write_repository.dart:46` |
| 2 | 🟡 중간 | 정지(suspended) 만료 자동 해제를 앱이 무시 — 정지 이력이 있으면 앱에서 무기한 차단 | `lib/core/auth/account_status.dart:86` |
| 3 | 🟡 중간 | 일시적 프로필 조회 실패를 계정 차단으로 취급 — role 조회만 실패하면 '다시 시도' 없이 로그아웃 강제 | `lib/core/auth/auth_service.dart:168` |
| 4 | 🟡 중간 | 세션(리프레시 토큰)이 평문 SharedPreferences 에 저장되고 Android 백업 차단도 없음 | `lib/core/supabase/supabase_client.dart:14` |
| 5 | 🟡 중간 | 숏폼 스크랩 토글이 DB CHECK·RLS(type='like'만 허용)에 항상 막혀 100% 실패 | `lib/features/community/data/community_write_repository.dart:62` |
| 6 | 🟡 중간 | 멘토 화면 학생 이름 조회가 맞춤의뢰 전용 RPC를 사용 — 구독 질문방 학생은 전원 '학생' 폴백 | `lib/features/question_room/data/student_lookup_repository.dart:54` |
| 7 | 🟡 중간 | 커뮤니티 페이지네이션: DB range 이후 차단 필터링으로 페이지 축소 — hasMore 오판·offset 드리프트(목록 조기 종료/중복) | `lib/features/community/data/community_read_repository.dart:47` |
| 8 | 🟡 중간 | 멘토의 자유 라벨 과목(예: '코딩') 선택 시 question_threads.subject FK 위반으로 질문 등록 실패 | `lib/data/mappings/subject_labels.dart:146` |
| 9 | 🟡 중간 | MentorLookupRepository.fetchMany가 멘토 수만큼 직렬 RPC 호출(N+1) | `lib/features/question_room/data/mentor_lookup_repository.dart:61` |
| 10 | 🟡 중간 | 스토어 빌드에 노출되는 구독 관리 안내 문구가 '웹 언급 없이' 원칙과 모순 — 심사 리젝 위험 | `lib/core/commerce/commerce_policy.dart:21` |
| 11 | 🟡 중간 | device_tokens upsert가 자체 명세한 RLS 정책과 충돌 — 재로그인 시 토큰 정합성 깨짐·이전 계정 푸시 오배송 | `lib/core/push/device_token_registrar.dart:28` |
| 12 | 🟡 중간 | 질문방 주석 전송: 평탄화 PNG를 축소 없이 업로드해 5MB 검증에 걸려 전송이 항상 실패 가능 | `lib/features/scan_annotation/data/scan_annotation_repository.dart:60` |
| 13 | 🟡 중간 | 주석 화면: 뷰포트 변경(회전·창 크기 변경) 시 기존 스트로크 좌표가 재변환되지 않아 저장 좌표·평탄화 결과가 오염됨 | `lib/features/scan_annotation/scan_annotation_screen.dart:243` |
| 14 | 🟡 중간 | setState 화살표 클로저가 Future를 반환하는 패턴(프로젝트가 버그로 규정·3곳 수정)이 9개 화면에 잔존 | `lib/features/question_room/ui/mentor/mentor_question_list_screen.dart:51` |
| 15 | 🟡 중간 | 게시판 무한스크롤: 카테고리 전환·reload와 진행 중 _loadMore가 경합해 다른 카테고리 페이지가 목록에 섞임 | `lib/features/community/ui/board/board_list_view.dart:86` |
| 16 | 🟡 중간 | 채팅 이미지 썸네일: cacheWidth 미지정으로 최대 4096px 원본을 전체 해상도로 디코딩 — 스레드당 수백 MB 메모리 | `lib/features/question_room/ui/widgets/message_image_attachment.dart:65` |
| 17 | 🟡 중간 | downscaleIfOversized: UI isolate에서 순수 Dart 디코드·전체 픽셀 투명도 스캔·재인코딩 — 대형 사진에서 수 초 UI 정지 | `lib/core/scan/image_downscaler.dart:22` |
| 18 | 🟡 중간 | 채팅 전송 실패 시 finally가 대기 첨부 이미지를 무조건 폐기 — 촬영 사진 등 사용자 작업물 유실 | `lib/features/question_room/ui/chat_screen.dart:211` |
| 19 | ⚪ 낮음 | 로그아웃과 경쟁하는 미대기(unawaited) 프로필 로드가 초기화된 상태를 되살릴 수 있음 | `lib/core/auth/auth_service.dart:123` |
| 20 | ⚪ 낮음 | 로그인 시도 '전에' 게스트 상태를 소거하고 실패 시 복구·통지가 없음 | `lib/core/auth/auth_service.dart:198` |
| 21 | ⚪ 낮음 | 삭제(deleted) 계정이 '상태 불명·잠시 후 다시 시도' 로 안내되고 재시도 버튼까지 노출됨 | `lib/core/auth/account_status.dart:88` |
| 22 | ⚪ 낮음 | 게스트 모드에서 IndexedStack 이 보호 탭을 전부 빌드해 인증 필요 쿼리를 실행 | `lib/app/home_shell.dart:110` |
| 23 | ⚪ 낮음 | 부팅·로그인 시 프로필 이중 로드 + 같은 users 행 2회 분할 조회 | `lib/core/auth/auth_service.dart:110` |
| 24 | ⚪ 낮음 | AuthService.entitlement 캐시는 소비처가 없고, 다중 구독 시 plan_tier 를 임의 선택 | `lib/core/entitlement/entitlement.dart:38` |
| 25 | ⚪ 낮음 | 멘토 요금제 조회에 is_active 필터 누락 — 활동 중단 멘토의 비활성 플랜도 활성 가격으로 표시 | `lib/features/mentors/data/mentor_directory_repository.dart:161` |
| 26 | ⚪ 낮음 | 서명 URL 캐시 TTL이 URL 만료시간과 동일 — 만료 직전 URL을 유효한 것으로 반환 | `lib/features/question_room/data/attachments/attachment_url_resolver.dart:51` |
| 27 | ⚪ 낮음 | 웹 브릿지 구독 딥링크 쿼리 파라미터가 웹 실제 구현과 불일치 (mentor vs mentorId) | `lib/core/web_bridge/web_bridge.dart:35` |
| 28 | ⚪ 낮음 | 디바이스 토큰 등록 시 platform이 항상 'android'로 기록 — iOS 기기 오분류 | `lib/core/push/push_service.dart:70` |
| 29 | ⚪ 낮음 | PushPayload.fromRemote의 무방비 캐스트 — 비문자열 type 값 수신 시 TypeError 크래시 | `lib/core/push/push_payload.dart:74` |
| 30 | ⚪ 낮음 | kInAppPaymentSteeringEnabled는 어떤 코드도 읽지 않는 죽은 스위치 — '단일 제어점' 주석이 허위 | `lib/core/commerce/commerce_policy.dart:9` |
| 31 | ⚪ 낮음 | WEB_BASE_URL 주입값의 끝 슬래시 미정규화 — '//경로' 형태의 비정상 URL 생성 | `lib/core/web_bridge/web_bridge.dart:78` |
| 32 | ⚪ 낮음 | 댓글 전송·IQ 액션: await 뒤 mounted 확인 없이 setState/컨트롤러 사용 (setState after dispose 경로) | `lib/features/community/ui/board/board_detail_screen.dart:169` |
| 33 | ⚪ 낮음 | IQ 상세 첨부: build마다 새 서명 URL Future 생성(FutureBuilder 안티패턴) — 리빌드 때마다 재요청·이미지 깜빡임 | `lib/features/individual_question/ui/iq_detail_screen.dart:553` |
| 34 | ⚪ 낮음 | IQ 목록 당겨서 새로고침: onRefresh가 즉시 완료돼 인디케이터가 로딩과 무관하게 사라짐 | `lib/features/individual_question/ui/student_iq_list_screen.dart:130` |

## 상세 발견사항

### 🟠 높음 (high)

#### 1. 🟠 createThread가 status를 보내지 않아 DB 기본값 'open'으로 생성 — 주간 질문 한도 우회 + 상태 워크플로 전면 붕괴

| | |
|---|---|
| **심각도** | 높음 (high) |
| **분류** | 정합성/한도우회 |
| **위치** | `lib/features/question_room/data/question_room_write_repository.dart:46` |
| **판정** | 확정(CONFIRMED) · app-data |

**문제**

웹은 질문 생성 시 status:'pending'을 명시적으로 넣지만(웹 lib/qna/questionRoomMutations.ts:96), 앱 createThread는 status를 생략해 DB 기본값 'open'(웹 002_p0_subscriptions_questions_draft.sql:168 `status text default 'open'`)으로 저장된다. 이후 마이그레이션(032)은 CHECK만 바꿨고 기본값·트리거는 그대로다. 결과: (1) 주간 사용량 RPC(098_weekly_usage_count_on_create.sql:85)는 status in ('pending','answered','confirmed','closed','archived')만 세므로 'open' 스레드는 영원히 카운트되지 않아, 앱에서 만든 질문은 라이트(주4)/스탠다드(주9) 한도를 전혀 소모하지 않는다(사실상 무제한). (2) 멘토 답변 화면은 `_status == ThreadStatus.pending`일 때만 markThreadAnswered를 호출(mentor_answer_screen.dart:196)하므로 'open' 스레드는 answered로 전이되지 않고, 학생 확인 버튼도 status==answered에서만 노출(question_list_screen.dart:128)돼 앱발 질문은 '답변 완료'에 도달할 수 없다. (3) 멘토 대시보드 pending 집계(ThreadStatusCounts)에서도 답변 대기로 잡히지 않는다.

**근거 코드**

```
// question_room_write_repository.dart:36-53
/// 스레드 생성. status 는 보내지 않고 DB 기본값('open')에 맡긴다.
Future<QuestionThread> createThread({...}) async {
  final Map<String, dynamic> row = await _client
      .from('question_threads')
      .insert(<String, dynamic>{
        'mentor_student_room_id': roomId,
        if (title != null) 'title': title, ...

-- 웹 098_weekly_usage_count_on_create.sql:85 ('open' 미포함)
and lower(coalesce(qt.status, '')) in ('pending', 'answered', 'confirmed', 'closed', 'archived')

// 웹 lib/qna/questionRoomMutations.ts:96
const base = { [roomColumn]: roomId, [t]: title, status: "pending" };
```

**권고**

createThread INSERT에 웹과 동일하게 'status': 'pending'을 명시한다. 기존 앱 생성분('open' + first_answered_at null) 백필과, 서버측 기본값을 'pending'으로 바꾸는 마이그레이션도 웹 팀과 협의해 병행하는 것이 안전하다.

---

### 🟡 중간 (medium)

#### 2. 🟡 정지(suspended) 만료 자동 해제를 앱이 무시 — 정지 이력이 있으면 앱에서 무기한 차단

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | cross-repo-consistency |
| **위치** | `lib/core/auth/account_status.dart:86` |
| **판정** | 확정(CONFIRMED) · app-auth |

**문제**

웹 정본(ssambership_web/lib/auth/accountStatus.ts)은 suspended 상태라도 suspended_until 이 지났으면 active 로 간주하는 lazy 해제 규약이며, 관리자 정지 액션(accountStatusCore.ts)은 suspended_until(7일/30일)만 기록하고 DB status 를 자동으로 'active' 로 되돌리지 않는다(102_account_status_management.sql 주석: '앱 가드가 lazy 판정'). 그런데 앱 AccountStatusReader 는 status 컬럼만 조회하고 suspended_until 을 아예 읽지 않아, status=='suspended' 면 만료 여부와 무관하게 무조건 차단한다. 결과: 7일 정지가 끝나 웹에서는 정상 이용 가능한 사용자가 앱에서는 관리자가 수동으로 status 를 되돌리기 전까지 영구 차단된다. 71줄 주석 '클라우드 users 스키마엔 status 만 존재(status_reason·suspended_until 없음)' 는 웹 102 SQL(운영 적용 대상: 예 — suspended_until·status_reason 컬럼 추가)과 모순되는 잘못된 전제다.

**근거 코드**

```
// 클라우드 users 스키마엔 status 만 존재(status_reason·suspended_until 없음).
...
.select('status')
...
case 'suspended':
  return const AccountState(kind: AccountStatusKind.suspended);

(웹 정본 accountStatus.ts) if (raw === "suspended") { ... if (until.getTime() <= now.getTime()) { return "active"; // 정지 기간 만료 → 자동 해제 } }
```

**권고**

select('status, suspended_until') 로 조회하고, suspended 이면서 suspended_until 이 현재 시각 이전이면 웹과 동일하게 active 로 간주한다(AccountState.suspendedUntil 필드는 이미 존재하므로 채우기만 하면 차단 화면의 '해제 예정' 표시도 함께 살아난다). 컬럼 부재 환경 호환이 걱정되면 웹 assertAccountActive 처럼 조회 실패 시 폴백 분기를 명시한다.

---

#### 3. 🟡 일시적 프로필 조회 실패를 계정 차단으로 취급 — role 조회만 실패하면 '다시 시도' 없이 로그아웃 강제

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | error-handling |
| **위치** | `lib/core/auth/auth_service.dart:168` |
| **판정** | 확정(CONFIRMED) · app-auth |

**문제**

_readRole 은 예외를 삼키고 AppRole.guest 를 반환하며, AccountStatusReader 도 예외 시 unknown 을 반환한다(보수 차단 자체는 의도된 설계). 문제는 매 토큰 갱신(_onAuthChange)마다 프로필을 재조회하므로, 사용 중 일시적 네트워크 오류가 나면 access 가 blocked 로 바뀌어 EntryGuard 가 어떤 화면에서든 /blocked 로 강제 이동시키고 내비게이션 상태를 잃는다는 점이다. 특히 role 조회만 실패하고 status 조회는 성공(active)한 부분 실패에서는 _account.kind 가 unknown 이 아니어서 isRecoverableBlock=false → 차단 화면에 '다시 시도' 버튼 없이 '로그아웃'만 노출되어, 일시 오류인데도 사용자가 세션을 버리는 것 외에 복구 수단이 없다. 오프라인 콜드 스타트도 유효 세션인데 '계정 상태를 확인할 수 없어요' 차단 화면으로 안내되어 네트워크 문제를 계정 문제로 오인시킨다.

**근거 코드**

```
} catch (_) {
  return AppRole.guest;
}
...
// role 불명(트리거 미생성 등) → 보수적으로 차단.
return AccessState.blocked;
...
bool get isRecoverableBlock =>
    isSignedIn &&
    _account.kind == AccountStatusKind.unknown &&
    _role != AppRole.admin;
```

**권고**

role 조회 실패를 '역할 없음(guest)'과 구분되는 실패 상태(예: AppRole? null 또는 별도 플래그)로 표기하고, 실패 유래 차단은 항상 isRecoverableBlock=true 로 재시도를 제공한다. 토큰 갱신 시 재조회 실패는 직전 정상 프로필을 유지(성공 시에만 교체)하는 편이 안전하다 — 차단 판정 자체는 최신 성공 조회 기준으로 유지된다.

---

#### 4. 🟡 세션(리프레시 토큰)이 평문 SharedPreferences 에 저장되고 Android 백업 차단도 없음

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | insecure-storage |
| **위치** | `lib/core/supabase/supabase_client.dart:14` |
| **판정** | 확정(CONFIRMED) · app-auth |

**문제**

Supabase.initialize 를 authOptions 없이 호출해 supabase_flutter 2.x 기본 localStorage(SharedPreferences, 비암호화 평문)를 그대로 쓴다. 장기 유효한 리프레시 토큰이 앱 데이터 XML 에 평문으로 남는다. 게다가 android/app/src/main/AndroidManifest.xml 은 android:allowBackup 을 명시하지 않아 기본값 true — 자동 백업 경로로 토큰이 기기 밖(클라우드 백업)으로 복사될 수 있고, 백업 복원을 통한 세션 탈취 면이 열린다. HANDOFF.md 의 'service_role 금지·anon+RLS' 원칙과 별개로 클라이언트 세션 보관 하드닝이 빠져 있다.

**근거 코드**

```
await Supabase.initialize(
  url: AppConfig.supabaseUrl,
  anonKey: AppConfig.anonKey,
);

(AndroidManifest.xml — allowBackup 미지정)
<application
    android:label="@string/app_name"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher">
```

**권고**

FlutterAuthClientOptions(localStorage: ...) 로 flutter_secure_storage(Keystore/Keychain) 기반 저장소를 주입하고, AndroidManifest 에 android:allowBackup="false"(또는 backup rules 로 shared_prefs 제외)를 명시한다. 출시(스토어 제출) 전 반영이 바람직하다.

---

#### 5. 🟡 숏폼 스크랩 토글이 DB CHECK·RLS(type='like'만 허용)에 항상 막혀 100% 실패

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | 런타임버그/스키마불일치 |
| **위치** | `lib/features/community/data/community_write_repository.dart:62` |
| **판정** | 확정(CONFIRMED) · app-data |

**문제**

toggleShortformReaction은 type에 'scrap'을 그대로 insert하지만, 웹 스키마 shortform_reactions는 `type text not null default 'like' check (type in ('like'))`(082_community_shortform_likes.sql:24)이고 INSERT RLS도 `and type = 'like'`로 이중 차단한다. 숏폼 상세 화면의 스크랩 버튼(shortform_detail_screen.dart:102-117, reactionScrap 전달)은 매번 예외 → 낙관적 상태 롤백 + '처리에 실패했어요' 스낵바로 끝난다. 즉 앱의 숏폼 스크랩 기능은 어떤 사용자도 성공할 수 없다. myShortformReactionIds('scrap')도 항상 빈 집합이다.

**근거 코드**

```
// community_write_repository.dart:54-66
/// 숏폼 반응 토글(좋아요/스크랩).
Future<void> toggleShortformReaction({... required String type, ...}) async {
  if (on) {
    await _client.from('shortform_reactions').insert(<String, dynamic>{
      'user_id': uid,
      'shortform_id': shortformId,
      'type': type,   // 'scrap' 전달 시 CHECK 위반
    });

-- 웹 082_community_shortform_likes.sql:24
type text not null default 'like' check (type in ('like')),
-- INSERT 정책: with check ( user_id = (select auth.uid()) and type = 'like' )
```

**권고**

DB에 scrap을 허용(CHECK·RLS 확장)하기 전까지 앱에서 숏폼 스크랩 버튼을 제거하거나 비활성화한다. 유지하려면 웹 저장소에 shortform_reactions CHECK/RLS를 ('like','scrap')으로 확장하는 마이그레이션을 먼저 적용해야 한다.

---

#### 6. 🟡 멘토 화면 학생 이름 조회가 맞춤의뢰 전용 RPC를 사용 — 구독 질문방 학생은 전원 '학생' 폴백

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | 정합성/잘못된RPC |
| **위치** | `lib/features/question_room/data/student_lookup_repository.dart:54` |
| **판정** | 확정(CONFIRMED) · app-data |

**문제**

fetchMany가 호출하는 `get_mentor_student_nicknames`(웹 058_mentor_student_nickname_rpc.sql)는 `exists (select 1 from custom_request_orders o where o.mentor_id = auth.uid() and o.student_id = u.id)` 조건으로, '맞춤의뢰 주문으로 연결된 학생'만 이름을 반환한다. 앱은 이를 멘토 질문방 학생 목록(mentor_inbox_screen.dart:74)과 마이페이지(mypage_repository.dart:192)에서 mentor_student_rooms(구독) 기반 학생들에 사용한다. 맞춤의뢰는 앱 범위 밖(HANDOFF §4)이므로 구독만으로 연결된 학생은 RPC가 0행을 돌려주고, 멘토의 받은-학생 목록은 전부 '학생'이라는 동일 폴백 이름으로 표시돼 구분이 불가능해진다. 스키마와 대조로 확인되는 잘못된 RPC 선택이다.

**근거 코드**

```
// student_lookup_repository.dart:54-57
final dynamic res = await _client.rpc(
  'get_mentor_student_nicknames',
  params: <String, dynamic>{'p_student_ids': unique},
);

-- 웹 058_mentor_student_nickname_rpc.sql (반환 조건)
and exists (
  select 1
  from public.custom_request_orders o
  where o.mentor_id = (select auth.uid())
    and o.student_id = u.id
)
```

**권고**

웹 저장소에 mentor_student_rooms 연결 기준의 SECURITY DEFINER RPC(예: rooms 당사자 학생 id[] → nickname/full_name)를 추가하고 앱이 그것을 호출하도록 교체한다. 임시로는 기존 RPC의 exists 절에 mentor_student_rooms 조건을 OR로 추가하는 방법도 있다.

---

#### 7. 🟡 커뮤니티 페이지네이션: DB range 이후 차단 필터링으로 페이지 축소 — hasMore 오판·offset 드리프트(목록 조기 종료/중복)

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | 페이지네이션 |
| **위치** | `lib/features/community/data/community_read_repository.dart:47` |
| **판정** | 확정(CONFIRMED) · app-data |

**문제**

boards()/shortforms()/comments()는 `.range(offset, offset+limit-1)`로 DB에서 limit개를 받은 뒤 _dropBlocked로 차단 작성자 행을 제거해 반환한다. 호출부(board_list_view.dart:74,90-95 / shortform_feed_view.dart:62,79)는 `_hasMore = page.length == _pageSize`와 `offset: _posts.length`를 쓰므로, 차단 사용자가 1명이라도 페이지에 섞이면 (1) 반환 길이 < pageSize가 되어 뒤 페이지가 남았는데도 페이징이 조기 종료되고, (2) 다음 offset이 '필터 후 개수' 기준으로 계산돼 raw offset과 어긋나 이미 받은 행을 다시 받는다(중복 표시). 필터 전 원본 개수를 함께 반환하는 notifications_repository의 NotificationsPage(hasMore=원본 행 수 기준) 패턴과 달리 이 레포는 정보를 유실한다.

**근거 코드**

```
// community_read_repository.dart:46-50
q = q.order('created_at', ascending: false);
if (limit != null) q = q.range(offset, offset + limit - 1);
final Future<Set<String>> blockedF = _blocks.myBlockedIds();
final List<Map<String, dynamic>> rows = await q;
return _dropBlocked(rows, await blockedF).map(BoardPost.fromMap).toList();

// board_list_view.dart:90-95 (호출부)
final List<BoardPost> page = await widget.read.boards(
    category: _category, limit: _pageSize, offset: _posts.length);
_hasMore = page.length == _pageSize;
```

**권고**

notifications처럼 (items, rawCount 또는 hasMore)를 함께 돌려주는 페이지 타입으로 바꾸고, 호출부 offset은 raw 행 수 누적으로 계산한다. 대안: 차단 id를 쿼리 단계에서 `not.in` 필터로 제외해 필터 전·후 개수를 일치시킨다.

---

#### 8. 🟡 멘토의 자유 라벨 과목(예: '코딩') 선택 시 question_threads.subject FK 위반으로 질문 등록 실패

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | 엣지케이스/FK위반 |
| **위치** | `lib/data/mappings/subject_labels.dart:146` |
| **판정** | 확정(CONFIRMED) · app-data |

**문제**

mentorSubjectCodesStrict는 정본 코드로 정규화되지 않는 teaching_subjects 값(자유 라벨)을 '버리지 않고 원값 그대로' 드롭다운 후보에 남기고, new_question_screen은 선택값을 그대로 createThread(subject:)로 보낸다. 그러나 DB는 `question_threads.subject text references public.subjects(code)`(웹 060_ai_readiness_question_schema.sql:35-36)라 subjects 카탈로그에 없는 값은 FK 위반으로 INSERT 전체가 실패한다('질문 등록에 실패했어요'). 웹은 normalizeQuestionSubjectCode 실패 시 subject 대신 topic/category로만 보내 이 문제를 피한다(questionRoomMutations.ts buildThreadPayloads). 자유 라벨을 후보에 노출하는 목적 자체가 무의미해지는 자기모순이다.

**근거 코드**

```
// subject_labels.dart:143-148
for (final String raw in mentorTeachingCodes) {
  final String t = raw.trim();
  if (t.isEmpty) continue;
  final String code = normalizeSubjectCode(t) ?? t; // 자유 라벨은 원값 유지
  if (seen.add(code)) out.add(code);
}

-- 웹 060:35-36
alter table public.question_threads
  add column if not exists subject text references public.subjects(code);
```

**권고**

createThread 직전(또는 레포 계층)에서 subject를 normalizeSubjectCode로 재검증해, 카탈로그 밖 값이면 subject 대신 topic으로 강등해 저장한다(웹과 동일 관용). 또는 드롭다운 후보에서 비정규 값은 표시만 하고 저장 시 'etc'로 매핑한다.

---

#### 9. 🟡 MentorLookupRepository.fetchMany가 멘토 수만큼 직렬 RPC 호출(N+1)

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | 성능/N+1 |
| **위치** | `lib/features/question_room/data/mentor_lookup_repository.dart:61` |
| **판정** | 확정(CONFIRMED) · app-data |

**문제**

fetchMany는 id마다 `mentor_user_public_v2` RPC를 for 루프에서 await로 순차 호출한다. 학생 질문방 목록(question_room_screen.dart:98)과 마이페이지 구독 카드(mypage_repository.dart:87)가 방/구독 멘토 전체에 대해 이를 호출하므로, 멘토 N명이면 N번의 직렬 왕복이 발생해 목록 로딩이 선형으로 느려진다. 같은 화면 흐름에서 StudentLookupRepository는 배열 인자 RPC 1회로 처리하고 있고, 디렉터리용 배치 RPC(mentor_directory_list_v2·mentor_profiles_for_directory_v2(p_ids uuid[]))도 이미 존재해 배치 패턴의 선례가 있다.

**근거 코드**

```
// mentor_lookup_repository.dart:58-65
Future<Map<String, MentorPublic>> fetchMany(Iterable<String> ids) async {
  final Map<String, MentorPublic> out = <String, MentorPublic>{};
  for (final String id in ids.toSet()) {
    final MentorPublic? m = await fetch(id);   // id당 RPC 1회, 직렬 await
    if (m != null) out[id] = m;
  }
  return out;
}
```

**권고**

최소한 Future.wait로 병렬화하고, 근본적으로는 uuid[] 인자를 받는 배치 RPC(예: mentor_users_public_v2(p_ids uuid[]))를 웹 저장소에 추가해 1회 호출로 교체한다.

---

#### 10. 🟡 스토어 빌드에 노출되는 구독 관리 안내 문구가 '웹 언급 없이' 원칙과 모순 — 심사 리젝 위험

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | policy-compliance |
| **위치** | `lib/core/commerce/commerce_policy.dart:21` |
| **판정** | 확정(CONFIRMED) · app-bridge |

**문제**

kSubscriptionManageNoticeText의 doc 주석은 '(웹 언급 없이 — 죽은 버튼·빈 공백 방지)'라고 명시하는데 실제 문자열은 '구독 변경·해지는 웹 계정에서 관리돼요'로 '웹'을 직접 언급한다. 이 문구는 kSubscriptionManageLinkEnabled=false인 스토어 기본 빌드에서 마이페이지에 항상 렌더된다(lib/features/mypage/ui/sections/student_subscription_section.dart:86). 프로젝트가 구독 관리 링크 자체를 스토어 빌드에서 숨긴 이유(Play 결제 정책 판단 확정 전 리스크 회피)와 정면으로 상충하며, Apple 3.1.1/Play 결제 정책의 외부 결제 유도(steering) 판단 대상이 될 수 있는 표현이다. 같은 파일의 kSubscribeNoticeText·kRechargeNoticeText는 웹 언급 없이 작성돼 있어 이 상수만 원칙에서 벗어난다.

**근거 코드**

```
/// 구독 관리 링크 off 시 대체 안내(웹 언급 없이 — 죽은 버튼·빈 공백 방지).
const String kSubscriptionManageNoticeText = '구독 변경·해지는 웹 계정에서 관리돼요';
```

**권고**

문구를 웹/외부 결제처를 언급하지 않는 중립 표현(예: '구독 변경·해지는 가입한 계정에서 관리돼요')으로 교체하거나, 최소한 doc 주석과 실값의 모순을 해소하고 스토어 심사 게이트 문서(docs/PLAY_STORE_REVIEW_PLAN.md)에서 이 문구를 검토 항목으로 등재할 것.

---

#### 11. 🟡 device_tokens upsert가 자체 명세한 RLS 정책과 충돌 — 재로그인 시 토큰 정합성 깨짐·이전 계정 푸시 오배송

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | data-integrity |
| **위치** | `lib/core/push/device_token_registrar.dart:28` |
| **판정** | 확정(CONFIRMED) · app-bridge |

**문제**

register()는 token을 고유키로 upsert하며 '같은 기기 재로그인 시 user_id 갱신'을 의도한다. 그러나 같은 저장소의 활성화 명세(lib/core/push/HANDOFF.md:35-36)가 지정한 RLS 정책은 `for all using (auth.uid() = user_id)`라서, 기기 공유·계정 전환 시 기존 행의 user_id가 이전 사용자이므로 새 사용자의 upsert UPDATE 경로가 RLS에 막힌다(등록 실패). 결과적으로 token→이전 user_id 매핑이 잔존하고, 로그아웃 시 unregister()(push_service.dart:74)는 앱 어디서도 호출되지 않아(HANDOFF 활성화 4단계에도 없음) 이전 계정의 답변·질문 알림(스레드 제목 포함)이 새 사용자가 쓰는 기기로 계속 발송된다. 현재 _tableExists=false로 잠복 상태지만, HANDOFF가 지시하는 그대로(테이블 생성+플래그 true) 활성화하면 코드 수정 없이 이 결함이 그대로 켜진다.

**근거 코드**

```
// token 고유키로 upsert — 같은 기기 재로그인 시 user_id 갱신.
await client.from('device_tokens').upsert(
  <String, dynamic>{
    'user_id': userId,
    'token': token, ...
  },
  onConflict: 'token',
);
// HANDOFF.md DDL: create policy device_tokens_self ... for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

**권고**

① HANDOFF의 DDL을 수정해 토큰 재귀속을 지원(예: 본인 행 정책 + `delete where token=? via RPC(SECURITY DEFINER)` 후 insert, 또는 upsert 전 기존 행 삭제를 서버 함수로), ② AuthService 로그아웃 훅에서 PushService.unregister(token) 호출을 활성화 체크리스트(HANDOFF §4단계)에 명시적으로 추가할 것.

---

#### 12. 🟡 질문방 주석 전송: 평탄화 PNG를 축소 없이 업로드해 5MB 검증에 걸려 전송이 항상 실패 가능

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | upload-failure |
| **위치** | `lib/features/scan_annotation/data/scan_annotation_repository.dart:60` |
| **판정** | 확정(CONFIRMED) · app-ui |

**문제**

ScanAnnotationRepository.submit(질문방 S15 경로)은 평탄화 PNG를 downscaleIfOversized 없이 SupabaseAttachmentUploader.upload에 그대로 넘긴다. 업로더는 validatePickedImage로 5MB 초과를 거부한다(attachment_upload.dart:29-31 '이미지가 너무 커요. 5MB 이하로 올려주세요.'). 평탄화는 배경 원본 해상도의 PNG 인코딩(annotation_flattener.dart)이라, 촬영 사진(JPEG 2~4MB, 장변 4096px — S16 픽커 캡)은 PNG 재인코딩 시 통상 10MB 이상으로 팽창한다. 즉 채팅의 '주석 달기'(전송 전 미리보기·전송된 이미지 뷰어 양쪽 진입점)가 일반적인 사진 첨부에서 '주석 전송에 실패했어요' 로 항상 실패한다. 같은 문제를 IQ 첨삭 경로는 이미 인지하고 수정했다(iq_annotation_repository.dart:64-69에서 downscaleIfOversized 적용 — '§6-4 규약, S17과 동일 경로' 주석). 질문방 경로만 누락됐다.

**근거 코드**

```
// 1) 평탄화 PNG → 기존 첨부 파이프라인으로 전송(중복 구현 금지).
final QuestionAttachment attachment = await _uploader.upload(
  roomId: roomId,
  threadId: threadId,
  image: PickedImage(
    bytes: flattenedPng,
    fileName: fileName,
    mimeType: 'image/png',
  ),
);

// (대조) iq_annotation_repository.dart:64-69 — IQ 경로만 축소 적용:
// 평탄화 PNG 가 5MB 를 넘으면 업로드 전 축소(§6-4 규약 — S17 과 동일 경로).
final PickedImage image = await downscaleIfOversized(PickedImage(...));
```

**권고**

IQ 경로(iq_annotation_repository.submitAnnotation)와 동일하게, submit에서 _uploader.upload 직전 `await downscaleIfOversized(PickedImage(bytes: flattenedPng, ...))` 를 적용한다(불투명 배경이므로 JPEG 재인코딩으로 자연 축소됨). 축소 후에도 초과하면 기존 검증 문구로 안내.

---

#### 13. 🟡 주석 화면: 뷰포트 변경(회전·창 크기 변경) 시 기존 스트로크 좌표가 재변환되지 않아 저장 좌표·평탄화 결과가 오염됨

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | coordinate-transform |
| **위치** | `lib/features/scan_annotation/scan_annotation_screen.dart:243` |
| **판정** | 확정(CONFIRMED) · app-ui |

**문제**

스트로크는 그리는 시점의 캔버스-로컬 픽셀 좌표로 scribble notifier에 쌓이고, 정규화는 '완료' 시점(_onDone)에 최신 _mapper/_fitted 로 일괄 수행된다. LayoutBuilder가 회전·분할화면·창 리사이즈로 다시 실행되면 _mapper/_fitted 는 새 fitted 사각형으로 갱신되지만 notifier 안의 기존 스트로크 좌표는 옛 캔버스 크기 기준 그대로다. 결과: (1) 화면상 스트로크가 배경 이미지와 즉시 어긋나고, (2) _onDone 의 _normalizePoint(133-134행)가 새 fitted 로 정규화해 ink.json·평탄화 PNG 모두 잘못된 위치로 영구 저장된다. _restoreIfNeeded(141-152행)도 _restored 플래그로 1회만 수행돼 복원 스트로크 역시 이후 뷰포트 변경에 추종하지 못한다. 앱 어디에도 setPreferredOrientations 잠금이 없어(전역 검색 0건) 태블릿+스타일러스라는 이 기능의 주 사용 환경에서 회전만으로 재현된다.

**근거 코드**

```
final InkCoordinateMapper mapper = InkCoordinateMapper.contain(
  imageSize: imageSize,
  viewport: viewport,
);
_mapper = mapper;
_fitted = mapper.fitted;
_restoreIfNeeded();
...
/// 캔버스-로컬 좌표 → 이미지 정규화(저장용). (133-134행)
Offset _normalizePoint(Offset local) =>
    _mapper!.normalize(local + _fitted!.topLeft);
```

**권고**

LayoutBuilder에서 fitted 크기 변경을 감지하면 현재 sketch를 '이전 mapper로 정규화 → 새 mapper로 역정규화'해 setSketch로 재적재한다(_restoreIfNeeded와 동일한 AnnotationSketch.transform 재사용). 간단한 임시 방편으로는 이 화면 진입 동안 화면 방향을 잠그는 것도 가능.

---

#### 14. 🟡 setState 화살표 클로저가 Future를 반환하는 패턴(프로젝트가 버그로 규정·3곳 수정)이 9개 화면에 잔존

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | setstate-future |
| **위치** | `lib/features/question_room/ui/mentor/mentor_question_list_screen.dart:51` |
| **판정** | 확정(CONFIRMED) · app-ui |

**문제**

`setState(() => _future = _load())` 화살표 클로저는 할당식 값(Future)을 반환해 debug 빌드에서 'setState() callback argument returned a Future' FlutterError를 던지고 markNeedsBuild가 실행되지 않아 새로고침이 무산된다. 이 저장소는 이를 명시적으로 버그로 규정하고 3곳을 블록 바디로 수정했다(mentors_screen.dart:55 주석, question_list_screen.dart:58-60 주석, iq_detail_screen.dart:142-149 주석 — 'S18 부수 수정: setState-Future 버그'). 그러나 동일 패턴이 9곳에 남아 있다: mentor_question_list_screen.dart:51, mentor_inbox_screen.dart:96, mentor_room_home_screen.dart:63, student_room_home_screen.dart:85, connection_notes_screen.dart:79, question_room_screen.dart:120, mypage_screen.dart:62, student_iq_list_screen.dart:54, mentor_iq_list_screen.dart:68. 답변 화면에서 돌아올 때·프로필 저장 후·IQ 목록 당겨서 새로고침 등 핵심 새로고침 경로가 전부 이 코드를 지난다.

**근거 코드**

```
void _refresh() => setState(() => _future = _read.threads(widget.room.id));

// (프로젝트 자체 근거) question_list_screen.dart:58-60
// ★ 블록 바디로: setState(() => _future = future)는 클로저가 Future를 반환해
//   'setState callback returned a Future' 예외로 리빌드가 취소된다(목록 미갱신).
```

**권고**

9곳 모두 이미 수정된 3곳과 동일하게 블록 바디로 변경: `void _refresh() { final f = _load(); setState(() { _future = f; }); }`. flutter analyze 규칙(unnecessary_lambdas 아님 — 커스텀 lint 또는 grep 체크)으로 재발 방지.

---

#### 15. 🟡 게시판 무한스크롤: 카테고리 전환·reload와 진행 중 _loadMore가 경합해 다른 카테고리 페이지가 목록에 섞임

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | race-condition |
| **위치** | `lib/features/community/ui/board/board_list_view.dart:86` |
| **판정** | 확정(CONFIRMED) · app-ui |

**문제**

_loadMore는 호출 시점의 _category와 offset(_posts.length)으로 요청을 시작하는데, 응답 대기 중 사용자가 카테고리 칩을 바꾸면 _selectCategory→_loadFirst가 _posts를 비우고 새 카테고리 1페이지를 채운 뒤, 뒤늦게 도착한 이전 카테고리의 2페이지 응답이 세대 검증 없이 _posts.addAll로 덧붙는다(_hasMore도 낡은 응답 기준으로 덮임). 같은 이유로 빠른 카테고리 2연속 전환 시 두 _loadFirst 응답이 모두 addAll되어 서로 다른 카테고리 글이 혼합 표시된다. 글 작성 후 reload()(community_screen.dart:63)와 스크롤 중 _loadMore의 경합도 동일하다. shortform_feed_view.dart(74-90행)는 필터가 없어 카테고리 혼합은 없지만 같은 구조다.

**근거 코드**

```
Future<void> _loadMore() async {
  if (_loadingMore || !_hasMore || _initialLoading) return;
  setState(() => _loadingMore = true);
  try {
    final List<BoardPost> page = await widget.read.boards(
        category: _category, limit: _pageSize, offset: _posts.length);
    if (!mounted) return;
    setState(() {
      _posts.addAll(page);
      _hasMore = page.length == _pageSize;
```

**권고**

요청 세대 토큰(int _generation)을 두고 _loadFirst 진입 시 ++, _loadFirst/_loadMore 응답 반영 직전에 자신이 캡처한 세대와 현재 세대가 다르면 결과를 버린다. 또는 _loadFirst 시작 시 진행 중 _loadMore 결과를 무효화하는 플래그를 둔다.

---

#### 16. 🟡 채팅 이미지 썸네일: cacheWidth 미지정으로 최대 4096px 원본을 전체 해상도로 디코딩 — 스레드당 수백 MB 메모리

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | memory |
| **위치** | `lib/features/question_room/ui/widgets/message_image_attachment.dart:65` |
| **판정** | 확정(CONFIRMED) · app-ui |

**문제**

말풍선 썸네일(표시 크기 180/220 논리픽셀)이 Image.network를 cacheWidth/cacheHeight 없이 사용해 첨부 원본(5MB·장변 최대 4096px — S16 픽커 캡)이 전체 해상도로 디코딩된다. 4096×3072 이미지 1장의 디코딩 비트맵은 약 48MB(RGBA)로, 이미지 첨부가 여러 장인 스레드를 스크롤하면 저사양 기기에서 OOM·백그라운드 킬 위험이 크다. iq_detail_screen.dart의 _AttachmentsCard 인라인 Image.network(580행)도 동일하다(전체화면 뷰어는 원본 디코딩이 의도된 동작이라 제외).

**근거 코드**

```
return Image.network(
  url,
  width: widget.size,
  height: widget.size,
  fit: BoxFit.cover,
  loadingBuilder: ...,
  errorBuilder: ...,
);
```

**권고**

썸네일에는 `cacheWidth: (widget.size * MediaQuery.devicePixelRatioOf(context)).round()` 를 지정해 디코딩 해상도를 표시 크기로 제한한다. IQ 상세 인라인 이미지도 레이아웃 폭 기준 cacheWidth 지정.

---

#### 17. 🟡 downscaleIfOversized: UI isolate에서 순수 Dart 디코드·전체 픽셀 투명도 스캔·재인코딩 — 대형 사진에서 수 초 UI 정지

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | performance |
| **위치** | `lib/core/scan/image_downscaler.dart:22` |
| **판정** | 확정(CONFIRMED) · app-ui |

**문제**

5MB 초과 이미지에 대해 package:image(순수 Dart)의 decodeImage→copyResize→encodeJpg/Png를 메인 isolate에서 실행하고, _hasTransparency는 리사이즈된 이미지의 모든 픽셀을 Dart 루프로 순회한다. 12MP급 촬영 사진(수천만 픽셀)이면 중급 기기에서 수 초간 프레임이 완전히 멈춘다(스피너도 없음 — 동기 잔크). 호출부는 채팅(_acceptPicked, chat_screen.dart:262), 멘토 답변(mentor_answer_screen.dart:265), IQ 작성(iq_create_screen.dart:172 — 최대 5장 순차 루프, 207행 평탄화본)으로 모두 사용자 입력 직후의 상호작용 경로다.

**근거 코드**

```
final img.Image? decoded = img.decodeImage(image.bytes);
...
bool _hasTransparency(img.Image image) {
  if (!image.hasAlpha) return false;
  for (final img.Pixel p in image) {
    if (p.a < p.maxChannelValue) return true;
  }
  return false;
}
```

**권고**

본문 전체를 `Isolate.run`(또는 compute)으로 감싸 워커 isolate에서 수행한다(입출력이 Uint8List라 전송 비용 낮음). _hasTransparency는 hasAlpha && 포맷이 PNG일 때만 검사하거나 픽셀 샘플링으로 축소.

---

#### 18. 🟡 채팅 전송 실패 시 finally가 대기 첨부 이미지를 무조건 폐기 — 촬영 사진 등 사용자 작업물 유실

| | |
|---|---|
| **심각도** | 중간 (medium) |
| **분류** | data-loss |
| **위치** | `lib/features/question_room/ui/chat_screen.dart:211` |
| **판정** | 확정(CONFIRMED) · app-ui |

**문제**

_send의 finally 블록이 성공·실패를 구분하지 않고 `_pending = null`로 미리보기 이미지를 지운다. appendMessage가 네트워크 오류로 throw하거나 _uploadPending이 실패(내부 catch로 스낵바만 표시)해도 선택·촬영한 이미지가 화면에서 사라져 재선택/재촬영해야 한다. 특히 S16 '촬영' 소스는 원본이 앱 상태에만 있어 사실상 사진이 유실된다. mentor_answer_screen.dart:212-218도 동일. IQ 작성 화면은 반대로 '실패분은 _images에 남겨 재시도(작업물 유실 금지)'를 명시 구현하고 있어(iq_create_screen.dart:243-265) 정책 불일치이기도 하다.

**근거 코드**

```
} catch (e) {
  _showError('전송에 실패했어요. ${friendlyError(e)}');
} finally {
  if (mounted) {
    setState(() {
      _sending = false;
      _pending = null;
    });
  }
}
```

**권고**

_uploadPending이 성공 여부(bool)를 반환하게 하고, 성공했을 때만 _pending을 비운다. appendMessage 실패 시에도 _pending을 유지해 재전송 가능하게 한다.

---

### ⚪ 낮음 (low)

#### 19. ⚪ 로그아웃과 경쟁하는 미대기(unawaited) 프로필 로드가 초기화된 상태를 되살릴 수 있음

| | |
|---|---|
| **심각도** | 낮음 (low) |
| **분류** | race-condition |
| **위치** | `lib/core/auth/auth_service.dart:123` |
| **판정** | 확정(CONFIRMED) · app-auth |

**문제**

_onAuthChange 는 tokenRefreshed/signedIn 등에서 _loadProfile 을 unawaited 로 실행하고, signedOut 은 _resetProfile 로 즉시 초기화한다. 진행 중이던 _loadProfile 은 진입 시점에만 세션을 검사하므로, 그 사이 signedOut 이 처리되면 이미 유효 토큰으로 발사된 응답이 도착해 _role/_displayName/_account/_entitlement 를 로그아웃 이후에 다시 채운다. isSignedIn 재검사가 없어 로그아웃 상태에서 currentRole 이 student/mentor 로 남을 수 있고, 이는 roleLabel·테마(app.dart:23 AppTheme.build(currentRole)) 등 role 파생 상태에 반영된다. 취소·세대(sequence) 가드나 완료 후 세션 재확인이 전혀 없고, signInWithPassword 의 명시적 _loadProfile 과 이벤트 트리거 로드가 동시 실행되는 것도 같은 구조적 문제다.

**근거 코드**

```
// signedIn / tokenRefreshed / initialSession / userUpdated 등 → 프로필 재로드.
unawaited(_loadProfile().then((_) => notifyListeners()));
```

**권고**

_loadProfile 에 세대 카운터를 두어(시작 시 ++, 완료 시 최신 세대일 때만 필드 반영) 늦게 도착한 결과를 버리거나, 각 await 후·필드 대입 직전에 _session 재확인 후 세션이 사라졌으면 중단한다. signedOut 시 세대를 올려 in-flight 로드를 무효화하면 signInWithPassword 중복 로드도 함께 정리된다.

---

#### 20. ⚪ 로그인 시도 '전에' 게스트 상태를 소거하고 실패 시 복구·통지가 없음

| | |
|---|---|
| **심각도** | 낮음 (low) |
| **분류** | state-consistency |
| **위치** | `lib/core/auth/auth_service.dart:198` |
| **판정** | 확정(CONFIRMED) · app-auth |

**문제**

signInWithPassword 는 signInWithPassword 호출이 성공하기 전에 _guest = false 로 만들고, AuthException 으로 실패하면 원복도 notifyListeners 도 하지 않는다. 둘러보기(게스트) 중 보호 탭을 눌러 로그인 화면으로 온 사용자가 비밀번호를 틀리면 access 는 guest 에서 loggedOut 으로 조용히 바뀌지만 리스너에게 통지되지 않아(ChangeNotifier 계약 위반) 내부 상태와 라우터 판단 시점이 어긋난다. 실질 피해는 '둘러보기 재진입 필요' 수준이지만, 상태 변경-미통지 패턴은 이후 라우팅 개편 시 잠복 버그가 된다.

**근거 코드**

```
_guest = false;
await client.auth.signInWithPassword(
  email: email.trim(),
  password: password,
);
```

**권고**

_guest 소거를 signInWithPassword 성공 이후로 옮기거나, 실패 catch 에서 원래 값으로 복구한다. _guest 를 바꾸는 모든 경로에서 notifyListeners 를 호출해 상태-통지 일관성을 지킨다.

---

#### 21. ⚪ 삭제(deleted) 계정이 '상태 불명·잠시 후 다시 시도' 로 안내되고 재시도 버튼까지 노출됨

| | |
|---|---|
| **심각도** | 낮음 (low) |
| **분류** | account-status |
| **위치** | `lib/core/auth/account_status.dart:88` |
| **판정** | 확정(CONFIRMED) · app-auth |

**문제**

웹 정본 115_account_deletion.sql 은 탈퇴 시 users.status='deleted' 로 마킹한다(현재 플래그 미적용·배포 예정). 앱 AccountStatusReader 는 active/banned/suspended 외 값을 전부 unknown 으로 접어, deleted 계정은 차단은 되지만 안내 문구가 '계정 상태를 확인할 수 없어요. 잠시 후 다시 시도해 주세요' 이고 isRecoverableBlock=true 로 '다시 시도' 버튼까지 노출된다 — 영구적으로 성공할 수 없는 재시도를 유도하는 오안내다. 접근 차단 자체는 보수 분기로 유지되므로 보안 문제는 아니다.

**근거 코드**

```
default:
  // 알 수 없는 상태값은 통과시키지 않는다('active'만 통과).
  return AccountState.unknown;

(웹 115_account_deletion.sql:82) status = 'deleted',
```

**권고**

AccountStatusKind 에 deleted(또는 banned 재사용) 분기를 추가해 'deleted' 값을 명시 처리하고, 탈퇴 계정 전용 문구(재시도 비노출)를 둔다. 웹 115 플래그 ON 배포 전에 반영해 두는 것이 안전하다.

---

#### 22. ⚪ 게스트 모드에서 IndexedStack 이 보호 탭을 전부 빌드해 인증 필요 쿼리를 실행

| | |
|---|---|
| **심각도** | 낮음 (low) |
| **분류** | guest-access |
| **위치** | `lib/app/home_shell.dart:110` |
| **판정** | 확정(CONFIRMED) · app-auth |

**문제**

HomeShell 은 5개 탭 화면을 const 리스트로 IndexedStack 에 넣어 게스트 모드에서도 전부 인플레이트한다. 탭 '선택'은 _onSelect 에서 가드되지만 화면 생성은 막지 못해, 게스트 진입 즉시 NotificationsScreen.initState 가 notifications 테이블 조회를 발사하고(익명이라 RLS 로 빈 결과 — 낭비 호출), IndividualQuestionTabScreen 은 게스트를 StudentIqListScreen 으로 분기해 listForStudent 가 AppError('로그인이 필요해요') 를 던진 오류 상태를 화면 뒤에서 만들어 둔다. QuestionRoomScreen 만 guest 분기(EmptyState) 가 있어 세 보호 탭의 게스트 처리가 비일관하다.

**근거 코드**

```
body: IndexedStack(index: _index, children: _pages),

(notifications_screen.dart:52-55) void initState() { super.initState(); _repo = ...; _load(); }
(individual_question_tab_screen.dart:30-34) final bool isMentor = isMentorOverride ?? (AuthService.instance.currentRole == AppRole.mentor);
return isMentor ? ... : const StudentIqListScreen(embedded: true);
```

**권고**

QuestionRoomScreen 과 동일하게 NotificationsScreen·IndividualQuestionTabScreen 최상단에 guest 분기(EmptyState '로그인이 필요해요')를 추가하거나, HomeShell 에서 게스트일 때 보호 탭 자리에 로그인 안내 위젯을 넣어 데이터 화면 자체를 빌드하지 않는다.

---

#### 23. ⚪ 부팅·로그인 시 프로필 이중 로드 + 같은 users 행 2회 분할 조회

| | |
|---|---|
| **심각도** | 낮음 (low) |
| **분류** | efficiency |
| **위치** | `lib/core/auth/auth_service.dart:110` |
| **판정** | 확정(CONFIRMED) · app-auth |

**문제**

bootstrap 은 onAuthStateChange 구독 직후 _loadProfile 을 명시 호출하는데, gotrue 스트림은 구독 시 initialSession 이벤트를 즉시 방출하므로 _onAuthChange 가 같은 로드를 한 번 더 실행한다. signInWithPassword 도 signedIn 이벤트 로드와 명시 로드가 중복된다. 여기에 _loadProfile 내부가 _readRole(users.role)·_readDisplayName(users.nickname,full_name) 을 같은 users 행에 대해 별도 쿼리 2번으로 나눠 조회해, 콜드 스타트에 users 행만 최대 4회 읽는다. 정합성 문제는 없으나 시작 지연과 불필요 트래픽이다.

**근거 코드**

```
_authSub ??= client.auth.onAuthStateChange.listen(_onAuthChange);
await _loadProfile();
...
.select('role')
...
.select('nickname, full_name')
```

**권고**

role·nickname·full_name·status 를 단일 select 로 합치고, bootstrap 은 initialSession 이벤트 기반 로드 하나로 통일(또는 이벤트 핸들러에서 initialSession 을 스킵)한다. 2번 발견의 세대 가드를 도입하면 중복 로드 병합도 자연히 해결된다.

---

#### 24. ⚪ AuthService.entitlement 캐시는 소비처가 없고, 다중 구독 시 plan_tier 를 임의 선택

| | |
|---|---|
| **심각도** | 낮음 (low) |
| **분류** | dead-code |
| **위치** | `lib/core/entitlement/entitlement.dart:38` |
| **판정** | 확정(CONFIRMED) · app-auth |

**문제**

AuthService 는 학생 로그인·토큰 갱신마다 EntitlementReader.fetchForStudent 로 subscriptions 를 조회해 _entitlement 에 캐시하지만, 저장소 전체에서 AuthService.instance.entitlement 를 읽는 코드가 없다(화면들은 SubscriptionReader/mypage_repository 로 직접 조회). 즉 매 갱신마다 결과가 쓰이지 않는 쿼리가 나간다. 또한 쿼리가 .eq('status','active').limit(1) 을 정렬 없이 사용해, 멘토별 구독이 여러 건인 학생은 어떤 구독의 plan_tier 가 잡힐지 비결정적이다 — 향후 이 게터를 소비하기 시작하면 잠복 버그가 된다.

**근거 코드**

```
final List<Map<String, dynamic>> rows = await client
    .from('subscriptions')
    .select('status, plan_tier')
    .eq('student_id', studentId)
    .eq('status', 'active')
    .limit(1);
```

**권고**

당장 소비 계획이 없으면 _loadProfile 의 entitlement 조회를 제거해 갱신 비용을 줄이고, 유지한다면 멘토별 구독 구조에 맞게 '활성 구독 존재 여부' 만 담도록 의미를 좁히거나(count/exists), 정렬 기준(예: current_period_end desc)을 명시해 결정적으로 만든다.

---

#### 25. ⚪ 멘토 요금제 조회에 is_active 필터 누락 — 활동 중단 멘토의 비활성 플랜도 활성 가격으로 표시

| | |
|---|---|
| **심각도** | 낮음 (low) |
| **분류** | 정합성/규칙위반 |
| **위치** | `lib/features/mentors/data/mentor_directory_repository.dart:161` |
| **판정** | 확정(CONFIRMED) · app-data |

**문제**

레포 doc 주석(12-13행)과 모델 주석은 "mentor_plans (is_active=true)"를 명시하지만 실제 _activePlans 쿼리는 is_active를 select하지도 filter하지도 않는다. mentor_plans SELECT RLS는 `using (true)`(웹 004:243-246)로 전 행이 내려오고, MentorPlan.fromMap은 is_active 키 부재 시 true로 기본값을 채운다(mentor_models.dart:40). 웹 103_mentor_activity_suspension.sql은 멘토 활동 중단 시 is_active=false로 '신규 구독 노출/허용 게이트'를 걸었는데, 앱 멘토 찾기 목록·상세는 이 게이트를 우회해 중단 멘토의 가격을 '최저가 ~부터'로 계속 노출한다(가격낮은순 정렬에도 반영).

**근거 코드**

```
// mentor_directory_repository.dart:160-164
Future<Map<String, List<MentorPlan>>> _activePlans(List<String> ids) async {
  final List<Map<String, dynamic>> rows = await _client
      .from('mentor_plans')
      .select('mentor_id, plan_tier, amount_cents, label')
      .inFilter('mentor_id', ids);   // is_active 필터 없음

// mentor_models.dart:40
isActive: (map['is_active'] as bool?) ?? true,

-- 웹 103: is_active is '멘토 활동 중단 시 false. 신규 구독 노출/허용 게이트'
```

**권고**

select에 is_active를 포함하고 `.eq('is_active', true)` 필터를 추가한다(또는 파싱 후 isActive==true만 plans에 담는다). 기본값 폴백도 컬럼 부재 시에만 true가 되도록 유지하되 필터가 정본이 되게 한다.

---

#### 26. ⚪ 서명 URL 캐시 TTL이 URL 만료시간과 동일 — 만료 직전 URL을 유효한 것으로 반환

| | |
|---|---|
| **심각도** | 낮음 (low) |
| **분류** | 엣지케이스 |
| **위치** | `lib/features/question_room/data/attachments/attachment_url_resolver.dart:51` |
| **판정** | 확정(CONFIRMED) · app-data,app-ui |

**문제**

AttachmentUrlResolver.signedUrl은 만료 1시간짜리 서명 URL을 발급받은 뒤 캐시 만료 시각을 `_now().add(_ttl)`(발급 시점+1h)로 저장한다. 즉 캐시 유효 판정과 실제 URL 만료가 같은 시각이라, 만료 몇 초 전에 조회하면 곧 죽을 URL을 돌려주고 이미지 로딩·외부 앱 열기(chat_screen._openFile)가 403으로 실패할 수 있다. 발급~저장 사이의 네트워크 지연만큼은 캐시가 실제 만료보다 늦게 만료되는 역전도 있다.

**근거 코드**

```
// attachment_url_resolver.dart:44-52
Future<String> signedUrl(String storagePath) async {
  final _CachedUrl? cached = _cache[storagePath];
  if (cached != null && _now().isBefore(cached.expiresAt)) {
    return cached.url;
  }
  final int seconds = _ttl.inSeconds;
  final String url = await _backend.createSignedUrl(storagePath, seconds);
  _cache[storagePath] = _CachedUrl(url, _now().add(_ttl));  // URL 만료와 동일 시각
```

**권고**

캐시 만료를 실제 URL 만료보다 앞당긴 안전 마진(예: `_now().add(_ttl - const Duration(minutes: 5))`, 발급 '요청 전' 시각 기준)으로 저장해 만료 임박 URL 재사용을 막는다.

---

#### 27. ⚪ 웹 브릿지 구독 딥링크 쿼리 파라미터가 웹 실제 구현과 불일치 (mentor vs mentorId)

| | |
|---|---|
| **심각도** | 낮음 (low) |
| **분류** | correctness |
| **위치** | `lib/core/web_bridge/web_bridge.dart:35` |
| **판정** | 확정(CONFIRMED) · app-bridge |

**문제**

앱의 openSubscribe()는 멘토 컨텍스트를 쿼리 키 'mentor'로 전달하지만, 웹 정본 페이지(ssambership_web/app/(student)/subscribe/page.tsx:30)는 `one(sp, "mentorId")`로 'mentorId' 키만 읽고, mentorId가 없으면 34행에서 '멘토를 먼저 선택해 주세요' 폴백 화면을 렌더한다. 즉 앱이 멘토 id를 넘겨도 웹은 이를 무시하고 항상 에러성 폴백에 착지한다. 현재는 컴플라이언스로 openSubscribeWeb 호출부가 없어 잠복 상태지만, 테스트(test/web_bridge/web_bridge_test.dart:23 `queryParameters['mentor']`)까지 잘못된 키를 고정하고 있어 정책 변경으로 이 동선을 켜는 순간 그대로 깨진 채 출시된다. 코드 주석은 '2026-07 실측'을 주장하나 파라미터명은 실측되지 않았다.

**근거 코드**

```
Future<WebOpenResult> openSubscribe({String? mentorId, String source = 'app'}) {
  return _open(WebBridgeConfig.subscribePath, <String, String>{
    'src': source,
    if (mentorId != null && mentorId.isNotEmpty) 'mentor': mentorId,
  });
}
// 웹: const mentorId = one(sp, "mentorId") ?? null;  → if (!mentorId) { '멘토를 먼저 선택해 주세요' 폴백 }
```

**권고**

쿼리 키를 'mentor' → 'mentorId'로 수정하고 test/web_bridge/web_bridge_test.dart·web_bridge_actions_test.dart의 기대값도 함께 갱신. 웹 브릿지 경로·파라미터를 실측할 때는 경로뿐 아니라 searchParams 키까지 웹 코드와 대조하는 체크리스트를 web_bridge_config.dart 주석에 남길 것.

---

#### 28. ⚪ 디바이스 토큰 등록 시 platform이 항상 'android'로 기록 — iOS 기기 오분류

| | |
|---|---|
| **심각도** | 낮음 (low) |
| **분류** | data-integrity |
| **위치** | `lib/core/push/push_service.dart:70` |
| **판정** | 확정(CONFIRMED) · app-bridge |

**문제**

PushService.registerCurrentToken()은 platform 인자 없이 register()를 호출하고, DeviceTokenRegistrarPort/SupabaseDeviceTokenRegistrar의 기본값은 'android'로 하드코딩돼 있다(device_token_registrar.dart:22). 앱은 Android·iOS 동시 타깃이므로 푸시 인프라 활성화 시 iOS 기기의 토큰도 전부 platform='android'로 저장된다. send-push Edge Function이나 운영 통계가 platform 컬럼을 신뢰하는 순간 잘못된 분기·집계가 발생한다.

**근거 코드**

```
// push_service.dart:70
await _registrar.register(userId: userId, token: token);
// device_token_registrar.dart:22
String platform = 'android',
```

**권고**

registerCurrentToken에서 `defaultTargetPlatform`(또는 Platform.isIOS) 기반으로 'ios'/'android'를 판별해 명시적으로 전달하고, 포트 기본값의 하드코딩 'android'는 제거하거나 필수 인자로 승격할 것.

---

#### 29. ⚪ PushPayload.fromRemote의 무방비 캐스트 — 비문자열 type 값 수신 시 TypeError 크래시

| | |
|---|---|
| **심각도** | 낮음 (low) |
| **분류** | robustness |
| **위치** | `lib/core/push/push_payload.dart:74` |
| **판정** | 확정(CONFIRMED) · app-bridge |

**문제**

수신 핸들러용으로 명세된 fromRemote()가 `data['type'] as String?` 다운캐스트를 사용한다. FCM data 값이 문자열이 아닌 형태(서버 구현 실수로 숫자/맵을 넣거나, iOS APNs 경유 커스텀 페이로드)로 도착하면 as 캐스트가 TypeError를 던져 (향후 배선될) 메시지 핸들러가 크래시한다. 같은 파일의 PushTarget.fromData는 `tid is String` 타입 검사로 방어하고 있어(29-35행) 이 지점만 방어가 빠졌다.

**근거 코드**

```
return PushPayload(
  type: PushType.fromCode(data['type'] as String?),
  ...
  target: PushTarget.fromData(data),
```

**권고**

`data['type'] as String?` 를 `data['type']?.toString()` 또는 `data['type'] is String ? data['type'] as String : null` 로 교체해 PushTarget.fromData와 동일한 방어 수준을 맞출 것.

---

#### 30. ⚪ kInAppPaymentSteeringEnabled는 어떤 코드도 읽지 않는 죽은 스위치 — '단일 제어점' 주석이 허위

| | |
|---|---|
| **심각도** | 낮음 (low) |
| **분류** | dead-code |
| **위치** | `lib/core/commerce/commerce_policy.dart:9` |
| **판정** | 확정(CONFIRMED) · app-bridge |

**문제**

doc 주석은 '정책이 바뀌면 [kInAppPaymentSteeringEnabled] 한 곳으로 재개 여부를 제어한다'고 선언하지만, 저장소 전체에서 이 상수를 참조하는 코드가 없다(구매 유도 억제는 openSubscribeWeb/openRechargeWeb 호출부를 물리적으로 제거하는 방식으로 구현됨). 나중에 정책 재개 시 이 플래그만 true로 바꾸면 아무 일도 일어나지 않아, 문서화된 제어점이 실제로는 작동하지 않는 함정이 된다.

**근거 코드**

```
/// 앱 내 결제 유도(구독·충전 '구매' 진입점) 노출 여부. false = 안내로 대체.
const bool kInAppPaymentSteeringEnabled = false;
// grep 결과: 이 상수의 참조는 자기 파일 doc 주석뿐, 소비 코드 0곳.
```

**권고**

상수를 제거하고 주석으로 '재개 시 호출부 복원 필요' 사실을 명시하거나, 반대로 실제 게이트로 쓰이도록 구매 유도 진입점(CommerceNoticeCard 분기 등)에 이 플래그를 소비시켜 문서와 코드를 일치시킬 것.

---

#### 31. ⚪ WEB_BASE_URL 주입값의 끝 슬래시 미정규화 — '//경로' 형태의 비정상 URL 생성

| | |
|---|---|
| **심각도** | 낮음 (low) |
| **분류** | robustness |
| **위치** | `lib/core/web_bridge/web_bridge.dart:78` |
| **판정** | 확정(CONFIRMED) · app-bridge |

**문제**

buildUri()는 `'$_baseUrl$path'` 단순 문자열 결합으로 URL을 만든다. WebBridgeConfig 주석(14-15행)이 '끝 슬래시 없음'을 경고하지만 런타임 정규화는 없어, dart-define으로 `WEB_BASE_URL=https://host/`처럼 슬래시가 붙은 값을 주입하면 모든 브릿지 URL이 `https://host//subscribe` 형태가 된다. 주석 규약에만 의존하는 취약한 조립이며, 스테이징/로컬 오버라이드가 일상적인 워크플로(HANDOFF 3-1-B)라 실수 확률이 낮지 않다.

**근거 코드**

```
Uri? buildUri(String path, [Map<String, String> query = const <String, String>{}]) {
  if (_baseUrl.isEmpty || path.isEmpty) return null;
  final Uri base = Uri.parse('$_baseUrl$path');
```

**권고**

buildUri(또는 WebBridge 생성자)에서 `_baseUrl.replaceAll(RegExp(r'/+$'), '')` 로 끝 슬래시를 정규화한 뒤 결합하고, 회귀 방지 테스트(끝 슬래시 주입 케이스)를 test/web_bridge에 추가할 것.

---

#### 32. ⚪ 댓글 전송·IQ 액션: await 뒤 mounted 확인 없이 setState/컨트롤러 사용 (setState after dispose 경로)

| | |
|---|---|
| **심각도** | 낮음 (low) |
| **분류** | setstate-after-dispose |
| **위치** | `lib/features/community/ui/board/board_detail_screen.dart:169` |
| **판정** | 확정(CONFIRMED) · app-ui |

**문제**

board_detail_screen.dart._send는 `await widget.write.addComment(...)` 뒤 mounted 확인 없이 `_input.clear()`(dispose된 TextEditingController 사용)와 `setState(...)`를 호출한다. 댓글 전송 직후 사용자가 뒤로가기로 화면을 pop하면 debug에서 'setState() called after dispose' / disposed ChangeNotifier 예외가 발생한다. 동일 패턴: shortform_detail_screen.dart:169-173(_send), iq_detail_screen.dart:183(_runAction — `await action()` 뒤 mounted 확인 없이 _refresh()→setState; 해결완료/환불/답변등록 진행 중 뒤로가기 시 발생). 같은 파일들의 finally 블록은 mounted를 확인하고 있어 이 지점만 누락이다.

**근거 코드**

```
await widget.write.addComment(
  postType: CommunityPostType.board,
  postId: widget.post.id,
  body: body,
);
_input.clear();
setState(() {
  _comments =
      widget.read.comments(CommunityPostType.board, widget.post.id);
});
```

**권고**

await 직후 `if (!mounted) return;` 추가(세 곳 모두). iq_detail의 _runAction은 `await action(); if (!mounted) return; _changed = true; _refresh();` 로 정리.

---

#### 33. ⚪ IQ 상세 첨부: build마다 새 서명 URL Future 생성(FutureBuilder 안티패턴) — 리빌드 때마다 재요청·이미지 깜빡임

| | |
|---|---|
| **심각도** | 낮음 (low) |
| **분류** | rebuild-efficiency |
| **위치** | `lib/features/individual_question/ui/iq_detail_screen.dart:553` |
| **판정** | 확정(CONFIRMED) · app-ui |

**문제**

_AttachmentsCard(StatelessWidget)가 build 안에서 `future: _signedUrl(a)` 를 호출해 부모 상태 변경(모든 액션의 _busy 토글, _refresh 등)마다 첨부 개수만큼 서명 URL을 재발급하고 FutureBuilder가 로딩 상태로 되돌아가 이미지가 스피너로 깜빡인다. 같은 화면의 질문방 버전(message_image_attachment.dart)은 initState에서 Future를 캡처해 이 문제를 피하고 있다.

**근거 코드**

```
Future<String> _signedUrl(IqAttachment a) async =>
    repo.signedAttachmentUrl(a.storagePath);
...
FutureBuilder<String>(
  future: _signedUrl(a),
```

**권고**

첨부 이미지 1건을 message_image_attachment.dart 처럼 StatefulWidget으로 분리해 initState에서 Future를 캡처하거나, AttachmentUrlResolver 류의 경로별 캐시를 repo에 도입한다.

---

#### 34. ⚪ IQ 목록 당겨서 새로고침: onRefresh가 즉시 완료돼 인디케이터가 로딩과 무관하게 사라짐

| | |
|---|---|
| **심각도** | 낮음 (low) |
| **분류** | ux-refresh |
| **위치** | `lib/features/individual_question/ui/student_iq_list_screen.dart:130` |
| **판정** | 확정(CONFIRMED) · app-ui |

**문제**

RefreshIndicator의 onRefresh가 `() async => _refresh()` 로 동기 함수(_refresh는 Future를 await하지 않고 _future만 교체)를 감싸 즉시 완료된다. 스피너가 데이터 도착 전에 사라지고 그 뒤 FutureBuilder가 전체 화면 로딩으로 바뀌어 새로고침 피드백이 이중으로 끊긴다. mentor_iq_list_screen.dart:190도 동일. (덧붙여 _refresh 자체가 finding #3의 setState-Future 패턴이라 debug에서는 당겨서 새로고침 즉시 예외가 난다.)

**근거 코드**

```
return RefreshIndicator(
  onRefresh: () async => _refresh(),
```

**권고**

`onRefresh: () { final f = _load(); setState(() { _future = f; }); return f; }` 처럼 새 Future를 반환해 인디케이터가 실제 로드 완료까지 유지되게 한다.

---

## 검토 방법과 한계

- **범위**: 이 보고서는 `ssambership-app` 저장소를 대상으로 한 정적 코드 리뷰입니다. 실제 운영 DB에 어떤 마이그레이션이 적용됐는지, 런타임 동작이 어떤지는 코드만으로 단정할 수 없으므로, 각 발견은 배포 전 실환경에서 재현·확인이 필요합니다.
- **DB 관련 발견**: 웹 저장소의 SQL 마이그레이션은 CLI 이력 없이 수동 번호제로 관리되어, 특정 SQL이 프로덕션에 적용됐는지는 파일 주석·`INDEX.md`에 의존합니다. RLS/RPC 관련 발견은 "해당 SQL이 라이브"라는 전제에서의 결함이며, 후불 정산(108~114) 등 DRAFT 표기 항목은 아직 미적용 초안일 수 있음을 심각도에 반영했습니다.
- **검증 방식**: 각 발견은 리뷰 에이전트가 파일을 정독해 1차 도출한 뒤, 별도 검증 에이전트가 인용 파일·줄을 다시 열어 재현성/악용영향/설계의도 3개 렌즈로 적대적으로 확인했습니다. 다수결로 REFUTED된 항목(예: 숏폼 썸네일 업로드 검증, signOut 예외 정리)은 이 목록에서 제외했습니다.

## 부록 A: 정적 분석 참고

이번 리뷰 환경에는 Flutter 툴체인이 없어 `flutter analyze` / 테스트를 **직접 실행하지는 못했습니다**. `HANDOFF.md`는 `flutter analyze lib/` 에러 0, 위젯·로직 테스트 250개 전부 통과(실제 DB·네트워크 없이 mock/fake 주입)를 자체 보고하고 있습니다. 위 발견사항은 전부 소스 정독 기반이며, 특히 아래 항목은 analyze/테스트가 잡지 못하는 **런타임·계약(웹 스키마 대비) 결함**이라 정적 분석 통과와 무관하게 성립합니다.

- createThread status 누락(1번) — 웹 DB 기본값과의 계약 불일치
- 정지 만료 자동 해제 미반영(2번) — 웹 정본 로직과의 불일치
- 숏폼 스크랩 토글의 DB CHECK 위반(항상 실패)
- 자유 라벨 과목의 FK 위반
- 세션 토큰 평문 SharedPreferences 저장

배포 전 실제 기기·실 DB에서 위 경로를 재현 검증할 것을 권합니다.
