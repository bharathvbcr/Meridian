// PlannedTaskRow.swift
// Meridian — iOS 27 / Swift 6
//
// A single row in the "Your Plan" list. Direct behavioral port of Android `PlannedTaskRow`
// (PlannerComponents.kt): renders the task's time + date IN THE TASK'S OWN ZONE, with actions to
// add it to the device calendar, share it as a .ics invite, or delete it.

import SwiftUI

struct PlannedTaskRow: View {
    let task: PlannedTask
    let use24Hour: Bool
    let onDelete: () -> Void

    @State private var icsURL: URL? = nil
    @State private var showShareSheet = false
    @State private var errorText: String? = nil
    @State private var feedbackTick = 0
    @State private var addedToCalendar = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let calendarRepo = CalendarRepository()

    private var zone: TimeZone { TimeFormats.safeTimeZone(id: task.tzId) }

    private var formatted: String {
        let time = TimeFormats.hourMinute(date: task.timestamp, timeZone: zone, use24Hour: use24Hour)
        let date = TimeFormats.shortDate(date: task.timestamp, timeZoneId: task.tzId)
        return "\(time) · \(date)"
    }

    private var shortZoneName: String {
        task.tzId.split(separator: "/").last.map {
            $0.replacingOccurrences(of: "_", with: " ")
        } ?? task.tzId
    }

    var body: some View {
        GlassCard(cornerRadius: MeridianRadius.small.rawValue, padding: MeridianSpacing.md.rawValue) {
            HStack(spacing: MeridianSpacing.sm.rawValue) {
                // Leading accent rule — signals these are actionable plan items,
                // mirroring ZoneTimeRow's day/night indicator pattern.
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(MeridianColors.primary)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue / 2) {
                    Text(task.title)
                        .font(.titleMedium)
                        .fontWeight(.bold)
                        .foregroundStyle(MeridianColors.onSurface)
                        .lineLimit(1)
                    Text("\(formatted) · \(shortZoneName)")
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurface.opacity(0.6))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: MeridianSpacing.xs.rawValue)

                iconButton(
                    addedToCalendar ? "checkmark.circle.fill" : "calendar",
                    tint: addedToCalendar ? MeridianColors.positive : MeridianColors.primary,
                    label: addedToCalendar ? "Added to calendar" : "Add to calendar"
                ) {
                    Task { await addToCalendar() }
                }
                iconButton("square.and.arrow.up", tint: MeridianColors.onSurfaceVariant, label: "Share invite") {
                    prepareICS()
                }
                iconButton("trash", tint: MeridianColors.error, label: "Delete") {
                    onDelete()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .contextMenu {
            Button("Add to calendar", systemImage: "calendar") {
                feedbackTick += 1
                Task { await addToCalendar() }
            }
            Button("Share invite", systemImage: "square.and.arrow.up") {
                feedbackTick += 1
                prepareICS()
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                feedbackTick += 1
                onDelete()
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: feedbackTick)
        .sheet(isPresented: $showShareSheet) {
            if let url = icsURL {
                ShareLink(item: url, subject: Text(task.title))
            }
        }
        .overlay(alignment: .bottom) {
            if let errorText {
                Text(errorText)
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.error.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
    }

    private func iconButton(
        _ systemImage: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            feedbackTick += 1
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                // 44 pt minimum iOS touch target; the glyph stays 17 pt.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    @MainActor
    private func addToCalendar() async {
        let result = await calendarRepo.insertEvent(
            title: task.title,
            startInstant: task.timestamp,
            durationMinutes: defaultEventDurationMinutes,
            zoneId: task.tzId
        )
        switch result {
        case .success:
            errorText = nil
            // Flip the calendar glyph to a success checkmark, matching SlotCard.
            withAnimation(reduceMotion ? nil : Motion.snappy()) { addedToCalendar = true }
        case let .failure(reason):
            errorText = reason
        }
    }

    private func prepareICS() {
        do {
            icsURL = try ICSGenerator.exportURL(
                title: task.title,
                startDate: task.timestamp,
                durationMinutes: defaultEventDurationMinutes,
                timeZoneId: task.tzId
            )
            showShareSheet = true
        } catch {
            errorText = "Could not generate .ics file."
        }
    }
}
