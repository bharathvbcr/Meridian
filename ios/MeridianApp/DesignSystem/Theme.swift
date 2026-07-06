import SwiftUI

// MARK: - Color Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b, a: Double
        switch hex.count {
        case 6:
            // RRGGBB — opaque.
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8)  & 0xFF) / 255.0
            b = Double( int        & 0xFF) / 255.0
            a = 1.0
        case 8:
            // RRGGBBAA — trailing alpha byte.
            r = Double((int >> 24) & 0xFF) / 255.0
            g = Double((int >> 16) & 0xFF) / 255.0
            b = Double((int >> 8)  & 0xFF) / 255.0
            a = Double( int        & 0xFF) / 255.0
        default:
            // Fail loudly in DEBUG so a mistyped token (e.g. a 3- or 4-digit shorthand)
            // is caught in development instead of silently shipping an opaque black surface.
            assertionFailure("Color(hex:) expects a 6-digit RRGGBB or 8-digit RRGGBBAA string; got \"\(hex)\" (\(hex.count) chars).")
            r = 0; g = 0; b = 0; a = 1.0
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Meridian Colors

enum MeridianColors {
    /// #60CDFF — brand primary, interactive accents
    static let primary = Color(hex: "60CDFF")

    /// #020617 — label on primary-colored surfaces
    static let onPrimary = Color(hex: "020617")

    /// #0D2A3B — tinted container behind primary elements
    static let primaryContainer = Color(hex: "0D2A3B")

    /// #CBE6FF — label on the primary container (selected nav text/icons)
    static let onPrimaryContainer = Color(hex: "CBE6FF")

    /// #94A3B8 — secondary label / supporting text
    static let secondary = Color(hex: "94A3B8")

    /// #020617 — root canvas / page background
    static let background = Color(hex: "020617")

    /// #0F172A — card / sheet / glass surface
    static let surface = Color(hex: "0F172A")

    /// #F1F5F9 — primary text on background
    static let onBackground = Color(hex: "F1F5F9")

    /// #F1F5F9 — primary text on surface cards
    static let onSurface = Color(hex: "F1F5F9")

    /// #94A3B8 — secondary / placeholder text on surface
    static let onSurfaceVariant = Color(hex: "94A3B8")

    // MARK: Day/night — ICON accent (sun & moon glyph tint)
    // Shared semantic token so day-vs-night reads identically across Now and World Clock.

    /// #FFD166 — daytime ICON accent (sun glyph)
    static let daylightAccent = Color(hex: "FFD166")

    /// #90D2FF — nighttime ICON accent (moon glyph)
    static let nightAccent = Color(hex: "90D2FF")

    // MARK: Day/night — card GLOW (distinct hue pair, glow counterpart of the accents)

    /// #FFB703 — warm GLOW for daytime cards
    static let daylightGlow = Color(hex: "FFB703")

    /// #219EBC — cool GLOW for nighttime cards
    static let nightGlow = Color(hex: "219EBC")

    /// #4CAF50 — success / available / overlap-score positive
    static let positive = Color(hex: "4CAF50")

    // MARK: Error (M3 dark error tones; Android: colorScheme.error / errorContainer)

    /// Error foreground — icons and emphasized error text.
    static let error = Color(hex: "FFB4AB")

    /// Error surface — the assistant's failed-turn bubble background.
    static let errorContainer = Color(hex: "93000A")

    /// Text on `errorContainer`.
    static let onErrorContainer = Color(hex: "FFDAD6")

    /// Frosted-glass card tint: primary at 6 % opacity
    static let cardTint = Color(hex: "60CDFF").opacity(0.06)

    /// Lifted base tone for agenda pills and time scrubbers. The highest tonal container
    /// (surface) nudged 12 % toward onSurface so the card reads clearly *lighter* than the
    /// near-black page behind it — mirrors Android's `GlassDefaults.scrubberCardTone`.
    static let scrubberCardTone = Color.lerp(surface, onSurface, 0.12)
}

// MARK: - Color blending helper

