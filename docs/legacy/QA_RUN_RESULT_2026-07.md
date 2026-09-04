# QA_RUN_RESULT 2026-07 — MANUAL_QA_RUN 실행 결과 (진행 중)

> [MANUAL_QA_RUN_2026-07.md](MANUAL_QA_RUN_2026-07.md)(17항목 실행 시트) 런의 **공식 결과
> 문서**. 이번 원격 세션은 기기 실행이 차단된 상태(Phase 0 게이트 미통과)라 **기기 실행분
> 0/17** 이며, 본 문서는 정직한 현재 상태 기록 + 로컬 PC(`C:\dev\ssambership-app`) 재개 시
> 갱신할 매트릭스 골격이다. 물리 항목 절차는
> [MANUAL_QA_HUMAN_2026-07.md](MANUAL_QA_HUMAN_2026-07.md) 를 따른다.

## 1. 런 메타

| 항목 | 값 |
|---|---|
| 실행 일자 | 2026-07-12 |
| 실행 환경 | Claude Code 원격 컨테이너(리눅스) — **adb·flutter·실기기 없음** |
| 레포 커밋 | `a91de81` |
| 브랜치 | `claude/android-qa-manual-2026-07-vwzdgm` |
| 상태 | **Phase 0 게이트 차단 — 기기 실행분 0/17** |
| 기기 슬롯 | T1(태블릿+스타일러스)·P1(폰) — 이번 세션 미연결 |

## 2. Phase 0 게이트 판정표

| # | 게이트 | 이번 세션 상태 | 근거·후속 조치 |
|---|---|---|---|
| ① | 기기 연결(`adb devices`) | **미충족** | 원격 컨테이너 — adb·실기기 없음. 로컬 PC 에서 T1/P1 연결 후 재판정 |
| ② | 화면 꺼짐 방지(stayon) | 해당 없음 | 기기 미연결로 설정 대상 자체가 없음. 기기 연결 후 적용 |
| ③ | 스타일러스 소스 확인 | **미확인** | stylus 이벤트 소스(SOURCE_STYLUS) 확인은 T1 실기기 필요 |
| ④ | `.env` 준비 | **미충족** | 레포에 `.env` 부재, `.env.example` 만 존재. **값(SUPABASE_URL·anon key)은 사용자가 로컬에서 직접 채운다**(본 문서·증적에 값 기록 금지) |
| ⑤ | 테스트 데이터 | **완료** | `docs/qa/2026-07/testdata/` 생성(PDF ①②③·이미지 4장·첨삭 대상 `qa-img5-annotate.jpg`·HEIC, [README](qa/2026-07/testdata/README.md)). HEIC 는 **변환본 사용** — 원산지 검증은 iOS QA(I1) 이월(§6) |
| ⑥ | 테스트 계정 | **미확인** | 사용자 확인 필요: 학생 계정 **캐시 잔액 ≥ 테스트 금액**, 멘토 계정 **질문방 연결 + IQ 지정 가능 상태** |
| ⑦ | 빌드·설치 | **미실행** | 컨테이너에 flutter 없음. 로컬에서 시트 §0-2 명령으로 수행 |

## 3. 판정 매트릭스 (17항목 × T1/P1)

> 이번 세션 기기 실행분 0/17 — 대상 셀은 전부 **미커버(환경)**. `—` 는 해당 기기 비대상.
> 로컬 실행 시 셀 값을 통과/실패/보류 로 갱신하고, 실패는 시트 §2 규약으로 실패 로그에 남긴다.
> 판정 주체는 역할 분담 기준: **adb 단독**(로컬 Claude adb 세션) / **하이브리드**(adb 이벤트
> 주입 + 사람 실물 확인) / **사람**(물리 수행, 런북 MANUAL_QA_HUMAN_2026-07.md).

| ID | 시나리오 | T1 | P1 | 판정 주체 | 비고 |
|---|---|---|---|---|---|
| A-1 | 촬영 권한 문구 | 미커버(환경) | 미커버(환경) | adb 단독 | 재설치 후 권한 대화상자 |
| A-2 | 촬영 권한 거부 | 미커버(환경) | 미커버(환경) | adb 단독 | "다시 묻지 않음" 포함 |
| A-3 | HEIC | 미커버(환경) | 미커버(환경) | adb 단독 | 변환본 HEIC 사용 — 원산지 검증 iOS 이월(§6) |
| A-4 | 크기 캡 실효 | — | 미커버(환경) | 사람 | 최고화소 촬영은 물리 수행, 산출물 판정은 Claude(런북 §4) |
| A-5 | PDF 일반(S19) | 미커버(환경) | 미커버(환경) | adb 단독 | qa-pdf1 9pt 판정 문단 기준 |
| A-6 | PDF 대용량(S19) | 미커버(환경) | 미커버(환경) | adb 단독 | P1(성능 하한) 우선. §4 계측 기록 필수 |
| A-7 | PDF 암호화(S19) | 미커버(환경) | 미커버(환경) | adb 단독 | qa-pdf3 폴백 문구 확인 |
| A-8 | 슬롯 연동(S19) | 미커버(환경) | 미커버(환경) | adb 단독 | 이미지 4장 + PDF ① |
| B-1 | 필압(의도된 off) | 미커버(환경) | — | 사람 | 스타일러스 필압은 adb 재현 불가 |
| B-2 | 팜 리젝션 | 미커버(환경) | — | 하이브리드 | stylus/finger 이벤트 대조=adb, 실손바닥(대면적)=사람 |
| B-3 | 좌표 정합(줌) | 미커버(환경) | — | 사람 | 핀치줌은 adb 멀티터치 재현 불가(판정은 캡처 대조) |
| B-4 | 기기 간 정합 | 미커버(환경) | 미커버(환경) | adb 단독 | **2대 필요 — 1대뿐이면 보류** |
| B-5 | 학생↔멘토 왕복(S17~S18 통합) | 미커버(환경) | 미커버(환경) | adb 단독 | 2대 교차가 기본. **1대면 축소 모드**(계정 전환 왕복, §6 기록) |
| B-6 | PDF→필기 연계(S19) | 미커버(환경) | — | adb 단독 | 필기 규약은 T1 기준 |
| C-1 | 한글 IME 조합 | — | 미커버(환경) | adb 단독(조건부 사람) | ADBKeyboard 미승인·조합 재현 실패 시에만 사람 이관(런북 §0-4) |
| C-2 | 소형 기기 키보드 | — | 미커버(환경) | adb 단독 | –360dp 소형 화면 전용 |
| C-3 | 수식 특수문자 | 미커버(환경) | 미커버(환경) | adb 단독(조건부 사람) | P1 전송↔T1 수신. 조건부 이관 규칙 C-1 과 동일 |

