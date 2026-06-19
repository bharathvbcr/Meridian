package com.example.core.time

import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

/** A point on Earth in degrees; longitude is east-positive. */
data class GeoPoint(val latitude: Double, val longitude: Double)

/**
 * Deterministic solar geometry used by the day/night terminator (§5.2) and sun times (§5.9).
 * Pure functions of an [Instant] — no `Instant.now()`, so every value is testable (§12.7).
 * Uses the standard low-precision NOAA approximation (≈ arc-minute accuracy), which is far
 * more than enough for a terminator and sunrise/sunset display.
 */
object SolarMath {

    private const val J2000 = 2451545.0
    private const val DEG = Math.PI / 180.0

    /** The point on Earth where the sun is directly overhead at [instant]. */
    fun subsolarPoint(instant: Instant): GeoPoint {
        val d = julianDay(instant) - J2000
        val g = 357.529 + 0.98560028 * d           // mean anomaly (deg)
        val q = 280.459 + 0.98564736 * d           // mean longitude (deg)
        val l = q + 1.915 * sin(g * DEG) + 0.020 * sin(2 * g * DEG) // ecliptic longitude
        val e = 23.439 - 0.00000036 * d            // obliquity (deg)

        val declination = asin(sin(e * DEG) * sin(l * DEG)) / DEG
        val rightAscension = atan2(cos(e * DEG) * sin(l * DEG), cos(l * DEG)) / DEG

        // Equation of time (minutes) -> subsolar longitude.
        val eqTimeMinutes = 4.0 * normalizeDegrees180(q - rightAscension)
        val utcHours = (instant.toEpochMilli().mod(86_400_000L)) / 3_600_000.0
        val subsolarLongitude = normalizeDegrees180(-15.0 * (utcHours - 12.0 + eqTimeMinutes / 60.0))

        return GeoPoint(declination, subsolarLongitude)
    }

    /**
     * True when the sun is above the horizon at ([latitude], [longitude]) for [instant].
     * Equivalent to the point lying on the sunlit hemisphere centered on the subsolar point.
     */
    fun isDaylight(latitude: Double, longitude: Double, instant: Instant): Boolean =
        cosSolarZenith(latitude, longitude, instant) > 0.0

    /** cos(zenith): > 0 day, = 0 on the terminator, < 0 night. */
    fun cosSolarZenith(latitude: Double, longitude: Double, instant: Instant): Double {
        val sub = subsolarPoint(instant)
        return sin(latitude * DEG) * sin(sub.latitude * DEG) +
            cos(latitude * DEG) * cos(sub.latitude * DEG) * cos((longitude - sub.longitude) * DEG)
    }

    /**
     * Sunrise/sunset wall-clock times for [date] at ([latitude], [longitude]) in [zone].
     * Returns null times for polar day/night where the sun never crosses the horizon.
     */
    fun sunTimes(latitude: Double, longitude: Double, date: LocalDate, zone: ZoneId): SunTimes {
        // Solar noon: when the subsolar longitude crosses this meridian. Approximate the day's
        // declination at local noon, then solve the hour angle for the horizon (zenith 90.833°).
        val noonInstant = date.atTime(LocalTime.NOON).atZone(zone).toInstant()
        val declination = subsolarPoint(noonInstant).latitude

        val zenith = 90.833 * DEG // includes atmospheric refraction + sun radius
        val cosHourAngle = (cos(zenith) - sin(latitude * DEG) * sin(declination * DEG)) /
            (cos(latitude * DEG) * cos(declination * DEG))

        if (cosHourAngle > 1.0) return SunTimes(null, null, polarNight = true)   // sun never rises
        if (cosHourAngle < -1.0) return SunTimes(null, null, polarDay = true)    // sun never sets

        val hourAngle = acos(cosHourAngle) / DEG // degrees
        // Equation of time at noon, in minutes.
        val d = julianDay(noonInstant) - J2000
        val q = 280.459 + 0.98564736 * d
        val gLong = q + 1.915 * sin((357.529 + 0.98560028 * d) * DEG)
        val e = 23.439 - 0.00000036 * d
        val ra = atan2(cos(e * DEG) * sin(gLong * DEG), cos(gLong * DEG)) / DEG
        val eqTimeMinutes = 4.0 * normalizeDegrees180(q - ra)

        // Solar noon in UTC minutes for this longitude, then convert each event to the zone.
        val solarNoonUtcMinutes = 720.0 - 4.0 * longitude - eqTimeMinutes
        val sunriseUtcMinutes = solarNoonUtcMinutes - 4.0 * hourAngle
        val sunsetUtcMinutes = solarNoonUtcMinutes + 4.0 * hourAngle

        return SunTimes(
            sunrise = utcMinutesToLocalTime(date, sunriseUtcMinutes, zone),
            sunset = utcMinutesToLocalTime(date, sunsetUtcMinutes, zone),
        )
    }

    private fun utcMinutesToLocalTime(date: LocalDate, utcMinutes: Double, zone: ZoneId): LocalTime {
        val wrapped = ((utcMinutes % 1440.0) + 1440.0) % 1440.0
        val instant = date.atStartOfDay(ZoneOffset.UTC)
            .plusSeconds((wrapped * 60.0).toLong())
            .toInstant()
        return ZonedDateTime.ofInstant(instant, zone).toLocalTime()
    }

    private fun julianDay(instant: Instant): Double =
        instant.toEpochMilli() / 86_400_000.0 + 2440587.5

    private fun normalizeDegrees180(deg: Double): Double {
        var v = deg % 360.0
        if (v > 180.0) v -= 360.0
        if (v < -180.0) v += 360.0
        return v
    }
}

/** Sunrise/sunset for a date, with explicit polar-day/night flags so the UI never shows a blank. */
data class SunTimes(
    val sunrise: LocalTime?,
    val sunset: LocalTime?,
    val polarDay: Boolean = false,
    val polarNight: Boolean = false,
)
