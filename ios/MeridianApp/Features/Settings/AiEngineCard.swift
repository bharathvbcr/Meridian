// AiEngineCard.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// The AI engine selector. Android shipped a static "Gemini Nano · on-device" panel; the
// iOS contract makes the engine user-selectable (On-Device / Cloud) via the persisted
// `aiEngine` setting, bound through `MainViewModel.setAiEngine`. On-device is the default
// and falls back to rules; Cloud uses a hosted model. Matches Android behavior (on-device
// first, transparent cloud fallback) while exposing the choice as an iOS-native picker.

import SwiftUI

// MARK: - Local design tokens

private extension Color {
    /// Caution accent for the Cloud privacy trade-off. Reuses the existing
    /// night/warning glow token (`daylightGlow` #FFB703) so the signal reads
    /// identically to the warning glow used elsewhere in the app.
    static let settingsCaution = MeridianColors.daylightGlow
}

// MARK: - AiEngineCard

struct AiEngineCard: View {
    @Bindable var viewModel: MainViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var engine: AiEngine { viewModel.settings.aiEngine }

    var body: some View {
        SettingsCard {
            HStack(spacing: MeridianSpacing.sm.rawValue) {
                Image(systemName: "cpu")
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.primary)
                    .accessibilityHidden(true)
                Text("Assistant engine")
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.onSurface)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text("The Assistant runs on-device with Apple Intelligence when supported — no key, and your prompts never leave the phone. Choose Cloud to always use a hosted model.")
                .font(.bodyMedium)
                .foregroundStyle(MeridianColors.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, MeridianSpacing.sm.rawValue)
                .padding(.bottom, MeridianSpacing.md.rawValue)

            Picker("Engine", selection: Binding(
                get: { engine },
                set: { viewModel.setAiEngine($0) }
            )) {
                Text("On-Device").tag(AiEngine.onDevice)
                Text("Cloud").tag(AiEngine.cloud)
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Choose where the Assistant runs")

            // Selected-engine summary line.
            HStack(spacing: MeridianSpacing.xs.rawValue + 2) {
                Image(systemName: engineIcon)
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundStyle(summaryAccent)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(engineSummary)
                    .font(.labelMedium)
                    .foregroundStyle(summaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .padding(.top, MeridianSpacing.md.rawValue)
            .accessibilityElement(children: .combine)
        }
        .animation(reduceMotion ? nil : Motion.snappy(), value: engine)
        .sensoryFeedback(.selection, trigger: engine)
    }

    private var engineIcon: String {
        engine == .onDevice ? "checkmark.seal.fill" : "cloud.fill"
    }

    /// Accent for the summary icon — positive for the private on-device path,
    /// caution for the cloud path (mirrors the text-color hierarchy).
    private var summaryAccent: Color {
        engine == .onDevice ? MeridianColors.positive : Color.settingsCaution
    }

    /// The Cloud message carries a privacy trade-off, so it reads in the caution
    /// accent; the neutral On-Device state stays in secondary text.
    private var summaryTextColor: Color {
        engine == .onDevice ? MeridianColors.onSurfaceVariant : Color.settingsCaution
    }

    private var engineSummary: String {
        switch engine {
        case .onDevice:
            return "On-device first · no key required · rules fallback"
        case .cloud:
            return "Cloud model · prompts may leave your device"
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    Color(hex: "#020617").ignoresSafeArea()
}
#endif
