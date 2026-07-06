// JumpModal.swift
// Meridian — iOS 27 / Swift 6
//
// "Jump to Place & Time" sheet. Direct behavioral port of Android `JumpToPlaceDateTimeModal`.
// Pick a target zone (local or any saved/searched zone) and a wall-clock date+time IN THAT ZONE;
// the sheet resolves to an absolute instant and the chosen zone id, surfacing the equivalent
// local time as a callout. The Plan screen then re-bases the window on that instant.

import SwiftUI

// MARK: - JumpModal

struct JumpModal: View {
    let localZoneId: String
    let localLocationName: String
    /// Saved zones offered as quick picks, plus the local zone.
    let savedZones: [SavedZone]
    let searchZones: (String) async -> [ZoneMatch]
    let use24Hour: Bool
    /// Called with the resolved absolute instant and the target zone id.
    let onJump: (Date, String) -> Void
    let onDismiss: () -> Void

    @State private var selectedZoneId: String
    @State private var selectedZoneLabel: String
    /// Wall-clock fields interpreted IN `selectedZoneId`.
    @State private var wallComponents: DateComponents
    @State private var results: [ZoneMatch] = []
    @State private var zoneQuery = ""
    @State private var searchTask: Task<Void, Never>? = nil
    /// True while a debounced zone search is in flight — drives the pending spinner
    /// and keeps the "no matches" row from flashing before results settle.
    @State private var isSearching = false

    init(
        localZoneId: String,
        localLocationName: String,
        savedZones: [SavedZone],
        searchZones: @escaping (String) async -> [ZoneMatch],
        use24Hour: Bool,
        onJump: @escaping (Date, String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.localZoneId = localZoneId
        self.localLocationName = localLocationName
        self.savedZones = savedZones
        self.searchZones = searchZones
        self.use24Hour = use24Hour
        self.onJump = onJump
        self.onDismiss = onDismiss
        _selectedZoneId = State(initialValue: localZoneId)
        _selectedZoneLabel = State(initialValue: localLocationName)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeFormats.safeTimeZone(id: localZoneId)
        _wallComponents = State(
            initialValue: cal.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        )
    }

    // MARK: Derived

    /// The absolute instant for the chosen wall-clock fields in the selected zone.
    private var targetInstant: Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeFormats.safeTimeZone(id: selectedZoneId)
        return cal.date(from: wallComponents)
    }

    /// `Date` bound for the DatePicker, expressed in the SELECTED zone's wall clock.
    private var pickerBinding: Binding<Date> {
        Binding(
            get: { targetInstant ?? Date() },
            set: { newDate in
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeFormats.safeTimeZone(id: selectedZoneId)
                wallComponents = cal.dateComponents([.year, .month, .day, .hour, .minute], from: newDate)
            }
        )
    }

    private var displayName: String {
        selectedZoneId == localZoneId ? localLocationName : selectedZoneLabel
    }

