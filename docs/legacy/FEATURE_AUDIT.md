# FEATURE_AUDIT — 웹(ssambership_web) ↔ 앱(ssambership_app) 기능 대조

> 목적: 웹의 실제 비즈니스 규칙과 앱을 대조해 "웹엔 있는데 앱엔 빠졌거나 다르게 동작하는" 기능을 목록화한다.
> 이 문서는 **감사 결과(목록)일 뿐 수정 지시가 아니다.** 코드 변경은 오너 판단 후 별도로 진행한다.
> 작성 기준일: 2026-07-02.

## 0. 감사 방법·범위·신뢰도

- **대조 방식**: 겹치는 5개 기능 영역(질문작성/질문방 · 멘토찾기 · 마이페이지/캐시/구독 · 커뮤니티 · 알림)만 대조.
  웹은 대규모(admin/mentor/student/public + CR/IQ 포함)이므로, 앱 범위와 겹치는 부분만 본다.
- **웹은 읽기 전용**으로만 열었다. 웹 파일 수정·생성·삭제 0, 비밀값(.env·service_role) 미열람·미출력.
- **앱도 이번 턴 코드 수정 0.** 이 문서 파일 1개만 생성.
- **근거 표기**: 각 항목에 웹/앱 파일 경로를 병기. 라인번호는 대조 시점 기준(근처 이동 가능).
- **신뢰도 구분**:
  - **[직접확인]** = 이 세션에서 내가 웹·앱 파일을 직접 읽어 확인 — 질문영역 전체(A1~A5), 멘토 앱측 로직, 설계제외 근거.
  - **[탐색확인]** = 읽기전용 탐색 에이전트가 웹·앱을 읽어 보고(파일경로 포함). 미검증 웹 파일이 일부 있어, 애매한 건 **확인필요**로 표기.
- **판단 보류/확인필요**: 앱이 서버(RPC/RLS)에 필터를 위임하는 경우, 앱 클라이언트 코드만으로는 규칙 유무를 단정할 수 없어 **확인필요**로 남겼다.

## 1. 심각도 집계 (차이 총 40건)

| 심각도 | 건수 | 의미 |
|---|---|---|
| 높음 | 3 | 핵심 규칙 위반·잘못된 데이터·정합성 깨짐 가능 |
| 중간 | 22 | UX 저하·정보 누락·검증 누락(일부 확인필요) |
| 낮음 | 15 | 지엽·표현 차이 |

> 이와 별개로 **설계상 제외**(버그 아님)는 §7에 분리했다. 위 집계에서 제외한다.

## 2. 심각도 '높음' 요약 (먼저 볼 것)

> 상태(2026-07-02): **A1 해결 · A2 부분해결(앱 계층) · D1 미해결(우선순위 낮음)**.

- **[A1] 질문 과목 선택지 필터 (오너 발견)** — ✅ **해결.** 앱이 방 멘토의 `teaching_subjects`로 과목 후보를 제한(빈 값이면 전체 폴백). 커밋 `f318308`.
- **[A2] 주간 질문 한도 강제** — ⚠️ **부분해결(앱 계층).** 앱이 질문 생성 직전 `get_weekly_question_usage` RPC로 검사·차단·잔여표시. 커밋 `dcdf9a1`. **★출시 후 필수 보강**: 이는 클라이언트 검사라 앱 우회 직접 INSERT는 못 막음 → **DB에 `question_threads` INSERT 트리거로 서버측 한도 강제 필요(백엔드/동업자 담당).**
- **[D1] 커뮤니티 게시판 카테고리 값 불일치** — 미해결. DB에 실데이터·CHECK 제약이 없어(확인 결과) 웹 상수를 표준으로 앱을 맞추는 방향. 우선순위 낮음, 별도 진행.

---

## 3. 질문작성 / 질문방  [직접확인]

