# 쌤버십 앱 v16 결함 수정 — 병렬/직렬 분류 + 자율 실행 지시서

> 기준 문서: `REMEDIATION_INSTRUCTIONS_v16_1.md` (웹+DB+앱 통합 마스터)
> 이 문서: 그 마스터에서 **앱(Flutter) 파트만** 추출해, 재개 시 실행 에이전트(CC)가
> 이전 대화 참조 없이 자율 실행할 수 있도록 재구성한 실행계획.
> 기준 커밋: 앱 `50d34091eac8` (master, 현재 HEAD) · 웹 `bad8694c5620`
> Supabase staging: `ssambership-staging` (project ref `lbeqxarxothkmzqvpudy`, ap-northeast-2)
> 작성 시점 상태: **전(全) 앱 파트 보류** — 대형 항목의 서버 계약이 staging에 미배포이고,
> 웹/DB 작업이 진행 중이라 앱을 지금 바꾸면 공유 DB 계약 충돌·재작업 위험이 있음.

---

## 0. 이 문서 사용법 (실행 에이전트 필독)

### 0-1. 착수 전 게이트 규칙
1. **각 작업의 "재개 게이트"를 먼저 staging 실조회로 확인한다.** 게이트가 명시된 작업은
   조건이 충족되기 전에는 **절대 착수하지 않는다.** (게이트 없는 작업 = "작업선 P"만 서버 무관.)
2. staging 조회는 **읽기 전용**으로만. `apply_migration`·`execute_sql`의 DDL/DML 금지.
   앱 저장소(`ssambership-app`)만 수정한다. 웹 저장소·Supabase SQL은 건드리지 않는다.
3. **모든 실행은 직렬.** 트랙 내부는 명시된 순서대로 하나씩. 병렬-안전 라인(작업선 P)도
   내부에 파일 겹침이 있으므로 한 항목씩 완료·검증 후 다음으로 넘어간다.
4. 착수 전 `flutter analyze`로 baseline을 잡고, 각 항목 완료 후 `flutter analyze` + 관련
   테스트가 green인지 확인한 뒤 커밋한다(항목 단위 커밋 권장).

### 0-2. 공통 설계 원칙 (마스터 문서 §1 요약 — 모든 앱 작업에 적용)
- 서버가 주는 역할·상태·자격 판정을 **클라이언트에서 재구현해 보안 경계로 삼지 않는다.**
  앱 검사는 UX용, 최종 판정은 서버.
- **실패를 성공처럼 처리하거나 로컬 상태만 갱신하지 않는다.** DB·Storage 실패는 사용자에게
  **재시도 가능한 오류**로 표시한다.
- Storage 업로드 후 DB/RPC 등록에 실패하면 **업로드한 미등록 객체를 보상 삭제**한다
  (단, 보상 삭제는 서버 DELETE 정책이 있어야 실동작 — 트랙 B 게이트 참조).
- 서버 의존 항목이 미배포인 동안 **임의의 RPC 이름·반환형·에러코드로 앱 코드를 확정하지 않는다.**
  서버 계약이 병합된 커밋을 받아 타입·에러코드를 그것에 맞춘다.
- 구버전 차단은 **서버 최소버전 응답 + 앱 시작 게이트가 모두 준비된 뒤**에만 사용한다.
- 범위 밖 파일·자동 생성 파일·웹 저장소를 정리·포맷하지 않는다.

### 0-3. staging 게이트 확인용 스니펫 (읽기 전용, Supabase MCP)
`project_id = lbeqxarxothkmzqvpudy`. 함수/테이블/정책 존재 확인 예:
```sql
-- 함수 존재
select p.proname, pg_get_function_identity_arguments(p.oid)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname = ANY(ARRAY['append_question_message','register_question_attachment']);
-- 테이블 존재
select table_name from information_schema.tables
where table_schema='public' and table_name = ANY(ARRAY['account_deletion_jobs','device_tokens']);
-- 정책 존재 (테이블/스토리지)
select policyname, cmd from pg_policies where schemaname='storage' and tablename='objects'
  and (qual ilike '%question-room-attachments%' or policyname ilike '%qra%');
```
> **~~작성 시점 실측~~ (2026-07-21 재기준화로 폐기):** 위 문단은 웹·DB 구현 **전** 실측이라 더 이상
> 사실이 아니다. SQL 160까지 적용된 staging 실정의 기준 최신 계약은
> **`docs/APP_V16_SERVER_CONTRACT_SNAPSHOT.md`** 가 정본이다. 요약:
> - 질문방 RPC 5종(`qna_create_question_thread`/`qna_create_free_question_thread`(위임 래퍼)/
>   `qna_append_message`/`qna_confirm_thread`/`qna_flag_wrong_answer`/`qna_register_attachment`) **배포됨** → 트랙 B 게이트 충족.
> - `question-room-attachments` **DELETE 정책 배포됨**(본인 소유·미등록 객체만) + `question_attachments.storage_path` UNIQUE.
> - `shortform_reactions_type_check = CHECK (type in ('like','scrap'))` + RLS 배포 → 트랙 F 게이트 충족.
> - `device_tokens`·`notification_deliveries`·`notification_settings`(실명 주의)·`mark_all_notifications_read()` 존재 → 트랙 C 기반 확인.
> - `account_deletion_jobs` + `account_deletion_request/cancel` + `account_deletion_write_blocked` 배포 → 트랙 D 게이트 충족.
> - **최소 앱 버전 API는 여전히 부재** → 트랙 E(댓글 정본 전환)만 WAITING_SERVER_GATE.
> - `subjects` 정본 catalog 35종 확정. 질문 생성 RPC는 catalog 밖 subject를 **조용히 NULL 처리**.

