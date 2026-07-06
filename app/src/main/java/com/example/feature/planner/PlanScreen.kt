package com.example.feature.planner

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.core.content.ContextCompat
import dev.chrisbanes.haze.HazeState
import com.example.core.designsystem.EmptyStateCard
import com.example.core.designsystem.LocalTabBarInsetHeight
import com.example.core.designsystem.Motion
import com.example.core.designsystem.LiquidGlassSurface
import com.example.core.designsystem.liquidGlass
import com.example.core.designsystem.MeridianWordmark
import com.example.core.designsystem.reportBarScroll
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import com.example.MainViewModel
import com.example.core.data.Person
import com.example.core.data.SavedZone
import com.example.core.designsystem.rememberIs24Hour
import kotlinx.datetime.toJavaInstant
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime

@Composable
fun PlanScreen(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier,
    hazeState: HazeState = remember { HazeState() },
    onNavigate: (String) -> Unit = {},
) {
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val density = LocalDensity.current
    val savedZones by viewModel.savedZones.collectAsStateWithLifecycle()
    val people by viewModel.people.collectAsStateWithLifecycle()
    val plannedTasks by viewModel.plannedTasks.collectAsStateWithLifecycle()
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val calendarEvents by viewModel.calendarEvents.collectAsStateWithLifecycle()
    val is24Hour = rememberIs24Hour(settings)

    val localZoneId = remember { ZoneId.systemDefault().id }
    val localLocationName = remember(savedZones, localZoneId) {
        localLocationLabel(savedZones, localZoneId)
    }

    var calendarPermissionGranted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR)
                == PackageManager.PERMISSION_GRANTED
        )
    }
    val calendarPermLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        calendarPermissionGranted = granted
    }

    val plannerPool = remember(savedZones, people, localZoneId) {
        plannerParticipantPool(savedZones, people, localZoneId)
    }
    val locationGroups = remember(plannerPool) {
        visiblePlannerGroups(
            buildParticipantLocationGroups(plannerPool.zones, plannerPool.people),
            localZoneId,
        )
    }

    // Selection state lives at the screen; defaults favorites to participating.
    val selected = rememberZoneSelection(plannerPool.zones)
    val selectedPeople = rememberPersonSelection(plannerPool.people)
    var durationMinutes by remember { mutableStateOf(45) }
    var selectedDateMillis by remember { mutableStateOf(todayUtcMidnightMillis()) }
    var selectedSlotInstant by remember { mutableStateOf<Instant?>(null) }
    var meetingTitle by remember { mutableStateOf("Meridian sync") }
    var excludeWeekends by remember { mutableStateOf(false) }
    var showJumpModal by remember { mutableStateOf(false) }

    val baseInstant = remember(selectedDateMillis, localZoneId) {
        startOfDayInstant(selectedDateMillis, localZoneId)
    }
    val participants by remember(locationGroups, localZoneId) {
        derivedStateOf { buildMeetingParticipants(localZoneId, locationGroups, selected, selectedPeople) }
    }
    val participantLabels by remember(locationGroups, localZoneId, localLocationName) {
        derivedStateOf { buildSelectedParticipantLabels(localZoneId, localLocationName, locationGroups, selected, selectedPeople) }
    }
    // All 24 hourly slots, ranked (fairest first) — drives the best-pick default and rotating series.
    val allSlots = remember(participants, baseInstant) {
        viewModel.computeMeetingSlots(participants, baseInstant)
    }
    val rankedSlots = remember(allSlots, excludeWeekends) {
        if (excludeWeekends) allSlots.filterNot(::isWeekendSlot) else allSlots
    }
    // Same 24 slots in chronological order for the dial; weekend-filtered hours become null bands.
    val dialHours = remember(allSlots, excludeWeekends) {
        allSlots.sortedBy { it.utcStartInstant }.map { slot ->
            val blocked = excludeWeekends && isWeekendSlot(slot)
            DialHour(
                instant = slot.utcStartInstant.toJavaInstant(),
                slot = if (blocked) null else slot,
                ratingLabel = if (blocked) null else slot.ratingLabel,
            )
        }
    }
    val defaultSlotInstant = rankedSlots.firstOrNull()?.utcStartInstant?.toJavaInstant()
    // Reset the selection to the fairest hour whenever dialHours changes (defaultSlotInstant is derived from dialHours).
    LaunchedEffect(dialHours) {
        val cur = selectedSlotInstant
        val valid = cur != null && dialHours.any { it.instant == cur && it.slot != null }
        if (!valid) selectedSlotInstant = defaultSlotInstant
    }
    val selectedIndex = dialHours.indexOfFirst { it.instant == selectedSlotInstant }
        .let { if (it >= 0) it else dialHours.indexOfFirst { h -> h.slot != null }.coerceAtLeast(0) }
    val selectedSlot = dialHours.getOrNull(selectedIndex)?.slot

    val listState = rememberLazyListState()

    // Pinned-dial behavior mirrors the World screen: hide on scroll-down, reveal on scroll-up.
    var dialVisible by remember { mutableStateOf(true) }
    var prevIndex by remember { mutableIntStateOf(0) }
    var prevOffset by remember { mutableIntStateOf(0) }
    LaunchedEffect(listState) {
        snapshotFlow { listState.firstVisibleItemIndex to listState.firstVisibleItemScrollOffset }
            .collect { (index, offset) ->
                dialVisible = when {
                    index == 0 && offset < 8 -> true
                    index < prevIndex || (index == prevIndex && offset < prevOffset) -> true
                    index > prevIndex || (index == prevIndex && offset > prevOffset) -> false
                    else -> dialVisible
                }
                prevIndex = index
                prevOffset = offset
            }
    }

    val wideLayout = LocalConfiguration.current.screenWidthDp >= 600
    val tabBarInset = LocalTabBarInsetHeight.current
    val dialBottomPadding by animateDpAsState(
        targetValue = if (wideLayout) 24.dp else tabBarInset,
        animationSpec = Motion.smooth(),
        label = "planDialBottomPadding"
    )

    // Measured height of the pinned dial (collapsed pill vs. expanded panel, and it grows with
    // Dynamic Type). Drives the list's bottom spacer so the last rows always clear the dial +
    // nav bar instead of relying on a fixed 240dp guess. Falls back to a sensible default
    // until the first measurement lands.
    var measuredDialHeight by remember { mutableStateOf(120.dp) }
    val listBottomClearance by animateDpAsState(
        targetValue = measuredDialHeight + dialBottomPadding + 24.dp,
        animationSpec = Motion.smooth(),
        label = "planListBottomClearance"
    )

    val lifecycleOwner = LocalLifecycleOwner.current
    LaunchedEffect(lifecycleOwner) {
        snapshotFlow { lifecycleOwner.lifecycle.currentState }
            .collect { state ->
                if (state == Lifecycle.State.RESUMED) {
                    calendarPermissionGranted = ContextCompat.checkSelfPermission(
                        context, Manifest.permission.READ_CALENDAR
                    ) == PackageManager.PERMISSION_GRANTED
                }
            }
    }

    LaunchedEffect(selectedDateMillis, calendarPermissionGranted) {
        if (calendarPermissionGranted) {
            val from = startOfDayInstant(selectedDateMillis, localZoneId)
            val to = ZonedDateTime.ofInstant(from, ZoneId.of(localZoneId)).plusDays(7).toInstant()
            viewModel.loadCalendarEvents(from.toEpochMilli(), to.toEpochMilli())
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
    LazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            // Clear the status bar with the real inset instead of a fixed top spacer.
            .statusBarsPadding()
            // Keep the "Meeting Title" field clear of the keyboard, matching the World Clock screen.
            .imePadding()
            .reportBarScroll()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            MeridianWordmark(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp, bottom = 8.dp)
            )
        }
        item {
            // Expose the screen title as a TalkBack heading so this long list is navigable by
            // headings, matching every SectionLabel below (which SectionHeader already marks).
            Box(modifier = Modifier.semantics(mergeDescendants = true) { heading() }) {
                PlannerHeader()
            }
        }
        item {
            LiquidGlassSurface(hazeState = hazeState, modifier = Modifier.fillMaxWidth()) {
            DetailsCard(
                modifier = Modifier.fillMaxWidth(),
                title = meetingTitle,
                onTitleChange = { meetingTitle = it }
            )
            }
        }
        item {
            LiquidGlassSurface(hazeState = hazeState, modifier = Modifier.fillMaxWidth()) {
            ParticipantsCard(
                modifier = Modifier.fillMaxWidth(),
                hazeState = hazeState,
                locationGroups = locationGroups,
                localZoneId = localZoneId,
                localLocationName = localLocationName,
                selectedZones = selected,
                people = plannerPool.people,
                selectedPeople = selectedPeople,
                onAddPerson = { p ->
                    viewModel.addPerson(
                        p.name,
                        p.zoneId,
                        p.locationName,
                        p.workStartHour,
                        p.workEndHour,
                        p.dndStartHour,
                        p.dndEndHour,
                        isFavorite = true,
                    )
                },
                onAddZone = { zone ->
                    viewModel.addZone(zone.copy(isFavorite = true))
                },
                onDeletePerson = viewModel::deletePerson,
                searchZones = viewModel::searchTimeZones,
                defaultWorkStart = settings.defaultWorkStartHour,
                defaultWorkEnd = settings.defaultWorkEndHour,
            )
            }
        }
        item {
            LiquidGlassSurface(hazeState = hazeState, modifier = Modifier.fillMaxWidth()) {
            WindowCard(
                modifier = Modifier.fillMaxWidth(),
                hazeState = hazeState,
                selectedDateMillis = selectedDateMillis,
                durationMinutes = durationMinutes,
                excludeWeekends = excludeWeekends,
                onDateChange = { selectedDateMillis = it },
                onDurationChange = { durationMinutes = it },
                onExcludeWeekendsChange = { excludeWeekends = it },
                onJumpClick = { showJumpModal = true }
            )
            }
        }
        // No SectionLabel here: CalendarEventsCard renders its own "Your Calendar" CardHeader,
        // so a section label above it would duplicate the title back-to-back. This mirrors how
        // FAIR SLOTS' SlotCard carries no redundant title under its section label.
        item {
            LiquidGlassSurface(hazeState = hazeState, modifier = Modifier.fillMaxWidth()) {
            CalendarEventsCard(
                modifier = Modifier.fillMaxWidth(),
                events = calendarEvents,
                hasPermission = calendarPermissionGranted,
                is24Hour = is24Hour,
                onRequestPermission = {
                    calendarPermLauncher.launch(Manifest.permission.READ_CALENDAR)
                },
            )
            }
        }
        item { SectionLabel("FAIR SLOTS", "Scrub the dial to explore every hour — bands mark the fair ones.") }

        if (rankedSlots.isEmpty()) {
            item {
                val isWeekend = remember(selectedDateMillis) {
                    val dow = Instant.ofEpochMilli(selectedDateMillis).atZone(ZoneOffset.UTC).dayOfWeek
                    dow == DayOfWeek.SATURDAY || dow == DayOfWeek.SUNDAY
                }
                val emptyHint = when {
                    excludeWeekends && isWeekend ->
                        "Weekends are excluded and this is a weekend. Pick a weekday or turn off the filter."
                    excludeWeekends ->
                        "Every workable hour falls in someone's sleep window. Try another date, fewer zones, or turn off the weekends filter."
                    else ->
                        "Every hour lands in someone's sleep window. Try another date or fewer zones."
                }
                LiquidGlassSurface(hazeState = hazeState, modifier = Modifier.fillMaxWidth()) {
                SlotsEmptyState(
                    modifier = Modifier.fillMaxWidth(),
                    hint = emptyHint,
                    actionLabel = "Pick another day",
                    onAction = { showJumpModal = true },
                )
                }
            }
        } else {
            selectedSlot?.let { slot ->
                item {
                    LiquidGlassSurface(hazeState = hazeState, modifier = Modifier.fillMaxWidth()) {
                    SlotCard(
                        modifier = Modifier.fillMaxWidth(),
                        slot = slot,
                        localZoneId = localZoneId,
                        localLocationName = localLocationName,
                        durationMinutes = durationMinutes,
                        is24Hour = is24Hour,
                        participantLabels = participantLabels,
                        expanded = true,
                        meetingTitle = meetingTitle,
                        onToggle = {},
                        interactive = false,
                    )
                    }
                }
            }
            item {
                OutlinedButton(
                    onClick = {
                        // Consequential action → a LongPress confirms the tap physically, matching
                        // the duration chips in WindowCard (north-star: springy/haptic feedback).
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        viewModel.createRotatingSeries(rankedSlots, 4, localZoneId)
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .semantics(mergeDescendants = true) {},
                ) {
                    Icon(Icons.Default.Repeat, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Create rotating weekly series (4 weeks)")
                }
            }
        }

        if (plannedTasks.isEmpty()) {
            item {
                SectionLabel("YOUR PLAN", "Events from Quick Schedule and the AI assistant.")
            }
            item {
                EmptyStateCard(
                    icon = Icons.Default.Event,
                    title = "Nothing scheduled yet",
                    message = "Save a fair slot above, use Quick Schedule in AI, or ask the assistant to plan a meeting.",
                    hazeState = hazeState,
                    actionLabel = "Ask AI",
                    onAction = { onNavigate("ai") },
                )
            }
        } else {
            item { SectionLabel("YOUR PLAN  (${plannedTasks.size})", "Events from Quick Schedule and the AI assistant.") }
            items(plannedTasks, key = { it.id }) { task ->
                PlannedTaskRow(
                    modifier = Modifier
                        .animateItem()
                        // Repeated planned-task row → lightweight glass (no per-row backdrop blur).
                        .liquidGlass(hazeState, blur = false),
                    task = task,
                    is24Hour = is24Hour,
                    onDelete = { viewModel.deleteTask(task.id) },
                )
            }
        }

        item {
            // Leave room so the last rows clear the pinned dial and the nav bar. Derived from the
            // measured dial height (which grows with Dynamic Type and shrinks to a pill when
            // collapsed) plus its bottom padding — not a fixed 240dp guess that over/under-shoots.
            val bottomClearance = if (rankedSlots.isNotEmpty()) listBottomClearance else tabBarInset
            Spacer(Modifier.height(bottomClearance))
        }
    }

    // Fair-time dial — pinned above the nav bar (like the World screen) so it stays reachable
    // while the planner scrolls underneath. Slides away on scroll-down.
    if (rankedSlots.isNotEmpty()) {
        AnimatedVisibility(
            visible = dialVisible,
            enter = slideInVertically(Motion.bouncy()) { it } + fadeIn(),
            exit = slideOutVertically(Motion.smooth()) { it } + fadeOut(),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(start = 16.dp, end = 16.dp, bottom = dialBottomPadding)
                .then(if (wideLayout) Modifier.widthIn(max = 520.dp) else Modifier)
                // Feed the real dial height back to the list's bottom clearance so the last rows
                // clear the collapsed pill (short) or the expanded panel (tall, taller at large
                // font scales) exactly, without a hardcoded spacer.
                .onSizeChanged { size ->
                    if (size.height > 0) {
                        val h = with(density) { size.height.toDp() }
                        if (h != measuredDialHeight) measuredDialHeight = h
                    }
                }
        ) {
            FairSlotsScrubber(
                hours = dialHours,
                selectedIndex = selectedIndex,
                localZoneId = localZoneId,
                durationMinutes = durationMinutes,
                is24Hour = is24Hour,
                hazeState = hazeState,
                onSelect = { idx -> selectedSlotInstant = dialHours.getOrNull(idx)?.instant },
            )
        }
    }
    }

    if (showJumpModal) {
        JumpToPlaceDateTimeModal(
            localZoneId = localZoneId,
            localLocationName = localLocationName,
            savedZones = savedZones,
            searchZones = viewModel::searchTimeZones,
            is24Hour = is24Hour,
            hazeState = hazeState,
            onDismiss = { showJumpModal = false },
            onJump = { targetInstant, zoneId ->
                val localZdt = ZonedDateTime.ofInstant(targetInstant, ZoneId.of(localZoneId))
                val localDate = localZdt.toLocalDate()
                val newSelectedDateMillis = localDate.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
                selectedDateMillis = newSelectedDateMillis
                selectedSlotInstant = targetInstant.truncatedTo(java.time.temporal.ChronoUnit.HOURS)
                showJumpModal = false
            }
        )
    }
}

