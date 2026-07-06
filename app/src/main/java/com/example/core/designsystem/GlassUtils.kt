package com.example.core.designsystem

import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState

/**
 * Warm (day) / cool (night) radial glow in a card's top-right corner. Uses drawWithCache so
 * the gradient brush is rebuilt only when the size or day/night state changes — not allocated
 * again on every draw pass, which matters on cards that redraw on a clock tick.
 */
@Composable
fun Modifier.daylightGlowBehind(isDaylight: Boolean): Modifier {
    val glowColor =
        (if (isDaylight) GlassDefaults.daylightGlow else GlassDefaults.nightGlow).copy(alpha = 0.22f)
    return drawWithCache {
        val center = Offset(size.width * 0.85f, size.height * 0.15f)
        val radius = size.width * 0.6f
        val brush = Brush.radialGradient(
            colors = listOf(glowColor, Color.Transparent),
            center = center,
            radius = radius,
        )
        onDrawBehind { drawCircle(brush = brush, center = center, radius = radius) }
    }
}

object GlassUtils {
    @Composable
    fun Modifier.applyGlassEffect(
        hazeState: HazeState,
        shape: Shape = GlassDefaults.cardShape,
        borderWidth: Dp = 0.5.dp,
        tintColor: Color = Color.White.copy(alpha = 0.1f),
        opaqueFallbackColor: Color = MaterialTheme.colorScheme.surface,
        borderColor: Color = Color.White.copy(alpha = 0.2f)
    ): Modifier {
        return this.liquidGlass(
            hazeState = hazeState,
            shape = shape,
            borderWidth = borderWidth,
            tintColor = tintColor,
            opaqueFallbackColor = opaqueFallbackColor,
            borderColor = borderColor
        )
    }
}
