// LegalDocument.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// The bundled legal / privacy copy shown in the Settings "About & Legal" section.
// Verbatim behavioral port of Android `SettingsLegalContent.kt` (LegalDocument enum):
// identical document titles, body copy, and external link affordances. Rendered by
// `LegalNoticeSheet`.

import Foundation

/// A single bundled legal document. `externalURL` / `externalLabel` drive an optional
/// "Learn more" affordance; `.thirdPartyPolicies` is special-cased in the sheet to show
/// two named buttons (Google Privacy + Firebase Terms) instead.
enum LegalDocument: String, Identifiable, CaseIterable, Sendable {
    case privacy
    case terms
    case dataHandling
    case openSource
    case thirdPartyPolicies

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy:            return "Privacy notice"
        case .terms:              return "Terms of use"
        case .dataHandling:       return "How your data is handled"
        case .openSource:         return "Open source licenses"
        case .thirdPartyPolicies: return "Third-party policies"
        }
    }

    /// Optional external link shown beneath the body (except `.thirdPartyPolicies`,
    /// which renders its own dedicated buttons).
    var externalURL: String? {
        switch self {
        case .privacy: return SettingsUrls.geminiAppsPrivacy
        default:       return nil
        }
    }

    var externalLabel: String? {
        switch self {
        case .privacy: return "Gemini app privacy help"
        default:       return nil
        }
    }

    var body: String {
        switch self {
        case .privacy:
            return """
            Meridian is built around on-device processing. Your clocks, saved zones, planner data, and settings are stored locally on your phone.

            What Meridian may access
            • Location — only when you choose “Use my location” to resolve your home time zone. Coordinates are not uploaded to Meridian servers.
            • Calendar — read-only access to show events on the planner when you grant permission.
            • Contacts — read-only access to import people into the planner when you grant permission.
            • Notifications — used only to deliver event reminders you schedule.

            AI assistant
            On supported devices, prompts are processed with Apple Intelligence on-device. If on-device AI is unavailable, Meridian may send your prompt to a cloud model as a fallback. Do not include sensitive information in prompts when cloud fallback may apply.

            Analytics & accounts
            Meridian does not require an account. We do not sell your personal data. Bundled platform SDKs may collect limited diagnostic or crash data according to their policies.

            Your choices
            You can revoke permissions at any time in the system Settings app. Deleting the app removes local Meridian data from your device.

            Questions
            Use “Send feedback” in Settings to reach the development team.

            Last updated: \(kLegalLastUpdated)
            """
        case .terms:
            return """
            By using Meridian you agree to these terms.

            The app
            Meridian provides world-time displays, multi-zone planning tools, reminders, and optional AI-assisted scheduling. Features may change or be removed as the product evolves.

            Acceptable use
            Use Meridian lawfully and do not attempt to reverse engineer, disrupt, or misuse the service. You are responsible for the accuracy of calendar events, invites, and reminders you create.

            No warranty
            Meridian is provided “as is” without warranties of any kind. Time-zone data, solar calculations, and AI suggestions are informational — always verify critical scheduling decisions independently.

            Limitation of liability
            To the fullest extent permitted by law, the developers are not liable for missed meetings, incorrect time conversions, data loss, or indirect damages arising from use of the app.

            Third-party services
            Cloud AI fallback, platform services, and device platform APIs are subject to their own terms. Your use of those features is also governed by the applicable provider agreements.

            Changes
            These terms may be updated in future releases. Continued use after an update constitutes acceptance of the revised terms.

            Last updated: \(kLegalLastUpdated)
            """
        case .dataHandling:
            return """
            Stored on your device
            • Pinned and saved time zones
            • Home location and home-country anchors
            • Planner participants, working hours, and preferences
            • App appearance and reminder settings

            Processed on your device
            • Time-zone math, fairness scoring, and solar calculations
            • On-device Apple Intelligence inference when hardware supports it

            May leave your device
            • Cloud AI requests when on-device AI is unavailable
            • Standard platform SDK telemetry, if enabled on your device
            • Calendar .ics files or share sheets you explicitly trigger

            Not collected by Meridian
            • No Meridian login or cloud profile
            • No upload of your full contact list or calendar by default
            • No sale of personal information

            Retention
            Data remains on your device until you delete app data or uninstall Meridian.

            Last updated: \(kLegalLastUpdated)
            """
        case .openSource:
            return """
            Meridian is built with open-source software. Key components include:

            • SwiftUI & Apple frameworks (Apple SDK terms)
            • Swift standard library (Apache 2.0 with Runtime Library Exception)
            • SF Symbols (Apple license)

            Full license texts are available in the respective project repositories. Source code for Meridian itself is maintained by the project authors.

            Last updated: \(kLegalLastUpdated)
            """
        case .thirdPartyPolicies:
            return """
            Meridian embeds platform services. When you use cloud AI fallback or platform-backed features, those providers’ policies also apply.

            Review the current policies at the links below. Meridian does not control third-party data practices.
            """
        }
    }
}
