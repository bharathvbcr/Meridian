package com.example.feature.planner

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.defaultMinSize
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
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.core.designsystem.GlassDefaults
import com.example.core.designsystem.Motion
import com.example.core.designsystem.LocalGlassOpacity
import com.example.core.designsystem.ScrubberGlass
import com.example.core.designsystem.ScrubberPillDefaults
import com.example.core.designsystem.detectScrubberPressDrag
import com.example.core.designsystem.liquidGlass
import com.example.core.time.FindOverlapUseCase.OverlapSlot
import com.example.core.time.TimeFormats
import dev.chrisbanes.haze.HazeState
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.abs

/**
 * One hour of the planning window. [slot] is null when the hour is filtered out (e.g. a weekend
 * with "Exclude weekends" on) — those render as muted, non-selectable bands.
 */
internal data class DialHour(
    val instant: java.time.Instant,
    val slot: OverlapSlot?,
    val ratingLabel: String?,
)

/**
 * Horizontal "fairness dial" across the 24 hours of the selected day. Colored bands mark
 * Optimal / Fair / Difficult hours; drag or tap snaps the handle to an hour. Shares the World
 * page's pill behavior ([TimelineScrubber][com.example.core.designsystem.TimelineScrubber]):
 * a compact glass pill that expands on press and supports drag-to-scrub without lifting.
 */
