package com.example.core.ai

import com.example.core.data.Person
import com.example.core.data.SavedZone
import com.example.core.data.localLocationLabel
import com.example.core.time.FindOverlapUseCase
import com.example.core.time.MeetingParticipant
import com.example.core.time.OffsetZones
import com.example.core.time.PlaceIndex
import com.example.core.time.LocalView
import com.example.core.time.TzAbbreviations
import com.google.firebase.ai.type.FunctionCallPart
import com.google.firebase.ai.type.FunctionDeclaration
import com.google.firebase.ai.type.Schema
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.datetime.toKotlinInstant
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.time.Instant
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit
import java.util.Locale

/**
 * The assistant's deterministic capability layer — the bridge that lets the model answer real-world
 * "what time is it in Tokyo?" questions and act on time instead of replying that it has no live data.
 *
 * Every fact here is computed by the app's own time engine and zone search (§12.7 — the LLM never
 * does time math), surfaced two complementary ways because the two inference paths differ:
 *
 *  - [functionDeclarations] + [dispatch] expose callable tools (`get_current_time`, `convert_time`,
 *    `find_meeting_time`) for the **cloud** Gemini path, which supports function calling. The model
 *    decides when to call them; [dispatch] runs the real computation and hands back JSON.
 *  - [groundingFacts] pre-resolves the live clock for the user's zones and any places named in the
 *    prompt and injects them as plain text into the system instruction. This is the path that works
 *    **on-device** (Gemini Nano), whose runtime silently drops tools (its request only carries text),
 *    so without it Nano would keep saying it lacks real-time information.
 *
 * Zone resolution is delegated to [resolvePlace] (the same multi-layer search the add-a-zone UI uses,
 * so "Tokyo", "NYC", "LHR", and "UTC+9" all resolve); [now] is injected so tests can pin the clock.
 */
