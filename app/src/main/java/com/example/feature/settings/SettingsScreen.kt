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
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Remove
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
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
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
import com.example.core.data.MeridianSettings
import com.example.core.data.SavedZone
import com.example.core.data.ZoneAnchorRole
import com.example.core.data.homeCountryZone
import com.example.core.data.residenceZone
import com.example.core.interop.InteropClient
import com.example.core.designsystem.GlassBottomSheet
import com.example.core.designsystem.GlassCard
import com.example.core.designsystem.HomeCityPickerSheet
import com.example.core.designsystem.MeridianWordmark
import com.example.core.designsystem.Motion
import com.example.core.designsystem.ScrollableChipRow
import dev.chrisbanes.haze.HazeState
import kotlinx.coroutines.delay

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

@Composable
fun SettingsScreen(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier,
    hazeState: HazeState = remember { HazeState() }
) {
    val settings by viewModel.settings.collectAsState()
    val savedZones by viewModel.savedZones.collectAsState()
    val onSurface = MaterialTheme.colorScheme.onSurface
    val haptics = LocalHapticFeedback.current
    val listState = rememberLazyListState()

    var focusedSection by remember { mutableStateOf<SettingsSection?>(null) }
    var expandedSections by remember { mutableStateOf(setOf<SettingsSection>()) }

    val visibleSections = if (focusedSection != null) {
        listOf(focusedSection!!)
    } else {
        SettingsSection.entries
    }

    LaunchedEffect(focusedSection) {
        if (focusedSection != null) {
            listState.animateScrollToItem(1)
        }
    }

    LazyColumn(
        state = listState,
        modifier = modifier
            .fillMaxSize()
            .padding(top = 48.dp)
    ) {
        item(key = "settings-header") {
            Column(modifier = Modifier.padding(16.dp)) {
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
                    color = onSurface.copy(alpha = 0.6f)
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
                        expandedSections = if (section in expandedSections) {
                            expandedSections - section
                        } else {
                            expandedSections + section
                        }
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
                            AiEngineCard(hazeState)
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

        item(key = "bottom-spacer") { Spacer(Modifier.height(180.dp)) }
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
    val client = remember { InteropClient(context) }
    var installed by remember { mutableStateOf(client.isPeerInstalled()) }
    LifecycleResumeEffect(Unit) {
        installed = client.isPeerInstalled()
        onPauseOrDispose { }
    }

    val onSurface = MaterialTheme.colorScheme.onSurface
    val accent = if (installed) MaterialTheme.colorScheme.primary else onSurface.copy(alpha = 0.5f)
    GlassCard(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
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
            text = "Quick actions",
            style = MaterialTheme.typography.labelLarge,
            color = onSurface.copy(alpha = 0.7f),
            fontWeight = FontWeight.SemiBold,
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
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                            selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
                        ),
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
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                        selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
                    ),
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
    val chevronRotation by animateFloatAsState(
        targetValue = if (expanded) 180f else 0f,
        animationSpec = Motion.smooth(),
        label = "settingsSectionChevron",
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
                    .clip(RoundedCornerShape(28.dp))
                    .clickable(onClick = onToggle),
                shape = RoundedCornerShape(28.dp),
            ) {
                SettingsSectionCardHeader(
                    section = section,
                    summary = summary,
                    expanded = expanded,
                    chevronRotation = chevronRotation,
                )
            }
        } else {
            SectionHeader(section.headerLabel)
        }

        AnimatedVisibility(
            visible = expanded,
            enter = expandVertically(animationSpec = Motion.smooth()) + fadeIn(animationSpec = Motion.smooth()),
            exit = shrinkVertically(animationSpec = Motion.smooth()) + fadeOut(animationSpec = Motion.smooth()),
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
            contentDescription = if (expanded) "Collapse" else "Expand",
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .padding(start = 8.dp)
                .size(22.dp)
                .rotate(chevronRotation),
        )
    }
}

