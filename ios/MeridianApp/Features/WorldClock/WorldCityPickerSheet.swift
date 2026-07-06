//  WorldCityPickerSheet.swift
//  Meridian — iOS 27 / Swift 6
//
//  Ported from the `WorldCityPickerSheet` composable in WorldClockScreen.kt.
//
//  A glass bottom-sheet city search for the World Clock, mirroring the Settings home-city
//  picker so the input sits cleanly above the keyboard (which auto-opens). Search-as-you-type
//  is debounced 120 ms and routed through `MainViewModel.searchTimeZones` (the multi-layer
//  offset → abbreviation → curated → city DB → airport → raw-IANA merge). Each result shows
//  its current local time. Tapping a row pins the zone and CLEARS the query — keeping the
//  sheet open and the keyboard up — so several cities can be added in one pass.

import SwiftUI

struct WorldCityPickerSheet: View {

    /// Owning view model — search runs on its main actor; adds go through `addZone`.
    let viewModel: MainViewModel
    /// Shared display instant (scrub-aware) for the per-row local time preview.
    let instant: Date
    let use24Hour: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var query: String = ""
    @State private var results: [ZoneMatch] = []
    /// True while the debounce + async `searchTimeZones` is in flight for a non-empty query,
    /// so the results section can show a searching state instead of flashing "No locations found".
    @State private var isSearching: Bool = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        GlassBottomSheet {
            VStack(alignment: .leading, spacing: 0) {
                Text("Add worldwide cities")
                    .font(.titleMedium.weight(.bold))
                    .foregroundStyle(MeridianColors.onSurface)
                    .padding(.bottom, MeridianSpacing.xs.rawValue)
                    .accessibilityAddTraits(.isHeader)

                Text("Search any city, airport, or time zone. Resolved on-device.")
                    .font(.labelMedium.weight(.regular))
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                    .padding(.bottom, MeridianSpacing.md.rawValue)

                searchField
                    .padding(.bottom, MeridianSpacing.md.rawValue)

                resultsSection
            }
            .padding(.horizontal, MeridianSpacing.lg.rawValue)
            .padding(.bottom, MeridianSpacing.lg.rawValue)
        }
        .presentationDetents([.large])
        // 120 ms debounce: any query change restarts this task; the sleep is cancelled before
        // a new search, matching Android's produceState debounce.
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                results = []
                isSearching = false
                return
            }
            // Enter the searching state immediately so a non-empty query never renders the
            // "No locations found" branch before the async lookup has had a chance to run.
            isSearching = true
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            let found = await viewModel.searchTimeZones(query)
            if Task.isCancelled { return }
            withAnimation(reduceMotion ? nil : Motion.snappy()) {
                results = found
                isSearching = false
            }
        }
        .task {
            // Autofocus shortly after present (Android delays 180 ms before requesting focus).
            try? await Task.sleep(for: .milliseconds(180))
            searchFocused = true
        }
    }

    // MARK: - Search field

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
            .onSubmit { searchFocused = false }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityAddTraits(.isButton)
                .sensoryFeedback(.impact(weight: .light), trigger: query)
            }
        }
        .padding(.leading, MeridianSpacing.md.rawValue)
        // Trailing padding is smaller so the clear button's own 44pt frame supplies the inset.
        .padding(.trailing, query.isEmpty ? MeridianSpacing.md.rawValue : MeridianSpacing.xs.rawValue)
        .padding(.vertical, query.isEmpty ? MeridianSpacing.md.rawValue : 0)
        .frame(minHeight: 44)
        .background {
            RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                .strokeBorder(
                    searchFocused ? MeridianColors.primary
                                  : MeridianColors.onSurfaceVariant.opacity(0.5),
                    lineWidth: 1
                )
        }
        .animation(reduceMotion ? nil : Motion.snappy(), value: searchFocused)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
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
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
        } else if !trimmed.isEmpty && isSearching {
            // In-flight: show a searching indicator so a cleared-but-pending query never flashes
            // the false-negative "No locations found" branch below.
            HStack(spacing: MeridianSpacing.sm.rawValue) {
                Spacer()
                ProgressView()
                    .tint(MeridianColors.primary)
                Text("Searching…")
                    .font(.bodyMedium)
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                Spacer()
            }
            .padding(.vertical, MeridianSpacing.xxl.rawValue)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Searching for locations")
        } else if !trimmed.isEmpty {
            HStack(spacing: MeridianSpacing.md.rawValue) {
                Spacer()
                Image(systemName: "mappin.slash")
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                    .accessibilityHidden(true)
                Text("No locations found")
                    .font(.bodyMedium)
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                Spacer()
            }
            .padding(.vertical, MeridianSpacing.xxl.rawValue)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No locations found for \(trimmed)")
        }
    }

    private func resultRow(_ result: ZoneMatch) -> some View {
        let localTime = TimeFormats.hourMinute(
            date: instant, timeZoneId: result.zoneId, use24Hour: use24Hour
        )
        return Button {
            // Add and clear the query (keeping the sheet open + keyboard up) so several
            // cities can be pinned in a row.
            viewModel.addZone(from: result)
            query = ""
        } label: {
            HStack(spacing: MeridianSpacing.md.rawValue) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.displayName)
                        .font(.bodyLarge.weight(.medium))
                        .foregroundStyle(MeridianColors.onSurface)
                    Text(result.zoneId)
                        .font(.labelMedium.weight(.regular))
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }

                Spacer(minLength: MeridianSpacing.sm.rawValue)

                Text(localTime)
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundStyle(MeridianColors.primary)
                    .monospacedDigit()

                Image(systemName: "plus")
                    .font(.bodyLarge.weight(.semibold))
                    .foregroundStyle(MeridianColors.primary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, MeridianSpacing.sm.rawValue)
            .padding(.vertical, MeridianSpacing.md.rawValue)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous))
        // One combined VoiceOver element for the whole tappable row instead of loose sub-elements.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.displayName), \(localTime) local")
        .accessibilityHint("Adds this location")
        .accessibilityAddTraits(.isButton)
        .sensoryFeedback(.impact(weight: .medium), trigger: result.id)
    }
}
