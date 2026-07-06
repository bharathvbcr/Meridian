package com.example.feature.settings

import android.Manifest
import android.app.AlarmManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Contacts
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Alarm
import androidx.compose.material.icons.filled.RestartAlt
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Work
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Gavel
import androidx.compose.material.icons.filled.PrivacyTip
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt
import com.example.BuildConfig
import com.example.MainViewModel
import com.example.core.data.HourCycle
import com.example.core.data.MapStyle
import com.example.core.data.MAX_GLASS_OPACITY
import com.example.core.data.MIN_GLASS_OPACITY
import com.example.core.data.MAX_BACKDROP_INTENSITY
import com.example.core.data.MIN_BACKDROP_INTENSITY
import com.example.core.ai.AiEngine
import com.example.core.data.MeridianSettings
import com.example.core.data.SavedZone
import com.example.core.data.ZoneAnchorRole
import com.example.core.data.homeCountryZone
import com.example.core.data.residenceZone
import com.example.core.interop.InteropClient
import com.example.core.designsystem.CardHeader
import com.example.core.designsystem.GlassBottomSheet
import com.example.core.designsystem.GlassCard
import com.example.core.designsystem.GlassDefaults
import com.example.core.designsystem.HomeCityPickerSheet
import com.example.core.designsystem.HourStepperRow
import com.example.core.designsystem.LocalReduceMotion
import com.example.core.designsystem.MeridianFilterChip
import com.example.core.designsystem.MeridianWordmark
import com.example.core.designsystem.Motion
import com.example.core.designsystem.ScrollableChipRow
import com.example.core.designsystem.SectionHeader
import com.example.core.designsystem.SettingsCard
import com.example.core.designsystem.meridianFilterChipColors
import com.example.core.designsystem.ExpressiveShapes
import com.example.core.designsystem.LocalTabBarInsetHeight
import com.example.core.designsystem.reportBarScroll
import dev.chrisbanes.haze.HazeState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private enum class SettingsSection(
    val pillLabel: String,
    val headerLabel: String,
    val icon: ImageVector,
) {
    HOME("Home", "HOME LOCATION", Icons.Default.Home),
    PERMISSIONS("Permissions", "PERMISSIONS", Icons.Default.Security),
    APPEARANCE("Appearance", "APPEARANCE & CLOCK", Icons.Default.Palette),
    AI("AI engine", "ON-DEVICE AI ENGINE", Icons.Default.Memory),
    REMINDERS("Reminders", "EVENT REMINDERS", Icons.Default.NotificationsActive),
    WORK_HOURS("Work hours", "DEFAULT WORK HOUR WINDOW", Icons.Default.Work),
    DATABASE("Database", "DATABASE & STORAGE", Icons.Default.Storage),
    ABOUT("About", "ABOUT & LEGAL", Icons.Default.Gavel),
}

private fun settingsSectionSummary(
    section: SettingsSection,
    settings: MeridianSettings,
    savedZones: List<SavedZone>,
): String = when (section) {
    SettingsSection.HOME ->
        savedZones.residenceZone()?.displayName ?: "Home not set"
    SettingsSection.PERMISSIONS -> "Location, calendar, contacts, alarms"
    SettingsSection.APPEARANCE -> when (settings.hourCycle) {
        HourCycle.H12 -> "12-hour · ${settings.mapStyle.name.lowercase()} map"
        HourCycle.H24 -> "24-hour · ${settings.mapStyle.name.lowercase()} map"
        HourCycle.SYSTEM -> "System format · ${settings.mapStyle.name.lowercase()} map"
    }
    SettingsSection.AI -> "Gemini Nano · on-device first"
    SettingsSection.REMINDERS ->
        if (settings.reminderLeadMinutes < 0) "Reminders disabled"
        else "${settings.reminderLeadMinutes} min before events"
    SettingsSection.WORK_HOURS ->
        "%02d:00 – %02d:00".format(settings.defaultWorkStartHour, settings.defaultWorkEndHour)
    SettingsSection.DATABASE -> "Pinned zones & local storage"
    SettingsSection.ABOUT -> "Privacy · support · v${BuildConfig.VERSION_NAME}"
}

/** LazyColumn index for a settings section card (after header, companion, quick-nav). */
private fun settingsSectionLazyIndex(section: SettingsSection): Int =
    3 + SettingsSection.entries.indexOf(section)

