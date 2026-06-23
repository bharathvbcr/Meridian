package com.example.core.designsystem

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SelectableChipColors
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState

/**
 * Shared FilterChip color recipe used by every selectable chip in the app
 * (map-style, hour-cycle, participant and zone filter chips).
 */
@Composable
fun meridianFilterChipColors(): SelectableChipColors {
    val primary = MaterialTheme.colorScheme.primaryContainer
    val onPrimary = MaterialTheme.colorScheme.onPrimaryContainer
    return FilterChipDefaults.filterChipColors(
        selectedContainerColor = primary,
        selectedLabelColor = onPrimary,
        selectedLeadingIconColor = onPrimary,
    )
}

/**
 * Unified selectable filter chip. Merges the byte-identical HourCycleChip / MapStyleChip
 * composables: a [FilterChip] with a LongPress haptic on click, a text label and the shared
 * [meridianFilterChipColors] recipe.
 */
@Composable
fun MeridianFilterChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val haptics = LocalHapticFeedback.current
    FilterChip(
        selected = selected,
        onClick = {
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            onClick()
        },
        label = { Text(label) },
        colors = meridianFilterChipColors(),
        modifier = modifier,
    )
}

/**
 * One canonical "section header + trailing divider" row. Replaces the four divergent copies
 * (AiScreen / NowScreen / SettingsScreen / PlannerComponents).
 *
 * Defaults match the most common heading role (titleMedium + Bold, onBackground text, a faint
 * onBackground divider). Call sites that previously used a different token / divider hue can pass
 * [style], [titleColor] and [dividerColor] to preserve their exact appearance; [icon] adds the
 * optional leading icon, [subtitle] adds the optional caption below the divider row.
 */
@Composable
fun SectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    iconContentDescription: String? = null,
    subtitle: String? = null,
    style: TextStyle = MaterialTheme.typography.titleMedium,
    fontWeight: FontWeight? = FontWeight.Bold,
    titleColor: Color = MaterialTheme.colorScheme.onBackground,
    iconTint: Color = MaterialTheme.colorScheme.primary,
    dividerColor: Color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.12f),
) {
    Column(modifier = modifier) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (icon != null) {
                Icon(
                    imageVector = icon,
                    contentDescription = iconContentDescription,
                    tint = iconTint,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(8.dp))
            }
            Text(
                text = title,
                style = style,
                fontWeight = fontWeight,
                color = titleColor,
                modifier = Modifier.padding(end = 12.dp),
            )
            HorizontalDivider(
                color = dividerColor,
                modifier = Modifier.weight(1f),
            )
        }
        if (subtitle != null) {
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * Standard Settings card shell: a [GlassCard] with the shared [GlassDefaults.cardShape], the
 * conventional fillMaxWidth + horizontal 16 / vertical 4 outer padding, and an inner
 * Column(padding 16) into which [content] is placed.
 */
@Composable
fun SettingsCard(
    hazeState: HazeState,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    GlassCard(
        hazeState = hazeState,
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = GlassDefaults.cardShape,
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            content()
        }
    }
}

/**
 * Transparent [Card] colors so the glass backdrop shows through. Used by [PlannerCard] and any
 * plain Card that sits on the glass layer.
 */
@Composable
fun transparentCardColors() = CardDefaults.cardColors(containerColor = Color.Transparent)

/**
 * Standard planner card shell: a transparent-container [Card] with [GlassDefaults.cardShape],
 * the shared [transparentCardColors] recipe and an inner Column(padding 16).
 */
@Composable
fun PlannerCard(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Card(
        shape = GlassDefaults.cardShape,
        colors = transparentCardColors(),
        modifier = modifier,
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            content()
        }
    }
}

/**
 * Shared "icon + title (+ optional subtitle)" card header row. Promotes planner's CardTitle into
 * the design system so Settings cards and NowScreen reuse it instead of re-inlining the row.
 */
@Composable
fun CardHeader(
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
    tint: Color = MaterialTheme.colorScheme.primary,
    modifier: Modifier = Modifier,
    iconContentDescription: String? = null,
) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = modifier) {
        Icon(
            imageVector = icon,
            contentDescription = iconContentDescription,
            tint = tint,
            modifier = Modifier.size(20.dp),
        )
        Spacer(Modifier.width(8.dp))
        if (subtitle == null) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
        } else {
            Column {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                )
            }
        }
    }
}

/**
 * Shared hour stepper row (replaces the planner + settings copies): a label, a "−" IconButton, the
 * "HH:00" value, and a "+" IconButton stepping (value+23)%24 / (value+1)%24.
 *
 * [haptics] (default null) optionally fires a LongPress on each step (the Settings copy did this,
 * the planner copy did not). [tint] colors the stepper icons.
 */
@Composable
fun HourStepperRow(
    label: String,
    value: Int,
    onChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
    haptics: HapticFeedback? = null,
    tint: Color = LocalContentColor.current,
    valueFontWeight: FontWeight = FontWeight.Bold,
    iconSize: androidx.compose.ui.unit.Dp = 18.dp,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier.padding(vertical = 2.dp),
    ) {
        Text(
            text = label,
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodyMedium,
        )
        IconButton(
            onClick = {
                haptics?.performHapticFeedback(HapticFeedbackType.LongPress)
                onChange((value - 1).coerceAtLeast(0))
            },
            enabled = value > 0,
        ) {
            Icon(
                Icons.Default.Remove,
                contentDescription = "Decrease hour",
                tint = tint,
                modifier = Modifier.size(iconSize),
            )
        }
        Text(
            text = "%02d:00".format(value.coerceIn(0, 23)),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = valueFontWeight,
        )
        IconButton(
            onClick = {
                haptics?.performHapticFeedback(HapticFeedbackType.LongPress)
                onChange((value + 1).coerceAtMost(23))
            },
            enabled = value < 23,
        ) {
            Icon(
                Icons.Default.Add,
                contentDescription = "Increase hour",
                tint = tint,
                modifier = Modifier.size(iconSize),
            )
        }
    }
}
