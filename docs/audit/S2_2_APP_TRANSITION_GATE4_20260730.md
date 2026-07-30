# S2-2 앱 제품 전환 — M17 표면·F2~F6·Gate 4 로컬 검증 감사 (2026-07-30)

> 로컬 판정 전용(PASS_LOCAL 체계). 운영 DB·운영 Data API(D-API-A)·M16 적용·앱 배포는
> 이번 세션에서 어떤 것도 수행하지 않았다. 이 문서는 S2-2 앱 전환 지시의 종료 보고 증거 원본이다.

## 1. 기준점 하드게이트 실측

| 항목 | 값 |
|------|-----|
| 앱 base branch | `claude/app-contract-m13-resync-iu94hr` |
| 앱 base commit | `bc89de109b53c0500ab03208878085f0dce72abd` (parent `ad3def11e58be95321e151471623028babd577df`) |
| 원격 branch tip | 동일 commit (fetch 실측) |
| master 대비 | `b0ea4051…` 대비 12커밋 ahead / 0 behind / **제품 코드 diff 0**(계약·감사 문서 3건 1,414행 추가뿐 — diff --stat 실측) |
| 작업 브랜치 | `claude/s2-2-app-transition-m17-gate4-afw0ag` (부모 `bc89de10…` — 플랫폼 접미사 브랜치) |
| worktree | clean (수정 전 status --porcelain 0행) |

앱 계약 정본 정체성(sha256sum·wc 실측 — 전건 일치, `APP_TRANSITION_CANON_MISMATCH` 없음):

| 파일 | 행/바이트 | SHA-256 |
|------|-----------|---------|
| `docs/contracts/api_app_v1_contract_v1_1.md` | 996 / 97,839 | `dfd00111a657ad1f756b89cbc8df84238b7929693c5cba9d2944c28ef56e2fbd` |
| `docs/contracts/api_app_v1_contract_v1_0.md` | 382 / 19,814 | `59b37c42d5b4ca81e3cc2c775a4760396fa484299d99d3b78a179facd5ae6c77` |

웹 읽기 전용 정본(`byite-co/ssambership_web` branch `claude/s2-2-transition-w3-c7-c8-20260730`
commit `602cc53d74b4e36a94bdae239d4726efc325189b` — 전건 일치):

| 파일 | 실측 | SHA-256 |
|------|------|---------|
| `docs/contracts/api_web_v1_contract_v1_1.md` | 2,994행 / 329,690바이트 | `bd9fc0dd2802c8358bb09f2938e0de7248d8b60703794895708e300f8ef32fa6` |
| `supabase/sql/20260730112525_api_app_v1_surface.sql` (M17) | 332행 | `6b6134df59430e14dbb88a0160740bc846523fe3273ccdb4b262b51efb142637` |

**웹 저장소 변경 0건**(작업 종료 시 `git status --porcelain` 0행 실측).
**앱 저장소 `supabase/**` 변경 0건**(SQL migration 생성 0 — M17 정본 소유는 웹 저장소).

## 2. 수정 전 앱 호출부 인벤토리 (전수 검색 — 6분할 병렬 스윕 실측)

### 2.1 community_posts 직접 조작 (수정 전)

| 위치 | 조작 | 분류 |
|------|------|------|
| `community_read_repository.dart:61-76` `boards` | `.from('community_posts').select('*')` status=published | M17 View 읽기 전환 |
| `community_read_repository.dart:157-174` `myActivity` | 동 SELECT author_id=uid | M17 View 읽기 전환 |
| `community_read_repository.dart:176-184` `_postsByIds` | 동 SELECT id in(...) | M17 View 읽기 전환 |
| `user_blocks_repository.dart:132-154` `blockAuthorOf` | `.from(table)` 동적('community_posts' 리터럴은 board_detail_screen.dart:148 단일) author_id 점조회 | M17 View 읽기 전환 |
| `community_write_repository.dart:178-213` `createPost` | **직접 INSERT** — payload `{title, content, body, category, author_id, author_role, status:'published'}` (board_author_gate 경유) | F4 전환 |
| `community_write_repository.dart:199-211` + `board_author_gate.dart:113-134·183` | **hard DELETE 보상** `deleteOwnPostForCompensation` — `.delete().eq(id).eq(author_id).select('id')` + `verifyCompensationDeleteReturn` | **폐기 대상(DB hard DELETE)** |

