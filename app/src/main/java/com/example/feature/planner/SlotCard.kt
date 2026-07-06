package com.example.feature.planner

import android.widget.Toast
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.Work
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.core.designsystem.LocalReduceMotion
import com.example.core.designsystem.Motion
import com.example.core.designsystem.PlannerCard
import com.example.core.time.FindOverlapUseCase.OverlapSlot
import com.example.core.time.LocalView
import com.example.core.time.TimeFormats
import com.example.feature.calendar.insertCalendarEvent
import com.example.feature.calendar.shareEventIcs
import kotlinx.datetime.toJavaInstant
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun SlotCard(
    modifier: Modifier = Modifier,
    slot: OverlapSlot,
    localZoneId: String,
    localLocationName: String,
    durationMinutes: Int,
    is24Hour: Boolean,
    participantLabels: List<ParticipantSlotLabel>,
    expanded: Boolean,
    meetingTitle: String,
    onToggle: () -> Unit,
    // When false the card renders as a static detail panel (no tap-to-toggle, no chevron) —
    // used under the fair-time dial where selection is driven by the scrubber.
    interactive: Boolean = true,
) {
    val context = LocalContext.current
    val clipboardManager = LocalClipboardManager.current
    val javaInstant = remember(slot) { slot.utcStartInstant.toJavaInstant() }
    val localZdt = remember(javaInstant, localZoneId) {
        ZonedDateTime.ofInstant(javaInstant, ZoneId.of(localZoneId))
    }
    val localTime = remember(localZdt, is24Hour) {
        localZdt.format(TimeFormats.hourMinuteWithContext(is24Hour))
    }
    val localEndTime = remember(javaInstant, durationMinutes, localZoneId, is24Hour) {
        ZonedDateTime.ofInstant(
            javaInstant.plusSeconds(durationMinutes * 60L),
            ZoneId.of(localZoneId)
        ).format(TimeFormats.hourMinute(is24Hour))
    }
    val localDateStr = remember(localZdt) {
        localZdt.format(TimeFormats.mediumDate())
    }
    val reduceMotion = LocalReduceMotion.current
    // Spring rotation matches the app's motion language (north-star: "spring physics ONLY").
    // Collapses to an instant snap when the user has requested reduced motion.
    val chevronRotation by animateFloatAsState(
        targetValue = if (expanded) 180f else 0f,
        animationSpec = if (reduceMotion) snap() else Motion.smooth(),
        label = "chevron"
    )

    PlannerCard(
        modifier = modifier
            .fillMaxWidth()
            .let {
                if (interactive) {
                    it
                        .semantics {
                            // Announce the expand/collapse state on the card itself so the chevron
                            // (cleared below) isn't read as a separate, redundant stop.
                            stateDescription = if (expanded) "Expanded" else "Collapsed"
                        }
                        .clickable(onClick = onToggle, role = Role.Button)
                } else {
                    it
                }
            },
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
                // Merge the time range, date, location and quality rating into one TalkBack stop so
                // the fair-slot summary reads as a single coherent utterance instead of three
                // fragments (with RatingBadge's out-of-context "Meeting quality: X").
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .weight(1f)
                        .semantics(mergeDescendants = true) {
                            contentDescription =
                                "$localTime to $localEndTime, $localDateStr, " +
                                "$localLocationName, quality ${slot.ratingLabel}"
                        }
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "$localTime – $localEndTime · $localDateStr",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Text(
                            text = localLocationName,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                        )
                    }
                    Spacer(Modifier.width(8.dp))
                    RatingBadge(slot.ratingLabel)
                }
                if (interactive) {
                    Spacer(Modifier.width(8.dp))
                    Icon(
                        imageVector = Icons.Default.KeyboardArrowDown,
                        // Decorative: the card's stateDescription already announces Expanded/Collapsed.
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                        modifier = Modifier
                            .size(20.dp)
                            .graphicsLayer { rotationZ = chevronRotation }
                    )
                }
            }

            Spacer(Modifier.height(8.dp))

            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                participantLabels
                    .filter { it.zoneId in slot.localHours }
                    .forEach { label ->
                        val view = slot.localViews[label.zoneId] ?: LocalView.AWAKE
                        ParticipantTag(
                            zoneId = label.zoneId,
                            who = label.displayWho(),
                            instant = javaInstant,
                            view = view,
                            is24Hour = is24Hour,
                            localZoneId = localZoneId,
                        )
                    }
            }

            AnimatedVisibility(visible = expanded) {
                Column {
                    Spacer(Modifier.height(16.dp))
                    androidx.compose.material3.HorizontalDivider(
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.15f),
                        thickness = 1.dp
                    )
                    Spacer(Modifier.height(16.dp))
                    val calendarButtonColors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = {
                                insertCalendarEvent(
                                    context = context,
                                    title = meetingTitle.ifBlank { "Meeting" },
                                    startInstant = javaInstant,
                                    durationMinutes = durationMinutes,
                                    zoneId = localZoneId,
                                )
                            },
                            modifier = Modifier.weight(1f),
                            colors = calendarButtonColors,
                        ) {
                            Icon(Icons.Default.Event, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("Calendar")
                        }
                        FilledTonalButton(
                            onClick = {
                                shareEventIcs(
                                    context = context,
                                    title = meetingTitle.ifBlank { "Meeting" },
                                    startInstant = javaInstant,
                                    durationMinutes = durationMinutes,
                                    zoneId = localZoneId,
                                )
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Icon(Icons.Default.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("Share .ics")
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    FilledTonalButton(
                        onClick = {
                            val localTimeStr = localZdt.format(TimeFormats.hourMinuteWithContext(is24Hour))
                            val localDateStrVal = localZdt.format(TimeFormats.mediumDate())
                            val timeStrings = participantLabels
                                .filter { it.zoneId in slot.localHours }
                                .map { label ->
                                    val zoneId = label.zoneId
                                    val zdt = ZonedDateTime.ofInstant(javaInstant, ZoneId.of(zoneId))
                                    val time = zdt.format(TimeFormats.hourMinute(is24Hour))
                                    val diff = java.time.temporal.ChronoUnit.DAYS.between(localZdt.toLocalDate(), zdt.toLocalDate())
                                    val dateDiff = when {
                                        diff > 0 -> " (+$diff d)"
                                        diff < 0 -> " ($diff d)"
                                        else -> ""
                                    }
                                    "$time$dateDiff (${label.displayWho()})"
                                }
                            val text = "${meetingTitle.ifBlank { "Proposed meeting time" }} on $localDateStrVal: $localTimeStr (You · $localLocationName) / " + timeStrings.joinToString(" / ")
                            clipboardManager.setText(AnnotatedString(text))
                            Toast.makeText(context, "Copied to clipboard", Toast.LENGTH_SHORT).show()
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Default.ContentCopy, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Copy to clipboard")
                    }
                }
            }
        }
    }

@Composable
internal fun RatingBadge(label: String) {
    val color = when (label) {
        "Optimal" -> MaterialTheme.colorScheme.primary
        "Fair" -> MaterialTheme.colorScheme.tertiary
        else -> MaterialTheme.colorScheme.error
    }
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(color.copy(alpha = 0.18f))
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .semantics { contentDescription = "Meeting quality: $label" }
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = color,
            fontWeight = FontWeight.Bold
        )
    }
}

