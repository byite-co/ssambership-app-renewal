# A-1 부트스트랩 보고서 — 2026-09-04

저장소 `byite-co/ssambership-app-renewal` · 작업 브랜치 `claude/new-session-2jl045` · 기준 `master` `635ae73`.
지시서: "CC 착수 지시서 — 앱 리뉴얼 A-1 부트스트랩". 원본 저장소 `ssambership-app` 은 읽지도 않았다(접근 범위 밖) — 수정·푸시 0.

## 0. 한눈에

| 질문 | 답 |
|---|---|
| Flutter SDK 로 실제 빌드·테스트를 돌렸는가 | **예 — 테스트·분석은 실제 실행.** 환경에 SDK 가 없어 CI 와 같은 **3.44.6 stable** 을 내려받아 돌렸다. **APK 빌드만 못 돌렸다**(Android SDK 없음 · `dl.google.com` 프록시 403) |
| 테스트 통과 수 | **1,517 / 1,517** (기준선 1,510 + 골든 7). 실패 0 |
| analyze | **error 0 · warning 0 · info 79** |
| 계약 테스트·매니페스트 잠금 | **실재.** `test/contracts/` 6개. 아웃바운드 매니페스트는 RPC 34 · 테이블/뷰 25 · 버킷 6 · 금지 표면 8 을 lib 소스 스캔으로 고정 — `baseline-2026-09-04.md` §2-2 |
| 골든 테스트 | `test/goldens/` 신설, **PNG 7장** 커밋. 대표 5화면 중 **4개 렌더 성공, 1개(학생 질문방 목록 1뎁스) 렌더 불가** → 대체 화면 + 결합 기록 골든 |
| CI 가 새 저장소에서 도는가 | `flutter-ci.yml` 은 시크릿 없이 그대로 동작 가능한 구조. **이 저장소에서의 실행 이력은 0건**이었다 — §4 에 이번 실행 결과 |
| 필요한 시크릿 | `flutter-ci`: **없음**. 서명 워크플로(수동 전용): Environment + 시크릿 7종(§4) |
| `master` 미병합 커밋이 있는 브랜치 | **31개** — `branch-archive-2026-09-04.md` 유지 표. 완전 병합 29개는 **삭제 대상으로 목록화했으나 삭제는 미실행**(세션 권한 정책 차단 — §1) |

---

## 1. 한 일 (§1 저장소 정리)

### 1-1. 브랜치

- 원격 브랜치 **61개**(master 제외) 전수 조사 → `docs/renewal/branch-archive-2026-09-04.md` (브랜치명·마지막 SHA·날짜·master 병합 여부·관련 PR·미병합 커밋 제목).
- master 에 **완전 병합 29개** → 삭제 대상. **미병합 커밋 있는 31개 + 이 작업 브랜치 1개** → 유지.
- ★ **삭제 실행은 못 했다.** `git push origin --delete <29개>` 를 이 세션의 권한 정책(자동 모드 분류기)이 차단했다. GitHub MCP 도구에도 브랜치 삭제 기능이 없어 우회하지 않았다. 아카이브 문서의 `## 삭제 명령` 절을 오너가 로컬에서 실행하면 끝난다.
- 유지 31개의 성격(아카이브 문서 하단 요약): 문서·감사 기록만 있는 브랜치 11개 · 2026-07-06~07 기능 브랜치(내용은 이후 master 에 반영됨) 8개 · api_app_v1 전환(S2-2) 계열 4개(코드 13~17커밋, **리뉴얼 방향과 겹침 — 검토 필요**) · PR 병합 후 추가 커밋 2개(`…app-fixes-sta99j` +3, `…supabase-interaction-gj79qr` +2 — 후자는 1.0.0+22 버전 범프 포함) · iOS/Android 설정 단건 6개 · `ci-logs` 1개(CI 가 덮어씀).

### 1-2. 낡은 문서

