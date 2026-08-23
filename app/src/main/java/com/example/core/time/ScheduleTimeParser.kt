package com.example.core.time

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.Month
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale

/**
 * Deterministically resolves a natural-language date/time phrase to an [Instant] in a given zone,
 * anchored at "now". This is the app's own time math (§12.7 — the LLM never computes time): the
 * assistant only *extracts* the phrase ("next Monday 2pm", "tomorrow", "2026-06-22 14:00") and this
 * parser turns it into an exact instant, so a weak on-device model can no longer pick the wrong time.
 *
 * Supported, case-insensitive:
 *  - absolute ISO dates `yyyy-MM-dd` (optionally with a time);
 *  - relative days: today/tonight, tomorrow, day after tomorrow, yesterday;
 *  - weekdays with optional `this`/`next` (e.g. "next friday"), and "next week";
 *  - month-day: "June 22", "22 Jun" (year optional; rolls to next year if already past);
 *  - durations from now: "in 30 minutes", "in 2 hours", "in a week";
 *  - times: "2pm", "2:30 pm", 24-hour "14:00", and noon/midnight/morning/afternoon/evening/tonight.
 *
 * Conventions: a bare or "this" weekday is the soonest occurrence *including today*; "next" weekday
 * skips today (so on a Monday, "next Monday" is +7). A date with no time defaults to [DEFAULT_TIME];
 * a time with no date is today if still ahead, otherwise tomorrow. Returns null if nothing parses.
 */
object ScheduleTimeParser {

    val DEFAULT_TIME: LocalTime = LocalTime.of(9, 0)

    /** Relative durations beyond this many years out are treated as unparseable, not scheduled. */
    private const val MAX_FUTURE_YEARS = 200

    fun parse(phrase: String, zone: ZoneId, now: Instant): Instant? {
        val text = phrase.lowercase(Locale.ROOT).trim()
        if (text.isEmpty()) return null
        val nowZdt = ZonedDateTime.ofInstant(now, zone)
        val time = parseTimeOfDay(text)

        // "in N <unit>" sets a full instant; for day/week units an explicit time-of-day still applies
        // ("in 2 days at 3pm" → that date at 15:00, not at the current wall-clock time).
        parseRelativeDuration(text, nowZdt, time)?.let { return it.toInstant() }

        val date = parseDate(text, nowZdt.toLocalDate())

        // A date plus an *explicit but impossible* clock time ("tomorrow 25:00", "…T24:00",
        // "13pm") is a user mistake, not an absent time: fail closed instead of silently booking
        // the 09:00 default nine hours away from what was asked.
        if (date != null && time == null && hasMalformedExplicitTime(text)) return null

        val local = when {
            date != null && time != null -> date.atTime(time)
            date != null -> date.atTime(DEFAULT_TIME)
            time != null -> {
                val todayAt = nowZdt.toLocalDate().atTime(time)
                if (todayAt.atZone(zone).toInstant().isAfter(now)) todayAt else todayAt.plusDays(1)
            }
            else -> return null
        }
        return local.atZone(zone).toInstant()
    }

    private fun parseRelativeDuration(text: String, nowZdt: ZonedDateTime, time: LocalTime?): ZonedDateTime? {
        val m = RELATIVE_DURATION.find(text) ?: return null
        val n = m.groupValues[1].let { if (it == "a" || it == "an") 1L else it.toLongOrNull() ?: return null }
        val unit = m.groupValues[2]
        // Absurd counts ("in 9999999999 weeks") overflow or land hundreds of millions of years out —
        // treat anything past a sane horizon (or that throws) as unparseable rather than scheduling it.
        return runCatching {
            val result: ZonedDateTime = when {
                // Minutes/hours are absolute offsets from now; a stray time-of-day doesn't apply.
                unit.startsWith("min") -> nowZdt.plusMinutes(n)
                unit.startsWith("h") -> nowZdt.plusHours(n)
                // Day/week offsets land on a date — honor an explicit time if the phrase had one.
                unit.startsWith("day") -> nowZdt.plusDays(n).applyTime(time)
                unit.startsWith("w") -> nowZdt.plusWeeks(n).applyTime(time)
                else -> return@runCatching null
            }
            if (result.year > nowZdt.year + MAX_FUTURE_YEARS) null else result
        }.getOrNull()
    }

