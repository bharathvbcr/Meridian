//  GlobeView.swift
//  Meridian — iOS 27 / Swift 6
//
//  Ported from app/src/main/java/com/example/feature/worldclock/GlobeView.kt
//
//  A 3D-style globe (§5.2). On Android this is an orthographic AGSL sphere; on iOS we use
//  SceneKit (hardware-accelerated, free atmosphere/lighting) with the day/night terminator
//  driven by the SHARED subsolar point — `SolarMath.subsolarPoint(for:)` — so the lit
//  hemisphere matches the 2D map and reality exactly (Android positions its shadow from the
//  same subsolar math). Saved-zone markers sit on the surface; drag to spin; slow
//  auto-rotation when idle.
//
//  The directional sun light is oriented to the subsolar point: a directional light points
//  along -Z by default, so we rotate it by (yaw = subsolarLongitude, pitch = -declination)
//  to make the lit hemisphere centre on the subsolar coordinate as the globe sits at its
//  identity orientation (lon 0 facing +Z, north up).

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

    // MARK: Constants

    private enum GlobeConst {
        static let radius: CGFloat = 1.0
        static let markerRadius: CGFloat = 0.038
        static let autoRotationDuration: TimeInterval = 120
        static let panSensitivity: Float = 0.005
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var lastPanLocation: CGPoint = .zero
        var userYaw: Float = 0
        var userPitch: Float = 0
        weak var globeNode: SCNNode?

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
                resumeAutoRotation(node: node)
            default:
                break
            }
        }

        func resumeAutoRotation(node: SCNNode) {
            let rotation = SCNAction.repeatForever(
                SCNAction.rotateBy(x: 0, y: CGFloat(2 * Float.pi), z: 0,
                                   duration: GlobeConst.autoRotationDuration)
            )
            node.runAction(rotation, forKey: "autoRotate")
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

        // Markers.
        rebuildMarkers(on: globeNode)

        context.coordinator.resumeAutoRotation(node: globeNode)

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        sceneView.addGestureRecognizer(pan)

        return sceneView
    }

    func updateUIView(_ sceneView: SCNView, context: Context) {
        guard let scene = sceneView.scene else { return }

        if let sunNode = scene.rootNode.childNode(withName: "sunLight", recursively: false) {
            let (yaw, pitch) = sunAngles(for: effectiveDate)
            sunNode.eulerAngles = SCNVector3(x: pitch, y: yaw, z: 0)
        }

        guard let globeNode = scene.rootNode.childNode(withName: "globe", recursively: false) else { return }
        globeNode.childNodes
            .filter { $0.name == "zoneMarker" }
            .forEach { $0.removeFromParentNode() }
        rebuildMarkers(on: globeNode)
    }

    // MARK: - Scene building

    private func buildGlobeNode() -> SCNNode {
        let sphere = SCNSphere(radius: GlobeConst.radius)
        sphere.segmentCount = 96

        let material = SCNMaterial()
        if style != .performance, let tex = Self.worldMapImage {
            // Photographic Earth wrapped on the sphere (textured styles).
            material.diffuse.contents = tex
            material.diffuse.wrapS = .repeat
            material.specular.contents = UIColor(red: 0.30, green: 0.62, blue: 0.85, alpha: 1)
            material.shininess = 24
        } else {
            // Flat two-tone day surface (Performance / no-texture parity with Android `uDay`).
            material.diffuse.contents = UIColor(MeridianColors.primaryContainer)
            material.specular.contents = UIColor(red: 0.30, green: 0.62, blue: 0.85, alpha: 1)
            material.shininess = 16
        }
        material.lightingModel = .phong
        material.emission.contents = UIColor(red: 0.01, green: 0.03, blue: 0.09, alpha: 1)
        sphere.materials = [material]

        let node = SCNNode(geometry: sphere)
        node.name = "globe"
        return node
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

    private func rebuildMarkers(on globeNode: SCNNode) {
        for tzId in zoneIds {
            let coord = ZoneGeo.coordinate(for: tzId)
            let marker = buildMarkerNode(lat: coord.latitude, lon: coord.longitude)
            globeNode.addChildNode(marker)
        }
    }

    private func buildMarkerNode(lat: Double, lon: Double) -> SCNNode {
        let r = Float(GlobeConst.radius + Double(GlobeConst.markerRadius) * 0.6)
        let latRad = Float(lat * .pi / 180)
        let lonRad = Float(lon * .pi / 180)
        let x = r * cos(latRad) * sin(lonRad)
        let y = r * sin(latRad)
        let z = r * cos(latRad) * cos(lonRad)

        let sphere = SCNSphere(radius: GlobeConst.markerRadius)
        sphere.segmentCount = 12
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(MeridianColors.primary)
        mat.emission.contents = UIColor(MeridianColors.primary)
        mat.lightingModel = .constant
        sphere.materials = [mat]

        let halo = SCNSphere(radius: GlobeConst.markerRadius * 1.8)
        halo.segmentCount = 12
        let haloMat = SCNMaterial()
        haloMat.diffuse.contents = UIColor(MeridianColors.primary).withAlphaComponent(0.25)
        haloMat.emission.contents = UIColor(MeridianColors.primary).withAlphaComponent(0.25)
        haloMat.lightingModel = .constant
        haloMat.isDoubleSided = true
        haloMat.transparencyMode = .rgbZero
        halo.materials = [haloMat]
        let haloNode = SCNNode(geometry: halo)

        let markerNode = SCNNode(geometry: sphere)
        markerNode.name = "zoneMarker"
        markerNode.position = SCNVector3(x: x, y: y, z: z)
        markerNode.addChildNode(haloNode)

        let pulseIn  = SCNAction.scale(to: 0.8, duration: 1.0)
        let pulseOut = SCNAction.scale(to: 1.2, duration: 1.0)
        pulseIn.timingMode = .easeInEaseOut
        pulseOut.timingMode = .easeInEaseOut
        haloNode.runAction(.repeatForever(.sequence([pulseOut, pulseIn])))

        return markerNode
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
