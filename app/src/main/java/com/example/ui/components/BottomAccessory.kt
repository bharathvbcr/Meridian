package com.example.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.core.data.PlannedTask
import com.example.core.designsystem.GlassDefaults
import com.example.core.designsystem.LiquidGlassSurface
import com.example.core.designsystem.LocalGlassOpacity
import com.example.core.designsystem.Motion
import com.example.core.designsystem.ScrubberGlass
import com.example.core.notify.Reminders
import dev.chrisbanes.haze.HazeState
import kotlinx.coroutines.delay

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
) {
    var nowMillis by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            nowMillis = System.currentTimeMillis()
            delay(1000)
        }
    }

    val next = remember(tasks, nowMillis) {
        tasks.filter { it.timestamp > nowMillis }.minByOrNull { it.timestamp }
    }
    val remaining = next?.let { it.timestamp - nowMillis }
    val withinWindow = remaining != null && remaining < Reminders.ACCESSORY_WINDOW_MILLIS

    AnimatedVisibility(
        visible = enabled && withinWindow,
        enter = slideInVertically(Motion.bouncy()) { it } + fadeIn(),
        exit = slideOutVertically(Motion.smooth()) { it } + fadeOut(),
        modifier = modifier,
    ) {
        val task = next ?: return@AnimatedVisibility
        LiquidGlassSurface(
            hazeState = hazeState,
            modifier = Modifier
                .navigationBarsPadding()
                .padding(bottom = 96.dp, start = 24.dp, end = 24.dp),
            shape = RoundedCornerShape(50),
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
                        shape = RoundedCornerShape(50),
                    )
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
            ) {
                Icon(
                imageVector = Icons.Default.Schedule,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.width(10.dp))
            Text(
                text = task.title,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.width(8.dp))
            val countdown = task.timestamp - nowMillis
            Text(
                text = "in ${Reminders.formatCountdown(countdown)}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.error,
            )
            }
        }
    }
}
