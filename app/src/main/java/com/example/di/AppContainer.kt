package com.example.di

import android.content.Context
import com.example.core.data.AppDatabase
import com.example.core.data.SettingsRepository
import com.example.core.interop.InteropClient
import com.example.core.interop.InteropSyncManager
import com.example.core.location.LocationZoneResolver
import com.example.core.notify.ReminderScheduler
import com.example.core.notify.WearSyncManager
import com.example.core.time.FindOverlapUseCase
import com.example.core.time.GeoPlaceRepository
import com.example.core.time.TimeEngine
import kotlinx.datetime.Clock

class AppContainer(context: Context) {
    val database = AppDatabase.getDatabase(context)
    val zoneDao = database.zoneDao()
    val taskDao = database.taskDao()
    val personDao = database.personDao()
    val settingsRepository = SettingsRepository(context.applicationContext)

    // Cross-app sharing: pulls tasks/events from ChronosFlow into DevTime's planned tasks.
    val interopClient = InteropClient(context.applicationContext)

    // When ChronosFlow is connected it becomes the sole notifier, so DevTime suppresses its own
    // reminders (the lambda is re-evaluated on each schedule/reconcile, not cached).
    val reminderScheduler = ReminderScheduler(
        context.applicationContext,
        settingsRepository,
        isPeerNotifier = { interopClient.isPeerShareAvailable() },
    )
    val locationZoneResolver = LocationZoneResolver(context.applicationContext)
    val wearSyncManager = WearSyncManager(context.applicationContext)
    // Comprehensive offline city/airport -> zone lookup (assets/cities.db) for location search.
    val geoPlaceRepository = GeoPlaceRepository(context.applicationContext)

    val interopSyncManager = InteropSyncManager(interopClient, taskDao, reminderScheduler)

    val clock: Clock = Clock.System
    val timeEngine = TimeEngine(clock)
    val findOverlapUseCase = FindOverlapUseCase(timeEngine)
}
