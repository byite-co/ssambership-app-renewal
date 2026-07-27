# v16 앱 세션 3 검증 기록 (2026-07-21) — 앱 코드 마감

> 범위: 계정탈퇴 UX(P1-10) · 리뷰 회귀(P0-2/P1-7) · 개별질문 환불(P0-5) ·
> Track E 게이트 재확인 · 네이티브/QA 준비 · 전체 회귀.
> 시작 HEAD `6ff9031`. 판정 상태: COMPLETE / WAITING_SERVER_GATE /
> WAITING_EXTERNAL_FIREBASE_CONFIG / READY_NOT_EXECUTED / BLOCKED_ENV.

## 1. 계정탈퇴 P1-10 — 코드 COMPLETE · 라이브 경로 WAITING_SERVER_API

- **스테이징 실측**: `account_deletion_request`/`account_deletion_cancel` ACL =
  `{postgres, service_role}` — **authenticated EXECUTE 없음** → 앱 직접 호출은 42501.
  (grant 요청은 `APP_V16_MIN_VERSION_SERVER_REQUIREMENT.md` 말미에 기록.)
- 구현(전부 fake 포트 테스트 — 실 staging 계정으로 삭제 RPC 미실행):
  - `AccountDeleteScreen`: 위험 고지 + 확인 체크 + 재확인 다이얼로그 → 요청.
  - 요청은 **`p_dry_run=false` 명시**(+`p_cancelable_minutes=30`) — 기본값 의존 금지 테스트 고정.
  - 이중 탭/재요청 → 서버 멱등 응답(existing) 수용. existing job 이 locked 등이면 취소 UI 없이 안내.
  - 성공 후: 안내 → `AuthService.signOut`(토큰 revoke → 세션 폐기 순서 보장) → 로그인 화면.
  - 취소: deletionPending 재로그인 사용자에게만 버튼. 판정은 서버
    (`NOT_CANCELABLE`/`CANCEL_WINDOW_PASSED` 시 버튼 제거+안내). 취소 성공 후에도 재로그인.
  - 42501 → `AccountDeletionUnavailable` → '웹에서 진행' 폴백(기존 웹 플로우 유지 — 회귀 없음).
  - locked/purging 은 앱 진입 자체가 차단(computeAccess)이라 write 반복 재시도 경로 없음.
- 테스트 14개: dry_run=false·멱등·취소 코드 3종·42501 분기·요청/취소 성공·실패 원복·
  signOut 순서(주입 저널)·취소창 만료 버튼 제거.

## 2. 리뷰 P0-2/P1-7 — COMPLETE (앱은 읽기 전용)

전수 조사(grep + 코드 리딩) 결과 앱의 reviews 접근은 **1곳뿐**:
`mentor_directory_repository.dart` 의 통계 집계(SELECT `mentor_id, rating` +
`moderation_state='visible' AND is_hidden=false AND is_blinded=false`).

- INSERT/UPDATE/DELETE/RPC 호출 **0** — 작성·멘토 답글·수정은 웹 위임(웹브리지 `/mentor/reviews`).
- `student_id`/`content` 사용 0. 학생 리뷰 UPDATE UI 0. 답글 재수정 UI 0(웹·서버 담당 —
  서버 트리거 `reviews_enforce_update` 가 답글 1회·보호필드·moderation 필드를 강제함을 실측 확인).
- 블라인드 리뷰: 앱 통계 쿼리가 RLS(`reviews_select_public_visible`)와 **이중 필터**.
- 통계 cap: 별도 cap 로직 없음 — 필터된 행 집계 그대로(회귀 없음, 기존
  `mentor_detail_stats_test`/`mentor_sort_test` 유지 통과).

## 3. 개별질문 환불 P0-5 — COMPLETE

- 호출 경로: **공개 wrapper `refund_individual_question` 단독**(레포 실측 —
  core `refund_individual_question_hold` 는 호출부 0 이며 service_role 전용 grant 재확인).
- 취소 버튼: `iqCanStudentRefund` = escrowed/open/assigned/claimed 만 — 서버 wrapper 허용
  집합과 1:1 (9종+unknown 전수 매트릭스 테스트).
- 결과 처리 보강: `already_refunded` → **멱등 성공 안내**('이미 환불된 질문이에요'),
  ok=false 기타 코드 → 실패 처리(성공 토스트 금지), `REFUND_NOT_ALLOWED`/
  `INDIVIDUAL_QUESTION_REFUND_FAILED` 한글 매핑 신설(내부 코드 비노출).
- 로컬 선반영 0(원래 없음 — 실패 시 버튼·상태 라벨 유지 테스트), 지갑 선반영 0
  (IQ 상세는 잔액 미표시 — 마이페이지 캐시는 '조회만').
- 신규 테스트 8개(매트릭스·성공·멱등·answered 거부·비소유자·실패 원복·오류 매핑).

## 4. Track E 댓글·최소버전 — WAITING_SERVER_GATE (변화 없음)