@Composable
fun SettingsScreen(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier,
    hazeState: HazeState = remember { HazeState() }
) {
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val savedZones by viewModel.savedZones.collectAsStateWithLifecycle()
    val onSurface = MaterialTheme.colorScheme.onSurface
    val haptics = LocalHapticFeedback.current
    val listState = rememberLazyListState()
    val tabBarInset = LocalTabBarInsetHeight.current
    val scope = rememberCoroutineScope()

    var focusedSection by remember { mutableStateOf<SettingsSection?>(null) }
    var expandedSections by remember { mutableStateOf(setOf<SettingsSection>()) }

    val visibleSections by remember(focusedSection) {
        derivedStateOf {
            if (focusedSection != null) listOf(focusedSection!!) else SettingsSection.entries
        }
    }

    LaunchedEffect(focusedSection) {
        focusedSection?.let { section ->
            listState.animateScrollToItem(settingsSectionLazyIndex(section))
        }
    }

    fun scrollToSection(section: SettingsSection) {
        scope.launch {
            listState.animateScrollToItem(settingsSectionLazyIndex(section))
        }
    }

    LazyColumn(
        state = listState,
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .reportBarScroll()
    ) {
        item(key = "settings-header") {
            Column(
                modifier = Modifier
                    .padding(16.dp)
                    // Wordmark + title + tagline read as one heading node so TalkBack lands on the
                    // screen title in a single swipe instead of three.
                    .semantics(mergeDescendants = true) { heading() },
            ) {
                MeridianWordmark(modifier = Modifier.padding(bottom = 12.dp))
                Text(
                    text = "Settings",
                    style = MaterialTheme.typography.displaySmall,
                    fontWeight = FontWeight.Black,
                    color = MaterialTheme.colorScheme.onBackground
                )
                Text(
                    text = "Configure Meridian's engine, surfaces, and integrations.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = onSurface.copy(alpha = 0.6f),
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
        }

        item(key = "companion-app") {
            CompanionAppCard(hazeState)
        }

        item(key = "quick-nav") {
            SettingsQuickNav(
                focusedSection = focusedSection,
                onSelectSection = { section ->
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    focusedSection = section
                    expandedSections = if (section != null) setOf(section) else emptySet()
                },
            )
        }

        visibleSections.forEach { section ->
            item(key = "section-${section.name}") {
                val isExpanded = focusedSection != null || section in expandedSections
                CollapsibleSettingsSection(
                    section = section,
                    summary = settingsSectionSummary(section, settings, savedZones),
                    expanded = isExpanded,
                    showToggle = focusedSection == null,
                    hazeState = hazeState,
                    onToggle = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        val expanding = section !in expandedSections
                        expandedSections = if (expanding) {
                            expandedSections + section
                        } else {
                            expandedSections - section
                        }
                        if (expanding) scrollToSection(section)
                    },
                ) {
                    when (section) {
                        SettingsSection.HOME -> {
                            HomeLocationCard(viewModel, savedZones, hazeState)
                            HomeCountryCard(viewModel, settings, savedZones, hazeState)
                        }
                        SettingsSection.PERMISSIONS -> {
                            PermissionsCard(viewModel, hazeState)
                        }
                        SettingsSection.APPEARANCE -> {
                            AppearanceCard(settings, viewModel, hazeState)
                        }
                        SettingsSection.AI -> {
                            AiEngineCard(settings, viewModel, hazeState)
                        }
                        SettingsSection.REMINDERS -> {
                            RemindersCard(settings, viewModel, hazeState)
                        }
                        SettingsSection.WORK_HOURS -> {
                            WorkHoursCard(settings, viewModel, hazeState)
                        }
                        SettingsSection.DATABASE -> {
                            ReseedCard(viewModel, hazeState)
                            DataManagementCard(hazeState)
                        }
                        SettingsSection.ABOUT -> {
                            AboutCard(hazeState)
                            OnDeviceCard(hazeState)
                            LegalNoticesCard(hazeState)
                            SupportCard(hazeState)
                        }
                    }
                }
            }
        }

        item(key = "settings-footer") {
            SettingsFooter()
        }

        item(key = "bottom-spacer") { Spacer(Modifier.height(tabBarInset + 84.dp)) }
    }
}

/**
 * Shows whether ChronosFlow (the companion planner) is installed, so the user knows whether
 * cross-app task/event sharing is active. Re-checks on every resume — the user may install or
 * remove ChronosFlow while Meridian is backgrounded.
 */
@Composable
private fun CompanionAppCard(hazeState: HazeState) {
    val context = LocalContext.current
    val client = remember { InteropClient(context.applicationContext) }
    var installed by remember { mutableStateOf(client.isPeerInstalled()) }
    LifecycleResumeEffect(Unit) {
        installed = client.isPeerInstalled()
        onPauseOrDispose { }
    }

    val onSurface = MaterialTheme.colorScheme.onSurface
    val accent = if (installed) MaterialTheme.colorScheme.primary else onSurface.copy(alpha = 0.5f)
    val statusLabel = if (installed) "connected" else "not installed"
    GlassCard(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Row(
            modifier = Modifier
                .padding(16.dp)
                // Status icon + name + description announce as one TalkBack stop; the icon's
                // meaning rides in stateDescription so it isn't dropped as a decorative glyph.
                .semantics(mergeDescendants = true) { stateDescription = statusLabel },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = if (installed) Icons.Outlined.CheckCircle else Icons.Filled.Close,
                contentDescription = null,
                tint = accent,
                modifier = Modifier.size(28.dp),
            )
            Spacer(Modifier.width(14.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "ChronosFlow",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = onSurface,
                )
                Text(
                    text = if (installed) {
                        "Connected — tasks and events are shared between apps."
                    } else {
                        "Not installed — Meridian runs on its own. Install ChronosFlow to share tasks and events."
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = onSurface.copy(alpha = 0.6f),
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
        }
    }
}

@Composable
private fun SettingsQuickNav(
    focusedSection: SettingsSection?,
    onSelectSection: (SettingsSection?) -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    val onSurface = MaterialTheme.colorScheme.onSurface
    val pillSections = if (focusedSection != null) {
        listOf(focusedSection)
    } else {
        SettingsSection.entries
    }
    val selectedChipIndex = if (focusedSection != null) 1 else -1

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Text(
            text = "Jump to a section",
            style = MaterialTheme.typography.labelLarge,
            color = onSurface.copy(alpha = 0.7f),
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.semantics { heading() },
        )
        Spacer(Modifier.height(8.dp))
        ScrollableChipRow(selectedIndex = selectedChipIndex) {
            if (focusedSection != null) {
                item(key = "all-sections") {
                    FilterChip(
                        selected = false,
                        onClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            onSelectSection(null)
                        },
                        label = { Text("All") },
                        colors = meridianFilterChipColors(),
                    )
                }
            }
            items(pillSections, key = { it.name }) { section ->
                FilterChip(
                    selected = focusedSection == section,
                    onClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        onSelectSection(if (focusedSection == section) null else section)
                    },
                    label = { Text(section.pillLabel) },
                    colors = meridianFilterChipColors(),
                )
            }
        }
    }
}

@Composable
private fun CollapsibleSettingsSection(
    section: SettingsSection,
    summary: String,
    expanded: Boolean,
    showToggle: Boolean,
    hazeState: HazeState,
    onToggle: () -> Unit,
    content: @Composable () -> Unit,
) {
    val reduceMotion = LocalReduceMotion.current
    // Spring rotation matches the app's motion language (north-star: "spring physics ONLY");
    // collapses to an instant snap when the user has requested reduced motion.
    val chevronRotation by animateFloatAsState(
        targetValue = if (expanded) 180f else 0f,
        animationSpec = if (reduceMotion) snap() else Motion.smooth(),
        label = "settingsSectionChevron",
    )

    // Springy pressed feedback: the default ripple over transparent glass is barely perceptible,
    // so tapping the section header gets the same tactile scale as the app's other glass cards.
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val pressScale by animateFloatAsState(
        targetValue = if (isPressed) 0.98f else 1f,
        animationSpec = if (reduceMotion) snap() else Motion.snappy(),
        label = "settingsSectionPressScale",
    )

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
    ) {
        if (showToggle) {
            GlassCard(
                hazeState = hazeState,
                modifier = Modifier
                    .fillMaxWidth()
                    .graphicsLayer {
                        scaleX = pressScale
                        scaleY = pressScale
                    }
                    // Clip BEFORE clickable so the ripple is bounded to the rounded corners;
                    // GlassCard's internal clip runs after this incoming modifier, too late for the ripple.
                    .clip(GlassDefaults.cardShape)
                    .clickable(
                        interactionSource = interactionSource,
                        indication = null,
                        onClick = onToggle,
                        role = Role.Button,
                    )
                    // Announce the collapsed/expanded state on the card so the chevron isn't read as
                    // a separate, redundant stop.
                    .semantics {
                        stateDescription = if (expanded) "Expanded" else "Collapsed"
                    },
                shape = GlassDefaults.cardShape,
            ) {
                SettingsSectionCardHeader(
                    section = section,
                    summary = summary,
                    expanded = expanded,
                    chevronRotation = chevronRotation,
                )
            }
        } else {
            SectionHeader(
                title = section.headerLabel,
                icon = section.icon,
                style = MaterialTheme.typography.labelLarge,
                titleColor = MaterialTheme.colorScheme.primary,
                dividerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }

        AnimatedVisibility(
            visible = expanded,
            enter = expandVertically(animationSpec = if (reduceMotion) snap() else Motion.smooth()) +
                fadeIn(animationSpec = if (reduceMotion) snap() else Motion.smooth()),
            exit = shrinkVertically(animationSpec = if (reduceMotion) snap() else Motion.smooth()) +
                fadeOut(animationSpec = if (reduceMotion) snap() else Motion.smooth()),
        ) {
            Column(modifier = Modifier.padding(top = 8.dp, bottom = 4.dp)) {
                content()
            }
        }
    }
}

