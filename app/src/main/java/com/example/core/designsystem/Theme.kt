package com.example.core.designsystem

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// Define Expressive shapes token (bold, rounded, dynamic morph-friendly)
val ExpressiveShapes = Shapes(
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(20.dp),
    large = RoundedCornerShape(28.dp),
    extraLarge = RoundedCornerShape(36.dp)
)

// Bold, modern display typography token for high hierarchy
val ExpressiveTypography = Typography(
    displayLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Black,
        fontSize = 44.sp,
        lineHeight = 52.sp,
        letterSpacing = (-1).sp
    ),
    displayMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.ExtraBold,
        fontSize = 36.sp,
        lineHeight = 44.sp,
        letterSpacing = (-0.5).sp
    ),
    displaySmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 28.sp,
        lineHeight = 36.sp,
        letterSpacing = 0.sp
    ),
    headlineLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 24.sp,
        lineHeight = 32.sp,
        letterSpacing = 0.sp
    ),
    headlineMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp,
        lineHeight = 28.sp,
        letterSpacing = 0.15.sp
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 22.sp,
        lineHeight = 28.sp,
        letterSpacing = 0.sp
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.15.sp
    ),
    titleSmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.1.sp
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.5.sp
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.25.sp
    ),
    bodySmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 13.sp,
        lineHeight = 18.sp,
        letterSpacing = 0.4.sp
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.1.sp
    ),
    labelMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.5.sp
    ),
    labelSmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Medium,
        fontSize = 11.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.5.sp
    )
)

// Dark Palette
val MeridianDarkColorScheme = darkColorScheme(
    primary = Color(0xFF60CDFF),
    onPrimary = Color(0xFF00354E),
    primaryContainer = Color(0xFF004C6F),
    onPrimaryContainer = Color(0xFFCBE6FF),
    secondary = Color(0xFF90D2FF),
    onSecondary = Color(0xFF003350),
    tertiary = Color(0xFFFFB2BE),
    onTertiary = Color(0xFF5E1129),
    background = Color(0xFF020617), // Deep space slate
    surface = Color(0xFF0F172A),    // Dark slate card background
    onBackground = Color(0xFFF1F5F9),
    onSurface = Color(0xFFF1F5F9),
    onSurfaceVariant = Color(0xFF94A3B8),
    // Celestial-neutral surface/outline family. Glass card tints, the frosted fallback outline
    // (LiquidGlass.fallbackOutline) and dividers read off these roles, so they are pinned to the
    // deep-space slate ramp rather than left to Material's seed-derived defaults — this keeps the
    // "Liquid Glass" surfaces on the same cool celestial neutral in both the static and (via
    // withMeridianBrand) the Material You paths.
    surfaceVariant = Color(0xFF1E293B),          // Slate 800 — glass tint / slider inactive track
    surfaceContainerHighest = Color(0xFF1E293B), // Lifted card tone base for scrubber glass
    outline = Color(0xFF475569),                 // Slate 600 — legible hairline / text-field border
    outlineVariant = Color(0xFF334155),          // Slate 700 — subtle divider
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005)
)

// Light Palette
val MeridianLightColorScheme = lightColorScheme(
    primary = Color(0xFF006591),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFCBE6FF),
    onPrimaryContainer = Color(0xFF001E30),
    secondary = Color(0xFF00669E),
    onSecondary = Color(0xFFFFFFFF),
    tertiary = Color(0xFF9C4054),
    onTertiary = Color(0xFFFFFFFF),
    background = Color(0xFFF8FAFC),
    surface = Color(0xFFFFFFFF),
    onBackground = Color(0xFF0F172A),
    onSurface = Color(0xFF0F172A),
    onSurfaceVariant = Color(0xFF475569),
    // Cool-neutral surface/outline family mirroring the dark scheme so glass tints, outlines and
    // dividers stay on the same slate ramp instead of Material's seed-derived defaults.
    surfaceVariant = Color(0xFFE2E8F0),          // Slate 200 — glass tint / slider inactive track
    surfaceContainerHighest = Color(0xFFE2E8F0), // Lifted card tone base for scrubber glass
    outline = Color(0xFF94A3B8),                 // Slate 400 — legible hairline / text-field border
    outlineVariant = Color(0xFFCBD5E1),          // Slate 300 — subtle divider
    error = Color(0xFFBA1A1A),
    onError = Color(0xFFFFFFFF)
)

/**
 * Overlays the Meridian brand identity onto a wallpaper-derived (Material You) scheme so the
 * celestial "Liquid Glass" language survives dynamic color. Material You may tint the wallpaper's
 * accent onto [primary]/[secondary] and lighten the canvas, which pushes the brand hue far from
 * #60CDFF and washes out the deep-space background. We preserve the wallpaper's neutral tonal
 * relationships but pin the load-bearing brand tokens: the brand accent, the celestial secondary,
 * the deep-space background/surface canvas that the glass surfaces are frosted over, the muted
 * variant used for subtitles/secondary text (whose WCAG-AA contrast on the dark canvas would
 * otherwise be at the mercy of the wallpaper), the celestial-neutral surface/outline family that
 * the "Liquid Glass" tints, frosted fallback outlines and dividers are frosted over (a warm
 * wallpaper would otherwise tint the glass away from the cool celestial neutral), and the semantic
 * error pair so alerts read identically regardless of Material You.
 */
private fun ColorScheme.withMeridianBrand(darkTheme: Boolean): ColorScheme {
    val brand = if (darkTheme) MeridianDarkColorScheme else MeridianLightColorScheme
    return copy(
        primary = brand.primary,
        onPrimary = brand.onPrimary,
        primaryContainer = brand.primaryContainer,
        onPrimaryContainer = brand.onPrimaryContainer,
        secondary = brand.secondary,
        onSecondary = brand.onSecondary,
        background = brand.background,
        onBackground = brand.onBackground,
        surface = brand.surface,
        onSurface = brand.onSurface,
        onSurfaceVariant = brand.onSurfaceVariant,
        surfaceVariant = brand.surfaceVariant,
        surfaceContainerHighest = brand.surfaceContainerHighest,
        outline = brand.outline,
        outlineVariant = brand.outlineVariant,
        error = brand.error,
        onError = brand.onError
    )
}

@Composable
fun MeridianExpressiveTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            val dynamicScheme =
                if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
            // Keep Material You's neutral tones but preserve the Meridian brand accent and
            // deep-space canvas so the celestial/glass identity isn't lost to the wallpaper.
            dynamicScheme.withMeridianBrand(darkTheme)
        }
        darkTheme -> MeridianDarkColorScheme
        else -> MeridianLightColorScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        shapes = ExpressiveShapes,
        typography = ExpressiveTypography,
        content = content
    )
}
