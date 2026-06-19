package com.example.core.ai

/**
 * Pre-resolved semantic context injected ahead of the user's message so on-device Gemini Nano
 * can answer without tool calls. [block] is the full text; [intent] drives lean prompt assembly.
 */
data class AiGrounding(
    val block: String,
    val intent: AiQueryIntent,
)

enum class AiQueryIntent {
    CURRENT_TIME,
    CONVERT,
    MEETING,
    SCHEDULE,
    GENERAL,
}
