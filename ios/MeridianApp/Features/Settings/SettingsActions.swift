// SettingsActions.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// Side-effecting helpers behind the Settings surface: open the system Settings app,
// open external web URLs, compose feedback, write the App Store review intent, and
// build the diagnostic text users can copy/attach. Behavioral port of Android
// `SettingsActions.kt` (which used Intents); on iOS we route through `UIApplication`,
// `URL` schemes, and SwiftUI's share sheet (`ShareLink`) where applicable.
//
// Also owns the "Auto-sync calendar" preference. Android wired this through its
// cross-app `InteropClient`; iOS has no separate companion app, so the equivalent
// "interop" is pulling the device calendar into the Plan screen. The previously-dead
// toggle is now backed by a real persisted flag here.

import Foundation
import SwiftUI
import UIKit

// MARK: - Legal "last updated" stamp (mirrors Android LEGAL_LAST_UPDATED)

/// Human-readable date the bundled legal copy was last revised.
let kLegalLastUpdated = "June 2026"

// MARK: - External URLs (mirrors Android SettingsUrls)

enum SettingsUrls {
    static let googlePrivacy     = "https://policies.google.com/privacy"
    static let firebaseTerms     = "https://firebase.google.com/terms"
    static let geminiAppsPrivacy = "https://support.google.com/gemini/answer/13594961"
    static let feedbackEmail     = "feedback@meridianapp.example.com"
}

// MARK: - Auto-sync preference

/// Persisted "pull device calendar into the Plan screen" toggle. Lives outside
/// `MeridianSettings` because it is a Settings-screen-local interop concern (the
/// Android equivalent lived in the cross-app InteropClient, not DataStore settings).
@MainActor
enum CalendarAutoSync {
    private static let key = "meridian.calendarAutoSyncEnabled"

    /// Defaults to `true` — Android auto-shared events when the peer was connected.
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - App version helpers (mirrors Android appVersionName / appVersionLabel)

@MainActor
enum AppInfo {
    /// Marketing version, e.g. "1.0".
    static var versionName: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Build number, e.g. "42".
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// "1.0 (42)" — Android `appVersionLabel`.
    static var versionLabel: String {
        "\(versionName) (\(buildNumber))"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.example.meridian"
    }

    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif
}

// MARK: - Diagnostics (mirrors Android buildDiagnosticText)

@MainActor
enum SettingsActions {

    /// Multi-line diagnostics block the user can copy or attach to feedback.
    static func buildDiagnosticText() -> String {
        let device = UIDevice.current
        let buildType = AppInfo.isDebugBuild ? "debug" : "release"
        return """
        Meridian diagnostics
        Version: \(AppInfo.versionLabel)
        Build: \(buildType)
        Bundle: \(AppInfo.bundleIdentifier)
        iOS: \(device.systemVersion)
        Device: \(device.model)
        """
    }

    /// Pre-filled feedback body (diagnostics + a prompt), matching Android `openFeedback`.
    static func feedbackBody() -> String {
        buildDiagnosticText() + "\n\nDescribe your feedback:\n"
    }

    static func feedbackSubject() -> String {
        "Meridian feedback (v\(AppInfo.versionName))"
    }

    // MARK: - Navigation actions

    /// Opens this app's page in the system Settings app (Android `openAppSettings`).
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Opens an arbitrary web URL in the default browser (Android `openWebUrl`).
    static func openWebURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }

    /// Opens the App Store review prompt for this app. Android opened the Play listing;
    /// the iOS analogue is the App Store product page with the review action.
    /// - Parameter appStoreId: The numeric App Store id. When unknown, falls back to a
    ///   search for "Meridian" so the action is never a dead end.
    static func openAppStoreReview(appStoreId: String? = nil) {
        if let id = appStoreId,
           let url = URL(string: "https://apps.apple.com/app/id\(id)?action=write-review") {
            UIApplication.shared.open(url)
        } else if let search = URL(string: "https://apps.apple.com/search?term=Meridian") {
            // VERIFY: replace with the real App Store id once the app is published.
            UIApplication.shared.open(search)
        }
    }

    /// Composes a feedback email via the `mailto:` scheme. Returns `false` if no mail
    /// client can handle it (the caller should then present a `ShareLink` instead).
    @discardableResult
    static func openFeedbackMail() -> Bool {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = SettingsUrls.feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: feedbackSubject()),
            URLQueryItem(name: "body", value: feedbackBody()),
        ]
        guard let url = components.url, UIApplication.shared.canOpenURL(url) else {
            return false
        }
        UIApplication.shared.open(url)
        return true
    }
}
