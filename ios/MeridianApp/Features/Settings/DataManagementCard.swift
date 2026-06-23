// DataManagementCard.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// "Manage local data" panel. Behavioral port of Android `DataManagementCard`. Android
// deep-linked to per-app storage settings to clear app data; iOS has no public "clear app
// storage" deep link, so we route to the app's page in the system Settings app (where the
// user can delete the app, which removes all local Meridian data).

import SwiftUI

// MARK: - Local design tokens

private extension Color {
    static let settingsPrimary      = Color(hex: "#60CDFF")
    static let settingsOnSurface    = Color(hex: "#F1F5F9")
    static let settingsOnSurfaceVar = Color(hex: "#94A3B8")
}

// MARK: - DataManagementCard

struct DataManagementCard: View {
    var body: some View {
        SettingsCard {
            Text("Manage local data")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.settingsOnSurface)

            Text("Meridian stores zones, planner data, and preferences on this device. Delete the app to remove everything — this cannot be undone.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.settingsOnSurfaceVar)
                .lineSpacing(2)
                .padding(.top, 6)
                .padding(.bottom, 12)

            Button {
                SettingsActions.openAppSettings()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Open app settings")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.settingsPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.settingsPrimary.opacity(0.4), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
