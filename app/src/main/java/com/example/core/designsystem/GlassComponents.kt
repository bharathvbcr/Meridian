package com.example.core.designsystem

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState

/**
 * Local mirror of Meridian's documented 4/8/12/16/20/24 spacing scale, kept private to this
 * design-system file so the two platforms stay conceptually in parity without leaking new
 * public surface. Prefer these over ad-hoc dp literals inside this file's components.
 */
private object GlassSpacing {
    val xs: Dp = 4.dp
    val sm: Dp = 8.dp
    val md: Dp = 12.dp
    val lg: Dp = 16.dp
    val xl: Dp = 20.dp
}

@Composable
fun GlassCard(
    hazeState: HazeState,
    modifier: Modifier = Modifier,
    shape: Shape = GlassDefaults.cardShape,
    borderWidth: Dp = 0.5.dp,
    tintColor: Color = GlassDefaults.cardTint,
    content: @Composable () -> Unit
) {
    // Two-layer glass so the AGSL refraction warps only the backdrop, never this card's content.
    LiquidGlassSurface(
        hazeState = hazeState,
        modifier = modifier,
        shape = shape,
        borderWidth = borderWidth,
        tintColor = tintColor,
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
    LiquidGlassSurface(
        hazeState = hazeState,
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(0.dp), // Toolbar usually bleeds to edges
        borderWidth = 0.dp,
        tintColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.5f),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.statusBars)
                .padding(horizontal = GlassSpacing.lg, vertical = GlassSpacing.md)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurface,
                // Expose the toolbar title as a heading so TalkBack users can jump to it.
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .semantics { heading() }
            )
            Row(
                modifier = Modifier.align(Alignment.CenterEnd),
                verticalAlignment = Alignment.CenterVertically
            ) {
                actions()
            }
        }
    }
}

@Composable
fun EmptyStateCard(
    icon: ImageVector,
    title: String,
    message: String,
    hazeState: HazeState,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    LiquidGlassSurface(
        hazeState = hazeState,
        modifier = modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier
                .padding(GlassSpacing.xl)
                // Merge icon + title + message into one TalkBack focus target so an empty
                // state reads as a single coherent announcement instead of three swipes.
                // The optional action Button keeps its own label and focus.
                .semantics(mergeDescendants = true) {},
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(
                imageVector = icon,
                // Decorative — the merged title/message already convey the meaning.
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.5f),
                modifier = Modifier.size(40.dp),
            )
            Spacer(Modifier.height(GlassSpacing.md))
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center,
            )
            // Message hugs its title (xs) so the pair reads as one unit; the larger gap
            // sits above the title (md), establishing icon → [title+message] → action rhythm.
            Spacer(Modifier.height(GlassSpacing.xs))
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
                // 0.7 keeps supporting copy legible against the dark glass (WCAG-AA) while
                // still reading as secondary to the title.
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
            )
            if (actionLabel != null && onAction != null) {
                Spacer(Modifier.height(GlassSpacing.lg))
                Button(
                    onClick = onAction,
                    // Match the card's rounded-rect language via a design-system radius
                    // token rather than a hardcoded full pill.
                    shape = MaterialTheme.shapes.large,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = MaterialTheme.colorScheme.onPrimary,
                    ),
                ) {
                    Text(actionLabel, style = MaterialTheme.typography.labelLarge)
                }
            }
        }
    }
}
