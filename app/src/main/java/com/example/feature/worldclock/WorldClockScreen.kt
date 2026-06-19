package com.example.feature.worldclock

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.HorizontalDivider
import androidx.compose.ui.draw.rotate
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.togetherWith
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.zIndex
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.geometry.Offset
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.OutlinedButton
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.outlined.StarBorder
import android.Manifest
import android.content.pm.PackageManager
import android.provider.ContactsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.TextButton
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import com.example.core.data.Person
import com.example.feature.now.AddContactToZoneDialog
import androidx.compose.ui.draw.drawBehind
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.ui.text.style.TextAlign
import com.example.core.designsystem.GlassBottomSheet
import com.example.core.designsystem.GlassCard
import com.example.core.designsystem.MeridianWordmark
import com.example.core.designsystem.liquidGlass
import dev.chrisbanes.haze.HazeState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.MainViewModel
import com.example.core.data.SavedZone
import com.example.core.data.ZoneAnchorRole
import com.example.core.data.isNowAnchor
import com.example.core.designsystem.Motion
import com.example.core.designsystem.rememberIs24Hour
import com.example.core.time.SolarMath
import com.example.core.time.TimeFormats
import com.example.core.time.ZoneCoordinates
import kotlinx.coroutines.delay
import com.example.feature.planner.contactsForZone
import com.example.feature.planner.unassignedContactGroups
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun WorldClockScreen(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier,
    hazeState: dev.chrisbanes.haze.HazeState = remember { dev.chrisbanes.haze.HazeState() }
) {
    val savedZones by viewModel.savedZones.collectAsState()
    val scrubInstant by viewModel.scrubInstant.collectAsState()
    val settings by viewModel.settings.collectAsState()
    val people by viewModel.people.collectAsState()
    val is24Hour = rememberIs24Hour(settings)

    val haptics = LocalHapticFeedback.current

    // Drag-to-reorder state (mirrors the Now page). The home zone stays pinned at the top and is
    // rendered as a separate, non-draggable card; only the non-home zones are reorderable, which
    // matches `viewModel.reorderZones` (it always forces the home zone to orderIndex 0).
    var draggingKey by remember { mutableStateOf<Any?>(null) }
    var draggingOffset by remember { mutableFloatStateOf(0f) }
    val isDragging = draggingKey != null
    var localWatchlistZones by remember { mutableStateOf(savedZones.filter { !it.isNowAnchor() }) }
    val dragHaptics = LocalHapticFeedback.current
    // Which zone card currently shows its options menu (driven by a hold-still release in the drag
    // detector below, or by the card's overflow button). Null = no menu open.
    var menuZoneId by remember { mutableStateOf<String?>(null) }

    // Keep the local draggable list in sync with the VM whenever the data changes — but never
    // mid-drag, or the list would yank out from under the finger.
    LaunchedEffect(savedZones) {
        if (!isDragging) {
            localWatchlistZones = savedZones.filter { !it.isNowAnchor() }
        }
    }

    // Adding cities happens in a bottom-sheet picker (mirrors the Settings home-city picker) so the
    // input field sits cleanly above the keyboard, which auto-opens when the sheet appears.
    var showCityPicker by remember { mutableStateOf(false) }

    val baseInstant = scrubInstant ?: ZonedDateTime.now().toInstant()
    val orphanContactGroups = remember(people, savedZones) {
        unassignedContactGroups(people, savedZones)
    }

    // Pinned dial reveals near the top / on scroll-up and tucks away on scroll-down so it stays
    // reachable without permanently covering the zone list.
    val listState = rememberLazyListState()
    var dialVisible by remember { mutableStateOf(true) }
    var prevIndex by remember { mutableIntStateOf(0) }
    var prevOffset by remember { mutableIntStateOf(0) }
    LaunchedEffect(listState) {
        snapshotFlow { listState.firstVisibleItemIndex to listState.firstVisibleItemScrollOffset }
            .collect { (index, offset) ->
                dialVisible = when {
                    index == 0 && offset < 8 -> true // at the top
                    index < prevIndex || (index == prevIndex && offset < prevOffset) -> true // up
                    index > prevIndex || (index == prevIndex && offset > prevOffset) -> false // down
                    else -> dialVisible
                }
                prevIndex = index
                prevOffset = offset
            }
    }

    // Wide screens (≥600dp) use a side nav rail instead of the bottom bar (and show no
    // bottom-pinned next-event pill), so the dial sits lower and width-capped there.
    val wideLayout = LocalConfiguration.current.screenWidthDp >= 600

    val dialBottomPadding by animateDpAsState(
        targetValue = if (wideLayout) 24.dp else 96.dp,
        animationSpec = Motion.smooth(),
        label = "dialBottomPadding"
    )

    Box(modifier = modifier.fillMaxSize()) {
    LazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .padding(top = 48.dp)
            .imePadding()
            .pointerInput(listState) {
                // Distinguishes a reorder from a "hold still" gesture: any real drag flips this true,
                // so on release we either commit the new order or — if it never moved — open the
                // card's options menu (the tap-and-hold submenu request).
                var didDrag = false
                detectDragGesturesAfterLongPress(
                    onDragStart = { offset ->
                        val item = listState.layoutInfo.visibleItemsInfo.find { info ->
                            offset.y.toInt() in info.offset until (info.offset + info.size)
                        }
                        val key = item?.key
                        if (key is String && localWatchlistZones.any { it.id == key }) {
                            draggingKey = key
                            draggingOffset = 0f
                            didDrag = false
                            dragHaptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        }
                    },
                    onDrag = { change, dragAmount ->
                        change.consume()
                        val key = draggingKey ?: return@detectDragGesturesAfterLongPress
                        draggingOffset += dragAmount.y
                        // Only count this as a real reorder once movement clears the touch slop —
                        // otherwise sub-pixel jitter during a "hold still → open menu" press would
                        // flip didDrag and trigger a redundant reorderZones DB write on release.
                        if (kotlin.math.abs(draggingOffset) > viewConfiguration.touchSlop) {
                            didDrag = true
                        }
                        val items = listState.layoutInfo.visibleItemsInfo
                        val current = items.find { it.key == key }
                            ?: return@detectDragGesturesAfterLongPress
                        val adjustedCenter =
                            current.offset + current.size / 2 + draggingOffset.toInt()
                        val target = items.find { other ->
                            other.key != key &&
                            other.key is String &&
                            localWatchlistZones.any { z -> z.id == other.key } &&
                            adjustedCenter in other.offset until (other.offset + other.size)
                        }
                        if (target != null) {
                            val fromIdx =
                                localWatchlistZones.indexOfFirst { it.id == key }
                            val toIdx =
                                localWatchlistZones.indexOfFirst { it.id == target.key }
                            if (fromIdx != -1 && toIdx != -1) {
                                localWatchlistZones =
                                    localWatchlistZones.toMutableList().apply {
                                        add(toIdx, removeAt(fromIdx))
                                    }
                                draggingOffset -=
                                    (target.offset - current.offset).toFloat()
                            }
                        }
                    },
                    onDragEnd = {
                        val key = draggingKey
                        if (key != null) {
                            if (didDrag) {
                                // savedZones can change mid-drag (a zone removed/added elsewhere, or
                                // home changed) while LaunchedEffect(savedZones) is skipped, leaving
                                // localWatchlistZones stale. Filter to ids that still exist so we
                                // never persist an order referencing a deleted/moved zone.
                                viewModel.reorderZones(
                                    localWatchlistZones.map { it.id }
                                        .filter { id -> savedZones.any { it.id == id } }
                                )
                            } else {
                                // Held still and released — surface the options submenu for that card.
                                menuZoneId = key as? String
                            }
                        }
                        draggingKey = null
                        draggingOffset = 0f
                    },
                    onDragCancel = {
                        draggingKey = null
                        draggingOffset = 0f
                        localWatchlistZones = savedZones.filter { !it.isNowAnchor() }
                    }
                )
            }
    ) {
        // Core Title / Header
        item {
            Column(modifier = Modifier.padding(16.dp)) {
                MeridianWordmark(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 4.dp, bottom = 8.dp)
                )
                Text(
                    text = "World Clock",
                    style = MaterialTheme.typography.displaySmall,
                    fontWeight = FontWeight.Black,
                    color = MaterialTheme.colorScheme.onBackground
                )
                Text(
                    text = "Search locations and scrub time across zones.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f)
                )
            }
        }

        // World day/night terminator — 2D map or 3D globe, sweeps as the scrubber moves (§5.2)
        item {
            WorldVisualization(
                instant = baseInstant,
                zones = savedZones,
                mapStyle = settings.mapStyle,
                hazeState = hazeState,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
            )
        }

        // Search Section Card
        item {
            GlassCard(
                hazeState = hazeState,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                shape = RoundedCornerShape(28.dp)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Default.Public,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(20.dp)
                        )
                        Spacer(Modifier.width(8.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                "Add Worldwide Cities",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                            Text(
                                "Search any city, airport, or time zone to pin its time.",
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                                fontSize = 12.sp
                            )
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                    OutlinedButton(
                        onClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            showCityPicker = true
                        },
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Default.Search, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text("Search worldwide cities")
                    }
                }
            }
        }

        // List Header & Empty State
        if (savedZones.isEmpty()) {
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(48.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Icon(
                        imageVector = Icons.Default.Public,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                        tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.5f)
                    )
                    Spacer(Modifier.height(16.dp))
                    Text(
                        text = "No pinned locations yet",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = "Search and add cities above to track their times across the globe.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center
                    )
                }
            }
        } else {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.Public,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = "Pinned Locations",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onBackground,
                        modifier = Modifier.padding(end = 12.dp)
                    )
                    androidx.compose.material3.HorizontalDivider(
                        color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.12f),
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }

        // Anchor zones (home + home country) stay pinned at the top and are not draggable.
        val anchorZones = savedZones
            .filter { it.isNowAnchor() }
            .sortedBy { zone ->
                when (zone.anchorRole) {
                    ZoneAnchorRole.RESIDENCE -> 0
                    ZoneAnchorRole.HOME_COUNTRY -> 1
                    else -> 2
                }
            }
        anchorZones.forEach { anchorZone ->
            item(key = anchorZone.id) {
                val zoneTime = ZonedDateTime.ofInstant(baseInstant, ZoneId.of(anchorZone.id))
                ZoneComparisonRow(
                    zoneName = anchorZone.displayName,
                    zoneId = anchorZone.id,
                    time = zoneTime,
                    is24Hour = is24Hour,
                    isHome = anchorZone.isHome,
                    hazeState = hazeState,
                    onSetHome = { viewModel.setHomeZone(anchorZone.id, anchorZone.displayName) },
                    onDelete = { viewModel.removeZone(anchorZone.id) },
                    workStartHour = settings.defaultWorkStartHour,
                    workEndHour = settings.defaultWorkEndHour,
                    contacts = contactsForZone(anchorZone, people, savedZones),
                    onAddContact = { name ->
                        viewModel.addPerson(
                            name = name,
                            zoneId = anchorZone.id,
                            locationName = anchorZone.displayName,
                            isFavorite = true,
                        )
                    },
                    onRemoveContact = { personId -> viewModel.deletePerson(personId) },
                    onToggleFavorite = { personId, isFav -> viewModel.togglePersonFavorite(personId, isFav) },
                    isFavorite = anchorZone.isFavorite,
                    onToggleZoneFavorite = { isFav -> viewModel.toggleZoneFavorite(anchorZone.id, isFav) },
                    menuExpanded = menuZoneId == anchorZone.id,
                    onShowMenu = { menuZoneId = anchorZone.id },
                    onDismissMenu = { menuZoneId = null },
                    modifier = Modifier
                        .padding(horizontal = 16.dp, vertical = 6.dp)
                        .animateItem()
                )
            }
        }

        // Main Board locations list — drag-to-reorder over non-anchor zones.
        itemsIndexed(localWatchlistZones, key = { _, zone -> zone.id }) { _, zone ->
            val zoneTime = ZonedDateTime.ofInstant(baseInstant, ZoneId.of(zone.id))
            val isDraggedItem = draggingKey == zone.id
            ZoneComparisonRow(
                zoneName = zone.displayName,
                zoneId = zone.id,
                time = zoneTime,
                is24Hour = is24Hour,
                isHome = zone.isHome,
                hazeState = hazeState,
                onSetHome = { viewModel.setHomeZone(zone.id, zone.displayName) },
                onDelete = { viewModel.removeZone(zone.id) },
                workStartHour = settings.defaultWorkStartHour,
                workEndHour = settings.defaultWorkEndHour,
                contacts = contactsForZone(zone, people, savedZones),
                onAddContact = { name ->
                    viewModel.addPerson(
                        name = name,
                        zoneId = zone.id,
                        locationName = zone.displayName,
                        isFavorite = true,
                    )
                },
                onRemoveContact = { personId -> viewModel.deletePerson(personId) },
                onToggleFavorite = { personId, isFav -> viewModel.togglePersonFavorite(personId, isFav) },
                isFavorite = zone.isFavorite,
                onToggleZoneFavorite = { isFav -> viewModel.toggleZoneFavorite(zone.id, isFav) },
                menuExpanded = menuZoneId == zone.id,
                onShowMenu = { menuZoneId = zone.id },
                onDismissMenu = { menuZoneId = null },
                isDragging = isDraggedItem,
                dragOffsetPx = if (isDraggedItem) draggingOffset else 0f,
                modifier = Modifier
                    .padding(horizontal = 16.dp, vertical = 6.dp)
                    .animateItem()
            )
        }

        if (orphanContactGroups.isNotEmpty()) {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Default.Group,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = "Contact locations",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onBackground,
                        modifier = Modifier.padding(end = 12.dp),
                    )
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.12f),
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            orphanContactGroups.forEach { group ->
                item(key = "contact-${group.zoneId}-${group.displayName}") {
                    val zoneTime = ZonedDateTime.ofInstant(baseInstant, ZoneId.of(group.zoneId))
                    ZoneComparisonRow(
                        zoneName = group.displayName,
                        zoneId = group.zoneId,
                        time = zoneTime,
                        is24Hour = is24Hour,
                        isHome = false,
                        hazeState = hazeState,
                        onSetHome = {},
                        onDelete = {},
                        workStartHour = settings.defaultWorkStartHour,
                        workEndHour = settings.defaultWorkEndHour,
                        contacts = group.people,
                        onAddContact = { name ->
                            viewModel.addPerson(
                                name = name,
                                zoneId = group.zoneId,
                                locationName = group.displayName,
                                isFavorite = true,
                            )
                        },
                        onRemoveContact = { personId -> viewModel.deletePerson(personId) },
                        onToggleFavorite = { personId, isFav -> viewModel.togglePersonFavorite(personId, isFav) },
                        contactOnlyLocation = true,
                        modifier = Modifier
                            .padding(horizontal = 16.dp, vertical = 6.dp)
                            .animateItem(),
                    )
                }
            }
        }

        item {
            // Leave room so the last rows clear the pinned time dial and the nav bar.
            Spacer(Modifier.height(340.dp))
        }
    }

    // Premium Dynamic Interactive Scrubber Dial — pinned above the nav bar so it stays
    // reachable while the zone list scrolls underneath it. Slides away on scroll-down.
    AnimatedVisibility(
        visible = dialVisible,
        enter = slideInVertically(Motion.bouncy()) { it } + fadeIn(),
        exit = slideOutVertically(Motion.smooth()) { it } + fadeOut(),
        modifier = Modifier
            .align(Alignment.BottomCenter)
            .navigationBarsPadding()
            .padding(start = 16.dp, end = 16.dp, bottom = dialBottomPadding)
            .then(if (wideLayout) Modifier.widthIn(max = 520.dp) else Modifier)
    ) {
        com.example.core.designsystem.TimelineScrubber(
            scrubInstant = scrubInstant,
            hazeState = hazeState,
            onScrubTimeChanged = { targetInstant ->
                viewModel.selectScrubTime(targetInstant)
            }
        )
    }

    if (showCityPicker) {
        WorldCityPickerSheet(
            is24Hour = is24Hour,
            baseInstant = baseInstant,
            hazeState = hazeState,
            onDismiss = { showCityPicker = false },
            onAddCity = { viewModel.addZone(it) },
            search = { query -> viewModel.searchTimeZones(query) }
        )
    }
    }
}

