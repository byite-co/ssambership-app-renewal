# v16 실기기 통합 QA 체크리스트 (Android/iOS)

> 상태: **READY_NOT_EXECUTED** — 이 실행 환경에는 Android SDK/emulator(네트워크 정책이
> dl.google.com 차단)·macOS/Xcode 가 없다. 코드·테스트는 준비 완료,
> 아래 절차는 기기/맥이 갖춰진 환경에서 그대로 실행한다. PASS 위조 금지.
>
> ★ **App-F0 이후 이 빌드에는 OS 푸시(FCM/APNs)가 없다.** Firebase SDK·디바이스 토큰
> 등록·OS 알림 런타임 권한 요청 경로가 코드에 존재하지 않는다(회귀 잠금
> `test/push/firebase_free_test.dart`). 따라서 아래 알림 항목은 **동작 확인이 아니라
> '부재 확인 + 인앱 대체 경로 확인'** 이다 — 권한 팝업이 뜨지 않고 `device_tokens` 행이
> 생기지 않는 것이 **PASS** 다. 앱이 제공하는 알림 표면은 **앱 내 알림함**뿐이다.
> 상세: `lib/core/push/HANDOFF.md`.

## 0. 사전 조건

푸시 SDK 설정은 **하지 않는다**. 아래 4줄은 '배치했는지'가 아니라 **'없는지'** 를 확인하는 항목이다
(예전 회차에서 남은 파일이 있으면 지우고 시작한다 — 있으면 회귀 잠금 테스트가 깨진다).

- [ ] `android/app/google-services.json` **없음** (배치하지 않는다)
- [ ] `ios/Runner/GoogleService-Info.plist` **없음** (배치하지 않는다)
- [ ] `android/app/build.gradle.kts` plugins 에 `com.google.gms.google-services` **없음** (추가하지 않는다)
- [ ] (iOS) Xcode Push Notifications capability·`aps-environment` entitlement·APNs 키 **모두 없음** (등록하지 않는다)
- [ ] (iOS) `cd ios && pod install`
- [ ] `.env` 에 staging SUPABASE_URL/ANON_KEY (운영 금지 — QA 는 staging)
- 절차 상세: `lib/core/push/HANDOFF.md`

## 1. Android (기기 또는 emulator, Android 13+)

### 알림 — OS 푸시 미도입 확인(부재) + 인앱 알림함 동작

**A. 부재 확인 — 아래는 "일어나지 않아야" PASS 다**

- [ ] 앱 최초 실행 → OS 알림 권한 팝업이 **뜨지 않는다**
- [ ] 첫 로그인 → OS 알림 권한 팝업이 **뜨지 않는다**
- [ ] 로그인 · 로그아웃 · 재로그인 어느 시점에도 **`device_tokens` 신규 행이 생기지 않는다**
      · 판정 쿼리는 `user_id = <QA 계정 uid>` 로 **한정**한다(전역 행 수로 판정 금지 —
        다른 계정의 기존 행이 남아 있는 것은 이번 판정 대상이 **아니다**)
      · 예: `select count(*) from device_tokens where user_id = '<QA uid>';` → QA 시작 전후 **동일**
- [ ] OS 권한 요청 표면 **0건** · 시스템 설정 화면으로 보내는 이동 **0건** · device token 등록 표면 **0건**
- [ ] 백그라운드/종료 상태에서 시스템 알림 트레이에 앱 알림이 **표시되지 않는다**
      (서버가 이벤트를 만들어도 이 빌드는 OS 로 배달하지 않는다 — 알림함에만 쌓인다)
- [ ] 위 전 구간 **크래시 0**

**B. 인앱 알림함 — 아래는 "정상 동작해야" PASS 다**

- [ ] 알림함 탭: 목록 로드(본인 알림만) · 빈 상태 문구 정상
- [ ] 읽음 처리: 항목 읽음 → 즉시 반영 · '모두 읽음' → 미읽음 배지 0
- [ ] 페이지네이션: 하단 도달 → 다음 페이지(20건 단위) 이어 로드 — **중복/누락 0**
      (키셋 커서 방식 — 스크롤 중 새 알림이 들어와도 경계 행이 겹치거나 빠지지 않아야 한다)
- [ ] 항목 탭 → 정본 17종 라우팅이 정상 목적지로 이동한다
      · `question_answered` → **질문방 탭**
      · `individual_question_*` 6종(assigned/claimed/answered/message/released/expired_refunded) → **개별질문 탭**
      · 구독·멘토 8종(renewal_upcoming/expired/renewal_succeeded/renewal_failed_insufficient_cash,
        mentor_subscription_price_changed/termination_notice/termination_refund/pause_notice) → **마이페이지**
      · 맞춤의뢰 2종(`new_order_message`/`new_application`) → CR 게이트 OFF 라 **목록에 노출되지 않는다**
        (DB 쿼리 단계 exact 제외 — 안 보이는 것이 정상)
- [ ] 알 수 없는 타입의 알림 → **크래시 0** · 목록에 일반 알림으로 표시 · **이동 없음**
- [ ] 어떤 알림에서도 **외부 URL·커스텀 스킴이 실행되지 않는다**
      (서버 payload 의 link/url 은 파싱 단계에서 버려진다 — 브라우저·외부 앱 전환 0건)
- [ ] 로그인 계정 전환(A 로그아웃 → B 로그인) → **B 화면에 A 의 알림이 남지 않는다**
      · 대기 중이던 A 의 이동도 실행되지 않는다

