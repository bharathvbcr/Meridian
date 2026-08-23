package com.example.core.interop

import android.util.Log
import com.example.core.data.PlannedTask
import com.example.core.data.TaskDao
import com.example.core.notify.ReminderScheduler
import java.util.TimeZone

/**
 * Pulls ChronosFlow's tasks and calendar events and mirrors them into DevTime's planned tasks.
 *
 * Imports are idempotent: each upstream row maps to a stable [PlannedTask.externalId], so repeated
 * syncs update in place rather than duplicating. Rows that vanish upstream are pruned. Imported
 * rows carry [PlannedTask.origin] = ChronosFlow's package, which the provider excludes from sharing,
 * so data never echoes back and forth.
 *
 * Also reconciles DevTime's own task reminders against the peer: when ChronosFlow is connected it
 * becomes the sole notifier, so DevTime cancels its reminders; when ChronosFlow is gone, DevTime
 * (re)schedules them so notifications still fire.
 */
class InteropSyncManager(
    private val client: InteropClient,
    private val taskDao: TaskDao,
    private val reminderScheduler: ReminderScheduler,
    private val systemZoneId: () -> String = { TimeZone.getDefault().id },
) {
    private val origin = InteropContract.CHRONOSFLOW

    suspend fun syncFromPeer() {
        try {
            reconcileOwnReminders()

            // If ChronosFlow isn't installed, do nothing — and deliberately leave any previously
            // imported rows untouched, so a transient uninstall/reinstall doesn't churn the mirror.
            // (When it IS installed but has nothing to share, the prune below removes stale rows.)
            if (!client.isPeerInstalled()) {
                Log.i(TAG, "ChronosFlow not installed — skipping interop sync, keeping existing imports.")
                return
            }

            val tasks = client.fetchPeerTasks()
            val events = client.fetchPeerEvents()

            val keep = mutableListOf<String>()

            for (t in tasks) {
                // DevTime planned tasks need a time; skip undated peer tasks.
                val ts = t.dueAt ?: continue
                val externalId = "task:${t.externalId}"
                upsert(externalId, t.title, ts, t.timezone)
                keep += externalId
            }
            for (e in events) {
                val externalId = "event:${e.externalId}"
                upsert(externalId, e.title, e.startAt, e.timezone)
                keep += externalId
            }

            if (keep.isEmpty()) {
                taskDao.deleteAllImported(origin)
            } else {
                taskDao.deleteImportedNotIn(origin, keep)
            }
            Log.i(TAG, "Interop sync from ChronosFlow: ${keep.size} item(s) mirrored.")
        } catch (e: Exception) {
            Log.w(TAG, "Interop sync failed (continuing standalone): ${e.message}")
        }
    }

    /**
     * Cancels DevTime's own task reminders when ChronosFlow is the active notifier, or (re)schedules
     * them when it isn't — so exactly one app reminds for any given task. Only locally-authored tasks
     * are touched; imported rows are ChronosFlow's responsibility.
     *
     * Public because it is also the boot/update path: AlarmManager alarms do not survive a reboot
     * or app update, so [com.example.core.notify.BootCompletedReceiver] calls this to re-arm them
     * from the persisted task list without needing the peer-sync round trip.
     */
    suspend fun reconcileOwnReminders() {
        val peerNotifier = client.isPeerShareAvailable()
        val nativeTasks = taskDao.getNativeTasksOnce()
        for (task in nativeTasks) {
            if (peerNotifier) {
                reminderScheduler.cancel(task.id)
            } else {
                reminderScheduler.schedule(task)
            }
        }
    }

    private suspend fun upsert(externalId: String, title: String, timestamp: Long, timezone: String?) {
        val zone = timezone?.takeIf { it.isNotBlank() } ?: systemZoneId()
        val existingId = taskDao.getImportedId(origin, externalId) ?: 0
        taskDao.insertTask(
            PlannedTask(
                id = existingId,
                title = title.ifBlank { "(untitled)" },
                timestamp = timestamp,
                zoneId = zone,
                origin = origin,
                externalId = externalId,
            ),
        )
    }

    private companion object {
        const val TAG = "InteropSyncManager"
    }
}
