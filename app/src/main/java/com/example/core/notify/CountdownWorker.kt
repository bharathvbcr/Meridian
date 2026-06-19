package com.example.core.notify

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.example.MeridianApplication
import com.example.R
import kotlinx.coroutines.flow.first

/**
 * Maintains the ongoing "time until next event" Live Update notification (§5.7). Runs periodically
 * (and on demand) via WorkManager: posts/updates an ongoing progress notification when an event is
 * within [Reminders.LIVE_WINDOW_MILLIS], and clears it otherwise.
 */
class CountdownWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val app = applicationContext as? MeridianApplication ?: return Result.success()
        val manager = NotificationManagerCompat.from(applicationContext)

        val now = System.currentTimeMillis()
        val next = app.container.taskDao.getAllTasks().first()
            .filter { it.timestamp > now }
            .minByOrNull { it.timestamp }

        if (next == null || next.timestamp - now > Reminders.LIVE_WINDOW_MILLIS) {
            manager.cancel(Reminders.LIVE_NOTIFICATION_ID)
            return Result.success()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return Result.success()
        }

        val remaining = next.timestamp - now
        val elapsedFraction = (100 - remaining * 100 / Reminders.LIVE_WINDOW_MILLIS).toInt().coerceIn(0, 100)

        val tapIntent = PendingIntent.getActivity(
            applicationContext,
            0,
            Intent(Intent.ACTION_VIEW, Uri.parse("meridian://plan")).setPackage(applicationContext.packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(applicationContext, Reminders.LIVE_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_meridian_notification)
            .setContentTitle(next.title)
            .setContentText("in ${Reminders.formatCountdown(remaining)}")
            .setProgress(100, elapsedFraction, false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(tapIntent)
            .build()

        manager.notify(Reminders.LIVE_NOTIFICATION_ID, notification)
        return Result.success()
    }
}
