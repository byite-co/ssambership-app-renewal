# S3 통합 수동 QA 체크리스트 — IQ 첨부·첨삭·web_bridge (2026-07-07)

> 대상: 운영 Supabase(웹·앱 공유) + 운영 웹(https://ssambership-web.vercel.app) + 앱 실기기.
> 전제: RPC v2·버킷 `application/json` 허용은 운영 적용 완료(2026-07-07). 거부 경로(비당사자/미인증/anon)와
> RPC 정상 등록은 실서버 검증 완료 — 이 체크리스트는 **JWT가 필요한 스토리지 구간과 실기기 UX**를 검증한다.
> 실행 모드: `flutter run --dart-define=IQ_CREATE_ENABLED=true` (docs/MANUAL_QA_RUN_2026-07.md §0-2).
> 계정: 학생 1(질문 작성자) + 멘토 1(해당 질문의 지정/클레임 멘토) — 같은 질문의 당사자 쌍이어야 한다.

## A. IQ 첨부 업로드 (학생)

| ID | 단계 | 예상 결과 | 실패 시 확인할 로그 |
|---|---|---|---|
| A-1 | 학생 로그인 → 개별질문 상세 → 이미지 1장 첨부 업로드 | 업로드 성공, 목록에 즉시 표시. 내부 경로/uuid/영문 코드 미노출 | 앱: `flutter run` 콘솔의 AppError·StorageException. 서버: Supabase 대시보드 → Logs → **Storage**(POST /object 4xx — mime/경로), **Postgres**(RPC `add_individual_question_attachment` 예외: NOT_QUESTION_PARTY/STORAGE_PATH_MISMATCH 등) |
| A-2 | 같은 화면 재진입(목록 새로고침) | A-1 첨부가 유지 표시(행 등록 확인 — 업로드만 되고 행 누락이면 여기서 사라짐) | Supabase → Logs → Postgres(REST select individual_question_attachments) |
| A-3 | 5MB 초과 고해상 이미지 첨부 | 자동 축소 후 업로드 성공(최종 ≤5MB) | 앱 콘솔(downscale 로그) · Storage 로그(413/파일 제한) |

## B. 멘토 첨삭 — UPDATE 정책 실검증 (핵심)

| ID | 단계 | 예상 결과 | 실패 시 확인할 로그 |
|---|---|---|---|
| B-1 | 멘토 로그인 → 해당 질문 → A-1 첨부에 첨삭 → **1차 저장** | 평탄화 PNG가 '새 첨부'로 등록(원본 불변) + `{questionId}/annotations/{원본첨부id}.json` 생성. **json 업로드가 mime 거부되지 않아야 함**(이번에 허용 추가한 경로) | Storage 로그: `POST /object/individual-question-attachments/...annotations....json` 이 400(invalid_mime_type)이면 버킷 mime 재확인. RLS 거부면 42501 |
| B-2 | 같은 첨부에 이어 그리기 → **2차 저장** (필수 2회 이상) | 같은 json 경로에 upsert 성공 — **2차부터는 UPDATE 정책(`iqa_storage_update_party_annotations`) 경유**. 여기서 실패하면 UPDATE 정책 문제 | Storage 로그: PUT/upsert 요청의 403(row-level security). Postgres 로그: storage.objects UPDATE 거부 |
| B-3 | 3차 저장(선택 — 안정성) | 2차와 동일하게 성공 | 동일 |
| B-4 | 첨삭 후 원본 첨부 확인 | 원본 이미지 변화 없음(첨삭본은 별도 첨부로 추가) | 앱 화면 대조 |

## C. 학생 열람

| ID | 단계 | 예상 결과 | 실패 시 확인할 로그 |
|---|---|---|---|
| C-1 | 학생 계정으로 질문 재진입 | 멘토의 첨삭본(새 첨부)이 보임, 원본도 그대로 | Storage 로그(GET 403이면 read 정책), 앱 콘솔 |
| C-2 | 첨삭본 확대 열람 | 필기 선명(평탄화 PNG), 다운로드 에러 없음 | 앱 콘솔 StorageException(404/403) |

## D. web_bridge 주요 버튼 탭 (실기기)

> 비로그인 HTTP 랜딩은 10/10 확인 완료(404/500 없음). 실기기에서는 **외부 브라우저로 열리는지 + 로그인 후 목적 페이지 도달**을 본다.

| ID | 단계 | 예상 결과 | 실패 시 확인할 로그 |
|---|---|---|---|
| D-1 | 학생 마이페이지 → 구독/충전 진입 버튼 | 외부 브라우저로 `/subscribe`·`/wallet/charge` — 학생 로그인 → 로그인 후 해당 페이지(`next=` 유지) | 앱 콘솔(url_launcher 실패), Vercel → 프로젝트 ssambership-web → Logs |
| D-2 | 이용약관 / 개인정보 / 고객센터 행 | 각각 약관·방침·FAQ 페이지 즉시 표시(로그인 불요) | 동일 |
| D-3 | 회원 탈퇴 행 | `/account/delete` — 학생 로그인 후 탈퇴 페이지. **앱 안에서 삭제 UI가 뜨면 안 됨**(Commerce-Zero/웹 위임 규약) | 동일 |
| D-4 | 멘토 계정: 정산/프로필/리뷰 행 | `/mentor/payouts`·`/mentor/profile`·`/mentor/reviews` — 멘토 로그인 유도 후 도달 | 동일 |
| D-5 | (선택) `--dart-define=WEB_BASE_URL=` 빈 값 빌드 | 웹을 열지 않고 "웹에서 진행(준비 중)" 폴백 문구 | 앱 콘솔 |

## 기록 규약

- 실패 항목은 ID·기기·계정 역할·시각(KST)을 남기고, 위 로그 위치의 원문 에러(errcode 포함)를 그대로 첨부.
- Supabase 로그 진입: 대시보드 → 프로젝트(lbeqxarxothkmzqvpudy) → Logs → Storage / Postgres / Auth 탭, 시간 필터로 좁히기.
- B-2 실패 시 즉시 중단하고 보고(정책 이슈 — 재시도 불요). A-1 mime 실패도 동일.
