package com.example.ui.components

import androidx.compose.animation.AnimatedVisibility
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
import com.example.core.designsystem.Motion
import com.example.core.designsystem.liquidGlass
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.materials.ExperimentalHazeMaterialsApi

@OptIn(ExperimentalHazeMaterialsApi::class)
@Composable
fun GlassNavBar(
    hazeState: HazeState,
    currentRoute: String,
    onNavigate: (String) -> Unit,
    modifier: Modifier = Modifier,
    collapsed: Boolean = false
) {
    val horizontalPadding by animateDpAsState(
        targetValue = if (collapsed) 8.dp else 12.dp,
        animationSpec = Motion.bouncy(),
        label = "navPadding"
    )

    Box(
        modifier = modifier
            .navigationBarsPadding()
            .padding(bottom = 16.dp)
            .height(72.dp)
            .wrapContentWidth()
            .liquidGlass(
                hazeState = hazeState,
                shape = CircleShape,
                tintColor = Color.Black.copy(alpha = 0.1f),
            ),
        contentAlignment = Alignment.Center
    ) {
        Row(
            modifier = Modifier.padding(horizontal = horizontalPadding),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            NavItem(
                icon = Icons.Default.Home,
                label = "Now",
                selected = currentRoute == "now",
                showLabel = !collapsed,
                onClick = { onNavigate("now") }
            )
            NavItem(
                icon = Icons.Default.Public,
                label = "World",
                selected = currentRoute == "world",
                showLabel = !collapsed,
                onClick = { onNavigate("world") }
            )
            // AI launcher button (center slot)
            AiNavButton(
                selected = currentRoute == "ai",
                onClick = { onNavigate("ai") }
            )
            NavItem(
                icon = Icons.AutoMirrored.Filled.EventNote,
                label = "Plan",
                selected = currentRoute == "plan",
                showLabel = !collapsed,
                onClick = { onNavigate("plan") }
            )
            NavItem(
                icon = Icons.Default.Settings,
                label = "Settings",
                selected = currentRoute == "settings",
                showLabel = !collapsed,
                onClick = { onNavigate("settings") }
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
    // Tactile shrink on press, matching the liquid-glass feel.
    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.88f else 1f,
        animationSpec = Motion.snappy(),
        label = "navItemScale"
    )

    Row(
        modifier = Modifier
            .scale(scale)
            .clip(CircleShape)
            .background(background)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = {
                    if (!selected) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onClick()
                }
            )
            .semantics {
                this.selected = selected
                this.role = Role.Tab
                this.contentDescription = "$label tab"
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
        // Show the label only for the active tab so the current page is obvious.
        AnimatedVisibility(
            visible = selected && showLabel,
            enter = fadeIn() + expandHorizontally(expandFrom = Alignment.Start),
            exit = fadeOut() + shrinkHorizontally(shrinkTowards = Alignment.Start)
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
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()

    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.88f else 1f,
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
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = {
                    if (!selected) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onClick()
                }
            )
            .semantics {
                this.selected = selected
                this.role = Role.Tab
                this.contentDescription = "AI Assistant tab"
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
            enter = fadeIn() + expandHorizontally(expandFrom = Alignment.Start),
            exit = fadeOut() + shrinkHorizontally(shrinkTowards = Alignment.Start)
        ) {
            Text(
                text = "AI",
                style = MaterialTheme.typography.labelLarge,
                color = contentColor
            )
        }
    }
}
