package com.example.core.designsystem

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.core.designsystem.GlassUtils.applyGlassEffect
import dev.chrisbanes.haze.HazeState

@Composable
fun GlassCard(
    hazeState: HazeState,
    modifier: Modifier = Modifier,
    shape: Shape = GlassDefaults.cardShape,
    borderWidth: Dp = 0.5.dp,
    tintColor: Color = GlassDefaults.cardTint,
    content: @Composable () -> Unit
) {
    Box(
        modifier = modifier
            .applyGlassEffect(
                hazeState = hazeState,
                shape = shape,
                borderWidth = borderWidth,
                tintColor = tintColor
            )
    ) {
        content()
    }
}

@Composable
fun GlassToolbar(
    title: String,
    hazeState: HazeState,
    modifier: Modifier = Modifier,
    actions: @Composable RowScope.() -> Unit = {}
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .applyGlassEffect(
                hazeState = hazeState,
                shape = RoundedCornerShape(0.dp), // Toolbar usually bleeds to edges
                borderWidth = 0.dp,
                tintColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.5f)
            )
            .windowInsetsPadding(WindowInsets.statusBars)
            .padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.align(Alignment.CenterStart)
        )
        Row(
            modifier = Modifier.align(Alignment.CenterEnd),
            verticalAlignment = Alignment.CenterVertically
        ) {
            actions()
        }
    }
}
