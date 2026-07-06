package com.example.core.data

import android.content.Context
import androidx.compose.runtime.Immutable
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.example.core.ai.AiEngine
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * How clocks render the hour, mirroring the plan's locale-aware 12/24h requirement (§15).
 * [SYSTEM] defers to the device locale; [H12]/[H24] are explicit overrides.
 */
enum class HourCycle { SYSTEM, H12, H24 }

/**
 * Render fidelity for the world map / globe (§5.2). Trades realism for frame cost:
 * [REALISTIC] is the full photographic texture plus the shader's atmosphere, night city-lights,
 * sun-glint and rim; [BALANCED] keeps the texture and day/night terminator but drops those
 * per-pixel extras; [PERFORMANCE] drops texture sampling entirely (a smooth two-tone shaded
 * sphere, downsampled flat map) so it stays fluid on low-end and pre-API-33 devices.
 * [VECTOR] is a 2D-only flat outline map drawn from a bundled ~55 KB land TopoJSON (no photo
 * texture at all — tiny memory, crisp at any size, recolorable); the globe falls back to the
 * Balanced shader since vector outlines don't translate to the orthographic sphere.
 */
enum class MapStyle { REALISTIC, BALANCED, PERFORMANCE, VECTOR }

/**
 * Unified frosted-glass opacity for the agenda pill and time scrubbers (10 = transparent, 100 = opaque).
 */
const val MIN_GLASS_OPACITY = 10
const val MAX_GLASS_OPACITY = 100
const val DEFAULT_GLASS_OPACITY_PERCENT = 60

/** @deprecated Legacy enum — migrated to [DEFAULT_GLASS_OPACITY_PERCENT] on read. */
enum class GlassOpacityLevel(val label: String) {
    TRANSPARENT("Transparent"),
    LIGHT("Light"),
    MEDIUM("Medium"),
    OPAQUE("Opaque"),
}

/** Default glass opacity for agenda pills and scrubbers. */
@Deprecated("Use DEFAULT_GLASS_OPACITY_PERCENT", ReplaceWith("DEFAULT_GLASS_OPACITY_PERCENT"))
val DEFAULT_GLASS_OPACITY = GlassOpacityLevel.MEDIUM

/** Default celestial backdrop strength (percent). */
const val DEFAULT_BACKDROP_INTENSITY = 55

/** Allowed range for [MeridianSettings.backdropIntensity]. */
const val MIN_BACKDROP_INTENSITY = 10
const val MAX_BACKDROP_INTENSITY = 100

/**
 * Immutable snapshot of all user preferences. One source of truth, surfaced as a [Flow]
 * from [SettingsRepository] and bound into UI state (§12.3).
 */
@Immutable
data class MeridianSettings(
    val hourCycle: HourCycle = HourCycle.SYSTEM,
    val glassEnabled: Boolean = true,
    val reduceTransparency: Boolean = false,
    val backdropEnabled: Boolean = true,
    /** Celestial glow strength as a percentage (10–100). */
    val backdropIntensity: Int = DEFAULT_BACKDROP_INTENSITY,
    /** Frosted-glass opacity for the agenda pill and time scrubbers (10–100%). */
    val glassOpacity: Int = DEFAULT_GLASS_OPACITY_PERCENT,
    val reminderLeadMinutes: Int = 10,
    val defaultWorkStartHour: Int = 9,
    val defaultWorkEndHour: Int = 17,
    val mapStyle: MapStyle = MapStyle.VECTOR,
    /** When true and a home-country city is set, the Now card shows that third clock. */
    val homeCountryEnabled: Boolean = false,
    /** Set to true after the user completes or skips the first-launch onboarding walkthrough. */
    val onboardingComplete: Boolean = false,
    /** Which inference engine the assistant prefers (on-device first vs always cloud). */
    val aiEngine: AiEngine = AiEngine.ON_DEVICE,
)

private val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(name = "meridian_settings")

/**
 * Persists [MeridianSettings] to DataStore. Offline-first: reads are a cold [Flow] that
 * replays the latest stored value, writes are atomic edits. No Android types escape upward.
 */
class SettingsRepository(private val context: Context) {

    private object Keys {
        val HOUR_CYCLE = stringPreferencesKey("hour_cycle")
        val GLASS_ENABLED = booleanPreferencesKey("glass_enabled")
        val REDUCE_TRANSPARENCY = booleanPreferencesKey("reduce_transparency")
        val BACKDROP_ENABLED = booleanPreferencesKey("backdrop_enabled")
        val BACKDROP_INTENSITY = intPreferencesKey("backdrop_intensity")
        val GLASS_OPACITY = stringPreferencesKey("glass_opacity")
        val GLASS_OPACITY_PERCENT = intPreferencesKey("glass_opacity_percent")
        val SCRUBBER_INTENSITY = intPreferencesKey("scrubber_intensity")
        val REMINDER_LEAD_MINUTES = intPreferencesKey("reminder_lead_minutes")
        val DEFAULT_WORK_START_HOUR = intPreferencesKey("default_work_start_hour")
        val DEFAULT_WORK_END_HOUR = intPreferencesKey("default_work_end_hour")
        val MAP_STYLE = stringPreferencesKey("map_style")
        val HOME_COUNTRY_ENABLED = booleanPreferencesKey("home_country_enabled")
        val ONBOARDING_COMPLETE = booleanPreferencesKey("onboarding_complete")
        val AI_ENGINE = stringPreferencesKey("ai_engine")
    }