- `docs/` 의 7~8월 문서 **49개**(`audit/`·`qa/` 포함)를 `docs/legacy/` 로 이동(`git mv`, 내용 무변경). `docs/legacy/README.md` 에 "2026-07 기준, 리뉴얼 전 상태" 명시. 루트 README 에도 한 줄.
- **옮기지 않은 4개**: `docs/ANDROID_BUILD.md` · `IOS_BUILD.md` · `IOS_RELEASE_RUNBOOK.md` · `S3E_QUESTION_ROOM_SAFETY_CONTRACT.md` — 계약 테스트가 **경로로 읽는다**(`test/contracts/android_signed_workflow_contract_test.dart:348`, `ios_release_config_contract_test.dart:19,409`, `s3e_doc_contract_test.dart:11`). 옮기면 테스트가 깨지고, 테스트 경로 상수를 고치는 것은 이번 범위(코드 변경 = pubspec·README·골든·CI) 밖이라 두었다. 오너 결정: (a) 그대로 두기 (b) 다음 단계에서 테스트 상수와 함께 이동.
- 루트 `HANDOFF.md`(7월 인수인계)는 지시 범위(`docs/`)가 아니라 그대로 두었다 — `docs/legacy/` 이동 후보.
- 부작용: `lib/`·`tool/` 주석 5곳이 옛 경로(`docs/APP_V16_SERVER_CONTRACT_SNAPSHOT.md`·`DATA_SAFETY_FORM.md`·`PLAY_STORE_REVIEW_PLAN.md`·`SCAN_INK_PLAN.md`)를 가리킨다. 주석뿐이라 동작 영향 0. legacy 문서 간 상대 링크도 일부 끊길 수 있다(내용 불변).

### 1-3. 저장소 메타

- `pubspec.yaml` `description` → `쌤버십 모바일 앱 — 학습 멘토링. 캐시 충전을 제외한 전 기능 지원.` (테스트 잠금 없음 확인).
- `version` **1.0.0+19 유지**. 번들 ID·applicationId **무변경**(`com.ssambership.edu` / `com.ssambership.app`).
- `README.md` 리뉴얼 기준으로 재작성 — 목적·범위·원본과의 관계·개발/테스트 방법·골든 운용·폴더 구조·CI·기여 규칙·단계표.

---

## 2. 기준선 (§2) → `docs/renewal/baseline-2026-09-04.md`

요점만:
- 빌드: pub get 성공 · analyze 0/0/79 · test 1,510 통과 · **apk 미실행**(환경 제약, 원인 기록).
- 테스트 파일 **173개**(지시서의 69개는 다른 시점 수치) + fake 2. 단위 905·위젯 565 선언. 통합 1(`flutter drive`, 미실행). 골든 0 → 7.
- 계약 테스트 6 + 파일 잠금 2. 버전 잠금 3곳(배포 시 함께 갱신).
- 구조: `lib/` 228파일. **GoRouter 라우트 4개**(+dev 2) · 하단 탭 5 · 화면 위젯 36 · **명령형 `MaterialPageRoute` push 44곳/26파일**(모델 객체 전달 27 · ID 전달 5 · 무인자 12).
- 상태관리: 패키지 없음. static 싱글턴 12종(표) — `AuthService.instance` 32곳/19파일, `SupabaseInit.clientOrNull` **56곳/40파일**, 화면 State 의 `const XxxRepository()` 직접 생성 66곳.
- 이관 자산 8종 전부 위치 확정. **다른 형태 2건**: RPC 봉투 파서는 공용 파서 없이 12+곳에 흩어진 `{ok:true}` 판정 · 서명 URL 리졸버는 같은 패턴 4벌.

---

## 3. 방어선 (§3)

### 3-1. 골든 테스트 인프라 — `test/goldens/`

**선택: `flutter_test` 내장 `matchesGoldenFile` 만 사용, 별도 패키지 미도입.**
이유: (1) 기준 이미지 생성·비교·실패 diff(`failures/*_masterImage/_testImage/_isolatedDiff.png`)가 내장돼 있어 목적(PNG 로 보기 + CI 회귀 감지)에 충분하다. (2) `golden_toolkit` 은 폰트 로딩·다중 시나리오 그리드가 장점인데 폰트 로딩은 20줄(`flutter_test_config.dart`)로 해결됐고, 그리드는 지금 필요 없다. 그 패키지는 유지보수가 멈춘 상태(archived)여서 의존을 늘릴 이유가 약하다. (3) `alchemist` 는 CI/로컬 이중 골든 등 규약이 커서 5장 규모엔 과하다. 필요가 생기면 하네스(`golden_harness.dart`) 한 곳만 바꿔 이행할 수 있게 진입점을 좁혀 두었다.

구성:
| 파일 | 역할 |
|---|---|
| `test/goldens/flutter_test_config.dart` | 이 디렉터리 전용 설정. `FontManifest.json` 을 읽어 **Pretendard 4종·MaterialIcons 를 실제 로드** — 기본 테스트 폰트(사각형 자리표시)를 피한다. 다른 테스트 디렉터리엔 영향 없음 |
| `golden_harness.dart` | `pumpGoldenScreen()` — 390×844 논리 픽셀 · 2배율 · `AppTheme.build(role)` · ko 로케일로 감싸 렌더. `expectScreenGolden(name)` → `images/<name>.png` |
| `golden_fixtures.dart` | Room·스레드 3·메시지 3·연결노트 2·마이페이지(학생/멘토) 픽스처 + 포트 fake(읽기 레포·실시간 no-op·신고/차단·업로더). 날짜는 전부 7일 이상 과거의 로컬 시각 → 실행일·시간대에 무관 |
| `*_golden_test.dart` 6개 | 아래 표 |
| `images/*.png` 7장 | 기준 이미지(Linux · Flutter 3.44.6 생성). 두 번 연속 실행해 결정성 확인 |

