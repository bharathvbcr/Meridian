//  DayNightMap.swift
//  Meridian — iOS 27 / Swift 6
//
//  Ported from app/src/main/java/com/example/feature/worldclock/DayNightMap.kt
//
//  A 2D equirectangular day/night map with a live terminator (§5.2). Reads the shared
//  `instant` (driven by the scrubber), so dragging time sweeps the night region and the
//  subsolar "sun" across the globe, and pins each saved zone at its coordinate (offline).
//
//  The terminator is a GPU `.colorEffect` (EarthShader.metal `nightTerminator`) over the
//  base layer — one draw, no per-frame CPU rasterisation — matching Android's single
//  bilinear blit of the cached night mask. Vector style (the default) draws the bundled
//  country outlines over the frosted glass surface; textured styles draw the photographic
//  Earth and shade it with the same terminator.

import SwiftUI

// MARK: - DayNightMap

struct DayNightMap: View {

    /// Shared display instant (scrub-aware) used to place the terminator + pins.
    let instant: Date
    /// Saved zones to pin on the map.
    let zoneIds: [String]
    /// Selected map rendering style (default `.vector`).
    var style: MapStyle = .vector
    /// The home zone's id + the device's vetted location: when both are set, the home pin
    /// marks the user's actual location instead of the zone's representative city.
    var homeZoneId: String? = nil
    var homeLocation: GeoPoint? = nil

    /// Observes the shared atlas so the vector outlines appear once the TopoJSON finishes
    /// parsing on first launch.
    @StateObject private var atlas = AtlasHolder.shared

    /// Honour the system Reduce Motion setting when cross-fading the map layers in.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The single semantic night-surface token, shared with `GlobeView` (whose SceneKit
    /// `nightTint` material value is documented to mirror this value). Both the 2D map and the
    /// 3D globe shade their night side with the SAME deep-night colour so the day/night surface
    /// stays in parity if the palette shifts — matching Android's `NIGHT_RGB = 0x0B1020`.
    /// Kept named (rather than a raw literal) so it reads as a token, not a duplicated hex.
    static let nightTint = Color(red: 0x0B / 255.0, green: 0x10 / 255.0, blue: 0x20 / 255.0)

    /// Flat ocean shown behind the textured styles when the photographic Earth asset is
    /// missing — the deep-space blue that reads as "sea" (Android `Color(0xFF0B2A52)`).
    static let oceanFallback = Color(red: 0x0B / 255.0, green: 0x2A / 255.0, blue: 0x52 / 255.0)

    /// Shared corner radius for the map card and its glass background (design token, medium).
    /// `fileprivate` so `VectorGlassBackground` in this file uses the SAME radius as the clip.
    fileprivate static let cardCornerRadius = MeridianRadius.medium.rawValue

    private var isVector: Bool { style == .vector }

    /// Subsolar point for the current instant (drives the terminator + sun marker).
    private var subsolar: GeoPoint {
        SolarMath.subsolarPoint(for: instant)
    }

