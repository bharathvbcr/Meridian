package com.example.core.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.example.MeridianApplication
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Re-arms event reminders after a reboot or an app update (§5.7). AlarmManager alarms are volatile:
 * without this receiver, every scheduled reminder silently dies whenever the device restarts and
 * never fires until the user happens to open the app again.
 *
 * Runs the same reconciliation the app uses at launch ([InteropSyncManager.reconcileOwnReminders]),
 * so peer-notifier arbitration and past-task skipping stay in one place. Also handles
 * [Intent.ACTION_MY_PACKAGE_REPLACED], which clears alarms just like a reboot does.
 */
class BootCompletedReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (!isRearmTrigger(intent.action)) return
        val app = context.applicationContext as? MeridianApplication ?: return
        val container = app.container

        val pendingResult = goAsync()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        scope.launch {
            try {
                container.interopSyncManager.reconcileOwnReminders()
            } catch (e: Exception) {
                android.util.Log.w(TAG, "Reminder re-arm after boot failed: ${e.message}")
            } finally {
                // Robolectric and some dispatch paths can hand back a null PendingResult.
                pendingResult?.finish()
            }
        }
    }

    /** Only boot and app-update broadcasts re-arm reminders; anything else is ignored. */
    internal fun isRearmTrigger(action: String?): Boolean =
        action == Intent.ACTION_BOOT_COMPLETED || action == Intent.ACTION_MY_PACKAGE_REPLACED

    private companion object {
        const val TAG = "BootCompletedReceiver"
    }
}
