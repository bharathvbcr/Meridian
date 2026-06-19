package com.example.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.example.core.data.SavedZone
import com.example.core.time.TimeFormats
import kotlinx.coroutines.delay
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Quick-pick chips (local + saved zones) with optional custom zone search.
 * Pass [alwaysShowSearch] for dialog layouts; inline forms use the Custom chip to expand search.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ZoneSearchPicker(
    localZoneId: String,
    quickZones: List<Pair<String, String>>,
    selectedZoneId: String,
    selectedZoneLabel: String,
    onZoneSelected: (id: String, label: String) -> Unit,
    searchZones: suspend (String) -> List<SavedZone>,
    is24Hour: Boolean,
    modifier: Modifier = Modifier,
    alwaysShowSearch: Boolean = false,
) {
    val haptics = LocalHapticFeedback.current
    val zoneSearchFocus = remember { FocusRequester() }
    var zoneQuery by remember { mutableStateOf("") }
    var customMode by remember { mutableStateOf(alwaysShowSearch) }

    val quickZoneIds = remember(quickZones) { quickZones.map { it.first } }
    val isCustomSelection = selectedZoneId !in quickZoneIds
    val showSearch = alwaysShowSearch || customMode

    LaunchedEffect(selectedZoneId, quickZoneIds) {
        if (selectedZoneId in quickZoneIds) {
            customMode = alwaysShowSearch
            zoneQuery = ""
        }
    }

    LaunchedEffect(customMode) {
        if (customMode && !alwaysShowSearch) {
            zoneSearchFocus.requestFocus()
        }
    }

    val onPickZone: (SavedZone) -> Unit = { zone ->
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        onZoneSelected(zone.id, zone.displayName)
        customMode = alwaysShowSearch
        zoneQuery = ""
    }

    Column(modifier = modifier) {
        if (alwaysShowSearch) {
            ZoneSearchResults(
                zoneQuery = zoneQuery,
                localZoneId = localZoneId,
                selectedZoneId = selectedZoneId,
                searchZones = searchZones,
                is24Hour = is24Hour,
                showOffset = true,
                expandFromBottom = true,
                onPickZone = onPickZone,
            )
            ZoneSearchField(
                zoneQuery = zoneQuery,
                onZoneQueryChange = { zoneQuery = it },
                visible = showSearch,
                focusRequester = zoneSearchFocus,
            )
            AnimatedVisibility(
                visible = zoneQuery.isBlank(),
                enter = fadeIn() + expandVertically(),
                exit = fadeOut() + shrinkVertically()
            ) {
                QuickZoneChips(
                    quickZones = quickZones,
                    selectedZoneId = selectedZoneId,
                    isCustomSelection = isCustomSelection,
                    customChipSelected = customMode || isCustomSelection,
                    showCustomChip = false,
                    selectedZoneLabel = selectedZoneLabel,
                    onQuickZoneSelected = { id, label ->
                        onZoneSelected(id, label)
                        customMode = false
                        zoneQuery = ""
                    },
                    onCustomChipClick = { customMode = true },
                    showSectionLabel = true,
                )
            }
        } else {
            QuickZoneChips(
                quickZones = quickZones,
                selectedZoneId = selectedZoneId,
                isCustomSelection = isCustomSelection,
                customChipSelected = customMode || isCustomSelection,
                showCustomChip = true,
                selectedZoneLabel = selectedZoneLabel,
                onQuickZoneSelected = { id, label ->
                    onZoneSelected(id, label)
                    customMode = false
                    zoneQuery = ""
                },
                onCustomChipClick = { customMode = true },
                showSectionLabel = false,
            )
            ZoneSearchResults(
                zoneQuery = zoneQuery,
                localZoneId = localZoneId,
                selectedZoneId = selectedZoneId,
                searchZones = searchZones,
                is24Hour = is24Hour,
                showOffset = false,
                expandFromBottom = false,
                onPickZone = onPickZone,
                visible = showSearch,
            )
            if (showSearch) {
                Spacer(Modifier.height(8.dp))
            }
            ZoneSearchField(
                zoneQuery = zoneQuery,
                onZoneQueryChange = { zoneQuery = it },
                visible = showSearch,
                focusRequester = zoneSearchFocus,
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun QuickZoneChips(
    quickZones: List<Pair<String, String>>,
    selectedZoneId: String,
    isCustomSelection: Boolean,
    customChipSelected: Boolean,
    showCustomChip: Boolean,
    selectedZoneLabel: String,
    onQuickZoneSelected: (id: String, label: String) -> Unit,
    onCustomChipClick: () -> Unit,
    showSectionLabel: Boolean,
) {
    val chipColors = FilterChipDefaults.filterChipColors(
        selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
        selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
        selectedLeadingIconColor = MaterialTheme.colorScheme.onPrimaryContainer,
    )

    Column {
        if (showSectionLabel) {
            Text(
                text = "Quick Select",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.height(6.dp))
        }
        FlowRow(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            quickZones.forEach { (id, name) ->
                FilterChip(
                    selected = selectedZoneId == id && !isCustomSelection,
                    onClick = { onQuickZoneSelected(id, name) },
                    label = { Text(name) },
                    leadingIcon = if (selectedZoneId == id && !isCustomSelection) {
                        { Icon(Icons.Default.Public, contentDescription = null, modifier = Modifier.size(16.dp)) }
                    } else null,
                    colors = chipColors
                )
            }
            if (showCustomChip) {
                val customChipLabel = if (isCustomSelection) {
                    selectedZoneLabel.take(18).let { t ->
                        if (selectedZoneLabel.length > 18) "$t…" else t
                    }
                } else {
                    "Custom"
                }
                FilterChip(
                    selected = customChipSelected,
                    onClick = onCustomChipClick,
                    label = { Text(customChipLabel) },
                    leadingIcon = if (isCustomSelection) {
                        { Icon(Icons.Default.Public, contentDescription = null, modifier = Modifier.size(16.dp)) }
                    } else null,
                    colors = chipColors
                )
            }
        }
    }
}

@Composable
private fun ZoneSearchResults(
    zoneQuery: String,
    localZoneId: String,
    selectedZoneId: String,
    searchZones: suspend (String) -> List<SavedZone>,
    is24Hour: Boolean,
    showOffset: Boolean,
    expandFromBottom: Boolean,
    onPickZone: (SavedZone) -> Unit,
    visible: Boolean = true,
) {
    AnimatedVisibility(
        visible = visible && zoneQuery.isNotBlank(),
        enter = fadeIn() + expandVertically(
            expandFrom = if (expandFromBottom) Alignment.Bottom else Alignment.Top
        ),
        exit = fadeOut() + shrinkVertically(
            shrinkTowards = if (expandFromBottom) Alignment.Bottom else Alignment.Top
        )
    ) {
        val results by produceState(initialValue = emptyList<SavedZone>(), zoneQuery) {
            value = if (zoneQuery.isBlank()) {
                emptyList()
            } else {
                delay(120)
                searchZones(zoneQuery)
            }
        }
        if (results.isEmpty()) {
            Text(
                text = "No matching time zones",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                modifier = Modifier.padding(bottom = 8.dp)
            )
        } else {
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 165.dp)
                    .padding(bottom = 8.dp)
            ) {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 8.dp)
                ) {
                    items(results, key = { it.id }) { zone ->
                        ZoneSearchResultRow(
                            zone = zone,
                            localZoneId = localZoneId,
                            selectedZoneId = selectedZoneId,
                            is24Hour = is24Hour,
                            showOffset = showOffset,
                            onSelect = { onPickZone(zone) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ZoneSearchField(
    zoneQuery: String,
    onZoneQueryChange: (String) -> Unit,
    visible: Boolean,
    focusRequester: FocusRequester,
) {
    AnimatedVisibility(
        visible = visible,
        enter = fadeIn() + expandVertically(),
        exit = fadeOut() + shrinkVertically()
    ) {
        OutlinedTextField(
            value = zoneQuery,
            onValueChange = onZoneQueryChange,
            label = { Text("Search location / time zone") },
            placeholder = { Text("e.g. Tokyo, London, UTC+5:30") },
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
            modifier = Modifier
                .fillMaxWidth()
                .focusRequester(focusRequester),
            shape = RoundedCornerShape(16.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = MaterialTheme.colorScheme.onSurface,
                unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
                focusedBorderColor = MaterialTheme.colorScheme.primary,
                unfocusedBorderColor = MaterialTheme.colorScheme.outline,
            )
        )
    }
}

@Composable
private fun ZoneSearchResultRow(
    zone: SavedZone,
    localZoneId: String,
    selectedZoneId: String,
    is24Hour: Boolean,
    showOffset: Boolean,
    onSelect: () -> Unit,
) {
    val currentLocalTime = remember(zone.id, is24Hour) {
        ZonedDateTime.now(ZoneId.of(zone.id)).format(TimeFormats.hourMinute(is24Hour))
    }
    val relativeOffset = remember(zone.id, localZoneId, showOffset) {
        if (!showOffset) return@remember null
        val targetOffset = ZoneId.of(zone.id).rules.getOffset(Instant.now())
        val localOffset = ZoneId.of(localZoneId).rules.getOffset(Instant.now())
        val diffSeconds = targetOffset.totalSeconds - localOffset.totalSeconds
        val diffHours = diffSeconds / 3600.0
        when {
            diffHours == 0.0 -> "same time"
            else -> {
                val sign = if (diffHours > 0) "+" else "-"
                val absHours = kotlin.math.abs(diffHours)
                val hourStr = if (absHours % 1 == 0.0) absHours.toInt().toString() else absHours.toString()
                "$sign${hourStr}h"
            }
        }
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect)
            .padding(vertical = 8.dp, horizontal = 4.dp),
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
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (relativeOffset != null) {
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = currentLocalTime,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Text(
                        text = relativeOffset,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                    )
                }
            } else {
                Text(
                    text = currentLocalTime,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            if (selectedZoneId == zone.id) {
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
