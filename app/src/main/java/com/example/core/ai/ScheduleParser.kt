package com.example.core.ai

import com.example.core.data.PlannedTask
import com.example.core.time.ScheduleTimeParser
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.longOrNull
import java.time.Instant
import java.time.ZoneId

/**
 * Turns the assistant's reply into a concrete scheduling action. Kept free of the Firebase model so
 * it can be tested directly: [GeminiRepository] only calls these after it has the model's text.
 *
 * The model never computes a timestamp (§12.7) — it emits a plain-words `when` and a place, and this
 * resolves the exact instant in-app via [ScheduleTimeParser], with fallbacks so a fumbled `when`
 * still works: the model's `when` → the user's original prompt → any legacy numeric `timestamp`.
 *
 * Hardened against fumbling models: a field that arrives as the wrong JSON type (object/array instead
 * of a primitive) is treated as absent rather than throwing, and extraction tolerates nested objects
 * and `}` characters inside string values.
 */
object ScheduleParser {

    private val json = Json { isLenient = true; ignoreUnknownKeys = true }
    private val ACTION_SCHEDULE = Regex("\"action\"\\s*:\\s*\"schedule\"")

    /**
     * The schedule-action JSON object embedded in [text], or null. Scans brace-balanced objects
     * (respecting string literals), so it works for a clean lone object, one inside ```fences```, one
     * wrapped in prose, several side by side, and objects that contain nested objects or a literal
     * `}` inside a string. Returns the first whose action is "schedule".
     */
    fun extractScheduleJson(text: String): String? {
        var i = 0
        while (i < text.length) {
            if (text[i] == '{') {
                val obj = balancedObjectAt(text, i)
                if (obj != null) {
                    if (ACTION_SCHEDULE.containsMatchIn(obj)) return obj
                    i += obj.length
                    continue
                }
            }
            i++
        }
        return null
    }

    /** The title in a schedule block (for a clarifying reply), or null. */
    fun titleOf(jsonStr: String): String? =
        parse(jsonStr)?.prim("title")?.contentOrNull?.takeIf { it.isNotBlank() }

    /**
     * Builds a [PlannedTask] from a schedule block, computing the instant in-app. [resolveZoneId]
     * maps a place name to an IANA id (the model may send either). Returns null if it isn't a
     * schedule action or no date/time can be resolved at all.
     */
    suspend fun buildScheduledTask(
        jsonStr: String,
        originalPrompt: String,
        now: Instant,
        homeZoneId: String,
        resolveZoneId: suspend (String) -> String?,
    ): PlannedTask? {
        val obj = parse(jsonStr) ?: return null
        if (obj.prim("action")?.contentOrNull != "schedule") return null

        val title = obj.prim("title")?.contentOrNull?.takeIf { it.isNotBlank() } ?: "New event"
        val rawZone = (obj.prim("zoneId") ?: obj.prim("zone"))?.contentOrNull.orEmpty()
        val zone = runCatching { ZoneId.of(resolveScheduleZone(rawZone, homeZoneId, resolveZoneId)) }
            .getOrDefault(ZoneId.systemDefault())

        val whenPhrase = obj.prim("when")?.contentOrNull.orEmpty()
        val legacyTimestamp = obj.prim("timestamp")?.longOrNull?.takeIf { it > 0L }
        val instant = ScheduleTimeParser.parse(whenPhrase, zone, now)
            ?: ScheduleTimeParser.parse(originalPrompt, zone, now)
            ?: legacyTimestamp?.let { Instant.ofEpochMilli(it) }
            ?: return null

        return PlannedTask(title = title, timestamp = instant.toEpochMilli(), zoneId = zone.id)
    }

    /** An IANA id is used as-is; a place name is resolved via [resolveZoneId]; else the home zone. */
    private suspend fun resolveScheduleZone(
        raw: String,
        homeZoneId: String,
        resolveZoneId: suspend (String) -> String?,
    ): String {
        if (raw.isBlank()) return homeZoneId
        runCatching { ZoneId.of(raw) }.getOrNull()?.let { return it.id }
        return resolveZoneId(raw) ?: homeZoneId
    }

    private fun parse(jsonStr: String): JsonObject? =
        runCatching { json.parseToJsonElement(jsonStr).jsonObject }.getOrNull()

    /** Field value as a primitive, or null if absent or a non-primitive (object/array) — never throws. */
    private fun JsonObject.prim(key: String): JsonPrimitive? = this[key] as? JsonPrimitive

    /** The complete `{...}` starting at [start], honoring string literals/escapes; null if unbalanced. */
    private fun balancedObjectAt(s: String, start: Int): String? {
        var depth = 0
        var inString = false
        var escaped = false
        for (i in start until s.length) {
            val c = s[i]
            if (inString) {
                when {
                    escaped -> escaped = false
                    c == '\\' -> escaped = true
                    c == '"' -> inString = false
                }
            } else {
                when (c) {
                    '"' -> inString = true
                    '{' -> depth++
                    '}' -> {
                        depth--
                        if (depth == 0) return s.substring(start, i + 1)
                    }
                }
            }
        }
        return null
    }
}
