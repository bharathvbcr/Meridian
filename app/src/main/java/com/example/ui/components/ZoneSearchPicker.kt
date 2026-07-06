package com.example.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
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
import androidx.compose.foundation.layout.width
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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.core.data.SavedZone
import com.example.core.designsystem.GlassDefaults
import com.example.core.designsystem.LocalReduceMotion
import com.example.core.designsystem.MeridianFilterChip
import com.example.core.designsystem.Motion
import com.example.core.time.TimeFormats
import kotlinx.coroutines.delay
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Private dimension tokens local to this file, mirroring the Meridian spacing / sizing scale
 * (4 / 6 / 8 spacing; 48dp minimum touch target) and glass radius so component internals reference a
 * named token instead of a bare literal — matching the north-star rule against duplicating a value
 * that should be a token, without adding to any shared token file.
 */
private val SpacingSmall: Dp = 8.dp
private val SectionLabelGap: Dp = 6.dp
private val ResultRowVerticalPadding: Dp = 8.dp
private val ResultRowHorizontalPadding: Dp = 4.dp

/** Android minimum accessible touch target (Material a11y guidance). */
private val MinTouchTarget: Dp = 48.dp

/** Field / result-panel corner radius on the Meridian "medium" radius step (matches search field). */
private val FieldRadius: Dp = 16.dp

/** Max height for the scrollable results panel so it never crowds out the surrounding form. */
private val ResultsMaxHeight: Dp = 165.dp

/** Selected-check glyph size for a result row (slightly larger than the chip leading icon). */
private val CheckIconSize: Dp = 18.dp

/**
 * Springy expand/shrink recipe for this file's [AnimatedVisibility] blocks, gated on
 * [LocalReduceMotion]. Mirrors HomeCityPickerSheet's search motion so the picker's show/hide reads
 * as the same liquid-glass language as the rest of the app; under reduce-motion it collapses to a
 * plain fade so the OS "remove animations" preference is honored.
 */
private fun springExpand(
    reduceMotion: Boolean,
    expandFrom: Alignment.Vertical = Alignment.Top,
): EnterTransition =
    if (reduceMotion) {
        fadeIn()
    } else {
        fadeIn(Motion.smooth()) + expandVertically(animationSpec = Motion.smooth(), expandFrom = expandFrom)
    }