@Composable
private fun SettingsSectionCardHeader(
    section: SettingsSection,
    summary: String,
    expanded: Boolean,
    chevronRotation: Float,
) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = section.icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(22.dp),
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = section.pillLabel,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = onSurface,
            )
            AnimatedVisibility(
                visible = !expanded,
                enter = fadeIn() + expandVertically(),
                exit = fadeOut() + shrinkVertically(),
            ) {
                Text(
                    text = summary,
                    style = MaterialTheme.typography.bodySmall,
                    color = onSurface.copy(alpha = 0.6f),
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
        }
        Icon(
            imageVector = Icons.Default.ExpandMore,
            // State is announced on the parent card via stateDescription; keep this glyph decorative
            // so TalkBack doesn't read "Collapsed" twice.
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .padding(start = 8.dp)
                .size(22.dp)
                .rotate(chevronRotation),
        )
    }
}

@Composable
private fun PermissionsCard(viewModel: MainViewModel, hazeState: HazeState) {
    val context = LocalContext.current
    val onSurface = MaterialTheme.colorScheme.onSurface
    var refreshKey by remember { mutableStateOf(0) }

    LifecycleResumeEffect(Unit) {
        refreshKey++
        onPauseOrDispose { }
    }

    val locationGranted = remember(refreshKey) { viewModel.hasLocationPermission() }
    val notificationsGranted = remember(refreshKey) {
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }
    val calendarGranted = remember(refreshKey) {
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED
    }
    val contactsGranted = remember(refreshKey) {
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) ==
            PackageManager.PERMISSION_GRANTED
    }
    val exactAlarmsGranted = remember(refreshKey) {
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            context.getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() == true
    }

    val locationLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { refreshKey++ }
    val notificationsLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { refreshKey++ }
    val calendarLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { refreshKey++ }
    val contactsLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { refreshKey++ }
    val exactAlarmsLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { refreshKey++ }

    fun requestExactAlarms() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            exactAlarmsLauncher.launch(
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = Uri.parse("package:${context.packageName}")
                }
            )
        }
    }

    SettingsCard(hazeState = hazeState) {
        CardHeader(icon = Icons.Default.Security, title = "App permissions")
        Text(
            text = "Meridian only asks for access when a feature needs it. Grant permissions here or in system settings.",
            style = MaterialTheme.typography.bodySmall,
            color = onSurface.copy(alpha = 0.6f),
            modifier = Modifier.padding(top = 8.dp, bottom = 12.dp)
        )

            PermissionRow(
                icon = Icons.Default.MyLocation,
                title = "Location",
                description = "Resolve your home time zone from your current position.",
                granted = locationGranted,
                onGrant = { locationLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION) },
                onOpenSettings = { openAppSettings(context) },
            )
            PermissionDivider()
            PermissionRow(
                icon = Icons.Default.NotificationsActive,
                title = "Notifications",
                description = "Post reminders before planned events.",
                granted = notificationsGranted,
                applicable = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
                onGrant = { notificationsLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) },
                onOpenSettings = { openAppSettings(context) },
            )
            PermissionDivider()
            PermissionRow(
                icon = Icons.Default.CalendarMonth,
                title = "Calendar",
                description = "Show your device calendar on the planner.",
                granted = calendarGranted,
                onGrant = { calendarLauncher.launch(Manifest.permission.READ_CALENDAR) },
                onOpenSettings = { openAppSettings(context) },
            )
            PermissionDivider()
            PermissionRow(
                icon = Icons.Default.Contacts,
                title = "Contacts",
                description = "Import people into the planner from your address book.",
                granted = contactsGranted,
                onGrant = { contactsLauncher.launch(Manifest.permission.READ_CONTACTS) },
                onOpenSettings = { openAppSettings(context) },
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PermissionDivider()
                PermissionRow(
                    icon = Icons.Default.Alarm,
                    title = "Exact alarms",
                    description = "Fire event reminders at the precise minute you chose.",
                    granted = exactAlarmsGranted,
                    onGrant = ::requestExactAlarms,
                    onOpenSettings = ::requestExactAlarms,
                )
            }
    }
}

@Composable
private fun PermissionDivider() {
    HorizontalDivider(
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f),
        modifier = Modifier.padding(vertical = 12.dp)
    )
}

@Composable
private fun PermissionRow(
    icon: ImageVector,
    title: String,
    description: String,
    granted: Boolean,
    onGrant: () -> Unit,
    onOpenSettings: () -> Unit,
    applicable: Boolean = true,
) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val statusLabel = when {
        !applicable -> "Not required"
        granted -> "Granted"
        else -> "Not granted"
    }
    val statusColor = when {
        !applicable -> onSurface.copy(alpha = 0.45f)
        granted -> GlassDefaults.positive
        else -> MaterialTheme.colorScheme.error.copy(alpha = 0.85f)
    }

    Column {
        Row(
            // Icon + title + status + description read as one TalkBack node, e.g.
            // "Location, Granted, Resolve your home time zone…", so the permission's name,
            // state, and purpose arrive together in a single swipe.
            modifier = Modifier.semantics(mergeDescendants = true) {
                stateDescription = statusLabel
            },
            verticalAlignment = Alignment.Top,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier
                    .padding(top = 2.dp)
                    .size(20.dp)
            )
            Spacer(Modifier.width(8.dp))
            Column(modifier = Modifier.weight(1f)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        title,
                        style = MaterialTheme.typography.bodyLarge,
                        color = onSurface,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        statusLabel,
                        style = MaterialTheme.typography.labelMedium,
                        color = statusColor,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
                Text(
                    description,
                    style = MaterialTheme.typography.bodySmall,
                    color = onSurface.copy(alpha = 0.6f),
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
        }
        if (applicable && !granted) {
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = onGrant,
                    shape = ExpressiveShapes.small,
                    modifier = Modifier
                        .weight(1f)
                        .sizeIn(minHeight = 48.dp),
                ) {
                    Text("Allow $title access")
                }
                TextButton(
                    onClick = onOpenSettings,
                    modifier = Modifier.sizeIn(minHeight = 48.dp),
                ) {
                    Text("System settings")
                }
            }
        }
    }
}

