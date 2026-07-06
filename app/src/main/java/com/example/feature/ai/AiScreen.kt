package com.example.feature.ai

import android.widget.Toast
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.WbTwilight
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import com.example.ChatMessage
import com.example.core.ai.AiProvenance
import com.example.MainViewModel
import com.example.core.data.PlannedTask
import com.example.core.data.SavedZone
import com.example.core.designsystem.GlassDatePickerSheet
import com.example.core.designsystem.GlassDefaults
import com.example.core.designsystem.GlassTimePickerSheet
import com.example.core.designsystem.LocalReduceMotion
import com.example.core.designsystem.Motion
import com.example.core.designsystem.SectionHeader
import com.example.core.designsystem.LiquidGlassSurface
import com.example.core.designsystem.liquidGlass
import com.example.core.designsystem.rememberIs24Hour
import com.example.core.designsystem.transparentCardColors
import com.example.core.designsystem.LocalTabBarInsetHeight
import com.example.core.designsystem.reportBarScroll
import com.example.core.time.TimeFormats
import com.example.feature.calendar.DEFAULT_EVENT_DURATION_MINUTES
import com.example.feature.calendar.EventActionResult
import com.example.feature.calendar.insertCalendarEvent
import com.example.feature.calendar.shareEventIcs
import com.example.ui.components.ZoneSearchPicker
import dev.chrisbanes.haze.HazeState
import kotlinx.coroutines.delay
import java.time.Duration
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime

// Curated prompts that seed the conversation; tapping one sends it straight to the model.
private val SUGGESTIONS = listOf(
    "What time is it in Tokyo right now?",
    "Schedule a call with London next Monday at 2 PM",
    "Best meeting time for New York, Berlin, and Singapore?",
    "Convert 9 AM Sydney time to my local time",
)