@Composable
internal fun FairSlotsScrubber(
    hours: List<DialHour>,
    selectedIndex: Int,
    localZoneId: String,
    durationMinutes: Int,
    is24Hour: Boolean,
    hazeState: HazeState,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (hours.isEmpty()) return
    val haptic = LocalHapticFeedback.current

    val optimalColor = MaterialTheme.colorScheme.primary
    val fairColor = MaterialTheme.colorScheme.tertiary
    val difficultColor = MaterialTheme.colorScheme.error
    val onSurfaceColor = MaterialTheme.colorScheme.onSurface
    // Material You elevated-card tone backing the blur, matching the World page scrubber.
    val cardSurfaceColor = GlassDefaults.scrubberCardTone
    val glassOpacity = LocalGlassOpacity.current
    val scrubberGlass = remember(glassOpacity) { ScrubberGlass.alphas(glassOpacity) }
    // Surface-colored halo behind the handle dot so the primary fill reads against ANY
    // band color (primary / tertiary / error) and the primary card tint.
    val handleRingColor = MaterialTheme.colorScheme.surface
    fun ratingColor(label: String?): Color = when (label) {
        "Optimal" -> optimalColor
        "Fair" -> fairColor
        "Difficult" -> difficultColor
        else -> onSurfaceColor.copy(alpha = 0.12f)
    }

    val selected = hours.getOrNull(selectedIndex) ?: hours.first()
    val selectedSlot = selected.slot

    // Pill label: "09:00–09:45 · Fair" for a workable hour, else just the time.
    val pillTime = remember(selected.instant, durationMinutes, localZoneId, is24Hour) {
        val zone = ZoneId.of(localZoneId)
        val start = ZonedDateTime.ofInstant(selected.instant, zone)
            .format(TimeFormats.hourMinuteWithContext(is24Hour))
        val end = ZonedDateTime.ofInstant(
            selected.instant.plusSeconds(durationMinutes * 60L), zone
        ).format(TimeFormats.hourMinute(is24Hour))
        "$start – $end"
    }

    // Pre-format a sparse set of hour labels (every 6th hour) for the dial track.
    val tickLabels = remember(hours, localZoneId, is24Hour) {
        hours.mapIndexed { index, h ->
            if (index % 6 == 0) {
                ZonedDateTime.ofInstant(h.instant, ZoneId.of(localZoneId))
                    .format(TimeFormats.hourMinute(is24Hour))
            } else null
        }
    }

    // --- Pill expand / auto-collapse, mirroring TimelineScrubber ---
    var expanded by remember { mutableStateOf(false) }
    var interactionTick by remember { mutableStateOf(0) }
    var dialPressed by remember { mutableStateOf(false) }
    LaunchedEffect(expanded, interactionTick, dialPressed) {
        if (expanded && !dialPressed) {
            kotlinx.coroutines.delay(400)
            expanded = false
        }
    }

    val pillScale by animateFloatAsState(
        targetValue = if (dialPressed) 0.94f else 1f,
        animationSpec = Motion.bouncy(),
        label = "fairPillScale"
    )

    val gestureContext = remember { object { var wasExpandedAtStart = false } }

    fun nearestSelectable(target: Int): Int {
        val clamped = target.coerceIn(0, hours.lastIndex)
        if (hours[clamped].slot != null) return clamped
        var best = -1
        var bestDist = Int.MAX_VALUE
        hours.forEachIndexed { i, h ->
            if (h.slot != null) {
                val d = abs(i - clamped)
                if (d < bestDist) { bestDist = d; best = i }
            }
        }
        return if (best >= 0) best else clamped
    }

    fun selectAt(target: Int) {
        val next = nearestSelectable(target)
        if (next != selectedIndex) {
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            onSelect(next)
        }
    }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .pointerInput(hours.size) {
                detectScrubberPressDrag(
                    onPressStart = {
                        gestureContext.wasExpandedAtStart = expanded
                        if (!expanded) {
                            expanded = true
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        }
                        dialPressed = true
                        interactionTick++
                    },
                    onDrag = { _, change ->
                        interactionTick++
                        val idx = (change.position.x / size.width * hours.size).toInt()
                        selectAt(idx)
                    },
                    onPressEnd = { dragged, releasePosition ->
                        dialPressed = false
                        interactionTick++
                        if (!dragged && gestureContext.wasExpandedAtStart) {
                            interactionTick++
                            val idx = (releasePosition.x / size.width * hours.size).toInt()
                            selectAt(idx)
                        }
                    },
                )
            },
        contentAlignment = Alignment.BottomCenter,
    ) {
    AnimatedContent(
        targetState = expanded,
        modifier = Modifier.fillMaxWidth(),
        transitionSpec = { Motion.scrubberExpandCollapseTransform(targetState) },
        contentAlignment = Alignment.BottomCenter,
        label = "fair_scrubber_expand"
    ) { isExpanded ->
        if (!isExpanded) {
            // ---- Collapsed pill ----
            Box(
                modifier = Modifier
                    .wrapContentWidth(Alignment.CenterHorizontally)
                    .defaultMinSize(
                        minWidth = ScrubberPillDefaults.minWidth,
                        minHeight = ScrubberPillDefaults.minHeight,
                    )
                    .scale(pillScale)
                    .clip(RoundedCornerShape(28.dp))
                    .liquidGlass(
                        hazeState = hazeState,
                        shape = RoundedCornerShape(28.dp),
                        tintColor = Color.Transparent,
                        borderWidth = 1.dp,
                        borderColor = optimalColor.copy(alpha = 0.4f),
                        frosted = scrubberGlass.frosted,
                    )
                    .background(
                        color = cardSurfaceColor.copy(alpha = scrubberGlass.pillTint),
                        shape = RoundedCornerShape(28.dp),
                    )
                    .padding(
                        horizontal = ScrubberPillDefaults.horizontalPadding,
                        vertical = ScrubberPillDefaults.verticalPadding,
                    )
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Default.Tune,
                        contentDescription = "Open fair-time dial",
                        tint = optimalColor,
                        modifier = Modifier.size(ScrubberPillDefaults.iconSize)
                    )
                    Spacer(Modifier.width(10.dp))
                    Text(
                        text = pillTime,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.ExtraBold,
                        color = onSurfaceColor.copy(alpha = 0.9f)
                    )
                    selected.ratingLabel?.let { label ->
                        Spacer(Modifier.width(10.dp))
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(50))
                                .background(ratingColor(label).copy(alpha = 0.18f))
                                .padding(horizontal = 10.dp, vertical = 4.dp)
                        ) {
                            Text(
                                text = label,
                                style = MaterialTheme.typography.labelMedium,
                                color = ratingColor(label),
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }
            }
            return@AnimatedContent
        }

        // ---- Expanded dial ----
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(24.dp))
                .liquidGlass(
                    hazeState = hazeState,
                    shape = RoundedCornerShape(24.dp),
                    tintColor = Color.Transparent,
                    borderWidth = 1.5.dp,
                    borderColor = optimalColor.copy(alpha = 0.5f),
                    frosted = scrubberGlass.frosted,
                )
                .background(
                    color = cardSurfaceColor.copy(alpha = scrubberGlass.cardTint),
                    shape = RoundedCornerShape(24.dp),
                )
                .padding(20.dp)
        ) {
            Column {
                Text(
                    text = "Fair-time dial",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.ExtraBold,
                    color = onSurfaceColor
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    text = "$pillTime · ${selected.ratingLabel ?: "No overlap"}",
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.SemiBold,
                    color = onSurfaceColor.copy(alpha = 0.9f)
                )

                Spacer(Modifier.height(16.dp))

                val labelStyle = TextStyle(
                    color = onSurfaceColor.copy(alpha = 0.85f),
                    fontSize = 10.sp,
                    fontWeight = FontWeight.SemiBold
                )
                val textMeasurer = rememberTextMeasurer()

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(72.dp)
                ) {
                    Canvas(modifier = Modifier.fillMaxSize()) {
                        val n = hours.size
                        val gap = 3.dp.toPx()
                        val segW = size.width / n
                        val trackTop = 12.dp.toPx()
                        val trackBottom = size.height - 16.dp.toPx()
                        val trackH = trackBottom - trackTop
                        val radius = 4.dp.toPx()

                        hours.forEachIndexed { i, h ->
                            val isSel = i == selectedIndex
                            val color = ratingColor(h.ratingLabel)
                            val left = i * segW + gap / 2f
                            val top = if (isSel) trackTop - 4.dp.toPx() else trackTop
                            val bottom = if (isSel) trackBottom + 4.dp.toPx() else trackBottom
                            drawRoundRect(
                                color = if (h.slot == null) color else color.copy(alpha = if (isSel) 0.95f else 0.5f),
                                topLeft = Offset(left, top),
                                size = Size(segW - gap, bottom - top),
                                cornerRadius = androidx.compose.ui.geometry.CornerRadius(radius, radius)
                            )
                        }

                        // Handle: bright Material You dot centered over the selected band, with a
                        // surface-colored halo behind it so the dot contrasts against any band color.
                        val cx = selectedIndex * segW + segW / 2f
                        drawCircle(
                            color = handleRingColor,
                            radius = 6.5.dp.toPx(),
                            center = Offset(cx, trackTop - 8.dp.toPx())
                        )
                        drawCircle(
                            color = optimalColor,
                            radius = 5.dp.toPx(),
                            center = Offset(cx, trackTop - 8.dp.toPx())
                        )

                        // Sparse hour labels under the track.
                        tickLabels.forEachIndexed { i, label ->
                            if (label != null) {
                                val layout = textMeasurer.measure(label, style = labelStyle)
                                drawText(
                                    textLayoutResult = layout,
                                    topLeft = Offset(
                                        x = (i * segW + segW / 2f - layout.size.width / 2f)
                                            .coerceIn(0f, size.width - layout.size.width),
                                        y = trackBottom + 4.dp.toPx()
                                    )
                                )
                            }
                        }
                    }
                }

                Spacer(Modifier.height(8.dp))
                Text(
                    text = "Hold & drag across the day — green is optimal, amber is fair, red is hard.",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = optimalColor
                )
            }
        }
    }
    }
}
