# 쌤버십 앱 인수인계 문서

> 이 문서 하나만 읽으면 남은 **설정·연결·출시**를 이어받을 수 있도록 정리했습니다.
> 비개발자도 이해할 수 있게 "무엇을/왜/어디에" 순서로 쓰되, 개발자용 **정확한 파일 경로·상수명**을 병기합니다.
> 코드에서 실제로 확인한 값만 적었고, 확인 못 한 항목은 **(확인 필요)** 로 표시했습니다.
> (기존 `lib/core/push/HANDOFF.md` 의 내용은 이 문서 3-4)에 흡수·통합했습니다. 원본 파일은 상세 참고용으로 남겨둡니다.)

---

## 1. 개요

- **무엇**: 기존 웹(Next.js, `ssambership_web`, 별도 저장소)의 **컴패니언 모바일 앱**. Flutter 단일 코드베이스로 Android·iOS 동시 타깃. 구독형 멘토 Q&A(질문방) 중심.
- **핵심 원칙**
  - **Commerce-Zero**: 앱 안에서 결제·가격 입력·구매를 **하지 않는다**. 구독·충전·정산 등 돈이 오가는 동선은 **웹 페이지를 여는 것**으로만 처리한다.
  - **웹과 백엔드 공유**: 새 백엔드를 만들지 않고 **웹과 같은 Supabase 1개**를 읽기 중심으로 사용한다(RLS 의존).
    ★ 주의: Supabase 프로젝트명 **`ssambership-staging`(`lbeqxarxothkmzqvpudy`) 이 곧 실제 운영 DB(웹·앱 공용)** 다 — 이름만 보고 스테이징(버려도 되는 DB)으로 오판하지 말 것.
  - **색·디자인은 동업자 소관**: `lib/design/tokens/color_tokens.dart` 의 색 토큰은 **임시 placeholder hex**다. **통째로 갈아엎지 말고** 값만 확정해서 교체한다(구조·역할명 유지).
  - **표시 규칙**: 화면에 내부 DB명·UUID·이벤트 코드·딥링크 경로·영문 코드값 노출 금지(과목·상태 등은 한글 매핑 사용).
- **위치**: 앱 = `C:\dev\ssambership_app`. 웹 = 별도 저장소(README 기준 `ssambership_web`), **DB(Supabase)는 앱과 공유**.
- **완성 현황**: 하단 **5탭 전부** 구현(질문방·커뮤니티·멘토찾기·알림·**개별질문** — 마이페이지는 하단 탭에서 빠져 **우측 상단 프로필 아이콘 push** 로 진입) + **필기·주석 시리즈(S13~S15·첨부 퀵윈·이미지 뷰어) 완료**(단, 연결노트 필기 S14 는 **제거됨** — docs/SCAN_INK_PLAN.md 참고) + **위젯/로직 테스트 250개 전부 통과**(실제 DB·네트워크 없이 mock/fake 주입). `flutter analyze lib/` 에러 0.
  - 참고: **전체 통과다.** 과거 한때 실패하던 12건(community·mypage 등)은 코드 결함이 아니라 **헤드리스 컨테이너의 셰이더 캐시 미워밍 아티팩트**(`ink_sparkle.frag`/`FragmentProgram.fromAsset` — "Unsupported runtime stages format version. Expected 2, got 0")로 판명됐고, **현재 해소되어 전부 통과**(Flutter 3.44.4 불변 상태에서 확인). (기존 "121개 전부 통과" 문구는 이 사실로 대체.)

---

## 2. 완성된 것 (S0~S12, 세션별)