    /// VoiceOver description for the map surface. Reflects the loading state on the vector
    /// style so the bare frosted surface isn't announced as a finished map on first launch.
    private var mapAccessibilityLabel: String {
        if isVector && atlas.geometry == nil {
            return "World day and night map, loading."
        }
        return "World day and night map. Sun is overhead near latitude "
            + "\(Int(subsolar.latitude)), longitude \(Int(subsolar.longitude)) degrees."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MeridianSpacing.sm.rawValue) {
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    // Base surface + terminator.
                    if isVector {
                        vectorMap(size: size)
                    } else {
                        texturedMap(size: size)
                    }

                    // Subsolar sun marker + zone pins as a crisp vector overlay.
                    overlayCanvas(size: size)
                }
                .compositingGroup()
                // Cross-fade the placeholder → outlines swap when the atlas resolves. Spring
                // physics per the design language; no animation under Reduce Motion.
                .animation(
                    reduceMotion ? nil : Motion.smooth(),
                    value: atlas.geometry != nil
                )
            }
            .aspectRatio(2, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous))
            .modifier(VectorGlassBackground(active: isVector))
            // Group the visualization into a single VoiceOver element with a static-image
            // trait so the decorative Canvas/shapes aren't announced piecemeal. While the
            // vector atlas is still parsing, announce the loading state instead of the
            // (not-yet-drawn) map so the empty surface isn't read as a finished map.
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel(mapAccessibilityLabel)

            // Caption aligned to the card content: match the map's corner inset so its leading
            // edge sits on the same grid as the rounded surface above it, on the 4/8 rhythm.
            Text("Day / night updates as you scrub time. Lit pins are in daylight now.")
                .font(.bodyMedium)
                .foregroundStyle(MeridianColors.onSurface.opacity(0.6))
                .padding(.horizontal, MeridianSpacing.sm.rawValue)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { if isVector { atlas.warm() } }
        .onChange(of: style) { _, newStyle in
            if newStyle == .vector { atlas.warm() }
        }
    }

    // MARK: - Vector style (atlas outlines over glass)

    @ViewBuilder
    private func vectorMap(size: CGSize) -> some View {
        // Translucent land + borders so the celestial backdrop refracts through, then the
        // night terminator at reduced opacity (Android draws the overlay at alpha 0.7 here).
        if let geometry = atlas.geometry {
            WorldAtlasShape(geometry: geometry, component: .land)
                .fill(MeridianColors.primary.opacity(0.28))
            WorldAtlasShape(geometry: geometry, component: .borders)
                .stroke(Color.white.opacity(0.38), lineWidth: 1)
                // Fade the outlines in when the atlas lands so first launch doesn't "pop"
                // (spring only when the user hasn't asked for Reduce Motion).
                .transition(reduceMotion ? .identity : .opacity)
        } else {
            // Until the TopoJSON finishes parsing on first launch the frosted surface is bare,
            // which reads as broken/empty. Surface a lightweight loading affordance instead.
            atlasLoadingPlaceholder
        }

        nightOverlay(size: size, maxAlpha: 0.82 * 0.7)
    }

    /// Centered progress indicator shown over the frosted glass while `atlas.geometry`
    /// resolves. The loading state is announced via the map container's accessibility label
    /// (`mapAccessibilityLabel`), so the placeholder itself is hidden from VoiceOver to avoid
    /// a duplicate element.
    @ViewBuilder
    private var atlasLoadingPlaceholder: some View {
        VStack(spacing: MeridianSpacing.sm.rawValue) {
            ProgressView()
                .tint(MeridianColors.primary)
            Text("Loading map…")
                .font(.labelMedium)
                .foregroundStyle(MeridianColors.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(reduceMotion ? .identity : .opacity)
        .accessibilityHidden(true)
    }

    // MARK: - Textured style (photographic Earth + shaded terminator)

    @ViewBuilder
    private func texturedMap(size: CGSize) -> some View {
        // The photographic Earth ships as a bundle image ("world_map"); fall back to a flat
        // ocean if it is absent. The night side is shaded by the same terminator math.
        // Performance style samples at half resolution (Android inSampleSize = 2).
        Group {
            if let ui = style == .performance ? Self.worldMapImageHalf : Self.worldMapImage {
                Image(uiImage: ui)
                    .resizable()
                    .interpolation(.high)
            } else {
                Self.oceanFallback
            }
        }
        // Shade day/night across the surface (parity with the globe's bright/night-floor mix).
        .colorEffect(
            ShaderLibrary.bundle(.main).terminatorShade(
                .float2(Float(size.width), Float(size.height)),
                .float2(Float(subsolar.latitude), Float(subsolar.longitude)),
                .color(Self.nightTint)
            )
        )
    }

    // MARK: - Night overlay (GPU colorEffect)

    /// A transparent rectangle the size of the map, with the night/twilight tint applied by
    /// the `nightTerminator` shader. Used by the vector style where there is no opaque surface
    /// to shade in place.
    @ViewBuilder
    private func nightOverlay(size: CGSize, maxAlpha: Float) -> some View {
        // Fill opaque so the rect always rasterizes; `nightTerminator` ignores the source
        // `color` and emits its own premultiplied output (transparent on the day side), so the
        // fill colour is never visible.
        Rectangle()
            .fill(Color.black)
            .colorEffect(
                ShaderLibrary.bundle(.main).nightTerminator(
                    .float2(Float(size.width), Float(size.height)),
                    .float2(Float(subsolar.latitude), Float(subsolar.longitude)),
                    .color(Self.nightTint),
                    .float(maxAlpha)
                )
            )
            .allowsHitTesting(false)
    }

    // MARK: - Pins + sun marker

    private func overlayCanvas(size: CGSize) -> some View {
        Canvas { ctx, canvasSize in
            let sub = subsolar
            let h = canvasSize.height

            // Subsolar sun marker.
            let sunPos = Self.project(lat: sub.latitude, lng: sub.longitude, size: canvasSize)
            let sunColor = MeridianColors.daylightGlow
            ctx.fill(
                Path(ellipseIn: CGRect(x: sunPos.x - h * 0.06, y: sunPos.y - h * 0.06,
                                       width: h * 0.12, height: h * 0.12)),
                with: .color(sunColor.opacity(0.35))
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: sunPos.x - h * 0.025, y: sunPos.y - h * 0.025,
                                       width: h * 0.05, height: h * 0.05)),
                with: .color(sunColor)
            )

            // Zone pins, tinted by whether it is day or night there at `instant`. The home
            // zone pins at the device's vetted location when the caller has one.
            for id in zoneIds {
                let coord = (id == homeZoneId ? homeLocation : nil)
                    ?? ZoneGeo.coordinate(for: id, at: instant)
                let lit = SolarMath.cosSolarZenith(
                    latitude: coord.latitude, longitude: coord.longitude, date: instant
                ) > 0.0
                let pos = Self.project(lat: coord.latitude, lng: coord.longitude, size: canvasSize)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: pos.x - h * 0.018, y: pos.y - h * 0.018,
                                           width: h * 0.036, height: h * 0.036)),
                    with: .color(.white)
                )
                let pinColor = lit ? MeridianColors.primary : MeridianColors.onSurface.opacity(0.55)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: pos.x - h * 0.012, y: pos.y - h * 0.012,
                                           width: h * 0.024, height: h * 0.024)),
                    with: .color(pinColor)
                )
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    /// Equirectangular projection from geo degrees to canvas points (Android `project`).
    private static func project(lat: Double, lng: Double, size: CGSize) -> CGPoint {
        let x = (lng + 180.0) / 360.0 * size.width
        let y = (90.0 - lat) / 180.0 * size.height
        return CGPoint(x: x, y: y)
    }

    /// The photographic Earth texture, loaded once. `nil` when the asset is not bundled
    /// (the vector style — the default — never needs it).
    private static let worldMapImage: UIImage? = UIImage(named: "world_map")

    /// Half-pixel-size decode for the Performance style (Android decodes the same asset
    /// with `inSampleSize = 2`), computed lazily and cached so the quarter-memory copy is
    /// only ever materialised when that style is actually selected.
    private static let worldMapImageHalf: UIImage? = {
        guard let full = worldMapImage else { return nil }
        let pixelSize = CGSize(
            width: max(1, full.size.width * full.scale / 2),
            height: max(1, full.size.height * full.scale / 2)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1   // render in raw pixels, half the source's pixel dimensions
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            full.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }()
}