---

## 1. 분류 요약 (한눈에)

### 작업선 P — 병렬-안전 독립 클라이언트 라인 (서버 게이트 없음 · 하나의 라인 · 내부 직렬)
> 서로 다른 저장소(앱)만 건드리고 공유 DB 계약을 바꾸지 않으며 미배포 서버에 의존하지 않는다.
> **웹 작업과 물리적으로 무충돌.** 단, 내부에 같은 파일을 만지는 항목이 있어 순서대로 실행.

| ID | 원항목 | 내용 | 주요 파일 |
|---|---|---|---|
| P-1 | P2-13 | 질문 생성 fail-open 제거(usage==null 안전차단) | `question_room/ui/new_question_screen.dart` |
| P-2 | P2-20 | 첨삭 평탄화 다운스케일·MIME/확장자·회전 매퍼 | `scan_annotation/annotation_flattener.dart`, `scan_annotation/scan_annotation_screen.dart` |
| P-3 | P2-21 | 커뮤니티 목록 커서/offset + 세대 토큰 | `community/data/community_read_repository.dart`, `community/ui/board/board_list_view.dart` |
| P-4 | P2-14a | 숏폼 플레이어 수정 + 설명 body/content 폴백 (스크랩 제외) | `community/ui/shortform/shortform_detail_screen.dart`, 숏폼 모델 |
| P-5 | P3-4 | mounted/refresh 가드 | `board_detail_screen.dart`, `shortform_detail_screen.dart`, `iq_detail_screen.dart`, `student_iq_list_screen.dart` |
| P-6 | P3-5 | 동기 이미지 처리 → `compute()` 이관 | `core/scan/image_downscaler.dart` |
| P-7 | P3-6 | IQ signed URL 재요청 → 리졸버 캐시 | `individual_question/ui/iq_detail_screen.dart`, `question_room/data/attachments/attachment_url_resolver.dart` |
| P-8 | P3-7 | 웹브리지 도메인 확정 + 딥링크/복귀 검증 | `core/web_bridge/web_bridge_config.dart` |

> **작업선 P 내부 파일 겹침(순서 주의):** `shortform_detail_screen.dart`는 P-4·P-5 공유,
> `iq_detail_screen.dart`는 P-5·P-7 공유. → **P-4와 P-5를 인접 실행**, **P-7을 P-5 직후 실행**
> (또는 같은 파일 변경을 한 번에 묶어 커밋).

### 직렬 트랙 — 서버 게이트 + 내부 순서 필수 (게이트 충족 전 착수 금지)

| 트랙 | 원항목 | 서버 재개 게이트 (staging에 있어야 착수) | 주요 파일군 |
|---|---|---|---|
| **B. 질문방 원자 RPC** | P1-8 + P2-19 | 질문방 생성/append/확인/오답/첨부 RPC + `question-room-attachments` **Storage DELETE 정책** | `question_room/data/*`, `question_room/ui/*` |
| **C. 알림·푸시** | P1-11 + P2-15/16/17/18 | outbox·`device_tokens`·토큰등록 RPC·`user_notification_settings`·`notifications.type` 정본화·전체읽음 RPC | `core/push/*`, `features/notifications/*`, `mypage/data/notification_settings_repository.dart`, 딥링크 |
| **D. 계정 라이프사이클** | P1-10 + P2-22 | `account_deletion_jobs` + 상태 RPC + write 게이트 + effective-status 응답 계약 | `core/auth/account_status.dart`, `features/auth/blocked_screen.dart`, 탈퇴 경로 |
| **E. 게시판 댓글 어댑터** | P1-12 | 댓글 브리지(community_comments→comments) + **최소 앱 버전 인프라** | `community/data/*comment*`, `community/ui/board/board_detail_screen.dart` |
| **F. 숏폼 스크랩** | P2-14b | `shortform_reactions` CHECK가 `('like','scrap')`로 확장 | `community/*shortform*` 반응 경로 |
| **G. 과목 FK 정책** | P2-23 | (서버 아님) **정책 결정** 3안 중 택1 확정 | `data/mappings/subject_labels.dart` |

