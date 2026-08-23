package com.example

import com.example.core.ai.AiProvenance
import com.example.core.ai.SemanticCache
import com.example.core.time.IcsGenerator
import com.example.core.time.ScheduleTimeParser
import com.example.core.time.WorkHourWindows
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.random.Random

/**
 * Adversarial stress tests for the hardened engines: folding must be lossless under any
 * input, window merges must never claim coverage that does not exist, the schedule parser
 * must fail closed on impossible explicit times, and the semantic cache must survive a
 * concurrent trim race. All randomness is seeded so failures reproduce exactly.
 */
class HardeningFuzzTest {

    // --- IcsGenerator: octet folding -----------------------------------------------------

    /** Unfolds physical lines per RFC 5545 §3.1 (strip CRLF + leading space). */
    private fun unfold(lines: List<String>): String =
        lines.mapIndexed { i, line -> if (i == 0) line else line.drop(1) }.joinToString("")

    @Test
    fun foldIsLosslessAndBoundedForArbitraryText() {
        val rnd = Random(0xC0FFEE)
        val alphabet = "aZ9 ;,\n\r\téü漢字🚀😀\u0301  ".toList()
        repeat(2_000) { iteration ->
            val len = rnd.nextInt(0, 400)
            val text = buildString { repeat(len) { append(alphabet[rnd.nextInt(alphabet.size)]) } }

            val folded = IcsGenerator.foldToOctets(text)

            assertTrue("empty input must stay empty", text.isNotEmpty() || folded.isEmpty())
            for ((idx, line) in folded.withIndex()) {
                val octets = line.toByteArray(Charsets.UTF_8)
                assertTrue(
                    "iteration $iteration: line $idx is ${octets.size} octets",
                    octets.size <= 75,
                )
                if (idx > 0) {
                    assertTrue("continuation lines start with one space", line.startsWith(" "))
                }
            }
            assertEquals(
                "iteration $iteration: folding must be lossless",
                text,
                unfold(folded),
            )
        }
    }

    @Test
    fun generatedIcsStaysCompliantUnderHostileTitles() {
        val rnd = Random(42)
        val nasty = listOf(
            "", " ", "\n", "\r\n", "a;b,c\\d", "🎉".repeat(60), "漢字".repeat(80), "x".repeat(500),
        ) + List(20) { i ->
            buildString { repeat(rnd.nextInt(0, 120)) { append("ab;\r\n,🎉"[rnd.nextInt(7)]) } }
        }
        for ((i, title) in nasty.withIndex()) {
            val ics = IcsGenerator.generateEventIcs(
                title = title,
                description = title + title,
                startInstant = Instant.parse("2026-06-20T07:30:00Z"),
                durationMinutes = 45,
                zoneId = if (i % 2 == 0) "+05:30" else "Asia/Kolkata",
            )
            assertEquals(0, Regex("(?<!\r)\n").findAll(ics).count())
            for (line in ics.split("\r\n")) {
                assertTrue(
                    "title #$i produced a ${line.toByteArray(Charsets.UTF_8).size}-octet line",
                    line.toByteArray(Charsets.UTF_8).size <= 75,
                )
            }
            assertNotEquals("", ics.trim())
        }
    }

    // --- WorkHourWindows: merge invariants -----------------------------------------------

    private fun hoursOf(window: Pair<Int, Int>) = WorkHourWindows.workWindowToHours(window.first, window.second)

    @Test
    fun randomWorkIntersectionsNeverOverCover() {
        val rnd = Random(7)
        repeat(5_000) { iteration ->
            val windows = List(rnd.nextInt(1, 4)) {
                var s = rnd.nextInt(0, 24); var e = rnd.nextInt(0, 24)
                if (s == e) e = (e + 1) % 24
                s to e
            }
            val merged = WorkHourWindows.intersectWorkWindows(windows)
            val truth = windows.map { hoursOf(it) }.reduce { acc, next -> acc intersect next }

            val claimed = hoursOf(merged)
            assertTrue(
                "iteration $iteration windows=$windows merged=$merged claimed=$claimed truth=$truth",
                claimed.all { it in truth },
            )
            if (truth.isEmpty()) {
                assertTrue("empty intersection must encode 'no window'", merged.first == merged.second)
            } else {
                assertTrue("non-empty intersection keeps its largest arc", claimed.isNotEmpty())
            }
            // Determinism: same input, same output.
            assertEquals(merged, WorkHourWindows.intersectWorkWindows(windows))
        }
    }

