// LiquidGlass.swift
// Meridian — iOS 27  Swift 6  SwiftUI
//
// The Liquid Glass surface treatment, ported from Android's `Modifier.liquidGlass`
// (LiquidGlass.kt). On iOS 27 the native `.glassEffect` is used unconditionally — there
// are no `#available(iOS 26)` fallbacks. The surface falls back to an opaque Material You
// card when the user disables glass, forces reduce-transparency, or the system
// accessibility "Reduce Transparency" flag is on.
//
// EnvironmentKeys (glassEnabled, glassOpacity, reduceTransparencyOverride)
// are defined in AppEnvironment.swift — no redefinition here.

import SwiftUI

// MARK: - GlassEffectModifier

/// Applies the liquid-glass surface. Reads the Meridian glass environment plus the system
/// `accessibilityReduceTransparency` flag and degrades to an opaque surface when any of them
/// requests reduced transparency or glass is disabled.
struct GlassEffectModifier: ViewModifier {
    var cornerRadius: CGFloat = 28
    /// Base tint hue. The effective alpha is derived from `\.glassOpacity` unless `tintOpacity`
    /// is supplied explicitly (matching Android's fixed `cardTint` at 6 %).
    var tint: Color = MeridianColors.primary
    /// Fixed tint alpha. Defaults to Android's 0.06 card tint; pass nil to follow glassOpacity.
    var tintOpacity: Double? = 0.06
    /// Border stroke width.
    var borderWidth: CGFloat = 0.5
    /// Opaque fallback surface used under reduce-transparency.
    var opaqueFallback: Color = MeridianColors.surface

    @Environment(\.glassEnabled) private var glassEnabled
    @Environment(\.glassOpacity) private var glassOpacity
    @Environment(\.reduceTransparencyOverride) private var reduceTransparencyOverride
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var resolvedTint: Color {
        if let tintOpacity { return tint.opacity(tintOpacity) }
        // Follow the slider for accessory surfaces that opt into glassOpacity.
        return tint.opacity(ScrubberGlass.alphas(opacity: glassOpacity).pillTint)
    }

    func body(content: Content) -> some View {
        // Opaque, high-contrast Material You fallback (§ reduce-transparency parity with Android).
        if systemReduceTransparency || reduceTransparencyOverride || !glassEnabled {
            content
                .background(opaqueFallback, in: shape)
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.8 * 0.2 + 0.16), lineWidth: borderWidth)
                }
                .clipShape(shape)
        } else {
            content
                .glassEffect(
                    .regular.tint(resolvedTint).interactive(false),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.2), lineWidth: borderWidth)
                }
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies the Meridian liquid-glass surface. Reads the glass environment internally;
    /// callers no longer pass `glassEnabled` / `reduceTransparency` (kept implicit for parity
    /// with the Android `Modifier.liquidGlass`, which reads its CompositionLocals).
    func liquidGlass(
        cornerRadius: CGFloat = 28,
        tint: Color = MeridianColors.primary,
        tintOpacity: Double? = 0.06,
        borderWidth: CGFloat = 0.5,
        opaqueFallback: Color = MeridianColors.surface
    ) -> some View {
        modifier(
            GlassEffectModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                tintOpacity: tintOpacity,
                borderWidth: borderWidth,
                opaqueFallback: opaqueFallback
            )
        )
    }
}

// MARK: - GlassCard

/// A frosted glass card. Mirrors Android's `GlassCard` — a padded box with the standard
/// liquid-glass surface and corner radius.
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let tint: Color
    @ViewBuilder let content: () -> Content

    init(
        cornerRadius: CGFloat = 28,
        padding: CGFloat = 16,
        tint: Color = MeridianColors.primary,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.tint = tint
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .liquidGlass(cornerRadius: cornerRadius, tint: tint)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("GlassCard — liquid glass") {
    ZStack {
        LinearGradient(
            colors: [MeridianColors.background, MeridianColors.surface],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack(spacing: 20) {
            GlassCard(cornerRadius: 20, padding: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Glass Enabled")
                        .font(.titleMedium)
                        .foregroundStyle(MeridianColors.onSurface)
                    Text("Native iOS 27 GlassEffect")
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .environment(\.glassEnabled, true)
            .environment(\.reduceTransparencyOverride, false)

            GlassCard(cornerRadius: 20, padding: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reduce Transparency")
                        .font(.titleMedium)
                        .foregroundStyle(MeridianColors.onSurface)
                    Text("Opaque dark surface fallback")
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .environment(\.glassEnabled, true)
            .environment(\.reduceTransparencyOverride, true)
        }
        .padding(.horizontal, 24)
    }
    .preferredColorScheme(.dark)
}
#endif
