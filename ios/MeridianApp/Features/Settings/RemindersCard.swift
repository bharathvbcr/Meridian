// RemindersCard.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// Two settings sections combined into one logical card:
//   • Event reminders — how many minutes before an event the local notification fires
//     (Android `RemindersCard`).
//   • Default work hours — the work-window start/end applied to new planner participants
//     (Android `WorkHoursCard`).
//
// Bound to `MainViewModel` settings delegates: `setReminderLeadMinutes`,
// `setDefaultWorkStartHour`, `setDefaultWorkEndHour`. The end hour is kept strictly
// greater than the start hour (Android invariant: bumping start past end pushes end up).

import SwiftUI

// MARK: - RemindersCard

struct RemindersCard: View {
    /// Which of the two logical cards to render. Android splits these into separate
    /// collapsible sections (REMINDERS / WORK_HOURS); `.both` keeps the combined
    /// rendering for any caller that wants the original stacked layout.
    enum Part {
        case reminders
        case workHours
        case both
    }

    @Bindable var viewModel: MainViewModel
    var part: Part = .both

    /// Lead-time options in minutes. The first entry is the disable sentinel: `-1`
    /// matches Android's "Disabled" option (the scheduler's `guard leadMinutes >= 0`
    /// suppresses/cancels the reminder). `0` would mean "fire at event time", which is
    /// NOT a disable — so the off option must persist as `-1`, and the settings store
    /// must not clamp lead minutes up to `0`.
    private let leadOptions: [(minutes: Int, label: String)] = [
        (-1, "Off"),
        (5, "5m"),
        (10, "10m"),
        (15, "15m"),
        (30, "30m"),
        (60, "1h"),
    ]

    var body: some View {
        switch part {
        case .reminders:
            remindersSection
        case .workHours:
            workHoursSection
        case .both:
            VStack(spacing: 16) {
                remindersSection
                workHoursSection
            }
        }
    }

    // MARK: Reminders

