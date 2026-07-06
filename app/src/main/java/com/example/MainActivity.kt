package com.example

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.core.content.ContextCompat
import androidx.compose.foundation.layout.Box
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navDeepLink
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import com.example.MainViewModel
import com.example.MainViewModelFactory
import android.app.Application
import android.content.Intent
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavGraph.Companion.findStartDestination
import com.example.feature.now.NowScreen
import com.example.feature.onboarding.OnboardingOverlay
import com.example.feature.worldclock.WorldClockScreen
import com.example.feature.planner.PlanScreen
import com.example.core.designsystem.CelestialBackdrop
import com.example.core.designsystem.LocalGlassEnabled
import com.example.core.designsystem.LocalReduceTransparencyOverride
import com.example.core.designsystem.LocalGlassOpacity
import com.example.core.designsystem.LocalTabBarInsetHeight
import com.example.core.designsystem.LocalBarScrollConnection
import com.example.core.designsystem.LocalReduceMotion
import com.example.core.designsystem.rememberReduceMotion
import com.example.core.designsystem.Motion
import com.example.core.designsystem.MeridianExpressiveTheme
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import com.example.ui.components.BottomAccessory
import com.example.ui.components.GlassNavBar
import com.example.ui.components.GlassNavRail
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource

// Scroll-delta thresholds for the minimize-on-scroll nav bar. A firm downward pull collapses the
// bar; re-expanding demands a slightly firmer upward pull. That asymmetry is the hysteresis that
// stops sub-pixel scroll jitter / fling-settle near the boundary from flickering the bar between
// its pill and full states (see barScrollConnection).
private const val BarCollapseThreshold = 5f
private const val BarExpandThreshold = 8f

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // enableEdgeToEdge() turns on isNavigationBarContrastEnforced, which makes the system paint
        // a translucent scrim behind the 3-button nav bar. That grey band fights the floating
        // GlassNavBar and the edge-to-edge glass sheets, so disable it (API 29+) to keep the bottom
        // edge consistently transparent.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
        // Keep the Live Update countdown fresh; WorkManager is initialized by app startup here.
        com.example.core.notify.LiveUpdates.schedulePeriodic(this)
        setContent {
            MeridianExpressiveTheme {
                MainAppHost()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        // Pull whatever ChronosFlow has shared every time Meridian comes to the foreground, so
        // cross-app tasks show up promptly without needing a cold restart.
        val app = application as MeridianApplication
        lifecycleScope.launch { app.container.interopSyncManager.syncFromPeer() }
    }
}