@Composable
private fun SectionHeader(label: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(end = 12.dp)
        )
        HorizontalDivider(
            color = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
            modifier = Modifier.weight(1f)
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

    fun openAppSettings() {
        context.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", context.packageName, null)
            }
        )
    }

    fun requestExactAlarms() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            exactAlarmsLauncher.launch(
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = Uri.parse("package:${context.packageName}")
                }
            )
        }
    }

    GlassCard(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = RoundedCornerShape(28.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.Security,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(Modifier.width(8.dp))
                Text("App permissions", color = onSurface, fontWeight = FontWeight.Medium)
            }
            Text(
                text = "Meridian only asks for access when a feature needs it. Grant permissions here or in system settings.",
                color = onSurface.copy(alpha = 0.5f),
                fontSize = 12.sp,
                modifier = Modifier.padding(top = 8.dp, bottom = 12.dp)
            )

            PermissionRow(
                icon = Icons.Default.MyLocation,
                title = "Location",
                description = "Resolve your home time zone from your current position.",
                granted = locationGranted,
                onGrant = { locationLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION) },
                onOpenSettings = ::openAppSettings,
            )
            PermissionDivider()
            PermissionRow(
                icon = Icons.Default.NotificationsActive,
                title = "Notifications",
                description = "Post reminders before planned events.",
                granted = notificationsGranted,
                applicable = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
                onGrant = { notificationsLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) },
                onOpenSettings = ::openAppSettings,
            )
            PermissionDivider()
            PermissionRow(
                icon = Icons.Default.CalendarMonth,
                title = "Calendar",
                description = "Show your device calendar on the planner.",
                granted = calendarGranted,
                onGrant = { calendarLauncher.launch(Manifest.permission.READ_CALENDAR) },
                onOpenSettings = ::openAppSettings,
            )
            PermissionDivider()
            PermissionRow(
                icon = Icons.Default.Contacts,
                title = "Contacts",
                description = "Import people into the planner from your address book.",
                granted = contactsGranted,
                onGrant = { contactsLauncher.launch(Manifest.permission.READ_CONTACTS) },
                onOpenSettings = ::openAppSettings,
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
        granted -> Color(0xFF4CAF50)
        else -> MaterialTheme.colorScheme.error.copy(alpha = 0.85f)
    }

    Column {
        Row(verticalAlignment = Alignment.Top) {
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
                    Text(title, color = onSurface, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                    Text(statusLabel, color = statusColor, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                }
                Text(
                    description,
                    color = onSurface.copy(alpha = 0.5f),
                    fontSize = 12.sp,
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
        }
        if (applicable && !granted) {
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = onGrant,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Allow")
                }
                TextButton(onClick = onOpenSettings) {
                    Text("System settings")
                }
            }
        }
    }
}

@Composable
private fun AppearanceCard(settings: MeridianSettings, viewModel: MainViewModel, hazeState: HazeState) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    GlassCard(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = RoundedCornerShape(28.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Clock format", color = onSurface, fontWeight = FontWeight.Medium)
            Text(
                "Choose how every clock renders the hour.",
                color = onSurface.copy(alpha = 0.5f),
                fontSize = 12.sp,
                modifier = Modifier.padding(bottom = 8.dp)
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                HourCycleChip("System", settings.hourCycle == HourCycle.SYSTEM) {
                    viewModel.setHourCycle(HourCycle.SYSTEM)
                }
                HourCycleChip("12-hour", settings.hourCycle == HourCycle.H12) {
                    viewModel.setHourCycle(HourCycle.H12)
                }
                HourCycleChip("24-hour", settings.hourCycle == HourCycle.H24) {
                    viewModel.setHourCycle(HourCycle.H24)
                }
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
                enter = fadeIn() + expandVertically(),
                exit = fadeOut() + shrinkVertically(),
            ) {
                BackdropIntensitySlider(
                    intensity = settings.backdropIntensity,
                    onIntensityChange = viewModel::setBackdropIntensity,
                )
            }

            Spacer(Modifier.height(20.dp))

            Text("World map style", color = onSurface, fontWeight = FontWeight.Medium)
            Text(
                "Realistic uses the full photo texture, atmosphere and night-lights. Balanced keeps " +
                    "the texture but drops the heavy effects. Performance shades a flat globe. Vector " +
                    "is a 2D flat outline map (tiny, crisp, recolors with the theme).",
                color = onSurface.copy(alpha = 0.5f),
                fontSize = 12.sp,
                modifier = Modifier.padding(top = 2.dp, bottom = 8.dp)
            )
            val mapStyleOptions = listOf(
                "Realistic" to MapStyle.REALISTIC,
                "Balanced" to MapStyle.BALANCED,
                "Performance" to MapStyle.PERFORMANCE,
                "Vector" to MapStyle.VECTOR,
            )
            ScrollableChipRow(
                selectedIndex = mapStyleOptions.indexOfFirst { it.second == settings.mapStyle },
            ) {
                items(mapStyleOptions) { (label, style) ->
                    MapStyleChip(label, settings.mapStyle == style) {
                        viewModel.setMapStyle(style)
                    }
                }
            }
        }
    }
}

