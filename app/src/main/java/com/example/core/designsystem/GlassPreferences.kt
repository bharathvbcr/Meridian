package com.example.core.designsystem

import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.dp

/**
 * User-controlled glass toggles, provided once near the root and read by [Modifier.liquidGlass].
 * Lets the "Liquid Glass compositor" and "Reduce transparency" settings (§5/§12.13) flow into
 * every glass surface without threading parameters through the whole tree.
 */
val LocalGlassEnabled = compositionLocalOf { true }

/** User override that forces opaque surfaces regardless of system accessibility state. */
val LocalReduceTransparencyOverride = compositionLocalOf { false }

/**
 * Bottom inset reserved for the floating tab bar (mirrors iOS `tabBarInsetHeight`).
 * Shrinks when the bar collapses on scroll-down so pinned scrubbers ride closer.
 */
val LocalTabBarInsetHeight = compositionLocalOf { 96.dp }

/** Nested-scroll hook the shell uses to collapse the tab bar; screens attach via [Modifier.reportBarScroll]. */
val LocalBarScrollConnection = compositionLocalOf<androidx.compose.ui.input.nestedscroll.NestedScrollConnection?> { null }

/** Forwards scroll deltas to the shell so minimize-on-scroll works inside NavHost children. */
fun Modifier.reportBarScroll(): Modifier = composed {
    val connection = LocalBarScrollConnection.current
    if (connection != null) nestedScroll(connection) else this
}