@Composable
private fun rememberZoneSelection(savedZones: List<SavedZone>): SnapshotStateMap<String, Boolean> {
    val selection = remember { mutableStateMapOf<String, Boolean>() }
    val zoneIds = savedZones.map { it.id }.toSet()
    selection.keys.toList().forEach { id -> if (id !in zoneIds) selection.remove(id) }
    savedZones.forEach { zone -> if (zone.id !in selection) selection[zone.id] = true }
    return selection
}

@Composable
private fun rememberPersonSelection(people: List<Person>): SnapshotStateMap<Int, Boolean> {
    val selection = remember { mutableStateMapOf<Int, Boolean>() }
    val personIds = people.map { it.id }.toSet()
    selection.keys.toList().forEach { id -> if (id !in personIds) selection.remove(id) }
    people.forEach { person -> if (person.id !in selection) selection[person.id] = true }
    return selection
}

/** True if the slot lands on a Saturday or Sunday in any participating zone. */
private fun isWeekendSlot(slot: com.example.core.time.FindOverlapUseCase.OverlapSlot): Boolean {
    val javaInstant = slot.utcStartInstant.toJavaInstant()
    return slot.localHours.keys.any { zoneId ->
        val dow = ZonedDateTime.ofInstant(javaInstant, ZoneId.of(zoneId)).dayOfWeek
        dow == DayOfWeek.SATURDAY || dow == DayOfWeek.SUNDAY
    }
}

private fun todayUtcMidnightMillis(): Long =
    ZonedDateTime.now(ZoneId.systemDefault()).toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()

private fun startOfDayInstant(utcMidnightMillis: Long, localZoneId: String): Instant {
    val date = Instant.ofEpochMilli(utcMidnightMillis).atZone(ZoneOffset.UTC).toLocalDate()
    return date.atStartOfDay(ZoneId.of(localZoneId)).toInstant()
}


