package com.example.feature.worldclock

import android.graphics.BitmapShader
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.os.Build
import androidx.annotation.RequiresApi
import android.graphics.BitmapFactory
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.example.core.data.MapStyle
import com.example.core.data.SavedZone
import com.example.core.time.SolarMath
import com.example.core.time.ZoneCoordinates
import java.time.Instant
import kotlin.math.PI
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

private const val DEG = PI / 180.0
// Sampling resolution for the Canvas fallback (pre-API 33 only; API 33+ uses the GPU shader).
// Each grid step is an individual drawRect re-issued on every spin frame, so this is kept modest
// to keep the fallback responsive on the older, slower devices that actually use it.
private const val GRID = 96
// Coarser grid for the Performance style: the flat two-tone sphere has no fine texture detail to
// resolve, so half the resolution looks identical while issuing a quarter of the drawRect calls.
private const val GRID_PERF = 48

/**
 * AGSL shader for the textured globe (API 33+). Runs once per pixel on the GPU: it inverts the
 * orthographic projection to a lat/lng, samples the realistic Earth texture, shades it smoothly
 * across the day/night terminator, adds limb darkening for depth, a soft atmospheric halo, a rim
 * highlight, and a subtle warm city-lights glow on the dark-side land.
 */
@Suppress("ktlint:standard:max-line-length")
private const val EARTH_AGSL = """
uniform float2 uSize;       // canvas size in px
uniform shader uTex;        // equirectangular Earth texture
uniform float2 uTexSize;    // texture size in px
uniform float uCenterLng;   // rotation, degrees
uniform float2 uSub;        // subsolar point: lat, lng (degrees)
uniform float4 uNight;      // deep-night tint
uniform float4 uAtmo;       // atmosphere color
uniform float4 uDay;        // flat day-surface color (used when uTextured = 0)
uniform float uTextured;    // 1 = sample the Earth texture, 0 = flat two-tone sphere
uniform float uExtras;      // 1 = draw glint / city-lights / rim, 0 = skip them

half4 main(float2 fragCoord) {
    float2 c = uSize * 0.5;
    float R = min(uSize.x, uSize.y) * 0.5 * 0.92;
    float nx = (fragCoord.x - c.x) / R;
    float ny = (c.y - fragCoord.y) / R;          // flip so +y points up
    float rho2 = nx * nx + ny * ny;
    float rho = sqrt(rho2);

    // Outside the sphere: soft atmospheric halo, fading to transparent.
    if (rho > 1.0) {
        float halo = smoothstep(1.14, 1.0, rho);
        return half4(half3(uAtmo.rgb * halo), half(halo * 0.45));
    }

    float lat = degrees(asin(clamp(ny, -1.0, 1.0)));
    float cosLat = cos(radians(lat));
    float lng = uCenterLng + degrees(asin(clamp(nx / max(cosLat, 1e-4), -1.0, 1.0)));
    float l = mod(lng, 360.0);

    // Textured styles sample the photographic Earth; the performance style skips the texture
    // fetch entirely and shades a flat two-tone sphere from uDay, which is the cheapest path.
    float3 surfRGB;
    if (uTextured > 0.5) {
        float u = l / 360.0;
        float v = (90.0 - clamp(lat, -90.0, 90.0)) / 180.0;
        half4 surf = uTex.eval(float2(u * uTexSize.x, v * uTexSize.y));
        surfRGB = float3(surf.rgb);
    } else {
        surfRGB = uDay.rgb;
    }

    // Day / twilight / night from the solar zenith angle.
    float la = radians(lat);
    float lo = radians(lng);
    float sla = radians(uSub.x);
    float slo = radians(uSub.y);
    float cz = sin(la) * sin(sla) + cos(la) * cos(sla) * cos(lo - slo);
    // Full daylight at the terminator (cz = 0), ramping to deep night by cz = -0.20. Twilight sits
    // on the night side of the line (sun below the horizon), matching the 2D map and reality —
    // not centered on the line, which would push the shadow ~6 degrees onto the sunlit side.
    float dayF = clamp((cz + 0.20) / 0.20, 0.0, 1.0);

    float limb = 0.55 + 0.45 * sqrt(max(0.0, 1.0 - rho2));
    // 0.30 night floor keeps the dark side dim but legible (the 2D map retains ~18% of the
    // texture); a lower floor crushes the night hemisphere to a near-black blob. The lit side is
    // unchanged: at dayF = 1 this is still 1.0.
    float bright = (0.30 + 0.70 * dayF) * limb;
    float nm = (1.0 - dayF) * 0.6;
    float3 col = surfRGB * bright * (1.0 - nm) + uNight.rgb * nm;

    // Realistic-only per-pixel extras (city night-lights, specular sun-glint, atmospheric rim).
    // Balanced/Performance skip this whole block, roughly halving the shader's ALU per pixel.
    if (uExtras > 0.5) {
        // Subtle city night-lights: warm glow on dark-side land (land reads warmer than ocean).
        float sr = surfRGB.r;
        float sg = surfRGB.g;
        float sb = surfRGB.b;
        float landish = clamp((max(sr, sg) - sb - 0.04) * 6.0, 0.0, 1.0);
        float nightSide = smoothstep(0.35, 0.0, dayF);
        col += float3(1.0, 0.78, 0.45) * (landish * nightSide * 0.10);

        // Specular sun-glint on open water where the sun is near-overhead (day side only).
        float ocean = 1.0 - landish;
        float glint = pow(max(cz, 0.0), 48.0) * ocean * limb;
        col += float3(1.0, 0.97, 0.85) * (glint * 0.45);

        // Atmospheric rim brightening toward the limb.
        float rim = smoothstep(0.82, 1.0, rho);
        col += uAtmo.rgb * (rim * 0.18 * (0.35 + 0.65 * dayF));
    }

    return half4(half3(col), 1.0);
}
"""