**C. 설정 화면 알림 토글 — 이것은 OS 권한이 아니라 '인앱 알림 설정'이다 (오판 금지)**

마이페이지 → 설정의 `알림 받기` 마스터 토글과 그룹별 토글은 **서버 정본 인앱 알림 설정**
(`notification_settings.push_enabled` / `notification_settings.groups`)을 읽고 쓴다.
**OS 푸시 권한이나 기기 토큰 설정이 아니다.** 이 빌드에서 OS 권한 포트는
`DisabledPushPermission` 으로 고정되어 조회·요청이 모두 no-op 이며, '기기 알림 권한이 꺼져 있어요'
안내는 `denied` 상태에서만 뜨는데 **이 빌드에서는 `denied` 가 발생하지 않는다**(안 뜨는 것이 정상).

- [ ] `알림 받기` 마스터 토글 ON/OFF → 저장 후 재진입 시 값 유지(`push_enabled` 반영)
- [ ] 그룹별 토글 5종(질문방 알림 · 개별질문 알림 · 구독·결제 알림 · 환불 알림 · 기타 알림)
      각각 ON/OFF → 저장 후 재진입 시 값 유지(`groups` 반영)
- [ ] **마스터 OFF → 그룹 토글이 잠긴다**(조작 불가) · 마스터 ON 으로 되돌리면 다시 조작 가능
- [ ] 저장 실패 유도(비행기 모드) → 토글이 **원복**되고 재시도 안내 스낵바 노출 → 복구 후 재시도 성공
- [ ] 로드 실패 유도(비행기 모드로 설정 진입) → 기본값(전부 ON)으로 **위장하지 않고** '다시 시도' 노출

> 판정 주의(테스터·검수자 공통):
> - 이 토글이 **동작하는 것이 정상**이다. OS 푸시가 없다는 이유로 결함 처리하지 말 것.
> - 이 토글을 "OS 푸시 권한 설정"·"기기 토큰 설정"으로 **설명하지 말 것**.
> - 이 토글을 **숨기거나 비활성화하라고 요구하지 말 것** — 인앱 알림 설정은 이번 출시 범위다.

### 기능
- [ ] 숏폼 상세: video_player 재생/일시정지/dispose(뒤로가기 후 오디오 잔류 0)
- [ ] 질문방 이미지 첨부: 촬영/갤러리/파일 → 5MB 초과 자동 축소 → 업로드 → 첨부 표시
- [ ] 첨부 등록 실패 유도(비행기 모드 전환) → 실패 안내 + pending 미리보기 유지 → 재시도 성공
- [ ] Storage 에 고아 객체 없음(등록 실패분 보상 삭제 확인)
- [ ] 첨부 파일 열기(서명 URL) → 외부 앱 → 1시간 경과 후 재열기(재서명)
- [ ] 웹브리지: 구독/약관/지원 → https://ssambership.com 만 열림, 타 도메인 차단 확인
- [ ] 계정탈퇴 화면: (grant 배포 전) '웹에서 진행' 폴백 노출 확인
- [ ] 알림 목록·모두 읽음·인앱 알림 설정 토글 → 위 §1-B·§1-C 에서 판정(중복 기재 방지)

## 2. iOS (macOS/Xcode 필요)

- [ ] `pod install` 성공(video_player 등 — **Firebase pods 는 포함되지 않는다**.
      `Podfile.lock` 에 `Firebase*`/`FirebaseMessaging` 항목이 **없어야** 정상)
- [ ] Debug 빌드 + 실기기 설치
- [ ] 앱 최초 실행·첫 로그인 → **알림 권한 요청 팝업이 뜨지 않는다** ·
      **APNs 토큰 발급 없음** · **`device_tokens` 신규 행 없음**(`user_id = QA 계정` 한정 판정)
- [ ] 시스템 알림 트레이에 앱 알림 **미표시**(OS 배달 경로 없음) · 크래시 0
- [ ] 인앱 알림함(목록·읽음·모두 읽음·페이지네이션·17종 라우팅·unknown 이동 없음·외부 URL 0)
      — Android §1-B 와 동일 시나리오
- [ ] 설정 화면 `알림 받기`·그룹별 토글 = **인앱 알림 설정**(`notification_settings`) 동작
      — Android §1-C 와 동일 시나리오(OS 권한으로 오판 금지)
- [ ] video_player(AVFoundation) 재생
- [ ] image_picker 촬영/앨범 권한 문구(한글) 확인
- [ ] 첨부 업로드/서명 URL/웹브리지 — Android 와 동일 시나리오
- [ ] 계정 전환 시 이전 계정 알림 잔존 0 — Android 와 동일 시나리오

## 3. 회귀(양 플랫폼 공통, staging 데이터)

- [ ] 질문 생성 → 주간 사용량 감소 · 한도 소진 시 차단 문구
- [ ] 멘토 첫 답변 → 학생 **앱 내 알림함**에 항목 생성(OS 알림 아님) + 상태칩 '진행 중'
- [ ] 학생 확인 → '답변 완료' → 이후 메시지 전송 시 THREAD_LOCKED 안내
- [ ] 오답 표시/해제 토글
- [ ] IQ 취소(escrowed) → 지갑 잔액 복원(마이페이지 캐시 확인)
- [ ] IQ answered 상태에서 취소 버튼 미노출