### [A1] 질문 과목 선택지 = 멘토 지정 과목만 (플래그십, 오너 발견)  — ✅ 해결(커밋 `f318308`)
> **구현 요지**: `new_question_screen.dart`가 진입 시 `mentorTeachingSubjects(room.mentorId)`(mentor_profiles.teaching_subjects, 읽기전용)를 조회 → `restrictQuestionSubjectCodes()`(subject_labels.dart)로 앱이 아는 코드만 드롭다운 후보로 제한. 빈 값·미매핑·조회 실패 시 **전체 폴백**(빈 드롭다운 금지). DB 미변경. 단위 테스트 `test/data/subject_restrict_test.dart`.

- **웹**: 질문 작성 폼이 `props.subjectOptions`(그 방 멘토가 지정한 과목)만 후보로 보여주고, 없을 때만 전체 카탈로그로 폴백.
  근거: `components/qna/QuestionRoomStudentThreadForm.tsx:76-110` (주석 "★질문방 멘토가 지정한 과목만 후보로(없으면 전체 폴백)"), `components/qna/QuestionRoomStudentDesignWorkspace.tsx:856`(subjectChipsRoom 주입).
- **앱**: 과목 드롭다운을 `subjectLabels` **전체**로 채움(멘토 무관).
  근거: `lib/features/question_room/ui/new_question_screen.dart:100-105` (`for ... subjectLabels.entries`).
- **차이**: 다름(조건부 필터 규칙 누락) · **심각도: 높음** · **난이도: 보통**
- 비고: 앱 `NewQuestionScreen`은 현재 `Room`만 받고 멘토의 `teaching_subjects`를 갖고 있지 않음 → 방/멘토 과목을 화면까지 전달하는 경로 필요. **확인필요**: `mentor_student_rooms`/디렉터리에서 멘토 담당과목 조회 경로.

### [A2] 주간 질문 한도(tier별) 강제  — ⚠️ 부분해결: 앱 계층(커밋 `dcdf9a1`)
> **구현 요지**: `new_question_screen.dart`가 질문 INSERT '직전'에 `weeklyUsage(studentId, mentorId)` → RPC `get_weekly_question_usage`(읽기전용) 호출. `can_ask=false`면 생성 차단 + 담백한 문구(`WeeklyQuestionUsage.blockMessage`). 잔여는 `question_list_screen.dart` 질문바에 "이번 주 남은 질문 N개" 표시(프리미엄=‘질문 가능’). 한도 숫자(4/9/999)는 **재하드코딩하지 않고 RPC 반환값만** 사용. RPC 실패 시 판정 불가로 흐름을 막지 않음(보수적). 단위 테스트 `test/entitlement/weekly_question_usage_test.dart`.
>
> **★ 출시 후 필수 보강(백엔드/동업자 담당)**: 이 검사는 **클라이언트 검사**라 앱을 우회한 직접 INSERT는 못 막는다(현재 DB에 강제 트리거 없음 — 확인됨). 진짜 서버측 강제를 위해 **DB에 `question_threads` INSERT 트리거(또는 전용 RPC)로 주간 한도 강제**를 추가해야 한다. 이 앱 변경만으로는 우회 가능성이 남는다.

- **웹**: tier별 한도 limited=4 / standard=9 / premium=999. 스레드 생성 시 `canAsk` 확인 후 초과면 차단(`WEEKLY_QUESTION_LIMIT_MESSAGE`).
  근거: `lib/qna/weeklyQuestionUsage.ts:14-19`(limitForTier), `lib/qna/questionThreadSubscriptionGuard.ts`(assertThreadCreationSubscriptionAllowed → usage.canAsk).
- **앱**: `SubscriptionSummary.canAsk = isActive && (remaining==null || remaining>0)`인데 `remaining`은 **항상 null**로 세팅됨 → 사실상 `isActive`만으로 게이팅. 한도 개념 없음.
  근거: `lib/core/entitlement/subscription_summary.dart:26, 57`.
