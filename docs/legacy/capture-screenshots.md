# 전 화면 스크린샷 캡처 절차 (에뮬레이터 + adb)

> 쌤버십 **앱(Flutter)** 출시범위 전 세부화면을 실제 백엔드(로컬 Supabase) 연결 상태로
> Android 에뮬레이터에서 캡처하는 재현 절차입니다. **앱 코드 로직/디자인 변경 없이 캡처만** 합니다.

Flutter는 화면을 캔버스로 렌더링하므로 uiautomator가 위젯 트리를 읽지 못합니다.
따라서 이 절차는 **좌표 탭(coordinate-tap) 기반 시각 내비게이션**으로 진행합니다.

---

## 1. 사전 준비 (Prerequisites)

### 1-1. 로컬 Supabase (실제 데이터/시드)
웹 저장소에서 로컬 스택을 띄웁니다. **웹 저장소 실제 경로는 `D:\dev\ssambership_web`** 입니다.

```powershell
# Docker Desktop 기동 확인 후
cd D:\dev\ssambership_web
npx supabase start        # 로컬 54321 + 시드 반영
```

- 로컬 스택은 `http://127.0.0.1:54321` 에서 뜹니다.
- 앱은 Android 에뮬레이터에서 `127.0.0.1` 을 **자동으로 `10.0.2.2` 로 변환**합니다
  (`lib/core/config/app_config.dart`). 에뮬레이터에서 호스트 로컬 Supabase에 그대로 붙습니다.
- `.env` 는 로컬 값을 사용합니다(별도 수정 불필요).

### 1-2. 에뮬레이터 (ssam_test)
- AVD 이름: **`ssam_test`** (Pixel 6, API 36).
- 부팅:
  ```powershell
  # 에뮬레이터
  & "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -avd ssam_test
  # 부팅 확인
  & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices   # emulator-5554  device
  ```

### 1-3. 앱 실행
JDK는 Android Studio 내장(jbr)을 사용합니다.

```powershell
cd C:\dev\ssambership_app
flutter run -d emulator-5554
```

- 앱 패키지: `com.ssambership.edu`
- 앱이 홈으로 튕겼을 때 재실행(세션 유지):
  ```powershell
  adb -s emulator-5554 shell monkey -p com.ssambership.edu -c android.intent.category.LAUNCHER 1
  ```

### 1-4. 개별질문(IQ) 플래그
IQ 화면은 `kIndividualQuestionEnabled = true` 일 때만 노출됩니다. 활성 상태를 확인하세요
(현재 기본 활성).

---

## 2. 시드 계정 (비밀번호 공통 `Local!Test1234`)

| 역할 | 이메일 | 용도 |
|------|--------|------|
| 학생(정상 플로우) | `local.student@ssam.test` | 구독/방/질문/연결노트/커뮤니티 등 전 학생 화면 |
| 멘토(가격설정) | `local.mentor.priced@ssam.test` | 멘토 인박스/답변/대시보드 |
| 학생(빈 상태) | `seed.student4@ssam.test` | 구독·질문방·알림·지갑 EmptyState (데이터 없음) |

> 새 질문 작성은 **잔여 질문권이 남은 방**이 필요합니다. `local.student` 기준
> **가격미설정멘토(잔여 4/4)** 방을 사용합니다(가격설정멘토는 0/4로 소진).
> 연결노트 **빈 상태**도 노트 0개인 가격미설정멘토 방에서 확인합니다.

---

## 3. ★ 로그인 함정 (반드시 준수)

로그인 화면에서 **키보드가 뜨면 폼이 위로 밀려**, 그 상태로 다음 필드를 탭하면
좌표가 어긋나 비밀번호가 이메일칸에 들어가는 등 오입력 → 400 이 납니다.

**해결: 각 입력 필드를 "키보드 닫힌 상태"에서 탭한다.**

