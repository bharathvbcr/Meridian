// AiResult.swift
// Meridian — iOS 27 / Swift 6
//
// The result of running the Meridian assistant. Ported from Android's
// `GeminiRepository.AiResult` (core/ai/GeminiRepository.kt).
//
// `onDevice` reflects where inference actually ran — true for on-device
// Foundation Models, false for the Gemini cloud fallback or the local
// rules engine.

import Foundation

// MARK: - AiResult

/// Discriminated result of a single assistant turn.
///
/// Mirrors the Android `sealed class AiResult`:
///  - `.success` — a plain text answer.
///  - `.scheduled` — the assistant resolved a scheduling request into a concrete
///    `PlannedTask` (the model never computes the timestamp; `ScheduleParser`
///    resolves it locally).
///  - `.error` — the turn failed; the associated string is a human-readable message.
///
/// - Note: This type is intentionally **not** `Sendable`. The `.scheduled` case
///   carries a `PlannedTask`, which is a SwiftData `@Model final class` and thus
///   not `Sendable`; a `Sendable` enum with a non-`Sendable` payload fails to
///   compile under `SWIFT_STRICT_CONCURRENCY=complete`. `AiResult` never crosses
///   an isolation boundary: it is produced by `AiAssistant` (`@MainActor`) and
///   consumed by `MainViewModel` (`@MainActor`), so main-actor isolation already
///   guarantees the safety that `Sendable` would otherwise provide.
enum AiResult {
    case success(text: String, onDevice: Bool)
    case scheduled(task: PlannedTask, onDevice: Bool)
    case error(String)
}

// MARK: - AiEngine

/// Which inference engine the user prefers, chosen by `MeridianSettings.aiEngine`.
///
/// Default is `.onDevice` (Foundation Models) with a rules fallback when the
/// on-device model is unavailable. `.cloud` routes to Gemini (network + API key
/// required — only the cloud branch ever touches the network).
enum AiEngine: String, CaseIterable, Codable, Sendable {
    case onDevice
    case cloud
}
