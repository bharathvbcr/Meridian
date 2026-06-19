package com.example.core.notify

/** Shared constants for the reminder notification + alarm pipeline (§5.7). */
object Reminders {
    const val CHANNEL_ID = "meridian_reminders"
    const val CHANNEL_NAME = "Event reminders"

    const val EXTRA_TITLE = "extra_title"
    const val EXTRA_ZONE = "extra_zone"
    const val EXTRA_TIME = "extra_time"
    const val EXTRA_ID = "extra_id"

    /** How far ahead of the event the reminder fires. */
    const val LEAD_MILLIS = 10 * 60 * 1000L

    // Live Update (ongoing countdown) channel + work (§5.7).
    const val LIVE_CHANNEL_ID = "meridian_live"
    const val LIVE_CHANNEL_NAME = "Event countdown"
    const val LIVE_NOTIFICATION_ID = 424242
    const val LIVE_WORK_NAME = "meridian_countdown"

    /** Window before an event during which the live countdown is shown. */
    const val LIVE_WINDOW_MILLIS = 24 * 60 * 60 * 1000L

    /** Window before an event during which the bottom accessory pill is shown. */
    const val ACCESSORY_WINDOW_MILLIS = 60 * 60 * 1000L

    /** Compact "2d 3h" / "45m" / "<1m" countdown string shared by the accessory and Live Update. */
    fun formatCountdown(millis: Long): String {
        val totalMinutes = (millis / 60_000L).coerceAtLeast(0)
        val days = totalMinutes / (60 * 24)
        val hours = (totalMinutes % (60 * 24)) / 60
        val minutes = totalMinutes % 60
        return when {
            days > 0 -> "${days}d ${hours}h"
            hours > 0 -> "${hours}h ${minutes}m"
            minutes > 0 -> "${minutes}m"
            else -> "<1m"
        }
    }
}
