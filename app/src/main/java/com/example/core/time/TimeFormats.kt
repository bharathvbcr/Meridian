package com.example.core.time

import com.example.core.data.HourCycle
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Centralized, locale-aware clock formatters so 12/24-hour rendering is consistent across
 * every surface (§5, §15). Pure: callers resolve the system default once and pass a boolean,
 * keeping these factories free of Android types and trivially testable.
 */
object TimeFormats {

    /** Resolves an explicit 24-hour flag from the user's [HourCycle] preference. */
    fun HourCycle.resolveIs24Hour(systemIs24Hour: Boolean): Boolean = when (this) {
        HourCycle.SYSTEM -> systemIs24Hour
        HourCycle.H12 -> false
        HourCycle.H24 -> true
    }

    fun hourMinute(is24Hour: Boolean, locale: Locale = Locale.getDefault()): DateTimeFormatter =
        DateTimeFormatter.ofPattern(if (is24Hour) "HH:mm" else "h:mm a", locale)

    fun hourMinuteSecond(is24Hour: Boolean, locale: Locale = Locale.getDefault()): DateTimeFormatter =
        DateTimeFormatter.ofPattern(if (is24Hour) "HH:mm:ss" else "h:mm:ss a", locale)

    fun hourMinuteWithContext(is24Hour: Boolean, locale: Locale = Locale.getDefault()): DateTimeFormatter =
        DateTimeFormatter.ofPattern(if (is24Hour) "HH:mm (EEE, MMM d)" else "h:mm a (EEE, MMM d)", locale)

    fun mediumDate(locale: Locale = Locale.getDefault()): DateTimeFormatter =
        DateTimeFormatter.ofPattern("EEE, MMM d", locale)
}