- **차이**: 단순화/빠짐(한도 미강제) · **심각도: 높음** · **난이도: 어려움**
- 비고: 앱은 `question_threads`에 직접 INSERT하고 "quota 검증은 이 레이어 책임 아님(서버)"이라 명시(`question_room_write_repository.dart:36-37`). **확인필요**: DB(RLS/트리거/RPC)가 주간 한도를 서버측에서 강제하는지. 강제하면 앱은 에러만 못 띄울 뿐 초과는 막힘. 미강제면 실질 우회 가능. (표시 보류는 §7 참고 — 의도적)

### [A3] 비구독자 무료 질문 1회 경로
- **웹**: 활성 구독이 없어도 학생이 **새 스레드**면 무료질문 허용/기록 후 통과.
  근거: `lib/qna/questionThreadSubscriptionGuard.ts`(active 없음 → `assertFreeQuestionAllowedAndRecord`), `lib/qna/freeQuestionUsage.ts`.
- **앱**: 비구독자는 질문 버튼 자체가 막힘("구독이 필요해요"). `canAsk`가 `isActive`를 요구.
  근거: `lib/features/question_room/ui/question_list_screen.dart:116-145`(_askBar), `subscription_summary.dart:26`.
- **차이**: 빠짐(앱이 더 제한적) · **심각도: 중간** · **난이도: 보통**
- **확인필요**: 무료질문 정책을 앱에도 노출할지 오너 정책 결정 필요.

### [A4] 단원·개념 메모(topic) 입력 필드
- **웹**: 과목과 별개로 `단원·개념 메모(topic)` 입력 제공.
  근거: `components/qna/QuestionRoomStudentThreadForm.tsx:115-126`.
- **앱**: 작성 화면에 topic 입력 없음. (쓰기 레포는 `topic` 파라미터를 지원하나 UI가 안 넘김.)
  근거: `lib/features/question_room/ui/new_question_screen.dart`(topic 미사용), `question_room_write_repository.dart:38-55`(topic 지원).
- **차이**: 빠짐 · **심각도: 중간** · **난이도: 쉬움**

### [A5] 제목 미입력 처리
- **웹**: 제목 비우면 서버가 "질문 N"(방 단위 순번) 자동 생성.
  근거: `components/qna/QuestionRoomStudentThreadForm.tsx:34, 146`.
- **앱**: 제목 null → 목록에서 "(제목 없음)"으로 표기.
  근거: `lib/features/question_room/ui/widgets/thread_card.dart:40-46`.
- **차이**: 다름 · **심각도: 낮음** · **난이도: 보통** (서버 자동번호 로직 확인필요)

---

## 4. 멘토찾기  [탐색확인 + 앱측 직접확인]

### [B1] 과목 필터 매칭(대분류→소분류)
- **웹**: 대분류 라벨 선택 시 소분류 라벨까지 부분일치로 매칭.
  근거: `lib/mentor/publicMentorsListQueries.ts:276-282`(subjectMatchesPreset).
- **앱**: 정확일치(`m.subjects.contains(_subject)`)만.
  근거: `lib/features/mentors/mentors_screen.dart:173-179`.
- **차이**: 다름 · **심각도: 중간** · **난이도: 보통**

### [B2] 정렬 옵션
- **웹**: 인기/리뷰/평점/응답시간/가격 등 다수.
  근거: `lib/mentor/mentorsListSearchParams.ts`.
- **앱**: 최신순·이름순 2종만(인기/추천순은 "공개 지표 없어 제외" 주석).
  근거: `lib/features/mentors/mentors_screen.dart:27, 208-211`.
- **차이**: 빠짐(일부 의도적) · **심각도: 중간** · **난이도: 보통**

### [B3] 공개 디렉터리 게이트(인증·과목0 제외)
- **웹**: 클라이언트단에서 인증 상태(approved/verified/active)와 담당과목 0개 멘토 제외를 명시.
  근거: `lib/mentor/publicMentorsListQueries.ts:584-594`.
- **앱**: `mentor_directory_list_v2` RPC 결과를 그대로 사용, 클라이언트 추가 필터 없음. 앱의 `isVerified`는 **배지 표시용**(schoolVerified || 'approved')일 뿐 목록 필터가 아님.
  근거: `lib/features/mentors/data/mentor_directory_repository.dart:28-41`, `mentor_models.dart:68-69`.