@Composable
fun AiScreen(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier,
    hazeState: HazeState = remember { HazeState() }
) {
    val chatMessages by viewModel.chatMessages.collectAsStateWithLifecycle()
    val aiLoading by viewModel.aiLoading.collectAsStateWithLifecycle()
    val aiPartialText by viewModel.aiPartialText.collectAsStateWithLifecycle()
    val pendingDraft by viewModel.pendingDraft.collectAsStateWithLifecycle()
    val savedZones by viewModel.savedZones.collectAsStateWithLifecycle()
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val is24Hour = rememberIs24Hour(settings)
    val haptics = LocalHapticFeedback.current

    var inputText by remember { mutableStateOf("") }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val reduceMotion = LocalReduceMotion.current

    // Auto-scroll to the freshest message as the conversation grows, but leave the scheduler
    // visible on first load (only the welcome message exists then). Honor reduce-motion by
    // jumping instantly instead of animating.
    LaunchedEffect(chatMessages.size, aiLoading, aiPartialText, pendingDraft) {
        if (chatMessages.size > 1 || aiLoading) {
            val count = listState.layoutInfo.totalItemsCount
            if (count > 0) {
                if (reduceMotion) listState.scrollToItem(count - 1)
                else listState.animateScrollToItem(count - 1)
            }
        }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
    ) {
        AssistantHeader(
            canClear = chatMessages.size > 1,
            onClear = {
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                viewModel.clearChat()
            }
        )

        Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
        LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .reportBarScroll()
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Interactive quick-scheduler — the model never has to be involved to add an event.
            item {
                QuickScheduleCard(
                    savedZones = savedZones.map { it.id to it.displayName },
                    is24Hour = is24Hour,
                    hazeState = hazeState,
                    searchZones = viewModel::searchTimeZones,
                    onAdd = { task -> viewModel.addTask(task) },
                )
            }

            // Tap-to-ask prompt starters.
            item {
                SectionHeader(
                    title = "TRY ASKING",
                    icon = Icons.Default.Bolt,
                    modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                )
                Spacer(Modifier.height(8.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    SUGGESTIONS.forEach { prompt ->
                        AssistChip(
                            onClick = {
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                viewModel.sendAiMessage(prompt)
                            },
                            label = { Text(prompt) },
                            leadingIcon = {
                                Icon(
                                    imageVector = Icons.Default.AutoAwesome,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp),
                                )
                            },
                            colors = AssistChipDefaults.assistChipColors(
                                labelColor = MaterialTheme.colorScheme.onSurface,
                                leadingIconContentColor = MaterialTheme.colorScheme.primary,
                            ),
                            // Announce as an actionable prompt suggestion for TalkBack.
                            modifier = Modifier.semantics {
                                role = Role.Button
                                contentDescription = "Ask: $prompt"
                            },
                        )
                    }
                }
            }

            item {
                SectionHeader(
                    title = "CONVERSATION",
                    icon = Icons.Default.AutoAwesome,
                    modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                )
            }

            items(chatMessages, key = { it.id }) { message ->
                val isError = message.sender == "System Error"
                Bubble(
                    message = message,
                    hazeState = hazeState,
                    onRetry = if (isError) {{ viewModel.retryAiMessage(message.id) }} else null,
                    // Springy per-message entrance so replies settle into place.
                    modifier = Modifier.animateItem(
                        fadeInSpec = Motion.smooth(),
                        placementSpec = Motion.smooth(),
                        fadeOutSpec = Motion.smooth(),
                    ),
                )
            }

            item {
                // Thinking/streaming indicator. Springy entrance to match message appear;
                // a polite live region lets TalkBack announce that the assistant is working.
                Column(
                    modifier = Modifier.semantics {
                        liveRegion = LiveRegionMode.Polite
                        if (aiLoading) contentDescription = "Assistant is thinking"
                    }
                ) {
                    AnimatedVisibility(
                        visible = aiLoading,
                        enter = fadeIn(Motion.smooth()) +
                            expandVertically(Motion.smooth()) +
                            slideInVertically(Motion.bouncy()) { it / 2 },
                        exit = fadeOut(Motion.snappy()) + shrinkVertically(Motion.smooth())
                    ) {
                        if (aiPartialText != null) {
                            StreamingPartialBubble(text = aiPartialText!!, hazeState = hazeState)
                        } else {
                            TypingIndicator(hazeState = hazeState)
                        }
                    }
                }
            }

            // Confirm-before-write card for a model-proposed event (§12.8).
            pendingDraft?.let { draft ->
                item(key = "draft_confirm") {
                    Box(modifier = Modifier.animateItem()) {
                        DraftConfirmCard(
                            draft = draft,
                            is24Hour = is24Hour,
                            hazeState = hazeState,
                            onConfirm = { viewModel.confirmDraft() },
                            onDiscard = { viewModel.discardDraft() },
                        )
                    }
                }
            }

            item { Spacer(Modifier.height(8.dp)) }
        }

            // Jump-to-latest affordance once the newest messages scroll out of view.
            val showScrollDown by remember { derivedStateOf { listState.canScrollForward } }
            Column(modifier = Modifier.align(Alignment.BottomEnd)) {
                AnimatedVisibility(
                    visible = showScrollDown,
                    enter = fadeIn(Motion.smooth()) + scaleIn(Motion.bouncy(), initialScale = 0.8f),
                    exit = fadeOut(Motion.snappy()) + scaleOut(Motion.snappy(), targetScale = 0.8f),
                ) {
                    FilledTonalIconButton(
                        onClick = {
                            scope.launch {
                                val count = listState.layoutInfo.totalItemsCount
                                if (count > 0) {
                                    if (reduceMotion) listState.scrollToItem(count - 1)
                                    else listState.animateScrollToItem(count - 1)
                                }
                            }
                        },
                        modifier = Modifier.padding(16.dp)
                    ) {
                        Icon(Icons.Default.KeyboardArrowDown, contentDescription = "Scroll to latest message")
                    }
                }
            }
        }

        // Chat composer, lifted clear of the floating glass nav bar at the bottom.
        ChatComposer(
            value = inputText,
            onValueChange = { inputText = it },
            isLoading = aiLoading,
            onSend = {
                if (inputText.isNotBlank()) {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    viewModel.sendAiMessage(inputText)
                    inputText = ""
                }
            }
        )
    }
}

