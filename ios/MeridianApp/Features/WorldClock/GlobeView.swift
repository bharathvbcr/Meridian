//  GlobeView.swift
//  Meridian — iOS 27 / Swift 6
//
//  Ported from app/src/main/java/com/example/feature/worldclock/GlobeView.kt
//
//  A 3D-style globe (§5.2). On Android this is an orthographic AGSL sphere; on iOS we use
//  SceneKit with the day/night terminator driven by the SHARED subsolar point —
//  `SolarMath.subsolarPoint(for:)` — so the lit hemisphere matches the 2D map and reality
//  exactly (Android positions its shadow from the same subsolar math). Saved-zone markers
//  sit on the surface, tinted by day/night; a sun marker sits at the subsolar point; drag
//  to spin; slow auto-rotation when idle.
//
//  Textured styles shade the terminator with a `.surface` shader modifier that ports the
//  exact bright / night-mix math of EarthShader.metal `terminatorShade` (constant lighting
//  model — no SceneKit light shapes the textured globe, matching Android where the AGSL
//  shader alone does the shading). The flat Performance sphere keeps the cheap phong +
//  directional-light path: the sun light points along -Z by default, so it's rotated by
//  (yaw = subsolarLongitude, pitch = -declination) toward the subsolar coordinate as the
//  globe sits at its identity orientation (lon 0 facing +Z, north up).

import SwiftUI
import SceneKit

// MARK: - DayNightGlobe

struct DayNightGlobe: UIViewRepresentable {

    /// IANA timezone IDs to mark with a pin.
    var zoneIds: [String]
    /// Shared display instant (scrub-aware) used to position the sun + day/night line.
    var effectiveDate: Date
    /// Map style — `.performance` shades a flatter, cheaper globe (parity with Android,
    /// which skips the texture + per-pixel extras there).
    var style: MapStyle = .vector
    /// The home zone's id + the device's vetted location: when both are set, the home pin
    /// marks the user's actual location instead of the zone's representative city.
    var homeZoneId: String? = nil
    var homeLocation: GeoPoint? = nil

    // MARK: Constants

    private enum GlobeConst {
        static let radius: CGFloat = 1.0
        static let markerRadius: CGFloat = 0.038
        static let sunMarkerRadius: CGFloat = 0.03   // Android draws the sun at r·0.03
        static let autoRotationDuration: TimeInterval = 120
        static let panSensitivity: Float = 0.005
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        var lastPanLocation: CGPoint = .zero
        var userYaw: Float = 0
        var userPitch: Float = 0
        weak var globeNode: SCNNode?
        weak var sceneView: SCNView?

        /// Live Reduce-Motion state; also observed so a mid-session toggle takes effect
        /// without re-creating the view (matches how the SwiftUI side honors Motion).
        /// The `Coordinator` is `@MainActor`-isolated (created via `makeCoordinator` on
        /// the main actor), so reading this main-actor accessibility flag here is safe.
        private(set) var reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled

        override init() {
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(reduceMotionDidChange),
                name: UIAccessibility.reduceMotionStatusDidChangeNotification,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func reduceMotionDidChange() {
            reduceMotion = UIAccessibility.isReduceMotionEnabled
            guard let node = globeNode else { return }
            if reduceMotion {
                // Freeze the perpetual auto-spin and settle every marker halo at rest scale.
                node.removeAction(forKey: "autoRotate")
                stopHaloPulses(on: node)
            } else {
                startHaloPulses(on: node)
                resumeAutoRotation(node: node)
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let node = globeNode else { return }
            let location = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began:
                node.removeAction(forKey: "autoRotate")
                lastPanLocation = location
            case .changed:
                let dx = Float(location.x - lastPanLocation.x)
                let dy = Float(location.y - lastPanLocation.y)
                lastPanLocation = location
                userYaw += dx * GlobeConst.panSensitivity
                userPitch = max(-.pi / 2, min(.pi / 2, userPitch + dy * GlobeConst.panSensitivity))
                let pitchQ = simd_quatf(angle: userPitch, axis: SIMD3<Float>(1, 0, 0))
                let yawQ   = simd_quatf(angle: userYaw,   axis: SIMD3<Float>(0, 1, 0))
                node.simdOrientation = yawQ * pitchQ
            case .ended, .cancelled:
                // Reduce Motion keeps the globe static (still drag-spinnable) rather than
                // auto-rotating.
                if !reduceMotion { resumeAutoRotation(node: node) }
            default:
                break
            }
        }

        func resumeAutoRotation(node: SCNNode) {
            guard !reduceMotion else { return }
            let rotation = SCNAction.repeatForever(
                SCNAction.rotateBy(x: 0, y: CGFloat(2 * Float.pi), z: 0,
                                   duration: GlobeConst.autoRotationDuration)
            )
            node.runAction(rotation, forKey: "autoRotate")
        }

        /// Restart the halo pulse on every marker (used when Reduce Motion turns back off).
        func startHaloPulses(on globeNode: SCNNode) {
            for marker in globeNode.childNodes where marker.name == "zoneMarker" {
                for halo in marker.childNodes {
                    halo.runAction(DayNightGlobe.haloPulseAction(), forKey: "haloPulse")
                }
            }
        }

        /// Stop the halo pulse and reset each halo to rest scale so markers render at rest.
        func stopHaloPulses(on globeNode: SCNNode) {
            for marker in globeNode.childNodes where marker.name == "zoneMarker" {
                for halo in marker.childNodes {
                    halo.removeAction(forKey: "haloPulse")
                    halo.scale = SCNVector3(1, 1, 1)
                }
            }
        }
    }

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = .clear
        sceneView.antialiasingMode = .multisampling4X
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = false

        let scene = SCNScene()
        sceneView.scene = scene

        // Camera.
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 2.6)
        scene.rootNode.addChildNode(cameraNode)

        // Ambient fill so the dark side isn't pure black (Android keeps a 0.30 night floor).
        let ambientNode = SCNNode()
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(white: 0.12, alpha: 1)
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Globe.
        let globeNode = buildGlobeNode()
        scene.rootNode.addChildNode(globeNode)
        context.coordinator.globeNode = globeNode

        // Sun (directional) light positioned by the subsolar point.
        let sunNode = buildSunNode(for: effectiveDate)
        scene.rootNode.addChildNode(sunNode)

        // Atmosphere halo billboard behind the globe.
        scene.rootNode.addChildNode(buildAtmosphereNode())

        // Bright subsolar sun marker — a child of the globe so it spins with the surface,
        // exactly like the zone pins (Android projects it with the same centerLng math).
        globeNode.addChildNode(buildSunMarkerNode(for: effectiveDate))

        // Markers. Reduce Motion renders halos at rest (no perpetual pulse).
        rebuildMarkers(on: globeNode, pulsing: !context.coordinator.reduceMotion)

        // Reduce Motion leaves the globe static (still drag-spinnable); otherwise it drifts.
        context.coordinator.sceneView = sceneView
        if !context.coordinator.reduceMotion {
            context.coordinator.resumeAutoRotation(node: globeNode)
        }

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        sceneView.addGestureRecognizer(pan)

        // The 3D scene isn't VoiceOver-traversable, so expose it as a single element with a
        // text summary that mirrors the 2D DayNightMap's descriptive label.
        sceneView.isAccessibilityElement = true
        sceneView.accessibilityTraits = .image
        sceneView.accessibilityLabel = Self.accessibilityDescription(for: effectiveDate)
        sceneView.accessibilityHint = "Drag to rotate"

