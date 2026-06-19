package com.example.core.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(entities = [SavedZone::class, PlannedTask::class, Person::class], version = 10, exportSchema = false)
abstract class AppDatabase : RoomDatabase() {
    abstract fun zoneDao(): ZoneDao
    abstract fun taskDao(): TaskDao
    abstract fun personDao(): PersonDao

    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null

        fun getDatabase(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "meridian_database"
                )
                .addMigrations(MIGRATION_8_9, MIGRATION_9_10)
                .fallbackToDestructiveMigrationFrom(1, 2, 3, 4, 5, 6, 7)
                .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
