# 쌤버십 앱 재구축 검토 — 웹 동등(결제 제외) 범위 · 신설 기능 설계 (2026-09)

> 목적: **웹(ssambership_web)에서 결제 기능만 제외한 수준**으로 앱을 새로 만들기 전에, (1) 기존 앱(ssambership-app)의 구현 방식 중 무엇을 살릴지, (2) 웹 대비 빠진 기능이 무엇인지, (3) 각 신설 기능을 프론트엔드·백엔드(Supabase RPC/RLS/Storage/Realtime)·DB 관점에서 어떻게 만들지 검토한 문서다.
> 범위 밖: UI/UX·디자인(전부 새로 만들 예정) — 이 문서의 "화면"은 이름·역할·데이터 의존만 뜻한다.
> 근거: 두 저장소의 실제 코드·SQL·계약 문서를 읽어 판정했다. 코드로 확인하지 못한 항목은 **(확인 필요)** 로 표시했고, 라이브 DB 카탈로그는 직접 조회하지 않았다(권한·정책은 2026-08-04 원격 스냅샷 + 이후 마이그레이션 팩 합성).
> 기준 시점: 웹 `main` (마이그레이션 팩 112본, 마지막 `20260903230300`) · 앱 `master` (`1.0.0+19`, Flutter 3.44.4).

---

## 0. 한 장 요약

1. **결제 경계는 DB 권한과 정확히 일치한다.** 자금을 움직이는 RPC(충전·구독 차감·갱신·에스크로 hold/payout/refund·분쟁 분배·정산 지급)는 전부 `service_role` 전용이라 앱은 구조적으로 결제를 실행할 수 없다. 예외적으로 DB가 `authenticated`에 열어 둔 자금 인접 RPC 4종(개별질문 생성 hold · release · refund · 정산 계좌 등록)만 오너 정책 결정이 필요하다.
2. **기존 앱은 "골격은 교체, 계약·파이프라인은 유지"가 답이다.** 라우팅(4 라우트 + 고정 5탭 + 모델 인자 push 46곳)·AccessState 5종·역할 분기 산재·전역 싱글턴 상태는 화면이 3~4배로 늘면 버티지 못한다. 반면 계정 상태 fail-closed 판정, RPC 봉투 파서·에러 매퍼, 첨부 업로드 파이프라인(보상 삭제·23505 멱등), 서명 URL 리졸버·Realtime 포트 계약, 웹 브릿지·WebView bootstrap 계약, 버전 게이트, 아웃바운드 매니페스트 잠금 테스트, CI 워크플로는 그대로 이식할 가치가 높다.
3. **신설 도메인은 6묶음이다.** ① 맞춤의뢰(앱 표면 0, 백엔드는 라이브) ② 멘토 콘솔(프로필 편집·요금제·학교 인증·학적 변경·정산 조회·리뷰 답글·활동 관리) ③ 계정(회원가입·비밀번호 재설정·본인인증/보호자 동의·온보딩 상태) ④ 학생 채널 정합(오답 표시·구독 해지 예약·리뷰 작성·멘토 필터/정렬·개별질문 direct 보드 등) ⑤ 커뮤니티·알림·지원 정합(댓글 답글/본인 삭제·게시판 임시저장·숏폼 네이티브 작성·공지·푸시 재도입·분쟁/신고 내역·환불 신청) ⑥ 플랫폼 공통(라우팅·셸·상태·DI·DB 계약 확장 원칙·테스트/CI·새 저장소 부트스트랩).
4. **웹 저장소 쪽 선행 작업이 있다.** 앱이 못 부르는 service_role 전용 기능은 `api_app_v1` SECURITY DEFINER thin wrapper(+`core_private` 구현부)로 열어야 하며, 마이그레이션은 웹 저장소 pack에만 쓴다(앱 저장소 SQL 금지). 앱 세션 bootstrap(`/api/app-session/bootstrap`)은 현재 멘토 전용·target 1종이라 본인인증·(선택) 관리자 위임을 위해 확장이 필요하다.
5. **오너 결정이 필요한 항목**(§9)은 맞춤의뢰 정식 오픈 여부(웹 게이트 기본 OFF), 관리자 콘솔 앱 포함 여부(권고: 제외 유지), 자금 인접 4종 포함 여부, 숏폼 네이티브 작성 vs WebView 유지, 푸시(FCM) 재도입 시점, 본인인증 게이트 앱 강제 여부, 새 저장소 방식(fork vs 신규 생성)이다.

---

## 1. 검토 범위와 방법

### 1.1 "웹에서 결제만 제외한 수준"의 정의

| 구분 | 정의 | 이 문서의 처리 |
|---|---|---|
| **결제 실행(앱 제외)** | 캐시 충전(Toss·페이싱크), 구독 시작(캐시 차감)·갱신, 개별질문 생성(캐시 hold), 맞춤의뢰 주문 생성(에스크로 hold)·납품 수락(지급)·학생 직접 취소(환불), 분쟁 분배, 환불 승인·거절, 정산 지급 배치 | 정책 정본 `docs/policy/app-web-payment-separation.md` §1·§3 + DB 권한(`service_role` 전용)으로 확정. 앱은 상태 조회만 |
| **결제 상태 읽기(앱 허용)** | 캐시 잔액·원장, 구독 상태·목록, 정산 요약·라인, 개별질문·주문 진행 상태 | 이미 허용. 단 "충전 유도" 문구·링크 금지(정책 §4) |
| **경계 모호(오너 결정)** | 구독 해지 예약·취소, 구독 잔여 환불 신청, 개별질문 release(에스크로 확정)·refund, 맞춤의뢰 납품 수락, 정산 계좌 등록, 가격 설정(멘토 콘솔), 가격 표시(학생 화면) | §3 판정표에서 항목별 권고안 제시 |
| **앱 범위 밖(별도 결정)** | 관리자 콘솔(35페이지, service_role 의존), cron·webhook·워커 | §5.3에서 포함 불가 근거와 옵션 제시 |

### 1.2 방법

1. 앱 저장소를 **아키텍처**(계층·부팅·세션·데이터 계층·라우팅·인프라·테스트/CI)와 **기능 인벤토리**(아웃바운드 매니페스트 기준 RPC 32+2·테이블 24+·버킷 6)로 나눠 읽었다.
2. 웹 저장소를 **학생 채널·맞춤의뢰·멘토 콘솔·커뮤니티/알림/지원·계정/본인인증/관리자·DB 표면/결제 경계** 6개 축으로 읽어 라우트별 서버 표면(RPC 시그니처·테이블 RLS·server action의 service_role 사용 여부·API route)과 결제 접촉을 표로 만들었다.
3. 도메인별로 갭 매트릭스 → 서버 표면 설계(기존 사용 가능 / 신규 필요) → 앱 프론트엔드 설계 → 데이터 모델 → 순서·규모 → 오너 결정 → 리스크를 작성했다.
4. 설계의 결정적 주장(RPC GRANT, RLS 정책, 트랜잭션 결합 여부, 트리거)은 마이그레이션 SQL로 재확인했다.

---

## 2. 기존 앱 자산 판정 — 유지 · 일반화 후 이식 · 교체

기존 앱(228 dart 파일, features 약 26k줄, 테스트 250개 통과)의 구조와 그 판정이다. 근거는 `ssambership-app/lib/**`·`test/contracts/**`·`HANDOFF.md`.

### 2.1 그대로 이식(계약 불변)

| 자산 | 위치 | 왜 유지하나 |
|---|---|---|
| 계정 상태 판정 | `lib/core/auth/account_status.dart`, `auth_service.dart` (`AccountStatusReader.resolve` → `AccountStatusKind` 7종 → `computeAccess` fail-closed) | 입력(`users.status/suspended_until`, `account_deletion_write_blocked`, `account_deletion_status_self`)이 웹 `assertAccountActive`와 동등. 관리자·역할 불명·조회 실패는 전부 차단 |
| RPC 봉투 파서·에러 매퍼 | `qna_error_mapper.dart`, `iq_error_mapper.dart`, `community_post_error_mapper.dart` 등 (raise `'CODE'` 스타일 + `{ok, code, contract_version}` strict 스타일) | 서버 계약 그대로. 단 도메인별 5벌 → 공통 코드 테이블 + 도메인 확장으로 통합 |
| Storage 업로드 파이프라인 | `question_room/data/attachments/attachment_upload.dart`, `individual_question/data/iq_attachment_upload_core.dart`, `core/scan/*`, `core/ink/*` | 경로 첫 세그먼트=RLS 소유 키, 업로드→RPC 등록→실패 시 보상 DELETE→23505 멱등 수용, 5MB 초과 다운스케일, PDF 래스터. 맞춤의뢰 납품·학교 서류·아바타가 같은 규약을 쓴다 |
| 서명 URL 리졸버 계약 | 4벌(질문방 1h·IQ·숏폼·게시글 이미지) | TTL·마진·single-flight·uid 키·실패 미캐시 규약 유지, **제네릭 1벌로 통합** |
| Realtime 포트 + 폴백 | `thread_realtime.dart`, `iq_realtime.dart`, `notifications_realtime.dart` | postgres_changes + 재조회 폴백 + 재연결 콜백. publication 미포함이어도 동작. 제네릭 1벌로 통합 |
| 교차 화면 무효화 | `core/refresh/data_refresh_bus.dart`, `shared/widgets/screen_visibility.dart` | 세대 토큰으로 늦은 응답 폐기. 도메인 세대 추가만 |
| 웹 브릿지·WebView 브릿지 | `core/web_bridge/*` (URL allowlist, `WebOpenResult`), `shortform_compose_bridge.dart` ↔ 웹 `POST /api/app-session/bootstrap` (쿠키 격리 버퍼·HttpOnly·303) | 결제 제외 다층 방어의 핵심. bootstrap target 확장(본인인증 등)만 |
| 버전 게이트 | `core/version_gate/*` (`get_mobile_app_version_policy`, SharedPrefs 캐시, 스토어 URL allowlist) | 새 앱 출시 시 구 앱 차단 수단이 `min_supported_build` 상향뿐 |
| 관측·정책 상수 | `core/observability/crash_reporting.dart`(Sentry fail-open), `core/commerce/commerce_policy.dart`, `data/mappings/subject_labels.dart`(웹 `subjectCatalog.ts` 35코드 1:1) | 정본 매핑 |
| 테스트·CI 규율 | `test/contracts/outbound_api_manifest_test.dart`(RPC/테이블/뷰/스키마/버킷/금지어 정확 집합 잠금), iOS/Android 워크플로 계약 테스트, 손코딩 Fake 주입(mock 프레임워크 금지), `flutter-ci.yml`·`android-signed-release-candidate.yml`, `tool/validate_release_env.dart` | 서버 표면 변경을 의도된 변경만 통과시키는 장치. 집합만 갱신 |

### 2.2 교체·재설계

| 자산 | 현행 한계(근거) | 방향 |
|---|---|---|
| 라우팅 | GoRouter 라우트 4개(`/splash /login /home /blocked`) + 상세 46곳 `Navigator.push`(모델 인자) — 딥링크·복원·역할별 네비 불가 (`lib/app/router.dart`, `home_shell.dart`) | 명명 라우트 테이블(id 파라미터 상세는 내부 조회) + 역할별 셸(StatefulShellRoute) + 경로 패턴×역할×AccessState 가드 매트릭스. `TabNavigator` int 채널 폐기 |
| 홈 셸 | 고정 5탭 IndexedStack, 탭 추가 시 5곳 수정(`AppTab`·`_pages`·`_icons`·`bottomTabLabels`·`guestAllowedTabs`) | 역할별 탭 구성을 데이터로, 게스트 허용을 라우트 메타로 |
| 접근 상태 | `AccessState` 5종·`AppRole` 4종 — 가입 직후·본인인증 필요·보호자 동의·멘토 승인 대기 표현 불가 | 온보딩 상태 추가(§7) |
| 역할 분기 | 화면·레포 내부 `AuthService.instance.currentRole` switch 12곳, 싱글턴 참조 19파일 | 라우트 가드·기능 등록 표로 상향 |
| 상태관리·DI | 전역 싱글턴 6종 + ChangeNotifier + `xxxOverride` 생성자 seam 30여 종, 공유 상태(구독 요약·차단·지갑)는 화면마다 재조회 | 스코프형 주입(생성자 주입 유지, Fake 규율 보존) + 공유 도메인 상태의 캐시 소유자(§7) |
| 중복 유틸 | `model_parse.dart` 2벌, 리졸버 4벌, Realtime 포트 3벌, 에러 매퍼 5벌 | 각 1벌 제네릭 |
| 알림 유형 분기 | `NotificationEventType` 18종 exhaustive switch 4곳 | 유형→(kind, destination, opener) 단일 테이블 |
| 문서 | HANDOFF §3-1·§3-4·§6, README, MIN_VERSION 문서가 코드와 불일치(WEB_BASE_URL 기본값 `https://ssambership.com` vs 문서의 vercel 도메인 등) | 새 저장소에서 정본화 |

### 2.3 웹 정본 변경(2026-09-03 DB-1~3)으로 재검토가 필요한 앱 자산

| 항목 | 웹 변경 | 앱 현행 | 조치 |
|---|---|---|---|
| 커뮤니티 본인 삭제 | `soft_delete_own_content(p_kind, p_id)` 하나로 통일(shortform/shortform_comment/board_comment/board_post), GRANT authenticated, 반환 void (`supabase/sql/196`) | 숏폼 댓글 `community_comment_soft_delete_self`, 게시글 `api_app_v1.community_post_soft_delete`, **게시판 댓글·숏폼 글 본인 삭제 없음** | 새 앱은 4종 모두 `soft_delete_own_content`로 통일(봉투 형식이 void라 파서 분기 필요). 기존 2개 RPC 유지 여부는 웹 결정 |
| 소프트 삭제 컬럼 | `deleted_at`·`deleted_by` 추가, 읽기 정책에 `deleted_at IS NULL` (`194`) | 모델에 `deleted_at` 없음, 숏폼 댓글 `status='visible'` 필터 | 모델에 두 컬럼 추가('작성자 삭제/관리자 삭제' 구분). `status` 필터 유지 여부 (확인 필요) |
| 하드 DELETE 차단 | `ugc_block_hard_delete` 트리거(`198`) | 세 표에 `.delete()` 0건 | 영향 없음. 198 헤더 주석이 앱 DELETE 대상을 `mentor_favorites`로 적었으나 정본 테이블은 `public.favorites`(`034_mentor_favorites.sql:4`)이고 앱도 `favorites`를 쓴다 — 주석 오기, 코드 영향 없음 |
| 캡 구조 | 가중치 1.0/2.25/4.75·한도 50은 DB 함수만 (`190`) | 앱은 cap 미계산 | 유지. 앱에 가중치 상수 두지 말 것 |
| 학교 인증 규칙 | 자동 판정=`pending` 잠정, 폴백 `그외` (`192`·`193`) | `mentor_directory_v1.school_verified` bool만 | `required_school_tier` 라벨에 `그외` 포함. 뷰 산출 조건 변경 여부 (확인 필요) |
| 연결노트 | 웹은 매 저장 append INSERT(upsert 아님), 구독 가드는 앱 계층 | 앱은 upsert 의미로 구현 | 의미 정합 결정(§5.4) |

