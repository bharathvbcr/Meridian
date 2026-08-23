package com.example

import com.example.core.time.ScheduleTimeParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * Deterministic date/time resolution for assistant-scheduled meetings (§12.7). The clock is pinned
 * to 2026-06-17T12:00Z, which is a **Wednesday** (13:00 BST in London), so every expectation is exact.
 */
class ScheduleTimeParserTest {

    private val now = Instant.parse("2026-06-17T12:00:00Z")
    private val london = ZoneId.of("Europe/London")     // BST (+01:00) in June
    private val tokyo = ZoneId.of("Asia/Tokyo")          // +09:00, no DST

    /** Expected instant for a wall-clock time in [zone]. */
    private fun at(zone: ZoneId, y: Int, mo: Int, d: Int, h: Int, mi: Int): Instant =
        LocalDateTime.of(y, mo, d, h, mi).atZone(zone).toInstant()

    private fun parse(phrase: String, zone: ZoneId = london) = ScheduleTimeParser.parse(phrase, zone, now)

    @Test
    fun `next weekday with time resolves to the coming occurrence`() {
        // Wed Jun 17 → coming Monday is Jun 22; 2pm = 14:00.
        assertEquals(at(london, 2026, 6, 22, 14, 0), parse("next monday 2pm"))
    }

    @Test
    fun `bare weekday defaults to nine am`() {
        // Wed Jun 17 → coming Friday is Jun 19.
        assertEquals(at(london, 2026, 6, 19, 9, 0), parse("friday"))
    }

    @Test
    fun `malformed explicit time with a date is rejected not defaulted`() {
        // The user asked for a specific (impossible) time — silently booking 09:00 instead would be
        // nine hours off. A date plus an unparseable clock time must fail closed.
        assertNull(parse("tomorrow 25:00"))
        assertNull(parse("tomorrow 14:75"))
        assertNull(parse("2026-06-22T24:00"))
        assertNull(parse("tomorrow 13pm"))
    }

    @Test
    fun `date without any time still defaults to nine am`() {
        assertEquals(at(london, 2026, 6, 22, 9, 0), parse("next monday"))
        assertEquals(at(london, 2026, 6, 18, 9, 0), parse("tomorrow"))
    }

    @Test
    fun `today is included for a bare weekday but skipped for next`() {
        assertEquals(at(london, 2026, 6, 17, 9, 0), parse("wednesday"))      // today
        assertEquals(at(london, 2026, 6, 24, 9, 0), parse("next wednesday")) // +7
    }

    @Test
    fun `tomorrow and day after tomorrow`() {
        assertEquals(at(london, 2026, 6, 18, 9, 0), parse("tomorrow 9am"))
        assertEquals(at(london, 2026, 6, 19, 15, 30), parse("day after tomorrow at 3:30 pm"))
    }

    @Test
    fun `explicit today keeps the date even if the time already passed`() {
        // now is 13:00 BST; "today 11am" stays on Jun 17 because the date is explicit.
        assertEquals(at(london, 2026, 6, 17, 11, 0), parse("today 11am"))
    }

    @Test
    fun `time-only rolls to tomorrow when it already passed today`() {
        // now is 13:00 BST. 3pm is still ahead → today; 11am has passed → tomorrow.
        assertEquals(at(london, 2026, 6, 17, 15, 0), parse("3pm"))
        assertEquals(at(london, 2026, 6, 18, 11, 0), parse("11am"))
    }

    @Test
    fun `iso date and time`() {
        assertEquals(at(london, 2026, 6, 22, 14, 0), parse("2026-06-22 14:00"))
        assertEquals(at(london, 2026, 6, 22, 14, 0), parse("2026-06-22T14:00"))
    }

    @Test
    fun `twenty four hour and am pm forms`() {
        assertEquals(at(london, 2026, 6, 18, 14, 30), parse("tomorrow 14:30"))
        assertEquals(at(london, 2026, 6, 18, 14, 30), parse("tomorrow 2:30 pm"))
        assertEquals(at(london, 2026, 6, 18, 0, 0), parse("tomorrow midnight"))
        assertEquals(at(london, 2026, 6, 18, 12, 0), parse("tomorrow noon"))
    }

    @Test
    fun `noon and midnight twelve-hour edge cases`() {
        assertEquals(at(london, 2026, 6, 18, 12, 0), parse("tomorrow 12pm")) // noon
        assertEquals(at(london, 2026, 6, 18, 0, 0), parse("tomorrow 12am"))  // midnight
    }

    @Test
    fun `relative durations are measured from now`() {
        assertEquals(now.plusSeconds(2 * 3600), parse("in 2 hours"))
        assertEquals(now.plusSeconds(30 * 60), parse("in 30 minutes"))
        assertEquals(now.plusSeconds(7L * 24 * 3600), parse("in a week"))
        assertEquals(now.plusSeconds(24 * 3600), parse("in 1 day"))
    }

    @Test
    fun `month and day, with next-year rollover`() {
        // June 22 hasn't passed → this year.
        assertEquals(at(london, 2026, 6, 22, 9, 0), parse("june 22"))
        assertEquals(at(london, 2026, 6, 22, 16, 0), parse("22 jun at 4pm"))
        // January 5 already passed in 2026 → next year.
        assertEquals(at(london, 2027, 1, 5, 9, 0), parse("jan 5"))
    }

    @Test
    fun `next week resolves seven days out`() {
        assertEquals(at(london, 2026, 6, 24, 9, 0), parse("next week"))
    }

