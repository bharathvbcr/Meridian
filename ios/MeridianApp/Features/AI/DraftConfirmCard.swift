// DraftConfirmCard.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// Confirm-before-write card for a model-proposed event (§12.8). The assistant
// never auto-writes a `PlannedTask`; it proposes one as `MainViewModel.pendingDraft`
// and the user confirms here. Mirrors the Android `DraftConfirmCard` in
// feature/ai/AiScreen.kt:
//   • "Add to plan"  → confirm (MainViewModel.confirmDraft)
//   • "Calendar"     → insert a real EventKit event (CalendarRepository.insertEvent)
//   • "Share .ics"   → export + share an .ics file (ICSGenerator + share sheet)
//   • "Discard"      → discard (MainViewModel.discardDraft)
//
// The model never computes the timestamp; `draft.timestamp` is an absolute `Date`
// resolved locally by ScheduleParser. Rendering it to wall-clock is the view's job.

import SwiftUI

// MARK: - DraftConfirmCard

struct DraftConfirmCard: View {

    let draft: PlannedTask
    let is24Hour: Bool
    let onConfirm: () -> Void
    let onDiscard: () -> Void

    // EventKit writes are serialized through this actor (created locally; stateless wrapper).
    private let calendarRepo = CalendarRepository()

    @State private var exportError: String? = nil
    @State private var shareURL: ShareItem? = nil
    @State private var feedbackTrigger: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Derived display

    private var whenText: String {
        TimeFormats.fullDateTime(date: draft.timestamp, timeZoneId: draft.tzId, use24Hour: is24Hour)
    }

    /// Last IANA segment with underscores replaced by spaces (Android `shortZone`).
    private var shortZone: String {
        draft.tzId.split(separator: "/").last.map {
            $0.replacingOccurrences(of: "_", with: " ")
        } ?? draft.tzId
    }

    /// Day/night solar glyph for the when-line, resolved in the draft's own zone
    /// (parity with the `todIcon` derivation in `QuickScheduleCard`).
    private var isDaytime: Bool {
        var calendar = Calendar(identifier: .gregorian)
        if let zone = TimeZone(identifier: draft.tzId) {
            calendar.timeZone = zone
        }
        let hour = calendar.component(.hour, from: draft.timestamp)
        return hour >= 6 && hour < 18
    }

    private var todIcon: String { isDaytime ? "sun.max.fill" : "moon.stars.fill" }
    private var todAccent: Color { isDaytime ? MeridianColors.daylightAccent : MeridianColors.nightAccent }

    /// VoiceOver-friendly single-string description of the proposed event.
    private var scheduleAccessibilityLabel: String {
        "Proposed event: \(draft.title). \(whenText), \(shortZone)."
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: MeridianSpacing.sm.rawValue) {
            VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue) {
                Text("Proposed event")
                    .font(.labelMedium)
                    .textCase(.uppercase)
                    .foregroundStyle(MeridianColors.primary.opacity(0.8))

                Text(draft.title)
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.onSurface)

                // When-line reads first after the title: full-contrast text led by the
                // day/night solar glyph, with the zone as a lighter trailing detail.
                HStack(spacing: MeridianSpacing.sm.rawValue) {
                    Image(systemName: todIcon)
                        .font(.bodyMedium)
                        .foregroundStyle(todAccent)
                        .accessibilityHidden(true)

                    Text(whenText)
                        .font(.bodyLarge)
                        .foregroundStyle(MeridianColors.onSurface)
                        + Text("  ·  \(shortZone)")
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }
                .padding(.top, MeridianSpacing.xs.rawValue)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(scheduleAccessibilityLabel)
            .accessibilityAddTraits(.isHeader)

            // Primary row: confirm + calendar export. The filled Add capsule is the
            // dominant, constructive default action.
            HStack(spacing: MeridianSpacing.md.rawValue) {
                Button {
                    feedbackTrigger &+= 1
                    onConfirm()
                } label: {
                    Text("Add to plan")
                        .font(.titleMedium)
                        .frame(maxWidth: .infinity, minHeight: minTouchTarget)
                        .background {
                            Capsule().fill(MeridianColors.primary)
                        }
                        .foregroundStyle(MeridianColors.onPrimary)
                }
                .buttonStyle(PressableCapsuleStyle())
                .accessibilityLabel("Add to plan")
                .accessibilityHint("Adds this event to your plan")
                .accessibilityAddTraits(.isButton)

                Button {
                    feedbackTrigger &+= 1
                    exportToCalendar()
                } label: {
                    Label("Calendar", systemImage: "calendar")
                        .font(.titleMedium)
                        .frame(maxWidth: .infinity, minHeight: minTouchTarget)
                        .background {
                            Capsule().fill(MeridianColors.primary.opacity(0.18))
                        }
                        .foregroundStyle(MeridianColors.primary)
                }
                .buttonStyle(PressableCapsuleStyle())
                .accessibilityLabel("Calendar")
                .accessibilityHint("Adds this event to your system calendar")
                .accessibilityAddTraits(.isButton)
            }
            .padding(.top, MeridianSpacing.xs.rawValue)