extension Color {
    /// Linearly interpolates between two colors in sRGB. `t` is clamped to 0...1.
    /// Used for `scrubberCardTone` and accessory-tint derivations.
    static func lerp(_ start: Color, _ end: Color, _ t: Double) -> Color {
        let clamped = min(max(t, 0), 1)
        let s = start.rgbaComponents
        let e = end.rgbaComponents
        return Color(
            red:   s.r + (e.r - s.r) * clamped,
            green: s.g + (e.g - s.g) * clamped,
            blue:  s.b + (e.b - s.b) * clamped,
            opacity: s.a + (e.a - s.a) * clamped
        )
    }

    /// Resolved sRGB components (best-effort; falls back to opaque black for undecodable colors).
    var rgbaComponents: (r: Double, g: Double, b: Double, a: Double) {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) {
            return (Double(r), Double(g), Double(b), Double(a))
        }
        #endif
        return (0, 0, 0, 1)
    }
}

// MARK: - Scrubber / accessory glass alphas
// Mirrors Android's `ScrubberGlass` (ScrubberGlass.kt). Maps the normalized glass-opacity
// fraction (0.10...1.0, see MeridianSettings.glassOpacity) onto pill/card tint strengths.

/// Resolved glass style for agenda pills and scrubber surfaces.
struct ScrubberGlassAlphas: Sendable, Equatable {
    /// Compact pill + agenda accessory surface scrim.
    let pillTint: Double
    /// Expanded scrubber card surface scrim — stronger than `pillTint` at every step.
    let cardTint: Double
    /// Track background scrim.
    let trackBackground: Double
    /// When true, use a milkier frosted backing rather than near-clear glass.
    let frosted: Bool
}

enum ScrubberGlass {
    // Floors are deliberately high so even the "transparent" end reads as a solid card whose
    // text/ticks stay legible over a busy backdrop; the slider scales contrast toward opaque.
    private static let pillTintMin = 0.66
    private static let pillTintMax = 1.0
    private static let cardTintMin = 0.86
    private static let cardTintMax = 1.0
    private static let trackBgMin = 0.22
    private static let trackBgMax = 0.46
    private static let frostedThreshold = 0.03

    /// `opacity` is the normalized fraction (0.10...1.0) carried in `\.glassOpacity`.
    static func alphas(opacity: Double) -> ScrubberGlassAlphas {
        let t = fraction(opacity)
        return ScrubberGlassAlphas(
            pillTint: lerp(pillTintMin, pillTintMax, t),
            cardTint: lerp(cardTintMin, cardTintMax, t),
            trackBackground: lerp(trackBgMin, trackBgMax, t),
            frosted: t >= frostedThreshold
        )
    }

    /// Maps normalized opacity (0.10...1.0) to a 0...1 slider fraction, matching Android's
    /// `fraction(percent)` where MIN=10 %, MAX=100 %.
    static func fraction(_ opacity: Double) -> Double {
        let minOpacity = 0.10
        let maxOpacity = 1.0
        return min(max((opacity - minOpacity) / (maxOpacity - minOpacity), 0), 1)
    }

    private static func lerp(_ start: Double, _ end: Double, _ t: Double) -> Double {
        start + (end - start) * t
    }
}

// MARK: - Accessory tint tokens (follow glassOpacity)

extension MeridianColors {
    /// Glass tint for bottom accessory and collapsed scrubber pills — follows `\.glassOpacity`.
    /// Backed by the lifted `scrubberCardTone` so the pill keeps card-like contrast.
    static func accessoryPillTint(opacity: Double) -> Color {
        scrubberCardTone.opacity(ScrubberGlass.alphas(opacity: opacity).pillTint)
    }

    /// Frosted surface tint for expanded scrubber cards — follows `\.glassOpacity`.
    static func accessoryCardTint(opacity: Double) -> Color {
        scrubberCardTone.opacity(ScrubberGlass.alphas(opacity: opacity).cardTint)
    }
}

// MARK: - Meridian Corner Radius

enum MeridianRadius: CGFloat {
    case small      = 12
    case medium     = 20
    case large      = 28
    case extraLarge = 36
}

// MARK: - Meridian Typography

// Each token keeps its original base point-size and weight (the source of truth for the
// default "Large" content-size category) but is resolved through `UIFontMetrics` so the
// rendered size scales with the user's Dynamic Type setting. The `relativeTo:` anchor is
// the closest standard text style, which controls how aggressively the size scales at the
// accessibility steps. See `Font.scaledSystem(size:weight:relativeTo:)` below.
extension Font {
    /// 44 pt Black — hero display text
    static var displayLarge: Font {
        .scaledSystem(size: 44, weight: .black, relativeTo: .largeTitle)
    }

