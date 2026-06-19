package com.example.core.location

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import androidx.core.content.ContextCompat
import com.example.core.time.ZoneCoordinates

/**
 * Resolves a best-guess home IANA zone from the device's last-known coarse location, fully
 * offline (§5.1, §8). Uses the platform [LocationManager] (no Play Services) and maps the
 * coordinate to the nearest known city via [ZoneCoordinates]. Returns null when permission is
 * missing or no fix is cached — the caller then falls back to manual selection.
 */
class LocationZoneResolver(private val context: Context) {

    fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    /** Best-effort home zone id, or null if it can't be determined without prompting further. */
    fun resolveHomeZoneId(): String? {
        if (!hasLocationPermission()) return null
        val manager = context.getSystemService(LocationManager::class.java) ?: return null
        val providers = listOf(
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER,
            LocationManager.GPS_PROVIDER,
        )
        val location = providers.firstNotNullOfOrNull { provider ->
            runCatching {
                if (manager.isProviderEnabled(provider)) manager.getLastKnownLocation(provider) else null
            }.getOrNull()
        } ?: return null
        return ZoneCoordinates.nearestKnownZone(location.latitude, location.longitude)
    }
}
