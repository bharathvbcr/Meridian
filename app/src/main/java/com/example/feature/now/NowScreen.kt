package com.example.feature.now

import android.Manifest
import android.content.pm.PackageManager
import android.provider.ContactsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material.icons.outlined.Home
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.TextButton
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import com.example.core.data.Person
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.MainViewModel
import com.example.core.data.SavedZone
import com.example.core.data.ZoneAnchorRole
import com.example.core.data.homeCountryZone
import com.example.core.data.isNowAnchor
import com.example.core.data.offsetDiffLabel
import com.example.core.data.residenceZone
import com.example.core.data.wallClockKey
import com.example.core.data.PlannedTask
import com.example.core.designsystem.GlassFormBottomSheet
import com.example.core.designsystem.HomeCityPickerSheet
import com.example.core.designsystem.liquidGlass
import com.example.core.designsystem.MeridianWordmark
import com.example.core.designsystem.Motion
import com.example.core.designsystem.rememberIs24Hour
import com.example.core.time.SolarMath
import com.example.core.time.TimeFormats
import com.example.core.time.ZoneCoordinates
import dev.chrisbanes.haze.HazeState
import kotlinx.coroutines.delay
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.togetherWith
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.HorizontalDivider
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.zIndex
import com.example.feature.planner.contactsForZone
import com.example.feature.planner.unassignedContactGroups
import com.example.feature.worldclock.ZoneComparisonRow
import kotlin.math.cos
import kotlin.math.sin

