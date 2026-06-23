// PlannerComponents.swift
// Meridian — iOS 27 / Swift 6  SwiftUI
//
// Reusable sub-views for the Plan screen. Direct behavioral port of the cards in Android
// `PlannerComponents.kt`, `WindowCard.kt`, `ParticipantsCard.kt`, and `CalendarEventsCard.kt`.
//
//   - PlannerHeaderView   title + subtitle
//   - SectionLabel        primary-tinted section header with subtitle
//   - DetailsCard         meeting-title text field
//   - WindowCard          date prev/next + jump + duration chips/stepper + exclude-weekends
//   - ParticipantsCard    "You" chip + per-zone group chips (toggle / fully-selected) + Add
//   - SlotsEmptyState     "no workable slots" panel
//   - CalendarEventsCard  device calendar list or permission prompt
//
// `MeetingSlot` is the canonical slot type (Models.swift); slots are rendered in LOCAL zones by
// SlotCard. There is no `PlannerParticipant` / `PlannerSlot` wrapper anymore.

import SwiftUI
import EventKit

// MARK: - Duration presets

let durationOptions = [30, 45, 60, 90, 120]
private let durationStep = 15
private let durationMin = 15
private let durationMax = 480

// MARK: - PlannerHeaderView

struct PlannerHeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Plan a meeting")
                .font(.system(size: 36, weight: .black))
                .foregroundStyle(MeridianColors.onBackground)
            Text("Pick who's in, when to look, and how long. Meridian finds a fair time.")
                .font(.bodyMedium)
                .foregroundStyle(MeridianColors.onSurface.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - SectionLabel

struct SectionLabel: View {
    let label: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.primary)
                Spacer()
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.6))
                    .multilineTextAlignment(.trailing)
            }
            Rectangle()
                .fill(MeridianColors.primary.opacity(0.15))
                .frame(height: 1)
                .padding(.top, 4)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - DetailsCard

struct DetailsCard: View {
    @Binding var title: String

    var body: some View {
        GlassCard(cornerRadius: 20, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Details", systemImage: "pencil")
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.onSurface)
                    .symbolRenderingMode(.hierarchical)
                TextField("e.g. Design Sync", text: $title)
                    .font(.bodyLarge)
                    .foregroundStyle(MeridianColors.onSurface)
                    .tint(MeridianColors.primary)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(MeridianColors.surface.opacity(0.7))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                            }
                    }
            }
        }
    }
}

// MARK: - WindowCard

struct WindowCard: View {
    /// UTC-midnight epoch of the selected day (matches Android's `selectedDateMillis` convention).
    @Binding var selectedDateMillis: Int
    @Binding var durationMinutes: Int
    @Binding var excludeWeekends: Bool
    let onJumpTapped: () -> Void

    @State private var customMode = false
    @State private var feedbackTick = 0

    private let dayMillis = 24 * 60 * 60 * 1000

