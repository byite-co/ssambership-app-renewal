# verify.py — Google Play 스토어 스크린샷 규격 검증
#
# build/store-screenshots/phone/ 안의 PNG 전부를 검사해 표로 출력한다.
#
# 판정 기준 (Play Console 폰 스크린샷):
#   - 크기:  각 변 320~3840px
#   - 비율:  긴 변 / 짧은 변 <= 2.0   (Play 업로드 게이트)
#   - 형식:  PNG, 알파 채널 없음 (RGBA/LA/PA 는 FAIL)
#   - 용량:  8MB 이하
#   - 장수:  2~8장
#   - 추천 노출 조건(별도 집계): 각 변 1080px 이상인 것이 4장 이상
#
# 사용법:
#   python scripts/store-screenshots/verify.py
#   python scripts/store-screenshots/verify.py --fix    # 알파 채널 → 흰 배경 합성 후 RGB 저장
#   python scripts/store-screenshots/verify.py --dir <다른 폴더>

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Pillow 가 필요합니다:  pip install Pillow")
    sys.exit(1)

MIN_SIDE = 320
MAX_SIDE = 3840
MAX_RATIO = 2.0
MAX_BYTES = 8 * 1024 * 1024
MIN_COUNT, MAX_COUNT = 2, 8
PROMO_SIDE = 1080   # 추천(피처링) 노출 조건: 각 변 1080px 이상 4장 이상
PROMO_NEED = 4

ALPHA_MODES = {"RGBA", "LA", "PA"}


def has_alpha(img: Image.Image) -> bool:
    return img.mode in ALPHA_MODES or (img.mode == "P" and "transparency" in img.info)


def fix_alpha(path: Path) -> None:
    """알파 채널을 흰 배경에 합성해 RGB PNG 로 재저장한다."""
    with Image.open(path) as img:
        rgba = img.convert("RGBA")
        bg = Image.new("RGB", rgba.size, (255, 255, 255))
        bg.paste(rgba, mask=rgba.split()[3])
        bg.save(path, "PNG")


def main() -> int:
    default_dir = Path(__file__).resolve().parents[2] / "build" / "store-screenshots" / "phone"
    ap = argparse.ArgumentParser(description="Play 스토어 스크린샷 규격 검증")
    ap.add_argument("--dir", type=Path, default=default_dir, help=f"검사할 폴더 (기본: {default_dir})")
    ap.add_argument("--fix", action="store_true", help="알파 채널 발견 시 흰 배경 합성 후 RGB 로 재저장")
    args = ap.parse_args()

    folder: Path = args.dir
    if not folder.is_dir():
        print(f"폴더가 없습니다: {folder}")
        return 1

    files = sorted(folder.glob("*.png"))
    if not files:
        print(f"PNG 파일이 없습니다: {folder}")
        return 1

    rows = []
    promo_count = 0
    all_pass = True

    for f in files:
        problems = []
        with Image.open(f) as img:
            fmt = img.format
            w, h = img.size
            alpha = has_alpha(img)

        if fmt != "PNG":
            problems.append(f"형식 {fmt}")

        if alpha and args.fix:
            fix_alpha(f)
            alpha = False
            with Image.open(f) as img:
                w, h = img.size
            print(f"[fix] 알파 제거(흰 배경 합성) → RGB 저장: {f.name}")
        if alpha:
            problems.append("알파 채널(RGBA)")

        if not (MIN_SIDE <= w <= MAX_SIDE) or not (MIN_SIDE <= h <= MAX_SIDE):
            problems.append(f"크기 범위 밖({MIN_SIDE}~{MAX_SIDE})")

        ratio = max(w, h) / min(w, h)
        if ratio > MAX_RATIO:
            problems.append(f"비율 {ratio:.2f} > {MAX_RATIO}")

        size = f.stat().st_size
        if size > MAX_BYTES:
            problems.append("8MB 초과")

        if min(w, h) >= PROMO_SIDE:
            promo_count += 1

        ok = not problems
        all_pass = all_pass and ok
        rows.append((f.name, f"{w}x{h}", f"{ratio:.2f}", f"{size / 1024 / 1024:.2f}MB",
                     "PASS" if ok else "FAIL", ", ".join(problems) or "-"))

    # 표 출력
    headers = ("파일", "해상도", "비율", "용량", "판정", "문제")
    widths = [max(len(str(r[i])) for r in rows + [headers]) for i in range(len(headers))]
    def line(cols):
        return "  ".join(str(c).ljust(widths[i]) for i, c in enumerate(cols))
    print()
    print(line(headers))
    print(line(["-" * w for w in widths]))
    for r in rows:
        print(line(r))

    # 장수·추천 조건 집계
    print()
    count_ok = MIN_COUNT <= len(files) <= MAX_COUNT
    if not count_ok:
        all_pass = False
    print(f"장수: {len(files)}장 ({MIN_COUNT}~{MAX_COUNT}장) → {'PASS' if count_ok else 'FAIL'}")

    promo_ok = promo_count >= PROMO_NEED
    print(f"추천 노출 조건: 각 변 {PROMO_SIDE}px 이상 {promo_count}장 (필요 {PROMO_NEED}장 이상) → "
          f"{'충족' if promo_ok else '미충족 (업로드는 가능, 피처링 추천에서 제외될 수 있음)'}")

    print()
    print(f"전체 판정: {'PASS — 업로드 가능' if all_pass else 'FAIL — 위 문제를 해결하세요'}")
    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())
