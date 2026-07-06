package com.example.core.ai

import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Deterministic, network-free fallback. Answers directly from the pre-computed grounding block
 * when semantic routing decides the LLM is unnecessary (mirrors iOS `RulesEngine`).
 */
object RulesEngine {

    fun answer(
        prompt: String,
        grounding: AiGrounding,
        zone: ZoneId,
        currentTime: ZonedDateTime,
    ): String {
        if (grounding.intent == AiQueryIntent.SCHEDULE) {
            val title = inferTitle(prompt)
            val whenText = prompt.trim()
            return """{"action":"schedule","title":"${escape(title)}","when":"${escape(whenText)}","zoneId":"${zone.id}"}"""
        }

        if (grounding.block.isNotEmpty()) {
            return when (grounding.intent) {
                AiQueryIntent.CURRENT_TIME -> liveClockSummary(grounding.block)
                AiQueryIntent.CONVERT ->
                    section(grounding.block, "TIME CONVERSIONS") ?: liveClockSummary(grounding.block)
                AiQueryIntent.MEETING ->
                    section(grounding.block, "MEETING SLOTS") ?: liveClockSummary(grounding.block)
                else -> liveClockSummary(grounding.block)
            }
        }

        return """
            I can help with world times, time-zone conversions, meeting windows, and scheduling. \
            Try "What time is it in Tokyo?", "Convert 3 PM New York to London", or \
            "Best meeting time for NYC, London, and Singapore".
        """.trimIndent()
    }

    private fun liveClockSummary(block: String): String {
        val bullets = block.lineSequence()
            .filter { it.startsWith("• ") }
            .map { it.removePrefix("• ") }
            .toList()
        return if (bullets.isEmpty()) block else bullets.joinToString("\n")
    }

    private fun section(block: String, header: String): String? {
        val lines = block.lines()
        val headerIdx = lines.indexOfFirst { it.startsWith(header) }
        if (headerIdx < 0) return null
        val out = mutableListOf<String>()
        for (line in lines.drop(headerIdx + 1)) {
            when {
                line.startsWith("• ") -> out += line.removePrefix("• ")
                out.isNotEmpty() -> break
            }
        }
        return out.takeIf { it.isNotEmpty() }?.joinToString("\n")
    }

    private fun inferTitle(prompt: String): String {
        val trimmed = prompt.trim()
        return trimmed.ifEmpty { "New event" }
    }

    private fun escape(s: String): String = s
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", " ")
}