    private var offsetDifference: String {
        let now = Date()
        let target = TimeFormats.offsetSeconds(for: selectedZoneId, at: now)
        let local = TimeFormats.offsetSeconds(for: localZoneId, at: now)
        let diffHours = Double(target - local) / 3600.0
        if diffHours == 0 { return "same time" }
        let sign = diffHours > 0 ? "+" : "-"
        let absHours = abs(diffHours)
        let hourStr = absHours.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(absHours)) : String(absHours)
        return "\(sign)\(hourStr)h"
    }

    private var localEquivalent: String? {
        guard let instant = targetInstant, selectedZoneId != localZoneId else { return nil }
        let date = TimeFormats.shortDate(date: instant, timeZoneId: localZoneId)
        let time = TimeFormats.hourMinute(
            date: instant, timeZone: TimeFormats.safeTimeZone(id: localZoneId), use24Hour: use24Hour
        )
        return "\(date) · \(time) (\(localLocationName))"
    }

    /// A spoken, non-symbolic description of `localEquivalent` for VoiceOver
    /// (the visual version leads with "=" and "·", which read poorly aloud).
    private var localEquivalentAccessibility: String? {
        guard let instant = targetInstant, selectedZoneId != localZoneId else { return nil }
        let date = TimeFormats.shortDate(date: instant, timeZoneId: localZoneId)
        let time = TimeFormats.hourMinute(
            date: instant, timeZone: TimeFormats.safeTimeZone(id: localZoneId), use24Hour: use24Hour
        )
        return "In your local time: \(date), \(time) in \(localLocationName)"
    }

    /// A spoken description of `offsetDifference` ("9 hours ahead of you") — clearer
    /// than the visual "+9h" for VoiceOver users.
    private var offsetDifferenceAccessibility: String {
        let now = Date()
        let target = TimeFormats.offsetSeconds(for: selectedZoneId, at: now)
        let local = TimeFormats.offsetSeconds(for: localZoneId, at: now)
        let diffHours = Double(target - local) / 3600.0
        if diffHours == 0 { return "Same time as you" }
        let absHours = abs(diffHours)
        let hourStr = absHours.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(absHours)) : String(absHours)
        let unit = absHours == 1 ? "hour" : "hours"
        let direction = diffHours > 0 ? "ahead of you" : "behind you"
        return "\(hourStr) \(unit) \(direction)"
    }

    /// True once a query has been entered and the search has settled with no matches.
    private var showsNoMatches: Bool {
        !zoneQuery.trimmingCharacters(in: .whitespaces).isEmpty && !isSearching && results.isEmpty
    }

    private var quickZones: [(id: String, label: String)] {
        var out: [(String, String)] = [(localZoneId, localLocationName)]
        for zone in savedZones where zone.id != localZoneId {
            out.append((zone.id, zone.displayName))
        }
        return out
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Place") {
                    Picker("Zone", selection: $selectedZoneId) {
                        ForEach(quickZones, id: \.id) { item in
                            Text(item.label).tag(item.id)
                        }
                    }
                    .onChange(of: selectedZoneId) { _, id in
                        selectedZoneLabel = quickZones.first { $0.id == id }?.label
                            ?? TimeFormats.safeTimeZone(id: id).identifier
                    }

                    HStack(spacing: MeridianSpacing.sm.rawValue) {
                        TextField("Search another city or zone", text: $zoneQuery)
                            .textInputAutocapitalization(.words)
                            .onChange(of: zoneQuery) { _, query in runSearch(query) }
                        if isSearching {
                            ProgressView()
                                .tint(MeridianColors.primary)
                                .accessibilityLabel("Searching")
                        }
                    }
                    ForEach(results.prefix(4)) { zone in
                        Button {
                            searchTask?.cancel()
                            isSearching = false
                            selectedZoneId = zone.zoneId
                            selectedZoneLabel = zone.displayName
                            zoneQuery = ""
                            results = []
                        } label: {
                            VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue) {
                                Text(zone.displayName)
                                    .font(.titleMedium)
                                    .foregroundStyle(MeridianColors.onSurface)
                                Text(zone.zoneId)
                                    .font(.bodyMedium)
                                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Selects this zone")
                    }
                    if showsNoMatches {
                        Text("No matching cities")
                            .font(.bodyMedium)
                            .foregroundStyle(MeridianColors.onSurfaceVariant)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("No matching cities found")
                    }
                }

                Section {
                    placeCard
                }

                Section("Date & time (in \(displayName))") {
                    DatePicker(
                        "When",
                        selection: pickerBinding,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .environment(\.timeZone, TimeFormats.safeTimeZone(id: selectedZoneId))
                }

                if let localEquivalent {
                    Section {
                        Label("= \(localEquivalent)", systemImage: "clock")
                            .font(.bodyMedium)
                            .foregroundStyle(MeridianColors.onSurface)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(localEquivalentAccessibility ?? localEquivalent)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: selectedZoneId)
            .navigationTitle("Jump to Place & Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Jump") {
                        if let instant = targetInstant { onJump(instant, selectedZoneId) }
                    }
                    .disabled(targetInstant == nil)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    private var placeCard: some View {
        HStack(alignment: .top, spacing: MeridianSpacing.md.rawValue) {
            VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue) {
                Text(displayName)
                    .font(.titleMedium)
                    .fontWeight(.bold)
                    .foregroundStyle(MeridianColors.onSurface)
                Text(selectedZoneId)
                    .font(.bodyMedium)
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                if selectedZoneId != localZoneId {
                    Text("\(offsetDifference) compared to you")
                        .font(.labelMedium)
                        .fontWeight(.semibold)
                        .foregroundStyle(MeridianColors.primary)
                        .accessibilityLabel(offsetDifferenceAccessibility)
                }
            }
            Spacer(minLength: MeridianSpacing.sm.rawValue)
            if let instant = targetInstant {
                VStack(alignment: .trailing, spacing: MeridianSpacing.xs.rawValue) {
                    Text(
                        TimeFormats.hourMinute(
                            date: instant,
                            timeZone: TimeFormats.safeTimeZone(id: selectedZoneId),
                            use24Hour: use24Hour
                        )
                    )
                    .font(.headlineMedium)
                    .fontWeight(.heavy)
                    .foregroundStyle(MeridianColors.primary)
                    Text(TimeFormats.shortDate(date: instant, timeZoneId: selectedZoneId))
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurface.opacity(0.7))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func runSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120)) // debounce
            guard !Task.isCancelled else { return }
            let hits = await searchZones(trimmed)
            guard !Task.isCancelled else { return }
            results = hits
            isSearching = false
        }
    }
}
