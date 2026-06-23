package com.example.core.designsystem

import android.content.Context
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityManager
import com.example.BuildConfig
import androidx.annotation.RequiresApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeEffect
import dev.chrisbanes.haze.materials.ExperimentalHazeMaterialsApi
import dev.chrisbanes.haze.materials.HazeMaterials

const val REFRACTION_SHADER_SRC = """
    uniform shader inputTexture;
    uniform vec2 resolution;
    uniform float distortion;
    uniform vec4 tintColor;

    half4 main(vec2 fragCoord) {
        vec2 uv = fragCoord / resolution;
        vec2 center = vec2(0.5, 0.5);
        vec2 toCenter = uv - center;
        float dist = length(toCenter);
        
        // Warp uv coordinates slightly toward/away from center for genuine lens refraction
        vec2 warpedUv = uv + toCenter * dist * distortion;
        
        // Clip to avoid reading out of bounds texture
        if (warpedUv.x < 0.0 || warpedUv.x > 1.0 || warpedUv.y < 0.0 || warpedUv.y > 1.0) {
            warpedUv = uv;
        }
        
        half4 color = inputTexture.eval(warpedUv * resolution);
        
        // Simulate a dynamic specular highlight from top left (-1.0, -1.0)
        vec2 lightDir = normalize(vec2(-1.0, -1.0));
        vec2 normal = normalize(toCenter);
        float spec = max(dot(normal, lightDir), 0.0);
        spec = pow(spec, 16.0) * 0.16; // Specular exponent and peak brightness
        
        // Soft perimeter glow
        float edgeGlow = smoothstep(0.42, 0.5, dist) * 0.06;
        
        // Composite color with tint and specular peaks
        color.rgb = color.rgb * (1.0 - tintColor.a) + tintColor.rgb * tintColor.a;
        color.rgb += vec3(spec + edgeGlow);
        
        return color;
    }
"""

object GlassDefaults {
    /** Unified Material You glass tint for all standard cards/surfaces.
     *  Day/night-aware cards (daylight, working-hours) intentionally override this. */
    val cardTint: Color
        @Composable get() = MaterialTheme.colorScheme.primary.copy(alpha = 0.06f)

    /**
     * Base tone for the agenda pill and time scrubbers: the highest tonal container nudged toward
     * [onSurface][androidx.compose.material3.ColorScheme.onSurface] so the card reads clearly
     * *lighter* than the near-black page behind it. In a dark dynamic scheme the container tones
     * sit so close to the background that even a fully opaque card looks dark-on-dark and its text
     * washes out — this lift restores genuine card contrast while staying inside the palette.
     */
    val scrubberCardTone: Color
        @Composable get() = androidx.compose.ui.graphics.lerp(
            MaterialTheme.colorScheme.surfaceContainerHighest,
            MaterialTheme.colorScheme.onSurface,
            0.12f,
        )

    /** Glass tint for bottom accessory and collapsed scrubber pills — follows [LocalGlassOpacity].
     *  Backed by the lifted [scrubberCardTone] so the pill keeps card-like contrast. */
    val accessoryPillTint: Color
        @Composable get() = scrubberCardTone.copy(
            alpha = ScrubberGlass.alphas(LocalGlassOpacity.current).pillTint
        )

    /** Frosted surface tint for expanded scrubber cards — follows [LocalGlassOpacity]. */
    val accessoryCardTint: Color
        @Composable get() = scrubberCardTone.copy(
            alpha = ScrubberGlass.alphas(LocalGlassOpacity.current).cardTint
        )

    /** Unified corner radius for all standard glass cards/surfaces. */
    val cardShape: Shape = RoundedCornerShape(28.dp)

    /** Corner radius for floating DropdownMenus / context menus (Material `shapes.medium`). */
    val menuShape: Shape = RoundedCornerShape(20.dp)

    /** Day/night sun & moon ICON accent. Shared semantic token so day-vs-night reads identically
     *  across Now and World Clock (the literals these replace are also duplicated ~25x). */
    val daylightAccent: Color
        @Composable get() = Color(0xFFFFD166)
    val nightAccent: Color
        @Composable get() = Color(0xFF90D2FF)

    /** Day/night card GLOW. Distinct hue pair previously diverged from the icon accent; kept as
     *  separate tokens but documented as the glow counterpart of [daylightAccent]/[nightAccent]. */
    val daylightGlow: Color
        @Composable get() = Color(0xFFFFB703)
    val nightGlow: Color
        @Composable get() = Color(0xFF219EBC)

    /** Success / "granted" green for permission status and similar positive states. */
    val positive: Color
        @Composable get() = Color(0xFF4CAF50)
}

/**
 * Reactively tracks whether the system high-contrast (reduce-transparency) flag is enabled.
 * Uses the public API on API 31+ and registers a live listener so the result updates while
 * the app is in the foreground. Returns false below API 31.
 */