private val DEG_TO_RAD = (Math.PI / 180.0).toFloat()

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun NowScreen(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier,
    hazeState: HazeState = remember { HazeState() }
) {
    var currentTime by remember { mutableStateOf(ZonedDateTime.now()) }
    val savedZones by viewModel.savedZones.collectAsState()
    val people by viewModel.people.collectAsState()
    val settings by viewModel.settings.collectAsState()
    val plannedTasks by viewModel.plannedTasks.collectAsState()
    val is24Hour = rememberIs24Hour(settings)

    val lazyListState = rememberLazyListState()
    var draggingKey by remember { mutableStateOf<Any?>(null) }
    var draggingOffset by remember { mutableFloatStateOf(0f) }
    val isDragging = draggingKey != null
    var localWatchlistZones by remember { mutableStateOf(savedZones.filter { !it.isNowAnchor() }) }
    val dragHaptics = LocalHapticFeedback.current
    // Which watchlist card currently shows its options menu (driven by a hold-still release, see the
    // drag detector below, or by the card's overflow button). Null = no menu open.
    var menuZoneId by remember { mutableStateOf<String?>(null) }
    // Favorites quick-filter: when on, the watchlist collapses to starred zones only.
    var showFavoritesOnly by remember { mutableStateOf(true) }

    val orphanContactGroups = remember(people, savedZones) {
        unassignedContactGroups(people, savedZones)
    }

    LaunchedEffect(savedZones) {
        if (!isDragging) {
            localWatchlistZones = savedZones.filter { !it.isNowAnchor() }
        }
    }

    LaunchedEffect(Unit) {
        while (true) {
            currentTime = ZonedDateTime.now()
            delay(1000)
        }
    }

    val localHour = currentTime.hour
    val greeting = when (localHour) {
        in 5..11 -> "Good morning"
        in 12..16 -> "Good afternoon"
        in 17..21 -> "Good evening"
        else -> "Good night"
    }

    val localZoneId = ZoneId.systemDefault()
    val homeCountryZone = savedZones.homeCountryZone()
    val residenceZone = savedZones.residenceZone()

    val upcomingTasks = remember(plannedTasks, currentTime.toEpochSecond() / 60) {
        val nowMs = currentTime.toInstant().toEpochMilli()
        plannedTasks
            .filter { it.timestamp > nowMs - 1800_000 }
            .sortedBy { it.timestamp }
            .take(3)
    }

    val zoneAbbreviation = remember(localZoneId) {
        ZonedDateTime.now(localZoneId).format(DateTimeFormatter.ofPattern("z"))
    }
    val offsetText = remember(localZoneId) {
        val offset = ZonedDateTime.now(localZoneId).offset.toString()
        if (offset == "Z") "±00:00" else offset
    }

    LazyColumn(
        state = lazyListState,
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp)
            .pointerInput(lazyListState) {
                // Distinguishes a reorder from a "hold still" gesture: any real drag flips this true,
                // so on release we either commit the new order or — if it never moved — open the
                // card's options menu (the tap-and-hold submenu request).
                var didDrag = false
                detectDragGesturesAfterLongPress(
                    onDragStart = { offset ->
                        val item = lazyListState.layoutInfo.visibleItemsInfo.find { info ->
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
                        didDrag = true
                        change.consume()
                        val key = draggingKey ?: return@detectDragGesturesAfterLongPress
                        draggingOffset += dragAmount.y
                        val items = lazyListState.layoutInfo.visibleItemsInfo
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
                                viewModel.reorderZones(localWatchlistZones.map { it.id })
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
            },
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Welcome and Local Header
        item {
            Spacer(Modifier.height(56.dp))
            MeridianWordmark(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp)
            )
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 16.dp),
                horizontalAlignment = Alignment.Start
            ) {
                AnimatedContent(
                    targetState = greeting,
                    transitionSpec = { fadeIn(tween(400)) togetherWith fadeOut(tween(400)) },
                    label = "greeting"
                ) { greetingText ->
                    Text(
                        text = greetingText,
                        style = MaterialTheme.typography.displayMedium,
                        fontWeight = FontWeight.Black,
                        color = MaterialTheme.colorScheme.onBackground
                    )
                }
                Text(
                    text = "$zoneAbbreviation · UTC$offsetText · ${localZoneId.id}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f)
                )
            }
        }

        // Time & Home Zone Card
        item {
            TimeAndLocationCard(
                viewModel = viewModel,
                homeCountryZone = homeCountryZone,
                residenceZone = residenceZone,
                showHomeCountry = settings.homeCountryEnabled,
                currentTime = currentTime,
                is24Hour = is24Hour,
                hazeState = hazeState,
            )
            Spacer(Modifier.height(16.dp))
        }

        // Solar & Daylight Widget
        item {
            val solarTargetZone = residenceZone?.let { ZoneId.of(it.id) } ?: localZoneId
            SolarDaylightWidget(solarTargetZone, currentTime, is24Hour, hazeState)
            Spacer(Modifier.height(16.dp))
        }

        // Agenda Section Header
        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.Start,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Filled.Schedule,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    text = "Upcoming Agenda",
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

        // Agenda List
        if (upcomingTasks.isEmpty()) {
            item {
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .liquidGlass(hazeState),
                    colors = CardDefaults.cardColors(containerColor = Color.Transparent)
                ) {
                    Column(
                        modifier = Modifier.padding(20.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(
                            imageVector = Icons.Default.EventAvailable,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.4f),
                            modifier = Modifier.size(40.dp)
                        )
                        Spacer(Modifier.height(8.dp))
                        Text(
                            text = "Your schedule is clear",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Spacer(Modifier.height(4.dp))
                        Text(
                            text = "Use the Plan tab or AI Assistant to schedule your next multi-zone meeting.",
                            style = MaterialTheme.typography.bodyMedium,
                            textAlign = TextAlign.Center,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                        )
                    }
                }
                Spacer(Modifier.height(16.dp))
            }
        } else {
            itemsIndexed(upcomingTasks, key = { _, task -> task.id }) { _, task ->
                Box(modifier = Modifier.animateItem()) {
                    AgendaItemRow(task, currentTime, is24Hour, viewModel, hazeState)
                }
                Spacer(Modifier.height(8.dp))
            }
            item {
                Spacer(Modifier.height(8.dp))
            }
        }

        // Favorites quick-filter: only meaningful once at least one watchlist zone is starred.
        val favoriteZones = localWatchlistZones.filter { it.isFavorite }
        val hasFavorites = favoriteZones.isNotEmpty()
        val favOnly = showFavoritesOnly && hasFavorites
        val displayedZones = if (favOnly) favoriteZones else localWatchlistZones

        // Saved Zones Header
        item {
            Column(modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Start,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Home,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.secondary,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = "Zone Watchlist",
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
                if (hasFavorites) {
                    Spacer(Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilterChip(
                            selected = !favOnly,
                            onClick = { showFavoritesOnly = false },
                            label = { Text("All") }
                        )
                        FilterChip(
                            selected = favOnly,
                            onClick = { showFavoritesOnly = true },
                            leadingIcon = {
                                Icon(
                                    imageVector = Icons.Filled.Star,
                                    contentDescription = null,
                                    modifier = Modifier.size(18.dp)
                                )
                            },
                            label = { Text("Favorites") }
                        )
                    }
                }
            }
        }

        // Pinned World Clocks
        if (localWatchlistZones.isEmpty()) {
            item {
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .liquidGlass(hazeState),
                    colors = CardDefaults.cardColors(containerColor = Color.Transparent)
                ) {
                    Column(
                        modifier = Modifier.padding(20.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(
                            imageVector = Icons.Default.Public,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.secondary.copy(alpha = 0.4f),
                            modifier = Modifier.size(40.dp)
                        )
                        Spacer(Modifier.height(8.dp))
                        Text(
                            text = "Watchlist is empty",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Spacer(Modifier.height(4.dp))
                        Text(
                            text = "Search and pin other cities in the World Clock tab to monitor them here.",
                            style = MaterialTheme.typography.bodyMedium,
                            textAlign = TextAlign.Center,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                        )
                    }
                }
            }
        } else {
            itemsIndexed(displayedZones, key = { _, zone -> zone.id }) { index, zone ->
                val isDraggedItem = draggingKey == zone.id
                WatchlistZoneCard(
                    zone = zone,
                    currentTime = currentTime,
                    is24Hour = is24Hour,
                    isFirst = index == 0,
                    isLast = index == displayedZones.size - 1,
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
                    onToggleZoneFavorite = { isFav -> viewModel.toggleZoneFavorite(zone.id, isFav) },
                    onMoveUp = { viewModel.reorderZone(zone.id, -1) },
                    onMoveDown = { viewModel.reorderZone(zone.id, 1) },
                    onSetHome = { viewModel.setHomeZone(zone.id, zone.displayName) },
                    onDelete = { viewModel.removeZone(zone.id) },
                    menuExpanded = menuZoneId == zone.id,
                    onShowMenu = { menuZoneId = zone.id },
                    onDismissMenu = { menuZoneId = null },
                    hazeState = hazeState,
                    isDragging = isDraggedItem,
                    dragOffsetPx = if (isDraggedItem) draggingOffset else 0f
                )
                Spacer(Modifier.height(8.dp))
            }
        }

        if (orphanContactGroups.isNotEmpty()) {
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 4.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "Contact locations",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                    )
                }
            }
            orphanContactGroups.forEach { group ->
                item(key = "contact-${group.zoneId}-${group.displayName}") {
                    ZoneComparisonRow(
                        zoneName = group.displayName,
                        zoneId = group.zoneId,
                        time = currentTime.withZoneSameInstant(ZoneId.of(group.zoneId)),
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
                        modifier = Modifier.padding(vertical = 4.dp),
                    )
                    Spacer(Modifier.height(8.dp))
                }
            }
        }

        item {
            Spacer(Modifier.height(120.dp)) // Navigation bar padding
        }
    }
}

