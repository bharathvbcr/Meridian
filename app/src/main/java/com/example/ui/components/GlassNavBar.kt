package com.example.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.EventNote
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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
 * Android's minimum recommended touch target. Every tab enforces this via [defaultMinSize] so the
 * icon-only (collapsed / unselected) items stay comfortably tappable even though their visual glass
 * pill is smaller.
 */
private val NavTouchTargetMin = 48.dp

/** Tactile shrink applied to a tab while pressed, matching the liquid-glass feel elsewhere. */
private const val NavPressedScale = 0.88f

@Composable
fun GlassNavBar(
    hazeState: HazeState,
    currentRoute: String,
    onNavigate: (String) -> Unit,
    modifier: Modifier = Modifier,
    collapsed: Boolean = false
) {
    val onNow = remember(onNavigate) { { onNavigate("now") } }
    val onWorld = remember(onNavigate) { { onNavigate("world") } }
    val onAi = remember(onNavigate) { { onNavigate("ai") } }
    val onPlan = remember(onNavigate) { { onNavigate("plan") } }
    val onSettings = remember(onNavigate) { { onNavigate("settings") } }

    val horizontalPadding by animateDpAsState(
        targetValue = if (collapsed) 8.dp else 12.dp,
        animationSpec = Motion.bouncy(),
        label = "navPadding"
    )

    LiquidGlassSurface(
        hazeState = hazeState,
        modifier = modifier
            .navigationBarsPadding()
            .padding(bottom = 16.dp)
            .height(72.dp)
            .wrapContentWidth(),
        shape = CircleShape,
        tintColor = GlassDefaults.cardTint,
    ) {
        Row(
            modifier = Modifier
                .align(Alignment.Center)
                .padding(horizontal = horizontalPadding),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            NavItem(
                icon = Icons.Default.Home,
                label = "Now",
                selected = currentRoute == "now",
                showLabel = !collapsed,
                onClick = onNow
            )
            NavItem(
                icon = Icons.Default.Public,
                label = "World",
                selected = currentRoute == "world",
                showLabel = !collapsed,
                onClick = onWorld
            )
            // AI launcher button (center slot)
            AiNavButton(
                selected = currentRoute == "ai",
                onClick = onAi
            )
            NavItem(
                icon = Icons.AutoMirrored.Filled.EventNote,
                label = "Plan",
                selected = currentRoute == "plan",
                showLabel = !collapsed,
                onClick = onPlan
            )
            NavItem(
                icon = Icons.Default.Settings,
                label = "Settings",
                selected = currentRoute == "settings",
                showLabel = !collapsed,
                onClick = onSettings
            )
        }
    }
}

@Composable
private fun NavItem(
    icon: ImageVector,
    label: String,
    selected: Boolean,
    showLabel: Boolean,
    onClick: () -> Unit
) {
    val haptics = LocalHapticFeedback.current
    val reduceMotion = LocalReduceMotion.current
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()

    // Smoothly crossfade between selected/unselected instead of snapping.
    val contentColor by animateColorAsState(
        targetValue = if (selected) {
            MaterialTheme.colorScheme.onPrimaryContainer
        } else {
            MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f)
        },
        animationSpec = Motion.smooth(),
        label = "navItemColor"
    )
    val background by animateColorAsState(
        targetValue = if (selected) {
            MaterialTheme.colorScheme.primaryContainer
        } else {
            Color.Transparent
        },
        animationSpec = Motion.smooth(),
        label = "navItemBackground"
    )
    // Tactile shrink on press, matching the liquid-glass feel. Skipped entirely when the user
    // has requested reduced motion (north-star: "Always respect Reduce Motion / animator scale").
    val scale by animateFloatAsState(
        targetValue = if (pressed && !reduceMotion) NavPressedScale else 1f,
        animationSpec = Motion.snappy(),
        label = "navItemScale"
    )

    Row(
        modifier = Modifier
            .scale(scale)
            .clip(CircleShape)
            .background(background)
            // Guarantee a 48dp touch target even when the visual pill (icon-only tabs) is smaller.
            .defaultMinSize(minWidth = NavTouchTargetMin, minHeight = NavTouchTargetMin)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = {
                    if (!selected) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onClick()
                }
            )
            // Merge into one focusable node so TalkBack announces the whole tab once. With Role.Tab
            // it already appends "tab", so the description is just the destination name (no doubling).
            .semantics(mergeDescendants = true) {
                this.selected = selected
                this.role = Role.Tab
                this.contentDescription = label
            }
            .padding(horizontal = if (selected && showLabel) 14.dp else 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = contentColor
        )
        // Show the label only for the active tab so the current page is obvious. The reveal
        // collapses to an instant swap under reduce-motion instead of the expand/fade.
        AnimatedVisibility(
            visible = selected && showLabel,
            enter = if (reduceMotion) EnterTransition.None
            else fadeIn() + expandHorizontally(expandFrom = Alignment.Start),
            exit = if (reduceMotion) ExitTransition.None
            else fadeOut() + shrinkHorizontally(shrinkTowards = Alignment.Start)
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge,
                color = contentColor
            )
        }
    }
}

@Composable
private fun AiNavButton(
    selected: Boolean,
    onClick: () -> Unit
) {
    val haptics = LocalHapticFeedback.current
    val reduceMotion = LocalReduceMotion.current
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()

    val scale by animateFloatAsState(
        targetValue = if (pressed && !reduceMotion) NavPressedScale else 1f,
        animationSpec = Motion.snappy(),
        label = "aiButtonScale"
    )
    val contentColor by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.onPrimaryContainer
        else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
        animationSpec = Motion.smooth(),
        label = "aiButtonColor"
    )
    val background by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.primaryContainer
        else Color.Transparent,
        animationSpec = Motion.smooth(),
        label = "aiButtonBackground"
    )

    Row(
        modifier = Modifier
            .scale(scale)
            .clip(CircleShape)
            .background(background)
            // Guarantee a 48dp touch target for the center AI slot as well.
            .defaultMinSize(minWidth = NavTouchTargetMin, minHeight = NavTouchTargetMin)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = {
                    if (!selected) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onClick()
                }
            )
            // Merge into one focusable node; Role.Tab appends "tab" so the description is the
            // fuller destination name ("AI Assistant") that the icon-only visual can't convey.
            .semantics(mergeDescendants = true) {
                this.selected = selected
                this.role = Role.Tab
                this.contentDescription = "AI Assistant"
            }
            .padding(horizontal = if (selected) 14.dp else 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Icon(
            imageVector = Icons.Default.AutoAwesome,
            contentDescription = null,
            tint = contentColor
        )
        AnimatedVisibility(
            visible = selected,
            enter = if (reduceMotion) EnterTransition.None
            else fadeIn() + expandHorizontally(expandFrom = Alignment.Start),
            exit = if (reduceMotion) ExitTransition.None
            else fadeOut() + shrinkHorizontally(shrinkTowards = Alignment.Start)
        ) {
            Text(
                text = "AI",
                style = MaterialTheme.typography.labelLarge,
                color = contentColor
            )
        }
    }
}
