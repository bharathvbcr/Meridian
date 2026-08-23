package com.example

import android.content.Intent
import android.app.AlarmManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.example.core.data.PlannedTask
import com.example.core.notify.BootCompletedReceiver
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlarmManager

/**
 * Reminders must survive a reboot: AlarmManager alarms are volatile, so [BootCompletedReceiver]
 * has to re-arm them from the persisted task list (§5.7). Runs the real receiver → Room →
 * DataStore → AlarmManager path under Robolectric.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class BootReminderTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    private fun upcomingTask(title: String, offsetMs: Long) = PlannedTask(
        title = title,
        timestamp = System.currentTimeMillis() + offsetMs,
        zoneId = "Europe/London",
    )

    @Test
    fun bootReschedulesUpcomingNativeReminders() {
        val container = (context.applicationContext as MeridianApplication).container

        val first = runCatching {
            kotlinx.coroutines.runBlocking { container.taskDao.insertTask(upcomingTask("Boot test", 3_600_000L)) }
        }
        if (first.isFailure) throw AssertionError("seeding task failed", first.exceptionOrNull())

        BootCompletedReceiver().onReceive(context, Intent(Intent.ACTION_BOOT_COMPLETED))

        val alarm = pollScheduledAlarm()
        assertNotNull("boot did not re-arm any alarm within timeout", alarm)
    }

    @Test
    fun packageReplacedAlsoRearmsReminders() {
        val container = (context.applicationContext as MeridianApplication).container
        kotlinx.coroutines.runBlocking { container.taskDao.insertTask(upcomingTask("Update test", 7_200_000L)) }

        BootCompletedReceiver().onReceive(context, Intent(Intent.ACTION_MY_PACKAGE_REPLACED))

        assertNotNull(pollScheduledAlarm())
    }

    @Test
    fun unrelatedBroadcastsDoNotRearm() {
        val receiver = BootCompletedReceiver()
        assertTrue(receiver.isRearmTrigger(Intent.ACTION_BOOT_COMPLETED))
        assertTrue(receiver.isRearmTrigger(Intent.ACTION_MY_PACKAGE_REPLACED))
        for (ignored in listOf(Intent.ACTION_TIME_TICK, Intent.ACTION_VIEW, null)) {
            assertFalse("action $ignored must not re-arm", receiver.isRearmTrigger(ignored))
        }
    }

    @Test
    fun manifestWiringAllowsBootDelivery() {
        val pm = context.packageManager
        // Without this permission the BOOT_COMPLETED broadcast is never delivered to the app.
        val info = pm.getPackageInfo(context.packageName, android.content.pm.PackageManager.GET_PERMISSIONS)
        assertTrue(
            "RECEIVE_BOOT_COMPLETED must be declared",
            info.requestedPermissions.orEmpty().contains(android.Manifest.permission.RECEIVE_BOOT_COMPLETED),
        )
        // Both triggers must resolve to our receiver so updates also re-arm alarms.
        for (action in listOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)) {
            val receivers = pm.queryBroadcastReceivers(Intent(action).setPackage(context.packageName), 0)
            assertTrue("no receiver resolves $action", receivers != null && receivers.isNotEmpty())
        }
    }

    /** The receiver schedules asynchronously (goAsync); poll the shadow until the alarm lands. */
    private fun pollScheduledAlarm(): ShadowAlarmManager.ScheduledAlarm? {
        val am = shadowOf(context.getSystemService(AlarmManager::class.java))
        val deadline = System.currentTimeMillis() + 5_000
        while (System.currentTimeMillis() < deadline) {
            am.nextScheduledAlarm?.let { return it }
            Thread.sleep(50)
        }
        return null
    }
}
