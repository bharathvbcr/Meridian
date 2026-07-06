package com.example.core.designsystem

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.RestartAlt
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import kotlin.math.abs
import kotlin.math.roundToInt
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.input.pointer.util.VelocityTracker
import kotlinx.coroutines.flow.drop

// Live grid: the finest the dial reports while dragging — slow, careful drags can land here.
private const val STEP_MIN = 5
private const val MINUTES_PER_TICK = 15f // one 16.dp tick column == 15 minutes at 1x speed
private const val MIN_OFFSET_MIN = -720f // −12h
private const val MAX_OFFSET_MIN = 720f  // +12h
// Detents fire at most this often, so a fast spin whirrs rather than machine-guns.
private const val DETENT_MIN_GAP_NANOS = 30_000_000L // 30ms
// Idle time before the expanded dial snaps back to the pill — keep under 500ms for a quick tuck-away.
private const val DIAL_COLLAPSE_DELAY_MS = 400L

// Acceleration curve for dragging: slow drags stay ~1:1 (granular), fast drags multiply the
// distance so a quick swipe covers far more time. `speedPxPerMs` is the finger's instant speed.
private fun dragGain(speedPxPerMs: Float): Float =
    (1f + speedPxPerMs * 1.1f).coerceIn(1f, 4f)

// On release, the fling speed (px/sec) picks how coarsely the dial settles: a hard flick rounds
// to the hour and covers lots of ground, a gentle release stays on the fine 5-minute grid.
private fun snapUnitForVelocity(absVelocityPxPerSec: Float): Int = when {
    absVelocityPxPerSec > 2500f -> 60
    absVelocityPxPerSec > 1000f -> 30
    absVelocityPxPerSec > 300f  -> 15
    else                        -> STEP_MIN
}

// Compact offset label, e.g. "Live", "+3h 15m", "-2h".
private fun offsetLabel(totalMinutes: Int): String {
    if (totalMinutes == 0) return "Live"
    val sign = if (totalMinutes > 0) "+" else "-"
    val abs = kotlin.math.abs(totalMinutes)
    val hours = abs / 60
    val minutes = abs % 60
    return buildString {
        append(sign)
        if (hours > 0) append("${hours}h")
        if (minutes > 0) {
            if (hours > 0) append(" ")
            append("${minutes}m")
        }
    }
}

// Spoken accessibility phrasing for the dial's current offset, e.g. "Live time",
// "3 hours 15 minutes later", "2 hours earlier" — TalkBack reads this instead of the
// terse "+3h 15m" pill glyph so the direction and units are unambiguous.
private fun offsetSpokenLabel(totalMinutes: Int): String {
    if (totalMinutes == 0) return "Live time"
    val abs = kotlin.math.abs(totalMinutes)
    val hours = abs / 60
    val minutes = abs % 60
    val parts = buildList {
        if (hours > 0) add(if (hours == 1) "1 hour" else "$hours hours")
        if (minutes > 0) add(if (minutes == 1) "1 minute" else "$minutes minutes")
    }
    val direction = if (totalMinutes > 0) "later" else "earlier"
    return "${parts.joinToString(" ")} $direction"
}

// Direction-aware crossfade for the readouts: the new value slides in from below when scrubbing
// later, from above when scrubbing earlier, so the motion mirrors the dial's direction. Under
// reduce-motion it collapses to a plain fade so nothing slides (north-star: respect Reduce Motion).
private fun directionalSlide(target: Int, initial: Int, reduceMotion: Boolean): ContentTransform {
    if (reduceMotion) {
        return ContentTransform(
            targetContentEnter = fadeIn(tween(120)),
            initialContentExit = fadeOut(tween(90)),
        )
    }
    val dir = if (target > initial) 1 else -1
    return ContentTransform(
        targetContentEnter = slideInVertically(tween(220)) { h -> dir * h } + fadeIn(tween(180)),
        initialContentExit = slideOutVertically(tween(220)) { h -> -dir * h } + fadeOut(tween(150)),
    )
}

