package com.example

import com.example.core.ai.ScheduleParser
import com.example.core.data.PlannedTask
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Brutal coverage of the chatbot's scheduling decision logic — extracting a schedule action from a
 * messy model reply and resolving it to an exact, zone-correct [PlannedTask] (§12.7: the app does the
 * time math). Clock pinned to 2026-06-17T12:00Z (a Wednesday).
 */
class ScheduleParserTest {

    private val now = Instant.parse("2026-06-17T12:00:00Z")
    private val home = "America/Chicago"

    // A stand-in for the app's zone search: only these place names resolve.
    private val resolve: suspend (String) -> String? = { q ->
        when (q.trim().lowercase()) {
            "tokyo" -> "Asia/Tokyo"
            "london" -> "Europe/London"
            else -> null
        }
    }

    private fun build(jsonStr: String, prompt: String = "") =
        runBlocking { ScheduleParser.buildScheduledTask(jsonStr, prompt, now, home, resolve) }

    private fun assertAt(task: PlannedTask?, zoneId: String, y: Int, mo: Int, d: Int, h: Int, mi: Int) {
        requireNotNull(task) { "expected a task" }
        assertEquals(zoneId, task.zoneId)
        val zdt = ZonedDateTime.ofInstant(Instant.ofEpochMilli(task.timestamp), ZoneId.of(zoneId))
        assertEquals(LocalDateTime.of(y, mo, d, h, mi), zdt.toLocalDateTime())
    }

    // ---- extractScheduleJson --------------------------------------------------------------------

    @Test fun `extracts a clean schedule object`() {
        val s = """{"action":"schedule","title":"Sync","when":"tomorrow 9am","zoneId":"Europe/London"}"""
        assertEquals(s, ScheduleParser.extractScheduleJson(s))
    }

    @Test fun `extracts from inside a code fence`() {
        val fenced = "```json\n{\"action\":\"schedule\",\"title\":\"X\",\"when\":\"tomorrow\"}\n```"
        val json = ScheduleParser.extractScheduleJson(fenced)
        assertTrue(json != null && json.contains("\"action\""))
    }

    @Test fun `extracts when wrapped in prose`() {
        val text = "Sure, I'll set that up. {\"action\":\"schedule\",\"title\":\"Call\",\"when\":\"5pm\"} Done!"
        assertTrue(ScheduleParser.extractScheduleJson(text)?.startsWith("{") == true)
    }

    @Test fun `picks the schedule object among several`() {
        val text = "{\"foo\":1} then {\"action\":\"schedule\",\"title\":\"Z\",\"when\":\"noon\"}"
        assertEquals(
            "{\"action\":\"schedule\",\"title\":\"Z\",\"when\":\"noon\"}",
            ScheduleParser.extractScheduleJson(text),
        )
    }

    @Test fun `tolerates whitespace in the action field`() {
        val s = """{ "action" : "schedule" , "title":"Y","when":"tomorrow" }"""
        assertEquals(s, ScheduleParser.extractScheduleJson(s))
    }

    @Test fun `a title containing the word schedule is not a false positive`() {
        val s = """{"action":"answer","title":"schedule review notes"}"""
        assertNull(ScheduleParser.extractScheduleJson(s))
    }

    @Test fun `non-schedule actions and plain prose return null`() {
        assertNull(ScheduleParser.extractScheduleJson("""{"action":"answer","text":"It is 3pm."}"""))
        assertNull(ScheduleParser.extractScheduleJson("Let me schedule that for you tomorrow."))
        assertNull(ScheduleParser.extractScheduleJson(""))
    }

    // ---- buildScheduledTask ---------------------------------------------------------------------

    @Test fun `when phrase with an IANA zone`() {
        val s = """{"action":"schedule","title":"Sync","when":"next monday 2pm","zoneId":"Europe/London"}"""
        assertAt(build(s), "Europe/London", 2026, 6, 22, 14, 0)
    }

    @Test fun `zone given as a place name is resolved`() {
        val s = """{"action":"schedule","title":"Sync","when":"tomorrow 9am","zoneId":"Tokyo"}"""
        assertAt(build(s), "Asia/Tokyo", 2026, 6, 18, 9, 0)
    }

    @Test fun `unknown or blank zone falls back to the home zone`() {
        val unknown = """{"action":"schedule","title":"S","when":"tomorrow 9am","zoneId":"Atlantis"}"""
        assertAt(build(unknown), home, 2026, 6, 18, 9, 0)
        val blank = """{"action":"schedule","title":"S","when":"tomorrow 9am","zoneId":""}"""
        assertAt(build(blank), home, 2026, 6, 18, 9, 0)
    }

    @Test fun `missing title defaults to New event`() {
        val s = """{"action":"schedule","when":"tomorrow 10am","zoneId":"Europe/London"}"""
        assertEquals("New event", build(s)?.title)
    }

    @Test fun `falls back to parsing the original prompt when the model omits when`() {
        val s = """{"action":"schedule","title":"Standup","zoneId":"Europe/London"}"""
        assertAt(build(s, prompt = "schedule standup tomorrow at 9am please"), "Europe/London", 2026, 6, 18, 9, 0)
    }

    @Test fun `a good when wins over a bogus legacy timestamp`() {
        val s = """{"action":"schedule","title":"S","when":"next monday 2pm","zoneId":"Europe/London","timestamp":1}"""
        assertAt(build(s), "Europe/London", 2026, 6, 22, 14, 0)
    }

