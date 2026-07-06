package com.example

import com.example.core.ai.MeridianAiTools
import com.example.core.data.Person
import com.example.core.data.SavedZone
import com.example.core.time.FindOverlapUseCase
import com.example.core.time.TimeEngine
import com.google.firebase.ai.type.FunctionCallPart
import kotlinx.coroutines.runBlocking
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.datetime.toKotlinInstant
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

/**
 * Unit coverage for the assistant's deterministic capability layer — the part that lets it answer
 * "what time is it in Tokyo?" with a real time instead of "I don't have real-time information".
 * The clock is pinned to 2026-06-17T12:00Z so every expected wall-clock value is exact.
 */
class MeridianAiToolsTest {

    private val fixedInstant = java.time.Instant.parse("2026-06-17T12:00:00Z")

    // A stand-in for the app's multi-layer zone search: case-insensitive exact lookup. Crucially,
    // "new york" resolves but "new" / "york" alone do not, so multi-word extraction is exercised.
    private val zones = mapOf(
        "tokyo" to SavedZone("Asia/Tokyo", "Tokyo"),
        "london" to SavedZone("Europe/London", "London"),
        "new york" to SavedZone("America/New_York", "New York"),
        "nyc" to SavedZone("America/New_York", "New York"),
        "chicago" to SavedZone("America/Chicago", "Chicago"),
        "berlin" to SavedZone("Europe/Berlin", "Berlin"),
        "singapore" to SavedZone("Asia/Singapore", "Singapore"),
        "paris" to SavedZone("Europe/Paris", "Paris"),
        "sydney" to SavedZone("Australia/Sydney", "Sydney"),
        "kathmandu" to SavedZone("Asia/Kathmandu", "Kathmandu"),
        "utc" to SavedZone("UTC", "UTC"),
    )

    private val tools: MeridianAiTools by lazy {
        val clock = object : Clock { override fun now(): Instant = fixedInstant.toKotlinInstant() }
        val timeEngine = TimeEngine(clock)
        MeridianAiTools(
            resolvePlace = { query -> zones[query.trim().lowercase()] },
            findOverlap = FindOverlapUseCase(timeEngine),
            now = { fixedInstant },
        )
    }

    private fun call(name: String, args: Map<String, JsonElement>) =
        runBlocking { tools.dispatch(FunctionCallPart(name, args)) }

    private fun JsonObject.str(key: String): String = getValue(key).jsonPrimitive.content

    @Test
    fun `get_current_time returns the real local time at a resolved place`() {
        val result = call("get_current_time", mapOf("location" to JsonPrimitive("Tokyo")))
        // 12:00 UTC is 21:00 in Tokyo (UTC+9), same calendar day.
        assertEquals("Asia/Tokyo", result.str("zoneId"))
        assertEquals("21:00", result.str("time"))
        assertEquals("UTC+09:00", result.str("utcOffset"))
        assertTrue(result.str("date").contains("17 June 2026"))
        assertFalse(result.containsKey("error"))
    }

    @Test
    fun `get_current_time reports an error for an unknown place`() {
        val result = call("get_current_time", mapOf("location" to JsonPrimitive("Atlantis")))
        assertTrue(result.containsKey("error"))
    }

    @Test
    fun `convert_time moves a wall-clock time between zones`() {
        val result = call(
            "convert_time",
            mapOf(
                "time" to JsonPrimitive("09:00"),
                "from_location" to JsonPrimitive("New York"),
                "to_location" to JsonPrimitive("London"),
            ),
        )
        // June → NY is UTC-4 (EDT), London UTC+1 (BST): 09:00 NY == 14:00 London, same day.
        assertTrue("expected 14:00 in '${result.str("to")}'", result.str("to").contains("14:00"))
        assertTrue(result.str("toIso").contains("14:00"))
        assertEquals("the same day", result.str("dayDifference"))
    }

    @Test
    fun `convert_time handles full ISO and space-separated datetimes with a day rollover`() {
        for (input in listOf("2026-06-17T23:00", "2026-06-17 23:00")) {
            val result = call(
                "convert_time",
                mapOf(
                    "time" to JsonPrimitive(input),
                    "from_location" to JsonPrimitive("New York"),
                    "to_location" to JsonPrimitive("Tokyo"),
                ),
            )
            // 23:00 EDT (UTC-4) is 12:00 the NEXT day in Tokyo (UTC+9).
            assertTrue("input '$input' → '${result.str("to")}'", result.str("to").contains("12:00"))
            assertEquals("the next day", result.str("dayDifference"))
        }
    }

