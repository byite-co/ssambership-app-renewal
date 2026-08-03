# SHORTFORM_ASSESSMENT — 숏폼 출시 소요 산정 & 웹 대비 현황

> **SUPERSEDED: 이 문서는 2026-07-02 시점의 조사·산정 스냅샷이다.**
> 전 기능 계약 수렴(2026-08) 이후 일부 항목이 변경됐다 — 예: 숏폼 조회수는
> 이제 `shortform_view_record_v2`(impression당 event key 멱등)로 집계하고,
> 숏폼 글 신고 `target_type` 정본은 `shortform_post`(구 모호 `shortform` 폐기)다.
> 신고·차단 현행 정본은 `docs/S3E_QUESTION_ROOM_SAFETY_CONTRACT.md`,
> 수렴 결과는 `docs/audit/full_contract_convergence_result_20260804.md` 를 따른다.
> 이 문서는 실행 지시나 현재 blocker 판정에 사용하지 않는다(역사 스냅샷).
>
> 조사·산정 문서. **코드 변경 없음.** 근거는 앱/웹 코드에서 직접 읽은 것만(웹은 읽기 참고).
> 작성 기준일: 2026-07-02.

## 0. 결론 요약 (먼저)

- **웹 숏폼은 "실제로 완전히 동작"한다** — HTML5 `<video controls>`로 재생, 업로드, 비공개 버킷+서명 URL, 조회수 집계까지.
- **앱 숏폼은 "열람 골격"만 있다** — 목록·좋아요·댓글·신고는 되지만 **영상 재생은 미구현**이고, 썸네일조차 **서명 URL 처리가 없어 실제로는 안 뜰 가능성이 높다**.
- **핵심 장애물은 '영상 플레이어'가 아니라 '비공개 버킷 서명 URL'이다.** 웹은 서버(세션/서비스롤)에서 서명하는데, 앱은 anon+RLS 클라이언트라 **모바일 클라이언트가 그 비공개 객체에 서명 URL을 만들 수 있는지(스토리지 정책)** 가 미확인 — 이게 안 되면 플레이어를 붙여도 재생 불가.
- **추천: 이번 출시에서 숏폼 재생은 빼고(준비중/열람만), 콘텐츠·스토리지 정책이 확인되면 fast-follow.** (사유는 §5.)

---

## 1. 앱 숏폼 현황 (무엇까지 되고 무엇이 안 되나)

| 항목 | 상태 | 근거(앱 파일) |
|---|---|---|
| 숏폼 목록(피드) | ✅ 됨(published, 최신순) | `data/community_read_repository.dart` `shortforms()` (`select('*').eq('status','published').order(created_at desc)`) |
| 페이징/카테고리 필터/정렬 | ❌ 없음(전체 로드) | 같은 곳(파라미터·커서 없음), `ui/shortform/shortform_feed_view.dart` |
| 썸네일 표시 | ⚠️ 코드는 있으나 **실제로는 대부분 안 뜰 것** | `ui/widgets/thumbnail_view.dart` `Image.network(thumbnailUrl)` — 실패 시 무비 아이콘 폴백 |
| **영상 재생** | ❌ **미구현(D9)** | `video_url`은 `ShortformPost.videoUrl`로 **파싱만** 하고 UI에서 전혀 안 씀. 상세/카드 모두 썸네일+재생아이콘 오버레이만(`shortform_detail_screen.dart:147-151`, `shortform_card.dart:32-35`, 파일 주석 "실제 영상 재생 플러그인 없음") |
| 좋아요 | ✅ 토글(insert/delete) | `data/community_write_repository.dart` `toggleShortformReaction(type:'like')` |
| 좋아요 '이미 누른' 초기상태 | ⚠️ 반영 안 함(항상 false로 시작) | `shortform_detail_screen.dart:36-38` (`_liked=false` 고정) |
| **스크랩(D8)** | ⚠️ 앱은 `type:'scrap'`을 insert하지만 **웹은 'like'만 씀** → DB CHECK에 막힐 수 있음 | 앱 `toggleShortformReaction(type:'scrap')` ↔ 웹 `communityShortformMutations.ts`는 like 전용. **DB `shortform_reactions.type` 허용값 확인필요** |
| 조회수 증가(D7) | ❌ 표시만, 증가 RPC 미호출 | 앱은 `view_count` 표시만. (웹은 `increment_shortform_post_view` 호출) |
| 댓글(작성/열람) | ✅ 됨 | `shortform_detail_screen.dart` `addComment`/`comments` |
| 신고 | ✅ 됨 | `report(targetType:'shortform_post')` — 수렴 후 정본(구 모호 `'shortform'` 폐기) |
| **작성(업로드)** | ❌ 없음(**설계상 웹 전용**) | `ui/widgets/community_write_notice.dart` (작성은 웹) |

