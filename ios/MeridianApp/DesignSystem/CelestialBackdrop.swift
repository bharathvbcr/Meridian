// CelestialBackdrop.swift
// Meridian — iOS 27 / Swift 6
//
// Ported from app/src/main/java/com/example/core/designsystem/CelestialBackdrop.kt
//
// A realistic, time-of-day aware sun/moon that lives behind every page. The body's
// position follows the sun across the sky between sunrise and sunset (and the moon
// across the night), its colour warms toward the horizon, and the moon shows the
// correct lit phase for the date. All geometry is derived from `SolarMath`; nothing
// is faked per-frame.
//
// On Android the scene re-renders once a minute and is rasterized into a cached
// bitmap so the haze source layer stays effectively static. iOS has no equivalent
// per-glass re-blur cost, but to match Android's once-a-minute cadence (and avoid a
// pointless redraw at the display refresh rate) the scene is driven by a
// `TimelineView(.periodic(from:by: 60))`. The `pulse` / `twinkle` animation values
// are fixed exactly as Android (`pulse = 0.5`, `twinkle = 0`) so the picture is
// deterministic and static between minute ticks.

import SwiftUI
import UIKit

// MARK: - CelestialBackdrop

/// Full-screen sun / moon / star backdrop, gated on `backdropEnabled` and scaled by
/// `backdropIntensity` (a normalized 0.10…1.0 fraction).
struct CelestialBackdrop: View {

    /// Backdrop glow strength as a normalized fraction (0.10…1.0).
    var intensity: Double = kDefaultBackdropIntensity