@Composable
fun rememberReduceTransparency(): Boolean {
    val context = LocalContext.current
    var highContrast by remember(context) {
        val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
        val initial = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.readHighTextContrastEnabled()
        } else {
            false
        }
        mutableStateOf(initial)
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        DisposableEffect(context) {
            val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
            val listener = AccessibilityManager.AccessibilityStateChangeListener {
                highContrast = am.readHighTextContrastEnabled()
            }
            am?.addAccessibilityStateChangeListener(listener)
            onDispose { am?.removeAccessibilityStateChangeListener(listener) }
        }
    }

    return highContrast
}

/**
 * Reads the system "high text contrast" flag, which doubles as the reduce-transparency signal.
 * [AccessibilityManager.isHighTextContrastEnabled] is hidden (`@hide`) in the public SDK, so it
 * is read reflectively; any failure is treated as "not enabled".
 */
private fun AccessibilityManager?.readHighTextContrastEnabled(): Boolean {
    if (this == null) return false
    return try {
        val method = javaClass.getMethod("isHighTextContrastEnabled")
        method.invoke(this) as? Boolean ?: false
    } catch (e: Exception) {
        if (BuildConfig.DEBUG) Log.d("LiquidGlass", "isHighTextContrastEnabled unavailable", e)
        false
    }
}

/**
 * Content-safe Liquid Glass modifier: backdrop blur (Haze) + translucent tint + hairline border.
 * Falls back to a clean, opaque Material You surface when "Reduce Transparency" is enabled or on
 * unsupported platforms.
 *
 * This variant deliberately does NOT apply the AGSL lens-refraction RenderEffect, because that
 * effect is applied to the node it lives on and therefore also distorts/erases any child content
 * (see the long note in [glassImpl]). When you want the full refraction effect on a surface that
 * holds content, use [LiquidGlassSurface], which renders the refracting glass in a separate layer
 * *behind* the content.
 */
@Composable
fun Modifier.liquidGlass(
    hazeState: HazeState,
    shape: Shape = GlassDefaults.cardShape,
    borderWidth: Dp = 0.5.dp,
    tintColor: Color = GlassDefaults.cardTint,
    opaqueFallbackColor: Color = MaterialTheme.colorScheme.surface,
    borderColor: Color = Color.White.copy(alpha = 0.2f),
    distortion: Float = 0.05f,
    // Backdrop blur is the single most expensive thing this modifier does, and its cost is paid
    // *per surface, per frame*. Numerous, frequently-redrawn surfaces (e.g. every row of a
    // scrolling list) should pass blur = false: they keep the translucent tint, border and the
    // refracted backdrop showing through, but skip the costly per-row Haze capture+blur and the
    // AGSL refraction. Reserve the full frosted effect for the few pieces of pinned chrome
    // (nav bar, scrubber, hero cards) where it reads clearly and isn't multiplied across a list.
    blur: Boolean = true,
    // Frosted surfaces swap the near-clear ultraThin backdrop for the heavier `regular` Haze
    // material — a milkier, more opaque scrim that reads as frosted glass rather than near-clear.
    // Use for floating chrome that must stand out over a busy backdrop (e.g. the time scrubbers).
    frosted: Boolean = false
): Modifier = glassImpl(
    hazeState, shape, borderWidth, tintColor, opaqueFallbackColor,
    borderColor, distortion, blur, frosted, refract = false
)

/**
 * Refracting Liquid Glass surface modifier — like [liquidGlass] but ALSO layers the AGSL lens
 * distortion + specular highlight on top via a `graphicsLayer` RenderEffect.
 *
 * That RenderEffect processes the node AND its children, so this MUST only be applied to an empty,
 * content-free layer. Prefer [LiquidGlassSurface], which wires this up correctly (a backdrop layer
 * behind the content). Below API 33 / when glass is disabled it degrades to plain [liquidGlass].
 */
@Composable
fun Modifier.liquidGlassBackdrop(
    hazeState: HazeState,
    shape: Shape = GlassDefaults.cardShape,
    borderWidth: Dp = 0.5.dp,
    tintColor: Color = GlassDefaults.cardTint,
    opaqueFallbackColor: Color = MaterialTheme.colorScheme.surface,
    borderColor: Color = Color.White.copy(alpha = 0.2f),
    distortion: Float = 0.05f,
    frosted: Boolean = false
): Modifier = glassImpl(
    hazeState, shape, borderWidth, tintColor, opaqueFallbackColor,
    borderColor, distortion, blur = true, frosted = frosted, refract = true
)