- **차이**: 확인필요 · **심각도: 중간(확인필요)** · **난이도: 쉬움~보통**
- **확인필요**: `mentor_directory_list_v2` RPC가 서버측에서 이미 동일 필터를 적용하는지. 적용하면 앱은 문제없음. 미적용이면 미인증·과목0 멘토가 앱 목록에 노출될 수 있음.

### [B4] 학교/학년/가격대/인증전용 필터
- **웹**: 학교(SKY 등)·학년(중등/고등/N수)·가격대·verifiedOnly 필터 제공.
  근거: `lib/mentor/mentorsListSearchParams.ts`, `publicMentorsListQueries.ts:284-339`.
- **앱**: 검색어 + 과목칩만. 위 필터 없음.
  근거: `lib/features/mentors/mentors_screen.dart`.
- **차이**: 빠짐 · **심각도: 중간~낮음** · **난이도: 어려움**

### [B5] 검색 대상 필드 범위
- **웹**: 이름·소개·과목·태그·대학·학과·학교·학년 등 다수 필드.
  근거: `lib/mentor/publicMentorsListQueries.ts:304-320`.
- **앱**: 이름·대학·학과·과목 4필드.
  근거: `lib/features/mentors/data/mentor_models.dart:149-161`(searchHaystack).
- **차이**: 다름 · **심각도: 낮음** · **난이도: 쉬움**

### [B6] 요금제 미확정 시 가격 표시
- **웹**: 활성 요금제 없으면 권장가(라이트 29,900 / 스탠다드 84,900 / 프리미엄 174,900 캐시) 표시.
  근거: `lib/subscribe/mentorPlanPricing.ts`(권장가 정본). (2026-07-24 QA4 갱신 — 구 55,000/114,900/249,900 표기는 2026-07-18 권장가 하향 개정으로 폐기)
- **앱**: 요금제 없으면 "요금제 문의"(가격 날조 금지 정책).
  근거: `lib/features/mentors/data/mentor_models.dart:142-147`.
- **차이**: 다름(**앱 의도적** — 미확정 가격 날조 금지, HANDOFF §5) · **심각도: 낮음~중간** · **난이도: 보통**
- 비고: 앱 정책이 명시적이므로 "버그"가 아니라 정책 차이. 오너 결정 사항.

---

## 5. 마이페이지 / 캐시 / 구독  [탐색확인]

### [C1] 잔여 질문수 표시
- **웹**: tier 한도 기반 "남은 N개" 표시.
  근거: `lib/qna/weeklyQuestionUsage.ts:14-19`, `lib/mypage/studentActiveSubscriptions.ts`(탐색).
- **앱**: `remaining` 항상 null → "구독 상태로 질문 가능/구독이 필요해요" 상태문구만.
  근거: `lib/core/entitlement/subscription_summary.dart:57`, `lib/features/mypage/ui/sections/student_subscription_section.dart:93-100`.
- **차이**: 빠짐 · **심각도: 중간** · **난이도: 어려움**
- 비고: **표시**는 HANDOFF §4상 의도적 보류(plan_constants 전부 null). 다만 [A2]의 한도 강제와 직결. §7 참고.

### [C2] 캐시 내역 유형 라벨
- **웹**: 15+ 상세 유형 라벨(구독결제/갱신/충전/환불승인/맞춤의뢰 결제/개별질문 지급 등).
  근거: `lib/cash/ledgerRowDisplay.ts`(탐색).
- **앱**: 부호 기반 2종("충전"/"사용")만.
  근거: `lib/features/mypage/data/mypage_models.dart:103-104`, `ui/sections/cash_section.dart:69`.
- **차이**: 다름 · **심각도: 중간** · **난이도: 보통**
- **확인필요**: 앱이 영문 reason 코드 비노출을 정책으로 함 → 한글 라벨 매핑 추가 여지.

