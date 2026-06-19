package com.example.core.designsystem

import android.text.format.DateFormat
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import com.example.core.data.MeridianSettings
import com.example.core.time.TimeFormats.resolveIs24Hour

/**
 * Resolves the effective 24-hour flag from the user's preference, falling back to the
 * device's locale-driven setting when [MeridianSettings.hourCycle] is SYSTEM (§15).
 * Recomputes if the device configuration (locale / clock setting) changes.
 */
@Composable
fun rememberIs24Hour(settings: MeridianSettings): Boolean {
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    val systemIs24Hour = remember(configuration) { DateFormat.is24HourFormat(context) }
    return settings.hourCycle.resolveIs24Hour(systemIs24Hour)
}
