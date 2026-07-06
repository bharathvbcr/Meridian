package com.example.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.example.core.data.PlannedTask
import com.example.core.designsystem.GlassDefaults
import com.example.core.designsystem.LiquidGlassSurface
import com.example.core.designsystem.LocalGlassOpacity
import com.example.core.designsystem.LocalReduceMotion
import com.example.core.designsystem.Motion
import com.example.core.designsystem.ScrubberGlass
import com.example.core.notify.Reminders
import dev.chrisbanes.haze.HazeState
import kotlinx.coroutines.delay

/**
 * Full-pill corner for the accessory surface and its inner scrim. A single private token so the
 * outer glass surface and the legibility scrim can never drift apart (they must clip identically),
 * mirroring the pill treatment on the time scrubber. Kept local because [GlassDefaults] exposes only
 * card/menu radii; promoting a shared pill token belongs in that file, not here.
 */
private val AccessoryPillShape: Shape = RoundedCornerShape(percent = 50)

// The accessory floats one control layer above the nav bar rather than stacking on it, so its
// bottom offset is derived from the bar's own geometry instead of a magic 96dp: if the bar height
// or its inset changes, the accessory stays aligned. These mirror GlassNavBar's own literals; they
// live here privately because that composable does not export them.
private val NavBarHeight: Dp = 72.dp
private val NavBarBottomInset: Dp = 16.dp
private val AccessoryNavBarGap: Dp = 8.dp

/** Comfortable vertical touch target for the whole tappable accessory (Android's 48dp minimum). */
private val AccessoryMinTouchTarget: Dp = 48.dp

/**
 * The glass bar's "now playing"-style bottom accessory (§4): a slim strip that surfaces the next
 * upcoming event with a live countdown. Materializes only when the next event is within one hour,
 * and sits above the nav bar on the same glass control layer (never stacked on it).
 */
@Composable
fun BottomAccessory(
    tasks: List<PlannedTask>,
    hazeState: HazeState,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
    onTap: (() -> Unit)? = null,
) {
    var nowMillis by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val lifecycleOwner = LocalLifecycleOwner.current
    LaunchedEffect(tasks, lifecycleOwner) {
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
            // Tick every second only while the countdown pill is visible; otherwise sleep until
            // the next event approaches the accessory window (or a minute, whichever is sooner).
            // This composable sits on every tab, so an unconditional 1 s tick would recompose it
            // app-wide even when nothing is shown.
            while (true) {
                val now = System.currentTimeMillis()
                nowMillis = now
                val nextTs = tasks.filter { it.timestamp > now }.minOfOrNull { it.timestamp }
                val untilWindow = nextTs?.let { it - now - Reminders.ACCESSORY_WINDOW_MILLIS }
                delay(
                    when {
                        untilWindow == null -> 60_000L
                        untilWindow > 0L -> untilWindow.coerceAtMost(60_000L)
                        else -> 1_000L
                    }
                )
            }
        }
    }

    val next = remember(tasks, nowMillis) {
        tasks.filter { it.timestamp > nowMillis }.minByOrNull { it.timestamp }
    }
    val remaining = next?.let { it.timestamp - nowMillis }
    val withinWindow = remaining != null && remaining < Reminders.ACCESSORY_WINDOW_MILLIS

    // North-star: user-facing motion "Always respect Reduce Motion / animator scale". When the OS
    // preference is on, the accessory appears/disappears instantly instead of the spring slide.
    val reduceMotion = LocalReduceMotion.current

    AnimatedVisibility(
        visible = enabled && withinWindow,
        enter = if (reduceMotion) EnterTransition.None
        else slideInVertically(Motion.bouncy()) { it } + fadeIn(Motion.smooth()),
        exit = if (reduceMotion) ExitTransition.None
        else slideOutVertically(Motion.smooth()) { it } + fadeOut(Motion.smooth()),
        modifier = modifier,
    ) {
        val task = next ?: return@AnimatedVisibility
        val countdown = task.timestamp - nowMillis
        val countdownLabel = Reminders.formatCountdown(countdown)
        // One spoken sentence for the whole strip. TalkBack reads the merged node, and because the
        // Row is a Polite live region this re-announces as the countdown ticks the event closer.
        val accessoryDescription = "${task.title} in $countdownLabel"

        LiquidGlassSurface(
            hazeState = hazeState,
            modifier = Modifier
                .navigationBarsPadding()
                // Float one control layer above the nav bar: clear its height + inset, then a small
                // gap — derived from the bar's own geometry tokens rather than a single 96dp literal.
                .padding(
                    bottom = NavBarHeight + NavBarBottomInset + AccessoryNavBarGap,
                    start = 24.dp,
                    end = 24.dp,
                )
                .then(
                    if (onTap != null) {
                        Modifier
                            // Keep the tap surface a comfortable target even though the pill is slim.
                            .defaultMinSize(minHeight = AccessoryMinTouchTarget)
                            .clickable(onClick = onTap)
                    } else {
                        Modifier
                    }
                ),
            shape = AccessoryPillShape,
            tintColor = androidx.compose.ui.graphics.Color.Transparent,
            borderWidth = 1.dp,
            borderColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.4f),
            frosted = ScrubberGlass.alphas(LocalGlassOpacity.current).frosted,
        ) {
            Row(
                modifier = Modifier
                    // Solid scrim over the glass shader so the next-event title and countdown stay
                    // legible, matching the time scrubber pills.
                    .background(
                        color = GlassDefaults.accessoryPillTint,
                        shape = AccessoryPillShape,
                    )
                    .padding(horizontal = 16.dp, vertical = 10.dp)
                    // Group the decorative icon, title and countdown into one focusable node with a
                    // single spoken sentence; announce updates politely as the event approaches. When
                    // tappable, expose the button role + action hint (the chevron itself is decorative).
                    .semantics(mergeDescendants = true) {
                        contentDescription = accessoryDescription
                        liveRegion = LiveRegionMode.Polite
                        if (onTap != null) role = Role.Button
                    },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
            ) {
                Icon(
                    imageVector = Icons.Default.Schedule,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.width(8.dp))
                // Title reads first: titleSmall (14sp) dominates the smaller, error-colored countdown.
                Text(
                    text = task.title,
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Spacer(Modifier.width(8.dp))
                // Secondary urgency cue — smaller label so the error color signals urgency without
                // competing with the title for first read.
                Text(
                    text = "in $countdownLabel",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.error,
                )
                if (onTap != null) {
                    Spacer(Modifier.width(8.dp))
                    Icon(
                        imageVector = Icons.Default.KeyboardArrowUp,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                        modifier = Modifier.size(14.dp),
                    )
                }
            }
        }
    }
}