@Composable
private fun AssistantHeader(
    canClear: Boolean,
    onClear: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(
                    Brush.linearGradient(
                        listOf(
                            MaterialTheme.colorScheme.primary,
                            MaterialTheme.colorScheme.tertiary
                        )
                    )
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.AutoAwesome,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onPrimary,
                modifier = Modifier.size(22.dp)
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(
            // Read the title + subtitle as one node so TalkBack lands on the assistant identity once.
            modifier = Modifier.weight(1f).semantics(mergeDescendants = true) {}
        ) {
            Text(
                text = "Meridian Assistant",
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onBackground,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = "Schedule across zones · ask anything about time",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.7f)
            )
        }
        AnimatedVisibility(
            visible = canClear,
            enter = fadeIn(Motion.smooth()) + scaleIn(Motion.bouncy(), initialScale = 0.8f),
            exit = fadeOut(Motion.snappy()) + scaleOut(Motion.snappy(), targetScale = 0.8f),
        ) {
            IconButton(onClick = onClear) {
                Icon(
                    imageVector = Icons.Default.DeleteSweep,
                    contentDescription = "Clear conversation",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun QuickScheduleCard(
    savedZones: List<Pair<String, String>>,
    is24Hour: Boolean,
    hazeState: HazeState,
    searchZones: suspend (String) -> List<SavedZone>,
    onAdd: (PlannedTask) -> Unit,
) {
    val localZoneId = remember { ZoneId.systemDefault().id }
    val nowZdt = ZonedDateTime.now()
    val haptics = LocalHapticFeedback.current

    var expanded by remember { mutableStateOf(true) }
    var title by remember { mutableStateOf("") }
    var selectedDate by remember { mutableStateOf(nowZdt.toLocalDate()) }
    var selectedHour by remember { mutableIntStateOf((nowZdt.hour + 1) % 24) }
    var selectedMinute by remember { mutableIntStateOf(0) }
    var selectedZoneId by remember { mutableStateOf(localZoneId) }
    var selectedZoneLabel by remember { mutableStateOf("Local") }
    var showDatePicker by remember { mutableStateOf(false) }
    var showTimePicker by remember { mutableStateOf(false) }
    var addedFlash by remember { mutableStateOf(false) }

    LaunchedEffect(addedFlash) {
        if (addedFlash) {
            delay(2200)
            addedFlash = false
        }
    }

    // Apply a relative shortcut (in local time) to the date/time/zone selectors at once.
    fun applyPreset(target: ZonedDateTime) {
        selectedDate = target.toLocalDate()
        selectedHour = target.hour
        selectedMinute = target.minute
        selectedZoneId = localZoneId
        selectedZoneLabel = "Local"
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
    }

    // Local zone first, then any saved zones (de-duplicated against local).
    val zoneOptions = remember(savedZones, localZoneId) {
        buildList {
            add(localZoneId to "Local")
            savedZones.forEach { (id, name) -> if (id != localZoneId) add(id to name) }
        }
    }

    val targetInstant = remember(selectedDate, selectedHour, selectedMinute, selectedZoneId) {
        selectedDate.atTime(selectedHour, selectedMinute)
            .atZone(ZoneId.of(selectedZoneId))
            .toInstant()
    }
    val timeLabel = remember(selectedHour, selectedMinute, is24Hour) {
        LocalTime.of(selectedHour, selectedMinute).format(TimeFormats.hourMinute(is24Hour))
    }
    val dateLabel = remember(selectedDate) { selectedDate.format(TimeFormats.mediumDate()) }
    val now = Instant.now()
    val relative = relativeTime(targetInstant, now)
    val isPast = targetInstant.isBefore(now)

    // A time-of-day glyph for the chosen hour, consistent with the app's solar theme.
    val todIcon = when (selectedHour) {
        in 5..10 -> Icons.Default.WbTwilight
        in 11..16 -> Icons.Default.WbSunny
        in 17..20 -> Icons.Default.WbTwilight
        else -> Icons.Default.Bedtime
    }

    // When scheduling in another zone, show what that lands at in the user's own time.
    val localEquivalent = remember(targetInstant, selectedZoneId, localZoneId, is24Hour) {
        if (selectedZoneId == localZoneId) null else {
            val local = ZonedDateTime.ofInstant(targetInstant, ZoneId.of(localZoneId))
            "${local.format(TimeFormats.mediumDate())} · ${local.format(TimeFormats.hourMinute(is24Hour))} your time"
        }
    }

    LiquidGlassSurface(
        hazeState = hazeState,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Header doubles as the collapse toggle so the card can fold away to focus on chat.
            val chevronRotation by animateFloatAsState(if (expanded) 180f else 0f, label = "chevron")
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .clickable { expanded = !expanded },
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.Schedule,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    text = "Quick schedule",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f)
                )
                Icon(
                    imageVector = Icons.Default.ExpandMore,
                    contentDescription = if (expanded) "Collapse" else "Expand",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.rotate(chevronRotation)
                )
            }

            AnimatedVisibility(
                visible = expanded,
                enter = fadeIn() + expandVertically(),
                exit = fadeOut() + shrinkVertically()
            ) {
                Column {
                    Spacer(Modifier.height(12.dp))
                    OutlinedTextField(
                        value = title,
                        onValueChange = { title = it },
                        placeholder = { Text("Event title") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        shape = RoundedCornerShape(16.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = MaterialTheme.colorScheme.onSurface,
                            unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
                            focusedBorderColor = MaterialTheme.colorScheme.primary,
                            unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                        )
                    )

                    // One-tap relative shortcuts.
                    Spacer(Modifier.height(12.dp))
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        PresetChip("In 1 hr") { applyPreset(ZonedDateTime.now().plusHours(1).withMinute(0)) }
                        PresetChip("Tonight 8 PM") { applyPreset(ZonedDateTime.now().withHour(20).withMinute(0)) }
                        PresetChip("Tomorrow 9 AM") { applyPreset(ZonedDateTime.now().plusDays(1).withHour(9).withMinute(0)) }
                        PresetChip("Next week") { applyPreset(ZonedDateTime.now().plusWeeks(1).withHour(9).withMinute(0)) }
                    }

                    Spacer(Modifier.height(12.dp))
                    Row(
                        modifier = Modifier
                            .fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        SelectorButton(
                            icon = Icons.Default.CalendarMonth,
                            label = dateLabel,
                            onClick = { showDatePicker = true },
                            modifier = Modifier.weight(1f)
                        )
                        SelectorButton(
                            icon = Icons.Default.Schedule,
                            label = timeLabel,
                            onClick = { showTimePicker = true },
                            modifier = Modifier.weight(1f)
                        )
                    }

                    Spacer(Modifier.height(12.dp))
                    Text(
                        text = "Time zone",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                    )
                    Spacer(Modifier.height(8.dp))
                    ZoneSearchPicker(
                        localZoneId = localZoneId,
                        quickZones = zoneOptions,
                        selectedZoneId = selectedZoneId,
                        selectedZoneLabel = selectedZoneLabel,
                        onZoneSelected = { id, label ->
                            selectedZoneId = id
                            selectedZoneLabel = label
                        },
                        searchZones = searchZones,
                        is24Hour = is24Hour,
                    )

                    Spacer(Modifier.height(16.dp))
                    // Live preview of exactly what will be added.
                    LiquidGlassSurface(
                        hazeState = hazeState,
                        modifier = Modifier.fillMaxWidth(),
                        tintColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.25f),
                        shape = RoundedCornerShape(14.dp),
                    ) {
                        Column(modifier = Modifier.padding(14.dp)) {
                            Text(
                                text = title.ifBlank { "Untitled event" },
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                            Spacer(Modifier.height(2.dp))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(
                                    imageVector = todIcon,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                                    modifier = Modifier.size(14.dp)
                                )
                                Spacer(Modifier.width(4.dp))
                                Text(
                                    text = "$dateLabel · $timeLabel · $selectedZoneLabel — $relative",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
                                )
                            }
                            if (localEquivalent != null) {
                                Spacer(Modifier.height(2.dp))
                                Text(
                                    text = "= $localEquivalent",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.primary
                                )
                            }
                            if (isPast) {
                                Spacer(Modifier.height(4.dp))
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.ErrorOutline,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.error,
                                        modifier = Modifier.size(14.dp)
                                    )
                                    Text(
                                        text = "That time has already passed — pick a later time.",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.error
                                    )
                                }
                            }
                        }
                    }

                    Spacer(Modifier.height(12.dp))
                    Button(
                        onClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            onAdd(
                                PlannedTask(
                                    title = title.trim(),
                                    timestamp = targetInstant.toEpochMilli(),
                                    zoneId = selectedZoneId,
                                )
                            )
                            title = ""
                            addedFlash = true
                        },
                        enabled = title.isNotBlank() && !isPast,
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
                    ) {
                        if (addedFlash) {
                            Icon(Icons.Default.CheckCircle, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text("Added to your plan")
                        } else {
                            Text("Add to plan")
                        }
                    }
                }
            }
        }
    }

    if (showDatePicker) {
        val initialMillis = selectedDate.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        GlassDatePickerSheet(
            onDismissRequest = { showDatePicker = false },
            hazeState = hazeState,
            initialSelectedDateMillis = initialMillis,
            onConfirm = { millis ->
                selectedDate = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
                showDatePicker = false
            },
        )
    }

    if (showTimePicker) {
        GlassTimePickerSheet(
            onDismissRequest = { showTimePicker = false },
            hazeState = hazeState,
            initialHour = selectedHour,
            initialMinute = selectedMinute,
            is24Hour = is24Hour,
            onConfirm = { h, m ->
                selectedHour = h
                selectedMinute = m
                showTimePicker = false
            },
        )
    }
}

