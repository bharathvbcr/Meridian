"""
Generates a 1024×500 feature graphic for the Meridian Android app.
"""

from PIL import Image, ImageDraw, ImageFont
import math
import os

OUTPUT_PATH = r"C:\Users\bhara\Downloads\Code\DevTIme\store_assets\feature_graphic.png"
W, H = 1024, 500

# ── Color palette ──────────────────────────────────────────────────────────────
TOP_LEFT    = (14,  74, 114)   # #0E4A72
MID         = (10,  53,  83)   # #0A3553
BOTTOM_RIGHT= ( 6,  40,  61)   # #06283D
WHITE       = (255, 255, 255)
GOLD        = (255, 200,  87)  # #FFC857
TAGLINE_CLR = (176, 196, 222)  # #B0C4DE  light steel blue
CAPTION_CLR = (123, 175, 212)  # #7BAFD4

# ── Font paths ─────────────────────────────────────────────────────────────────
FONT_BOLD   = r"C:\Windows\Fonts\arialbd.ttf"
FONT_REGULAR= r"C:\Windows\Fonts\arial.ttf"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Background: diagonal gradient
# ─────────────────────────────────────────────────────────────────────────────
img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
pixels = img.load()

for y in range(H):
    for x in range(W):
        # t = 0 at top-left, t = 1 at bottom-right (diagonal blend)
        t = (x / (W - 1) + y / (H - 1)) / 2.0
        r = int(TOP_LEFT[0] + (BOTTOM_RIGHT[0] - TOP_LEFT[0]) * t)
        g = int(TOP_LEFT[1] + (BOTTOM_RIGHT[1] - TOP_LEFT[1]) * t)
        b = int(TOP_LEFT[2] + (BOTTOM_RIGHT[2] - TOP_LEFT[2]) * t)
        pixels[x, y] = (r, g, b, 255)

# ─────────────────────────────────────────────────────────────────────────────
# 2. Globe wireframe — drawn on a separate RGBA layer and composited
# ─────────────────────────────────────────────────────────────────────────────
GLOBE_CX, GLOBE_CY, GLOBE_R = 300, 250, 180
WIRE_ALPHA = 200  # semi-transparent white

globe_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(globe_layer)

def wire_color(alpha=WIRE_ALPHA):
    return (255, 255, 255, alpha)

# Outer circle
bb = [GLOBE_CX - GLOBE_R, GLOBE_CY - GLOBE_R,
      GLOBE_CX + GLOBE_R, GLOBE_CY + GLOBE_R]
gd.ellipse(bb, outline=wire_color(), width=3)

# Equator — horizontal line clipped to circle diameter
gd.line([(GLOBE_CX - GLOBE_R, GLOBE_CY), (GLOBE_CX + GLOBE_R, GLOBE_CY)],
        fill=wire_color(), width=2)

# Prime meridian — vertical line clipped to circle diameter
gd.line([(GLOBE_CX, GLOBE_CY - GLOBE_R), (GLOBE_CX, GLOBE_CY + GLOBE_R)],
        fill=wire_color(), width=2)

# Wide latitude ellipse  (rx=180, ry=55)
RX_WIDE, RY_WIDE = 180, 55
bb_wide = [GLOBE_CX - RX_WIDE, GLOBE_CY - RY_WIDE,
           GLOBE_CX + RX_WIDE, GLOBE_CY + RY_WIDE]
gd.ellipse(bb_wide, outline=wire_color(180), width=2)

# Tall longitude ellipse  (rx=55, ry=180)
RX_TALL, RY_TALL = 55, 180
bb_tall = [GLOBE_CX - RX_TALL, GLOBE_CY - RY_TALL,
           GLOBE_CX + RX_TALL, GLOBE_CY + RY_TALL]
gd.ellipse(bb_tall, outline=wire_color(180), width=2)

# Second wide ellipse offset slightly for extra depth
RX2, RY2 = 180, 100
bb2 = [GLOBE_CX - RX2, GLOBE_CY - RY2,
       GLOBE_CX + RX2, GLOBE_CY + RY2]
