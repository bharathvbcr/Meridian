package com.example

import com.example.feature.ai.looksLikeMarkdown
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatMarkdownTest {

    @Test
    fun looksLikeMarkdown_detectsBold() {
        assertTrue(looksLikeMarkdown("Use **bold** for emphasis"))
    }

    @Test
    fun looksLikeMarkdown_detectsBulletList() {
        assertTrue(looksLikeMarkdown("Tips:\n- Tokyo is ahead\n- London is behind"))
    }

    @Test
    fun looksLikeMarkdown_detectsInlineCode() {
        assertTrue(looksLikeMarkdown("Run `adb devices` to check"))
    }

    @Test
    fun looksLikeMarkdown_detectsLinks() {
        assertTrue(looksLikeMarkdown("See [IANA zones](https://www.iana.org/time-zones)"))
    }

    @Test
    fun looksLikeMarkdown_plainSentenceIsFalse() {
        assertFalse(looksLikeMarkdown("What time is it in Tokyo right now?"))
    }
}