    private fun ZonedDateTime.applyTime(time: LocalTime?): ZonedDateTime =
        if (time == null) this else toLocalDate().atTime(time).atZone(zone)

    /**
     * True when the phrase contains an explicit numeric clock candidate that failed validation —
     * hours/minutes out of range in either 24-hour or am/pm form. Distinguishes "no time given"
     * from "given but unparseable" so callers can reject instead of defaulting.
     */
    private fun hasMalformedExplicitTime(text: String): Boolean {
        ATTACHED_CLOCK_TIME.containsMatchIn(text) && return true
        ATTACHED_AM_PM_TIME.containsMatchIn(text) && return true
        AM_PM_TIME.find(text)?.let { m ->
            val h = m.groupValues[1].toInt()
            val min = m.groupValues[2].toIntOrNull() ?: 0
            if (h !in 1..12 || min !in 0..59) return true
        }
        TWENTY_FOUR_HOUR.find(text)?.let { m ->
            val h = m.groupValues[1].toInt()
            val min = m.groupValues[2].toInt()
            if (h !in 0..23 || min !in 0..59) return true
        }
        return false
    }

    private fun parseTimeOfDay(text: String): LocalTime? {        AM_PM_TIME.find(text)?.let { m ->
            var h = m.groupValues[1].toInt()
            val min = m.groupValues[2].toIntOrNull() ?: 0
            val pm = m.groupValues[3].replace(".", "") == "pm"
            if (h in 1..12 && min in 0..59) {
                if (h == 12) h = 0
                if (pm) h += 12
                return LocalTime.of(h, min)
            }
        }
        TWENTY_FOUR_HOUR.find(text)?.let { m ->
            val h = m.groupValues[1].toInt()
            val min = m.groupValues[2].toInt()
            if (h in 0..23 && min in 0..59) return LocalTime.of(h, min)
        }
        return when {
            "midnight" in text -> LocalTime.MIDNIGHT
            // Word-boundary match: "noon" must not fire on the "noon" inside "afternoon".
            NOON.containsMatchIn(text) -> LocalTime.NOON
            "afternoon" in text -> LocalTime.of(14, 0)
            "morning" in text -> LocalTime.of(9, 0)
            "evening" in text -> LocalTime.of(18, 0)
            "tonight" in text || "night" in text -> LocalTime.of(20, 0)
            else -> null
        }
    }

    private fun parseDate(text: String, today: LocalDate): LocalDate? {
        ISO_DATE.find(text)?.let { m ->
            runCatching {
                LocalDate.of(m.groupValues[1].toInt(), m.groupValues[2].toInt(), m.groupValues[3].toInt())
            }.getOrNull()?.let { return it }
        }
        when {
            "day after tomorrow" in text -> return today.plusDays(2)
            "tomorrow" in text -> return today.plusDays(1)
            "today" in text || "tonight" in text -> return today
            "yesterday" in text -> return today.minusDays(1)
        }
        // "next week [monday]" anchors the weekday search a week ahead (so it isn't this week's).
        val nextWeek = NEXT_WEEK.containsMatchIn(text)
        val anchor = if (nextWeek) today.plusWeeks(1) else today
        parseWeekday(text, anchor)?.let { return it }
        if (nextWeek) return anchor
        parseMonthDay(text, today)?.let { return it }
        return null
    }

    private fun parseWeekday(text: String, anchor: LocalDate): LocalDate? {
        for ((name, dow) in WEEKDAYS) {
            if (!Regex("\\b$name\\b").containsMatchIn(text)) continue
            val isNext = Regex("\\bnext\\s+$name\\b").containsMatchIn(text)
            var days = ((dow.value - anchor.dayOfWeek.value) % 7 + 7) % 7
            if (isNext && days == 0) days = 7
            return anchor.plusDays(days.toLong())
        }
        return null
    }

