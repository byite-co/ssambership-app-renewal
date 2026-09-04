# DB_VERIFY_QUERIES — 높음 3건(A1·A2·D1) 구현 전 DB 확인 요청서

> 목적: 앱에서 A1(과목필터)·A2(주간한도)·D1(커뮤니티 카테고리)를 **정확히** 구현하기 전에,
> 클라우드 DB에서 반드시 확인해야 할 사실을 특정하고, **읽기 전용 SELECT 쿼리**로 만든 문서.
> 실행: **오너가 Supabase 대시보드(프로젝트 `ssambership-staging`)의 SQL Editor**에서 붙여넣어 실행.
> 작성 기준일: 2026-07-02. 근거는 웹/앱 코드에서 직접 확인한 것만.
>
> ## ⚠️ 안전
> - **이 문서의 모든 쿼리는 SELECT/조회 전용이다. INSERT·UPDATE·DELETE·DDL·ALTER 없음.**
> - 각 쿼리는 **데이터를 바꾸지 않는다**(카탈로그·행 조회만). 실수로 여러 번 돌려도 안전.
> - Claude Code는 DB에 직접 연결/쓰기를 하지 않았다. 실행은 오너가 한다.

---

## 한 줄 요약 (무엇을 확인하면 구현이 확정되나)

- **A1**: 멘토의 담당 과목이 `mentor_profiles.teaching_subjects`에 **어떤 형식(배열/CSV, 코드/한글)**으로 있고, `mentor_student_rooms`에서 멘토를 **어떤 컬럼**으로 참조하는지 → 확정되면 앱이 "방→멘토→과목"을 조회해 드롭다운을 그 과목으로 제한할 수 있다.
- **A2**: 주간 한도를 **DB(트리거/제약/INSERT용 RPC)가 강제하는가, 아니면 앱계층만 막는가** → 이 하나로 앱 수정 범위가 크게 갈린다(아래 별도 강조).
- **D1**: `community_posts.category`에 **실제로 저장된 코드 값**이 무엇인지 → 웹(all/study/school/career/college)과 앱(study/school/free/college/career) 중 어느 집합이 DB와 맞는지 확정.

---

## ★ A2가 왜 결정적인가 (앱 수정 범위가 여기서 갈림)

코드에서 확인한 사실:
- 웹은 질문 생성 시 **앱계층(Next 서버)** 에서만 한도를 검사한다:
  `lib/qna/questionRoomThreadService.ts:29-69`(`assertStudentCanCreateThread`) → 읽기전용 RPC `get_weekly_question_usage` 호출 → 초과면 **HTTP 429** 반환(`app/api/question-room/threads/route.ts`).
- 실제 INSERT는 **직접 테이블 insert**다(RPC 아님): `lib/qna/questionRoomMutations.ts`(`createQuestionThread` → `insertWithCandidates` → `supabase.from(table).insert(...)`).
- 앱(Flutter)도 `question_threads`에 **직접 INSERT**한다: `lib/features/question_room/data/question_room_write_repository.dart:38-55`(주석: "quota 검증은 이 레이어 책임 아님 — 서버").

→ 따라서 **INSERT 자체에 한도 검사가 없다.** 한도가 지켜지는 이유는 "웹 서버 코드가 INSERT 전에 막기 때문"일 뿐일 수 있다.

- **만약 DB에 한도 강제 장치(트리거/제약/전용 RPC)가 있으면** → 앱은 `get_weekly_question_usage`를 **읽어서 표시**하고, INSERT 실패(예외) 시 친절한 문구만 띄우면 된다. **수정 작음. 보안 구멍 없음.**
- **만약 DB 강제가 없고 앱계층(Next)만 막는 구조면** → 지금 **Flutter 직접 INSERT는 주간 한도를 완전히 우회**한다(구독만 활성이면 무제한 질문 가능). 이 경우:
  1. (최소) 앱이 INSERT 전에 `get_weekly_question_usage`를 호출해 `can_ask=false`면 막도록 구현(웹과 동일). **단 이는 클라이언트 검사라 우회 가능**.
  2. (권장) 오너가 DB에 트리거/전용 RPC로 **서버측 강제**를 추가 → 앱·웹 양쪽이 안전. (이건 DB 변경이라 이번 감사 범위 밖 — 오너 결정.)