| 세션 | 내용 |
|---|---|
| **S0** | Flutter 스캐폴드 — 모듈 구조·라우팅(빈 5탭)·Supabase(로컬)·색토큰/상수/과목매핑 |
| **S1** | 디자인 시스템 공통 위젯 10종(AppCard·InitialAvatar·AppBadge·StatusPill·Primary/SecondaryButton·ChipScroll·EmptyState 등) + dev 위젯 갤러리 |
| **S2** | 이메일 로그인·세션·역할(student/mentor/admin/guest)·계정상태 분기 + 게스트 둘러보기(커뮤니티·멘토찾기) + 마이페이지 로그아웃/사용자정보 |
| **S3** | 질문방 데이터 계층(모델·레포·RLS 검증) — 실제 스키마 기준 |
| **S4** | 학생 질문방 화면(목록→멘토방홈→질문영역→채팅→연결노트), 상태 라벨 웹 기준 |
| **S5** | 멘토 질문방 화면(학생목록→학생방홈→질문목록탭→답변→연결노트) |
| **S6** | 질문방 실시간·이미지첨부·연결노트 저장(인프라 있으면 연결, 없으면 골격+인수인계) |
| **S7** | 푸시 인프라 클라이언트 골격(Firebase·서버는 인수인계) |
| **S8** | 알림 센터(목록·읽음·유형필터·딥링크, CR/환불 제외) |
| **S9** | 커뮤니티 열람·댓글(숏폼/게시판/내활동, 작성은 웹) |
| **S10** | 멘토 찾기(열람·상세, 구독은 웹브릿지) |
| **S11** | 마이페이지 보강(구독현황·캐시조회·설정, 결제는 웹) |
| **S12** | 웹 브릿지 통일(구독·충전·결제관리 동선, URL 상수화 — 미확정 시 안내 폴백) |

> 모두 로컬 `master` 에 커밋됨. **원격(remote) 저장소는 아직 없음** — 백업/공유하려면 remote 추가 후 push 필요.

---

## 2-B. 필기·주석 시리즈 (S13~S15 + 첨부 퀵윈)

연결노트 필기와 첨부 이미지 주석 기능. 모두 `master` squash 머지 완료.

| 세션 | 커밋 | 내용 |
|---|---|---|
| **S13** 공유 잉크 코어 | `2cdb650` | `lib/core/ink/` 5모듈(입력모드·문서봉투 `InkDocument`·좌표정합 `InkCoordinateMapper`·Storage 경로·scribble 어댑터). `scribble ^0.10.0+1` 도입 |
| **S14-1** 필기 화면 | `b089e98` | `ink_note/` 풀스크린 필기 화면·캔버스·P0 툴바(펜/지우개·undo/redo·색 3·굵기 3·손가락 토글) — **제거됨**(연결노트 자유 캔버스 필기는 오구현 판단, docs/SCAN_INK_PLAN.md 참고). 공용 `InkToolbar` 만 `lib/core/ink/widgets/` 로 이동해 S15 가 계속 사용 |
| **S14-2** 필기 저장 계층 | `8000006` | `ink_note_repository`(주입형 포트) + `ConnectionNote` 에 `inkPath`·`inkThumbPath` + 재편집 + 경로 규약 정합 수정 — **제거됨**(모듈 삭제. `connection_notes.ink_path/ink_thumb_path` 컬럼·모델 필드는 웹 호환 위해 유지, UI 미참조) |
| **첨부 퀵윈** | `c32d53f` | `attachment_upload` 버킷명 정정·경로 roomId 접두·`_storageReady=true` + `chat_screen`/`mentor_answer_screen` 배선 |
| **S15** 첨부 이미지 주석 | `20840dc` | `scan_annotation/` 4모듈(화면·flattener·sketch 헬퍼·repository). 진입점 = 채팅 입력바의 **전송 전 이미지 미리보기 '주석 달기'** |
| **S16** 스캔 소스 확장 | (feat/s16-scan-sources) | `lib/core/scan/` 신설 — `ScanSource`(촬영·갤러리·파일)·`ScanSourcePort`·`DeviceScanSourcePicker`(image_picker 품질85+장변4096캡, `file_picker ^11.0.2` 이미지 확장자만·PDF는 S19 폴백 안내)·`downscaleIfOversized`(5MB 초과 축소). 채팅·멘토답변 첨부가 소스 선택 시트 경유. `PickedImage` 는 core/scan 으로 이동(attachment_upload 가 re-export — 기존 경로 호환) |
| **S17** 개별질문 첨부 | (feat/s17-iq-attachments) | 기존 웹 스키마 재사용(`individual_question_attachments`·`individual-question-attachments` 버킷·당사자 RLS). 행 등록 RPC `add_individual_question_attachment` **초안만**(supabase/migrations/, 적용은 사람 승인 대기 → **2026-07-07 운영 적용·검증 완료**). `iq_attachments_repository`(업로드+RPC 한 메서드) + 작성 화면 첨부(최대 5장·부분 실패 재시도) + 상세 탭→뷰어. `downscaleIfOversized` 를 package:image JPEG(품질85) 재인코딩으로 교체(투명 PNG 만 PNG 유지) |
| **S18** 개별질문 첨삭 | (feat/s18-iq-annotation) | **앱 요구 DB 변경 0**(단, ink.json upsert 용 스토리지 UPDATE 정책 1건은 실서버 검토에서 발견돼 운영 적용 — 아래 저장 규약 표). `AnnotationTarget` 포트로 `ScanAnnotationScreen` 전송 대상 일반화(질문방 기본/IQ/로컬 캡처 — 옵션 추가만, 기존 호출부 무변경). 학생: 작성 화면 첨부 썸네일 '필기하기'(전송 전 로컬 첨삭 — 평탄화본이 첨부 대체, 원본+스트로크는 화면 생존 동안 보관해 이어 그리기). 멘토: 상세 '첨삭하기'(빨강 프리셋) — 완료 시 ① ink.json 을 첨부 버킷 `{questionId}/annotations/{원본첨부id}.json` 에 upsert(재편집용, **테이블 행 미등록**) ② 평탄화 PNG 를 새 첨부로 등록(원본 불변·덮어쓰기 금지). 같은 원본 재첨삭 시 이어 그리기 제안. 부수 수정: 상세 `_refresh` 의 setState-Future 버그(해결완료·환불 후 새로고침도 같은 경로) |
| **S19** PDF 스캔 | (feat/s19-pdf-scan) | **`pdfx ^2.9.2` 도입**(신규 의존성 — 3.44.4·기존 deps 충돌 없음, Android/iOS 네이티브 렌더). `lib/core/scan/pdf_rasterizer.dart`(포트+구현, 본렌더 장변 2560px — downscale 규약과 수렴) + `widgets/pdf_page_select_screen.dart`(지연 썸네일 그리드·다중 최대 5·선택 순번 배지) + `widgets/scan_pick_expander.dart`(소스 계층 공통: 이미지 1장/PDF 는 그리드, 1페이지 PDF 는 그리드 생략, 남은 슬롯 상한). 채팅·멘토 답변·IQ 작성 **자동 적용(화면별 분기 없음)**. S16 의 "PDF 곧 지원" 거부 → 실지원 전환('미지원 확장자' 일반 방어만 유지). 암호화·손상·0페이지 폴백 문구. **실기기 QA 실행 시트 신설(docs/MANUAL_QA_RUN_2026-07.md)** — 필기 시리즈(S13~S19) 마감 |

