# 전 기능 계약 수렴 실행 보고서 (앱) — 2026-08-04 세션

프리플라이트: `docs/audit/full_contract_convergence_preflight_20260804.md`.
DB·웹 정본은 `ssambership_web/docs/audit/full_contract_convergence_result_20260804.md`.

## A. 기준점

| 항목 | 값 |
|------|-----|
| 앱 기본 브랜치 | `master` @ `db20f21452c70273bcce9d8756f101e8e6ec1803` |
| 앱 작업 브랜치 | `claude/ssambership-convergence-defect-closure-ckc2z2` |
| 수렴한 기존 PR | #41(`1dc5e61`) — PR #38/#39/#40 전체 포함, 개별 재병합 0 |
| 최종 versionCode | `0.1.0+15` (기존 통합값 14 + 1, 1회 증가) |

## B. 수정 결과 (기능별 · 소비하는 서버 계약)

| 영역 | 앱 변경 | 판정 |
|------|---------|------|
| 프로필 self RPC | `profile_edit_repository.dart` → `api_app_v1.user_profile_update_self`(strict 봉투 + 코드 매핑); 학생 학년 비우기=`''` 전송, 멘토는 `p_grade_level` 미전송; users 직접 UPDATE 제거 | PASS |
| 멘토 찾기 | `mentor_directory_repository.dart`/`mentor_models.dart` → `api_web_v1.mentor_directory_v1` 100행 페이징(created_at desc, mentor_id desc·dedup·50p cap→incomplete 노출); legacy RPC 3종 제거; full_name fallback 제거(닉네임 없으면 '멘토'); `mentor_plans` `is_active=true` 필터; `mentor_lookup_repository` 뷰 단건 조회 | PASS |
| 커뮤니티 읽기 | `community_read_repository.dart` 게시판 목록·내활동·id조회 → `api_web_v1.community_posts_v1`(deleted_at 서버 강제); 숏폼은 base table; 게스트·로그인 동일 SQL | PASS |
| 신고 target | 게시판 댓글 `board_comment`(구 `comment` — 서버 거부 실사용 버그 수정), 숏폼 글 `shortform_post`, 숏폼 댓글 `community_comment`, 사용자 `user` | PASS |
| 숏폼 view v2 | `shortform_view_record_v2`(impression당 UUID event key, rebuild 재생성·재시도 0); legacy `increment_shortform_post_view` 제거 | PASS |
| 숏폼 댓글 삭제 | 본인 댓글만 삭제 노출(`authorId==uid` 게이트) → `community_comment_soft_delete_self`; 코드 매핑 | PASS |
| IQ Realtime | `iq_realtime.dart`(채널 `iq_{id}`, message/attachment INSERT + question UPDATE + reconnect) + `iq_messages_controller.dart`(dedup upsert); dispose/logout/questionId 변경 시 정리, resume·reconnect 서버 재조회, 실패 시 현 데이터 유지 | PASS |
| IQ 양방향 | 학생 후속·멘토 후속 메시지 `iq_append_message`; 멘토 첫 답변 `answer_individual_question`; 본문 없으면 전송 비활성; `iq_error_mapper.dart` 신규 코드 전량 매핑(첨부 Storage 실패 포함) | PASS |
| 알림 Realtime | `notifications_realtime.dart`(INSERT filter `recipient_user_id=eq`, reconnect); 목록 상단 upsert(dedup·게이트 타입 제외); resume·reconnect·탭재선택 재조회 | PASS |
| unread 배지 | `notification_badge_controller.dart` 서버 count 전용(`notification_unread_count_self`); 0 숨김·'99+'; 낙관 감소+롤백; HomeShell 배지 | PASS |
| 개별 읽음 | `markRead` → `mark_notification_read`(멱등 봉투) | PASS |
| 딥링크 | `notification_deep_link_controller.dart` UUID 검증 라우팅(room+thread/IQ/post/shortform/mentor); 삭제·미인가 target 중립 폴백; 맞춤의뢰 제외; free-form URL 미개방; TTL·dedup 유지 | PASS |
| 계정 삭제 v2 | `account_deletion_request_self_v2`/`_consented_v2`(창 30분 서버고정); `p_cancelable_minutes`/`p_dry_run` 전량 제거; consent/취소 코드 유지 | PASS |
| Commerce-Zero | 결제·충전·구독 진입점 0 유지; 금융 테이블 읽기 전용 | PASS |
| Firebase-free | 의존성 0 유지; `test/push/firebase_free_test.dart` 통과 | PASS |
| contract manifest CI | `test/contracts/outbound_api_manifest_test.dart` — RPC 29·view/table·bucket 정확 집합, 금지어(legacy RPC·users 직접쓰기·community_posts base write·firebase) 0 | PASS |

## C. P0/P1 해소