- 직접 UPDATE·UPSERT: **0건**(수정 전에도 부재 — F5/F6 UI 자체가 없었음).
- 이미지 쓰기 경로: **0건**(`community-post-images` 문자열 lib/ 전체 0 — 게시판 작성은 텍스트 전용이었음). Storage 보상 삭제가 존재하는 기존 경로는 질문방 첨부(`attachment_upload.dart` — 이번 전환 무관·불변)뿐.
- Realtime: community 표면 구독 **0건**(앱 유일 Realtime 은 question_room `thread_realtime.dart`). 커뮤니티 신선도는 resume 재조회·PTR·상세 pop(true) 재조회 3경로.

### 2.2 질문방·기타 (수정 전)

| 위치 | 내용 | 분류 |
|------|------|------|
| `free_question_entry.dart:125-149` `fetch` | room SELECT(student_id=본인, mentor_id) + free_question_usage 사실값 카운트. 방 부재 → CTA 차단(roomMissing — 앱 생성 불가) | F2 전환 |
| `free_question_entry.dart:152-184` `createFreeThread` | `public.qna_create_free_question_thread` RPC | F3 전환 |
| `question_room_write_repository.dart:73-104` `createThread` | `public.qna_create_question_thread` RPC | F3 전환 |
| `mentor_student_rooms` INSERT·23505 수렴 | **0건**(방 생성 코드 부재 실측) | — |
| `community_write_repository.dart:111-156` `addComment` | board 댓글 `{post_id, author_id, content[, parent_id]}` 만 전송 — 라벨 미전송 | M13 대표 검증 대상(불변) |
| `community_screen.dart:127-135` 작성 FAB | 게시판 탭에서 **역할 무관 노출**(학생 포함) | CTA 멘토 전용 전환 |
| shortform 작성·재생 | 멘토 전용 WebView 작성기·별도 재생 경로 | 무변경 확인 |
| 멱등키 | 커뮤니티 경로 **0건**(IQ 경로에만 존재) | F4 멱등 도입 |

## 3. 수정 후 전환 그래프

