// LegalNoticeSheet.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// A bottom sheet that renders a `LegalDocument`: scrollable body, an optional external
// link (or, for third-party policies, two named buttons), a "Copy text" action, and a
// Close button. Behavioral port of Android `LegalNoticeSheet` (the GlassBottomSheet in
// SettingsScreen.kt). Uses `.glassEffect` for the iOS-native frosted look.

import SwiftUI
import UIKit

// MARK: - Local design tokens

private extension Color {
    static let settingsPrimary      = Color(hex: "#60CDFF")
    static let settingsBackground   = Color(hex: "#020617")
    static let settingsOnSurface    = Color(hex: "#F1F5F9")
    static let settingsOnSurfaceVar = Color(hex: "#94A3B8")
}

// MARK: - LegalNoticeSheet

struct LegalNoticeSheet: View {
    let document: LegalDocument
    var onDismiss: () -> Void

    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.settingsBackground.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(document.body)
                                .font(.system(size: 15))
                                .foregroundStyle(Color.settingsOnSurface.opacity(0.85))
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            externalLinks
                        }
                        .padding(20)
                    }

                    footer
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.settingsBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { close() }
                        .foregroundStyle(Color.settingsPrimary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    // MARK: External link affordances

    @ViewBuilder
    private var externalLinks: some View {
        if document == .thirdPartyPolicies {
            VStack(spacing: 8) {
                linkButton(title: "Google Privacy Policy", url: SettingsUrls.googlePrivacy)
                linkButton(title: "Firebase Terms of Service", url: SettingsUrls.firebaseTerms)
            }
            .padding(.top, 4)
        } else if let url = document.externalURL {
            Button {
                SettingsActions.openWebURL(url)
            } label: {
                Text(document.externalLabel ?? "Learn more")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.settingsPrimary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func linkButton(title: String, url: String) -> some View {
        Button {
            SettingsActions.openWebURL(url)
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.settingsPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.settingsPrimary.opacity(0.4), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer (copy + close)

    private var footer: some View {
        HStack {
            Button {
                UIPasteboard.general.string = document.body
                withAnimation { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { copied = false }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                    Text(copied ? "Copied" : "Copy text")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.settingsPrimary)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: copied)

            Spacer()

            Button("Close") { close() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.settingsOnSurfaceVar)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
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
