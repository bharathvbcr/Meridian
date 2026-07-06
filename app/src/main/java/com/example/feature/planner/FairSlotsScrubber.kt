package com.example.feature.planner

import androidx.compose.runtime.Immutable
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.togetherWith
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
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.example.core.designsystem.GlassDefaults
import com.example.core.designsystem.LocalReduceMotion
import com.example.core.designsystem.Motion
import com.example.core.designsystem.LocalGlassOpacity
import com.example.core.designsystem.ScrubberGlass
import com.example.core.designsystem.ScrubberPillDefaults
import com.example.core.designsystem.detectScrubberPressDrag
import com.example.core.designsystem.LiquidGlassSurface
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
@Immutable
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
    // Honor the OS "remove animations" preference: the pill press-scale and expand/collapse morph
    // collapse to instant, while the essential haptics + selection stay (north-star: respect
    // Reduce Motion / animator scale). Mirrors the World-page TimelineScrubber.
    val reduceMotion = LocalReduceMotion.current

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

    // Press-scale for the collapsed pill so it feels physical when held. Purely decorative, so
    // reduce-motion pins it to 1f (no scale) and routes through a no-overshoot spring.
    val pillScale by animateFloatAsState(
        targetValue = if (dialPressed && !reduceMotion) 0.94f else 1f,
        animationSpec = if (reduceMotion) Motion.quick() else Motion.bouncy(),
        label = "fairPillScale"
    )

    val gestureContext = remember { object { var wasExpandedAtStart = false } }

    // Hoist textMeasurer, labelStyle, and pre-measured tick layouts to composable scope so the
    // Canvas draw lambda never calls TextMeasurer.measure() at 60-120 fps during drag.
    val textMeasurer = rememberTextMeasurer()
    // Tick captions follow the documented type scale (labelSmall) so they honor Dynamic Type
    // instead of a hand-set sp literal; only the tint, weight, and centering are overridden for
    // the Canvas. Mirrors the World-page TimelineScrubber tick style.
    val labelBaseStyle = MaterialTheme.typography.labelSmall
    val labelStyle: TextStyle = remember(onSurfaceColor, labelBaseStyle) {
        labelBaseStyle.copy(
            color = onSurfaceColor.copy(alpha = 0.85f),
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center
        )
    }
    val tickLayouts = remember(tickLabels, labelStyle) {
        tickLabels.map { label ->
            label?.let { textMeasurer.measure(it, style = labelStyle) }
        }
    }

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

    // TalkBack navigation: step to the next / previous *selectable* hour (skipping filtered-out
    // bands), so the seekbar's swipe-up / swipe-down and the explicit actions land only on hours
    // a user can actually pick — matching the drag gesture's snap-to-selectable behavior.
    fun step(direction: Int) {
        var i = selectedIndex + direction
        while (i in hours.indices) {
            if (hours[i].slot != null) {
                selectAt(i)
                return
            }
            i += direction
        }
    }

    // Count of pickable hours + the selected hour's ordinal among them, so the spoken position
    // ("3 of 9 workable hours") is meaningful even when weekends/filters mute part of the day.
    val selectableCount = remember(hours) { hours.count { it.slot != null } }
    val selectableOrdinal = remember(hours, selectedIndex) {
        hours.take(selectedIndex + 1).count { it.slot != null }
    }
    // Spoken state, e.g. "9:00 to 9:45, Fair, 3 of 9 workable hours" — unambiguous where the
    // terse pill glyph is not (mirrors the World-page dial's offsetSpokenLabel).
    val selectedSpokenLabel = buildString {
        append(pillTime.replace("–", "to").replace("-", "to"))
        selected.ratingLabel?.let { append(", $it") }
        if (selectableCount > 0 && selected.slot != null) {
            append(", $selectableOrdinal of $selectableCount workable hours")
        } else if (selected.slot == null) {
            append(", no overlap this hour")
        }
    }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .pointerInput(hours) {
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
                            val idx = (releasePosition.x / size.width * hours.size).toInt()
                            selectAt(idx)
                        }
                    },
                )
            }
            // The dial is a drag-only control, invisible to TalkBack on its own. Expose it as an
            // adjustable seekbar so a screen-reader user can read the selected hour + rating and
            // nudge the handle via swipe-up/down (setProgress) or the explicit next/previous
            // actions — none possible with the raw pointer gesture. Mirrors the World-page dial.
            // clearAndSetSemantics collapses the pill/dial's decorative text (icon label, badge,
            // Canvas ticks) into this single curated node so TalkBack speaks one coherent control.
            .clearAndSetSemantics {
                // No explicit Role: progressBarRangeInfo + setProgress make TalkBack treat this as
                // an adjustable seek control (swipe up/down); a misleading Role would override that.
                contentDescription = "Fair-time dial"
                stateDescription = selectedSpokenLabel
                progressBarRangeInfo = ProgressBarRangeInfo(
                    current = selectedIndex.toFloat(),
                    range = 0f..hours.lastIndex.toFloat().coerceAtLeast(0f),
                    steps = (hours.size - 2).coerceAtLeast(0),
                )
                setProgress { targetIndex ->
                    if (!expanded) expanded = true
                    interactionTick++
                    selectAt(targetIndex.toInt().coerceIn(0, hours.lastIndex))
                    true
                }
                customActions = listOf(
                    CustomAccessibilityAction(label = "Next hour") {
                        if (!expanded) expanded = true
                        interactionTick++
                        step(1)
                        true
                    },
                    CustomAccessibilityAction(label = "Previous hour") {
                        if (!expanded) expanded = true
                        interactionTick++
                        step(-1)
                        true
                    },
                )
            },
        contentAlignment = Alignment.BottomCenter,
    ) {
    AnimatedContent(
        targetState = expanded,
        modifier = Modifier.fillMaxWidth(),
        transitionSpec = {
            // Reduce-motion: swap the springy expand/collapse morph for an instant crossfade so the
            // dial appears/tucks without sliding or scaling (north-star: respect Reduce Motion).
            if (reduceMotion) {
                androidx.compose.animation.fadeIn(Motion.quick()) togetherWith
                    androidx.compose.animation.fadeOut(Motion.quick())
            } else {
                Motion.scrubberExpandCollapseTransform(targetState)
            }
        },
        contentAlignment = Alignment.BottomCenter,
        label = "fair_scrubber_expand"
    ) { isExpanded ->
        if (!isExpanded) {
            // ---- Collapsed pill ----
            LiquidGlassSurface(
                hazeState = hazeState,
                modifier = Modifier
                    .wrapContentWidth(Alignment.CenterHorizontally)
                    .scale(pillScale),
                shape = GlassDefaults.cardShape,
                tintColor = Color.Transparent,
                borderWidth = 1.dp,
                borderColor = optimalColor.copy(alpha = 0.4f),
                frosted = scrubberGlass.frosted,
            ) {
                Row(
                    modifier = Modifier
                        .defaultMinSize(
                            minWidth = ScrubberPillDefaults.minWidth,
                            minHeight = ScrubberPillDefaults.minHeight,
                        )
                        // Legibility scrim on the content layer, above the backdrop refraction.
                        .background(
                            color = cardSurfaceColor.copy(alpha = scrubberGlass.pillTint),
                            shape = GlassDefaults.cardShape,
                        )
                        .padding(
                            horizontal = ScrubberPillDefaults.horizontalPadding,
                            vertical = ScrubberPillDefaults.verticalPadding,
                        ),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
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
                        val badgeColor = ratingColor(label)
                        Spacer(Modifier.width(10.dp))
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(50))
                                .background(badgeColor.copy(alpha = 0.18f))
                                .padding(horizontal = 8.dp, vertical = 4.dp)
                        ) {
                            Text(
                                text = label,
                                style = MaterialTheme.typography.labelMedium,
                                color = badgeColor,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }
            }
            return@AnimatedContent
        }

        // ---- Expanded dial ----
        LiquidGlassSurface(
            hazeState = hazeState,
            modifier = Modifier.fillMaxWidth(),
            shape = GlassDefaults.cardShape,
            tintColor = Color.Transparent,
            borderWidth = 1.5.dp,
            borderColor = optimalColor.copy(alpha = 0.5f),
            frosted = scrubberGlass.frosted,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    // Legibility scrim on the content layer, above the backdrop refraction.
                    .background(
                        color = cardSurfaceColor.copy(alpha = scrubberGlass.cardTint),
                        shape = GlassDefaults.cardShape,
                    )
                    .padding(20.dp)
            ) {
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
                        tickLayouts.forEachIndexed { i, layout ->
                            if (layout != null) {
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
                // The sentence is instructions, not a status, so it reads in the muted onSurface
                // caption tint; only the band words carry their band color (primary / tertiary /
                // error) so color maps to meaning rather than implying one band is "the" state.
                val legendCaption = buildAnnotatedString {
                    append("Hold & drag across the day — ")
                    withStyle(SpanStyle(color = optimalColor, fontWeight = FontWeight.Bold)) {
                        append("optimal")
                    }
                    append(", ")
                    withStyle(SpanStyle(color = fairColor, fontWeight = FontWeight.Bold)) {
                        append("fair")
                    }
                    append(", ")
                    withStyle(SpanStyle(color = difficultColor, fontWeight = FontWeight.Bold)) {
                        append("difficult")
                    }
                    append(".")
                }
                Text(
                    text = legendCaption,
                    style = MaterialTheme.typography.labelSmall,
                    color = onSurfaceColor.copy(alpha = 0.7f)
                )
            }
        }
    }
    }
}
