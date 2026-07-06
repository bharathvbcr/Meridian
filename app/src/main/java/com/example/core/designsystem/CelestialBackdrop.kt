package com.example.core.designsystem

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Canvas
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import com.example.core.time.GeoPoint
import com.example.core.time.SolarMath
import com.example.core.time.ZoneCoordinates
import com.example.core.data.DEFAULT_BACKDROP_INTENSITY
import kotlinx.coroutines.delay
import java.time.Instant
import java.time.ZoneId
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * A realistic, time-of-day aware sun/moon that lives *behind* every page (§ ambience).
 *
 * It is drawn inside the Haze source layer, so the light it casts is blurred, refracted and
 * diffused by every liquid-glass element on top of it — the sun's warm corona bleeds around the
 * glass cards and the nav bar exactly like a real backdrop seen through frosted glass.
 *
 * The body's position follows the sun across the sky between sunrise and sunset (and the moon
 * across the night), its colour warms toward the horizon, and the moon shows the correct lit
 * phase for the date. All geometry is derived from [SolarMath]; nothing is faked per-frame.
 */
@Composable
fun CelestialBackdrop(
    modifier: Modifier = Modifier,
    intensity: Float = DEFAULT_BACKDROP_INTENSITY / 100f,
) {
    val zoneId = remember { ZoneId.systemDefault() }
    val geo: GeoPoint = remember(zoneId) { ZoneCoordinates.coordinateFor(zoneId.id, Instant.now()) }

    // Reduce-transparency parity: the glass surfaces on top of this backdrop flatten to opaque
    // (via `glassImpl`) whenever the OS high-contrast flag or the user override is on. When they do,
    // the busy refracted glow behind them no longer serves its purpose and only erodes the contrast
    // of text now sitting on solid cards. So read the *same* signal the glass reads and calm the
    // canvas in lockstep — dim the whole scene and drop the twinkling starfield — instead of drawing
    // the full-intensity sun/moon/stars regardless. Mirrors the iOS backdrop's reduce-transparency gate.
    val reduceTransparency = rememberReduceTransparency() || LocalReduceTransparencyOverride.current

    // Recompute the sky once a minute — fast enough to track the sun, cheap enough to ignore.
    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(zoneId) {
        while (true) {
            now = Instant.now()
            delay(60_000)
        }
    }

    // This backdrop is the Haze *source* layer, so anything that invalidates it forces every
    // liquid-glass surface in the app to re-capture and re-blur the backdrop. A per-frame infinite
    // shimmer/twinkle therefore drove a full re-blur of every glass element at the display refresh
    // rate (up to 120 Hz) even when the user was doing nothing — the dominant cause of app-wide
    // stutter. The light now updates only with `now` (once a minute), so the blurred backdrop is
    // effectively static and the glass layers sample a cached source instead of a live animation.
    val sky = remember(now, geo, zoneId) { computeSky(now, geo, zoneId) }

    // The scene below is a heavy vector draw (radial-gradient corona + halo + disc, 12 rotated
    // gradient rays, a 96-point moon-phase path, 64 stars) and it lives inside the Haze source
    // layer. Replaying all of that — and re-allocating every Brush/Path/Color — each time the
    // source GraphicsLayer re-records (every glass capture, scroll, transition) is wasteful when
    // the picture only changes once a minute. So rasterize the whole scene once into an
    // ImageBitmap and replay it as a single drawImage. `drawWithCache`'s build block re-runs only
    // when the layout size or `sky` changes, exactly matching how often the image must change.
    // This is the same cache-to-bitmap approach used for the DayNightMap terminator overlay.
    //
    // The bitmap is rendered at a fraction of the layout resolution (BACKDROP_RENDER_SCALE) and
    // upscaled on replay: the backdrop is a soft glow that the glass blurs anyway, so it doesn't
    // need native resolution. This cuts the cached bitmap's memory (~4x at 0.5) and the per-minute
    // rasterization cost by the same factor. To keep the picture pixel-identical to the 1:1
    // version, the scene is drawn in full-resolution logical coordinates under a `scale` transform
    // rather than by shrinking the geometry — so absolute sizes (disc radius, stroke and star
    // widths) scale down with the canvas and back up on replay instead of being clamped at raw px.
    // Under reduce-transparency, fade the glow well down so text on the now-opaque cards keeps its
    // contrast, while still leaving a faint calm wash so the app doesn't read as flat black.
    val effectiveIntensity =
        (if (reduceTransparency) intensity * CALM_INTENSITY_SCALE else intensity).coerceIn(0f, 1f)

    Box(
        modifier = modifier
            .fillMaxSize()
            // Decorative ambience only — the sky conveys no information a screen reader needs, and
            // the real time-of-day content lives in the foreground surfaces. Keep it out of the tree.
            .clearAndSetSemantics { }
            .alpha(effectiveIntensity)
            .drawWithCache {
                val fullW = size.width
                val fullH = size.height
                val bw = (fullW * BACKDROP_RENDER_SCALE).toInt()
                val bh = (fullH * BACKDROP_RENDER_SCALE).toInt()
                if (bw <= 0 || bh <= 0) {
                    onDrawBehind { }
                } else {
                    val image = ImageBitmap(bw, bh)
                    // The scene is direction-agnostic (all positions are explicit), so Ltr is fine.
                    CanvasDrawScope().draw(
                        this,
                        LayoutDirection.Ltr,
                        Canvas(image),
                        Size(bw.toFloat(), bh.toFloat()),
                    ) {
                        scale(BACKDROP_RENDER_SCALE, BACKDROP_RENDER_SCALE, pivot = Offset.Zero) {
                            drawSky(sky, fullW, fullH, calm = reduceTransparency)
                        }
                    }
                    val dst = IntSize(fullW.toInt(), fullH.toInt())
                    onDrawBehind {
                        drawImage(image = image, dstSize = dst, filterQuality = FilterQuality.Low)
                    }
                }
            }
    )
}