```bash
ADB="…/adb.exe"; D="$ADB -s emulator-5554"
# 1) 이메일칸(정지 좌표) 탭 → 키보드 열림 → 입력
$D shell input tap 540 1056
$D shell input text "seed.student4@ssam.test"
$D shell input keyevent 4          # 키보드 닫기(폼 정지 복귀)
# 2) 비번칸(정지 좌표) 탭 → 입력
$D shell input tap 540 1205
$D shell input text "Local!Test1234"
$D shell input keyevent 4          # 키보드 닫기
# 3) 로그인 버튼
$D shell input tap 540 1404
```

> 주의: "둘러보기(게스트)" 진입 후 질문방을 누르면 로그인 화면에
> **"로그인이 필요해요" 배너**가 추가되어 입력 필드가 아래로 밀립니다.
> 이때는 위 정지 좌표가 아니라 **배너만큼 내려간 좌표**로 탭하거나, 앱을 재실행해
> 배너 없는 깨끗한 로그인 화면에서 위 좌표를 사용하세요.

---

## 4. 캡처 명령

```bash
adb -s emulator-5554 exec-out screencap -p > "역할-순번-화면.png"
```

원본 해상도 **1080×2400**. (Read 툴 표시 배율 900×2000 → 좌표는 ×1.2 로 원본 매핑.)

### 하단 탭 좌표(원본 기준)
| 탭 | 좌표(x, y) |
|----|-----------|
| 질문방 | (90, 2228) |
| 커뮤니티 | (318, 2228) |
| 멘토 찾기 | (540, 2228) |
| 알림 | (750, 2228) |
| 마이페이지 | (978, 2228) |

---

## 5. 캡처 대상 · 화면 순서 (출시범위)

> 제외: **맞춤의뢰(CR)·admin** = 앱에 화면 파일 없음, **onboarding** = 라우터 미연결.

### 공용 (pub-)
1. `pub-01-login` — 로그인 화면
2. `pub-02-login-required` — 게스트 진입 후 질문방 탭 → "로그인이 필요해요" 배너

### 학생 (stu-) — `local.student`
질문방목록 → 방홈 → 질문목록 → 채팅 → 연결노트 → 필기(ink) → 새질문 → 과목드롭다운 →
커뮤니티(숏폼/게시판/내활동) → 게시판상세 → 숏폼상세 → 멘토찾기 → 멘토상세 →
알림 → 마이페이지(상단/캐시/설정) → 프로필편집 → 개별질문(목록/작성/상세)

`stu-01`~`stu-24` (파일명 참조).

### 멘토 (mentor-) — `local.mentor.priced`
인박스 → 방홈 → 질문목록 → 답변 → 마이페이지(대시보드) → 프로필편집 → 개별질문(목록/상세)

`mentor-01`~`mentor-08`.

### 빈 상태 (empty-) — `seed.student4` (연결노트만 `local.student`)
- `empty-01-questionroom` — "아직 질문방이 없어요"
- `empty-02-subscription` — 마이페이지 "구독 중인 멘토가 없어요"
- `empty-03-notifications` — 알림 "새 알림이 없어요"
- `empty-04-wallet` — 마이페이지 캐시 "거래 내역이 없어요" (아래로 스크롤)
- `empty-05-connection-notes` — 노트 0개 방의 연결노트 EmptyState

---

## 6. 캡처하지 못한 화면 (사유)

| 화면 | 사유 |
|------|------|
| splash | 순간 전환(수백 ms) — 안정적 캡처 어려움. 로고는 로그인 상단과 동일 |
| blocked(차단) | admin/guest 차단 계정 시드 없음 — 화면 코드는 존재 |
| onboarding | 라우터에 미연결(도달 불가) |
| attachment_viewer(첨부 뷰어) | 시드에 첨부 데이터 없음 — 열 대상 없음 |
| scan_annotation(스캔 주석) | 시드에 스캔/이미지 데이터 없음 |

---

## 7. 산출물

- 캡처본: `screenshots_full_detail/` (역할-순번-화면.png)
- 압축: `app_screenshots_full_detail.zip`
- 스택 종료: `npx supabase stop` (D:\dev\ssambership_web), 에뮬레이터 종료.
