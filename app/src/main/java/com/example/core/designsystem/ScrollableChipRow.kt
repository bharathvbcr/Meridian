package com.example.core.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
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
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Design tokens local to the chip strip. Mirrors the shared spacing scale
 * (4 / 8 / 12 / 16 / 20 / 24) so the row stays on the app-wide rhythm without
 * hardcoding bare literals inline.
 */
private object ChipRowTokens {
    /** Gap between adjacent chips — spacing/8. */
    val ChipGap: Dp = 8.dp

    /** Horizontal breathing room so the first/last chip's selection ring isn't clipped. */
    val ContentInset: Dp = 2.dp

    /** Width of the decorative edge fade. */
    val FadeWidth: Dp = 24.dp
}

/**
 * Horizontally scrollable chip strip with edge fades and auto-scroll to [selectedIndex].
 *
 * The edge fades are purely decorative gradients painted over the interactive chips;
 * they carry no [Modifier.clickable] so they never intercept touches, and they are
 * hidden from accessibility so TalkBack focuses only the real chips.
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
    val reduceMotion = rememberReduceMotion()

    LaunchedEffect(selectedIndex, reduceMotion) {
        if (selectedIndex >= 0) {
            if (reduceMotion) {
                // Respect the platform Reduce Motion setting: jump instantly.
                listState.scrollToItem(selectedIndex)
            } else {
                listState.animateScrollToItem(selectedIndex)
            }
        }
    }

    Box(modifier = modifier.fillMaxWidth()) {
        LazyRow(
            state = listState,
            horizontalArrangement = Arrangement.spacedBy(ChipRowTokens.ChipGap),
            contentPadding = PaddingValues(horizontal = ChipRowTokens.ContentInset),
            content = content,
        )
        // Edge fades span the full measured row height (matchParentSize) so taller
        // chip content — leading-icon chips, wrapped labels — never shows a hard edge
        // bleeding past the gradient.
        if (canScrollBackward) {
            Box(
                Modifier
                    .align(Alignment.CenterStart)
                    .matchParentSize()
                    .width(ChipRowTokens.FadeWidth)
                    .clearAndSetSemantics { }
                    .background(Brush.horizontalGradient(listOf(fadeColor, Color.Transparent)))
            )
        }
        if (canScrollForward) {
            Box(
                Modifier
                    .align(Alignment.CenterEnd)
                    .matchParentSize()
                    .width(ChipRowTokens.FadeWidth)
                    .clearAndSetSemantics { }
                    .background(Brush.horizontalGradient(listOf(Color.Transparent, fadeColor)))
            )
        }
    }
}