    @Test
    fun randomDndUnionsNeverOverBlock() {
        val rnd = Random(13)
        repeat(5_000) { iteration ->
            val windows = List(rnd.nextInt(1, 4)) {
                var s = rnd.nextInt(0, 24); var e = rnd.nextInt(0, 24)
                if (s == e) e = (e + 1) % 24
                s to e
            }
            val merged = WorkHourWindows.unionDndWindows(windows)
            if (merged.first in 0..23 || merged.second in 0..23) {
                val truth = windows.map { hoursOf(it) }.reduce { acc, next -> acc union next }
                val claimed = hoursOf(merged)
                assertTrue(
                    "iteration $iteration windows=$windows merged=$merged claimed=$claimed truth=$truth",
                    claimed.all { it in truth },
                )
            }
        }
    }

    // --- ScheduleTimeParser: fail-closed behaviour ----------------------------------------

    private val now = Instant.parse("2026-06-17T12:00:00Z")
    private val london = ZoneId.of("Europe/London")

    @Test
    fun impossibleExplicitTimesWithDatesAlwaysFailClosed() {
        val dates = listOf("tomorrow", "next monday", "2026-07-01", "july 4", "friday")
        val badTimes = listOf("24:00", "25:61", "99:99", "13pm", "0am", "12:60am", "-1:30")
        for (d in dates) for (t in badTimes) {
            assertNull("$d $t must be rejected", ScheduleTimeParser.parse("$d $t", london, now))
        }
    }

    @Test
    fun garbagePhrasesNeverThrowAndNeverInventInstants() {
        val rnd = Random(99)
        val junkBits = listOf("tomorrow", ":", "9999999999", "in", "days", "pm", "🎉", "-", "\n", "at", "week", "00")
        repeat(3_000) {
            val phrase = buildString {
                repeat(rnd.nextInt(1, 10)) { append(junkBits[rnd.nextInt(junkBits.size)]); append(' ') }
            }.trim()
            val result = try {
                ScheduleTimeParser.parse(phrase, london, now)
            } catch (e: Exception) {
                throw AssertionError("parser threw on \"$phrase\": $e", e)
            }
            if (result != null) {
                assertTrue("parsed instant must be finite", !result.isAfter(Instant.parse("2266-01-01T00:00:00Z")))
            }
        }
    }

    // --- SemanticCache: concurrent trim race ----------------------------------------------

    @Test
    fun concurrentStoresNeverTripTheTrimRace() {
        val cache = SemanticCache(maxEntries = 16)
        val threads = 8
        val perThread = 500
        val pool = Executors.newFixedThreadPool(threads)
        val ready = CountDownLatch(threads)
        val errors = mutableListOf<Throwable>()
        repeat(threads) { t ->
            pool.submit {
                ready.countDown()
                try {
                    repeat(perThread) { i ->
                        cache.store("prompt $t-$i", "answer $t-$i", AiProvenance.RULES, groundingKey = (i % 3).toLong())
                        cache.lookup("prompt $t-${i / 2}", groundingKey = (i % 3).toLong())
                    }
                } catch (e: Throwable) {
                    synchronized(errors) { errors.add(e) }
                }
            }
        }
        pool.shutdown()
        assertTrue(pool.awaitTermination(30, TimeUnit.SECONDS))
        assertTrue("concurrent store/lookup threw: ${errors.firstOrNull()}", errors.isEmpty())
    }

    // --- partialChunks: streaming bounds ---------------------------------------------------

    @Test
    fun partialChunksStayBoundedAndMonotoneForAnyShape() {
        fun check(text: String, maxChunks: Int): List<String> {
            val chunks = com.example.core.ai.partialChunks(text, maxChunks)
            assertTrue(chunks.isNotEmpty())
            assertTrue("chunks=${chunks.size} max=$maxChunks", chunks.size <= maxChunks)
            assertEquals(text, chunks.last())
            assertTrue(chunks.zipWithNext().all { (a, b) -> b.startsWith(a) && b.length > a.length })
            return chunks
        }
        val rnd = Random(1234)
        repeat(500) {
            val words = List(rnd.nextInt(1, 300)) { "w${it}" }
            val text = words.joinToString(" ")
            val maxChunks = rnd.nextInt(1, 64)
            val chunks = check(text, maxChunks)
            if (words.size <= maxChunks) {
                assertEquals("short texts stream word-by-word", words.size, chunks.size)
            }
        }
        check("single", 32)
        check("", 32) // blank input → single empty chunk, no crash
    }
}