@Composable
private fun AppearanceCard(settings: MeridianSettings, viewModel: MainViewModel, hazeState: HazeState) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val reduceMotion = LocalReduceMotion.current
    SettingsCard(hazeState = hazeState) {
        Text(
            "Clock format",
            style = MaterialTheme.typography.titleSmall,
            color = onSurface,
            fontWeight = FontWeight.SemiBold,
        )
            Text(
                "Choose how every clock renders the hour.",
                style = MaterialTheme.typography.bodySmall,
                color = onSurface.copy(alpha = 0.6f),
                modifier = Modifier.padding(top = 2.dp, bottom = 8.dp)
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MeridianFilterChip(
                    label = "System",
                    selected = settings.hourCycle == HourCycle.SYSTEM,
                    onClick = { viewModel.setHourCycle(HourCycle.SYSTEM) },
                )
                MeridianFilterChip(
                    label = "12-hour",
                    selected = settings.hourCycle == HourCycle.H12,
                    onClick = { viewModel.setHourCycle(HourCycle.H12) },
                )
                MeridianFilterChip(
                    label = "24-hour",
                    selected = settings.hourCycle == HourCycle.H24,
                    onClick = { viewModel.setHourCycle(HourCycle.H24) },
                )
            }

            Spacer(Modifier.height(20.dp))

            SettingSwitchRow(
                title = "Liquid Glass compositor",
                subtitle = "Apply hardware-accelerated blur onto navigators.",
                checked = settings.glassEnabled,
                onCheckedChange = viewModel::setGlassEnabled
            )

            Spacer(Modifier.height(16.dp))

            SettingSwitchRow(
                title = "Reduce transparency",
                subtitle = "Swap glass for opaque surfaces for maximum legibility.",
                checked = settings.reduceTransparency,
                onCheckedChange = viewModel::setReduceTransparency
            )

            Spacer(Modifier.height(16.dp))

            GlassOpacitySlider(
                opacity = settings.glassOpacity,
                onOpacityChange = viewModel::setGlassOpacity,
            )

            Spacer(Modifier.height(16.dp))

            SettingSwitchRow(
                title = "Celestial backdrop",
                subtitle = "Show the sun and moon behind the interface. Glass surfaces refract this layer.",
                checked = settings.backdropEnabled,
                onCheckedChange = viewModel::setBackdropEnabled
            )

            AnimatedVisibility(
                visible = settings.backdropEnabled,
                enter = if (reduceMotion) fadeIn(snap()) else fadeIn() + expandVertically(),
                exit = if (reduceMotion) fadeOut(snap()) else fadeOut() + shrinkVertically(),
            ) {
                BackdropIntensitySlider(
                    intensity = settings.backdropIntensity,
                    onIntensityChange = viewModel::setBackdropIntensity,
                )
            }

            Spacer(Modifier.height(20.dp))

            Text(
                "World map style",
                style = MaterialTheme.typography.titleSmall,
                color = onSurface,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                "Realistic uses the full photo texture, atmosphere and night-lights. Balanced keeps " +
                    "the texture but drops the heavy effects. Performance shades a flat globe. Vector " +
                    "is a 2D flat outline map (tiny, crisp, recolors with the theme).",
                style = MaterialTheme.typography.bodySmall,
                color = onSurface.copy(alpha = 0.6f),
                modifier = Modifier.padding(top = 2.dp, bottom = 8.dp)
            )
            val mapStyleOptions = remember {
                listOf(
                    "Realistic" to MapStyle.REALISTIC,
                    "Balanced" to MapStyle.BALANCED,
                    "Performance" to MapStyle.PERFORMANCE,
                    "Vector" to MapStyle.VECTOR,
                )
            }
            ScrollableChipRow(
                selectedIndex = mapStyleOptions.indexOfFirst { it.second == settings.mapStyle },
            ) {
                items(mapStyleOptions) { (label, style) ->
                    MeridianFilterChip(
                        label = label,
                        selected = settings.mapStyle == style,
                        onClick = { viewModel.setMapStyle(style) },
                    )
                }
            }
    }
}

@Composable
private fun GlassOpacitySlider(
    opacity: Int,
    onOpacityChange: (Int) -> Unit,
) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val haptics = LocalHapticFeedback.current
    val levelLabel = when (opacity) {
        in MIN_GLASS_OPACITY..24 -> "Transparent"
        in 25..49 -> "Light"
        in 50..74 -> "Medium"
        else -> "Opaque"
    }
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Agenda & scrubber glass",
                style = MaterialTheme.typography.bodyLarge,
                color = onSurface,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = levelLabel,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Text(
            text = "Glass opacity and contrast for the agenda pill, the compact scrubber pill, " +
                "and the expanded time dial. Higher means a more solid, legible card.",
            style = MaterialTheme.typography.bodySmall,
            color = onSurface.copy(alpha = 0.6f),
            modifier = Modifier.padding(top = 2.dp, bottom = 4.dp),
        )
        val opacitySliderColors = SliderDefaults.colors(
            thumbColor = MaterialTheme.colorScheme.primary,
            activeTrackColor = MaterialTheme.colorScheme.primary,
            inactiveTrackColor = MaterialTheme.colorScheme.surfaceVariant,
        )
        Slider(
            value = opacity.toFloat(),
            onValueChange = { value ->
                val snapped = value.roundToInt()
                    .coerceIn(MIN_GLASS_OPACITY, MAX_GLASS_OPACITY)
                if (snapped != opacity) {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    onOpacityChange(snapped)
                }
            },
            valueRange = MIN_GLASS_OPACITY.toFloat()..MAX_GLASS_OPACITY.toFloat(),
            steps = MAX_GLASS_OPACITY - MIN_GLASS_OPACITY - 1,
            colors = opacitySliderColors,
            // Announce the named level ("Glass opacity, Medium") rather than a bare 0–100 percent
            // that means nothing to a TalkBack user.
            modifier = Modifier.semantics {
                contentDescription = "Glass opacity"
                stateDescription = levelLabel
            },
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text = "Transparent",
                style = MaterialTheme.typography.labelSmall,
                color = onSurface.copy(alpha = 0.45f),
            )
            Text(
                text = "Opaque",
                style = MaterialTheme.typography.labelSmall,
                color = onSurface.copy(alpha = 0.45f),
            )
        }
    }
}

