package com.example.wear

import android.content.Context
import androidx.wear.tiles.TileService
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService

class WearSyncListenerService : WearableListenerService() {

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        for (event in dataEvents) {
            if (event.type == DataEvent.TYPE_CHANGED) {
                val path = event.dataItem.uri.path
                if (path == "/meridian/zones") {
                    val dataMap = DataMapItem.fromDataItem(event.dataItem).dataMap
                    val homeId = dataMap.getString("home_zone_id") ?: ""
                    val homeName = dataMap.getString("home_zone_name") ?: ""
                    val secondId = dataMap.getString("second_zone_id") ?: ""
                    val secondName = dataMap.getString("second_zone_name") ?: ""

                    // Save to Shared Preferences
                    val prefs = getSharedPreferences("meridian_wear_prefs", Context.MODE_PRIVATE)
                    prefs.edit()
                        .putString("home_zone_id", homeId)
                        .putString("home_zone_name", homeName)
                        .putString("second_zone_id", secondId)
                        .putString("second_zone_name", secondName)
                        .apply()

                    // Request Tile update to reflect new zone instantly
                    TileService.getUpdater(applicationContext)
                        .requestUpdate(SecondZoneTileService::class.java)
                }
            }
        }
    }
}
