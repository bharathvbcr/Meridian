package com.example

import com.example.core.time.PlaceIndex
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

class PlaceIndexTest {

    private fun firstZoneFor(query: String): String? =
        PlaceIndex.search(query).firstOrNull()?.zoneId

    @Test
    fun resolvesCitiesWhoseNameIsNotInTheIanaId() {
        // The whole point: these words never appear in their IANA id.
        assertEquals("America/Los_Angeles", firstZoneFor("San Francisco"))
        assertEquals("Asia/Kolkata", firstZoneFor("Mumbai"))
        assertEquals("Asia/Shanghai", firstZoneFor("Beijing"))
        assertEquals("Europe/Berlin", firstZoneFor("Munich"))
        assertEquals("America/New_York", firstZoneFor("Boston"))
    }

    @Test
    fun resolvesAlternateSpellingsAndAirportCodes() {
        assertEquals("Asia/Kolkata", firstZoneFor("Bangalore")) // alias of Bengaluru
        assertEquals("America/Los_Angeles", firstZoneFor("SFO"))
        assertEquals("Asia/Dubai", firstZoneFor("DXB"))
        assertEquals("Asia/Kolkata", firstZoneFor("Bombay"))
    }

    @Test
    fun resolvesCountryNames() {
        assertEquals("Asia/Tokyo", firstZoneFor("Japan"))
        assertEquals("Europe/London", firstZoneFor("England"))
    }

    @Test
    fun prefixMatchesOutrankSubstringMatches() {
        // "san" should surface a city starting with "San", not e.g. "Porto-Novo".
        val top = PlaceIndex.search("san").firstOrNull()
        assertNotNull(top)
        assertTrue(top!!.city.lowercase().startsWith("san"))
    }

    @Test
    fun blankQueryReturnsNothing() {
        assertTrue(PlaceIndex.search("   ").isEmpty())
    }

    @Test
    fun respectsLimit() {
        assertTrue(PlaceIndex.search("a", limit = 3).size <= 3)
    }

    @Test
    fun resolveConfidentIgnoresIanaSubstringFalsePositives() {
        // "york" must not match every America/New_York city via the zone id fragment.
        assertEquals(null, PlaceIndex.resolveConfident("york"))
        assertEquals("Europe/London", PlaceIndex.resolveConfident("london")?.zoneId)
        assertEquals("America/New_York", PlaceIndex.resolveConfident("new york")?.zoneId)
    }

    @Test
    fun everyCuratedZoneIdIsAValidIanaZone() {
        val available = ZoneId.getAvailableZoneIds()
        val invalid = PlaceIndex.PLACES.map { it.zoneId }.filter { it !in available }
        assertTrue("Unknown IANA zone ids in PlaceIndex: $invalid", invalid.isEmpty())
    }
}
