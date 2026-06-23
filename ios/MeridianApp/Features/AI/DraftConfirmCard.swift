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

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proposed event")
                .font(.labelMedium)
                .foregroundStyle(MeridianColors.primary.opacity(0.7))

            Text(draft.title)
                .font(.titleMedium)
                .foregroundStyle(MeridianColors.onSurface)

            Text("\(whenText) · \(shortZone)")
                .font(.bodyMedium)
                .foregroundStyle(MeridianColors.onSurface.opacity(0.8))

            // Primary row: confirm + calendar export.
            HStack(spacing: 12) {
                Button {
                    feedbackTrigger &+= 1
                    onConfirm()
                } label: {
                    Text("Add to plan")
                        .font(.titleMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            Capsule().fill(MeridianColors.primary)
                        }
                        .foregroundStyle(MeridianColors.onPrimary)
                }
                .buttonStyle(.plain)

                Button {
                    feedbackTrigger &+= 1
                    exportToCalendar()
                } label: {
                    Label("Calendar", systemImage: "calendar")
                        .font(.titleMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            Capsule().fill(MeridianColors.primary.opacity(0.18))
                        }
                        .foregroundStyle(MeridianColors.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)

            // Secondary row: share .ics + discard.
            HStack(spacing: 12) {
                Button {
                    feedbackTrigger &+= 1
                    exportICS()
                } label: {
                    Label("Share .ics", systemImage: "square.and.arrow.up")
                        .font(.bodyMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        }
                        .foregroundStyle(MeridianColors.onSurface)
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    feedbackTrigger &+= 1
                    onDiscard()
                } label: {
                    Text("Discard")
                        .font(.bodyMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        }
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }
                .buttonStyle(.plain)
            }

            if let exportError {
                Text(exportError)
                    .font(.labelMedium)
                    .foregroundStyle(.red)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 20, tint: MeridianColors.primary)
        .sensoryFeedback(.impact(weight: .light), trigger: feedbackTrigger)
        .sheet(item: $shareURL) { item in
            ShareSheet(items: [item.url])
        }
    }

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
                exportError = reason
            } else {
                exportError = nil
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
            exportError = nil
            shareURL = ShareItem(url: url)
        } catch {
            exportError = "Couldn't create the .ics file."
        }
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