---

## 3. 결제 경계 판정표

정본: `ssambership_web/docs/policy/app-web-payment-separation.md`. 분류 — **[실행·제외]** 결제 실행 / **[읽기·허용]** / **[모호]** 자금 인접이지만 소비자 결제가 아닌 행위(권고안 제시, 최종 결정은 오너).

| # | 웹 기능 | 서버 표면 · DB 권한(a/u/s) | 판정 | 권고 |
|---|---|---|---|---|
| 1 | 캐시 충전(Toss 카드) | `api_web_v1.record_cash_topup_v2` — s만 | [실행·제외] | 화면·버튼·링크·문구 전면 금지(정책 §3) |
| 2 | 캐시 충전(페이싱크 무통장) | `paysync_invoices` 쓰기 s, pending 조회 u | [실행·제외] | pending 주문 조회도 "충전 화면"이므로 비표시 |
| 3 | 구독 시작(캐시 차감) | `subscription_checkout_confirm_v2` — s만 | [실행·제외] | 상태 조회만 |
| 4 | 구독 상태·목록 조회 | `api_web_v1.my_subscriptions_self()`, `subscriptions` SELECT 당사자 — u | [읽기·허용] | 앱 이미 사용 |
| 5 | 구독 해지 예약 / 예약 취소 | 웹은 `requireRole` 후 service_role로 `subscriptions.cancel_at_period_end` UPDATE(전용 RPC 없음, authenticated UPDATE 정책 없음) | [모호] | 해지 예약은 *결제 중단* 행위로 외부 결제 유도가 아님 → **조건부 포함 가능**(가격·재유도 문구 없이). `api_app_v1.subscription_cancel_at_period_end_self(uuid)` 신설 필요. 예약 취소(재개)는 "다음 결제 재동의"에 가까워 웹 위임 권고 |
| 6 | 구독 갱신(자동 차감) | cron `process_subscription_renewal` — s만 | [실행·제외] | 갱신 알림 읽기만 |
| 7 | 구독 잔여 환불 신청 | 웹 service_role로 `refunds` INSERT(`refund_ins`는 admin만), 금액 서버 산정 | [모호] | 환불 *신청*은 구매가 아님. 포함 시 `refund_request_subscription_self(uuid, text)` 신설(별표4 비례식 SQL 이식). 정책 문서 §3은 "원칙 ❌·재검토" → 오너 결정 |
| 8 | 환불 승인·거절 | `approve/reject_refund_request_admin` — s만 | [관리자·제외] | — |
| 9 | 개별질문 생성(캐시 hold) | 웹 코어 `create_individual_question_with_hold_v2` s만; DB에 `create_individual_question_as_student` u 존재(subject/tier 인자 없음) | [모호 → 현행 제외] | 앱 `IQ_CREATE_ENABLED` 기본 off·웹 페이지로만. "기충전 캐시를 앱 내 재화에 소비"가 Play Billing 대상인지·Apple 3.1.3(b)는 **법무 확인 필요**. **권고: 웹 위임 유지** |
| 10 | IQ claim·answer·message·첨부 | `claim_individual_question_as_mentor`, `answer_individual_question`, `iq_append_message`, `add_individual_question_attachment` — u | [상태 전이·허용] | 앱 이미 사용 |
| 11 | IQ release(학생 해결완료 → 멘토 85% 지급) | `release_individual_question(uuid)` — u(학생 본인) | [모호] | 에스크로 확정이지 새 결제가 아님. 앱 이미 호출 중 → **허용 유지 권고**(금액 표시 최소화) |
| 12 | IQ refund(학생 취소 환불) | `refund_individual_question(uuid)` — u | [허용] | 지갑으로 되돌리는 행위 |
| 13 | 맞춤의뢰 주문 생성(에스크로 hold) | `record_custom_order_escrow_hold` — s만; 웹은 세션 insert → SR hold → SR update 3단계(한 트랜잭션 아님) | [실행·제외] | 학생의 "멘토 선정"을 웹으로 위임(딥링크 `/custom-request/{postId}/applications`). hold 없는 `unpaid` 주문을 앱이 만들면 웹 흐름에서 갇히므로 **금지** |
| 14 | 맞춤의뢰 납품 수락(→ 멘토 95% 즉시 지급) | `accept_custom_order_deliverable_atomic(p_order_id, p_student_id, …)` — s만, 실측 본문은 즉시 지급 호출 | [모호] | #11과 동형이나 현재 앱 도달 불가. 포함 시 `custom_order_student_accept(uuid)` thin wrapper 신설. 오너 결정 |
| 15 | 맞춤의뢰 분쟁 분배 | `record_custom_order_dispute_split` — s만 | [관리자·제외] | — |
| 16 | 맞춤의뢰 진행(작업 시작·납품·수정요청·메시지·이벤트·분쟁 제기) | `custom_order_mentor_start/deliver/student_request_revision` u, `custom_order_messages`/`order_events`/`disputes` INSERT RLS | [허용] | 자금 없음 |
| 17 | 맞춤의뢰 글 등록·멘토 지원 | `custom_request_posts`/`custom_request_applications` INSERT RLS — u | [허용, 게이트 공백] | 웹은 지원 전 본인인증 서버 게이트(`IDENTITY_GATE_ENABLED`). DB 게이트는 설계상 금지 → 앱 직접 INSERT 시 게이트 없음. 재현 방법 결정 필요(§5.1) |
| 18 | 정산 조회(멘토) | `mentor_settlement_summary(p_month)`, `mentor_settlement_lines(p_from,p_to)`, `api_web_v1.mentor_settlement_self()` — u | [읽기·허용] | 정책 §3 ✅. 앱은 현재 `/mentor/payouts` 링크 숨김 |
| 19 | 정산 계좌 등록 | `api_web_v1.mentor_payout_account_update_self(text,text)` — u. 계좌 2컬럼 UPDATE(자금 이동 없음), 은행 allowlist 17종 | [모호] | 지급 수취 계좌 등록(소비자 결제 아님) → **조건부 포함 권고**. DB 추가 객체 불필요 |
| 20 | 정산 지급 배치 | `run_scheduled_payout`, `pay_due_payouts_for_run` — s | [제외] | — |
| 21 | 가격 설정(멘토 플랜 F8·IQ 단가) | `mentor_plan_prices_set_self(int,int,int)`(밴드 DB 강제), `set_individual_question_price(int)` — u | [모호] | 판매자 콘솔 행위. 학생 화면에 가격+구매 유도가 없으면 정책 §4 유형이 아님 → **멘토 전용 화면으로 포함 가능** |
| 22 | 가격 표시(학생 대상) | `mentor_plans` SELECT(anon 포함), `mentor_directory_v1` | [모호] | 정책 §4 "가격표+구매 유도 조합" 금지. 앱은 이미 제거(`5002c1d`) → **비표시 유지 권고** |
| 23 | 캐시 잔액·원장 조회 | `api_web_v1.my_wallet_v1`/`my_cash_ledger_v1` — u | [읽기·허용] | 앱 이미 사용. 원장 화면이 충전 유도로 읽히지 않게 |
| 24 | 잔액 부족 상태 표시 | — | [허용] | "캐시가 부족합니다" 사실만, 해결 방법 안내 금지 |
| 25 | 본인인증(NICE PASS) | `/api/identity/start·return`(service_role, `identity_verifications`·`nice_auth_tokens` s만), `users.identity_verified_at` 읽기 u | [웹 전용 흐름] | 앱은 WebView 위임 + 상태 표시(§5.3) |
| 26 | 탈퇴 시 잔액 소멸 동의 | `account_deletion_request_self_consented_v2(bigint)` — u | [허용] | 앱 이미 사용 |


---

## 4. 갭 매트릭스 총괄

도메인별 갭 판정 집계(항목 단위 근거는 각 설계 문서 §2).

| 도메인 | 항목 | 포함(기존 객체) | 포함(서버 선행) | 웹 위임 | 제외 | 오너 결정 | 앱 현재 |
|---|---|---|---|---|---|---|---|
| 맞춤의뢰 | 32 | 20 | 4(W-0·W-7·W-8·S-6 등 Tier A) | 3(선정·수락·취소) | 1 | 4 | 표면 0(알림 게이트 흔적만) |
| 멘토 콘솔 | 35 | 16 | (오너 결정에 포함) | 1 | 7 | 11(대부분 "포함 권고") | 대시보드 섹션 3값·웹 링크 |
| 계정·본인인증·관리자 | 30 | 19 | 3(학생증 RPC·마케팅 동의·탈퇴 사전조건) | 3(NICE self/guardian·새 비밀번호) | 3(관리자 2·소셜) | 2 | 로그인·게스트·탈퇴만 |
| 학생 채널 정합 | 36 | 23 | 4(S-1·S-2·S-4·S-7) | 2 | 4 | 3 | 핵심 루프 완비 |
| 커뮤니티·알림·지원 | 50 | 32 | 1(S-1 계정 게이트 트리거) | 3 | 6 | 8 | 열람·작성·댓글·반응·신고·차단·알림 완비 |
| **합계** | **183** | **110** | **12** | **12** | **21** | **28** | |

읽는 법: "포함(기존 객체)"는 서버 변경 없이 앱 코드만으로 되는 것, "포함(서버 선행)"은 웹 저장소 pack에 객체를 먼저 만들어야 하는 것(§6), "오너 결정"은 결제 경계·정책 번복·비용 판단이 걸린 것(§9). 관리자 콘솔 35페이지는 별도 항목으로 세지 않고 §5.3의 결정 (i)로 다뤘다.

---


---

## 5. 도메인별 설계

각 절은 갭 요약 · 서버 표면(기존 사용 가능 / 신규) · 앱 구조 · 순서·규모 · 오너 결정 · 지뢰 순이다. 상세(시그니처·오류코드·데이터 모델·파일 단위 배치)는 `docs/app-rebuild-review-2026-09/design/*.md`에 있다.

### 5.1 맞춤의뢰(Custom Request)

> 상세 설계: `design/custom_request.md` (갭 32항목 · 서버 신설 Tier A 8 · Tier B 3 · Tier C 3 · 단계 Phase 0~4).

**전제 두 가지.**
1. **CR 백엔드는 이미 라이브다.** 테이블 9종·RPC 11종·버킷 4종·알림 트리거(159)가 마이그레이션에 포함돼 있고, 웹 게이트 `NEXT_PUBLIC_FEATURE_CUSTOM_REQUEST`(기본 OFF)는 네비 숨김·랜딩 배너만 제어한다. 라우트·server action·DB는 게이트 없이 동작한다. 따라서 **앱 노출 = 사실상 CR 출시**이며, 웹 게이트를 동시에 ON 하지 않으면 앱 사용자가 만든 의뢰에 웹 멘토가 네비로 도달하지 못한다.
2. **결제 경계와 DB 권한이 정확히 일치한다.** 자금 이동 RPC 5종(`record_custom_order_escrow_hold/payout/refund`, `accept_custom_order_deliverable_atomic`, `record_custom_order_dispute_split`)은 라이브 ACL이 `service_role` 전용. 웹의 "학생 선정 → 주문 생성 + hold"는 한 트랜잭션이 아니라 세션 insert → SR hold → SR update 3단계 + 보상 삭제이며, hold 없는 `unpaid` 주문은 웹 흐름에서 "이미 주문 있음"으로 갇힌다 → **앱이 주문 행만 만드는 설계는 금지**. 납품 수락은 as-applied 본문이 정산 행 생성 + **즉시 지급**을 한 트랜잭션으로 수행한다(후불 110은 초안). 자동 수락은 존재하지 않는다(3일 카운트다운은 표시 전용).

**앱의 학생 흐름.** 작성 → 지원 받기 → **[선정: 웹 위임]** → 진행·납품·수정 요청·메시지·분쟁 → **[수락/취소: 웹 위임]** → 완료 조회. 웹 선정/주문방 페이지로의 딥링크는 정책 §4(웹 결제 URL 유도 금지) 때문에 IQ 등록 링크와 같은 플래그 패턴(기본 OFF)을 권고한다.

**갭 요약(32항목 → 포함 24 · 웹 위임 3 · 제외 1 · 오너 결정 4).**

| 구분 | 항목 | 서버 표면 |
|---|---|---|
| 포함(RLS/RPC 직접) | CR 랜딩, 의뢰 작성·임시저장·이어쓰기(`crp_insert/update`), 의뢰 첨부(버킷 20 MiB — 웹 상수 50MB와 불일치), 내 의뢰 목록, 공개 의뢰 상세(RPC 006 폴백), 지원 비교(읽기, 닉네임은 `mentor_directory_v1`), 학생 주문 목록·탭, 주문방 번들(진행 단계·납품·메시지·수정요청·분쟁·정산 배너 — 당사자 SELECT), 멘토 작업 시작(`custom_order_mentor_start`), 수정 요청(`custom_order_student_request_revision`, ≤2회), 납품 다운로드(세션 서명 URL — 학생은 완료 후만 DB 강제), 분쟁 제기(`dispute_ins`, 활성 1건 유니크), 분쟁 목록·상세, 완료 화면, 멘토 대시보드 KPI, 멘토 오픈 풀(RPC 018, 멘토 role 필수), 멘토 주문 목록 탭 7종, 학생 표시명(`get_mentor_student_nicknames` 재사용), 알림 2종 표시·이동(게이트 해제) | 새 객체 0 |
| 포함(서버 선행, Tier A) | 임시저장 삭제(W-0 — posts DELETE 정책 없음), 납품 등록(W-8 — 버전 채번 + `custom_order_mentor_deliver` + 이벤트를 원자화; 현재 `cdel_insert`는 멘토 여부만 검사), 주문 메시지+첨부(W-7 — 종료 주문 차단·연락처 마스킹이 웹 TS 전용이라 DB로 이전), `core_private.mask_contact_text` 추출(S-4), Realtime publication 4 테이블(S-5, 현재 CR 테이블 0건), `notification_unread_count_self` CR 제외 해제(S-6 — **앱 게이트 해제와 같은 릴리스 필수**), `cro_update` 잠금(S-7 — 라이브에 광범위 UPDATE 정책 실재, 웹 세션 UPDATE 0건 → DROP 안전), applications `(post_id, mentor_id)` 유니크(S-8) | 마이그레이션 ~8본 |
| 권장(Tier B) | 멘토 지원 생성 W-9(승인 게이트·중복·마스킹·(선택) 본인인증 DB 검사), 글 생성/수정 W-10(필수값·예산 1,000~200,000·동의 2종·마스킹), Storage DELETE 정책 3 버킷(S-9 — 보상 삭제가 실제 동작하게) — 채택하지 않으면 앱이 Dart로 재구현(버전별 드리프트) |
| 웹 위임(결제 실행) | 멘토 선정(hold), 납품 수락(즉시 지급), 학생 직접 취소(전액 환불) — 오너가 앱 내 실행을 원하면 Tier C wrapper W-1/W-2/W-3(단일 트랜잭션·envelope 변환) 신설 = 결제 실행이 앱에 들어오는 결정 |
| 제외 | 관리자 분쟁 처리·분배·환불 승인 |
| 오너 결정 | 본인인증 게이트 적용 방식(현재 웹도 OFF), Realtime 도입, 검토 3일 만료 정책, 결제 wrapper 3종 |

