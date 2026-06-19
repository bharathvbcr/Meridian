package com.example.core.time

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toJavaInstant
import kotlinx.datetime.toKotlinInstant
import java.time.ZoneId
import java.time.ZonedDateTime

class TimeEngine(
    private val clock: Clock
) {
    private val _scrubInstant = MutableStateFlow<java.time.Instant?>(null)
    val scrubInstant: StateFlow<java.time.Instant?> = _scrubInstant.asStateFlow()

    fun updateScrub(instant: java.time.Instant?) {
        _scrubInstant.value = instant
    }

    /**
     * Converts a java.time.Instant to kotlinx.datetime.Instant
     */
    fun javaToKotlinInstant(instant: java.time.Instant): Instant {
        return instant.toKotlinInstant()
    }

    /**
     * Converts a kotlinx.datetime.Instant to java.time.Instant
     */
    fun kotlinToJavaInstant(instant: Instant): java.time.Instant {
        return instant.toJavaInstant()
    }

    /**
     * Obtains the current instant using the injected kotlinx.datetime.Clock
     */
    fun nowKotlin(): Instant {
        return clock.now()
    }

    fun now(): java.time.Instant {
        return clock.now().toJavaInstant()
    }

    /**
     * Safely converts kotlinx-datetime timezone and instant into ZonedDateTime
     * using the injected clock or scrubbed instant without manual offset mathematics.
     */
    fun getScrubbedZonedDateTime(zoneId: ZoneId): ZonedDateTime {
        val currentKotlinInstant = _scrubInstant.value?.toKotlinInstant() ?: clock.now()
        val javaInstant = currentKotlinInstant.toJavaInstant()
        return ZonedDateTime.ofInstant(javaInstant, zoneId)
    }

    /**
     * Additional helper to convert a Kotlin Instant and TimeZone into java.time.ZonedDateTime.
     * Guarantees zero manual offset calculations.
     */
    fun toZonedDateTime(instant: Instant, timeZone: TimeZone): ZonedDateTime {
        return ZonedDateTime.ofInstant(instant.toJavaInstant(), ZoneId.of(timeZone.id))
    }
}
