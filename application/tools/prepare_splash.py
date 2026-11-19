#!/usr/bin/env python3
"""Prepares the Android 12+ version of the launch-screen picture.

Run from the application/ folder after placing branding/splash_img.png:

    pip install pillow
    python tools/prepare_splash.py

It checks branding/splash_img.png and writes branding/splash_img_android12.png: the same picture, never cropped or
stretched, scaled down onto a transparent 1024 x 1024 canvas so that it fits inside the circle Android 12 and newer
cut every launch icon to. (Android 12+ draws only an icon in that circle; it cannot show a full-height picture.)
Older Android versions use branding/splash_img.png itself, shown at full height.
"""
import math
import sys
from pathlib import Path

from PIL import Image

SRC = Path("branding/splash_img.png")
OUT = Path("branding/splash_img_android12.png")
CANVAS = 1024
# Android 12 shows the icon inside a circle of 2/3 of the canvas width. The artwork's diagonal stays inside 66% of it,
# the same safe area the app logo uses.
SAFE_DIAMETER = int(CANVAS * 0.66)


def main() -> int:
    if not SRC.exists():
        print(f"Missing {SRC}. Place your picture there first (see branding/README.md).")
        return 1
    img = Image.open(SRC).convert("RGBA")
    w, h = img.size
    print(f"{SRC}: {w} x {h} px (aspect {w / h:.3f})")
    if h <= w:
        print("Note: this is meant for a vertical (portrait) picture; yours is not taller than wide.")
    if h < 1400:
        print("Warning: under 1400 px tall will look soft on large phones. 1920 px tall is recommended.")
    if h > 2400 or w > 1300:
        print("Warning: larger than needed. Around 1080 x 1920 px is plenty and keeps the app small.")
    print(
        f"Older Android shows it about {h / 4:.0f} dp tall and {w / 4:.0f} dp wide "
        "(1 dp = source pixels / 4); a phone screen is usually 640-900 dp tall."
    )

    # Fit the visible artwork (not the empty margin around it) inside the safe circle, keeping the aspect ratio.
    box = img.getchannel("A").getbbox() or (0, 0, w, h)
    art = img.crop(box)
    aw, ah = art.size
    scale = SAFE_DIAMETER / math.hypot(aw, ah)
    nw, nh = max(1, round(aw * scale)), max(1, round(ah * scale))
    art = art.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(art, ((CANVAS - nw) // 2, (CANVAS - nh) // 2), art)
    canvas.save(OUT)
    print(f"Wrote {OUT} ({nw} x {nh} px picture on a {CANVAS} x {CANVAS} canvas).")
    print("Next: dart run flutter_native_splash:create")
    return 0


if __name__ == "__main__":
    sys.exit(main())