**앱 구조.** `lib/features/custom_request/{data,ui}` 신설. `data/`: 모델 12종 + enum + `custom_order_lifecycle.dart` 포트(primary 상태 열·종료 판정·탭 분류·검토 마감 — 순수 함수 + 단위 테스트), `CustomRequestBackend` 포트 + Supabase 구현 + Fake, read repository(12 메서드), write repository(RPC 경로 + 봉투 파서 + 에러 매퍼: 088 코드 17종 + W-* 코드), 첨부 정책·경로 빌더(4 버킷, DB CHECK 정규식과 일치 테스트)·업로더·서명 URL 리졸버(5벌째 → 제네릭 통합), `CustomOrderRealtimePort`(채널·필터·재연결·폴백), 플래그 파일(`CR_ENABLED`, 웹 딥링크 OFF 등 dart-define 4종), `DataRefreshBus.customRequestGeneration`. `ui/`: push 라우트 15개(진입·학생 홈·내 의뢰·작성(문서 파일 선택은 `ScanSourcePort`가 이미지+PDF 한정이라 `DocumentPickerPort` 신설)·상세·지원 비교·주문 목록 학생/멘토·**주문방(XL)**·완료·분쟁 목록/상세·멘토 대시보드·오픈 풀·지원서 작성). 진입은 마이페이지 push + 알림 딥링크로 시작(탭 추가는 셸 재설계와 함께). 알림: `kGatedNotificationTypeCodes` 비우기, 목적지 2종·route 2종·opener 분기, 설정 라벨 `'order'` 재명명. 매니페스트: CR RPC·테이블 9종·버킷 4종 추가.

**순서·규모(1인 기준).** Phase 0 결정·계약 증보(앱 계약 v1.x CR 절 신설 — 웹 계약 v1.1은 CR을 "신규 객체 없는 유지 영역"으로 고정하고 있음) M → Phase 1 서버(S-7·S-8·S-4·W-0·W-8·W-7·(W-9·W-10)·S-9·S-5·S-6 + pack 등재·rollback·검증) ≈ 6~8일 → Phase 2 앱 데이터 계층 ≈ 6~8일 → Phase 3 화면 15개 ≈ 15~20일 → Phase 4 통합(알림 배선·테스트·계약 테스트·스토어 정책 QA·출시 동시 조치: 웹 게이트 ON + 앱 `CR_ENABLED` + S-6 + 버전 정책) ≈ 5~7일.

**오너 결정 권고(16항목 요지).** Q1 웹 게이트 동시 ON / Q2 결제 3종 1차 웹 위임(Play 검토 후 IQ release·refund와 함께 재판정) / Q3 웹 딥링크 플래그 기본 OFF / Q4 Realtime 도입 / Q5 마스킹·종료 차단·승인 게이트는 DB wrapper / Q6 본인인증 게이트는 impl 내부 검사 + DB 설정 ON/OFF(웹 플래그와 동시 전환) / Q7 `cro_update` DROP / Q8 지원 유니크 추가 / Q9 수정요청 중 상태는 `order_status` 우선 판독·수락 CTA 숨김 / Q10 즉시지급 기준 문구, 모델은 양쪽 수용 / Q11 3일 만료는 표시 전용 유지 / Q12 선정된 글의 오픈 풀 잔류는 RPC 018 필터(앱 단독 불가) / Q13 진입점 마이페이지 push / Q14 `'order'` 라벨 서버 그룹 확인 후 재명명 / Q15 지원 첨부 "선정 후 미리보기" DB 정책 강제 / Q16 CR 완료는 리뷰 자격 미포함(웹과 동일).

**지뢰.** `cro_update` 잠금 전 출시 금지(`payment_status` 위조 가능). S-6와 앱 게이트 해제 릴리스가 어긋나면 배지≠목록. CR 테이블이 publication에 없어 구독해도 무음 → 폴백 필수. 학생 납품 서명 URL은 완료 전 DB 거부 → 모델에서 `storage_path` 제거. 메시지 첨부 `storage_path` CHECK 정규식·납품 3세그먼트 경로 불일치 시 23514/웹 다운로드 불가. 의뢰 첨부 MIME 7종(gif 없음). `cra_insert` 역할 미검증·`posts.status` 미갱신 → 주문된 글에 지원 지속. accept RPC는 `{ok:false, message}` 형(코드 없음) → wrapper 시 코드 변환. iOS PrivacyInfo(문서 업로드)·서명 워크플로 테스트 수 고정(1,508) 갱신.

### 5.2 멘토 콘솔

> 상세 설계: `design/mentor_console.md` (갭 35항목 · 서버 신설 10종(필수 4·권장 1·선택 5) · 단계 S1~S4 / A0~A9).

**현황.** 기존 앱의 멘토 기능은 질문방·개별질문·마이페이지 대시보드 섹션(구독 학생=방 수, 답변 대기, 최근 정산 1건)뿐이고 프로필 편집·정산·리뷰는 웹 링크로 넘긴다. 웹 멘토 콘솔의 실질 홈은 `/mentor/mypage`(`/mentor/dashboard`·`/mentor/channel`은 page 없이 loading.tsx만 남은 빈 라우트).

**결제 경계 판정.** 정산 조회 = 상태 읽기(허용). 정산 계좌 등록(F13) = `mentor_profiles` 두 컬럼 UPDATE, 자금 이동 없음(오너 결정·조건부 포함 권고). 가격 설정(F8·IQ 단가) = 판매자 콘솔 행위(오너 결정·포함 권고, 학생 가격표·구매 CTA와 화면 분리). 활동 관리(일시중단·복귀·종료 신청) = 자금 이동 없음(종료 시 환불 생성은 배치 `finalize`로 분리되어 있음). 정산 화면에 충전 유도 문구·링크 혼입 금지.

**갭 요약(35항목 → 포함 16 · 웹 위임 1 · 제외 7 · 오너 결정 11).**

| 구분 | 항목 | 서버 표면(권한 근거) |
|---|---|---|
| 포함(기존 객체) | 홈 KPI 확장(답변 대기·활성 구독자·이번 달 수익·평점), 5개월 수익 차트(`my_cash_ledger_v1`), 구독 수용량(cap RPC 3종 anon/authenticated EXECUTE — 웹의 service_role은 경로 통일 목적일 뿐), 구독 열림 토글(F7), 인증 상태·학교 인증·학적 현황 조회(`msv_select_own`, `macc_select_own`), 프로필 편집 9필드(F7 `mentor_profile_update_self` authenticated GRANT), 정산 월 요약·라인(`mentor_settlement_summary(p_month)`·`mentor_settlement_lines(p_from,p_to)` — 웹 API route는 얇은 래퍼), 정산 계좌 마스킹 조회, 받은 리뷰·통계(`reviews_select_public_visible` + `get_mentor_review_stats`), 리뷰 답글(RLS `reviews_update_mentor` + 트리거 1회 강제 — 길이 규칙은 RPC 권고), 멘토 측 분쟁 목록·상세(조회 전용, `dispute_select`) | 새 객체 0 |
| 오너 결정(포함 권고) | 아바타 업로드(`profile-avatars` public 버킷 own-folder + F7), 플랜 가격 설정(F8 밴드 DB 강제), 개별질문 단가(`set_individual_question_price` — SETOF·raise 스타일이라 파서 분리), 학교·전공 서류 제출(`msv_insert_own_pending` + `student-id-images` insert_own 직접 가능), 학적 변경 요청(`macc_insert_own_pending`), 학생증 사후 제출(**신규 RPC 필수** — 컬럼 반영이 service_role UPDATE), 활동 관리 3종(**신규 RPC 필수** — 전부 service_role), 정산 계좌 등록(F13, 조건부), 본인 활동 이력(보류/최소) |
| 웹 위임 | 본인인증 게이트(상태 표시만) |
| 제외 | 정산 엑셀, 리뷰 숨김(admin 전용), 무단 이탈(UI 미연결), 서류 원본 열람(2026-07 결정 "민감 서류 URL 앱 비노출" 유지), 빈 라우트·redirect, 정산 지급 배치 |

**서버 신설(웹 저장소 pack, `api_app_v1` SECDEF + `core_private` impl, envelope 규약).**
1. `mentor_student_id_document_set_self(p_object_path text)` — 경로 첫 세그먼트=uid·세그먼트 수 2·`storage.objects` 실재+`owner_id` 검증 후 `student_id_image_url` UPDATE (S)
2. `mentor_activity_pause_self(p_days, p_reason)` / `mentor_activity_resume_self()` / `mentor_activity_terminate_self()` — `mentorActivityService.ts` 규칙(7일 상한·rest 6개월 1회 KST·구독 기간 연장·`mentor_plans.is_active`·`mentor_activity_events` 로그) 이식, 158 트리거 알림 fan-out 그대로. 종료는 환불 생성 없음 (M)
3. `mentor_review_reply_self(p_review_id, p_reply)` — 2~500자·1회·RETURNING 1행 판정 (S, 권장)
4. F7/F8/F13 `api_app_v1` 동명 wrapper(B-07 "전용 api_app_v1 RPC로 여는 원칙") + F7에 `p_expected_updated_at` 낙관적 잠금(`PROFILE_STALE`) — 관리자 학적 승인(service_role `university_name` 갱신)과 앱의 9필드 전면 교체 경합 방지 (S~M)
5. 선택: `mentor_activity_events_self(p_limit)`(정책 0 테이블 대체), `mentor_cap_usage_self()`(5회 왕복→1회, 가중치 사본 금지), `mentor_school_verification_submit_self`/`mentor_academic_record_change_submit_self`(객체 실재·pending 중복·길이 서버 강제), `payout_bank_allowlist()`(은행 17종 앱 상수 복제 회피)

**앱 구조.** `lib/features/mentor_console/` 신설(기존 `mypage`는 진입만): `data/`(`MentorConsoleRpcBackend(schema 인자)`, 홈·프로필·정산·리뷰·인증·활동 레포, 모델 18종, error mapper), `ui/` 화면 11개(홈·프로필 편집·가격·정산 요약/라인·계좌·리뷰·인증 현황/서류 제출/학적 변경·활동 관리·분쟁). 재사용: envelope 파서 1벌, 업로드 파이프라인·`downscaleIfOversized`·매직바이트 정책, `DataRefreshBus` 세대 2종(mentorProfile·settlement). 멘토 전용 셸 진입(역할별 탭 구성 — §7). 매니페스트: RPC 10여 종·테이블(`mentor_school_verifications`, `mentor_academic_record_change_requests`, `reviews`, `disputes`)·버킷(`student-id-images`, `profile-avatars`) 추가.

**순서·규모.** 결정 불요·읽기 중심 먼저: A0 코어 M → A1 홈 M → A4 정산 M → A6 리뷰 S~M → A2 프로필 편집 M → 오너 결정 후 S1~S4 서버 → A3 가격 S · A5 계좌 S · A7 인증 서류 M · A8 활동 S → A9 분쟁 S(CR 주문 번들 모델 공유). 총 L(전부 포함 시 L~XL).

**오너 결정 권고(13항목 요지).** 가격 설정·IQ 단가 포함 / 서류 업로드 포함(원본 열람 제외, iOS 수집 유형 갱신) · 계좌 조건부 포함 / 활동 관리 3종 포함 + 웹 액션도 같은 impl로 전환 / `api_app_v1` wrapper 선행(개발 중 `api_web_v1` 직접 호출 임시 허용 여부 별도) / 아바타 포함 / 리뷰 답글 RPC / 활동 이력 보류 / 이번 달 수익 = `mentor_settlement_summary.by_source_this_month` 합 / 엑셀 제외 / V7 학생 라벨 미노출 / 은행 allowlist 서버 RPC / F7 낙관적 잠금 도입.

**지뢰.** F7 전면 교체 ↔ 관리자 학적 승인 경합(승인값 롤백 + 192 트리거로 학교 인증 pending 회귀). 가격 밴드·cap 가중치 앱 사본 금지. 활동 RPC를 만들고 웹 액션을 전환하지 않으면 규칙 이원화(KST 6개월·기간 연장 SQL 이식 검증). 자동 복귀(`pause_until` 경과)가 DB 미반영 — 앱 판정식 정합 필요. `student-id-images` 버킷 크기·MIME 무제한(클라이언트 검증 의존 → RPC로 보강). `profile-avatars` public 버킷 보상 삭제 누락 시 고아 공개 객체. 계좌 원문은 마스킹 후 즉시 폐기(로그·Sentry·SharedPreferences 금지). 리뷰 작성자 라벨은 `users` RLS로 0행 → `get_mentor_student_nicknames` 범위 밖은 '학생' 폴백.

### 5.3 계정 · 본인인증 · 온보딩 (+ 관리자 콘솔 포함 여부)

> 상세 설계: `design/account_identity_admin.md` (갭 30항목 · 서버 신설 0-A~0-E · 앱 단계 1~9).

**핵심 판정(코드·SQL 재확인).**
- 회원가입은 브라우저 `auth.signUp` + 메타 20키 하나이고, `users`·`mentor_profiles(verification_status='pending')`·`verification_logs`·`user_consent_records` 행은 SECURITY DEFINER 트리거 2종이 만든다 → **앱이 같은 메타로 직접 가입 가능, 서버 객체 신설 0**. `app_role`은 `student|mentor`만 유효(그 외는 student 폴백).
- 소셜 로그인은 웹·앱 모두 0건. 이메일 인증(Confirm email)은 코드가 양쪽 지원, 운영값 (확인 필요).
- `users`는 authenticated UPDATE 권한 회수 + 보호 컬럼 트리거 + `status` CHECK(active/suspended/banned/deleted). `mentor_profiles`는 클라이언트 쓰기 전면 회수 → 멘토 학생증 반영(`student_id_image_url`)만 신설 RPC가 필요하다.
- NICE 본인인증은 `/api/identity/start·return` + service_role 전용 테이블(`identity_verifications`, `nice_auth_tokens`) + 서버 env 암호키(AES-256-GCM, HMAC di_hash) + 쿠키 세션 + 웹 도메인 복귀 URL에 묶여 있어 **네이티브 재현 불가 → WebView 위임이 유일한 현실적 경로**. 현재 `/api/app-session/bootstrap`은 멘토 전용·target 1종(`shortform_create`)이라 확장이 선행된다.
- 계정 상태 판정은 앱 `AccountStatusReader`가 웹 strict 게이트와 같은 입력으로 동등 판정한다. 탈퇴는 앱이 self v2 RPC 4종으로 이미 정합(취소창 DB 정본 30일 — 웹 문구 "30분"이 오기).
- 관리자 콘솔 35페이지 중 service_role 비의존은 3화면 정도, 관리자 JWT로 가능한 쓰기 RPC는 2종(`approve_mentor_school_verification_admin`, `admin_issue_user_warning`)뿐, MFA 코드 검증 미구현.

**갭 요약(30항목 → 포함 22 · 웹 위임 3 · 제외 3 · 오너 결정 2).**

