#!/usr/bin/env python3
"""2026-07 실기기 QA 테스트 데이터 생성 스크립트.

docs/MANUAL_QA_RUN_2026-07.md §0-3 준비물(PDF ①②③·이미지·HEIC)을
docs/qa/2026-07/testdata/ 에 전부 재생성한다(README.md 매니페스트 포함).

실행(레포 루트 어디서든 가능):
    python3 docs/qa/2026-07/make_testdata.py

의존성: reportlab, pikepdf, Pillow, pillow_heif (모두 pip 설치본)
주의: qa-pdf3-encrypted.pdf 는 암호화 시 /ID 가 랜덤이라 재생성 때마다
      sha256 이 달라진다(README 매니페스트는 본 스크립트가 매 실행 갱신).
"""

import hashlib
import sys
from pathlib import Path

import pikepdf
import pillow_heif
from PIL import Image, ImageDraw, ImageFont
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.pdfgen import canvas

BASE = Path(__file__).resolve().parent          # docs/qa/2026-07/
OUT = BASE / "testdata"
OUT.mkdir(parents=True, exist_ok=True)

KO = "HYSMyeongJo-Medium"                        # reportlab 내장 한글 CID 폰트(비임베드)
PDF3_PASSWORD = "qa-lock-2026"
DIGIT_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

pdfmetrics.registerFont(UnicodeCIDFont(KO))


# ---------------------------------------------------------------- qa-pdf1
def make_pdf1(path: Path) -> None:
    """4페이지 문제지 스타일 — 텍스트+수식, 페이지별 식별 문구, 9pt 판정 문단."""
    w, h = A4
    c = canvas.Canvas(str(path), pagesize=A4, invariant=1)
    c.setTitle("QA-PDF1 일반 문제지 (2026-07)")

    idents = [
        ("은하수 ALPHA-01", "이차방정식", "문제 1. 이차방정식 x²+3x−10=0 의 두 근을 구하고, 두 근의 합과 곱을 쓰시오."),
        ("소나무 BRAVO-02", "무리수", "문제 2. √2 와 √8 의 곱을 간단히 하고, 그 값이 4 ≤ x ≤ 5 를 만족하는지 판별하시오."),
        ("바닷길 CHARLIE-03", "수열의 합", "문제 3. ∑ 기호를 사용하여 1부터 n까지 자연수의 합을 나타내고, n=20 일 때 값을 구하시오."),
        ("달빛 DELTA-04", "부등식", "문제 4. 부등식 x²+3x−10 ≤ 0 의 해를 수직선 위에 나타내시오. (√ 값은 근사 없이 그대로 둘 것)"),
    ]
    for n, (ident, topic, problem) in enumerate(idents, start=1):
        # 초대형 페이지 번호(우상단)
        c.setFont("Helvetica-Bold", 64)
        c.drawRightString(w - 40, h - 88, f"P.{n}")
        # 머리글
        c.setFont(KO, 15)
        c.drawString(48, h - 60, f"QA-PDF1 일반 문제지 — {n}/4 페이지")
        c.setFont(KO, 11)
        c.drawString(48, h - 82, f"식별 문구: {ident} / 단원: {topic}")
        c.line(48, h - 96, w - 48, h - 96)

        # 문제 본문(12pt)
        c.setFont(KO, 12)
        y = h - 130
        c.drawString(48, y, problem)
        y -= 22
        c.drawString(48, y, "보기: ① x=2, x=−5   ② x=−2, x=5   ③ √2 ≤ x   ④ ∑k = n(n+1)/2")
        y -= 40

        # 9pt 판정 문단 — A-5 확대 화질 판정 기준
        c.setFont(KO, 10)
        c.drawString(48, y, "[A-5 판정 기준] 아래 문단이 '9pt 본문 화질 판정 기준 문자열'이다.")
        y -= 16
        c.drawString(48, y, "확대(장변 2560 렌더) 시 아래 9pt 문단이 뭉개짐 없이 읽히면 통과.")
        y -= 20
        c.setFont(KO, 9)
        for line in (
            f"(9pt) 페이지 {n} 판정 문단: 다람쥐 헌 쳇바퀴에 타고파. 정확한 판별식은 b²−4ac 이며,",
            "(9pt) 근의 공식은 x = (−b ± √(b²−4ac)) / 2a 이다. 획이 겹치기 쉬운 글자: 뷁 홟 쀍 빫 쁿.",
            "(9pt) 숫자·기호 대비: 0O 1lI 5S 8B, ≤ ≥ ∑ √ − ± × ÷. 이 세 줄이 모두 읽히는지 확인한다.",
        ):
            c.drawString(48, y, line)
            y -= 14

        # 바닥글
        c.setFont(KO, 9)
        c.drawCentredString(w / 2, 36, f"쌤버십 QA 문제지 · {ident} · {n}/4")
        c.showPage()
    c.save()