### [C3] 구독 상태 분기
- **웹**: active/scheduled(만료예정)/pastDue(결제실패)/expired/cancelled/refunded 등 다분기.
  근거: `lib/subscribe/subscriptionDisplay.ts`(탐색).
- **앱**: "구독 중"/"구독 만료" 2종만(`status=='active'` 여부).
  근거: `lib/core/entitlement/subscription_summary.dart:50`, `lib/features/mypage/data/mypage_models.dart`.
- **차이**: 다름/단순화 · **심각도: 중간** · **난이도: 보통**

### [C4] 다음 갱신 정보(금액·자동갱신 상태)
- **웹**: 다음 결제 금액 + 날짜 + 자동갱신 중단 여부 표시.
  근거: `lib/subscribe/subscriptionDisplay.ts`, `lib/mypage/studentActiveSubscriptions.ts`(탐색).
- **앱**: 날짜만("다음 갱신 M/D"). 금액·상태 없음.
  근거: `lib/core/entitlement/subscription_summary.dart:55-56`, `ui/sections/student_subscription_section.dart:90-92`.
- **차이**: 다름 · **심각도: 중간** · **난이도: 어려움**

### [C5] 요금제 라벨 표시
- **웹**: tier 라벨 항상 표시.
  근거: `lib/subscribe/subscribePlanCatalog.ts`(탐색).
- **앱**: `planLabels` 비어 있어 배지 미표시(`if planLabel != null`).
  근거: `lib/shared/constants/plan_constants.dart`, `lib/features/mypage/data/mypage_models.dart:70-81`.
- **차이**: 빠짐(**의도적 보류** — 상수 채우면 자동 표시) · **심각도: 중간** · **난이도: 쉬움**

### [C6] 캐시 내역 조회 범위·필터
- **웹**: 기간/유형 필터 + 페이징 + 거래후 잔액.
  근거: `components/cash/WalletLedgerPageBody.tsx`, `lib/cash/ledgerRowDisplay.ts`(탐색).
- **앱**: 최근 5건 고정, 필터 없음(조회 전용).
  근거: `lib/features/mypage/data/mypage_repository.dart`(limit 5).
- **차이**: 다름(앱 조회전용 의도) · **심각도: 낮음** · **난이도: 보통**

### [C7] 표현 지엽차(잔액 문구·거래후 잔액·리셋 요일)
- 웹은 "현재 잔액 X캐시"·거래후 누적 잔액·요일 포함 날짜. 앱은 "X원"·거래후 잔액 없음·요일 미포함.
  근거: `lib/cash/cashQueries.ts`, `lib/cash/ledgerRowDisplay.ts`(탐색) ↔ `lib/features/mypage/format/cash_format.dart`, `ui/sections/cash_section.dart`.
- **차이**: 다름 · **심각도: 낮음** · **난이도: 쉬움~보통**

---

## 6. 커뮤니티  [탐색확인]

> 앱은 **열람·댓글·반응·신고·내활동**만 하고 **글/숏폼 작성은 웹 전용**(설계, §7). 아래는 앱이 실제로 하는 기능 안에서의 차이.

### [D1] 게시판 카테고리 값 불일치  — 미해결(우선순위 낮음, 별도 진행)
> **확인 결과(DB)**: `community_posts.category`에 실데이터·CHECK/enum 제약이 사실상 없음 → 특정 저장값이 강제되지 않음. 방향: **웹 상수(all/study/school/career/college)를 표준으로 앱 라벨/필터를 정렬**(앱의 `free`는 실사용 확인 후 정리). 데이터 위험이 낮아 A1·A2보다 후순위.
- **웹**: `all/study/school/career/college`.
  근거: `lib/community/communityBoardConstants.ts:1-8`.
- **앱**: `study/school/free/college/career`(웹의 `all`↔앱의 `free` 등 매핑 상이).
  근거: `lib/features/community/.../community_labels.dart:5-11`.
- **차이**: 불일치(정합성) · **심각도: 높음** · **난이도: 어려움**
- **확인필요**: DB에 실제 저장되는 category 코드가 무엇인지 대조 필요(앱/웹이 서로 다른 값을 쓰면 필터 누락).