gd.ellipse(bb2, outline=wire_color(110), width=1)

# Gold dot at top of prime meridian
GOLD_X, GOLD_Y, GOLD_DOT_R = GLOBE_CX, GLOBE_CY - GLOBE_R, 7
gd.ellipse([GOLD_X - GOLD_DOT_R, GOLD_Y - GOLD_DOT_R,
            GOLD_X + GOLD_DOT_R, GOLD_Y + GOLD_DOT_R],
           fill=(*GOLD, 255), outline=(*GOLD, 255))

# Subtle glow ring around gold dot
gd.ellipse([GOLD_X - GOLD_DOT_R - 4, GOLD_Y - GOLD_DOT_R - 4,
            GOLD_X + GOLD_DOT_R + 4, GOLD_Y + GOLD_DOT_R + 4],
           outline=(*GOLD, 90), width=2)

img = Image.alpha_composite(img, globe_layer)

# ─────────────────────────────────────────────────────────────────────────────
# 3. Decorative star/city dots scattered around the globe
# ─────────────────────────────────────────────────────────────────────────────
dot_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
dd = ImageDraw.Draw(dot_layer)

star_positions = [
    (130, 160, 2, 70),
    (210,  95, 3, 65),
    (390, 105, 2, 75),
    (450, 200, 2, 60),
    (410, 360, 3, 70),
    (200, 390, 2, 65),
    (110, 310, 2, 55),
    (160, 220, 2, 60),
]
for (sx, sy, sr, sa) in star_positions:
    dd.ellipse([sx - sr, sy - sr, sx + sr, sy + sr],
               fill=(255, 255, 255, sa))

img = Image.alpha_composite(img, dot_layer)

# ─────────────────────────────────────────────────────────────────────────────
# 4. Text — right side
# ─────────────────────────────────────────────────────────────────────────────
text_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
td = ImageDraw.Draw(text_layer)

try:
    font_title   = ImageFont.truetype(FONT_BOLD,    72)
    font_tagline = ImageFont.truetype(FONT_REGULAR, 28)
    font_caption = ImageFont.truetype(FONT_REGULAR, 18)
except OSError:
    font_title   = ImageFont.load_default()
    font_tagline = ImageFont.load_default()
    font_caption = ImageFont.load_default()

TEXT_X = 580
TITLE_Y = 170

# App name
td.text((TEXT_X, TITLE_Y), "MERIDIAN",
        font=font_title, fill=(*WHITE, 255))

# Measure title height to position rule and tagline
title_bbox = td.textbbox((TEXT_X, TITLE_Y), "MERIDIAN", font=font_title)
title_bottom = title_bbox[3]

# Thin horizontal rule  (40% white)
RULE_Y = title_bottom + 14
td.line([(TEXT_X, RULE_Y), (TEXT_X + 280, RULE_Y)],
        fill=(255, 255, 255, 102), width=1)

# Tagline
TAGLINE_Y = RULE_Y + 18
td.text((TEXT_X, TAGLINE_Y), "Every timezone. One glance.",
        font=font_tagline, fill=(*TAGLINE_CLR, 255))

img = Image.alpha_composite(img, text_layer)

# ─────────────────────────────────────────────────────────────────────────────
# 5. Bottom caption
# ─────────────────────────────────────────────────────────────────────────────
caption_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
cd = ImageDraw.Draw(caption_layer)
cd.text((40, 460), "World Clocks · Globe · AI Planner",
        font=font_caption, fill=(*CAPTION_CLR, 200))

img = Image.alpha_composite(img, caption_layer)

# ─────────────────────────────────────────────────────────────────────────────
# 6. Save as RGB PNG
# ─────────────────────────────────────────────────────────────────────────────
final = img.convert("RGB")
final.save(OUTPUT_PATH, "PNG")

size_kb = os.path.getsize(OUTPUT_PATH) / 1024
print(f"Saved: {OUTPUT_PATH}")
print(f"Dimensions: {final.size[0]}x{final.size[1]} px")
print(f"File size: {size_kb:.1f} KB")
