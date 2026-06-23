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
    static let settingsPrimary      = Color(hex: "#60CDFF")
    static let settingsOnSurface    = Color(hex: "#F1F5F9")
    static let settingsOnSurfaceVar = Color(hex: "#94A3B8")
    static let settingsPositive     = Color(hex: "#4CAF50")
}

// MARK: - AiEngineCard

struct AiEngineCard: View {
    @Bindable var viewModel: MainViewModel

    private var engine: AiEngine { viewModel.settings.aiEngine }

    var body: some View {
        SettingsCard {
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.settingsPrimary)
                Text("Assistant engine")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.settingsOnSurface)
            }

            Text("The Assistant runs on-device with Apple Intelligence when supported — no key, and your prompts never leave the phone. Choose Cloud to always use a hosted model.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.settingsOnSurfaceVar)
                .padding(.top, 8)
                .padding(.bottom, 12)

            Picker("Engine", selection: Binding(
                get: { engine },
                set: { viewModel.setAiEngine($0) }
            )) {
                Text("On-Device").tag(AiEngine.onDevice)
                Text("Cloud").tag(AiEngine.cloud)
            }
            .pickerStyle(.segmented)

            // Selected-engine summary line.
            HStack(spacing: 6) {
                Image(systemName: engineIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(engine == .onDevice ? Color.settingsPositive : Color.settingsPrimary)
                Text(engineSummary)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.settingsOnSurfaceVar)
            }
            .padding(.top, 12)
        }
    }

    private var engineIcon: String {
        engine == .onDevice ? "checkmark.seal.fill" : "cloud.fill"
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
