package com.example.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.example.core.data.SavedZone
import com.example.core.time.TimeFormats
import java.time.ZoneId
import java.time.ZonedDateTime

@Composable
fun TimeBoardItem(
    zone: SavedZone,
    currentTime: ZonedDateTime,
    is24Hour: Boolean,
    modifier: Modifier = Modifier
) {
    val formatter = remember(is24Hour) { TimeFormats.hourMinute(is24Hour) }
    val zoneTime = currentTime.withZoneSameInstant(ZoneId.of(zone.id))
    
    Box(
        modifier = modifier
            .padding(vertical = 8.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(16.dp)
    ) {
        Column {
            Text(
                text = zone.displayName,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = zoneTime.format(formatter),
                style = MaterialTheme.typography.displayMedium,
                color = MaterialTheme.colorScheme.primary
            )
        }
    }
}
