"""
Render Meridian 512x512 Play Store icon with 4x supersampling for smooth edges.
Renders at 2048x2048 then downscales to 512x512 with LANCZOS.
"""

import math
import os
from PIL import Image, ImageDraw

RENDER_SIZE = 2048   # 4x supersample
OUTPUT_SIZE = 512
OUTPUT = "C:/Users/bhara/Downloads/Code/DevTIme/store_assets/ic_launcher_512.png"
SCALE = RENDER_SIZE / 108.0   # viewport 108 → render size

def lerp_color(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))

def gradient_color(t):
    if t < 0.55:
        return lerp_color((0x0E, 0x4A, 0x72), (0x0A, 0x35, 0x53), t / 0.55)
    else:
        return lerp_color((0x0A, 0x35, 0x53), (0x06, 0x28, 0x3D), (t - 0.55) / 0.45)

# ── 1. Background gradient ────────────────────────────────────────────────────
img = Image.new("RGBA", (RENDER_SIZE, RENDER_SIZE), (0, 0, 0, 255))
pixels = img.load()

for y in range(RENDER_SIZE):
    for x in range(RENDER_SIZE):
        t = (x / (RENDER_SIZE - 1) + y / (RENDER_SIZE - 1)) / 2
        r, g, b = gradient_color(t)
        pixels[x, y] = (r, g, b, 255)

# ── 2. Globe wireframe ────────────────────────────────────────────────────────
draw = ImageDraw.Draw(img)

def s(v):
    return v * SCALE

cx, cy, r = s(54), s(54), s(27)

WHITE = (255, 255, 255, 255)
GOLD  = (0xFF, 0xC8, 0x57, 255)

sw_main  = max(2, round(3.6 * SCALE))
sw_inner = max(2, round(3.2 * SCALE))

# Globe rim
draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=WHITE, width=sw_main)

# Equator
draw.line([(s(27), s(54)), (s(81), s(54))], fill=WHITE, width=sw_main)

# Prime meridian
draw.line([(s(54), s(27)), (s(54), s(81))], fill=WHITE, width=sw_main)

# Curved longitude: rx=11, ry=27
rx_lon, ry_lon = s(11), s(27)
draw.ellipse([cx - rx_lon, cy - ry_lon, cx + rx_lon, cy + ry_lon],
             outline=WHITE, width=sw_inner)

# Curved latitude: rx=27, ry=11
rx_lat, ry_lat = s(27), s(11)
draw.ellipse([cx - rx_lat, cy - ry_lat, cx + rx_lat, cy + ry_lat],
             outline=WHITE, width=sw_inner)

# ── 3. Solar-noon dot ─────────────────────────────────────────────────────────
# path "M54,22 a5,5 0 1,1 0,10 ..." → circle at (54, 27) r=5 in viewport
dot_cx, dot_cy, dot_r = s(54), s(27), s(5)
draw.ellipse([dot_cx - dot_r, dot_cy - dot_r,
              dot_cx + dot_r, dot_cy + dot_r],
             fill=GOLD, outline=GOLD)

# ── 4. Downsample to 512x512 (LANCZOS = best quality) ────────────────────────
img = img.resize((OUTPUT_SIZE, OUTPUT_SIZE), Image.LANCZOS)

# ── 5. Save ───────────────────────────────────────────────────────────────────
os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
img.save(OUTPUT, "PNG")
print(f"Saved {os.path.getsize(OUTPUT):,} bytes -> {OUTPUT}")