    val settings: Flow<MeridianSettings> = context.settingsDataStore.data.map { prefs ->
        MeridianSettings(
            hourCycle = prefs[Keys.HOUR_CYCLE]?.let(::parseHourCycle) ?: HourCycle.SYSTEM,
            glassEnabled = prefs[Keys.GLASS_ENABLED] ?: true,
            reduceTransparency = prefs[Keys.REDUCE_TRANSPARENCY] ?: false,
            backdropEnabled = prefs[Keys.BACKDROP_ENABLED] ?: true,
            backdropIntensity = (prefs[Keys.BACKDROP_INTENSITY] ?: DEFAULT_BACKDROP_INTENSITY)
                .coerceIn(MIN_BACKDROP_INTENSITY, MAX_BACKDROP_INTENSITY),
            glassOpacity = parseGlassOpacity(prefs),
            reminderLeadMinutes = prefs[Keys.REMINDER_LEAD_MINUTES] ?: 10,
            defaultWorkStartHour = prefs[Keys.DEFAULT_WORK_START_HOUR] ?: 9,
            defaultWorkEndHour = prefs[Keys.DEFAULT_WORK_END_HOUR] ?: 17,
            mapStyle = prefs[Keys.MAP_STYLE]?.let(::parseMapStyle) ?: MapStyle.VECTOR,
            homeCountryEnabled = prefs[Keys.HOME_COUNTRY_ENABLED] ?: false,
            onboardingComplete = prefs[Keys.ONBOARDING_COMPLETE] ?: false,
            aiEngine = prefs[Keys.AI_ENGINE]?.let(::parseAiEngine) ?: AiEngine.ON_DEVICE,
        )
    }

    suspend fun setHourCycle(cycle: HourCycle) {
        context.settingsDataStore.edit { it[Keys.HOUR_CYCLE] = cycle.name }
    }

    suspend fun setGlassEnabled(enabled: Boolean) {
        context.settingsDataStore.edit { it[Keys.GLASS_ENABLED] = enabled }
    }

    suspend fun setReduceTransparency(enabled: Boolean) {
        context.settingsDataStore.edit { it[Keys.REDUCE_TRANSPARENCY] = enabled }
    }

    suspend fun setBackdropEnabled(enabled: Boolean) {
        context.settingsDataStore.edit { it[Keys.BACKDROP_ENABLED] = enabled }
    }

    suspend fun setBackdropIntensity(percent: Int) {
        context.settingsDataStore.edit {
            it[Keys.BACKDROP_INTENSITY] = percent.coerceIn(MIN_BACKDROP_INTENSITY, MAX_BACKDROP_INTENSITY)
        }
    }

    suspend fun setGlassOpacity(percent: Int) {
        context.settingsDataStore.edit {
            it[Keys.GLASS_OPACITY_PERCENT] = percent.coerceIn(MIN_GLASS_OPACITY, MAX_GLASS_OPACITY)
            it.remove(Keys.GLASS_OPACITY)
            it.remove(Keys.SCRUBBER_INTENSITY)
        }
    }

    suspend fun setReminderLeadMinutes(minutes: Int) {
        context.settingsDataStore.edit { it[Keys.REMINDER_LEAD_MINUTES] = minutes }
    }

    suspend fun setDefaultWorkStartHour(hour: Int) {
        context.settingsDataStore.edit { it[Keys.DEFAULT_WORK_START_HOUR] = hour }
    }

    suspend fun setDefaultWorkEndHour(hour: Int) {
        context.settingsDataStore.edit { it[Keys.DEFAULT_WORK_END_HOUR] = hour }
    }

    suspend fun setMapStyle(style: MapStyle) {
        context.settingsDataStore.edit { it[Keys.MAP_STYLE] = style.name }
    }

    suspend fun setHomeCountryEnabled(enabled: Boolean) {
        context.settingsDataStore.edit { it[Keys.HOME_COUNTRY_ENABLED] = enabled }
    }

    suspend fun setOnboardingComplete(complete: Boolean) {
        context.settingsDataStore.edit { it[Keys.ONBOARDING_COMPLETE] = complete }
    }

    suspend fun setAiEngine(engine: AiEngine) {
        context.settingsDataStore.edit { it[Keys.AI_ENGINE] = engine.name }
    }

    private fun parseHourCycle(raw: String): HourCycle =
        runCatching { HourCycle.valueOf(raw) }.getOrDefault(HourCycle.SYSTEM)

    private fun parseMapStyle(raw: String): MapStyle =
        runCatching { MapStyle.valueOf(raw) }.getOrDefault(MapStyle.VECTOR)

    private fun parseAiEngine(raw: String): AiEngine =
        runCatching { AiEngine.valueOf(raw) }.getOrDefault(AiEngine.ON_DEVICE)

    private fun parseGlassOpacity(prefs: Preferences): Int {
        prefs[Keys.GLASS_OPACITY_PERCENT]?.let {
            return it.coerceIn(MIN_GLASS_OPACITY, MAX_GLASS_OPACITY)
        }
        prefs[Keys.GLASS_OPACITY]?.let { raw ->
            val level = runCatching { GlassOpacityLevel.valueOf(raw) }.getOrNull()
            if (level != null) return legacyGlassOpacityPercent(level)
        }
        prefs[Keys.SCRUBBER_INTENSITY]?.let {
            return it.coerceIn(MIN_GLASS_OPACITY, MAX_GLASS_OPACITY)
        }
        return DEFAULT_GLASS_OPACITY_PERCENT
    }

    private fun legacyGlassOpacityPercent(level: GlassOpacityLevel): Int = when (level) {
        GlassOpacityLevel.TRANSPARENT -> 10
        GlassOpacityLevel.LIGHT -> 35
        GlassOpacityLevel.MEDIUM -> 60
        GlassOpacityLevel.OPAQUE -> 100
    }
}
