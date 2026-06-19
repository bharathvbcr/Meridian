package com.example.feature.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.text.FontWeight
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.cornerRadius
import com.example.MeridianApplication
import com.example.core.data.SavedZone
import kotlinx.coroutines.flow.first
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

class MeridianWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = context.applicationContext as MeridianApplication
        val zoneDao = app.container.zoneDao

        // Tapping the widget deep-links into the World screen (§5.4).
        val openWorldIntent = Intent(Intent.ACTION_VIEW, Uri.parse("meridian://world"))
            .setPackage(context.packageName)

        provideContent {
            // Retrieve pinned zones on launch/refresh from Room
            var savedZones = emptyList<SavedZone>()
            try {
                // Fetch the list of saved zones from flow cleanly
                savedZones = kotlinx.coroutines.runBlocking {
                    zoneDao.getAllZones().first()
                }
            } catch (e: Exception) {
                // Handle fallback if database is loading
            }

            // Theme-driven like the app: GlanceTheme uses Material You dynamic color on
            // Android 12+ and a sensible light/dark baseline otherwise, so the widget stays
            // legible in both modes instead of being pinned to the dark slate palette.
            GlanceTheme {
            Box(
                modifier = GlanceModifier
                    .fillMaxSize()
                    .background(GlanceTheme.colors.background)
                    .cornerRadius(16.dp)
                    .clickable(actionStartActivity(openWorldIntent))
                    .padding(12.dp),
                contentAlignment = Alignment.TopStart
            ) {
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    // Header row
                    Row(
                        modifier = GlanceModifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Meridian World Clock",
                            style = TextStyle(
                                color = GlanceTheme.colors.primary,
                                fontWeight = FontWeight.Bold,
                                fontSize = 14.sp
                            )
                        )
                    }

                    Spacer(modifier = GlanceModifier.height(8.dp))

                    if (savedZones.isEmpty()) {
                        Box(
                            modifier = GlanceModifier.fillMaxSize(),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = "No pinned locations yet. Open Meridian to add worldwide cities.",
                                style = TextStyle(
                                    color = GlanceTheme.colors.onSurfaceVariant,
                                    fontSize = 12.sp
                                )
                            )
                        }
                    } else {
                        LazyColumn(modifier = GlanceModifier.fillMaxSize()) {
                            items(savedZones) { zone ->
                                val nowInstant = Instant.now()
                                val zZoneId = try {
                                    ZoneId.of(zone.id)
                                } catch (e: Exception) {
                                    ZoneId.systemDefault()
                                }
                                val zonedDateTime = ZonedDateTime.ofInstant(nowInstant, zZoneId)
                                val formattedTime = zonedDateTime.format(DateTimeFormatter.ofPattern("hh:mm a"))

                                Row(
                                    modifier = GlanceModifier
                                        .fillMaxWidth()
                                        .background(GlanceTheme.colors.surfaceVariant)
                                        .cornerRadius(8.dp)
                                        .padding(horizontal = 10.dp, vertical = 6.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Column(modifier = GlanceModifier.defaultWeight()) {
                                        Text(
                                            text = zone.displayName,
                                            style = TextStyle(
                                                color = GlanceTheme.colors.onSurface,
                                                fontWeight = FontWeight.Bold,
                                                fontSize = 12.sp
                                            )
                                        )
                                        Text(
                                            text = zone.id,
                                            style = TextStyle(
                                                color = GlanceTheme.colors.onSurfaceVariant,
                                                fontSize = 10.sp
                                            )
                                        )
                                    }
                                    Spacer(modifier = GlanceModifier.width(8.dp))
                                    Text(
                                        text = formattedTime,
                                        style = TextStyle(
                                            color = GlanceTheme.colors.primary,
                                            fontWeight = FontWeight.Bold,
                                            fontSize = 13.sp
                                        )
                                    )
                                }
                                Spacer(modifier = GlanceModifier.height(4.dp))
                            }
                        }
                    }
                }
            }
            }
        }
    }
}

/**
 * Android Home Screen Broadcaster Receiver required to host the Glance Widget provider.
 */
class MeridianWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = MeridianWidget()
}
