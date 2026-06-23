// PermissionsCard.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// Unified permissions panel: notifications, calendar, contacts, and location, each with a
// normalized status pill and a contextual action (request inline when undetermined, or open
// the system Settings app when denied). Behavioral port of Android `PermissionsCard`, driven
// by the shared `PermissionsManager` (which owns the actual EventKit / Contacts / Location /
// UNUserNotificationCenter requests). Re-polls on appear and when the app returns to the
// foreground, mirroring Android's `LifecycleResumeEffect` refresh.

import SwiftUI

// MARK: - Local design tokens

private extension Color {
    static let settingsPrimary      = Color(hex: "#60CDFF")
    static let settingsOnSurface    = Color(hex: "#F1F5F9")
    static let settingsOnSurfaceVar = Color(hex: "#94A3B8")
    static let settingsPositive     = Color(hex: "#4CAF50")
    static let settingsError        = Color(hex: "#F87171")
    static let settingsWarning      = Color(hex: "#FFB703")
}

// MARK: - PermissionsCard

struct PermissionsCard: View {
    @State private var permissions = PermissionsManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        SettingsCard {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.settingsPrimary)
                Text("App permissions")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.settingsOnSurface)
            }

            Text("Meridian only asks for access when a feature needs it. Grant permissions here or in the system Settings app.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.settingsOnSurfaceVar)
                .padding(.top, 8)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                PermissionStatusRow(
                    icon: "location",
                    title: "Location",
                    description: "Resolve your home time zone from your current position.",
                    state: permissions.snapshot.location
                ) {
                    await permissions.requestLocation()
                }

                divider

                PermissionStatusRow(
                    icon: "bell.badge",
                    title: "Notifications",
                    description: "Post reminders before planned events.",
                    state: permissions.snapshot.notifications
                ) {
                    await permissions.requestNotifications()
                }

                divider

                PermissionStatusRow(
                    icon: "calendar",
                    title: "Calendar",
                    description: "Show your device calendar on the planner.",
                    state: permissions.snapshot.calendar
                ) {
                    await permissions.requestCalendar()
                }

                divider

                PermissionStatusRow(
                    icon: "person.crop.circle",
                    title: "Contacts",
                    description: "Import people into the planner from your address book.",
                    state: permissions.snapshot.contacts
                ) {
                    await permissions.requestContacts()
                }
            }
        }
        .task { await permissions.refresh() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await permissions.refresh() }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 12)
    }
}

// MARK: - PermissionStatusRow

/// One permission line: icon, title, status label, description, and a contextual action
/// row shown only when the permission is not yet usable.
struct PermissionStatusRow: View {
    let icon: String
    let title: String
    let description: String
    let state: PermissionState
    /// Inline request action (no-op when the only path forward is system Settings).
    let request: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.settingsPrimary)
                    .frame(width: 20)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.settingsOnSurface)
                        Spacer()
                        Text(statusLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(statusColor)
                    }
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.settingsOnSurfaceVar)
                }
            }

            if !state.isUsable {
                HStack(spacing: 8) {
                    if state == .notDetermined {
                        actionButton(title: "Allow \(title)", filled: true) {
                            Task { await request() }
                        }
                    }
                    actionButton(title: "System settings", filled: false) {
                        SettingsActions.openAppSettings()
                    }
                }
                .padding(.leading, 28)
            }
        }
    }

    // MARK: Status mapping

    private var statusLabel: String {
        switch state {
        case .granted:       return "Granted"
        case .limited:       return "Limited"
        case .denied:        return "Not granted"
        case .notDetermined: return "Not set"
        }
    }

    private var statusColor: Color {
        switch state {
        case .granted:       return .settingsPositive
        case .limited:       return .settingsWarning
        case .denied:        return .settingsError
        case .notDetermined: return .settingsOnSurfaceVar
        }
    }

    @ViewBuilder
    private func actionButton(title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(filled ? Color(hex: "#020617") : Color.settingsPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background {
                    if filled {
                        Capsule().fill(Color.settingsPrimary)
                    } else {
                        Capsule().strokeBorder(Color.settingsPrimary.opacity(0.4), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
