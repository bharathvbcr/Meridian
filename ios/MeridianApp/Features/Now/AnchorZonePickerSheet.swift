// AnchorZonePickerSheet.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// Ported from `HomeCityPickerSheet` usage in `NowScreen.kt`.
//
// A searchable city/zone picker used to choose an anchor zone (residence or home
// country). Search delegates to the live multi-layer `MainViewModel.searchTimeZones`,
// matching the Android `search = { viewModel.searchTimeZones(it) }` wiring. On selection
// it calls `onSelect(zoneId:displayName:)` and dismisses.

import SwiftUI

// MARK: - AnchorZonePickerSheet

struct AnchorZonePickerSheet: View {

    /// Sheet title (Android varies it by anchor role).
    let title: String
    /// Optional "use current location" handler; hidden when `nil`.
    var onUseLocation: (() -> Void)? = nil
    /// Performs the search; the view model's async multi-layer merge.
    let search: (String) async -> [ZoneMatch]
    /// Called with the chosen zone.
    let onSelect: (_ zoneId: String, _ displayName: String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var results: [ZoneMatch] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            ZStack {
                MeridianColors.background.ignoresSafeArea()

                List {
                    if let onUseLocation, query.isEmpty {
                        Button {
                            onUseLocation()
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(MeridianColors.primary)
                                Text("Use current location")
                                    .font(.titleMedium)
                                    .foregroundStyle(MeridianColors.onSurface)
                                Spacer()
                            }
                        }
                        .listRowBackground(Color.clear)
                    }

                    if isSearching {
                        HStack {
                            ProgressView().tint(MeridianColors.primary)
                            Text("Searching…")
                                .font(.bodyMedium)
                                .foregroundStyle(MeridianColors.onSurfaceVariant)
                        }
                        .listRowBackground(Color.clear)
                    } else if !query.isEmpty && results.isEmpty {
                        Text("No matches for \"\(query)\".")
                            .font(.bodyMedium)
                            .foregroundStyle(MeridianColors.onSurfaceVariant)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(results) { match in
                            Button {
                                onSelect(match.zoneId, match.displayName)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 18))
                                        .foregroundStyle(MeridianColors.primary.opacity(0.8))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(match.displayName)
                                            .font(.titleMedium)
                                            .foregroundStyle(MeridianColors.onSurface)
                                        Text(match.zoneId)
                                            .font(.labelMedium)
                                            .foregroundStyle(MeridianColors.onSurfaceVariant)
                                    }
                                    Spacer()
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(MeridianColors.primary)
                }
            }
            .searchable(text: $query, prompt: "Search a city or zone")
        }
        .preferredColorScheme(.dark)
        .onChange(of: query) { _, newValue in
            scheduleSearch(newValue)
        }
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            let found = await search(trimmed)
            if Task.isCancelled { return }
            results = found
            isSearching = false
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("AnchorZonePickerSheet") {
    AnchorZonePickerSheet(
        title: "Choose your home city",
        search: { _ in
            [
                ZoneMatch(zoneId: "Asia/Kolkata", displayName: "Kolkata"),
                ZoneMatch(zoneId: "Asia/Tokyo", displayName: "Tokyo"),
            ]
        },
        onSelect: { _, _ in }
    )
}
#endif
