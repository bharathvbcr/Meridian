package com.example.feature.planner

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import android.widget.Toast
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.EventBusy
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.core.data.Person
import com.example.core.data.PlannedTask
import com.example.core.data.SavedZone
import com.example.core.data.localLocationLabel
import com.example.core.time.MeetingParticipant
import com.example.core.time.WorkHourWindows
import com.example.core.time.TimeFormats
import com.example.feature.calendar.DEFAULT_EVENT_DURATION_MINUTES
import com.example.feature.calendar.EventActionResult
import com.example.feature.calendar.insertCalendarEvent
import com.example.feature.calendar.shareEventIcs
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

@Composable
internal fun PlannerHeader() {
    Column {
        Text(
            text = "Plan a meeting",
            style = MaterialTheme.typography.displaySmall,
            fontWeight = FontWeight.Black,
            color = MaterialTheme.colorScheme.onBackground
        )
        Text(
            text = "Pick who's in, when to look, and how long. Meridian finds a fair time.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
        )
    }
}

@Composable
internal fun SectionLabel(label: String, subtitle: String) {
    Column(modifier = Modifier.padding(top = 16.dp, bottom = 4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(end = 8.dp)
            )
            androidx.compose.material3.HorizontalDivider(
                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
                modifier = Modifier.weight(1f)
            )
        }
        Text(
            text = subtitle,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
        )
    }
}

@Composable
internal fun plannerCardColors() = CardDefaults.cardColors(
    containerColor = androidx.compose.ui.graphics.Color.Transparent
)

@Composable
internal fun CardTitle(icon: ImageVector, title: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(20.dp)
        )
        Spacer(Modifier.width(8.dp))
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
    }
}