    /// When Reduce Motion is on, the once-a-minute body reposition is an instant cut
    /// rather than a glide, so the sun/moon never visibly slides across the screen.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Recompute the sky once a minute — fast enough to track the sun, cheap
        // enough to ignore. Matches Android's 60_000 ms cadence.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Canvas { gc, size in
                let sky = Self.computeSky(now: context.date)
                Self.drawSky(sky, into: gc, size: size)
            }
            // The scene is intentionally static between ticks; the only movement is the
            // once-a-minute reposition. Glide it with a gentle spring when motion is
            // allowed, but leave an instant redraw when Reduce Motion is requested.
            .animation(reduceMotion ? nil : Motion.smooth(), value: context.date)
            .allowsHitTesting(false)
        }
        .opacity(min(max(intensity, 0.0), 1.0))
        .ignoresSafeArea()
        // Purely decorative: the day/night state it conveys is carried by the accent
        // tokens on the cards in front of it, so keep it out of the a11y tree entirely.
        .accessibilityHidden(true)
    }

    // MARK: - SkyState

    /// Pre-computed, frame-independent description of the sky for the current instant.
    private struct SkyState {
        let dayFactor: Double      // 1 = full sun, 0 = full moon, blended through twilight
        let progressX: Double      // 0..1 horizontal travel of the visible body
        let altitude: Double       // 0 at horizon, 1 at peak
        let moonTerminator: Double // cos(phase angle): +1 new, -1 full
        let moonWaxing: Bool
    }

    // 29.530588853 days; 2000-01-06T18:14:00Z.
    private static let synodicMonthMs: Double = 2_551_442_876.0
    private static let knownNewMoonMs: Double = 947_182_440_000.0

    private static func computeSky(now: Date) -> SkyState {
        let zone = TimeZone.current
        let geo = ZoneGeo.coordinate(for: zone.identifier, at: now)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let nowMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        let sun = SolarMath.solarInfo(for: now, latitude: geo.latitude, longitude: geo.longitude)
        let cosZenith = SolarMath.cosSolarZenith(
            latitude: geo.latitude, longitude: geo.longitude, date: now)

        // Smooth sun↔moon crossfade through twilight rather than a hard switch at the horizon.
        let dayFactor = smoothstep(-0.10, 0.06, cosZenith)

        let progressX: Double
        let altitude: Double

        if sun.polarDay {
            progressX = 0.5; altitude = 0.7
        } else if sun.polarNight {
            progressX = 0.5; altitude = 0.55
        } else if let sunrise = sun.sunrise, let sunset = sun.sunset {
            let riseComps = calendar.dateComponents([.hour, .minute], from: sunrise)
            let setComps  = calendar.dateComponents([.hour, .minute], from: sunset)
            let rise = (riseComps.hour ?? 0) * 60 + (riseComps.minute ?? 0)
            let set  = (setComps.hour ?? 0) * 60 + (setComps.minute ?? 0)

            if dayFactor >= 0.5 && set > rise {
                let p = clamp01(Double(nowMin - rise) / Double(set - rise))
                progressX = p
                altitude = clamp01(sin(p * .pi))
            } else {
                // Night arc from sunset, wrapping past midnight to the next sunrise.
                let nightLen = max(1440 - (set - rise), 1)
                let elapsed = nowMin >= set ? nowMin - set : nowMin + (1440 - set)
                let p = clamp01(Double(elapsed) / Double(nightLen))
                progressX = p
                altitude = clamp01(sin(p * .pi))
            }
        } else {
            progressX = 0.5; altitude = 0.5
        }

        // Moon phase from the synodic cycle since a known new moon.
        let nowMs = now.timeIntervalSince1970 * 1000.0
        let ageFraction = (((nowMs - knownNewMoonMs) / synodicMonthMs)
            .truncatingRemainder(dividingBy: 1.0) + 1.0)
            .truncatingRemainder(dividingBy: 1.0)
        let moonTerminator = cos(2.0 * .pi * ageFraction)
        let moonWaxing = ageFraction < 0.5

        return SkyState(
            dayFactor: dayFactor,
            progressX: progressX,
            altitude: altitude,
            moonTerminator: moonTerminator,
            moonWaxing: moonWaxing
        )
    }

    // MARK: - Backdrop palette

    /// The backdrop needs a richer, multi-stop ramp than the four flat day/night
    /// tokens, but its warm/cool *endpoints* are anchored to the shared theme colours
    /// (`daylightAccent`/`daylightGlow`, `nightAccent`/`nightGlow`) so the sky stays in
    /// the same hue family as the cards that sit in front of it — a brand-colour change
    /// propagates here for free. Only the intermediate specular highlights (near-white
    /// disc peaks) and the deep earthshine shadow are backdrop-specific constants,
    /// because no shared token represents "the hottest point of the sun" or "the ashen
    /// unlit face of the moon".
    private enum Palette {

        // Sun — warm endpoints derived from the daytime tokens; the low, near-horizon
        // sun leans toward the warm glow, the high sun toward the bright accent.
        static let sunCoreLow  = MeridianColors.daylightGlow                 // hottest low-sun tint
        static let sunCoreHigh = Color(hex: "FFF6D8")                        // near-white noon core (specular peak)
        static let sunWarmLow  = Color.lerp(MeridianColors.daylightGlow,
                                            MeridianColors.error, 0.30)      // deep sunset red-orange
        static let sunWarmHigh = MeridianColors.daylightAccent              // bright high-sun gold

        // Moon — cool endpoints anchored to the night tokens.
        static let moonGlow    = MeridianColors.nightAccent                  // cool moonlight halo/glow
        static let moonDiscHi  = Color(hex: "FDFEFF")                        // specular disc highlight
        static let moonDiscMid = Color.lerp(MeridianColors.nightAccent,
                                            Color.white, 0.72)              // lit-face midtone
        static let moonDiscLo  = Color.lerp(MeridianColors.nightAccent,
                                            MeridianColors.nightGlow, 0.45) // shaded lit-limb toward the glow hue
        static let moonMaria   = Color.lerp(MeridianColors.nightAccent,
                                            MeridianColors.nightGlow, 0.30) // faint maria mottling
        static let moonShadow  = Color.lerp(MeridianColors.nightGlow,
                                            MeridianColors.background, 0.55) // deep ashen earthshine

        // Stars — a pale tint of the night accent so they read as the same cool family.
        static let star        = Color.lerp(MeridianColors.nightAccent,
                                            Color.white, 0.60)
    }

    // MARK: - Drawing

    private static func drawSky(_ sky: SkyState, into gc: GraphicsContext, size: CGSize) {
        // `pulse` was an animated value; it is now a fixed mid-pulse so the scene is static.
        let pulse = 0.5
        let twinkle = 0.0
        let w = size.width
        let h = size.height

        // Where the body sits: horizontal travel sunrise→sunset (or across the night
        // for the moon), vertical position arcing up toward solar noon.
        let cx = (0.16 + 0.68 * sky.progressX) * w
        let cy = (0.40 - 0.30 * sky.altitude) * h

        if sky.dayFactor > 0.01 {
            drawSun(cx: cx, cy: cy, w: w, h: h, sky: sky, pulse: pulse, alpha: sky.dayFactor, into: gc)
        }
        if sky.dayFactor < 0.99 {
            let nightAlpha = 1.0 - sky.dayFactor
            drawStars(w: w, h: h, twinkle: twinkle, alpha: nightAlpha, into: gc)
            drawMoon(cx: cx, cy: cy, w: w, h: h, sky: sky, pulse: pulse, alpha: nightAlpha, into: gc)
        }
    }

    /// The sun: a wide diffuse corona, a hot core and soft rays.
    private static func drawSun(
        cx: Double, cy: Double, w: Double, h: Double,
        sky: SkyState, pulse: Double, alpha: Double, into gc: GraphicsContext
    ) {
        let center = CGPoint(x: cx, y: cy)
        // Warm low sun → bright high sun. Endpoints are anchored to the daytime tokens
        // (see `Palette`) so the sun stays in the cards' hue family.
        let core = lerpColor(Palette.sunCoreLow, Palette.sunCoreHigh, sky.altitude)
        let warm = lerpColor(Palette.sunWarmLow, Palette.sunWarmHigh, sky.altitude)

        // The big atmospheric glow.
        let glowRadius = max(w, h) * (0.85 + 0.10 * pulse)
        let glowGradient = Gradient(stops: [
            .init(color: warm.opacity(0.55 * alpha), location: 0.0),
            .init(color: warm.opacity(0.30 * alpha), location: 0.18),
            .init(color: warm.opacity(0.10 * alpha), location: 0.45),
            .init(color: .clear, location: 1.0),
        ])
        gc.fill(
            circlePath(center: center, radius: glowRadius),
            with: .radialGradient(glowGradient, center: center,
                                  startRadius: 0, endRadius: glowRadius)
        )

        // Soft directional rays for a touch of god-ray realism.
        let rayLen = max(w, h) * 0.7
        for i in 0..<12 {
            var rays = gc
            // base rotate(pulse * 6) then i * 30 about the center. GraphicsContext has no
            // anchored rotate, so translate to the center, rotate, translate back.
            let angle = Angle.degrees(pulse * 6.0 + Double(i) * 30.0)
            rays.translateBy(x: center.x, y: center.y)
            rays.rotate(by: angle)
            rays.translateBy(x: -center.x, y: -center.y)
            var line = Path()
            line.move(to: center)
            line.addLine(to: CGPoint(x: center.x, y: center.y - rayLen))
            let rayGradient = Gradient(colors: [warm.opacity(0.10 * alpha), .clear])
            rays.stroke(
                line,
                with: .linearGradient(rayGradient,
                                      startPoint: center,
                                      endPoint: CGPoint(x: center.x, y: center.y - rayLen)),
                style: StrokeStyle(lineWidth: 26, lineCap: .round)
            )
        }

        let discRadius = min(max(0.052 * max(w, h), 46), 120)

        // Halo around the disc.
        let haloRadius = discRadius * 2.4
        let haloGradient = Gradient(stops: [
            .init(color: core.opacity(0.9 * alpha), location: 0.0),
            .init(color: warm.opacity(0.5 * alpha), location: 0.6),
            .init(color: .clear, location: 1.0),
        ])
        gc.fill(
            circlePath(center: center, radius: haloRadius),
            with: .radialGradient(haloGradient, center: center,
                                  startRadius: 0, endRadius: haloRadius)
        )

        // The bright body itself, lit toward the upper-left.
        let discCenter = CGPoint(x: cx - discRadius * 0.2, y: cy - discRadius * 0.2)
        let discGradient = Gradient(stops: [
            .init(color: Color.white.opacity(alpha), location: 0.0),
            .init(color: core.opacity(alpha), location: 0.5),
            .init(color: warm.opacity(0.85 * alpha), location: 1.0),
        ])
        gc.fill(
            circlePath(center: center, radius: discRadius),
            with: .radialGradient(discGradient, center: discCenter,
                                  startRadius: 0, endRadius: discRadius)
        )
    }

    /// The moon with its true lit phase, a cool halo and a faint cast glow.
    private static func drawMoon(
        cx: Double, cy: Double, w: Double, h: Double,
        sky: SkyState, pulse: Double, alpha: Double, into gc: GraphicsContext
    ) {
        let center = CGPoint(x: cx, y: cy)
        // Cool moonlight halo/glow, anchored to the night accent token.
        let cool = Palette.moonGlow

        // Cool moonlight glow.
        let glowRadius = max(w, h) * (0.5 + 0.06 * pulse)
        let glowGradient = Gradient(stops: [
            .init(color: cool.opacity(0.28 * alpha), location: 0.0),
            .init(color: cool.opacity(0.10 * alpha), location: 0.3),
            .init(color: .clear, location: 1.0),
        ])
        gc.fill(
            circlePath(center: center, radius: glowRadius),
            with: .radialGradient(glowGradient, center: center,
                                  startRadius: 0, endRadius: glowRadius)
        )

        let r = min(max(0.045 * max(w, h), 40), 100)

        // Halo ring.
        let haloRadius = r * 2.2
        let haloGradient = Gradient(stops: [
            .init(color: cool.opacity(0.35 * alpha), location: 0.0),
            .init(color: cool.opacity(0.12 * alpha), location: 0.7),
            .init(color: .clear, location: 1.0),
        ])
        gc.fill(
            circlePath(center: center, radius: haloRadius),
            with: .radialGradient(haloGradient, center: center,
                                  startRadius: 0, endRadius: haloRadius)
        )

        // Lit disc, lightly shaded toward the lower-right for a spherical feel.
        let discCenter = CGPoint(x: cx - r * 0.25, y: cy - r * 0.25)
        let discGradient = Gradient(stops: [
            .init(color: Palette.moonDiscHi.opacity(alpha), location: 0.0),
            .init(color: Palette.moonDiscMid.opacity(alpha), location: 0.7),
            .init(color: Palette.moonDiscLo.opacity(alpha), location: 1.0),
        ])
        gc.fill(
            circlePath(center: center, radius: r),
            with: .radialGradient(discGradient, center: discCenter,
                                  startRadius: 0, endRadius: r)
        )

        // A couple of subtle maria so the disc doesn't read as a flat dot.
        let maria = Palette.moonMaria
        gc.fill(
            circlePath(center: CGPoint(x: cx - r * 0.30, y: cy - r * 0.18), radius: r * 0.20),
            with: .color(maria.opacity(0.30 * alpha))
        )
        gc.fill(
            circlePath(center: CGPoint(x: cx + r * 0.22, y: cy + r * 0.28), radius: r * 0.14),
            with: .color(maria.opacity(0.24 * alpha))
        )
        gc.fill(
            circlePath(center: CGPoint(x: cx + r * 0.05, y: cy - r * 0.35), radius: r * 0.10),
            with: .color(maria.opacity(0.20 * alpha))
        )

        // Phase shadow: the unlit portion as a dim, ashen earthshine face rather than a
        // black hole, so even a near-new moon still reads as a moon.
        let shadow = buildMoonShadow(cx: cx, cy: cy, r: r,
                                     c: sky.moonTerminator, waxing: sky.moonWaxing)
        gc.fill(shadow, with: .color(Palette.moonShadow.opacity(0.82 * alpha)))

        // A faint rim so the full disc is always defined, whatever the phase.
        gc.stroke(
            circlePath(center: center, radius: r),
            with: .color(cool.opacity(0.22 * alpha)),
            style: StrokeStyle(lineWidth: 1.4)
        )
    }

    /// The unlit region of the moon as a closed path bounded by the dark limb and the
    /// terminator ellipse. `c` is cos(phase angle): +1 at new moon, −1 at full.
    private static func buildMoonShadow(cx: Double, cy: Double, r: Double, c: Double, waxing: Bool) -> Path {
        var path = Path()
        let n = 48
        func wAt(_ i: Int) -> (y: Double, w: Double) {
            let y = -r + 2.0 * r * Double(i) / Double(n)
            let ww = (r * r - y * y >= 0 ? (r * r - y * y) : 0).squareRoot()
            return (y, ww)
        }
        if waxing {
            // Lit on the right → shadow spans the left limb across to the terminator at x = c·w.
            path.move(to: CGPoint(x: cx, y: cy - r))
            for i in 0...n { let (y, ww) = wAt(i); path.addLine(to: CGPoint(x: cx - ww, y: cy + y)) }
            for i in stride(from: n, through: 0, by: -1) {
                let (y, ww) = wAt(i); path.addLine(to: CGPoint(x: cx + c * ww, y: cy + y))
            }
        } else {
            // Waning is the mirror image: lit on the left, shadow on the right.
            path.move(to: CGPoint(x: cx, y: cy - r))
            for i in 0...n { let (y, ww) = wAt(i); path.addLine(to: CGPoint(x: cx + ww, y: cy + y)) }
            for i in stride(from: n, through: 0, by: -1) {
                let (y, ww) = wAt(i); path.addLine(to: CGPoint(x: cx - c * ww, y: cy + y))
            }
        }
        path.closeSubpath()
        return path
    }

    /// A deterministic field of faint stars for the night sky. The twinkle value is
    /// fixed at 0 to match Android's static scene.
    private static func drawStars(w: Double, h: Double, twinkle: Double, alpha: Double, into gc: GraphicsContext) {
        // Tiny LCG — deterministic so stars don't jump between frames.
        var seed: Int64 = 1337
        func rnd() -> Double {
            seed = (seed &* 1103515245 &+ 12345) & 0x7FFFFFFF
            return Double(seed) / Double(0x7FFFFFFF)
        }
        let count = 64
        for _ in 0..<count {
            let sx = rnd() * w
            // Keep stars mostly in the upper two-thirds of the sky.
            let sy = rnd() * h * 0.7
            let baseR = 0.6 + rnd() * 1.8
            let phase = rnd() * (2.0 * .pi)
            let t = (sin(twinkle + phase) + 1.0) / 2.0
            let a = (0.20 + 0.55 * t) * alpha
            let radius = baseR * (0.7 + 0.5 * t)
            gc.fill(
                circlePath(center: CGPoint(x: sx, y: sy), radius: radius),
                with: .color(Palette.star.opacity(a))
            )
        }
    }

    // MARK: - Math helpers

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = clamp01((x - edge0) / (edge1 - edge0))
        return t * t * (3.0 - 2.0 * t)
    }

    private static func clamp01(_ v: Double) -> Double { min(max(v, 0.0), 1.0) }

    private static func circlePath(center: CGPoint, radius: Double) -> Path {
        Path(ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2))
    }

    /// Linear RGB interpolation between two colors, matching Compose `lerp(Color, Color, t)`
    /// closely enough for the warm-sun gradient (sRGB component lerp).
    private static func lerpColor(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let f = clamp01(t)
        let ca = a.resolveRGBA()
        let cb = b.resolveRGBA()
        return Color(
            .sRGB,
            red:   ca.r + (cb.r - ca.r) * f,
            green: ca.g + (cb.g - ca.g) * f,
            blue:  ca.b + (cb.b - ca.b) * f,
            opacity: ca.a + (cb.a - ca.a) * f
        )
    }
}

// MARK: - Color RGBA resolution

private extension Color {
    /// Resolves the sRGB components for color interpolation via `UIColor`, matching the
    /// existing decomposition pattern in Theme.swift (`UIColor(self).getRed(...)`).
    func resolveRGBA() -> (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }
}

#if DEBUG
#Preview("CelestialBackdrop") {
    ZStack {
        MeridianColors.background.ignoresSafeArea()
        CelestialBackdrop(intensity: 0.8)
    }
}
#endif
