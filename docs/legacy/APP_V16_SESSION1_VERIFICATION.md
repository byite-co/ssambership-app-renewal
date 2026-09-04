# v16 앱 세션 1 검증 기록 (2026-07-21)

> 범위: 서버 계약 재기준화 + 질문방 원자 RPC 전환(P1-8/P2-13/P2-19) +
> 독립 클라이언트 결함 수정(P2-14/20/21/22/23, P3-4/5/6/7).
> 기준: master `50d34091` / staging `lbeqxarxothkmzqvpudy`(SQL 160) /
> 계약 정본 `docs/APP_V16_SERVER_CONTRACT_SNAPSHOT.md`.

## 1. 검증 결과 요약

| 항목 | 결과 |
|---|---|
| `flutter analyze` | **info 73건, warning/error 0** (시작 baseline: info 73 + warning 1 → warning 해소) |
| `flutter test` | **440/440 통과** (baseline 337 → 신규 103) |
| `dart format` (이번 세션 수정 파일) | clean |
| `dart format` (저장소 전체) | ★기존 부채: 3.44.6 포매터 기준 미수정 파일 ~110개 drift — "저장소 전체 기계적 포맷 금지" 지시에 따라 미적용(세션 수정 파일만 포맷) |
| `flutter build apk --debug` (로컬) | **BLOCKED_ENV** — 실행 환경 네트워크 정책이 dl.google.com 차단(프록시 403) → Android SDK 설치 불가. push 시 CI(flutter-ci: analyze·test·appbundle)가 빌드 검증 |
| iOS 빌드 | 환경에 macOS/Xcode 없음 — **PASS 기록 안 함**(실기기/맥 부채). 정적 검증만 수행(아래 §4) |

## 2. 질문방 RPC 전환 — 제거된 직접 write 경로

| 이전(직접 write) | 이후(서버 RPC) |
|---|---|
| `question_threads` INSERT(status='pending' 명시) + 첫 `question_messages` INSERT (2단계) | `qna_create_question_thread` 1회 — thread+첫 메시지+사용량 소비 원자, status 미전송 |
| 학생·멘토 후속 `question_messages` INSERT | `qna_append_message` |
| `confirmThread`: `question_threads.status` UPDATE | `qna_confirm_thread`(멱등) |
| `markThreadAnswered`: status UPDATE (멘토 화면에서 호출) | **메서드 삭제** — 첫 멘토 메시지/첨부 시 서버가 answered 전이+`question_answered` 알림. 앱은 `answered_transition` 신호만 반영 |
| 오답 표시 | 직접 UPDATE 경로 원래 없음 → `flagWrongAnswer`(qna_flag_wrong_answer) 신규 제공(UI 연결은 오답노트 트랙에서) |
| `question_attachments` INSERT | `qna_register_attachment` |
| PushTrigger 앱 호출 | 원래 호출부 없음(정의만 존재) — 알림은 서버 RPC 단독 책임 확인 |

## 3. 첨부 실패/보상 검증(P2-19)

- 등록 RPC 실패 → 방금 올린 본인 소유·미등록 객체만 `remove` (서버 DELETE 정책
  `qra_storage_delete_unregistered_owner`와 일치). 등록 성공 객체는 삭제 코드 경로 없음.
- 보상 삭제 실패 → `AttachmentRegistrationFailure`에 원래 실패(registrationError)와
  보상 실패(compensationError)를 **별도 보존**.
- 동일 storage_path 재시도(23505) → 기존 메타행 수용(중복 행 0), 보상 삭제 금지.
- `_uploadPending` `Future<void>` 오류 삼킴 제거 → `Future<bool>`; pending 첨부는
  **성공 시에만** 정리(본문 성공·첨부 실패를 전체 성공으로 표시하지 않음 — 위젯 테스트로 고정).
- 오류 UX: 서버 구조화 코드 20종(한도/무료질문권/환불보류/잠금/계정/멘토승인/당사자/차단/
  첨부/존재) → 한글 구분 안내, 미지 코드는 일반 재시도 문구(내부 SQL/RPC명 비노출) —
  `qna_error_mapper_test` 로 고정.

## 4. iOS 정적 검증(빌드 아님)

- `Info.plist` 파싱 정상. 카메라/사진 보관함 사용 문구(한글) 존재.
  `NSAppTransportSecurity=NSAllowsLocalNetworking`(로컬 개발용) 외 예외 없음.
- `Podfile` 존재(플랫폼 13.0+ — supabase/image_picker/pdfx/file_picker/url_launcher 요건 충족 주석).
- ★ 신규 의존 `video_player`는 iOS AVFoundation 플러그인 포함 — **맥에서 pod install +
  실기기 검증 부채**(세션 3).

## 5. 서버 게이트 판정에 따른 보류 항목

- **Track E(댓글 정본 전환·최소버전 게이트): WAITING_SERVER_GATE** — staging에 최소 앱 버전
  API/테이블 부재(실조회 0건). board_detail 은 mounted 가드까지만 수행.
- Track C(알림 17종·토큰 등록·FCM/APNs): 기반 테이블·전체읽음 RPC 존재 확인 완료.
  토큰 등록 RPC 유무만 세션 2 시작 시 추가 확인.

## 5-1. 기록 정정 (세션 2, 2026-07-21)

세션 1 보고의 "신규 커밋 4개"는 오기다. 정정:
- 세션 시작점 이후: `6b1da7e..5150c9c` = **5커밋**
- master 대비: `50d34091..5150c9c` = **6커밋**
- PR #33 변경 파일 = **50개**
(기존 커밋은 amend 하지 않고 본 문서로만 정정한다.)

## 6. 알려진 잔여 부채

1. 실기기 Android/iOS 검증(첨부 업로드·플레이어·딥링크) — 세션 3.
2. 오답 표시 UI(flagWrongAnswer 연결) — 오답노트 화면 트랙.
3. 저장소 전체 dart format drift(포매터 버전 차) — 별도 일괄 커밋으로만 처리할 것.
4. deletionPending 상태의 노출 문구(UI 소비처 없음 — 현재 이용 가능 취급).
5. 웹 경로(/account/delete 등) 실존은 웹 저장소 배포 기준 재확인 필요(앱 저장소에서 정적 확인만).