### 트랙 간 독립성 (동시성 참고 — 본 지시상 실행은 직렬)
- 작업선 P는 모든 트랙과 무관·서버 무관 → 언제든 가능.
- 트랙 B/C/D/E/F는 대체로 **파일군이 서로 disjoint**(질문방 / 알림 / 계정 / 게시판 / 숏폼)라
  다른 실행자라면 병렬 가능하나, **본 지시상 한 번에 한 트랙만 직렬 진행.**
- **파일 겹침 주의:** P3-4(작업선 P)는 `board_detail_screen.dart`(트랙 E)·`shortform_detail_screen.dart`(트랙 F)·
  `iq_detail_screen.dart`를 만진다 → 작업선 P를 트랙 E/F보다 **먼저** 끝내면 겹침 회피.

---

## 2. 작업선 P — 상세 지시서 (서버 무관·즉시 가능)

### P-1 · P2-13 — 질문 생성 fail-open 제거
- **대상:** `lib/features/question_room/ui/new_question_screen.dart` — `_submit()` (line 62–108), 핵심 71–84.
- **재개 게이트:** 없음. `get_weekly_question_usage` RPC는 이미 staging 배포됨(그대로 읽기).
- **문제:** line 71 주석대로 `usage == null`(RPC 실패/판정 불가)이면 흐름을 **막지 않고 진행**한다(fail-open).
  한도 초과 사용자도 조회 실패 시 생성 가능.
- **지시(단계):**
  1. `weeklyUsage(...)` 결과가 `null`이면 **제출을 중단**한다: `setState(() => _busy=false)` 후
     "사용량을 확인하지 못했어요. 잠시 후 다시 시도해 주세요." 스낵바 노출하고 `return`.
     (fail-open → **fail-closed** 전환이 목적.)
  2. `usage != null && !usage.canAsk` (한도 초과) 분기는 그대로 유지.
  3. **`usage != null && usage.canAsk`일 때만** `createThread`/`appendMessage` 진행.
  4. `catch(e)`의 네트워크/DB 예외는 기존 `friendlyError` 유지하되, "판정 불가(null)"와 "예외"를
     사용자 문구로 구분(둘 다 재시도 가능 상태).
- **권장:** usage 조회를 `initState`나 별도 상태(`_usageError`/`_usageLoading`)로 승격해 **제출 버튼을
  usage 확정 전까지 비활성화**하면 UX가 더 명확(선택). 최소 구현은 위 1–3.
- **주의:** line 69–70의 "클라 검사일 뿐·서버 강제는 P1-8" 주석은 **유지**한다(사실). 우회 직접 INSERT는
  트랙 B(P1-8)에서 서버가 막는다. 여기선 정상 앱 흐름만 fail-closed로.
- **검증/DoD:** `flutter analyze` 0. usage=null 모킹 시 `createThread` 미호출 단위테스트 추가.
  수동: 네트워크 차단/RPC 오류 강제 시 제출 차단·안내 노출.

### P-2 · P2-20 — 첨삭 평탄화 다운스케일·MIME/확장자·회전 매퍼
- **대상:** `lib/features/scan_annotation/annotation_flattener.dart` (line 19–72),
  `lib/features/scan_annotation/scan_annotation_screen.dart` (line 141 "1회 플래그").
- **재개 게이트:** 없음(순수 클라 이미지 처리). 업로드 대상 스토리지 계약(iqa annotations, json mime,
  UPDATE 정책)은 이미 배포됨.
- **문제:** 원본 픽셀 PNG로 평탄화 → 5MB 초과 가능. 회전 시 현재 편집 스케치가 이전 mapper로
  정규화되지 않아 좌표가 어긋남.
- **지시(단계):**
  1. **평탄화 전 배경 다운스케일:** 배경 이미지를 장변 캡(예 2560px, 파라미터화)으로 축소한 뒤 합성.
     `core/scan/image_downscaler.dart`의 idiom(`package:image`, `copyResize`, `_hasTransparency`,
     `_withExt`) 재사용. **무거운 인코딩은 P-6과 동일하게 `compute()`로 이관**(같은 파일군이면 P-6 먼저).
  2. **MIME↔확장자 일치 강제:** 출력이 PNG면 `image/png`+`.png`, JPEG면 `image/jpeg`+`.jpg`.
     불일치 시 하류 검증/서버 mime 화이트리스트에서 거부되므로 반드시 일치.
  3. **회전 매퍼:** `scan_annotation_screen.dart:141`의 1회 플래그를 제거하고, 회전 시
     **현재 편집 스케치를 이전 mapper로 정규화 → 새 mapper로 복원**(좌표계 변환). 매 회전마다 수행.