    @Test
    fun `convert_time rejects an unparseable time`() {
        val result = call(
            "convert_time",
            mapOf(
                "time" to JsonPrimitive("teatime"),
                "from_location" to JsonPrimitive("London"),
                "to_location" to JsonPrimitive("Tokyo"),
            ),
        )
        assertTrue(result.containsKey("error"))
    }

    @Test
    fun `find_meeting_time ranks shared slots across places`() {
        val result = call(
            "find_meeting_time",
            mapOf(
                "locations" to JsonArray(listOf(JsonPrimitive("New York"), JsonPrimitive("London"), JsonPrimitive("Tokyo"))),
                "within_days" to JsonPrimitive(0),
            ),
        )
        assertEquals(3, (result.getValue("places") as JsonArray).size)
        val slots = result.getValue("rankedSlots") as JsonArray
        assertTrue("expected ranked slots", slots.isNotEmpty())
        // Each slot lists every resolved place's local hour.
        val first = slots.first() as JsonObject
        assertEquals(3, (first.getValue("localTimes") as JsonArray).size)
        assertTrue(first.containsKey("rating"))
    }

    @Test
    fun `find_meeting_time needs at least two recognizable places`() {
        val result = call(
            "find_meeting_time",
            mapOf("locations" to JsonArray(listOf(JsonPrimitive("Tokyo"), JsonPrimitive("Atlantis")))),
        )
        assertTrue(result.containsKey("error"))
    }

    @Test
    fun `groundingFacts injects home, saved zones, and the place named in the prompt`() = runBlocking {
        val facts = tools.groundingFacts(
            prompt = "what time is it in Tokyo right now?",
            homeZoneId = "America/Chicago",
            savedZones = listOf(SavedZone("Europe/London", "London")),
        )
        assertTrue(facts.contains("LIVE CLOCK"))
        assertTrue("home time missing", facts.contains("You ·"))
        assertTrue("saved zone missing", facts.contains("London"))
        assertTrue("prompt place missing", facts.contains("Tokyo"))
        // Tokyo is 21:00 at the pinned instant.
        assertTrue(facts.contains("21:00"))
    }

    @Test
    fun `groundingFacts resolves multi-word place names`() = runBlocking {
        val facts = tools.groundingFacts(
            prompt = "best time to call new york?",
            homeZoneId = "Europe/London",
            savedZones = emptyList(),
        )
        assertTrue("multi-word place missing", facts.contains("New York"))
    }

    @Test
    fun `groundingFacts still reports home time when no place is named`() = runBlocking {
        val facts = tools.groundingFacts(
            prompt = "hello there",
            homeZoneId = "America/Chicago",
            savedZones = emptyList(),
        )
        assertFalse(facts.isEmpty())
        assertTrue(facts.contains("You ·"))
        // 12:00 UTC is 07:00 in Chicago (UTC-5, CDT).
        assertTrue(facts.contains("07:00"))
    }

    @Test
    fun `groundingFacts dedupes the home zone against a saved zone`() = runBlocking {
        val facts = tools.groundingFacts(
            prompt = "morning",
            homeZoneId = "America/Chicago",
            savedZones = listOf(SavedZone("America/Chicago", "Home")),
        )
        // "America/Chicago" appears once (as the home line), not twice.
        assertEquals(1, facts.split("\n").count { it.contains("07:00") })
    }

    @Test
    fun `three tools are advertised and unknown calls are guarded`() {
        assertEquals(3, tools.functionDeclarations().size)
        val unknown = call("not_a_tool", emptyMap())
        assertTrue(unknown.containsKey("error"))
    }

    // ---- brutal edge cases ----------------------------------------------------------------------

    @Test
    fun `get_current_time errors on a blank or missing location`() {
        assertTrue(call("get_current_time", mapOf("location" to JsonPrimitive(""))).containsKey("error"))
        assertTrue(call("get_current_time", emptyMap()).containsKey("error"))
    }

    @Test
    fun `get_current_time is case-insensitive and handles a UTC zone`() {
        assertEquals("Asia/Tokyo", call("get_current_time", mapOf("location" to JsonPrimitive("TOKYO"))).str("zoneId"))
        val utc = call("get_current_time", mapOf("location" to JsonPrimitive("utc")))
        assertEquals("12:00", utc.str("time"))
        assertEquals("UTC+00:00", utc.str("utcOffset"))
    }