@Composable
private fun PresetChip(label: String, onClick: () -> Unit) {
    AssistChip(
        onClick = onClick,
        label = { Text(label) },
        leadingIcon = {
            Icon(Icons.Default.Bolt, contentDescription = null, modifier = Modifier.size(16.dp))
        },
        colors = AssistChipDefaults.assistChipColors(
            labelColor = MaterialTheme.colorScheme.onSurface,
            leadingIconContentColor = MaterialTheme.colorScheme.primary
        )
    )
}

@Composable
private fun SelectorButton(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier,
        shape = RoundedCornerShape(16.dp),
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Text(
            label,
            maxLines = 1,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false),
        )
    }
}

@Composable
private fun StreamingPartialBubble(text: String, hazeState: HazeState) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Bottom,
    ) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Default.AutoAwesome,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(16.dp),
            )
        }
        Spacer(Modifier.width(8.dp))
        LiquidGlassSurface(
            hazeState = hazeState,
            tintColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f),
            shape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp, bottomStart = 4.dp, bottomEnd = 16.dp),
        ) {
            ChatMarkdownText(
                text = text,
                textColor = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
            )
        }
    }
}

@Composable
private fun TypingIndicator(hazeState: HazeState) {
    val transition = rememberInfiniteTransition(label = "typing")
    Row(
        // Decorative dots convey "thinking" visually; the parent already announces it politely,
        // so keep this row out of the TalkBack tree to avoid duplicate chatter.
        modifier = Modifier.clearAndSetSemantics {},
        verticalAlignment = Alignment.Bottom
    ) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.AutoAwesome,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(16.dp)
            )
        }
        Spacer(Modifier.width(8.dp))
        LiquidGlassSurface(
            hazeState = hazeState,
            tintColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f),
            shape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp, bottomStart = 4.dp, bottomEnd = 16.dp),
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp)
            ) {
            repeat(3) { i ->
                val dotAlpha by transition.animateFloat(
                    initialValue = 0.3f,
                    targetValue = 1f,
                    animationSpec = infiniteRepeatable(
                        animation = tween(durationMillis = 600, delayMillis = i * 150),
                        repeatMode = RepeatMode.Reverse
                    ),
                    label = "dot$i"
                )
                Box(
                    modifier = Modifier
                        .size(8.dp)
                        .alpha(dotAlpha)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.onSurfaceVariant)
                )
            }
        }
        }
    }
}

