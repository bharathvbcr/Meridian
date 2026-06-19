package com.example.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.core.designsystem.liquidGlass
import dev.chrisbanes.haze.HazeState

/**
 * The medium/expanded-window counterpart to [GlassNavBar] (§6): a floating vertical glass rail.
 * Same destinations and glass language as the phone bar, with the AI launcher as the prominent
 * center slot. Falls back to an opaque surface under reduce-transparency like all glass surfaces.
 */
@Composable
fun GlassNavRail(
    hazeState: HazeState,
    currentRoute: String,
    onNavigate: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .width(72.dp)
            .liquidGlass(
                hazeState = hazeState,
                shape = RoundedCornerShape(36.dp),
                tintColor = Color.Black.copy(alpha = 0.1f),
            )
            .padding(vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        RailItem(Icons.Default.Home, "Now", currentRoute == "now") { onNavigate("now") }
        Spacer(Modifier.height(12.dp))
        RailItem(Icons.Default.Public, "World", currentRoute == "world") { onNavigate("world") }
        Spacer(Modifier.height(12.dp))
        RailItem(Icons.Default.AutoAwesome, "AI Assistant", currentRoute == "ai") { onNavigate("ai") }
        Spacer(Modifier.height(12.dp))
        RailItem(Icons.Default.Schedule, "Plan", currentRoute == "plan") { onNavigate("plan") }
        Spacer(Modifier.height(12.dp))
        RailItem(Icons.Default.Settings, "Settings", currentRoute == "settings") { onNavigate("settings") }
    }
}

@Composable
private fun RailItem(icon: ImageVector, label: String, selected: Boolean, onClick: () -> Unit) {
    IconButton(
        onClick = onClick,
        modifier = Modifier.semantics {
            this.selected = selected
            this.role = Role.Tab
            this.contentDescription = "$label tab"
        }
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = if (selected) MaterialTheme.colorScheme.primary
            else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        )
    }
}