    private fun parseMonthDay(text: String, today: LocalDate): LocalDate? {
        for ((name, month) in MONTHS) {
            val after = Regex("\\b$name\\b\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{4}))?\\b").find(text)
            val before = Regex("\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+$name\\b(?:,?\\s+(\\d{4}))?").find(text)
            val match = after ?: before ?: continue
            val day = match.groupValues[1].toIntOrNull() ?: continue
            val year = match.groupValues[2].toIntOrNull()
            var date = runCatching { LocalDate.of(year ?: today.year, month.value, day) }.getOrNull() ?: continue
            // No explicit year and the date already passed this year → the user means next year.
            if (year == null && date.isBefore(today)) date = date.plusYears(1)
            return date
        }
        return null
    }

    private val WEEKDAYS: List<Pair<String, DayOfWeek>> = listOf(
        "monday" to DayOfWeek.MONDAY, "tuesday" to DayOfWeek.TUESDAY, "wednesday" to DayOfWeek.WEDNESDAY,
        "thursday" to DayOfWeek.THURSDAY, "friday" to DayOfWeek.FRIDAY, "saturday" to DayOfWeek.SATURDAY,
        "sunday" to DayOfWeek.SUNDAY,
        "mon" to DayOfWeek.MONDAY, "tue" to DayOfWeek.TUESDAY, "wed" to DayOfWeek.WEDNESDAY,
        "thu" to DayOfWeek.THURSDAY, "fri" to DayOfWeek.FRIDAY, "sat" to DayOfWeek.SATURDAY,
        "sun" to DayOfWeek.SUNDAY,
    )

    private val MONTHS: List<Pair<String, Month>> = listOf(
        "january" to Month.JANUARY, "february" to Month.FEBRUARY, "march" to Month.MARCH,
        "april" to Month.APRIL, "may" to Month.MAY, "june" to Month.JUNE, "july" to Month.JULY,
        "august" to Month.AUGUST, "september" to Month.SEPTEMBER, "october" to Month.OCTOBER,
        "november" to Month.NOVEMBER, "december" to Month.DECEMBER,
        "jan" to Month.JANUARY, "feb" to Month.FEBRUARY, "mar" to Month.MARCH, "apr" to Month.APRIL,
        "jun" to Month.JUNE, "jul" to Month.JULY, "aug" to Month.AUGUST, "sep" to Month.SEPTEMBER,
        "sept" to Month.SEPTEMBER, "oct" to Month.OCTOBER, "nov" to Month.NOVEMBER, "dec" to Month.DECEMBER,
    )

    private val RELATIVE_DURATION =
        Regex("\\bin\\s+(\\d+|an?)\\s+(minutes?|mins?|hours?|hrs?|days?|weeks?)\\b")
    // Sign characters are excluded from both lookbehinds so "-1:30"/"-3pm" are never read as
    // plain "1:30"/"3pm" — a negative clock time is a user mistake, not a valid time of day.
    private val AM_PM_TIME = Regex("(?<![\\d+\\-])(\\d{1,2})(?::(\\d{2}))?\\s*(a\\.?m\\.?|p\\.?m\\.?)(?![a-z])")
    // Digit lookarounds (not \b) so an ISO "…-22T14:00" still yields the date and the 14:00 time —
    // a letter like 'T' next to a digit is not a word boundary.
    private val TWENTY_FOUR_HOUR = Regex("(?<![\\d:+\\-])(\\d{1,2}):(\\d{2})(?!\\d)")
    private val ATTACHED_CLOCK_TIME = Regex("(?<=[+\\-/])\\s*(\\d{1,2}):(\\d{2})(?!\\d)")
    private val ATTACHED_AM_PM_TIME = Regex("(?<=[+\\-/])\\s*(\\d{1,2})\\s*(?:a\\.?m\\.?|p\\.?m\\.?)")
    private val ISO_DATE = Regex("(?<!\\d)(\\d{4})-(\\d{1,2})-(\\d{1,2})(?!\\d)")
    private val NEXT_WEEK = Regex("\\bnext\\s+week\\b")
    private val NOON = Regex("\\b(noon|midday)\\b")
}
