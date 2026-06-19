package com.example.core.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface PersonDao {
    @Query("SELECT * FROM people ORDER BY name ASC")
    fun getAllPeople(): Flow<List<Person>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertPerson(person: Person): Long

    @Query("DELETE FROM people WHERE id = :personId")
    suspend fun deletePerson(personId: Int)

    @Query("UPDATE people SET isFavorite = :isFavorite WHERE id = :personId")
    suspend fun updateFavorite(personId: Int, isFavorite: Boolean)
}
