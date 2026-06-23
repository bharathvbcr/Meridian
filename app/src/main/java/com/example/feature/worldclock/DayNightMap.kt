package com.example.feature.worldclock

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.IntSize
import com.example.core.data.MapStyle
import com.example.core.data.SavedZone
import com.example.core.designsystem.GlassDefaults
import com.example.core.designsystem.liquidGlassBackdrop
import com.example.core.time.SolarMath
import com.example.core.time.ZoneCoordinates
import dev.chrisbanes.haze.HazeState
import java.time.Instant
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

private const val GRID_COLS = 160
private const val GRID_ROWS = 80
private const val DEG = PI / 180.0

/**
 * A 2D equirectangular day/night map with a live terminator (§5.2). Reads the shared
 * [instant] (driven by the scrubber), so dragging time sweeps the night region and the
 * subsolar "sun" across the globe. Pins each saved zone at its coordinate (offline lookup).
 * Battery-friendly: pure Canvas, no GPU model, redraws only when [instant] changes.
 */
@Composable
fun DayNightMap(
    instant: Instant,
    zones: List<SavedZone>,
    modifier: Modifier = Modifier,
    style: MapStyle = MapStyle.REALISTIC,
    hazeState: HazeState,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val isVector = style == MapStyle.VECTOR
    // The map is a single scaled drawImage either way, so the texture only differs in resolution:
    // Realistic/Balanced decode the full 2048×1024 source; Performance halves it (inSampleSize = 2,
    // ~8 MB → 2 MB). Vector decodes no photo at all — it draws bundled land outlines instead.
    val mapImage = remember(style) {
        if (isVector) return@remember null
        try {
            val opts = BitmapFactory.Options().apply {
                inSampleSize = if (style == MapStyle.PERFORMANCE) 2 else 1
            }
            BitmapFactory.decodeResource(context.resources, com.example.R.drawable.world_map, opts)
                ?.asImageBitmap()
        } catch (e: Exception) {
            null
        }
    }
    // Vector style: decode the country TopoJSON once into unit-space fill + border paths (see
    // [WorldAtlas]). Parsed off the composition thread to avoid a first-frame stall.
    val worldGeometry by androidx.compose.runtime.produceState<WorldGeometry?>(null, isVector) {
        value = if (isVector) {
            kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
                WorldAtlas.load(context)
            }
        } else {
            null
        }
    }
    // The decoded paths are in unit space; transform them to pixel space once per size so the border
    // stroke stays a uniform width (canvas-scaling a 2:1 map would make vertical borders look 2×
    // thicker than horizontal ones). Rebuilds only when the geometry or canvas size changes.
    var canvasSize by remember { mutableStateOf(IntSize.Zero) }
    val pixelPaths = remember(worldGeometry, canvasSize) {
        val g = worldGeometry
        if (g == null || canvasSize == IntSize.Zero) {
            null
        } else {
            val m = androidx.compose.ui.graphics.Matrix().apply {
                scale(canvasSize.width.toFloat(), canvasSize.height.toFloat())
            }
            val fill = Path().apply { addPath(g.land); transform(m) }
            val border = Path().apply { addPath(g.borders); transform(m) }
            fill to border
        }
    }

    val subsolar = remember(instant) { SolarMath.subsolarPoint(instant) }
    val pins = remember(instant, zones) {
        zones.map { it.displayName to ZoneCoordinates.coordinateFor(it.id, instant) }
    }

    // The terminator used to be rasterized as up to ~6,400 alpha-blended drawRect calls (plus a
    // Color allocation each) on every redraw. Instead we build the night/twilight mask once into a
    // small GRID_COLS×GRID_ROWS bitmap and let the GPU scale it up with one bilinear drawImage —
    // identical look, but a single draw call and no per-frame allocations. Cached on the subsolar
    // point, so it only rebuilds when the scrubbed time actually moves.
    val nightOverlay = remember(subsolar) { buildNightOverlay(subsolar.latitude, subsolar.longitude) }

    val oceanFallback = Color(0xFF0B2A52)
    val mapShape = RoundedCornerShape(20.dp)
    // Vector style: translucent fills over the frosted glass surface so the celestial backdrop
    // refracts through like the other cards on this screen.
    val vectorLand = MaterialTheme.colorScheme.primary.copy(alpha = 0.28f)
    val vectorBorder = Color.White.copy(alpha = 0.38f)
    val sunColor = MaterialTheme.colorScheme.tertiary
    val pinColor = MaterialTheme.colorScheme.primary
    val pinNightColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f)

    Column(modifier = modifier) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(2f)
                .clip(mapShape)
                .onSizeChanged { canvasSize = it }
                .semantics {
                    contentDescription = "World day and night map. Sun is overhead near " +
                        "latitude ${subsolar.latitude.toInt()}, longitude ${subsolar.longitude.toInt()} degrees."
                }
        ) {
            // Vector mode gets the full liquid-glass surface as a backdrop layer *behind* the map
            // canvas, so the refraction warps only the blurred backdrop, never the map or its pins.
            if (isVector) {
                Box(
                    Modifier
                        .matchParentSize()
                        .liquidGlassBackdrop(
                            hazeState = hazeState,
                            shape = mapShape,
                            tintColor = GlassDefaults.cardTint,
                        )
                )
            }
            Canvas(modifier = Modifier.fillMaxSize()) {
            val w = size.width
            val h = size.height

            when {
                // Vector: frosted glass shows through the ocean; land and borders are translucent
                // tints on top. Paths are pre-transformed to pixel space (pixelPaths).
                isVector -> {
                    pixelPaths?.let { (fill, border) ->
                        drawPath(path = fill, color = vectorLand)
                        drawPath(
                            path = border,
                            color = vectorBorder,
                            style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.dp.toPx()),
                        )
                    }
                }
                // Realistic / Balanced / Performance: photographic Earth texture in full color.
                mapImage != null -> drawImage(image = mapImage, dstSize = IntSize(w.toInt(), h.toInt()))
                else -> drawRect(color = oceanFallback)
            }

            // Night/twilight overlay: one GPU-scaled draw of the cached mask (built in
            // buildNightOverlay), replacing the former per-cell rectangle loop.
            drawImage(
                image = nightOverlay,
                dstSize = IntSize(w.toInt(), h.toInt()),
                alpha = if (isVector) 0.7f else 1f,
            )

            // Subsolar sun marker.
            val sunPos = project(subsolar.latitude, subsolar.longitude, w, h)
            drawCircle(color = sunColor.copy(alpha = 0.35f), radius = h * 0.06f, center = sunPos)
            drawCircle(color = sunColor, radius = h * 0.025f, center = sunPos)

            // Zone pins, tinted by whether it's day or night there right now.
            pins.forEach { (_, coord) ->
                val lit = cosZenith(coord.latitude, coord.longitude, subsolar.latitude, subsolar.longitude) > 0.0
                val pos = project(coord.latitude, coord.longitude, w, h)
                drawCircle(color = Color.White, radius = h * 0.018f, center = pos)
                drawCircle(
                    color = if (lit) pinColor else pinNightColor,
                    radius = h * 0.012f,
                    center = pos,
                )
            }
            }
        }

        Spacer(Modifier.height(8.dp))
        Text(
            text = "Day / night updates as you scrub time. Lit pins are in daylight now.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
            modifier = Modifier.padding(horizontal = 4.dp)
        )
    }
}

