package com.example.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.core.designsystem.GlassDefaults
import com.example.core.designsystem.LiquidGlassSurface
import com.example.core.designsystem.LocalReduceMotion
import com.example.core.designsystem.Motion
import dev.chrisbanes.haze.HazeState

/**
 * Rail width, mirrored from [GlassNavBar]'s 72.dp bar height so the two share the same cross-axis
 * footprint — the rail is conceptually the bar rotated to the vertical edge.
 */
private val RailWidth = 72.dp

/** Android's minimum recommended touch target, matching [GlassNavBar]'s NavTouchTargetMin. */
private val RailTouchTargetMin = 48.dp

/** Tactile shrink applied to a rail item while pressed, matching [GlassNavBar]'s NavPressedScale. */
private const val RailPressedScale = 0.88f

/**
 * The medium/expanded-window counterpart to [GlassNavBar] (§6): a floating vertical glass rail.
 * Same destinations and glass language as the phone bar, with the AI launcher as the prominent
 * center slot. Falls back to an opaque surface under reduce-transparency like all glass surfaces.
 */
@Composable
fun GlassNavRail(
    hazeState: HazeState,
    currentRoute: String,
    onNavigate: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val onNow = remember(onNavigate) { { onNavigate("now") } }
    val onWorld = remember(onNavigate) { { onNavigate("world") } }
    val onAi = remember(onNavigate) { { onNavigate("ai") } }
    val onPlan = remember(onNavigate) { { onNavigate("plan") } }
    val onSettings = remember(onNavigate) { { onNavigate("settings") } }

    LiquidGlassSurface(
        hazeState = hazeState,
        modifier = modifier
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .width(RailWidth),
        shape = MaterialTheme.shapes.extraLarge,
        tintColor = GlassDefaults.cardTint,
    ) {
        Column(
            modifier = Modifier.padding(vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            RailItem(Icons.Default.Home, "Now", currentRoute == "now", onNow)
            Spacer(Modifier.height(12.dp))
            RailItem(Icons.Default.Public, "World", currentRoute == "world", onWorld)
            Spacer(Modifier.height(12.dp))
            RailItem(Icons.Default.AutoAwesome, "AI Assistant", currentRoute == "ai", onAi)
            Spacer(Modifier.height(12.dp))
            RailItem(Icons.Default.Schedule, "Plan", currentRoute == "plan", onPlan)
            Spacer(Modifier.height(12.dp))
            RailItem(Icons.Default.Settings, "Settings", currentRoute == "settings", onSettings)
        }
    }
}

@Composable
private fun RailItem(icon: ImageVector, label: String, selected: Boolean, onClick: () -> Unit) {
    val haptics = LocalHapticFeedback.current
    val reduceMotion = LocalReduceMotion.current
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()

    val background by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.primaryContainer else Color.Transparent,
        animationSpec = Motion.smooth(),
        label = "railItemBg"
    )
    val iconTint by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.onPrimaryContainer
        else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        animationSpec = Motion.smooth(),
        label = "railItemTint"
    )
    // Tactile shrink on press, mirroring GlassNavBar's NavItem. Skipped entirely under reduce-motion
    // (north-star: "Always respect Reduce Motion / animator scale").
    val scale by animateFloatAsState(
        targetValue = if (pressed && !reduceMotion) RailPressedScale else 1f,
        animationSpec = Motion.snappy(),
        label = "railItemScale"
    )
    IconButton(
        onClick = {
            // Confirm a destination change with the same LongPress tick the bar uses; skipped when
            // re-tapping the current tab so no-op taps stay silent.
            if (!selected) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            onClick()
        },
        interactionSource = interactionSource,
        modifier = Modifier
            .size(RailTouchTargetMin)
            .scale(scale)
            .clip(CircleShape)
            .background(background)
            // Merge into one focusable node so TalkBack announces the tab once. Role.Tab already
            // appends "tab", so the description is just the destination name (no doubling).
            .semantics(mergeDescendants = true) {
                this.selected = selected
                this.role = Role.Tab
                this.contentDescription = label
            }
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = iconTint,
        )
    }
}