@Composable
internal fun ParticipantTag(
    zoneId: String,
    who: String,
    instant: Instant,
    view: LocalView,
    is24Hour: Boolean,
    localZoneId: String,
) {
    val participantZdt = remember(zoneId, instant) {
        ZonedDateTime.ofInstant(instant, ZoneId.of(zoneId))
    }
    val time = remember(participantZdt, is24Hour) {
        participantZdt.format(TimeFormats.hourMinute(is24Hour))
    }
    val dateDiff = remember(zoneId, instant, localZoneId) {
        val localDate = ZonedDateTime.ofInstant(instant, ZoneId.of(localZoneId)).toLocalDate()
        val participantDate = ZonedDateTime.ofInstant(instant, ZoneId.of(zoneId)).toLocalDate()
        val diff = java.time.temporal.ChronoUnit.DAYS.between(localDate, participantDate)
        when {
            diff > 0 -> " (+$diff d)"
            diff < 0 -> " ($diff d)"
            else -> ""
        }
    }
    val style = localViewStyle(view)
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(style.color.copy(alpha = 0.14f))
            .padding(horizontal = 8.dp, vertical = 4.dp)
            // Read each participant as one node ("Ada, 3:00 PM (+1 d), Asleep") instead of three
            // fragments; the inner icon description is nulled below so it isn't announced twice.
            .semantics(mergeDescendants = true) {
                contentDescription = "$who, $time$dateDiff, ${style.label}"
            }
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = style.icon,
                contentDescription = null,
                tint = style.color,
                modifier = Modifier.size(12.dp)
            )
            Spacer(Modifier.width(5.dp))
            Column {
                val dateDiffColor = if (dateDiff.contains("+")) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.secondary
                Text(
                    text = remember(who, time, dateDiff, dateDiffColor) {
                        androidx.compose.ui.text.buildAnnotatedString {
                            append("$who · $time")
                            if (dateDiff.isNotEmpty()) {
                                pushStyle(
                                    androidx.compose.ui.text.SpanStyle(
                                        color = dateDiffColor,
                                        fontWeight = FontWeight.Bold
                                    )
                                )
                                append(dateDiff)
                                pop()
                            }
                        }
                    },
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    fontWeight = FontWeight.Medium
                )
                Text(
                    text = style.label,
                    style = MaterialTheme.typography.labelSmall,
                    color = style.color
                )
            }
        }
    }
}

@Stable
internal data class LocalViewStyle(val icon: ImageVector, val label: String, val color: Color)

@Composable
internal fun localViewStyle(view: LocalView): LocalViewStyle = when (view) {
    LocalView.WORKING -> LocalViewStyle(Icons.Default.Work, "Working", MaterialTheme.colorScheme.primary)
    LocalView.AWAKE -> LocalViewStyle(Icons.Default.WbSunny, "Awake", MaterialTheme.colorScheme.tertiary)
    LocalView.OUTSIDE_HOURS -> LocalViewStyle(Icons.Default.Coffee, "Off-hours", MaterialTheme.colorScheme.secondary)
    LocalView.ASLEEP -> LocalViewStyle(Icons.Default.Bedtime, "Asleep", MaterialTheme.colorScheme.error)
}