/** Deep-night tint as a packed RGB (matches the former Color(0xFF0B1020)); alpha is added per cell. */
private const val NIGHT_RGB = 0x0B1020

/**
 * Builds the night/twilight mask once at [GRID_COLS]×[GRID_ROWS] resolution: each pixel's alpha
 * ramps continuously from 0 at the day/night line to a deep-night cap, exactly as the old per-cell
 * loop did, but as a single small bitmap the GPU can stretch over the map with one bilinear blit.
 */
private fun buildNightOverlay(subLat: Double, subLng: Double): ImageBitmap {
    val pixels = IntArray(GRID_COLS * GRID_ROWS)
    for (gy in 0 until GRID_ROWS) {
        val lat = 90.0 - (gy + 0.5) / GRID_ROWS * 180.0
        for (gx in 0 until GRID_COLS) {
            val lng = -180.0 + (gx + 0.5) / GRID_COLS * 360.0
            val cosZ = cosZenith(lat, lng, subLat, subLng)
            pixels[gy * GRID_COLS + gx] = if (cosZ < 0.0) {
                val night = (-cosZ / 0.20).coerceIn(0.0, 1.0) // 0 at line .. 1 deep night
                val alpha = (night * 0.82 * 255.0).toInt().coerceIn(0, 255)
                (alpha shl 24) or NIGHT_RGB
            } else {
                0 // daylight: fully transparent
            }
        }
    }
    return Bitmap.createBitmap(pixels, GRID_COLS, GRID_ROWS, Bitmap.Config.ARGB_8888).asImageBitmap()
}

/** Equirectangular projection from geo degrees to canvas pixels. */
private fun project(lat: Double, lng: Double, w: Float, h: Float): Offset {
    val x = ((lng + 180.0) / 360.0 * w).toFloat()
    val y = ((90.0 - lat) / 180.0 * h).toFloat()
    return Offset(x, y)
}

/** cos(solar zenith) given a precomputed subsolar point; > 0 day, < 0 night. */
private fun cosZenith(lat: Double, lng: Double, subLat: Double, subLng: Double): Double =
    sin(lat * DEG) * sin(subLat * DEG) +
        cos(lat * DEG) * cos(subLat * DEG) * cos((lng - subLng) * DEG)