@Composable
private fun TimeAndLocationCard(
    viewModel: MainViewModel,
    homeCountryZone: SavedZone?,
    residenceZone: SavedZone?,
    showHomeCountry: Boolean,
    currentTime: ZonedDateTime,
    is24Hour: Boolean,
    hazeState: HazeState,
) {
    val timeFormatter = remember(is24Hour) { TimeFormats.hourMinuteSecond(is24Hour) }
    val anchorTimeFormatter = remember(is24Hour) { TimeFormats.hourMinute(is24Hour) }
    val dateFormatter = remember { TimeFormats.mediumDate() }
    val localUtcOffset = remember(currentTime) {
        val o = currentTime.offset.toString()
        if (o == "Z") "UTC±0" else "UTC$o"
    }
    var isResolving by remember { mutableStateOf(false) }
    var pickingAnchor by remember { mutableStateOf<String?>(null) }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
        onResult = { isGranted ->
            if (isGranted) {
                isResolving = true
                viewModel.resolveHomeFromLocation { isResolving = false }
            }
        }
    )

    val anchorClockVisibility = remember(
        homeCountryZone,
        residenceZone,
        showHomeCountry,
        currentTime.toEpochSecond() / 60,
    ) {
        val seen = mutableSetOf(wallClockKey(currentTime))
        fun consumeClock(zone: SavedZone?): Boolean {
            if (zone == null) return false
            val key = wallClockKey(currentTime.withZoneSameInstant(ZoneId.of(zone.id)))
            return if (key in seen) false else {
                seen.add(key)
                true
            }
        }
        val residenceClock = if (residenceZone != null) consumeClock(residenceZone) else false
        val homeCountryClock = if (showHomeCountry && homeCountryZone != null) {
            consumeClock(homeCountryZone)
        } else {
            false
        }
        Pair(residenceClock, homeCountryClock)
    }

    val isDaylight = remember(currentTime) {
        val zoneId = ZoneId.systemDefault().id
        val coord = ZoneCoordinates.coordinateFor(zoneId, currentTime.toInstant())
        SolarMath.isDaylight(coord.latitude, coord.longitude, currentTime.toInstant())
    }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .liquidGlass(hazeState, tintColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.05f))
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
        Column(modifier = Modifier.padding(20.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = currentTime.format(timeFormatter),
                        style = MaterialTheme.typography.displaySmall.copy(
                            fontSize = 32.sp,
                            fontWeight = FontWeight.Black
                        ),
                        color = MaterialTheme.colorScheme.primary
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = currentTime.format(dateFormatter),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    Text(
                        text = "$localUtcOffset · Now",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                AnalogClock(time = currentTime)
            }

            AnchorZoneSection(
                slotLabel = "Home",
                zone = residenceZone,
                currentTime = currentTime,
                anchorTimeFormatter = anchorTimeFormatter,
                dateFormatter = dateFormatter,
                showDigitalClock = anchorClockVisibility.first,
                emptyTitle = "Home",
                emptySubtitle = "Your usual base — campus city or apartment.",
                icon = Icons.Filled.Home,
                onPickCity = { pickingAnchor = ZoneAnchorRole.RESIDENCE },
                onUseLocation = {
                    if (viewModel.hasLocationPermission()) {
                        isResolving = true
                        viewModel.resolveHomeFromLocation { isResolving = false }
                    } else {
                        permissionLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
                    }
                },
                isResolving = isResolving,
            )

            if (showHomeCountry && homeCountryZone != null) {
                AnchorZoneSection(
                    slotLabel = "Home country",
                    zone = homeCountryZone,
                    currentTime = currentTime,
                    anchorTimeFormatter = anchorTimeFormatter,
                    dateFormatter = dateFormatter,
                    showDigitalClock = anchorClockVisibility.second,
                    emptyTitle = "Home country",
                    emptySubtitle = "",
                    icon = Icons.Filled.Public,
                    onPickCity = {},
                    showChangeButton = false,
                )
            }
        }
    }

    pickingAnchor?.let { anchorRole ->
        HomeCityPickerSheet(
            onDismiss = { pickingAnchor = null },
            onCitySelected = { result ->
                viewModel.setAnchorZone(result.id, result.displayName, anchorRole)
                pickingAnchor = null
            },
            search = { query -> viewModel.searchTimeZones(query) },
            hazeState = hazeState,
            title = when (anchorRole) {
                ZoneAnchorRole.RESIDENCE -> "Choose your home city"
                else -> "Choose a city"
            },
        )
    }
}