@Composable
private fun BackdropIntensitySlider(
    intensity: Int,
    onIntensityChange: (Int) -> Unit,
) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val haptics = LocalHapticFeedback.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Backdrop intensity",
                style = MaterialTheme.typography.bodyLarge,
                color = onSurface,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = "$intensity%",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Text(
            text = "How strongly the sun and moon glow through the glass.",
            style = MaterialTheme.typography.bodySmall,
            color = onSurface.copy(alpha = 0.6f),
            modifier = Modifier.padding(top = 2.dp, bottom = 4.dp),
        )
        val intensitySliderColors = SliderDefaults.colors(
            thumbColor = MaterialTheme.colorScheme.primary,
            activeTrackColor = MaterialTheme.colorScheme.primary,
            inactiveTrackColor = MaterialTheme.colorScheme.surfaceVariant,
        )
        Slider(
            value = intensity.toFloat(),
            onValueChange = { value ->
                val snapped = value.roundToInt()
                    .coerceIn(MIN_BACKDROP_INTENSITY, MAX_BACKDROP_INTENSITY)
                if (snapped != intensity) {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    onIntensityChange(snapped)
                }
            },
            valueRange = MIN_BACKDROP_INTENSITY.toFloat()..MAX_BACKDROP_INTENSITY.toFloat(),
            steps = MAX_BACKDROP_INTENSITY - MIN_BACKDROP_INTENSITY - 1,
            colors = intensitySliderColors,
            modifier = Modifier.semantics {
                contentDescription = "Backdrop intensity"
                stateDescription = "$intensity percent"
            },
        )
    }
}

@Composable
private fun SettingSwitchRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val haptics = LocalHapticFeedback.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            // Title + subtitle + switch read as one toggle node so TalkBack announces the
            // setting's name, purpose, and on/off state together in a single swipe.
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(end = 12.dp),
        ) {
            Text(
                title,
                style = MaterialTheme.typography.bodyLarge,
                color = onSurface,
                fontWeight = FontWeight.Medium,
            )
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = onSurface.copy(alpha = 0.6f),
                modifier = Modifier.padding(top = 2.dp),
            )
        }
        val switchColors = SwitchDefaults.colors(
            checkedThumbColor = MaterialTheme.colorScheme.onPrimary,
            checkedTrackColor = MaterialTheme.colorScheme.primary,
        )
        Switch(
            checked = checked,
            onCheckedChange = {
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                onCheckedChange(it)
            },
            colors = switchColors,
        )
    }
}

@Composable
private fun HomeLocationCard(viewModel: MainViewModel, savedZones: List<SavedZone>, hazeState: HazeState) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val residence = savedZones.residenceZone()
    var status by remember { mutableStateOf<String?>(null) }
    var showCityPicker by remember { mutableStateOf(false) }

    fun resolve() = viewModel.resolveHomeFromLocation { zoneId ->
        status = if (zoneId != null) {
            "Home set to ${zoneId.substringAfterLast('/').replace('_', ' ')}"
        } else {
            "Couldn't read your location. Pick a city manually below."
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) resolve() else status = "Location permission denied. You can still choose a home city manually."
    }

    SettingsCard(hazeState = hazeState) {
            Row(
                modifier = Modifier.semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Default.Home,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(Modifier.width(8.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = residence?.let { "Home · ${it.displayName}" } ?: "No home set",
                        style = MaterialTheme.typography.bodyLarge,
                        color = onSurface,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = "Your usual base for the Now card and planning. Resolved on-device — never sent anywhere.",
                        style = MaterialTheme.typography.bodySmall,
                        color = onSurface.copy(alpha = 0.6f),
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = {
                    if (viewModel.hasLocationPermission()) resolve()
                    else permissionLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
                },
                shape = ExpressiveShapes.small,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.MyLocation, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Use my location")
            }
            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                onClick = { showCityPicker = true },
                shape = ExpressiveShapes.small,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.Search, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Set city manually")
            }
            AnimatedVisibility(
                visible = status != null,
                enter = fadeIn() + expandVertically(),
                exit = fadeOut() + shrinkVertically()
            ) {
                status?.let {
                    Column {
                        Spacer(Modifier.height(8.dp))
                        Text(
                            it,
                            style = MaterialTheme.typography.bodySmall,
                            color = onSurface.copy(alpha = 0.75f),
                        )
                    }
                }
            }
    }

    if (showCityPicker) {
        HomeCityPickerSheet(
            onDismiss = { showCityPicker = false },
            onCitySelected = { result ->
                viewModel.setHomeZone(result.id, result.displayName)
                status = "Home set to ${result.displayName}"
                showCityPicker = false
            },
            search = { query -> viewModel.searchTimeZones(query) },
            hazeState = hazeState,
            title = "Choose your home city",
        )
    }
}

