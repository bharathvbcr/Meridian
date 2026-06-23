// SupportCard.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// The "Support" links section: send feedback (mail compose with diagnostics, or a share
// sheet fallback), rate the app, and jump to the app's page in the system Settings app.
// Behavioral port of Android `SupportCard`.

import SwiftUI

// MARK: - Local design tokens

private extension Color {
    static let settingsPrimary      = Color(hex: "#60CDFF")
    static let settingsOnSurface    = Color(hex: "#F1F5F9")
    static let settingsOnSurfaceVar = Color(hex: "#94A3B8")
}

// MARK: - SupportCard

struct SupportCard: View {
    @State private var showShareFallback = false
    @State private var shareText = ""

    var body: some View {
        SettingsCard {
            Text("Support")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.settingsOnSurface)
                .padding(.bottom, 4)

            SettingsLinkRow(
                icon: "envelope",
                title: "Send feedback",
                subtitle: "Email or share diagnostics with your report"
            ) {
                if !SettingsActions.openFeedbackMail() {
                    // No mail client — fall back to the share sheet.
                    shareText = SettingsActions.feedbackBody()
                    showShareFallback = true
                }
            }

            SettingsLinkDivider()

            SettingsLinkRow(
                icon: "star",
                title: "Rate on the App Store",
                subtitle: "Leave a review if Meridian helps you"
            ) {
                SettingsActions.openAppStoreReview()
            }

            SettingsLinkDivider()

            SettingsLinkRow(
                icon: "arrow.up.right.square",
                title: "App permissions in system settings",
                subtitle: "Review or revoke access granted to Meridian"
            ) {
                SettingsActions.openAppSettings()
            }
        }
        .sheet(isPresented: $showShareFallback) {
            ShareLink(item: shareText) {
                Label("Share feedback", systemImage: "square.and.arrow.up")
            }
            .padding()
            .presentationDetents([.medium])
        }
    }
}

// MARK: - SettingsLinkRow

/// A tappable settings row: leading icon, title + subtitle, trailing chevron.
/// Shared by Support and Legal sections (Android `SettingsLinkRow`).
struct SettingsLinkRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.settingsPrimary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.settingsOnSurface)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.settingsOnSurfaceVar)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.settingsOnSurfaceVar.opacity(0.6))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: title)
    }
}

// MARK: - SettingsLinkDivider

struct SettingsLinkDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }
}
