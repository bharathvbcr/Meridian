"""
Generate a 1024×500 feature graphic for the Meridian Android Play Store listing.

Usage:
    python store_assets/gen_feature_graphic.py
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# devcouncil: allow-unwired — one-shot store asset CLI (also declared in pyproject scripts)

HERE = Path(__file__).resolve().parent
OUTPUT_PATH = HERE / "feature_graphic.png"
W, H = 1024, 500

# Color palette
TOP_LEFT = (14, 74, 114)  # #0E4A72
BOTTOM_RIGHT = (6, 40, 61)  # #06283D
WHITE = (255, 255, 255)
GOLD = (255, 200, 87)  # #FFC857
TAGLINE_CLR = (176, 196, 222)  # #B0C4DE
CAPTION_CLR = (123, 175, 212)  # #7BAFD4
WIRE_ALPHA = 200


def _font_candidates(bold: bool) -> list[Path]:
    if bold:
        names = [
            Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf"),
            Path("/Library/Fonts/Arial Bold.ttf"),
            Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"),
            Path(r"C:\Windows\Fonts\arialbd.ttf"),
        ]
    else:
        names = [
            Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
            Path("/Library/Fonts/Arial.ttf"),
            Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
            Path(r"C:\Windows\Fonts\arial.ttf"),
        ]
    return names


def load_font(size: int, *, bold: bool = False) -> ImageFont.ImageFont:
    for path in _font_candidates(bold):
        if path.is_file():
            try:
                return ImageFont.truetype(str(path), size)
            except OSError:
                continue
    return ImageFont.load_default()


def wire_color(alpha: int = WIRE_ALPHA) -> tuple[int, int, int, int]:
    return (255, 255, 255, alpha)


def main() -> int:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    pixels = img.load()

    for y in range(H):
        for x in range(W):
            t = (x / (W - 1) + y / (H - 1)) / 2.0
            r = int(TOP_LEFT[0] + (BOTTOM_RIGHT[0] - TOP_LEFT[0]) * t)
            g = int(TOP_LEFT[1] + (BOTTOM_RIGHT[1] - TOP_LEFT[1]) * t)
            b = int(TOP_LEFT[2] + (BOTTOM_RIGHT[2] - TOP_LEFT[2]) * t)
            pixels[x, y] = (r, g, b, 255)

    globe_cx, globe_cy, globe_r = 300, 250, 180
    globe_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(globe_layer)

    bb = [globe_cx - globe_r, globe_cy - globe_r, globe_cx + globe_r, globe_cy + globe_r]
    gd.ellipse(bb, outline=wire_color(), width=3)
    gd.line(
        [(globe_cx - globe_r, globe_cy), (globe_cx + globe_r, globe_cy)],
        fill=wire_color(),
        width=2,
    )
    gd.line(
        [(globe_cx, globe_cy - globe_r), (globe_cx, globe_cy + globe_r)],
        fill=wire_color(),
        width=2,
    )

    rx_wide, ry_wide = 180, 55
    gd.ellipse(
        [globe_cx - rx_wide, globe_cy - ry_wide, globe_cx + rx_wide, globe_cy + ry_wide],
        outline=wire_color(180),
        width=2,
    )
    rx_tall, ry_tall = 55, 180
    gd.ellipse(
        [globe_cx - rx_tall, globe_cy - ry_tall, globe_cx + rx_tall, globe_cy + ry_tall],
        outline=wire_color(180),
        width=2,
    )
    rx2, ry2 = 180, 100
    gd.ellipse(
        [globe_cx - rx2, globe_cy - ry2, globe_cx + rx2, globe_cy + ry2],
        outline=wire_color(110),
        width=1,
    )

    gold_x, gold_y, gold_dot_r = globe_cx, globe_cy - globe_r, 7
    gd.ellipse(
        [
            gold_x - gold_dot_r,
            gold_y - gold_dot_r,
            gold_x + gold_dot_r,
            gold_y + gold_dot_r,
        ],
        fill=(*GOLD, 255),
        outline=(*GOLD, 255),
    )
    gd.ellipse(
        [
            gold_x - gold_dot_r - 4,
            gold_y - gold_dot_r - 4,
            gold_x + gold_dot_r + 4,
            gold_y + gold_dot_r + 4,
        ],
        outline=(*GOLD, 90),
        width=2,
    )
    img = Image.alpha_composite(img, globe_layer)

    dot_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dot_layer)
    star_positions = [
        (130, 160, 2, 70),
        (210, 95, 3, 65),
        (390, 105, 2, 75),
        (450, 200, 2, 60),
        (410, 360, 3, 70),
        (200, 390, 2, 65),
        (110, 310, 2, 55),
        (160, 220, 2, 60),
    ]
    for sx, sy, sr, sa in star_positions:
        dd.ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=(255, 255, 255, sa))
    img = Image.alpha_composite(img, dot_layer)

    text_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    td = ImageDraw.Draw(text_layer)
    font_title = load_font(72, bold=True)
    font_tagline = load_font(28)
    font_caption = load_font(18)

    text_x, title_y = 580, 170
    td.text((text_x, title_y), "MERIDIAN", font=font_title, fill=(*WHITE, 255))
    title_bbox = td.textbbox((text_x, title_y), "MERIDIAN", font=font_title)
    rule_y = title_bbox[3] + 14
    td.line([(text_x, rule_y), (text_x + 280, rule_y)], fill=(255, 255, 255, 102), width=1)
    td.text(
        (text_x, rule_y + 18),
        "Every timezone. One glance.",
        font=font_tagline,
        fill=(*TAGLINE_CLR, 255),
    )
    img = Image.alpha_composite(img, text_layer)

    caption_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(caption_layer)
    cd.text(
        (40, 460),
        "World Clocks · Globe · AI Planner",
        font=font_caption,
        fill=(*CAPTION_CLR, 200),
    )
    img = Image.alpha_composite(img, caption_layer)

    final = img.convert("RGB")
    final.save(OUTPUT_PATH, "PNG")
    size_kb = os.path.getsize(OUTPUT_PATH) / 1024
    print(f"Saved: {OUTPUT_PATH}")
    print(f"Dimensions: {final.size[0]}x{final.size[1]} px")
    print(f"File size: {size_kb:.1f} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
