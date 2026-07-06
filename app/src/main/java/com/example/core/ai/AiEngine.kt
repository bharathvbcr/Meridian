package com.example.core.ai

/** User preference for where assistant inference runs — mirrors iOS `AiEngine`. */
enum class AiEngine {
    /** Prefer on-device Gemini Nano; transparent cloud fallback when unavailable. */
    ON_DEVICE,
    /** Always use cloud Gemini (requires network). */
    CLOUD,
}
