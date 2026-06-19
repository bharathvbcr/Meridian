package com.example.core.designsystem

import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState

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
