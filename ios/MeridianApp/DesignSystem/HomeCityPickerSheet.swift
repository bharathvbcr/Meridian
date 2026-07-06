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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var query: String = ""
    @State private var results: [SavedZone] = []
    /// True while the debounce sleep + async `search()` are in flight for a
    /// non-empty query. Gates the empty state so a valid search doesn't briefly
    /// flash "No locations found" before the first result set returns.
    @State private var isSearching: Bool = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        GlassBottomSheet {
            VStack(alignment: .leading, spacing: MeridianSpacing.md.rawValue) {
                VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue) {
                    Text(title)
                        .font(.titleLarge)
                        .foregroundStyle(MeridianColors.onSurface)

                    Text(subtitle)
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                searchField

                resultsSection
            }
            .padding(.horizontal, MeridianSpacing.lg.rawValue)
            .padding(.bottom, MeridianSpacing.lg.rawValue)
        }
        // 120 ms debounce: any change to the query restarts this task; the sleep is
        // cancelled before issuing a new search, matching Android's produceState.
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                results = []
                isSearching = false
                return
            }
            isSearching = true
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            let found = await search(query)
            if Task.isCancelled { return }
            withAnimation(reduceMotion ? nil : Motion.smooth()) {
                results = found
                isSearching = false
            }
        }
        .task {
            // Autofocus shortly after present so the field is attached (Android delays 180 ms).
            try? await Task.sleep(for: .milliseconds(180))
            searchFocused = true
        }
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: MeridianSpacing.sm.rawValue) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MeridianColors.onSurfaceVariant)
                .accessibilityHidden(true)

            TextField(
                "",
                text: $query,
                prompt: Text("E.g. Paris, Tokyo, Sydney...")
                    .foregroundColor(MeridianColors.onSurfaceVariant)
            )
            .focused($searchFocused)
            .font(.bodyLarge)
            .foregroundStyle(MeridianColors.onSurface)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .accessibilityLabel("Search cities")
            .accessibilityHint("Search any city, airport, or time zone")

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .sensoryFeedback(.impact(weight: .light), trigger: query)
                .transition(.opacity)
            }
        }
        .padding(.leading, MeridianSpacing.md.rawValue)
        // Trailing padding is tighter so the 44pt clear button keeps its edge rhythm.
        .padding(.trailing, query.isEmpty ? MeridianSpacing.md.rawValue : MeridianSpacing.xs.rawValue)
        .padding(.vertical, query.isEmpty ? MeridianSpacing.md.rawValue : MeridianSpacing.xs.rawValue)
        .frame(minHeight: 44)
        .background {
            // Subtle fill so the field reads as a tappable input on the frosted
            // sheet — mirrors how MeridianChip fills its capsule — with the
            // focused-state primary stroke as the focus cue.
            RoundedRectangle(cornerRadius: MeridianRadius.medium.rawValue, style: .continuous)
                .fill(MeridianColors.surface.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: MeridianRadius.medium.rawValue, style: .continuous)
                        .strokeBorder(
                            searchFocused ? MeridianColors.primary
                                          : MeridianColors.onSurfaceVariant.opacity(0.5),
                            lineWidth: searchFocused ? 1.5 : 1
                        )
                }
        }
        .animation(reduceMotion ? nil : Motion.snappy(), value: searchFocused)
        .animation(reduceMotion ? nil : Motion.quick(), value: query.isEmpty)
    }

    // MARK: Results

    @ViewBuilder
    private var resultsSection: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        Group {
            if !results.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            resultRow(result)
                            if index < results.count - 1 {
                                Rectangle()
                                    .fill(MeridianColors.onSurface.opacity(0.08))
                                    .frame(height: 1)
                                    .padding(.horizontal, MeridianSpacing.sm.rawValue)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
            } else if isSearching {
                // In-flight: debounce sleep or async search running. Show progress
                // instead of a premature empty state so a valid search never flashes
                // "No locations found".
                HStack(spacing: MeridianSpacing.sm.rawValue) {
                    Spacer(minLength: 0)
                    ProgressView()
                        .tint(MeridianColors.primary)
                    Text("Searching…")
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, MeridianSpacing.xxl.rawValue)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Searching cities")
            } else if !trimmed.isEmpty {
                // Query present, search finished, nothing found.
                HStack {
                    Spacer(minLength: 0)
                    Text("No locations found")
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, MeridianSpacing.xxl.rawValue)
            }
        }
        .animation(reduceMotion ? nil : Motion.smooth(), value: results.isEmpty)
        .animation(reduceMotion ? nil : Motion.smooth(), value: isSearching)
    }

    private func resultRow(_ result: SavedZone) -> some View {
        Button {
            searchFocused = false
            onCitySelected(result)
        } label: {
            HStack(spacing: MeridianSpacing.md.rawValue) {
                Image(systemName: "house")
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.primary)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue / 2) {
                    Text(result.displayName)
                        .font(.titleMedium)
                        .foregroundStyle(MeridianColors.onSurface)
                    Text(result.id)
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, MeridianSpacing.sm.rawValue)
            .padding(.vertical, MeridianSpacing.md.rawValue)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous))
        .sensoryFeedback(.impact(weight: .light), trigger: result.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.displayName)
        .accessibilityHint("Sets your home city")
        .accessibilityAddTraits(.isButton)
    }
}
