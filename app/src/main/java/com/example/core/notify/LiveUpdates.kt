package com.example.core.notify

import android.content.Context
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Schedules the [CountdownWorker] that drives the Live Update countdown (§5.7). A 15-minute
 * periodic job keeps it fresh in the background; [refreshNow] updates it immediately after a change.
 */
object LiveUpdates {

    // Calls are wrapped defensively: if WorkManager isn't initialized (e.g. under test), the
    // countdown is simply skipped rather than crashing the caller.
    fun schedulePeriodic(context: Context) {
        runCatching {
            val request = PeriodicWorkRequestBuilder<CountdownWorker>(15, TimeUnit.MINUTES).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                Reminders.LIVE_WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request,
            )
        }
    }

    fun refreshNow(context: Context) {
        runCatching {
            WorkManager.getInstance(context).enqueue(OneTimeWorkRequestBuilder<CountdownWorker>().build())
        }
    }
}