// Bottom-sheet city picker for the World Clock, mirroring the Settings home-city picker so the input
// sits cleanly above the keyboard (which auto-opens). Stays open after each add so several cities can
// be pinned in one pass.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WorldCityPickerSheet(
    is24Hour: Boolean,
    baseInstant: java.time.Instant,
    hazeState: HazeState,
    onDismiss: () -> Unit,
    onAddCity: (SavedZone) -> Unit,
    search: suspend (String) -> List<SavedZone>
) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val haptics = LocalHapticFeedback.current
    val keyboardController = LocalSoftwareKeyboardController.current
    val focusRequester = remember { FocusRequester() }

    var query by remember { mutableStateOf("") }
    // Debounce search-as-you-type before querying the bundled city database, mirroring the Settings
    // home-city flow.
    val results by produceState(initialValue = emptyList<SavedZone>(), query) {
        value = if (query.isBlank()) {
            emptyList()
        } else {
            delay(120)
            search(query)
        }
    }

    // Open the keyboard automatically once the sheet has finished animating in, so the user can start
    // typing a city immediately without an extra tap.
    LaunchedEffect(Unit) {
        delay(180)
        focusRequester.requestFocus()
        keyboardController?.show()
    }

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
                text = "Add worldwide cities",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = onSurface,
                modifier = Modifier.padding(bottom = 4.dp)
            )
            Text(
                text = "Search any city, airport, or time zone. Resolved on-device.",
                color = onSurface.copy(alpha = 0.6f),
                fontSize = 12.sp,
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
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
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
                ),
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                    capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.Words,
                    imeAction = androidx.compose.ui.text.input.ImeAction.Search
                ),
                keyboardActions = androidx.compose.foundation.text.KeyboardActions(
                    onSearch = { keyboardController?.hide() }
                )
            )

            Spacer(Modifier.height(12.dp))

            if (query.isNotBlank() && results.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 24.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "No locations found",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 360.dp)
                ) {
                    itemsIndexed(results, key = { _, it -> it.id }) { index, result ->
                        val resultTimeText = ZonedDateTime.ofInstant(baseInstant, ZoneId.of(result.id))
                            .format(TimeFormats.hourMinute(is24Hour))
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .clickable {
                                    // Add and clear the query (keeping the sheet open and the
                                    // keyboard up) so several cities can be pinned in a row.
                                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                    onAddCity(result)
                                    query = ""
                                }
                                .padding(horizontal = 8.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
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
                            Text(
                                text = resultTimeText,
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.padding(end = 8.dp)
                            )
                            Icon(
                                Icons.Default.Add,
                                contentDescription = "Add ${result.displayName}",
                                tint = MaterialTheme.colorScheme.primary
                            )
                        }
                        if (index < results.size - 1) {
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

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ZoneComparisonRow(
    zoneName: String,
    zoneId: String,
    time: ZonedDateTime,
    is24Hour: Boolean,
    isHome: Boolean,
    hazeState: dev.chrisbanes.haze.HazeState,
    onSetHome: () -> Unit,
    onDelete: () -> Unit,
    workStartHour: Int = 9,
    workEndHour: Int = 17,
    contacts: List<Person> = emptyList(),
    onAddContact: (String) -> Unit = {},
    onRemoveContact: (Int) -> Unit = {},
    onToggleFavorite: (Int, Boolean) -> Unit = { _, _ -> },
    isFavorite: Boolean = false,
    onToggleZoneFavorite: (Boolean) -> Unit = {},
    menuExpanded: Boolean = false,
    onShowMenu: () -> Unit = {},
    onDismissMenu: () -> Unit = {},
    isDragging: Boolean = false,
    dragOffsetPx: Float = 0f,
    contactOnlyLocation: Boolean = false,
    modifier: Modifier = Modifier
) {
    val timeFormatter = remember(is24Hour) { TimeFormats.hourMinute(is24Hour) }
    val isWorkingHours = time.hour in workStartHour..workEndHour

    // Intentional day/night / working-hours tint — kept as-is (not unified to GlassDefaults.cardTint).
    val containerColor = if (isWorkingHours) {
        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.18f)
    } else {
        MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.25f)
    }

    val textColor = MaterialTheme.colorScheme.onSurface

    val isDaylight = remember(zoneId, time) {
        val coord = ZoneCoordinates.coordinateFor(zoneId, time.toInstant())
        SolarMath.isDaylight(coord.latitude, coord.longitude, time.toInstant())
    }

    var expanded by remember { mutableStateOf(false) }
    var showAddContactDialog by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current

    Box(
        modifier = modifier
            // Lifted-card feedback while this row is being dragged for reorder (matches Now).
            .zIndex(if (isDragging) 1f else 0f)
            .graphicsLayer {
                if (isDragging) {
                    translationY = dragOffsetPx
                    scaleX = 1.04f
                    scaleY = 1.04f
                    shadowElevation = 24f
                    alpha = 0.93f
                }
            }
    ) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                // Long-press is owned by the list's drag-to-reorder detector (on the LazyColumn).
                // Holding still and releasing opens the options menu; holding and dragging reorders —
                // so this card doesn't claim onLongClick itself, which would swallow the drag gesture.
                .combinedClickable(
                    onClick = { expanded = !expanded },
                    onLongClick = null
                )
                // Lightweight glass (no per-row backdrop blur): this row repeats once per saved zone
                // inside a scrolling list, so a full Haze blur here would multiply across every visible
                // row each frame. The translucent tint over the blurred backdrop keeps the glass look
                // while staying cheap enough to scroll smoothly on lower-end devices.
                .liquidGlass(
                    hazeState = hazeState,
                    tintColor = containerColor,
                    blur = false
                )
                .drawBehind {
                    val glowColor = if (isDaylight) {
                        Color(0xFFFFB703).copy(alpha = 0.22f)
                    } else {
                        Color(0xFF219EBC).copy(alpha = 0.22f)
                    }
                    drawCircle(
                        brush = androidx.compose.ui.graphics.Brush.radialGradient(
                            colors = listOf(glowColor, Color.Transparent),
                            center = Offset(size.width * 0.85f, size.height * 0.15f),
                            radius = size.width * 0.6f
                        ),
                        center = Offset(size.width * 0.85f, size.height * 0.15f),
                        radius = size.width * 0.6f
                    )
                },
            colors = CardDefaults.cardColors(containerColor = Color.Transparent)
        ) {
        Column(modifier = Modifier.padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = zoneName,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = textColor
                    )
                    if (isFavorite) {
                        Spacer(Modifier.width(6.dp))
                        Icon(
                            imageVector = Icons.Filled.Star,
                            contentDescription = "Favorite",
                            tint = Color(0xFFFFD166),
                            modifier = Modifier.size(14.dp)
                        )
                    }
                    Spacer(Modifier.width(6.dp))
                    Icon(
                        imageVector = if (isDaylight) Icons.Default.WbSunny else Icons.Default.NightsStay,
                        contentDescription = if (isDaylight) "Daytime" else "Nighttime",
                        tint = if (isDaylight) Color(0xFFFFD166) else Color(0xFF90D2FF),
                        modifier = Modifier.size(16.dp)
                    )
                    if (isHome) {
                        Spacer(Modifier.width(6.dp))
                        Icon(
                            imageVector = Icons.Filled.Home,
                            contentDescription = "Home zone",
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }
                Spacer(Modifier.height(2.dp))
                Text(
                    text = if (isWorkingHours) "Working hours" else "Off-hours",
                    style = MaterialTheme.typography.bodySmall,
                    color = if (isWorkingHours) MaterialTheme.colorScheme.primary.copy(alpha = 0.9f)
                            else textColor.copy(alpha = 0.55f)
                )
                val utcOffset = remember(time) {
                    val o = time.offset.toString()
                    if (o == "Z") "UTC±0" else "UTC$o"
                }
                Text(
                    text = utcOffset,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                    fontSize = 10.sp
                )
                val favoriteContacts = contacts.filter { it.isFavorite }
                if (favoriteContacts.isNotEmpty()) {
                    Spacer(Modifier.height(4.dp))
                    Row(horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(4.dp)) {
                        favoriteContacts.forEach { person ->
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(50))
                                    .background(MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.65f))
                                    .padding(horizontal = 7.dp, vertical = 2.dp)
                            ) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(3.dp)
                                ) {
                                    Icon(
                                        imageVector = Icons.Filled.Star,
                                        contentDescription = null,
                                        tint = Color(0xFFFFD166),
                                        modifier = Modifier.size(10.dp)
                                    )
                                    Text(
                                        text = person.name,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                                        fontSize = 10.sp
                                    )
                                }
                            }
                        }
                    }
                }
                SunTimesLine(zoneId = zoneId, time = time, is24Hour = is24Hour, textColor = textColor)
            }

            Column(horizontalAlignment = Alignment.End) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = time.format(timeFormatter),
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary
                    )
                    val chevronRotation by animateFloatAsState(
                        targetValue = if (expanded) 180f else 0f,
                        animationSpec = Motion.smooth(),
                        label = "chevron"
                    )
                    Icon(
                        imageVector = Icons.Default.ExpandMore,
                        contentDescription = if (expanded) "Collapse" else "Expand",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                        modifier = Modifier.size(20.dp).rotate(chevronRotation)
                    )
                    IconButton(onClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        onShowMenu()
                    }) {
                        Icon(
                            imageVector = Icons.Filled.MoreVert,
                            contentDescription = "Show options",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                val dateFormatter = remember { TimeFormats.mediumDate() }
                Text(
                    text = time.format(dateFormatter),
                    style = MaterialTheme.typography.bodySmall,
                    color = textColor.copy(alpha = 0.6f),
                    fontWeight = FontWeight.Bold
                )
            }
        }

        AnimatedVisibility(
            visible = expanded,
            enter = expandVertically(animationSpec = Motion.smooth()) + fadeIn(animationSpec = Motion.smooth()),
            exit = shrinkVertically(animationSpec = Motion.smooth()) + fadeOut(animationSpec = Motion.smooth())
        ) {
            Column(modifier = Modifier.fillMaxWidth().padding(top = 10.dp)) {
                HorizontalDivider(
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f),
                    modifier = Modifier.padding(bottom = 8.dp)
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column {
                        Text(
                            text = "Work window",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                        )
                        Text(
                            text = "${"%02d".format(workStartHour)}:00 – ${"%02d".format(workEndHour)}:00",
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.Bold
                        )
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text(
                            text = "Zone ID",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                        )
                        Text(
                            text = zoneId,
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                        )
                    }
                }
                Spacer(Modifier.height(8.dp))
                HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.10f))
                Spacer(Modifier.height(6.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Filled.Group,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = "Contacts",
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                    )
                    Spacer(Modifier.weight(1f))
                    TextButton(
                        onClick = { showAddContactDialog = true },
                        modifier = Modifier.height(28.dp),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 8.dp, vertical = 0.dp)
                    ) {
                        Icon(Icons.Filled.PersonAdd, contentDescription = null, modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(3.dp))
                        Text("Add", style = MaterialTheme.typography.labelSmall)
                    }
                }
                val favoriteContacts = contacts.filter { it.isFavorite }
                if (favoriteContacts.isEmpty()) {
                    Text(
                        text = "No starred contacts — tap Add or star someone to include them in Plan",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f),
                        modifier = Modifier.padding(top = 2.dp, bottom = 4.dp)
                    )
                } else {
                    favoriteContacts.forEach { person ->
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(vertical = 1.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Person,
                                contentDescription = null,
                                modifier = Modifier.size(14.dp),
                                tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
                            )
                            Spacer(Modifier.width(6.dp))
                            Text(
                                text = person.name,
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.weight(1f)
                            )
                            IconButton(
                                onClick = { onToggleFavorite(person.id, !person.isFavorite) },
                                modifier = Modifier.size(28.dp)
                            ) {
                                Icon(
                                    imageVector = if (person.isFavorite) Icons.Filled.Star else Icons.Outlined.StarBorder,
                                    contentDescription = if (person.isFavorite) "Unstar" else "Star",
                                    tint = if (person.isFavorite) Color(0xFFFFD166)
                                           else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f),
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                            IconButton(
                                onClick = { onRemoveContact(person.id) },
                                modifier = Modifier.size(28.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Delete,
                                    contentDescription = "Remove contact",
                                    tint = MaterialTheme.colorScheme.error.copy(alpha = 0.6f),
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        }
                    }
                }
            }
        }
        }
        }

        if (showAddContactDialog) {
            AddContactToZoneDialog(
                zoneName = zoneName,
                hazeState = hazeState,
                onDismiss = { showAddContactDialog = false },
                onConfirm = { name -> onAddContact(name); showAddContactDialog = false }
            )
        }

        // Liquid-glass options sheet: transparent container so the menu's own surface doesn't
        // paint over the frosted tint, with the glass tint + refraction + border supplied by
        // liquidGlass() to match the rest of the app's chrome instead of a flat Material popup.
        // Move Up / Move Down are intentionally gone — reordering is now drag-to-reorder.
        DropdownMenu(
            expanded = menuExpanded,
            onDismissRequest = onDismissMenu,
            shape = RoundedCornerShape(22.dp),
            containerColor = Color.Transparent,
            tonalElevation = 0.dp,
            shadowElevation = 0.dp,
            border = null,
            // blur = false: the menu lives in its own popup window, where Haze would sample the
            // backdrop at the wrong coordinates. The translucent tint + border still reads as glass.
            modifier = Modifier.liquidGlass(
                hazeState = hazeState,
                shape = RoundedCornerShape(22.dp),
                tintColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.82f),
                borderColor = Color.White.copy(alpha = 0.25f),
                blur = false
            )
        ) {
            if (!contactOnlyLocation) {
                DropdownMenuItem(
                    text = { Text(if (isFavorite) "Remove from Favorites" else "Add to Favorites") },
                    onClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        onToggleZoneFavorite(!isFavorite)
                        onDismissMenu()
                    },
                    leadingIcon = {
                        Icon(
                            imageVector = if (isFavorite) Icons.Filled.Star else Icons.Outlined.StarBorder,
                            contentDescription = null,
                            tint = Color(0xFFFFD166)
                        )
                    }
                )
            }
            DropdownMenuItem(
                text = { Text("Add contact to $zoneName") },
                onClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    showAddContactDialog = true
                    onDismissMenu()
                },
                leadingIcon = { Icon(Icons.Filled.PersonAdd, contentDescription = null) }
            )
            if (!contactOnlyLocation && !isHome) {
                DropdownMenuItem(
                    text = { Text("Set as My Home Zone") },
                    onClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        onSetHome()
                        onDismissMenu()
                    },
                    leadingIcon = { Icon(Icons.Filled.Home, contentDescription = null, tint = MaterialTheme.colorScheme.primary) }
                )
            }
            if (!contactOnlyLocation) {
                DropdownMenuItem(
                    text = { Text("Remove from Watchlist") },
                    onClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        onDelete()
                        onDismissMenu()
                    },
                    leadingIcon = { Icon(Icons.Default.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) }
                )
            }
        }
    }
}

