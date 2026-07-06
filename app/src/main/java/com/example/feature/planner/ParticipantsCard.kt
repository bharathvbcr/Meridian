package com.example.feature.planner

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.core.data.Person
import com.example.core.data.SavedZone
import com.example.core.designsystem.LocalReduceMotion
import com.example.core.designsystem.PlannerCard
import com.example.core.designsystem.meridianFilterChipColors
import dev.chrisbanes.haze.HazeState
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ParticipantsCard(
    modifier: Modifier = Modifier,
    hazeState: HazeState,
    locationGroups: List<ParticipantLocationGroup>,
    localZoneId: String,
    localLocationName: String,
    selectedZones: SnapshotStateMap<String, Boolean>,
    people: List<Person>,
    selectedPeople: SnapshotStateMap<Int, Boolean>,
    onAddPerson: (Person) -> Unit,
    onAddZone: (SavedZone) -> Unit,
    onDeletePerson: (Int) -> Unit,
    searchZones: suspend (String) -> List<SavedZone>,
    defaultWorkStart: Int = 9,
    defaultWorkEnd: Int = 17,
) {
    var showAddDialog by remember { mutableStateOf(false) }

    // selectedZones and selectedPeople are SnapshotStateMaps — derivedStateOf tracks their reads
    // automatically. Including them as remember keys would recreate the derived state on every
    // map mutation, defeating the purpose of derivedStateOf.
    val allSelected by remember(locationGroups) {
        derivedStateOf {
            locationGroups.all { group ->
                isGroupFullySelected(group, selectedZones, selectedPeople)
            }
        }
    }
    val hasFavorites = locationGroups.isNotEmpty() || people.isNotEmpty()

    PlannerCard(modifier = modifier) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                modifier = Modifier.weight(1f),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Default.Group,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(8.dp))
                Column {
                    Text(
                        "Participants",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        "Starred cities and contacts from World Clock & Now",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
                    )
                }
            }
            if (hasFavorites) {
                TextButton(
                    onClick = {
                        val target = !allSelected
                        locationGroups.forEach { group ->
                            group.savedZone?.let { selectedZones[it.id] = target }
                            group.people.forEach { selectedPeople[it.id] = target }
                        }
                    },
                ) {
                    Text(
                        text = if (allSelected) "None" else "All",
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        if (!hasFavorites) {
            Text(
                text = "Add cities and people here, or star them on World Clock or Now.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
            )
            Spacer(Modifier.height(10.dp))
            Button(
                onClick = { showAddDialog = true },
                shape = RoundedCornerShape(50),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = MaterialTheme.colorScheme.onPrimary,
                ),
            ) {
                Text("Add participant", style = MaterialTheme.typography.labelLarge)
            }
            Spacer(Modifier.height(12.dp))
        }
        val youChipColors = FilterChipDefaults.filterChipColors(
            disabledSelectedContainerColor = MaterialTheme.colorScheme.primary,
            disabledLabelColor = MaterialTheme.colorScheme.onPrimary,
        )
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            itemVerticalAlignment = Alignment.CenterVertically,
        ) {
            FilterChip(
                selected = true,
                enabled = false,
                onClick = {},
                label = { Text("You · $localLocationName", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                colors = youChipColors,
                // A disabled+selected FilterChip is announced by TalkBack as merely "disabled",
                // which reads as broken. Override with a clean, self-describing announcement so
                // screen-reader users understand You are permanently part of the meeting.
                modifier = Modifier.clearAndSetSemantics {
                    contentDescription = "You in $localLocationName"
                    selected = true
                    disabled()
                    stateDescription = "Always included"
                },
            )
            if (hasFavorites) {
                locationGroups.forEach { group ->
                    val groupSelected = isGroupSelected(group, selectedZones, selectedPeople)
                    when {
                        group.people.isEmpty() -> {
                            FilterChip(
                                selected = groupSelected,
                                onClick = {
                                    group.savedZone?.let { zone ->
                                        selectedZones[zone.id] = !groupSelected
                                    }
                                },
                                label = {
                                    Text(
                                        group.displayName,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                },
                                colors = meridianFilterChipColors(),
                            )
                        }
                        group.people.size == 1 -> {
                            val person = group.people.first()
                            PersonChip(
                                label = groupChipLabel(group),
                                selected = groupSelected,
                                onToggle = {
                                    val target = !groupSelected
                                    group.savedZone?.let { selectedZones[it.id] = target }
                                    selectedPeople[person.id] = target
                                },
                                onDelete = { onDeletePerson(person.id) },
                            )
                        }
                        else -> {
                            val cityChipSelected = isGroupFullySelected(group, selectedZones, selectedPeople)
                            FilterChip(
                                selected = cityChipSelected,
                                onClick = {
                                    val target = !cityChipSelected
                                    group.savedZone?.let { selectedZones[it.id] = target }
                                    group.people.forEach { selectedPeople[it.id] = target }
                                },
                                label = {
                                    Text(
                                        group.displayName,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                },
                                colors = meridianFilterChipColors(),
                            )
                            group.people.forEach { person ->
                                PersonChip(
                                    label = personChipLabel(person),
                                    selected = selectedPeople[person.id] == true,
                                    onToggle = {
                                        selectedPeople[person.id] = !(selectedPeople[person.id] ?: false)
                                        if (selectedPeople[person.id] == true) {
                                            group.savedZone?.let { selectedZones[it.id] = true }
                                        }
                                    },
                                    onDelete = { onDeletePerson(person.id) },
                                )
                            }
                        }
                    }
                }
            }
            // An action, not a selection: an AssistChip with a primary tint sets it apart from the
            // toggleable participant chips it trails, so "Add" never reads as one more participant.
            AssistChip(
                onClick = { showAddDialog = true },
                label = { Text("Add", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                leadingIcon = {
                    Icon(Icons.Default.PersonAdd, contentDescription = null, modifier = Modifier.size(18.dp))
                },
                colors = AssistChipDefaults.assistChipColors(
                    labelColor = MaterialTheme.colorScheme.primary,
                    leadingIconContentColor = MaterialTheme.colorScheme.primary,
                ),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.5f)),
                modifier = Modifier.semantics {
                    role = Role.Button
                    contentDescription = "Add participant"
                },
            )
        }
    }

    if (showAddDialog) {
        AddPersonDialog(
            searchZones = searchZones,
            hazeState = hazeState,
            onDismiss = { showAddDialog = false },
            onConfirmPerson = { person ->
                onAddPerson(person)
                showAddDialog = false
            },
            onConfirmCity = { zone ->
                onAddZone(zone)
                showAddDialog = false
            },
            defaultWorkStart = defaultWorkStart,
            defaultWorkEnd = defaultWorkEnd,
        )
    }
}

/**
 * Tap to toggle selection. Two delete paths, both discoverable:
 *  - a visible trailing ✕ button (keyboard / switch / sighted users), mirroring PeopleCard's
 *    trailing delete IconButton, and
 *  - a hold-for-~700 ms shortcut on the label — a left-to-right fill sweeps in with escalating
 *    haptic ticks, ending in a strong LongPress pulse on confirm; releasing early springs back.
 *
 * The hold's fill animation and escalating ticks are gated on Reduce Motion: when it is on, the
 * fill snaps and the tick loop is skipped, per the north-star's "always respect Reduce Motion".
 * Fills and border weight track [meridianFilterChipColors] so this chip reads as one family with
 * the Material FilterChips beside it in the same FlowRow.
 */
@Composable
private fun PersonChip(
    label: String,
    selected: Boolean,
    onToggle: () -> Unit,
    onDelete: () -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    val reduceMotion = LocalReduceMotion.current
    val scope = rememberCoroutineScope()
    val progress = remember { Animatable(0f) }
    val chipShape = RoundedCornerShape(50)

    // Match meridianFilterChipColors(): selected fill = primaryContainer on onPrimaryContainer;
    // unselected = a single hairline outline (Material FilterChip's unselected border), so the
    // two chip types are indistinguishable at rest.
    val selectedBg = MaterialTheme.colorScheme.primaryContainer
    val selectedLabel = MaterialTheme.colorScheme.onPrimaryContainer
    val unselectedLabel = MaterialTheme.colorScheme.onSurfaceVariant
    val outlineColor = MaterialTheme.colorScheme.outline
    val errorColor = MaterialTheme.colorScheme.error
    val onErrorColor = MaterialTheme.colorScheme.onError

    val p = progress.value
    val baseLabel = if (selected) selectedLabel else unselectedLabel
    val density = androidx.compose.ui.platform.LocalDensity.current
    val strokeWidthPx = remember(density) { with(density) { 1.dp.toPx() } }

    Row(
        modifier = Modifier
            .clip(chipShape)
            .semantics(mergeDescendants = true) {
                role = Role.Button
                // The label Box + delete IconButton below both clearAndSetSemantics, so the merged
                // node needs the name spelled out here or TalkBack would read an unnamed toggle.
                contentDescription = label
                this.selected = selected
                stateDescription = if (selected) "Included" else "Excluded"
                customActions = listOf(
                    CustomAccessibilityAction(label = "Remove $label") { onDelete(); true }
                )
            }
            .drawBehind {
                val radius = CornerRadius(size.height / 2)
                if (selected) {
                    drawRoundRect(color = selectedBg, cornerRadius = radius)
                }
                if (!selected) {
                    drawRoundRect(
                        color = lerp(outlineColor, errorColor, p),
                        cornerRadius = radius,
                        style = Stroke(width = strokeWidthPx),
                    )
                }
                if (p > 0f) {
                    drawRoundRect(
                        color = errorColor.copy(alpha = 0.25f + 0.25f * p),
                        size = Size(size.width * p, size.height),
                        cornerRadius = radius,
                    )
                }
            }
            .height(FilterChipDefaults.Height),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .clearAndSetSemantics { }
                .pointerInput(label, reduceMotion) {
                    detectTapGestures(
                        onTap = { onToggle() },
                        onPress = {
                            val job = scope.launch {
                                delay(80)
                                val hapticJob = if (reduceMotion) null else launch {
                                    var interval = 160L
                                    while (isActive) {
                                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                        delay(interval)
                                        interval = maxOf(30L, interval - 25L)
                                    }
                                }
                                if (reduceMotion) {
                                    delay(700)
                                    progress.snapTo(1f)
                                } else {
                                    progress.animateTo(1f, tween(700, easing = LinearEasing))
                                }
                                hapticJob?.cancel()
                                if (progress.value >= 0.99f) {
                                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                    onDelete()
                                }
                            }
                            tryAwaitRelease()
                            job.cancel()
                            if (progress.value < 0.99f) {
                                scope.launch {
                                    if (reduceMotion) {
                                        progress.snapTo(0f)
                                    } else {
                                        progress.animateTo(0f, spring(stiffness = Spring.StiffnessMedium))
                                    }
                                }
                            }
                        },
                    )
                }
                .padding(start = 12.dp, end = 4.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = label,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.labelLarge,
                color = lerp(baseLabel, onErrorColor, (p * 2.5f).coerceIn(0f, 1f)),
            )
        }
        // Visible remove affordance for keyboard / switch / sighted users who never discover the
        // hold shortcut. Kept visually at chip height for FlowRow parity while
        // minimumInteractiveComponentSize expands the hit area to the 48dp a11y minimum. Hidden
        // from TalkBack (clearAndSetSemantics) so the merged-parent's "Remove $label" custom
        // action stays the single, canonical delete announcement.
        IconButton(
            onClick = onDelete,
            modifier = Modifier
                .minimumInteractiveComponentSize()
                .size(FilterChipDefaults.Height)
                .clearAndSetSemantics { },
        ) {
            Icon(
                imageVector = Icons.Default.Close,
                contentDescription = null,
                tint = lerp(baseLabel, onErrorColor, (p * 2.5f).coerceIn(0f, 1f)),
                modifier = Modifier.size(16.dp),
            )
        }
    }
}