@Composable
fun TimelineScrubber(
    scrubInstant: Instant?,
    hazeState: HazeState,
    onScrubTimeChanged: (Instant?) -> Unit,
    modifier: Modifier = Modifier,
    is24Hour: Boolean = false,
) {
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    // Honor the OS "remove animations" preference: decorative slides/scales collapse to instant,
    // while the essential drag-release snap physics stay (they are feedback, not decoration).
    val reduceMotion = LocalReduceMotion.current

    // Dial offset in *minutes* (−720..720) held in an Animatable so resets, tap-to-jump, and
    // drag-release all *glide* to their target instead of snapping. Bounds let a fast drag pin
    // cleanly at ±12h instead of overshooting.
    val slider = remember { Animatable(0f).apply { updateBounds(MIN_OFFSET_MIN, MAX_OFFSET_MIN) } }
    val sliderValue = slider.value
    // True while a programmatic glide is running, so the live watcher below doesn't
    // machine-gun haptics/callbacks through the in-between steps.
    var programmatic by remember { mutableStateOf(false) }
    var dialPressed by remember { mutableStateOf(false) } // true while a finger is held on the dial
    // Finger velocity at release decides how coarsely the dial settles (see snapUnitForVelocity).
    val velocityTracker = remember { VelocityTracker() }

    val density = LocalDensity.current
    val tickSpacingPx = remember { with(density) { 16.dp.toPx() } }
    val textMeasurer = rememberTextMeasurer()

    val primaryColor = MaterialTheme.colorScheme.primary
    val onSurfaceColor = MaterialTheme.colorScheme.onSurface
    // Muted caption tint for the eyebrow title + drag hint, so the live readout stays the focus.
    val onSurfaceVariantColor = MaterialTheme.colorScheme.onSurfaceVariant
    // Material You elevated-card tone backing the blur — lifted lighter than the page so the
    // card and its text never wash out into the dark background (see GlassDefaults.scrubberCardTone).
    val cardSurfaceColor = GlassDefaults.scrubberCardTone
    val glassOpacity = LocalGlassOpacity.current
    val scrubberGlass = remember(glassOpacity) { ScrubberGlass.alphas(glassOpacity) }
    // Tick captions follow the documented type scale (labelSmall) so they honor Dynamic Type
    // instead of a hand-set sp literal; only the tint + centering are overridden for the Canvas.
    val labelBaseStyle = MaterialTheme.typography.labelSmall
    val labelStyle = remember(onSurfaceColor, labelBaseStyle) {
        labelBaseStyle.copy(
            color = onSurfaceColor.copy(alpha = 0.85f),
            textAlign = TextAlign.Center
        )
    }
    val readoutFormatter = remember(is24Hour) {
        val timePat = if (is24Hour) "HH:mm" else "hh:mm a"
        DateTimeFormatter.ofPattern("$timePat · EEE, MMM d")
    }

    // Pre-measure all 25 possible hour-offset labels so the Canvas draw lambda
    // never allocates a TextLayoutResult at 60-120 fps during drag.
    val tickTextLayouts = remember(textMeasurer, labelStyle) {
        (-12..12).associate { h ->
            val text = when {
                h > 0 -> "+${h}h"
                h < 0 -> "${h}h"
                else -> "Live"
            }
            h to textMeasurer.measure(text, style = labelStyle)
        }
    }
    // Hoist fixed px conversions out of the Canvas draw lambda (they never change between frames).
    val hourTickLenPx = remember(density) { with(density) { 24.dp.toPx() } }
    val halfTickLenPx = remember(density) { with(density) { 16.dp.toPx() } }
    val qtrTickLenPx  = remember(density) { with(density) { 8.dp.toPx()  } }
    val hourStrokePx  = remember(density) { with(density) { 2.5.dp.toPx() } }
    val thinStrokePx  = remember(density) { with(density) { 1.5.dp.toPx() } }
    val glowWidthPx   = remember(density) { with(density) { 7.dp.toPx()  } }
    val centerWidthPx = remember(density) { with(density) { 3.dp.toPx()  } }
    val caretSizePx   = remember(density) { with(density) { 6.dp.toPx()  } }
    // Reuse a single Path instance; reset and repopulate each frame instead of allocating.
    val caretPath     = remember { androidx.compose.ui.graphics.Path() }
    // Fixed-alpha tints hoisted out of the dial draw loop — Color.copy in the per-tick loop
    // would otherwise allocate for every tick on every frame of a 60-120 fps drag.
    val bandTint          = remember(primaryColor)   { primaryColor.copy(alpha = 0.18f) }
    val centerGlowTint    = remember(primaryColor)   { primaryColor.copy(alpha = 0.35f) }
    val hourTickColor     = remember(onSurfaceColor) { onSurfaceColor.copy(alpha = 0.95f) }
    val halfHourTickColor = remember(onSurfaceColor) { onSurfaceColor.copy(alpha = 0.65f) }
    val quarterTickColor  = remember(onSurfaceColor) { onSurfaceColor.copy(alpha = 0.4f) }

    val totalSteps = 48 // −48..+48 quarter-hour steps span the ±12h range

    // The live offset, snapped to a fine 5-minute grid — the single source of truth for the
    // readout, the pill, and the callback. Slow drags can land on any 5-min mark (granular);
    // fast flicks settle on coarser marks (see onDragEnd).
    val liveOffsetMin by remember {
        derivedStateOf { (slider.value / STEP_MIN).roundToInt() * STEP_MIN }
    }
    val scrubbed = liveOffsetMin != 0

    // Whenever the live offset changes for a *user-driven* reason, tell the parent and tick a
    // detent. Programmatic glides (reset / tap-to-jump) stay silent here and fire their own
    // single update on arrival. snapshotFlow conflates per frame, so a fast spin won't flood.
    LaunchedEffect(Unit) {
        var lastHapticNanos = 0L
        snapshotFlow { liveOffsetMin }
            .drop(1) // skip the initial 0 so opening the screen is silent
            .collect { offset ->
                if (!programmatic) {
                    onScrubTimeChanged(if (offset == 0) null else Instant.now().plusSeconds(offset * 60L))
                    val now = System.nanoTime()
                    if (now - lastHapticNanos > DETENT_MIN_GAP_NANOS) {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        lastHapticNanos = now
                    }
                }
            }
    }

    // External reset (parent clears the scrub) — glide home, unless a finger or another
    // animation is already driving the dial. Marked programmatic so the watcher stays quiet.
    LaunchedEffect(scrubInstant) {
        if (scrubInstant == null && slider.value != 0f && !slider.isRunning && !dialPressed) {
            programmatic = true
            try {
                slider.animateTo(0f, tween(360, easing = FastOutSlowInEasing))
            } finally {
                programmatic = false
            }
        }
    }

    // Glide the dial to a target quarter-hour step, then fire one haptic + time update on arrival.
    // The try/finally clears `programmatic` even if a new gesture cancels the glide; the trailing
    // update is reached only on a clean arrival (a cancelling gesture drives its own update).
    fun goToStep(step: Int, animate: Boolean = true) {
        val clamped = step.coerceIn(-totalSteps, totalSteps)
        scope.launch {
            programmatic = true
            try {
                val target = (clamped * 15).toFloat()
                if (animate) slider.animateTo(target, tween(380, easing = FastOutSlowInEasing))
                else slider.snapTo(target)
            } finally {
                programmatic = false
            }
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            onScrubTimeChanged(if (clamped == 0) null else Instant.now().plusSeconds(clamped * 15L * 60L))
        }
    }

    // Collapsed-by-default UX: show a compact, solid pill. Tap to expand into the full
    // dial; after a brief idle the dial auto-collapses back to the pill.
    var expanded by remember { mutableStateOf(false) }
    var interactionTick by remember { mutableStateOf(0) } // bump on any interaction to reset the timer

    // Auto-collapse after a short idle, but never while a finger is still down
    // (so a press-and-hold or a pause mid-slide keeps the dial open).
    LaunchedEffect(expanded, interactionTick, dialPressed) {
        if (expanded && !dialPressed) {
            delay(DIAL_COLLAPSE_DELAY_MS)
            expanded = false
        }
    }

    // Press-scale for the collapsed pill so it feels physical when held. Purely decorative, so
    // reduce-motion pins it to 1f (no scale) rather than animating.
    val pillScale by animateFloatAsState(
        targetValue = if (dialPressed && !reduceMotion) 0.94f else 1f,
        animationSpec = if (reduceMotion) Motion.quick() else Motion.bouncy(),
        label = "pillScale"
    )

    val gestureContext = remember { object { var wasExpandedAtStart = false } }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .pointerInput(tickSpacingPx) {
                detectScrubberPressDrag(
                    onPressStart = {
                        gestureContext.wasExpandedAtStart = expanded
                        if (!expanded) {
                            expanded = true
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        }
                        dialPressed = true
                        programmatic = false
                        interactionTick++
                        velocityTracker.resetTracking()
                        scope.launch { slider.stop() }
                    },
                    onDrag = { delta, change ->
                        velocityTracker.addPosition(change.uptimeMillis, change.position)
                        val dtMs = (change.uptimeMillis - change.previousUptimeMillis)
                            .coerceAtLeast(1L).toFloat()
                        val gain = dragGain(abs(delta.x) / dtMs)
                        val minutesChange = -(delta.x / tickSpacingPx) * MINUTES_PER_TICK * gain
                        val target = (slider.value + minutesChange).coerceIn(MIN_OFFSET_MIN, MAX_OFFSET_MIN)
                        scope.launch { slider.snapTo(target) }
                        interactionTick++
                    },
                    onPressEnd = { dragged, releasePosition ->
                        dialPressed = false
                        interactionTick++
                        if (dragged) {
                            val velocityX = velocityTracker.calculateVelocity().x
                            val unit = snapUnitForVelocity(abs(velocityX))
                            scope.launch {
                                val snapped = ((slider.value / unit).roundToInt() * unit).toFloat()
                                slider.animateTo(snapped, animationSpec = Motion.snappy())
                            }
                        } else if (gestureContext.wasExpandedAtStart) {
                            interactionTick++
                            val tappedStep = (slider.value / 15f +
                                (releasePosition.x - size.width / 2f) / tickSpacingPx).roundToInt()
                            goToStep(tappedStep)
                        }
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
                (fadeIn(tween(90)) togetherWith fadeOut(tween(90)))
            } else {
                Motion.scrubberExpandCollapseTransform(targetState)
            }
        },
        contentAlignment = Alignment.BottomCenter,
        label = "scrubber_expand"
    ) { isExpanded ->
        if (!isExpanded) {
            // ---- Collapsed pill ----
            LiquidGlassSurface(
                hazeState = hazeState,
                modifier = Modifier
                    .wrapContentWidth(Alignment.CenterHorizontally)
                    .scale(pillScale)
                    .testTag("timeline_scrubber_pill"),
                shape = GlassDefaults.cardShape,
                tintColor = Color.Transparent,
                borderWidth = 1.dp,
                borderColor = primaryColor.copy(alpha = 0.4f),
                frosted = scrubberGlass.frosted,
            ) {
                Box(
                    modifier = Modifier
                        .defaultMinSize(
                            minWidth = ScrubberPillDefaults.minWidth,
                            minHeight = ScrubberPillDefaults.minHeight,
                        )
                        // Solid scrim over the glass so the pill stays legible (kept on the content
                        // layer so it sits above the backdrop refraction and under the content).
                        .background(
                            color = cardSurfaceColor.copy(alpha = scrubberGlass.pillTint),
                            shape = GlassDefaults.cardShape,
                        )
                        .padding(
                            horizontal = ScrubberPillDefaults.horizontalPadding,
                            vertical = ScrubberPillDefaults.verticalPadding,
                        )
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                    // Icon sits in a primary-tinted chip so the control reads as tappable chrome
                    // regardless of how transparent the glass behind it is.
                    Box(
                        modifier = Modifier
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(primaryColor.copy(alpha = 0.16f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = Icons.Default.Tune,
                            // Announce the current offset alongside the affordance so a TalkBack user
                            // hears where the scrub sits before opening the dial.
                            contentDescription = "Open time dial, currently ${offsetSpokenLabel(liveOffsetMin)}",
                            tint = primaryColor,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                    Spacer(modifier = Modifier.width(10.dp))
                    AnimatedContent(
                        targetState = liveOffsetMin,
                        transitionSpec = { directionalSlide(targetState, initialState, reduceMotion) },
                        contentAlignment = Alignment.CenterStart,
                        label = "pill_label"
                    ) { off ->
                        Text(
                            text = offsetLabel(off),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.ExtraBold,
                            color = if (off == 0) onSurfaceColor else primaryColor
                        )
                    }
                    // Up-chevron hints the pill expands into the full dial on press.
                    if (!scrubbed) {
                        Spacer(modifier = Modifier.width(6.dp))
                        Icon(
                            imageVector = Icons.Default.KeyboardArrowUp,
                            contentDescription = null,
                            tint = onSurfaceColor.copy(alpha = 0.5f),
                            modifier = Modifier.size(18.dp)
                        )
                    }
                    // When scrubbed, offer a one-tap reset right on the pill — no need to expand.
                    if (scrubbed) {
                        Spacer(modifier = Modifier.width(8.dp))
                        Box(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(primaryColor.copy(alpha = 0.15f))
                                .clickable {
                                    interactionTick++
                                    goToStep(0)
                                }
                                .padding(4.dp)
                                .testTag("pill_reset_to_live")
                        ) {
                            Icon(
                                imageVector = Icons.Default.RestartAlt,
                                contentDescription = "Reset to live",
                                tint = primaryColor,
                                modifier = Modifier.size(16.dp)
                            )
                        }
                    }
                }
                }
            }
            return@AnimatedContent
        }

    LiquidGlassSurface(
        hazeState = hazeState,
        modifier = Modifier
            .fillMaxWidth()
            .testTag("timeline_scrubber_card"),
        shape = GlassDefaults.cardShape,
        tintColor = Color.Transparent,
        borderWidth = 1.5.dp,
        borderColor = primaryColor.copy(alpha = 0.5f),
        frosted = scrubberGlass.frosted,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                // Solid Material You scrim laid *over* the backdrop glass (which otherwise washes
                // the tint toward the dark surface) and *under* the content, so the dial's text and
                // ticks always sit on a legible, clearly-raised card.
                .background(
                    color = cardSurfaceColor.copy(alpha = scrubberGlass.cardTint),
                    shape = GlassDefaults.cardShape,
                )
                .padding(20.dp)
        ) {
            Column {
                // Header of Scrubber
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Eyebrow title over the live readout. The readout is the loudest element in the
                    // group (titleMedium) so the scrubbed date/time reads first; the title is demoted
                    // to a muted labelMedium caption. Merged so TalkBack speaks it as one summary.
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .semantics(mergeDescendants = true) {}
                    ) {
                        Text(
                            text = "Time Dial",
                            style = MaterialTheme.typography.labelMedium,
                            color = onSurfaceVariantColor
                        )
                        Spacer(modifier = Modifier.height(2.dp))
                        AnimatedContent(
                            targetState = liveOffsetMin,
                            transitionSpec = { directionalSlide(targetState, initialState, reduceMotion) },
                            contentAlignment = Alignment.CenterStart,
                            label = "scrub_readout"
                        ) { off ->
                            val text = if (off == 0) {
                                "Synced with Live Ticker"
                            } else {
                                ZonedDateTime
                                    .ofInstant(Instant.now().plusSeconds(off * 60L), ZoneId.systemDefault())
                                    .format(readoutFormatter)
                            }
                            Text(
                                text = text,
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.ExtraBold,
                                color = onSurfaceColor,
                                maxLines = 1
                            )
                        }
                    }

                    if (scrubbed) {
                        IconButton(
                            onClick = {
                                interactionTick++
                                goToStep(0)
                            },
                            colors = IconButtonDefaults.iconButtonColors(
                                containerColor = primaryColor.copy(alpha = 0.1f),
                                contentColor = primaryColor
                            ),
                            modifier = Modifier
                                .size(36.dp)
                                .testTag("reset_timeline_scrub")
                        ) {
                            Icon(
                                imageVector = Icons.Default.RestartAlt,
                                contentDescription = "Reset time scrubber to live",
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(20.dp))

                // The Draggable Physical Dial Canvas
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(80.dp)
                        .background(
                            color = onSurfaceColor.copy(alpha = scrubberGlass.trackBackground),
                            shape = RoundedCornerShape(12.dp)
                        )
                        // The dial is a drag-only control; expose it to TalkBack as an adjustable
                        // seekbar so a screen-reader user can read the current offset and nudge it
                        // via swipe-up/down (setProgress) or the explicit earlier/later/reset actions
                        // — none of which are possible with the raw pointer gesture alone.
                        .semantics {
                            // No explicit Role: the progressBarRangeInfo + setProgress below make
                            // TalkBack treat this as an adjustable seek control (swipe up/down),
                            // which a misleading Role (there is no Slider role) would override.
                            contentDescription = "Time dial"
                            stateDescription = offsetSpokenLabel(liveOffsetMin)
                            progressBarRangeInfo = ProgressBarRangeInfo(
                                current = liveOffsetMin.toFloat(),
                                range = MIN_OFFSET_MIN..MAX_OFFSET_MIN,
                                // Quarter-hour detents across the ±12h span (‑48..+48 = 96 gaps).
                                steps = totalSteps * 2 - 1,
                            )
                            setProgress { targetMinutes ->
                                val clamped = targetMinutes.coerceIn(MIN_OFFSET_MIN, MAX_OFFSET_MIN)
                                interactionTick++
                                goToStep((clamped / 15f).roundToInt())
                                true
                            }
                            customActions = listOf(
                                CustomAccessibilityAction(label = "Later by 15 minutes") {
                                    interactionTick++
                                    goToStep((liveOffsetMin / 15f).roundToInt() + 1)
                                    true
                                },
                                CustomAccessibilityAction(label = "Earlier by 15 minutes") {
                                    interactionTick++
                                    goToStep((liveOffsetMin / 15f).roundToInt() - 1)
                                    true
                                },
                                CustomAccessibilityAction(label = "Reset to live") {
                                    interactionTick++
                                    goToStep(0)
                                    true
                                },
                            )
                        }
                ) {
                    Canvas(modifier = Modifier.fillMaxSize()) {
                        val widthValue = size.width
                        val heightValue = size.height
                        val centerX = widthValue / 2f

                        // High-contrast center highlight: a soft primary-tinted band marks the
                        // "now" column so the selected time reads clearly against the ticks.
                        val bandHalf = tickSpacingPx * 0.9f
                        drawRect(
                            color = bandTint,
                            topLeft = Offset(centerX - bandHalf, 0f),
                            size = androidx.compose.ui.geometry.Size(bandHalf * 2f, heightValue),
                        )

                        // Draw ticks
                        // Total ticks: we cover from -48 steps to +48 steps
                        val centerStep = (sliderValue / 15f)
                        val startTick = (centerStep - 20).roundToInt().coerceAtLeast(-48)
                        val endTick = (centerStep + 20).roundToInt().coerceAtLeast(startTick).coerceAtMost(48)

                        for (tick in startTick..endTick) {
                            // Calculate position based on the scrolling center offsets
                            val itemX = centerX + (tick - centerStep) * tickSpacingPx

                            val isHourTick = tick % 4 == 0
                            val isHalfHourTick = tick % 2 == 0

                            val tickLen = when {
                                isHourTick -> hourTickLenPx
                                isHalfHourTick -> halfTickLenPx
                                else -> qtrTickLenPx
                            }

                            // Brightened so even the minor 15-min ticks stay visible over glass.
                            val color = when {
                                isHourTick -> hourTickColor
                                isHalfHourTick -> halfHourTickColor
                                else -> quarterTickColor
                            }

                            val strokeWidth = when {
                                isHourTick -> hourStrokePx
                                else -> thinStrokePx
                            }

                            // Draw tick lines hanging downwards from top or upwards from bottom
                            drawLine(
                                color = color,
                                start = Offset(itemX, heightValue - tickLen),
                                end = Offset(itemX, heightValue),
                                strokeWidth = strokeWidth,
                                cap = StrokeCap.Round
                            )

                            // Label the major Hour tick marks with offsets or localized equivalents
                            if (isHourTick) {
                                val offsetHours = (tick * 15 / 60)
                                tickTextLayouts[offsetHours]?.let { textLayout ->
                                    drawText(
                                        textLayoutResult = textLayout,
                                        topLeft = Offset(
                                            x = itemX - (textLayout.size.width / 2f),
                                            y = heightValue - tickLen - textLayout.size.height - 4
                                        )
                                    )
                                }
                            }
                        }

                        // Center indicator: a soft glow underlay + a crisp primary line so the
                        // present-moment marker pops at any glass opacity.
                        drawLine(
                            color = centerGlowTint,
                            start = Offset(centerX, 0f),
                            end = Offset(centerX, heightValue),
                            strokeWidth = glowWidthPx,
                            cap = StrokeCap.Round
                        )
                        drawLine(
                            color = primaryColor,
                            start = Offset(centerX, 0f),
                            end = Offset(centerX, heightValue),
                            strokeWidth = centerWidthPx,
                            cap = StrokeCap.Square
                        )
                        // Caret at the top of the center line — reuse the hoisted Path instance.
                        caretPath.reset()
                        caretPath.moveTo(centerX - caretSizePx, 0f)
                        caretPath.lineTo(centerX + caretSizePx, 0f)
                        caretPath.lineTo(centerX, caretSizePx * 1.4f)
                        caretPath.close()
                        drawPath(path = caretPath, color = primaryColor)
                    }
                }
                
                Spacer(modifier = Modifier.height(12.dp))

                // Range endpoints + drag hint. Purely visual scaffolding for the dial, so it is
                // cleared from TalkBack (the dial node above already announces its range and state).
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clearAndSetSemantics { }
                ) {
                    Text(
                        "-12 hrs",
                        style = MaterialTheme.typography.labelMedium,
                        color = onSurfaceVariantColor
                    )
                    Spacer(modifier = Modifier.weight(1f))
                    // Demoted from primary+Bold to a muted caption so it supports — not competes with —
                    // the live readout above.
                    Text(
                        "Hold & drag to scrub · flick to jump",
                        style = MaterialTheme.typography.labelSmall,
                        color = onSurfaceVariantColor,
                        textAlign = TextAlign.Center
                    )
                    Spacer(modifier = Modifier.weight(1f))
                    Text(
                        "+12 hrs",
                        style = MaterialTheme.typography.labelMedium,
                        color = onSurfaceVariantColor
                    )
                }
            }
        }
    }
    }
    }
}
