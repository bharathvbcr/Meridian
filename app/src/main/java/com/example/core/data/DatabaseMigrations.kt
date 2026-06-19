package com.example.core.data

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

/** Adds [Person.locationName] and back-fills from the IANA zone id for legacy rows. */
val MIGRATION_8_9 = object : Migration(8, 9) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL(
            "ALTER TABLE people ADD COLUMN locationName TEXT NOT NULL DEFAULT ''",
        )
        db.execSQL(
            """
            UPDATE people
            SET locationName = replace(substr(zoneId, instr(zoneId, '/') + 1), '_', ' ')
            WHERE locationName = ''
            """.trimIndent(),
        )
    }
}

/**
 * Adds [PlannedTask.origin] and [PlannedTask.externalId] for cross-app sharing: rows imported
 * from ChronosFlow carry the source package + its row id so re-imports update in place and never
 * get re-shared. Both columns are nullable, so existing locally-authored tasks default to null.
 */
val MIGRATION_9_10 = object : Migration(9, 10) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE planned_tasks ADD COLUMN origin TEXT")
        db.execSQL("ALTER TABLE planned_tasks ADD COLUMN externalId TEXT")
    }
}
