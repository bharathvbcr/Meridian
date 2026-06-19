package com.example.core.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Horizontally scrollable chip strip with edge fades and auto-scroll to [selectedIndex].
 */
@Composable
fun ScrollableChipRow(
    modifier: Modifier = Modifier,
    selectedIndex: Int = -1,
    content: LazyListScope.() -> Unit,
) {
    val listState = rememberLazyListState()
    val canScrollBackward by remember { derivedStateOf { listState.canScrollBackward } }
    val canScrollForward by remember { derivedStateOf { listState.canScrollForward } }
    val fadeColor = MaterialTheme.colorScheme.background

    LaunchedEffect(selectedIndex) {
        if (selectedIndex >= 0) {
            listState.animateScrollToItem(selectedIndex)
        }
    }

    Box(modifier = modifier.fillMaxWidth()) {
        LazyRow(
            state = listState,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = PaddingValues(horizontal = 2.dp),
            content = content,
        )
        if (canScrollBackward) {
            Box(
                Modifier
                    .align(Alignment.CenterStart)
                    .width(24.dp)
                    .height(FilterChipDefaults.Height)
                    .background(Brush.horizontalGradient(listOf(fadeColor, Color.Transparent)))
            )
        }
        if (canScrollForward) {
            Box(
                Modifier
                    .align(Alignment.CenterEnd)
                    .width(24.dp)
                    .height(FilterChipDefaults.Height)
                    .background(Brush.horizontalGradient(listOf(Color.Transparent, fadeColor)))
            )
        }
    }
}