@Composable
fun MainAppHost() {
    val context = LocalContext.current
    val application = context.applicationContext as Application
    val viewModel: MainViewModel = viewModel(
        factory = MainViewModelFactory(application)
    )

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, viewModel) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> viewModel.prewarmAi()
                Lifecycle.Event.ON_STOP -> viewModel.releaseAiModels()
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route ?: "now"

    // Window size class (approx): medium/expanded gets a side rail, compact gets the bottom bar (§6).
    val wideLayout = LocalConfiguration.current.screenWidthDp >= 600
    val onNavigate: (String) -> Unit = remember(navController) {
        { route ->
            navController.navigate(route) {
                // Keep the bottom-nav back stack flat (one tab deep). We deliberately omit
                // saveState/restoreState: paired with the meridian:// deep links, restoreState
                // could resurrect a deep-linked tab's saved back stack when a *different* tab was
                // tapped — e.g. opening via a "meridian://plan" reminder then tapping Now left you
                // stuck on Plan instead of going Home.
                popUpTo(navController.graph.findStartDestination().id)
                launchSingleTop = true
            }
        }
    }

    val hazeState = remember { HazeState() }
    // OS "remove animations" / animator-duration-scale signal. Consumed across the app via
    // LocalReduceMotion (nav bar, scrubber, accessory, pickers) but only *provided* here at the
    // root — so every spring falls back to an instant transition when the user has motion reduced.
    val reduceMotion = rememberReduceMotion()
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val plannedTasks by viewModel.plannedTasks.collectAsStateWithLifecycle()
    val scrubInstant by viewModel.scrubInstant.collectAsStateWithLifecycle()
    val accessoryEnabled = currentRoute !in setOf("world", "plan", "ai") && scrubInstant == null
    var pendingWorldCityPicker by remember { mutableStateOf(false) }

    fun consumeAddZoneDeepLinkIfNeeded() {
        val intent = (context as? Activity)?.intent ?: return
        if (intent.data?.host == "addzone") {
            pendingWorldCityPicker = true
            intent.data = null
        }
    }

    LaunchedEffect(navBackStackEntry?.id) {
        if (currentRoute == "world") consumeAddZoneDeepLinkIfNeeded()
    }

    LifecycleResumeEffect(currentRoute) {
        if (currentRoute == "world") consumeAddZoneDeepLinkIfNeeded()
        onPauseOrDispose { }
    }

    // Ask for notification permission once on first launch (Android 13+) so reminders can post.
    val notificationPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* Reminders degrade silently if denied; the in-app countdown still works. */ }
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    // Minimize-on-scroll: collapse the glass bar to a pill when scrolling down content,
    // expand it on scroll up (§4). Driven by the nested-scroll deltas of any child list.
    var barCollapsed by remember { mutableStateOf(false) }
    LaunchedEffect(currentRoute) {
        barCollapsed = false
    }
    // Hysteresis: a firm downward pull collapses the bar to a pill, a firm upward pull expands it.
    // The dead-band between the two thresholds keeps sub-pixel scroll jitter near the boundary from
    // rapidly toggling the bar (flicker between pill and full). GlassNavBar spring-animates the state
    // change, so the boolean is only flipped on a genuine direction change.
    val barScrollConnection = remember {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (available.y < -BarCollapseThreshold && !barCollapsed) barCollapsed = true
                else if (available.y > BarExpandThreshold && barCollapsed) barCollapsed = false
                return Offset.Zero
            }
        }
    }

    val tabBarInsetHeight by animateDpAsState(
        targetValue = when {
            wideLayout -> 0.dp
            barCollapsed -> 72.dp
            else -> 96.dp
        },
        animationSpec = Motion.smooth(),
        label = "tabBarInset",
    )

    CompositionLocalProvider(
        LocalGlassEnabled provides settings.glassEnabled,
        LocalReduceTransparencyOverride provides settings.reduceTransparency,
        LocalGlassOpacity provides settings.glassOpacity,
        LocalTabBarInsetHeight provides tabBarInsetHeight,
        LocalBarScrollConnection provides barScrollConnection,
        // Bridge the OS animator-scale / "remove animations" signal to every LocalReduceMotion
        // consumer (nav bar press scale, scrubber pill, accessory slide, search pickers). Without a
        // provider here it defaulted to `false`, so reduce-motion was silently a no-op app-wide.
        LocalReduceMotion provides reduceMotion,
        // The app content sits on a gradient Box rather than a Material Surface, so nothing
        // provides a theme-driven content color. Without this, LocalContentColor stays at its
        // default (Color.Black) and any Text that doesn't set an explicit color renders black on
        // the dark background. Provide onBackground so default text follows the Material scheme.
        LocalContentColor provides MaterialTheme.colorScheme.onBackground,
    ) {
    // Background is theme-driven (dynamic color by default, §12.15) — a subtle
    // vertical gradient from surface to background so the glass layer has depth to refract.
    Box(modifier = Modifier
        .fillMaxSize()
        .nestedScroll(barScrollConnection)
    ) {
        // Everything inside this Box is the Haze source. The gradient lives here so it is always
        // captured by hazeSource — glass blur draws from this layer whether or not the celestial
        // backdrop is enabled, giving surfaces a coloured base to refract against in both states.
        Box(modifier = Modifier
            .fillMaxSize()
            .background(
                brush = Brush.verticalGradient(
                    colors = listOf(
                        MaterialTheme.colorScheme.surface,
                        MaterialTheme.colorScheme.background
                    )
                )
            )
            .hazeSource(state = hazeState)
        ) {
        if (settings.backdropEnabled) {
            CelestialBackdrop(
                modifier = Modifier.fillMaxSize(),
                intensity = settings.backdropIntensity / 100f,
            )
        }
        // Tab transitions carry the same spring physics as in-screen animation (north-star forbids
        // linear-eased tweens for user-facing navigation): a smooth settle-in on enter, a snappy
        // fade-away on exit. Under reduce-motion the scale zoom is dropped for a plain fade so
        // vestibular-sensitive users aren't subjected to a zoom on every tab switch.
        val navEnter: EnterTransition = if (reduceMotion) {
            fadeIn(animationSpec = Motion.smooth())
        } else {
            fadeIn(animationSpec = Motion.smooth()) +
                scaleIn(initialScale = 0.96f, animationSpec = Motion.smooth())
        }
        val navExit: ExitTransition = if (reduceMotion) {
            fadeOut(animationSpec = Motion.snappy())
        } else {
            fadeOut(animationSpec = Motion.snappy()) +
                scaleOut(targetScale = 0.96f, animationSpec = Motion.snappy())
        }
        NavHost(
            navController = navController,
            startDestination = "now",
            enterTransition = { navEnter },
            exitTransition = { navExit },
            popEnterTransition = { navEnter },
            popExitTransition = { navExit },
            modifier = Modifier
                .padding(start = if (wideLayout) 96.dp else 0.dp)
        ) {
            composable("now") { NowScreen(viewModel = viewModel, hazeState = hazeState, onNavigate = onNavigate) }
            composable(
                "world",
                deepLinks = listOf(
                    navDeepLink { uriPattern = "meridian://world" },
                    navDeepLink { uriPattern = "meridian://addzone" },
                )
            ) {
                WorldClockScreen(
                    viewModel = viewModel,
                    hazeState = hazeState,
                    openCityPickerOnLaunch = pendingWorldCityPicker,
                    onCityPickerLaunchConsumed = { pendingWorldCityPicker = false },
                )
            }
            composable("ai") { com.example.feature.ai.AiScreen(viewModel = viewModel, hazeState = hazeState) }
            composable(
                "plan",
                deepLinks = listOf(navDeepLink { uriPattern = "meridian://plan" })
            ) { PlanScreen(viewModel = viewModel, hazeState = hazeState, onNavigate = onNavigate) }
            composable("settings") { com.example.feature.settings.SettingsScreen(viewModel = viewModel, hazeState = hazeState) }
        }
        }

        if (wideLayout) {
            GlassNavRail(
                hazeState = hazeState,
                currentRoute = currentRoute,
                onNavigate = onNavigate,
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .padding(start = 12.dp)
            )

            BottomAccessory(
                tasks = plannedTasks,
                hazeState = hazeState,
                enabled = accessoryEnabled,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(start = 96.dp, bottom = 24.dp),
                onTap = { onNavigate("plan") },
            )
        } else {
            BottomAccessory(
                tasks = plannedTasks,
                hazeState = hazeState,
                enabled = accessoryEnabled,
                modifier = Modifier.align(Alignment.BottomCenter),
                onTap = { onNavigate("plan") },
            )

            GlassNavBar(
                hazeState = hazeState,
                currentRoute = currentRoute,
                onNavigate = onNavigate,
                collapsed = barCollapsed,
                modifier = Modifier.align(Alignment.BottomCenter)
            )
        }

        if (!settings.onboardingComplete) {
            // Modal trap: the live NavHost + nav bar underneath stay composed and focusable, so
            // without this a TalkBack swipe or residual scroll could reach the Now screen behind the
            // scrim. A full-bleed no-op clickable above the app content (but below OnboardingOverlay)
            // swallows every tap and keeps focus/scroll from leaking through, making onboarding truly
            // modal for touch, switch-access and TalkBack users.
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        onClickLabel = null,
                        onClick = { },
                    )
                    .semantics { isTraversalGroup = true }
            )
            OnboardingOverlay(
                hazeState = hazeState,
                onFinish = { viewModel.setOnboardingComplete(true) },
            )
        }
    }
    }
}
