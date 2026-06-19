package com.example.core.data

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "saved_zones")
data class SavedZone(
    @PrimaryKey val id: String, // e.g. "America/Los_Angeles"
    val displayName: String,    // e.g. "San Francisco"
    val isHome: Boolean = false,
    /** [ZoneAnchorRole] slot on the Now card; empty for watchlist-only zones. */
    val anchorRole: String = ZoneAnchorRole.NONE,
    val orderIndex: Int = 0,
    val isFavorite: Boolean = false
)