@Composable
private fun MapStyleChip(label: String, selected: Boolean, onClick: () -> Unit) {
    val haptics = LocalHapticFeedback.current
    FilterChip(
        selected = selected,
        onClick = {
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            onClick()
        },
        label = { Text(label) },
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
            selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer
        )
    )
}

@Composable
private fun GlassOpacitySlider(
    opacity: Int,
    onOpacityChange: (Int) -> Unit,
) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val haptics = LocalHapticFeedback.current
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Agenda & scrubber glass",
                color = onSurface,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = when (opacity) {
                    in MIN_GLASS_OPACITY..24 -> "Transparent"
                    in 25..49 -> "Light"
                    in 50..74 -> "Medium"
                    else -> "Opaque"
                },
                color = onSurface.copy(alpha = 0.6f),
                fontSize = 12.sp,
            )
        }
        Text(
            text = "Glass opacity and contrast for the agenda pill, the compact scrubber pill, " +
                "and the expanded time dial. Higher means a more solid, legible card.",
            color = onSurface.copy(alpha = 0.5f),
            fontSize = 12.sp,
            modifier = Modifier.padding(top = 2.dp, bottom = 4.dp),
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
            colors = SliderDefaults.colors(
                thumbColor = MaterialTheme.colorScheme.primary,
                activeTrackColor = MaterialTheme.colorScheme.primary,
                inactiveTrackColor = MaterialTheme.colorScheme.surfaceVariant,
            ),
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text = "Transparent",
                color = onSurface.copy(alpha = 0.45f),
                fontSize = 11.sp,
            )
            Text(
                text = "Opaque",
                color = onSurface.copy(alpha = 0.45f),
                fontSize = 11.sp,
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
                color = onSurface,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = "$intensity%",
                color = onSurface.copy(alpha = 0.6f),
                fontSize = 12.sp,
            )
        }
        Text(
            text = "How strongly the sun and moon glow through the glass.",
            color = onSurface.copy(alpha = 0.5f),
            fontSize = 12.sp,
            modifier = Modifier.padding(top = 2.dp, bottom = 4.dp),
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
            colors = SliderDefaults.colors(
                thumbColor = MaterialTheme.colorScheme.primary,
                activeTrackColor = MaterialTheme.colorScheme.primary,
                inactiveTrackColor = MaterialTheme.colorScheme.surfaceVariant,
            ),
        )
    }
}

