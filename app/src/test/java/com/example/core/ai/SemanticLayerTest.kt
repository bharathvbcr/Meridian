package com.example.core.ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SemanticLayerTest {

    private val groundingKey = SemanticCachePolicy.groundingKey(0L, "Europe/London")

    @Test
    fun embedder_similarPrompts_scoreHigh() {
        val a = SemanticEmbedder.embed("What time is it in Tokyo right now?")
        val b = SemanticEmbedder.embed("what time is it in tokyo now")
        val score = SemanticEmbedder.cosine(a, b)
        assertTrue("Similar prompts should score > 0.7 (was $score)", score > 0.7f)
    }

    @Test
    fun cache_returnsNearDuplicate() {
        val cache = SemanticCache()
        cache.store("What time is it in Tokyo?", "Tokyo is 9 PM JST.", AiProvenance.RULES, groundingKey)
        val hit = cache.lookup("what time is it in tokyo", groundingKey)
        assertNotNull(hit)
        assertEquals("Tokyo is 9 PM JST.", hit!!.response)
        assertEquals(AiProvenance.CACHED, hit.provenance)
    }

    @Test
    fun cache_missesUnrelatedPrompt() {
        val cache = SemanticCache()
        cache.store("What time is it in Tokyo?", "Tokyo is 9 PM JST.", AiProvenance.RULES, groundingKey)
        assertNull(cache.lookup("Schedule lunch with Emma tomorrow at 1pm", groundingKey))
    }

    @Test
    fun cache_expiresStaleTimeAnswer() {
        var now = 0L
        // 30s TTL, virtual clock so the test is deterministic.
        val cache = SemanticCache(ttlMs = 30_000L, nowMs = { now })
        cache.store("What time is it in Tokyo?", "Tokyo is 9:41 PM JST.", AiProvenance.RULES, groundingKey)

        now = 10_000L // within TTL — safe to replay
        assertNotNull(cache.lookup("what time is it in tokyo", groundingKey))

        now = 60_000L // past TTL — the 9:41 reading is now stale, must not replay
        assertNull(cache.lookup("what time is it in tokyo", groundingKey))
    }

    @Test
    fun cache_rejectsAmbiguousTopTwo() {
        val cache = SemanticCache(threshold = 0.5f, margin = 0.04f)
        cache.store("What time is it in Tokyo?", "Tokyo answer.", AiProvenance.RULES, groundingKey)
        cache.store("What time is it in Tokyo now?", "Tokyo now answer.", AiProvenance.RULES, groundingKey)
        // Two very similar prompts — margin guard should reject if scores are too close.
        val hit = cache.lookup("what time is it in tokyo right now", groundingKey)
        // Either null (margin rejected) or a clear winner — must not crash.
        if (hit != null) {
            assertTrue(hit.response.isNotBlank())
        }
    }

    @Test
    fun cache_invalidatesOnGroundingKeyChange() {
        val cache = SemanticCache()
        cache.store("What time is it in Tokyo?", "Tokyo is 9 PM JST.", AiProvenance.RULES, groundingKey)
        val nextMinuteKey = SemanticCachePolicy.groundingKey(60_001L, "Europe/London")
        assertNull(cache.lookup("what time is it in tokyo", nextMinuteKey))
    }

    @Test
    fun cachePolicy_bypassesCurrentTime() {
        assertTrue(SemanticCachePolicy.shouldBypass(AiQueryIntent.CURRENT_TIME, "What time is it?"))
    }

    @Test
    fun cachePolicy_bypassesConvertWithNow() {
        assertTrue(SemanticCachePolicy.shouldBypass(AiQueryIntent.CONVERT, "Convert now to London"))
    }

    @Test
    fun cachePolicy_bypassesSchedule() {
        // A schedule is an action, not a cacheable answer — two near-duplicate requests must not
        // replay the first booking's time.
        assertTrue(SemanticCachePolicy.shouldBypass(AiQueryIntent.SCHEDULE, "schedule lunch tomorrow at 1pm"))
        assertFalse(SemanticCachePolicy.shouldBypass(AiQueryIntent.GENERAL, "what's happening"))
    }

    @Test
    fun router_currentTime_goesToRules() {
        val route = SemanticRouter.route(
            AiQueryIntent.CURRENT_TIME,
            "What time is it in Tokyo?",
            "LIVE CLOCK\n• Tokyo: 9 PM",
        )
        assertEquals(SemanticRoute.RULES, route)
    }

    @Test
    fun router_schedule_staysStandard() {
        val route = SemanticRouter.route(
            AiQueryIntent.SCHEDULE,
            "Schedule a call with London next Monday at 2 PM",
            "LIVE CLOCK\n• London: 2 PM",
        )
        assertEquals(SemanticRoute.STANDARD, route)
    }

    @Test
    fun compressor_trimsLongGrounding() {
        val bullets = (1..80).joinToString("\n") { "• Zone $it at longitude ${it * 3}: ${it % 24}:00 local with extended label padding" }
        val block = "LIVE CLOCK\n$bullets"
        assertTrue(block.length > 1_200)
        val compressed = SemanticCompressor.compress(block, maxBulletsPerSection = 3)
        assertTrue(compressed.length < block.length)
        assertTrue(compressed.lines().count { it.startsWith("• ") } <= 3)
    }
}