    private var remindersSection: some View {
        SettingsCard {
            header(icon: "bell.badge", title: "Alarm Lead Time")

            Text("Adjust how many minutes before an event the reminder notification fires.")
                .font(.labelMedium)
                .foregroundStyle(MeridianColors.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, MeridianSpacing.xs.rawValue)
                .padding(.bottom, MeridianSpacing.md.rawValue)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MeridianSpacing.sm.rawValue) {
                    ForEach(leadOptions, id: \.minutes) { option in
                        MeridianChip(
                            label: option.label,
                            isSelected: viewModel.settings.reminderLeadMinutes == option.minutes
                        ) {
                            viewModel.setReminderLeadMinutes(option.minutes)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Text(reminderLeadSummary)
                .font(.labelMedium)
                .foregroundStyle(MeridianColors.onSurfaceVariant)
                .padding(.top, MeridianSpacing.sm.rawValue)
                .contentTransition(.opacity)
                .accessibilityLabel(reminderLeadSummary)
        }
        .accessibilityElement(children: .contain)
    }

    /// Textual echo of the active lead-time so "Off" vs a minute value is unambiguous
    /// (mirrors the summary-line pattern used by `AiEngineCard`).
    private var reminderLeadSummary: String {
        let minutes = viewModel.settings.reminderLeadMinutes
        guard minutes >= 0 else { return "Reminders off" }
        if let match = leadOptions.first(where: { $0.minutes == minutes }) {
            return "Fires \(match.label) before"
        }
        return "Fires \(minutes) min before"
    }

    // MARK: Work hours

    private var workHoursSection: some View {
        SettingsCard {
            header(icon: "briefcase", title: "Default Work Hours")

            Text("The standard business-hours window. New planner participants default to these values.")
                .font(.labelMedium)
                .foregroundStyle(MeridianColors.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, MeridianSpacing.xs.rawValue)
                .padding(.bottom, MeridianSpacing.md.rawValue)

            VStack(spacing: MeridianSpacing.md.rawValue) {
                WorkHourStepperRow(
                    label: "Work Start",
                    icon: "sunrise",
                    hour: viewModel.settings.defaultWorkStartHour
                ) { newStart in
                    viewModel.setDefaultWorkStartHour(newStart)
                    // Keep end strictly after start (Android invariant).
                    if newStart >= viewModel.settings.defaultWorkEndHour {
                        viewModel.setDefaultWorkEndHour(min(23, newStart + 1))
                    }
                }

                Rectangle()
                    .fill(MeridianColors.onSurface.opacity(0.08))
                    .frame(height: 1)
                    .accessibilityHidden(true)

                WorkHourStepperRow(
                    label: "Work End",
                    icon: "sunset",
                    hour: viewModel.settings.defaultWorkEndHour
                ) { newEnd in
                    if newEnd > viewModel.settings.defaultWorkStartHour {
                        viewModel.setDefaultWorkEndHour(newEnd)
                    }
                }
            }
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func header(icon: String, title: String) -> some View {
        HStack(spacing: MeridianSpacing.sm.rawValue) {
            Image(systemName: icon)
                .font(.titleMedium)
                .foregroundStyle(MeridianColors.primary)
                .accessibilityHidden(true)
            Text(title)
                .font(.titleMedium)
                .foregroundStyle(MeridianColors.onSurface)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - WorkHourStepperRow

/// A label + −/+ stepper bound to a 0...23 hour, showing a formatted 12-hour time.
/// Mirrors Android `HourStepperRow` (named distinctly to avoid colliding with the
/// planner's own `HourStepperRow`).
struct WorkHourStepperRow: View {
    let label: String
    let icon: String
    let hour: Int
    let onChange: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var formattedTime: String {
        let h = ((hour % 24) + 24) % 24
        let period = h < 12 ? "AM" : "PM"
        let displayH = h % 12 == 0 ? 12 : h % 12
        return "\(displayH):00 \(period)"
    }

    private func decrement() {
        guard hour > 0 else { return }
        onChange(max(0, hour - 1))
    }

    private func increment() {
        guard hour < 23 else { return }
        onChange(min(23, hour + 1))
    }

    var body: some View {
        HStack(spacing: MeridianSpacing.md.rawValue) {
            Image(systemName: icon)
                .font(.bodyMedium.weight(.semibold))
                .foregroundStyle(MeridianColors.primary)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(label)
                .font(.bodyLarge.weight(.semibold))
                .foregroundStyle(MeridianColors.onSurface)

            Spacer(minLength: MeridianSpacing.sm.rawValue)

            Text(formattedTime)
                .font(.bodyMedium.weight(.semibold))
                .foregroundStyle(MeridianColors.primary)
                .monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)
                .contentTransition(.numericText())

            stepButton(systemName: "minus", accessibilityLabel: "Decrease \(label)") {
                decrement()
            }
            .disabled(hour <= 0)

            stepButton(systemName: "plus", accessibilityLabel: "Increase \(label)") {
                increment()
            }
            .disabled(hour >= 23)
        }
        .animation(reduceMotion ? nil : Motion.snappy(), value: hour)
        // Present the whole row as one native-stepper-like adjustable element so
        // VoiceOver reads "<label>, <time>" and swipe up/down changes the hour.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(formattedTime)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: increment()
            case .decrement: decrement()
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private func stepButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.labelMedium.weight(.bold))
                .foregroundStyle(MeridianColors.primary)
                .frame(width: 30, height: 30)
                .background {
                    Circle().fill(MeridianColors.primary.opacity(0.12))
                }
                // Keep the 30pt glass circle, but expand the tappable region to the
                // 44pt minimum without enlarging the visual affordance.
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: hour)
        .accessibilityLabel(accessibilityLabel)
        // The parent row is the adjustable stepper; hide the raw +/- from VoiceOver.
        .accessibilityHidden(true)
    }
}