/**
 * Fraction of the configured intensity the backdrop is drawn at when reduce-transparency is on.
 * Low enough to stop the glow from bleeding contrast out of the now-opaque cards, but non-zero so a
 * calm celestial wash remains instead of a flat void.
 */
private const val CALM_INTENSITY_SCALE = 0.35f

/** Fraction of the layout resolution the backdrop bitmap is rendered at; see the call site. */
private const val BACKDROP_RENDER_SCALE = 0.5f

/**
 * Paints the full sun/moon/stars scene for [sky] into the current [DrawScope] at size [w]×[h].
 * When [calm] is set (reduce-transparency), the fine starfield is dropped and the sun's directional
 * rays are suppressed so the canvas is a quiet glow rather than a busy, contrast-eroding backdrop.
 */
private fun DrawScope.drawSky(sky: SkyState, w: Float, h: Float, calm: Boolean = false) {
    // `pulse` was an animated value; it is now a fixed mid-pulse so the scene is static (see above).
    val pulse = 0.5f
    val twinkle = 0f

    // Where the body sits: horizontal travel sunrise→sunset (or across the night for the
    // moon), vertical position arcing up toward solar noon.
    val cx = (0.16f + 0.68f * sky.progressX) * w
    val cy = (0.40f - 0.30f * sky.altitude) * h

    if (sky.dayFactor > 0.01f) {
        drawSun(cx, cy, w, h, sky, pulse, sky.dayFactor, calm)
    }
    if (sky.dayFactor < 0.99f) {
        val nightAlpha = 1f - sky.dayFactor
        // Skip the 64-star field entirely when calm: it's the busiest, lowest-value element and the
        // one most likely to sit behind high-contrast text.
        if (!calm) drawStars(w, h, twinkle, nightAlpha)
        drawMoon(cx, cy, w, h, sky, pulse, nightAlpha)
    }
}