결과:
| 대표 화면 | 골든 | 렌더 | 비고 |
|---|---|---|---|
| ① 학생 질문방 목록(1뎁스, `QuestionRoomScreen`→`_StudentRoomList`) | `question_room_tab_singleton_fallback.png` | **불가** | `AuthService.instance.currentRole` 로 분기 + `_StudentRoomList` 가 `const QuestionRoomReadRepository()`·`SupabaseInit.clientOrNull` 을 직접 읽음(주입 seam 없음). 테스트에선 싱글턴 기본값(guest) 때문에 **"질문방은 학생·멘토 전용이에요" 빈 상태**가 그려진다. 그 사실 자체를 골든+단언으로 고정(A-2/A-3 뒤 교체 대상) |
| ① 대체: 학생 질문 목록(3뎁스, `QuestionListScreen`) | `student_question_list.png` | 성공 | 대기·답변완료·확인완료 3장, 잔여 질문 3개 표시 |
| ② 질문 대화(`ChatScreen`) | `student_chat.png` | 성공 | 학생 2·멘토 1 말풍선, 상태칩, 입력바. 첨부 0 |
| ③ 멘토 답변(`MentorAnswerScreen`) | `mentor_answer.png` | 성공 | 같은 대화를 멘토 시점·멘토 강조색으로 |
| ④ 연결노트(`ConnectionNotesScreen`) | `connection_notes.png` | 성공 | 상대(멘토) 노트 카드 + 내 노트 에디터(시드) |
| ⑤ 마이페이지(`MyPageScreen`) | `mypage_student.png` · `mypage_mentor.png` | 성공(변형 주의) | `loaderOverride` 주입. 단 화면이 `AuthService.instance.isSignedIn`(테스트=false)을 직접 읽어 **로그아웃 상태 변형**으로 그려진다(프로필 수정·로그아웃 요소) |

**렌더되지 않았거나 싱글턴 폴백으로 그려진 지점 = A-2·A-3 우선순위**
1. `lib/features/question_room/question_room_screen.dart:41` — `AuthService.instance.currentRole` 분기(학생/멘토 화면 선택을 위젯이 결정).
2. `question_room_screen.dart:91-92,126` — `_StudentRoomList` 가 레포 2종을 필드에서 직접 생성, `SupabaseInit.clientOrNull` 로 사용자 id 조회. 멘토 인박스(`ui/mentor/mentor_inbox_screen.dart:52-53`)도 동일 구조 → **멘토 질문방 목록도 렌더 불가**.
3. `lib/features/mypage/mypage_screen.dart:242,265,275` — `AuthService.instance.isSignedIn/signOut` 직접 참조.
4. `ui/chat_screen.dart:98,112` · `ui/mentor/mentor_answer_screen.dart:96,110` — 쓰기 레포·URL 리졸버는 주입 불가(전송·첨부 경로가 골든에서 죽어 있어 렌더에는 안 걸렸지만 상호작용 테스트는 막힌다).
5. `ui/connection_notes_screen.dart:50-52` — 읽기/쓰기 레포 직접 생성(`notesLoader`/`onSaveNote` 콜백 주입으로만 우회).
6. `HomeShell`(`lib/app/home_shell.dart:68,73-74,83`) — `AuthService`·`NotificationBadgeController` 싱글턴. 탭 5개 전체를 담은 셸 골든은 이 때문에 만들지 않았다.

**골든이 드러낸 디자인 결함(고치지 않음 — A-6 입력)**: AppBar 제목과 `PrimaryButton` 라벨이 골든에서 사각형으로 나온다. 원인은 폰트 미로드가 아니라 **스타일에 `fontFamily` 가 없는 것** — `appBarTheme.titleTextStyle: AppType.display`(`lib/design/theme.dart:90`, `typography_tokens.dart:22`)와 `FilledButton.styleFrom(textStyle: TextStyle(w800, 15))`(`lib/design/widgets/primary_button.dart:47`)는 `ThemeData.fontFamily` 를 상속하지 않는다. 즉 **실기기에서도 이 두 요소는 Pretendard 가 아니라 시스템 폰트**로 그려지고 있다(본문 `Text(style:)` 는 상속돼 정상). 골든이 없었으면 계속 몰랐을 종류의 문제다.

