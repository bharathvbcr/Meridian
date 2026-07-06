package com.example.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.core.data.SavedZone
import com.example.core.designsystem.GlassCard
import com.example.core.designsystem.GlassDefaults
import com.example.core.time.TimeFormats
import dev.chrisbanes.haze.HazeState
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Local mirror of Meridian's documented 4/8/12/16/20/24 spacing scale, kept private to this
 * file so it stays conceptually in parity with the shared design system without leaking new
 * public surface. Prefer these over ad-hoc dp literals.
 */
private object TimeBoardSpacing {
    val xs: Dp = 4.dp
    val lg: Dp = 16.dp
}

@Composable
fun TimeBoardItem(
    zone: SavedZone,
    currentTime: ZonedDateTime,
    is24Hour: Boolean,
    modifier: Modifier = Modifier,
    // A glass surface needs a HazeState to blur its backdrop against. Callers that live inside a
    // hazeSource-registered scaffold can pass theirs so this card frosts the real backdrop; the
    // default keeps the item self-contained (matching SettingsCard / NowScreen conventions) and
    // preserves the existing 4-arg call sites, which never passed one.
    hazeState: HazeState = remember { HazeState() },
) {
    val formatter = remember(is24Hour) { TimeFormats.hourMinute(is24Hour) }
    val zoneTime = currentTime.withZoneSameInstant(ZoneId.of(zone.id))
    val formattedTime = zoneTime.format(formatter)

    // One spoken label so TalkBack announces the row as a single unit ("Tokyo, 3:00 PM")
    // instead of forcing two swipes across a name and a time it can't relate.
    val spokenLabel = "${zone.displayName}, $formattedTime"

    // On the celestial backdrop this now reads as a first-class frosted glass card (28dp,
    // GlassDefaults.cardShape) rather than a foreign flat surfaceVariant tile. Item-to-item
    // spacing is intentionally left to the parent list's Arrangement.spacedBy, so the card's
    // own padding stays a clean 16dp all around — matching GlassCard usage elsewhere.
    GlassCard(
        hazeState = hazeState,
        // Explicit for intent: the unified 28dp glass radius, replacing the old foreign 16dp tile.
        shape = GlassDefaults.cardShape,
        modifier = modifier
            .fillMaxWidth()
            .clearAndSetSemantics { contentDescription = spokenLabel },
    ) {
        Column(
            modifier = Modifier.padding(TimeBoardSpacing.lg),
            verticalArrangement = Arrangement.spacedBy(TimeBoardSpacing.xs),
        ) {
            Text(
                text = zone.displayName,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Medium,
                // Secondary to the hero time, but kept clearly legible (WCAG-AA) so the label
                // is never lost under the much larger display figure below it.
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
            )
            Text(
                text = formattedTime,
                style = MaterialTheme.typography.displayMedium,
                // The hero figure reads as primary content on the glass, on-tone with the
                // rest of the celestial surface rather than a saturated accent block.
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}