```text
[읽기]
boards / myActivity / _postsByIds / blockAuthorOf('community_posts')
  → api_app_v1.community_posts_v1 (View SELECT 전용 — DML 0)
    · image_refs(text[]) 계약 필드 — BoardPost.imageRefs 신설
    · body = View 수렴값 · updated_at 원문 보존(updatedAtRaw — F5 낙관적 잠금용)
    · author_id 는 차단·본인 글 판정 전용(UI 비노출 — BoardPost.isMine)
    · 표시 시점 signed URL TTL 3600 · 메모리 캐시만(CommunityPostImageUrlResolver)
    · 레거시 signed URL ref → path 추출 재서명 · 파싱 불가 ref 는 해당 이미지만 숨김+구조화 로그

[명령]
BoardWriteScreen(멘토 전용 CTA) → CommunityWriteRepository.createPost
  → createBoardPostV1: 로컬 검증(MIME·magic bytes·5MiB·5장)
    → Storage 업로드({uid}/{uuid}-{safe}.{ext}, upsert=false)
    → api_app_v1.community_post_create(named: p_title, p_body, p_category,
       p_idempotency_key, p_image_refs, p_status) — author_* 미전송
    → envelope 해석(ok 없는 응답은 성공 아님)
    → 보상 4분기: ①업로드 실패=신규분 즉시 삭제 ②확정 실패(ok:false)=신규분 삭제
       ③불명확=DELETE 0회·동일 멱등키 1회 재호출(replay-first) ④성공/재생=유지
    → 불명확 지속 시 CommunityCreateUnclear — 화면이 같은 키 유지 재시도(새 키 금지)
BoardEditScreen → updatePost → api_app_v1.community_post_update
  (p_expected_updated_at = 실측 원문(NULL 포함) · UPDATE_CONFLICT 자동 덮어쓰기 금지
   · removed_image_refs 만 commit 후 best-effort 삭제 — 실패해도 성공 유지)
BoardDetailScreen(본인 글 메뉴) → softDeletePost → api_app_v1.community_post_soft_delete
  (hard delete 0 · already_deleted:true = 정상 성공 · purge 0)

FreeQuestionEntrySection(학생) → ensureRoom → api_app_v1.ensure_free_question_room(p_mentor_id)
  (학생 ID 미전송 · roomMissing CTA 차단 폐지 — 질문 시점 원자 확보 · 질문권 소비 없음)
  → compose → api_app_v1.qna_create_question_thread (F3 envelope — 소비는 F3 트랜잭션)
NewQuestionScreen(구독) → createThread → api_app_v1.qna_create_question_thread
  (envelope {ok:false, code} → 안정 코드 한글 매핑 · SUBSCRIPTION_REFUND_PENDING 포함
   · FREE_QUOTA_STUDENT_NOT_FOUND·ROLE_NOT_STUDENT·MENTOR_NOT_FOUND·ROOM_ENSURE_FAILED 추가)
```

**제거된 것**: `board_author_gate.dart` 파일 전체(작성자 정본 게이트 — F4 서버 도출로 대체) ·
`deleteOwnPostForCompensation`/`BoardPostCompensator`/`verifyCompensationDeleteReturn`
(**DB 게시글 hard DELETE 보상 — 전면 폐기**) · `community_posts` 직접 INSERT ·
학생 작성 CTA(작성 FAB 멘토 한정) · roomMissing CTA 차단 · public qna RPC 직접 호출
(fallback 미추가 — `qna_create_free_question_thread` 참조 0).

**유지된 것**: Storage 신규 이미지 보상 삭제(§6.3 4분기 — 신설 경로에 구현) ·
질문방 첨부 보상 파이프라인(무관·불변) · 댓글 최소 payload(라벨 미전송) ·
숏폼 작성·재생 경로 · 기존 학생 글 열람 · Realtime 부재 시 재조회 fallback
(resume·PTR·pop 3경로 — `community_surface_refresh_test` 전건 유지) ·
`increment_community_post_view` 등 기존 public 읽기 보조 RPC.

**직접 쓰기 0건 실측(수정 후)**: `grep -rn "from('community_posts')" lib/` → **0건**
(읽기 포함 전부 View·wrapper 경유). `deleteOwnPostForCompensation` 실코드 0건
(폐기 기록 주석 2건뿐). 금지 기능(`record_cash_topup`·`subscription_checkout_confirm`·
`account_deletion_request_self_consented`·`api_web_v1`) lib/ 참조 **0건**.
버전 번호·스토어 설정 변경 0건(`pubspec.yaml` version 불변).

## 4. D-API-A 로컬 게이트 (격리 스택 실측)

스택: PG 17.6(`supabase/postgres:17.6.1.008`) · **웹 clean-install 187/187 적용 성공**
(175 레거시 후보 C 순서 + S2 timestamp 12건 M0→M15→M1→M13→M4→M5→M6→M7→M17→M8→M14→M9,
각 파일 자가 게이트 포함 전건 통과) · GoTrue v2.177.0(마이그레이션 54건) ·
PostgREST v12.2.12(`db-schemas = public, api_web_v1, api_app_v1`) ·
Storage API v1.25.7 · nginx 게이트웨이(rest/auth/storage 단일 진입 — kong 상당).
운영·staging 데이터 반입 0. fixture: gotrue 실계정 6명(승인 멘토1·미승인 멘토1·학생3·관리자1).

