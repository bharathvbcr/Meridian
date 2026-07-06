package com.example.core.designsystem

import android.provider.Settings
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntSize

/**
 * User-facing motion animations honor this flag. Provided once near the root (alongside
 * [LocalGlassEnabled] / [LocalReduceTransparencyOverride] in GlassPreferences) so every consumer —
 * nav bar scale/color, [TimelineScrubber] pill scale + expand transform, BottomAccessory slide,
 * ScrollableChipRow auto-scroll — can collapse to an instant `snapTo` when reduce-motion is on.
 *
 * Defaults to the system signal via [rememberReduceMotion]; a `false` default keeps motion on when
 * no provider is present, mirroring how transparency defaults to "enabled".
 */
val LocalReduceMotion = compositionLocalOf { false }

/**
 * Reactively tracks whether the OS "remove animations" preference is on, read from
 * [Settings.Global.ANIMATOR_DURATION_SCALE] (`0f` means the platform disables animator-driven
 * animation). Mirrors the shape of [rememberReduceTransparency]: it registers a live
 * [android.database.ContentObserver] so the result updates while the app is in the foreground.
 *
 * The north-star mandates that motion "Always respect Reduce Motion / animator scale"; feed this
 * into [LocalReduceMotion] near the root so springs across the app fall back to instant transitions.
 */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    var reduceMotion by remember(context) {
        mutableStateOf(context.readAnimatorScale() == 0f)
    }

    DisposableEffect(context) {
        val resolver = context.contentResolver
        val observer = object : android.database.ContentObserver(null) {
            override fun onChange(selfChange: Boolean) {
                reduceMotion = context.readAnimatorScale() == 0f
            }
        }
        val uri = Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE)
        resolver.registerContentObserver(uri, false, observer)
        onDispose { resolver.unregisterContentObserver(observer) }
    }

    return reduceMotion
}

/** Reads the global animator duration scale, defaulting to `1f` (animations on) on any failure. */
private fun android.content.Context.readAnimatorScale(): Float =
    try {
        Settings.Global.getFloat(contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
    } catch (_: Exception) {
        1f
    }

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

    fun <T> quick() = spring<T>(
        dampingRatio = 1.0f, // No overshoot
        stiffness = 500f
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
                // Fade/scale exit routes through a fast no-overshoot spring for parity with the rest
                // of the system (north-star: "No linear tweens for user-facing transitions").
                initialContentExit = fadeOut(snappy()) +
                    scaleOut(targetScale = 0.94f, animationSpec = snappy()),
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
