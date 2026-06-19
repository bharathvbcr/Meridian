package com.example.core.interop

import android.content.ContentProvider
import android.content.ContentValues
import android.content.UriMatcher
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import androidx.sqlite.db.SupportSQLiteDatabase
import com.example.core.data.AppDatabase

/**
 * Read-only provider exposing DevTime's shareable data to ChronosFlow. Authority is
 * `<applicationId>.share`. Every query is gated by [PeerVerifier]; only self-authored rows
 * (origin IS NULL) are served so imported copies are never re-shared.
 *
 * DevTime owns tasks, zones and people. The other paths return empty cursors so the peer can
 * query uniformly and simply get nothing for types this app doesn't have.
 */
class InteropProvider : ContentProvider() {

    private val matcher = UriMatcher(UriMatcher.NO_MATCH)

    override fun onCreate(): Boolean {
        val authority = "${context!!.packageName}.share"
        matcher.addURI(authority, InteropContract.PATH_TASKS, CODE_TASKS)
        matcher.addURI(authority, InteropContract.PATH_ZONES, CODE_ZONES)
        matcher.addURI(authority, InteropContract.PATH_PEOPLE, CODE_PEOPLE)
        matcher.addURI(authority, InteropContract.PATH_EVENTS, CODE_EVENTS)
        matcher.addURI(authority, InteropContract.PATH_HABITS, CODE_HABITS)
        matcher.addURI(authority, InteropContract.PATH_MEDICATIONS, CODE_MEDS)
        matcher.addURI(authority, InteropContract.PATH_GOALS, CODE_GOALS)
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? {
        val ctx = context ?: return null
        PeerVerifier.requireTrusted(ctx, callingPackage)
        val db = AppDatabase.getDatabase(ctx).openHelper.readableDatabase
        return when (matcher.match(uri)) {
            CODE_TASKS -> tasksCursor(db)
            CODE_ZONES -> zonesCursor(db)
            CODE_PEOPLE -> peopleCursor(db)
            // Types DevTime does not own — empty cursors keep peers' code uniform.
            CODE_EVENTS -> MatrixCursor(InteropContract.EVENT_COLUMNS)
            CODE_HABITS -> MatrixCursor(InteropContract.HABIT_COLUMNS)
            CODE_MEDS -> MatrixCursor(InteropContract.MEDICATION_COLUMNS)
            CODE_GOALS -> MatrixCursor(InteropContract.GOAL_COLUMNS)
            else -> null
        }
    }

    private fun tasksCursor(db: SupportSQLiteDatabase): Cursor {
        val out = MatrixCursor(InteropContract.TASK_COLUMNS)
        db.query(
            "SELECT id, title, timestamp, zoneId FROM planned_tasks WHERE origin IS NULL ORDER BY orderIndex ASC",
        ).use { c ->
            while (c.moveToNext()) {
                val ts = c.getLong(2)
                out.addRow(
                    arrayOf<Any?>(
                        c.getInt(0).toString(), // external_id
                        c.getString(1),         // title
                        null,                   // notes
                        ts,                     // due_at
                        0,                      // is_completed
                        null,                   // priority
                        c.getString(3),         // timezone (IANA zone id)
                        ts,                     // updated_at
                    ),
                )
            }
        }
        return out
    }

    private fun zonesCursor(db: SupportSQLiteDatabase): Cursor {
        val out = MatrixCursor(InteropContract.ZONE_COLUMNS)
        db.query("SELECT id, displayName, isHome FROM saved_zones ORDER BY orderIndex ASC").use { c ->
            while (c.moveToNext()) {
                out.addRow(
                    arrayOf<Any?>(
                        c.getString(0), // external_id
                        c.getString(0), // zone_id (IANA id)
                        c.getString(1), // display_name
                        c.getInt(2),    // is_home (0/1)
                    ),
                )
            }
        }
        return out
    }

    private fun peopleCursor(db: SupportSQLiteDatabase): Cursor {
        val out = MatrixCursor(InteropContract.PEOPLE_COLUMNS)
        db.query(
            "SELECT id, name, zoneId, locationName, workStartHour, workEndHour FROM people ORDER BY name ASC",
        ).use { c ->
            while (c.moveToNext()) {
                out.addRow(
                    arrayOf<Any?>(
                        c.getInt(0).toString(), // external_id
                        c.getString(1),         // name
                        c.getString(2),         // zone_id
                        c.getString(3),         // location_name
                        c.getInt(4),            // work_start_hour
                        c.getInt(5),            // work_end_hour
                    ),
                )
            }
        }
        return out
    }

    override fun getType(uri: Uri): String? = when (matcher.match(uri)) {
        UriMatcher.NO_MATCH -> null
        else -> "vnd.android.cursor.dir/vnd.${InteropContract.SELF_PACKAGE}.interop"
    }

    // Read-only provider: mutations are not supported.
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    private companion object {
        const val CODE_TASKS = 1
        const val CODE_ZONES = 2
        const val CODE_PEOPLE = 3
        const val CODE_EVENTS = 4
        const val CODE_HABITS = 5
        const val CODE_MEDS = 6
        const val CODE_GOALS = 7
    }
}