### 모듈 지도
```
lib/core/ink/                     ← 공유 코어(필기·주석 공통). 시그니처 변경 금지·추가만.
  ink_input_mode.dart               입력 모드(펜 전용/손가락 허용) 정책 단일 소스
  ink_document.dart                 문서 봉투(canvas·sketch·inputMode·updatedAt) + JSON 직렬화
  ink_coordinate_mapper.dart        ★ 이미지 기준 0..1 정규화 좌표 정합의 단일 소스
  ink_storage_paths.dart            버킷·경로 규약(연결노트 필기 / 스캔 주석)
  scribble_ink_adapter.dart         scribble 엔진 어댑터(생성/복원/내보내기/썸네일/입력모드)
  widgets/ink_toolbar.dart          공용 필기 툴바(구 ink_note 에서 이동 — S15 주석 화면이 사용)
(연결노트 필기 ink_note/(S14) 는 제거됨 — docs/SCAN_INK_PLAN.md 참고)
lib/features/scan_annotation/          ← 첨부 이미지 주석(S15, S18 에서 대상 포트화)
  scan_annotation_screen.dart · annotation_flattener.dart · annotation_sketch.dart · data/scan_annotation_repository.dart
  annotation_target.dart              ★ S18 전송 대상 포트(질문방 기본/로컬 캡처) — 화면은 대상을 모른다
lib/features/individual_question/data/
  iq_annotation_repository.dart       ← S18 IQ 첨삭(ink.json 저장/복원 + 새 첨부 등록 + IqAnnotationTarget)
```