# ---------------------------------------------------------------- qa-pdf2
def make_pdf2(path: Path) -> None:
    """60페이지 — 초대형 페이지 번호(썸네일 그리드 식별) + 간단 본문. 1MB 이내."""
    w, h = A4
    c = canvas.Canvas(str(path), pagesize=A4, invariant=1)
    c.setTitle("QA-PDF2 대용량 60p (2026-07)")
    for n in range(1, 61):
        c.setFont("Helvetica-Bold", 300)
        c.drawCentredString(w / 2, h / 2 - 100, str(n))
        c.setFont(KO, 14)
        c.drawCentredString(w / 2, h - 60, f"QA-PDF2 대용량 문제집 — {n}/60 페이지")
        c.setFont(KO, 10)
        c.drawCentredString(w / 2, 40, "A-6 그리드 스크롤·지연 로드·메모리 확인용 더미 본문")
        c.showPage()
    c.save()


# ---------------------------------------------------------------- qa-pdf3
def make_pdf3(src: Path, path: Path) -> None:
    """qa-pdf1 을 AES-256(R=6) user password 로 암호화."""
    with pikepdf.open(src) as pdf:
        pdf.save(
            path,
            encryption=pikepdf.Encryption(user=PDF3_PASSWORD, owner=PDF3_PASSWORD, R=6),
        )


# ---------------------------------------------------------------- images
IMG_SPECS = [
    ("qa-img1.jpg", "1", (198, 40, 40), (255, 255, 255), "QA-IMG-1 RED"),
    ("qa-img2.jpg", "2", (21, 101, 192), (255, 255, 255), "QA-IMG-2 BLUE"),
    ("qa-img3.jpg", "3", (46, 125, 50), (255, 255, 255), "QA-IMG-3 GREEN"),
    ("qa-img4.jpg", "4", (249, 200, 14), (0, 0, 0), "QA-IMG-4 YELLOW"),
]


def make_images() -> None:
    """1200×1600, 배경색 4종(빨/파/초/노) + 중앙 초대형 숫자 + 하단 라벨 (A-8)."""
    big = ImageFont.truetype(DIGIT_FONT, 900)
    small = ImageFont.truetype(DIGIT_FONT, 72)
    for name, digit, bg, fg, label in IMG_SPECS:
        im = Image.new("RGB", (1200, 1600), bg)
        d = ImageDraw.Draw(im)
        d.text((600, 730), digit, font=big, fill=fg, anchor="mm")
        d.text((600, 1490), label, font=small, fill=fg, anchor="mm")
        im.save(OUT / name, "JPEG", quality=85)


def make_annotate_image(path: Path) -> None:
    """B-1~B-3 첨삭 대상 — 종이 질감 문제지 스타일 1200×1600.

    미세 텍스트 행(L01~L12)과 B-3 밑줄 대상 행(L07, 대상 문자 'K'),
    이미지 대조 정렬용 모서리 십자를 포함한다. 컨테이너에 한글 래스터 폰트가
    없어 본문은 라틴/수식 문자만 사용(밑줄 '위치' 판정에는 문자 종류 무관).
    """
    sans = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    paper, ink, faint = (247, 245, 239), (25, 25, 30), (150, 148, 140)
    im = Image.new("RGB", (1200, 1600), paper)
    d = ImageDraw.Draw(im)

    # 모서리 정렬 십자(전송본 diff 정렬 기준)
    for cx, cy in ((60, 60), (1140, 60), (60, 1540), (1140, 1540)):
        d.line((cx - 24, cy, cx + 24, cy), fill=ink, width=3)
        d.line((cx, cy - 24, cx, cy + 24), fill=ink, width=3)

    title = ImageFont.truetype(DIGIT_FONT, 44)
    label = ImageFont.truetype(DIGIT_FONT, 26)
    fine = ImageFont.truetype(sans, 19)          # 9pt급 미세 본문
    target = ImageFont.truetype(sans, 30)        # B-3 밑줄 대상 행

    d.text((600, 130), "QA-IMG-5 ANNOTATE TARGET", font=title, fill=ink, anchor="mm")
    d.text((600, 185), "B-1 / B-2 / B-3", font=label, fill=faint, anchor="mm")
    d.line((100, 220, 1100, 220), fill=ink, width=2)

    fine_text = "x²+3x−10=0   √2≈1.414   ∑k=n(n+1)/2   0O 1lI 5S 8B   ≤ ≥ ± × ÷"
    y = 290
    for n in range(1, 13):
        row = f"L{n:02d}"
        d.text((110, y), row, font=label, fill=faint, anchor="lm")
        if n == 7:
            # B-3 밑줄 대상 행 — 넓은 자간, 대상 문자는 'K'
            d.text((210, y), "T A R G E T :   H   J   K   L   M   N", font=target, fill=ink, anchor="lm")
        else:
            d.text((210, y), fine_text, font=fine, fill=ink, anchor="lm")
        y += 78

    d.line((100, y, 1100, y), fill=ink, width=2)
    d.text((600, y + 60), "B-3: zoom 300%+, underline the letter K on row L07", font=label, fill=ink, anchor="mm")
    d.text((600, y + 110), "then compare sent (flattened) image — tolerance: half char width", font=fine, fill=faint, anchor="mm")
    im.save(path, "JPEG", quality=88)


