package com.example.feature.planner

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Today
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.example.core.designsystem.LocalReduceMotion
import com.example.core.designsystem.Motion
import com.example.core.designsystem.ScrollableChipRow
import com.example.core.designsystem.PlannerCard
import com.example.core.designsystem.meridianFilterChipColors
import com.example.core.time.TimeFormats
import com.example.core.designsystem.GlassDatePickerSheet
import dev.chrisbanes.haze.HazeState
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime

internal val DURATION_OPTIONS = listOf(30, 45, 60, 90, 120)

private const val DURATION_STEP = 15
private const val DURATION_MIN = 15
private const val DURATION_MAX = 480

private val DAY_MS = 24L * 60L * 60L * 1000L

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun WindowCard(
    modifier: Modifier = Modifier,
    hazeState: HazeState,
    selectedDateMillis: Long,
    durationMinutes: Int,
    excludeWeekends: Boolean,
    onDateChange: (Long) -> Unit,
    onDurationChange: (Int) -> Unit,
    onExcludeWeekendsChange: (Boolean) -> Unit,
    onJumpClick: () -> Unit,
) {
    var showDatePicker by remember { mutableStateOf(false) }
    // Custom mode is on whenever the active duration isn't one of the presets. Kept as explicit
    // state so tapping "Custom" while sitting on a preset value opens the stepper too.
    var customMode by remember { mutableStateOf(durationMinutes !in DURATION_OPTIONS) }
    val haptics = LocalHapticFeedback.current
    val reduceMotion = LocalReduceMotion.current

    // Exit custom mode when a parent-driven change lands on a preset value.
    LaunchedEffect(durationMinutes) {
        if (customMode && durationMinutes in DURATION_OPTIONS) customMode = false
    }

    val selectedChipIndex = remember(durationMinutes, customMode) {
        if (customMode) DURATION_OPTIONS.size
        else DURATION_OPTIONS.indexOf(durationMinutes).coerceAtLeast(0)
    }
    val dateLabel = remember(selectedDateMillis) { formatPickedDate(selectedDateMillis) }
    val todayMillis = ZonedDateTime.now(ZoneId.systemDefault()).toLocalDate()
        .atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
    val isToday = selectedDateMillis == todayMillis

    PlannerCard(modifier = modifier) {
        CardTitle(Icons.Default.CalendarMonth, "Window")
        Spacer(Modifier.height(12.dp))

            // Date picker with prev/next day navigation arrows
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                IconButton(
                    onClick = { onDateChange(selectedDateMillis - DAY_MS) },
                    modifier = Modifier.minimumInteractiveComponentSize()
                ) {
                    Icon(
                        Icons.Default.KeyboardArrowLeft,
                        contentDescription = "Previous day",
                        tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                    )
                }
                OutlinedButton(
                    onClick = { showDatePicker = true },
                    modifier = Modifier.weight(1f)
                ) {
                    Icon(Icons.Default.Event, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(dateLabel)
                }
                IconButton(
                    onClick = { onDateChange(selectedDateMillis + DAY_MS) },
                    modifier = Modifier.minimumInteractiveComponentSize()
                ) {
                    Icon(
                        Icons.Default.KeyboardArrowRight,
                        contentDescription = "Next day",
                        tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                    )
                }
            }

            // Animated "Back to today" pill — only visible when browsing another day
            AnimatedVisibility(
                visible = !isToday,
                enter = springExpand(reduceMotion),
                exit = springShrink(reduceMotion)
            ) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                    TextButton(onClick = { onDateChange(todayMillis) }) {
                        Icon(
                            Icons.Default.Today,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(Modifier.width(4.dp))
                        Text("Back to today", style = MaterialTheme.typography.labelMedium)
                    }
                }
            }

            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                onClick = onJumpClick,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.Schedule, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Jump to place & time…")
            }

            Spacer(Modifier.height(16.dp))
            Text(
                "Duration",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
            )
            Spacer(Modifier.height(8.dp))
            val chipColors = meridianFilterChipColors()
            ScrollableChipRow(selectedIndex = selectedChipIndex) {
                itemsIndexed(DURATION_OPTIONS) { _, minutes ->
                    val label = when {
                        minutes < 60 -> "${minutes}m"
                        minutes % 60 == 0 -> "${minutes / 60}h"
                        else -> "${minutes}m"
                    }
                    FilterChip(
                        selected = !customMode && durationMinutes == minutes,
                        onClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            customMode = false
                            onDurationChange(minutes)
                        },
                        label = { Text(label) },
                        colors = chipColors
                    )
                }
                item {
                    FilterChip(
                        selected = customMode,
                        onClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            customMode = true
                        },
                        label = {
                            Text(if (customMode) formatDuration(durationMinutes) else "Custom")
                        },
                        colors = chipColors
                    )
                }
            }

            // Inline stepper: any 15-min increment between 15m and 8h.
            AnimatedVisibility(
                visible = customMode,
                enter = springExpand(reduceMotion),
                exit = springShrink(reduceMotion)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center
                ) {
                    IconButton(
                        onClick = { onDurationChange((durationMinutes - DURATION_STEP).coerceAtLeast(DURATION_MIN)) },
                        enabled = durationMinutes > DURATION_MIN,
                        modifier = Modifier.minimumInteractiveComponentSize()
                    ) {
                        Icon(Icons.Default.Remove, contentDescription = "Decrease duration")
                    }
                    Text(
                        text = formatDuration(durationMinutes),
                        style = MaterialTheme.typography.titleMedium,
                        // widthIn (not a hard width) keeps the value centered but lets long or
                        // Dynamic-Type-scaled labels like "1 h 15 m" grow instead of clipping.
                        modifier = Modifier.widthIn(min = 96.dp),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center
                    )
                    IconButton(
                        onClick = { onDurationChange((durationMinutes + DURATION_STEP).coerceAtMost(DURATION_MAX)) },
                        enabled = durationMinutes < DURATION_MAX,
                        modifier = Modifier.minimumInteractiveComponentSize()
                    ) {
                        Icon(Icons.Default.Add, contentDescription = "Increase duration")
                    }
                }
            }

            Spacer(Modifier.height(16.dp))
            // Toggle the whole row so TalkBack reads label + state as one control ("Exclude
            // weekends, off") and the entire row is a 48dp-tall switch target, not just the thumb.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .toggleable(
                        value = excludeWeekends,
                        role = Role.Switch,
                        onValueChange = onExcludeWeekendsChange
                    )
                    .semantics(mergeDescendants = true) {
                        stateDescription = if (excludeWeekends) "On" else "Off"
                    },
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "Exclude weekends",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                    modifier = Modifier.weight(1f)
                )
                Switch(
                    checked = excludeWeekends,
                    // The row owns the toggle semantics/click; null keeps the thumb visually in
                    // sync without registering a second, redundant a11y toggle node.
                    onCheckedChange = null
                )
            }
        }

    if (showDatePicker) {
        GlassDatePickerSheet(
            onDismissRequest = { showDatePicker = false },
            hazeState = hazeState,
            initialSelectedDateMillis = selectedDateMillis,
            onConfirm = { millis ->
                onDateChange(millis)
                showDatePicker = false
            },
        )
    }
}