| 구분 | 항목 |
|---|---|
| 포함(기존 객체) | 학생/멘토 회원가입 네이티브, 비밀번호 재설정 메일 발송(`resetPasswordForEmail`), 로그인·로그아웃·게스트(유지), 계정 상태 판정(`deleted` 명시 + 미지 값 fail-closed 권고), 탈퇴 요청·취소(유지), 탈퇴 비밀번호 재인증(일회용 클라이언트 `persistSession:false`), 프로필·알림 설정·차단(유지), 가입 직후 온보딩 상태 기계 |
| 포함(서버 선행) | 멘토 학생증 반영 `api_app_v1.mentor_student_id_image_set_self(p_storage_path)` + impl(경로 첫 세그먼트=uid·객체 실존/소유자/MIME/20MB 검증·잠금 규칙) · 마케팅 동의 `api_app_v1.user_marketing_consent_set_self(boolean)`(현재 `api_web_v1`에만 존재, impl 분리) · 탈퇴 사전조건 5종 조회 `account_deletion_preconditions_self()`(웹 TS 집계식을 읽기 RPC로) |
| 웹 위임(WebView) | 본인(self) NICE 인증, 보호자(guardian) 인증·동의 기록, 새 비밀번호 설정(recovery 세션 — 앱 딥링크 스킴 0) |
| 제외 | 관리자 로그인·콘솔(권고), 소셜 로그인(범위 밖) |
| 오너 결정 | 이메일 인증 운영값, IDENTITY_GATE 앱 강제 여부 |

**서버 선행(웹 저장소).** 0-A bootstrap 확장 — target 맵 `{shortform_create(mentor), identity_onboarding→/app/onboarding/verify(student|mentor), (옵션)admin_console(admin)}` + 역할 허용 집합 + 오류코드 `role_not_allowed` + 완료 브릿지 kind `identity`/result `{verified, cancelled}` + 앱 표면 페이지 `app/app/onboarding/verify·guardian` + `/api/identity/start`에 `surface:'app'` 쿠키로 복귀 폴백 분기 (M) · 0-B 학생증 RPC (S) · 0-C 마케팅 동의 wrapper (S) · 0-D 탈퇴 사전조건 RPC (M) · 0-E(옵션) `get_app_runtime_flags()`로 IDENTITY_GATE 플래그 전달 (S).

**앱 구조.** `AccessState` 5→7종: `needsIdentity`(게이트 강제 ON일 때만 생성, 미채택 시 `full` + 배지) · (선택) `needsMentorDocs`는 접근 상태가 아니라 마이페이지 배너 권고. `EntryGuard`를 "허용 위치 집합" 방식으로 재정의(`loggedOut`: `/login /signup* /forgot-password`, `needsIdentity`: `/onboarding/identity /account/delete /blocked` 등). `AuthService`의 users 통합 SELECT에 `identity_verified_at` 추가(왕복 0 증가). `ShortformComposeBridge` → `AppSurfaceBridge` 일반화 + `AppSurfaceWebViewScreen`. 모듈: `features/auth/`(가입 폼·검증·메타 직렬화), `features/onboarding/`(상태 기계·WebView 진입), `features/account/`(탈퇴 정합·마케팅 동의). 매니페스트: RPC 3종 추가, 버킷 `student-id-images` 추가, iOS PrivacyInfo 수집 유형(이름·생년월일·학교) 갱신.

**순서·규모.** 서버 0-A~0-D(M+S+S+M) → 앱 1 코어(AccessState·EntryGuard·라우트) M → 2 브릿지 일반화 M → 3 회원가입 L → 4 비밀번호 재설정 S → 5 본인인증 WebView M → 6 학생증 M → 7 마케팅 동의 S → 8 탈퇴 정합 M → 9 매니페스트·계약 문서 갱신 S.

**오너 결정 권고.** (i) 관리자 콘솔 **제외 유지**(admin→blocked) — WebView 위임은 MFA(PR-12b) 완료 후 재검토, 최소 표면 네이티브는 XL. (ii) 회원가입 **네이티브**. (iii) 본인인증 **WebView 위임**. (iii-1) 이메일 인증 운영값 확인 후 가입 직후 흐름 확정. (iv) 소셜 로그인 미도입. (v) IDENTITY_GATE 1차 비강제(배지) → 운영 ON 확정 후 플래그 RPC 기반 강제, DB 게이트는 비권고. (vi) 비밀번호 재설정 새 비밀번호 입력은 웹 완료. (vii) 탈퇴 사전조건은 조회 RPC만(요청 RPC 내 강제는 구 앱 회귀 위험). (viii) 마케팅 동의 토글 앱 노출. (ix) 미지 status fail-closed.

**지뢰.** 트리거 지연·`app_role` 오타 → role 불명 blocked 또는 학생 폴백(최초 로드 재시도 필요). NICE 표준창 외부 호스트가 코드 상수에 없어 WebView allowlist 정확 호스트 고정 필수 (확인 필요). Confirm email ON이면 세션 없는 가입 직후 학생증 업로드 불가(첫 로그인 유도). 비밀번호 최소 길이 서버 6 vs 웹 8 → 앱 8 강제. `consent_version` 불일치(`legal-placeholder-2026-06-20` vs 마케팅 RPC `v1`). Storage 업로드 `owner_id` 채움 여부 (확인 필요) — 신설 RPC가 fail-closed로 전부 거절할 수 있다.

### 5.4 학생 채널 정합 — 질문방 · 개별질문 · 멘토찾기 · 구독 조회 · 리뷰 · 마이페이지

> 상세 설계: `design/student_channels_parity.md` (갭 36항목 · 서버 신설 S-1~S-7 · 단계 P0~P6). 이 도메인은 설계 에이전트가 반복 타임아웃되어 1단계 근거를 통합해 종합 단계에서 직접 작성했다.

**현황.** 기존 앱의 핵심 루프(질문 작성 → 답변 → 확인, 첨부·스캔·주석·PDF, 개별질문 목록·상세·메시지·첨부·release·refund, 멘토 디렉터리·찜·무료질문, 알림·마이페이지)는 웹과 같은 RPC·뷰를 쓰고 있어 정합도가 높다. 갭은 "웹에 있는 부수 기능"과 "앱 계층에만 있는 정책 판정"에 몰려 있다.

**갭 요약(36항목 → 포함 27 · 웹 위임 2 · 제외 4 · 오너 결정 3).**

| 구분 | 항목 | 서버 표면 |
|---|---|---|
| 포함(기존 객체) | **오답 표시**(`qna_flag_wrong_answer` u — 앱 미사용), 스레드 생성 `topic` 전달, 스레드 탭 분류(all/waiting/needReview/done) 정합, **마이페이지 구독 카드 잔여 질문수**(`weekly_question_usage_self_batch` ≤50 — 현재 null), 한도 RPC 실패 시 fail-closed 표시(현재 보수적 통과), IQ **direct 멘토 보드**(디렉터리 + 단가 배치 — 가격 비표시 정책 하 "개별질문 가능" 여부만), IQ → 구독방 이전 링크(`individual_question_transfers` `iqt_select_student`), 멘토찾기 **필터 7종·정렬 4종**(웹 인메모리 규칙을 순수 함수로 이식 + 동치 테스트; 학교등급·계열 카탈로그 SELECT), 카드 게이트(승인 + 과목≥1), 최근 본 멘토(SharedPreferences ≤20 + 디렉터리 `.in`), 상세 **구독 마감 배지**(cap RPC 3종 anon/authenticated — 웹의 service_role은 필수 아님), `is_open_for_subscriptions`, **리뷰 열람**(공개 predicate + `get_mentor_review_stats(…, false)`, 작성자는 RLS 0행 → "학*" 마스킹 폴백), 구독 목록 **7종 status 라벨**(`cancel_scheduled` 누락 정정)·이용개시 판정, 마이페이지 집계(`payments` 건수는 결제 인접·제외), 원장 기간 필터·페이징 | 새 객체 0 |
| 포함(서버 선행) | **S-1** `qna_append_message` 구독 게이트(RPC가 구독 만료·무료 스레드를 검사하지 않음 — 웹은 TS로만 차단 → 앱 직접 호출 공백) · **S-2(권장)** 리뷰 `review_eligibility_self / review_create_self / review_update_self`(자격은 RLS `reviews_insert_student`가 DB에서 강제하지만 20~500자·1~5·마스킹·모더레이션 잠금은 TS 전용) · **S-4(권장)** 연결노트 `connection_note_save/update/delete_self`(구독 가드 서버화 — 현재 웹 앱 계층 전용) · **S-7** IQ 3테이블 Realtime publication 확인 | 마이그레이션 3~4본 |
| 웹 위임 | IQ 생성(캐시 hold — 현행 유지), 구독 해지 예약 취소(undo, 재개=결제 재동의) |
| 제외 | 상세 CTA 구독(Commerce-Zero), 리뷰 삭제(웹도 없음), 재구독, 홈·노트·레거시 redirect |
| 오너 결정 | IQ **답변 확정 의미**(웹 명시 UPDATE vs RPC 첫 메시지 자동 전이 — `answer_individual_question` u 존재), **구독 해지 예약 포함**(S-3 `subscription_cancel_at_period_end_self` 조건부), 잔여 환불 신청(지원 도메인 결정 C와 동일 RPC) |

**결제 경계 판정.** IQ release(`release_individual_question` u, 학생 본인) = 에스크로 확정 → 허용 유지(앱 이미 호출). IQ refund(u) 허용. 가격대 필터·가격 정렬·가격 표시는 정책 §4("가격표+구매 유도") 회피를 위해 앱 제외 유지 권고. 캐시 잔액·원장·구독 상태 읽기 허용, 페이싱크 pending 섹션은 제외.

**앱 구조.** 기존 feature 확장: `question_room`(오답 표시·topic·탭 분류 순수 함수·배치 사용량 → `SubscriptionSummaryStore`·`WeeklyUsage.failed`), `individual_question`(direct 보드 화면·transfer 링크·확정 의미), `mentors`(`MentorDirectoryFilter`·`MentorSort` 순수 함수 + 카탈로그 레포 + `RecentMentorsStore` + 상세 cap 배지·리뷰 진입), 신설 `features/reviews/`(레포·모델·매퍼·목록·작성 — S-2 RPC 경로, 미채택 시 직접 INSERT + Dart 검증 + 23505 처리), `mypage`(구독 관리 화면 7종 라벨·해지 예약·환불 신청 진입·집계 정합·원장 확장). `DataRefreshBus.subscription` 세대는 현재 생산자 0 → 해지 예약·환불 신청이 첫 생산자. 매니페스트: RPC `qna_flag_wrong_answer`·`get_mentor_review_stats`·cap RPC 3종(·S-2/S-3/S-4·`answer_individual_question`), 테이블 `reviews`·`individual_question_transfers`·`school_tier_catalog`·`major_category_catalog`(·`subscription_billing_events`·`refunds`).

**순서·규모.** P0 서버(S-1·S-7 → 결정 후 S-2·S-3·S-4) → P1 질문방 정합 S~M → P2 멘토찾기 정합 M → P3 리뷰 열람 S → 작성 M → P4 구독 관리 M(+해지 예약 S) → P5 IQ 정합 M → P6 연결노트 S. 총 L.

**오너 결정 권고(10항목 요지).** D-1 해지 예약 조건부 포함(undo는 웹) / D-2 환불 신청은 지원 도메인 결정과 동일 / D-3 연결노트 append 의미 유지 + S-4 RPC(웹 액션도 같은 impl) / D-4 `qna_append_message` 게이트 서버화(웹 동작 변화 없음) / D-5 IQ 확정 = RPC 자동 전이를 정본, 웹 명시 확정은 `answer_individual_question`로 수렴 / D-6 가격대 필터·정렬·표시 앱 제외 / D-7 리뷰 검증 RPC(웹 API route도 같은 impl) / D-8 디렉터리 서버측 검색 RPC는 멘토 1,000 미만이면 보류 / D-9 무료 스레드 배지 서버 객체 보류 가능 / D-10 웹 `CLAUDE.md` 리뷰 조건 문구("2회 연속 결제")를 SQL 170 기준으로 정정.

**지뢰.** `check_review_eligibility`의 authenticated EXECUTE 여부 (확인 필요) — 사전 자격 조회는 S-2 wrapper로. `subscription_billing_events` 당사자 SELECT 정책 (확인 필요) — 없으면 `my_subscriptions_self().current_plan_amount_cents`. IQ `expires_at` NULL 가능 → `created_at + 기본시간` 폴백을 앱도 동일 적용. 디렉터리 전량 로드(앱 100×50 / 웹 10,000 상한) 한계 동일. `weekly_question_usage_self_batch` 최대 50 → 분할 호출. 학교등급 카탈로그 `그외`(193) 포함 — 필터 UI는 웹처럼 `그외` 비노출·`미분류` 종속 규칙 확인.

### 5.5 커뮤니티 · 공지 · 알림 · 지원 정합

> 상세 설계: `design/community_notifications_support.md` (갭 50항목 · 서버 신설 S-1~S-6 · 단계 P0~P7).

**현황.** 앱은 게시판 열람·작성·수정·삭제·댓글(평면)·반응·이미지·조회수, 숏폼 열람·재생·좋아요/스크랩·댓글, 신고·차단, 알림 목록·읽음·unread·Realtime·설정을 이미 갖고 있다(웹보다 넓은 부분도 있다: 숏폼 스크랩, 댓글 작성자 차단, 알림 Realtime). 웹 대비 갭은 "쓰기 정합"과 "지원 표면"에 몰려 있다.

**갭 요약(50항목 → 포함 33 · 웹 위임 3 · 제외 6 · 오너 결정 8).**

