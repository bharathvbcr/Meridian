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
    /// Destructive accent for the "Manage local data" card. Mirrors the
    /// `#F87171` warning tint used by `PermissionsCard`, kept private so this
    /// file stays self-contained without touching shared tokens.
    static let settingsDestructive = Color(hex: "#F87171")
}

/// Shared pressed feedback for the primary/outline CTAs in this panel: a small
/// scale + opacity dip on `Motion.quick()`, gated on Reduce Motion so the press
/// stays instantaneous when the user opts out of animation. Mirrors the
/// `NavPressStyle` treatment used across the nav chrome.
private struct SettingsPressStyle: ButtonStyle {
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(reduceMotion ? nil : Motion.quick(), value: configuration.isPressed)
    }
}

// MARK: - ReseedCard

/// "Seed starter zones" panel. Behavioral port of Android `ReseedCard`
/// (SettingsScreen.kt): one tap adds London, Tokyo, and New York to the pinned
/// zones, then flips into a confirmation state. `addZone` upserts by IANA id, so
/// re-tapping is harmless.
struct ReseedCard: View {
    @Bindable var viewModel: MainViewModel
    @State private var seeded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsCard {
            Text("Seed starter zones")
                .font(.titleMedium)
                .foregroundStyle(MeridianColors.onSurface)

            Text("Adds London, Tokyo, and New York to your pinned zones.")
                .font(.bodyMedium)
                .foregroundStyle(MeridianColors.onSurfaceVariant)
                .padding(.top, MeridianSpacing.xs.rawValue)
                .padding(.bottom, MeridianSpacing.md.rawValue)

            Button {
                viewModel.addZone(SavedZone(id: "Europe/London", displayName: "London"))
                viewModel.addZone(SavedZone(id: "Asia/Tokyo", displayName: "Tokyo"))
                viewModel.addZone(SavedZone(id: "America/New_York", displayName: "New York"))
                withAnimation(reduceMotion ? nil : Motion.smooth()) { seeded = true }
            } label: {
                HStack(spacing: MeridianSpacing.sm.rawValue) {
                    Image(systemName: seeded ? "checkmark.circle.fill" : "arrow.counterclockwise")
                        .font(.bodyMedium.weight(.semibold))
                    Text(seeded ? "Zones added to Watchlist" : "Add starter zones")
                        .font(.bodyMedium.weight(.semibold))
                }
                .foregroundStyle(seeded ? MeridianColors.positive : MeridianColors.onPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                        .fill(seeded ? MeridianColors.positive.opacity(0.15) : MeridianColors.primary)
                }
            }
            .buttonStyle(SettingsPressStyle(reduceMotion: reduceMotion))
            .sensoryFeedback(.success, trigger: seeded)
            .accessibilityLabel(seeded ? "Zones added to Watchlist" : "Add starter zones")
            .accessibilityValue(seeded ? "Zones added" : "")
            .accessibilityHint(seeded
                ? "London, Tokyo, and New York are now in your Watchlist."
                : "Adds London, Tokyo, and New York to your pinned zones.")
            .accessibilityAddTraits(.isButton)
        }
    }
}

// MARK: - DataManagementCard

struct DataManagementCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openedSettings = false

    var body: some View {
        SettingsCard {
            HStack(spacing: MeridianSpacing.sm.rawValue) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.bodyLarge.weight(.semibold))
                    .foregroundStyle(Color.settingsDestructive)
                    .accessibilityHidden(true)
                Text("Manage local data")
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.onSurface)
            }

            Text("Meridian stores zones, planner data, and preferences on this device. Delete the app to remove everything — this cannot be undone.")
                .font(.bodyMedium)
                .foregroundStyle(MeridianColors.onSurfaceVariant)
                .lineSpacing(2)
                .padding(.top, MeridianSpacing.xs.rawValue)
                .padding(.bottom, MeridianSpacing.md.rawValue)

            Button {
                openedSettings.toggle()
                SettingsActions.openAppSettings()
            } label: {
                HStack(spacing: MeridianSpacing.sm.rawValue) {
                    Image(systemName: "externaldrive")
                        .font(.bodyMedium.weight(.semibold))
                    Text("Open app settings")
                        .font(.bodyMedium.weight(.semibold))
                }
                .foregroundStyle(Color.settingsDestructive)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                        .strokeBorder(Color.settingsDestructive.opacity(0.4), lineWidth: 1)
                }
            }
            .buttonStyle(SettingsPressStyle(reduceMotion: reduceMotion))
            .sensoryFeedback(.impact(weight: .light), trigger: openedSettings)
            .accessibilityLabel("Open app settings")
            .accessibilityHint("Opens Meridian in the system Settings app, where you can delete the app to remove all local data. This cannot be undone.")
            .accessibilityAddTraits(.isButton)
        }
        .accessibilityElement(children: .contain)
    }
}
