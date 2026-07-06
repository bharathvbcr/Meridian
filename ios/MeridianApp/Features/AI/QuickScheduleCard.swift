// QuickScheduleCard.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// Interactive quick-scheduler on the AI screen — the model is never involved to
// add an event. Behavioral port of the Android `QuickScheduleCard`
// (feature/ai/AiScreen.kt):
//   • collapsible glass card
//   • event-title field
//   • one-tap relative presets (In 1 hr / Tonight 8 PM / Tomorrow 9 AM / Next week)
//   • date + time selectors (native pickers)
//   • zone selector (local + saved zones + async search), default "Local"
//   • live preview with a time-of-day glyph, relative phrasing, local-equivalent,
//     and a "time has passed" guard
//   • "Add to plan" builds a `PlannedTask` at the absolute instant for the chosen
//     zone (local wall-clock → instant), with a transient "Added" confirmation.

import SwiftUI

// MARK: - QuickScheduleCard

struct QuickScheduleCard: View {

    /// (zoneId, displayName) pairs for the user's saved zones.
    let savedZones: [(id: String, displayName: String)]
    let is24Hour: Bool
    /// Async multi-layer zone search (delegates to `MainViewModel.searchTimeZones`).
    let searchZones: (String) async -> [ZoneMatch]
    /// Commits the assembled task to the plan.
    let onAdd: (PlannedTask) -> Void

    // MARK: State

    private let localZoneId = TimeZone.current.identifier

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expanded = true
    @State private var title = ""
    @State private var selectedDate = Date()        // wall-clock components are read in selectedZoneId
    @State private var selectedZoneId = TimeZone.current.identifier
    @State private var selectedZoneLabel = "Local"
    @State private var showZonePicker = false
    @State private var addedFlash = false
    @State private var feedbackTrigger = 0

    // MARK: Derived

    /// Zone options: Local first, then saved zones de-duplicated against local.
    private var zoneOptions: [(id: String, label: String)] {
        var options: [(id: String, label: String)] = [(localZoneId, "Local")]
        for zone in savedZones where zone.id != localZoneId {
            options.append((zone.id, zone.displayName))
        }
        return options
    }