- 재조회: 버전 관련 테이블·함수 **0건**(`%version%`/`app_config` 전수). `comments` 정본
  RLS 7정책은 준비돼 있으나 게이트 없이 전환 금지 원칙 유지.
- legacy 게시판 write 유지(제거 금지 준수), 임시 테이블명 전환 없음.
- 요구 계약 명세: **`docs/APP_V16_MIN_VERSION_SERVER_REQUIREMENT.md`** (RPC 시그니처·
  grant·앱 게이트 동작·전환 시 일괄 반영 목록).

## 5. Firebase — WAITING_EXTERNAL_FIREBASE_CONFIG (코드 준비 완결)

- `google-services.json`/`GoogleService-Info.plist` 부재 재확인. CI(flutter-ci.yml)에
  Firebase secret 주입 경로 없음(GITHUB_TOKEN 뿐).
- 앱 ID 계약(2026-07-22 갱신 — 플랫폼별 상이): Android `applicationId=com.ssambership.edu`,
  iOS `PRODUCT_BUNDLE_IDENTIFIER=com.ssambership.app` — Firebase Android 앱 등록 시 `com.ssambership.edu`, iOS 는 `com.ssambership.app`.
- 값 날조·타 프로젝트 복사 없음. gradle google-services 플러그인 의도적 미적용
  (파일 없이 켜면 빌드 실패). readiness 경계 + fake 테스트 유지(세션 2).
- 배치 절차: `lib/core/push/HANDOFF.md` + `APP_V16_DEVICE_QA_CHECKLIST.md` §0 —
  파일 배치 후 **plugins 1줄 + pod install** 만으로 활성화되는 상태 확인.

## 6. Android/iOS 실행 — READY_NOT_EXECUTED / BLOCKED_ENV

- Android emulator/SDK: 환경 네트워크 정책(dl.google.com 차단)으로 설치 불가 —
  **BLOCKED_ENV**. 실행 시나리오는 `APP_V16_DEVICE_QA_CHECKLIST.md` §1 로 준비.
- iOS: macOS/Xcode 없음 — plist(권한 문구·ATS)·Podfile(13.0+)·번들 ID 정적 검증만 수행,
  pod install/실기기는 **READY_NOT_EXECUTED** (PASS 위조 없음).

## 7. P2/P3 최종 회귀 — 계약↔테스트 매핑 (재작성 없음, 전부 통과)

| 계약 | 고정 테스트 |
|---|---|
| 질문 생성·append·confirm·오답·첨부 = qna RPC만, 직접 write 0 | new_question_submit / chat_attachment_send / wrong_answer_toggle / qna_error_mapper |
| 첨부 23505 의미 검증·미등록만 보상 삭제 | attachment_upload_rpc (11) |
| usage fail-closed | new_question_submit |
| 숏폼 player/scrap/body fallback | shortform_detail (9) + community_models |
| 이미지 compute/downscale/MIME | image_downscaler (11) + annotation_flatten_downscale |
| pagination raw cursor·generation | community_paginator (5) |
| account fetch failure fail-closed(+RPC 정본) | account_status (20) + auth_access |
| subjects 정본 code만 | subject_restrict (11) |
| mounted 가드 | iq/board/shortform 화면 테스트 + 코드 가드 |
| IQ signed URL cache | iq_attachment_url_resolver + iq_detail_url_cache |
| 신뢰 도메인 | trusted_attachment_url + web_bridge (10+) |
| 클라이언트 발송 0·17종 매핑 | push/* + notification_classify(17/17) |
| 알림 cursor·전체읽음·설정 원복 | notifications_repository/screen + settings_section |
| 임의 URL 딥링크 0 | deeplink/* (42 포함) |

## 8. 관리자 QA — ADMIN_QA_READY_NOT_EXECUTED

정적 검증(관리자 앱 차단·기능 누출 0·블라인드 이중 필터·보호필드 전송 0)은 완료,
실행 QA 는 관리자 계정 환경에서 `APP_V16_ADMIN_QA_CHECKLIST.md` §2 수행(계정/DB 임의 수정 없음).

## 9. 검증 결과

| 항목 | 결과 |
|---|---|
| flutter analyze | warning/error 0 (아래 최종 수치 참조) |
| flutter test | 전체 통과(세션 2 512 + 신규 — 최종 수치는 PR 참조) |
| flutter build appbundle (로컬) | BLOCKED_ENV(dl.google.com) → CI appbundle 검증 |
| 작업 트리 | clean · PR #33 draft 유지 · merge/force-push/신규 PR 없음 |

## 10. 구현 완료도 vs 배포 준비도 (분리 보고)

- **앱 코드 구현 완료도: ~95%** — 남은 코드 작업은 Track E 전환(서버 게이트 대기)뿐.
- **배포 준비도: ~70%** — 외부 조치 대기: ① Firebase 설정 파일 2개(+플러그인 1줄·pod install),
  ② 최소버전 API + 댓글 전환(1세션), ③ 탈퇴 RPC authenticated grant,
  ④ 실기기 QA(Android/iOS)·관리자 QA 실행, ⑤ release keystore/스토어 제출(오너 로컬).
