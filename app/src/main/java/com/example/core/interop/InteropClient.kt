package com.example.core.interop

import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.util.Log

/**
 * Reads ChronosFlow's [InteropProvider]. Every call degrades to an empty list when ChronosFlow
 * isn't installed, hasn't granted us access, or otherwise fails — DevTime always works standalone.
 */
class InteropClient(private val context: Context) {

    /**
     * True if ChronosFlow is installed on this device (and visible to us via the manifest
     * `<queries>` entry). Use this to gate any "shared with ChronosFlow" UI — when it's false the
     * app simply runs solo. Cheap enough to call on demand.
     */
    fun isPeerInstalled(): Boolean = try {
        context.packageManager.getPackageInfo(InteropContract.CHRONOSFLOW, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    /**
     * True if ChronosFlow is installed AND exposes a trusted interop provider we're allowed to read
     * (installed + correct authority owner + pinned signing cert). This is the precondition every
     * fetch already checks internally; expose it so callers/UI can branch without issuing a query.
     */
    fun isPeerShareAvailable(): Boolean = isPeerInstalled() && peerProviderTrusted()

    data class RemoteTask(
        val externalId: String,
        val title: String,
        val dueAt: Long?,
        val timezone: String?,
    )

    data class RemoteEvent(
        val externalId: String,
        val title: String,
        val startAt: Long,
        val endAt: Long,
        val timezone: String?,
        val isAllDay: Boolean,
    )

    fun fetchPeerTasks(): List<RemoteTask> = query(InteropContract.PATH_TASKS) { c ->
        RemoteTask(
            externalId = c.string("external_id") ?: return@query null,
            title = c.string("title").orEmpty(),
            dueAt = c.longOrNull("due_at"),
            timezone = c.string("timezone"),
        )
    }

    fun fetchPeerEvents(): List<RemoteEvent> = query(InteropContract.PATH_EVENTS) { c ->
        RemoteEvent(
            externalId = c.string("external_id") ?: return@query null,
            title = c.string("title").orEmpty(),
            startAt = c.longOrNull("start_at") ?: return@query null,
            endAt = c.longOrNull("end_at") ?: 0L,
            timezone = c.string("timezone"),
            isAllDay = (c.longOrNull("is_all_day") ?: 0L) != 0L,
        )
    }

    private fun <T> query(path: String, map: (Cursor) -> T?): List<T> {
        if (!peerProviderTrusted()) return emptyList()
        return try {
            context.contentResolver.query(InteropContract.peerUri(path), null, null, null, null)
                ?.use { c ->
                    buildList {
                        while (c.moveToNext()) map(c)?.let(::add)
                    }
                } ?: emptyList()
        } catch (e: SecurityException) {
            Log.w(TAG, "Interop: peer denied access to /$path: ${e.message}")
            emptyList()
        } catch (e: Exception) {
            // Peer not installed / provider missing / transient failure — stay standalone.
            Log.d(TAG, "Interop: /$path unavailable: ${e.message}")
            emptyList()
        }
    }

    /**
     * Confirms the app that actually owns ChronosFlow's authority is the real, pinned ChronosFlow
     * before we query it — so an app squatting `com.chronosflow.share` can't feed us forged data.
     */
    private fun peerProviderTrusted(): Boolean {
        val info = try {
            context.packageManager.resolveContentProvider(InteropContract.PEER_AUTHORITY, 0)
        } catch (e: Exception) {
            null
        } ?: return false
        if (info.packageName != InteropContract.CHRONOSFLOW) {
            Log.w(TAG, "Interop: ${InteropContract.PEER_AUTHORITY} is owned by ${info.packageName}, not ChronosFlow — ignoring.")
            return false
        }
        return PeerVerifier.isTrusted(context, info.packageName)
    }

    private fun Cursor.string(name: String): String? {
        val i = getColumnIndex(name)
        return if (i < 0 || isNull(i)) null else getString(i)
    }

    private fun Cursor.longOrNull(name: String): Long? {
        val i = getColumnIndex(name)
        return if (i < 0 || isNull(i)) null else getLong(i)
    }

    private companion object {
        const val TAG = "InteropClient"
    }
}