- **권장:** 좌표 변환은 순수 함수로 분리해 단위테스트(회전 0/90/180/270에서 왕복 항등) 작성.
- **검증/DoD:** 대형 배경(>5MB) 평탄화 결과 ≤5MB, MIME/확장자 일치. 회전 후 필기 좌표 정합(수동).
  `flutter analyze` 0.

### P-3 · P2-21 — 커뮤니티 목록 커서/offset + 세대 토큰
- **대상:** `lib/features/community/data/community_read_repository.dart`
  (`_dropBlocked` line 27–34, `boards` 38–51, `shortforms` 54–66),
  `lib/features/community/ui/board/board_list_view.dart` (페이징 상태 line 74·104 부근).
- **재개 게이트:** 없음(읽기 전용, 기존 테이블 `community_posts`/`shortform_posts`).
- **문제:** `_dropBlocked`가 차단 작성자를 제거하며 **페이지 길이를 축소**한다. 화면은 `range(offset, ...)`의
  요청 길이 기준으로 다음 offset을 계산 → 차단분만큼 **행이 건너뛰어지거나 중복** 로드됨. 또 카테고리 전환/새로고침
  시 이전 세대 응답이 뒤늦게 도착해 목록 오염 가능.
- **지시(단계):**
  1. **원본 DB cursor/offset을 필터와 분리 유지:** 페이지네이션 기준을 "필터 후 개수"가 아니라
     **DB에서 실제로 읽은 원본 행 수(offset 전진량)**로 잡는다. 즉 `_dropBlocked`는 표시용으로만 쓰고,
     다음 offset은 요청한 `limit`(또는 실제 반환 raw 행 수) 기준으로 전진.
  2. 리포지토리가 **원본 raw 개수/마지막 커서**를 함께 반환하도록 시그니처 확장(예: `PagedResult<BoardPost>`
     `{items, rawCount, nextOffset, hasMore}`). 화면은 `nextOffset`으로만 다음 페이지 요청.
  3. **세대 토큰:** `board_list_view.dart`에서 카테고리 변경/새로고침마다 `int _generation++`을 증가시키고,
     비동기 응답 도착 시 **자신의 세대가 최신일 때만** `setState` 반영(오래된 응답 폐기).
- **권장:** 진짜 커서(예: `created_at < lastCreatedAt`) 기반이면 offset drift가 근본 차단되지만, 최소 구현은
  "raw 행 수 기준 offset + 세대 토큰"으로 충분. 정렬은 기존 `created_at desc` 유지.
- **주의:** `_dropBlocked`의 차단 로직 자체(내가 차단한 author 숨김)는 유지. 페이징 기준만 교정.
- **검증/DoD:** 차단 작성자가 섞인 목록에서 스크롤 시 누락/중복 0. 카테고리 빠른 전환 시 이전 결과 미표시.
  `flutter analyze` 0 + 페이징 단위테스트.

### P-4 · P2-14a — 숏폼 플레이어 수정 + 설명 body/content 폴백 (스크랩 제외)
- **대상:** `lib/features/community/ui/shortform/shortform_detail_screen.dart` (플레이어 line 231 부근),
  숏폼 모델(`community_models.dart` 등의 `ShortformPost`).
- **재개 게이트:** 없음(스크랩만 트랙 F로 분리 — 여기서 **스크랩은 다루지 않는다**).
- **문제:** 플레이어 동작 결함(line 231). 설명이 모델 필드 불일치로 유실(`body`/`content` 어느 쪽만 채워짐).
- **지시(단계):**
  1. 플레이어 초기화/컨트롤러 처리 수정(재생/일시정지·dispose 정합). 구체 결함은 현 코드 대조 후 확정.
  2. 설명 표시를 **`body ?? content ?? ''`(또는 반대)** 폴백으로 통일해 웹·앱 어느 필드로 저장돼도 노출.
- **주의:** **스크랩(reaction) 기능은 서버 CHECK 미배포로 트랙 F.** 여기서 스크랩 버튼을 활성화하지 않는다.
- **검증/DoD:** 플레이어 정상 재생·해제. 설명 필드 어느 쪽이든 표시. `flutter analyze` 0.

### P-5 · P3-4 — mounted/refresh 가드
- **대상:** `board_detail_screen.dart`(line 190), `shortform_detail_screen.dart`(line 190),
  `iq_detail_screen.dart`(line 183), `student_iq_list_screen.dart`(line 54).
- **재개 게이트:** 없음.
- **문제:** 비동기 후 `setState`/refresh 호출 전 `mounted` 미검사 → dispose 이후 setState 예외 가능.
- **지시(단계):** 각 지점의 비동기 후속 `setState`/refresh 앞에 `if (!mounted) return;` 가드 추가.
  `await` 이후 `BuildContext` 사용 지점도 `mounted` 확인.
- **주의:** **P-4(shortform_detail) 직후 실행**해 같은 파일 겹침 회피. `iq_detail_screen.dart`는 **P-7과 공유** →
  P-7 직전/직후 인접 실행 권장.