### 영상 데이터는 어디서 오나
- 테이블 `shortform_posts`, 필드 `video_url` / `thumbnail_url`(앱 `ShortformPost.fromMap`이 `video_url`·`thumbnail_url` 파싱).
- ★ 이 값들은 **비공개 스토리지 참조(버킷/경로)** 이지 바로 열리는 URL이 아니다(§2 참조). 앱은 이를 **raw로 `Image.network`/미사용** 처리 → 서명 URL 없이는 썸네일 로드·영상 재생 모두 불가.
- ※ 콘텐츠 존재: `shortform_posts`는 현재 **사실상 비어 있는 것으로 추정**(오너 DB 점검상 숏폼 0건). 비면 앱 피드는 "아직 숏폼이 없어요" 빈 상태.

---

## 2. 웹 숏폼 현황 (읽기 참고) — 실제로 완전 동작

| 항목 | 웹 구현 | 근거(웹 파일) |
|---|---|---|
| **영상 재생(상세)** | ✅ `<video src controls playsInline poster>` — 컨트롤 있는 실제 재생 | `components/community/CommunityShortformDetailView.tsx:27-33` |
| 영상 재생(피드 카드) | ✅ 썸네일 우선, 없으면 `<video muted playsInline preload="metadata">` | `components/community/CommunityShortformVideoCard.tsx:15-25` |
| 영상/썸네일 저장 | 비공개 버킷 `shortform-videos` / `shortform-thumbnails` | `lib/community/communityShortformConstants.ts:17-18` |
| **서명 URL 해석** | 조회 시 저장참조(버킷/경로)를 **서명 URL로 변환** 후 클라에 전달 | `lib/community/communityShortformStorage.ts` `resolveShortformVideoUrl`/`resolveShortformThumbnailUrl` → `createSignedStorageUrl`; `communityShortformQueries.ts:92-99` |
| 업로드 | ✅ 서버 액션(매직바이트 MIME 검증, mp4/quicktime/webm) | `lib/community/communityShortformActions.ts`, `communityShortformStorage.ts` |
| 업로드 제약 | 최대 500MB, 최대 180초 | `communityShortformConstants.ts:13-14` (`SHORTFORM_VIDEO_MAX_BYTES=524288000`, `SHORTFORM_VIDEO_MAX_SEC=180`) |
| 조회수 증가 | ✅ RPC `increment_shortform_post_view` | `communityShortformQueries.ts:213-215` |
| 카테고리 | all/study/school/career/college | `communityShortformConstants.ts:1-6` |
| 정렬 | 최신/인기(view_count) | `communityShortformQueries.ts:115` |

**→ 웹에서 숏폼 영상 재생은 '실제로 된다'(확정).** 저장·서명·재생·업로드·조회수까지 완결. DB에 실제 영상이 있는지는 콘텐츠(멘토 업로드) 문제로, 코드 구조상 재생 경로는 완성돼 있음.

---

## 3. 앱을 '출시 가능 수준'으로 만들려면 (작업 목록·난이도·소요)

> 구분: **[앱]** = 앱 Dart 코드만 / **[인프라]** = DB·Storage 정책 등 동업자/백엔드 영역.

| # | 작업 | 구분 | 난이도 | 대략 소요 | 비고 |
|---|---|---|---|---|---|
| S1 | **서명 URL 해석 데이터 계층** — 저장참조(버킷/경로) 파싱 + `storage.createSignedUrl(bucket, path, ttl)`로 썸네일·영상 URL 생성. (웹 `parseStorageRef`/`resolveShortform*Url` 이식) | **[앱]** + **[인프라 의존]** | 보통 | 0.5~1일 | ★ **모바일 클라이언트가 비공개 버킷 객체에 서명 URL을 만들 수 있는지(Storage RLS/정책)** 가 관건. 웹은 서버측 서명. 앱 anon/auth로 안 되면 이 기능 자체가 막힘 → **인프라 확인 필수** |
| S2 | **영상 플레이어 도입** — `video_player`(+선택 `chewie`) 패키지 추가, iOS/Android 설정, 세로 9:16 재생 위젯(버퍼링·에러·dispose 처리), 서명 URL 재생 | **[앱]** | 보통~어려움 | 1~2일 | 네이티브 의존·앱 용량 증가. 서명 URL 만료 대비(재요청) 필요 |
| S3 | **썸네일 정상화** — S1의 서명 URL을 `Image.network`에 사용(현재 raw) | **[앱]** | 쉬움 | ~0.5일 | S1에 종속 |
| S4 | **조회수 증가(D7)** — 상세 진입 시 `increment_shortform_post_view` RPC 호출 | **[앱]** | 쉬움 | 1~2시간 | RPC는 이미 존재(웹 사용) |
| S5 | **스크랩 정상화(D8)** — DB `shortform_reactions.type`이 'scrap' 허용하는지 확인 후, 허용 안 하면 앱에서 스크랩 제거(웹과 동일 like-only) 또는 [인프라] CHECK 확장 | **[앱]**(제거) 또는 **[인프라]**(허용) | 쉬움 | ~1시간 | 방향은 확인 결과에 따라 |
| S6 | (선택) 카테고리 필터·정렬·페이징 파리티 | **[앱]** | 보통 | 0.5~1일 | 출시 필수 아님 |
| S7 | (선택) 좋아요/스크랩 초기상태 로드(내 반응 조회) | **[앱]** | 쉬움 | 2~4시간 | UX 개선 |
| S8 | mock 위젯/유닛 테스트(플레이어는 fake, 서명 URL은 mock) | **[앱]** | 보통 | ~0.5일 | 실제 DB/네트워크 미접촉 |
| I1 | **Storage 버킷·정책** — `shortform-videos`/`shortform-thumbnails` 존재 + **앱 사용자용 서명 URL 허용 정책** | **[인프라]** | — | 동업자/백엔드 | S1/S2/S3의 전제 |
| I2 | **콘텐츠** — 멘토가 웹으로 실제 숏폼 업로드(현재 0건 추정) | **[인프라/운영]** | — | — | 없으면 앱은 빈 피드 |