    /// The absolute instant the chosen wall-clock date/time lands at in `selectedZoneId`.
    private var targetInstant: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeFormats.safeTimeZone(id: selectedZoneId)
        // Read the picker's wall-clock fields *in the local zone* (that is how the user
        // entered them on the native pickers) then reinterpret them in the selected zone.
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = TimeFormats.safeTimeZone(id: localZoneId)
        let comps = localCal.dateComponents([.year, .month, .day, .hour, .minute], from: selectedDate)
        return cal.date(from: comps) ?? selectedDate
    }

    private var now: Date { Date() }
    private var isPast: Bool { targetInstant < now }

    private var timeLabel: String {
        TimeFormats.hourMinute(date: selectedDate, timeZoneId: localZoneId, use24Hour: is24Hour)
    }

    private var dateLabel: String {
        TimeFormats.shortDate(date: selectedDate, timeZoneId: localZoneId)
    }

    private var relative: String { Self.relativeTime(target: targetInstant, now: now) }

    /// When scheduling in another zone, what that lands at in the user's own time.
    private var localEquivalent: String? {
        guard selectedZoneId != localZoneId else { return nil }
        let date = TimeFormats.shortDate(date: targetInstant, timeZoneId: localZoneId)
        let time = TimeFormats.hourMinute(date: targetInstant, timeZoneId: localZoneId, use24Hour: is24Hour)
        return "\(date) · \(time) your time"
    }

    /// True when the chosen hour reads as daytime (drives the solar accent + glyph).
    private var isDaytimeHour: Bool {
        let hour = Calendar.current.component(.hour, from: selectedDate)
        return (5...20).contains(hour)
    }

    /// Time-of-day glyph for the chosen hour (solar theme parity).
    private var todIcon: String {
        let hour = Calendar.current.component(.hour, from: selectedDate)
        switch hour {
        case 5...10:  return "sunrise"
        case 11...16: return "sun.max"
        case 17...20: return "sunset"
        default:      return "moon.stars"
        }
    }

    /// Sun/moon accent matching the chosen hour — reads identically to Now & World Clock.
    private var todAccent: Color {
        isDaytimeHour ? MeridianColors.daylightAccent : MeridianColors.nightAccent
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                expandedContent
                    .padding(.top, MeridianSpacing.md.rawValue)
                    .transition(reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(MeridianSpacing.lg.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: MeridianRadius.medium.rawValue, tint: MeridianColors.primary)
        .sensoryFeedback(.impact(weight: .light), trigger: feedbackTrigger)
        .sensoryFeedback(.success, trigger: addedFlash) { _, new in new }
        .sheet(isPresented: $showZonePicker) {
            ZonePickerSheet(
                localZoneId: localZoneId,
                quickZones: zoneOptions,
                selectedZoneId: selectedZoneId,
                searchZones: searchZones
            ) { id, label in
                selectedZoneId = id
                selectedZoneLabel = label
                showZonePicker = false
            }
        }
        .task(id: addedFlash) {
            guard addedFlash else { return }
            try? await Task.sleep(for: .seconds(2.2))
            if !Task.isCancelled { addedFlash = false }
        }
    }

    // MARK: Header (collapse toggle)

    private var header: some View {
        Button {
            if reduceMotion {
                expanded.toggle()
            } else {
                withAnimation(Motion.snappy()) {
                    expanded.toggle()
                }
            }
        } label: {
            HStack(spacing: MeridianSpacing.sm.rawValue) {
                Image(systemName: "clock")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MeridianColors.primary)
                    .accessibilityHidden(true)
                Text("Quick schedule")
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.onSurface)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel("Quick schedule")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityHint(expanded ? "Double tap to collapse" : "Double tap to expand")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Expanded content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: MeridianSpacing.md.rawValue) {
            // Title field.
            TextField("Event title", text: $title)
                .font(.bodyLarge)
                .foregroundStyle(MeridianColors.onSurface)
                .tint(MeridianColors.primary)
                .padding(.horizontal, MeridianSpacing.md.rawValue)
                .padding(.vertical, MeridianSpacing.md.rawValue)
                .frame(minHeight: 44)
                .background {
                    RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                        .fill(MeridianColors.onSurface.opacity(0.05))
                        .overlay {
                            RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        }
                }
                .accessibilityLabel("Event title")

            // Relative presets.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MeridianSpacing.sm.rawValue) {
                    presetChip("In 1 hr") { applyPreset(addingHours: 1, minute: 0) }
                    presetChip("Tonight 8 PM") { applyPreset(hour: 20, minute: 0) }
                    presetChip("Tomorrow 9 AM") { applyPreset(addingDays: 1, hour: 9, minute: 0) }
                    presetChip("Next week") { applyPreset(addingDays: 7, hour: 9, minute: 0) }
                }
            }
            .accessibilityLabel("Quick time presets")

            // Date + time selectors (native pickers in a compact graphical style).
            HStack(spacing: MeridianSpacing.md.rawValue) {
                DatePicker(
                    "",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(MeridianColors.primary)
                .accessibilityLabel("Event date")

                DatePicker(
                    "",
                    selection: $selectedDate,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(MeridianColors.primary)
                .accessibilityLabel("Event time")

                Spacer(minLength: 0)
            }

            // Zone selector.
            VStack(alignment: .leading, spacing: MeridianSpacing.sm.rawValue) {
                Text("Time zone")
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.7))
                    .accessibilityHidden(true)
                Button {
                    showZonePicker = true
                } label: {
                    HStack(spacing: MeridianSpacing.sm.rawValue) {
                        Image(systemName: "globe")
                            .font(.system(size: 16, weight: .medium))
                            .accessibilityHidden(true)
                        Text(selectedZoneLabel)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MeridianColors.onSurfaceVariant)
                            .accessibilityHidden(true)
                    }
                    .font(.bodyMedium)
                    .foregroundStyle(MeridianColors.onSurface)
                    .padding(.horizontal, MeridianSpacing.md.rawValue)
                    .padding(.vertical, MeridianSpacing.md.rawValue)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .background {
                        RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    }
                }
                .buttonStyle(PressableScaleStyle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Time zone, \(selectedZoneLabel)")
                .accessibilityHint("Double tap to change time zone")
                .accessibilityAddTraits(.isButton)
            }

            preview

            // Add button.
            Button {
                addTask()
            } label: {
                HStack(spacing: MeridianSpacing.sm.rawValue) {
                    if addedFlash {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(MeridianColors.positive)
                            .transition(.scale.combined(with: .opacity))
                        Text("Added to your plan")
                    } else {
                        Text("Add to plan")
                    }
                }
                .font(.titleMedium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MeridianSpacing.md.rawValue)
                .frame(minHeight: 44)
                .contentShape(Capsule())
                .background {
                    Capsule().fill(canAdd ? MeridianColors.primary : MeridianColors.onSurfaceVariant.opacity(0.3))
                }
                .foregroundStyle(MeridianColors.onPrimary)
                .animation(reduceMotion ? nil : Motion.bouncy(), value: addedFlash)
            }
            .buttonStyle(PressableScaleStyle())
            .disabled(!canAdd)
            .animation(reduceMotion ? nil : Motion.snappy(), value: canAdd)
            .accessibilityLabel(addedFlash ? "Added to your plan" : "Add to plan")
            .accessibilityHint(addButtonHint)
        }
    }

    /// Explains why the Add button is unavailable so VoiceOver users understand the disabled state.
    private var addButtonHint: String {
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Enter an event title to add it to your plan"
        }
        if isPast {
            return "The chosen time has already passed. Pick a later time to add it."
        }
        return "Adds this event to your plan"
    }

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !isPast
    }

    // MARK: Live preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue) {
            Text(title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled event" : title)
                .font(.titleMedium)
                .foregroundStyle(MeridianColors.onSurface)

            HStack(spacing: MeridianSpacing.xs.rawValue) {
                Image(systemName: todIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(todAccent)
                    .accessibilityHidden(true)
                Text("\(dateLabel) · \(timeLabel) · \(selectedZoneLabel) — \(relative)")
                    .font(.bodyMedium)
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.65))
            }

            if let localEquivalent {
                HStack(spacing: MeridianSpacing.xs.rawValue) {
                    Text("Your time:")
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                    Text(localEquivalentValue ?? localEquivalent)
                        .font(.bodyMedium.weight(.semibold))
                        .foregroundStyle(MeridianColors.primary)
                }
                .padding(.top, MeridianSpacing.xs.rawValue)
                .accessibilityElement(children: .combine)
            }

            if isPast {
                HStack(spacing: MeridianSpacing.xs.rawValue) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12))
                        .accessibilityHidden(true)
                    Text("That time has already passed — pick a later time.")
                }
                .font(.labelMedium)
                .foregroundStyle(MeridianColors.error)
                .padding(.top, MeridianSpacing.xs.rawValue)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("That time has already passed. Pick a later time.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MeridianSpacing.md.rawValue)
        .background {
            RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                .fill(MeridianColors.surface.opacity(0.5))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview")
        .accessibilityValue(previewAccessibilityValue)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// The bare local-equivalent value ("date · time"), with the trailing " your time" stripped
    /// since the visible "Your time:" prefix now carries that meaning.
    private var localEquivalentValue: String? {
        guard let localEquivalent else { return nil }
        let suffix = " your time"
        guard localEquivalent.hasSuffix(suffix) else { return localEquivalent }
        return String(localEquivalent.dropLast(suffix.count))
    }

    /// A single spoken summary of the live preview for VoiceOver.
    private var previewAccessibilityValue: String {
        let name = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled event" : title
        var parts = ["\(name), \(dateLabel) at \(timeLabel) \(selectedZoneLabel), \(relative)"]
        if let localEquivalent { parts.append("Your time: \(localEquivalent)") }
        if isPast { parts.append("That time has already passed. Pick a later time.") }
        return parts.joined(separator: ". ")
    }

    // MARK: Chips

    private func presetChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button {
            feedbackTrigger &+= 1
            action()
        } label: {
            HStack(spacing: MeridianSpacing.xs.rawValue) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MeridianColors.primary)
                    .accessibilityHidden(true)
                Text(label)
            }
            .font(.labelMedium)
            .foregroundStyle(MeridianColors.onSurface)
            .padding(.horizontal, MeridianSpacing.md.rawValue)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .background {
                Capsule()
                    .fill(MeridianColors.surface.opacity(0.6))
                    .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
            }
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Actions

    /// Applies a relative shortcut (in local time) to the date/time + resets zone to Local,
    /// mirroring Android `applyPreset`.
    private func applyPreset(addingDays days: Int = 0, addingHours hours: Int = 0, hour: Int? = nil, minute: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeFormats.safeTimeZone(id: localZoneId)
        var target = Date()
        if days != 0 { target = cal.date(byAdding: .day, value: days, to: target) ?? target }
        if hours != 0 { target = cal.date(byAdding: .hour, value: hours, to: target) ?? target }
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: target)
        if let hour { comps.hour = hour }
        comps.minute = minute
        comps.second = 0
        if let resolved = cal.date(from: comps) {
            selectedDate = resolved
        }
        selectedZoneId = localZoneId
        selectedZoneLabel = "Local"
    }

    private func addTask() {
        feedbackTrigger &+= 1
        onAdd(
            PlannedTask(
                title: title.trimmingCharacters(in: .whitespaces),
                timestamp: targetInstant,
                tzId: selectedZoneId
            )
        )
        title = ""
        addedFlash = true
    }

    // MARK: Helpers

    /// Human relative phrasing like "in 3 hrs" / "2 days ago" (Android `relativeTime`).
    static func relativeTime(target: Date, now: Date) -> String {
        let minutes = Int(target.timeIntervalSince(now) / 60)
        let past = minutes < 0
        let absMinutes = abs(minutes)
        let hours = absMinutes / 60
        let days = hours / 24

        let core: String
        if absMinutes < 1 {
            return "now"
        } else if absMinutes < 60 {
            core = "\(absMinutes) min"
        } else if hours < 24 {
            core = "\(hours) hr\(hours > 1 ? "s" : "")"
        } else {
            core = "\(days) day\(days > 1 ? "s" : "")"
        }
        return past ? "\(core) ago" : "in \(core)"
    }
}