로컬 baseline 환경 차이(W1~W3 선례와 동일 기록): ① 신규 클라우드 기본(auto-expose OFF —
public 스키마 default privilege 의 anon/authenticated/service_role 자동 부여 제거)을
적용 전에 재현 — M13·M17 자가 게이트의 전제 환경(CLI 2.110.0 과 동일) ② 라이브 platform
기본 grant 재현을 시험 구간에만 로컬 부여(community_posts·comments·community_comments·
users·mentor_student_rooms·free_question_usage·question_threads·question_messages·
post_reactions·mentor_profiles·mentor_plans·user_blocks·shortform_posts) 후 종료 시 회수 —
레포 migration 에 grant/revoke 없음.

| # | 검증 | 결과 |
|---|------|------|
| 1 | `api_app_v1.community_posts_v1` SELECT (authenticated) → 200 | PASS |
| 2 | wrapper 5종 authenticated 호출 가능(F2 envelope·F3 ROOM_NOT_FOUND·F4 TITLE_REQUIRED·F5/F6 POST_NOT_FOUND_OR_NOT_OWNED — 도달성+envelope 실측) | PASS |
| 3 | PUBLIC·anon 호출 거부(View SELECT·wrapper 호출 모두 42501) | PASS |
| 4 | `core_private` 직접 요청 → **PGRST106**(schema 비노출 오류) | PASS |
| 5 | 정상 요청 PGRST106·PGRST002 **0건** | PASS |
| 6 | M17 소유 객체 **정확히 7개**(schema 1 + view 1 + function 5 — pg census) | PASS |
| 7 | 구현부 복제 0 — `core_private` 공용 5종(B-1~B-4·F10) identity argument 정확 일치·각 1개(총 6번째 객체는 M9 소유 `record_cash_topup_impl` — 계약 §11.1 의 정상 F11 구현부이며 복제 아님) | PASS |
| 8 | 앱 저장소 SQL migration 생성 0건(`git status supabase/` 0행) | PASS |

**판정: `D_API_A_LOCAL: PASS` · `D_API_A_REMOTE: NOT_STARTED`**
(운영 Supabase Dashboard·Exposed schemas 는 미접촉 — 앱 계약 §3.1 순서 유지).

## 5. Gate 4 시나리오 (로컬 스택 — 앱 호출 경로 실측)

검증 방식 2층: ① 신규 계약 단위 테스트(가짜 주입 — 스택 불요, 상시 CI 실행)
② 라이브 스택 통합 테스트 `test/gate4/gate4_local_stack_test.dart`
(**실제 앱 리포지토리 클래스**로 스택 호출 — `GATE4_STACK_URL` 미설정 시 전건 skip 으로
일반 `flutter test` 의 DB 미접촉 유지). 라이브 실행 결과: **23/23 전건 PASS**.

### 질문방

| 시나리오 | 결과 |
|----------|------|
| 방 없는 학생 F2 성공 → 재호출 created:false·같은 room_id·방 1개 | PASS |
| 동일 pair **동시 F2 5회** → room_id 1종·행 1개(원자 확보) | PASS |
| F3 스레드 생성(envelope) — thread_id·path 반환 | PASS |
| F3 오류 envelope 안정 코드 한글 매핑(ROOM_NOT_FOUND 실측 · 무료 한도 소진 `FREE_QUOTA_MENTOR_EXHAUSTED` 는 반복 실행 중 실측 — '무료 질문권을 모두 사용했어요' 매핑 확인 · SUBSCRIPTION_REFUND_PENDING 매핑은 기존 유지+단위 고정) | PASS |
| F2 학생 전용 — 멘토 세션 거부 | PASS |
| F2 성공 시 로컬 질문권 차감 없음(소비는 F3 — 코드·테스트 고정) | PASS |