def make_heic(src: Path, path: Path) -> None:
    """qa-img1 → HEIC 변환본(아이폰 원본 아님 — README 주의 문구 참조)."""
    pillow_heif.register_heif_opener()
    with Image.open(src) as im:
        im.save(path, format="HEIF", quality=80)


# ---------------------------------------------------------------- verify
def sha12(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:12]


def verify() -> list[str]:
    """페이지 수·암호화·이미지 크기·HEIC 재오픈 검증. 실패 시 AssertionError."""
    notes: list[str] = []

    with pikepdf.open(OUT / "qa-pdf1-normal.pdf") as p:
        assert len(p.pages) == 4, f"pdf1 pages={len(p.pages)}"
        notes.append("qa-pdf1-normal.pdf: 4 pages OK")
    with pikepdf.open(OUT / "qa-pdf2-large-60p.pdf") as p:
        assert len(p.pages) == 60, f"pdf2 pages={len(p.pages)}"
        notes.append("qa-pdf2-large-60p.pdf: 60 pages OK")
    assert (OUT / "qa-pdf2-large-60p.pdf").stat().st_size < 1024 * 1024, "pdf2 >= 1MB"

    # 암호화: 비밀번호 없이 열면 PasswordError 여야 한다
    try:
        pikepdf.open(OUT / "qa-pdf3-encrypted.pdf")
        raise AssertionError("pdf3 opened WITHOUT password — encryption missing")
    except pikepdf.PasswordError:
        notes.append("qa-pdf3-encrypted.pdf: no-password open -> PasswordError OK")
    with pikepdf.open(OUT / "qa-pdf3-encrypted.pdf", password=PDF3_PASSWORD) as p:
        assert len(p.pages) == 4
        assert p.is_encrypted
        notes.append(
            f"qa-pdf3-encrypted.pdf: password open OK (4 pages, R={p.encryption.R})"
        )

    for name, *_ in IMG_SPECS:
        with Image.open(OUT / name) as im:
            assert im.size == (1200, 1600), f"{name} size={im.size}"
    notes.append("qa-img1~4.jpg: 1200x1600 OK")

    with Image.open(OUT / "qa-img5-annotate.jpg") as im:
        assert im.size == (1200, 1600), f"qa-img5 size={im.size}"
    notes.append("qa-img5-annotate.jpg: 1200x1600 OK")

    pillow_heif.register_heif_opener()
    with Image.open(OUT / "qa-heic-converted.heic") as im:
        assert im.size == (1200, 1600)
        notes.append(f"qa-heic-converted.heic: reopen OK ({im.format} {im.size[0]}x{im.size[1]})")

    return notes


# ---------------------------------------------------------------- README
MANIFEST = [
    ("qa-pdf1-normal.pdf", "PDF ① 일반 — 4p 문제지(수식+한글, 9pt 판정 문단 포함)", "A-5, A-8, B-6"),
    ("qa-pdf2-large-60p.pdf", "PDF ② 대용량 — 60p, 초대형 페이지 번호(그리드 식별)", "A-6"),
    ("qa-pdf3-encrypted.pdf", "PDF ③ 암호화 — PDF ① AES-256 잠금(폴백 문구 확인)", "A-7"),
    ("qa-img1.jpg", "빨강 배경 + 숫자 1 (1200×1600)", "A-8, B-5"),
    ("qa-img2.jpg", "파랑 배경 + 숫자 2 (1200×1600)", "A-8, B-5"),
    ("qa-img3.jpg", "초록 배경 + 숫자 3 (1200×1600)", "A-8, B-5"),
    ("qa-img4.jpg", "노랑 배경 + 숫자 4 (1200×1600)", "A-8, B-5"),
    ("qa-img5-annotate.jpg", "첨삭 대상 문제지 스타일 — 미세 텍스트 행 L01~L12, B-3 밑줄 대상 L07 'K', 정렬 십자", "B-1, B-2, B-3"),
    ("qa-heic-converted.heic", "qa-img1 의 HEIC 변환본(아이폰 원본 아님)", "A-3(보조)"),
]