- **검증/DoD:** `flutter analyze` 0(특히 `use_build_context_synchronously` 경고 해소). 빠른 진입·이탈 반복 시 예외 없음.

### P-6 · P3-5 — 동기 이미지 처리 → `compute()` 이관
- **대상:** `lib/core/scan/image_downscaler.dart` (전체 — decode/copyResize/encode/`_hasTransparency`).
- **재개 게이트:** 없음.
- **문제:** `downscaleIfOversized`가 UI isolate에서 decode/resize/encode를 동기 수행 → 대형 이미지에서 프레임 드랍.
- **지시(단계):**
  1. decode→copyResize→encode(+`_hasTransparency`) 전체를 **top-level 함수**로 추출(예:
     `Uint8List? _downscaleWorker(_DownscaleArgs args)`), 인자·반환을 **Uint8List/기본형 경계**로.
  2. `downscaleIfOversized`에서 `await compute(_downscaleWorker, args)` 호출. 실패/`null`이면 기존처럼 **원본 반환**.
- **권장:** `package:image`는 순수 Dart라 isolate 안전. 인자 객체는 `bytes`(Uint8List)·`maxLongSide`·`maxBytes`만.
  P-2에서 같은 워커를 재사용하도록 설계.
- **검증/DoD:** 대형 이미지 축소 시 UI 프리즈 없음. 기존 동작(≤maxBytes 원본 유지, 실패 시 원본) 회귀 없음.
  `flutter analyze` 0 + 기존 downscaler 테스트 green.

### P-7 · P3-6 — IQ signed URL 재요청 → 리졸버 캐시
- **대상:** `lib/features/individual_question/ui/iq_detail_screen.dart` (line 552 부근),
  `lib/features/question_room/data/attachments/attachment_url_resolver.dart` (캐시 소유).
- **재개 게이트:** 없음(기존 스토리지 재서명).
- **문제:** IQ 상세가 signed URL을 매번 재요청 → 불필요한 네트워크/지연.
- **지시(단계):** `iq_detail_screen.dart:552`의 직접 재서명 호출을 **`AttachmentUrlResolver` 캐시 경유**로 교체.
  리졸버에 TTL 캐시가 없으면 `storage_path → (url, expiresAt)` 캐시 추가(만료 전 재사용, 만료 시 재서명).
- **주의:** `iq_detail_screen.dart`는 **P-5와 공유** → 인접 실행. TTL은 기존 재서명 TTL(예 1h)보다 짧은 여유값 사용.
- **검증/DoD:** 동일 첨부 반복 표시 시 재서명 1회. 만료 후 자동 재서명. `flutter analyze` 0.

### P-8 · P3-7 — 웹브리지 도메인 확정 + 딥링크/복귀 검증
- **대상:** `lib/core/web_bridge/web_bridge_config.dart` (`baseUrl` defaultValue line 16–19).
- **재개 게이트:** 코드 게이트는 없으나 **웹 운영 도메인 확정·배포 타이밍**에 의존(아래 주의).
- **문제:** 현재 defaultValue = `https://ssambership-web.vercel.app`. 마스터 문서는 운영 도메인 `ssambership.com` 지향.
- **지시(단계):**
  1. **운영 도메인이 `ssambership.com`으로 확정·배포되었는지 사용자/웹팀에 확인**한 뒤에만 defaultValue 교체.
     (확정 전에는 변경 금지 — 앱을 아직 안 뜬 도메인으로 가리키면 전 웹 흐름이 깨진다.)
  2. 교체 후 `billingManagePath` 등 실측 라우트가 새 도메인에서 유효한지 대조.
  3. 딥링크·로그인 복귀(웹→앱) 경로를 실기기에서 검증.
- **주의:** 이 항목만 **외부 확정 의존**이라 작업선 P 중 유일하게 "사용자 확인 후" 진행. 나머지 P는 즉시 가능.
- **검증/DoD:** 새 도메인으로 웹브리지 진입·복귀 정상(실기기). 라우트 404 없음.

---

## 3. 직렬 트랙 — 상세 지시서 (게이트 충족 전 착수 금지)

> 각 트랙은 **서버 계약이 staging에 배포되고, 그 계약이 병합된 커밋으로 RPC 이름·인자·에러코드를
> 확정받은 뒤에만** 착수한다. 서버 계약 확정 전 임의 RPC 시그니처로 코딩 금지(§0-2).

### 트랙 B · P1-8 + P2-19 — 질문방 원자 RPC 전환 (+ 첨부 보상)
- **대상 파일:** `question_room/data/question_room_write_repository.dart`,
  `question_room/data/attachments/attachment_upload.dart`,
  `question_room/ui/new_question_screen.dart`(P-1과 통합), `question_room/ui/chat_screen.dart`,
  `question_room/ui/mentor/mentor_answer_screen.dart`, 질문방 모델·오류 매핑.
