// LegalNoticeSheet.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// A bottom sheet that renders a `LegalDocument`: scrollable body, an optional external
// link (or, for third-party policies, two named buttons), a "Copy text" action, and a
// Close button. Behavioral port of Android `LegalNoticeSheet` (the GlassBottomSheet in
// SettingsScreen.kt). Uses the shared liquid-glass treatment for the iOS-native frosted look.

import SwiftUI
import UIKit

// MARK: - Local press feedback

/// Pressed feedback for the link / copy affordances in this sheet: a small scale +
/// opacity dip on `Motion.quick()`, gated on Reduce Motion so the press stays
/// instantaneous when the user opts out of animation. Mirrors `SettingsPressStyle`
/// in the sibling Settings cards so all Settings CTAs share one press language.
private struct LegalPressStyle: ButtonStyle {
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(reduceMotion ? nil : Motion.quick(), value: configuration.isPressed)
    }
}

// MARK: - LegalNoticeSheet

struct LegalNoticeSheet: View {
    let document: LegalDocument
    var onDismiss: () -> Void

    @State private var copied = false
    /// Bumped on every external-link tap so `.sensoryFeedback` fires on the
    /// actual interaction (a constant title/url would only trigger once on appear).
    @State private var linkTapTick = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Standard iOS minimum touch target — reused across the tappable affordances here.
    private let hitTarget: CGFloat = 44

    var body: some View {
        NavigationStack {
            ZStack {
                MeridianColors.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: MeridianSpacing.md.rawValue) {
                            Text(document.body)
                                .font(.bodyLarge)
                                .foregroundStyle(MeridianColors.onSurface)
                                .lineSpacing(MeridianSpacing.xs.rawValue)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel("\(document.title). \(document.body)")

                            externalLinks
                                .sensoryFeedback(.impact(weight: .light), trigger: linkTapTick)
                        }
                        .padding(MeridianSpacing.xl.rawValue)
                    }

                    footer
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MeridianColors.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { close() }
                        .foregroundStyle(MeridianColors.primary)
                        .accessibilityHint("Dismisses the \(document.title) document")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(MeridianColors.background)
    }

    // MARK: External link affordances

    @ViewBuilder
    private var externalLinks: some View {
        if document == .thirdPartyPolicies {
            VStack(spacing: MeridianSpacing.sm.rawValue) {
                linkButton(title: "Google Privacy Policy", url: SettingsUrls.googlePrivacy)
                linkButton(title: "Firebase Terms of Service", url: SettingsUrls.firebaseTerms)
            }
            .padding(.top, MeridianSpacing.xs.rawValue)
        } else if let url = document.externalURL {
            let label = document.externalLabel ?? "Learn more"
            Button {
                linkTapTick += 1
                SettingsActions.openWebURL(url)
            } label: {
                HStack(spacing: MeridianSpacing.sm.rawValue) {
                    Text(label)
                        .font(.titleMedium)
                    Image(systemName: "arrow.up.right")
                        .font(.labelMedium)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(MeridianColors.primary)
                .frame(minHeight: hitTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(LegalPressStyle(reduceMotion: reduceMotion))
            .padding(.top, MeridianSpacing.xs.rawValue)
            .accessibilityLabel(label)
            .accessibilityHint("Opens in your browser")
            .accessibilityAddTraits(.isLink)
        }
    }

    @ViewBuilder
    private func linkButton(title: String, url: String) -> some View {
        Button {
            linkTapTick += 1
            SettingsActions.openWebURL(url)
        } label: {
            HStack {
                Text(title)
                    .font(.titleMedium)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.labelMedium)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(MeridianColors.primary)
            .padding(.horizontal, MeridianSpacing.md.rawValue)
            .padding(.vertical, MeridianSpacing.md.rawValue)
            .frame(maxWidth: .infinity, minHeight: hitTarget)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                    .strokeBorder(MeridianColors.primary.opacity(0.4), lineWidth: 1)
            }
        }
        .buttonStyle(LegalPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(title)
        .accessibilityHint("Opens in your browser")
        .accessibilityAddTraits(.isLink)
    }

    // MARK: Footer (copy action)

    private var footer: some View {
        Button {
            UIPasteboard.general.string = document.body
            withAnimation(Motion.reduced(Motion.smooth(), reduceMotion: reduceMotion)) {
                copied = true
            }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(Motion.reduced(Motion.smooth(), reduceMotion: reduceMotion)) {
                    copied = false
                }
            }
        } label: {
            HStack(spacing: MeridianSpacing.sm.rawValue) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.titleMedium)
                    .accessibilityHidden(true)
                Text(copied ? "Copied" : "Copy text")
                    .font(.titleMedium)
            }
            .foregroundStyle(copied ? MeridianColors.positive : MeridianColors.primary)
            .frame(maxWidth: .infinity, minHeight: hitTarget)
            .contentShape(Rectangle())
            .background {
                Capsule(style: .continuous)
                    .strokeBorder(
                        (copied ? MeridianColors.positive : MeridianColors.primary).opacity(0.4),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(LegalPressStyle(reduceMotion: reduceMotion))
        .sensoryFeedback(.success, trigger: copied)
        .accessibilityLabel(copied ? "Copied to clipboard" : "Copy document text")
        .accessibilityHint("Copies the full \(document.title) text to your clipboard")
        .padding(.horizontal, MeridianSpacing.xl.rawValue)
        .padding(.vertical, MeridianSpacing.lg.rawValue)
        .background {
            // Shared liquid-glass surface for the footer bar (matches GlassBottomSheet),
            // with a hairline top divider so the action bar reads as anchored chrome.
            MeridianColors.surface.opacity(0.6)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(MeridianColors.onSurface.opacity(0.08))
                        .frame(height: 0.5)
                }
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func close() {
        onDismiss()
        dismiss()
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Privacy") {
    LegalNoticeSheet(document: .privacy, onDismiss: {})
        .preferredColorScheme(.dark)
}

#Preview("Third-party policies") {
    LegalNoticeSheet(document: .thirdPartyPolicies, onDismiss: {})
        .preferredColorScheme(.dark)
}
#endif
