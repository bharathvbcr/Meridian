package com.example

import com.example.core.time.OffsetZones
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

class OffsetZonesTest {

    private fun parseOne(query: String) = OffsetZones.parse(query).singleOrNull()

    @Test
    fun bareUtcGmtZuluResolveToUtc() {
        for (q in listOf("utc", "UTC", "gmt", "GMT", "z", "Z", "zulu")) {
            assertEquals("$q -> UTC", "UTC", parseOne(q)?.zoneId)
        }
    }

    @Test
    fun parsesSignedOffsets() {
        assertEquals("+05:00", parseOne("utc+5")?.zoneId)
        assertEquals("-08:00", parseOne("gmt-8")?.zoneId)
        assertEquals("+05:30", parseOne("utc+5:30")?.zoneId)
        assertEquals("+05:30", parseOne("+05:30")?.zoneId)
        assertEquals("-09:30", parseOne("-0930")?.zoneId)
        assertEquals("+05:30", parseOne("utc+0530")?.zoneId)
    }

    @Test
    fun displayNameIsUtcPrefixed() {
        assertEquals("UTC+05:30", parseOne("utc+5:30")?.displayName)
        assertEquals("UTC-08:00", parseOne("gmt-8")?.displayName)
        assertEquals("UTC", parseOne("utc")?.displayName)
    }

    @Test
    fun zeroOffsetCollapsesToUtc() {
        assertEquals("UTC", parseOne("utc+0")?.zoneId)
        assertEquals("UTC", parseOne("+0")?.zoneId)
        assertEquals("UTC", parseOne("gmt-0:00")?.zoneId)
    }

    @Test
    fun honoursTheEighteenHourCap() {
        assertEquals("+14:00", parseOne("utc+14")?.zoneId) // real max (Kiribati)
        assertTrue(OffsetZones.parse("utc+25").isEmpty())
        assertTrue(OffsetZones.parse("+5:99").isEmpty())   // invalid minutes
    }

    @Test
    fun plainTextAndBareNumbersAreNotOffsets() {
        // An offset must be anchored by utc/gmt or an explicit sign.
        for (q in listOf("", "   ", "5", "12", "london", "san", "paris", "utc+", "z+5", "gmt+5:3")) {
            assertTrue("'$q' should not parse as an offset", OffsetZones.parse(q).isEmpty())
        }
    }

    @Test
    fun everyProducedZoneIdIsConstructible() {
        // The UI calls ZoneId.of(result.id) to render the time, so ids must always be valid.
        for (q in listOf("utc", "utc+5", "gmt-8", "utc+5:30", "-0930", "+14:00", "utc-12")) {
            val id = parseOne(q)?.zoneId
            assertTrue("no result for $q", id != null)
            ZoneId.of(id) // throws if invalid
        }
    }
}