| 구분 | 항목 | 서버 표면 |
|---|---|---|
| 포함(기존 객체로 가능) | 게시판 정렬 popular·keyset 페이징, **임시저장(draft)** 작성·목록·이어쓰기(`community_post_create(p_status='draft')`), **답글 2-depth**(`comments.parent_id`, 뷰 트리 조립), **게시판 댓글 본인 삭제**(`soft_delete_own_content('board_comment')`), 본인 숨김 배지, 숏폼 카테고리 4종·정렬, **숏폼 썸네일 서명 URL**(현행은 ref를 `Image.network`에 넘겨 항상 플레이스홀더 — 결함), 내 신고 내역(`content_reports` 본인 SELECT), 공지 목록(`app_notices` anon/authenticated SELECT), 알림 kind에 `refund` 추가·딥링크 보강(`subscription_id`, `notification_id` 재조회) | 새 객체 0 |
| 포함(서버 선행) | **S-1 UGC 직접 INSERT 계정 게이트 트리거** — 댓글·반응·신고·차단 직접 INSERT 정책에 계정 상태 검사가 없어 정지·탈퇴 진행 중 계정이 쓸 수 있다(웹은 server action `assertAccountActive`로만 막음) | 마이그레이션 1본(트리거 + 롤백) |
| 소프트 삭제 통일 | 앱 4종(게시글·게시판 댓글·숏폼·숏폼 댓글) 모두 `soft_delete_own_content(p_kind, p_id)`로 전환 권고. 반환 void → 앱 봉투 strict 파서가 아닌 `raise 'CODE'` 매퍼 스타일. `deleted_by` 기록·관리자 숨김 글 `CONTENT_MODERATED`·멱등이 단일 규약이 된다. 구 `community_comment_soft_delete_self` 회수는 버전 게이트 최소 빌드 상향과 동기 | 앱 매니페스트 RPC −2 |
| 오너 결정 | A 숏폼 작성(WebView 유지 → 2차 `api_app_v1.shortform_post_create/update` 신설) · B OS 푸시 재도입(서버 GRANT `register_device_token`은 2026-08-27 적용 증적 있음, 남은 것은 앱 SDK·Data Safety·활성 순서) · C 환불 신청(포함 시 `refund_request_subscription_self` SECDEF 신설, 별표4 비례식 SQL 이식) · D 삭제 RPC 통일 범위 · E 숏폼 본인 삭제 UI · F 신고 사유 정본 어휘(앱 영문 코드 5종 vs 웹 한글 5종 — 불일치 시 멱등 키가 갈려 교차 중복 접수) · G 공지 팝업 방식 · H 분쟁 목록/상세(CR 포함 여부 종속) · K 댓글 연락처 마스킹 서버 트리거화 · L `sfv_public_read` 버킷 전체 SELECT 축소 |
| 웹 위임 | 분쟁 제기(CR 주문방 진입점), 고객센터 FAQ(웹 `/support`에 충전·구독 링크가 있어 `?src=app` 시 비노출 권고), 약관·개인정보(정적 TSX, DB 원천 없음) |
| 제외 | promotion_campaigns(웹도 미소비), 공지→알림 producer 없음, 분쟁 처리 이력(admin RLS), 해시태그(웹 사장), 댓글 좋아요(표면 없음), 레거시 API route |

**앱 구조.** 기존 `lib/features/community`·`notifications`·`mypage/support` 확장. 추가 모듈: `features/notices/`(레포·목록·배너), 알림 유형→(kind, destination, opener) 단일 테이블, 썸네일 리졸버(제네릭 리졸버 1벌로 통합 시 버킷 인자만), 푸시 재도입 시 `core/push/` 준비 경계(`FirebasePushGateway`)·토큰 수명주기(로그인/복원 시 `register_device_token`, 로그아웃 전 본인 행 `revoked_at`)·푸시 탭은 `notification_id`로 행 재조회 후 인앱 라우터 재사용. 매니페스트 갱신: RPC `soft_delete_own_content`·`register_device_token`(·`refund_request_subscription_self`), 테이블 `app_notices`(·`disputes`/`refunds`), 버킷 `shortform-thumbnails`.

**순서·규모.** P0 서버 선행(S-1, 신고 어휘) S → P1 커뮤니티 정합 M → P2 공지 S → P3 알림 정합 S~M → P4 지원 읽기 S(신고)/M(분쟁) → P5 환불 신청(결정 C) 서버 M+앱 M → P6 푸시 재도입(결정 B) 앱 L → P7 숏폼 네이티브(결정 A) XL.

**지뢰.** `api_app_v1` RPC는 `.schema('api_app_v1')` 필수(PGRST202). CR 게이트 2종을 앱 `kGatedNotificationTypeCodes`와 서버 `notification_unread_count_self`가 각자 제외 — CR 포함 시 서버 재정의 없이 앱만 바꾸면 배지≠목록. 푸시 활성 순서(워커 플래그 ON → `push_transport_enabled` → live) 고정. iOS 계약 테스트의 `DeviceID` 금지 집합·`'firebase' 0건` 테스트는 의도된 계약 갱신으로 함께 바꿔야 한다. 환불 신청 성공 즉시 해당 구독 질문 작성이 `SUBSCRIPTION_REFUND_PENDING`으로 잠긴다(사전 고지 + `DataRefreshBus` bump).

---

## 6. 서버 신설 객체 총람 (웹 저장소 pack 선행 작업)

규약: `api_app_v1.<name>` SECURITY DEFINER · `SET search_path=''` · `auth.uid()` 자체 도출(`p_user_id` 인자 금지) · 판정은 `core_private.<name>_impl(p_actor uuid, …)` INVOKER · `REVOKE ALL FROM PUBLIC, anon` → `GRANT EXECUTE TO authenticated`(service_role 부여 금지) · 반환 envelope `{ok, contract_version:1, …}` / `{ok:false, contract_version:1, code}` · 계정 게이트(positive allowlist + `account_deletion_write_blocked`) · 파일 `supabase/sql/199_*.sql` + rollback + `post_ledger_backfills` 등재 → pack 생성기 → `validate_*` → `db-apply-pending` → `contracts:export/verify` → 앱 매니페스트. **자금 인접 객체는 §9 결정 전에는 만들지 않는다.**

### 6.1 Tier A — 포함 확정, 앱 출시 전 필수

| # | 객체 | 도메인 | 규모 |
|---|---|---|---|
| A1 | `public.ugc_account_gate()` BEFORE INSERT 트리거 6종(`comments`·`community_comments`·`post_reactions`·`shortform_reactions`·`content_reports`·`user_blocks`) — SECURITY INVOKER, `ACCOUNT_*` | 커뮤니티 | S |
| A2 | `public.qna_append_message` 구독 게이트 보강(또는 `question_messages` BEFORE INSERT 트리거) — `SUBSCRIPTION_REQUIRED` | 학생 채널 | S |
| A3 | `api_app_v1.custom_request_post_delete_draft(p_post_id)` (W-0) | 맞춤의뢰 | S |
| A4 | `api_app_v1.custom_order_deliverable_register(p_order_id, p_storage_path, p_original_filename, p_mime_type, p_file_size, p_note)` (W-8) — 버전 채번 + `custom_order_mentor_deliver` + 이벤트 원자화 | 맞춤의뢰 | M |
| A5 | `api_app_v1.custom_order_message_create(p_order_id, p_body, p_attachment jsonb)` (W-7) — 종료 차단·마스킹 DB 이전 | 맞춤의뢰 | M |
| A6 | `core_private.mask_contact_text(text)` IMMUTABLE — 커뮤니티 RPC 인라인 정규식 6종 추출(CR·리뷰·댓글 트리거가 공유) | 공통 | S |
| A7 | `alter publication supabase_realtime add table` CR 4테이블(+ IQ 3테이블 포함 여부 확인) | 맞춤의뢰·학생 채널 | S |
| A8 | `public.notification_unread_count_self()` 재정의 — CR 2종 제외 해제(**앱 게이트 해제와 같은 릴리스**) | 맞춤의뢰·알림 | S |
| A9 | `drop policy cro_update`(authenticated) — `payment_status` 위조 가능 정책 잠금 | 맞춤의뢰 | S |
| A10 | `unique index ux_cra_post_mentor_once on custom_request_applications(post_id, mentor_id)` | 맞춤의뢰 | S |
| A11 | `api_app_v1.mentor_student_id_document_set_self(p_object_path)` (+impl: 경로·`storage.objects` 실재·소유·MIME 검증) | 멘토 콘솔·계정 | S |
| A12 | `api_app_v1.user_marketing_consent_set_self(boolean)` — `api_web_v1` 본문을 impl로 분리·공유 | 계정 | S |
| A13 | `api_app_v1.account_deletion_preconditions_self()` — 웹 TS 사전조건 5종 집계를 읽기 RPC로 | 계정 | M |
| A14 | `POST /api/app-session/bootstrap` 확장(target 맵 `identity_onboarding`·`mentor_verification`, 역할 게이트, admin 불허, kind `identity`/results, `role_not_allowed`) + 앱 표면 페이지 `app/app/onboarding/verify·guardian` + `/api/identity/start` `surface:'app'` 복귀 분기 + 계약 테스트 | 계정 | M(웹 코드) |
| A15 | `get_mobile_app_config(p_platform)` anon RPC(또는 버전 정책 RPC 확장) — `identity_gate_enabled`(필수)·`cr_enabled`·`push_enabled`·`maintenance_message` | 플랫폼 | S |
| A16 | 로컬 `supabase/config.toml [api].schemas`에 `api_web_v1`·`api_app_v1` 추가 | 플랫폼 | S |

### 6.2 Tier B — 권장(미채택 시 앱이 Dart로 재구현 → 이중 정본)

| # | 객체 | 도메인 | 규모 |
|---|---|---|---|
| B1 | `api_app_v1.mentor_profile_update_self(9인자 + p_expected_updated_at)` / `mentor_plan_prices_set_self(3)` / `mentor_payout_account_update_self(2)` — F7/F8/F13 `api_app_v1` twin(impl 공유), F7 낙관적 잠금 `PROFILE_STALE` | 멘토 콘솔 | S~M |
| B2 | `api_app_v1.mentor_activity_pause_self(p_days, p_reason)` / `mentor_activity_resume_self()` / `mentor_activity_terminate_self()` + impl(`mentorActivityService.ts` 규칙 이식, 환불 생성 없음) — 웹 액션도 같은 impl로 전환 | 멘토 콘솔 | M |
| B3 | `api_app_v1.mentor_review_reply_self(p_review_id, p_reply)` — 2~500자·1회·RETURNING 판정 | 멘토 콘솔 | S |
| B4 | `api_app_v1.review_eligibility_self(p_mentor_id)` / `review_create_self(p_mentor_id, p_rating, p_body)` / `review_update_self(p_review_id, p_rating, p_body)` — 웹 API route도 같은 impl | 학생 채널 | M |
| B5 | `api_app_v1.connection_note_save_self(p_room_id, p_body)` (+update/delete) — 구독 가드 서버화, append 의미 유지 | 학생 채널 | S~M |
| B6 | `api_app_v1.custom_request_application_create(...)` (W-9) / `custom_request_post_create/update(...)` (W-10) — 승인 게이트·중복·필수값·예산·동의·마스킹 | 맞춤의뢰 | M+M |
| B7 | Storage DELETE 정책(미등록 본인 객체) — CR 3 버킷 (S-9) | 맞춤의뢰 | S |
| B8 | `comments`/`community_comments` 연락처 마스킹 BEFORE INSERT 트리거(A6 공유) | 커뮤니티 | S |
| B9 | `content_reports.reason` 정본 어휘 CHECK(NOT VALID) 또는 `reason_code` 컬럼 | 커뮤니티 | S |
| B10 | `sfv_public_read`(+`cpi_public_read`) 버킷 전체 SELECT → published 참조 객체 + 본인 폴더로 축소 | 커뮤니티 | S |
| B11 | 선택: `mentor_activity_events_self(p_limit)`, `mentor_cap_usage_self()`, `mentor_school_verification_submit_self`/`mentor_academic_record_change_submit_self`, `payout_bank_allowlist()`, `mentor_directory_search_v1(...)`, 무료 스레드 배지용 컬럼/RPC, RPC 018 활성 주문 제외 필터, 지원 첨부 "선정 후 미리보기" 정책 강제 | 멘토 콘솔·학생 채널·맞춤의뢰 | S each |

### 6.3 Tier C — 오너 결정 전 금지(결제 경계 §3)

| # | 객체 | 판정표 | 조건 |
|---|---|---|---|
| C1 | `api_app_v1.subscription_cancel_at_period_end_self(p_subscription_id)` | §3 #5 | 해지 예약 포함 결정 시 |
| C2 | `api_app_v1.refund_estimate_subscription_self` / `refund_request_subscription_self(p_subscription_id, p_reason)` + impl(별표4 비례식 SQL 이식, advisory lock) | §3 #7 | 환불 신청 포함 결정 + 정책 문서 §3 개정 |
| C3 | `api_app_v1.custom_order_select_application_with_hold(p_post_id, p_application_id)` (W-1) · `custom_order_student_accept(p_order_id)` (W-2) · `custom_order_student_cancel(p_order_id)` (W-3) | §3 #13·#14 | 결제 실행이 앱에 들어오는 결정 — 1차 웹 위임 권고 |
| C4 | `create_individual_question_as_student_v2(... p_subject, p_topic, p_required_school_tier, p_required_major_category)` | §3 #9 | IQ 생성 앱 포함 결정 시(법무 확인 선행) — 권고 웹 위임 유지 |
| C5 | `api_app_v1.shortform_post_create(...)` / `shortform_post_update(...)` + impl(ref 소유 검증·마스킹·author_label·멱등·rightsAck) | — | 숏폼 네이티브 작성 결정 시(2차) |

### 6.4 계약·매니페스트 동반 변경
- 앱 계약(`api_app_v1_contract`) v1.2 증보: 위 객체 시그니처·envelope·오류코드(UPPER_SNAKE 추가만)·GRANT, **읽기 뷰의 `api_web_v1` 교차 사용 명문화**, CR 절 신설(웹 계약 v1.1은 CR을 "신규 객체 없는 유지 영역"으로 고정 → §19.5 재동기화).
- `docs/contracts/api_web_v1_contract_v1_1.md` §7/§9 오류코드 사전 추가 → `npm run contracts:export && contracts:verify`.
- 앱 `outbound_api_manifest_test.dart`: 키를 `schema.name` 쌍으로 개정, 신규 RPC·테이블(`custom_request_*`·`custom_order_*`·`disputes`·`reviews`·`app_notices`·`individual_question_transfers`·`mentor_school_verifications`·`mentor_academic_record_change_requests`·`school_tier_catalog`·`major_category_catalog`…)·버킷(`custom-request-post-attachments`·`custom-request-application-attachments`·`custom-order-deliverables`·`student-id-images`·`profile-avatars`·`shortform-thumbnails`) 추가, 폐기 표면(`community_comment_soft_delete_self`·`connection-note-ink`)은 `kForbiddenWords`로, 자금 인접 RPC(`create_individual_question_as_student` 등)는 §9 결정에 따라 금지어 이동.
- 웹 `contracts:export` 산출물을 앱 CI가 읽어 "매니페스트의 모든 `schema.name`이 존재하고 authenticated EXECUTE/SELECT가 있다"를 검증하는 잡 신설.

---


---

## 7. 플랫폼 공통 아키텍처 (기능 도메인의 밑바닥)

> 상세 설계: `design/platform_common.md` ((1)~(8) 절 · 유지/일반화/교체 총괄표 · 오너 결정).

### 7.1 라우팅·셸 — 권고 C: `StatefulShellRoute` + 역할별 브랜치 테이블 + id 파라미터 상세 라우트

현행(라우트 4개 + 고정 5탭 IndexedStack + 모델 인자 push 46곳 + `TabNavigator` int 채널)은 딥링크·복원·역할별 네비를 표현하지 못한다. 대안 4개(현행 유지 / 평면 명명 라우트 / 셸 라우트 + 브랜치 테이블 / 역할별 라우터 2개) 중 **C**를 권고한다.