@Composable
private fun HomeCountryCard(
    viewModel: MainViewModel,
    settings: MeridianSettings,
    savedZones: List<SavedZone>,
    hazeState: HazeState,
) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val homeCountry = savedZones.homeCountryZone()
    val reduceMotion = LocalReduceMotion.current
    var status by remember { mutableStateOf<String?>(null) }
    var showCityPicker by remember { mutableStateOf(false) }

    SettingsCard(hazeState = hazeState) {
            SettingSwitchRow(
                title = "Home country",
                subtitle = "Show your origin country clock on the Now card — e.g. India for family calls.",
                checked = settings.homeCountryEnabled,
                onCheckedChange = { viewModel.setHomeCountryEnabled(it) }
            )
            AnimatedVisibility(
                visible = settings.homeCountryEnabled,
                enter = if (reduceMotion) fadeIn(snap()) else fadeIn() + expandVertically(),
                exit = if (reduceMotion) fadeOut(snap()) else fadeOut() + shrinkVertically()
            ) {
                Column {
                    Spacer(Modifier.height(12.dp))
                    HorizontalDivider(color = onSurface.copy(alpha = 0.08f))
                    Spacer(Modifier.height(12.dp))
                    Row(
                        modifier = Modifier.semantics(mergeDescendants = true) {},
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = Icons.Default.Public,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(20.dp)
                        )
                        Spacer(Modifier.width(8.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = homeCountry?.let { "City · ${it.displayName}" } ?: "No city chosen",
                                style = MaterialTheme.typography.bodyLarge,
                                color = onSurface,
                                fontWeight = FontWeight.Medium
                            )
                            Text(
                                text = "Pick the city that represents your home country time zone.",
                                style = MaterialTheme.typography.bodySmall,
                                color = onSurface.copy(alpha = 0.6f),
                                modifier = Modifier.padding(top = 2.dp),
                            )
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                    OutlinedButton(
                        onClick = { showCityPicker = true },
                        shape = ExpressiveShapes.small,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Default.Search, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text(if (homeCountry == null) "Pick city" else "Change city")
                    }
                    AnimatedVisibility(
                        visible = status != null,
                        enter = fadeIn() + expandVertically(),
                        exit = fadeOut() + shrinkVertically()
                    ) {
                        status?.let {
                            Column {
                                Spacer(Modifier.height(8.dp))
                                Text(
                                    it,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = onSurface.copy(alpha = 0.75f),
                                )
                            }
                        }
                    }
                }
            }
    }

    if (showCityPicker) {
        HomeCityPickerSheet(
            onDismiss = { showCityPicker = false },
            onCitySelected = { result ->
                viewModel.setAnchorZone(result.id, result.displayName, ZoneAnchorRole.HOME_COUNTRY)
                status = "Home country set to ${result.displayName}"
                showCityPicker = false
            },
            search = { query -> viewModel.searchTimeZones(query) },
            hazeState = hazeState,
            title = "Choose your home country city",
        )
    }
}

@Composable
private fun AiEngineCard(
    settings: MeridianSettings,
    viewModel: MainViewModel,
    hazeState: HazeState,
) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    SettingsCard(hazeState = hazeState) {
            CardHeader(icon = Icons.Default.Memory, title = "Assistant engine")
            Spacer(Modifier.height(8.dp))
            Text(
                text = "The Assistant runs on-device with Gemini Nano when supported — no API key, and your prompts never leave the phone. Choose Cloud to always use a hosted model.",
                style = MaterialTheme.typography.bodySmall,
                color = onSurface.copy(alpha = 0.6f),
                modifier = Modifier.padding(bottom = 12.dp)
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MeridianFilterChip(
                    label = "On-Device",
                    selected = settings.aiEngine == AiEngine.ON_DEVICE,
                    onClick = { viewModel.setAiEngine(AiEngine.ON_DEVICE) },
                )
                MeridianFilterChip(
                    label = "Cloud",
                    selected = settings.aiEngine == AiEngine.CLOUD,
                    onClick = { viewModel.setAiEngine(AiEngine.CLOUD) },
                )
            }

            Spacer(Modifier.height(12.dp))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = if (settings.aiEngine == AiEngine.ON_DEVICE) {
                        Icons.Outlined.CheckCircle
                    } else {
                        Icons.Filled.Cloud
                    },
                    contentDescription = null,
                    tint = if (settings.aiEngine == AiEngine.ON_DEVICE) {
                        GlassDefaults.positive
                    } else {
                        MaterialTheme.colorScheme.tertiary
                    },
                    modifier = Modifier.size(16.dp)
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    text = if (settings.aiEngine == AiEngine.ON_DEVICE) {
                        "On-device first · no key required · rules fallback"
                    } else {
                        "Cloud model · prompts may leave your device"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = onSurface.copy(alpha = 0.75f),
                    fontWeight = FontWeight.Medium,
                )
            }
    }
}

@Composable
private fun RemindersCard(
    settings: MeridianSettings,
    viewModel: MainViewModel,
    hazeState: HazeState
) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val leadTimeOptions = remember {
        listOf(
            -1 to "Disabled",
            5 to "5m",
            10 to "10m",
            15 to "15m",
            30 to "30m",
            60 to "1h"
        )
    }

    SettingsCard(hazeState = hazeState) {
            CardHeader(icon = Icons.Default.NotificationsActive, title = "Alarm lead time")
            Spacer(Modifier.height(8.dp))
            Text(
                "Adjust how many minutes prior to an event the system notification alarm triggers.",
                style = MaterialTheme.typography.bodySmall,
                color = onSurface.copy(alpha = 0.6f),
                modifier = Modifier.padding(bottom = 12.dp)
            )

            // Same scrollable chip strip (edge fades + auto-scroll to the selected option) the rest
            // of the app uses, instead of a bare horizontalScroll Row.
            ScrollableChipRow(
                selectedIndex = leadTimeOptions.indexOfFirst {
                    it.first == settings.reminderLeadMinutes
                },
            ) {
                items(leadTimeOptions, key = { it.first }) { (minutes, label) ->
                    MeridianFilterChip(
                        label = label,
                        selected = settings.reminderLeadMinutes == minutes,
                        onClick = { viewModel.setReminderLeadMinutes(minutes) },
                    )
                }
            }
    }
}

@Composable
private fun WorkHoursCard(
    settings: MeridianSettings,
    viewModel: MainViewModel,
    hazeState: HazeState
) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    SettingsCard(hazeState = hazeState) {
            CardHeader(icon = Icons.Default.Work, title = "Default work hours")
            Spacer(Modifier.height(8.dp))
            Text(
                "Define the starting point and ending point for standard business hours. New participants in the planner default to these values.",
                style = MaterialTheme.typography.bodySmall,
                color = onSurface.copy(alpha = 0.6f),
                modifier = Modifier.padding(bottom = 12.dp)
            )

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                HourStepperRow(
                    label = "Work Start Hour",
                    value = settings.defaultWorkStartHour,
                    onChange = { newStart ->
                        viewModel.setDefaultWorkStartHour(newStart)
                        if (newStart >= settings.defaultWorkEndHour) {
                            viewModel.setDefaultWorkEndHour(newStart + 1)
                        }
                    },
                    haptics = LocalHapticFeedback.current,
                    tint = MaterialTheme.colorScheme.primary,
                    valueFontWeight = FontWeight.SemiBold,
                    modifier = Modifier.fillMaxWidth(),
                )
                HourStepperRow(
                    label = "Work End Hour",
                    value = settings.defaultWorkEndHour,
                    onChange = { newEnd ->
                        if (newEnd > settings.defaultWorkStartHour) {
                            viewModel.setDefaultWorkEndHour(newEnd)
                        }
                    },
                    haptics = LocalHapticFeedback.current,
                    tint = MaterialTheme.colorScheme.primary,
                    valueFontWeight = FontWeight.SemiBold,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
    }
}

