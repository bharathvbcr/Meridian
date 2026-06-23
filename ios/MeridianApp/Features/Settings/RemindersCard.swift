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

// MARK: - Local design tokens

private extension Color {
    static let settingsPrimary      = Color(hex: "#60CDFF")
    static let settingsOnSurface    = Color(hex: "#F1F5F9")
    static let settingsOnSurfaceVar = Color(hex: "#94A3B8")
}

// MARK: - RemindersCard

struct RemindersCard: View {
    @Bindable var viewModel: MainViewModel

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
        VStack(spacing: 16) {
            remindersSection
            workHoursSection
        }
    }

    // MARK: Reminders

    private var remindersSection: some View {
        SettingsCard {
            header(icon: "bell.badge", title: "Alarm Lead Time")

            Text("Adjust how many minutes before an event the reminder notification fires.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.settingsOnSurfaceVar)
                .padding(.top, 4)
                .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
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
        }
    }

    // MARK: Work hours

    private var workHoursSection: some View {
        SettingsCard {
            header(icon: "briefcase", title: "Default Work Hours")

            Text("The standard business-hours window. New planner participants default to these values.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.settingsOnSurfaceVar)
                .padding(.top, 4)
                .padding(.bottom, 12)

            VStack(spacing: 14) {
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
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

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
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.settingsPrimary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.settingsOnSurface)
        }
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

    private var formattedTime: String {
        let h = ((hour % 24) + 24) % 24
        let period = h < 12 ? "AM" : "PM"
        let displayH = h % 12 == 0 ? 12 : h % 12
        return "\(displayH):00 \(period)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.settingsPrimary)
                .frame(width: 24)

            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.settingsOnSurface)

            Spacer()

            Text(formattedTime)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.settingsPrimary)
                .monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)
                .contentTransition(.numericText())

            stepButton(systemName: "minus") {
                onChange(max(0, hour - 1))
            }
            .disabled(hour <= 0)

            stepButton(systemName: "plus") {
                onChange(min(23, hour + 1))
            }
            .disabled(hour >= 23)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hour)
    }

    @ViewBuilder
    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.settingsPrimary)
                .frame(width: 30, height: 30)
                .background {
                    Circle().fill(Color.settingsPrimary.opacity(0.12))
                }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: hour)
    }
}
