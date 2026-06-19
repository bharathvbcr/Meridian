package com.example.core.designsystem

import androidx.compose.runtime.compositionLocalOf

/**
 * User-controlled glass toggles, provided once near the root and read by [Modifier.liquidGlass].
 * Lets the "Liquid Glass compositor" and "Reduce transparency" settings (§5/§12.13) flow into
 * every glass surface without threading parameters through the whole tree.
 */
val LocalGlassEnabled = compositionLocalOf { true }

/** User override that forces opaque surfaces regardless of system accessibility state. */
val LocalReduceTransparencyOverride = compositionLocalOf { false }
