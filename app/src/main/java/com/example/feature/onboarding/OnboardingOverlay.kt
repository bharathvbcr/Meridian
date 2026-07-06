package com.example.feature.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.core.designsystem.GlassCard
import com.example.core.designsystem.LocalReduceMotion
import com.example.core.designsystem.Motion
import dev.chrisbanes.haze.HazeState

/**
 * Local mirror of Meridian's documented 4/8/12/16/20/24 spacing and 12/20/28 radius scales, kept
 * private to this overlay so the two platforms stay conceptually in parity without leaking new
 * public surface. Prefer these over ad-hoc dp literals inside this file.
 */
private object OnboardingTokens {
    val spaceSm = 8.dp
    val spaceMd = 12.dp
    val spaceLg = 16.dp
    val spaceXl = 24.dp
    val cardInset = 28.dp
    val radiusMedium = 20.dp
    val iconSize = 52.dp
    val minTouchTarget = 48.dp
    /** Inactive page-dot circle. */
    val dotInactive = 6.dp
    /** Active page-dot pill dimensions — widened so progress reads at a glance, not by size delta alone. */
    val activePillWidth = 18.dp
    val activePillHeight = 6.dp
    /** Raised from the near-invisible 0.25 so inactive dots clear low-vision legibility. */
    const val inactiveDotAlpha = 0.4f
}

private data class OnboardingStep(
    val icon: ImageVector,
    val title: String,
    val body: String,
)

private val STEPS = listOf(
    OnboardingStep(
        Icons.Filled.Explore,
        "Welcome to Meridian",
        "A time-zone companion built for people who live and work across the world.",
    ),
    OnboardingStep(
        Icons.Filled.Schedule,
        "Now",
        "Your local time at a glance — sunrise, sunset, working hours, and favourite world clocks all in one card.",
    ),
    OnboardingStep(
        Icons.Filled.Public,
        "World Clock",
        "A live globe shows you what every time zone looks like right now. Scrub through time to plan ahead.",
    ),
    OnboardingStep(
        Icons.Filled.DateRange,
        "Planner",
        "Find fair meeting windows for distributed teams. Meridian ranks overlap times so no one always loses sleep.",
    ),
    OnboardingStep(
        Icons.Filled.AutoAwesome,
        "AI Assistant",
        "Ask natural-language questions about times and meetings. Answers run on-device when your phone supports it.",
    ),
)

@Composable
fun OnboardingOverlay(
    hazeState: HazeState,
    onFinish: () -> Unit,
) {
    var step by remember { mutableIntStateOf(0) }
    val isLast = step == STEPS.lastIndex
    val reduceMotion = LocalReduceMotion.current
    val haptics = LocalHapticFeedback.current

    Box(
        modifier = Modifier
            .fillMaxSize()
            // Tint the dim toward the celestial deep-space canvas (#020617) instead of a flat black
            // wash so the scrim harmonizes with the palette rather than reading as a generic overlay.
            .background(MaterialTheme.colorScheme.background.copy(alpha = 0.72f))
            .systemBarsPadding(),
        contentAlignment = Alignment.Center,
    ) {
        GlassCard(
            hazeState = hazeState,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = OnboardingTokens.cardInset),
        ) {
            Column(
                modifier = Modifier.padding(
                    horizontal = OnboardingTokens.spaceXl,
                    vertical = OnboardingTokens.cardInset,
                ),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                AnimatedContent(
                    targetState = step,
                    transitionSpec = {
                        if (reduceMotion) {
                            // Reduce-motion: cross-dissolve with no directional travel.
                            fadeIn(Motion.smooth()) togetherWith fadeOut(Motion.smooth())
                        } else {
                            // Directional spring slide so stepping forward/back feels physical and
                            // matches the app-wide spring language (north-star: no linear tweens).
                            val forward = targetState >= initialState
                            val direction = if (forward) 1 else -1
                            (slideInHorizontally(Motion.smooth()) { width -> direction * width / 4 } +
                                fadeIn(Motion.smooth())) togetherWith
                                (slideOutHorizontally(Motion.smooth()) { width -> -direction * width / 4 } +
                                    fadeOut(Motion.smooth()))
                        }
                    },
                    label = "onboarding-step",
                ) { targetStep ->
                    val current = STEPS[targetStep]
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            imageVector = current.icon,
                            // Voice the illustration with the step title so the icon isn't silent.
                            contentDescription = current.title,
                            modifier = Modifier.size(OnboardingTokens.iconSize),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                        Spacer(Modifier.height(OnboardingTokens.spaceLg))
                        Text(
                            text = current.title,
                            style = MaterialTheme.typography.headlineSmall,
                            color = MaterialTheme.colorScheme.onSurface,
                            textAlign = TextAlign.Center,
                            // Expose the title as a heading so TalkBack users can jump to it.
                            modifier = Modifier.semantics { heading() },
                        )
                        Spacer(Modifier.height(OnboardingTokens.spaceMd))
                        Text(
                            text = current.body,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                }

                Spacer(Modifier.height(OnboardingTokens.spaceXl))

                Row(
                    horizontalArrangement = Arrangement.spacedBy(OnboardingTokens.spaceSm),
                    verticalAlignment = Alignment.CenterVertically,
                    // Announce progress as one live-updating unit; the individual dots are decorative
                    // once the Row carries the "Step N of M" label.
                    modifier = Modifier.semantics {
                        liveRegion = LiveRegionMode.Polite
                        contentDescription = "Step ${step + 1} of ${STEPS.size}"
                    },
                ) {
                    STEPS.indices.forEach { i ->
                        val active = i == step
                        Box(
                            modifier = Modifier
                                .clearAndSetSemantics {}
                                .then(
                                    if (active) {
                                        Modifier
                                            .width(OnboardingTokens.activePillWidth)
                                            .height(OnboardingTokens.activePillHeight)
                                    } else {
                                        Modifier.size(OnboardingTokens.dotInactive)
                                    }
                                )
                                .background(
                                    color = if (active) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.onSurface
                                        .copy(alpha = OnboardingTokens.inactiveDotAlpha),
                                    shape = if (active) {
                                        RoundedCornerShape(OnboardingTokens.radiusMedium)
                                    } else {
                                        CircleShape
                                    },
                                ),
                        )
                    }
                }

                Spacer(Modifier.height(OnboardingTokens.spaceXl))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    // On the terminal step there is a single clear action, so keep "Done" in its
                    // usual trailing slot; earlier steps balance Skip ↔ Next at opposite edges.
                    horizontalArrangement = if (isLast) Arrangement.End else Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // Hide the low-emphasis Skip on the last step: "Skip" next to "Done" is
                    // ambiguous (both dismiss), so the final step presents one unambiguous action.
                    if (!isLast) {
                        TextButton(
                            onClick = onFinish,
                            modifier = Modifier.heightIn(min = OnboardingTokens.minTouchTarget),
                        ) {
                            Text("Skip")
                        }
                    }
                    Button(
                        onClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            if (isLast) onFinish() else step++
                        },
                        modifier = Modifier.heightIn(min = OnboardingTokens.minTouchTarget),
                    ) {
                        Text(if (isLast) "Done" else "Next")
                    }
                }
            }
        }
    }
}