- **재개 게이트 (staging 전부 확인):**
  1. 질문방 **원자 생성 RPC**(스레드+첫 메시지+주간/무료 사용량 소비) 배포.
  2. `append_question_message`(본문 append) 배포.
  3. 학생 확인 RPC(`answered→confirmed`) 배포.
  4. `register_question_attachment`(첨부 등록 + 멘토 첫 첨부 answered 전이) 배포.
  5. `question-room-attachments` 버킷 **Storage DELETE 정책** 신설(업로더가 미등록 객체만 삭제 가능).
  6. (서버) `question_attachments.storage_path` UNIQUE, `free_question_usage.thread_id` 반영은 서버 몫 —
     앱은 확정된 RPC 반환형·에러코드만 수용.
  ```sql
  -- 게이트 확인 예
  select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and proname = ANY(ARRAY['append_question_message','register_question_attachment']);
  select policyname,cmd from pg_policies where schemaname='storage' and tablename='objects'
   and policyname ilike '%qra%' and cmd='DELETE';
  ```
- **서버 계약에서 받아야 할 것:** 각 RPC의 정확한 **함수명·파라미터·반환형·구조화 오류코드**(SQLSTATE/메시지).
  마스터 문서의 `append_question_message`/`register_question_attachment`는 **자리표시 이름**일 수 있으므로
  실제 배포명으로 맞춘다.
- **앱 지시(순서 고정):**
  1. `question_room_write_repository.dart`의 **스레드 INSERT(`createThread`)+첫 메시지 INSERT(`appendMessage`)
     분리 호출을 원자 생성 RPC 하나로 교체.**
  2. 학생·멘토 **본문 메시지 직접 INSERT 제거 → `append_question_message` RPC만 사용**
     (`chat_screen.dart`·`mentor_answer_screen.dart` 공통).
  3. **`markThreadAnswered`(현 write repo line 94, `mentor_answer_screen.dart:199` 호출) 제거** —
     멘토 첫 메시지/첨부의 `answered` 전이는 서버 RPC가 수행. 앱은 status를 임의 UPDATE하지 않는다.
  4. 학생 확인은 전용 확인 RPC로만(`confirmThread` 직접 UPDATE 제거).
  5. **첨부 경로(P2-19):** `attachment_upload.dart`의 `question_attachments` **직접 INSERT를 제거**하고
     Storage 업로드 후 `register_question_attachment` RPC 호출로 전환.
  6. `chat_screen.dart`·`mentor_answer_screen.dart`의 `_uploadPending`을 **`Future<bool>` 또는 예외 재던지기**로
     변경(현재 `Future<void>`+오류 삼킴, `chat_screen.dart` line 217–223 `_uploadPending`, finally에서 무조건
     `_pending=null` line 208–214). **RPC 성공일 때만 pending 첨부 clear.**
  7. RPC 실패 시 **본인이 업로드한 미등록 객체만** 서버 DELETE 정책으로 정리. 보상 삭제까지 실패하면 원 오류와
     정리 실패를 **분리 기록**하고 사용자 재시도 허용. 메시지 본문 성공 + 첨부 실패를 **"전체 성공"으로 표시 금지**.
  8. **오류 UX 분리 매핑**(서버 구조화 오류 → 문구):
     한도 소진/무료권 만료 · 구독 환불 pending · 종료된 스레드 · 정지/차단 계정 · 미승인/비활성 멘토 ·
     재시도 가능 네트워크/DB 오류. 각기 다른 안내·행동으로.
  9. `new_question_screen.dart`는 P-1의 fail-closed를 유지하되, 생성 호출을 원자 RPC로 교체(신규 상태를
     클라가 지정하지 않음 — 서버가 `pending`).
- **주의:** 전환기 앱이 `open` 상태를 수신할 수 있으니 표시·후속대화는 유지하되 생성 상태를 클라가 지정하지 않는다.
  동일 객체 재시도가 같은 `storage_path`로 **중복 메타행을 만들지 않아야**(서버 UNIQUE 전제).
- **검증/DoD:** answered 이후 학생·멘토 후속 append 정상, `confirmed/closed/archived` append 거부 UX, 멘토 첫
  메시지/첨부만 answered 전이, 첨부-only 답변도 register RPC로 정상, RPC 실패 시 고아 객체 정리(정책 있을 때),
  중복 재시도 무중복. `flutter analyze` 0 + 질문방 테스트 갱신.