/** Draws the sun: a wide diffuse corona (the light the glass refracts), a hot core and soft rays. */
private fun DrawScope.drawSun(
    cx: Float,
    cy: Float,
    w: Float,
    h: Float,
    sky: SkyState,
    pulse: Float,
    alpha: Float,
    calm: Boolean = false,
) {
    val center = Offset(cx, cy)
    // Warm low sun → bright high sun. Drives both the disc and the cast light.
    val core = lerp(Color(0xFFFF7B3D), Color(0xFFFFF6D8), sky.altitude)
    val warm = lerp(Color(0xFFFF5E3A), Color(0xFFFFD66B), sky.altitude)

    // The big atmospheric glow. This is what bleeds around and through the glass.
    val glowRadius = max(w, h) * (0.85f + 0.10f * pulse)
    drawCircle(
        brush = Brush.radialGradient(
            colorStops = arrayOf(
                0.0f to warm.copy(alpha = 0.55f * alpha),
                0.18f to warm.copy(alpha = 0.30f * alpha),
                0.45f to warm.copy(alpha = 0.10f * alpha),
                1.0f to Color.Transparent
            ),
            center = center,
            radius = glowRadius
        ),
        radius = glowRadius,
        center = center
    )

    // Soft directional rays for a touch of god-ray realism. Suppressed under reduce-transparency:
    // the 12 crossing gradient streaks are the busiest part of the sun and add the least value when
    // the goal is a quiet, high-contrast canvas.
    if (!calm) {
        val rayLen = max(w, h) * 0.7f
        rotate(degrees = pulse * 6f, pivot = center) {
            for (i in 0 until 12) {
                rotate(degrees = i * 30f, pivot = center) {
                    drawLine(
                        brush = Brush.linearGradient(
                            colors = listOf(
                                warm.copy(alpha = 0.10f * alpha),
                                Color.Transparent
                            ),
                            start = center,
                            end = Offset(center.x, center.y - rayLen)
                        ),
                        start = center,
                        end = Offset(center.x, center.y - rayLen),
                        strokeWidth = 26f,
                        cap = StrokeCap.Round
                    )
                }
            }
        }
    }

    val discRadius = (0.052f * max(w, h)).coerceIn(46f, 120f)
    // Halo around the disc.
    drawCircle(
        brush = Brush.radialGradient(
            colorStops = arrayOf(
                0.0f to core.copy(alpha = 0.9f * alpha),
                0.6f to warm.copy(alpha = 0.5f * alpha),
                1.0f to Color.Transparent
            ),
            center = center,
            radius = discRadius * 2.4f
        ),
        radius = discRadius * 2.4f,
        center = center
    )
    // The bright body itself.
    drawCircle(
        brush = Brush.radialGradient(
            colorStops = arrayOf(
                0.0f to Color.White.copy(alpha = alpha),
                0.5f to core.copy(alpha = alpha),
                1.0f to warm.copy(alpha = 0.85f * alpha)
            ),
            center = Offset(cx - discRadius * 0.2f, cy - discRadius * 0.2f),
            radius = discRadius
        ),
        radius = discRadius,
        center = center
    )
}

