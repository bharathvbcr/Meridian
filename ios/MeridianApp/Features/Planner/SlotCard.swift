// SlotCard.swift
// Meridian — iOS 27 / Swift 6
//
// Detail card for a single ranked `MeetingSlot`. Direct behavioral port of Android `SlotCard.kt`.
//
// UTC-BUG FIX: `MeetingSlot.start` is an ABSOLUTE instant. Every wall-clock string here is
// rendered with an explicit per-zone `Date.FormatStyle.timeZone(...)` — the local zone for the
// headline and the participant's own zone for each tag — so NO UTC string is ever baked in.

import SwiftUI
import UIKit

// MARK: - SlotCard

struct SlotCard: View {
    let slot: MeetingSlot
    let localZoneId: String
    let localLocationName: String
    let durationMinutes: Int
    let use24Hour: Bool
    let participantLabels: [ParticipantSlotLabel]
    /// When `false` the card renders as a static detail panel (no chevron / tap-to-toggle) — used
    /// under the fair-time dial where selection is driven by the scrubber.
    var interactive: Bool = true
    var expanded: Bool = true
    let meetingTitle: String
    var onToggle: () -> Void = {}

    @State private var copied = false
    @State private var icsURL: URL? = nil
    @State private var showShareSheet = false
    @State private var addedToCalendar = false
    @State private var calendarError: String? = nil
    /// Bumped on any button tap so `.sensoryFeedback` fires a light impact.
    @State private var feedbackTick = 0

    private let calendarRepo = CalendarRepository()

    private var localZone: TimeZone { TimeFormats.safeTimeZone(id: localZoneId) }
    private var endDate: Date { slot.start.addingTimeInterval(Double(durationMinutes) * 60.0) }

    private var headline: String {
        let start = TimeFormats.hourMinute(date: slot.start, timeZone: localZone, use24Hour: use24Hour)
        let end = TimeFormats.hourMinute(date: endDate, timeZone: localZone, use24Hour: use24Hour)
        let date = TimeFormats.shortDate(date: slot.start, timeZoneId: localZoneId)
        return "\(start) – \(end) · \(date)"
    }

    private var effectiveTitle: String {
        meetingTitle.trimmingCharacters(in: .whitespaces).isEmpty ? "Meeting" : meetingTitle
    }

    private var ratingColor: Color { Self.ratingColor(for: slot.label) }