@Composable
private fun WorldVisualization(
    instant: java.time.Instant,
    zones: List<SavedZone>,
    mapStyle: com.example.core.data.MapStyle,
    hazeState: dev.chrisbanes.haze.HazeState,
    modifier: Modifier = Modifier,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    // Graceful degrade: force 2D on battery saver or low-RAM devices (§5.2, §16).
    val constrained = remember {
        val power = context.getSystemService(android.os.PowerManager::class.java)
        val activity = context.getSystemService(android.app.ActivityManager::class.java)
        (power?.isPowerSaveMode == true) || (activity?.isLowRamDevice == true)
    }
    // The Performance map style is for keeping frames cheap, so the heavier 3D globe is disabled
    // there too — the toggle hides and the view is forced to the flat 2D map.
    val performanceMode = mapStyle == com.example.core.data.MapStyle.PERFORMANCE
    val twoDOnly = constrained || performanceMode
    var globeMode by remember { mutableStateOf(false) }
    val showGlobe = globeMode && !twoDOnly

    Column(modifier = modifier) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (!twoDOnly) {
                SingleChoiceSegmentedButtonRow {
                    SegmentedButton(
                        selected = !showGlobe,
                        onClick = { globeMode = false },
                        shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2),
                        label = { Text("2D") }
                    )
                    SegmentedButton(
                        selected = showGlobe,
                        onClick = { globeMode = true },
                        shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2),
                        label = { Text("3D") }
                    )
                }
            } else {
                Text(
                    if (performanceMode) "3D off (Performance style)" else "3D off (power saver)",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        AnimatedContent(
            targetState = showGlobe,
            label = "MapGlobeTransition",
            transitionSpec = {
                fadeIn() togetherWith fadeOut()
            }
        ) { isGlobe ->
            if (isGlobe) {
                GlobeView(
                    instant = instant,
                    zones = zones,
                    dayColor = MaterialTheme.colorScheme.primaryContainer,
                    nightColor = Color(0xFF0B1020),
                    sunColor = MaterialTheme.colorScheme.tertiary,
                    pinColor = MaterialTheme.colorScheme.primary,
                    pinNightColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
                    atmosphereColor = MaterialTheme.colorScheme.primary,
                    style = mapStyle,
                )
            } else {
                DayNightMap(instant = instant, zones = zones, style = mapStyle, hazeState = hazeState)
            }
        }
    }
}

@Composable
private fun SunTimesLine(
    zoneId: String,
    time: ZonedDateTime,
    is24Hour: Boolean,
    textColor: Color
) {
    val timeFormatter = remember(is24Hour) { TimeFormats.hourMinute(is24Hour) }
    val sun = remember(zoneId, time.toLocalDate()) {
        val coord = ZoneCoordinates.coordinateFor(zoneId, time.toInstant())
        SolarMath.sunTimes(coord.latitude, coord.longitude, time.toLocalDate(), time.zone)
    }
    val label = when {
        sun.polarDay -> "☀️ Midnight sun — no sunset"
        sun.polarNight -> "🌑 Polar night — no sunrise"
        sun.sunrise != null && sun.sunset != null ->
            "🌅 ${sun.sunrise.format(timeFormatter)}   🌇 ${sun.sunset.format(timeFormatter)}"
        else -> "Sun times unavailable"
    }
    Text(
        text = label,
        style = MaterialTheme.typography.bodySmall,
        color = textColor.copy(alpha = 0.6f),
        fontSize = 10.sp,
        modifier = Modifier.padding(top = 2.dp)
    )
}
