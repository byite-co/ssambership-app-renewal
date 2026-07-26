# 알림 — 인앱 알림함 전용 (상태: OS 푸시 미도입 / App-F0)

이 디렉터리(`lib/core/push/`)에는 **OS 푸시 구현이 없다**. App-F0 에서
Firebase/FCM SDK·초기화·디바이스 토큰·OS 알림 권한 요청을 전부 제거했다.

> 발송은 언제나 서버 outbox worker 단독이다(`record_domain_notification` →
> `notification_outbox` → deliveries). 클라이언트 발송 경로는 만들지 않는다
> (과거 `push_trigger.dart`/`edge_function_push_sender.dart` 는 2026-07-21 삭제).

## 지금 있는 것

| 파일 | 역할 |
|---|---|
| `push_payload.dart` | 알림 payload 파싱 — `type` 은 정본 17종(`notification_types.dart`) 정확 일치, id(room/thread/question) + dedup 키(notification_id/event_key). **link/url 등 외부 경로는 버린다.** 순수 로직이라 OS 푸시 없이도 유효하다. |
| `push_ports.dart` | 설정 화면이 참조하는 최소 권한 추상(`PushPermissionPort`/`PushPermissionStatus`) + 유일한 구현 `DisabledPushPermission`(조회·요청 모두 no-op). |

## 제거된 것 (App-F0)

- `firebase_core` / `firebase_messaging` pubspec 의존성
- `firebase_push_gateway.dart` — `Firebase.initializeApp` · `FirebaseMessaging` ·
  `@pragma('vm:entry-point')` 백그라운드 핸들러 · `FirebasePushPermission`
- `device_token_registrar.dart` — `register_device_token` RPC 등록/철회
- `push_service.dart` — 토큰 수명주기 오케스트레이션(로그인·회전·로그아웃 철회)
- `main.dart` 의 `PushService.initialize()` 호출
- `AuthService` 의 토큰 등록·철회 배선(`performSignOut` 의 revoke 단계 포함)
- Android 알림 런타임 권한 선언

## 유지되는 것 — 앱 내 알림함

OS 푸시와 무관하게 **서버 `notifications` 조회·읽음·페이지네이션·17종 라우팅은
그대로 동작한다**. 알림함은 인앱 데이터이지 OS 알림이 아니다.

- 목록/읽음/페이지네이션: `lib/features/notifications/`
- 탭 이동 판정(순수): `lib/core/deeplink/notification_deep_link_controller.dart`
- 배선: `lib/core/deeplink/deep_link_service.dart` — `initialize()` 에 payload
  스트림을 주지 않으면 구독 0개다. **프로덕션은 생산자를 붙이지 않는다**(OS 푸시가
  없어 알림 '탭' 이벤트 자체가 발생하지 않는다). 스트림 주입은 테스트 전용 경계다.
- 허용 목적지는 `notificationDestinationOf` 의 탭뿐 — payload 로 URL/외부 scheme 을
  실행하지 않는다.

## 지뢰(하지 말 것)

- 앱에서 푸시 **발송** 경로 복원 금지(위 원칙).
- 푸시 SDK 설정 파일(`google-services.json`/`GoogleService-Info.plist`)·entitlements
  **날조·커밋 금지**. `.gitignore` 항목을 유지한다.
- UI 가 OS 푸시 수신을 **약속하지 말 것** — 권한 요청 경로가 없으므로
  `PushPermissionStatus.granted` 는 이 빌드에서 발생하지 않는다.
- `PushPermissionPort`/`PushPermissionStatus` 시그니처 변경 금지(설정 라인이 import).

## 재도입한다면

OS 푸시를 다시 넣는 것은 **되돌리기가 아니라 새 도입**이다. 최소한 다음이 함께
와야 하고, 그 전에는 UI 가 푸시 수신을 약속해서는 안 된다.

1. 푸시 SDK 의존성 + 플랫폼 설정 파일(저장소에 커밋하지 않는다)
2. 게이트웨이·토큰 등록 구현 + 서버 `device_tokens` 계약 재확인
   (등록 RPC `register_device_token`, 철회는 본인 행 직접 UPDATE — `revoke_device_token`
   은 authenticated EXECUTE 권한이 없다)
3. Android 알림 런타임 권한 선언 + 요청 경로
4. iOS 푸시 entitlement / APNs 키
5. `docs/DATA_SAFETY_FORM.md` 의 '기기 또는 기타 ID' 행 재작성(수집 = 예)
6. 회귀 잠금 테스트 `test/push/firebase_free_test.dart` 갱신 또는 대체

## 테스트

- `test/push/push_payload_test.dart` — 정본 17종 매핑·외부 URL 무시·형 안전(유지)
- `test/push/firebase_free_test.dart` — App-F0 회귀 잠금(의존성·파일·매니페스트·포트)
- `test/deeplink/` — 목적지 매핑·dedup·pending·계정 전환·배선(스트림 주입)