@Composable
internal fun SlotsEmptyState(
    modifier: Modifier = Modifier,
    hint: String = "No overlap found for this day. Try a different date with the arrows in Window, shorten the meeting duration, or deselect participants who are hard to reach.",
) {
    Card(shape = RoundedCornerShape(28.dp), colors = plannerCardColors(), modifier = modifier) {
        Column(
            modifier = Modifier.padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(
                imageVector = Icons.Default.EventBusy,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f),
                modifier = Modifier.size(40.dp),
            )
            Spacer(Modifier.height(12.dp))
            Text(
                text = "No workable slots on this day",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = hint,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
internal fun PlannedTaskRow(modifier: Modifier = Modifier,
    
    task: PlannedTask,
    is24Hour: Boolean,
    onDelete: () -> Unit,
) {
    val context = LocalContext.current
    val formatted = remember(task, is24Hour) {
        val zdt = ZonedDateTime.ofInstant(Instant.ofEpochMilli(task.timestamp), ZoneId.of(task.zoneId))
        val timeStr = zdt.format(TimeFormats.hourMinuteWithContext(is24Hour))
        val dateStr = zdt.format(TimeFormats.mediumDate())
        "$timeStr · $dateStr"
    }
    val startInstant = remember(task) { Instant.ofEpochMilli(task.timestamp) }
    // Run an export action and surface only the failure (§12.6); success opens system UI itself.
    fun export(action: () -> EventActionResult) {
        val result = action()
        if (result is EventActionResult.Failure) {
            Toast.makeText(context, result.reason, Toast.LENGTH_SHORT).show()
        }
    }
    Card(shape = RoundedCornerShape(28.dp), colors = plannerCardColors(), modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(start = 16.dp, top = 8.dp, bottom = 8.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    task.title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    "$formatted · ${shortZoneName(task.zoneId)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            // Export the scheduled meeting as a real calendar event: add it to the device calendar…
            IconButton(onClick = {
                export {
                    insertCalendarEvent(context, task.title, startInstant, DEFAULT_EVENT_DURATION_MINUTES, task.zoneId)
                }
            }) {
                Icon(Icons.Default.Event, contentDescription = "Add to calendar", tint = MaterialTheme.colorScheme.primary)
            }
            // …or share it as a standard .ics invite.
            IconButton(onClick = {
                export {
                    shareEventIcs(context, task.title, startInstant, DEFAULT_EVENT_DURATION_MINUTES, task.zoneId)
                }
            }) {
                Icon(Icons.Default.Share, contentDescription = "Share invite (.ics)", tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(onClick = onDelete) {
                Icon(Icons.Default.Delete, contentDescription = "Delete", tint = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
internal fun DetailsCard(modifier: Modifier = Modifier,
    
    title: String,
    onTitleChange: (String) -> Unit
) {
    Card(shape = RoundedCornerShape(28.dp), colors = plannerCardColors(), modifier = modifier) {
        Column(modifier = Modifier.padding(16.dp)) {
            CardTitle(Icons.Default.Edit, "Details")
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = title,
                onValueChange = onTitleChange,
                label = { Text("Meeting Title") },
                placeholder = { Text("e.g. Design Sync") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

internal fun shortZoneName(zoneId: String): String = zoneId.substringAfterLast('/').replace('_', ' ')

/** @see com.example.core.data.localLocationLabel */
internal fun localLocationLabel(savedZones: List<SavedZone>, localZoneId: String): String =
    savedZones.localLocationLabel(localZoneId)

/** Favorite pinned cities (not home) and favorite contacts offered on the Plan screen. */
internal data class PlannerParticipantPool(
    val zones: List<SavedZone>,
    val people: List<Person>,
)

internal fun plannerParticipantPool(
    savedZones: List<SavedZone>,
    people: List<Person>,
    localZoneId: String,
): PlannerParticipantPool = PlannerParticipantPool(
    zones = savedZones.filter { it.isFavorite && !it.isHome && it.id != localZoneId },
    people = people.filter { it.isFavorite },
)

/** Contacts shown on a pinned city's row — exact city match or same-tz orphan city. */
internal fun contactsForZone(
    zone: SavedZone,
    people: List<Person>,
    savedZones: List<SavedZone>,
): List<Person> = people.filter { it.appearsOnZoneRow(zone, savedZones) }

/** Hide a redundant city pill when it only duplicates the local "You" chip. */
internal fun visiblePlannerGroups(
    groups: List<ParticipantLocationGroup>,
    localZoneId: String,
): List<ParticipantLocationGroup> = groups.filter { group ->
    group.zoneId != localZoneId || group.people.isNotEmpty()
}

internal fun isGroupFullySelected(
    group: ParticipantLocationGroup,
    selectedZones: Map<String, Boolean>,
    selectedPeople: Map<Int, Boolean>,
): Boolean = when {
    group.people.isEmpty() -> group.savedZone?.let { selectedZones[it.id] == true } == true
    group.savedZone != null -> {
        selectedZones[group.savedZone.id] == true &&
            group.people.all { selectedPeople[it.id] == true }
    }
    else -> group.people.all { selectedPeople[it.id] == true }
}

internal fun personChipLabel(person: Person): String =
    if (person.name.isBlank()) person.displayLocation()
    else person.name

internal fun groupChipLabel(group: ParticipantLocationGroup): String {
    val names = group.people.map { personChipLabel(it) }
    return when {
        names.isEmpty() -> group.displayName
        names.size == 1 -> "${names[0]} · ${group.displayName}"
        else -> "${names.joinToString(", ")} · ${group.displayName}"
    }
}

internal fun isGroupSelected(
    group: ParticipantLocationGroup,
    selectedZones: Map<String, Boolean>,
    selectedPeople: Map<Int, Boolean>,
): Boolean {
    val zoneOn = group.savedZone?.let { selectedZones[it.id] == true } == true
    if (group.people.isEmpty()) return zoneOn
    val peopleOn = group.people.any { selectedPeople[it.id] == true }
    return zoneOn || peopleOn
}

internal data class ParticipantSlotLabel(
    val zoneId: String,
    val locationLabel: String,
    val names: List<String> = emptyList(),
) {
    fun displayWho(): String =
        if (names.isEmpty()) locationLabel else "${names.joinToString(", ")} · $locationLabel"
}

internal data class ParticipantLocationGroup(
    val zoneId: String,
    val displayName: String,
    val savedZone: SavedZone?,
    val people: List<Person>,
)

internal fun locationKey(zoneId: String, displayName: String): String =
    "$zoneId\u0000${displayName.lowercase()}"

internal fun buildParticipantLocationGroups(
    savedZones: List<SavedZone>,
    people: List<Person>,
): List<ParticipantLocationGroup> {
    val assignedIds = mutableSetOf<Int>()
    val raw = savedZones.map { zone ->
        val matched = people.filter { person ->
            person.zoneId == zone.id &&
                person.displayLocation().equals(zone.displayName, ignoreCase = true)
        }
        assignedIds += matched.map { it.id }
        ParticipantLocationGroup(zone.id, zone.displayName, zone, matched)
    } + people
        .filter { it.id !in assignedIds }
        .groupBy { locationKey(it.zoneId, it.displayLocation()) }
        .map { (_, groupPeople) ->
            val first = groupPeople.first()
            ParticipantLocationGroup(first.zoneId, first.displayLocation(), null, groupPeople)
        }
    return consolidateParticipantGroupsByTimeZone(raw)
}

/** One row per IANA zone so Denver + El Paso do not each get their own pill. */
private fun consolidateParticipantGroupsByTimeZone(
    groups: List<ParticipantLocationGroup>,
): List<ParticipantLocationGroup> {
    val byZone = linkedMapOf<String, MutableList<ParticipantLocationGroup>>()
    groups.forEach { group ->
        byZone.getOrPut(group.zoneId) { mutableListOf() }.add(group)
    }
    return byZone.values.map { zoneGroups ->
        if (zoneGroups.size == 1) return@map zoneGroups.first()
        val cities = mergedCityNames(zoneGroups)
        val people = zoneGroups.flatMap { it.people }.distinctBy { it.id }
        val savedZone = zoneGroups.firstNotNullOfOrNull { it.savedZone }
        ParticipantLocationGroup(
            zoneId = zoneGroups.first().zoneId,
            displayName = cities.joinToString(", "),
            savedZone = savedZone,
            people = people,
        )
    }
}

private fun mergedCityNames(groups: List<ParticipantLocationGroup>): List<String> =
    groups.flatMap { group ->
        group.displayName.split(',').map { it.trim() }.filter { it.isNotEmpty() }
    }.distinctBy { it.lowercase() }
        .sortedBy { it.lowercase() }

internal fun unassignedContactGroups(
    people: List<Person>,
    savedZones: List<SavedZone>,
): List<ParticipantLocationGroup> {
    val favoriteZoneIds = savedZones.filter { it.isFavorite }.map { it.id }.toSet()
    val orphans = people.filter { person ->
        person.isFavorite &&
            !person.isAssignedToAny(savedZones) &&
            person.zoneId !in favoriteZoneIds
    }
    return buildParticipantLocationGroups(emptyList(), orphans)
}

internal fun buildMeetingParticipants(
    localZoneId: String,
    groups: List<ParticipantLocationGroup>,
    selectedZones: Map<String, Boolean>,
    selectedPeople: Map<Int, Boolean>,
): List<MeetingParticipant> {
    val byZone = linkedMapOf(localZoneId to MeetingParticipant(localZoneId))
    groups.forEach { group ->
        val zoneActive = group.savedZone?.let { selectedZones[it.id] == true } == true
        val activePeople = group.people.filter { selectedPeople[it.id] == true }
        if (!zoneActive && activePeople.isEmpty()) return@forEach

        val candidate = when {
            activePeople.isNotEmpty() -> participantFromPeople(activePeople)
            else -> MeetingParticipant(group.zoneId)
        }
        val key = group.zoneId
        byZone[key] = mergeMeetingParticipants(byZone[key], candidate)
    }
    return byZone.values.toList()
}

private fun participantFromPeople(people: List<Person>): MeetingParticipant {
    val zoneId = people.first().zoneId
    val work = WorkHourWindows.intersectWorkWindows(
        people.map { it.workStartHour to it.workEndHour },
    )
    val dnd = WorkHourWindows.unionDndWindows(
        people.mapNotNull { person ->
            if (person.dndStartHour in 0..23 && person.dndEndHour in 0..23) {
                person.dndStartHour to person.dndEndHour
            } else {
                null
            }
        },
    )
    return MeetingParticipant(
        zoneId = zoneId,
        workStartHour = work.first,
        workEndHour = work.second,
        dndStartHour = dnd.first,
        dndEndHour = dnd.second,
    )
}

private fun mergeMeetingParticipants(
    existing: MeetingParticipant?,
    next: MeetingParticipant,
): MeetingParticipant {
    if (existing == null) return next
    val work = WorkHourWindows.intersectWorkWindows(
        listOf(
            existing.workStartHour to existing.workEndHour,
            next.workStartHour to next.workEndHour,
        ),
    )
    val dnd = WorkHourWindows.unionDndWindows(
        listOfNotNull(
            if (existing.dndStartHour in 0..23 && existing.dndEndHour in 0..23) {
                existing.dndStartHour to existing.dndEndHour
            } else {
                null
            },
            if (next.dndStartHour in 0..23 && next.dndEndHour in 0..23) {
                next.dndStartHour to next.dndEndHour
            } else {
                null
            },
        ),
    )
    return MeetingParticipant(
        zoneId = next.zoneId,
        workStartHour = work.first,
        workEndHour = work.second,
        dndStartHour = dnd.first,
        dndEndHour = dnd.second,
    )
}

internal fun buildSelectedParticipantLabels(
    localZoneId: String,
    localLocationName: String,
    groups: List<ParticipantLocationGroup>,
    selectedZones: Map<String, Boolean>,
    selectedPeople: Map<Int, Boolean>,
): List<ParticipantSlotLabel> {
    val labels = mutableListOf(
        ParticipantSlotLabel(
            zoneId = localZoneId,
            locationLabel = "You · $localLocationName",
        ),
    )
    val seenZones = mutableSetOf(localZoneId)
    groups.forEach { group ->
        val zoneActive = group.savedZone?.let { selectedZones[it.id] == true } == true
        val activeNames = group.people
            .filter { selectedPeople[it.id] == true }
            .map { personChipLabel(it) }
        if (!zoneActive && activeNames.isEmpty()) return@forEach
        // Zone-only row that duplicates the local "You" chip.
        if (group.zoneId == localZoneId && activeNames.isEmpty()) return@forEach
        if (!seenZones.add(group.zoneId)) return@forEach

        labels += ParticipantSlotLabel(
            zoneId = group.zoneId,
            locationLabel = group.displayName,
            names = activeNames,
        )
    }
    return labels
}


