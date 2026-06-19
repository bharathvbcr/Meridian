package com.example

import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import com.example.core.data.SavedZone
import com.example.core.designsystem.MeridianExpressiveTheme
import com.example.ui.components.TimeBoardItem
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Screenshot test for a key design-system component (§12.9), to catch visual regressions.
 * Run `./gradlew :app:recordRoborazziDebug` to refresh the baseline.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36])
class TimeBoardScreenshotTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun timeBoardItem_rendersZoneAndTime() {
        composeRule.setContent {
            MeridianExpressiveTheme(dynamicColor = false) {
                TimeBoardItem(
                    zone = SavedZone("Asia/Tokyo", "Tokyo"),
                    currentTime = ZonedDateTime.of(2026, 6, 16, 15, 0, 0, 0, ZoneId.of("UTC")),
                    is24Hour = true,
                    modifier = Modifier.padding(16.dp),
                )
            }
        }
        composeRule.onRoot().captureRoboImage("src/test/screenshots/time_board_item.png")
    }
}
