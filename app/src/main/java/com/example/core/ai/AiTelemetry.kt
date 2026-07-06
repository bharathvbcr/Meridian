package com.example.core.ai

import android.util.Log

/**
 * Privacy-safe debug telemetry for on-device AI paths. Logs inference route + latency only —
 * never prompt or response text.
 */
object AiTelemetry {
    private const val TAG = "MeridianAI"

    fun logInference(path: String, provenance: AiProvenance, latencyMs: Long) {
        Log.d(TAG, "path=$path provenance=$provenance latencyMs=$latencyMs")
    }
}