**즉 A2-Q3(트리거 존재 여부) 결과가 "앱만 조금 고치면 됨" ↔ "DB까지 손대야 진짜 안전" 을 가른다.**

---

# A1. 질문 과목 필터 — 멘토 담당 과목의 위치·형식·참조 경로

## 왜 확인하나
- 웹 근거: `components/qna/QuestionRoomStudentThreadForm.tsx:76-110`(멘토 지정 과목만 후보) ← `roomSubjectChips`(`lib/qna/questionRoomStudentDisplay.ts:65-88`)가 **방의 멘토 프로필 과목**(`d.subjects || d.tags`, 없으면 room의 subject/subjects/topic/major)에서 뽑는다.
- 멘토 프로필 과목 필드 후보: `mentorDisplayFields.ts:80` = `["teaching_subjects","subjects","subject_list"]`.
- 앱 근거: `lib/features/question_room/ui/new_question_screen.dart:100-105`는 `subjectLabels` **전체**를 노출. 앱은 질문방에서 멘토 프로필(`mentor_profiles`)을 조회하지 않음.
- 확정해야 할 것: (1) `mentor_profiles`에 `teaching_subjects` 컬럼이 있고 그 **형식**(text[] vs CSV 문자열, 저장값이 코드 vs 한글). (2) `mentor_student_rooms`가 멘토를 참조하는 **컬럼명**(`mentor_id` 추정). (3) 방→멘토→과목 조인이 실제로 값을 돌려주는지.

### A1-Q1 — mentor_profiles 컬럼 확인 *(읽기 전용 — 데이터 안 바뀜)*
```sql
select column_name, data_type, udt_name, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'mentor_profiles'
order by ordinal_position;
```

### A1-Q2 — mentor_student_rooms 컬럼 확인(멘토 참조 컬럼) *(읽기 전용 — 데이터 안 바뀜)*
```sql
select column_name, data_type, udt_name, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'mentor_student_rooms'
order by ordinal_position;
```

### A1-Q3 — teaching_subjects 실제 값·형식 샘플 *(읽기 전용 — 데이터 안 바뀜)*
```sql
select user_id,
       teaching_subjects,
       pg_typeof(teaching_subjects) as subjects_type
from public.mentor_profiles
where teaching_subjects is not null
limit 20;
```

### A1-Q4 — 방→멘토→과목 조인이 값을 돌려주는지(구현 경로 증명) *(읽기 전용 — 데이터 안 바뀜)*
> A1-Q2에서 멘토 참조 컬럼이 `mentor_id`가 아니면 아래 `r.mentor_id`를 그 컬럼명으로 바꿔서 실행.
```sql
select r.id as room_id,
       r.mentor_id,
       p.teaching_subjects
from public.mentor_student_rooms r
left join public.mentor_profiles p on p.user_id = r.mentor_id
limit 20;
```

### A1-Q5 — (선택) 과목 정본 테이블 존재 여부 *(읽기 전용 — 데이터 안 바뀜)*
> 웹은 `lib/subjects/subjectCatalog.ts`(코드 모듈)로 코드↔라벨을 관리. DB에 별도 과목 테이블이 있는지 확인(있으면 앱도 그걸 재사용 가능).
```sql
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('subjects', 'subject_catalog', 'question_subjects');
```

## 결과 → 구현 분기 (A1)
- **teaching_subjects 존재 + text[](배열)** 이고 값이 **코드**(예: `math_calculus`) → 앱: 방의 `mentor_id`로 `mentor_profiles.teaching_subjects` 조회 → 그 코드들만 드롭다운에 노출(코드→한글은 기존 `subject_labels`로). 드롭다운을 전체가 아닌 이 목록으로 교체.
- **teaching_subjects가 CSV 문자열**(예: `"수학,영어"`) → 앱: 콤마 분리 후 각 토큰을 `subject_labels`의 **라벨/코드와 매칭**해 후보 구성(웹 `mentorSubjectChips`와 동일한 라벨 기반 처리). 저장값이 **한글 라벨**이면 라벨 그대로 표시하고 전송 시 코드로 정규화.
- **teaching_subjects가 비어있는 멘토가 많음** → 웹처럼 **전체 폴백**(과목 미지정 허용) 유지가 안전. "멘토가 과목 지정 시 제한, 아니면 전체" 규칙으로 구현.
- **A1-Q2에 멘토 참조 컬럼이 `mentor_id`가 아님**(예: `mentor_user_id`) → 앱 조회 쿼리도 그 컬럼명으로. (앱은 현재 `mentor_student_rooms`를 `select('*')`로 읽으므로 컬럼명만 맞추면 됨.)
- **A1-Q4가 항상 빈 teaching_subjects** → **확인필요**: 멘토 과목이 다른 소스(디렉터리 RPC `mentor_profiles_for_directory_v2` 등)에만 채워지는지. 그렇다면 앱은 그 RPC 경로로 과목을 받아야 함.