            // Secondary row: share .ics (constructive) + discard (destructive).
            HStack(spacing: MeridianSpacing.md.rawValue) {
                Button {
                    feedbackTrigger &+= 1
                    exportICS()
                } label: {
                    Label("Share .ics", systemImage: "square.and.arrow.up")
                        .font(.bodyMedium)
                        .frame(maxWidth: .infinity, minHeight: minTouchTarget)
                        .background {
                            Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        }
                        .foregroundStyle(MeridianColors.onSurface)
                }
                .buttonStyle(PressableCapsuleStyle())
                .accessibilityLabel("Share .ics")
                .accessibilityHint("Exports an .ics file to share")
                .accessibilityAddTraits(.isButton)

                // Discard carries a distinct error-tinted treatment so the destructive
                // dismiss action is unmistakable versus the constructive Share button.
                Button(role: .destructive) {
                    feedbackTrigger &+= 1
                    onDiscard()
                } label: {
                    Text("Discard")
                        .font(.bodyMedium)
                        .frame(maxWidth: .infinity, minHeight: minTouchTarget)
                        .background {
                            Capsule().strokeBorder(MeridianColors.error.opacity(0.5), lineWidth: 1)
                        }
                        .foregroundStyle(MeridianColors.error)
                }
                .buttonStyle(PressableCapsuleStyle())
                .accessibilityLabel("Discard")
                .accessibilityHint("Dismisses this proposed event without saving")
                .accessibilityAddTraits(.isButton)
            }

            if let exportError {
                Text(exportError)
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.error)
                    .padding(.top, MeridianSpacing.xs.rawValue)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityLabel("Error: \(exportError)")
            }
        }
        .padding(MeridianSpacing.lg.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: MeridianRadius.medium.rawValue, tint: MeridianColors.primary)
        .sensoryFeedback(.impact(weight: .light), trigger: feedbackTrigger)
        // Card animates in/out when the parent inserts/removes it; degrades to a
        // plain fade under Reduce Motion.
        .transition(
            reduceMotion
                ? .opacity
                : .scale(scale: 0.94).combined(with: .opacity)
        )
        .sheet(item: $shareURL) { item in
            ShareSheet(items: [item.url])
        }
    }

    /// iOS minimum comfortable touch-target height (Apple HIG 44 pt).
    private var minTouchTarget: CGFloat { 44 }

    // MARK: Export actions

    /// Inserts a real EventKit event in the draft's own zone (parity with Android
    /// `insertCalendarEvent`). Only failures are surfaced.
    private func exportToCalendar() {
        let title = draft.title
        let start = draft.timestamp
        let zoneId = draft.tzId
        Task {
            let result = await calendarRepo.insertEvent(
                title: title,
                startInstant: start,
                durationMinutes: defaultEventDurationMinutes,
                zoneId: zoneId
            )
            if case let .failure(reason) = result {
                withAnimation(reduceMotion ? nil : Motion.snappy()) { exportError = reason }
            } else {
                withAnimation(reduceMotion ? nil : Motion.snappy()) { exportError = nil }
            }
        }
    }

    /// Writes an .ics file to a temp URL and presents the system share sheet
    /// (parity with Android `shareEventIcs`).
    private func exportICS() {
        do {
            let url = try ICSGenerator.exportURL(
                title: draft.title,
                startDate: draft.timestamp,
                durationMinutes: defaultEventDurationMinutes,
                timeZoneId: draft.tzId
            )
            withAnimation(reduceMotion ? nil : Motion.snappy()) { exportError = nil }
            shareURL = ShareItem(url: url)
        } catch {
            withAnimation(reduceMotion ? nil : Motion.snappy()) {
                exportError = "Couldn't create the .ics file."
            }
        }
    }
}

// MARK: - PressableCapsuleStyle

/// Shared pressed-scale feedback for the card's capsule actions — depresses to
/// 0.96 on touch with a quick spring, mirroring the Liquid-Glass press idiom used
/// by nav pills and other controls. Reduce Motion collapses the scale to identity.
private struct PressableCapsuleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(Motion.quick(), value: configuration.isPressed)
    }
}

// MARK: - ShareItem

/// Identifiable wrapper so the share sheet can be driven by `.sheet(item:)`.
private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - ShareSheet

/// Thin `UIActivityViewController` wrapper for sharing the exported .ics file.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#if DEBUG
#Preview("DraftConfirmCard", traits: .sizeThatFitsLayout) {
    DraftConfirmCard(
        draft: PlannedTask(
            title: "Sync with London",
            timestamp: Date().addingTimeInterval(3600),
            tzId: "Europe/London"
        ),
        is24Hour: false,
        onConfirm: {},
        onDiscard: {}
    )
    .padding()
    .background(Color(hex: "#020617"))
    .environment(\.glassEnabled, true)
}
#endif
