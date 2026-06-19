"""
Convert Meridian Android Vector Drawables to a 512x512 Play Store icon PNG.

Strategy:
  1. Build an SVG that composites the background (gradient) and foreground (globe paths).
  2. Render with cairosvg at 512x512.
  3. Fallback: upscale xxxhdpi webp with Pillow if cairosvg fails.
"""

import sys
import os

OUTPUT = os.path.join(os.path.dirname(__file__), "ic_launcher_512.png")
SIZE = 512

# ── SVG source ────────────────────────────────────────────────────────────────
# The Android Vector viewport is 108x108.
# Background: linear gradient from #0E4A72 (TL) → #0A3553 (55%) → #06283D (BR)
# Foreground paths (white strokes) + solar-noon dot (#FFC857).
# We composite them as a single SVG (background rect + foreground paths).
# The adaptive icon safe zone is a circle of radius 33 centred at (54,54);
# for the Play Store icon we render the full 108x108 square (background fills it).

SVG = """\
<?xml version="1.0" encoding="utf-8"?>
<svg xmlns="http://www.w3.org/2000/svg"
     xmlns:xlink="http://www.w3.org/1999/xlink"
     viewBox="0 0 108 108"
     width="512" height="512">
  <defs>
    <!-- Background diagonal gradient (ocean → space) -->
    <linearGradient id="bg" x1="0" y1="0" x2="108" y2="108"
                    gradientUnits="userSpaceOnUse">
      <stop offset="0%"   stop-color="#0E4A72"/>
      <stop offset="55%"  stop-color="#0A3553"/>
      <stop offset="100%" stop-color="#06283D"/>
    </linearGradient>
  </defs>

  <!-- Background -->
  <rect x="0" y="0" width="108" height="108" fill="url(#bg)"/>

  <!-- Globe rim (circle) -->
  <path d="M54,27 a27,27 0 1,1 0,54 a27,27 0 1,1 0,-54 Z"
        fill="none" stroke="#FFFFFF" stroke-width="3.6"
        stroke-linecap="round"/>

  <!-- Equator -->
  <path d="M27,54 L81,54"
        fill="none" stroke="#FFFFFF" stroke-width="3.6"
        stroke-linecap="round"/>

  <!-- Prime meridian -->
  <path d="M54,27 L54,81"
        fill="none" stroke="#FFFFFF" stroke-width="3.6"
        stroke-linecap="round"/>

  <!-- Curved meridian (longitude) -->
  <path d="M54,27 a11,27 0 1,0 0,54 a11,27 0 1,0 0,-54"
        fill="none" stroke="#FFFFFF" stroke-width="3.2"/>

  <!-- Curved latitude -->
  <path d="M27,54 a27,11 0 1,0 54,0 a27,11 0 1,0 -54,0"
        fill="none" stroke="#FFFFFF" stroke-width="3.2"/>

  <!-- Solar-noon marker (gold dot at top of prime meridian) -->
  <path d="M54,22 a5,5 0 1,1 0,10 a5,5 0 1,1 0,-10 Z"
        fill="#FFC857"/>
</svg>
"""

def try_cairosvg():
    try:
        import cairosvg
        png_bytes = cairosvg.svg2png(bytestring=SVG.encode("utf-8"),
                                     output_width=SIZE, output_height=SIZE)
        with open(OUTPUT, "wb") as f:
            f.write(png_bytes)
        print(f"[cairosvg] Saved {len(png_bytes):,} bytes -> {OUTPUT}")
        return True
    except Exception as e:
        print(f"[cairosvg] Failed: {e}", file=sys.stderr)
        return False


def try_pillow_upscale():
    """Fallback: upscale the xxxhdpi webp launcher icon."""
    from PIL import Image

    project = os.path.dirname(os.path.dirname(__file__))
    webp = os.path.join(project, "app", "src", "main", "res",
                        "mipmap-xxxhdpi", "ic_launcher.webp")
    if not os.path.exists(webp):
        print(f"[pillow] Source not found: {webp}", file=sys.stderr)
        return False

    img = Image.open(webp).convert("RGBA")
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.save(OUTPUT, "PNG")
    print(f"[pillow-upscale] Saved {os.path.getsize(OUTPUT):,} bytes -> {OUTPUT}")
    return True


if __name__ == "__main__":
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    if not try_cairosvg():
        if not try_pillow_upscale():
            print("ERROR: all methods failed", file=sys.stderr)
            sys.exit(1)
    print("Done.")