@Composable
private fun OnDeviceCard(hazeState: HazeState) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    GlassCard(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = GlassDefaults.cardShape
    ) {
        Row(
            modifier = Modifier
                .padding(16.dp)
                .semantics(mergeDescendants = true) {},
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.Security,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(24.dp)
            )
            Spacer(Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    "On-device first validation",
                    style = MaterialTheme.typography.bodyLarge,
                    color = onSurface,
                    fontWeight = FontWeight.Medium,
                )
                Text(
                    "All time-zone lookups and slot math run on-device. Cloud AI is an opt-in fallback only.",
                    style = MaterialTheme.typography.bodySmall,
                    color = onSurface.copy(alpha = 0.6f),
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
        }
    }
}

@Composable
private fun ReseedCard(viewModel: MainViewModel, hazeState: HazeState) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val reduceMotion = LocalReduceMotion.current
    var seeded by remember { mutableStateOf(false) }
    val buttonContainerColor by animateColorAsState(
        targetValue = if (seeded) MaterialTheme.colorScheme.secondaryContainer
                      else MaterialTheme.colorScheme.primaryContainer,
        animationSpec = if (reduceMotion) snap() else Motion.smooth(),
        label = "reseedButtonColor"
    )
    val buttonContentColor by animateColorAsState(
        targetValue = if (seeded) MaterialTheme.colorScheme.onSecondaryContainer
                      else MaterialTheme.colorScheme.onPrimaryContainer,
        animationSpec = if (reduceMotion) snap() else Motion.smooth(),
        label = "reseedContentColor"
    )
    SettingsCard(hazeState = hazeState) {
            Text(
                "Seed starter zones",
                style = MaterialTheme.typography.titleSmall,
                color = onSurface,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "Adds London, Tokyo, and New York to your pinned zones.",
                style = MaterialTheme.typography.bodySmall,
                color = onSurface.copy(alpha = 0.6f),
                modifier = Modifier.padding(top = 2.dp, bottom = 12.dp)
            )
            Button(
                onClick = {
                    viewModel.addZone(SavedZone("Europe/London", "London"))
                    viewModel.addZone(SavedZone("Asia/Tokyo", "Tokyo"))
                    viewModel.addZone(SavedZone("America/New_York", "New York"))
                    seeded = true
                },
                colors = ButtonDefaults.buttonColors(
                    containerColor = buttonContainerColor,
                    contentColor = buttonContentColor
                ),
                shape = ExpressiveShapes.small,
                modifier = Modifier.fillMaxWidth()
            ) {
                AnimatedVisibility(visible = seeded, enter = fadeIn(), exit = fadeOut()) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.CheckCircle, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text("Zones added to Watchlist")
                    }
                }
                AnimatedVisibility(visible = !seeded, enter = fadeIn(), exit = fadeOut()) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.RestartAlt, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text("Add starter zones")
                    }
                }
            }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LegalNoticeSheet(
    document: LegalDocument,
    hazeState: HazeState,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val onSurface = MaterialTheme.colorScheme.onSurface
    val clipboard = LocalClipboardManager.current
    val haptics = LocalHapticFeedback.current
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            kotlinx.coroutines.delay(2000)
            copied = false
        }
    }

    GlassBottomSheet(onDismissRequest = onDismiss, hazeState = hazeState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 24.dp),
        ) {
            Text(
                text = document.title,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = onSurface,
            )
            Spacer(Modifier.height(12.dp))
            Text(
                text = document.body,
                style = MaterialTheme.typography.bodyMedium,
                color = onSurface.copy(alpha = 0.85f),
                lineHeight = 22.sp,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 420.dp)
                    .verticalScroll(rememberScrollState()),
            )
            if (document == LegalDocument.THIRD_PARTY_POLICIES) {
                Spacer(Modifier.height(12.dp))
                OutlinedButton(
                    onClick = { openWebUrl(context, SettingsUrls.GOOGLE_PRIVACY) },
                    shape = ExpressiveShapes.small,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Google Privacy Policy")
                }
                Spacer(Modifier.height(8.dp))
                OutlinedButton(
                    onClick = { openWebUrl(context, SettingsUrls.FIREBASE_TERMS) },
                    shape = ExpressiveShapes.small,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Firebase Terms of Service")
                }
            } else if (document.externalUrl != null) {
                Spacer(Modifier.height(12.dp))
                TextButton(
                    onClick = { openWebUrl(context, document.externalUrl) },
                ) {
                    Text(document.externalLabel ?: "Learn more")
                }
            }
            Spacer(Modifier.height(16.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(
                    onClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        clipboard.setText(AnnotatedString(document.body))
                        copied = true
                    },
                ) {
                    Icon(Icons.Default.ContentCopy, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(if (copied) "Copied" else "Copy text")
                }
                TextButton(onClick = onDismiss) { Text("Close") }
            }
        }
    }
}

