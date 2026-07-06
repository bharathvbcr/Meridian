// EventCountdownLiveActivity.swift
// Meridian — iOS 27 / Swift 6 — WidgetKit extension target
//
// Live Activity UI (lock screen banner + Dynamic Island) for the "time until next event"
// countdown. Port of the Android ongoing-countdown notification (§5.7).
//
// The countdown is rendered by the system clock via `Text(timerInterval:)`, so no
// per-second push updates are needed — `LiveActivityManager` only sets the title and the
// target instant in `EventCountdownAttributes.ContentState`. This file owns presentation
// only; the attributes type is the shared `ios/Shared/EventCountdownAttributes.swift`.

import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - Widget palette
//
// Local copy of the brand colors (the app's `MeridianColors` is not linked here).

private enum LiveActivityPalette {
    static let primary  = Color(red: 0x60 / 255, green: 0xCD / 255, blue: 0xFF / 255) // #60CDFF
    static let onSurface = Color(red: 0xF1 / 255, green: 0xF5 / 255, blue: 0xF9 / 255) // #F1F5F9
    static let onSurfaceVariant = Color(red: 0x94 / 255, green: 0xA3 / 255, blue: 0xB8 / 255) // #94A3B8
    static let background = Color(red: 0x02 / 255, green: 0x06 / 255, blue: 0x17 / 255) // #020617
}

struct EventCountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EventCountdownAttributes.self) { context in
            // MARK: Lock screen / banner presentation
            LockScreenView(context: context)
                .activityBackgroundTint(LiveActivityPalette.background.opacity(0.9))
                .activitySystemActionForegroundColor(LiveActivityPalette.primary)

        } dynamicIsland: { context in
            // MARK: Dynamic Island (expanded)
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title3)
                        .foregroundStyle(LiveActivityPalette.primary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // System-rendered countdown — ticks without push updates.
                    Text(timerInterval: countdownInterval(for: context), countsDown: true)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                        .foregroundStyle(LiveActivityPalette.primary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.eventTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(LiveActivityPalette.onSurface)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        // Determinate progress across the 24 h approach window — the
                        // system advances it (Android: setProgress on the notification).
                        ProgressView(timerInterval: progressInterval(for: context), countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .progressViewStyle(.linear)
                        .tint(LiveActivityPalette.primary)
                        Text("Starts \(context.state.eventDate, style: .time)")
                            .font(.caption)
                            .foregroundStyle(LiveActivityPalette.onSurfaceVariant)
                    }
                }
            } compactLeading: {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(LiveActivityPalette.primary)
            } compactTrailing: {
                Text(timerInterval: countdownInterval(for: context), countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
                    .foregroundStyle(LiveActivityPalette.primary)
            } minimal: {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(LiveActivityPalette.primary)
            }
            .widgetURL(URL(string: "meridian://plan"))
            .keylineTint(LiveActivityPalette.primary)
        }
    }

    /// The interval the system clock counts down across: from now until the event start.
    /// Clamped so a just-passed event does not produce a negative/zero-length range.
    private func countdownInterval(
        for context: ActivityViewContext<EventCountdownAttributes>
    ) -> ClosedRange<Date> {
        let start = context.state.eventDate
        let lower = min(Date.now, start)
        return lower...max(start, lower.addingTimeInterval(1))
    }

    /// The 24 h approach window the progress bar fills across (Android:
    /// `LIVE_WINDOW_MILLIS` elapsed fraction).
    private func progressInterval(
        for context: ActivityViewContext<EventCountdownAttributes>
    ) -> ClosedRange<Date> {
        liveActivityProgressInterval(eventDate: context.state.eventDate)
    }
}

/// Shared 24 h progress window helper (lock screen + Dynamic Island).
private func liveActivityProgressInterval(eventDate: Date) -> ClosedRange<Date> {
    let end = max(eventDate, Date.now.addingTimeInterval(1))
    return end.addingTimeInterval(-24 * 3600)...end
}

// MARK: - Lock screen view

private struct LockScreenView: View {
    let context: ActivityViewContext<EventCountdownAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2)
                .foregroundStyle(LiveActivityPalette.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.eventTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(LiveActivityPalette.onSurface)
                Text("Starts \(context.state.eventDate, style: .time)")
                    .font(.caption)
                    .foregroundStyle(LiveActivityPalette.onSurfaceVariant)
            }

            Spacer(minLength: 8)

            // Countdown — rendered by the system, no push needed.
            Text(timerInterval: interval, countsDown: true)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 96)
                .foregroundStyle(LiveActivityPalette.primary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .safeAreaInset(edge: .bottom) {
            // Determinate progress across the 24 h approach window (Android: the
            // ongoing notification's progress bar).
            ProgressView(
                timerInterval: liveActivityProgressInterval(eventDate: context.state.eventDate),
                countsDown: false
            ) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(LiveActivityPalette.primary)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .padding(.top, 6)
        }
    }

    private var interval: ClosedRange<Date> {
        let start = context.state.eventDate
        let lower = min(Date.now, start)
        return lower...max(start, lower.addingTimeInterval(1))
    }
}
