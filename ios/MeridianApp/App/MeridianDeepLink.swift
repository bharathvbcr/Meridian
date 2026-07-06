// MeridianDeepLink.swift
// Meridian — iOS 27 / Swift 6
//
// URL-scheme routing for the `meridian://` deep links.
//
// Android parity: `MainActivity` registers `navDeepLink { uriPattern = "meridian://world" }`
// and `"meridian://plan"` on the world/plan destinations; tapping a reminder opens
// `meridian://plan` (ReminderReceiver / NotificationDelegate). We collapse all of that into a
// single `MeridianDeepLink` parser shared by `onOpenURL`, App Intents, and reminder taps.

import Foundation

// MARK: - MeridianDeepLink

/// The set of destinations reachable via the `meridian://` URL scheme.
///
/// Hosts mirror the Android `navDeepLink` uri patterns exactly:
///   - `meridian://world` → World Clock tab
///   - `meridian://addzone` → World Clock tab + city picker
///   - `meridian://plan`  → Planner tab (also the reminder-tap target)
///
/// Unknown hosts resolve to `nil` so the caller can ignore the link rather than navigating
/// somewhere surprising.
enum MeridianDeepLink: Equatable, Sendable {
    case world(openCityPicker: Bool = false)
    case plan

    /// The URL scheme the app registers (`Info.plist` `CFBundleURLSchemes`).
    static let scheme = "meridian"

    /// Parses an incoming `meridian://…` URL into a known destination, or `nil`.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        // The destination is carried in the host (`meridian://world`); fall back to the first
        // path component for `meridian:///world`-style links some launchers emit.
        let token = (url.host ?? url.pathComponents.first { $0 != "/" })?.lowercased()
        switch token {
        case "world":
            let queryPicker = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .contains { $0.name == "picker" && $0.value != "0" && $0.value != "false" } ?? false
            self = .world(openCityPicker: queryPicker)
        case "plan":
            self = .plan
        case "addzone":
            self = .world(openCityPicker: true)
        default:
            return nil
        }
    }

    /// The tab this deep link selects.
    var tab: MeridianTab {
        switch self {
        case .world: return .world
        case .plan:  return .plan
        }
    }

    /// Whether the World screen should open the city picker on arrival.
    var opensWorldCityPicker: Bool {
        switch self {
        case let .world(openCityPicker): return openCityPicker
        case .plan: return false
        }
    }

    /// The canonical URL for this destination (used by App Intents / shortcuts).
    var url: URL {
        switch self {
        case .world: return URL(string: "meridian://world")!
        case .plan:  return URL(string: "meridian://plan")!
        }
    }
}
