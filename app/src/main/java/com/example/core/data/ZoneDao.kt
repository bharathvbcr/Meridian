package com.example.core.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ZoneDao {
    @Query("SELECT * FROM saved_zones ORDER BY orderIndex ASC")
    fun getAllZones(): Flow<List<SavedZone>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertZone(zone: SavedZone)

    @Query("DELETE FROM saved_zones WHERE id = :zoneId")
    suspend fun deleteZone(zoneId: String)

    @Query("UPDATE saved_zones SET isFavorite = :isFavorite WHERE id = :zoneId")
    suspend fun updateFavorite(zoneId: String, isFavorite: Boolean)
}
