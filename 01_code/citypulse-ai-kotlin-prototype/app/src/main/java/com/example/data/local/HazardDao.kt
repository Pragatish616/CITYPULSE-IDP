package com.example.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface HazardDao {
    @Query("SELECT * FROM hazard_observations ORDER BY timestampEpochMs DESC")
    fun getAllHazardsFlow(): Flow<List<HazardEntity>>

    @Query("SELECT * FROM hazard_observations WHERE edgeId = :edgeId")
    suspend fun getHazardsForEdge(edgeId: String): List<HazardEntity>

    @Query("SELECT * FROM hazard_observations WHERE isChronicWatchlist = 1")
    fun getWatchlistFlow(): Flow<List<HazardEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertHazards(hazards: List<HazardEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertHazard(hazard: HazardEntity)

    @Query("DELETE FROM hazard_observations WHERE isChronicWatchlist = 0")
    suspend fun clearLiveHazards()

    @Query("DELETE FROM hazard_observations WHERE id = :id")
    suspend fun deleteHazardById(id: String)
}
