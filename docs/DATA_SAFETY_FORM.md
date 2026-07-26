# Play Console — Data safety 설문 초안 (P1-5)

> 작성일: 2026-07-12 · 대상: `ssambership_app` v0.1.0+1 · 기준 코드: master `c1b005f` + 스토어 잔존물 배치
> 갱신: 2026-07-26 (App-F0) — **OS 푸시(FCM) 제거 반영**. firebase_core/firebase_messaging 의존성·게이트웨이·디바이스 토큰 등록·알림 런타임 권한 선언을 전부 삭제했다. '기기 또는 기타 ID' 수집 = **아니요**.
> 성격: **근거 있는 초안** — 실제 콘솔 설문 입력은 사람이 한다. 각 응답의 코드 근거(파일:라인)를 함께 적어
> 입력자가 코드를 다시 뒤지지 않고 검증·기입할 수 있게 한다. 코드가 바뀌면 이 문서를 먼저 갱신할 것.
>
> ⚠️ 범위 주의: Data safety 는 **이 앱(APK/AAB)이 수집·전송하는 데이터** 기준이다. 웹(가입 폼·결제)은
> 웹 개인정보처리방침 관할이지만, 앱이 로그인 시 이메일을 전송하는 것은 앱의 수집으로 기재한다.

---

## 1. 총괄 응답 (설문 첫 페이지)

| 설문 문항 | 응답 | 근거 |
|---|---|---|
| 앱이 필수 사용자 데이터를 수집·공유하는가 | **수집: 예 · 공유: 아니요** | 아래 §2 수집 항목표. 광고·분석·크래시 SDK 없음 — `pubspec.yaml` 에 analytics/crashlytics/광고 SDK 부재. **App-F0 이후 Firebase SDK 도 없다**(firebase_core/firebase_messaging 제거) — 데이터 저장·전송은 Supabase 단일 백엔드뿐. 제3자 푸시 전송 서비스로 나가는 식별자가 없다 |
| 전송 중 데이터 암호화 | **예** | 운영 백엔드는 Supabase 원격(`https://<ref>.supabase.co`) — `.env.example:7-8` 운영 예시, `lib/core/config/app_config.dart:24-27`(`_isRemote` 분기). 로컬 http 는 dev 전용(`SUPABASE_URL=http://127.0.0.1`) |
| 사용자가 데이터 삭제를 요청할 수 있는가 | **예** | 인앱 진입 `lib/features/mypage/ui/sections/settings_section.dart:143-147`('회원 탈퇴') → 확인 다이얼로그(:49-75) → `openAccountDeleteWeb` → 웹 `/account/delete`(`lib/core/web_bridge/web_bridge_config.dart:35-38`). 콘솔 '삭제 요청 URL' 칸: `https://ssambership-web.vercel.app/account/delete` |

## 2. 수집 항목표 (카테고리별 상세 응답)

수집 목적 코드는 Play 설문 선택지 기준: **앱 기능(App functionality)** / **계정 관리(Account management)**.
모든 항목 공통: **공유 안 함 · 판매 안 함 · 임시 처리 아님 · 처리 위탁은 Supabase(백엔드 호스팅)뿐**.

