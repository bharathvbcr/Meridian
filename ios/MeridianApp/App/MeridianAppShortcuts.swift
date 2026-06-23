// MeridianAppShortcuts.swift
// Meridian — iOS 27 / Swift 6
//
// App Intents + AppShortcutsProvider so Meridian's primary destinations are reachable
// from Spotlight, the Shortcuts app, and Siri — the iOS-native counterpart to Android's
// launcher deep links / app shortcuts. Each intent opens the app and routes through the
// same `MeridianDeepLink` path used by `onOpenURL` and reminder taps, so there is exactly
// one navigation code path.

import AppIntents
import SwiftUI

// MARK: - MeridianIntentRouter

/// Bridges App-Intent invocations into the running app's deep-link router.
///
/// An `AppIntent` may run while the app is suspended; we mark each intent
/// `openAppWhenRun = true` so the system foregrounds Meridian first, then the intent
/// hands its destination to this router. The app installs `handler` at launch (the same
/// closure it gives `onOpenURL` / the notification delegate). Until then, the last
/// requested destination is buffered in `pending` and replayed once the handler attaches,
/// so a cold launch from Spotlight still lands on the right tab.
@MainActor
final class MeridianIntentRouter {

    static let shared = MeridianIntentRouter()

    /// The app's deep-link handler. Set once at launch.
    private var handler: ((MeridianDeepLink) -> Void)?

    /// Destination requested before the handler was installed (cold launch).
    private var pending: MeridianDeepLink?

    private init() {}

    /// Installs the live handler and replays any buffered destination.
    func install(handler: @escaping (MeridianDeepLink) -> Void) {
        self.handler = handler
        if let pending {
            handler(pending)
            self.pending = nil
        }
    }

    /// Routes a destination now, or buffers it until the handler is installed.
    func route(_ link: MeridianDeepLink) {
        if let handler {
            handler(link)
        } else {
            pending = link
        }
    }
}

// MARK: - Intents

/// Opens the World Clock tab (`meridian://world`).
struct OpenWorldClockIntent: AppIntent {
    static let title: LocalizedStringResource = "Open World Clock"
    static let description = IntentDescription(
        "Jump straight to Meridian's world clock to see the time across your saved zones."
    )

    /// Foreground the app so the router's handler is live before we route.
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        MeridianIntentRouter.shared.route(.world)
        return .result()
    }
}

/// Opens the Planner tab (`meridian://plan`).
struct OpenPlannerIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Planner"
    static let description = IntentDescription(
        "Open Meridian's planner to find fair meeting windows across time zones."
    )

    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        MeridianIntentRouter.shared.route(.plan)
        return .result()
    }
}

// MARK: - AppShortcutsProvider

/// Registers Meridian's shortcuts so they surface in Spotlight and Siri without any user
/// setup. Phrases must include the `\(.applicationName)` token (App Intents requirement);
/// the system substitutes the app's display name.
struct MeridianAppShortcuts: AppShortcutsProvider {

    // VERIFY: `AppShortcut` / `AppShortcutsProvider` — stable since iOS 16, current on iOS 27.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenWorldClockIntent(),
            phrases: [
                "Open World Clock in \(.applicationName)",
                "Show the world clock in \(.applicationName)",
                "\(.applicationName) world clock"
            ],
            shortTitle: "World Clock",
            systemImageName: "globe.americas.fill"
        )
        AppShortcut(
            intent: OpenPlannerIntent(),
            phrases: [
                "Open the planner in \(.applicationName)",
                "Plan a meeting in \(.applicationName)",
                "\(.applicationName) planner"
            ],
            shortTitle: "Planner",
            systemImageName: "calendar.badge.clock"
        )
    }
}
