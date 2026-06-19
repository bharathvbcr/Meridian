package com.example.core.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource

@Preview(showBackground = true)
@Composable
fun DesignSystemPreviews() {
    MeridianExpressiveTheme(darkTheme = true) {
        Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                Text(
                    text = "Typography",
                    style = MaterialTheme.typography.displaySmall,
                    color = MaterialTheme.colorScheme.primary
                )
                
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Display Large", style = MaterialTheme.typography.displayLarge)
                    Text("Display Medium", style = MaterialTheme.typography.displayMedium)
                    Text("Display Small", style = MaterialTheme.typography.displaySmall)
                    Text("Headline Large", style = MaterialTheme.typography.headlineLarge)
                    Text("Headline Medium", style = MaterialTheme.typography.headlineMedium)
                    Text("Title Large", style = MaterialTheme.typography.titleLarge)
                    Text("Title Medium", style = MaterialTheme.typography.titleMedium)
                    Text("Body Large", style = MaterialTheme.typography.bodyLarge)
                    Text("Body Medium", style = MaterialTheme.typography.bodyMedium)
                }

                Text(
                    text = "Buttons",
                    style = MaterialTheme.typography.displaySmall,
                    color = MaterialTheme.colorScheme.primary
                )

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = {}) { Text("Filled") }
                    FilledTonalButton(onClick = {}) { Text("Tonal") }
                    ElevatedButton(onClick = {}) { Text("Elevated") }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = {}) { Text("Outlined") }
                    TextButton(onClick = {}) { Text("Text") }
                }

                Text(
                    text = "Colors Token",
                    style = MaterialTheme.typography.displaySmall,
                    color = MaterialTheme.colorScheme.primary
                )

                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ColorBox("Primary", MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.onPrimary)
                    ColorBox("Secondary", MaterialTheme.colorScheme.secondary, MaterialTheme.colorScheme.onSecondary)
                    ColorBox("Tertiary", MaterialTheme.colorScheme.tertiary, MaterialTheme.colorScheme.onTertiary)
                }
                
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ColorBox("Surface", MaterialTheme.colorScheme.surface, MaterialTheme.colorScheme.onSurface)
                    ColorBox("Background", MaterialTheme.colorScheme.background, MaterialTheme.colorScheme.onBackground)
                    ColorBox("Error", MaterialTheme.colorScheme.error, MaterialTheme.colorScheme.onError)
                }
            }
        }
    }
}

@Composable
private fun ColorBox(name: String, backgroundColor: androidx.compose.ui.graphics.Color, contentColor: androidx.compose.ui.graphics.Color) {
    Card(
        modifier = Modifier
            .width(100.dp)
            .height(80.dp),
        colors = CardDefaults.cardColors(containerColor = backgroundColor, contentColor = contentColor)
    ) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = androidx.compose.ui.Alignment.Center) {
            Text(text = name, style = MaterialTheme.typography.labelMedium)
        }
    }
}