### 게시글·이미지

| 시나리오 | 결과 |
|----------|------|
| 승인 멘토 0장·1장·5장 작성 → View image_refs 정본 형식·signed URL(TTL 3600) 발급 | PASS |
| 학생 작성 거부 `ROLE_NOT_MENTOR` | PASS |
| 미승인 멘토 작성 거부 `MENTOR_NOT_APPROVED` (구분 문구 단위 고정) | PASS |
| 일반 관리자 작성 거부 `ROLE_NOT_MENTOR` | PASS |
| 타인 ref 공격 `IMAGE_NOT_OWNED`(기존 타인 객체는 보상 삭제 대상 아님 — 실존 유지 확인) | PASS |
| 비실존 ref `IMAGE_OBJECT_NOT_FOUND` | PASS |
| MIME(`application/pdf`)·5MiB 초과 업로드 — Storage bucket 2차 거부 | PASS |
| F5 정상 수정(실측 updated_at 원문 전달) → 반영 확인 | PASS |
| F5 stale `p_expected_updated_at` → `UPDATE_CONFLICT`(자동 덮어쓰기 0 — 단위·통합 이중 고정) | PASS |
| F6 soft-delete → View 제외·행 보존 / 재호출 `already_deleted:true` = 정상 성공 | PASS |
| 기존 학생 글(하네스 시드): 본인 F5 → `ROLE_NOT_MENTOR` 거부 · 본인 F6 허용 | PASS |
| 웹 이미지 글(api_web_v1 동명 wrapper 작성)이 앱 목록·상세 View 에 동일 형상 표시 + 학생 세션 서명 발급 | PASS |

### T-CONC-10 앱 표면 재검증 (M17 이중 확인 — canonical 소유 M7 불변)

```text
이미지 업로드 → F4 서버 commit 성공 → 응답 유실 모사(전송 계층 예외)
→ 재호출 전 Storage DELETE 0회 실측(기록 프록시 removeCalls == [])
→ 동일 멱등키 F4 재호출(호출 2회 — 두 호출 p_idempotency_key 동일 실측)
결과: 동일 post_id · idempotent_replay:true · 게시글 정확히 1건 ·
image_refs 불변(1건) · 참조 객체 전부 존재(서명 URL 발급 성공) ·
보상 삭제 0회(확정 미커밋 분기 전용 — 단위 테스트로 해당 분기도 별도 고정)
```

**PASS** — 재호출 선행·보상 삭제 후행 순서는 단위 테스트
(`community_post_actions_test.dart` — removesAtCall == [0,0])로도 고정했다.

### M13 대표 재검증 (앱 호출 경로 — canonical T-M13-01~16 소유는 웹 Batch B)

| # | 시나리오 | 결과 |
|---|----------|------|
| ① | 앱 board 댓글 작성 시 라벨 미전송 → 서버 트리거가 `users.nickname` 도출(author_label='학생하나'·author_role='student') | PASS |
| ② | spoof payload(구버전 모사 — author_label='해커라벨'·author_role='mentor' 포함 INSERT) → 서버 기준 덮어쓰기 | PASS |
| ③ | canonical(`comments`)/legacy(`community_comments` board) 표시 라벨 동일(163/164 브리지 행 실측) | PASS |
| ④ | shortform 댓글 무변경(트리거 미발화 — 라벨 = 컬럼 default, 닉네임 아님) | PASS |
| ⑤⑥ | `author_label` spoof UPDATE → `COMMENT_PROTECTED_FIELDS_IMMUTABLE` 명시 실패 + 값 불변(성공 no-op 위장 없음) | PASS |

### 잔여 검증

- Realtime 미수신 fallback: community Realtime 구독 0(불변) — resume·PTR·pop 재조회
  3경로 유지(`community_surface_refresh_test` 전건 통과). Realtime payload 를 View 행으로
  간주하는 코드 0(구독 자체 없음).