### 저장 규약 (Supabase 실사 기준)
| 용도 | 버킷 | 경로 | 정책 요건 |
|---|---|---|---|
| 질문방 첨부 | `question-room-attachments` | `{roomId}/{threadId}/{ts}_{name}` | `user_is_room_party_for_qra_path` — **경로 첫 세그먼트 = room UUID** |
| ~~연결노트 필기 원본~~ | `connection-note-ink`(비공개) | `{roomId}/{authorId}/ink.json` | **deprecated — 신규 쓰기 중단**(기능 제거, docs/SCAN_INK_PLAN.md). 기존 객체 보존, 마이그레이션 불요 |
| ~~연결노트 필기 썸네일~~ | `connection-note-ink` | `{roomId}/{authorId}/thumb.png` | (동일 — deprecated) |
| 스캔 주석 원본(재편집용) | `scan-annotations` | `{roomId}/{attachmentId}/ink.json` | 방 참여자 insert/select/update, **첫 세그먼트=roomId** |
| 스캔 주석 평탄화 PNG | (기존 첨부 파이프라인으로 전송) | — | 첨부와 동일 규약 |
| 개별질문 첨부(S17) | `individual-question-attachments`(기존·웹 공유) | `{questionId}/{ts}-{salt}.{ext}` — **첫 세그먼트=질문 uuid** | 당사자 스토리지 RLS + 행 등록은 RPC `add_individual_question_attachment` 만(테이블 SELECT-only) |
| 개별질문 첨삭 원본(S18) | `individual-question-attachments`(**같은 버킷 — iq-annotations 신설 폐기**) | `{questionId}/annotations/{원본첨부id}.json` — 첫 세그먼트=질문 uuid | 당사자 RLS. 버킷 정책 구성(2026-07-07 운영 적용·검증): **SELECT/INSERT 당사자 전체 경로 · UPDATE 는 `annotations/` 프리픽스 한정**(`iqa_storage_update_party_annotations`, `supabase/migrations/20260707T1130_...` 기록) — ink.json 같은 경로 upsert 용이며 원본 첨부는 계속 덮어쓰기 불가(= 원본 불변 규약의 정책 레벨 근거). **attachments 테이블에 행 미등록**(표시용 첨부 아님 — 목록은 테이블 기준이라 자연히 숨겨진다) |

- `connection_notes` 에 `ink_path`·`ink_thumb_path`(nullable, 코멘트 포함) 컬럼 추가 — **웹 기존 코드 무영향**.
- 필기·주석 스트로크는 화면 픽셀이 아니라 **이미지 기준 0..1 정규화 좌표**로 저장(저장 직전 `InkCoordinateMapper` normalize, 복원 시 denormalize). 기기·줌과 무관하게 첨삭 위치가 보존된다.

### 재사용 원칙 (지뢰)
- **`lib/core/ink/` 의 기존 API 시그니처는 변경 금지 — 추가만 허용.** S14·S15 는 이 코어를 소비만 했다.
- **`InkToolbar`(현 위치 `lib/core/ink/widgets/ink_toolbar.dart`) 는 주석 화면에서 그대로 재사용** — 수정 시 하위호환 유지하며 옵션 추가만.
- **첨부 업로더(`SupabaseAttachmentUploader`)는 재구현 금지** — 주석 평탄화 PNG 전송도 이 기존 파이프라인을 호출한다.