    /// 36 pt Heavy — large display text
    static var displayMedium: Font {
        .scaledSystem(size: 36, weight: .heavy, relativeTo: .largeTitle)
    }

    /// 24 pt Bold — screen / section headlines
    static var headlineLarge: Font {
        .scaledSystem(size: 24, weight: .bold, relativeTo: .title2)
    }

    /// 20 pt SemiBold — secondary headlines
    static var headlineMedium: Font {
        .scaledSystem(size: 20, weight: .semibold, relativeTo: .title3)
    }

    /// 22 pt Bold — card / modal titles
    static var titleLarge: Font {
        .scaledSystem(size: 22, weight: .bold, relativeTo: .title2)
    }

    /// 16 pt SemiBold — row / list titles
    static var titleMedium: Font {
        .scaledSystem(size: 16, weight: .semibold, relativeTo: .body)
    }

    /// 16 pt Regular — primary body copy
    static var bodyLarge: Font {
        .scaledSystem(size: 16, weight: .regular, relativeTo: .body)
    }

    /// 14 pt Regular — secondary body copy
    static var bodyMedium: Font {
        .scaledSystem(size: 14, weight: .regular, relativeTo: .subheadline)
    }

    /// 13 pt Regular — dense secondary copy (captions, metadata rows)
    static var bodySmall: Font {
        .scaledSystem(size: 13, weight: .regular, relativeTo: .footnote)
    }

    /// 12 pt SemiBold — labels, tags, badges
    static var labelMedium: Font {
        .scaledSystem(size: 12, weight: .semibold, relativeTo: .caption)
    }

    /// 11 pt SemiBold — smallest label rung (compact badges/pills)
    static var labelSmall: Font {
        .scaledSystem(size: 11, weight: .semibold, relativeTo: .caption2)
    }
}

private extension Font {
    /// Builds a system font at an exact base point size that genuinely scales with the
    /// user's Dynamic Type setting, anchored to the closest standard text style.
    ///
    /// Chaining a no-op onto `.system(size:)` (as an earlier revision did) produced a
    /// fixed, non-scaling font. This instead resolves the size through `UIFontMetrics`
    /// so a 44 pt token becomes ~52 pt at the "Large" accessibility step, ~38 pt at the
    /// smallest, etc. — the numeric base size stays the source of truth for the default
    /// (Large) content-size category, and everything above/below scales proportionally.
    ///
    /// On platforms without UIKit (e.g. macOS previews) it degrades to the fixed-size
    /// system font, which keeps the tokens usable without crashing.
    static func scaledSystem(
        size: CGFloat,
        weight: Font.Weight,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        #if canImport(UIKit)
        let metrics = UIFontMetrics(forTextStyle: textStyle.uiTextStyle)
        let scaledSize = metrics.scaledValue(for: size)
        return .system(size: scaledSize, weight: weight, design: .default)
        #else
        return .system(size: size, weight: weight, design: .default)
        #endif
    }
}

#if canImport(UIKit)
private extension Font.TextStyle {
    /// Maps a SwiftUI text style to its UIKit counterpart so `UIFontMetrics` can scale
    /// against the matching category. Falls back to `.body` for any unmapped style.
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title:      return .title1
        case .title2:     return .title2
        case .title3:     return .title3
        case .headline:   return .headline
        case .subheadline: return .subheadline
        case .body:       return .body
        case .callout:    return .callout
        case .footnote:   return .footnote
        case .caption:    return .caption1
        case .caption2:   return .caption2
        @unknown default: return .body
        }
    }
}
#endif

// MARK: - Meridian Spacing

enum MeridianSpacing: CGFloat {
    /// 4 pt — hairline gaps, icon padding
    case xs  = 4
    /// 8 pt — compact insets, icon-to-label gaps
    case sm  = 8
    /// 12 pt — standard internal padding
    case md  = 12
    /// 16 pt — section padding, list row insets
    case lg  = 16
    /// 20 pt — card padding, modal insets
    case xl  = 20
    /// 24 pt — generous spacing between sections
    case xxl = 24
}
