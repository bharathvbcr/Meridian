package com.example.core.notify

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.example.core.data.PlannedTask

import com.example.core.data.SettingsRepository
import kotlinx.coroutines.flow.first

/**
 * Schedules and cancels exact alarms for event reminders (§5.7). Degrades gracefully: if the app
 * lacks the exact-alarm permission (Android 13+), it falls back to an inexact alarm rather than
 * throwing. The reminder fires dynamically before the event based on settings, or is skipped if past.
 */
class ReminderScheduler(
    private val context: Context,
    private val settingsRepository: SettingsRepository,
    /**
     * True when ChronosFlow is connected and has taken over reminders. While it returns true,
     * DevTime stays silent for its own tasks so the two apps don't both notify for shared items.
     */
    private val isPeerNotifier: () -> Boolean = { false },
) {

    private val alarmManager = context.getSystemService(AlarmManager::class.java)

    suspend fun schedule(task: PlannedTask) {
        val am = alarmManager ?: return
        // Hand notification duty to ChronosFlow when it's the active notifier.
        if (isPeerNotifier()) {
            cancel(task.id)
            return
        }
        val settings = runCatching { settingsRepository.settings.first() }.getOrNull()
        val leadMinutes = settings?.reminderLeadMinutes ?: 10
        if (leadMinutes < 0) return // negative indicates reminders are disabled
        
        val leadMillis = leadMinutes * 60 * 1000L
        val triggerAt = task.timestamp - leadMillis
        if (triggerAt <= System.currentTimeMillis()) return

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            task.id,
            Intent(context, ReminderReceiver::class.java).apply {
                putExtra(Reminders.EXTRA_TITLE, task.title)
                putExtra(Reminders.EXTRA_ZONE, task.zoneId)
                putExtra(Reminders.EXTRA_TIME, task.timestamp)
                putExtra(Reminders.EXTRA_ID, task.id)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
        try {
            if (canExact) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            } else {
                am.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            }
        } catch (e: SecurityException) {
            am.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        }
    }

    fun cancel(taskId: Int) {
        val am = alarmManager ?: return
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            taskId,
            Intent(context, ReminderReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        if (pendingIntent != null) {
            am.cancel(pendingIntent)
            pendingIntent.cancel()
        }
    }
}