### [D2] 목록 페이징 부재(성능)
- **웹**: 커서 페이징(pageSize 12).
  근거: `lib/community/communityBoardQueries.ts:170-222`.
- **앱**: 게시판/숏폼 전체 로드(페이징 없음).
  근거(탐색): `lib/features/community/data/community_read_repository.dart`(boards()/shortforms() 전량).
- **차이**: 빠짐(성능) · **심각도: 중간(데이터 많아지면 높음)** · **난이도: 어려움**

### [D3] 정렬 옵션(인기순)
- **웹**: latest/popular(좋아요·조회·댓글 가중).
  근거: `lib/community/communityBoardSort.ts`, `communityShortformQueries.ts:103-117`.
- **앱**: 최신순만.
  근거(탐색): `.../board_list_view.dart:32`, `shortform_feed_view.dart:28`.
- **차이**: 빠짐 · **심각도: 중간** · **난이도: 보통~어려움**

### [D4] 숏폼 카테고리 필터 부재
- **웹**: 카테고리 필터 있음. **앱**: 없음(전체 노출).
  근거: `lib/community/communityShortformConstants.ts` ↔ `.../shortform_feed_view.dart`.
- **차이**: 빠짐 · **심각도: 중간** · **난이도: 보통**

### [D5] 댓글 길이 상한 없음
- **웹**: 1~2000자.
  근거: `lib/community/communityBoardMutations.ts:137`.
- **앱**: 하한(1자)만, 상한 없음.
  근거(탐색): `.../board_detail_screen.dart:128-129`.
- **차이**: 검증 누락 · **심각도: 중간** · **난이도: 쉬움**

### [D6] 댓글 작성 시 계정활성 검사
- **웹**: `assertAccountActive()` 호출.
  근거: `lib/community/communityBoardActions.ts:178`.
- **앱**: 검사 없음.
  근거(탐색): `.../board_detail_screen.dart:132-137`.
- **차이**: 빠짐 · **심각도: 중간** · **난이도: 쉬움**
- **확인필요**: 앱이 차단계정 진입 자체를 상위(AccountStatus/RLS)에서 막는지.

### [D7] 조회수 집계
- **웹**: `incrementPostView`/`incrementShortformView` RPC 호출.
  근거: `lib/community/communityBoardMutations.ts:175-177`, `communityShortformQueries.ts:213-215`.
- **앱**: 호출 없음(집계 안 됨).
  근거(탐색): 앱 read 경로에 increment 없음.
- **차이**: 빠짐 · **심각도: 중간** · **난이도: 쉬움**

### [D8] 숏폼 반응(scrap) 불일치
- **웹**: 숏폼은 like만.
  근거: `lib/community/communityShortformMutations.ts:100-128`.
- **앱**: 숏폼에 like+scrap.
  근거(탐색): `.../community_write_repository.dart:54-75`.
- **차이**: 불일치(앱에만 scrap) · **심각도: 중간** · **난이도: 보통**
- **확인필요**: `shortform_reactions`에 scrap 저장이 유효한지(무효면 앱에서 실패/무의미).

### [D9] 숏폼 영상 재생 미구현
- **웹**: 실제 재생. **앱**: 썸네일 + 재생아이콘만(플레이어 미도입).
  근거(탐색): `.../shortform_detail_screen.dart:150`(주석 "실제 영상 재생 플러그인 없음").
- **차이**: 미구현 · **심각도: 중간** · **난이도: 어려움**
- 비고: 앱 주석상 알려진 골격 → 인수인계 성격.

### [D10] 신고 사유 세트·상세설명
- **웹**: 사유 세트 + 상세설명(최대 500자).
  근거: `lib/community/communityReportActions.ts:62`.
- **앱**: 사유만(웹과 사유 항목도 상이), 상세설명 없음.
  근거(탐색): `.../report_sheet.dart`.
- **차이**: 다름 · **심각도: 낮음** · **난이도: 쉬움**