        return sceneView
    }

    func updateUIView(_ sceneView: SCNView, context: Context) {
        guard let scene = sceneView.scene else { return }

        // Announce the scrubbed instant so VoiceOver users hear the day/night state change.
        sceneView.accessibilityLabel = Self.accessibilityDescription(for: effectiveDate)

        let reduceMotion = context.coordinator.reduceMotion

        // Spring the terminator sweep so scrubbing glides frame-to-frame instead of snapping,
        // matching the app's spring-physics feel. Reduce Motion assigns instantly.
        SCNTransaction.begin()
        SCNTransaction.animationDuration = reduceMotion ? 0 : 0.3
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        if let sunNode = scene.rootNode.childNode(withName: "sunLight", recursively: false) {
            let (yaw, pitch) = sunAngles(for: effectiveDate)
            sunNode.eulerAngles = SCNVector3(x: pitch, y: yaw, z: 0)
        }

        guard let globeNode = scene.rootNode.childNode(withName: "globe", recursively: false) else {
            SCNTransaction.commit()
            return
        }

        // Terminator shading + sun marker track the scrubbed instant.
        if let material = globeNode.geometry?.firstMaterial, material.shaderModifiers != nil {
            material.setValue(
                NSValue(scnVector3: Self.subsolarDirection(for: effectiveDate)),
                forKey: "sunDirection"
            )
        }
        if let sunMarker = globeNode.childNode(withName: "sunMarker", recursively: false) {
            let sub = SolarMath.subsolarPoint(for: effectiveDate)
            sunMarker.position = Self.surfacePosition(
                lat: sub.latitude, lon: sub.longitude, lift: GlobeConst.sunMarkerRadius * 0.6
            )
        }

        SCNTransaction.commit()

        globeNode.childNodes
            .filter { $0.name == "zoneMarker" }
            .forEach { $0.removeFromParentNode() }
        rebuildMarkers(on: globeNode, pulsing: !reduceMotion)
    }

    // MARK: - Scene building

    private func buildGlobeNode() -> SCNNode {
        let sphere = SCNSphere(radius: GlobeConst.radius)
        sphere.segmentCount = 96

        let material = SCNMaterial()
        if style != .performance, let tex = Self.worldMapImage {
            // Photographic Earth wrapped on the sphere (textured styles). Android's AGSL
            // shader does ALL day/night shading itself, so here the lighting model is
            // constant and the surface modifier below ports the exact terminator mix from
            // EarthShader.metal — the directional sun light no longer shades this path.
            material.diffuse.contents = tex
            material.diffuse.wrapS = .repeat
            material.lightingModel = .constant
            material.shaderModifiers = [.surface: Self.terminatorSurfaceModifier]
            material.setValue(
                NSValue(scnVector3: Self.subsolarDirection(for: effectiveDate)),
                forKey: "sunDirection"
            )
            // Deep-night tint #0B1020 (Android nightColor / DayNightMap.nightTint).
            material.setValue(
                NSValue(scnVector3: SCNVector3(0x0B / 255.0, 0x10 / 255.0, 0x20 / 255.0)),
                forKey: "nightTint"
            )
        } else {
            // Flat two-tone day surface (Performance / no-texture parity with Android
            // `uDay`) — keeps the cheap phong + directional-light terminator.
            material.diffuse.contents = UIColor(MeridianColors.primaryContainer)
            material.specular.contents = UIColor(red: 0.30, green: 0.62, blue: 0.85, alpha: 1)
            material.shininess = 16
            material.lightingModel = .phong
        }
        material.emission.contents = UIColor(red: 0.01, green: 0.03, blue: 0.09, alpha: 1)
        sphere.materials = [material]

        let node = SCNNode(geometry: sphere)
        node.name = "globe"
        return node
    }

    /// SceneKit `.surface` modifier porting EarthShader.metal `terminatorShade` (:86-104,
    /// same constants): dayF = clamp((cz + 0.20) / 0.20), bright = 0.30 + 0.70·dayF, then a
    /// (1 − dayF)·0.6 mix toward the deep-night tint. cz is taken against the MODEL-space
    /// normal — on a unit sphere that IS the surface point's geographic direction — so the
    /// terminator sticks to the surface while the globe spins/auto-rotates without needing
    /// per-frame uniform updates (Android shades from geographic lat/lng the same way).
    private static let terminatorSurfaceModifier = """
    #pragma arguments
    float3 sunDirection;
    float3 nightTint;
    #pragma body
    float3 geoNormal = normalize((scn_node.inverseModelViewTransform * float4(_surface.normal, 0.0)).xyz);
    float cz = dot(geoNormal, sunDirection);
    float dayF = clamp((cz + 0.20) / 0.20, 0.0, 1.0);
    float bright = 0.30 + 0.70 * dayF;
    float nm = (1.0 - dayF) * 0.6;
    _surface.diffuse.rgb = _surface.diffuse.rgb * bright * (1.0 - nm) + nightTint * nm;
    """

    /// Unit vector toward the subsolar point in the globe's model (geographic) basis —
    /// the same lon-0-facing-+Z convention as `surfacePosition`.
    private static func subsolarDirection(for date: Date) -> SCNVector3 {
        let sub = SolarMath.subsolarPoint(for: date)
        let lat = sub.latitude * .pi / 180
        let lon = sub.longitude * .pi / 180
        return SCNVector3(
            Float(cos(lat) * sin(lon)),
            Float(sin(lat)),
            Float(cos(lat) * cos(lon))
        )
    }

    private func buildAtmosphereNode() -> SCNNode {
        let sphere = SCNSphere(radius: GlobeConst.radius * 1.08)
        sphere.segmentCount = 48
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(MeridianColors.primary).withAlphaComponent(0.18)
        mat.emission.contents = UIColor(MeridianColors.primary).withAlphaComponent(0.18)
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.transparencyMode = .rgbZero
        sphere.materials = [mat]
        let node = SCNNode(geometry: sphere)
        node.name = "atmosphere"
        return node
    }

    private func buildSunNode(for date: Date) -> SCNNode {
        let light = SCNLight()
        light.type = .directional
        light.color = UIColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1)
        light.intensity = 1100
        let node = SCNNode()
        node.light = light
        node.name = "sunLight"
        let (yaw, pitch) = sunAngles(for: date)
        node.eulerAngles = SCNVector3(x: pitch, y: yaw, z: 0)
        return node
    }

    /// Sun Euler angles from the SHARED subsolar point. With lon 0 facing +Z and north up,
    /// a point at (lat, lng) sits at direction (cosLat·sinLng, sinLat, cosLat·cosLng). A
    /// directional light points along its local -Z; rotating it by yaw = lng about Y and
    /// pitch = -lat about X aims the lit hemisphere at the subsolar coordinate.
    private func sunAngles(for date: Date) -> (yaw: Float, pitch: Float) {
        let sub = SolarMath.subsolarPoint(for: date)
        let yaw = Float(sub.longitude * .pi / 180.0)
        let pitch = Float(-sub.latitude * .pi / 180.0)
        return (yaw, pitch)
    }

    private func rebuildMarkers(on globeNode: SCNNode, pulsing: Bool = true) {
        for tzId in zoneIds {
            // `at:` keeps the DST-correct offset fallback (Android passes the instant too).
            // The home zone pins at the device's vetted location when the caller has one.
            let coord = (tzId == homeZoneId ? homeLocation : nil)
                ?? ZoneGeo.coordinate(for: tzId, at: effectiveDate)
            let lit = SolarMath.cosSolarZenith(
                latitude: coord.latitude, longitude: coord.longitude, date: effectiveDate
            ) > 0
            let marker = buildMarkerNode(
                lat: coord.latitude, lon: coord.longitude, lit: lit, pulsing: pulsing
            )
            globeNode.addChildNode(marker)
        }
    }

    /// Surface position for (lat, lon) — lon 0 facing +Z, north up — lifted slightly off
    /// the sphere so markers don't z-fight with the surface.
    private static func surfacePosition(lat: Double, lon: Double, lift: CGFloat) -> SCNVector3 {
        let r = Float(GlobeConst.radius + lift)
        let latRad = Float(lat * .pi / 180)
        let lonRad = Float(lon * .pi / 180)
        return SCNVector3(
            x: r * cos(latRad) * sin(lonRad),
            y: r * sin(latRad),
            z: r * cos(latRad) * cos(lonRad)
        )
    }

    private func buildMarkerNode(lat: Double, lon: Double, lit: Bool, pulsing: Bool = true) -> SCNNode {
        // Day pins keep the primary accent; night pins dim to onSurface at 0.55 — the same
        // tinting the 2D map applies to its pins (Android pinColor / pinNightColor).
        let pinColor = lit
            ? UIColor(MeridianColors.primary)
            : UIColor(MeridianColors.onSurface).withAlphaComponent(0.55)

        let sphere = SCNSphere(radius: GlobeConst.markerRadius)
        sphere.segmentCount = 12
        let mat = SCNMaterial()
        mat.diffuse.contents = pinColor
        mat.emission.contents = pinColor
        mat.lightingModel = .constant
        sphere.materials = [mat]

        let halo = SCNSphere(radius: GlobeConst.markerRadius * 1.8)
        halo.segmentCount = 12
        let haloMat = SCNMaterial()
        haloMat.diffuse.contents = pinColor.withAlphaComponent(0.25)
        haloMat.emission.contents = pinColor.withAlphaComponent(0.25)
        haloMat.lightingModel = .constant
        haloMat.isDoubleSided = true
        haloMat.transparencyMode = .rgbZero
        halo.materials = [haloMat]
        let haloNode = SCNNode(geometry: halo)

        let markerNode = SCNNode(geometry: sphere)
        markerNode.name = "zoneMarker"
        markerNode.position = Self.surfacePosition(
            lat: lat, lon: lon, lift: GlobeConst.markerRadius * 0.6
        )
        markerNode.addChildNode(haloNode)

        // Reduce Motion renders the halo at rest scale; otherwise it breathes.
        if pulsing {
            haloNode.runAction(Self.haloPulseAction(), forKey: "haloPulse")
        }

        return markerNode
    }

    /// The perpetual halo breathe — extracted so the Coordinator can start/stop it on a live
    /// Reduce-Motion toggle without re-creating the markers.
    fileprivate static func haloPulseAction() -> SCNAction {
        let pulseIn  = SCNAction.scale(to: 0.8, duration: 1.0)
        let pulseOut = SCNAction.scale(to: 1.2, duration: 1.0)
        pulseIn.timingMode = .easeInEaseOut
        pulseOut.timingMode = .easeInEaseOut
        return .repeatForever(.sequence([pulseOut, pulseIn]))
    }

    /// A VoiceOver summary mirroring the 2D `DayNightMap`'s descriptive label word-for-word
    /// (globe vs. map): the 3D scene isn't traversable, so the sun's subsolar position — and
    /// hence the day/night state — is summarized in text and refreshed as time is scrubbed.
    private static func accessibilityDescription(for date: Date) -> String {
        let sub = SolarMath.subsolarPoint(for: date)
        return "World day and night globe. Sun is overhead near latitude "
            + "\(Int(sub.latitude)), longitude \(Int(sub.longitude)) degrees."
    }

    /// Bright emissive sun dot at the subsolar surface point (Android draws it at r·0.03).
    /// SceneKit's depth buffer hides it behind the sphere when the point faces away.
    private func buildSunMarkerNode(for date: Date) -> SCNNode {
        let sphere = SCNSphere(radius: GlobeConst.sunMarkerRadius)
        sphere.segmentCount = 16
        let mat = SCNMaterial()
        // The app's sun token (`daylightGlow`) — same warm color as the 2D map's sun marker.
        let warm = UIColor(MeridianColors.daylightGlow)
        mat.diffuse.contents = warm
        mat.emission.contents = warm
        mat.lightingModel = .constant
        sphere.materials = [mat]

        let node = SCNNode(geometry: sphere)
        node.name = "sunMarker"
        let sub = SolarMath.subsolarPoint(for: date)
        node.position = Self.surfacePosition(
            lat: sub.latitude, lon: sub.longitude, lift: GlobeConst.sunMarkerRadius * 0.6
        )
        return node
    }

    /// Photographic Earth texture, loaded once. `nil` keeps the globe on the flat two-tone path.
    private static let worldMapImage: UIImage? = UIImage(named: "world_map")
}

// MARK: - Preview

#if DEBUG
#Preview("DayNightGlobe") {
    ZStack {
        MeridianColors.background.ignoresSafeArea()
        DayNightGlobe(
            zoneIds: ["America/New_York", "Europe/London", "Asia/Tokyo", "Australia/Sydney"],
            effectiveDate: Date()
        )
        .frame(height: 300)
    }
}
#endif
