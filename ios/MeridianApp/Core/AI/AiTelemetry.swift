// AiTelemetry.swift
// Meridian — iOS 27 / Swift 6
//
// Privacy-safe debug telemetry — logs inference path + latency only.

import Foundation
import os

enum AiTelemetry {
    private static let log = Logger(subsystem: "com.meridian.app", category: "AI")

    static func logInference(path: String, source: InferenceSource, latencyMs: Int64) {
        log.debug("path=\(path, privacy: .public) source=\(source.rawValue, privacy: .public) latencyMs=\(latencyMs)")
    }
}