@Composable
private fun HourCycleChip(label: String, selected: Boolean, onClick: () -> Unit) {
    val haptics = LocalHapticFeedback.current
    FilterChip(
        selected = selected,
        onClick = {
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            onClick()
        },
        label = { Text(label) },
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
            selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer
        )
    )
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
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, color = onSurface, fontWeight = FontWeight.Medium)
            Text(subtitle, color = onSurface.copy(alpha = 0.5f), fontSize = 12.sp)
        }
        Switch(
            checked = checked,
            onCheckedChange = {
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                onCheckedChange(it)
            },
            colors = SwitchDefaults.colors(
                checkedThumbColor = MaterialTheme.colorScheme.onPrimary,
                checkedTrackColor = MaterialTheme.colorScheme.primary
            )
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

    GlassCard(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = RoundedCornerShape(28.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
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
                        color = onSurface,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = "Your usual base for the Now card and planning. Resolved on-device — never sent anywhere.",
                        color = onSurface.copy(alpha = 0.5f),
                        fontSize = 12.sp
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = {
                    if (viewModel.hasLocationPermission()) resolve()
                    else permissionLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
                },
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.MyLocation, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Use my location")
            }
            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                onClick = { showCityPicker = true },
                shape = RoundedCornerShape(12.dp),
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
                        Text(it, color = onSurface.copy(alpha = 0.7f), fontSize = 12.sp)
                    }
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
    var status by remember { mutableStateOf<String?>(null) }
    var showCityPicker by remember { mutableStateOf(false) }

    GlassCard(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = RoundedCornerShape(28.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            SettingSwitchRow(
                title = "Home country",
                subtitle = "Show your origin country clock on the Now card — e.g. India for family calls.",
                checked = settings.homeCountryEnabled,
                onCheckedChange = { viewModel.setHomeCountryEnabled(it) }
            )
            AnimatedVisibility(
                visible = settings.homeCountryEnabled,
                enter = fadeIn() + expandVertically(),
                exit = fadeOut() + shrinkVertically()
            ) {
                Column {
                    Spacer(Modifier.height(12.dp))
                    HorizontalDivider(color = onSurface.copy(alpha = 0.08f))
                    Spacer(Modifier.height(12.dp))
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
                                text = homeCountry?.let { "City · ${it.displayName}" } ?: "No city chosen",
                                color = onSurface,
                                fontWeight = FontWeight.Medium
                            )
                            Text(
                                text = "Pick the city that represents your home country time zone.",
                                color = onSurface.copy(alpha = 0.5f),
                                fontSize = 12.sp
                            )
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                    OutlinedButton(
                        onClick = { showCityPicker = true },
                        shape = RoundedCornerShape(12.dp),
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
                                Text(it, color = onSurface.copy(alpha = 0.7f), fontSize = 12.sp)
                            }
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
private fun AiEngineCard(hazeState: HazeState) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    GlassCard(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = RoundedCornerShape(28.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.Memory,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    text = "Gemini Nano · on-device",
                    color = onSurface,
                    fontWeight = FontWeight.Medium
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(
                text = "The Assistant runs Gemini Nano directly on your device when supported — no API key, and your prompts never leave the phone. On devices without on-device support it transparently falls back to cloud Gemini.",
                color = onSurface.copy(alpha = 0.5f),
                fontSize = 12.sp,
                modifier = Modifier.padding(bottom = 12.dp)
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Outlined.CheckCircle,
                    contentDescription = null,
                    tint = Color(0xFF4CAF50),
                    modifier = Modifier.size(16.dp)
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    text = "On-device first · no key required",
                    color = onSurface.copy(alpha = 0.7f),
                    fontSize = 12.sp
                )
            }
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
    val leadTimeOptions = listOf(
        -1 to "Disabled",
        5 to "5m",
        10 to "10m",
        15 to "15m",
        30 to "30m",
        60 to "1h"
    )

    GlassCard(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = RoundedCornerShape(28.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.NotificationsActive,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(Modifier.width(8.dp))
                Text("Alarm Lead Time", color = onSurface, fontWeight = FontWeight.Medium)
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "Adjust how many minutes prior to an event the system notification alarm triggers.",
                color = onSurface.copy(alpha = 0.5f),
                fontSize = 12.sp,
                modifier = Modifier.padding(bottom = 12.dp)
            )

            val remindersHaptics = LocalHapticFeedback.current
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                leadTimeOptions.forEach { (minutes, label) ->
                    val isSelected = settings.reminderLeadMinutes == minutes
                    FilterChip(
                        selected = isSelected,
                        onClick = {
                            remindersHaptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            viewModel.setReminderLeadMinutes(minutes)
                        },
                        label = { Text(label) },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                            selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer
                        )
                    )
                }
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
    GlassCard(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = RoundedCornerShape(28.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.Work,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(Modifier.width(8.dp))
                Text("Default Work Hours", color = onSurface, fontWeight = FontWeight.Medium)
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "Define the starting point and ending point for standard business hours. New participants in the planner default to these values.",
                color = onSurface.copy(alpha = 0.5f),
                fontSize = 12.sp,
                modifier = Modifier.padding(bottom = 12.dp)
            )

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SettingsHourStepperRow(
                    label = "Work Start Hour",
                    value = settings.defaultWorkStartHour,
                    onChange = { viewModel.setDefaultWorkStartHour(it) }
                )
                SettingsHourStepperRow(
                    label = "Work End Hour",
                    value = settings.defaultWorkEndHour,
                    onChange = { viewModel.setDefaultWorkEndHour(it) }
                )
            }
        }
    }
}

@Composable
private fun SettingsHourStepperRow(
    label: String,
    value: Int,
    onChange: (Int) -> Unit
) {
    val haptics = LocalHapticFeedback.current
    val onSurface = MaterialTheme.colorScheme.onSurface
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(
            text = label,
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodyMedium,
            color = onSurface
        )
        IconButton(
            onClick = {
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                onChange((value + 23) % 24)
            }
        ) {
            Icon(
                imageVector = Icons.Filled.Remove,
                contentDescription = "Decrease",
                tint = MaterialTheme.colorScheme.primary
            )
        }
        Text(
            text = "%02d:00".format(value),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = onSurface
        )
        IconButton(
            onClick = {
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                onChange((value + 1) % 24)
            }
        ) {
            Icon(
                imageVector = Icons.Filled.Add,
                contentDescription = "Increase",
                tint = MaterialTheme.colorScheme.primary
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
        shape = RoundedCornerShape(28.dp)
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
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
                Text("On-device first validation", color = onSurface, fontWeight = FontWeight.Medium)
                Text(
                    "All time-zone lookups and slot math run on-device. Cloud AI is an opt-in fallback only.",
                    color = onSurface.copy(alpha = 0.5f),
                    fontSize = 12.sp
                )
            }
        }
    }
}

@Composable
private fun ReseedCard(viewModel: MainViewModel, hazeState: HazeState) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    var seeded by remember { mutableStateOf(false) }
    val buttonContainerColor by animateColorAsState(
        targetValue = if (seeded) MaterialTheme.colorScheme.secondaryContainer
                      else MaterialTheme.colorScheme.primaryContainer,
        label = "reseedButtonColor"
    )
    val buttonContentColor by animateColorAsState(
        targetValue = if (seeded) MaterialTheme.colorScheme.onSecondaryContainer
                      else MaterialTheme.colorScheme.onPrimaryContainer,
        label = "reseedContentColor"
    )
    GlassCard(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = RoundedCornerShape(28.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Seed starter zones", color = onSurface, fontWeight = FontWeight.Medium)
            Text(
                text = "Adds London, Tokyo, and New York to your pinned zones.",
                color = onSurface.copy(alpha = 0.5f),
                fontSize = 12.sp,
                modifier = Modifier.padding(bottom = 12.dp)
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
                shape = RoundedCornerShape(12.dp),
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
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Google Privacy Policy")
                }
                Spacer(Modifier.height(8.dp))
                OutlinedButton(
                    onClick = { openWebUrl(context, SettingsUrls.FIREBASE_TERMS) },
                    shape = RoundedCornerShape(12.dp),
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

    GlassCard(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = RoundedCornerShape(28.dp),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            MeridianWordmark(modifier = Modifier.padding(bottom = 8.dp))
            Text(
                text = "Time & world planner",
                color = onSurface.copy(alpha = 0.6f),
                fontSize = 13.sp,
            )
            Spacer(Modifier.height(8.dp))
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(12.dp))
                    .clickable {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        clipboard.setText(AnnotatedString(buildDiagnosticText(context)))
                        copied = true
                    }
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = if (copied) "Diagnostics copied" else "Version $versionLabel",
                    color = if (copied) MaterialTheme.colorScheme.primary else onSurface.copy(alpha = 0.5f),
                    fontSize = 12.sp,
                )
                if (!copied) {
                    Spacer(Modifier.width(6.dp))
                    Icon(
                        Icons.Default.ContentCopy,
                        contentDescription = "Copy diagnostics",
                        tint = onSurface.copy(alpha = 0.35f),
                        modifier = Modifier.size(14.dp),
                    )
                }
            }
            if (BuildConfig.DEBUG) {
                Spacer(Modifier.height(6.dp))
                Text(
                    text = "Debug build",
                    color = MaterialTheme.colorScheme.tertiary,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            Spacer(Modifier.height(12.dp))
            Text(
                text = "Local clocks, multi-zone planning, and optional on-device AI — built with a privacy-first, on-device engine.",
                color = onSurface.copy(alpha = 0.65f),
                fontSize = 13.sp,
                lineHeight = 18.sp,
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
        shape = RoundedCornerShape(28.dp),
    ) {
        Column(modifier = Modifier.padding(vertical = 8.dp)) {
            Text(
                text = "Legal & privacy",
                color = onSurface,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
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
        shape = RoundedCornerShape(28.dp),
    ) {
        Column(modifier = Modifier.padding(vertical = 8.dp)) {
            Text(
                text = "Support",
                color = onSurface,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
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

    GlassCard(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = RoundedCornerShape(28.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Manage local data", color = onSurface, fontWeight = FontWeight.Medium)
            Text(
                text = "Meridian stores zones, planner data, and preferences on this device. " +
                    "Clear storage from system settings to remove everything — this cannot be undone.",
                color = onSurface.copy(alpha = 0.5f),
                fontSize = 12.sp,
                lineHeight = 17.sp,
                modifier = Modifier.padding(top = 6.dp, bottom = 12.dp),
            )
            OutlinedButton(
                onClick = { openAppSettings(context) },
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Default.Storage, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Open app storage settings")
            }
        }
    }
}

@Composable
private fun SettingsFooter() {
    val onSurface = MaterialTheme.colorScheme.onSurface
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = "© ${java.util.Calendar.getInstance().get(java.util.Calendar.YEAR)} Meridian",
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
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable {
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                onClick()
            }
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
            Text(title, color = onSurface, fontWeight = FontWeight.Medium)
            Text(subtitle, color = onSurface.copy(alpha = 0.5f), fontSize = 12.sp)
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