@Composable
private fun AboutCard(hazeState: HazeState) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val haptics = LocalHapticFeedback.current
    val versionLabel = remember { appVersionLabel(context) }
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            kotlinx.coroutines.delay(2000)
            copied = false
        }
    }

    GlassCard(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = GlassDefaults.cardShape,
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            MeridianWordmark(modifier = Modifier.padding(bottom = 8.dp))
            Text(
                text = "Time & world planner",
                style = MaterialTheme.typography.bodyMedium,
                color = onSurface.copy(alpha = 0.6f),
            )
            Spacer(Modifier.height(8.dp))
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(12.dp))
                    .clickable(role = Role.Button) {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        clipboard.setText(AnnotatedString(buildDiagnosticText(context)))
                        copied = true
                    }
                    // Guarantee the Android 48dp accessible target on this compact tap-to-copy row.
                    .sizeIn(minHeight = 48.dp)
                    .semantics(mergeDescendants = true) {
                        contentDescription = "Version $versionLabel, tap to copy diagnostics"
                    }
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = if (copied) "Diagnostics copied" else "Version $versionLabel",
                    style = MaterialTheme.typography.bodySmall,
                    color = if (copied) MaterialTheme.colorScheme.primary else onSurface.copy(alpha = 0.55f),
                )
                if (!copied) {
                    Spacer(Modifier.width(6.dp))
                    Icon(
                        Icons.Default.ContentCopy,
                        contentDescription = null,
                        tint = onSurface.copy(alpha = 0.35f),
                        modifier = Modifier.size(14.dp),
                    )
                }
            }
            if (BuildConfig.DEBUG) {
                Spacer(Modifier.height(6.dp))
                Text(
                    text = "Debug build",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.tertiary,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            Spacer(Modifier.height(12.dp))
            Text(
                text = "Local clocks, multi-zone planning, and optional on-device AI — built with a privacy-first, on-device engine.",
                style = MaterialTheme.typography.bodyMedium,
                color = onSurface.copy(alpha = 0.65f),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}

@Composable
private fun LegalNoticesCard(hazeState: HazeState) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    var activeDocument by remember { mutableStateOf<LegalDocument?>(null) }

    GlassCard(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = GlassDefaults.cardShape,
    ) {
        Column(modifier = Modifier.padding(vertical = 8.dp)) {
            Text(
                text = "Legal & privacy",
                style = MaterialTheme.typography.titleSmall,
                color = onSurface,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .padding(horizontal = 16.dp, vertical = 8.dp)
                    .semantics { heading() },
            )
            SettingsLinkRow(
                icon = Icons.Default.PrivacyTip,
                title = "Privacy notice",
                subtitle = "What Meridian accesses and how data is used",
                onClick = { activeDocument = LegalDocument.PRIVACY },
            )
            SettingsLinkDivider()
            SettingsLinkRow(
                icon = Icons.Default.Storage,
                title = "How your data is handled",
                subtitle = "On-device storage, cloud fallback, and retention",
                onClick = { activeDocument = LegalDocument.DATA_HANDLING },
            )
            SettingsLinkDivider()
            SettingsLinkRow(
                icon = Icons.Default.Gavel,
                title = "Terms of use",
                subtitle = "Acceptable use, disclaimers, and liability",
                onClick = { activeDocument = LegalDocument.TERMS },
            )
            SettingsLinkDivider()
            SettingsLinkRow(
                icon = Icons.Default.Code,
                title = "Open source licenses",
                subtitle = "Third-party libraries used by Meridian",
                onClick = { activeDocument = LegalDocument.OPEN_SOURCE },
            )
            SettingsLinkDivider()
            SettingsLinkRow(
                icon = Icons.AutoMirrored.Filled.OpenInNew,
                title = "Third-party policies",
                subtitle = "Google & Firebase privacy and terms",
                onClick = { activeDocument = LegalDocument.THIRD_PARTY_POLICIES },
            )
        }
    }

    activeDocument?.let { document ->
        LegalNoticeSheet(
            document = document,
            hazeState = hazeState,
            onDismiss = { activeDocument = null },
        )
    }
}

@Composable
private fun SupportCard(hazeState: HazeState) {
    val context = LocalContext.current
    val onSurface = MaterialTheme.colorScheme.onSurface

    GlassCard(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = GlassDefaults.cardShape,
    ) {
        Column(modifier = Modifier.padding(vertical = 8.dp)) {
            Text(
                text = "Support",
                style = MaterialTheme.typography.titleSmall,
                color = onSurface,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .padding(horizontal = 16.dp, vertical = 8.dp)
                    .semantics { heading() },
            )
            SettingsLinkRow(
                icon = Icons.Default.Email,
                title = "Send feedback",
                subtitle = "Email or share diagnostics with your report",
                onClick = { openFeedback(context) },
            )
            SettingsLinkDivider()
            SettingsLinkRow(
                icon = Icons.Default.Star,
                title = "Rate on Google Play",
                subtitle = "Leave a review if Meridian helps you",
                onClick = { openPlayStoreListing(context) },
            )
            SettingsLinkDivider()
            SettingsLinkRow(
                icon = Icons.AutoMirrored.Filled.OpenInNew,
                title = "App permissions in system settings",
                subtitle = "Review or revoke access granted to Meridian",
                onClick = { openAppSettings(context) },
            )
        }
    }
}

@Composable
private fun DataManagementCard(hazeState: HazeState) {
    val context = LocalContext.current
    val onSurface = MaterialTheme.colorScheme.onSurface

    SettingsCard(hazeState = hazeState) {
            Text(
                "Manage local data",
                style = MaterialTheme.typography.titleSmall,
                color = onSurface,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "Meridian stores zones, planner data, and preferences on this device. " +
                    "Clear storage from system settings to remove everything — this cannot be undone.",
                style = MaterialTheme.typography.bodySmall,
                color = onSurface.copy(alpha = 0.6f),
                modifier = Modifier.padding(top = 6.dp, bottom = 12.dp),
            )
            OutlinedButton(
                onClick = { openAppSettings(context) },
                shape = ExpressiveShapes.small,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Default.Storage, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Open app storage settings")
            }
    }
}

@Composable
private fun SettingsFooter() {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val year = remember { java.time.Year.now().value }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = "© $year Meridian",
            style = MaterialTheme.typography.labelSmall,
            color = onSurface.copy(alpha = 0.4f),
        )
        Text(
            text = "On-device first · Last updated $LEGAL_LAST_UPDATED",
            style = MaterialTheme.typography.labelSmall,
            color = onSurface.copy(alpha = 0.35f),
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}

@Composable
private fun SettingsLinkRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val haptics = LocalHapticFeedback.current
    val reduceMotion = LocalReduceMotion.current

    // Springy pressed feedback matching the section-header cards, since the default ripple over
    // transparent glass is barely perceptible.
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val pressScale by animateFloatAsState(
        targetValue = if (isPressed) 0.98f else 1f,
        animationSpec = if (reduceMotion) snap() else Motion.snappy(),
        label = "settingsLinkPressScale",
    )

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .graphicsLayer {
                scaleX = pressScale
                scaleY = pressScale
            }
            // Icon + title + subtitle read as one Button node; the trailing chevron is decorative.
            .semantics(mergeDescendants = true) { role = Role.Button }
            .clickable(interactionSource = interactionSource, indication = null) {
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                onClick()
            }
            // Keep the whole row at the 48dp accessible minimum even with a single-line subtitle.
            .sizeIn(minHeight = 48.dp)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(22.dp),
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                title,
                style = MaterialTheme.typography.bodyLarge,
                color = onSurface,
                fontWeight = FontWeight.Medium,
            )
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = onSurface.copy(alpha = 0.6f),
                modifier = Modifier.padding(top = 2.dp),
            )
        }
        Icon(
            imageVector = Icons.Default.ChevronRight,
            contentDescription = null,
            tint = onSurface.copy(alpha = 0.35f),
            modifier = Modifier.size(20.dp),
        )
    }
}

@Composable
private fun SettingsLinkDivider() {
    HorizontalDivider(
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f),
        modifier = Modifier.padding(horizontal = 16.dp),
    )
}