### [D11] 지엽: 댓글 삭제/댓글 좋아요/게시판 멘토배지
- 웹은 댓글 소프트삭제·댓글 좋아요·작성자 역할 배지 제공. 앱은 댓글 삭제 없음, 댓글 좋아요 없음, 멘토배지는 숏폼에서만.
  근거(탐색): `communityBoardMutations.ts:161-173`, `communityBoardQueries.ts:42` ↔ `comment_tile.dart`, `shortform_detail_screen.dart:159-162`.
- **차이**: 빠짐/다름 · **심각도: 낮음** · **난이도: 쉬움~보통**

---

## 7. 알림  [탐색확인]

### [E1] 알림 유형 커버리지
- **웹**: 8종+ 유형별 배지(질문방·맞춤의뢰·구독결제·환불·공지/프로모·신고분쟁·리뷰·멘토활동).
  근거: `components/notifications/notificationTypeIcon.ts:27-48`.
- **앱**: 필터 칩 4개(전체·질문방·구독결제·개별질문) + 읽지않음. 환불·공지·리뷰 등 나머지는 '기타'로 표시(숨기지 않음). **맞춤의뢰 2종(new_order_message·new_application)은 CR 게이트 OFF로 앱 표면에서 exact type 제외**(DB 쿼리 단계, 서버 정본 17종 계약·발신은 불변).
  근거: `lib/features/notifications/data/app_notification.dart`, `notification_types.dart`(kGatedNotificationTypeCodes), `notifications_repository.dart`. (2026-07-24 QA4 갱신)
- **차이**: 단순화(의도적 출시 표면) · **심각도: 낮음** · **난이도: —**

### [E2] 딥링크 정밀도
- **웹**: 역할·유형별로 특정 방/스레드/주문 등 상세 경로 + ID 라우팅.
  근거: `lib/notifications/notificationDeepLink.ts`.
- **앱**: 탭 전환만(`subscription→마이페이지 탭`, 그 외→질문방 탭). ID·상세 미전달. `deep_link_service.dart`는 골격.
  근거: `lib/features/notifications/notifications_screen.dart:146-152`, `lib/core/deeplink/deep_link_service.dart`.
- **차이**: 단순화(인스코프 question_answered도 특정 방/스레드로 못 감) · **심각도: 중간~높음** · **난이도: 어려움**
- 비고: 푸시 인프라(S7) 인수인계와 직결. CR/IQ 딥링크는 설계 제외(§7).

### [E3] 유형 필터 탭 구성
- **웹**: 실제 존재하는 카테고리 동적 탭. **앱**: 고정(전체/질문방/구독결제 + 읽지않음).
  근거: `components/notifications/NotificationList.tsx` ↔ `notifications_screen.dart:180-205`.
- **차이**: 다름 · **심각도: 낮음** · **난이도: 보통**

### [E4] 지엽: 페이징 크기·뱃지색
- 웹 10건(모바일 5)/유형별 배지색 ↔ 앱 20건/단일 톤 배지. **심각도: 낮음**.
- 참고(차이 아님): "모두 읽음"은 **앱에만** 있고 웹엔 없음(앱이 우위).

---

## 8. 설계상 제외 (버그 아님 — 누락과 구분)

HANDOFF.md §4 / 웹 CLAUDE.md 잠금값 기준, 아래는 **의도적으로 뺀 것**이라 위 집계에서 제외한다.

