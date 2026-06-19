package com.example.core.designsystem

import androidx.compose.runtime.Immutable
import com.example.core.data.DEFAULT_GLASS_OPACITY_PERCENT
import com.example.core.data.MAX_GLASS_OPACITY
import com.example.core.data.MIN_GLASS_OPACITY

/** Resolved glass style for agenda pills and scrubber [liquidGlass] surfaces. */
@Immutable
data class ScrubberGlassAlphas(
    /** Compact pill + agenda accessory surface scrim (10–100% slider). */
    val pillTint: Float,
    /** Expanded scrubber card surface scrim — slightly stronger than [pillTint] at every step. */
    val cardTint: Float,
    val trackBackground: Float,
    /** When true, use the milkier Haze regular material instead of ultra-thin. */
    val frosted: Boolean,
)

/** Maps the unified glass-opacity slider (10–100%) to tint strengths. */
object ScrubberGlass {
    // Floors are deliberately high: even at the "transparent" end the pill/dial must read as a
    // solid Material You card whose text and ticks stay legible over a busy refracted backdrop.
    // The slider scales contrast up from there toward a fully opaque surface at "opaque".
    // The expanded dial carries the most text, so its floor is the highest.
    private const val PILL_TINT_MIN = 0.66f
    private const val PILL_TINT_MAX = 1.0f
    private const val CARD_TINT_MIN = 0.86f
    private const val CARD_TINT_MAX = 1.0f
    private const val TRACK_BG_MIN = 0.22f
    private const val TRACK_BG_MAX = 0.46f
  /** Frosted blur is on for all but the very lowest slider step, so content keeps a milky backing. */
    private const val FROSTED_THRESHOLD = 0.03f

    fun alphas(percent: Int): ScrubberGlassAlphas {
        val t = fraction(percent)
        return ScrubberGlassAlphas(
            pillTint = lerp(PILL_TINT_MIN, PILL_TINT_MAX, t),
            cardTint = lerp(CARD_TINT_MIN, CARD_TINT_MAX, t),
            trackBackground = lerp(TRACK_BG_MIN, TRACK_BG_MAX, t),
            frosted = t >= FROSTED_THRESHOLD,
        )
    }

    fun fraction(percent: Int): Float =
        ((percent - MIN_GLASS_OPACITY).toFloat() / (MAX_GLASS_OPACITY - MIN_GLASS_OPACITY))
            .coerceIn(0f, 1f)

    private fun lerp(start: Float, end: Float, fraction: Float): Float =
        start + (end - start) * fraction
}

/** Persisted glass opacity (10–100%) for agenda pills and scrubbers, provided near the app root. */
val LocalGlassOpacity = androidx.compose.runtime.compositionLocalOf { DEFAULT_GLASS_OPACITY_PERCENT }
