# v16 E2E 검증 리포트 (실서버 왕복)

> 상태: **E2E_PASS** — 실계정 3종(학생·멘토·관리자)으로 staging(=운영 공용 DB
> `lbeqxarxothkmzqvpudy`) 을 실제로 왕복하는 통합 시나리오가 전부 통과했다
> (`flutter drive`, 웹 렌더러 + chromedriver, `All tests passed / DRIVE_EXIT=0`).
> 실행 산출물(가역 쓰기 1건 + 설정 토글)은 모두 원상복구했고 **staging 잔여 0** 을
> 재조회로 확인했다(§4). 이 과정에서 **전 로그인 차단 P0 결함 1건을 발견·수정**했다(§3).

## 1. 대상·방식

- 테스트 코드: `integration_test/e2e_staging_test.dart` (드라이버 `test_driver/integration_test.dart`).
- 계정: `--dart-define` 로만 자격증명 주입(코드/저장소/로그에 평문 0). 학생/멘토/관리자.
- 실행: `flutter drive --profile --no-web-resources-cdn -d web-server --browser-name=chrome`.
  - `--no-web-resources-cdn`: CanvasKit/폰트를 CDN(gstatic) 대신 로컬 서빙(이 환경은 gstatic 차단).
- 네트워크: 이 실행 환경의 브라우저→외부 TLS 가 막혀 있어, 로컬 포워더(평문 →
  세션 프록시+CA 번들 → staging)를 두고 앱의 `SUPABASE_URL` 을 그 포워더로 지정.
  **요청은 전부 실제 staging 으로 왕복**했다(auth/rest/rpc 200 로그로 확인). 포워더는
  검증 편의를 위한 경유일 뿐 mock 이 아니다(REST/auth/RPC 실응답).

## 2. 통과한 시나리오 (전부 실서버 왕복)

| 단계 | 검증 내용 | 서버 왕복(관측) |
|---|---|---|
| 학생 로그인 | 이메일/비번 → 홈 셸 진입, 하단 5탭(질문방·커뮤니티·멘토 찾기·알림·개별질문) 렌더 | `POST /auth/v1/token 200`, `GET /users 200` |
| 계정 상태 판정 | 로그인 후 차단 없이 통과(§3 수정 반영) | `rpc/account_deletion_status_self 200`, `rpc/account_deletion_write_blocked 200` |
| 질문방 read | 초기 탭 목록 로드, 에러 문구 0 | `GET /mentor_student_rooms 200`, `individual_questions 200` |
| 커뮤니티 게시판 | 탭 전환('작성' FAB 확인) → 게시글 상세 진입 | `GET /community_posts 200`, `GET /comments 200` |
| **게시판 댓글 쓰기(가역)** | 정책 동의 다이얼로그 → 전송 → **목록에 실제 반영**(입력필드 오탐 아닌 목록 Text 로 확인) | `POST /rest/v1/comments`(신경로 `comments` 테이블 — 브리지가 `community_comments` 로 미러) |
| 멘토 찾기 / 알림 / 개별질문 | 각 탭 read, 알림 헤더('안 읽음') 렌더 | `rpc/mentor_directory_list_v2 200`, `GET /notifications 200` |
| **알림 설정 토글(가역)** | 마이페이지 → '알림 받기' 마스터 스위치 off/on 왕복 → **원상복구** | `notification_settings` upsert 왕복 |
| 학생 로그아웃 | 세션 폐기 → 로그인 화면 복귀 | — |
| 멘토 로그인 | 동일 홈 셸(멘토 뷰) 렌더 → 마이페이지 → 로그아웃 | `POST /auth/v1/token 200`(멘토) |
| 관리자 로그인 | **차단 화면** '앱을 이용할 수 없어요' + '학생·멘토 전용' 안내, '다시 시도' 버튼 없음(비재시도) → 로그아웃 | `computeAccess` admin→blocked (클라이언트 게이트, §관리자 검증과 정합) |

## 3. E2E 로 발견·수정한 결함