/** Draws the moon with its true lit phase, a cool halo and a faint cast glow. */
private fun DrawScope.drawMoon(
    cx: Float,
    cy: Float,
    w: Float,
    h: Float,
    sky: SkyState,
    pulse: Float,
    alpha: Float,
) {
    val center = Offset(cx, cy)
    val cool = Color(0xFFC9D8FF)

    // Cool moonlight glow — softer and tighter than the sun's, but still diffused by the glass.
    val glowRadius = max(w, h) * (0.5f + 0.06f * pulse)
    drawCircle(
        brush = Brush.radialGradient(
            colorStops = arrayOf(
                0.0f to cool.copy(alpha = 0.28f * alpha),
                0.3f to cool.copy(alpha = 0.10f * alpha),
                1.0f to Color.Transparent
            ),
            center = center,
            radius = glowRadius
        ),
        radius = glowRadius,
        center = center
    )

    val r = (0.045f * max(w, h)).coerceIn(40f, 100f)

    // Halo ring.
    drawCircle(
        brush = Brush.radialGradient(
            colorStops = arrayOf(
                0.0f to cool.copy(alpha = 0.35f * alpha),
                0.7f to cool.copy(alpha = 0.12f * alpha),
                1.0f to Color.Transparent
            ),
            center = center,
            radius = r * 2.2f
        ),
        radius = r * 2.2f,
        center = center
    )

    // Lit disc, lightly shaded toward the lower-right for a spherical feel.
    drawCircle(
        brush = Brush.radialGradient(
            colorStops = arrayOf(
                0.0f to Color(0xFFFDFEFF).copy(alpha = alpha),
                0.7f to Color(0xFFE6ECFB).copy(alpha = alpha),
                1.0f to Color(0xFFB7C4E0).copy(alpha = alpha)
            ),
            center = Offset(cx - r * 0.25f, cy - r * 0.25f),
            radius = r
        ),
        radius = r,
        center = center
    )

    // A couple of subtle maria so the disc doesn't read as a flat dot.
    drawCircle(Color(0xFF9FB0D0).copy(alpha = 0.30f * alpha), r * 0.20f, Offset(cx - r * 0.30f, cy - r * 0.18f))
    drawCircle(Color(0xFF9FB0D0).copy(alpha = 0.24f * alpha), r * 0.14f, Offset(cx + r * 0.22f, cy + r * 0.28f))
    drawCircle(Color(0xFF9FB0D0).copy(alpha = 0.20f * alpha), r * 0.10f, Offset(cx + r * 0.05f, cy - r * 0.35f))

    // Phase shadow: the unlit portion rendered as a dim, ashen earthshine face rather than a black
    // hole, so even a near-new moon still reads as a moon and never as a cut-out in the sky.
    val shadow = buildMoonShadow(cx, cy, r, sky.moonTerminator, sky.moonWaxing)
    drawPath(path = shadow, color = Color(0xFF2A3658).copy(alpha = 0.82f * alpha))

    // A faint rim so the full disc is always defined, whatever the phase.
    drawCircle(
        color = cool.copy(alpha = 0.22f * alpha),
        radius = r,
        center = center,
        style = Stroke(width = 1.4f)
    )
}

/**
 * Builds the unlit region of the moon as a closed path bounded by the dark limb and the
 * terminator ellipse. [c] is cos(phase angle): +1 at new moon (fully dark), -1 at full (fully lit).
 */
private fun buildMoonShadow(cx: Float, cy: Float, r: Float, c: Float, waxing: Boolean): Path {
    val path = Path()
    val n = 48
    fun wAt(i: Int): Pair<Float, Float> {
        val y = -r + 2f * r * i / n
        val w = sqrt((r * r - y * y).coerceAtLeast(0f))
        return y to w
    }
    if (waxing) {
        // Lit on the right → shadow spans the left limb across to the terminator at x = c·w.
        path.moveTo(cx, cy - r)
        for (i in 0..n) { val (y, w) = wAt(i); path.lineTo(cx - w, cy + y) }
        for (i in n downTo 0) { val (y, w) = wAt(i); path.lineTo(cx + c * w, cy + y) }
    } else {
        // Waning is the mirror image: lit on the left, shadow on the right.
        path.moveTo(cx, cy - r)
        for (i in 0..n) { val (y, w) = wAt(i); path.lineTo(cx + w, cy + y) }
        for (i in n downTo 0) { val (y, w) = wAt(i); path.lineTo(cx - c * w, cy + y) }
    }
    path.close()
    return path
}

