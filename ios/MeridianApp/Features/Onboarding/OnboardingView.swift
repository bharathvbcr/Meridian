// OnboardingView.swift
// Meridian — iOS 27  Swift 6  SwiftUI
//
// Ported to match the Android OnboardingOverlay (source of truth):
//   - Translucent black scrim (alpha 0.55) layered OVER the live UI — the overlay
//     does NOT paint an opaque background; whatever is behind stays visible.
//   - A single glass card centered horizontally with horizontal padding.
//   - Cross-fade (fadeIn / fadeOut) between steps — NO swipe paging.
//   - Always-visible "Skip" (left) and "Next"/"Done" (right).
//   - Step dots: active = 8pt filled primary, inactive = 5pt onSurface @ 0.25.
//   - Copy / icons / labels mirror Android exactly ("Done", not "Get Started").
//
// iOS polish kept: a tasteful, bounded `.symbolEffect` on the step icon.

import SwiftUI

// MARK: - OnboardingStep model

struct OnboardingStep: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let body: String
}

// MARK: - Steps data (copy mirrors Android STEPS)

private let onboardingSteps: [OnboardingStep] = [
    OnboardingStep(
        id: 0,
        icon: "safari",                     // Android: Icons.Filled.Explore
        title: "Welcome to Meridian",
        body: "A time-zone companion built for people who live and work across the world."
    ),
    OnboardingStep(
        id: 1,
        icon: "clock",                      // Android: Icons.Filled.Schedule
        title: "Now",
        body: "Your local time at a glance — sunrise, sunset, working hours, and favourite world clocks all in one card."
    ),
    OnboardingStep(
        id: 2,
        icon: "globe",                      // Android: Icons.Filled.Public
        title: "World Clock",
        body: "A live globe shows you what every time zone looks like right now. Scrub through time to plan ahead."
    ),
    OnboardingStep(
        id: 3,
        icon: "calendar",                   // Android: Icons.Filled.DateRange
        title: "Planner",
        body: "Find fair meeting windows for distributed teams. Meridian ranks overlap times so no one always loses sleep."
    ),
    OnboardingStep(
        id: 4,
        icon: "sparkles",                   // Android: Icons.Filled.AutoAwesome
        title: "AI Assistant",
        body: "Ask natural-language questions about times and meetings. Answers run on-device when your phone supports it."
    )
]

// MARK: - OnboardingView

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var currentStep: Int = 0

    private var isLastStep: Bool { currentStep == onboardingSteps.count - 1 }

    var body: some View {
        ZStack {
            // Translucent scrim over the live UI (Android: Color.Black @ 0.55).
            // No opaque background — the app remains visible behind the overlay.
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            // Centered glass card with horizontal padding (Android: 28dp).
            VStack(spacing: 28) {
                // Cross-fading step content.
                ZStack {
                    ForEach(onboardingSteps) { step in
                        if step.id == currentStep {
                            OnboardingStepContent(step: step)
                                .transition(.opacity)
                        }
                    }
                }
                .animation(Motion.smooth(), value: currentStep)

                // Step dots.
                StepDots(total: onboardingSteps.count, current: currentStep)

                // Skip (left) + Next/Done (right) — both always visible.
                HStack {
                    Button {
                        withAnimation(Motion.smooth()) { onComplete() }
                    } label: {
                        Text("Skip")
                            .font(.titleMedium)
                            .foregroundStyle(MeridianColors.onSurfaceVariant)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        withAnimation(Motion.smooth()) {
                            if isLastStep {
                                onComplete()
                            } else {
                                currentStep += 1
                            }
                        }
                    } label: {
                        Text(isLastStep ? "Done" : "Next")
                            .font(.titleMedium)
                            .foregroundStyle(MeridianColors.background)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background {
                                Capsule().fill(MeridianColors.primary)
                            }
                    }
                    .buttonStyle(.plain)
                    .animation(Motion.snappy(), value: isLastStep)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.60))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(MeridianColors.primary.opacity(0.06))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    }
            }
            .padding(.horizontal, 28)
        }
    }
}

// MARK: - OnboardingStepContent

private struct OnboardingStepContent: View {
    let step: OnboardingStep

    var body: some View {
        VStack(spacing: 0) {
            OnboardingIcon(systemName: step.icon)

            Spacer().frame(height: 16)

            Text(step.title)
                .font(.headlineMedium)
                .foregroundStyle(MeridianColors.onSurface)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 10)

            Text(step.body)
                .font(.bodyMedium)
                .foregroundStyle(MeridianColors.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - OnboardingIcon

private struct OnboardingIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 52, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(MeridianColors.primary)
            // Tasteful iOS polish: a gentle, bounded pulse on appearance.
            // VERIFY: `.symbolEffect(.bounce, options:)` available on iOS 27.
            .symbolEffect(.bounce, options: .nonRepeating)
            .id(systemName)
    }
}

// MARK: - StepDots (active = 8pt filled, inactive = 5pt @ 0.25 — matches Android)

private struct StepDots: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< total, id: \.self) { index in
                Circle()
                    .fill(
                        index == current
                            ? MeridianColors.primary
                            : MeridianColors.onSurface.opacity(0.25)
                    )
                    .frame(
                        width: index == current ? 8 : 5,
                        height: index == current ? 8 : 5
                    )
            }
        }
        .animation(Motion.snappy(), value: current)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("OnboardingView") {
    ZStack {
        MeridianColors.background.ignoresSafeArea()
        OnboardingView(onComplete: { })
    }
}
#endif
