package com.example.feature.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.core.designsystem.GlassCard
import dev.chrisbanes.haze.HazeState

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

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.55f))
            .systemBarsPadding(),
        contentAlignment = Alignment.Center,
    ) {
        GlassCard(
            hazeState = hazeState,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 28.dp),
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 28.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                AnimatedContent(
                    targetState = step,
                    transitionSpec = {
                        fadeIn() togetherWith fadeOut()
                    },
                    label = "onboarding-step",
                ) { targetStep ->
                    val current = STEPS[targetStep]
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            imageVector = current.icon,
                            contentDescription = null,
                            modifier = Modifier.size(52.dp),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                        Spacer(Modifier.height(16.dp))
                        Text(
                            text = current.title,
                            style = MaterialTheme.typography.headlineSmall,
                            color = MaterialTheme.colorScheme.onSurface,
                            textAlign = TextAlign.Center,
                        )
                        Spacer(Modifier.height(10.dp))
                        Text(
                            text = current.body,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                }

                Spacer(Modifier.height(24.dp))

                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    STEPS.indices.forEach { i ->
                        Box(
                            modifier = Modifier
                                .size(if (i == step) 8.dp else 5.dp)
                                .background(
                                    color = if (i == step) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.25f),
                                    shape = CircleShape,
                                ),
                        )
                    }
                }

                Spacer(Modifier.height(24.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TextButton(onClick = onFinish) {
                        Text("Skip")
                    }
                    Button(
                        onClick = { if (isLast) onFinish() else step++ },
                    ) {
                        Text(if (isLast) "Done" else "Next")
                    }
                }
            }
        }
    }
}
