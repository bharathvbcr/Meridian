package com.example.feature.widget

import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.example.MeridianApplication
import com.example.core.data.SavedZone
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

/**
 * A Quick Settings tile for a one-glance "world times" peek (§5.4). Shows the home (or first
 * pinned) zone's current time as the subtitle; tapping it opens the World screen.
 */
class WorldClockTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile ?: return
        tile.state = Tile.STATE_ACTIVE
        tile.label = "World times"

        val zone = loadPrimaryZone()
        if (zone != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val now = ZonedDateTime.now(ZoneId.of(zone.id)).format(DateTimeFormatter.ofPattern("h:mm a"))
            tile.subtitle = "${zone.displayName} · $now"
        }
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("meridian://world"))
            .setPackage(packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pending = PendingIntent.getActivity(
                this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun loadPrimaryZone(): SavedZone? {
        val zones = runCatching {
            val dao = (applicationContext as MeridianApplication).container.zoneDao
            runBlocking { dao.getAllZones().first() }
        }.getOrDefault(emptyList())
        return zones.firstOrNull { it.isHome } ?: zones.firstOrNull()
    }
}
