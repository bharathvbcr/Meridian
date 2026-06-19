package com.example.core.data

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "planned_tasks")
data class PlannedTask(
    @PrimaryKey(autoGenerate = true) val id: Int = 0,
    val title: String,
    val timestamp: Long,
    val zoneId: String,
    val orderIndex: Int = 0,
    /**
     * Package name of the app this row was imported from (e.g. ChronosFlow), or null for tasks
     * authored locally in DevTime. Imported rows are never re-shared, preventing echo loops.
     */
    val origin: String? = null,
    /** Stable id of the source row within [origin]; used to upsert imports idempotently. */
    val externalId: String? = null,
)