### 트랙 C · P1-11 + P2-15/16/17/18 — 알림·푸시
- **대상 파일:** `core/push/*`(이미 스캐폴드 존재: `push_trigger.dart`·`device_token_registrar.dart`·
  `push_service.dart`·`push_ports.dart`·`edge_function_push_sender.dart`·`push_payload.dart`·`push_types.dart`,
  참조 `core/push/HANDOFF.md`), `features/notifications/*`(`notifications_repository.dart`·`notifications_screen.dart`·
  `data/app_notification.dart`·`ui/widgets/notification_card.dart`),
  `features/mypage/data/notification_settings_repository.dart`, 딥링크 핸들러, `AndroidManifest.xml`,
  iOS entitlements, `pubspec.yaml`.
- **재개 게이트 (staging):** outbox 테이블 · `device_tokens` 테이블(+본인 토큰 RLS) · 토큰 등록/조회/폐기 RPC ·
  `notifications`의 `(recipient_user_id, event_key)` 복합 UNIQUE·정본 type · `user_notification_settings`(또는 정본 플래그) ·
  **전체 읽음 RPC**(P2-15). 정본 이벤트 17종 확정.
- **내부 순서(직렬):**
  1. **P1-11 토큰·수신:** 클라이언트 `PushTrigger` **폐기**(위조·중복·유실). `device_token_registrar`를
     서버 토큰 등록 RPC에 배선(로그인/계정전환/로그아웃 시 등록·폐기). FCM 수신(앱 종료 상태 포함).
     `AndroidManifest` POST_NOTIFICATIONS, iOS entitlement/aps-environment, `pubspec` FCM 의존 추가.
     payload의 event id로 **클라 중복 제거**(at-least-once 계약).
  2. **P2-15 인앱 조회:** `notifications_repository`를 **커서 페이징**으로. "모두 읽음"은 로드된 ID 반복 UPDATE가
     아니라 **서버 전체읽음 RPC 호출**.
  3. **P2-16 분류:** `app_notification.dart`의 `classifyNotificationType`(line 30–73)에 정본 type 도입 시
     `mentor_pause_notice`·`mentor_termination_notice` 두 유형을 **정본 매핑**으로 분류(현재는 키워드 방어분류라
     `other`로 숨겨질 수 있음 — line 42–48 'refund'/'order' 필터와 충돌 주의). **P1-11 enum 확정값과 함께** 교체.
  4. **P2-17 토글:** `notification_settings_repository`가 `users.notification_enabled`(또는 정본 테이블) **DB write**로.
     **SharedPreferences 자동 폴백 금지** — DB 저장 성공을 기준으로 UI 확정, 실패 시 재시도 오류.
  5. **P2-18 딥링크:** 허용 도메인·라우트 **화이트리스트** + 로그인 전 pending link 보관 + 임의 URL 차단.
     라우트는 P1-11 payload 규약과 일치시킨다.
- **주의:** type CHECK 정본화는 서버 단계적 전환(백필→양쪽 신매핑→관찰→레거시 컬럼 삭제)에 맞춰 앱 매핑 교체.
  **실기기 QA 필수**(토큰 등록·앱 종료 수신·중복 없음·딥링크 이동).
- **검증/DoD:** 실기기 토큰 등록·수신, 다중 수신자 이벤트 각자 1건, 커서 페이징·서버 전체읽음, pause/termination
  노출, 토글 DB 정본, 딥링크 화이트리스트 차단. `flutter analyze` 0.

### 트랙 D · P1-10 + P2-22 — 계정 라이프사이클
- **대상 파일:** `core/auth/account_status.dart`(line 72 status만), `features/auth/blocked_screen.dart`(line 39),
  탈퇴 진입 경로(앱은 삭제를 웹에 위임 — `web_bridge_config.accountDeletePath`), 세션/로그인 상태 처리.
- **재개 게이트 (staging):** `account_deletion_jobs` 테이블 + 상태 변경 SECURITY DEFINER RPC + 핵심 write RPC/RLS의
  deletion-state 게이트 + effective account status 응답 계약(P2-22).
- **내부 순서(직렬):**
  1. **P1-10 앱 측:** `locked`/`purging` 계정에서 서버가 write를 거부할 때의 **오류 처리·재로그인 UX**.
     세션 전역 폐기 후에는 "복원"이 아니라 **재로그인 요구**(취소 시 잠금·게이트 해제 후 재로그인). 부분 실패를
     "완료"로 표시 금지. (탈퇴 실행 로직 자체는 서버/웹 — 앱은 상태 수신·안내·재로그인.)
  2. **P2-22:** `account_status.dart`가 **서버 effective status**(suspended_until 등 포함)를 수신하도록 모델 교체.
     `blocked_screen.dart:39`에서 **role 조회 실패 + active**를 **재시도 가능 오류상태**로 분리(영구 차단으로 오인 금지).
- **주의:** `blocked_screen.dart`는 P1-10·P2-22 공유 → 한 트랙에서 순서대로. effective-status 계약이 확정되기
  전에는 모델 필드를 임의로 확정하지 않는다.
- **검증/DoD:** locked 계정 write 거부 시 재로그인 유도, role 실패+active가 재시도 오류로 표시.
  `flutter analyze` 0.