/** A deterministic field of faint, gently twinkling stars for the night sky. */
private fun DrawScope.drawStars(w: Float, h: Float, twinkle: Float, alpha: Float) {
    var seed = 1337
    fun rnd(): Float {
        // Tiny LCG — deterministic so stars don't jump between frames (no Math.random).
        seed = (seed * 1103515245 + 12345) and 0x7FFFFFFF
        return seed / 0x7FFFFFFF.toFloat()
    }
    val count = 64
    for (i in 0 until count) {
        val sx = rnd() * w
        // Keep stars mostly in the upper two-thirds of the sky.
        val sy = rnd() * h * 0.7f
        val baseR = 0.6f + rnd() * 1.8f
        val phase = rnd() * (2f * PI).toFloat()
        val t = (sin(twinkle + phase) + 1f) / 2f
        val a = (0.20f + 0.55f * t) * alpha
        drawCircle(
            color = Color(0xFFEAF1FF).copy(alpha = a),
            radius = baseR * (0.7f + 0.5f * t),
            center = Offset(sx, sy)
        )
    }
}

/** Pre-computed, frame-independent description of the sky for the current instant. */
private data class SkyState(
    val dayFactor: Float,    // 1 = full sun, 0 = full moon, blended through twilight
    val progressX: Float,    // 0..1 horizontal travel of the visible body
    val altitude: Float,     // 0 at horizon, 1 at peak
    val moonTerminator: Float, // cos(phase angle): +1 new, -1 full
    val moonWaxing: Boolean,
)

private const val SYNODIC_MONTH_MS = 2_551_442_876.0 // 29.530588853 days
private const val KNOWN_NEW_MOON_MS = 947_182_440_000L // 2000-01-06T18:14:00Z

private fun computeSky(now: Instant, geo: GeoPoint, zoneId: ZoneId): SkyState {
    val zdt = now.atZone(zoneId)
    val date = zdt.toLocalDate()
    val sun = SolarMath.sunTimes(geo.latitude, geo.longitude, date, zoneId)
    val cosZenith = SolarMath.cosSolarZenith(geo.latitude, geo.longitude, now)

    // Smooth sun↔moon crossfade through twilight rather than a hard switch at the horizon.
    val dayFactor = smoothstep(-0.10f, 0.06f, cosZenith.toFloat())

    val nowMin = zdt.hour * 60 + zdt.minute

    val progressX: Float
    val altitude: Float
    when {
        sun.polarDay -> { progressX = 0.5f; altitude = 0.7f }
        sun.polarNight -> { progressX = 0.5f; altitude = 0.55f }
        sun.sunrise != null && sun.sunset != null -> {
            val rise = sun.sunrise.hour * 60 + sun.sunrise.minute
            val set = sun.sunset.hour * 60 + sun.sunset.minute
            if (dayFactor >= 0.5f && set > rise) {
                val p = ((nowMin - rise).toFloat() / (set - rise)).coerceIn(0f, 1f)
                progressX = p
                altitude = sin(p * PI).toFloat().coerceIn(0f, 1f)
            } else {
                // Night arc from sunset, wrapping past midnight to the next sunrise.
                val nightLen = (1440 - (set - rise)).coerceAtLeast(1)
                val elapsed = if (nowMin >= set) nowMin - set else nowMin + (1440 - set)
                val p = (elapsed.toFloat() / nightLen).coerceIn(0f, 1f)
                progressX = p
                altitude = sin(p * PI).toFloat().coerceIn(0f, 1f)
            }
        }
        else -> { progressX = 0.5f; altitude = 0.5f }
    }

    // Moon phase from the synodic cycle since a known new moon.
    val ageFraction = (((now.toEpochMilli() - KNOWN_NEW_MOON_MS) / SYNODIC_MONTH_MS) % 1.0 + 1.0) % 1.0
    val moonTerminator = cos(2.0 * PI * ageFraction).toFloat()
    val moonWaxing = ageFraction < 0.5

    return SkyState(
        dayFactor = dayFactor,
        progressX = progressX,
        altitude = altitude,
        moonTerminator = moonTerminator,
        moonWaxing = moonWaxing,
    )
}

private fun smoothstep(edge0: Float, edge1: Float, x: Float): Float {
    val t = ((x - edge0) / (edge1 - edge0)).coerceIn(0f, 1f)
    return t * t * (3f - 2f * t)
}
