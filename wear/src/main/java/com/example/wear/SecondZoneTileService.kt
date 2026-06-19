package com.example.wear

import androidx.wear.protolayout.ColorBuilders
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import android.content.Context
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

private const val RESOURCES_VERSION = "1"
private val HM = DateTimeFormatter.ofPattern("HH:mm")

/**
 * A standalone Wear OS tile showing the watch's local time plus a quick second zone (§6/§17).
 * Times are computed on-device with java.time and refreshed each minute — no phone data needed,
 * so the tile works on its own. Synced home/second zone is loaded from SharedPreferences.
 */
class SecondZoneTileService : TileService() {

    override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest
    ): ListenableFuture<TileBuilders.Tile> {
        val now = ZonedDateTime.now(ZoneId.systemDefault())

        // Read synced second zone from SharedPreferences
        val prefs = getSharedPreferences("meridian_wear_prefs", Context.MODE_PRIVATE)
        val secondZoneId = prefs.getString("second_zone_id", "UTC") ?: "UTC"
        val secondZoneName = prefs.getString("second_zone_name", "UTC") ?: "UTC"

        val secondZone = runCatching { ZoneId.of(secondZoneId) }.getOrDefault(ZoneOffset.UTC)
        val secondTime = ZonedDateTime.now(secondZone)

        // Simplify names like "New York" or just take name as is
        val briefSecondName = secondZoneName.substringAfterLast('/').replace('_', ' ')

        val root = LayoutElementBuilders.Column.Builder()
            .addContent(label("Local"))
            .addContent(timeText(now.format(HM)))
            .addContent(label(briefSecondName))
            .addContent(timeText(secondTime.format(HM)))
            .build()

        val tile = TileBuilders.Tile.Builder()
            .setResourcesVersion(RESOURCES_VERSION)
            .setFreshnessIntervalMillis(60_000)
            .setTileTimeline(TimelineBuilders.Timeline.fromLayoutElement(root))
            .build()

        return Futures.immediateFuture(tile)
    }

    override fun onTileResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest
    ): ListenableFuture<ResourceBuilders.Resources> =
        Futures.immediateFuture(
            ResourceBuilders.Resources.Builder().setVersion(RESOURCES_VERSION).build()
        )

    private fun label(text: String): LayoutElementBuilders.Text =
        LayoutElementBuilders.Text.Builder()
            .setText(text)
            .setFontStyle(
                LayoutElementBuilders.FontStyle.Builder()
                    .setSize(DimensionBuilders.sp(13f))
                    .setColor(ColorBuilders.argb(0xFF60CDFF.toInt()))
                    .build()
            )
            .build()

    private fun timeText(text: String): LayoutElementBuilders.Text =
        LayoutElementBuilders.Text.Builder()
            .setText(text)
            .setFontStyle(
                LayoutElementBuilders.FontStyle.Builder()
                    .setSize(DimensionBuilders.sp(28f))
                    .setColor(ColorBuilders.argb(0xFFFFFFFF.toInt()))
                    .build()
            )
            .build()
}
