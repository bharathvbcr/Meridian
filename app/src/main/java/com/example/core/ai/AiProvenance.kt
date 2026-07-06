package com.example.core.ai

/** Where an assistant reply was actually computed — drives the provenance badge in chat. */
enum class AiProvenance {
    /** Gemini Nano on-device inference. */
    ON_DEVICE,
    /** Gemini cloud fallback. */
    CLOUD,
    /** Deterministic rules engine — offline, no model. */
    RULES,
    /** Semantic cache hit — prior answer reused (<15 ms). */
    CACHED,
}
