// LocationZoneResolver.swift
// Meridian — iOS 27 / Swift 6, strict concurrency
//
// Resolves a best-guess home IANA timezone from the device's current location.
//
// Mirrors the Android `LocationZoneResolver` (§5.1, §8): a privacy-friendly, one-shot
// resolution that falls back to manual selection when permission is missing or no fix is
// available. On iOS we prefer Apple's reverse-geocoder, which returns the *exact* IANA
// zone for the coordinate (`CLPlacemark.timeZone`); when that is unavailable (offline,
// throttled) we fall back to the same nearest-known-city heuristic Android uses.

import CoreLocation
import Foundation

// MARK: - LocationAuthStatus

/// Coarse authorization summary the UI can switch on without importing CoreLocation.
enum LocationAuthStatus: Sendable {
    case notDetermined
    case denied        // denied or restricted
    case authorized    // whenInUse or always

    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .authorizedWhenInUse, .authorizedAlways:
            self = .authorized
        case .denied, .restricted:
            self = .denied
        @unknown default:
            self = .denied
        }
    }
}

// MARK: - LocationZoneResolver

/// One-shot location → IANA zone resolver.
///
/// `CLLocationManager` is not `Sendable` and posts delegate callbacks on the main thread,
/// so the resolver is `@MainActor`-isolated. A single call to ``resolveHomeZoneId()`` will,
/// if necessary, request *when-in-use* authorization, await one location fix via the modern
/// `CLLocationUpdate.liveUpdates()` async stream, reverse-geocode it, and return an IANA id.
@MainActor
final class LocationZoneResolver {

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    /// How long to wait for a single location fix before giving up.
    private let fixTimeout: Duration = .seconds(8)

    init() {}

    // MARK: - Authorization

    /// Current authorization status, without prompting.
    var authStatus: LocationAuthStatus {
        LocationAuthStatus(manager.authorizationStatus)
    }

    /// `true` when the app already holds when-in-use or always authorization.
    var hasLocationPermission: Bool {
        authStatus == .authorized
    }

    /// Requests *when-in-use* authorization if the status is still undetermined, then
    /// returns the resolved status. Resolves immediately when already determined.
    ///
    /// - Returns: The post-prompt ``LocationAuthStatus``.
    func requestAuthorization() async -> LocationAuthStatus {
        let current = manager.authorizationStatus
        guard current == .notDetermined else {
            return LocationAuthStatus(current)
        }
        return await withCheckedContinuation { continuation in
            let delegate = AuthDelegate { status in
                continuation.resume(returning: LocationAuthStatus(status))
            }
            // Retain the delegate for the lifetime of the prompt.
            self.authDelegate = delegate
            self.manager.delegate = delegate
            self.manager.requestWhenInUseAuthorization()
        }
    }

    /// Strong reference that keeps the one-shot auth delegate alive across the async prompt.
    private var authDelegate: AuthDelegate?

    // MARK: - Resolution