/**
 * An orthographic 3D-style globe (§5.2). On API 33+ the textured sphere is rendered per-pixel by a
 * GPU [RuntimeShader] (smooth at any size, with atmosphere and night-lights); older devices fall
 * back to a pure-Canvas grid sampler. Either way it shows the day/night terminator from the shared
 * [instant], plots saved-zone pins on the visible hemisphere, and spins by dragging.
 */
@Composable
fun GlobeView(
    instant: Instant,
    zones: List<SavedZone>,
    dayColor: Color,
    nightColor: Color,
    sunColor: Color,
    pinColor: Color,
    pinNightColor: Color,
    atmosphereColor: Color,
    modifier: Modifier = Modifier,
    style: MapStyle = MapStyle.REALISTIC,
) {
    // Performance style shades a flat two-tone sphere, so it never samples the texture; skip the
    // photographic decode (and the ~8 MB it would hold) and run purely from the day/night colors.
    val textured = style != MapStyle.PERFORMANCE
    val extras = style == MapStyle.REALISTIC
    val context = androidx.compose.ui.platform.LocalContext.current
    val mapBitmap = remember(textured) {
        if (!textured) {
            null
        } else try {
            BitmapFactory.decodeResource(context.resources, com.example.R.drawable.world_map)
        } catch (e: Exception) {
            null
        }
    }
    val bitmapWidth = mapBitmap?.width ?: 0
    val bitmapHeight = mapBitmap?.height ?: 0

    // The GPU path is available on API 33+ whenever the chosen style has its bitmap (textured) or
    // doesn't need one (flat Performance). The shader still requires its uTex input to be bound, so
    // in flat mode we feed it a 1×1 placeholder that uTextured = 0 keeps it from ever sampling.
    val canUseShader = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
        (mapBitmap != null || !textured)
    // Compile the AGSL up front; if it ever fails on a device we drop to the Canvas path.
    val earthShader = remember(canUseShader) {
        if (canUseShader) runCatching { RuntimeShader(EARTH_AGSL) }.getOrNull() else null
    }
    val bitmapShader = remember(mapBitmap, canUseShader, textured) {
        if (!canUseShader) {
            null
        } else if (mapBitmap != null) {
            BitmapShader(mapBitmap, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        } else {
            val placeholder = android.graphics.Bitmap.createBitmap(1, 1, android.graphics.Bitmap.Config.ARGB_8888)
            BitmapShader(placeholder, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        }
    }
    val shaderActive = earthShader != null && bitmapShader != null

    // Pixel buffer is only needed by the Canvas fallback (the shader samples the texture itself).
    val pixelArray = remember(mapBitmap, shaderActive) {
        if (!shaderActive && mapBitmap != null && bitmapWidth > 0 && bitmapHeight > 0) {
            val arr = IntArray(bitmapWidth * bitmapHeight)
            mapBitmap.getPixels(arr, 0, bitmapWidth, 0, 0, bitmapWidth, bitmapHeight)
            arr
        } else {
            null
        }
    }
    var centerLng by remember { mutableFloatStateOf(0f) }
    val subsolar = remember(instant) { SolarMath.subsolarPoint(instant) }
    val pins = remember(instant, zones) {
        zones.map { it.displayName to ZoneCoordinates.coordinateFor(it.id, instant) }
    }

    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .semantics { contentDescription = "Rotatable 3D globe showing day and night. Drag to spin." }
            .pointerInput(Unit) {
                detectDragGestures { change, drag ->
                    change.consume()
                    centerLng = ((centerLng - drag.x * 0.4f) % 360f)
                }
            }
    ) {
        val r = size.minDimension / 2f * 0.92f
        val cx = size.width / 2f
        val cy = size.height / 2f
        val lng0 = centerLng.toDouble()

        if (shaderActive && earthShader != null && bitmapShader != null) {
            drawEarthSphere(
                shader = earthShader,
                tex = bitmapShader,
                texWidth = bitmapWidth.coerceAtLeast(1),
                texHeight = bitmapHeight.coerceAtLeast(1),
                centerLng = centerLng,
                subLat = subsolar.latitude.toFloat(),
                subLng = subsolar.longitude.toFloat(),
                dayColor = dayColor,
                nightColor = nightColor,
                atmosphereColor = atmosphereColor,
                textured = textured,
                extras = extras,
            )
        } else {
            drawCanvasGlobe(
                r = r,
                cx = cx,
                cy = cy,
                lng0 = lng0,
                grid = if (textured) GRID else GRID_PERF,
                subLat = subsolar.latitude,
                subLng = subsolar.longitude,
                pixelArray = pixelArray,
                bitmapWidth = bitmapWidth,
                bitmapHeight = bitmapHeight,
                dayColor = dayColor,
                nightColor = nightColor,
                atmosphereColor = atmosphereColor,
            )
        }

        // Pins on the visible (front) hemisphere — crisp vector overlay for both paths.
        pins.forEach { (_, coord) ->
            val dLng = (coord.longitude - lng0) * DEG
            val front = cos(coord.latitude * DEG) * cos(dLng)
            if (front >= 0.0) {
                val sx = (cos(coord.latitude * DEG) * sin(dLng)).toFloat()
                val sy = sin(coord.latitude * DEG).toFloat()
                val pos = Offset(cx + sx * r, cy - sy * r)
                val lit = cosZenith(coord.latitude, coord.longitude, subsolar.latitude, subsolar.longitude) > 0.0
                drawCircle(Color.White, radius = r * 0.022f, center = pos)
                drawCircle(if (lit) pinColor else pinNightColor, radius = r * 0.014f, center = pos)
            }
        }

        // Subsolar sun marker, if on the visible hemisphere.
        val sunDLng = (subsolar.longitude - lng0) * DEG
        if (cos(subsolar.latitude * DEG) * cos(sunDLng) >= 0.0) {
            val sx = (cos(subsolar.latitude * DEG) * sin(sunDLng)).toFloat()
            val sy = sin(subsolar.latitude * DEG).toFloat()
            drawCircle(sunColor, radius = r * 0.03f, center = Offset(cx + sx * r, cy - sy * r))
        }
    }
}

/** GPU path: feed uniforms to the AGSL shader and fill the canvas with the textured sphere. */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
private fun DrawScope.drawEarthSphere(
    shader: RuntimeShader,
    tex: BitmapShader,
    texWidth: Int,
    texHeight: Int,
    centerLng: Float,
    subLat: Float,
    subLng: Float,
    dayColor: Color,
    nightColor: Color,
    atmosphereColor: Color,
    textured: Boolean,
    extras: Boolean,
) {
    shader.setFloatUniform("uSize", size.width, size.height)
    shader.setFloatUniform("uTexSize", texWidth.toFloat(), texHeight.toFloat())
    shader.setFloatUniform("uCenterLng", centerLng)
    shader.setFloatUniform("uSub", subLat, subLng)
    shader.setFloatUniform("uNight", nightColor.red, nightColor.green, nightColor.blue, 1f)
    shader.setFloatUniform("uAtmo", atmosphereColor.red, atmosphereColor.green, atmosphereColor.blue, 1f)
    shader.setFloatUniform("uDay", dayColor.red, dayColor.green, dayColor.blue, 1f)
    shader.setFloatUniform("uTextured", if (textured) 1f else 0f)
    shader.setFloatUniform("uExtras", if (extras) 1f else 0f)
    shader.setInputShader("uTex", tex)
    drawRect(brush = ShaderBrush(shader))
}

/** CPU fallback (pre-API 33): sample the texture across a grid over the disc. */
private fun DrawScope.drawCanvasGlobe(
    r: Float,
    cx: Float,
    cy: Float,
    lng0: Double,
    grid: Int,
    subLat: Double,
    subLng: Double,
    pixelArray: IntArray?,
    bitmapWidth: Int,
    bitmapHeight: Int,
    dayColor: Color,
    nightColor: Color,
    atmosphereColor: Color,
) {
    // Atmosphere halo.
    drawCircle(color = atmosphereColor.copy(alpha = 0.25f), radius = r * 1.06f, center = Offset(cx, cy))
    // Globe base circle (default night ocean).
    drawCircle(color = nightColor, radius = r, center = Offset(cx, cy))

    val step = (2f * r) / grid
    var gx = 0
    while (gx <= grid) {
        var gy = 0
        val px = -r + gx * step
        while (gy <= grid) {
            val py = -r + gy * step
            val nx = px / r
            val ny = py / r
            val rho = sqrt(nx * nx + ny * ny)
            if (rho <= 1.0) {
                val lat = asin(ny.coerceIn(-1f, 1f).toDouble()) / DEG
                val cosLat = cos(lat * DEG)
                if (cosLat > 1e-4) {
                    val sinArg = (nx / cosLat).coerceIn(-1.0, 1.0)
                    val lng = lng0 + asin(sinArg) / DEG

                    var surface = dayColor
                    if (pixelArray != null && bitmapWidth > 0 && bitmapHeight > 0) {
                        var l = lng
                        l %= 360.0
                        if (l < 0.0) l += 360.0
                        val clampedLat = lat.coerceIn(-90.0, 90.0)
                        val u = l / 360.0
                        val vCoord = (90.0 - clampedLat) / 180.0
                        val x = (u * (bitmapWidth - 1)).toInt().coerceIn(0, bitmapWidth - 1)
                        val y = (vCoord * (bitmapHeight - 1)).toInt().coerceIn(0, bitmapHeight - 1)
                        val pixel = pixelArray[y * bitmapWidth + x]
                        surface = Color(
                            red = ((pixel ushr 16) and 0xFF) / 255f,
                            green = ((pixel ushr 8) and 0xFF) / 255f,
                            blue = (pixel and 0xFF) / 255f,
                        )
                    }

                    val cz = cosZenith(lat, lng, subLat, subLng)
                    // Match the shader: full day at the terminator (cz = 0), night by cz = -0.20.
                    val dayF = (((cz + 0.20) / 0.20).coerceIn(0.0, 1.0)).toFloat()
                    val limb = (0.55f + 0.45f * sqrt((1.0 - rho * rho)).toFloat())
                    // Match the shader's 0.30 night floor (keeps the dark side legible).
                    val bright = (0.30f + 0.70f * dayF) * limb
                    val nightMix = (1f - dayF) * 0.6f
                    val color = Color(
                        red = (surface.red * bright * (1f - nightMix) + nightColor.red * nightMix).coerceIn(0f, 1f),
                        green = (surface.green * bright * (1f - nightMix) + nightColor.green * nightMix).coerceIn(0f, 1f),
                        blue = (surface.blue * bright * (1f - nightMix) + nightColor.blue * nightMix).coerceIn(0f, 1f),
                    )

                    drawRect(
                        color = color,
                        topLeft = Offset(cx + px, cy - py),
                        size = androidx.compose.ui.geometry.Size(step + 1f, step + 1f),
                    )
                }
            }
            gy++
        }
        gx++
    }
}

private fun cosZenith(lat: Double, lng: Double, subLat: Double, subLng: Double): Double =
    sin(lat * DEG) * sin(subLat * DEG) +
        cos(lat * DEG) * cos(subLat * DEG) * cos((lng - subLng) * DEG)
