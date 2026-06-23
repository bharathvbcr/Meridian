// SettingsRepository.swift
// Meridian — iOS 27 / Swift 6
//
// Persists all user preferences to UserDefaults. Source of truth is the Android
// `SettingsRepository` (Kotlin / DataStore). Android stores glass opacity and
// backdrop intensity as integer percents (10...100); on iOS we keep them as
// normalized fractions in 0.10...1.0 — the canonical contract form — and migrate
// any legacy persisted values (raw 10...100 percents, or the deprecated
// GlassOpacityLevel enum names) on load.

import Foundation
import Observation

// HourCycle and MapStyle are defined in Models.swift (canonical).
// AiEngine is defined in Core/AiResult.swift (canonical); we persist it via a
// stable local string mapping so this file does not depend on its raw-value
// conformance.

// MARK: - Glass / backdrop bounds

/// Minimum normalized fraction for glass opacity / backdrop intensity.
let kMinGlassFraction = 0.10
/// Maximum normalized fraction for glass opacity / backdrop intensity.
let kMaxGlassFraction = 1.0
/// Default glass opacity (Android DEFAULT_GLASS_OPACITY_PERCENT = 60).
let kDefaultGlassOpacity = 0.60
/// Default backdrop intensity (Android DEFAULT_BACKDROP_INTENSITY = 55).
let kDefaultBackdropIntensity = 0.55

// MARK: - MeridianSettings

/// Value type that carries every user-configurable setting.
/// Equatable + Sendable so it can be freely diffed and passed across concurrency domains.
struct MeridianSettings: Equatable, Sendable {

    // MARK: Time display
    var hourCycle: HourCycle = .system

    // MARK: Glass / visual
    var glassEnabled: Bool         = true
    var reduceTransparency: Bool   = false
    var backdropEnabled: Bool      = true
    /// Backdrop glow strength as a normalized fraction in 0.10...1.0. Default = 0.55.
    var backdropIntensity: Double  = kDefaultBackdropIntensity
    /// Glass panel opacity as a normalized fraction in 0.10...1.0. Default = 0.60.
    var glassOpacity: Double       = kDefaultGlassOpacity

    // MARK: Map
    var mapStyle: MapStyle = .vector

    // MARK: Reminders
    /// Minutes before a planned task that its reminder fires. Android default = 10.
    var reminderLeadMinutes: Int = 10

    // MARK: Work hours
    var defaultWorkStartHour: Int = 9
    var defaultWorkEndHour: Int   = 17

    // MARK: AI
    var aiEngine: AiEngine = .onDevice

    // MARK: Features
    var homeCountryEnabled: Bool  = false
    var onboardingComplete: Bool  = false
}

// MARK: - AiEngine persistence mapping

extension MeridianSettings {
    /// Stable persisted string for an `AiEngine`, independent of the enum's own
    /// raw-value conformance (which is owned by another module).
    static func persistedString(for engine: AiEngine) -> String {
        switch engine {
        case .onDevice: return "onDevice"
        case .cloud:    return "cloud"
        }
    }

    static func aiEngine(fromPersisted raw: String) -> AiEngine? {
        switch raw {
        case "onDevice": return .onDevice
        case "cloud":    return .cloud
        default:         return nil
        }
    }
}

// MARK: - SettingsRepository

/// Observable store that reads / writes `MeridianSettings` fields individually to
/// `UserDefaults` so that each preference survives app restarts.
@MainActor
@Observable
final class SettingsRepository {

    // MARK: Singleton

    static let shared = SettingsRepository()

    // MARK: Observed state

    private(set) var settings: MeridianSettings = .init()

    // MARK: Private helpers

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let hourCycle              = "meridian.hourCycle"
        static let glassEnabled           = "meridian.glassEnabled"
        static let reduceTransparency     = "meridian.reduceTransparency"
        static let backdropEnabled        = "meridian.backdropEnabled"
        static let backdropIntensity      = "meridian.backdropIntensity"
        static let glassOpacity           = "meridian.glassOpacity"
        static let mapStyle               = "meridian.mapStyle"
        static let reminderLeadMinutes    = "meridian.reminderLeadMinutes"
        static let defaultWorkStartHour   = "meridian.defaultWorkStartHour"
        static let defaultWorkEndHour     = "meridian.defaultWorkEndHour"
        static let aiEngine               = "meridian.aiEngine"
        static let homeCountryEnabled     = "meridian.homeCountryEnabled"
        static let onboardingComplete     = "meridian.onboardingComplete"