@Composable
private fun ChatComposer(
    value: String,
    onValueChange: (String) -> Unit,
    isLoading: Boolean,
    onSend: () -> Unit,
) {
    val canSend = value.isNotBlank() && !isLoading
    val sendAlpha by animateFloatAsState(
        targetValue = if (canSend) 1f else 0.4f,
        animationSpec = Motion.smooth(),
        label = "sendAlpha",
    )
    // Send button gives a subtle spring-scale press feedback and pops when it becomes active.
    val sendScale by animateFloatAsState(
        targetValue = if (canSend) 1f else 0.9f,
        animationSpec = Motion.bouncy(),
        label = "sendScale",
    )
    // The floating glass nav bar (≈72dp pill + 16dp inset) only needs clearing while it is
    // visible; once the keyboard is up the bar is hidden behind it, so collapse the lift and let
    // the composer sit snug above the IME.
    val imeVisible = WindowInsets.ime.getBottom(LocalDensity.current) > 0
    val tabBarInset = LocalTabBarInsetHeight.current
    val pillClearance by animateDpAsState(
        targetValue = if (imeVisible) 0.dp else tabBarInset,
        label = "pillClearance"
    )
    Row(
        modifier = Modifier
            .fillMaxWidth()
            // ONE combined inset (the per-side max of IME and nav bar) so the bar rides flush on
            // whichever is taller — the keyboard when it's up, the nav bar when it's down. Chaining
            // navigationBarsPadding().imePadding() instead can add the nav-bar inset twice (the IME
            // inset already spans the nav-bar region), leaving the bar floating a nav-bar height too
            // high above the keyboard. union() applies it exactly once.
            .windowInsetsPadding(WindowInsets.ime.union(WindowInsets.navigationBars))
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .padding(bottom = pillClearance),
        verticalAlignment = Alignment.CenterVertically
    ) {
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            placeholder = { Text("Ask anything — time zones, best meeting windows, schedule…", color = MaterialTheme.colorScheme.onSurfaceVariant) },
            modifier = Modifier.weight(1f),
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { onSend() }),
            shape = RoundedCornerShape(16.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = MaterialTheme.colorScheme.onSurface,
                unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
                focusedBorderColor = MaterialTheme.colorScheme.primary,
                unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                focusedContainerColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f),
                unfocusedContainerColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.03f)
            )
        )
        Spacer(Modifier.width(12.dp))
        IconButton(
            onClick = onSend,
            enabled = canSend,
            modifier = Modifier
                .graphicsLayer {
                    scaleX = sendScale
                    scaleY = sendScale
                }
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primary.copy(alpha = sendAlpha))
                .size(48.dp)
        ) {
            if (isLoading) {
                // While the assistant is replying, the send button shows progress rather than
                // accepting a second prompt.
                CircularProgressIndicator(
                    modifier = Modifier
                        .size(20.dp)
                        .semantics { contentDescription = "Assistant is replying" },
                    strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.onPrimary,
                )
            } else {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.Send,
                    contentDescription = "Send prompt",
                    tint = MaterialTheme.colorScheme.onPrimary
                )
            }
        }
    }
}

