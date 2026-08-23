package com.example.core.ai

import android.content.Context
import android.os.Build
import android.os.PowerManager

/**
 * Tiered AI degradation under power-save, thermal stress, or low battery.
 * When degraded: prefer RULES-only routing, skip LLM, disable prewarm.
 */
class AiResourcePolicy(context: Context) {

    enum class Tier { NORMAL, DEGRADED, CRITICAL }

    // getSystemService returns a platform type; some profiles/emulators can hand back null, so
    // degrade to NORMAL-tier instead of crashing on a missing power manager.
    private val powerManager: PowerManager? = context.getSystemService(PowerManager::class.java)

    fun currentTier(): Tier {
        val pm = powerManager ?: return Tier.NORMAL
        if (pm.isPowerSaveMode) return Tier.DEGRADED
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            when (pm.currentThermalStatus) {
                PowerManager.THERMAL_STATUS_SEVERE,
                PowerManager.THERMAL_STATUS_CRITICAL,
                PowerManager.THERMAL_STATUS_EMERGENCY,
                PowerManager.THERMAL_STATUS_SHUTDOWN -> return Tier.CRITICAL
                PowerManager.THERMAL_STATUS_MODERATE -> return Tier.DEGRADED
            }
        }
        return Tier.NORMAL
    }

    fun preferRulesOnly(): Boolean = currentTier() != Tier.NORMAL

    fun skipLlm(): Boolean = currentTier() == Tier.CRITICAL

    fun skipPrewarm(): Boolean = currentTier() != Tier.NORMAL
}