        // Legacy keys migrated on load.
        /// Old key that stored opacity as an integer percent (10...100).
        static let legacyGlassOpacityPercent = "meridian.glassOpacityPercent"
        /// Old key that stored the deprecated GlassOpacityLevel enum name.
        static let legacyGlassOpacityLevel   = "meridian.glassOpacityLevel"
    }

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Clamp helpers

    private static func clampFraction(_ value: Double) -> Double {
        min(kMaxGlassFraction, max(kMinGlassFraction, value))
    }

    private static func clampHour(_ value: Int) -> Int {
        min(23, max(0, value))
    }

    /// Normalizes a persisted glass/backdrop value into a 0.10...1.0 fraction.
    /// Legacy builds stored integer percents (10...100); detect those (anything
    /// > 1.0) and divide by 100 before clamping.
    private static func normalizeFraction(_ raw: Double) -> Double {
        let fraction = raw > 1.0 ? raw / 100.0 : raw
        return clampFraction(fraction)
    }

    /// Maps a deprecated GlassOpacityLevel enum name to its fraction.
    /// Mirrors Android `legacyGlassOpacityPercent`.
    private static func legacyGlassLevelFraction(_ name: String) -> Double? {
        switch name.uppercased() {
        case "TRANSPARENT": return 0.10
        case "LIGHT":       return 0.35
        case "MEDIUM":      return 0.60
        case "OPAQUE":      return 1.00
        default:            return nil
        }
    }

    // MARK: - Load

    private func load() {
        if let raw = defaults.string(forKey: Key.hourCycle),
           let value = HourCycle(rawValue: raw) {
            settings.hourCycle = value
        }

        if defaults.object(forKey: Key.glassEnabled) != nil {
            settings.glassEnabled = defaults.bool(forKey: Key.glassEnabled)
        }

        if defaults.object(forKey: Key.reduceTransparency) != nil {
            settings.reduceTransparency = defaults.bool(forKey: Key.reduceTransparency)
        }

        if defaults.object(forKey: Key.backdropEnabled) != nil {
            settings.backdropEnabled = defaults.bool(forKey: Key.backdropEnabled)
        }

        if defaults.object(forKey: Key.backdropIntensity) != nil {
            settings.backdropIntensity = Self.normalizeFraction(
                defaults.double(forKey: Key.backdropIntensity)
            )
        }

        settings.glassOpacity = loadGlassOpacity()

        if let raw = defaults.string(forKey: Key.mapStyle),
           let value = MapStyle(rawValue: raw) {
            settings.mapStyle = value
        }

        if defaults.object(forKey: Key.reminderLeadMinutes) != nil {
            // Stored verbatim — no clamp. Android uses -1 as the "Reminders disabled"
            // sentinel (SettingsRepository.kt stores the raw value), and
            // ReminderScheduler honors `leadMinutes >= 0` to suppress notifications.
            settings.reminderLeadMinutes = defaults.integer(forKey: Key.reminderLeadMinutes)
        }

        if defaults.object(forKey: Key.defaultWorkStartHour) != nil {
            settings.defaultWorkStartHour = Self.clampHour(defaults.integer(forKey: Key.defaultWorkStartHour))
        }

        if defaults.object(forKey: Key.defaultWorkEndHour) != nil {
            settings.defaultWorkEndHour = Self.clampHour(defaults.integer(forKey: Key.defaultWorkEndHour))
        }

        if let raw = defaults.string(forKey: Key.aiEngine),
           let value = MeridianSettings.aiEngine(fromPersisted: raw) {
            settings.aiEngine = value
        }

        if defaults.object(forKey: Key.homeCountryEnabled) != nil {
            settings.homeCountryEnabled = defaults.bool(forKey: Key.homeCountryEnabled)
        }

        if defaults.object(forKey: Key.onboardingComplete) != nil {
            settings.onboardingComplete = defaults.bool(forKey: Key.onboardingComplete)
        }
    }

    /// Resolves glass opacity, preferring the current key and falling back through
    /// legacy representations (integer percent, then deprecated enum level).
    /// Mirrors Android `parseGlassOpacity`.
    private func loadGlassOpacity() -> Double {
        if defaults.object(forKey: Key.glassOpacity) != nil {
            return Self.normalizeFraction(defaults.double(forKey: Key.glassOpacity))
        }
        if defaults.object(forKey: Key.legacyGlassOpacityPercent) != nil {
            return Self.normalizeFraction(Double(defaults.integer(forKey: Key.legacyGlassOpacityPercent)))
        }
        if let name = defaults.string(forKey: Key.legacyGlassOpacityLevel),
           let fraction = Self.legacyGlassLevelFraction(name) {
            return fraction
        }
        return kDefaultGlassOpacity
    }

    // MARK: - Setters

    /// Replaces the entire settings snapshot and persists every field.
    func update(_ newSettings: MeridianSettings) {
        var clamped = newSettings
        clamped.glassOpacity      = Self.clampFraction(clamped.glassOpacity)
        clamped.backdropIntensity = Self.clampFraction(clamped.backdropIntensity)
        clamped.defaultWorkStartHour = Self.clampHour(clamped.defaultWorkStartHour)
        clamped.defaultWorkEndHour   = Self.clampHour(clamped.defaultWorkEndHour)
        // reminderLeadMinutes is NOT clamped: -1 is the Android "disabled" sentinel.
        settings = clamped
        persist()
    }

    func setHourCycle(_ value: HourCycle) {
        settings.hourCycle = value
        defaults.set(value.rawValue, forKey: Key.hourCycle)
    }

    func setGlassEnabled(_ value: Bool) {
        settings.glassEnabled = value
        defaults.set(value, forKey: Key.glassEnabled)
    }

    func setReduceTransparency(_ value: Bool) {
        settings.reduceTransparency = value
        defaults.set(value, forKey: Key.reduceTransparency)
    }

    func setBackdropEnabled(_ value: Bool) {
        settings.backdropEnabled = value
        defaults.set(value, forKey: Key.backdropEnabled)
    }

    /// - Parameter value: Normalized fraction; clamped to 0.10...1.0.
    func setBackdropIntensity(_ value: Double) {
        settings.backdropIntensity = Self.clampFraction(value)
        defaults.set(settings.backdropIntensity, forKey: Key.backdropIntensity)
    }

    /// - Parameter value: Normalized fraction; clamped to 0.10...1.0.
    func setGlassOpacity(_ value: Double) {
        settings.glassOpacity = Self.clampFraction(value)
        defaults.set(settings.glassOpacity, forKey: Key.glassOpacity)
        // Drop any legacy representations so future loads use the canonical key.
        defaults.removeObject(forKey: Key.legacyGlassOpacityPercent)
        defaults.removeObject(forKey: Key.legacyGlassOpacityLevel)
    }

    func setMapStyle(_ value: MapStyle) {
        settings.mapStyle = value
        defaults.set(value.rawValue, forKey: Key.mapStyle)
    }

    /// Persists the lead verbatim. A value of `-1` is the Android "Reminders
    /// disabled" sentinel; ReminderScheduler suppresses scheduling when < 0.
    func setReminderLeadMinutes(_ value: Int) {
        settings.reminderLeadMinutes = value
        defaults.set(value, forKey: Key.reminderLeadMinutes)
    }

    func setDefaultWorkStartHour(_ value: Int) {
        settings.defaultWorkStartHour = Self.clampHour(value)
        defaults.set(settings.defaultWorkStartHour, forKey: Key.defaultWorkStartHour)
    }

    func setDefaultWorkEndHour(_ value: Int) {
        settings.defaultWorkEndHour = Self.clampHour(value)
        defaults.set(settings.defaultWorkEndHour, forKey: Key.defaultWorkEndHour)
    }

    func setAiEngine(_ value: AiEngine) {
        settings.aiEngine = value
        defaults.set(MeridianSettings.persistedString(for: value), forKey: Key.aiEngine)
    }

    func setHomeCountryEnabled(_ value: Bool) {
        settings.homeCountryEnabled = value
        defaults.set(value, forKey: Key.homeCountryEnabled)
    }

    func setOnboardingComplete(_ value: Bool) {
        settings.onboardingComplete = value
        defaults.set(value, forKey: Key.onboardingComplete)
    }

    // MARK: - Private persist (bulk)

    private func persist() {
        defaults.set(settings.hourCycle.rawValue,    forKey: Key.hourCycle)
        defaults.set(settings.glassEnabled,          forKey: Key.glassEnabled)
        defaults.set(settings.reduceTransparency,    forKey: Key.reduceTransparency)
        defaults.set(settings.backdropEnabled,       forKey: Key.backdropEnabled)
        defaults.set(settings.backdropIntensity,     forKey: Key.backdropIntensity)
        defaults.set(settings.glassOpacity,          forKey: Key.glassOpacity)
        defaults.set(settings.mapStyle.rawValue,     forKey: Key.mapStyle)
        defaults.set(settings.reminderLeadMinutes,   forKey: Key.reminderLeadMinutes)
        defaults.set(settings.defaultWorkStartHour,  forKey: Key.defaultWorkStartHour)
        defaults.set(settings.defaultWorkEndHour,    forKey: Key.defaultWorkEndHour)
        defaults.set(MeridianSettings.persistedString(for: settings.aiEngine), forKey: Key.aiEngine)
        defaults.set(settings.homeCountryEnabled,    forKey: Key.homeCountryEnabled)
        defaults.set(settings.onboardingComplete,    forKey: Key.onboardingComplete)
        // Canonical write wins; clear legacy glass keys.
        defaults.removeObject(forKey: Key.legacyGlassOpacityPercent)
        defaults.removeObject(forKey: Key.legacyGlassOpacityLevel)
    }
}
