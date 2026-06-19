package com.example

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import com.example.core.designsystem.MeridianExpressiveTheme
import com.example.feature.ai.ChatMarkdownText
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Regression test for the AI chat crash: an assistant reply containing Markdown took the
 * [ChatMarkdownText] -> `Markdown()` path, which on a Compose runtime older than 1.8 hit
 * `NoSuchMethodError: Composer.shouldExecute(ZI)Z` and crashed the app. Composing the Markdown
 * path here fails on the old runtime and passes once the Compose BOM supplies that method.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36])
class ChatMarkdownRenderTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun chatMarkdownText_rendersMarkdownContentWithoutCrashing() {
        composeRule.setContent {
            MeridianExpressiveTheme(dynamicColor = false) {
                ChatMarkdownText(
                    text = "Here are the **times**:\n" +
                        "- Tokyo is ahead\n" +
                        "- London is behind\n\n" +
                        "Run `adb devices` and see [zones](https://www.iana.org/time-zones).",
                    textColor = Color.Black,
                )
            }
        }
        composeRule.onRoot().assertExists()
    }
}