class MeridianAiTools(
    private val resolvePlace: suspend (String) -> SavedZone?,
    private val findOverlap: FindOverlapUseCase,
    private val now: () -> Instant = { Instant.now() },
) {

    /** Tool schemas advertised to the (cloud) model. Mirror the branches in [dispatch] exactly. */
    fun functionDeclarations(): List<FunctionDeclaration> = listOf(
        FunctionDeclaration(
            "get_current_time",
            "Get the current real-world local date and time at a city, place, airport code, or UTC " +
                "offset. Call this whenever the user asks what time it is somewhere.",
            mapOf(
                "location" to Schema.string(
                    "A city, place, airport code, or UTC offset — e.g. \"Tokyo\", \"New York\", " +
                        "\"LHR\", or \"UTC+9\"."
                )
            ),
            emptyList(),
        ),
        FunctionDeclaration(
            "convert_time",
            "Convert a clock time from one place to the equivalent local time in another place.",
            mapOf(
                "time" to Schema.string(
                    "The time to convert — 24-hour \"HH:mm\" or ISO \"yyyy-MM-ddTHH:mm\". If only a " +
                        "time of day is given, today's date in the source place is assumed."
                ),
                "from_location" to Schema.string("The place the given time is in."),
                "to_location" to Schema.string("The place to convert the time into."),
            ),
            emptyList(),
        ),
        FunctionDeclaration(
            "find_meeting_time",
            "Find the fairest meeting hours shared across two or more places, ranked best-first — " +
                "for questions like \"best time to meet for New York, Berlin and Singapore?\".",
            mapOf(
                "locations" to Schema.array(
                    Schema.string("A city, place, or time zone."),
                    "Two or more places that need to meet.",
                ),
                "within_days" to Schema.integer(
                    "How many days from today to search (0 = today, 1 = tomorrow). Optional; " +
                        "defaults to today."
                ),
            ),
            listOf("within_days"),
        ),
    )

    /** Executes a model-requested tool call and returns its result as the JSON the model gets back. */
    suspend fun dispatch(call: FunctionCallPart): JsonObject = when (call.name) {
        "get_current_time" -> getCurrentTime(call.stringArg("location"))
        "convert_time" -> convertTime(
            call.stringArg("time"),
            call.stringArg("from_location"),
            call.stringArg("to_location"),
        )
        "find_meeting_time" -> findMeetingTime(call.stringListArg("locations"), call.intArg("within_days") ?: 0)
        else -> errorResult("Unknown tool \"${call.name}\".")
    }

    private suspend fun getCurrentTime(location: String?): JsonObject {
        if (location.isNullOrBlank()) return errorResult("No location was provided.")
        val zone = resolveZone(location) ?: return errorResult("Couldn't find a place matching \"$location\".")
        val zdt = ZonedDateTime.ofInstant(now(), zone.zone)
        return buildJsonObject {
            put("location", zone.name)
            put("zoneId", zone.id)
            put("time", zdt.format(CLOCK_FMT))
            put("date", zdt.format(DATE_FMT))
            put("dayOfWeek", zdt.dayOfWeek.getDisplayName(TextStyle.FULL, Locale.ENGLISH))
            put("utcOffset", "UTC${zdt.offset.id.let { if (it == "Z") "+00:00" else it }}")
            put("iso", zdt.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME))
        }
    }

    private suspend fun convertTime(time: String?, from: String?, to: String?): JsonObject {
        if (time.isNullOrBlank() || from.isNullOrBlank() || to.isNullOrBlank()) {
            return errorResult("convert_time needs a time, a from_location, and a to_location.")
        }
        val fromZone = resolveZone(from) ?: return errorResult("Couldn't find a place matching \"$from\".")
        val toZone = resolveZone(to) ?: return errorResult("Couldn't find a place matching \"$to\".")
        val source = parseWallClock(time, fromZone.zone)
            ?: return errorResult("Couldn't understand the time \"$time\". Use \"HH:mm\" or \"yyyy-MM-ddTHH:mm\".")
        val target = source.withZoneSameInstant(toZone.zone)
        val dayShift = target.toLocalDate().toEpochDay() - source.toLocalDate().toEpochDay()
        return buildJsonObject {
            put("from", "${fromZone.name}: ${source.format(CLOCK_FMT)} ${source.format(DATE_FMT)}")
            put("to", "${toZone.name}: ${target.format(CLOCK_FMT)} ${target.format(DATE_FMT)}")
            put("fromZoneId", fromZone.id)
            put("toZoneId", toZone.id)
            put("fromIso", source.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME))
            put("toIso", target.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME))
            put(
                "dayDifference",
                when {
                    dayShift > 0L -> "the next day"
                    dayShift < 0L -> "the previous day"
                    else -> "the same day"
                },
            )
        }
    }

    private suspend fun findMeetingTime(locations: List<String>, withinDays: Int): JsonObject {
        val resolved = LinkedHashMap<String, Resolved>()
        for (raw in locations) {
            val zone = resolveZone(raw) ?: continue
            resolved.putIfAbsent(zone.id, zone)
        }
        if (resolved.size < 2) {
            return errorResult("Need at least two recognizable places to compare; resolved ${resolved.size}.")
        }
        val baseDate = now().truncatedTo(ChronoUnit.DAYS)
            .plus(withinDays.toLong().coerceIn(0L, 365L), ChronoUnit.DAYS)
        val slots = findOverlap.rankParticipantSlots(
            baseDate.toKotlinInstant(),
            resolved.values.map { MeetingParticipant(it.id) },
        ).take(3)
        return buildJsonObject {
            put("places", buildJsonArray { resolved.values.forEach { add(it.name) } })
            put("rankedSlots", buildJsonArray {
                slots.forEach { slot ->
                    add(buildJsonObject {
                        put("rating", slot.ratingLabel)
                        put("localTimes", buildJsonArray {
                            resolved.values.forEach { r ->
                                val hour = slot.localHours[r.id]
                                if (hour != null) add("${r.name} ${"%02d:00".format(hour)}")
                            }
                        })
                    })
                }
            })
        }
    }

    /**
     * The live-clock block injected into the system instruction so the model — including on-device
     * Nano, which can't call tools — always has the real times in front of it. Covers the user's home
     * zone, their saved zones, and any places named in [prompt]. Returns "" when nothing resolves.
     */
    suspend fun groundingFacts(
        prompt: String,
        homeZoneId: String,
        savedZones: List<SavedZone>,
        people: List<Person> = emptyList(),
    ): String = buildGrounding(prompt, homeZoneId, savedZones, people).block

    suspend fun buildGrounding(
        prompt: String,
        homeZoneId: String,
        savedZones: List<SavedZone>,
        people: List<Person> = emptyList(),
    ): AiGrounding = withContext(Dispatchers.IO) {
        val instant = now()
        val lines = LinkedHashMap<String, String>()
        val linePeople = LinkedHashMap<String, Person>()
        fun add(zoneId: String, name: String, person: Person? = null) {
            val key = person?.let { "${it.zoneId}\u0000${it.displayLocation()}" } ?: zoneId
            if (person == null && lines.containsKey(key)) return
            val zone = runCatching { ZoneId.of(zoneId) }.getOrNull() ?: return
            val zdt = ZonedDateTime.ofInstant(instant, zone)
            val tag = person?.let { scheduleTag(zdt.hour, it) }.orEmpty()
            lines[key] = "$name — ${zdt.format(GROUNDING_FMT)}$tag"
            if (person != null) linePeople[key] = person
        }

        add(homeZoneId, "You · ${savedZones.localLocationLabel(homeZoneId)}")
        savedZones.take(MAX_SAVED_ZONES).forEach { add(it.id, it.displayName) }
        savedZonesMentionedIn(prompt, savedZones).forEach { add(it.id, it.displayName) }

        val mentionedPeople = peopleMentionedIn(prompt, people)
        mentionedPeople.forEach { person ->
            val label = if (person.name.isBlank()) person.displayLocation()
                        else "${person.name} · ${person.displayLocation()}"
            add(person.zoneId, label, person)
        }

        // Resolve places explicitly named in the prompt: longest phrase first, never re-using a token
        // already claimed by a longer match, and bounded so an off-topic prompt stays cheap.
        // Curated [PlaceIndex] hits are tried before the full DB search so common cities resolve in
        // one indexed lookup instead of up to 24 SQLite round-trips.
        val tokens = TOKEN_SPLIT.split(prompt.trim()).filter { it.isNotBlank() }.take(MAX_PROMPT_TOKENS)
        val claimed = BooleanArray(tokens.size)
        val promptPlaces = mutableListOf<Resolved>()
        var tries = 0
        for (candidate in rankedPlaceCandidates(tokens, prompt)) {
            if (promptPlaces.size >= MAX_PROMPT_PLACES) break
            if (candidate.overlaps(claimed)) continue
            val zone = resolveZoneFast(candidate.text)
                ?: if (tries >= MAX_RESOLVE_TRIES) null
                else {
                    tries++
                    resolveZoneSlow(candidate.text)
                }
                ?: continue
            candidate.claim(claimed)
            promptPlaces += zone
            add(zone.id, zone.name)
        }

        if (lines.isEmpty()) return@withContext AiGrounding("", AiQueryIntent.GENERAL)

        val intent = detectIntent(prompt)
        val conversions = buildConversions(prompt, promptPlaces, homeZoneId, instant)
        val participants = meetingParticipants(promptPlaces, mentionedPeople)
        val withinDays = parseMeetingWithinDays(prompt)
        val meetingSlots = if (intent == AiQueryIntent.MEETING && participants.size >= 2) {
            buildMeetingSlots(participants, withinDays, instant)
        } else {
            emptyList()
        }

        val block = buildString {
            append(
                "LIVE CLOCK — authoritative real-world times, current as of this request. Use these " +
                    "directly and never say you lack real-time information:\n"
            )
            lines.values.forEach { append("• ").append(it).append('\n') }
            if (conversions.isNotEmpty()) {
                append("TIME CONVERSIONS (already computed — use these exact values, do not recompute):\n")
                conversions.forEach { append("• ").append(it).append('\n') }
            }
            if (meetingSlots.isNotEmpty()) {
                append("MEETING SLOTS (already ranked — use these exact values, do not recompute):\n")
                meetingSlots.forEach { append("• ").append(it).append('\n') }
            }
            append("QUERY INTENT: ").append(intent.promptHint).append('\n')
        }.trimEnd()
        AiGrounding(block, intent)
    }

    /**
     * When [prompt] names a clock time, converts that time (today, in each prompt-named place) to the
     * user's home zone — or between the first two named places when the user asks A→B. Empty if no
     * time is named or no places were resolved from the prompt.
     */
    private fun buildConversions(
        prompt: String,
        promptPlaces: List<Resolved>,
        homeZoneId: String,
        instant: Instant,
    ): List<String> {
        if (promptPlaces.isEmpty()) return emptyList()
        val time = parseClockTime(prompt) ?: return emptyList()
        val ordered = promptPlaces.sortedBy { place ->
            prompt.lowercase(Locale.ROOT).indexOf(place.name.lowercase(Locale.ROOT)).let { if (it < 0) Int.MAX_VALUE else it }
        }
        if (ordered.size >= 2 && !wantsHomeTime(prompt)) {
            return listOf(formatConversion(ordered[0], ordered[1], time, instant))
        }
        val homeZone = runCatching { ZoneId.of(homeZoneId) }.getOrNull() ?: return emptyList()
        val homeName = shortZoneName(homeZoneId)
        return ordered.filter { it.zone != homeZone }.map { place ->
            formatConversion(place, Resolved(homeZoneId, homeName, homeZone), time, instant)
        }
    }

    private fun formatConversion(
        from: Resolved,
        to: Resolved,
        time: LocalTime,
        instant: Instant,
    ): String {
        val src = ZonedDateTime.ofInstant(instant, from.zone).toLocalDate().atTime(time).atZone(from.zone)
        val dst = src.withZoneSameInstant(to.zone)
        val shift = dst.toLocalDate().toEpochDay() - src.toLocalDate().toEpochDay()
        val shiftLabel = when {
            shift > 0L -> " (the next day)"
            shift < 0L -> " (the previous day)"
            else -> ""
        }
        return "${src.format(CLOCK_FMT)} in ${from.name} = ${dst.format(CLOCK_FMT)} in ${to.name}$shiftLabel"
    }

    /** Pre-ranks fair meeting hours when the prompt asks for one — on-device Nano can't call tools. */
    private suspend fun buildMeetingSlots(
        participants: List<MeetingParticipantLabel>,
        withinDays: Int,
        instant: Instant,
    ): List<String> {
        if (participants.size < 2) return emptyList()
        val baseDate = instant.truncatedTo(ChronoUnit.DAYS)
            .plus(withinDays.toLong().coerceIn(0L, 365L), ChronoUnit.DAYS)
            .toKotlinInstant()
        val meetingPeople = participants.map { it.participant }
        return findOverlap.rankParticipantSlots(baseDate, meetingPeople)
            .take(3)
            .map { slot ->
                val locals = participants.mapNotNull { label ->
                    slot.localHours[label.participant.zoneId]?.let { hour ->
                        val viewTag = when (slot.localViews[label.participant.zoneId]) {
                            LocalView.WORKING -> " (working)"
                            LocalView.AWAKE -> " (awake)"
                            LocalView.OUTSIDE_HOURS -> " (off-hours)"
                            LocalView.ASLEEP -> " (asleep)"
                            null -> ""
                        }
                        "${label.displayName} ${"%02d:00".format(hour)}$viewTag"
                    }
                }.joinToString(", ")
                "${slot.ratingLabel}: $locals"
            }
    }

    private data class MeetingParticipantLabel(
        val displayName: String,
        val participant: MeetingParticipant,
    )

    private fun meetingParticipants(
        promptPlaces: List<Resolved>,
        mentionedPeople: List<Person>,
    ): List<MeetingParticipantLabel> {
        val out = LinkedHashMap<String, MeetingParticipantLabel>()
        promptPlaces.forEach { place ->
            out.putIfAbsent(place.id, MeetingParticipantLabel(place.name, MeetingParticipant(place.id)))
        }
        mentionedPeople.forEach { person ->
            val key = "${person.zoneId}\u0000${person.displayLocation()}"
            out.putIfAbsent(
                key,
                MeetingParticipantLabel(
                    person.name.ifBlank { person.displayLocation() },
                    MeetingParticipant(
                        person.zoneId,
                        person.workStartHour,
                        person.workEndHour,
                        person.dndStartHour,
                        person.dndEndHour,
                    ),
                ),
            )
        }
        return out.values.toList()
    }

    private fun savedZonesMentionedIn(prompt: String, savedZones: List<SavedZone>): List<SavedZone> {
        if (savedZones.isEmpty()) return emptyList()
        val lower = prompt.lowercase(Locale.ROOT)
        return savedZones
            .filter { zone ->
                val name = zone.displayName.trim().lowercase(Locale.ROOT)
                name.length >= MIN_TOKEN_LEN && lower.contains(name)
            }
            .sortedByDescending { it.displayName.length }
            .distinctBy { it.id }
    }

    private fun wantsHomeTime(prompt: String): Boolean {
        val p = prompt.lowercase(Locale.ROOT)
        return HOME_TIME_HINT.any { p.contains(it) }
    }

    private fun parseMeetingWithinDays(prompt: String): Int {
        val p = prompt.lowercase(Locale.ROOT)
        return when {
            "day after tomorrow" in p -> 2
            "tomorrow" in p -> 1
            else -> 0
        }
    }

    private fun scheduleTag(hour: Int, person: Person): String = when {
        inDndWindow(hour, person.dndStartHour, person.dndEndHour) -> " (do not disturb)"
        inWorkWindow(hour, person.workStartHour, person.workEndHour) -> " (working)"
        hoursOutsideWindow(hour, person.workStartHour, person.workEndHour) <= 2 -> " (awake, off-hours)"
        hoursOutsideWindow(hour, person.workStartHour, person.workEndHour) <= 4 -> " (off-hours)"
        else -> " (likely asleep)"
    }

    private fun inWorkWindow(hour: Int, start: Int, end: Int): Boolean = inWindow(hour, start, end)

    private fun inDndWindow(hour: Int, start: Int, end: Int): Boolean =
        start in 0..23 && end in 0..23 && inWindow(hour, start, end)

    private fun inWindow(hour: Int, start: Int, end: Int): Boolean {
        if (start < 0 || end < 0 || start == end) return false
        return if (start < end) hour in start until end else hour >= start || hour < end
    }

    private fun hoursOutsideWindow(hour: Int, start: Int, end: Int): Int {
        if (inWindow(hour, start, end)) return 0
        val lastWorkingHour = (end + 23) % 24
        return minOf(circularDistance(hour, start), circularDistance(hour, lastWorkingHour))
    }

    private fun circularDistance(a: Int, b: Int): Int {
        val diff = ((a - b) % 24 + 24) % 24
        return minOf(diff, 24 - diff)
    }

    private fun detectIntent(prompt: String): AiQueryIntent {
        val p = prompt.lowercase(Locale.ROOT)
        return when {
            SCHEDULE_HINT.any { p.contains(it) } -> AiQueryIntent.SCHEDULE
            MEETING_HINT.any { p.contains(it) } -> AiQueryIntent.MEETING
            CONVERT_HINT.any { p.contains(it) } || parseClockTime(prompt) != null && p.contains(" to ") ->
                AiQueryIntent.CONVERT
            CURRENT_TIME_HINT.any { p.contains(it) } -> AiQueryIntent.CURRENT_TIME
            else -> AiQueryIntent.GENERAL
        }
    }

    private val AiQueryIntent.promptHint: String
        get() = when (this) {
            AiQueryIntent.CURRENT_TIME -> "current time lookup — answer from LIVE CLOCK"
            AiQueryIntent.CONVERT -> "time conversion — answer from TIME CONVERSIONS if present, else call convert_time"
            AiQueryIntent.MEETING -> "meeting time — answer from MEETING SLOTS if present, else call find_meeting_time"
            AiQueryIntent.SCHEDULE -> "schedule an event — reply with schedule JSON only"
            AiQueryIntent.GENERAL -> "general time question — use LIVE CLOCK and tools as needed"
        }
    private fun peopleMentionedIn(prompt: String, people: List<Person>): List<Person> {
        if (people.isEmpty()) return emptyList()
        val lower = prompt.lowercase(Locale.ROOT)
        return people
            .filter { person ->
                val name = person.name.trim().lowercase(Locale.ROOT)
                name.length >= MIN_PERSON_NAME_LEN && lower.contains(name)
            }
            .sortedByDescending { it.name.length }
            .distinctBy { it.zoneId }
            .take(MAX_MENTIONED_PEOPLE)
    }

    private fun shortZoneName(zoneId: String): String = zoneId.substringAfterLast('/').replace('_', ' ')

    // --- helpers -------------------------------------------------------------------------------

    /** Resolves a place name or zone query to a validated IANA zone id, or null. */
    suspend fun resolveZoneId(query: String): String? = resolveZone(query)?.id

    private data class Resolved(val id: String, val name: String, val zone: ZoneId)

    private suspend fun resolveZone(query: String): Resolved? =
        resolveZoneFast(query) ?: resolveZoneSlow(query)

    /** Curated index, abbreviations, and UTC offsets — synchronous, no SQLite. */
    private fun resolveZoneFast(query: String): Resolved? {
        TzAbbreviations.resolve(query)?.let { match ->
            val zone = runCatching { ZoneId.of(match.zoneId) }.getOrNull() ?: return@let null
            return Resolved(match.zoneId, match.displayName, zone)
        }
        PlaceIndex.resolveConfident(query)?.let { place ->
            val zone = runCatching { ZoneId.of(place.zoneId) }.getOrNull() ?: return@let null
            return Resolved(place.zoneId, place.city, zone)
        }
        OffsetZones.parse(query).firstOrNull()?.let { match ->
            val zone = runCatching { ZoneId.of(match.zoneId) }.getOrNull() ?: return@let null
            return Resolved(match.zoneId, match.displayName, zone)
        }
        return null
    }

    private suspend fun resolveZoneSlow(query: String): Resolved? {
        val match = runCatching { resolvePlace(query) }.getOrNull() ?: return null
        val zone = runCatching { ZoneId.of(match.id) }.getOrNull() ?: return null
        return Resolved(match.id, match.displayName, zone)
    }

    /** Parses a time-of-day (today in [zone]) or full ISO "yyyy-MM-ddTHH:mm" into a zoned time. */
    private fun parseWallClock(raw: String, zone: ZoneId): ZonedDateTime? {
        // Tolerate a space between date and time ("2026-06-17 09:00") as well as the ISO "T".
        val text = raw.trim().replaceFirst(DATE_TIME_SPACE, "T")
        runCatching { LocalDateTime.parse(text) }.getOrNull()?.let { return it.atZone(zone) }
        parseClockTime(text)?.let { time ->
            return ZonedDateTime.ofInstant(now(), zone).toLocalDate().atTime(time).atZone(zone)
        }
        return null
    }

    /** Lenient time-of-day so a model's "9:00" / "9am" / "2:30 pm" works, not just padded "09:00". */
    private fun parseClockTime(raw: String): LocalTime? {
        val t = raw.lowercase(Locale.ROOT).trim()
        AM_PM_CLOCK.find(t)?.let { m ->
            var h = m.groupValues[1].toInt()
            val min = m.groupValues[2].toIntOrNull() ?: 0
            if (h in 1..12 && min in 0..59) {
                if (h == 12) h = 0
                if (m.groupValues[3].replace(".", "") == "pm") h += 12
                return LocalTime.of(h, min)
            }
        }
        HOUR_MINUTE.find(t)?.let { m ->
            val h = m.groupValues[1].toInt()
            val min = m.groupValues[2].toInt()
            if (h in 0..23 && min in 0..59) return LocalTime.of(h, min)
        }
        return null
    }

    private fun FunctionCallPart.stringArg(key: String): String? =
        args[key]?.let { runCatching { it.jsonPrimitive.contentOrNull }.getOrNull() }

    private fun FunctionCallPart.intArg(key: String): Int? =
        args[key]?.let { runCatching { it.jsonPrimitive.intOrNull }.getOrNull() }

    private fun FunctionCallPart.stringListArg(key: String): List<String> =
        args[key]?.let {
            runCatching { it.jsonArray.mapNotNull { e -> e.jsonPrimitive.contentOrNull } }.getOrNull()
        } ?: emptyList()

    private fun errorResult(message: String): JsonObject = buildJsonObject { put("error", message) }

    /** A contiguous run of prompt tokens [start, end) tried as one place name; [-1,-1) = whole-string. */
    private class PlaceCandidate(val start: Int, val end: Int, val text: String) {
        fun overlaps(claimed: BooleanArray): Boolean = (start until end).any { claimed[it] }
        fun claim(claimed: BooleanArray) { for (i in start until end) claimed[i] = true }
    }

    /** UTC/GMT-offset phrases first, then word n-grams ranked by PlaceIndex confidence. */
    private fun rankedPlaceCandidates(tokens: List<String>, prompt: String): List<PlaceCandidate> {
        val out = mutableListOf<PlaceCandidate>()
        OFFSET_IN_PROMPT.findAll(prompt).forEach { match ->
            out += PlaceCandidate(-1, -1, match.value.replace(Regex("\\s+"), ""))
        }
        tokens.forEach { token ->
            if (token.contains("utc", ignoreCase = true) || token.contains("gmt", ignoreCase = true)) {
                out += PlaceCandidate(-1, -1, token)
            } else if (TzAbbreviations.looksLikeAbbreviation(token)) {
                out += PlaceCandidate(-1, -1, token)
            }
        }
        for (size in MAX_NGRAM downTo 1) {
            if (size > tokens.size) continue
            for (start in 0..tokens.size - size) {
                val slice = tokens.subList(start, start + size)
                if (size == 1) {
                    val t = slice[0].lowercase(Locale.ROOT)
                    if (t.length < MIN_TOKEN_LEN || t in STOPWORDS) continue
                } else {
                    if (slice.first().lowercase(Locale.ROOT) in STOPWORDS) continue
                    if (slice.last().lowercase(Locale.ROOT) in STOPWORDS) continue
                }
                out += PlaceCandidate(start, start + size, slice.joinToString(" "))
            }
        }
        return out.sortedWith(compareBy({ candidatePriority(it.text) }, { -it.text.length }))
    }
    private fun candidatePriority(text: String): Int {
        if (OffsetZones.parse(text).isNotEmpty()) return 0
        if (TzAbbreviations.resolve(text) != null) return 1
        if (PlaceIndex.resolveConfident(text) != null) return 2
        val q = text.trim().lowercase(Locale.ROOT)
        if (q.length < MIN_TOKEN_LEN) return 100
        return if (q.contains(' ')) 5 else 50
    }

    private companion object {
        const val MAX_NGRAM = 3
        const val MIN_TOKEN_LEN = 3
        const val MAX_PROMPT_PLACES = 4
        const val MAX_SAVED_ZONES = 6
        const val MAX_RESOLVE_TRIES = 24
        const val MAX_PROMPT_TOKENS = 40
        const val MAX_MENTIONED_PEOPLE = 4
        const val MIN_PERSON_NAME_LEN = 2

        val OFFSET_IN_PROMPT = Regex("""(?i)\b(?:utc|gmt)\s*([+-])\s*(\d{1,2})(?::?(\d{2}))?\b""")
        val SCHEDULE_HINT = listOf("schedule", "add event", "add meeting", "set up", "book", "create event")
        val MEETING_HINT = listOf(
            "meeting", "meet with", "best time", "good time", "fair time", "overlap",
            "call with", "schedule a call", "find a time", "when can we", "time to meet",
        )
        val CONVERT_HINT = listOf("convert", "what is", "what's", "equals", "equivalent")
        val CURRENT_TIME_HINT = listOf(
            "what time", "current time", "time is it", "time in", "time now", "right now",
        )
        val HOME_TIME_HINT = listOf("my time", "my local", "local time", "my timezone", "here at home")

        val TOKEN_SPLIT = Regex("[^\\p{L}\\p{Nd}+]+")
        // The single space between an ISO date and time, so "2026-06-17 09:00" parses like the "T" form.
        val DATE_TIME_SPACE = Regex("(?<=\\d) (?=\\d)")
        // Lenient clock-time forms accepted by convert_time (digit lookarounds, not \b, for ISO "T14:00").
        val AM_PM_CLOCK = Regex("(?<!\\d)(\\d{1,2})(?::(\\d{2}))?\\s*(a\\.?m\\.?|p\\.?m\\.?)")
        val HOUR_MINUTE = Regex("(?<![\\d:])(\\d{1,2}):(\\d{2})(?!\\d)")
        val CLOCK_FMT: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm", Locale.ENGLISH)
        val DATE_FMT: DateTimeFormatter = DateTimeFormatter.ofPattern("EEEE, d MMMM yyyy", Locale.ENGLISH)
        val GROUNDING_FMT: DateTimeFormatter =
            DateTimeFormatter.ofPattern("EEE HH:mm, d MMM yyyy", Locale.ENGLISH)

        // Filler words that shouldn't be tried as place names — also pruned from the start/end of
        // multi-word candidates so "in tokyo" or "to call new york" don't waste a lookup before the
        // bare "tokyo" / "new york" n-gram resolves. Kept tight so real places still get through.
        val STOPWORDS = setOf(
            "the", "what", "whats", "what's", "is", "are", "was", "time", "times", "now", "right",
            "current", "currently", "today", "tonight", "tomorrow", "yesterday", "for", "and", "with",
            "between", "vs", "versus", "from", "into", "convert", "schedule", "plan", "add", "set",
            "meeting", "meet", "call", "best", "when", "whens", "when's", "tell", "give", "show", "get",
            "please", "local", "zone", "clock", "date", "day", "you", "your", "can", "could", "would",
            "about", "here", "there", "this", "that", "over", "city", "country",
            // Short prepositions/articles/pronouns (also caught as unigrams by the length filter, but
            // listed so they're pruned from multi-word phrase edges too).
            "in", "it", "at", "on", "to", "of", "as", "by", "an", "do", "does", "me", "my", "we", "us",
            "or", "if", "so", "am", "pm",
        )
    }
}
