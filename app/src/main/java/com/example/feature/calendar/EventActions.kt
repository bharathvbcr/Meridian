package com.example.feature.calendar

import android.content.Context
import android.content.Intent
import android.provider.CalendarContract
import androidx.core.content.FileProvider
import com.example.core.time.IcsGenerator
import java.io.File
import java.time.Instant

/** Default length for a scheduled meeting that carries no explicit duration (matches IcsGenerator). */
const val DEFAULT_EVENT_DURATION_MINUTES = 60

/**
 * Outcome of an event action so callers can surface success/failure explicitly (§12.6),
 * e.g. when no calendar app or share target is installed.
 */
sealed interface EventActionResult {
    data object Success : EventActionResult
    data class Failure(val reason: String) : EventActionResult
}

/**
 * Opens the system event editor pre-filled with a zone-aware event (§5.6). Uses the
 * zero-permission [Intent.ACTION_INSERT] path and stamps [CalendarContract.Events.EVENT_TIMEZONE]
 * so the event lands at the correct wall-clock time for the chosen IANA zone.
 */
fun insertCalendarEvent(
    context: Context,
    title: String,
    startInstant: Instant,
    durationMinutes: Int,
    zoneId: String,
): EventActionResult {
    val endInstant = startInstant.plusSeconds(durationMinutes * 60L)
    val intent = Intent(Intent.ACTION_INSERT).apply {
        data = CalendarContract.Events.CONTENT_URI
        putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startInstant.toEpochMilli())
        putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endInstant.toEpochMilli())
        putExtra(CalendarContract.Events.TITLE, title)
        putExtra(CalendarContract.Events.EVENT_TIMEZONE, zoneId)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    return runCatching {
        context.startActivity(intent)
        EventActionResult.Success
    }.getOrElse { EventActionResult.Failure("No calendar app available to add the event.") }
}

/**
 * Generates an RFC-5545 invite with a zone-aware DTSTART;TZID and shares it via
 * [Intent.ACTION_SEND] using a [FileProvider] URI (§5.6).
 */
fun shareEventIcs(
    context: Context,
    title: String,
    startInstant: Instant,
    durationMinutes: Int,
    zoneId: String,
): EventActionResult = runCatching {
    val ics = IcsGenerator.generateEventIcs(
        title = title,
        startInstant = startInstant,
        durationMinutes = durationMinutes,
        zoneId = zoneId,
    )
    val dir = File(context.cacheDir, "invites").apply { mkdirs() }
    val file = File(dir, "meridian-invite-${startInstant.toEpochMilli()}.ics")
    file.writeText(ics)

    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/calendar"
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_SUBJECT, title)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(
        Intent.createChooser(intent, "Share invite").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    )
    EventActionResult.Success
}.getOrElse { EventActionResult.Failure("Couldn't create the invite file to share.") }
