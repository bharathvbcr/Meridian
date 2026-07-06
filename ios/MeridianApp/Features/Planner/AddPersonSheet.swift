// AddPersonSheet.swift
// Meridian — iOS 27 / Swift 6
//
// "Add participant" sheet. Direct behavioral port of Android `AddPersonDialog` (PeopleCard.kt):
// leave the name blank to add a CITY only, or enter a name to add a PERSON with their own
// work window and optional DND window. A debounced zone search backs the city/time-zone field.

import SwiftUI

// MARK: - AddParticipantResult

/// What the sheet resolved to on confirm — a nameless city pin, or a named contact.
enum AddParticipantResult: Sendable {
    case city(zoneId: String, displayName: String)
    case person(
        name: String,
        zoneId: String,
        displayName: String,
        workStartHour: Int,
        workEndHour: Int,
        dndStartHour: Int,
        dndEndHour: Int
    )
}

// MARK: - AddPersonSheet

struct AddPersonSheet: View {
    /// Debounced multi-layer zone search (delegated to `MainViewModel.searchTimeZones`).
    let searchZones: (String) async -> [ZoneMatch]
    var defaultWorkStart: Int = 9
    var defaultWorkEnd: Int = 17
    let onConfirm: (AddParticipantResult) -> Void
    let onDismiss: () -> Void

    @State private var name = ""
    @State private var zoneQuery = ""
    @State private var pickedZone: ZoneMatch? = nil
    @State private var results: [ZoneMatch] = []
    @State private var workStart: Int
    @State private var workEnd: Int
    @State private var dndEnabled = false
    @State private var dndStart = 22
    @State private var dndEnd = 7
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var showContactPicker = false
    @State private var isSearching = false
    @State private var didConfirm = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Spring used for content reveals; collapses to no animation under Reduce Motion.
    private var revealAnimation: Animation? { reduceMotion ? nil : Motion.snappy() }