1. 라우트 테이블을 데이터로 — `lib/app/routes/app_routes.dart`의 `AppRouteSpec{path, builder, meta{roles, guestAllowed, requiresOnboardingDone, tab, devOnly}}`. `EntryGuard.redirect`는 순수 함수로 유지하되 입력을 "경로 문자열 매칭"에서 "매칭된 spec의 메타"로 바꾼다(전수표 테스트 승계).
2. 셸 — `StatefulShellRoute.indexedStack` 브랜치를 `RoleTabSpec` 테이블(학생: 웹 잠금 7 네비 중 결제·충전 제외 집합 / 멘토: 질문방·맞춤의뢰·커뮤니티)에서 생성. 현행 5곳 결합(`AppTab`·`_pages`·`_icons`·`bottomTabLabels`·`guestAllowedTabs`)을 spec 1곳으로 흡수. `ScreenVisibility`/`ResumeVisibilityGate`는 브랜치 활성 여부로 그대로 공급, lazy 빌드는 `StatefulShellBranch` 기본 제공.
3. 상세 라우트는 id 파라미터(`/question-room/:roomId/threads/:threadId`, `/iq/:questionId`, `/community/board/:postId`, `/mentors/:mentorId`, `/custom-request/orders/:orderId` …) — 화면이 id로 자체 조회(RLS 정본). 기존 모델 인자 화면은 `XxxScreen.fromId(id)` 진입 생성자를 추가해 점진 이식(46곳 push를 한 번에 안 바꿔도 컴파일 유지).
4. **딥링크 경로 스킴을 웹 라우트와 맞춘다**(`/mentors/[mentorId]`, `/question-room/[roomId]`, `/community/board/[id]`, 멘토는 `/mentor/...` 접두) — 푸시 `type+ids → 경로` 변환이 한 줄이 되고, 향후 App Links/Universal Links 도입 시 `assetlinks.json`·AASA만 웹에 두면 된다(웹 선행).
5. `TabNavigator.go(int)` → `AppNavigator.go(AppRouteTarget)`(sealed: Tab/Path). `NotificationDeepLinkController`는 콜백 타입만 바꾸고 판정·dedup·pending TTL은 무변경. `core → app` 역방향 import는 콜백 주입으로 끊는다.
6. 게스트·온보딩 중간 상태는 라우트 메타(`guestAllowed`, `/onboarding/*` 그룹)로 셸 밖에서 판정.
7. Realtime 채널은 "보이는 브랜치만 구독, 가려지면 해제·재조회" 규약을 공통 포트에 넣어 탭 수 증가에 대비.

### 7.2 세션·역할·상태 — 권고 B: `AccessState`에 `onboarding` 1종 + `OnboardingNeed` 집합

1. `AccessState { loading, loggedOut, guest, onboarding, full, blocked }`. `computeAccess` 순서: `… → admin → blocked → (student|mentor) → needs.isEmpty ? full : onboarding`. 순수 함수 유지, 전수표 테스트에 onboarding 행 추가.
2. `OnboardingNeed`: `profileRowMissing`(users 행 없음 — 즉시 blocked가 아니라 짧은 재시도 창), `identityRequired`(`identity_verified_at == null` ∧ 서버 게이트 ON), `guardianRequired`(서버 판정을 읽는다 — 나이 계산 로컬 금지), `mentorApprovalPending`(`verification_status ∉ {approved, verified, active}` — 컬럼 SELECT 권한 (확인 필요)), `mentorProfileIncomplete`, (이메일 인증 ON이면) `emailUnconfirmed`. 각 need는 읽기 허용 라우트를 갖는다(라우트 메타 `allowedDuring`).
3. 게이트 플래그의 서버 정본화 — 앱은 `IDENTITY_GATE_ENABLED`를 알 수 없으므로 `get_mobile_app_version_policy` 응답에 싣거나 `get_mobile_app_config()` anon RPC를 신설(웹 pack 선행). 서버 값이 없으면 "게이트 OFF"가 아니라 "미확인 → 온보딩 유도 없음 + 쓰기 실패 시 `IDENTITY_REQUIRED` 매핑"으로 동작.
4. 역할별 기능 등록 표 — `lib/app/feature_registry.dart`의 `AppFeature{id, roles, guestAllowed, onboardingAllowed, tabSpec?, routes, notificationDestinations, refreshDomains}`. 화면 내부 `switch(currentRole)` 12곳은 (a) 역할별 별도 라우트(학생 `/question-room` ↔ 멘토 `/mentor/inbox`)로 분리, (b) 데이터 계층 분기는 `AppRole`을 인자로 받게. 목표: `currentRole` 읽기는 `app/` 3곳으로 수렴. 계약 테스트로 "모든 GoRoute가 registry에 있고 roles가 비어 있지 않다"를 강제.
5. 관리자 차단 유지(`admin → blocked`, WebView bootstrap도 admin 불허).
6. `AccountStatusReader.resolve`의 "그 외 값 active"를 `deleted`·미지 값 → 비복구 차단으로 좁힘(`users.status` CHECK 4종).
7. `AuthService.signUp(email, password, metadata)` 추가(메타 키 = 웹 `buildSignupUserMetadata` 20키).
8. `AuthService`를 `SessionController` + `ProfileController` + `AccessResolver`(순수)로 분리하되 외부 게터는 파사드로 유지(테스트 호환).

### 7.3 상태관리·DI — 권고 B: 수동 스코프 DI(`AppScope` + `Deps`) + 생성자 주입 유지, Riverpod는 조건부 보류

1. `lib/core/di/app_scope.dart`: `AppScope(deps, child)` InheritedWidget 1개 + `Deps` 불변 레코드(세션/프로필 컨트롤러, 레포 팩토리, `WebBridge`, `AttachmentUploaderPort`, `SignedUrlResolver`, `RealtimeFactory`, `FeatureFlags`, `Clock`). 테스트는 `Deps.fake(...)` — **손코딩 Fake·mock 프레임워크 금지 규율 그대로**, 기존 위젯 테스트 250개는 `xxxOverride` 우선순위(생성자 인자 > 스코프 > 기본값)로 무수정 통과.
2. 싱글턴 폐기 순서: `AuthService.instance` → `Deps.session`; `TabNavigator`/`DataRefreshBus`/`NotificationBadgeController`/`DeletionNoticeController`/`VersionGateController`는 `Deps` 소유. 계약 테스트 `lib/features/**`에서 `.instance` 0건.
3. 공유 상태 소유자: `WalletStore`, `SubscriptionSummaryStore`, `BlocksStore`(현 static 캐시 이전), `MentorProfileStore`, `CrCountersStore`를 `ChangeNotifier`로 `Deps`에 두고 `DataRefreshBus` 세대 신호를 구독해 재조회. store는 서버 정본 재조회만, 로컬 계산·영속 캐시 금지.
4. Riverpod 도입 재검토 트리거: 비동기 파생 상태 조합 3개 이상 또는 keep-alive 캐시 요구. 그때도 `AppScope → ProviderScope` 치환은 국소적.
5. 의존 방향 강제: `test/contracts/layering_contract_test.dart` 신설(`core`는 `features`/`app` import 0, `shared`는 `features` import 0 — 현 위반 4건은 포트를 `core`로 이동).

### 7.4 DB 계약 확장 원칙 — 쓰기는 `api_app_v1`, 읽기 뷰·self RPC는 `api_web_v1` 허용을 앱 계약에 명문화

| 논점 | 권고 |
|---|---|
| 표준 스키마 | 신설 쓰기 wrapper는 전부 `api_app_v1`. 읽기 뷰(invoker·동일 형상)는 `api_web_v1` 교차 사용을 계약에 명문화(복제는 유지비만). `community_posts_v1`은 앱 뷰가 있으니 `api_app_v1`로 전환. `api_web_v1`에만 있는 self RPC(F7·F8·F13·마케팅 동의)는 앱이 쓰는 시점에 `api_app_v1` 동명 wrapper(impl 공유, 계약 B-07) |
| 봉투 | 신설 wrapper는 envelope `{ok, contract_version:1, code}` 의무(계약 §8.1), 레거시 `public` raise RPC는 재정의하지 않음. 앱은 `RpcOutcome` 정규화 1벌(raise → 선두 토큰, envelope → `payload.code`, `contract_version==1` 검사) + 공통 코드 사전(`AUTH_REQUIRED`·`ACCOUNT_*`·`ROLE_NOT_ALLOWED`·`BLOCKED`·`IDENTITY_REQUIRED`) + 도메인 오버레이 |
| 매니페스트 키 | 이름 집합 → **`schema.name` 쌍 집합**(`.schema('x').rpc('y')` 함께 추출) — 새 저장소 첫 PR에서 도입 |
| 마이그레이션 위치 | 웹 pack만(변경 없음). 앱 저장소는 `SCHEMA_SOURCE_OF_TRUTH.md` + 매니페스트 테스트만 |

신설 기능 1건당 절차: ① 앱 계약 문서 항목 추가(시그니처·envelope·오류코드·GRANT) → ② `api_app_v1.<name>` SECDEF thin wrapper + `core_private.<name>_impl(p_actor uuid, …)` INVOKER, `REVOKE ALL FROM PUBLIC` → `GRANT EXECUTE TO authenticated`(service_role 부여 금지) → ③ `supabase/sql/NNN_*.sql` + rollback + `post_ledger_backfills` 등재 → `build_native_migration_pack.py` → `validate_*` PASS → PR → 라이브는 `db-apply-pending.yml`만(MCP `apply_migration` 금지, 했다면 같은 세션 역수입) → ④ `contracts:export/verify` → ⑤ `NOTIFY pgrst, 'reload schema'` → ⑥ 앱 매니페스트 갱신(같은 앱 PR) → ⑦ 로컬 `config.toml [api].schemas`에 `api_web_v1`·`api_app_v1` 추가(웹 선행) → ⑧ 자금 인접 RPC는 결제 경계 판정 전 wrapper를 만들지 않는다.

### 7.5 공통 인프라 이식 판정(20종)

| 판정 | 자산 |
|---|---|
| **그대로** | `downscaleIfOversized`, PDF 래스터(`pdfx` 포트), `ScreenVisibility`/`ResumeVisibilityGate`, `web_bridge`(경로 표에 CR·멘토 콘솔 폴백 추가만), 버전 게이트, Sentry 부팅, `commerce_policy`, scan/ink 코어("시그니처 변경 금지·추가만"), 푸시 포트(재도입은 별건), 계정 상태·탈퇴 배너(+`deleted`·`OnboardingNeed` 입력), 정본 라벨 매핑(`subject_labels` 등), 손코딩 Fake 모음 |
| **일반화(1벌로)** | 첨부 업로드 파이프라인 → `UploadPipeline{bucket, pathPolicy, registerRpc, compensate}` 코어 + 도메인 어댑터(질문방·IQ·CR 납품·CR 첨부·학생증·게시판 이미지) — HANDOFF의 "SupabaseAttachmentUploader 재구현 금지"는 "코어를 복제하지 말라"로 해석 / 서명 URL 리졸버 4벌 → `SignedUrlResolver<Ref>` 제네릭 1벌(결과 타입은 Shortform의 `{absent, resolved, failed, invalidReference}` 공통 채택, `Deps` 소유) / Realtime 포트 3벌 → `PostgresChangesSubscription` 1벌 / `DataRefreshBus` → `RefreshDomain` enum 맵 / 에러 매퍼 → `RpcOutcome` + `ErrorCodeTable` / WebView 브릿지 → `AppSurfaceBridge` 표(웹 target enum 확장 선행) / `AppConfig`·`.env` / `model_parse` 2벌·페이지네이터 → `core/data/parse.dart` 1벌 + `KeysetPaginator<T>` 1벌 |
| **교체** | 라우팅·셸·`AccessState`·역할 분기·싱글턴(7.1~7.3) |

### 7.6 테스트·CI

- **승계**: `outbound_api_manifest_test`(키를 `schema.name`으로 개정), `iq_create_boundary_test`, `ios_release_config_contract_test`(상수만 새 값), `xcode_cloud_bootstrap_contract_test`, `android_signed_workflow_contract_test`(재작성된 워크플로에 맞게), `s3e_doc_contract_test`. `flutter-ci.yml`은 그대로(analyze 파싱 게이트 유지, **Flutter 핀 3.44.6** — HANDOFF의 3.44.4는 구식).
- **신설 계약 테스트**: `layering_contract_test`(의존 방향), `feature_registry_contract_test`(모든 라우트가 registry에·admin 허용 라우트 0), `flags_contract_test`(릴리즈 기본값 표 ↔ `bool.fromEnvironment` 기본값 일치), `bridge_targets_contract_test`(앱 target·allowlist ↔ 웹 `appSurfacePaths.ts` 상수 문자열 일치), `no_singleton_in_features_test`.
- **서명 워크플로 재작성**: 현행은 `SOURCE_SHA`·`EXPECTED_PR`·테스트 수 정확 일치(1,508 — HANDOFF 250·grep 1,470과 3값 혼재)가 특정 PR에 묶인 검증 전용이라 재사용 불가 → 태그 기반(`on: push: tags: v*` + Environment 승인, 빌드 대상=태그 커밋)으로 재작성, 검증 단계(analyze·test·`validate_release_env`·keystore·jarsigner·bundletool·내장 env·artifact·cleanup)는 이식, 테스트 수 핀은 제거하고 "실패 0·스킵 0"만.
- **계약 스냅샷 자동 대조**: 앱 `docs/APP_V16_SERVER_CONTRACT_SNAPSHOT.md` 같은 수동 스냅샷은 새 저장소에 복사하지 않고, 웹 `contracts:export` 산출물(카탈로그·grant)을 앱 CI가 읽어 "매니페스트의 모든 `schema.name`이 인벤토리에 존재하고 authenticated EXECUTE/SELECT가 있다"를 검증. 서버 표면을 바꾸는 작업 = 웹 pack PR → 앱 PR 순서 2건, 앱 PR 본문에 웹 pack version 명시.
- **e2e**: 실 운영 DB 대상 규칙(쓰기 2건·가역) 유지, CR·가입 시나리오는 e2e에 넣지 않는다(비가역 쓰기).

### 7.7 새 저장소 부트스트랩 전략 — 권고 B: 이력 보존 복제 후 코어 재구성

현행 사실: 네이티브 폴더는 git 추적 중(android 21 · ios 45 · web 7 파일 — HANDOFF "untracked"·README "S0 스캐폴드" 서술은 구식). Android `applicationId=com.ssambership.edu`, minSdk 24 · target/compile 36, AGP 9.0.1 · Kotlin 2.3.20 · JDK 17, `key.properties` 서명, Firebase 제거 상태. iOS 번들 `com.ssambership.app`, 배포 타깃 13.0, SwiftPM, `PrivacyInfo.xcprivacy`·`Info.plist`가 계약 테스트로 잠김. 버전 `1.0.0+19`. Flutter 핀 3.44.6. 스토어 실제 등재·업로드 이력 (확인 필요).

| 안 | 평가 |
|---|---|
| A 기존 저장소 장기 브랜치 | 이력·CI·서명 연속이지만 구 문서가 같은 트리에 남아 "정본 오독" 지뢰 지속 |
| **B 이력 보존 복제(`git clone --mirror`/import) 후 기본 브랜치에서 코어 재구성** | A의 장점 + 깨끗한 문서·이슈 공간, 네이티브·서명·CI·계약 테스트 재사용 100%. GitHub Environment secrets·Xcode Cloud 재등록 필요 |
| C `flutter create` + 모듈 이식 | 네이티브 설정·서명·CI·계약 테스트 재구축 비용 최대, 검증된 AGP/Kotlin/Flutter 조합 무효화, 초기 CI 전면 적색. 얻는 것은 템플릿 최신화 정도 |
| D 모노레포 | 앱 CI·서명 secrets가 웹 권한 모델과 섞임, "웹 구조 침범 금지" 정신과 충돌 |