    /// Best-effort home IANA zone id, or `nil` when it can't be determined without further
    /// prompting (no permission, no fix, or geocoder + heuristic both fail).
    ///
    /// Steps:
    /// 1. Ensure authorization (requests when-in-use if undetermined).
    /// 2. Await one location fix (with timeout) via `CLLocationUpdate.liveUpdates()`.
    /// 3. Reverse-geocode the fix; prefer the placemark's exact IANA `timeZone`.
    /// 4. Fall back to the nearest known city's zone (offline parity with Android).
    func resolveHomeZoneId() async -> String? {
        let status = await requestAuthorization()
        guard status == .authorized else { return nil }

        guard let location = await currentLocation() else { return nil }

        // Prefer the exact zone Apple resolves for the coordinate.
        if let exact = await reverseGeocodeZone(location) {
            return exact
        }

        // Offline / throttled fallback: nearest known city (matches Android heuristic).
        let nearest = Self.nearestKnownZone(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        // The nearest known city can sit across a border (much of southern India is closer to
        // Colombo than Kolkata). When the device's configured zone keeps the same clock as that
        // candidate, trust the device — the location-based guess only wins when the offsets
        // actually differ (i.e. the device zone is stale). Android parity.
        if let nearestZone = TimeZone(identifier: nearest),
           nearestZone.secondsFromGMT(for: .now) == TimeZone.current.secondsFromGMT(for: .now) {
            return TimeZone.current.identifier
        }
        return nearest
    }

    /// Device's last-known coordinate from the system cache (no fresh fix requested), or `nil`
    /// without authorization or a cached fix. Used to pin the home zone at the user's actual
    /// location on the day/night map instead of the zone's representative city.
    var lastKnownCoordinate: GeoPoint? {
        guard hasLocationPermission, let location = manager.location else { return nil }
        return GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    // MARK: - Location fix

    /// Awaits a single location fix using the modern async location stream, bounded by
    /// ``fixTimeout``. Returns `nil` on timeout or stream error.
    private func currentLocation() async -> CLLocation? {
        await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                // `firstLiveUpdate()` is `@MainActor`, so the await hops back to the main
                // actor on its own; an explicit `@MainActor in` here trips the region-based
                // isolation checker, so leave the child task non-isolated.
                await self.firstLiveUpdate()
            }
            group.addTask {
                try? await Task.sleep(for: self.fixTimeout)
                return nil  // timeout sentinel
            }

            // Return the first non-nil result, or nil if the timeout task wins.
            for await result in group {
                group.cancelAll()
                return result
            }
            return nil
        }
    }

    /// Pulls the first usable fix from `CLLocationUpdate.liveUpdates()`.
    // VERIFY: CLLocationUpdate.liveUpdates() async stream — introduced iOS 17, stable on iOS 27.
    private func firstLiveUpdate() async -> CLLocation? {
        do {
            let updates = CLLocationUpdate.liveUpdates(.default)
            for try await update in updates {
                if let location = update.location {
                    return location
                }
                // `update.locationUnavailable` indicates the system can't provide a fix.
                if update.locationUnavailable {
                    return nil
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Reverse geocoding

    /// Reverse-geocodes a location and returns the placemark's IANA timezone identifier.
    // VERIFY: CLPlacemark.timeZone populated by reverseGeocodeLocation — stable since iOS 9.
    private func reverseGeocodeZone(_ location: CLLocation) async -> String? {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            return placemarks.first?.timeZone?.identifier
        } catch {
            return nil
        }
    }

    // MARK: - Offline nearest-zone heuristic (Android parity)

    /// The known IANA zone whose representative city is geographically closest to the given
    /// coordinate. Delegates to the single canonical ``ZoneGeo`` table (the full IANA set) so the
    /// offline home-zone heuristic, the day/night map and the globe all agree on coordinates.
    /// Previously this resolver carried its own major-city subset, which could disagree with
    /// `ZoneGeo` and resolve a different (often farther) "nearest" city for the same fix.
    static func nearestKnownZone(latitude lat: Double, longitude lng: Double) -> String {
        ZoneGeo.nearestKnownZone(lat: lat, lng: lng)
    }
}

// MARK: - AuthDelegate

/// Minimal one-shot delegate that fires once when the authorization status first changes
/// away from `.notDetermined`. `@MainActor` because `CLLocationManager` delivers callbacks
/// on the main run loop.
@MainActor
private final class AuthDelegate: NSObject, @MainActor CLLocationManagerDelegate {
    private var onChange: ((CLAuthorizationStatus) -> Void)?

    init(onChange: @escaping (CLAuthorizationStatus) -> Void) {
        self.onChange = onChange
        super.init()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        // Fire once, then detach so the continuation can never be resumed twice.
        let callback = onChange
        onChange = nil
        callback?(status)
    }
}
