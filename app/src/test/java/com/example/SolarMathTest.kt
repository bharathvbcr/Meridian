package com.example

import com.example.core.time.SolarMath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

class SolarMathTest {

    @Test
    fun subsolarLatitudeStaysWithinTropics() {
        // Across a year the subsolar latitude never leaves +/- the axial tilt.
        var date = LocalDate.of(2026, 1, 1)
        repeat(365) {
            val instant = date.atStartOfDay(ZoneId.of("UTC")).toInstant()
            val lat = SolarMath.subsolarPoint(instant).latitude
            assertTrue("lat $lat out of tropics on $date", lat in -23.6..23.6)
            date = date.plusDays(1)
        }
    }

    @Test
    fun summerSolsticeSubsolarNearTropicOfCancer() {
        val instant = Instant.parse("2026-06-21T12:00:00Z")
        val sub = SolarMath.subsolarPoint(instant)
        assertEquals(23.4, sub.latitude, 0.4)
        // At 12:00 UTC the sun is roughly over the prime meridian (small EoT offset).
        assertEquals(0.0, sub.longitude, 5.0)
    }

    @Test
    fun londonIsLightAtNoonAndDarkAtMidnight() {
        val noon = Instant.parse("2026-06-21T12:00:00Z")
        val midnight = Instant.parse("2026-06-21T00:00:00Z")
        assertTrue(SolarMath.isDaylight(51.51, -0.13, noon))
        assertFalse(SolarMath.isDaylight(51.51, -0.13, midnight))
    }

    @Test
    fun londonSunriseBeforeSunsetInSummer() {
        val times = SolarMath.sunTimes(51.51, -0.13, LocalDate.of(2026, 6, 21), ZoneId.of("Europe/London"))
        assertNotNull(times.sunrise)
        assertNotNull(times.sunset)
        val sunrise = times.sunrise!!
        val sunset = times.sunset!!
        assertTrue("sunrise $sunrise", sunrise.hour in 3..6)
        assertTrue("sunset $sunset", sunset.hour in 20..22)
        assertTrue(sunrise.isBefore(sunset))
    }

    @Test
    fun polarDayAndNightAreFlagged() {
        val zone = ZoneId.of("UTC")
        val summer = SolarMath.sunTimes(80.0, 20.0, LocalDate.of(2026, 6, 21), zone)
        assertTrue(summer.polarDay)
        assertEquals(null, summer.sunset)

        val winter = SolarMath.sunTimes(80.0, 20.0, LocalDate.of(2026, 12, 21), zone)
        assertTrue(winter.polarNight)
        assertEquals(null, winter.sunrise)
    }
}