// MARK: - WorldAtlasShape

/// A `Shape` that draws one component of a parsed `WorldGeometry`, scaled from unit space
/// into the shape's rect. The geometry is injected so the shape re-evaluates when the atlas
/// finishes loading (the enclosing view observes `AtlasHolder`).
private struct WorldAtlasShape: Shape {
    enum Component { case land, borders }
    let geometry: WorldGeometry
    let component: Component

    func path(in rect: CGRect) -> Path {
        let unit = component == .land ? geometry.land : geometry.borders
        let transform = CGAffineTransform(scaleX: rect.width, y: rect.height)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return unit.applying(transform)
    }
}

// MARK: - VectorGlassBackground

/// For the vector style the map sits on the frosted glass surface so the backdrop refracts
/// through the translucent ocean. Other styles draw an opaque texture and need no glass.
private struct VectorGlassBackground: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        let radius = DayNightMap.cardCornerRadius
        if active {
            content
                .background {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(MeridianColors.cardTint)
                }
                .liquidGlass(
                    cornerRadius: radius,
                    tint: MeridianColors.primary
                )
        } else {
            content
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
    }
}

// MARK: - AtlasHolder

/// Main-actor holder so `WorldAtlasShape` (a value-type `Shape`) can read the parsed atlas.
/// `DayNightMap` triggers the async load; once it lands, an observation tick re-renders the
/// shapes. Kept tiny and main-actor-confined to satisfy strict concurrency.
@MainActor
final class AtlasHolder: ObservableObject {
    static let shared = AtlasHolder()
    @Published private(set) var geometry: WorldGeometry?

    private var loading = false

    func warm() {
        guard geometry == nil, !loading else { return }
        loading = true
        Task {
            let g = await WorldAtlas.load()
            self.geometry = g
            self.loading = false
        }
    }
}