@OptIn(ExperimentalHazeMaterialsApi::class)
@Composable
private fun Modifier.glassImpl(
    hazeState: HazeState,
    shape: Shape,
    borderWidth: Dp,
    tintColor: Color,
    opaqueFallbackColor: Color,
    borderColor: Color,
    distortion: Float,
    blur: Boolean,
    frosted: Boolean,
    refract: Boolean,
): Modifier {
    // Fall back to an opaque Material surface when the system requests reduced transparency,
    // the user disables the glass compositor, or the user forces reduced transparency (§12.13).
    val systemReduceTransparency = rememberReduceTransparency()
    val glassEnabled = LocalGlassEnabled.current
    val userReduceTransparency = LocalReduceTransparencyOverride.current

    if (systemReduceTransparency || userReduceTransparency || !glassEnabled) {
        return this
            .clip(shape)
            .background(opaqueFallbackColor)
            .border(borderWidth, borderColor.copy(alpha = 0.8f), shape)
    }

    // Lightweight glass: translucent tint over the (already blurred) backdrop, no per-surface
    // blur or refraction. Visually close to the frosted variant but a fraction of the GPU cost,
    // which is what lets long lists scroll smoothly even on mid-range devices.
    if (!blur) {
        return this
            .clip(shape)
            .background(tintColor)
            .border(borderWidth, borderColor, shape)
    }

    // Base layout with Haze backdrop blur.
    var processedModifier = this
        .clip(shape)
        .hazeEffect(
            state = hazeState,
            style = if (frosted) HazeMaterials.regular() else HazeMaterials.ultraThin()
        )
        .border(borderWidth, borderColor, shape)
        .background(tintColor)

    // AGSL lens refraction + specular highlight, applied as a graphicsLayer RenderEffect.
    // This RenderEffect processes this node AND its children, so it is gated behind `refract`,
    // which is only ever true on a content-free backdrop layer (see [LiquidGlassSurface]). Applying
    // it to a node that holds content would distort/erase that content. The RuntimeShader and
    // RenderEffect are built once and remembered; only the size-dependent resolution uniform is
    // updated per draw.
    if (refract) {
        data class ShaderHolder(
            val shader: android.graphics.RuntimeShader,
            val effect: android.graphics.RenderEffect
        )
        val shaderHolder = remember(distortion, tintColor) {
            if (Build.VERSION.SDK_INT >= 33) {
                runCatching {
                    val shader = android.graphics.RuntimeShader(REFRACTION_SHADER_SRC).apply {
                        setFloatUniform("distortion", distortion)
                        setFloatUniform("tintColor", tintColor.red, tintColor.green, tintColor.blue, tintColor.alpha)
                    }
                    val effect = android.graphics.RenderEffect
                        .createRuntimeShaderEffect(shader, "inputTexture")
                    ShaderHolder(shader, effect)
                }.onFailure { e ->
                    if (BuildConfig.DEBUG) Log.e("LiquidGlass", "AGSL compile error", e)
                }.getOrNull()
            } else {
                null
            }
        }
        if (shaderHolder != null) {
            processedModifier = processedModifier.then(
                Modifier.graphicsLayer {
                    val widthVal = size.width
                    val heightVal = size.height
                    if (widthVal > 0f && heightVal > 0f) {
                        try {
                            shaderHolder.shader.setFloatUniform("resolution", widthVal, heightVal)
                            renderEffect = shaderHolder.effect.asComposeRenderEffect()
                        } catch (e: Exception) {
                            if (BuildConfig.DEBUG) Log.e("LiquidGlass", "AGSL uniform error", e)
                        }
                    }
                }
            )
        }
    }

    return processedModifier
}

/**
 * Two-layer Liquid Glass container: an empty refracting glass surface ([liquidGlassBackdrop]) drawn
 * *behind* [content]. The AGSL lens refraction therefore warps only the blurred backdrop and never
 * the content placed on top — which is exactly the bug that applying the effect to a content-bearing
 * node caused (empty frosted cards). Use this anywhere a glass surface holds content and you want the
 * full refraction; reach for the plain [liquidGlass] modifier only for backgrounds without content.
 */
@Composable
fun LiquidGlassSurface(
    hazeState: HazeState,
    modifier: Modifier = Modifier,
    shape: Shape = GlassDefaults.cardShape,
    borderWidth: Dp = 0.5.dp,
    tintColor: Color = GlassDefaults.cardTint,
    borderColor: Color = Color.White.copy(alpha = 0.2f),
    frosted: Boolean = false,
    content: @Composable BoxScope.() -> Unit,
) {
    Box(modifier.clip(shape)) {
        // Content-free backdrop layer: it is the only thing the refraction RenderEffect touches.
        Box(
            Modifier
                .matchParentSize()
                .liquidGlassBackdrop(
                    hazeState = hazeState,
                    shape = shape,
                    borderWidth = borderWidth,
                    tintColor = tintColor,
                    borderColor = borderColor,
                    frosted = frosted,
                )
        )
        content()
    }
}
