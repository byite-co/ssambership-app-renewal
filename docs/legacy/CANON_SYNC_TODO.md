# CANON_SYNC_TODO — 웹 정본 대비 앱 수정 작업 목록

> 목적: 웹 팀 정본 기준으로 현재 앱(C:\dev\ssambership_app) 차이를 대조한 **수정 작업 목록**.
> 이번 턴은 **대조·목록만.** 코드 수정 0(문서만). 색 토큰 미터치. 앱 폴더 밖 미변경.
> 갱신 기준일: 2026-07-02.

## ⚠️ 정본 문서 부재 안내 (재확인)

지정 정본 문서 **`쌤버십_앱정합_정본.md`·`WEB_DATA_CANON.md` 2개가 아직 `docs/`에 없다**
(Glob·PowerShell 재확인 — md 5개만 존재, 정본 2개 부재). 넣을 위치: **`C:\dev\ssambership_app\docs\`**.

문서가 도착할 때까지, 태스크 전제("정본 = 웹 실제 코드 기준 정답")에 따라 **① 이 태스크 본문에 명시된 정본 값**과
**② 내가 직접 읽은 웹 실제 소스코드**를 기준선으로 대조했다. 정본 .md 도착 시 값이 다르면 재조정한다.

**기준선으로 실제 읽은 웹 파일:**
`lib/subjects/subjectCatalog.ts` · `lib/qna/weeklyQuestionUsage.ts` · `lib/qna/questionThreadStatus.ts` ·
`lib/community/communityBoardConstants.ts`·`communityShortformConstants.ts` · `lib/subscribe/subscriptionDisplay.ts`

---

## ★ A1·A2 정본 재검증 (맨 앞) ★

### ✅ A1 (과목 코드) — 정본과 **정확히 일치. 통과. 수정 불필요.**
- 앱 `lib/data/mappings/subject_labels.dart` = **정확히 35개 엔트리**, 웹 `subjectCatalog.ts`와 code/label/parent **1:1**.
- 구조 확인(정본대로): **대분류 9개**(korean·english·math·korean_history·social·science·essay·career·etc) 중 **소분류를 갖는 대분류는 korean/math/social/science 4개만**.
  - korean(5): korean, korean_speech_writing, korean_language_media, korean_reading, korean_literature
  - english(1, 단일) · math(6): math, math_1, math_2, math_calculus, math_statistics, math_geometry
  - korean_history(1, 단일) · social(1+9): social + life_ethics/ethics_thought/korea_geo/world_geo/east_asia_history/world_history/economics/politics_law/culture
  - science(1+8): science + physics_1/chemistry_1/biology_1/earth_1/physics_2/chemistry_2/biology_2/earth_2
  - essay(1) · career(1) · etc(1)
- **빠진 code 0 / 다른 code 0 / 폐기 대상 제3어휘(`math_common`·`math_algebra`·구 `science_physics` 등) 잔존 0** — 전량 교체.
- 정규화(한글라벨 `수학`→`math`, 레거시 `화학`→`science`) = 웹 `LABEL_TO_CODE`/`LEGACY_LABEL_TO_CODE`와 동일.
- 저장 코드(`math`·`korean`…)가 `question_threads.subject`(웹 저장값)와 정합.

### ⚠️ A2 (주간 한도) — 계산·한도값·소비/집계 정의는 정본 정합. **표시 이원화·클라 폴백만 잔존.**
정본(본문+`weeklyQuestionUsage.ts`) 대비 항목별:
| 정본 규칙 | 앱 현재 | 일치? |
|---|---|---|
| 한도 limited4/standard9/**premium999** | RPC `limit`만 사용(재하드코딩 없음) | ✅ |
| 창 = 구독 `started_at` 앵커 **rolling 7일**(없으면 created_at) | RPC의 `week_start/week_end` 신뢰(앱이 직접 계산 안 함) | ✅(RPC 위임) |
| 소비시점 = 스레드 **작성(created_at)** | RPC 집계에 위임(앱 미계산) | ✅(위임) |
| 집계 상태 = pending/answered/confirmed/**closed/archived** | RPC 집계에 위임(앱 미계산) | ✅(위임) |
| "주 N개·잔여 X/N" 표시(멘토명 옆+목록) | 질문목록 화면(`question_list_screen.dart:134`)에 `remainingLabel` 표시 | △ 질문영역만 |
| — | **마이페이지 구독카드 잔여는 여전히 null**(`mypage_models.dart:65`, `subscription_summary.dart:57`) | ✗ 이원화 |
| RPC 실패 시 클라 폴백 재계산(`fetchWeeklyQuestionUsageWithFallback`) | **앱엔 폴백 없음** → RPC 실패 시 표시·게이팅 모두 없음(보수적 통과) | ✗ |

- **결론: A2의 값·정의·창 계산은 정본과 정합(RPC 위임).** 남은 건 (1) 마이페이지 잔여표시 연결, (2) RPC 실패 대비 클라 폴백, (3) RPC 존재 자체 확인(인프라).

---

## ★ 심각도 '높음' 요약

**정본 대비 새 '높음(데이터 오류·기능 깨짐)'은 0건.** (A1·D1 일치, A2 정본 위임 정합)
**유일한 조건부 리스크**: A2가 의존하는 DB RPC `get_weekly_question_usage`가 실제 존재·정상 동작해야 함(§2-c, **인프라 확인**). 없으면 앱은 한도 표시·게이팅 불가.

---

## 항목별 대조표
> 열: 정본 값 / 앱 현재 / 차이 / 심각도 / 수정 파일 / **작업 종류(앱만 vs 인프라)**

### 1. 과목 코드
| 정본 | 앱 현재 | 차이 | 심각도 | 파일 | 종류 |
|---|---|---|---|---|---|
| 35코드, 대분류9/소분류는 korean·math·social·science만 | 동일(35, 동일 구조) | **없음** | — | — | — |

### 2. 주간 한도
| 정본 | 앱 현재 | 차이 | 심각도 | 파일 | 종류 |
|---|---|---|---|---|---|
| 한도4/9/999·rolling7d(started_at)·소비=created_at·집계5상태 | RPC 위임(값·창·집계) | 없음 | — | — | — |
| (2-a) 잔여 마이페이지에도 표시 | 질문영역만, 마이페이지 null | 표시 이원화 | 중간 | `subscription_summary.dart`, `mypage_models.dart`, mypage 구독섹션 | **앱만** |
| (2-b) RPC 실패 시 클라 폴백 | 폴백 없음 | 빠짐 | 중간 | `weekly_question_usage.dart`, `question_room_read_repository.dart` | **앱만** |
| (2-c) 서버측 한도 강제 + RPC 존재 | RPC 위임(존재 미확인), 서버강제 없음 | 확인필요 | 중간(조건부) | (DB) `get_weekly_question_usage`, question_threads 트리거 | **인프라** |

### 3. 질문 폼
| 정본 | 앱 현재 | 차이 | 심각도 | 파일 | 종류 |
|---|---|---|---|---|---|
| 멘토과목 우선→없으면 전체 폴백→"선택 안 함"(빈값) 포함 | 동일(`restrictQuestionSubjectCodes` + '선택 안 함') | **없음** | — | — | — |

### 4. 커뮤니티 카테고리
| 정본 | 앱 현재 | 차이 | 심각도 | 파일 | 종류 |
|---|---|---|---|---|---|
| 저장 5종 study/school/career/college/free + `all`(UI전용, 미매칭시 free폴백) | 5종 동일 + '전체' 별도 부착 | **코드집합 일치** | 낮음 | (선택) `community_labels.dart` | 앱만 |
| 라벨 `study`='학습법', 노출 순서 | `study`='학습', 순서 상이 | 표현차 | 낮음 | `community_labels.dart` | 앱만 |
| 숏폼 저장 4종(free 없음) + all UI | 앱 숏폼 카테고리 필터 미도입 | 필터 없음(불일치 아님) | 중간(UX) | 숏폼 피드 뷰 | 앱만 |

### 5. 상태 enum
| 정본 | 앱 현재 | 차이 | 심각도 | 파일 | 종류 |
|---|---|---|---|---|---|
| **스레드 status**: pending/answered/confirmed/open/closed/archived | enum 6종 **정확 일치** + unknown 폴백 | 없음(표시 라벨 3단계 통일만 선택) | 낮음 | (선택) `thread_card.dart` | 앱만 |
| **구독 status**: pending/active/past_due/canceled/expired(+refunded/cancel_scheduled) 다분기 표시 | `isActive` **2종(구독중/만료)만**, 나머지 전부 '만료'로 뭉침 | 축약(past_due·해지예정·환불 구분 없음) | 중간(표시) | `mypage_models.dart:68`, `subscription_summary.dart:50` | 앱만(데이터는 인프라 제공) |

### 6. 기타
| 정본 | 앱 현재 | 차이 | 심각도 | 파일 | 종류 |
|---|---|---|---|---|---|
| 알림 딥링크: 역할·유형별 특정 방/스레드/주문 ID 라우팅 | 탭 전환만(ID 미전달, 골격) | 정밀도 낮음 | 중간 | `notifications_screen.dart`, `deep_link_service.dart` | **인프라+앱**(푸시 S7) |
| 구독 게이팅 = room 생성 단계(웹) | 앱은 room INSERT 불가(RLS), 질문 게이팅은 isActive+주간한도 | 게이팅 지점 상이 | 낮음(확인필요) | (DB) RLS/room 정책 | **인프라** |
| 공개 디렉터리 게이트(미인증·과목0 제외) | RPC 결과 그대로(클라 필터 없음) | 서버 위임 | 중간(조건부) | `mentor_directory_repository.dart` / (DB) RPC | **인프라**(or 앱 필터) |
| 댓글 등 계정활성 검사 | 미검사(상위 의존) | 빠짐 | 중간(조건부) | community 쓰기 경로 | 앱만(상태원천은 인프라) |

---

## 집계 (정본 대비 차이)
| 심각도 | 건수 | 항목 |
|---|---|---|
| **높음(데이터오류·깨짐)** | **0** | — (A1·D1 일치, A2 정합) |
| 중간(표시·조건부) | 7 | 2-a 마이페이지잔여, 2-b 클라폴백, 2-c RPC확인, 4-숏폼필터, 5-구독status, 6-딥링크, 6-디렉터리게이트, 6-계정활성 중 대표 |
| 낮음(지엽) | 4 | 4-라벨/순서, 5-스레드표시라벨, 6-게이팅지점 등 |
| **일치(수정 불필요)** | — | 1-과목, 2-값/창/집계, 3-질문폼, 4-코드집합, 5-스레드enum |

- 작업 종류별: **앱만 가능**(2-a·2-b·4·5-구독·계정활성 등) / **인프라 필요**(2-c RPC·서버강제, 디렉터리 RPC, 딥링크 푸시, room 게이팅).

## 확인 필요 (정본 .md 또는 DB로 확정)
1. 정본 .md 2개를 `docs/`에 배치 → 위 기준선(웹 코드)과 값 대조 확정.
2. DB RPC `get_weekly_question_usage` 존재·반환·질문thread 트리거(§2-c).
3. `mentor_directory_list_v2` 서버필터, 딥링크 정본 스펙, room 게이팅 정책.

## 수정 우선순위(제안 — 별도 턴)
1. (조건부/인프라) 2-c RPC·서버강제 확인 → 없으면 2-b 앱 폴백 추가.
2. (앱만·중간) 2-a 마이페이지 잔여표시, 5 구독 상태 다분기.
3. (앱만·낮음) 4 community 라벨/순서, 5 스레드 상태 표시 통일.

---
_(끝) 이번 턴 코드 수정 0. 정본 .md 부재로 태스크 본문 명시값 + 웹 실제 코드를 기준선으로 한 잠정 대조이며, 문서 도착 시 재조정한다._
