// SupportCard.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// The "Support" links section: send feedback (mail compose with diagnostics, or a share
// sheet fallback), rate the app, and jump to the app's page in the system Settings app.
// Behavioral port of Android `SupportCard`.

import SwiftUI

// MARK: - Local design tokens

// These file-scoped aliases keep call sites terse while sourcing every value from the
// shared `MeridianColors` palette, so there is no hardcoded hex that duplicates a token.
private extension Color {
    static let settingsPrimary      = MeridianColors.primary
    static let settingsOnSurface    = MeridianColors.onSurface
    static let settingsOnSurfaceVar = MeridianColors.onSurfaceVariant
}

// MARK: - SupportCard

struct SupportCard: View {
    @State private var showShareFallback = false
    @State private var shareText = ""

    var body: some View {
        SettingsCard {
            Text("Support")
                .font(.titleMedium)
                .foregroundStyle(Color.settingsOnSurface)
                .padding(.bottom, MeridianSpacing.xs.rawValue)
                .accessibilityAddTraits(.isHeader)

            SettingsLinkRow(
                icon: "envelope",
                title: "Send feedback",
                subtitle: "Email or share diagnostics with your report",
                opensExternally: true,
                accessibilityHint: "Opens your mail app"
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
                subtitle: "Leave a review if Meridian helps you",
                opensExternally: true,
                accessibilityHint: "Opens the App Store"
            ) {
                SettingsActions.openAppStoreReview()
            }

            SettingsLinkDivider()

            SettingsLinkRow(
                icon: "arrow.up.right.square",
                title: "App permissions in system settings",
                subtitle: "Review or revoke access granted to Meridian",
                opensExternally: true,
                accessibilityHint: "Opens the system Settings app"
            ) {
                SettingsActions.openAppSettings()
            }
        }
        .glassBottomSheet(isPresented: $showShareFallback) {
            ShareFallbackSheet(shareText: shareText)
        }
    }
}

// MARK: - ShareFallbackSheet

/// Presented only when no mail client is installed: a titled, card-aligned explanation
/// with a share action so the diagnostics report can still leave the device.
private struct ShareFallbackSheet: View {
    let shareText: String

    var body: some View {
        VStack(alignment: .leading, spacing: MeridianSpacing.md.rawValue) {
            VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue) {
                Text("No mail app found")
                    .font(.headlineMedium)
                    .foregroundStyle(Color.settingsOnSurface)

                Text("We couldn't open a mail composer on this device. Share your diagnostics report through another app instead.")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.settingsOnSurfaceVar)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            ShareLink(item: shareText) {
                HStack(spacing: MeridianSpacing.sm.rawValue) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Share report")
                        .font(.titleMedium)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(MeridianColors.onPrimary)
                .padding(.vertical, MeridianSpacing.md.rawValue)
                .padding(.horizontal, MeridianSpacing.lg.rawValue)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                        .fill(Color.settingsPrimary)
                )
            }
            .accessibilityLabel("Share report")
            .accessibilityHint("Opens the share sheet")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MeridianSpacing.lg.rawValue)
        .presentationDetents([.medium])
    }
}

// MARK: - SettingsLinkRow

/// A tappable settings row: leading icon, title + subtitle, trailing chevron (or an
/// outward arrow for rows that leave the app).
/// Shared by Support and Legal sections (Android `SettingsLinkRow`).
struct SettingsLinkRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    /// When true the row hands off to another app; it shows an outward arrow and
    /// exposes an external-navigation hint to VoiceOver.
    var opensExternally: Bool = false
    var accessibilityHint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MeridianSpacing.md.rawValue) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.settingsPrimary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.settingsOnSurface)
                    if let subtitle {
                        Text(subtitle)
                            .font(.labelMedium)
                            .foregroundStyle(Color.settingsOnSurfaceVar)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: MeridianSpacing.sm.rawValue)

                Image(systemName: opensExternally ? "arrow.up.right" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.settingsOnSurfaceVar.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(accessibilityHint ?? "")
        .sensoryFeedback(.selection, trigger: title)
    }
}

// MARK: - SettingsRowButtonStyle

/// Lightweight list-cell press feedback: a faint primary-tinted highlight and gentle
/// dim on touch-down, so taps read as intentional the way a native cell does.
private struct SettingsRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                    .fill(MeridianColors.primary.opacity(configuration.isPressed ? 0.06 : 0))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.reducedOrInstant(Motion.quick(), reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}

// MARK: - SettingsLinkDivider

struct SettingsLinkDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