---

# A2. 주간 질문 한도 — DB 강제 vs 앱계층 강제

## 왜 확인하나
- 위 "★ A2가 왜 결정적인가" 참조. 핵심은 **INSERT에 한도 강제가 붙어있는가**다.
- 웹 근거: `lib/qna/questionRoomThreadService.ts:29-69`(앱계층 검사), `lib/qna/weeklyQuestionUsage.ts:111`(RPC `get_weekly_question_usage` 호출, 읽기전용), `weeklyQuestionUsage.ts:14-19`(코드 폴백 상수 limited=4/standard=9/premium=999 — **1차 소스는 RPC의 `limit`**).
- 앱 근거: `lib/features/question_room/data/question_room_write_repository.dart:38-55`(직접 INSERT, quota 검증 없음), `lib/core/entitlement/subscription_summary.dart:26,57`(`remaining` 항상 null → `isActive`만 게이팅).

### A2-Q1 — get_weekly_question_usage 함수 존재/시그니처 *(읽기 전용 — 데이터 안 바뀜)*
```sql
select n.nspname as schema,
       p.proname  as function,
       pg_get_function_identity_arguments(p.oid) as args,
       pg_get_function_result(p.oid) as returns
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where p.proname ilike '%weekly_question_usage%';
```

### A2-Q2 — 그 함수의 전체 정의(한도값·집계 상태 확인) *(읽기 전용 — 데이터 안 바뀜)*
> 함수 안에 tier별 한도(4/9/999)와 "무엇을 카운트하는지(pending/answered/confirmed…)"가 들어있는지 본다.
```sql
select pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'get_weekly_question_usage';
```

### A2-Q3 — ★ question_threads 트리거 존재 여부(한도 서버강제의 핵심) *(읽기 전용 — 데이터 안 바뀜)*
```sql
select t.tgname as trigger_name,
       pg_get_triggerdef(t.oid) as trigger_def
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'question_threads'
  and not t.tgisinternal;
```

### A2-Q4 — question_threads 제약(CHECK 등) *(읽기 전용 — 데이터 안 바뀜)*
```sql
select conname,
       contype,
       pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.question_threads'::regclass;
```

### A2-Q5 — INSERT를 대신하는 전용 RPC(있으면 그 안에서 강제할 수 있음) *(읽기 전용 — 데이터 안 바뀜)*
```sql
select n.nspname as schema,
       p.proname  as function,
       pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (p.proname ilike '%question_thread%'
       or p.proname ilike '%create%thread%'
       or p.proname ilike '%ask%question%');
```

### A2-Q6 — tier별 한도값이 DB 테이블에 있는지(코드 상수 vs DB) *(읽기 전용 — 데이터 안 바뀜)*
```sql
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and (column_name ilike '%weekly%'
       or column_name ilike '%quota%'
       or column_name ilike '%question%limit%'
       or column_name ilike '%cap%')
order by table_name, column_name;
```

## 결과 → 구현 분기 (A2)
- **A2-Q3에 question_threads INSERT 트리거가 있고**(정의에 한도 초과 시 `raise exception`/`get_weekly_question_usage` 호출 등) → **DB가 강제한다.**
  → 앱 수정 **작음**: (1) `get_weekly_question_usage` RPC를 읽어 "남은 N개" 표시(현재 `remaining` null 대체), (2) INSERT 실패(트리거 예외) 시 친절한 문구 노출. 보안 구멍 없음.
- **A2-Q3에 관련 트리거 없음 + A2-Q5에 INSERT 전용 강제 RPC 없음** → **DB는 강제하지 않고 앱계층만 막는 구조.**
  → 앱 수정 **큼/주의**: (1) 앱이 INSERT 전에 `get_weekly_question_usage`를 호출해 `can_ask=false`면 차단(웹과 동일). **단 클라이언트 검사라 우회 가능** → 보고에 "진짜 안전하려면 DB 트리거 추가 필요(오너/백엔드 결정)"로 남길 것.
