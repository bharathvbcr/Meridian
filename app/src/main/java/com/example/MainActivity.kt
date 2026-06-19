package com.example

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.runtime.LaunchedEffect
import androidx.core.content.ContextCompat
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.background
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
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
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavGraph.Companion.findStartDestination
import com.example.feature.now.NowScreen
import com.example.feature.worldclock.WorldClockScreen
import com.example.feature.planner.PlanScreen
import com.example.core.designsystem.CelestialBackdrop
import com.example.core.designsystem.LocalGlassEnabled
import com.example.core.designsystem.LocalReduceTransparencyOverride
import com.example.core.designsystem.LocalGlassOpacity
import com.example.core.designsystem.MeridianExpressiveTheme
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import com.example.ui.components.BottomAccessory
import com.example.ui.components.GlassNavBar
import com.example.ui.components.GlassNavRail
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Keep the Live Update countdown fresh; WorkManager is initialized by app startup here.
        com.example.core.notify.LiveUpdates.schedulePeriodic(this)
        setContent {
            MeridianExpressiveTheme {
                MainAppHost()
            }
        }
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

    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route ?: "now"

    // Window size class (approx): medium/expanded gets a side rail, compact gets the bottom bar (§6).
    val wideLayout = LocalConfiguration.current.screenWidthDp >= 600
    val onNavigate: (String) -> Unit = { route ->
        navController.navigate(route) {
            popUpTo(navController.graph.findStartDestination().id) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }
    
    val hazeState = remember { HazeState() }
    val settings by viewModel.settings.collectAsState()
    val plannedTasks by viewModel.plannedTasks.collectAsState()
    val scrubInstant by viewModel.scrubInstant.collectAsState()
    val accessoryEnabled = currentRoute !in setOf("world", "plan", "ai") && scrubInstant == null

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
    val barScrollConnection = remember {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (available.y < -3f) barCollapsed = true
                else if (available.y > 3f) barCollapsed = false
                return Offset.Zero
            }
        }
    }

    CompositionLocalProvider(
        LocalGlassEnabled provides settings.glassEnabled,
        LocalReduceTransparencyOverride provides settings.reduceTransparency,
        LocalGlassOpacity provides settings.glassOpacity,
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
        NavHost(
            navController = navController,
            startDestination = "now",
            enterTransition = {
                fadeIn(animationSpec = tween(durationMillis = 220, easing = FastOutSlowInEasing)) +
                scaleIn(initialScale = 0.96f, animationSpec = tween(durationMillis = 220, easing = FastOutSlowInEasing))
            },
            exitTransition = {
                fadeOut(animationSpec = tween(durationMillis = 180, easing = FastOutSlowInEasing)) +
                scaleOut(targetScale = 0.96f, animationSpec = tween(durationMillis = 180, easing = FastOutSlowInEasing))
            },
            popEnterTransition = {
                fadeIn(animationSpec = tween(durationMillis = 220, easing = FastOutSlowInEasing)) +
                scaleIn(initialScale = 0.96f, animationSpec = tween(durationMillis = 220, easing = FastOutSlowInEasing))
            },
            popExitTransition = {
                fadeOut(animationSpec = tween(durationMillis = 180, easing = FastOutSlowInEasing)) +
                scaleOut(targetScale = 0.96f, animationSpec = tween(durationMillis = 180, easing = FastOutSlowInEasing))
            },
            modifier = Modifier
                .padding(start = if (wideLayout) 96.dp else 0.dp)
        ) {
            composable("now") { NowScreen(viewModel = viewModel, hazeState = hazeState) }
            composable(
                "world",
                deepLinks = listOf(navDeepLink { uriPattern = "meridian://world" })
            ) { WorldClockScreen(viewModel = viewModel, hazeState = hazeState) }
            composable("ai") { com.example.feature.ai.AiScreen(viewModel = viewModel, hazeState = hazeState) }
            composable(
                "plan",
                deepLinks = listOf(navDeepLink { uriPattern = "meridian://plan" })
            ) { PlanScreen(viewModel = viewModel, hazeState = hazeState) }
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
        } else {
            BottomAccessory(
                tasks = plannedTasks,
                hazeState = hazeState,
                enabled = accessoryEnabled,
                modifier = Modifier.align(Alignment.BottomCenter)
            )

            GlassNavBar(
                hazeState = hazeState,
                currentRoute = currentRoute,
                onNavigate = onNavigate,
                collapsed = barCollapsed,
                modifier = Modifier.align(Alignment.BottomCenter)
            )
        }
    }
    }
}
