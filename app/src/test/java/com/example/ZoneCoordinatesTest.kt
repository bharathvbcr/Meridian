package com.example

import com.example.core.time.ZoneCoordinates
import org.junit.Assert.assertEquals
import org.junit.Test

class ZoneCoordinatesTest {

    @Test
    fun nearestKnownZoneResolvesMajorCities() {
        // Coordinates a little off each city still resolve to that city's zone.
        assertEquals("Europe/London", ZoneCoordinates.nearestKnownZone(51.6, -0.2))
        assertEquals("Asia/Tokyo", ZoneCoordinates.nearestKnownZone(35.7, 139.8))
        assertEquals("America/New_York", ZoneCoordinates.nearestKnownZone(40.6, -73.9))
        assertEquals("Australia/Sydney", ZoneCoordinates.nearestKnownZone(-33.9, 151.0))
        assertEquals("Asia/Kolkata", ZoneCoordinates.nearestKnownZone(22.6, 88.4))
    }

    @Test
    fun offsetFallbackUsedForUnknownZone() {
        // An unknown zone falls back to its standard meridian at the equator.
        val point = ZoneCoordinates.coordinateFor("Etc/GMT-5", java.time.Instant.parse("2026-06-16T00:00:00Z"))
        assertEquals(0.0, point.latitude, 0.0001)
        // Etc/GMT-5 is UTC+5 -> 75 degrees east.
        assertEquals(75.0, point.longitude, 0.001)
    }
}
