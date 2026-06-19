package com.example

import com.example.core.time.TzAbbreviations
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TzAbbreviationsTest {

    @Test
    fun resolvesCommonAbbreviations() {
        assertEquals("America/New_York", TzAbbreviations.resolve("EST")?.zoneId)
        assertEquals("America/Los_Angeles", TzAbbreviations.resolve("PST")?.zoneId)
        assertEquals("Asia/Kolkata", TzAbbreviations.resolve("IST")?.zoneId)
        assertEquals("Asia/Tokyo", TzAbbreviations.resolve("JST")?.zoneId)
    }

    @Test
    fun resolvesPhraseDisambiguation() {
        assertEquals("Asia/Shanghai", TzAbbreviations.resolve("china cst")?.zoneId)
        assertEquals("America/Chicago", TzAbbreviations.resolve("US CST")?.zoneId)
    }

    @Test
    fun ignoresBareAmbiguousCst() {
        assertNull(TzAbbreviations.resolve("CST"))
    }
}
