//  WorldClockScreen.swift
//  Meridian — iOS 27 / Swift 6
//
//  Ported from app/src/main/java/com/example/feature/worldclock/WorldClockScreen.kt
//
//  The World Clock: a world day/night visualization (2D map ⇄ 3D globe, see
//  `WorldVisualization`), a "search worldwide cities" entry that opens the glass city
//  picker, and a list of pinned-zone rows that expand for details + contacts. Anchor zones
//  (residence + home country) stay pinned at the top and are NOT reorderable; the remaining
//  watchlist zones reorder via a real `List` `.onMove`, persisted through
//  `MainViewModel.reorderZones(ids:)` (which always packs anchors at the front).
//
//  The timeline scrubber pins `TimeEngine.shared.scrubInstant`; every row, the map, and the
//  globe render from that shared display instant so dragging time sweeps the terminator and
//  re-tints every zone in lock-step.

import SwiftUI
import SwiftData

// MARK: - WorldClockScreen

struct WorldClockScreen: View {

    @Environment(\.mainViewModel) private var injectedViewModel
    @Environment(TimeEngine.self) private var timeEngine
    @Environment(SettingsRepository.self) private var settingsRepo

    /// Scrub offset (seconds from live) bound to the TimelineScrubber and mirrored into the
    /// shared `TimeEngine.scrubInstant` so the whole app tracks the same instant.
    @State private var scrubOffsetSeconds: TimeInterval = 0
    @State private var showCityPicker = false
    /// Drives a re-render of "live" time when not scrubbing.
    @State private var liveTick: Date = .init()

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // MARK: Derived

    private var viewModel: MainViewModel? { injectedViewModel }
    private var settings: MeridianSettings { settingsRepo.settings }
    private var use24Hour: Bool { TimeFormats.uses24Hour(cycle: settings.hourCycle) }

    /// The shared display instant: scrub instant while scrubbing, else live.
    private var displayInstant: Date {
        timeEngine.scrubInstant ?? liveTick
    }

    private var savedZones: [SavedZone] { viewModel?.savedZones ?? [] }

    /// Anchor zones (residence, then home country), pinned + non-reorderable.
    private var anchorZones: [SavedZone] {
        savedZones
            .filter { $0.isNowAnchor }
            .sorted { lhs, rhs in
                func rank(_ z: SavedZone) -> Int {
                    switch z.anchorRole {
                    case .residence:   return 0
                    case .homeCountry: return 1
                    case .none:        return 2
                    }
                }
                return rank(lhs) < rank(rhs)
            }
    }