@Composable
private fun DraftConfirmCard(
    draft: PlannedTask,
    is24Hour: Boolean,
    hazeState: HazeState,
    onConfirm: () -> Unit,
    onDiscard: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val whenText = remember(draft, is24Hour) {
        runCatching {
            val zdt = ZonedDateTime.ofInstant(Instant.ofEpochMilli(draft.timestamp), ZoneId.of(draft.zoneId))
            zdt.format(TimeFormats.hourMinuteWithContext(is24Hour))
        }.getOrElse { draft.zoneId }
    }
    val startInstant = remember(draft) { Instant.ofEpochMilli(draft.timestamp) }
    // Export the proposed meeting as a real calendar event; surface only failures (§12.6).
    fun exportSync(action: () -> EventActionResult) {
        val result = action()
        if (result is EventActionResult.Failure) {
            Toast.makeText(context, result.reason, Toast.LENGTH_SHORT).show()
        }
    }
    // ICS export writes a file to cache — dispatch to IO to avoid blocking the UI thread.
    fun exportIo(action: () -> EventActionResult) {
        scope.launch(kotlinx.coroutines.Dispatchers.IO) {
            val result = action()
            if (result is EventActionResult.Failure) {
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) {
                    Toast.makeText(context, result.reason, Toast.LENGTH_SHORT).show()
                }
            }
        }
    }
    LiquidGlassSurface(
        hazeState = hazeState,
        modifier = Modifier.fillMaxWidth(),
        shape = GlassDefaults.cardShape,
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Header + details read as one polite announcement when the draft first appears.
            Column(
                modifier = Modifier.semantics(mergeDescendants = true) {
                    liveRegion = LiveRegionMode.Polite
                }
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Default.AutoAwesome,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.7f),
                        modifier = Modifier.size(14.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        text = "Proposed event",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.7f)
                    )
                }
                Spacer(Modifier.height(2.dp))
                Text(
                    text = draft.title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurface
                )
                Text(
                    text = "$whenText · ${shortZone(draft.zoneId)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.8f)
                )
            }
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = onConfirm, modifier = Modifier.weight(1f)) { Text("Add to plan") }
                FilledTonalButton(
                    onClick = {
                        exportSync {
                            insertCalendarEvent(context, draft.title, startInstant, DEFAULT_EVENT_DURATION_MINUTES, draft.zoneId)
                        }
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Default.Event, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Calendar")
                }
            }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(
                    onClick = {
                        exportIo {
                            shareEventIcs(context, draft.title, startInstant, DEFAULT_EVENT_DURATION_MINUTES, draft.zoneId)
                        }
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Default.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Share .ics")
                }
                OutlinedButton(onClick = onDiscard, modifier = Modifier.weight(1f)) { Text("Discard") }
            }
        }
    }
}