1. **users 직접 UPDATE 제거**: profile_edit_repository 가 M1 이후 잠긴 users 테이블에 직접 쓰지 않고 RPC 사용. manifest 테스트가 `from('users')` 직접 UPDATE/INSERT 재등장 0 을 소스로 잠금.
2. **신고 단절(P1)**: 게시판 댓글 `comment`→`board_comment`(서버 allowlist 통과). 리터럴 테스트 고정.
3. **soft-delete 노출(P1)**: 커뮤니티 읽기가 `community_posts_v1` 뷰(deleted_at 서버 강제)로 전환.
4. **IQ/알림 실시간 부재(P1)**: IQ·알림 realtime 포트 신설 + 서버 재조회 병행.
5. **멘토 200명 누락(P1)**: 뷰 100행 페이징 무손실(201·250행 테스트).
6. **배지 부정확(P1)**: 서버 count 전용 배지.

## D. 데이터 변화

앱은 스키마·데이터를 변경하지 않는다(클라이언트 계약 소비만). staging 데이터 변화는 웹 보고서 §D 참조.

## E. 테스트

- `flutter analyze` — **error 0 · warning 0**(단, `.env` asset 미존재 경고 1건은 master 부터 존재하는 기존 baseline — 수렴 도입분 0). info 74(기존 baseline 71 + const 힌트 3).
- `flutter test` — **전체 1292/1292 pass** (Flutter 3.44.8 / Dart 3.12.2)
- dart-define 모드: `IQ_CREATE_ENABLED=true`(221 pass) · `SUBS_MANAGE_LINK_ENABLED`+`PAYOUT_MANAGE_LINK_ENABLED`(137 pass)
- `test/contracts/` + `test/push/`(firebase-free) — 27 pass
- `test/app/build_version_test.dart` — vc15 계약 pass
- 신규 테스트: profile RPC 파라미터·봉투·코드매핑 / 멘토 201·250행 페이징·incomplete·full_name 부재 / community view 소스잠금 / board·shortform 신고 리터럴 / 숏폼 view key 안정성 / 숏폼 댓글 삭제 소유권·봉투 / IQ append·realtime / 알림 배지·딥링크 라우팅·realtime dedup / 계정삭제 v2 파라미터 / outbound manifest

## F. 산출물

- 브랜치: `claude/ssambership-convergence-defect-closure-ckc2z2`
- 신규 소스: `iq_realtime.dart` · `iq_messages_controller.dart` · `iq_error_mapper.dart` · `notifications_realtime.dart` · `notification_badge_controller.dart` · `notification_target_opener.dart`
- 신규 테스트 7 + 수정 테스트 다수
- versionCode 15 (pubspec + build_version_test)

## G. 잔여 blocker

- **BLOCKED_ENV — release AAB 빌드**: 이 세션에 Android SDK(`ANDROID_HOME` 미설정·sdkmanager 없음)와 **업로드 keystore**(`android/key.properties` — 오너 보유 비밀, gitignore 차단)가 모두 없다. release-signed AAB 는 오너의 keystore 환경(Build 13 AAB 를 만든 곳)에서만 생성 가능. **코드는 릴리즈 준비 완료**(analyze 0·전체 테스트 pass·버전 15·버전 계약 테스트 green). 빌드 명령: `flutter clean && flutter pub get && flutter analyze && flutter test && flutter build appbundle --release`(keystore 보유 환경).
- **NOT_RUN_DEVICE**: 실기기 통합(Realtime 라이브 수신·딥링크 실이동·push 정책)은 위젯/유닛 테스트까지 수행, 실기기 미보유로 미실행.
- **BLOCKED_ENV — 앱 E2E(staging 라이브)**: staging Supabase egress 정책 차단(웹 보고서 §G 동일).

## H. 최종 판정 (앱 범위)

```
SOURCE_CONVERGENCE: PASS
APP_CONTRACTS: PASS
SECURITY_P0: PASS (users 직접쓰기 0 — manifest 소스잠금)
FUNCTIONAL_P1: PASS
REALTIME_IN_APP_NOTIFICATIONS: PASS (analyze·test)
ACCOUNT_DELETION_REAL_RUN_ENABLED: NO
OS_PUSH_POLICY: EXCLUDED_APP_F0 (Firebase 0)
CONTRACT_MANIFEST_CI: PASS
FLUTTER_ANALYZE: PASS (0 error / 0 warning; .env baseline 제외)
FLUTTER_TEST: PASS (1292/1292 + dart-define 모드)
APP_VERSION: 0.1.0+15 (1회 증가)
RELEASE_AAB_READY: YES (코드) / BUILD: BLOCKED_ENV (SDK·keystore 부재)
PLAY_UPLOADED: NO
DEVICE_QA: NOT_RUN_DEVICE
READY_FOR_PRODUCTION: NO (실기기 QA·keystore AAB·Play 업로드 잔존)
```
