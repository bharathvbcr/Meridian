package com.example.core.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Meridian brand mark — a wireframe globe (prime meridian + equator + curved longitude/latitude
 * lines) with a "solar noon" marker where the prime meridian crosses the rim.
 *
 * Fully theme-aware: the globe inherits [lineColor] (the Material primary) and the marker uses
 * [markerColor] (the tertiary accent), so it follows light/dark and Material You dynamic colour
 * automatically. This mirrors the adaptive launcher icon so the brand reads the same everywhere.
 */
@Composable
fun MeridianLogo(
    modifier: Modifier = Modifier,
    size: Dp = 32.dp,
    lineColor: Color = MaterialTheme.colorScheme.primary,
    markerColor: Color = MaterialTheme.colorScheme.tertiary,
) {
    Canvas(
        modifier = modifier
            .size(size)
            .semantics { contentDescription = "Meridian logo" }
    ) {
        val w = this.size.minDimension
        val center = Offset(w / 2f, w / 2f)
        val radius = w * 0.40f
        val strokeWidth = w * 0.055f
        val stroke = Stroke(width = strokeWidth, cap = StrokeCap.Round)

        // Globe rim
        drawCircle(color = lineColor, radius = radius, center = center, style = stroke)
        // Equator (horizontal diameter)
        drawLine(
            color = lineColor,
            start = Offset(center.x - radius, center.y),
            end = Offset(center.x + radius, center.y),
            strokeWidth = strokeWidth,
            cap = StrokeCap.Round
        )
        // Prime meridian (vertical diameter)
        drawLine(
            color = lineColor,
            start = Offset(center.x, center.y - radius),
            end = Offset(center.x, center.y + radius),
            strokeWidth = strokeWidth,
            cap = StrokeCap.Round
        )
        // Curved meridian (longitude ellipse)
        val meridianHalfWidth = radius * 0.42f
        drawOval(
            color = lineColor,
            topLeft = Offset(center.x - meridianHalfWidth, center.y - radius),
            size = Size(meridianHalfWidth * 2f, radius * 2f),
            style = stroke
        )
        // Curved latitude (ellipse)
        val latitudeHalfHeight = radius * 0.42f
        drawOval(
            color = lineColor,
            topLeft = Offset(center.x - radius, center.y - latitudeHalfHeight),
            size = Size(radius * 2f, latitudeHalfHeight * 2f),
            style = stroke
        )
        // Solar-noon marker where the prime meridian meets the rim
        drawCircle(
            color = markerColor,
            radius = w * 0.085f,
            center = Offset(center.x, center.y - radius)
        )
    }
}

/**
 * Logo + "Meridian" wordmark, laid out horizontally for headers and brand surfaces.
 */
@Composable
fun MeridianWordmark(
    modifier: Modifier = Modifier,
    logoSize: Dp = 28.dp,
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        MeridianLogo(size = logoSize)
        Text(
            text = "Meridian",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Black,
            color = MaterialTheme.colorScheme.onBackground
        )
    }
}
