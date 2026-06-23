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
        GlassCard(cornerRadius: 16, padding: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
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
                Spacer(minLength: 4)

                iconButton("calendar", tint: MeridianColors.primary, label: "Add to calendar") {
                    Task { await addToCalendar() }
                }
                iconButton("square.and.arrow.up", tint: MeridianColors.onSurfaceVariant, label: "Share invite") {
                    prepareICS()
                }
                iconButton("trash", tint: .red, label: "Delete") {
                    onDelete()
                }
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
                    .foregroundStyle(Color.red.opacity(0.85))
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
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @MainActor
    private func addToCalendar() async {
        let result = await calendarRepo.insertEvent(
            title: task.title,
            startInstant: task.timestamp,
            durationMinutes: defaultEventDurationMinutes,
            zoneId: task.tzId
        )
        if case let .failure(reason) = result { errorText = reason }
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
