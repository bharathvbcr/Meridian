package com.example.feature.planner

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.core.designsystem.CardHeader
import com.example.core.designsystem.PlannerCard
import com.example.core.time.TimeFormats
import com.example.feature.calendar.CalendarEvent
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

@Composable
internal fun CalendarEventsCard(
    events: List<CalendarEvent>,
    hasPermission: Boolean,
    is24Hour: Boolean,
    onRequestPermission: () -> Unit,
    modifier: Modifier = Modifier,
) {
    PlannerCard(modifier = modifier) {
        CardHeader(icon = Icons.Default.CalendarMonth, title = "Your Calendar")
        Spacer(Modifier.height(12.dp))

        when {
            !hasPermission -> {
                Text(
                    text = "Allow calendar access to see your upcoming events alongside meeting slots.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                )
                Spacer(Modifier.height(12.dp))
                OutlinedButton(
                    onClick = onRequestPermission,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(
                        Icons.Default.CalendarMonth,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text("Grant calendar access")
                }
            }
            events.isEmpty() -> {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        Icons.Default.CalendarMonth,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.35f),
                    )
                    Text(
                        text = "No events scheduled for the next 7 days.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    )
                }
            }
            else -> {
                val display = remember(events) { events.take(5) }
                display.forEachIndexed { i, event ->
                    CalendarEventRow(event = event, is24Hour = is24Hour)
                    if (i < display.lastIndex) {
                        HorizontalDivider(
                            modifier = Modifier.padding(vertical = 4.dp),
                            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f),
                        )
                    }
                }
                if (events.size > 5) {
                    Spacer(Modifier.height(8.dp))
                    val overflow = events.size - 5
                    Text(
                        text = "+$overflow more events this week",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    )
                }
            }
        }
    }
}

@Composable
private fun CalendarEventRow(event: CalendarEvent, is24Hour: Boolean) {
    val zone = remember(event.timeZone) {
        runCatching { ZoneId.of(event.timeZone) }.getOrElse { ZoneId.systemDefault() }
    }
    val timeLabel = remember(event.startMillis, event.endMillis, is24Hour, event.isAllDay, event.timeZone) {
        if (event.isAllDay) "All day" else {
            val fmt = TimeFormats.hourMinute(is24Hour)
            val start = ZonedDateTime.ofInstant(Instant.ofEpochMilli(event.startMillis), zone).format(fmt)
            val end = ZonedDateTime.ofInstant(Instant.ofEpochMilli(event.endMillis), zone).format(fmt)
            "$start – $end"
        }
    }
    val dateLabel = remember(event.startMillis, zone) {
        ZonedDateTime.ofInstant(Instant.ofEpochMilli(event.startMillis), zone)
            .format(TimeFormats.mediumDate())
    }

    Row(
        // Read the whole event as one TalkBack node ("Standup, Jul 4, 9:00 – 9:30") instead of three
        // separate stops for title, time and date. Mirrors the merged-semantics rows in SlotCard.
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = "${event.title}, $dateLabel, $timeLabel"
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = event.title,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = timeLabel,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
            )
        }
        Spacer(Modifier.width(8.dp))
        // Demoted from the primary accent so the event title reads first; accent stays reserved for
        // the meeting-slot RatingBadge, keeping the accent's meaning consistent across the tab.
        Text(
            text = dateLabel,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        )
    }
}