| Play 카테고리 → 항목 | 수집? | 필수/선택 | 목적 | 코드 근거 |
|---|---|---|---|---|
| 개인 정보 → 이메일 주소 | **예** | 필수(로그인 시) | 계정 관리 | 로그인 전송 `lib/core/auth/auth_service.dart:190-199`(`signInWithPassword`), 마이페이지 표시용 조회 `lib/features/mypage/data/mypage_repository.dart:66`(`users.email` select) |
| 개인 정보 → 이름(닉네임·표시명) | **예** | 선택(프로필 수정) | 앱 기능 | `lib/features/mypage/data/profile_edit_repository.dart:25-30`(`users.nickname` update) |
| 개인 정보 → 기타 정보(학년) | **예** | 선택 | 앱 기능 | `users.grade_level` — 조회 `mypage_repository.dart:66-70`, 입력 `lib/features/mypage/ui/profile_edit_screen.dart:34-35`, 저장 `profile_edit_repository.dart:28` |
| 개인 정보 → 학교 | **아니요(앱은 입력 없음)** | — | — | 학교·전공은 **멘토 공개 프로필의 표시 전용**(`lib/features/mentors/data/mentor_models.dart:45-72`) — 입력·수정은 웹(`openProfileEditWeb`). 학생 학교 입력 UI 없음 |
| 개인 정보 → 성적 | **아니요** | — | — | 성적 입력 코드 없음(lib 전수 grep — 커뮤니티 `'school'→'내신'` 은 카테고리 라벨뿐, `lib/features/community/data/community_labels.dart:8`) |
| 사진 및 동영상 → 사진 | **예** | 선택(사용자 발의 업로드) | 앱 기능 | 질문방 첨부 `lib/features/question_room/ui/chat_screen.dart:203-244`(선택→업로드), Storage 업로드 `lib/features/question_room/data/attachments/attachment_upload.dart:117`(`uploadBinary`, 버킷 `question-room-attachments` :81, 5MB 제한 :25), IQ 첨부 `lib/features/individual_question/data/iq_attachments_repository.dart:64`, 촬영·갤러리·파일 선택 `lib/core/scan/scan_source_picker.dart:51-61`(image_picker/file_picker — 카메라는 시스템 인텐트, `CAMERA` 권한 선언 없음: `android/app/src/main/AndroidManifest.xml` 권한은 INTERNET 1개) |
| 파일 및 문서 | **아니요(서버 미전송)** | — | — | PDF 는 온디바이스 래스터화(pdfx) 후 이미지로만 업로드 — 원본 문서 파일을 서버로 보내지 않음(`lib/core/scan/` 포트) |
| 메시지 → 기타 인앱 메시지(질문·답변) | **예** | 선택 | 앱 기능 | 질문방 메시지·IQ 답변 — `lib/features/individual_question/data/individual_question_repository.dart:12`(RPC `answer_individual_question` 등), 질문방 전송 `chat_screen.dart` |
| 앱 활동 → 기타 사용자 생성 콘텐츠(게시글·댓글) | **예** | 선택 | 앱 기능 | 게시글 `lib/features/community/data/community_write_repository.dart:119-138`(`community_posts` insert), 댓글 :98-115(`community_comments` insert), 신고 :140-156(`content_reports`), 차단 목록 `lib/features/community/data/user_blocks_repository.dart:101`(`user_blocks` insert) |
| 기기 또는 기타 ID | **아니요** | — | — | App-F0: OS 푸시를 출시 범위에서 제외했다. `firebase_messaging`·게이트웨이·`register_device_token` 등록 경로가 **코드에 존재하지 않으며**(회귀 잠금: `test/push/firebase_free_test.dart`), 푸시 SDK 설정 파일도 빌드에 포함되지 않는다. 따라서 device token 을 발급·수집·전송하지 않는다. 재도입 시 이 행을 '예'로 되돌리고 설문을 재제출할 것 |
| 위치·연락처·건강·금융 정보 등 그 외 전 카테고리 | **아니요** | — | — | 해당 권한·SDK·입력 UI 없음(매니페스트 권한 = INTERNET 1개 — 위치/연락처/센서/전화 권한 없음) |

부수 저장값(설문 카테고리 해당 없음 판단, 입력자 참고): 알림 수신 설정 `notification_settings.push_enabled` ·
`notification_settings.groups`(`lib/features/mypage/data/notification_settings_repository.dart:6-16`) —
기능 설정값이며 식별·추적 용도 아님.
구 `users.notification_enabled` 컬럼은 staging DB 에 실재하나 앱·웹·DB 함수/뷰/정책/인덱스 참조가 모두 0인
**고아 컬럼**이다(정본은 `notification_settings`). 컬럼 제거 여부는 별도 DB 스키마 정리 오너 결정 —
docs/PLAY_STORE_REVIEW_PLAN.md '델타' 표 참조.

## 3. 전송·보관·삭제 경로 (설문 부속 설명용)

- **전송**: 모든 데이터는 Supabase 클라이언트(`lib/core/supabase/supabase_client.dart` — `Supabase.initialize`)를
  통해 단일 백엔드로만 전송. URL/anon key 는 `.env` 주입(`lib/core/config/app_config.dart`), 하드코딩 없음.
  운영 도메인은 TLS(https) — 스토어 빌드 전 `.env` 가 원격 production 값인지 확인(§4-체크리스트).
- **접근 통제**: 쓰기 경로는 전부 본인 uid 기준 RLS 전제(예: `profile_edit_repository.dart:7`,
  `attachment_upload.dart:123-124` author_id 기록).
- **계정 삭제**: 앱 내 '회원 탈퇴'(마이페이지 → 설정) → 되돌릴 수 없음 고지 다이얼로그 → 운영 웹
  `/account/delete` 로 이동. 실제 삭제 처리(auth.users + 데이터 정리)는 웹 레포 소유의 Edge Function —
  **콘솔 기재 전 웹 페이지가 실동작하는지 사람 확인 필수**(PLAY_STORE_REVIEW_PLAN '사람이 해야 하는 것' §2-3).

## 4. 콘솔 입력자 체크리스트 (사람 작업)

1. [ ] 스토어 빌드의 `.env` 가 운영 Supabase(https) 값인지 확인 후 §1 '암호화 전송=예' 기입.
2. [ ] `https://ssambership-web.vercel.app/account/delete` 실페이지 동작 확인 후 삭제 URL 기입.
3. [ ] §2 표를 설문 카테고리 순서대로 옮겨 기입하고,
   '수집=예'로 표시된 항목을 빠짐없이 입력했는지 확인
   (표에 없는 나머지 카테고리는 전부 아니요).
4. [ ] 개인정보처리방침 URL(`/legal/privacy`) 을 스토어 등재정보에 함께 등록(P0-2 콘솔측).
5. [ ] 푸시(FCM): **미도입**(App-F0 에서 제거) → '기기 또는 기타 ID' 아니요로 기입. 재도입하거나 IQ 작성(on 전환) 도입 시 §2 갱신 → 설문 재제출.