- **A2-Q2 정의에 한도값이 하드코딩** → 앱은 값을 **RPC 반환(`limit`/`remaining`/`can_ask`)로만** 쓰고 앱에 4/9/999를 재하드코딩하지 말 것(정본은 DB).
- **A2-Q6에 한도 테이블 존재**(예: `subscription_plans.weekly_question_limit`) → 표시·검증 시 그 테이블을 정본으로.
- **A2-Q1이 빈 결과**(함수 없음) → **확인필요**: 웹이 폴백 경로(`fetchWeeklyQuestionUsageWithFallback`의 클라이언트 계산)에만 의존하는지. 그렇다면 한도 로직 전체가 앱계층이며, 앱도 동일 계산을 직접 해야 함(더 큼).

---

# D1. 커뮤니티 카테고리 — DB에 실제 저장된 코드

## 왜 확인하나
- 앱 근거: `lib/features/community/data/community_labels.dart:5-11` → 코드 집합 `study·school·free·college·career`. 조회는 `community_read_repository.dart:25,29`에서 `from('community_posts')` + `.eq('category', code)`.
- 웹 근거: `lib/community/communityBoardConstants.ts`(탐색) → `all·study·school·career·college` (여기서 `all`은 "전체" 필터용 UI 값이지 저장값이 아닐 가능성 높음).
- 불일치 지점: 앱엔 `free`가 있는데 웹엔 없음. 웹엔 `all`이 있는데 앱엔 없음.
- 확정해야 할 것: `community_posts.category`(및 `shortform_posts.category`)에 **실제로 존재하는 distinct 값**. 그게 정본이다.

### D1-Q1 — community_posts 카테고리 분포 *(읽기 전용 — 데이터 안 바뀜)*
```sql
select coalesce(category, '(null)') as category, count(*) as posts
from public.community_posts
group by category
order by posts desc;
```

### D1-Q2 — shortform_posts 카테고리 분포 *(읽기 전용 — 데이터 안 바뀜)*
```sql
select coalesce(category, '(null)') as category, count(*) as posts
from public.shortform_posts
group by category
order by posts desc;
```

### D1-Q3 — category 컬럼 타입·CHECK/enum 제약(허용값이 고정돼 있나) *(읽기 전용 — 데이터 안 바뀜)*
```sql
select column_name, data_type, udt_name
from information_schema.columns
where table_schema = 'public' and table_name = 'community_posts'
  and column_name = 'category';

select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.community_posts'::regclass
  and contype = 'c';
```

## 결과 → 구현 분기 (D1)
- **distinct 값이 {study,school,career,college}뿐(‘free’ 없음)** → 저장 정본은 웹 집합. 앱의 `free`는 실사용 없음 → 앱 라벨/필터에서 `free` 제거(또는 실제 쓰이는 코드로 교체). `all`은 UI 전용이므로 앱은 "전체"를 별도로 앞에 붙이면 됨.
- **distinct 값에 ‘free’가 실제로 존재** → 앱 집합이 맞고 웹이 `free`를 필터에서 빠뜨린 것(웹 수정은 범위 밖, 앱은 유지). 다만 웹/앱 라벨 통일 필요.
- **distinct 값에 두 집합 어디에도 없는 코드/`(null)` 다수** → 양쪽 다 매핑 누락 → 실제 값 기준으로 `_categoryLabels` 재정렬, 미매핑은 '기타' 폴백 유지.
- **D1-Q3에 CHECK/enum 제약 존재** → 그 제약의 허용값이 **절대 정본** → 앱·웹 카테고리 집합을 그 값에 맞춤.

---

## 실행 순서 제안(오너)
1. **A2-Q3 먼저**(트리거 유무) — 앱 수정 규모를 가장 크게 가르므로 우선.
2. A2-Q1·Q2(함수·한도 정의), A2-Q5·Q6(전용 RPC·한도 테이블).
3. A1-Q1~Q4(과목 위치·형식·조인).
4. D1-Q1~Q3(실제 카테고리 값).
5. 결과를 이 문서 각 "결과 → 구현 분기"에 대입하면 앱 수정 방향이 확정된다.

---
_(끝) 이 문서의 모든 쿼리는 SELECT 전용이며 데이터를 변경하지 않는다. 이번 작업에서 코드·DB 변경 0._