## 4. 계측 기록 템플릿 — A-6 메모리 (dumpsys meminfo)

측정 명령(각 시점, 기기별 `-s <serial>`):

```bash
adb shell dumpsys meminfo com.ssambership.edu | head -40
```

| 기기 | 시점 | TOTAL PSS (KB) | Java Heap | Native Heap | Graphics | 비고 |
|---|---|---|---|---|---|---|
| P1 | 그리드 진입 전 | | | | | |
| P1 | 스크롤 중(왕복) | | | | | |
| P1 | 가져오기 완료 후 | | | | | |
| T1 | 그리드 진입 전 | | | | | |
| T1 | 스크롤 중(왕복) | | | | | |
| T1 | 가져오기 완료 후 | | | | | |

logcat OOM 감시(그리드 스크롤~가져오기 완료 동안 병행):

```bash
adb logcat -v time | grep -E "OutOfMemory|lowmemorykiller|onTrimMemory|Ssambership.*(OOM|memory)"
```

| 감시 항목 | 결과 |
|---|---|
| OutOfMemoryError / lowmemorykiller 발생 | (미실행) |
| 프로세스 사망·재시작 여부 | (미실행) |

## 5. 증적 색인

- 규약(시트 §2·런북 §0-2 동일): `docs/qa/2026-07/<항목ID>-<n>.png` — 스크린샷은 `.png`,
  기기에서 pull 한 바이너리는 원본 확장자 유지(예: `A-4-2.jpg`). 통과·실패 공통으로 커밋에 포함.
- **현재 증적: 0건**(기기 실행분 없음).
- 테스트 데이터: [docs/qa/2026-07/testdata/README.md](qa/2026-07/testdata/README.md) — 파일
  매니페스트(sha256)·기기 push 절차·qa-pdf3 비밀번호. `make_testdata.py` 1회 실행으로 재생성.

## 6. 대체물·축소 모드 기록

| 항목 | 대체물/축소 내용 | 이월·후속 |
|---|---|---|
| A-3 HEIC | `qa-heic-converted.heic`(qa-img1 변환본, iPhone 원본 아님)로 Android 디코딩·변환 산출물 경로만 확인 | **원산지 검증(iPhone 촬영 원본 메타데이터·업로드 경로)은 iOS QA(I1)로 이월** |
| B-4 | (자리) 1대 실행이 되면 '보류' 기록 | 2대 확보 후 재실행 |
| B-5 | (자리) 1대 실행 시 축소 모드(단일 기기 계정 전환 왕복) 사용 여부 기록 | 2대 교차 실행으로 상향 권장 |
| 기타 | (자리) | |

## 7. 다음 실행 절차 요약 (로컬 PC 재개 체크리스트)

로컬 PC `C:\dev\ssambership-app` 에서 순서대로:

1. [ ] `git fetch && git checkout claude/android-qa-manual-2026-07-vwzdgm` (커밋 `a91de81` 이후 상태 확인)
2. [ ] `.env` 작성 — `cp .env.example .env` 후 운영 값 입력(값은 어떤 문서에도 기록하지 않음)
3. [ ] `flutter pub get`
4. [ ] 빌드 — `flutter build apk --debug --dart-define=IQ_CREATE_ENABLED=true` (**debug** — A-4 의 run-as 증적 확보 전제. 반복 실행은 `flutter run --dart-define=IQ_CREATE_ENABLED=true`)
5. [ ] 설치 — `adb install -r build/app/outputs/flutter-apk/app-debug.apk` (T1·P1 각각 `-s <serial>`)
6. [ ] 테스트 데이터 push — `adb push docs/qa/2026-07/testdata/. /sdcard/Download/qa/` (양 기기, testdata README §3)
7. [ ] Phase 0 잔여 게이트 재판정(§2 ①②③⑥) 후 **Phase 1(adb 단독 항목)부터** 실행 — 물리 항목은 MANUAL_QA_HUMAN_2026-07.md 런북으로, 결과는 본 문서 §3~§6 갱신

> 실기기에서는 capture-screenshots.md 의 에뮬레이터 좌표탭이 통하지 않으므로 좌표 탭
> 내비게이션을 쓰지 않는다(런북 머리말 동일 규칙).