    var body: some View {
        GlassCard(cornerRadius: 20, padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                header
                participantTags
                if expanded { expandedActions }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard interactive else { return }
            feedbackTick += 1
            onToggle()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: feedbackTick)
        .sheet(isPresented: $showShareSheet) {
            if let url = icsURL {
                ShareLink(item: url, subject: Text(effectiveTitle))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.titleMedium)
                    .fontWeight(.bold)
                    .foregroundStyle(MeridianColors.onSurface)
                Text(localLocationName)
                    .font(.bodyMedium)
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.5))
            }
            Spacer(minLength: 8)
            RatingBadge(label: slot.label)
            if interactive {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.5))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .animation(.easeInOut(duration: 0.2), value: expanded)
            }
        }
    }

    // MARK: Participant tags

    private var participantTags: some View {
        FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(participantLabels.filter { slot.localHours[$0.zoneId] != nil }) { label in
                let view = slot.localViews[label.zoneId] ?? .awake
                ParticipantTag(
                    zoneId: label.zoneId,
                    who: label.displayWho(),
                    instant: slot.start,
                    view: view,
                    use24Hour: use24Hour,
                    localZoneId: localZoneId
                )
            }
        }
    }

    // MARK: Expanded actions

    @ViewBuilder
    private var expandedActions: some View {
        Divider().background(Color.white.opacity(0.15)).padding(.vertical, 8)

        HStack(spacing: 8) {
            actionButton(
                title: addedToCalendar ? "Added" : "Calendar",
                systemImage: addedToCalendar ? "checkmark.circle.fill" : "calendar.badge.plus",
                filled: true
            ) {
                feedbackTick += 1
                Task { await addToCalendar() }
            }
            actionButton(title: "Share .ics", systemImage: "square.and.arrow.up", filled: false) {
                feedbackTick += 1
                prepareICS()
            }
        }

        actionButton(
            title: copied ? "Copied" : "Copy to clipboard",
            systemImage: copied ? "checkmark" : "doc.on.doc",
            filled: false
        ) {
            feedbackTick += 1
            copyToClipboard()
        }

        if let calendarError {
            Text(calendarError)
                .font(.labelMedium)
                .foregroundStyle(Color.red.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        filled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                Text(title).font(.titleMedium)
            }
            .foregroundStyle(filled ? MeridianColors.onPrimary : MeridianColors.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(filled ? MeridianColors.primary : MeridianColors.primary.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(MeridianColors.primary.opacity(filled ? 0 : 0.3), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    @MainActor
    private func addToCalendar() async {
        let result = await calendarRepo.insertEvent(
            title: effectiveTitle,
            startInstant: slot.start,
            durationMinutes: durationMinutes,
            zoneId: localZoneId
        )
        switch result {
        case .success:
            addedToCalendar = true
            calendarError = nil
        case let .failure(reason):
            calendarError = reason
        }
    }

    private func prepareICS() {
        do {
            icsURL = try ICSGenerator.exportURL(
                title: effectiveTitle,
                startDate: slot.start,
                durationMinutes: durationMinutes,
                timeZoneId: localZoneId
            )
            showShareSheet = true
        } catch {
            calendarError = "Could not generate .ics file."
        }
    }

    /// Builds a shareable summary line listing each participant's local time + day offset.
    /// Mirrors Android SlotCard's "Copy to clipboard". Renders every time in its own zone.
    private func copyToClipboard() {
        let localTime = TimeFormats.hourMinute(date: slot.start, timeZone: localZone, use24Hour: use24Hour)
        let localDate = TimeFormats.shortDate(date: slot.start, timeZoneId: localZoneId)

        let parts: [String] = participantLabels
            .filter { slot.localHours[$0.zoneId] != nil }
            .map { label in
                let zone = TimeFormats.safeTimeZone(id: label.zoneId)
                let time = TimeFormats.hourMinute(date: slot.start, timeZone: zone, use24Hour: use24Hour)
                let suffix = Self.dayOffsetSuffix(instant: slot.start, zoneId: label.zoneId, localZoneId: localZoneId)
                return "\(time)\(suffix) (\(label.displayWho()))"
            }

        let title = meetingTitle.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Proposed meeting time" : meetingTitle
        let text = "\(title) on \(localDate): \(localTime) (You · \(localLocationName)) / "
            + parts.joined(separator: " / ")
        UIPasteboard.general.string = text
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { copied = true }
    }

    // MARK: - Rating color

    static func ratingColor(for label: SlotLabel) -> Color {
        switch label {
        case .optimal:   return MeridianColors.primary
        case .fair:      return MeridianColors.daylightGlow
        case .difficult: return Color.red
        }
    }

    /// " (+N d)" / " (-N d)" for a participant whose local calendar day differs from the local
    /// zone's. Mirrors Android's `dateDiff` logic.
    static func dayOffsetSuffix(instant: Date, zoneId: String, localZoneId: String) -> String {
        let diff = dayOffset(instant: instant, zoneId: zoneId, localZoneId: localZoneId)
        if diff > 0 { return " (+\(diff) d)" }
        if diff < 0 { return " (\(diff) d)" }
        return ""
    }

    static func dayOffset(instant: Date, zoneId: String, localZoneId: String) -> Int {
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = TimeFormats.safeTimeZone(id: localZoneId)
        var zoneCal = Calendar(identifier: .gregorian)
        zoneCal.timeZone = TimeFormats.safeTimeZone(id: zoneId)

        let localDay = localCal.startOfDay(for: instant)
        let zoneDay = zoneCal.startOfDay(for: instant)
        // Compare the two wall-clock calendar dates as day numbers in a neutral calendar.
        let localComps = localCal.dateComponents([.year, .month, .day], from: instant)
        let zoneComps = zoneCal.dateComponents([.year, .month, .day], from: instant)
        var neutral = Calendar(identifier: .gregorian)
        neutral.timeZone = TimeZone(identifier: "UTC")!
        guard
            let l = neutral.date(from: DateComponents(year: localComps.year, month: localComps.month, day: localComps.day)),
            let z = neutral.date(from: DateComponents(year: zoneComps.year, month: zoneComps.month, day: zoneComps.day))
        else {
            // Fallback to start-of-day comparison if component reconstruction fails.
            return Int((zoneDay.timeIntervalSince(localDay) / 86_400).rounded())
        }
        return Int((z.timeIntervalSince(l) / 86_400).rounded())
    }
}

// MARK: - RatingBadge

struct RatingBadge: View {
    let label: SlotLabel

    var body: some View {
        let color = SlotCard.ratingColor(for: label)
        Text(label.displayName)
            .font(.labelMedium)
            .fontWeight(.bold)
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background { Capsule().fill(color.opacity(0.18)) }
            .accessibilityLabel("Meeting quality: \(label.displayName)")
    }
}

// MARK: - ParticipantTag

/// One participant chip: their local time (in THEIR zone), a day-offset badge, and a LocalView
/// icon + label. Mirrors Android `ParticipantTag`.
struct ParticipantTag: View {
    let zoneId: String
    let who: String
    let instant: Date
    let view: LocalView
    let use24Hour: Bool
    let localZoneId: String

    private var style: LocalViewStyle { LocalViewStyle.style(for: view) }

    private var time: String {
        TimeFormats.hourMinute(
            date: instant,
            timeZone: TimeFormats.safeTimeZone(id: zoneId),
            use24Hour: use24Hour
        )
    }

    private var dayOffset: Int {
        SlotCard.dayOffset(instant: instant, zoneId: zoneId, localZoneId: localZoneId)
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: style.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(style.color)
            VStack(alignment: .leading, spacing: 0) {
                primaryLine
                Text(style.label)
                    .font(.system(size: 10))
                    .foregroundStyle(style.color)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background { Capsule().fill(style.color.opacity(0.14)) }
    }

    private var primaryLine: Text {
        var line = Text("\(who) · \(time)")
            .font(.labelMedium)
            .foregroundStyle(MeridianColors.onSurface)
        if dayOffset != 0 {
            let suffix = dayOffset > 0 ? " (+\(dayOffset) d)" : " (\(dayOffset) d)"
            let offsetColor = dayOffset > 0 ? MeridianColors.daylightGlow : MeridianColors.secondary
            line = line + Text(suffix)
                .font(.labelMedium)
                .fontWeight(.bold)
                .foregroundStyle(offsetColor)
        }
        return line
    }
}

// MARK: - LocalViewStyle

/// Icon + label + color for a `LocalView`. Mirrors Android `localViewStyle`.
struct LocalViewStyle {
    let systemImage: String
    let label: String
    let color: Color

    static func style(for view: LocalView) -> LocalViewStyle {
        switch view {
        case .working:
            return LocalViewStyle(systemImage: "briefcase.fill", label: "Working", color: MeridianColors.primary)
        case .awake:
            return LocalViewStyle(systemImage: "sun.max.fill", label: "Awake", color: MeridianColors.daylightGlow)
        case .outsideHours:
            return LocalViewStyle(systemImage: "cup.and.saucer.fill", label: "Off-hours", color: MeridianColors.secondary)
        case .asleep:
            return LocalViewStyle(systemImage: "moon.fill", label: "Asleep", color: Color.red)
        }
    }
}