- **맞춤의뢰(CR)**: 이번 출시에서 **게이트 OFF** — 앱은 CR 알림 2종(new_order_message·new_application)을 exact type 비교로 표시하지 않는다(부분 문자열 매칭 아님). 서버 producer·DB 정본 17종 enum·발신 계약은 그대로 유지하며, '서버 계약'과 '앱 출시 표면'은 서로 다른 개념이다. CR 필터·카테고리·딥링크는 미추가. (2026-07-24 QA4 갱신 — 구 "흔적 없이 제외" 서술 폐기)
- **개별질문(IQ)**: **앱 지원 기능** (2026-07-24 정정 — 구 "앱 범위 밖" 서술 폐기). 현재 앱은 목록·상세(학생·멘토 화면, 하단 5번째 탭)·멘토 답변·첨부(전용 버킷 + 서명 URL 재서명 캐시)·학생 환불·알림 라우팅(개별질문 탭 이동·필터 칩·설정 그룹 `개별질문 알림`)을 지원한다. 학생의 '새 개별질문 작성(캐시 예치)' 진입점만 스토어 결제정책 검토 완료까지 기본 off(`kIndividualQuestionCreateEnabled`, A안). 단 **캐시충전·결제·구독 시작은 웹 전용**이며 앱에 결제 경로를 추가하지 않는다.
- **관리자 콘솔·회원가입 폼**: 앱 미제공(관리자 로그인은 앱에서 차단).
- **앱 내 결제/가격입력/충전 실행**: 전부 웹 브릿지(Commerce-Zero). 구독·충전·정산·결제관리는 웹 URL 열기.
- **커뮤니티 작성** (2026-07-24 정정 — 구 "웹 전용(S9)·앱은 열람만" 서술 폐기): 게시판 글 작성은 **앱 네이티브 작성기를 유지**한다(제거·WebView 전환 금지). 숏폼 작성은 앱 인앱 WebView 브릿지(`/app/community/shortform/new` + `/app/bridge/complete`)를 사용한다. 정본: `docs/RELEASE_SCOPE_DECISIONS_2026-07.md` §3.
- **잔여 질문수(주간 문항수) 숫자 표기**: 값 미확정으로 **의도적 보류**(`plan_constants` 전부 null, 확정 시 활성). 지금은 상태 문구로 대체(날조 금지). (→ [C1]/[C5] 표시는 이 보류의 결과. 단 [A2] 한도 '강제'는 별개의 실질 차이)
- **메시지·첨부 수정/삭제**: append 전용(모델·DB 모두). 의도적.

---

## 9. '확인필요'(서버측 규칙 위임 등으로 앱 코드만으론 단정 불가)

1. **[A1]** 앱에서 멘토 담당과목 조회 경로(방/디렉터리) 존재 여부.
2. **[A2]** 주간 한도를 DB(RLS/트리거/RPC)가 서버측 강제하는지.
3. **[A3]** 무료질문 정책을 앱에도 열지(오너 정책).
4. **[B3]** `mentor_directory_list_v2` RPC의 서버측 인증·과목0 필터 여부.
5. **[B6]** 웹 기본가 표시 파일(`lib/subscribe/mentorPlanPricing.ts`) 정확 경로/라인 재확인.
6. **[D1]** DB 실제 저장 category 코드 값(웹·앱 정합).
7. **[D6]** 앱의 차단계정 진입 차단이 상위(AccountStatus/RLS)에서 되는지.
8. **[D8]** `shortform_reactions`의 scrap 저장 유효성.
9. **[E1]** 공지·리뷰·멘토활동 알림의 앱 노출 정책.

---

## 10. 오너 조치 우선순위(제안)

- **완료**: [A1] 과목 필터(✅), [A2] 주간 한도 앱-계층 검사(⚠️ 부분 — DB 트리거 보강은 출시 후 백엔드 담당).
- **먼저(높음, 남음)**: [A2] 서버측 강제(DB `question_threads` INSERT 트리거) 추가 — 백엔드/동업자. [D1] 커뮤니티 카테고리 정합(우선순위 낮음).
- **다음(중간·쉬움부터)**: [C5] 요금제 라벨 상수 채우기, [D5] 댓글 상한, [D6] 계정활성 검사, [D7] 조회수 RPC, [A4] topic 필드, [C2] 캐시 라벨.
- **정책 결정 필요**: [A3] 무료질문, [B6] 가격 기본값, [C1] 잔여수 표기(=plan_constants 확정), [E1] 알림 유형 확장, IQ 재검토.

---
_(끝) 이 문서는 대조 결과 목록이며, 어떤 코드도 이번 작업에서 변경하지 않았다._