    init(
        searchZones: @escaping (String) async -> [ZoneMatch],
        defaultWorkStart: Int = 9,
        defaultWorkEnd: Int = 17,
        onConfirm: @escaping (AddParticipantResult) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.searchZones = searchZones
        self.defaultWorkStart = defaultWorkStart
        self.defaultWorkEnd = defaultWorkEnd
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        _workStart = State(initialValue: defaultWorkStart)
        _workEnd = State(initialValue: defaultWorkEnd)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var canConfirm: Bool { pickedZone != nil }
    private var confirmTitle: String { trimmedName.isEmpty ? "Add city" : "Add person" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Leave name blank to add a city only, or enter a name to add a person.")
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }

                Section("Name") {
                    HStack(spacing: 8) {
                        TextField("Name (optional)", text: $name)
                            .textInputAutocapitalization(.words)
                        // Pull the name from system contacts (Android: trailing person
                        // icon → ActivityResultContracts.PickContact). Zone stays manual.
                        Button {
                            showContactPicker = true
                        } label: {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 18))
                                .foregroundStyle(MeridianColors.primary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Pick from contacts")
                        .accessibilityHint("Fill the name from a system contact")
                    }
                }

                Section {
                    if let zone = pickedZone {
                        HStack(spacing: MeridianSpacing.sm.rawValue) {
                            VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue) {
                                Text(zone.displayName).fontWeight(.bold)
                                Text(zone.zoneId)
                                    .font(.bodyMedium)
                                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Selected city, \(zone.displayName), \(zone.zoneId)")
                            Spacer()
                            Button {
                                pickedZone = nil
                                zoneQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear selected city")
                            .accessibilityHint("Search for a different city")
                        }
                    } else {
                        TextField("Search city or time zone", text: $zoneQuery)
                            .textInputAutocapitalization(.words)
                            .onChange(of: zoneQuery) { _, query in runSearch(query) }
                        ForEach(results.prefix(4)) { zone in
                            Button {
                                pickedZone = zone
                                results = []
                            } label: {
                                VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue) {
                                    Text(zone.displayName).fontWeight(.semibold)
                                    Text(zone.zoneId)
                                        .font(.bodyMedium)
                                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Select this city")
                        }
                        if !zoneQuery.trimmingCharacters(in: .whitespaces).isEmpty
                            && results.isEmpty && !isSearching {
                            Label {
                                Text("No matching cities")
                                    .font(.bodyMedium)
                                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                            } icon: {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                                    .accessibilityHidden(true)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("No matching cities. Try another name.")
                        }
                    }
                } header: {
                    Text("City / time zone")
                } footer: {
                    if !canConfirm {
                        Text("Pick a city to continue.")
                            .font(.labelMedium)
                            .foregroundStyle(MeridianColors.onSurfaceVariant)
                    }
                }

                if !trimmedName.isEmpty {
                    Section("Work hours") {
                        HourStepperRow(label: "Work start", hour: $workStart) { newStart in
                            if newStart >= workEnd { workEnd = min(newStart + 1, 23) }
                        }
                        HourStepperRow(label: "Work end", hour: $workEnd) { newEnd in
                            if newEnd <= workStart { workEnd = workStart + 1 }
                        }
                    }
                    Section {
                        Toggle("Do not disturb", isOn: $dndEnabled)
                            .tint(MeridianColors.primary)
                            .accessibilityHint("Silence notifications during set hours")
                        if dndEnabled {
                            HourStepperRow(label: "DND start", hour: $dndStart)
                            HourStepperRow(label: "DND end", hour: $dndEnd)
                        }
                    } footer: {
                        if dndEnabled {
                            Text("Notifications are muted between these hours in this person's local time.")
                                .font(.labelMedium)
                                .foregroundStyle(MeridianColors.onSurfaceVariant)
                        }
                    }
                }
            }
            .animation(revealAnimation, value: pickedZone)
            .animation(revealAnimation, value: results)
            .animation(revealAnimation, value: isSearching)
            .animation(revealAnimation, value: dndEnabled)
            .animation(revealAnimation, value: trimmedName.isEmpty)
            .navigationTitle("Add participant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle, action: confirm)
                        .fontWeight(.semibold)
                        .disabled(!canConfirm)
                        .accessibilityHint(canConfirm ? "" : "Select a city first")
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .sensoryFeedback(.success, trigger: didConfirm)
        .sheet(isPresented: $showContactPicker) {
            ContactPicker { pickedName in
                name = pickedName
            }
        }
    }

    private func runSearch(_ query: String) {
        pickedZone = nil
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { results = []; isSearching = false; return }
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

    private func confirm() {
        guard let zone = pickedZone else { return }
        didConfirm.toggle()
        if trimmedName.isEmpty {
            onConfirm(.city(zoneId: zone.zoneId, displayName: zone.displayName))
        } else {
            onConfirm(
                .person(
                    name: trimmedName,
                    zoneId: zone.zoneId,
                    displayName: zone.displayName,
                    workStartHour: workStart,
                    workEndHour: workEnd,
                    dndStartHour: dndEnabled ? dndStart : -1,
                    dndEndHour: dndEnabled ? dndEnd : -1
                )
            )
        }
    }
}

// MARK: - HourStepperRow

/// A labelled 0–23 hour stepper. Mirrors Android `HourStepperRow`.
struct HourStepperRow: View {
    let label: String
    @Binding var hour: Int
    var onChange: (Int) -> Void = { _ in }

    private var formattedHour: String { String(format: "%02d:00", hour) }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(MeridianColors.onSurface)
            Spacer()
            Stepper(
                value: Binding(
                    get: { hour },
                    set: { newValue in
                        let clamped = min(max(newValue, 0), 23)
                        hour = clamped
                        onChange(clamped)
                    }
                ),
                in: 0...23
            ) {
                Text(formattedHour)
                    .monospacedDigit()
                    .foregroundStyle(MeridianColors.onSurface)
            }
            .labelsHidden()
            .tint(MeridianColors.primary)
            .accessibilityLabel(label)
            .accessibilityValue(formattedHour)
            Text(formattedHour)
                .monospacedDigit()
                .frame(minWidth: 56, alignment: .trailing)
                .foregroundStyle(MeridianColors.onSurface)
                .accessibilityHidden(true)
        }
    }
}
