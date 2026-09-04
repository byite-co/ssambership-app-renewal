# 2026-07 실기기 QA 테스트 데이터

> `docs/MANUAL_QA_RUN_2026-07.md` §0-3 준비물(PDF ①②③·이미지·HEIC)의 실제 파일.
> 전부 `python3 docs/qa/2026-07/make_testdata.py` 1회 실행으로 재생성된다(이 README 포함).

## 1. 파일 매니페스트

| 파일 | 용도 | 대응 QA 항목 | 크기 | sha256(12) |
|---|---|---|---|---|
| `qa-pdf1-normal.pdf` | PDF ① 일반 — 4p 문제지(수식+한글, 9pt 판정 문단 포함) | A-5, A-8, B-6 | 8 KB | `5b3e52d08a9b` |
| `qa-pdf2-large-60p.pdf` | PDF ② 대용량 — 60p, 초대형 페이지 번호(그리드 식별) | A-6 | 43 KB | `5f31005d0581` |
| `qa-pdf3-encrypted.pdf` | PDF ③ 암호화 — PDF ① AES-256 잠금(폴백 문구 확인) | A-7 | 9 KB | `d711bc72aefa` |
| `qa-img1.jpg` | 빨강 배경 + 숫자 1 (1200×1600) | A-8, B-5 | 48 KB | `b2ca8f6d219c` |
| `qa-img2.jpg` | 파랑 배경 + 숫자 2 (1200×1600) | A-8, B-5 | 54 KB | `243791070ed1` |
| `qa-img3.jpg` | 초록 배경 + 숫자 3 (1200×1600) | A-8, B-5 | 54 KB | `89225ac4f243` |
| `qa-img4.jpg` | 노랑 배경 + 숫자 4 (1200×1600) | A-8, B-5 | 56 KB | `dc496c3fb4a7` |
| `qa-img5-annotate.jpg` | 첨삭 대상 문제지 스타일 — 미세 텍스트 행 L01~L12, B-3 밑줄 대상 L07 'K', 정렬 십자 | B-1, B-2, B-3 | 141 KB | `ca4f1e7470d5` |
| `qa-heic-converted.heic` | qa-img1 의 HEIC 변환본(아이폰 원본 아님) | A-3(보조) | 24 KB | `d8b7b87c1651` |

- 합계 437 KB. `qa-pdf3-encrypted.pdf` 는 암호화 /ID 가 랜덤이라 **재생성 시 sha256 이 변동**된다(매니페스트는 스크립트가 매 실행 갱신).
- `qa-pdf1-normal.pdf` 각 페이지에 **[A-5 판정 기준] 라벨이 붙은 9pt 문단** 3줄이 있다. 확대 시 이 문단이 뭉개짐 없이 읽히면 A-5 통과.
- 한글 본문은 reportlab 내장 CID 폰트(HYSMyeongJo-Medium, 비임베드)라서 일부 PC 뷰어는 대체 폰트로 표시할 수 있다. 판정은 **기기(Android 렌더러) 화면 기준**.
- `qa-img5-annotate.jpg` 는 B-1~B-3 첨삭 대상용이다: 미세 텍스트 행 L01~L12(9pt급), **B-3 밑줄 대상 = L07 행의 문자 `K`**(±글자 반폭 판정), 네 모서리 정렬 십자(전송본 이미지 대조 정렬 기준). 생성 환경에 한글 래스터 폰트가 없어 본문은 라틴/수식 문자만 사용 — 밑줄 **위치** 판정에는 문자 종류가 무관하다.

## 2. qa-pdf3 비밀번호

| 항목 | 값 |
|---|---|
| user/owner password | `qa-lock-2026` |
| 알고리즘 | AES-256 (pikepdf R=6) |

> A-7 은 비밀번호 입력이 아니라 **"이 PDF는 열 수 없어요…" 폴백 문구** 확인이 목적. 비밀번호는 파일 상태 재검증용으로만 사용.

## 3. 기기 배치 (adb push → /sdcard/Download/qa/)

로컬 PC 레포 루트(`C:\dev\ssambership-app`)에서 실행. 기기가 2대 이상이면 모든 `adb` 에 `-s <serial>` 을 붙인다(`adb devices` 로 확인 — 예: T1 태블릿·P1 폰에 각각 push).

PowerShell:

```powershell
adb shell mkdir -p /sdcard/Download/qa
Get-ChildItem docs\qa\2026-07\testdata -File | ForEach-Object { adb push $_.FullName /sdcard/Download/qa/ }
# 다중 기기 예: adb -s R3CX90ABCDE push docs\qa\2026-07\testdata\qa-pdf1-normal.pdf /sdcard/Download/qa/
```

bash:

```bash
adb shell mkdir -p /sdcard/Download/qa
adb push docs/qa/2026-07/testdata/. /sdcard/Download/qa/
# 다중 기기 예: adb -s emulator-5554 push docs/qa/2026-07/testdata/. /sdcard/Download/qa/
```

- 파일 선택기(SAF)의 Download > qa 폴더에서 즉시 보인다. 갤러리·이미지 선택기에 jpg 가 안 뜨면 미디어 스캔 후 재시도:
  `adb shell content call --method scan_volume --uri content://media --arg external_primary`

## 4. HEIC 변환본 주의

`qa-heic-converted.heic` 는 **qa-img1.jpg 를 pillow_heif 로 변환한 파일**이며 iPhone 촬영 원본이 아니다.
A-3 의 원산지 검증(iPhone 촬영 원본 HEIC 의 메타데이터·업로드 경로)은 **iOS QA(I1 기기)로 이월**하고,
이 파일은 Android '파일' 소스에서 HEIC 디코딩·변환 산출물(PNG/JPEG) 경로가 도는지 보는 보조용으로만 쓴다.
