// HomeCityPickerSheet.swift
// Meridian — iOS 27 / Swift 6
//
// Ported from app/src/main/java/com/example/core/designsystem/HomeCityPickerSheet.kt
//
// A glass bottom-sheet city search: an autofocused search field, a 120 ms-debounced
// async search returning `[SavedZone]`, a results list (home icon + display name +
// IANA id, divided rows), and a "No locations found" empty state. Selecting a row
// dismisses the keyboard and invokes `onCitySelected`.
//
// Presentation: wrap in `.sheet { HomeCityPickerSheet(...) }` (it renders its own
// `GlassBottomSheet` chrome).

import SwiftUI

struct HomeCityPickerSheet: View {

    /// Called when the user taps a result.
    let onCitySelected: (SavedZone) -> Void
    /// Async, debounced search. Mirrors Android `search: suspend (String) -> List<SavedZone>`.
    /// MainActor-isolated (not `@Sendable`): `SavedZone` is a SwiftData `@Model` reference
    /// type, and the backing search (`MainViewModel.searchTimeZones`) is `@MainActor`.
    let search: (String) async -> [SavedZone]
    var title: String = "Choose your home city"
    var subtitle: String = "Search any city, airport, or time zone. Resolved on-device."

    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var results: [SavedZone] = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        GlassBottomSheet {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))   // titleLarge + Bold
                    .foregroundStyle(MeridianColors.onSurface)
                    .padding(.bottom, 4)

                Text(subtitle)
                    .font(.system(size: 12))                   // bodySmall
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.6))
                    .padding(.bottom, 12)

                searchField
                    .padding(.bottom, 12)

                resultsSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        // 120 ms debounce: any change to the query restarts this task; the sleep is
        // cancelled before issuing a new search, matching Android's produceState.
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                results = []
                return
            }
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            let found = await search(query)
            if Task.isCancelled { return }
            results = found
        }
        .task {
            // Autofocus shortly after present so the field is attached (Android delays 180 ms).
            try? await Task.sleep(for: .milliseconds(180))
            searchFocused = true
        }
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MeridianColors.onSurfaceVariant)

            TextField(
                "",
                text: $query,
                prompt: Text("E.g. Paris, Tokyo, Sydney...")
                    .foregroundColor(MeridianColors.onSurfaceVariant)
            )
            .focused($searchFocused)
            .foregroundStyle(MeridianColors.onSurface)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .sensoryFeedback(.impact(weight: .light), trigger: query)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    searchFocused ? MeridianColors.primary
                                  : MeridianColors.onSurfaceVariant.opacity(0.5),
                    lineWidth: 1
                )
        }
    }

    // MARK: Results

    @ViewBuilder
    private var resultsSection: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && results.isEmpty {
            HStack {
                Spacer()
                Text("No locations found")
                    .font(.system(size: 14))
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                Spacer()
            }
            .padding(.vertical, 24)
        } else if !results.isEmpty {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        resultRow(result)
                        if index < results.count - 1 {
                            Rectangle()
                                .fill(MeridianColors.onSurface.opacity(0.08))
                                .frame(height: 1)
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }

    private func resultRow(_ result: SavedZone) -> some View {
        Button {
            searchFocused = false
            onCitySelected(result)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "house")
                    .font(.system(size: 18))
                    .foregroundStyle(MeridianColors.primary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(result.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(MeridianColors.onSurface)
                    Text(result.id)
                        .font(.system(size: 12))
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sensoryFeedback(.impact(weight: .light), trigger: result.id)
        .accessibilityAddTraits(.isButton)
    }
}
