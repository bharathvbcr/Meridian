package com.example.core.location

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import androidx.core.content.ContextCompat
import com.example.core.time.GeoPoint
import com.example.core.time.ZoneCoordinates
import java.time.Instant
import java.time.ZoneId

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
        val location = lastKnownLocation() ?: return null
        val nearest = ZoneCoordinates.nearestKnownZone(location.latitude, location.longitude)
        // The nearest known city can sit across a border (much of southern India is closer to
        // Colombo than Kolkata). When the device's configured zone keeps the same clock as that
        // candidate, trust the device — it knows which country it's in; the location-based guess
        // only wins when the offsets actually differ (i.e. the device zone is stale).
        val system = ZoneId.systemDefault()
        val now = Instant.now()
        val sameClock = runCatching {
            ZoneId.of(nearest).rules.getOffset(now) == system.rules.getOffset(now)
        }.getOrDefault(false)
        return if (sameClock) system.id else nearest
    }

    /** Device's last-known coordinate, or null without a permission or cached fix. */
    fun lastKnownCoordinate(): GeoPoint? =
        lastKnownLocation()?.let { GeoPoint(it.latitude, it.longitude) }

    private fun lastKnownLocation(): Location? {
        if (!hasLocationPermission()) return null
        val manager = context.getSystemService(LocationManager::class.java) ?: return null
        val providers = listOf(
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER,
            LocationManager.GPS_PROVIDER,
        )
        return providers.firstNotNullOfOrNull { provider ->
            runCatching {
                if (manager.isProviderEnabled(provider)) manager.getLastKnownLocation(provider) else null
            }.getOrNull()
        }
    }
}