### 잔여 (다음 작업)
- **실기기 QA 실행(에뮬레이터 불가)**: 스타일러스(필압·팜리젝션·좌표 정합)에 더해 S19 실 PDF 렌더 화질·대용량·암호화 폴백까지 — **실행 절차·빌드 명령·계정 준비가 docs/MANUAL_QA_RUN_2026-07.md 에 시트로 준비됨(필기 시리즈 S13~S19 마감 — 지금 실행).**
- **IQ 첨삭 메시지 연동(후속)**: 멘토 첨삭 새 첨부의 `p_message_id` 는 현재 null — 답변 메시지와 묶으려면 RPC 의 message_id 소유 검증 보강과 함께 진행.
- ~~이미지 뷰어(서명 URL) + 전송 후 주석 진입점~~ **✅ 완료(PR #8 `b1fb61a`)**: 채팅 말풍선 이미지 썸네일 + 전체화면 뷰어(줌·팬) + 뷰어에서 '주석 달기'로 전송된 이미지에 주석(S15 화면 재사용). 서명 URL은 `attachment_url_resolver.dart`(만료 1h·메모리 캐시).

---

## 3. 동업자가 할 일 (우선순위 순)

각 항목: **왜 / 어디에 무엇을 / 하면 무엇이 켜지나** + 실제 코드 위치.

### 3-1. 웹 URL — ✅ 운영 도메인 확정(2026-07)
- **확정**: `https://ssambership-web.vercel.app` 이 출시용 운영 웹 도메인이다. `lib/core/web_bridge/web_bridge_config.dart` 의 `baseUrl` 은 `String.fromEnvironment('WEB_BASE_URL', defaultValue: <운영 도메인>)` — **릴리즈 빌드는 주입 없이 그대로 동작**한다.
- **경로 상수(코드 실값, 2026-07 실측)**: `subscribePath='/subscribe'` · `rechargePath='/wallet/charge'` · **`billingManagePath='/subscriptions'`** · `payoutManagePath='/mentor/payouts'` · `profileEditPath='/mentor/profile'` + 정보/지원 경로 `termsPath='/legal/terms'` · `privacyPath='/legal/privacy'` · `supportPath='/support'` · `reviewsPath='/mentor/reviews'` · `accountDeletePath='/account/delete'`.
- **구조**: 서비스 `lib/core/web_bridge/web_bridge.dart`(`WebBridge`, launcher 주입 가능), 화면 헬퍼 `web_bridge_actions.dart`. 모든 화면이 이 헬퍼만 호출한다(중복 없음). 구매 유도 헬퍼(`openSubscribeWeb`/`openRechargeWeb`)는 컴플라이언스로 **호출부 없음**(관리·조회성 경로만 배선).
- **폴백 유지**: 빈 값 주입 시(`--dart-define=WEB_BASE_URL=`) `isConfigured=false` → "웹에서 진행(준비 중)" 안내 폴백이 그대로 동작한다.
- **(선택) 웹→앱 복귀 딥링크**: 결제 완료 후 앱 복귀 스킴은 미구현(핵심은 "웹 열기"까지). 필요 시 앱 스킴 등록(모바일 빌드) + 콜백 라우트 설계.

### 3-1-B. 컴파일 타임 스위치(dart-define) 3종 — 릴리즈 빌드는 주입 불필요
```bash
# 개별질문 '작성(캐시 예치)' 켜기 — dev/내부 테스트 전용 (A안, 2026-07 확정)
flutter run --dart-define=IQ_CREATE_ENABLED=true
flutter test --dart-define=IQ_CREATE_ENABLED=true   # on 상태 테스트

# 웹 브릿지를 스테이징/로컬 웹으로 오버라이드
flutter run --dart-define=WEB_BASE_URL=http://127.0.0.1:3000

# '구독 관리 (웹)' 링크 켜기 — dev 전용 (P0-3 옵션1, 2026-07 확정: 스토어 기본 off)
flutter run --dart-define=SUBS_MANAGE_LINK_ENABLED=true

# 스토어 제출(릴리즈): 아무것도 주입하지 않는다
#   = IQ 작성 off + 구독 관리 링크 off + 운영 도메인(전부 기본값).
#   게이트: docs/PLAY_STORE_REVIEW_PLAN.md
flutter build appbundle
```

**버전 규약**: `pubspec.yaml` 의 `version: x.y.z+N` — **스토어 업로드마다 `+N`(versionCode)을 반드시 1 이상 증가**시킨다(같은 versionCode 재업로드는 Play 가 거부). 표시 버전(x.y.z)은 의미 변경 시에만.

### 3-2. 이미지 첨부 — ✅ 연결 완료 (실사 정정)
- **정정(중요)**: 기존 HANDOFF의 "`question-attachments` 버킷 없음 → 오너 생성 필요"는 **오기**였다. Supabase 실사 결과 **실제 버킷 `question-room-attachments` 가 방 참여자 정책과 함께 이미 존재**했고, **첨부 퀵윈(`c32d53f`)으로 앱 연결을 완료**했다.
  - `attachment_upload.dart`: `bucket = 'question-room-attachments'`, `_storageReady = true`, 업로드 경로 **`{roomId}/{threadId}/{ts}_{name}`**(정책 `user_is_room_party_for_qra_path` — **첫 세그먼트 = room UUID** 요건 충족).
  - 이미지 선택기: `DeviceImagePicker`(image_picker 기반, `isAvailable=true`)가 이미 `chat_screen`·`mentor_answer_screen` 기본으로 주입됨.
- **동작**: 첨부 버튼 → 갤러리 선택 → 미리보기 → 업로드 + `question_attachments` 행 생성. (전송 전 미리보기에서 **'주석 달기'**(S15)로 진입 가능.)
- **✅ 이미지 뷰어 완료(PR #8)**: 채팅 말풍선에 이미지 썸네일 표시 + 탭 시 전체화면 뷰어(서명 URL, 줌·팬) + 뷰어 '주석 달기'로 전송된 이미지에 주석까지 연결됐다. (`attachment_url_resolver.dart`·`attachment_viewer_screen.dart`·`message_image_attachment.dart`.)
- **제약(고정)**: 업로드 제한 문구 `kAttachmentRestrictionText`(교재 PDF 등 저작권 자료 금지), 최대 5MB(`kMaxAttachmentBytes`), 이미지 형식만. `question_attachments` 컬럼: `thread_id·message_id·storage_path·file_name·mime_type`.

### 3-3. 실시간(Realtime) publication 확인
- **왜**: 채팅 실시간 구독 코드는 완성. Realtime **서비스는 가동 중**이나, 대상 테이블이 publication에 포함됐는지 미확인.
- **어디에 무엇을**: Supabase에서 `question_messages`·`question_threads` 가 **`supabase_realtime` publication에 포함**됐는지 확인/추가.
  - 구독 구현: `lib/features/question_room/data/thread_realtime.dart`(`SupabaseThreadRealtime`, `onPostgresChanges`).
- **하면**: 새 메시지·상태 변경이 **새로고침 없이 즉시** 반영. 미포함이어도 앱은 **폴백**으로 동작함 — 전송 후 재조회 + AppBar **새로고침 버튼**(`chat_screen.dart:_refresh` line 109 / 버튼 line 196, `mentor_answer_screen.dart` 동일).

### 3-4. 푸시 알림 (FCM) — 수신·토큰 등록 (상태: WAITING_EXTERNAL_FIREBASE_CONFIG)
- **원칙(2026-07-21 확정)**: **발송은 서버 outbox worker 단독**(`record_domain_notification` → `notification_outbox` → deliveries). **앱은 수신·토큰 등록만 담당** — FCM HTTP·Edge Function invoke 등 클라이언트 발송 경로는 **제거됐고 다시 만들지 말 것**(과거 `push_trigger.dart`/`edge_function_push_sender.dart` 삭제됨).
- **코드는 완료**(`lib/core/push/` + `lib/core/deeplink/`, 상세: `lib/core/push/HANDOFF.md`):
  - `firebase_core`/`firebase_messaging` 의존성 추가됨. `FirebasePushGateway` 가 **준비 경계** — Firebase 설정 파일이 없으면 초기화 실패를 삼키고 푸시만 조용히 비활성(앱은 정상 구동).
  - 토큰 수명주기: 로그인/세션 복원 시 RPC `register_device_token(p_token, p_platform)` 로 등록(서버가 ON CONFLICT 재소유 — 계정 전환은 재등록만), 토큰 회전 시 재등록, 로그아웃은 **signOut '이전'** 본인 행 `revoked_at` UPDATE(RPC `revoke_device_token` 은 권한 없음 — 호출 금지).
  - 수신 → 딥링크: 알림 '탭'(onMessageOpenedApp/getInitialMessage) → 정본 17종 `notificationDestinationOf` 의 **탭 이동만**(`TabNavigator.go`) — payload 의 link/url 은 무시. 중복 수신 dedup + 비로그인 pending(TTL 15분).
- **남은 외부 작업**(파일 날조 금지 — `lib/core/push/HANDOFF.md` 활성화 절차):
  1. `android/app/google-services.json` 배치 + `com.google.gms.google-services` gradle 플러그인 추가(json 없이 플러그인만 넣으면 빌드 깨짐 — 의도적 미적용).
  2. iOS(macOS): `GoogleService-Info.plist` + Push Notifications capability(aps-environment) + APNs 키 등록 + `pod install`.
  3. 실기기 검증(에뮬레이터는 FCM 제한).

### 3-5. 색·디자인 확정
- **왜**: 색 토큰 hex가 임시 placeholder. 화면 레이아웃/기능은 완성이나 최종 비주얼 미확정.
- **어디에 무엇을**: `lib/design/tokens/color_tokens.dart` — **역할명·구조는 유지**하고 hex만 확정값으로 교체(role: `page/surface/elevated`, `primary/secondary/muted`, `accent/accentMuted`, `success/warning/danger`, `border`). 단일 스카이 강조 + 시맨틱 유지. 필요 시 화면별 미세 조정.
- 레퍼런스: 토스 + 클래스101. **맞춤의뢰(CR)는 앱 범위 밖**이므로 관련 디자인 불필요.

### 3-6. 빌드·출시
- **pubspec.lock 은 커밋한다**(앱 저장소 표준 — 팀·CI·출시 빌드가 같은 의존성 해석을 재현. 2026-07-07 S19 에서 .gitignore 제외를 제거하고 정책 전환).
- **네이티브 폴더**: `android/`·`ios/` (현재 untracked 상태로 존재). 없거나 갱신 필요 시:
  `flutter create . --org com.ssambership --project-name ssambership_app --platforms=android,ios` (기존 `lib/`·`pubspec.yaml` 보존, 누락 폴더만 생성). 패키지 계약(2026-07-22 갱신): **Android** applicationId/namespace=`com.ssambership.edu` (Play 등록 package — 기존 `com.ssambership.app` 은 Play 요구로 `.edu` 로 수렴), **iOS** 번들ID=`com.ssambership.app` (이번 Android 작업에서 변경 없음). Firebase Android 앱 등록 시 package 는 반드시 `com.ssambership.edu`.
- **.env 원격 전환**(출시): 로컬 → 원격 production 값 교체(README 참조)
  `SUPABASE_URL=https://<project-ref>.supabase.co` / `SUPABASE_ANON_KEY=<remote-anon-key>`. 원격이면 플랫폼 분기 없이 그대로 사용.
- **Android**: 릴리스 빌드·서명 키·Play Store 등록. **iOS**: 번들ID·서명·App Store 등록.

---

## 4. 의도적으로 제외한 것 (버그 아님)

- **맞춤의뢰(CR)·관리자·회원가입 폼**: 앱 범위 밖(README 핵심 원칙 "제외, 흔적 없이"). 알림·통계·메뉴에서도 노출하지 않음(알림 유형 분류가 CR/환불을 `NotificationKind.other` 로 숨김 — `lib/features/notifications/data/app_notification.dart`).
- **개별질문(IQ)은 더 이상 제외가 아님** — 하단 5탭의 1급 기능으로 승격(§1 참고). `kIndividualQuestionEnabled`(노출)/`kIndividualQuestionCreateEnabled`(작성) 스위치 지배. 알림도 전용 종류(`NotificationKind.individualQuestion`)로 분류되어 개별질문 탭(`AppTab.individualQuestion`=4)으로 딥링크된다.
- **잔여 질문수(주간 문항수) 숫자 표기 보류**: 값 미확정(특히 프리미엄 FUP). 지금은 숫자 대신 **구독 상태**로 표기(날조 금지). 확정되면 `lib/shared/constants/plan_constants.dart` 의 `planWeeklyQuestionQuota`(현재 전부 `null`)·`planLabels`(현재 전부 `''`)·`planMonthlyPriceCash`(현재 `null`)를 채우면 활성. 구독 요약의 `remaining`도 현재 `null`(`lib/core/entitlement/subscription_summary.dart`).
- **관리자 계정**: 앱에서 접근 시 차단(`AccessState.blocked`) — 학생·멘토 전용.

---

## 5. 하지 말 것 (지뢰)

- **`color_tokens.dart` 통째 교체 금지** — 역할 구조 유지, hex 값만 확정 교체.
- **미확정 가격·URL 하드코딩(날조) 금지** — 값이 없으면 비우고 안내. `baseUrl`·요금제 값이 대표 예.
- **앱 안에 결제/구매/가격입력 화면 금지** — 모든 결제는 웹 브릿지(웹으로만).
- **메시지·첨부는 append 전용** — 수정/삭제 기능·컬럼 없음(DB·모델 모두). 새로 추가하지 말 것.
- **service_role 키를 앱/클라이언트에 넣지 말 것** — 앱은 anon key + RLS만. (검증용 조회도 서버측에서.)
- **웹 저장소(ssambership_web) 구조를 앱에서 복제/침범 금지** — DB만 공유, 로직은 각자.

---

## 6. 검증·실행

- **테스트**: `flutter test` → **250개 전부 통과**(실제 DB·네트워크 없이 mock/fake 주입). `flutter analyze lib/` 에러 0. 코드 변경 후 이 둘을 유지할 것.
  - 과거 한때 실패하던 12건은 헤드리스 컨테이너의 **셰이더 캐시 미워밍 아티팩트**(`ink_sparkle.frag`/`FragmentProgram.fromAsset`)로 판명됐고 **현재 해소되어 전부 통과**(Flutter 3.44.4 불변 상태 확인). 실기기/정상 렌더 환경에선 애초에 무관.
- **로컬 실행**: 웹 서버 모드 권장 — `flutter run -d web-server --web-port 5599` (`http://127.0.0.1:5599`). `-d chrome` 직접 구동은 이 환경에서 불안정하니 지양(URL을 브라우저에 직접 붙여 확인).
- **백엔드**: 개발은 **웹과 공유하는 로컬 Supabase**(`http://127.0.0.1:54321`). 앱 `.env` 의 `SUPABASE_URL` 이 웹 로컬 스택과 일치해야 함. URL은 플랫폼별 자동 분기(`lib/core/config/app_config.dart`: Android 에뮬 `10.0.2.2`, iOS/데스크탑 `127.0.0.1`, 실기기 `.env` `SUPABASE_URL_LAN`).
- **로컬 테스트 계정**: **웹 시드에 정의됨**(앱 저장소엔 계정 목록 없음 — **정확한 값은 웹 시드/`users` 테이블에서 확인 필요**). 시드 사용자 예: 학생/멘토(가격설정·가격미설정 멘토, 시드멘토1~16)·관리자. 관리자로는 앱 로그인이 **차단**된다(정상). 오너 제공 예시 계정(예: `local.student@…`, `local.mentor.priced@…`)의 정확한 주소·비밀번호는 웹 시드 기준으로 확인.
- **로컬 스키마 확인법**(참고): MCP로는 로컬 프로젝트가 안 잡히므로, PostgREST OpenAPI를 anon 키로 조회 — `GET http://127.0.0.1:54321/rest/v1/` (헤더 `apikey`/`Authorization: Bearer <anon>`). RLS로 가려진 표는 anon으로 개수/행이 안 보이는 게 정상(삭제 아님).

---

## 7. 프로젝트 구조

```
lib/
  app/        라우팅(router)·루트앱·홈셸(home_shell, 5탭)·진입가드(entry_guard)·탭이동(app_tabs=딥링크 채널)
  core/       supabase/ · config/(app_config) · auth/(AuthService·역할·계정상태) ·
              entitlement/(구독요약) · web_bridge/(★결제 동선 단일 소스) · push/(푸시 골격) · deeplink/
  design/     tokens/(color_tokens·typography) · widgets/(공통 10종)
  features/   auth/ onboarding/ question_room/ individual_question/ community/ mentors/ notifications/ mypage/ scan_annotation/(첨부 주석)
              (각 feature: data/ 모델·레포, ui/ 화면·위젯 — 한 파일에 안 몰기)
  shared/     constants/(app_constants·plan_constants) · format/(Formatters) · labels/ · errors/
  data/       mappings/(subject_labels 한글 매핑)
test/         위젯·로직 테스트(250개, DB 비의존). 폴더: data/ widgets/ screens/ notifications/ web_bridge/ mypage/ community/ push/ labels/ ink/ core_ink/ scan_annotation/
```

- **탭 딥링크**: 알림 등에서 `TabNavigator.go(AppTab.questionRoom|myPage|…)`(`lib/app/app_tabs.dart`) → `HomeShell` 이 수신해 탭 전환. (정확한 thread 딥링크가 아니라 관련 **탭 이동** — 필요 시 개선 여지. `mentors`/`mypage` 상단의 `TODO(S10/S11)` 라우트 주석은 탭이 이미 HomeShell에 연결돼 있어 **실제 변경 불필요**한 참고 표시임.)

---

### 인수인계 요약 (한 줄씩)
1. `web_bridge_config.dart` `baseUrl` 채우기 → 결제 동선 즉시 켜짐.
2. ✅ 이미지 첨부 **연결 완료**(버킷 `question-room-attachments` 실존 + `_storageReady=true` + `DeviceImagePicker`) — 첨부 퀵윈. **전송된 이미지 뷰어(서명 URL)·전송 후 주석 진입점도 완료(PR #8)**.
3. `supabase_realtime` publication에 질문 테이블 포함 → 실시간 켜짐(없어도 폴백 동작).
4. Firebase 설정 파일(google-services.json/GoogleService-Info.plist) + gradle 플러그인·APNs 만 채우면 푸시 수신 켜짐 — **발송은 서버 outbox worker 단독, 앱은 수신·토큰 등록만**(클라이언트 발송 경로 만들지 말 것).
5. `color_tokens.dart` hex 확정.
6. `.env` 원격 전환 + Android/iOS 빌드·서명·스토어 등록.
