package com.example.feature.planner

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.core.data.SavedZone
import com.example.core.designsystem.GlassDatePickerSheet
import com.example.core.designsystem.GlassFormBottomSheet
import com.example.core.designsystem.GlassTimePickerSheet
import com.example.ui.components.ZoneSearchPicker
import com.example.core.time.TimeFormats
import dev.chrisbanes.haze.HazeState
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime


@Composable
fun JumpToPlaceDateTimeModal(
    localZoneId: String,
    localLocationName: String,
    savedZones: List<SavedZone>,
    searchZones: suspend (String) -> List<SavedZone>,
    is24Hour: Boolean,
    hazeState: HazeState,
    onDismiss: () -> Unit,
    onJump: (Instant, String) -> Unit
) {
    var selectedZoneId by remember { mutableStateOf<String?>(localZoneId) }
    var selectedZoneLabel by remember { mutableStateOf(localLocationName) }

    val nowZdt = remember(localZoneId) { ZonedDateTime.now(ZoneId.of(localZoneId)) }
    var selectedDate by remember { mutableStateOf(nowZdt.toLocalDate()) }
    var selectedHour by remember { mutableIntStateOf(nowZdt.hour) }
    var selectedMinute by remember { mutableIntStateOf(0) }

    var showDatePicker by remember { mutableStateOf(false) }
    var showTimePicker by remember { mutableStateOf(false) }

    val quickZones = remember(savedZones, localZoneId, localLocationName) {
        buildList {
            add(localZoneId to localLocationName)
            savedZones.forEach { if (it.id != localZoneId) add(it.id to it.displayName) }
        }
    }

    val targetZdt = remember(selectedDate, selectedHour, selectedMinute, selectedZoneId) {
        selectedZoneId?.let { zoneId ->
            selectedDate.atTime(selectedHour, selectedMinute)
                .atZone(ZoneId.of(zoneId))
        }
    }

    val localEquivalent = remember(targetZdt, localZoneId, localLocationName, is24Hour) {
        targetZdt?.let { zdt ->
            val local = zdt.withZoneSameInstant(ZoneId.of(localZoneId))
            "${local.format(TimeFormats.mediumDate())} · ${local.format(TimeFormats.hourMinute(is24Hour))} ($localLocationName)"
        }
    }

    val dateLabel = remember(selectedDate) { selectedDate.format(TimeFormats.mediumDate()) }
    val timeLabel = remember(selectedHour, selectedMinute, is24Hour) {
        LocalTime.of(selectedHour, selectedMinute).format(TimeFormats.hourMinute(is24Hour))
    }

    GlassFormBottomSheet(
        onDismissRequest = onDismiss,
        hazeState = hazeState,
        title = { Text("Jump to Place & Time") },
        confirmButton = {
            TextButton(
                onClick = {
                    targetZdt?.let { zdt ->
                        onJump(zdt.toInstant(), selectedZoneId!!)
                    }
                },
                enabled = selectedZoneId != null
            ) {
                Text("Jump")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
        content = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                ZoneSearchPicker(
                    localZoneId = localZoneId,
                    quickZones = quickZones,
                    selectedZoneId = selectedZoneId ?: localZoneId,
                    selectedZoneLabel = selectedZoneLabel,
                    onZoneSelected = { id, label ->
                        selectedZoneId = id
                        selectedZoneLabel = label
                    },
                    searchZones = searchZones,
                    is24Hour = is24Hour,
                    alwaysShowSearch = true,
                )

                // Display selected place details card
                selectedZoneId?.let { zoneId ->
                    val displayName = remember(zoneId, selectedZoneLabel, localLocationName) {
                        if (zoneId == localZoneId) localLocationName else selectedZoneLabel
                    }

                    val offsetDifference = remember(zoneId, localZoneId) {
                        val targetOffset = ZoneId.of(zoneId).rules.getOffset(Instant.now())
                        val localOffset = ZoneId.of(localZoneId).rules.getOffset(Instant.now())
                        val diffSeconds = targetOffset.totalSeconds - localOffset.totalSeconds
                        val diffHours = diffSeconds / 3600.0
                        if (diffHours == 0.0) {
                            "same time"
                        } else {
                            val sign = if (diffHours > 0) "+" else "-"
                            val absHours = kotlin.math.abs(diffHours)
                            val hourStr = if (absHours % 1 == 0.0) absHours.toInt().toString() else absHours.toString()
                            "$sign${hourStr}h"
                        }
                    }

                    val targetTimeFormatted = remember(selectedDate, selectedHour, selectedMinute, is24Hour) {
                        LocalTime.of(selectedHour, selectedMinute).format(TimeFormats.hourMinute(is24Hour))
                    }

                    val targetDateFormatted = remember(selectedDate) {
                        selectedDate.format(TimeFormats.mediumDate())
                    }

                    Card(
                        shape = RoundedCornerShape(28.dp),
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.08f)
                        ),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = displayName,
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onSurface
                                )
                                Text(
                                    text = zoneId,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                                )
                                if (zoneId != localZoneId) {
                                    Spacer(Modifier.height(4.dp))
                                    Text(
                                        text = "$offsetDifference compared to you",
                                        style = MaterialTheme.typography.labelSmall,
                                        fontWeight = FontWeight.SemiBold,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                }
                            }
                            Column(
                                horizontalAlignment = Alignment.End
                            ) {
                                Text(
                                    text = targetTimeFormatted,
                                    style = MaterialTheme.typography.headlineSmall,
                                    fontWeight = FontWeight.ExtraBold,
                                    color = MaterialTheme.colorScheme.primary
                                )
                                Text(
                                    text = targetDateFormatted,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                                )
                            }
                        }
                    }
                }

                Spacer(Modifier.height(4.dp))

                // Date and Time Selectors.
                Row(
                    modifier = Modifier
                        .fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    SelectorTile(
                        label = "Date",
                        value = dateLabel,
                        icon = Icons.Default.CalendarMonth,
                        onClick = { showDatePicker = true },
                        modifier = Modifier.weight(1f)
                    )

                    SelectorTile(
                        label = "Time",
                        value = timeLabel,
                        icon = Icons.Default.Schedule,
                        onClick = { showTimePicker = true },
                        modifier = Modifier.weight(1f)
                    )
                }

                // Local Equivalent callout box
                localEquivalent?.let {
                    if (selectedZoneId != localZoneId) {
                        Card(
                            shape = RoundedCornerShape(12.dp),
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.4f)
                            ),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Row(
                                modifier = Modifier.padding(12.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Schedule,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.onSecondaryContainer,
                                    modifier = Modifier.size(16.dp)
                                )
                                Spacer(Modifier.width(8.dp))
                                Text(
                                    text = "= $it",
                                    style = MaterialTheme.typography.bodySmall,
                                    fontWeight = FontWeight.Medium,
                                    color = MaterialTheme.colorScheme.onSecondaryContainer
                                )
                            }
                        }
                    }
                }
            }
        }
    )

    if (showDatePicker) {
        val initialMillis = selectedDate.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        GlassDatePickerSheet(
            onDismissRequest = { showDatePicker = false },
            hazeState = hazeState,
            initialSelectedDateMillis = initialMillis,
            onConfirm = { millis ->
                selectedDate = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
                showDatePicker = false
            },
        )
    }

    if (showTimePicker) {
        GlassTimePickerSheet(
            onDismissRequest = { showTimePicker = false },
            hazeState = hazeState,
            initialHour = selectedHour,
            initialMinute = selectedMinute,
            is24Hour = is24Hour,
            onConfirm = { h, m ->
                selectedHour = h
                selectedMinute = m
                showTimePicker = false
            },
        )
    }
}

@Composable
private fun SelectorTile(
    label: String,
    value: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        shape = RoundedCornerShape(0.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
        ),
        border = BorderStroke(
            width = 1.dp,
            color = MaterialTheme.colorScheme.outlineVariant
        ),
        modifier = modifier.clickable(onClick = onClick)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(20.dp)
            )
            Spacer(Modifier.width(8.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = label.uppercase(),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.65f),
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = value,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}