권고 절차:
1. 이력 보존 복제, 구 저장소는 아카이브(README 상단 링크). 기본 브랜치 `main`(`flutter-ci.yml`의 `master` 트리거 갱신).
2. **첫 정리 커밋(코드 무변경)**: HANDOFF·README를 현행 사실로 재작성, `docs/APP_V16_*`·`CROSS_VERIFY_*`·`QA_*_2026-07`은 `docs/archive/`로(계약 테스트가 읽는 `docs/S3E_QUESTION_ROOM_SAFETY_CONTRACT.md`는 유지), `lib/core/push/HANDOFF.md`를 정본으로 승격, 참조 0인 `onboarding_screen.dart` 삭제.
3. **이식 순서**(단계마다 analyze·test 그린): ① 코어 — `core/di/app_scope` → `core/auth` 확장(`onboarding`·`OnboardingNeed`·status allowlist) → `core/config/feature_flags` → 공통 인프라 일반화(업로드 코어·리졸버·Realtime·RefreshBus·에러 매퍼·parse) → `app/` 재설계(라우트 spec·역할 탭 spec·`StatefulShellRoute`·`AppNavigator`) → 계약 테스트 신설. ② 기존 feature(서버 계약 변동 없음) — 질문방·연결노트·첨부/스캔/주석 → 알림(딥링크→경로) → 커뮤니티(`community_posts_v1`을 `api_app_v1`로, 삭제 RPC 통일은 결정 후) → 멘토 찾기·찜·무료질문 → 마이페이지·탈퇴·프로필 → IQ. 각 feature는 `fromId` 진입 추가·화면 내부 `currentRole` 제거. ③ 신설 feature(웹 pack 선행 필수) — 가입/온보딩(WebView 위임 target) → 멘토 콘솔(F7/F8/F13 `api_app_v1` twin) → 맞춤의뢰(테이블·RPC 신규 등록·게이트 해제) → 지원/공지 → 푸시(FCM) → 결제 경계 판정 후속(구독 해지 예약·환불 신청·CR 납품 수락).
4. 네이티브 계약 유지: 패키지·번들 그대로(번들 `.edu` 정렬은 첫 업로드 전에만 가능 — 오너 결정), `versionCode`는 `+19`에서 단조 증가(스토어 미등재여도 낮추지 않음), keystore·`key.properties` Environment secret 재등록, Firebase는 재도입 결정 시에만.
5. 버전 계약 3곳(`kPinnedPubspecVersion`·`build_version_test`·워크플로 `EXPECTED_VERSION*`) 동시 갱신을 `tool/bump_version.dart`로 묶는다.
6. **웹 저장소 선행 작업**(앱 ③ 이전 pack 적용·`contracts:verify` green): (a) `api_app_v1` 신설 wrapper 일괄(§6 총람) (b) bootstrap target 확장(`identity_onboarding`·`mentor_verification`, 역할 게이트, admin 불허, kinds/results/error codes, 계약 테스트) (c) 게이트 env의 서버 노출(`identity_gate_enabled`) (d) `mobile_app_version_policies` `store_url` 채움 → `min_supported_build` 상향 (e) Realtime publication에 CR 테이블(+IQ 확인) (f) 로컬 `supabase/config.toml [api].schemas`에 `api_web_v1`·`api_app_v1` (g) App Links/Universal Links 채택 시 well-known 파일 배포 (h) 앱 계약 v1.2 동기화(읽기 뷰 허용 명문화).

### 7.8 컴파일 타임 스위치·환경 — 단일 표 + 두 계층

현행: dart-define 3종(`IQ_CREATE_ENABLED`·`SUBS_MANAGE_LINK_ENABLED`·`PAYOUT_MANAGE_LINK_ENABLED`, 기본 false) + `WEB_BASE_URL`(기본 `https://ssambership.com`) + 컴파일 상수(`kInAppPaymentSteeringEnabled=false` 등)가 4파일에 분산. 릴리즈 계약 = **dart-define 무주입**(워크플로·Xcode Cloud·계약 테스트가 검사). `.env`는 에셋(부재 시 analyze/test 실패). 서버 원격값은 버전 정책 RPC 하나.

권고:
1. **`lib/core/config/feature_flags.dart` 단일 표** — `iqCreate`·`subsManageLink`·`payoutManageLink`·`crEnabled(CR_ENABLED)`·`pushEnabled`·`signupEnabled`·`identityOnboardingEnabled`·`mentorConsoleEnabled`·`shortformNativeCompose`·`webBaseUrl`·`devTools`. 각 항목에 `releaseDefault`를 선언하고 `flags_contract_test`가 "기본값 == releaseDefault"를 잠근다. **결제 인접 플래그(`subsManageLink`·`payoutManageLink`·`iqCreate`)는 서버 원격으로 절대 올리지 않는다**(심사 빌드와 동작이 갈리면 정책 위반).
2. **서버 원격 표(`RemoteConfig`)** — `get_mobile_app_version_policy` 확장 또는 `get_mobile_app_config(p_platform)` anon RPC 신설(웹 pack): `identity_gate_enabled`(필수)·`cr_enabled`·`push_enabled`·`maintenance_message`. 조회 실패는 기능별 fail-safe 기본(CR 숨김·게이트 "유도 없음"), 컴파일 플래그 OFF면 원격값 무시(AND 결합).
3. `.env`는 Supabase·Sentry 자격값 전용 유지 + `SUPABASE_ENV=local|production`(URL 문자열로 원격을 유추하는 `_isRemote` 대체). `.env` 부재 시 죽는 문제는 `tool/bootstrap_env.dart`로 표준화. `AppConfig`는 `Deps`로 주입되는 `AppEnvironment` 값 객체로.
4. `AppConstants.appVersion` 하드코딩 제거 → `package_info_plus` 단일 소스.


---

## 8. 구현 단계 (권고 로드맵)

전제: 웹 저장소 선행 작업(§6 Tier A + 계약 증보)이 각 단계의 앱 착수보다 앞선다. 규모는 1인 기준 S(≤1일)·M(2~4일)·L(1~2주)·XL(2주+).

| 단계 | 내용 | 산출 | 규모 |
|---|---|---|---|
| **0. 결정·계약** | §9 오너 결정 일괄 확정 → 앱 계약 v1.2 초안(CR 절·읽기 뷰 명문화·오류코드) → 웹 pack Tier A 작성·적용·`contracts:verify` | 결정 기록, 계약 문서, 마이그레이션 ~16본 | M(웹) |
| **1. 저장소·코어** | 이력 보존 복제 → 첫 정리 커밋(구 문서 아카이브) → `core/di`(`AppScope`/`Deps`) → `core/auth` 확장(`onboarding`·`OnboardingNeed`·status allowlist·`signUp`) → `core/config/feature_flags` + `RemoteConfig` → 공통 인프라 일반화(업로드 코어·리졸버·Realtime·RefreshBus·`RpcOutcome`·parse·`KeysetPaginator`) → `app/` 재설계(라우트 spec·역할 탭 spec·`StatefulShellRoute`·`AppNavigator`·`EntryGuard` 메타) → 계약 테스트 신설(layering·feature_registry·flags·bridge_targets·no_singleton) → 서명 워크플로 태그 기반 재작성 | 그린 CI의 빈 셸 + 코어 | L |
| **2. 기존 feature 이식** | 질문방·연결노트·첨부/스캔/주석 → 알림(딥링크→경로, kind 테이블) → 커뮤니티(`api_app_v1` 뷰 전환·`soft_delete_own_content` 통일) → 멘토 찾기·찜·무료질문 → 마이페이지·탈퇴·프로필 → IQ. 각 feature `fromId` 진입·`currentRole` 제거 | 기존 앱 기능 동등 | L |
| **3. 학생 채널 정합** | 오답 표시·topic·탭 분류·마이페이지 잔여·실패 표시 → 멘토찾기 필터/정렬/최근/카탈로그/cap 배지 → 리뷰 열람 → IQ direct 보드·transfer·확정 의미 → 구독 관리 7종 라벨 | §5.4 P1~P5 | L |
| **4. 계정·온보딩** | `AppSurfaceBridge` 일반화 → 회원가입 네이티브(학생/멘토·메타 20키·상태 기계·이메일 인증 분기) → 비밀번호 재설정 → 본인인증 WebView(`identity_onboarding`) → 학생증 RPC → 마케팅 동의 → 탈퇴 정합 | §5.3 단계 1~9 | L |
| **5. 멘토 콘솔** | 홈 KPI·cap·수익 차트 → 정산 요약·라인·계좌 조회 → 리뷰·답글 → 프로필 편집·아바타 → (결정 후) 가격 설정·계좌 등록·서류 제출·학적 변경·활동 관리 → 분쟁 조회 | §5.2 A0~A9 | L |
| **6. 커뮤니티·공지·알림·지원 정합** | 소프트 삭제 통일·답글 2-depth·임시저장·정렬/keyset·숏폼 카테고리/썸네일 → 공지 → 알림 kind/딥링크 보강 → 내 신고 내역·분쟁 목록 | §5.5 P1~P4 | M |
| **7. 맞춤의뢰** | 데이터 계층(모델 12·레포·첨부·Realtime·플래그) → 화면 15개(주문방 XL) → 알림 배선·게이트 해제 → 출시 동시 조치(웹 게이트 ON·`CR_ENABLED`·A8·버전 정책) | §5.1 Phase 2~4 | XL |
| **8. 결정 종속 후속** | 구독 해지 예약(C1)·환불 신청(C2)·CR 결제 wrapper(C3)·IQ 생성(C4)·숏폼 네이티브(C5)·OS 푸시 재도입(Data Safety·활성 순서)·관리자 WebView(MFA 후) | 각 결정별 | M~XL |
| **9. 출시** | `mobile_app_version_policies` `store_url` 채움 → `min_supported_build` 상향(구 앱 차단) → 스토어 정책 QA(정책 §7 체크리스트: 결제 유도 문구 0·웹 URL 전수·잔액 0 계정 탐색) → Data Safety·PrivacyInfo 재제출 | 스토어 빌드 | S~M |

병행 가능: 3·5·6은 1·2 이후 서로 독립. 7은 6의 알림 kind 테이블과 A8에 의존. 4는 A14(웹 bootstrap 확장)에 의존.

---

## 9. 오너 결정 총람

각 도메인 문서의 결정 항목을 주제별로 묶었다. 권고는 검토 결과이며 최종 결정은 오너 몫이다.

### 9.1 결제 경계(정책 정본 개정이 따르는 항목)
| # | 결정 | 권고 |
|---|---|---|
| P1 | 구독 해지 예약 앱 포함(C1) | 조건부 포함(결제 중단 행위, 가격·재유도 문구 0). 예약 취소(재개)는 웹 위임 |
| P2 | 구독 잔여 환불 신청 앱 포함(C2) | 조건부 포함(구매 아님·캐시 차감 0). 정책 문서 §3 "원칙 ❌" 행 개정 선행. 신청 성공 즉시 질문 잠금 고지 |
| P3 | IQ 생성(캐시 hold) 앱 포함(C4) | **웹 위임 유지**. Play Billing 해당 여부·Apple 3.1.3(b) 법무 확인 후 재판정 |
| P4 | IQ release·refund 앱 허용 유지 | 유지(에스크로 확정·지갑 환원, 앱 이미 호출) |
| P5 | CR 선정(hold)·수락(지급)·취소(환불) 앱 wrapper(C3) | **1차 웹 위임**. 웹 선정/주문방 딥링크는 플래그 기본 OFF |
| P6 | 정산 계좌 등록(F13) 앱 포함 | 조건부 포함(지급 수취 계좌, 소비자 결제 아님) — 플랫폼 문서는 웹 위임 유지 의견 → 오너 판단 |
| P7 | 가격 설정(F8·IQ 단가) 앱 포함 | 포함(멘토 전용 화면, 학생 가격표·구매 CTA 분리) |
| P8 | 가격 표시·가격대 필터·가격 정렬(학생) | 비표시·제외 유지 |
| P9 | 자금 인접 RPC 매니페스트 처리 | 결정 결과대로 허용 집합 ↔ `kForbiddenWords` 이동 |

### 9.2 범위·정책
| # | 결정 | 권고 |
|---|---|---|
| R1 | 맞춤의뢰 정식 오픈 — 앱 출시 시 웹 게이트 동시 ON | 동시 ON(백엔드·알림 이미 라이브, 웹 멘토 동선 단절 방지) |
| R2 | 관리자 콘솔 앱 포함 | **제외 유지**(admin→blocked). WebView 위임은 MFA(PR-12b) 완료 후 재검토 |
| R3 | 회원가입 앱 네이티브 | 네이티브(`auth.signUp` + 메타 20키, 서버 객체 신설 0 — 학생증 RPC만) |
| R4 | 본인인증·보호자 동의 | WebView 위임(bootstrap `identity_onboarding` + 학생 허용) |
| R5 | 이메일 인증(Confirm email) 운영값 | 확인 후 가입 직후 흐름 확정 |
| R6 | IDENTITY_GATE 앱 강제 | 1차 비강제(배지·안내) → 운영 ON 확정 후 `RemoteConfig` 기반 강제. DB 게이트 비권고 |
| R7 | 소셜 로그인 | 미도입(범위 밖) |
| R8 | 민감 서류(학생증·학교·학적) 앱 업로드 — 2026-07 "웹 전용" 번복 | 포함(제출·상태만, 원본 열람 제외, iOS 수집 유형 갱신) |
| R9 | 멘토 활동 관리 3종 앱 포함(B2) | 포함(자금 이동 없음), 무단 이탈 제외, 웹 액션도 같은 impl |
| R10 | 숏폼 작성 | 1차 WebView 유지 → 2차 `api_app_v1.shortform_post_create/update`(C5). RLS 직접 네이티브는 비권고 |
| R11 | OS 푸시(FCM) 재도입 | 재도입(서버 GRANT 적용 증적 있음). 조건: Data Safety 재제출·iOS DeviceID 계약 재판정·처리위탁 문안·활성 순서 |
| R12 | 커뮤니티 본인 삭제 통일 | 앱 4종 `soft_delete_own_content`, 구 RPC 회수는 버전 게이트와 동기 |
| R13 | 숏폼 본인 삭제 UI(웹 parity 밖) | 앱 추가(저비용), 웹도 동시 권고 |
| R14 | 신고 사유 정본 어휘 | 영문 코드 집합으로 웹 정합(멱등 키 일관성) |
| R15 | 공지 팝업 방식 | 홈 상단 배너(닫기 기기 로컬) |
| R16 | 분쟁 목록/상세 앱 포함 | CR 포함 결정에 종속(포함 시 읽기 전용·새 객체 0) |
| R17 | 고객센터 FAQ | 웹 `/support?src=app`에서 결제 링크 비노출(웹 변경 1건) |
| R18 | 약관·개인정보 | 외부 브라우저 유지(정적 TSX) |
| R19 | 댓글 연락처 마스킹 | 서버 트리거(B8) |
| R20 | `sfv_public_read` 축소(B10) | 축소 |
| R21 | IQ 답변 확정 의미 | RPC 자동 전이 정본, 웹 명시 확정은 `answer_individual_question`로 수렴 |
| R22 | 연결노트 의미·구독 가드 | append 유지 + B5 RPC |
| R23 | 리뷰 검증 위치 | RPC(B4) |
| R24 | 마케팅 동의 토글 앱 노출 | 노출(웹은 UI 없음 — 앱이 앞섬) |
| R25 | 탈퇴 사전조건 DB 강제 | 조회 RPC만(A13), 요청 RPC 내 강제는 구 앱 회귀 위험 |