    private static let todayMillis: Int = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let startOfToday = cal.startOfDay(for: Date())
        let comps = cal.dateComponents([.year, .month, .day], from: startOfToday)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let utcMidnight = utc.date(from: comps) ?? Date()
        return Int(utcMidnight.timeIntervalSince1970 * 1000)
    }()

    private var isToday: Bool { selectedDateMillis == Self.todayMillis }

    var body: some View {
        GlassCard(cornerRadius: 20, padding: 20) {
            VStack(alignment: .leading, spacing: 0) {
                Label("Window", systemImage: "calendar")
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.onSurface)
                    .symbolRenderingMode(.hierarchical)
                Spacer().frame(height: 12)

                dateRow
                if !isToday { backToTodayButton }

                Spacer().frame(height: 8)
                jumpButton

                Spacer().frame(height: 16)
                Text("Duration")
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.7))
                Spacer().frame(height: 8)
                durationChips
                if customMode { customStepper }

                Spacer().frame(height: 16)
                weekendsToggle
            }
        }
        .sensoryFeedback(.selection, trigger: feedbackTick)
        .onAppear { customMode = !durationOptions.contains(durationMinutes) }
        .onChange(of: durationMinutes) { _, value in
            if customMode && durationOptions.contains(value) { customMode = false }
        }
    }

    private var dateRow: some View {
        HStack(spacing: 8) {
            Button {
                feedbackTick += 1
                selectedDateMillis -= dayMillis
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.7))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            // Compact DatePicker is the primary day control; the arrows step ±1 day. Editing it in
            // UTC (via `dateBinding`) keeps the stored UTC-midnight epoch aligned with Android.
            DatePicker("", selection: dateBinding, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(MeridianColors.primary)
                .colorScheme(.dark)
                .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                .frame(maxWidth: .infinity)

            Button {
                feedbackTick += 1
                selectedDateMillis += dayMillis
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.7))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
    }

    /// DatePicker bound to the UTC-midnight epoch, edited in UTC so the day never shifts.
    private var dateBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: Double(selectedDateMillis) / 1000) },
            set: { newDate in
                var utc = Calendar(identifier: .gregorian)
                utc.timeZone = TimeZone(identifier: "UTC")!
                let comps = utc.dateComponents([.year, .month, .day], from: newDate)
                if let midnight = utc.date(from: comps) {
                    selectedDateMillis = Int(midnight.timeIntervalSince1970 * 1000)
                }
            }
        )
    }

    private var backToTodayButton: some View {
        HStack {
            Spacer()
            Button {
                feedbackTick += 1
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedDateMillis = Self.todayMillis
                }
            } label: {
                Label("Back to today", systemImage: "calendar.badge.clock")
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.primary)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 4)
    }

    private var jumpButton: some View {
        Button {
            feedbackTick += 1
            onJumpTapped()
        } label: {
            Label("Jump to place & time…", systemImage: "clock.arrow.2.circlepath")
                .font(.bodyLarge)
                .foregroundStyle(MeridianColors.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(MeridianColors.primary.opacity(0.4), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var durationChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(durationOptions, id: \.self) { minutes in
                    chip(label: durationChipLabel(minutes), selected: !customMode && durationMinutes == minutes) {
                        customMode = false
                        durationMinutes = minutes
                    }
                }
                chip(label: customMode ? formatDuration(durationMinutes) : "Custom", selected: customMode) {
                    customMode = true
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            feedbackTick += 1
            action()
        } label: {
            Text(label)
                .font(.labelMedium)
                .foregroundStyle(selected ? MeridianColors.onPrimary : MeridianColors.onSurfaceVariant)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(selected ? MeridianColors.primary : MeridianColors.surface.opacity(0.6))
                        .overlay {
                            Capsule().strokeBorder(
                                selected ? MeridianColors.primary.opacity(0.6) : Color.white.opacity(0.14),
                                lineWidth: 1
                            )
                        }
                }
        }
        .buttonStyle(.plain)
    }

    private var customStepper: some View {
        HStack {
            Spacer()
            Button {
                feedbackTick += 1
                durationMinutes = max(durationMinutes - durationStep, durationMin)
            } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 28))
                    .foregroundStyle(durationMinutes > durationMin ? MeridianColors.primary : MeridianColors.onSurfaceVariant.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(durationMinutes <= durationMin)

            Text(formatDuration(durationMinutes))
                .font(.titleMedium)
                .foregroundStyle(MeridianColors.onSurface)
                .frame(width: 96)
                .multilineTextAlignment(.center)

            Button {
                feedbackTick += 1
                durationMinutes = min(durationMinutes + durationStep, durationMax)
            } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 28))
                    .foregroundStyle(durationMinutes < durationMax ? MeridianColors.primary : MeridianColors.onSurfaceVariant.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(durationMinutes >= durationMax)
            Spacer()
        }
        .padding(.top, 8)
    }

    private var weekendsToggle: some View {
        Toggle(isOn: $excludeWeekends) {
            Text("Exclude weekends")
                .font(.labelMedium)
                .foregroundStyle(MeridianColors.onSurface.opacity(0.7))
        }
        .tint(MeridianColors.primary)
        .colorScheme(.dark)
    }

    private func durationChipLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }
}

