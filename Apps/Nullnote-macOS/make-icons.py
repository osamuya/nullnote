#!/usr/bin/env python3
"""元絵1枚から、アセットカタログのアイコン7枚を作り直す。

    ./make-icons.py <元絵.png>

元絵は **1024×1024 の正方形**。角丸はここで当てるので、元絵は角を立てたまま渡す。

## なぜ角丸をこちらで当てるか

macOS のアイコンは、1024 の画布に **824 の角丸四角**（半径 22.4%）で収める。
この形を焼き込まないと、Dock で四角いまま並び、他のアプリから浮く。
最低 OS が macOS 14 なので、システム側の自動整形には頼れない。
"""
import sys
from PIL import Image, ImageDraw

CANVAS = 1024
BODY = 824                      # 画布 1024 に対する本体の大きさ
RADIUS = round(BODY * 0.2237)   # macOS のアイコンの角丸
SUPERSAMPLE = 4                 # マスクは4倍で作ってから縮める。縁のギザギザ防止
SIZES = (16, 32, 64, 128, 256, 512, 1024)
DESTINATION = "Nullnote/Assets.xcassets/AppIcon.appiconset"


def rounded_mask(size: int, radius: int) -> Image.Image:
    big = size * SUPERSAMPLE
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, big - 1, big - 1], radius=radius * SUPERSAMPLE, fill=255
    )
    return mask.resize((size, size), Image.LANCZOS)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 1

    source = Image.open(sys.argv[1]).convert("RGBA")
    if source.width != source.height:
        print(f"正方形ではありません: {source.width}×{source.height}", file=sys.stderr)
        return 1

    body = source.resize((BODY, BODY), Image.LANCZOS)
    body.putalpha(rounded_mask(BODY, RADIUS))
    master = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    master.paste(body, ((CANVAS - BODY) // 2,) * 2, body)

    for size in SIZES:
        # 1024 から一発で縮める。中間サイズを経由すると縁が濁る。
        master.resize((size, size), Image.LANCZOS).save(f"{DESTINATION}/icon_{size}.png")
        print(f"icon_{size}.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
