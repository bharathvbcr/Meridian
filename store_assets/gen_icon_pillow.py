"""
Render Meridian 512x512 Play Store icon using Pillow ImageDraw.

The design matches ic_launcher_background.xml + ic_launcher_foreground.xml:
  - Background: deep blue diagonal gradient (#0E4A72 → #0A3553 → #06283D)
  - Globe wireframe: rim circle, equator line, prime meridian line,
    curved longitude ellipse, curved latitude ellipse (all white strokes)
  - Solar-noon marker: gold dot at top of prime meridian
"""

import math
from PIL import Image, ImageDraw

SIZE = 512
OUTPUT = "C:/Users/bhara/Downloads/Code/DevTIme/store_assets/ic_launcher_512.png"

# ── 1. Background gradient ────────────────────────────────────────────────────
# Diagonal linear gradient from top-left (#0E4A72) to bottom-right (#06283D)
# via midpoint at 55% (#0A3553).

def lerp_color(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))

def gradient_color(t):
    """t in [0,1] along the diagonal"""
    if t < 0.55:
        return lerp_color((0x0E, 0x4A, 0x72), (0x0A, 0x35, 0x53), t / 0.55)
    else:
        return lerp_color((0x0A, 0x35, 0x53), (0x06, 0x28, 0x3D), (t - 0.55) / 0.45)

img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
pixels = img.load()
diag = math.sqrt(2)  # normalise diagonal length to 1

for y in range(SIZE):
    for x in range(SIZE):
        t = (x / (SIZE - 1) + y / (SIZE - 1)) / 2  # 0 at TL, 1 at BR
        r, g, b = gradient_color(t)
        pixels[x, y] = (r, g, b, 255)

# ── 2. Draw globe wireframe ───────────────────────────────────────────────────
# The Android vector viewport is 108x108.  We scale to 512x512.
# Scale factor
S = SIZE / 108.0

def s(v):
    """Scale a viewport coordinate to pixel space."""
    return v * S

draw = ImageDraw.Draw(img)

# Viewport centre = (54, 54), globe radius = 27
cx, cy, r = 54 * S, 54 * S, 27 * S

WHITE = (255, 255, 255, 255)
GOLD  = (0xFF, 0xC8, 0x57, 255)

stroke_main = max(1, int(3.6 * S))
stroke_inner = max(1, int(3.2 * S))

# --- Globe rim (circle) ---
box = [cx - r, cy - r, cx + r, cy + r]
draw.ellipse(box, outline=WHITE, width=stroke_main)

# --- Equator (horizontal line) ---
draw.line([(s(27), s(54)), (s(81), s(54))], fill=WHITE, width=stroke_main)

# --- Prime meridian (vertical line) ---
draw.line([(s(54), s(27)), (s(54), s(81))], fill=WHITE, width=stroke_main)

# --- Curved longitude: ellipse with rx=11, ry=27 centred at (54,54) ---
# a11,27 in viewport coords
rx_lon = 11 * S
ry_lon = 27 * S
lon_box = [cx - rx_lon, cy - ry_lon, cx + rx_lon, cy + ry_lon]
draw.ellipse(lon_box, outline=WHITE, width=stroke_inner)

# --- Curved latitude: ellipse with rx=27, ry=11 centred at (54,54) ---
rx_lat = 27 * S
ry_lat = 11 * S
lat_box = [cx - rx_lat, cy - ry_lat, cx + rx_lat, cy + ry_lat]
draw.ellipse(lat_box, outline=WHITE, width=stroke_inner)

# ── 3. Solar-noon marker (gold dot) ──────────────────────────────────────────
# Android path: M54,22 a5,5 0 1,1 0,10 a5,5 0 1,1 0,-10 Z
# This is a circle of radius 5 centred at (54, 27) in viewport.
dot_cx = s(54)
dot_cy = s(27)  # top of prime meridian (54, 27+5=32 path start, centre at 54,27)
dot_r  = s(5)
gold_box = [dot_cx - dot_r, dot_cy - dot_r, dot_cx + dot_r, dot_cy + dot_r]
draw.ellipse(gold_box, fill=GOLD, outline=GOLD)

# ── 4. Anti-alias by 2x downsample ───────────────────────────────────────────
# Pillow doesn't do real anti-aliasing on draw ops, so we rendered at 2x
# above... actually we rendered at 512 directly.  Apply a mild smooth pass.
from PIL import ImageFilter
img = img.filter(ImageFilter.SMOOTH)

# ── 5. Save ───────────────────────────────────────────────────────────────────
import os
os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
img.save(OUTPUT, "PNG")
import os
print(f"Saved {os.path.getsize(OUTPUT):,} bytes -> {OUTPUT}")
