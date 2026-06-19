package com.example

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import com.example.core.notify.Reminders
import com.example.di.AppContainer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MeridianApplication : Application() {
    lateinit var container: AppContainer

    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        createChannels()
        // Pull any tasks/events shared by ChronosFlow on launch (no-op if it isn't installed).
        appScope.launch { container.interopSyncManager.syncFromPeer() }
        // Live Update scheduling happens from MainActivity (where WorkManager is initialized).
    }

    private fun createChannels() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                Reminders.CHANNEL_ID,
                Reminders.CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply { description = "Reminders for upcoming cross-zone events" }
        )
        manager.createNotificationChannel(
            NotificationChannel(
                Reminders.LIVE_CHANNEL_ID,
                Reminders.LIVE_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Ongoing countdown to your next event" }
        )
    }
}
