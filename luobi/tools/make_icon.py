#!/usr/bin/env python3
"""Generate the Ulysses Native macOS app icon.

Style: calm, restrained, writer's tool. Rounded-square beige (#F2EFE8)
canvas, a white sheet of paper, and olive-green (107,127,94) details.

Outputs the full standard macOS iconset (10 PNGs, 16..512@2x) into
ulysses-native/icons/icon.iconset/.
"""

import os
from PIL import Image, ImageDraw

ROUNDED = "#F2EFE8"   # beige canvas
PAPER = "#FFFFFF"     # white sheet
OLIVE = (107, 127, 94)  # olive-green accents
OLIVE_SOFT = (107, 127, 94, 60)

BASE = 1024
CANVAS_MARGIN = 64          # margin from icon edge to rounded square
RADIUS = 180                # corner radius of the rounded square

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "icons", "icon.iconset")


def rounded_square(draw, x0, y0, x1, y1, radius, fill):
    draw.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=fill)


def draw_base(size):
    """1024x1024 master: beige rounded square + white paper + olive details."""
    img = Image.new("RGBA", (BASE, BASE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # --- beige rounded-square backdrop, nearly full-bleed (macOS style) ---
    m = CANVAS_MARGIN
    rounded_square(d, m, m, BASE - m, BASE - m, RADIUS, ROUNDED)

    # --- white paper sheet, slightly rotated feel via offset columns ---
    # paper occupies the center, portrait orientation
    px0, py0 = 300, 200
    px1, py1 = 724, 824
    rounded_square(d, px0, py0, px1, py1, 36, PAPER)
    # subtle paper edge shadow line
    d.rounded_rectangle([px0, py0, px1, py1], radius=36, outline=(0, 0, 0, 22), width=3)

    # --- olive details on the paper ---
    # header: olive title bar band across the top of the sheet
    d.rounded_rectangle([px0 + 44, py0 + 44, px1 - 44, py0 + 108], radius=18, fill=OLIVE)

    # text lines: restrained olive-tinted rules, rhythm of real prose
    line_x0 = px0 + 44
    line_x1 = px1 - 44
    ys = [348, 414, 480, 546, 612]
    widths = [1.0, 0.92, 1.0, 0.72, 0.85]
    for y, w in zip(ys, widths):
        x_end = line_x0 + int((line_x1 - line_x0) * w)
        d.rounded_rectangle([line_x0, y, x_end, y + 26], radius=13, fill=OLIVE_SOFT)

    # olive fountain-pen nib mark bottom-right of the sheet (writer's identity)
    d.ellipse([px1 - 132, py1 - 132, px1 - 60, py1 - 60], fill=OLIVE)
    d.ellipse([px1 - 114, py1 - 114, px1 - 78, py1 - 78], fill=PAPER)

    return img


def export_iconset(master):
    os.makedirs(OUT_DIR, exist_ok=True)
    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for name, s in sizes:
        master.resize((s, s), Image.LANCZOS).save(os.path.join(OUT_DIR, name))
        print(f"wrote {name} ({s}x{s})")


if __name__ == "__main__":
    master = draw_base(BASE)
    export_iconset(master)
    master.save(os.path.join(OUT_DIR, "..", "icon_1024_master.png"))
    print(f"iconset written to {os.path.abspath(OUT_DIR)}")
