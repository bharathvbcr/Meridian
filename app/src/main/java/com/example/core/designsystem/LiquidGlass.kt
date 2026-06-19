package com.example.core.designsystem

import android.content.Context
import android.os.Build
import android.view.accessibility.AccessibilityManager
import androidx.annotation.RequiresApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
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
}

/**
 * Accesses system accessibility states for high contrast and reduce transparency settings (if available).
 */
@Composable
fun rememberReduceTransparency(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager ?: return@remember false
        val isSystemHighContrast = try {
            val highContrastMethod = am.javaClass.getMethod("isHighContrastTextEnabled")
            highContrastMethod.invoke(am) as? Boolean ?: false
        } catch (e: Exception) {
            false
        }
        
        isSystemHighContrast
    }
}

/**
 * A highly customizable Liquid Glass modifier that applies backdrop blur using Haze.
 * Automatically falls back to a clean, high-contrast, opaque Material You surface
 * when accessibility checks indicate "Reduce Transparency" is enabled or on unsupported platforms.
 * Applies the AGSL lens distortion and specular highlights on Android T (API 33) or higher.
 */
@OptIn(ExperimentalHazeMaterialsApi::class)
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

    // Base layout with Haze backdrop blur
    var processedModifier = this
        .clip(shape)
        .hazeEffect(
            state = hazeState,
            style = if (frosted) HazeMaterials.regular() else HazeMaterials.ultraThin()
        )
        .border(borderWidth, borderColor, shape)
        .background(tintColor)

    // Enhance with AGSL refraction on API 33+ (Android 13+). The RuntimeShader is compiled once
    // and remembered — building it inside the graphicsLayer block recompiled the AGSL on every
    // single draw/scroll frame, which was a major source of jank. Only the size-dependent
    // resolution uniform is updated per-draw.
    val refractionShader = remember(distortion, tintColor) {
        if (Build.VERSION.SDK_INT >= 33) {
            runCatching {
                android.graphics.RuntimeShader(REFRACTION_SHADER_SRC).apply {
                    setFloatUniform("distortion", distortion)
                    setFloatUniform("tintColor", tintColor.red, tintColor.green, tintColor.blue, tintColor.alpha)
                }
            }.getOrNull()
        } else {
            null
        }
    }
    if (refractionShader != null) {
        processedModifier = processedModifier.then(
            Modifier.graphicsLayer {
                val widthVal = size.width
                val heightVal = size.height
                if (widthVal > 0f && heightVal > 0f) {
                    try {
                        refractionShader.setFloatUniform("resolution", widthVal, heightVal)
                        renderEffect = android.graphics.RenderEffect
                            .createRuntimeShaderEffect(refractionShader, "inputTexture")
                            .asComposeRenderEffect()
                    } catch (e: Exception) {
                        // Fall back gracefully on devices with incomplete AGSL support (standard blur works)
                    }
                }
            }
        )
    }

    return processedModifier
}