/**
 * Springy expand/shrink recipe for this file's [AnimatedVisibility] reveals (the "Back to today"
 * pill and the custom-duration stepper), gated on [LocalReduceMotion]. Mirrors ZoneSearchPicker's
 * planner motion so these reveals read as the same liquid-glass language as the rest of the app;
 * under reduce-motion they collapse to a plain fade so the OS "remove animations" preference wins.
 */
private fun springExpand(reduceMotion: Boolean): EnterTransition =
    if (reduceMotion) {
        fadeIn()
    } else {
        fadeIn(Motion.smooth()) + expandVertically(animationSpec = Motion.smooth())
    }

private fun springShrink(reduceMotion: Boolean): ExitTransition =
    if (reduceMotion) {
        fadeOut()
    } else {
        fadeOut(Motion.smooth()) + shrinkVertically(animationSpec = Motion.smooth())
    }

/** Human-readable duration, e.g. "45 m", "1 h", "1 h 15 m". */
internal fun formatDuration(minutes: Int): String {
    val hours = minutes / 60
    val mins = minutes % 60
    return when {
        hours == 0 -> "$mins m"
        mins == 0 -> "$hours h"
        else -> "$hours h $mins m"
    }
}

internal fun formatPickedDate(utcMidnightMillis: Long): String {
    val date = Instant.ofEpochMilli(utcMidnightMillis).atZone(ZoneOffset.UTC).toLocalDate()
    return date.format(TimeFormats.mediumDate())
}