@Composable
private fun Bubble(
    message: ChatMessage,
    hazeState: HazeState,
    onRetry: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val isUser = message.isUser
    val isError = message.sender == "System Error"
    val alignment = if (isUser) Alignment.End else Alignment.Start
    val containerColor = when {
        isError -> MaterialTheme.colorScheme.errorContainer
        isUser -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.surfaceVariant
    }
    val textColor = when {
        isError -> MaterialTheme.colorScheme.onErrorContainer
        isUser -> MaterialTheme.colorScheme.onPrimary
        else -> MaterialTheme.colorScheme.onSurface
    }
    val clipboardManager = LocalClipboardManager.current
    val haptics = LocalHapticFeedback.current
    val context = LocalContext.current
    // Spoken role prefix so TalkBack announces who is speaking before the message text.
    val speaker = when {
        isError -> "Error"
        isUser -> "You said"
        else -> "Assistant said"
    }
    fun copyMessage() {
        clipboardManager.setText(AnnotatedString(message.text))
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        Toast.makeText(context, "Copied to clipboard", Toast.LENGTH_SHORT).show()
    }

    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = alignment
    ) {
        Row(verticalAlignment = Alignment.Bottom) {
            // Small avatar leads assistant/system replies for clear role separation.
            if (!isUser) {
                Box(
                    modifier = Modifier
                        .size(28.dp)
                        .clip(CircleShape)
                        .background(
                            if (isError) MaterialTheme.colorScheme.error.copy(alpha = 0.15f)
                            else MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = if (isError) Icons.Default.ErrorOutline else Icons.Default.AutoAwesome,
                        contentDescription = null,
                        tint = if (isError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(16.dp)
                    )
                }
                Spacer(Modifier.width(8.dp))
            }
            val bubbleShape = RoundedCornerShape(
                topStart = 16.dp, topEnd = 16.dp,
                bottomStart = if (isUser) 16.dp else 4.dp,
                bottomEnd = if (isUser) 4.dp else 16.dp
            )
            Box(
                modifier = Modifier
                    .widthIn(max = 300.dp)
                    .then(
                        if (!isUser && !isError) {
                            Modifier.liquidGlass(
                                hazeState = hazeState,
                                tintColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f),
                                shape = bubbleShape
                            )
                        } else {
                            Modifier.clip(bubbleShape).background(containerColor)
                        }
                    )
                    .pointerInput(message.id) {
                        detectTapGestures(onLongPress = { copyMessage() })
                    }
                    // One coherent TalkBack node: "<speaker>: <text>", with a copy custom action
                    // mirroring the long-press gesture (which touch-explore users can't perform).
                    .semantics(mergeDescendants = true) {
                        contentDescription = "$speaker: ${message.text}"
                        customActions = listOf(
                            CustomAccessibilityAction("Copy message") { copyMessage(); true }
                        )
                    }
                    .padding(14.dp)
            ) {
                if (isError) {
                    Column {
                        Text(
                            text = message.text,
                            color = textColor,
                            style = MaterialTheme.typography.bodyMedium
                        )
                        if (onRetry != null) {
                            Spacer(Modifier.height(8.dp))
                            TextButton(onClick = onRetry) {
                                Icon(
                                    imageVector = Icons.Default.Refresh,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp),
                                )
                                Spacer(Modifier.width(6.dp))
                                Text("Try again")
                            }
                        }
                    }
                } else {
                    ChatMarkdownText(
                        text = message.text,
                        textColor = textColor,
                        linkColor = if (isUser) {
                            textColor.copy(alpha = 0.9f)
                        } else {
                            MaterialTheme.colorScheme.primary
                        },
                    )
                }
            }
        }
        // Provenance badge: shows where this reply was generated (on-device, cloud, rules, cache).
        if (!isUser && !isError) {
            message.provenance?.let { provenance ->
                Spacer(Modifier.height(4.dp))
                InferenceSourceBadge(provenance = provenance, hazeState = hazeState, modifier = Modifier.padding(start = 36.dp))
            }
        }
    }
}