    @Test
    fun `resolution is zone-aware`() {
        // "tomorrow 9am" anchored in Tokyo (now there is 21:00 Jun 17) → Jun 18 09:00 Tokyo.
        assertEquals(at(tokyo, 2026, 6, 18, 9, 0), parse("tomorrow 9am", tokyo))
    }

    @Test
    fun `ignores surrounding words like a place name`() {
        // The model may pass "next monday 2pm london" — the place is ignored, date/time still parse.
        assertEquals(at(london, 2026, 6, 22, 14, 0), parse("next monday 2pm london"))
    }

    @Test
    fun `unparseable phrases return null`() {
        assertNull(parse("sometime soon"))
        assertNull(parse("whenever you like"))
        assertNull(parse(""))
    }

    // ---- brutal edge cases ----------------------------------------------------------------------

    @Test
    fun `odd durations and multi-week`() {
        assertEquals(now.plusSeconds(90 * 60), parse("in 90 minutes"))
        assertEquals(now.plusSeconds(14L * 24 * 3600), parse("in 2 weeks"))
        assertEquals(now.plusSeconds(45 * 60), parse("in 45 mins"))
    }

    @Test
    fun `weekday abbreviations and this-prefix`() {
        assertEquals(at(london, 2026, 6, 19, 9, 0), parse("fri"))        // coming Friday
        assertEquals(at(london, 2026, 6, 19, 14, 0), parse("this friday at 2pm"))
    }

    @Test
    fun `case and surrounding whitespace are ignored`() {
        assertEquals(at(london, 2026, 6, 18, 15, 0), parse("  TOMORROW 3PM  "))
    }

    @Test
    fun `fuzzy times of day`() {
        assertEquals(at(london, 2026, 6, 18, 9, 0), parse("tomorrow morning"))
        assertEquals(at(london, 2026, 6, 18, 18, 0), parse("tomorrow evening"))
    }

    @Test
    fun `twenty-three fifty-nine and explicit minutes`() {
        assertEquals(at(london, 2026, 6, 18, 23, 59), parse("tomorrow 23:59"))
        assertEquals(at(london, 2026, 6, 18, 8, 5), parse("tomorrow 8:05 am"))
    }

    @Test
    fun `month-day end of month rolls to next year when already past`() {
        // Jan 31 already passed in 2026 (today is Jun 17) → 2027.
        assertEquals(at(london, 2027, 1, 31, 9, 0), parse("january 31"))
    }

    @Test
    fun `an impossible calendar date does not resolve`() {
        assertNull(parse("february 30"))
    }

    @Test
    fun `garbage around a valid time still extracts the time`() {
        // 4pm is ahead of 13:00 now → today.
        assertEquals(at(london, 2026, 6, 17, 16, 0), parse("asdf qwerty 4pm zzz"))
    }

    // ---- regression guards for review findings --------------------------------------------------

    @Test
    fun `afternoon is 2pm, not noon`() {
        // "noon" must not match inside "afternoon".
        assertEquals(at(london, 2026, 6, 18, 14, 0), parse("tomorrow afternoon"))
        assertEquals(at(london, 2026, 6, 18, 12, 0), parse("tomorrow at noon"))
    }

    @Test
    fun `a day or week duration honors an explicit time of day`() {
        assertEquals(at(london, 2026, 6, 19, 15, 0), parse("in 2 days at 3pm"))
        // No explicit time → the duration keeps the current wall-clock offset from now.
        assertEquals(now.plusSeconds(2L * 24 * 3600), parse("in 2 days"))
    }

    @Test
    fun `next week with a weekday lands in the following week`() {
        // Wed Jun 17: "next week monday" is Jun 29, not this coming Monday (Jun 22).
        assertEquals(at(london, 2026, 6, 29, 9, 0), parse("next week monday"))
    }

    // ---- worst-case / adversarial ---------------------------------------------------------------

    @Test
    fun `absurd durations fail soft to null, never overflow`() {
        assertNull(parse("in 9999999999 weeks"))                 // would overflow the date range
        assertNull(parse("in 999999999999999999999 days"))       // doesn't even fit in a Long
    }

    @Test
    fun `in zero hours is now`() {
        assertEquals(now, parse("in 0 hours"))
    }

    @Test
    fun `year boundary resolves`() {
        assertEquals(at(london, 2026, 12, 31, 23, 59), parse("december 31 11:59 pm"))
    }

    @Test
    fun `impossible calendar dates resolve to null without throwing`() {
        assertNull(parse("february 29"))   // 2026 isn't a leap year; no silent wrong date
        assertNull(parse("april 31"))
        assertNull(parse("november 0"))
    }

    @Test
    fun `a DST fall-back ambiguous time still resolves to a valid instant`() {
        // 2026-11-01 01:30 occurs twice in America/Chicago (clocks fall back). Must not throw.
        assertNotNull(ScheduleTimeParser.parse("november 1 1:30 am", ZoneId.of("America/Chicago"), now))
    }

    @Test
    fun `a long noisy phrase with a trailing time still extracts it`() {
        val noisy = ("meeting ".repeat(40)) + "at 4pm"
        assertEquals(at(london, 2026, 6, 17, 16, 0), parse(noisy))
    }

    @Test
    fun `whitespace and punctuation only is null`() {
        assertNull(parse("   "))
        assertNull(parse("???!!! ... ,,,"))
    }

    @Test
    fun `a far-but-sane future duration is still allowed`() {
        // ~10 years out (520 weeks) is within the horizon and must resolve.
        assertNotNull(parse("in 520 weeks"))
    }

    @Test
    fun `a past date still resolves (the UI flags past, the parser doesn't reject)`() {
        assertEquals(at(london, 2026, 6, 16, 9, 0), parse("yesterday 9am"))
    }
}
