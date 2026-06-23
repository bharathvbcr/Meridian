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
                    TextField("Name (optional)", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("City / time zone") {
                    if let zone = pickedZone {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(zone.displayName).fontWeight(.bold)
                                Text(zone.zoneId)
                                    .font(.bodyMedium)
                                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                            }
                            Spacer()
                            Button {
                                pickedZone = nil
                                zoneQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                            }
                            .buttonStyle(.plain)
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
                                VStack(alignment: .leading) {
                                    Text(zone.displayName).fontWeight(.semibold)
                                    Text(zone.zoneId)
                                        .font(.bodyMedium)
                                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                                }
                            }
                        }
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
                        if dndEnabled {
                            HourStepperRow(label: "DND start", hour: $dndStart)
                            HourStepperRow(label: "DND end", hour: $dndEnd)
                        }
                    }
                }
            }
            .navigationTitle("Add participant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle, action: confirm).disabled(!canConfirm)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    private func runSearch(_ query: String) {
        pickedZone = nil
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { results = []; return }
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120)) // debounce
            guard !Task.isCancelled else { return }
            let hits = await searchZones(trimmed)
            guard !Task.isCancelled else { return }
            results = hits
        }
    }

    private func confirm() {
        guard let zone = pickedZone else { return }
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
                Text(String(format: "%02d:00", hour))
                    .monospacedDigit()
                    .foregroundStyle(MeridianColors.onSurface)
            }
            .labelsHidden()
            Text(String(format: "%02d:00", hour))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
                .foregroundStyle(MeridianColors.onSurface)
        }
    }
}
