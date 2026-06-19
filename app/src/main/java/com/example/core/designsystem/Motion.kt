package com.example.core.designsystem

import androidx.compose.animation.ContentTransform
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.ui.unit.IntSize

object Motion {
    fun <T> smooth() = spring<T>(
        dampingRatio = 1.0f, // No overshoot
        stiffness = 300f
    )

    fun <T> bouncy() = spring<T>(
        dampingRatio = 0.7f,
        stiffness = 300f
    )

    fun <T> snappy() = spring<T>(
        dampingRatio = 0.85f,
        stiffness = 400f
    )

    /** Bouncy expand / smooth tuck-away for scrubber pill ↔ dial transitions. */
    fun scrubberExpandCollapseTransform(expanding: Boolean): ContentTransform {
        // Size morph must never overshoot — bouncy springs can yield negative interim padding and crash.
        val sizeSpec = spring<IntSize>(
            dampingRatio = Spring.DampingRatioNoBouncy,
            stiffness = if (expanding) Spring.StiffnessMediumLow else Spring.StiffnessMedium,
        )
        return if (expanding) {
            ContentTransform(
                targetContentEnter = slideInVertically(bouncy()) { height -> height / 4 } +
                    fadeIn(smooth()) +
                    scaleIn(initialScale = 0.92f, animationSpec = bouncy()),
                initialContentExit = fadeOut(tween(160, easing = FastOutSlowInEasing)) +
                    scaleOut(targetScale = 0.94f, animationSpec = tween(160, easing = FastOutSlowInEasing)),
                sizeTransform = SizeTransform { _, _ -> sizeSpec },
            )
        } else {
            ContentTransform(
                targetContentEnter = fadeIn(smooth()) +
                    scaleIn(initialScale = 0.94f, animationSpec = bouncy()),
                initialContentExit = slideOutVertically(smooth()) { height -> height / 4 } +
                    fadeOut(smooth()) +
                    scaleOut(targetScale = 0.92f, animationSpec = smooth()),
                sizeTransform = SizeTransform { _, _ -> sizeSpec },
            )
        }
    }
}