    @Test fun `legacy numeric timestamp is honored when no phrase resolves`() {
        val epoch = 1_750_000_000_000L
        val s = """{"action":"schedule","title":"Legacy","timestamp":$epoch,"zoneId":"Europe/London"}"""
        assertEquals(epoch, build(s, prompt = "schedule it")?.timestamp)
    }

    @Test fun `timestamp sent as a string still parses`() {
        val epoch = 1_750_000_000_000L
        val s = """{"action":"schedule","title":"Legacy","timestamp":"$epoch","zoneId":"Europe/London"}"""
        assertEquals(epoch, build(s, prompt = "schedule it")?.timestamp)
    }

    @Test fun `no resolvable time anywhere yields null`() {
        val s = """{"action":"schedule","title":"S","when":"whenever","zoneId":"Europe/London"}"""
        assertNull(build(s, prompt = "just schedule something"))
    }

    @Test fun `non-schedule action yields null`() {
        assertNull(build("""{"action":"answer","title":"X","when":"tomorrow"}"""))
    }

    @Test fun `malformed json yields null instead of throwing`() {
        assertNull(build("""{"action":"schedule", "title": }"""))
        assertNull(build("not json at all"))
    }

    @Test fun `titleOf reads the title or null`() {
        assertEquals("Lunch", ScheduleParser.titleOf("""{"action":"schedule","title":"Lunch"}"""))
        assertNull(ScheduleParser.titleOf("""{"action":"schedule","title":""}"""))
        assertNull(ScheduleParser.titleOf("garbage"))
    }

    // ---- regression guards for review findings --------------------------------------------------

    @Test fun `a structured (non-primitive) field is treated as absent, never throws`() {
        // Title is an object, zoneId is an array — both degrade gracefully instead of crashing.
        val s = """{"action":"schedule","title":{"x":1},"when":"tomorrow 9am","zoneId":["Europe/London"]}"""
        val task = build(s)
        assertEquals("New event", task?.title)   // non-primitive title → default
        assertAt(task, home, 2026, 6, 18, 9, 0)  // non-primitive zone → home
    }

    @Test fun `a structured when falls back to the original prompt instead of throwing`() {
        val s = """{"action":"schedule","title":"S","when":{"date":"tomorrow"},"zoneId":"Europe/London"}"""
        assertAt(build(s, prompt = "schedule it tomorrow 9am"), "Europe/London", 2026, 6, 18, 9, 0)
    }

    @Test fun `titleOf does not throw on a non-primitive title`() {
        assertNull(ScheduleParser.titleOf("""{"action":"schedule","title":{"x":1}}"""))
    }

    @Test fun `extracts a schedule object that contains a nested object`() {
        val s = """{"action":"schedule","title":"X","when":"tomorrow 9am","meta":{"k":1},"zoneId":"Europe/London"}"""
        // Brace-balanced extraction returns the whole object, and the extra key is ignored.
        assertEquals(s, ScheduleParser.extractScheduleJson(s))
        assertAt(build(s), "Europe/London", 2026, 6, 18, 9, 0)
    }

    @Test fun `a closing brace inside a string value does not truncate extraction`() {
        val s = """{"action":"schedule","title":"Sprint }","when":"tomorrow 9am","zoneId":"Europe/London"}"""
        assertEquals(s, ScheduleParser.extractScheduleJson(s))
        assertEquals("Sprint }", build(s)?.title)
    }

    // ---- worst-case / adversarial ---------------------------------------------------------------

    @Test fun `empty and actionless objects are not schedules`() {
        assertNull(ScheduleParser.extractScheduleJson("{}"))
        assertNull(build("{}"))
        assertNull(build("""{"title":"X","when":"tomorrow 9am"}"""))
    }

    @Test fun `a non-string action is rejected`() {
        assertNull(ScheduleParser.extractScheduleJson("""{"action":5,"title":"X","when":"tomorrow"}"""))
        assertNull(build("""{"action":5,"title":"X","when":"tomorrow"}"""))
        assertNull(build("""{"action":true,"when":"tomorrow"}"""))
    }

    @Test fun `unicode and emoji in the title survive intact`() {
        val s = """{"action":"schedule","title":"Café ☕ サミット","when":"tomorrow 9am","zoneId":"Europe/London"}"""
        assertEquals("Café ☕ サミット", build(s)?.title)
    }

    @Test fun `an absurd when duration yields null without throwing`() {
        val s = """{"action":"schedule","title":"X","when":"in 9999999999 weeks","zoneId":"Europe/London"}"""
        assertNull(build(s, prompt = "just schedule it"))
    }

    @Test fun `escaped quotes and braces inside string values are handled`() {
        val s = """{"action":"schedule","title":"Say \"hi {there}\"","when":"tomorrow 9am","zoneId":"Europe/London"}"""
        assertEquals(s, ScheduleParser.extractScheduleJson(s))
        assertEquals("""Say "hi {there}"""", build(s)?.title)
    }

    @Test fun `deeply nested junk around the schedule object is tolerated`() {
        val s = """noise {"a":{"b":{"c":1}}} {"action":"schedule","title":"Deep","when":"tomorrow 9am","zoneId":"Europe/London"} trailing"""
        assertAt(build(ScheduleParser.extractScheduleJson(s)!!), "Europe/London", 2026, 6, 18, 9, 0)
    }
}
