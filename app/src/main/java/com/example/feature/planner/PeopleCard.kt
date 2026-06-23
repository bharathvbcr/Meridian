package com.example.feature.planner

import android.Manifest
import android.content.pm.PackageManager
import android.provider.ContactsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.example.core.data.Person
import com.example.core.data.SavedZone
import com.example.core.designsystem.GlassDefaults
import com.example.core.designsystem.GlassFormBottomSheet
import com.example.core.designsystem.HourStepperRow
import com.example.core.designsystem.PlannerCard
import com.example.core.designsystem.meridianFilterChipColors
import dev.chrisbanes.haze.HazeState
import kotlinx.coroutines.delay

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun PeopleCard(
    modifier: Modifier = Modifier,
    hazeState: HazeState,
    people: List<Person>,
    selected: SnapshotStateMap<Int, Boolean>,
    onAddPerson: (Person) -> Unit,
    onDeletePerson: (Int) -> Unit,
    searchZones: suspend (String) -> List<SavedZone>,
    defaultWorkStart: Int = 9,
    defaultWorkEnd: Int = 17,
) {
    var showAddDialog by remember { mutableStateOf(false) }

    PlannerCard(modifier = modifier) {
            CardTitle(Icons.Default.Group, "People")
            Spacer(Modifier.height(12.dp))
            if (people.isEmpty()) {
                Text(
                    text = "Add people you meet with — each carries their own time zone.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                )
                Spacer(Modifier.height(12.dp))
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                people.forEach { person ->
                    FilterChip(
                        selected = selected[person.id] == true,
                        onClick = { selected[person.id] = !(selected[person.id] ?: false) },
                        label = {
                            Text(
                                if (person.name.isBlank()) person.displayLocation()
                                else "${person.name} · ${person.displayLocation()}"
                            )
                        },
                        trailingIcon = {
                            IconButton(onClick = { onDeletePerson(person.id) }) {
                                Icon(
                                    imageVector = Icons.Default.Delete,
                                    contentDescription = "Remove ${person.name}",
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        },
                        colors = meridianFilterChipColors()
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
            OutlinedButton(onClick = { showAddDialog = true }) {
                Icon(Icons.Default.PersonAdd, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Add person")
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
            defaultWorkStart = defaultWorkStart,
            defaultWorkEnd = defaultWorkEnd
        )
    }
}

@Composable
internal fun AddPersonDialog(
    searchZones: suspend (String) -> List<SavedZone>,
    hazeState: HazeState,
    onDismiss: () -> Unit,
    onConfirmPerson: (Person) -> Unit,
    onConfirmCity: (SavedZone) -> Unit = {},
    defaultWorkStart: Int = 9,
    defaultWorkEnd: Int = 17,
) {
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    var name by remember { mutableStateOf("") }
    var zoneQuery by remember { mutableStateOf("") }
    var pickedZone by remember { mutableStateOf<SavedZone?>(null) }
    var workStart by remember { mutableStateOf(defaultWorkStart) }
    var workEnd by remember { mutableStateOf(defaultWorkEnd) }
    var dndEnabled by remember { mutableStateOf(false) }
    var dndStart by remember { mutableStateOf(22) }
    var dndEnd by remember { mutableStateOf(7) }
    val results by produceState(initialValue = emptyList<SavedZone>(), zoneQuery, pickedZone) {
        value = if (pickedZone != null || zoneQuery.isBlank()) {
            emptyList()
        } else {
            delay(120) // debounce before querying the bundled city database
            searchZones(zoneQuery)
        }
    }

    val contactPickerLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.PickContact()
    ) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        runCatching {
            context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.Contacts.DISPLAY_NAME),
                null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    cursor.getString(cursor.getColumnIndexOrThrow(ContactsContract.Contacts.DISPLAY_NAME))
                        ?.takeIf { it.isNotBlank() }?.let { name = it }
                }
            }
        }.onFailure { e -> android.util.Log.e("AddPersonDialog", "Contact query failed", e) }
    }

    val readContactsPermLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) contactPickerLauncher.launch(null)
    }

    GlassFormBottomSheet(
        onDismissRequest = onDismiss,
        hazeState = hazeState,
        title = { Text("Add participant") },
        confirmButton = {
            TextButton(
                // Name is optional — only a zone is required to add a participant. When left blank
                // the chips fall back to showing the zone name (see ParticipantsCard).
                enabled = pickedZone != null,
                onClick = {
                    pickedZone?.let { zone ->
                        if (name.isBlank()) {
                            onConfirmCity(zone)
                        } else {
                            onConfirmPerson(
                                Person(
                                    name = name.trim(),
                                    zoneId = zone.id,
                                    locationName = zone.displayName,
                                    workStartHour = workStart,
                                    workEndHour = workEnd,
                                    dndStartHour = if (dndEnabled) dndStart else -1,
                                    dndEndHour = if (dndEnabled) dndEnd else -1,
                                ),
                            )
                        }
                    }
                }
            ) { Text(if (name.isBlank()) "Add city" else "Add person") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
        content = {
                Text(
                    text = "Leave name blank to add a city only, or enter a name to add a person.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    modifier = Modifier.padding(bottom = 12.dp),
                )
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name (optional)") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                    modifier = Modifier.fillMaxWidth(),
                    trailingIcon = {
                        IconButton(onClick = {
                            if (ContextCompat.checkSelfPermission(
                                    context, Manifest.permission.READ_CONTACTS
                                ) == PackageManager.PERMISSION_GRANTED
                            ) {
                                contactPickerLauncher.launch(null)
                            } else {
                                readContactsPermLauncher.launch(Manifest.permission.READ_CONTACTS)
                            }
                        }) {
                            Icon(
                                Icons.Default.Person,
                                contentDescription = "Pick from contacts",
                                modifier = Modifier.size(20.dp),
                            )
                        }
                    }
                )
                Spacer(Modifier.height(12.dp))
                // DROP-UP: matching zones render ABOVE the field (inverted) so they rise toward the
                // top of the dialog instead of dropping below the fold near the keyboard.
                if (results.isNotEmpty()) {
                    val zoneResultCardColors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
                    )
                    Card(
                        shape = GlassDefaults.cardShape,
                        colors = zoneResultCardColors,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(modifier = Modifier.padding(8.dp)) {
                            results.take(4).forEach { zone ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable {
                                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                            pickedZone = zone
                                        }
                                        .padding(horizontal = 12.dp, vertical = 8.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = zone.displayName,
                                            style = MaterialTheme.typography.bodyMedium,
                                            fontWeight = FontWeight.Bold
                                        )
                                        Text(
                                            text = zone.id,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                                        )
                                    }
                                    if (pickedZone?.id == zone.id) {
                                        Icon(
                                            imageVector = Icons.Default.Check,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.primary,
                                            modifier = Modifier.size(18.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                }
                OutlinedTextField(
                    value = pickedZone?.let { "${it.displayName} · ${it.id}" } ?: zoneQuery,
                    onValueChange = {
                        zoneQuery = it
                        pickedZone = null
                    },
                    label = { Text("City / time zone") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(12.dp))
                if (name.isNotBlank()) {
                    HourStepperRow("Work start", workStart, onChange = { newStart ->
                        workStart = newStart
                        if (newStart >= workEnd) workEnd = (newStart + 1).coerceAtMost(23)
                    })
                    HourStepperRow("Work end", workEnd, onChange = { newEnd ->
                        if (newEnd > workStart) workEnd = newEnd
                    })
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Do not disturb", modifier = Modifier.weight(1f))
                        Switch(checked = dndEnabled, onCheckedChange = { dndEnabled = it })
                    }
                    if (dndEnabled) {
                        HourStepperRow("DND start", dndStart, onChange = { dndStart = it })
                        HourStepperRow("DND end", dndEnd, onChange = { dndEnd = it })
                    }
                }
        },
    )
}