    @Test
    fun `get_current_time given a non-string arg degrades to an error`() {
        // The model fumbles and sends a number; there's no place "5" so it's a clean error, no crash.
        assertTrue(call("get_current_time", mapOf("location" to JsonPrimitive(5))).containsKey("error"))
    }

    @Test
    fun `convert_time across the same zone is a no-op day`() {
        val r = call(
            "convert_time",
            mapOf(
                "time" to JsonPrimitive("10:00"),
                "from_location" to JsonPrimitive("London"),
                "to_location" to JsonPrimitive("London"),
            ),
        )
        assertEquals("the same day", r.str("dayDifference"))
        assertTrue(r.str("to").contains("10:00"))
    }

    @Test
    fun `convert_time can roll back to the previous day`() {
        // 01:00 in Tokyo today is the previous day in New York.
        val r = call(
            "convert_time",
            mapOf(
                "time" to JsonPrimitive("01:00"),
                "from_location" to JsonPrimitive("Tokyo"),
                "to_location" to JsonPrimitive("New York"),
            ),
        )
        assertEquals("the previous day", r.str("dayDifference"))
    }

    @Test
    fun `convert_time errors on missing arguments`() {
        assertTrue(call("convert_time", mapOf("time" to JsonPrimitive("9am"))).containsKey("error"))
    }

    @Test
    fun `find_meeting_time dedupes repeated places and needs two distinct`() {
        val onlyOne = call(
            "find_meeting_time",
            mapOf("locations" to JsonArray(listOf(JsonPrimitive("London"), JsonPrimitive("London")))),
        )
        assertTrue(onlyOne.containsKey("error"))

        val twoDistinct = call(
            "find_meeting_time",
            mapOf("locations" to JsonArray(listOf(JsonPrimitive("London"), JsonPrimitive("Tokyo"), JsonPrimitive("London")))),
        )
        assertEquals(2, (twoDistinct.getValue("places") as JsonArray).size)
    }

    @Test
    fun `find_meeting_time errors on an empty location list`() {
        assertTrue(call("find_meeting_time", mapOf("locations" to JsonArray(emptyList()))).containsKey("error"))
    }

    @Test
    fun `groundingFacts caps the number of saved zones`() = runBlocking {
        val saved = listOf(
            "Asia/Tokyo", "Europe/London", "America/New_York", "Europe/Berlin",
            "Asia/Singapore", "Europe/Paris", "Asia/Kolkata", "Australia/Sydney",
        ).mapIndexed { i, id -> SavedZone(id, id.substringAfterLast('/')) }
        val facts = tools.groundingFacts("hello", "America/Chicago", saved)
        // Home line + at most MAX_SAVED_ZONES (6) saved lines.
        assertEquals(7, facts.split("\n").count { it.trimStart().startsWith("•") })
    }

    @Test
    fun `groundingFacts caps places named in the prompt`() = runBlocking {
        val facts = tools.groundingFacts(
            "times in tokyo london berlin singapore and paris",
            "America/Chicago",
            emptyList(),
        )
        // Home + at most 4 prompt places; the 5th (Paris, last) is dropped.
        assertEquals(5, facts.split("\n").count { it.trimStart().startsWith("•") })
        assertFalse(facts.contains("Paris"))
    }

    @Test
    fun `groundingFacts dedupes a prompt place against the home zone`() = runBlocking {
        val facts = tools.groundingFacts("what time is it in Tokyo?", "Asia/Tokyo", emptyList())
        // Tokyo is the home zone; it must not be listed twice.
        assertEquals(1, facts.split("\n").count { it.contains("21:00") })
    }

    @Test
    fun `convert_time accepts a non-zero-padded hour`() {
        // A model often emits "9:00" rather than "09:00"; both must convert NY→London to 14:00.
        val r = call(
            "convert_time",
            mapOf(
                "time" to JsonPrimitive("9:00"),
                "from_location" to JsonPrimitive("New York"),
                "to_location" to JsonPrimitive("London"),
            ),
        )
        assertFalse(r.containsKey("error"))
        assertTrue(r.str("to").contains("14:00"))
    }

    @Test
    fun `groundingFacts injects an app-computed conversion for a convert request`() = runBlocking {
        // The on-device fix for "Convert 9 AM Sydney to my local time": the LIVE CLOCK must carry the
        // exact conversion so Nano (no tool access) doesn't do the math itself and get it wrong.
        val facts = tools.groundingFacts("Convert 9 AM Sydney time to my local time", "America/Chicago", emptyList())
        assertTrue("missing conversions section", facts.contains("TIME CONVERSIONS"))
        // 09:00 AEST (UTC+10) is 18:00 the previous day in Chicago (CDT, UTC-5).
        assertTrue("wrong conversion in:\n$facts", facts.contains("09:00 in Sydney = 18:00 in Chicago (the previous day)"))
    }

