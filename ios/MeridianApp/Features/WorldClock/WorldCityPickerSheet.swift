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

    @State private var query: String = ""
    @State private var results: [ZoneMatch] = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        GlassBottomSheet {
            VStack(alignment: .leading, spacing: 0) {
                Text("Add worldwide cities")
                    .font(.system(size: 16, weight: .bold))   // titleMedium + Bold
                    .foregroundStyle(MeridianColors.onSurface)
                    .padding(.bottom, 4)

                Text("Search any city, airport, or time zone. Resolved on-device.")
                    .font(.system(size: 12))
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.6))
                    .padding(.bottom, 12)

                searchField
                    .padding(.bottom, 12)

                resultsSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .presentationDetents([.large])
        // 120 ms debounce: any query change restarts this task; the sleep is cancelled before
        // a new search, matching Android's produceState debounce.
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                results = []
                return
            }
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            let found = await viewModel.searchTimeZones(query)
            if Task.isCancelled { return }
            results = found
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

    // MARK: - Results

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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(MeridianColors.onSurface)
                    Text(result.zoneId)
                        .font(.system(size: 12))
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }

                Spacer(minLength: 0)

                Text(localTime)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MeridianColors.primary)
                    .monospacedDigit()

                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MeridianColors.primary)
                    .accessibilityLabel("Add \(result.displayName)")
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sensoryFeedback(.impact(weight: .medium), trigger: result.id)
    }
}
