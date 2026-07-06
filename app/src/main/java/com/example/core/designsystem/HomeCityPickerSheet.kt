package com.example.core.designsystem

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.core.data.SavedZone
import dev.chrisbanes.haze.HazeState
import kotlinx.coroutines.delay

/** Minimum accessible touch target (Material / north-star: 48dp), mirrored from the shared token. */
private val MinTouchTarget: Dp = 48.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeCityPickerSheet(
    onDismiss: () -> Unit,
    onCitySelected: (SavedZone) -> Unit,
    search: suspend (String) -> List<SavedZone>,
    hazeState: HazeState,
    title: String = "Choose your home city",
    subtitle: String = "Search any city, airport, or time zone. Resolved on-device.",
) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val haptics = LocalHapticFeedback.current
    val keyboardController = LocalSoftwareKeyboardController.current
    val focusRequester = remember { FocusRequester() }
    val reduceMotion = LocalReduceMotion.current

    LaunchedEffect(Unit) {
        delay(180)
        try {
            focusRequester.requestFocus()
            keyboardController?.show()
        } catch (_: Exception) {
            // Node not yet attached to the layout tree; keyboard will open on first tap.
        }
    }

    var query by remember { mutableStateOf("") }
    // Track the debounce/search window explicitly so the results/empty swap can show a progress
    // affordance instead of flashing "No locations found" during the 120ms delay. `null` results
    // means "still searching"; an empty list means "searched, nothing matched".
    val searchState by produceState(initialValue = SearchState(), query) {
        value = if (query.isBlank()) {
            SearchState(results = emptyList(), searching = false)
        } else {
            value = SearchState(results = null, searching = true)
            delay(120)
            SearchState(results = search(query), searching = false)
        }
    }
    val results = searchState.results.orEmpty()
    val searching = searchState.searching

    GlassBottomSheet(
        onDismissRequest = onDismiss,
        hazeState = hazeState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 16.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = onSurface,
                modifier = Modifier.padding(bottom = 4.dp)
            )
            Text(
                text = subtitle,
                color = onSurface.copy(alpha = 0.6f),
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(bottom = 12.dp)
            )

            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .focusRequester(focusRequester),
                placeholder = {
                    Text(
                        "E.g. Paris, Tokyo, Sydney...",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                },
                leadingIcon = {
                    Icon(
                        Icons.Default.Search,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                },
                trailingIcon = {
                    if (query.isNotEmpty()) {
                        IconButton(onClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            query = ""
                        }) {
                            Icon(
                                Icons.Default.Close,
                                contentDescription = "Clear search",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                },
                singleLine = true,
                shape = RoundedCornerShape(16.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = onSurface,
                    unfocusedTextColor = onSurface,
                    focusedBorderColor = MaterialTheme.colorScheme.primary,
                    unfocusedBorderColor = MaterialTheme.colorScheme.outline
                )
            )

            Spacer(Modifier.height(12.dp))

            // Loading affordance: a small spinner + label while the debounced search is in flight,
            // so the results area never sits silent/blank. Announced politely for TalkBack.
            AnimatedVisibility(
                visible = query.isNotBlank() && searching,
                enter = if (reduceMotion) fadeIn() else fadeIn(Motion.smooth()) +
                    expandVertically(animationSpec = Motion.smooth()),
                exit = if (reduceMotion) fadeOut() else fadeOut(Motion.smooth()) +
                    shrinkVertically(animationSpec = Motion.smooth())
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 20.dp)
                        .semantics {
                            liveRegion = LiveRegionMode.Polite
                            contentDescription = "Searching locations"
                        },
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Spacer(Modifier.width(12.dp))
                    Text(
                        text = "Searching…",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            // Empty state: only after a completed search that matched nothing. The live region
            // lets TalkBack announce the "no results" outcome as it appears.
            AnimatedVisibility(
                visible = query.isNotBlank() && !searching && results.isEmpty(),
                enter = if (reduceMotion) fadeIn() else fadeIn(Motion.smooth()) +
                    expandVertically(animationSpec = Motion.smooth()),
                exit = if (reduceMotion) fadeOut() else fadeOut(Motion.smooth()) +
                    shrinkVertically(animationSpec = Motion.smooth())
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 24.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "No locations found",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.semantics {
                            liveRegion = LiveRegionMode.Polite
                            contentDescription = "No locations found for “$query”"
                        }
                    )
                }
            }

            // Results: same expand/shrink language as ZoneSearchPicker so appearance/dismissal
            // reads as one continuous motion rather than an abrupt swap.
            AnimatedVisibility(
                visible = results.isNotEmpty(),
                enter = if (reduceMotion) fadeIn() else fadeIn(Motion.smooth()) +
                    expandVertically(animationSpec = Motion.smooth()),
                exit = if (reduceMotion) fadeOut() else fadeOut(Motion.smooth()) +
                    shrinkVertically(animationSpec = Motion.smooth())
            ) {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 360.dp)
                ) {
                    itemsIndexed(results, key = { _, it -> it.id }) { index, result ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                // Merge the icon + name + zone id into a single focusable node so
                                // TalkBack announces the whole row as one tappable item.
                                .semantics(mergeDescendants = true) {
                                    role = Role.Button
                                    contentDescription = "${result.displayName}, ${result.id}"
                                }
                                .clickable {
                                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                    keyboardController?.hide()
                                    onCitySelected(result)
                                }
                                .sizeIn(minHeight = MinTouchTarget)
                                .padding(horizontal = 8.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                imageVector = Icons.Default.Home,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(Modifier.width(12.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    result.displayName,
                                    color = onSurface,
                                    fontWeight = FontWeight.Medium
                                )
                                Text(
                                    result.id,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    style = MaterialTheme.typography.bodySmall
                                )
                            }
                        }
                        if (index < results.lastIndex) {
                            HorizontalDivider(
                                color = onSurface.copy(alpha = 0.08f),
                                modifier = Modifier.padding(horizontal = 8.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Snapshot of the debounced search: `null` results = still searching, empty = matched nothing. */
private data class SearchState(
    val results: List<SavedZone>? = emptyList(),
    val searching: Boolean = false,
)
