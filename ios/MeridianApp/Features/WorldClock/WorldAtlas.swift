//  WorldAtlas.swift
//  Meridian — iOS 27 / Swift 6
//
//  Ported from app/src/main/java/com/example/feature/worldclock/WorldAtlas.kt
//
//  Decodes the bundled `countries-110m.json` world-atlas TopoJSON for the flat Vector
//  map style (§5.2). Native equivalent of `topojson-client` + `d3.geoEquirectangular()`:
//  arcs are delta-decoded and de-quantized to lng/lat with the topology's `transform`,
//  then projected with the same equirectangular mapping DayNightMap uses — emitted in
//  unit space (u, v ∈ [0,1]) so the caller can fit the cached paths to any size with one
//  transform instead of re-projecting per frame.
//
//  Two paths come out: `land` (filled continents, from the topology's `land` object) and
//  `borders` (every arc drawn once — coastlines + interior country borders, de-duplicated
//  because a topology stores each shared boundary as a single arc).
//
//  No d3 / WebView: the projection is one linear formula and the asset is ~108 KB, decoded
//  once off the main thread. `WorldGeometry` is `Sendable` (CGPath is sendable; the unit-space
//  point arrays are value types) so it can cross the actor boundary back to the view.

import Foundation
import SwiftUI

/// Land fill + the country/coastline border mesh, both in unit space (u, v ∈ [0,1]).
/// The paths are immutable CGPaths, safe to hand back to the main actor.
struct WorldGeometry: Sendable {
    let land: Path
    let borders: Path
}

/// Offline TopoJSON → unit-space `Path` decoder for the Vector map style.
enum WorldAtlas {

    /// The decoded geometry, cached after the first successful load. Access is funnelled
    /// through `load()` which is `@MainActor` only for the cache check; the heavy parse runs
    /// on a detached task. Returns `nil` if the asset is missing or malformed.
    private static let cache = AtlasCache()

    /// Decodes (or returns the cached) world geometry. Safe to call repeatedly; the JSON is
    /// parsed at most once. Runs the parse off the main thread.
    static func load() async -> WorldGeometry? {
        await cache.load()
    }

    // MARK: - Parsing

    /// Parses `countries-110m.json` from the main bundle into unit-space paths.
    fileprivate static func parse() -> WorldGeometry? {
        guard let url = Bundle.main.url(forResource: "countries-110m", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let transform = root["transform"] as? [String: Any],
              let scale = transform["scale"] as? [Double], scale.count >= 2,
              let translate = transform["translate"] as? [Double], translate.count >= 2,
              let arcsJson = root["arcs"] as? [[[Double]]],
              let objects = root["objects"] as? [String: Any]
        else { return nil }

        let sx = scale[0], sy = scale[1]
        let tx = translate[0], ty = translate[1]

        // Decode every arc once: delta-accumulate the quantized integers, de-quantize to
        // lng/lat, then project to unit space. `arcsUv[i]` is arc i as unit-space points.
        var arcsUv: [[CGPoint]] = []
        arcsUv.reserveCapacity(arcsJson.count)
        for arc in arcsJson {
            var x = 0.0
            var y = 0.0
            var pts: [CGPoint] = []
            pts.reserveCapacity(arc.count)
            for p in arc where p.count >= 2 {
                x += p[0]
                y += p[1]
                let lng = x * sx + tx
                let lat = y * sy + ty
                pts.append(
                    CGPoint(
                        x: (lng + 180.0) / 360.0,
                        y: (90.0 - lat) / 180.0
                    )
                )
            }
            arcsUv.append(pts)
        }

        // Land fill — the topology's `land` object (continents merged, no interior lines).
        var land = Path()
        if let landObj = objects["land"] as? [String: Any],
           let geometries = landObj["geometries"] as? [[String: Any]] {
            for geom in geometries {
                addGeometry(&land, geom: geom, arcsUv: arcsUv)
            }
        }

        // Border mesh — every arc once. Coastlines + shared country boundaries, de-duplicated
        // for free because the topology stores each boundary as exactly one arc.
        var borders = Path()
        for arc in arcsUv where !arc.isEmpty {
            borders.move(to: arc[0])
            for m in 1..<arc.count {
                borders.addLine(to: arc[m])
            }
        }

        return WorldGeometry(land: land, borders: borders)
    }

    /// Add one geometry's fill: Polygon (rings) or MultiPolygon (polygons → rings).
    private static func addGeometry(_ path: inout Path, geom: [String: Any], arcsUv: [[CGPoint]]) {
        guard let type = geom["type"] as? String else { return }
        switch type {
        case "Polygon":
            if let rings = geom["arcs"] as? [[Int]] {
                for ring in rings { addRing(&path, ring: ring, arcsUv: arcsUv) }
            }
        case "MultiPolygon":
            if let polygons = geom["arcs"] as? [[[Int]]] {
                for rings in polygons {
                    for ring in rings { addRing(&path, ring: ring, arcsUv: arcsUv) }
                }
            }
        default:
            break
        }
    }

    /// Stitch a ring's arcs (negative index ⇒ that arc reversed) into one closed sub-path.
    private static func addRing(_ path: inout Path, ring: [Int], arcsUv: [[CGPoint]]) {
        var started = false
        for idx in ring {
            // TopoJSON: a negative index references arc `~idx` traversed in reverse.
            let arc: [CGPoint]
            if idx >= 0 {
                guard idx < arcsUv.count else { continue }
                arc = arcsUv[idx]
            } else {
                let real = ~idx
                guard real < arcsUv.count else { continue }
                arc = arcsUv[real].reversed()
            }
            for (m, pt) in arc.enumerated() {
                // Skip the first point of every arc after the first: it duplicates the
                // previous arc's last point (TopoJSON arcs share endpoints).
                if m == 0 && started { continue }
                if !started {
                    path.move(to: pt)
                    started = true
                } else {
                    path.addLine(to: pt)
                }
            }
        }
        if started { path.closeSubpath() }
    }
}

// MARK: - One-shot async cache

/// Serialises the (idempotent) parse so concurrent callers share one decode.
private actor AtlasCache {
    private var cached: WorldGeometry?
    private var didAttempt = false

    func load() async -> WorldGeometry? {
        if didAttempt { return cached }
        didAttempt = true
        // Hop off the actor's executor for the CPU-bound parse.
        let parsed = await Task.detached(priority: .userInitiated) {
            WorldAtlas.parse()
        }.value
        cached = parsed
        return parsed
    }
}
