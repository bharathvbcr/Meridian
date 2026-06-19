package com.example.core.designsystem

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.unit.dp
import kotlin.math.hypot

/** Shared collapsed-pill sizing so both scrubbers stay easy to grab. */
object ScrubberPillDefaults {
    val horizontalPadding = 24.dp
    val verticalPadding = 14.dp
    val minHeight = 48.dp
    val minWidth = 132.dp
    val iconSize = 20.dp
}

/**
 * Press on the pill expands the dial; horizontal drag continues on the same finger without
 * lifting. [onPressEnd] receives whether the gesture moved past touch slop.
 */
internal suspend fun PointerInputScope.detectScrubberPressDrag(
    onPressStart: (position: Offset) -> Unit,
    onDrag: (delta: Offset, change: PointerInputChange) -> Unit,
    onPressEnd: (dragged: Boolean, releasePosition: Offset) -> Unit,
) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        onPressStart(down.position)
        val pointerId = down.id
        var dragged = false
        val touchSlop = viewConfiguration.touchSlop
        var accumulatedX = 0f
        var accumulatedY = 0f
        var lastPosition = down.position
        try {
            while (true) {
                val event = awaitPointerEvent()
                val change = event.changes.firstOrNull { it.id == pointerId } ?: break
                if (!change.pressed) break
                val delta = change.positionChange()
                if (delta != Offset.Zero) {
                    accumulatedX += delta.x
                    accumulatedY += delta.y
                    if (!dragged && hypot(accumulatedX.toDouble(), accumulatedY.toDouble()) > touchSlop) {
                        dragged = true
                    }
                    if (dragged) {
                        change.consume()
                        onDrag(delta, change)
                    }
                }
                lastPosition = change.position
            }
        } finally {
            onPressEnd(dragged, lastPosition)
        }
    }
}