    /// Reorderable watchlist zones (everything that is not an anchor), in sortOrder.
    private var watchlistZones: [SavedZone] {
        savedZones.filter { !$0.isNowAnchor }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                MeridianColors.background.ignoresSafeArea()

                List {
                    header
                    visualizationSection
                    searchCard

                    if savedZones.isEmpty {
                        emptyState
                    } else {
                        pinnedLocationsHeader
                        anchorRows
                        watchlistRows
                    }

                    // Clearance so the last rows scroll above the pinned scrubber dial + tab bar.
                    Color.clear
                        .frame(height: 180)
                        .plainRow()
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)

                scrubberOverlay
            }
            .navigationTitle("World")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            scrubOffsetSeconds = timeEngine.scrubInstant.map { $0.timeIntervalSince(timeEngine.now()) } ?? 0
        }
        .onReceive(ticker) { now in
            if timeEngine.scrubInstant == nil { liveTick = now }
        }
        .onChange(of: scrubOffsetSeconds) { _, newValue in
            // Mirror the scrubber into the shared engine: 0 → live, otherwise an absolute instant.
            if abs(newValue) < 1 {
                viewModel?.selectScrubTime(nil)
            } else {
                viewModel?.selectScrubTime(timeEngine.now().addingTimeInterval(newValue))
            }
        }
        .sheet(isPresented: $showCityPicker) {
            if let viewModel {
                WorldCityPickerSheet(
                    viewModel: viewModel,
                    instant: displayInstant,
                    use24Hour: use24Hour
                )
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("World Clock")
                .font(.displayMedium)
                .foregroundStyle(MeridianColors.onBackground)
            Text("Search locations and scrub time across zones.")
                .font(.bodyMedium)
                .foregroundStyle(MeridianColors.onBackground.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .plainRow()
    }

    private var visualizationSection: some View {
        WorldVisualization(
            instant: displayInstant,
            zoneIds: savedZones.map(\.id),
            mapStyle: settings.mapStyle
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .plainRow()
    }

    private var searchCard: some View {
        GlassCard(cornerRadius: 20, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(MeridianColors.primary)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Worldwide Cities")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(MeridianColors.onSurface)
                        Text("Search any city, airport, or time zone to pin its time.")
                            .font(.system(size: 12))
                            .foregroundStyle(MeridianColors.onSurface.opacity(0.5))
                    }
                    Spacer(minLength: 0)
                }

                Button {
                    showCityPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("Search worldwide cities")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MeridianColors.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(MeridianColors.primary.opacity(0.5), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .light), trigger: showCityPicker)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .plainRow()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(MeridianColors.primary.opacity(0.5))
            Text("No pinned locations yet")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MeridianColors.onSurface)
            Text("Search and add cities above to track their times across the globe.")
                .font(.bodyMedium)
                .foregroundStyle(MeridianColors.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(48)
        .plainRow()
    }

    private var pinnedLocationsHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .foregroundStyle(MeridianColors.primary)
                .frame(width: 20, height: 20)
            Text("Pinned Locations")
                .font(.titleLarge)
                .foregroundStyle(MeridianColors.onBackground)
            Rectangle()
                .fill(MeridianColors.onBackground.opacity(0.12))
                .frame(height: 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .plainRow()
    }

    @ViewBuilder
    private var anchorRows: some View {
        ForEach(anchorZones) { zone in
            zoneRow(zone)
                .plainRow()
        }
    }

    @ViewBuilder
    private var watchlistRows: some View {
        ForEach(watchlistZones) { zone in
            zoneRow(zone)
                .plainRow()
        }
        .onMove(perform: moveWatchlist)
    }

    // MARK: - Row builder

    private func zoneRow(_ zone: SavedZone) -> some View {
        ZoneComparisonRow(
            zone: zone,
            instant: displayInstant,
            use24Hour: use24Hour,
            workStartHour: settings.defaultWorkStartHour,
            workEndHour: settings.defaultWorkEndHour,
            favoriteContacts: favoriteContacts(for: zone),
            onSetHome: { viewModel?.setHomeZone(id: zone.id, displayName: zone.displayName) },
            onToggleFavorite: { viewModel?.toggleZoneFavorite(id: zone.id) },
            onDelete: { viewModel?.removeZone(id: zone.id) }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Reorder

    /// Persist a watchlist reorder. `reorderZones(ids:)` packs anchors at the front, so we
    /// pass only the watchlist order (Android filters to still-existing ids; here the array
    /// is always current).
    private func moveWatchlist(from offsets: IndexSet, to destination: Int) {
        var ids = watchlistZones.map(\.id)
        ids.move(fromOffsets: offsets, toOffset: destination)
        viewModel?.reorderZones(ids: ids)
    }

    // MARK: - Contacts

    /// Favorite contacts pinned to this zone (matching Android's favorite-contact chips).
    private func favoriteContacts(for zone: SavedZone) -> [Person] {
        (viewModel?.people ?? []).filter { $0.isFavorite && $0.tzId == zone.id }
    }

    // MARK: - Scrubber overlay

    private var scrubberOverlay: some View {
        VStack {
            Spacer()
                .allowsHitTesting(false)   // don't block list scrolling above the dial
            VStack(spacing: 6) {
                TimelineScrubber(offsetSeconds: $scrubOffsetSeconds)
                if abs(scrubOffsetSeconds) >= 1 {
                    Button("Reset to Live") {
                        withAnimation(Motion.snappy()) { scrubOffsetSeconds = 0 }
                    }
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(.clear)
        }
    }
}

// MARK: - List row chrome helper

private extension View {
    /// Strips the default List row chrome (separators, insets, background) so rows lay out
    /// edge-to-edge like the Android LazyColumn while still supporting `.onMove`.
    func plainRow() -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

// MARK: - ZoneComparisonRow

/// A single expandable zone card: name + day/night icon + favorite/home markers, the local
/// time + date, a working-hours / off-hours sub-label, the UTC offset, favorite-contact
/// chips, and a sun-times line. Tapping toggles an expanded panel (work window, zone id,
/// contacts). A context menu surfaces favorite / set-home / remove (Android's options menu).
struct ZoneComparisonRow: View {

    let zone: SavedZone
    let instant: Date
    let use24Hour: Bool
    var workStartHour: Int = 9
    var workEndHour: Int = 17
    var favoriteContacts: [Person] = []
    var onSetHome: () -> Void = {}
    var onToggleFavorite: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var expanded = false

    // MARK: Computed

    private var timeZone: TimeZone { TimeFormats.safeTimeZone(id: zone.id) }

    private var localHour: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.component(.hour, from: instant)
    }

    private var isWorkingHours: Bool {
        localHour >= workStartHour && localHour < workEndHour
    }

    private var isDaylight: Bool {
        let c = ZoneGeo.coordinate(for: zone.id, at: instant)
        return SolarMath.isDaylight(latitude: c.latitude, longitude: c.longitude, date: instant)
    }

    private var localTime: String {
        TimeFormats.hourMinute(date: instant, timeZone: timeZone, use24Hour: use24Hour)
    }

    private var localDate: String {
        TimeFormats.shortDate(date: instant, timeZoneId: zone.id)
    }

    private var utcOffset: String {
        TimeFormats.utcOffset(for: zone.id, at: instant)
    }

    private var containerTint: Color {
        isWorkingHours ? MeridianColors.primaryContainer.opacity(0.18)
                       : MeridianColors.surface.opacity(0.25)
    }

    private var glowColor: Color {
        (isDaylight ? MeridianColors.daylightGlow : MeridianColors.nightGlow).opacity(0.22)
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
            if expanded { expandedPanel }
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Motion.smooth()) { expanded.toggle() }
        }
        .sensoryFeedback(.selection, trigger: expanded)
        .contextMenu { contextMenuItems }
        .animation(Motion.snappy(), value: isWorkingHours)
        .animation(Motion.snappy(), value: isDaylight)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.6))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(containerTint)
            // Day/night corner glow (Android drawBehind radial gradient).
            RadialGradient(
                colors: [glowColor, .clear],
                center: UnitPoint(x: 0.85, y: 0.15),
                startRadius: 0,
                endRadius: 160
            )
        }
    }

    // MARK: Main row

    private var mainRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(zone.displayName)
                        .font(.titleMedium)
                        .foregroundStyle(MeridianColors.onSurface)
                        .lineLimit(1)
                    if zone.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(MeridianColors.daylightGlow)
                    }
                    Image(systemName: isDaylight ? "sun.max.fill" : "moon.stars.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(isDaylight ? MeridianColors.daylightAccent
                                                    : MeridianColors.nightAccent)
                    if zone.isHome {
                        Image(systemName: "house.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(MeridianColors.primary)
                    }
                }

                Text(isWorkingHours ? "Working hours" : "Off-hours")
                    .font(.system(size: 12))
                    .foregroundStyle(isWorkingHours ? MeridianColors.primary.opacity(0.9)
                                                    : MeridianColors.onSurface.opacity(0.55))

                Text(utcOffset)
                    .font(.system(size: 10))
                    .foregroundStyle(MeridianColors.onSurfaceVariant.opacity(0.7))

                if !favoriteContacts.isEmpty {
                    contactChips
                        .padding(.top, 4)
                }

                SunTimesLine(
                    zoneId: zone.id,
                    instant: instant,
                    use24Hour: use24Hour,
                    textColor: MeridianColors.onSurface
                )
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(localTime)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(MeridianColors.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MeridianColors.onSurfaceVariant.opacity(0.5))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                Text(localDate)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.6))
            }
        }
    }

    private var contactChips: some View {
        HStack(spacing: 4) {
            ForEach(favoriteContacts) { person in
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(MeridianColors.daylightGlow)
                    Text(person.name)
                        .font(.system(size: 10))
                        .foregroundStyle(MeridianColors.onSurface.opacity(0.85))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(MeridianColors.primary.opacity(0.12)))
            }
        }
    }

    // MARK: Expanded panel

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(MeridianColors.onSurface.opacity(0.12))
                .frame(height: 1)
                .padding(.top, 10)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Work window")
                        .font(.system(size: 11))
                        .foregroundStyle(MeridianColors.onSurface.opacity(0.5))
                    Text(String(format: "%02d:00 – %02d:00", workStartHour, workEndHour))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MeridianColors.onSurface)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Zone ID")
                        .font(.system(size: 11))
                        .foregroundStyle(MeridianColors.onSurface.opacity(0.5))
                    Text(zone.id)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MeridianColors.onSurface.opacity(0.6))
                }
            }

            Rectangle()
                .fill(MeridianColors.onSurface.opacity(0.10))
                .frame(height: 1)

            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.7))
                Text("Contacts")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.7))
            }

            if favoriteContacts.isEmpty {
                Text("No starred contacts — star someone to include them in Plan")
                    .font(.system(size: 12))
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.4))
            } else {
                ForEach(favoriteContacts) { person in
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(MeridianColors.onSurface.opacity(0.4))
                        Text(person.name)
                            .font(.system(size: 12))
                            .foregroundStyle(MeridianColors.onSurface)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            onToggleFavorite()
        } label: {
            Label(zone.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: zone.isFavorite ? "star.slash" : "star")
        }
        if !zone.isHome {
            Button {
                onSetHome()
            } label: {
                Label("Set as My Home Zone", systemImage: "house")
            }
        }
        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Remove from Watchlist", systemImage: "trash")
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("WorldClockScreen") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: SavedZone.self, Person.self, PlannedTask.self,
                                        configurations: config)
    let zones: [(String, String, ZoneAnchorRole?)] = [
        ("America/New_York", "New York", .residence),
        ("Europe/London", "London", nil),
        ("Asia/Tokyo", "Tokyo", nil),
        ("Australia/Sydney", "Sydney", nil),
    ]
    for (i, (id, name, role)) in zones.enumerated() {
        container.mainContext.insert(
            SavedZone(id: id, displayName: name, isHome: role == .residence,
                      anchorRole: role, sortOrder: i)
        )
    }
    let vm = MainViewModel(modelContext: container.mainContext)

    return WorldClockScreen()
        .modelContainer(container)
        .environment(\.mainViewModel, vm)
        .environment(TimeEngine.shared)
        .environment(SettingsRepository.shared)
        .preferredColorScheme(.dark)
}
#endif