### P0 — 전(全) 로그인 차단 (`account_deletion_jobs` 직접 SELECT 403)
- **증상**: 로그인 직후 모든 사용자가 "잠시 확인이 필요해요 / 계정 상태를 확인하지 못했어요"
  화면에서 멈춰 앱에 진입 불가.
- **원인**: 계정 상태 판정 3단계가 `account_deletion_jobs` 를 **직접 SELECT** 했는데,
  이 테이블은 authenticated 에게 테이블 GRANT 자체가 없어(ACL: postgres·service_role 뿐)
  요청이 **403** 으로 실패 → fail-closed 규칙에 의해 `fetchFailed`(차단)로 귀결.
  종전 스냅샷의 "RLS 정책 0개 → 0행(오류 아님)" 전제가 오측이었음을 e2e 로 확인.
- **수정**(`lib/core/auth/account_status.dart`): 직접 SELECT 제거 →
  self RPC `account_deletion_status_self`(SQL 161, authenticated EXECUTE)로 교체.
  `exists/state/write_blocked` 기반 판정으로 기존 우선순위(write-block > completed >
  pending)와 fail-closed 를 그대로 유지. 단위 테스트 fake 도 self RPC 형태로 갱신.
- **부수 효과**: 지금까지 도달 불가였던 `deletionPending`(재로그인 취소 UX)이 실제 동작하게 됨.

### 부수 수정 (e2e 진입을 막던 웹 전용 이슈)
- `lib/core/push/firebase_push_gateway.dart`: 웹에서 `Firebase.initializeApp()` 이
  gstatic firebasejs 를 dynamic import 하다 **Dart try/catch 밖 unhandled promise** 로
  새어 e2e 존을 오염 → `kIsWeb` 이면 초기화 자체를 생략(모바일 경로 불변, 푸시 타깃은
  Android/iOS). 앱 로직상으로도 웹은 푸시 대상이 아니므로 회귀 없음.

> ※ 위 2건은 실기기(Android/iOS)에서는 서로 다른 양상이나, **P0(account_status)** 는
>   플랫폼 무관한 실결함으로 실기기에서도 동일하게 전 로그인을 막았을 것이다 — e2e 가
>   아니었으면 단위/위젯 테스트(계약 모사)로는 잡히지 않았다.

## 4. 정리(cleanup) — staging 잔여 0 확인

가역 쓰기만 수행했고 실행 후 전부 되돌렸다(실계정 탈퇴·질문 생성·게시글 작성·신고/차단은
시나리오에서 원천 제외).

- **게시판 댓글 1건**: `[E2E]` 표식으로 유일 식별 후, 미러(`community_comments`) →
  canonical(`comments`) 순으로 하드 삭제. 재조회 결과 `[E2E]` 잔존 0,
  대상 게시글 `comment_count` 0 복원(카운트 리프레시 트리거로 자동 보정),
  canonical/legacy live 카운트 모두 0.
- **알림 설정 토글**: off/on 왕복으로 원래 값(push_enabled) 그대로 복구 확인.
- **디바이스 토큰**: 웹 푸시 비활성으로 애초에 미등록 — 토큰 잔여 0.

## 5. 이 환경에서 제외/미실행 (사유 명시 — PASS 날조 없음)

- **질문 생성 / 답변 / IQ**: 무료 쿼터·IQ 실소모라 실행 금지(계약은 단위 테스트로 검증됨).
- **회원 탈퇴 플로우**: 실계정 탈퇴 금지 — status_self read 까지만(요청/취소 실행 안 함).
- **푸시 수신·딥링크 실동작**: Firebase 설정 파일 부재(WAITING_EXTERNAL_FIREBASE_CONFIG) +
  웹은 푸시 비대상. 수신/딥링크 매핑은 단위 테스트로 검증.
- **실기기(Android/iOS) 렌더·제스처**: 이 환경은 웹 렌더러로만 구동(BLOCKED_ENV — Android
  SDK 다운로드 프록시 차단). 실기기 QA 는 별도(READY_NOT_EXECUTED).
- **realtime(WebSocket)**: 포워더가 REST/auth/RPC 만 중계 — 실시간 채널은 미검증.