// MARK: - PressableScaleStyle

/// Shared pressed-scale feedback for the card's hand-rolled controls, matching the
/// Liquid-Glass system's press treatment (subtle depress on `Motion.quick()`).
/// Respects Reduce Motion by skipping the transform.
private struct PressableScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.96 : 1.0))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(Motion.quick(), value: configuration.isPressed)
    }
}

// MARK: - ZonePickerSheet

/// A compact zone picker: quick options (local + saved) plus async search across
/// the multi-layer `searchTimeZones` engine. Self-contained replacement for the
/// Android `ZoneSearchPicker`.
private struct ZonePickerSheet: View {

    let localZoneId: String
    let quickZones: [(id: String, label: String)]
    let selectedZoneId: String
    let searchZones: (String) async -> [ZoneMatch]
    let onSelect: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ZoneMatch] = []
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section("Quick zones") {
                        ForEach(quickZones, id: \.id) { zone in
                            row(id: zone.id, label: zone.label)
                        }
                    }
                } else {
                    Section("Results") {
                        if results.isEmpty {
                            Text("No matching zones")
                                .foregroundStyle(MeridianColors.onSurfaceVariant)
                        } else {
                            ForEach(results) { match in
                                row(id: match.zoneId, label: match.displayName)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Time zone")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search cities, airports, offsets…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else {
                    results = []
                    return
                }
                searchTask = Task {
                    let hits = await searchZones(trimmed)
                    if !Task.isCancelled { results = hits }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(id: String, label: String) -> some View {
        Button {
            onSelect(id, label)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.bodyLarge)
                        .foregroundStyle(MeridianColors.onSurface)
                    Text(id)
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }
                Spacer()
                if id == selectedZoneId {
                    Image(systemName: "checkmark")
                        .foregroundStyle(MeridianColors.primary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("QuickScheduleCard", traits: .sizeThatFitsLayout) {
    QuickScheduleCard(
        savedZones: [("Europe/London", "London"), ("Asia/Tokyo", "Tokyo")],
        is24Hour: false,
        searchZones: { _ in [] },
        onAdd: { _ in }
    )
    .padding()
    .background(Color(hex: "#020617"))
    .environment(\.glassEnabled, true)
}
#endif
