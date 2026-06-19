package com.example.core.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface TaskDao {
    @Query("SELECT * FROM planned_tasks ORDER BY orderIndex ASC, timestamp ASC")
    fun getAllTasks(): Flow<List<PlannedTask>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertTask(task: PlannedTask): Long

    @Query("DELETE FROM planned_tasks WHERE id = :taskId")
    suspend fun deleteTask(taskId: Int)

    // --- Cross-app sharing (interop) ---------------------------------------------------------

    /** Row id of an already-imported task, so a re-import REPLACEs it instead of duplicating. */
    @Query("SELECT id FROM planned_tasks WHERE origin = :origin AND externalId = :externalId LIMIT 1")
    suspend fun getImportedId(origin: String, externalId: String): Int?

    /** Locally-authored tasks (not imported from a peer); used to reconcile their reminders. */
    @Query("SELECT * FROM planned_tasks WHERE origin IS NULL")
    suspend fun getNativeTasksOnce(): List<PlannedTask>

    /** Drops imported rows from [origin] that are no longer present upstream. */
    @Query("DELETE FROM planned_tasks WHERE origin = :origin AND externalId NOT IN (:keepExternalIds)")
    suspend fun deleteImportedNotIn(origin: String, keepExternalIds: List<String>)

    /** Drops every imported row from [origin] (used when the peer now has nothing to share). */
    @Query("DELETE FROM planned_tasks WHERE origin = :origin")
    suspend fun deleteAllImported(origin: String)
}