private fun springShrink(
    reduceMotion: Boolean,
    shrinkTowards: Alignment.Vertical = Alignment.Top,
): ExitTransition =
    if (reduceMotion) {
        fadeOut()
    } else {
        fadeOut(Motion.smooth()) + shrinkVertically(animationSpec = Motion.smooth(), shrinkTowards = shrinkTowards)
    }

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
    val reduceMotion = LocalReduceMotion.current
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
                reduceMotion = reduceMotion,
                onPickZone = onPickZone,
            )
            ZoneSearchField(
                zoneQuery = zoneQuery,
                onZoneQueryChange = { zoneQuery = it },
                visible = showSearch,
                reduceMotion = reduceMotion,
                focusRequester = zoneSearchFocus,
            )
            AnimatedVisibility(
                visible = zoneQuery.isBlank(),
                enter = springExpand(reduceMotion),
                exit = springShrink(reduceMotion)
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
                reduceMotion = reduceMotion,
                onPickZone = onPickZone,
                visible = showSearch,
            )
            if (showSearch) {
                Spacer(Modifier.height(SpacingSmall))
            }
            ZoneSearchField(
                zoneQuery = zoneQuery,
                onZoneQueryChange = { zoneQuery = it },
                visible = showSearch,
                reduceMotion = reduceMotion,
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
    Column {
        if (showSectionLabel) {
            // A labelMedium section header (12sp SemiBold with wider tracking) reads as a deliberate
            // group label above the chips; marking it a heading lets TalkBack jump to the group.
            Text(
                text = "Quick Select",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.semantics { heading() }
            )
            Spacer(Modifier.height(SectionLabelGap))
        }
        FlowRow(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(SpacingSmall),
            verticalArrangement = Arrangement.spacedBy(SpacingSmall)
        ) {
            quickZones.forEach { (id, name) ->
                // Route through MeridianFilterChip for LongPress-haptic + unified selected semantics
                // parity with every other selectable chip in the app. The leading globe appears only
                // while selected, carrying a "Selected" description for TalkBack.
                MeridianFilterChip(
                    label = name,
                    selected = selectedZoneId == id && !isCustomSelection,
                    onClick = { onQuickZoneSelected(id, name) },
                    leadingIcon = Icons.Default.Public,
                    leadingIconContentDescription = "Selected",
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
                MeridianFilterChip(
                    label = customChipLabel,
                    selected = customChipSelected,
                    onClick = onCustomChipClick,
                    leadingIcon = if (isCustomSelection) Icons.Default.Public else null,
                    leadingIconContentDescription = "Selected",
                )
            }
        }
    }
}

/** In-flight vs. settled search outcome, so the panel can show a spinner instead of flashing
 *  "no matches" during the debounce window. */
private data class ZoneSearchState(val results: List<SavedZone>, val searching: Boolean)

@Composable
private fun ZoneSearchResults(
    zoneQuery: String,
    localZoneId: String,
    selectedZoneId: String,
    searchZones: suspend (String) -> List<SavedZone>,
    is24Hour: Boolean,
    showOffset: Boolean,
    expandFromBottom: Boolean,
    reduceMotion: Boolean,
    onPickZone: (SavedZone) -> Unit,
    visible: Boolean = true,
) {
    // Hoisted above AnimatedVisibility so results survive show/hide cycles without flashing
    // "No matching time zones" on every re-entry. `searching` stays true through the debounce so the
    // empty-state copy only appears once a query genuinely returned nothing.
    val state by produceState(
        initialValue = ZoneSearchState(emptyList(), searching = false),
        zoneQuery,
    ) {
        value = if (zoneQuery.isBlank()) {
            ZoneSearchState(emptyList(), searching = false)
        } else {
            value = ZoneSearchState(value.results, searching = true)
            delay(120)
            ZoneSearchState(searchZones(zoneQuery), searching = false)
        }
    }
    val results = state.results
    val searching = state.searching

    val expandFrom = if (expandFromBottom) Alignment.Bottom else Alignment.Top

    AnimatedVisibility(
        visible = visible && zoneQuery.isNotBlank(),
        enter = springExpand(reduceMotion, expandFrom = expandFrom),
        exit = springShrink(reduceMotion, shrinkTowards = expandFrom)
    ) {
        when {
            searching && results.isEmpty() -> {
                // Loading affordance so the results area never sits silent/blank during the debounce.
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = SpacingSmall)
                        .semantics {
                            liveRegion = LiveRegionMode.Polite
                            contentDescription = "Searching time zones"
                        },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(CheckIconSize),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Spacer(Modifier.width(SpacingSmall))
                    Text(
                        text = "Searching…",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            results.isEmpty() -> {
                Text(
                    text = "No matching time zones",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                    modifier = Modifier
                        .padding(bottom = SpacingSmall)
                        .semantics {
                            liveRegion = LiveRegionMode.Polite
                            contentDescription = "No time zones match “$zoneQuery”"
                        }
                )
            }
            else -> {
                // Match the app's floating result surfaces: the shared glass card radius plus the
                // canonical unified glass tint (GlassDefaults.cardTint) instead of an ad-hoc
                // surfaceVariant alpha. This call site has no HazeState to pass to GlassCard, so it
                // reuses the same shape + tint tokens to stay in the liquid-glass language.
                Card(
                    shape = GlassDefaults.cardShape,
                    colors = CardDefaults.cardColors(containerColor = GlassDefaults.cardTint),
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = ResultsMaxHeight)
                        .padding(bottom = SpacingSmall)
                ) {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = SpacingSmall)
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
}

@Composable
private fun ZoneSearchField(
    zoneQuery: String,
    onZoneQueryChange: (String) -> Unit,
    visible: Boolean,
    reduceMotion: Boolean,
    focusRequester: FocusRequester,
) {
    AnimatedVisibility(
        visible = visible,
        enter = springExpand(reduceMotion),
        exit = springShrink(reduceMotion)
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
            shape = RoundedCornerShape(FieldRadius),
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

    val isSelected = selectedZoneId == zone.id

    // One merged spoken label per row so TalkBack announces the whole option once ("Tokyo,
    // Asia/Tokyo, 14:30, +5 hours") plus a "Selected"/"Not selected" state — instead of reading the
    // name, id, time and check icon as four disconnected nodes with no selected cue.
    val rowDescription = buildString {
        append(zone.displayName)
        append(", ")
        append(zone.id)
        append(", ")
        append(currentLocalTime)
        if (relativeOffset != null) {
            append(", ")
            append(relativeOffset)
        }
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            // Guarantee the Android 48dp accessible target even for a single-line row.
            .heightIn(min = MinTouchTarget)
            .clickable(onClick = onSelect)
            .padding(vertical = ResultRowVerticalPadding, horizontal = ResultRowHorizontalPadding)
            .semantics(mergeDescendants = true) {
                role = Role.Button
                selected = isSelected
                contentDescription = rowDescription
                stateDescription = if (isSelected) "Selected" else "Not selected"
            },
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
            horizontalArrangement = Arrangement.spacedBy(SpacingSmall)
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
            if (isSelected) {
                // Selected state is carried by the merged row semantics above; the glyph stays
                // decorative (null description) so TalkBack doesn't double-announce it.
                Icon(
                    imageVector = Icons.Default.Check,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(CheckIconSize)
                )
            }
        }
    }
}
