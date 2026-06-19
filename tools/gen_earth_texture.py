"""
Generate a realistic equirectangular Earth texture from the silhouette land mask.

The app shipped a flat black continent silhouette (500x250). Both the 2D day/night
map and the 3D globe tinted that single shape with one flat color, so the map looked
like "just pixels". This script keeps the silhouette's accurate coastlines but paints
a believable Earth on top: depth-shaded oceans, latitude-driven land biomes
(tropical green -> desert tan -> boreal -> polar ice) and fractal terrain variation.

Output: app/src/main/res/drawable/world_map.png (RGB, opaque), high resolution.
"""
import os
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt, gaussian_filter

HERE = os.path.dirname(os.path.abspath(__file__))
DRAWABLE = os.path.join(HERE, "..", "app", "src", "main", "res", "drawable")
SRC = os.path.join(HERE, "world_silhouette.png")  # original land mask (kept out of the APK)
OUT = os.path.join(DRAWABLE, "world_map.png")     # realistic texture both views render

W, H = 2048, 1024  # target resolution

rng = np.random.default_rng(42)  # deterministic so rebuilds are stable


def fractal_noise(w, h, octaves=6, persistence=0.55):
    """Sum of upsampled random layers -> smooth value noise in [0,1]."""
    total = np.zeros((h, w), dtype=np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        scale = 2 ** (o + 1)
        lh, lw = max(2, h // (2 ** (octaves - o)) ), max(2, w // (2 ** (octaves - o)))
        layer = rng.random((lh, lw)).astype(np.float32)
        layer = np.asarray(Image.fromarray((layer * 255).astype(np.uint8))
                           .resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0
        total += layer * amp
        norm += amp
        amp *= persistence
    total /= norm
    return (total - total.min()) / (total.max() - total.min() + 1e-6)


def lerp(a, b, t):
    t = t[..., None]
    return a * (1 - t) + b * t


def main():
    mask_img = Image.open(SRC).convert("RGBA").resize((W, H), Image.LANCZOS)
    alpha = np.asarray(mask_img)[..., 3].astype(np.float32) / 255.0
    land = alpha > 0.5  # accurate continent shapes from the original silhouette

    # Per-pixel latitude (degrees), +90 top .. -90 bottom.
    lat = np.linspace(90, -90, H)[:, None].repeat(W, axis=1).astype(np.float32)
    abslat = np.abs(lat)

    # --- Oceans: depth shading via distance from the nearest coast ---
    # Tight continental shelf (narrow teal rim), quickly falling to deep navy so open
    # ocean doesn't read as one flat glow. eased^0.6 keeps the rim crisp near coasts.
    ocean_dist = distance_transform_edt(~land).astype(np.float32)
    depth = np.clip(ocean_dist / 42.0, 0, 1) ** 0.6  # 0 coast .. 1 open ocean
    shallow = np.array([48, 132, 156], np.float32)   # teal shelf water
    deep = np.array([6, 28, 72], np.float32)         # deep navy
    ocean = lerp(shallow, deep, depth)
    # Warmer, lighter tropical seas; cooler/darker toward the poles.
    tropic = np.clip(1.0 - abslat / 45.0, 0, 1)      # 1 at equator .. 0 by 45 deg
    ocean = lerp(ocean, ocean * np.array([1.05, 1.10, 1.12], np.float32), tropic * 0.35)
    ocean *= (1.0 - 0.22 * (abslat / 90.0))[..., None]

    # --- Land biomes by latitude, blended with noise ---
    n_big = fractal_noise(W, H, octaves=5)            # biome blotches
    n_fine = fractal_noise(W, H, octaves=7)           # terrain texture

    tropical = np.array([38, 110, 42], np.float32)
    savanna = np.array([120, 140, 58], np.float32)
    desert = np.array([196, 170, 110], np.float32)
    temperate = np.array([56, 104, 50], np.float32)
    boreal = np.array([74, 96, 64], np.float32)
    tundra = np.array([140, 138, 120], np.float32)
    snow = np.array([238, 240, 245], np.float32)

    # Smooth biome gradient as a continuous function of latitude. Control points
    # (deg -> color) are interpolated, so there are no hard horizontal seams.
    stops = [0, 14, 24, 38, 52, 64, 74, 90]
    cols = [tropical, savanna, temperate, temperate, boreal, tundra, snow, snow]
    cols = np.array(cols, np.float32)

    # Perturb the latitude used for biome lookup with noise so band edges meander
    # across continents instead of cutting straight lines. Larger blotch noise also
    # pushes some subtropical zones toward desert.
    jitter = (n_big - 0.5) * 22.0 + (n_fine - 0.5) * 8.0  # +/- ~15 deg of wander
    biome_lat = np.clip(abslat + jitter, 0, 90)
    base = np.empty((H, W, 3), np.float32)
    for c in range(3):
        base[..., c] = np.interp(biome_lat, stops, cols[:, c])

    # Deserts: dry blotches concentrated in the subtropics (~15-33 deg).
    sub_weight = np.clip(1.0 - np.abs(abslat - 24) / 12.0, 0, 1)
    desert_amt = np.clip((n_big - 0.50) / 0.22, 0, 1) * sub_weight
    base = lerp(base, desert, desert_amt)

    # Antarctica / Greenland read as ice regardless of the gradient above.
    base[(lat < -60) & land] = snow
    # Greenland & high Arctic land ice (kicks in a touch lower so Greenland reads icy).
    base[(lat > 62) & land] = lerp(tundra, snow, np.clip((lat - 62) / 12.0, 0, 1))[(lat > 62) & land]

    # Richer land contrast: push colors away from their mid-gray a little.
    gray = base.mean(axis=2, keepdims=True)
    base = np.clip(gray + (base - gray) * 1.18, 0, 255)

    # Terrain variation + faint coastal lightening on land.
    land_dist = distance_transform_edt(land).astype(np.float32)
    coastal = np.clip(1.0 - land_dist / 30.0, 0, 1)  # bright near shore
    shade = 0.80 + 0.34 * n_fine                      # +/- terrain brightness
    base *= shade[..., None]
    base = lerp(base, base * 1.12 + 18, coastal * 0.30)

    # Compose land over ocean using the (soft) coastline alpha for clean edges.
    soft = gaussian_filter(alpha, sigma=0.6)[..., None]
    rgb = base * soft + ocean * (1 - soft)

    # Gentle global polish.
    rgb = np.clip(rgb, 0, 255)
    out = np.dstack([rgb.astype(np.uint8), np.full((H, W), 255, np.uint8)])
    Image.fromarray(out, "RGBA").save(OUT)
    print(f"wrote {OUT} ({W}x{H})")


if __name__ == "__main__":
    main()