운용 규칙: 기준 이미지는 Linux·Flutter 3.44.6(=CI) 산출물이 정본. 로컬(Windows/macOS)에서 `--update-goldens` 하지 않는다. 의도한 디자인 변경이면 CI diff 확인 후 갱신하고 PR 에 이유를 적는다.

### 3-2. CI

- `flutter-ci.yml` 은 원본 참조가 없고 시크릿이 필요 없어 **그대로 동작 가능**. 골든을 위해 2 step 추가: 테스트 실패 시 `test/**/failures/**` artifact(`golden-failures`) · 매 실행 `test/goldens/images/*.png` artifact(`golden-screens`). 게이트 로직 무변경.
- **빌드 포함 여부**: 기존 `appbundle` 단계는 `allowInsecureSigning` 으로 debug 서명 폴백을 쓰므로 **서명 키 없이 돈다** → 유지(게이트 아님, 산출물은 제출 불가 표기). 별도 APK 단계는 중복이라 추가하지 않았다.
- `android-signed-release-candidate.yml` — 수동 전용이라 **자연히 비활성**. 원본 저장소의 PR #51·`SOURCE_SHA 1bbbc214`·테스트 수 1508 에 고정돼 있어 새 저장소에선 1단계에서 실패한다. 배포 시점에 재고정(+계약 테스트 갱신) 필요. 필요한 설정: GitHub Environment **`android-release-candidate`**(required reviewers · 배포 브랜치 master 단독) + 시크릿 **`SUPABASE_URL` · `SUPABASE_ANON_KEY` · `SENTRY_DSN` · `ANDROID_KEYSTORE_BASE64` · `ANDROID_KEYSTORE_PASSWORD` · `ANDROID_KEY_ALIAS` · `ANDROID_KEY_PASSWORD`**. 오너가 설정한다.
- iOS Xcode Cloud 훅(`ios/ci_scripts/ci_post_clone.sh`)은 새 저장소를 Xcode Cloud 에 연결해야 산다(콘솔 작업).

### 3-3. 회귀 감지 기준선 (2026-09-04, 이 브랜치 HEAD)

| 지표 | 값 | 규칙 |
|---|---|---|
| `flutter test` 통과 수 | **1,517** (실패 0 · 스킵 0) | 이 수가 **줄면 회귀**. 늘어야 정상 |
| 골든 | **7장** 전부 일치(2회 연속 실행 결정성 확인) | 불일치 = 의도 확인 필요 |
| `flutter analyze` | **error 0 · warning 0 · info 79** | error/warning 1건이면 CI 실패. info 는 늘리지 않는다(현재 79 — 감소 목표) |
| Flutter | 3.44.6 stable · Dart 3.12.2 | 버전 올릴 때 골든 재생성 각오 |

---

## 4. 이 저장소에서의 CI 실행

작업 브랜치 push 후 `flutter-ci` 를 `workflow_dispatch` 로 실행해 새 저장소에서 실제로 도는지 확인한다. 결과는 아래에 기록한다.

- 실행 전 상태: Actions 실행 이력 0건(`ci-logs` 브랜치 내용은 원본 저장소 실행분).
- 실행 결과: _(push 뒤 기록)_

---

## 5. 다음 단계 입력

- **A-2 라우팅 교체**: 라우트 4개 + `MaterialPageRoute` 44곳(모델 객체 전달 27곳 — baseline §4 표). 알림 딥링크 오프너(`notification_target_opener.dart`)가 7종 화면을 직접 push 하므로 라우트 테이블 설계의 첫 소비자.
- **A-3 상태관리 교체**: 싱글턴 12종(baseline §4 표). 첫 순서는 골든이 막힌 지점 — `AuthService`(역할·세션) 와 `SupabaseInit.clientOrNull`(56곳) 을 주입으로 바꾸면 질문방 1뎁스·멘토 인박스·홈셸 골든이 열린다. 레포 `const` 직접 생성 66곳.
- **A-4 기능 개방**: 매니페스트 잠금(`outbound_api_manifest_test.dart`)과 IQ 등록 경계(`iq_create_boundary_test.dart`)를 **의도적으로** 갱신하는 작업이 포함된다. RPC 봉투 파서 단일화·서명 URL 리졸버 통합은 여기서 같이.
- **A-6 디자인 통일**: AppBar 제목·PrimaryButton 폰트 패밀리 누락(위). `lib/design/typography_tokens.dart` 와 `lib/design/tokens/typography.dart` 두 타입 스케일이 공존한다(통합 대상).
- **오너 결정 대기**: 브랜치 29개 삭제 실행 · 유지 31개 처리 · 테스트 잠금 문서 4개 이동 여부 · 서명 워크플로 Environment/시크릿 · Xcode Cloud 연결.