**앱만으로 가능한 부분**: S2(플레이어), S4(조회수), S5(스크랩 제거안), S6·S7·S8, 그리고 S1/S3의 코드 부분.
**인프라(DB/Storage) 필요**: I1(서명 URL 정책 — S1·S2·S3의 전제), I2(콘텐츠), S5의 CHECK 확장안.

---

## 4. '넣기 vs 빼기' 작업량 비교

### 넣기(이번 출시에 숏폼 재생 포함)
- 필요: **S1+S2+S3+S4+S5+S8 + I1(+I2)**.
- 소요(앱): 대략 **3~5 개발일** + 인프라(스토리지 서명 정책 확인/설정, 콘텐츠 확보).
- 리스크(높음):
  - **I1 미확인** — 모바일 클라이언트 서명 URL 정책이 막혀 있으면 플레이어를 붙여도 **재생 불가**(가장 큰 불확실성).
  - **콘텐츠 0건** — 지금 올라온 숏폼이 없으면 기능을 넣어도 **빈 피드로 출시**.
  - 네이티브 플레이어 의존·앱 용량·기기별 코덱 이슈를 출시 직전에 떠안음.

### 빼기(이번 출시에서 숏폼 재생 제외 — 준비중/열람만)
- 옵션 A(최소): **현행 유지**. 콘텐츠가 없어 피드는 자연히 "아직 숏폼이 없어요" 빈 상태 → 사실상 이미 '준비중'. **추가 작업 0**.
- 옵션 B(정직한 표기): 오해 소지(재생될 것 같은 재생 아이콘·상세 진입)를 줄이도록 숏폼 진입점을 "준비 중" 안내로 처리하거나 탭/섹션에서 임시 숨김. **~0.5~1일 [앱]**.
- 리스크: 낮음. 되돌리기 쉬움(콘텐츠·정책 확인 후 fast-follow로 S1~S5 진행).

---

## 5. 추천

**이번 출시에서는 숏폼 '재생'을 빼고(열람/준비중), fast-follow로 미룬다.** 사유:
1. **인프라 불확실성** — 모바일 클라이언트의 비공개 버킷 서명 URL 허용(I1)이 미확인. 이게 안 되면 플레이어 작업(S2)이 통째로 헛수고가 될 수 있어, 확인 전 착수는 위험.
2. **콘텐츠 부재** — `shortform_posts`가 비어 있어(추정), 지금 기능을 넣어도 빈 피드로 출시된다. 웹으로 멘토 업로드가 쌓인 뒤 넣는 게 효율적.
3. **출시 리스크 관리** — 네이티브 영상 플레이어 도입은 앱 용량·기기별 코덱·수명주기 버그를 동반. 핵심(질문방 등)이 우선인 출시 직전에 떠안을 이유가 약함.
4. **되돌리기 쉬움** — 빼기는 작업량이 0~1일이고, 나중에 S1~S5로 빠르게 켤 수 있다(웹 로직 이식 경로가 명확).

**전제가 풀리면(위 I1 서명정책 OK + I2 콘텐츠 존재) fast-follow 순서**: S1(서명URL) → S3(썸네일) → S2(플레이어) → S4(조회수) → S5(스크랩) → S6~S8.

---

## 6. 확인필요 (다음 결정 전 체크)
1. **[I1]** 앱 사용자(anon/auth)가 `shortform-videos`/`shortform-thumbnails` 비공개 객체에 `createSignedUrl`을 만들 수 있는지(Storage RLS/정책). — S1·S2·S3의 전제.
2. **[콘텐츠]** `shortform_posts`에 published 실데이터가 있는지(현재 0건 추정 확인).
3. **[D8]** `shortform_reactions.type`이 'scrap'을 허용하는지(CHECK 제약) — 앱 스크랩 유지/제거 결정.
4. `thumbnail_url`/`video_url`의 실제 저장 형식(전체 URL vs 버킷/경로 참조) 샘플 확인 — S1 파싱 로직 확정용.

---
_(끝) 이 문서는 조사·산정이며, 이번 작업에서 앱 코드·DB는 전혀 변경하지 않았다._
