# v16 앱 세션 2 검증 기록 (2026-07-21)

> 범위: 세션 1 잔여 보정 3건 + P1-11/P2-15~P2-18 알림·FCM·설정·딥링크 전 범위.
> 시작 HEAD `5150c9c` → 최종 HEAD는 PR #33 참조. 계약 정본:
> `docs/APP_V16_SERVER_CONTRACT_SNAPSHOT.md` §4.1(세션 2 재조회분 포함).

## 1. 검증 결과 요약

| 항목 | 결과 |
|---|---|
| `flutter analyze` | **info 69 · warning/error 0** (세션1 종료 73 → 감소) |
| `flutter test` | **512/512 통과** (세션1 종료 440 → +72, 기존 회귀 0) |
| `dart format` | 세션 수정 파일 전부 clean(저장소 전체 포맷 부채는 세션1 기록과 동일) |
| `flutter build appbundle` (로컬) | **BLOCKED_ENV** — dl.google.com 프록시 차단(세션1과 동일) → CI appbundle 검증 |
| iOS | 정적 검증만(맥/Xcode 없음). APNs/entitlement/pod install 은 실기기 부채 |

## 2. 세션 1 보정 3건

1. **탈퇴 job fail-open 제거**: write-block 정본은 `account_deletion_write_blocked` RPC
   (스테이징 실측: `account_deletion_jobs` 는 RLS enabled + 정책 0개 → 직접 SELECT 는 항상
   0행이라 행 조회만으로는 purging 을 못 거른다). RPC/행 조회 실패는 `fetchFailed`
   (재시도 가능한 차단), **0행 + RPC false 만 active 통과**. canceled/failed 만 있으면 active.
2. **첨부 23505 의미 일치**: storage_path·thread_id·message_id 정확 일치 + author_id
   (존재 시) 현재 사용자 일치일 때만 멱등 성공. 불일치는 `AttachmentRegistrationConflict`
   (성공 위장·보상 DELETE 금지). 행 없음이면 기존 보상 삭제 흐름. 조회 인자를 무시하는
   백엔드도 테스트를 통과할 수 없음(반환 행 의미 검증). 구 정책명 주석
   `user_is_room_party_for_qra_path` → `qra_storage_insert_party` 정정.
3. **오답 표시 UI 연결**: 학생 질문 목록(answered/confirmed)에 "오답으로 표시/해제" —
   `qna_flag_wrong_answer` RPC만 호출, 성공 시 재조회 수렴, 실패 시 원상 유지+재시도 안내,
   멘토 화면(별도 파일) 미노출.

## 3. 서버 토큰 실계약(스테이징 실측)

- `register_device_token(p_token, p_platform)` → `{ok, device_token_id}` —
  `ON CONFLICT(token) DO UPDATE user_id=auth.uid(), revoked_at=null` 로 **계정 전환 원자
  재소유 서버 수행**(WAITING_SERVER_API 아님).
- `revoke_device_token` 은 **authenticated EXECUTE 미부여** → 앱은 미호출. 로그아웃 revoke 는
  RLS `device_tokens_modify_own` 하에서 본인 행 직접 UPDATE(revoked_at) — signOut '이전' 실행.
- `record_domain_notification` 은 서버 전용(앱 호출 금지) 확인.

## 4. 17/17 정본 매핑 (`notification_types.dart`)

| type | kind | 목적지 |
|---|---|---|
| question_answered | 질문방 | 질문방 탭 |
| new_order_message / new_application | 맞춤의뢰 | 목록 내 확인(전용 화면 부재 — 이동 없음) |
| mentor_subscription_price_changed / mentor_pause_notice / mentor_termination_notice / mentor_termination_refund | 구독·결제 | 마이페이지 |
| individual_question_{assigned,claimed,answered,message,released,expired_refunded} | 개별질문 | 개별질문 탭 |
| subscription_{renewal_upcoming,expired,renewal_succeeded,renewal_failed_insufficient_cash} | 구독·결제 | 마이페이지(★/wallet/charge 는 따라가지 않음 — Commerce-Zero) |
| (미지 타입) | 기타 | 이동 없음·일반 표시·크래시 0 |

- pause/termination 누락 없음(회귀 테스트), 내부 영문 type 비노출, 맞춤의뢰·환불도 표시.

## 5. 클라이언트 발송 경로 폐기(P1-11)

- `PushTrigger`·`EdgeFunctionPushSender`·`PushSenderPort`·`push_types.dart` 삭제 —
  grep 검증: 발송 호출부 0 (남은 것은 "발송 경로 제거됨" 주석 1건).
- HANDOFF(루트·core/push) 교정: 발송은 서버 outbox worker 단독
  (record_domain_notification → notification_outbox → deliveries), 앱은 수신·토큰 등록만.
- 도메인 write 성공 뒤 앱측 푸시 발송 호출 0건 확인.

## 6. 알림 목록·커서·설정

- 키셋 커서 `(created_at DESC, id DESC)` + pageSize+1 hasNext + id 중복 제거 + 세대 토큰.
  동률 created_at 3페이지 타일링(45행)에서 중복·누락 0 테스트.
- 전체 읽음 = `mark_all_notifications_read()` 1회, 성공 후에만 UI 반영. 개별 읽음 동일(실패 원복).
- 설정: `notification_settings` 정본(행 없음=ON), 그룹 5종(qna/order/subscription/refund/system —
  서버 `notification_event_group` 과 일치), 로드 실패 재시도 UI(기본값 위장 금지),
  저장 성공 후 확정·실패 원복, OS 권한 거부 상태 별도 안내. SharedPreferences 정본 사용 없음.

## 7. Firebase 상태

- 의존성: firebase_core 4.12.1 / firebase_messaging 16.4.3.
- **google-services.json · GoogleService-Info.plist 저장소/CI 에 없음 → 값 날조·시크릿 커밋 금지
  원칙에 따라 미배치. 상태: `WAITING_EXTERNAL_FIREBASE_CONFIG`.**
  gradle `com.google.gms.google-services` 플러그인도 의도적으로 미적용(json 없이 빌드 실패 방지).
  활성화 절차는 `lib/core/push/HANDOFF.md`에 문서화(파일 배치 → 플러그인 적용 →
  Xcode Push capability/aps-environment/APNs 키 → pod install).
- readiness 경계: 초기화 실패 흡수(크래시 0·등록 시도 0·권한 요청 no-op) — 테스트 고정.

## 8. 실기기에서만 남은 항목

- FCM 실수신(전경/배경/종료 상태), 알림 탭 → 탭 이동, Android 13 권한 팝업 실동작,
  iOS APNs 토큰 발급·수신, video_player·첨부 업로드 실동작 — 세션 3(실기기 QA).

## 9. 게이트 현황

- 댓글 정본 전환·최소 앱 버전: **WAITING_SERVER_GATE 유지**(이번 세션 재확인 없음 — 계약 변화 없음).
- Firebase 설정: **WAITING_EXTERNAL_FIREBASE_CONFIG** (앱 코드는 배치 즉시 활성).