- fixture·Storage 객체 잔여 0: 검증 종료 후 fixture 데이터·`community-post-images` 객체·
  로컬 한정 grant·fixture 계정 전량 회수 실측(§7).

## 6. 정적·회귀 검증

| 항목 | 결과 |
|------|------|
| `flutter analyze` | **오류 0 · warning 0** (info 린트만 — CI 게이트 기준 비차단, 기존 유지) |
| `flutter test` (수정 전 기준선) | **915/915 전건 통과** (Flutter 3.44.8 stable) |
| `flutter test` (수정 후 전체) | **922 통과 + skip 1(gate4 환경 게이트 — GATE4_STACK_URL 미설정 시 의도된 skip), 실패 0** — 기준 915 대비 순증 +7. 기존 테스트 중 폐기는 `board_author_role_test.dart` 1파일뿐(직접 INSERT + hard DELETE 보상 계약 고정 테스트 — 전환으로 계약 자체가 소멸, 신규 F4 계약 테스트가 대체) |
| 신규 Gate 4 테스트 | 계약 단위 3파일(actions·envelope·images) + 위젯 갱신(멱등키 규약·CTA 멘토 전용·F2 확보 흐름) + 라이브 스택 23건(환경변수 게이트 — 미설정 시 skip 1로 계수) |
| Android debug build | **환경 차단(BLOCKED_BY_ENV)** — 컨테이너 egress 정책이 `dl.google.com` CONNECT 를 403 거부(실측)해 Android SDK 설치 자체가 불가(maven.google.com·services.gradle.org 는 도달 가능 — SDK 패키지 저장소만 차단). 코드 결함 아님 |
| 대체 컴파일 검증 | `flutter build web --release` **성공**(`✓ Built build/web` — dart2js 전체 프로그램 컴파일로 lib/ 전건 컴파일 성립 검증, 산출물 미커밋) |
| iOS build | 불가(Linux 컨테이너 — macOS 전용 toolchain) |
| `git diff --check` | **무결**(공백 오류 0) |

## 7. 종료 시 잔여 0 실측

```text
fixture 계정(@gate4.local)               : 0 (6명 전량 삭제)
community_posts / comments / community_comments : 0 / 0 / 0 행
mentor_student_rooms / free_question_usage      : 0 / 0 행
community-post-images 객체               : 0 개
로컬 한정 grant(authenticated 재현분)     : 0 (전량 REVOKE)
```

## 8. 최종 판정

```text
APP_M17_VIEW_TRANSITION: PASS_LOCAL
APP_GATE4_F2: PASS_LOCAL
APP_GATE4_F3: PASS_LOCAL
APP_GATE4_F4: PASS_LOCAL
APP_GATE4_F5: PASS_LOCAL
APP_GATE4_F6: PASS_LOCAL
APP_COMMUNITY_DIRECT_WRITE_ZERO: PASS
APP_DB_COMPENSATION_DELETE_REMOVED: PASS
APP_STORAGE_COMPENSATION_PRESERVED: PASS
APP_T_CONC_10_REPLAY_FIRST: PASS
APP_M13_REPRESENTATIVE: PASS_LOCAL
APP_FORBIDDEN_PAYMENT_FEATURES_ZERO: PASS
D_API_A_LOCAL: PASS
D_API_A_REMOTE: NOT_STARTED
APP_GATE_4_LOCAL: PASS
S2_2_APP_TRANSITION: COMPLETE
READY_FOR_C9_C10_FINALIZATION: YES
READY_FOR_S2_2_BATCH_F: NO
```

이번 완료는 앱 제품 코드와 Gate 4 의 **로컬 전환 완료**만 의미한다. 운영 D-API-A ·
운영 DB 적용 · M16(HD-1) · 앱 스토어 배포는 수행하지 않았고 이 문서가 완료를 주장하지 않는다.