@Composable
private fun InferenceSourceBadge(provenance: AiProvenance, hazeState: HazeState, modifier: Modifier = Modifier) {
    val label = when (provenance) {
        AiProvenance.ON_DEVICE -> "On-device · Gemini Nano"
        AiProvenance.CLOUD -> "Cloud Gemini"
        AiProvenance.RULES -> "On-device · Rules"
        AiProvenance.CACHED -> "Instant · Cached"
    }
    val icon = when (provenance) {
        AiProvenance.CLOUD -> Icons.Default.Cloud
        AiProvenance.CACHED -> Icons.Default.Bolt
        else -> Icons.Default.Memory
    }
    val tint = when (provenance) {
        AiProvenance.CLOUD -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
        else -> MaterialTheme.colorScheme.primary
    }
    LiquidGlassSurface(
        hazeState = hazeState,
        modifier = modifier,
        tintColor = tint.copy(alpha = 0.07f),
        shape = RoundedCornerShape(50),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
        Icon(imageVector = icon, contentDescription = null, tint = tint, modifier = Modifier.size(12.dp))
        Spacer(Modifier.width(4.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = tint
        )
    }
    }
}

private fun shortZone(zoneId: String): String = zoneId.substringAfterLast('/').replace('_', ' ')

/** Human relative phrasing like "in 3 hrs" / "2 days ago" for the scheduler preview. */
private fun relativeTime(target: Instant, now: Instant): String {
    val minutes = Duration.between(now, target).toMinutes()
    val past = minutes < 0
    val abs = kotlin.math.abs(minutes)
    val hours = abs / 60
    val days = hours / 24
    val core = when {
        abs < 1 -> return "now"
        abs < 60 -> "$abs min"
        hours < 24 -> "$hours hr${if (hours > 1) "s" else ""}"
        else -> "$days day${if (days > 1) "s" else ""}"
    }
    return if (past) "$core ago" else "in $core"
}
