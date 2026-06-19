package com.example.core.notify

import android.content.Context
import com.example.core.data.SavedZone
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import java.time.ZoneId

class WearSyncManager(private val context: Context) {

    fun syncZones(zones: List<SavedZone>) {
        val homeZone = zones.find { it.isHome }
        val systemZoneId = ZoneId.systemDefault().id

        // Determine home zone info
        val homeId = homeZone?.id ?: systemZoneId
        val homeName = homeZone?.displayName ?: homeId.substringAfterLast('/').replace('_', ' ')

        // Determine second zone info
        // Rule: We look for the first pinned zone that is different from the watch's system zone.
        // Since we don't know the watch's system zone here, we use the first pinned zone that is
        // not the phone's system default. If no other zone is pinned, we default to UTC.
        val nonSystemZone = zones.firstOrNull { it.id != systemZoneId }
        val secondId = nonSystemZone?.id ?: "UTC"
        val secondName = nonSystemZone?.displayName ?: "UTC"

        val request = PutDataMapRequest.create("/meridian/zones").run {
            dataMap.putString("home_zone_id", homeId)
            dataMap.putString("home_zone_name", homeName)
            dataMap.putString("second_zone_id", secondId)
            dataMap.putString("second_zone_name", secondName)
            dataMap.putLong("timestamp", System.currentTimeMillis())
            asPutDataRequest()
        }

        Wearable.getDataClient(context).putDataItem(request)
    }
}