### 9.3 플랫폼·저장소
| # | 결정 | 권고 |
|---|---|---|
| T1 | 새 저장소 방식 | 이력 보존 복제(B) — `flutter create`는 검증된 네이티브·서명·CI·계약 테스트 무효화 |
| T2 | 상태관리 | 수동 `AppScope`/`Deps` DI(B), Riverpod는 조건 충족 시 |
| T3 | 딥링크 스킴 | 웹 도메인 App Links/Universal Links(경로를 웹과 동일화, well-known 파일 웹 배포) |
| T4 | 읽기 뷰 `api_web_v1` 교차 사용 | 앱 계약에 명문화, 쓰기·self RPC는 `api_app_v1`, `community_posts_v1`만 앱 뷰로 전환 |
| T5 | iOS 번들 ID `com.ssambership.app` 유지 vs `.edu` | 첫 업로드 전이면 `.edu` 정렬. **첫 업로드 후 변경 불가**(업로드 이력 확인 필요) |
| T6 | 서버 원격 플래그 RPC(A15) | 신설(`identity_gate_enabled` 필수) |
| T7 | 로컬 `config.toml` 노출 스키마 확장(A16) | 승인 |
| T8 | `connection-note-ink` 버킷 상수·연결노트 직접 CRUD | 버킷 상수 제거, CRUD는 B5 결정과 함께 |
| T9 | 비밀번호 재설정 딥링크 | 웹 완료 유지(앱 스킴 도입은 T3와 함께) |
| T10 | 디렉터리 서버측 검색 RPC 도입 시점 | 멘토 1,000 미만이면 보류 |

---

## 10. 리스크·지뢰 총람

### 10.1 구조·계약
1. **운영 DB 오인** — `ssambership-staging`(`lbeqxarxothkmzqvpudy`)이 곧 운영. 로컬 스택이 `api_*` 스키마를 노출하지 않아 개발이 운영 DB로 몰린다(A16 선행).
2. **동명 함수 3스키마 공존**(`qna_create_question_thread`·`community_post_*`·`ensure_free_question_room`) — `.schema()` 누락 시 PGRST202 또는 봉투 스타일 변경. 매니페스트 `schema.name` 화 전까지 미탐지.
3. **봉투 2스타일 혼재 확대** — DB-3 `soft_delete_own_content`는 void+raise. `RpcOutcome` 정규화 없이 매퍼가 도메인별로 늘면 5벌→10벌.
4. **게이트 불일치** — `IDENTITY_GATE_ENABLED`는 웹 서버 env. 앱 직접 쓰기 경로(CR 지원 등)는 게이트 밖 → 정책 구멍. DB 게이트는 웹 설계 원칙상 금지(전제는 "앱 재배포 없음"이었음 — 새 앱이면 재검토 가능).
5. **status allowlist 차이** — 앱은 미지 status를 active 취급, 웹 앱 표면은 거부 → WebView 진입에서만 `account_blocked`.
6. **역방향 import 4건**(`core→app/features`, `shared→features`)을 먼저 끊지 않으면 "코어 먼저 이식"이 컴파일에서 막힘.
7. **IndexedStack 상주 + 브랜치 증가** — Realtime 채널·재조회 팬아웃 회귀(N12/N13 재발). "보이는 브랜치만 구독" 규약 필수.
8. **계약 거버넌스** — 웹 계약 v1.1이 CR을 "유지 영역"으로 고정. 신규 객체는 계약 증보 없이는 `contracts:verify`·감사 문서와 어긋난다.
9. **구식 문서 지뢰** — HANDOFF(도메인·FCM·250개 테스트·untracked)·README(S0)·`APP_V16_*`(RPC명·DB-1~3 이전). 새 저장소에 복사하면 과거 앱 저장소 SQL 4건 사고와 동형의 계약 오독 재발.

### 10.2 도메인
10. CR `cro_update` 광범위 UPDATE 정책 라이브 — 잠금(A9) 전 출시 금지. A8과 앱 게이트 해제 릴리스가 어긋나면 배지≠목록.
11. CR 테이블 Realtime publication 미포함(A7 전까지 무음). 학생 납품 서명 URL은 완료 전 DB 거부 → 모델에서 `storage_path` 제거. 의뢰 첨부 웹 50MB vs 버킷 20 MiB.
12. F7 9필드 전면 교체 ↔ 관리자 학적 승인(service_role `university_name`) 경합 → 승인값 롤백 + 192 트리거로 학교 인증 pending 회귀(B1 낙관적 잠금).
13. 가격 밴드·cap 가중치의 앱 사본 금지(DB·TS 이중 정본에 3번째 추가 위험).
14. 가입 트리거 지연·`app_role` 오타 → role 불명 blocked 또는 학생 폴백. NICE 표준창 외부 호스트 allowlist (확인 필요). Confirm email ON이면 가입 직후 학생증 업로드 불가. 비밀번호 최소 길이 서버 6 vs 웹 8. `consent_version` 불일치.
15. `soft_delete_own_content` 반환 void — strict 봉투 파서에 넣으면 항상 실패 오판. 구 RPC 회수 타이밍은 버전 게이트 최소 빌드 상향과 동기.
16. 푸시 재도입 — 활성 순서(워커 플래그 → `push_transport_enabled` → live) 위반 시 outbox 폭주; FCM data 6키로는 상세 딥링크 불가(`notification_id` 재조회); `'firebase' 0건`·iOS DeviceID 금지 집합이 CI를 막음(의도된 계약 갱신 동반).
17. `sfv_public_read` 버킷 전체 SELECT — 네이티브 업로드 시 표면 확대. `is_mentor()` 승인 미검사.
18. 신고 어휘 웹(한글)/앱(영문) 불일치 + 멱등 키(reason 포함) → 교차 중복 접수.
19. 리뷰 작성자 `users` RLS 0행 → 마스킹 폴백. `check_review_eligibility` EXECUTE 여부·`subscription_billing_events` 정책 (확인 필요).
20. 환불 신청 성공 즉시 해당 구독 질문 작성 잠금(`SUBSCRIPTION_REFUND_PENDING`). 환불 예상액 웹 TS/서버 SQL 이중 구현 시 금액 불일치.

### 10.3 출시
21. 새 앱 출시 시 구 앱 차단 수단은 `min_supported_build` 상향 하나 — `store_url` 선행 필수(실측 값 확인 필요).
22. iOS PrivacyInfo 금지 유형(`Name` 등) ↔ 가입·본인인증·학생증·문서 업로드 수집 표면 충돌 — 계약 테스트·매니페스트·Data Safety 동시 갱신.
23. 서명 워크플로의 `SOURCE_SHA`·`EXPECTED_PR`·테스트 수 1,508 정확 일치 핀 — 복사 즉시 실패(태그 기반 재작성).
24. `register_device_token` GRANT 상태 문서 불일치(헤더 "미적용" vs PUSH-APPLY 증적) — 착수 전 원장 대조.
25. 웹 `/support` 외부 브라우저에 `/wallet/charge`·`/subscribe` 링크 노출 — 심사 회색지대(R17).

---

## 11. 확인 필요 항목 (코드로 판정하지 못한 것)

| # | 항목 | 확인 방법 |
|---|---|---|
| 1 | Data API Exposed schemas 실제 목록(`api_web_v1`·`api_app_v1` 노출) | Supabase 대시보드 / Management API |
| 2 | Realtime publication에 IQ 3테이블 포함 여부 | `select * from pg_publication_tables where pubname='supabase_realtime'` |
| 3 | `register_device_token` authenticated EXECUTE 라이브 상태 | `routine_privileges` 실측(PUSH-APPLY.md 증적 대조) |
| 4 | `mobile_app_version_policies` 현재 행(min/latest/store_url) | service_role 조회 |
| 5 | 스토어 실제 등재·업로드 이력(Android `com.ssambership.edu`, iOS 번들) | Play Console / App Store Connect |
| 6 | Supabase Auth Confirm email 운영값 | Auth 설정 |
| 7 | `IDENTITY_GATE_ENABLED` 운영값 | 웹 배포 env |
| 8 | `check_review_eligibility` authenticated EXECUTE | `has_function_privilege` |
| 9 | `subscription_billing_events` 당사자 SELECT 정책 | `pg_policies` |
| 10 | `school_tier_catalog`·`major_category_catalog` authenticated SELECT GRANT | `role_table_grants` |
| 11 | `mentor_activity_events` authenticated SELECT GRANT 잔존 여부 | 동일 |
| 12 | Storage 업로드 시 `owner_id` 채움 여부(앱 세션 클라이언트) | 실업로드 후 `storage.objects.owner_id` |
| 13 | NICE 표준창 외부 호스트(WebView allowlist) | NICE 문서·웹 코드 상수 |
| 14 | `/api/identity/*`의 쿠키 회전이 앱 표면 HttpOnly 속성을 내리는지 | 웹 코드 검토 |
| 15 | 앱 IQ wrapper(`create_individual_question_as_student`)의 `expires_at` 설정 여부 | SQL 092 본문 |
| 16 | `is_open_for_subscriptions`가 학생 CTA에 반영되는지 | 웹 `MentorDetailCTASection` props |
| 17 | `notification_event_group`의 CR 타입 그룹(설정 라벨 `'order'`) | SQL 152 |
| 18 | `mentor_directory_v1.school_verified` 산출 조건이 192(pending 잠정) 이후 바뀌었는지 | 뷰 정의 |
| 19 | `comments_write_guard`가 본문 INSERT를 통과시키는지(실환경) | 로컬/스테이징 테스트 |
| 20 | Apple 3.1.1/3.1.3(b) 해석(기충전 캐시 앱 내 소비·다중플랫폼 IAP 병행) | 법무 |
| 21 | 앱 `HEIC` 첨부·숏폼 WebView 프레임 추출 동작 | 실기기 |
| 22 | CR 운영 데이터(주문·글 건수 — 분쟁 0·정산 0은 확인) | service_role 조회 |

---

## 12. 검증 메모

- 1단계 리포트 8종은 서로 독립적으로 코드·SQL을 읽었고, 2단계 설계는 결정적 주장(RPC GRANT·RLS 정책·트랜잭션 결합·트리거)을 마이그레이션 SQL로 재확인했다. 교차 대조에서 정정된 항목: (1) `register_device_token` GRANT — 마이그레이션 헤더 "라이브 미적용"과 달리 `docs/sprint-push/PUSH-APPLY.md`가 2026-08-27 적용(원장 93→94)을 기록 → 설계는 적용 완료 전제, 착수 전 원장 재확인(§11 #3). (2) `favorites` 테이블명 — SQL 198 헤더의 `mentor_favorites`는 주석 오기, 정본 `public.favorites`(034), 앱도 `favorites`. (3) 웹 `CLAUDE.md` 리뷰 조건 "동일 멘토 2회 연속 결제 성공 후"는 SQL 066 구 기준, 현행 정본은 SQL 170(구독 `active/expired/cancel_scheduled` OR IQ `answered/released`). (4) 앱 테스트 수 — HANDOFF 250개·CI 핀 1,508·grep 약 1,470 3값 혼재 → 정확 일치 핀 제거 권고. (5) 웹 Flutter 핀 3.44.6(CI·Xcode Cloud·계약 테스트) vs HANDOFF 3.44.4(구식).
- 학생 채널 정합 설계는 에이전트 반복 타임아웃으로 종합 단계에서 직접 작성했다. 근거는 1단계 리포트의 파일:행을 그대로 옮겼고 새 주장은 추가하지 않았다.
- 라이브 DB 카탈로그·플랫폼 설정·스토어 콘솔은 조회하지 않았다. §11의 22항목은 착수 전 실측이 필요하다.

---

## 부록. 문서 구성

| 경로 | 내용 |
|---|---|
| `docs/APP_REBUILD_REVIEW_2026-09.md` | 이 문서(종합) |
| `docs/app-rebuild-review-2026-09/phase1/app_architecture.md` | 기존 앱 아키텍처·패턴·확장 포인트(§1~§9) |
| `docs/app-rebuild-review-2026-09/phase1/app_features.md` | 기존 앱 기능 인벤토리·아웃바운드 표면·의도적 제외·이식 분류 |
| `docs/app-rebuild-review-2026-09/phase1/web_student_channels.md` | 웹 학생 채널(질문방·IQ·멘토찾기·구독·마이페이지) 서버 표면 |
| `docs/app-rebuild-review-2026-09/phase1/web_custom_request.md` | 웹 맞춤의뢰 수명주기·RLS·버킷·결제 접촉 |
| `docs/app-rebuild-review-2026-09/phase1/web_mentor_console.md` | 웹 멘토 콘솔 서버 표면·RPC 권한 |
| `docs/app-rebuild-review-2026-09/phase1/web_community_notifications_support.md` | 웹 커뮤니티·공지·알림·지원 + 앱 대조 갭 |
| `docs/app-rebuild-review-2026-09/phase1/web_account_identity_admin.md` | 웹 계정·본인인증·탈퇴·관리자 콘솔 인벤토리 |
| `docs/app-rebuild-review-2026-09/phase1/web_db_surface_payment_boundary.md` | DB 스키마 지도·RLS 매트릭스·Storage·결제 경계 판정표·DB 변경 규율·신규 객체 후보 |
| `docs/app-rebuild-review-2026-09/design/custom_request.md` | 맞춤의뢰 설계 |
| `docs/app-rebuild-review-2026-09/design/mentor_console.md` | 멘토 콘솔 설계 |
| `docs/app-rebuild-review-2026-09/design/account_identity_admin.md` | 계정·본인인증·관리자 설계 |
| `docs/app-rebuild-review-2026-09/design/student_channels_parity.md` | 학생 채널 정합 설계 |
| `docs/app-rebuild-review-2026-09/design/community_notifications_support.md` | 커뮤니티·알림·지원 정합 설계 |
| `docs/app-rebuild-review-2026-09/design/platform_common.md` | 플랫폼 공통·저장소 부트스트랩 설계 |

> 문서 내 경로 표기: `app:` 접두 또는 `lib/...`는 앱 저장소, `web:` 접두 또는 `supabase/...`·`app/(student)/...`는 웹 저장소. 1단계·설계 문서가 서로를 가리키는 경로는 이 폴더 기준 상대 경로(`../phase1/…`, `../design/…`)로 정리했다.