@Composable
private fun AnchorZoneSection(
    slotLabel: String,
    zone: SavedZone?,
    currentTime: ZonedDateTime,
    anchorTimeFormatter: java.time.format.DateTimeFormatter,
    dateFormatter: java.time.format.DateTimeFormatter,
    showDigitalClock: Boolean,
    emptyTitle: String,
    emptySubtitle: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onPickCity: () -> Unit,
    onUseLocation: (() -> Unit)? = null,
    isResolving: Boolean = false,
    showChangeButton: Boolean = true,
) {
    androidx.compose.material3.HorizontalDivider(
        modifier = Modifier.padding(vertical = 14.dp),
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f)
    )

    if (zone != null) {
        val zoneZdt = currentTime.withZoneSameInstant(ZoneId.of(zone.id))
        val diffText = offsetDiffLabel(currentTime, zoneZdt)
        val utcOffset = zoneZdt.offset.toString().let { o -> if (o == "Z") "UTC±0" else "UTC$o" }
        val sameClockNote = if (showDigitalClock) {
            "$slotLabel · $diffText"
        } else {
            val matchesLocal = wallClockKey(zoneZdt) == wallClockKey(currentTime)
            "$slotLabel · ${if (matchesLocal) "Same as now" else "Same clock as above"}"
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                modifier = Modifier.weight(1f),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(24.dp)
                )
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(
                        text = zone.displayName,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    if (showDigitalClock) {
                        Text(
                            text = "${zoneZdt.format(dateFormatter)} · $utcOffset",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Text(
                        text = sameClockNote,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(
                            alpha = if (showDigitalClock) 0.7f else 1f
                        )
                    )
                }
            }
            if (showDigitalClock) {
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = zoneZdt.format(anchorTimeFormatter),
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary
                    )
                    if (showChangeButton) {
                        TextButton(onClick = onPickCity) {
                            Text("Change")
                        }
                    }
                }
            } else if (showChangeButton) {
                TextButton(onClick = onPickCity) {
                    Text("Change")
                }
            }
        }
    } else {
        Column(modifier = Modifier.fillMaxWidth()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(24.dp)
                )
                Spacer(Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = emptyTitle,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    Text(
                        text = emptySubtitle,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(
                    onClick = onPickCity,
                    modifier = Modifier.weight(1f)
                ) {
                    Icon(
                        imageVector = Icons.Filled.Search,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text("Pick city")
                }
                if (onUseLocation != null) {
                    TextButton(
                        onClick = onUseLocation,
                        modifier = Modifier.weight(1f)
                    ) {
                        if (isResolving) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        } else {
                            Icon(
                                imageVector = Icons.Filled.LocationOn,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(Modifier.width(4.dp))
                            Text("Use location")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AnalogClock(
    time: ZonedDateTime,
    modifier: Modifier = Modifier
) {
    val primaryColor = MaterialTheme.colorScheme.primary
    val secondaryColor = MaterialTheme.colorScheme.secondary
    val tertiaryColor = MaterialTheme.colorScheme.tertiary
    val onSurfaceColor = MaterialTheme.colorScheme.onSurface

    Canvas(modifier = modifier.size(100.dp)) {
        val center = Offset(size.width / 2f, size.height / 2f)
        val radius = size.width / 2f

        // Draw clock face outline
        drawCircle(
            color = onSurfaceColor.copy(alpha = 0.15f),
            radius = radius,
            center = center,
            style = Stroke(width = 2.dp.toPx())
        )

        // Draw ticks
        for (i in 0 until 12) {
            val angle = i * 30f * DEG_TO_RAD
            val isMainTick = i % 3 == 0
            val tickLength = if (isMainTick) 8.dp.toPx() else 4.dp.toPx()
            val outerPoint = Offset(
                x = center.x + (radius - 2.dp.toPx()) * sin(angle),
                y = center.y - (radius - 2.dp.toPx()) * cos(angle)
            )
            val innerPt = Offset(
                x = center.x + (radius - tickLength - 2.dp.toPx()) * sin(angle),
                y = center.y - (radius - tickLength - 2.dp.toPx()) * cos(angle)
            )
            drawLine(
                color = onSurfaceColor.copy(alpha = if (isMainTick) 0.5f else 0.2f),
                start = outerPoint,
                end = innerPt,
                strokeWidth = if (isMainTick) 2.dp.toPx() else 1.dp.toPx(),
                cap = StrokeCap.Round
            )
        }

        val hour = time.hour % 12
        val minute = time.minute
        val second = time.second

        val hourAngle = (hour + minute / 60f) * 30f * DEG_TO_RAD
        val minuteAngle = (minute + second / 60f) * 6f * DEG_TO_RAD
        val secondAngle = second * 6f * DEG_TO_RAD

        // Hour hand
        val hourLength = radius * 0.5f
        val hourEnd = Offset(
            x = center.x + hourLength * sin(hourAngle),
            y = center.y - hourLength * cos(hourAngle)
        )
        drawLine(
            color = primaryColor,
            start = center,
            end = hourEnd,
            strokeWidth = 3.5.dp.toPx(),
            cap = StrokeCap.Round
        )

        // Minute hand
        val minuteLength = radius * 0.75f
        val minuteEnd = Offset(
            x = center.x + minuteLength * sin(minuteAngle),
            y = center.y - minuteLength * cos(minuteAngle)
        )
        drawLine(
            color = secondaryColor,
            start = center,
            end = minuteEnd,
            strokeWidth = 2.dp.toPx(),
            cap = StrokeCap.Round
        )

        // Second hand
        val secondLength = radius * 0.85f
        val secondEnd = Offset(
            x = center.x + secondLength * sin(secondAngle),
            y = center.y - secondLength * cos(secondAngle)
        )
        drawLine(
            color = tertiaryColor,
            start = center,
            end = secondEnd,
            strokeWidth = 1.dp.toPx(),
            cap = StrokeCap.Round
        )

        // Center pin
        drawCircle(
            color = tertiaryColor,
            radius = 3.dp.toPx(),
            center = center
        )
    }
}

@Composable
private fun SolarDaylightWidget(
    zoneId: ZoneId,
    currentTime: ZonedDateTime,
    is24Hour: Boolean,
    hazeState: HazeState,
) {
    val geoPoint = remember(zoneId) {
        ZoneCoordinates.coordinateFor(zoneId.id, Instant.now())
    }
    val localDate = currentTime.toLocalDate()
    val sunTimes = remember(geoPoint, localDate, zoneId) {
        SolarMath.sunTimes(geoPoint.latitude, geoPoint.longitude, localDate, zoneId)
    }

    val isDaylight = remember(geoPoint, currentTime.toEpochSecond() / 60) {
        SolarMath.isDaylight(geoPoint.latitude, geoPoint.longitude, currentTime.toInstant())
    }

    val daylightSummaryText = remember(sunTimes) {
        if (sunTimes.sunrise != null && sunTimes.sunset != null) {
            val duration = java.time.Duration.between(sunTimes.sunrise, sunTimes.sunset)
            val hours = duration.toHours()
            val minutes = duration.toMinutes() % 60
            "$hours hrs $minutes mins of daylight today"
        } else if (sunTimes.polarDay) {
            "Midnight Sun (24 hrs daylight)"
        } else {
            "Polar Night (24 hrs darkness)"
        }
    }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .liquidGlass(hazeState, tintColor = MaterialTheme.colorScheme.tertiary.copy(alpha = 0.05f))
            .drawBehind {
                val glowColor = if (isDaylight) {
                    Color(0xFFFFB703).copy(alpha = 0.22f) // warm sun orange/yellow glow
                } else {
                    Color(0xFF219EBC).copy(alpha = 0.22f) // cool moon cyan/blue glow
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
                Icon(
                    imageVector = if (isDaylight) Icons.Filled.WbSunny else Icons.Filled.NightsStay,
                    contentDescription = null,
                    tint = if (isDaylight) Color(0xFFFFD166) else Color(0xFF90D2FF),
                    modifier = Modifier.size(24.dp)
                )
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(
                        text = if (isDaylight) "Sunlight Status" else "Nighttime Status",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    Text(
                        text = if (isDaylight) "Currently Daylight" else "Currently Nighttime",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    if (sunTimes.sunrise != null && sunTimes.sunset != null) {
                        val tf = TimeFormats.hourMinute(is24Hour)
                        Spacer(Modifier.height(2.dp))
                        Text(
                            text = "↑ ${sunTimes.sunrise.format(tf)}  ↓ ${sunTimes.sunset.format(tf)}",
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            // Beautiful Custom Sun Track
            SunTrackCanvas(
                sunrise = sunTimes.sunrise,
                sunset = sunTimes.sunset,
                currentTime = currentTime.toLocalTime(),
                polarDay = sunTimes.polarDay,
                polarNight = sunTimes.polarNight
            )

            Spacer(Modifier.height(8.dp))

            Text(
                text = daylightSummaryText,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.8f),
                fontWeight = FontWeight.SemiBold
            )
        }
    }
}

@Composable
private fun SunTrackCanvas(
    sunrise: java.time.LocalTime?,
    sunset: java.time.LocalTime?,
    currentTime: java.time.LocalTime,
    polarDay: Boolean,
    polarNight: Boolean,
    modifier: Modifier = Modifier
) {
    val trackColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.15f)
    val daylightColor = Color(0xFFFFD166).copy(alpha = 0.8f)
    val nightColor = Color(0xFF90D2FF).copy(alpha = 0.8f)
    val dotColor = if (sunrise != null && sunset != null && currentTime.isAfter(sunrise) && currentTime.isBefore(sunset)) {
        Color(0xFFFFD166)
    } else {
        Color(0xFF90D2FF)
    }

    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(28.dp)
    ) {
        val width = size.width
        val height = size.height
        val centerY = height / 2f

        // Draw background line
        drawLine(
            color = trackColor,
            start = Offset(0f, centerY),
            end = Offset(width, centerY),
            strokeWidth = 4.dp.toPx(),
            cap = StrokeCap.Round
        )

        // Calculate progress percentage
        var pct = 0f
        var isSpecialState = false
        var specialColor = trackColor

        when {
            polarDay -> {
                pct = 0.5f // sun is up all day, center it
                isSpecialState = true
                specialColor = daylightColor
            }
            polarNight -> {
                pct = 0.5f // sun is down all day
                isSpecialState = true
                specialColor = nightColor
            }
            sunrise != null && sunset != null -> {
                val riseMin = sunrise.hour * 60 + sunrise.minute
                val setMin = sunset.hour * 60 + sunset.minute
                val currentMin = currentTime.hour * 60 + currentTime.minute

                if (currentMin in riseMin..setMin) {
                    // Daylight progress
                    val range = setMin - riseMin
                    pct = if (range > 0) (currentMin - riseMin).toFloat() / range else 0f
                    // Draw active daylight segment
                    drawLine(
                        color = daylightColor,
                        start = Offset(0f, centerY),
                        end = Offset(pct * width, centerY),
                        strokeWidth = 4.dp.toPx(),
                        cap = StrokeCap.Round
                    )
                } else {
                    // Nighttime progress
                    val range = if (currentMin < riseMin) {
                        (1440 - setMin) + currentMin
                    } else {
                        currentMin - setMin
                    }
                    val totalNight = 1440 - (setMin - riseMin)
                    pct = if (totalNight > 0) range.toFloat() / totalNight else 0f
                    // Draw active night segment
                    drawLine(
                        color = nightColor,
                        start = Offset(0f, centerY),
                        end = Offset(pct * width, centerY),
                        strokeWidth = 4.dp.toPx(),
                        cap = StrokeCap.Round
                    )
                }
            }
        }

        // Draw sun/moon position node
        if (isSpecialState) {
            drawCircle(
                color = specialColor,
                radius = 6.dp.toPx(),
                center = Offset(width / 2f, centerY)
            )
        } else {
            drawCircle(
                color = dotColor,
                radius = 7.dp.toPx(),
                center = Offset(pct * width, centerY)
            )
            // Add a subtle glowing ring
            drawCircle(
                color = dotColor.copy(alpha = 0.3f),
                radius = 11.dp.toPx(),
                center = Offset(pct * width, centerY),
                style = Stroke(width = 2.dp.toPx())
            )
        }
    }
}

@Composable
private fun AgendaItemRow(
    task: PlannedTask,
    currentTime: ZonedDateTime,
    is24Hour: Boolean,
    viewModel: MainViewModel,
    hazeState: HazeState
) {
    val taskZdt = Instant.ofEpochMilli(task.timestamp).atZone(ZoneId.systemDefault())
    val timeFormatter = remember(is24Hour) { TimeFormats.hourMinute(is24Hour) }
    val dateFormatter = remember { TimeFormats.mediumDate() }

    val minutesDiff = remember(task.timestamp, currentTime.toEpochSecond() / 60) {
        val nowMinutes = currentTime.toEpochSecond() / 60
        val taskMinutes = task.timestamp / 60000
        taskMinutes - nowMinutes
    }

    val relativeText = remember(minutesDiff) {
        val absDiff = kotlin.math.abs(minutesDiff)
        val hours = absDiff / 60
        val days = hours / 24

        val suffix = if (minutesDiff >= 0) "from now" else "ago"
        when {
            absDiff < 1 -> "Just now"
            absDiff < 60 -> "$absDiff min $suffix"
            hours < 24 -> "$hours hr${if (hours > 1) "s" else ""} $suffix"
            else -> "$days day${if (days > 1) "s" else ""} $suffix"
        }
    }

    val haptics = LocalHapticFeedback.current
    val isPast = minutesDiff < 0
    val tagColor = when {
        isPast -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
        minutesDiff < 60 -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.primary
    }

    val zoneLabel = remember(task.zoneId) {
        val sysId = ZoneId.systemDefault().id
        if (task.zoneId != sysId) task.zoneId.substringAfterLast('/').replace('_', ' ') else null
    }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .alpha(if (minutesDiff < -30) 0.55f else 1f)
            // Repeated agenda list row → lightweight glass (no per-row backdrop blur) so the cost
            // doesn't scale with the number of upcoming tasks.
            .liquidGlass(hazeState, blur = false),
        colors = CardDefaults.cardColors(containerColor = Color.Transparent)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                modifier = Modifier.weight(1f),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Colored status indicator dot
                Canvas(modifier = Modifier.size(10.dp)) {
                    drawCircle(color = tagColor)
                }
                Spacer(Modifier.width(14.dp))
                Column {
                    Text(
                        text = task.title,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = buildString {
                            append("${taskZdt.format(timeFormatter)} · ${taskZdt.format(dateFormatter)} ($relativeText)")
                            if (zoneLabel != null) append(" · $zoneLabel")
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            IconButton(
                onClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    viewModel.deleteTask(task.id)
                }
            ) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = "Dismiss",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                    modifier = Modifier.size(20.dp)
                )
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun WatchlistZoneCard(
    zone: SavedZone,
    currentTime: ZonedDateTime,
    is24Hour: Boolean,
    isFirst: Boolean,
    isLast: Boolean,
    workStartHour: Int = 9,
    workEndHour: Int = 17,
    contacts: List<Person> = emptyList(),
    onAddContact: (String) -> Unit = {},
    onRemoveContact: (Int) -> Unit = {},
    onToggleFavorite: (Int, Boolean) -> Unit = { _, _ -> },
    onToggleZoneFavorite: (Boolean) -> Unit = {},
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onSetHome: () -> Unit,
    onDelete: () -> Unit,
    menuExpanded: Boolean = false,
    onShowMenu: () -> Unit = {},
    onDismissMenu: () -> Unit = {},
    hazeState: HazeState,
    isDragging: Boolean = false,
    dragOffsetPx: Float = 0f
) {
    val zoneId = remember(zone.id) { ZoneId.of(zone.id) }
    val zoneTime = currentTime.withZoneSameInstant(zoneId)
    val timeFormatter = remember(is24Hour) { TimeFormats.hourMinute(is24Hour) }
    val dateFormatter = remember { TimeFormats.mediumDate() }

    val zoneUtcOffset = remember(zoneTime) {
        val o = zoneTime.offset.toString()
        if (o == "Z") "UTC±0" else "UTC$o"
    }

    val isWorkingHours = zoneTime.hour in workStartHour..workEndHour

    val geoPoint = remember(zone.id) {
        ZoneCoordinates.coordinateFor(zone.id, Instant.now())
    }
    val isDaylight = remember(geoPoint, currentTime.toEpochSecond() / 60) {
        SolarMath.isDaylight(geoPoint.latitude, geoPoint.longitude, currentTime.toInstant())
    }

    var expanded by remember { mutableStateOf(false) }
    var showAddContactDialog by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current

    Box(
        modifier = Modifier
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
                // Long-press is owned by the watchlist's drag-to-reorder detector (on the LazyColumn).
                // Holding still and releasing opens the options menu; holding and dragging reorders —
                // so this card doesn't claim onLongClick itself, which would swallow the drag gesture.
                .combinedClickable(
                    onClick = { expanded = !expanded },
                    onLongClick = null
                )
                // Repeated watchlist row → lightweight glass (no per-row backdrop blur) so a long
                // watchlist scrolls smoothly; the translucent tint over the backdrop keeps the look.
                .liquidGlass(
                    hazeState = hazeState,
                    tintColor = if (isWorkingHours) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.18f)
                                else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.25f),
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
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    modifier = Modifier.weight(1f),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = if (isDaylight) Icons.Filled.WbSunny else Icons.Filled.NightsStay,
                        contentDescription = null,
                        tint = if (isDaylight) Color(0xFFFFD166) else Color(0xFF90D2FF),
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(Modifier.width(14.dp))
                    Column {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = zone.displayName,
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                            if (zone.isFavorite) {
                                Spacer(Modifier.width(6.dp))
                                Icon(
                                    imageVector = Icons.Filled.Star,
                                    contentDescription = "Favorite",
                                    tint = Color(0xFFFFD166),
                                    modifier = Modifier.size(14.dp)
                                )
                            }
                        }
                        Text(
                            text = "${zoneTime.format(dateFormatter)} · $zoneUtcOffset",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            text = if (isWorkingHours) "Working hours" else "Off hours",
                            style = MaterialTheme.typography.labelSmall,
                            color = if (isWorkingHours) MaterialTheme.colorScheme.primary.copy(alpha = 0.85f)
                                    else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f),
                            fontSize = 10.sp
                        )
                        // Favorite contact pills — shown even when card is collapsed
                        val favoriteContacts = contacts.filter { it.isFavorite }
                        if (favoriteContacts.isNotEmpty()) {
                            Spacer(Modifier.height(4.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                favoriteContacts.forEach { person ->
                                    Box(
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(50))
                                            .background(MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.65f))
                                            .padding(horizontal = 7.dp, vertical = 2.dp)
                                    ) {
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(3.dp)
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
                    }
                }

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = zoneTime.format(timeFormatter),
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
            }

            AnimatedVisibility(
                visible = expanded,
                enter = expandVertically(animationSpec = Motion.smooth()) + fadeIn(animationSpec = Motion.smooth()),
                exit = shrinkVertically(animationSpec = Motion.smooth()) + fadeOut(animationSpec = Motion.smooth())
            ) {
                val sunFormatter = remember(is24Hour) {
                    DateTimeFormatter.ofPattern(if (is24Hour) "HH:mm" else "h:mm a")
                }
                val sunTimes = remember(zone.id, zoneTime.toLocalDate()) {
                    SolarMath.sunTimes(geoPoint.latitude, geoPoint.longitude, zoneTime.toLocalDate(), zoneId)
                }
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 14.dp, end = 14.dp, bottom = 14.dp)
                ) {
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f),
                        modifier = Modifier.padding(vertical = 8.dp)
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(20.dp)
                    ) {
                        if (sunTimes.sunrise != null) {
                            Column {
                                Text(
                                    text = "Sunrise",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                                )
                                Text(
                                    text = sunTimes.sunrise.format(sunFormatter),
                                    style = MaterialTheme.typography.bodySmall,
                                    fontWeight = FontWeight.Bold,
                                    color = Color(0xFFFFD166)
                                )
                            }
                        }
                        if (sunTimes.sunset != null) {
                            Column {
                                Text(
                                    text = "Sunset",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                                )
                                Text(
                                    text = sunTimes.sunset.format(sunFormatter),
                                    style = MaterialTheme.typography.bodySmall,
                                    fontWeight = FontWeight.Bold,
                                    color = Color(0xFF90D2FF)
                                )
                            }
                        }
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
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(
                        text = zone.id,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.35f)
                    )
                    Spacer(Modifier.height(10.dp))
                    HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.10f))
                    Spacer(Modifier.height(8.dp))
                    // Contacts section
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Group,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                            modifier = Modifier.size(14.dp)
                        )
                        Spacer(Modifier.width(4.dp))
                        Text(
                            text = "Contacts",
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
                        )
                        Spacer(Modifier.weight(1f))
                        TextButton(
                            onClick = { showAddContactDialog = true },
                            modifier = Modifier.minimumInteractiveComponentSize()
                        ) {
                            Icon(Icons.Filled.PersonAdd, contentDescription = null, modifier = Modifier.size(12.dp))
                            Spacer(Modifier.width(3.dp))
                            Text("Add", style = MaterialTheme.typography.labelSmall)
                        }
                    }
                    val favoriteContacts = contacts.filter { it.isFavorite }
                    if (favoriteContacts.isEmpty()) {
                        Text(
                            text = "No starred contacts — tap Add or star someone to include them in Plan",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f),
                            modifier = Modifier.padding(top = 4.dp, bottom = 4.dp)
                        )
                    } else {
                        favoriteContacts.forEach { person ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 2.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = person.name,
                                    style = MaterialTheme.typography.bodySmall,
                                    modifier = Modifier.weight(1f),
                                    color = MaterialTheme.colorScheme.onSurface
                                )
                                IconButton(
                                    onClick = { onToggleFavorite(person.id, !person.isFavorite) },
                                    modifier = Modifier.minimumInteractiveComponentSize()
                                ) {
                                    Icon(
                                        imageVector = if (person.isFavorite) Icons.Filled.Star else Icons.Outlined.StarBorder,
                                        contentDescription = if (person.isFavorite) "Unfavorite" else "Favorite",
                                        tint = if (person.isFavorite) Color(0xFFFFD166) else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.35f),
                                        modifier = Modifier.size(16.dp)
                                    )
                                }
                                IconButton(
                                    onClick = { onRemoveContact(person.id) },
                                    modifier = Modifier.minimumInteractiveComponentSize()
                                ) {
                                    Icon(
                                        imageVector = Icons.Filled.Delete,
                                        contentDescription = "Remove contact",
                                        tint = MaterialTheme.colorScheme.error.copy(alpha = 0.6f),
                                        modifier = Modifier.size(14.dp)
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        if (showAddContactDialog) {
            AddContactToZoneDialog(
                zoneName = zone.displayName,
                hazeState = hazeState,
                onDismiss = { showAddContactDialog = false },
                onConfirm = { name ->
                    onAddContact(name)
                    showAddContactDialog = false
                }
            )
        }

        // Liquid-glass options sheet: transparent container so the menu's own surface doesn't
        // paint over the frosted tint, with the glass tint + refraction + border supplied by
        // liquidGlass() to match the rest of the app's chrome instead of a flat Material popup.
        DropdownMenu(
            expanded = menuExpanded,
            onDismissRequest = onDismissMenu,
            shape = RoundedCornerShape(22.dp),
            containerColor = Color.Transparent,
            tonalElevation = 0.dp,
            shadowElevation = 0.dp,
            border = null,
            // blur = false: the menu lives in its own popup window, where Haze would sample the
            // backdrop at the wrong coordinates. The translucent tint + border still reads as glass
            // and keeps the menu text legible over whatever sits behind the popup.
            modifier = Modifier.liquidGlass(
                hazeState = hazeState,
                shape = RoundedCornerShape(22.dp),
                tintColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.82f),
                borderColor = Color.White.copy(alpha = 0.25f),
                blur = false
            )
        ) {
            DropdownMenuItem(
                text = { Text(if (zone.isFavorite) "Remove from Favorites" else "Add to Favorites") },
                onClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onToggleZoneFavorite(!zone.isFavorite)
                    onDismissMenu()
                },
                leadingIcon = {
                    Icon(
                        imageVector = if (zone.isFavorite) Icons.Filled.Star else Icons.Outlined.StarBorder,
                        contentDescription = null,
                        tint = Color(0xFFFFD166)
                    )
                }
            )
            DropdownMenuItem(
                text = { Text("Add contact to ${zone.displayName}") },
                onClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    showAddContactDialog = true
                    onDismissMenu()
                },
                leadingIcon = { Icon(Icons.Filled.PersonAdd, contentDescription = null) }
            )
            DropdownMenuItem(
                text = { Text("Set as My Home Zone") },
                onClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onSetHome()
                    onDismissMenu()
                },
                leadingIcon = {
                    Icon(Icons.Filled.Home, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                }
            )
            DropdownMenuItem(
                text = { Text("Move Up in Watchlist") },
                onClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onMoveUp()
                    onDismissMenu()
                },
                enabled = !isFirst,
                leadingIcon = {
                    Icon(Icons.Filled.ArrowUpward, contentDescription = null)
                }
            )
            DropdownMenuItem(
                text = { Text("Move Down in Watchlist") },
                onClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onMoveDown()
                    onDismissMenu()
                },
                enabled = !isLast,
                leadingIcon = {
                    Icon(Icons.Filled.ArrowDownward, contentDescription = null)
                }
            )
            DropdownMenuItem(
                text = { Text("Remove from Watchlist") },
                onClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onDelete()
                    onDismissMenu()
                },
                leadingIcon = {
                    Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                }
            )
        }
    }
}

@Composable
internal fun AddContactToZoneDialog(
    zoneName: String,
    hazeState: HazeState,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
) {
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    var name by remember { mutableStateOf("") }

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
                    cursor.getString(0)?.takeIf { it.isNotBlank() }?.let { name = it }
                }
            }
        }
    }
    val readContactsPermLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> if (granted) contactPickerLauncher.launch(null) }

    GlassFormBottomSheet(
        onDismissRequest = onDismiss,
        hazeState = hazeState,
        title = { Text("Add contact to $zoneName") },
        confirmButton = {
            TextButton(
                enabled = name.isNotBlank(),
                onClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onConfirm(name.trim())
                }
            ) { Text("Add") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
        content = {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Name") },
                singleLine = true,
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
                            Icons.Filled.Person,
                            contentDescription = "Pick from contacts",
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }
            )
        },
    )
}