    @Test
    fun `groundingFacts omits conversions when no time is named`() = runBlocking {
        val facts = tools.groundingFacts("what time is it in Sydney?", "America/Chicago", emptyList())
        assertFalse(facts.contains("TIME CONVERSIONS"))
    }

    @Test
    fun `convert_time accepts a twelve-hour am pm time`() {
        val r = call(
            "convert_time",
            mapOf(
                "time" to JsonPrimitive("9 am"),
                "from_location" to JsonPrimitive("New York"),
                "to_location" to JsonPrimitive("London"),
            ),
        )
        assertTrue(r.str("to").contains("14:00"))
    }

    // ---- worst-case / adversarial ---------------------------------------------------------------

    @Test
    fun `convert_time rejects out-of-range and garbage times`() {
        for (bad in listOf("25:00", "99:99", "🕘", "abc", "13 pm")) {
            val r = call(
                "convert_time",
                mapOf(
                    "time" to JsonPrimitive(bad),
                    "from_location" to JsonPrimitive("Tokyo"),
                    "to_location" to JsonPrimitive("London"),
                ),
            )
            assertTrue("expected error for time '$bad'", r.containsKey("error"))
        }
    }

    @Test
    fun `find_meeting_time with many duplicates of one place still errors`() {
        val locs = JsonArray(List(10) { JsonPrimitive("London") })
        assertTrue(call("find_meeting_time", mapOf("locations" to locs)).containsKey("error"))
    }

    @Test
    fun `groundingFacts bounds a pathologically long prompt`() = runBlocking {
        // Place named past the token cap is ignored; the call returns promptly with just home.
        val prompt = ("blah ".repeat(60)) + "tokyo"
        val facts = tools.groundingFacts(prompt, "America/Chicago", emptyList())
        assertTrue(facts.contains("You ·"))
        assertFalse("place past the token cap should be ignored", facts.contains("Tokyo"))
    }

    @Test
    fun `groundingFacts degrades gracefully when the home zone is invalid`() = runBlocking {
        // Bad home id is skipped (not crashed); a prompt place still resolves.
        val facts = tools.groundingFacts("what time is it in Tokyo?", "Not/AZone", emptyList())
        assertTrue(facts.contains("Tokyo"))
        assertFalse(facts.contains("You ·"))
    }

    @Test
    fun `dispatch tolerates a wrong-typed argument`() {
        // locations sent as a string instead of an array → empty list → clean error, no crash.
        val r = call("find_meeting_time", mapOf("locations" to JsonPrimitive("London")))
        assertTrue(r.containsKey("error"))
    }

    @Test
    fun `get_current_time formats a sub-hour UTC offset`() {
        // Nepal is UTC+05:45; 12:00 UTC → 17:45 there.
        val r = call("get_current_time", mapOf("location" to JsonPrimitive("Kathmandu")))
        assertEquals("17:45", r.str("time"))
        assertEquals("UTC+05:45", r.str("utcOffset"))
    }

    @Test
    fun `find_meeting_time coerces an out-of-range within_days`() {
        for (d in listOf(-10, 100000)) {
            val r = call(
                "find_meeting_time",
                mapOf(
                    "locations" to JsonArray(listOf(JsonPrimitive("London"), JsonPrimitive("Tokyo"))),
                    "within_days" to JsonPrimitive(d),
                ),
            )
            assertFalse("within_days=$d should not error", r.containsKey("error"))
            assertEquals(2, (r.getValue("places") as JsonArray).size)
        }
    }

    @Test
    fun `groundingFacts includes a saved person named in the prompt`() = runBlocking {
        val facts = tools.groundingFacts(
            prompt = "best time to call Priya this week?",
            homeZoneId = "America/Chicago",
            savedZones = emptyList(),
            people = listOf(Person(name = "Priya", zoneId = "Asia/Kolkata")),
        )
        assertTrue(facts.contains("Priya"))
        // 12:00 UTC is 17:30 in Kolkata (UTC+5:30).
        assertTrue(facts.contains("17:30"))
    }