/// Human-readable duration, e.g. "45 m", "1 h", "1 h 15 m". Mirrors Android `formatDuration`.
func formatDuration(_ minutes: Int) -> String {
    let hours = minutes / 60
    let mins = minutes % 60
    if hours == 0 { return "\(mins) m" }
    if mins == 0 { return "\(hours) h" }
    return "\(hours) h \(mins) m"
}

// MARK: - ParticipantsCard

struct ParticipantsCard: View {
    let locationGroups: [ParticipantLocationGroup]
    let localLocationName: String
    @Binding var selectedZones: [String: Bool]
    @Binding var selectedPeople: [UUID: Bool]
    let onAddTapped: () -> Void
    let onDeletePerson: (UUID) -> Void

    @State private var feedbackTick = 0

    private var hasFavorites: Bool { !locationGroups.isEmpty }

    private var allSelected: Bool {
        locationGroups.allSatisfy {
            ParticipantGrouping.isGroupFullySelected($0, selectedZones: selectedZones, selectedPeople: selectedPeople)
        }
    }

    var body: some View {
        GlassCard(cornerRadius: 20, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                header
                if !hasFavorites {
                    Text("Add cities and people here, or star them on World Clock or Now.")
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurface.opacity(0.6))
                }
                chipFlow
            }
        }
        .sensoryFeedback(.selection, trigger: feedbackTick)
    }

    private var header: some View {
        HStack(alignment: .top) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(MeridianColors.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Participants").font(.titleMedium).fontWeight(.bold)
                        .foregroundStyle(MeridianColors.onSurface)
                    Text("Starred cities and contacts from World Clock & Now")
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurface.opacity(0.55))
                }
            }
            Spacer()
            if hasFavorites {
                Button {
                    feedbackTick += 1
                    let target = !allSelected
                    for group in locationGroups {
                        if let zoneId = group.savedZoneId { selectedZones[zoneId] = target }
                        for person in group.people { selectedPeople[person.id] = target }
                    }
                } label: {
                    Text(allSelected ? "None" : "All")
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var chipFlow: some View {
        FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            // The local "You" chip is always present and non-interactive.
            Text("You · \(localLocationName)")
                .font(.labelMedium)
                .foregroundStyle(MeridianColors.onPrimary)
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background { Capsule().fill(MeridianColors.primary) }

            ForEach(locationGroups) { group in
                groupChip(group)
            }

            Button {
                feedbackTick += 1
                onAddTapped()
            } label: {
                Label("Add", systemImage: "person.badge.plus")
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.primary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background {
                        Capsule().strokeBorder(MeridianColors.primary.opacity(0.4), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func groupChip(_ group: ParticipantLocationGroup) -> some View {
        let fullySelected = ParticipantGrouping.isGroupFullySelected(
            group, selectedZones: selectedZones, selectedPeople: selectedPeople
        )
        let anySelected = ParticipantGrouping.isGroupSelected(
            group, selectedZones: selectedZones, selectedPeople: selectedPeople
        )

        if group.people.isEmpty {
            // City-only chip.
            selectableChip(label: group.displayName, selected: anySelected) {
                if let zoneId = group.savedZoneId { selectedZones[zoneId] = !anySelected }
            }
        } else if group.people.count == 1 {
            // Single person + (optional) city — toggles both together; long-press to delete.
            let person = group.people[0]
            selectableChip(
                label: ParticipantGrouping.groupChipLabel(group),
                selected: anySelected,
                onDelete: { onDeletePerson(person.id) }
            ) {
                let target = !anySelected
                if let zoneId = group.savedZoneId { selectedZones[zoneId] = target }
                selectedPeople[person.id] = target
            }
        } else {
            // Multi-person group: a city chip (toggles all) plus one chip per person.
            selectableChip(label: group.displayName, selected: fullySelected) {
                let target = !fullySelected
                if let zoneId = group.savedZoneId { selectedZones[zoneId] = target }
                for person in group.people { selectedPeople[person.id] = target }
            }
            ForEach(group.people) { person in
                selectableChip(
                    label: person.chipLabel,
                    selected: selectedPeople[person.id] == true,
                    onDelete: { onDeletePerson(person.id) }
                ) {
                    let next = !(selectedPeople[person.id] ?? false)
                    selectedPeople[person.id] = next
                    if next, let zoneId = group.savedZoneId { selectedZones[zoneId] = true }
                }
            }
        }
    }

    private func selectableChip(
        label: String,
        selected: Bool,
        onDelete: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Text(label)
            .font(.labelMedium)
            .foregroundStyle(selected ? MeridianColors.onPrimary : MeridianColors.onSurfaceVariant)
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(selected ? MeridianColors.primary : MeridianColors.surface.opacity(0.6))
                    .overlay {
                        Capsule().strokeBorder(
                            selected ? MeridianColors.primary.opacity(0.6) : Color.white.opacity(0.14),
                            lineWidth: 1
                        )
                    }
            }
            .contentShape(Capsule())
            .onTapGesture {
                feedbackTick += 1
                action()
            }
            .contextMenu {
                if let onDelete {
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
    }
}

// MARK: - SlotsEmptyState

struct SlotsEmptyState: View {
    let hint: String

    var body: some View {
        GlassCard(cornerRadius: 20, padding: 20) {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.3))
                    .symbolRenderingMode(.hierarchical)
                Text("No workable slots on this day")
                    .font(.titleMedium)
                    .fontWeight(.bold)
                    .foregroundStyle(MeridianColors.onSurface)
                    .multilineTextAlignment(.center)
                Text(hint)
                    .font(.bodyMedium)
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - CalendarEventsCard

struct CalendarEventsCard: View {
    let events: [CalendarEventModel]
    let hasPermission: Bool
    let use24Hour: Bool
    let onRequestPermission: () -> Void

    private var displayEvents: [CalendarEventModel] { Array(events.prefix(5)) }

    var body: some View {
        GlassCard(cornerRadius: 20, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Your Calendar", systemImage: "calendar")
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.onSurface)
                    .symbolRenderingMode(.hierarchical)

                if !hasPermission {
                    Text("Allow calendar access to see your upcoming events alongside meeting slots.")
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurface.opacity(0.6))
                    Button(action: onRequestPermission) {
                        Label("Grant calendar access", systemImage: "calendar")
                            .font(.bodyLarge)
                            .foregroundStyle(MeridianColors.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(MeridianColors.primary.opacity(0.4), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                } else if events.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 16))
                            .foregroundStyle(MeridianColors.onSurface.opacity(0.35))
                        Text("No events scheduled for the next 7 days.")
                            .font(.bodyMedium)
                            .foregroundStyle(MeridianColors.onSurface.opacity(0.6))
                    }
                } else {
                    ForEach(Array(displayEvents.enumerated()), id: \.element.id) { index, event in
                        eventRow(event)
                        if index < displayEvents.count - 1 {
                            Divider().background(Color.white.opacity(0.08))
                        }
                    }
                    if events.count > 5 {
                        Text("+\(events.count - 5) more events this week")
                            .font(.bodyMedium)
                            .foregroundStyle(MeridianColors.onSurface.opacity(0.5))
                    }
                }
            }
        }
    }

    private func eventRow(_ event: CalendarEventModel) -> some View {
        // The model carries no IANA zone, so device-local rendering matches the Android intent
        // for events without an explicit zone.
        let timeLabel: String = {
            if event.isAllDay { return "All day" }
            let start = TimeFormats.hourMinute(date: event.startDate, timeZone: .current, use24Hour: use24Hour)
            let end = TimeFormats.hourMinute(date: event.endDate, timeZone: .current, use24Hour: use24Hour)
            return "\(start) – \(end)"
        }()
        let dateLabel = TimeFormats.shortDate(date: event.startDate, timeZoneId: TimeZone.current.identifier)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.bodyLarge)
                    .fontWeight(.medium)
                    .foregroundStyle(MeridianColors.onSurface)
                    .lineLimit(1)
                Text(timeLabel)
                    .font(.bodyMedium)
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.6))
            }
            Spacer()
            Text(dateLabel)
                .font(.labelMedium)
                .foregroundStyle(MeridianColors.primary.opacity(0.7))
        }
        .padding(.vertical, 4)
    }
}
