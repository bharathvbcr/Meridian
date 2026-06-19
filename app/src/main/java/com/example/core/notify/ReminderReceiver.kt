package com.example.core.notify

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.example.R
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

/**
 * Posts the reminder notification when its alarm fires (§5.7). Honors the runtime
 * POST_NOTIFICATIONS permission (Android 13+) and tapping it deep-links into the planner.
 */
class ReminderReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra(Reminders.EXTRA_TITLE) ?: "Upcoming event"
        val zoneId = intent.getStringExtra(Reminders.EXTRA_ZONE) ?: ZoneId.systemDefault().id
        val time = intent.getLongExtra(Reminders.EXTRA_TIME, 0L)
        val id = intent.getIntExtra(Reminders.EXTRA_ID, 0)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return // No permission — nothing to post; the in-app countdown still covers it.
        }

        val tapIntent = PendingIntent.getActivity(
            context,
            id,
            Intent(Intent.ACTION_VIEW, Uri.parse("meridian://plan")).setPackage(context.packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, Reminders.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_meridian_notification)
            .setContentTitle(title)
            .setContentText(buildWhen(time, zoneId))
            .setAutoCancel(true)
            .setContentIntent(tapIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        NotificationManagerCompat.from(context).notify(id, notification)
    }

    private fun buildWhen(epochMillis: Long, zoneId: String): String {
        if (epochMillis <= 0L) return "Starting soon"
        val zone = runCatching { ZoneId.of(zoneId) }.getOrDefault(ZoneId.systemDefault())
        val zdt = ZonedDateTime.ofInstant(Instant.ofEpochMilli(epochMillis), zone)
        return "Starts ${zdt.format(DateTimeFormatter.ofPattern("h:mm a, EEE MMM d"))} (${zone.id})"
    }
}
