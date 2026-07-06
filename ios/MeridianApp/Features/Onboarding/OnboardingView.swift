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
    @State private var advanceTrigger = 0
    @State private var skipTrigger = 0

    /// Drives an `AccessibilityFocusState` move so VoiceOver re-reads the card
    /// each time the step advances (the silent cross-fade otherwise conveys nothing).
    @AccessibilityFocusState private var stepFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLastStep: Bool { currentStep == onboardingSteps.count - 1 }

    private var currentStepModel: OnboardingStep { onboardingSteps[currentStep] }

    /// Spring used for the step advance; collapses to no animation under Reduce Motion.
    private var stepTransition: Animation? {
        reduceMotion ? nil : Motion.smooth()
    }

    var body: some View {
        ZStack {
            // Translucent scrim over the live UI (Android: Color.Black @ 0.55).
            // No opaque background — the app remains visible behind the overlay.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            // Centered glass card with horizontal padding (Android: 28dp).
            VStack(spacing: MeridianSpacing.xxl.rawValue) {
                // Cross-fading step content. Combined into one accessibility
                // element so VoiceOver reads icon-title-body as a single unit,
                // and re-focused on step change so the advance is announced.
                ZStack {
                    ForEach(onboardingSteps) { step in
                        if step.id == currentStep {
                            OnboardingStepContent(step: step)
                                .transition(.opacity)
                        }
                    }
                }
                // Reserve height so differing body lengths settle smoothly
                // instead of popping the card between steps, and so scaled
                // Dynamic Type still expands the card without clipping.
                .frame(minHeight: 168)
                .animation(stepTransition, value: currentStep)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(currentStepModel.title). \(currentStepModel.body)"))
                .accessibilityValue(Text("Step \(currentStep + 1) of \(onboardingSteps.count)"))
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($stepFocused)

                // Step dots — decorative visually, but expose progress to VoiceOver.
                StepDots(total: onboardingSteps.count, current: currentStep)

                // Skip (left) + Next/Done (right) — both always visible.
                HStack {
                    Button {
                        skipTrigger &+= 1
                        withAnimation(stepTransition) { onComplete() }
                    } label: {
                        Text("Skip")
                            .font(.titleMedium)
                            .foregroundStyle(MeridianColors.onSurfaceVariant)
                            .padding(.horizontal, MeridianSpacing.lg.rawValue)
                            .padding(.vertical, MeridianSpacing.md.rawValue)
                            // Guarantee a >=44pt hit target for the text-only button.
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Skip"))
                    .accessibilityHint(Text("Skips the introduction and opens Meridian"))
                    .accessibilityAddTraits(.isButton)

                    Spacer()

                    Button {
                        advanceTrigger &+= 1
                        withAnimation(stepTransition) {
                            if isLastStep {
                                onComplete()
                            } else {
                                currentStep += 1
                            }
                        }
                    } label: {
                        Text(isLastStep ? "Done" : "Next")
                            .font(.titleMedium)
                            .foregroundStyle(MeridianColors.onPrimary)
                            .padding(.horizontal, MeridianRadius.large.rawValue)
                            .padding(.vertical, MeridianSpacing.md.rawValue)
                            .frame(minHeight: 44)
                            .background {
                                Capsule().fill(MeridianColors.primary)
                            }
                    }
                    .buttonStyle(.plain)
                    .animation(reduceMotion ? nil : Motion.snappy(), value: isLastStep)
                    .accessibilityLabel(Text(isLastStep ? "Done" : "Next"))
                    .accessibilityHint(Text(isLastStep ? "Finishes onboarding and opens Meridian" : "Shows the next introduction step"))
                    .accessibilityAddTraits(.isButton)
                }
            }
            .padding(.horizontal, MeridianSpacing.xxl.rawValue)
            .padding(.vertical, MeridianRadius.large.rawValue)
            .frame(maxWidth: .infinity)
            // Compose with the shared liquid-glass surface so the card refracts
            // the celestial backdrop identically to Now's cards and honors the
            // reduce-transparency override, instead of a bespoke material trick.
            .liquidGlass(cornerRadius: MeridianRadius.large.rawValue)
            .padding(.horizontal, MeridianRadius.large.rawValue)
        }
        .sensoryFeedback(.selection, trigger: advanceTrigger)
        .sensoryFeedback(.impact(weight: .light), trigger: skipTrigger)
        // Move VoiceOver focus to the freshly cross-faded card so the step
        // change is announced non-visually.
        .onChange(of: currentStep) { _, _ in
            stepFocused = true
        }
        .onAppear { stepFocused = true }
    }
}

// MARK: - OnboardingStepContent

private struct OnboardingStepContent: View {
    let step: OnboardingStep

    var body: some View {
        VStack(spacing: 0) {
            OnboardingIcon(systemName: step.icon)
                // Decorative — the combined parent label carries the meaning.
                .accessibilityHidden(true)

            Spacer().frame(height: MeridianSpacing.lg.rawValue)

            Text(step.title)
                .font(.headlineMedium)
                .foregroundStyle(MeridianColors.onSurface)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: MeridianSpacing.sm.rawValue)

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 52, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(MeridianColors.primary)
            // Tasteful iOS polish: a gentle, bounded pulse on appearance —
            // suppressed under Reduce Motion (the icon itself is unchanged).
            .symbolEffect(.bounce, options: .nonRepeating, isActive: !reduceMotion)
            .id(systemName)
    }
}

// MARK: - StepDots (active = 8pt filled, inactive = 5pt @ 0.25 — matches Android)

private struct StepDots: View {
    let total: Int
    let current: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: MeridianSpacing.xs.rawValue + 2) {
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
        .animation(reduceMotion ? nil : Motion.snappy(), value: current)
        // Purely decorative — progress is already conveyed via the step card's
        // accessibilityValue, so avoid double-announcing "Step X of Y".
        .accessibilityHidden(true)
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
