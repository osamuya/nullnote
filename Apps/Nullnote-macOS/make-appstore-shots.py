#!/usr/bin/env python3
"""App Store 用のスクリーンショットを作る。

    ./make-appstore-shots.py AppStore/src/*.png

規定サイズは 1280x800 / 1440x900 / 2560x1600 / 2880x1800 のいずれか。
**手元の窓の大きさは、まず一致しない。** そのまま出すと弾かれるので、
規定の画布（既定 2560x1600）の中央に置き直して余白を作る。

出力: AppStore/<元のファイル名>.png

## 元になる画像の撮り方

窓ひとつを、影なしで撮る:

    screencapture -o -w AppStore/src/01-editor.png

**ターミナルに画面収録の許可が要る。**
システム設定 → プライバシーとセキュリティ → 画面収録。
許可した後、ターミナルを再起動すること。

うまくいかないときは ⌘⇧4 → Space → 窓をクリックでもよい
（影が付くので `-o` 相当にはならないが、この道具が余白を作り直すので問題ない）。

## 背景色

ファイル名に `dark` を含むと暗い背景、それ以外は明るい背景になる。
アプリのテーマに合わせておくと、一覧で並んだときに落ち着く。
"""
import sys, os
from PIL import Image, ImageFilter

SIZES  = {"1280x800": (1280, 800), "1440x900": (1440, 900),
          "2560x1600": (2560, 1600), "2880x1800": (2880, 1800)}
CANVAS = SIZES["2560x1600"]    # --canvas で変えられる
MARGIN = 0.88                  # 画布に対する窓の最大占有率
LIGHT  = (242, 242, 245)
DARK   = (28, 28, 30)

def build(src, out, canvas):
    name = os.path.basename(src).lower()
    bg = DARK if "dark" in name else LIGHT
    shot = Image.open(src).convert("RGBA")

    # 画布に収まる最大倍率。拡大はしない（にじむため）。
    limit = (int(canvas[0] * MARGIN), int(canvas[1] * MARGIN))
    scale = min(limit[0] / shot.width, limit[1] / shot.height, 1.0)
    if scale < 1.0:
        shot = shot.resize((round(shot.width * scale), round(shot.height * scale)),
                           Image.LANCZOS)

    # 元が小さいと、余白ばかりの間の抜けた絵になる。**引き伸ばさずに知らせる。**
    if shot.width < limit[0] * 0.75 and shot.height < limit[1] * 0.75:
        print(f"    ⚠️  {os.path.basename(src)} は {shot.width}x{shot.height} と小さい。"
              f"Retina のまま撮り直すか --canvas 1280x800 を試す")

    sheet = Image.new("RGBA", canvas, bg + (255,))
    x = (canvas[0] - shot.width) // 2
    y = (canvas[1] - shot.height) // 2

    # 影。窓と背景の境目が溶けないよう、薄く敷く。
    shadow = Image.new("RGBA", canvas, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 70), (x, y + 12, x + shot.width, y + shot.height + 12))
    sheet = Image.alpha_composite(sheet, shadow.filter(ImageFilter.GaussianBlur(28)))

    sheet.paste(shot, (x, y), shot)
    # App Store はアルファを受け付けない。**必ず RGB に落とす。**
    sheet.convert("RGB").save(out, "PNG")
    print(f"    {out}  {canvas[0]}x{canvas[1]}")

if __name__ == "__main__":
    args = sys.argv[1:]
    canvas = CANVAS
    if "--canvas" in args:
        i = args.index("--canvas")
        canvas = SIZES[args[i + 1]]
        del args[i:i + 2]
    if not args:
        print(__doc__); sys.exit(1)
    here = os.path.dirname(os.path.abspath(__file__))
    dest = os.path.join(here, "AppStore")
    os.makedirs(dest, exist_ok=True)
    print("==> App Store 用に作り直す")
    for src in args:
        build(src, os.path.join(dest, os.path.basename(src)), canvas)
    print(f"\n    最低1枚、最大10枚。3〜5枚が読みやすい。")