    @Test
    fun `groundingFacts precomputes meeting slots for a multi-place meeting query`() = runBlocking {
        val facts = tools.groundingFacts(
            prompt = "best time to meet for New York and London?",
            homeZoneId = "America/Chicago",
            savedZones = emptyList(),
        )
        assertTrue("missing meeting slots in:\n$facts", facts.contains("MEETING SLOTS"))
        assertTrue(facts.contains("QUERY INTENT: meeting time"))
    }

    @Test
    fun `groundingFacts converts between two named places when both appear`() = runBlocking {
        val facts = tools.groundingFacts(
            prompt = "convert 9am New York to London",
            homeZoneId = "America/Chicago",
            savedZones = emptyList(),
        )
        assertTrue(facts.contains("TIME CONVERSIONS"))
        assertTrue("expected NY→London in:\n$facts", facts.contains("in New York =") && facts.contains("in London"))
    }

    @Test
    fun `groundingFacts treats a plain what's-the-time question as current time not conversion`() = runBlocking {
        val facts = tools.groundingFacts(
            prompt = "What's the time in Tokyo?",
            homeZoneId = "America/Chicago",
            savedZones = emptyList(),
        )
        // "what's" must not trigger CONVERT without a clock time — otherwise this current-time
        // query gets a bogus conversion hint and (CONVERT-without-"now") is cached stale.
        assertTrue("expected current-time intent in:\n$facts", facts.contains("QUERY INTENT: current time lookup"))
    }

    @Test
    fun `groundingFacts keeps a clocked what's query as a conversion`() = runBlocking {
        val facts = tools.groundingFacts(
            prompt = "What's 3 PM in London?",
            homeZoneId = "America/Chicago",
            savedZones = emptyList(),
        )
        assertTrue("expected conversion intent in:\n$facts", facts.contains("QUERY INTENT: time conversion"))
    }

    @Test
    fun `groundingFacts precomputes meeting slots for people only`() = runBlocking {
        val facts = tools.groundingFacts(
            prompt = "best time to call Priya and Emma tomorrow?",
            homeZoneId = "America/Chicago",
            savedZones = emptyList(),
            people = listOf(
                Person(name = "Priya", zoneId = "Asia/Kolkata"),
                Person(name = "Emma", zoneId = "Europe/London"),
            ),
        )
        assertTrue("missing meeting slots in:\n$facts", facts.contains("MEETING SLOTS"))
        assertTrue(facts.contains("Priya"))
        assertTrue(facts.contains("Emma"))
    }

    @Test
    fun `groundingFacts resolves timezone abbreviations in the prompt`() = runBlocking {
        val facts = tools.groundingFacts(
            prompt = "what time is it in EST right now?",
            homeZoneId = "America/Chicago",
            savedZones = emptyList(),
        )
        assertTrue(facts.contains("EST"))
        // 12:00 UTC is 08:00 in New York (EDT).
        assertTrue(facts.contains("08:00"))
    }

    @Test
    fun `groundingFacts tags a mentioned person with their schedule state`() = runBlocking {
        val facts = tools.groundingFacts(
            prompt = "is Priya awake now?",
            homeZoneId = "America/Chicago",
            savedZones = emptyList(),
            people = listOf(Person(name = "Priya", zoneId = "Asia/Kolkata", workStartHour = 9, workEndHour = 17)),
        )
        assertTrue(facts.contains("Priya"))
        assertTrue(
            facts.contains("(working)") || facts.contains("(off-hours)") ||
                facts.contains("(awake") || facts.contains("(likely asleep)")
        )
    }

    @Test
    fun `resolveZoneId uses PlaceIndex without hitting resolvePlace`() = runBlocking {
        var resolveCalls = 0
        val localTools = MeridianAiTools(
            resolvePlace = {
                resolveCalls++
                null
            },
            findOverlap = FindOverlapUseCase(TimeEngine(object : Clock {
                override fun now(): Instant = fixedInstant.toKotlinInstant()
            })),
            now = { fixedInstant },
        )
        assertEquals("Asia/Tokyo", localTools.resolveZoneId("Tokyo"))
        assertEquals(0, resolveCalls)
    }

    @Test
    fun `convert_time can roll forward to the next day`() {
        // 23:00 in London (BST) is 07:00 the next day in Tokyo.
        val r = call(
            "convert_time",
            mapOf(
                "time" to JsonPrimitive("23:00"),
                "from_location" to JsonPrimitive("London"),
                "to_location" to JsonPrimitive("Tokyo"),
            ),
        )
        assertEquals("the next day", r.str("dayDifference"))
        assertTrue(r.str("to").contains("07:00"))
    }
}