README_TEMPLATE = """# 2026-07 실기기 QA 테스트 데이터

> `docs/MANUAL_QA_RUN_2026-07.md` §0-3 준비물(PDF ①②③·이미지·HEIC)의 실제 파일.
> 전부 `python3 docs/qa/2026-07/make_testdata.py` 1회 실행으로 재생성된다(이 README 포함).

## 1. 파일 매니페스트

| 파일 | 용도 | 대응 QA 항목 | 크기 | sha256(12) |
|---|---|---|---|---|
{rows}

- 합계 {total_kb} KB. `qa-pdf3-encrypted.pdf` 는 암호화 /ID 가 랜덤이라 **재생성 시 sha256 이 변동**된다(매니페스트는 스크립트가 매 실행 갱신).
- `qa-pdf1-normal.pdf` 각 페이지에 **[A-5 판정 기준] 라벨이 붙은 9pt 문단** 3줄이 있다. 확대 시 이 문단이 뭉개짐 없이 읽히면 A-5 통과.
- 한글 본문은 reportlab 내장 CID 폰트(HYSMyeongJo-Medium, 비임베드)라서 일부 PC 뷰어는 대체 폰트로 표시할 수 있다. 판정은 **기기(Android 렌더러) 화면 기준**.
- `qa-img5-annotate.jpg` 는 B-1~B-3 첨삭 대상용이다: 미세 텍스트 행 L01~L12(9pt급), **B-3 밑줄 대상 = L07 행의 문자 `K`**(±글자 반폭 판정), 네 모서리 정렬 십자(전송본 이미지 대조 정렬 기준). 생성 환경에 한글 래스터 폰트가 없어 본문은 라틴/수식 문자만 사용 — 밑줄 **위치** 판정에는 문자 종류가 무관하다.

## 2. qa-pdf3 비밀번호

| 항목 | 값 |
|---|---|
| user/owner password | `{password}` |
| 알고리즘 | AES-256 (pikepdf R=6) |

> A-7 은 비밀번호 입력이 아니라 **"이 PDF는 열 수 없어요…" 폴백 문구** 확인이 목적. 비밀번호는 파일 상태 재검증용으로만 사용.

## 3. 기기 배치 (adb push → /sdcard/Download/qa/)

로컬 PC 레포 루트(`C:\\dev\\ssambership-app`)에서 실행. 기기가 2대 이상이면 모든 `adb` 에 `-s <serial>` 을 붙인다(`adb devices` 로 확인 — 예: T1 태블릿·P1 폰에 각각 push).

PowerShell:

```powershell
adb shell mkdir -p /sdcard/Download/qa
Get-ChildItem docs\\qa\\2026-07\\testdata -File | ForEach-Object {{ adb push $_.FullName /sdcard/Download/qa/ }}
# 다중 기기 예: adb -s R3CX90ABCDE push docs\\qa\\2026-07\\testdata\\qa-pdf1-normal.pdf /sdcard/Download/qa/
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
"""


def write_readme() -> None:
    rows = []
    total = 0
    for name, purpose, qa_ids in MANIFEST:
        p = OUT / name
        size = p.stat().st_size
        total += size
        rows.append(f"| `{name}` | {purpose} | {qa_ids} | {size / 1024:.0f} KB | `{sha12(p)}` |")
    (OUT / "README.md").write_text(
        README_TEMPLATE.format(
            rows="\n".join(rows),
            total_kb=f"{total / 1024:.0f}",
            password=PDF3_PASSWORD,
        ),
        encoding="utf-8",
    )
    assert total < 3 * 1024 * 1024, f"total {total} bytes >= 3MB budget"


# ---------------------------------------------------------------- main
def main() -> int:
    pdf1 = OUT / "qa-pdf1-normal.pdf"
    make_pdf1(pdf1)
    make_pdf2(OUT / "qa-pdf2-large-60p.pdf")
    make_pdf3(pdf1, OUT / "qa-pdf3-encrypted.pdf")
    make_images()
    make_annotate_image(OUT / "qa-img5-annotate.jpg")
    make_heic(OUT / "qa-img1.jpg", OUT / "qa-heic-converted.heic")

    for note in verify():
        print("[verify]", note)
    write_readme()

    total = sum((OUT / name).stat().st_size for name, *_ in MANIFEST)
    print(f"[done] {len(MANIFEST)} files + README.md, total {total / 1024:.0f} KB -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
