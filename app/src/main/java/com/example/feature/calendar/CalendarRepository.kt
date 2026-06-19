package com.example.feature.calendar

import android.content.Context
import android.provider.CalendarContract

data class CalendarEvent(
    val id: Long,
    val title: String,
    val startMillis: Long,
    val endMillis: Long,
    val timeZone: String,
    val isAllDay: Boolean,
)

object CalendarRepository {
    fun readEvents(context: Context, fromMillis: Long, toMillis: Long): List<CalendarEvent> =
        runCatching {
            val projection = arrayOf(
                CalendarContract.Events._ID,
                CalendarContract.Events.TITLE,
                CalendarContract.Events.DTSTART,
                CalendarContract.Events.DTEND,
                CalendarContract.Events.EVENT_TIMEZONE,
                CalendarContract.Events.ALL_DAY,
            )
            val selection = "${CalendarContract.Events.DTSTART} >= ? AND " +
                "${CalendarContract.Events.DTSTART} < ? AND " +
                "${CalendarContract.Events.DELETED} = 0"
            val selectionArgs = arrayOf(fromMillis.toString(), toMillis.toString())

            context.contentResolver.query(
                CalendarContract.Events.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                "${CalendarContract.Events.DTSTART} ASC",
            )?.use { cursor ->
                buildList {
                    while (cursor.moveToNext()) {
                        add(
                            CalendarEvent(
                                id = cursor.getLong(0),
                                title = cursor.getString(1) ?: "(No title)",
                                startMillis = cursor.getLong(2),
                                endMillis = cursor.getLong(3),
                                timeZone = cursor.getString(4) ?: "UTC",
                                isAllDay = cursor.getInt(5) == 1,
                            )
                        )
                    }
                }
            } ?: emptyList()
        }.getOrElse { emptyList() }
}