### 트랙 E · P1-12 — 게시판 댓글 어댑터
- **대상 파일:** 앱 게시판 댓글 read/write(`community/data/*` 중 comment 경로),
  `community/ui/board/board_detail_screen.dart`(차단 인자 line 165).
- **재개 게이트 (staging):** `community_comments(post_type='board')` → `comments` 브리지(백필·트리거) 배포 +
  **최소 앱 버전 강제 인프라**(서버 최소버전 응답).
- **내부 순서(직렬):**
  1. **모델 어댑터:** `community_comments`의 `body`/`status`/`post_type`를 canonical `comments`의
     `content`/`is_deleted`/`parent_id`로 변환하는 **read/write 어댑터** 구현(테이블명만 바꾸지 않는다).
  2. 앱 read/write를 board(→`comments` 어댑터) / shortform(→`community_comments`)로 **분리**.
     `board_detail_screen.dart:165`의 차단 인자를 `'comments'`로.
  3. **삭제 단방향:** soft-delete 정본에 맞춰 앱은 hard delete를 호출하지 않는다.
  4. **최소버전 게이트:** 서버 최소버전 응답 + 앱 시작 게이트로 구버전 legacy board 쓰기 차단(트랙 C/P1-8과 공유
     인프라). 게이트가 없으면 브리지 컷오버 착수 금지.
- **검증/DoD:** 웹·앱 게시판 댓글 합계 정합, soft-delete, 2depth, 숏폼(community_comments) 격리·무변경.
  `flutter analyze` 0.

### 트랙 F · P2-14b — 숏폼 스크랩
- **대상:** 숏폼 반응 경로(스크랩 버튼·리포지토리).
- **재개 게이트 (staging):** `shortform_reactions_type_check`가 `('like','scrap')`로 확장(서버 `130`).
  ```sql
  select pg_get_constraintdef(c.oid) from pg_constraint c join pg_class t on t.oid=c.conrelid
   where t.relname='shortform_reactions' and c.contype='c';
  ```
- **지시:** CHECK/RLS가 scrap을 허용한 뒤에만 앱 스크랩 토글 활성화(반응 type `'scrap'`). 실패는 재시도 오류.
- **검증/DoD:** 스크랩 on/off DB 반영, 미허용 시 버튼 비활성. `flutter analyze` 0.

### 트랙 G · P2-23 — 과목 FK 정책
- **대상:** `lib/data/mappings/subject_labels.dart` (line 146 `normalizeSubjectCode` 부근).
- **재개 게이트:** 서버가 아니라 **정책 결정** — 3안 중 택1 확정 필요(사용자/기획):
  (a) 정본 매핑 추가, (b) catalog 확장, (c) 자유과목 정책.
- **지시:** 결정 후 `normalizeSubjectCode(input) ?? input`로 **원본 보존**(미매핑 입력도 유실 없이 유지).
  카탈로그는 웹과 공유되므로 값 확정을 웹과 맞춘다.
- **검증/DoD:** 미매핑 과목 입력 시 유실 없음, 결정된 정책대로 표시. `flutter analyze` 0.

---

## 4. 권장 실행 순서 (재개 시)

```
0. staging 게이트 재확인(§0-3) — 각 트랙 대상 RPC/테이블/정책 실조회
1. 작업선 P (서버 무관, 즉시): P-1 → P-6 → P-2 → P-3 → P-4 → P-5 → P-7 → P-8
   (P-6를 P-2 앞에: compute 워커 재사용. P-4·P-5 인접(shortform_detail 공유). P-5·P-7 인접(iq_detail 공유).
    P-8은 웹 도메인 확정 후.)
2. 게이트 충족된 직렬 트랙만, 한 번에 하나씩:
   트랙 B(질문방) → 트랙 C(알림·푸시) → 트랙 D(계정) → 트랙 E(게시판) → 트랙 F(숏폼 스크랩)
   (상호 파일 disjoint라 순서는 게이트 배포 순서를 따라 조정 가능. 각 트랙 내부는 명시 순서 고정.)
3. 트랙 G(과목 정책)는 정책 결정 시점에 삽입.
```

## 5. 검증 한계 (환경)
- Flutter SDK/실기기 없음 → 앱 항목(특히 트랙 C/P1-11)은 **실기기 QA 필수**. 여기선 `flutter analyze`·단위테스트까지.
- 운영/staging Supabase는 **읽기 전용 대조만**. RPC/RLS/정책 배포는 서버 몫.
- **최소 앱 버전 강제 인프라는 저장소에 아직 없음**(트랙 B/C/E 공유 의존) → 별도 구축 후에야 구버전 차단·legacy
  거부가 성립.
- 서버 계약(RPC 이름·인자·반환형·에러코드)은 **병합 커밋으로 확정받은 뒤** 앱 타입에 반영(임의 확정 금지).
