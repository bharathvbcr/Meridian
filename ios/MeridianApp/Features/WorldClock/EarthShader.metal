//  EarthShader.metal
//  Meridian — iOS 27 / Swift 6
//
//  Day/night terminator shaders for the World Clock 2D map, ported from the Android
//  AGSL globe shader + `buildNightOverlay` rasteriser in DayNightMap.kt / GlobeView.kt.
//
//  Two SwiftUI `.colorEffect` entry points live here. Both follow the required
//  stitchable color-filter signature:
//
//      [[ stitchable ]] half4 name(float2 position, half4 color, args...)
//
//  where `position` is in user-space (point) coordinates and `color` is the
//  pre-multiplied source pixel. Because a `.colorEffect` shader only sees the pixel
//  it is shading (not the whole image), the caller fills the view with a base layer
//  (the day surface for `terminatorOverlay`, or transparent for the standalone
//  `nightTerminator`) and these shaders shade the day/night gradient per pixel.
//
//  Equirectangular projection (matches DayNightMap.project / WorldAtlas):
//      u = (lng + 180) / 360,  v = (90 - lat) / 180
//  so for a fragment at (px, py) over a viewport of `size`:
//      lng = px / size.x * 360 - 180
//      lat = 90 - py / size.y * 180

#include <metal_stdlib>
using namespace metal;

// cos(solar zenith) at (lat, lng) given the subsolar point (subLat, subLng).
// > 0 day, = 0 on the terminator, < 0 night. Mirrors SolarMath.cosSolarZenith.
static inline float cosZenith(float lat, float lng, float subLat, float subLng) {
    const float DEG = 3.14159265358979323846f / 180.0f;
    return sin(lat * DEG) * sin(subLat * DEG)
         + cos(lat * DEG) * cos(subLat * DEG) * cos((lng - subLng) * DEG);
}

// MARK: - 2D night overlay (Android buildNightOverlay parity)
//
// Produces the night/twilight tint exactly as Android's GRID_COLS×GRID_ROWS mask did:
//   night = clamp(-cosZ / 0.20, 0, 1)            // 0 at the day/night line .. 1 deep night
//   alpha = night * 0.82                         // capped deep-night opacity
//   rgb   = deep-night tint (#0B1020)
// Daylight pixels (cosZ >= 0) are fully transparent so the day surface shows through.
//
// Designed to be applied over a TRANSPARENT base (a clear Rectangle of the map size):
// `color` is ignored; we emit the night tint pre-multiplied by its own alpha.
//
// Uniforms:
//   size       viewport size in points (width, height)
//   subsolar   subsolar point (latitude, longitude) in degrees
//   nightTint  deep-night RGB (e.g. #0B1020), alpha ignored
//   maxAlpha   peak overlay opacity (Android uses 0.82 for textured, scaled by the
//              caller for the vector style which dims it to ~0.7 of that)
[[ stitchable ]]
half4 nightTerminator(float2 position,
                      half4 color,
                      float2 size,
                      float2 subsolar,
                      half4 nightTint,
                      float maxAlpha) {
    float lng = position.x / max(size.x, 1.0f) * 360.0f - 180.0f;
    float lat = 90.0f - position.y / max(size.y, 1.0f) * 180.0f;

    float cz = cosZenith(lat, lng, subsolar.x, subsolar.y);
    if (cz >= 0.0f) {
        return half4(0.0h, 0.0h, 0.0h, 0.0h); // daylight: fully transparent
    }
    float night = clamp(-cz / 0.20f, 0.0f, 1.0f);
    float alpha = clamp(night * maxAlpha, 0.0f, 1.0f);
    // Pre-multiplied output (SwiftUI colorEffect works in pre-multiplied space).
    return half4(half3(nightTint.rgb) * half(alpha), half(alpha));
}

// MARK: - Textured / two-tone day-night shading (Android EARTH_AGSL parity)
//
// Shades a base layer (the day surface — a photographic map or a flat day color the
// caller already drew into `color`) across the terminator, matching the globe shader:
//   dayF   = clamp((cz + 0.20) / 0.20, 0, 1)     // full day at the line, night by cz=-0.20
//   bright = 0.30 + 0.70 * dayF                  // 0.30 night floor keeps the dark side legible
//   nm     = (1 - dayF) * 0.6                     // blend toward the deep-night tint
//   col    = surf * bright * (1 - nm) + night * nm
// Applied as a colorEffect over the opaque day map, so `color` IS the surface RGB.
//
// Uniforms:
//   size       viewport size in points
//   subsolar   subsolar point (latitude, longitude) in degrees
//   nightTint  deep-night RGB tint
[[ stitchable ]]
half4 terminatorShade(float2 position,
                      half4 color,
                      float2 size,
                      float2 subsolar,
                      half4 nightTint) {
    float lng = position.x / max(size.x, 1.0f) * 360.0f - 180.0f;
    float lat = 90.0f - position.y / max(size.y, 1.0f) * 180.0f;

    float cz = cosZenith(lat, lng, subsolar.x, subsolar.y);
    float dayF = clamp((cz + 0.20f) / 0.20f, 0.0f, 1.0f);
    float bright = 0.30f + 0.70f * dayF;
    float nm = (1.0f - dayF) * 0.6f;

    // color is pre-multiplied; for an opaque map alpha == 1 so rgb is the surface.
    half3 surf = color.rgb;
    half3 col = surf * half(bright) * half(1.0f - nm) + half3(nightTint.rgb) * half(nm);
    return half4(col, color.a);
}
