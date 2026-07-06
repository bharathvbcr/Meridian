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
    @Environment(\.worldCityPickerRequest) private var worldCityPickerRequest
    @Environment(\.tabBarInsetHeight) private var tabBarInsetHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    private var people: [Person] { viewModel?.people ?? [] }

    /// Starred contacts whose zone is NOT pinned, grouped one row per IANA zone
    /// (Android's "Contact locations" section; helper shared with the Now screen).
    private var orphanContactGroups: [ContactLocationGroup] {
        unassignedContactGroups(people: people, savedZones: savedZones)
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

                    if !orphanContactGroups.isEmpty {
                        contactLocationsHeader
                        contactLocationRows
                    }

                    // Clearance so the last rows scroll above the pinned scrubber dial + tab bar.
                    Color.clear
                        .frame(height: tabBarInsetHeight + 84)
                        .plainRow()
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
                .coordinateSpace(name: "worldScroll")

                scrubberOverlay
            }
            .navigationTitle("World")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            scrubOffsetSeconds = timeEngine.scrubInstant.map { $0.timeIntervalSince(timeEngine.now()) } ?? 0
            // Pick up a fresher cached fix so the home pin tracks the user across sessions.
            viewModel?.refreshDeviceCoordinate()
            consumeWorldCityPickerRequestIfNeeded()
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
        .onChange(of: worldCityPickerRequest.wrappedValue) { _, pending in
            if pending { consumeWorldCityPickerRequestIfNeeded() }
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
        VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue) {
            MeridianWordmark()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, MeridianSpacing.sm.rawValue)
                .accessibilityHidden(true)
            Text("World Clock")
                .font(.displayMedium)
                .foregroundStyle(MeridianColors.onBackground)
                .accessibilityAddTraits(.isHeader)
            Text("Search locations and scrub time across zones.")
                .font(.bodyMedium)
                .foregroundStyle(MeridianColors.onBackground.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MeridianSpacing.lg.rawValue)
        .padding(.top, MeridianSpacing.xs.rawValue)
        .reportScrollOffset(in: "worldScroll")
        .plainRow()
    }

    private var visualizationSection: some View {
        WorldVisualization(
            instant: displayInstant,
            zoneIds: savedZones.map(\.id),
            mapStyle: settings.mapStyle,
            homeZoneId: savedZones.first(where: \.isHome)?.id,
            homeLocation: viewModel?.homeLocation
        )
        .padding(.horizontal, MeridianSpacing.lg.rawValue)
        .padding(.vertical, MeridianSpacing.sm.rawValue)
        .plainRow()
    }

    private var searchCard: some View {
        // The screen header already explains "Search locations and scrub time across zones,"
        // and the picker sheet repeats it a third time — so the card carries just the action.
        GlassCard(cornerRadius: MeridianRadius.medium.rawValue, padding: MeridianSpacing.lg.rawValue) {
            Button {
                showCityPicker = true
            } label: {
                HStack(spacing: MeridianSpacing.sm.rawValue) {
                    Image(systemName: "globe")
                    Text("Search worldwide cities")
                }
                .font(.titleMedium)
                .foregroundStyle(MeridianColors.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, MeridianSpacing.md.rawValue)
                .background(
                    RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                        .strokeBorder(MeridianColors.primary.opacity(0.5), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search worldwide cities")
            .accessibilityHint("Opens a picker to add a city, airport, or time zone")
            .accessibilityAddTraits(.isButton)
            .sensoryFeedback(.impact(weight: .light), trigger: showCityPicker)
        }
        .padding(.horizontal, MeridianSpacing.lg.rawValue)
        .padding(.vertical, MeridianSpacing.sm.rawValue)
        .plainRow()
    }

    private var emptyState: some View {
        EmptyStateCard(
            icon: "globe",
            title: "No pinned locations yet",
            message: "Search and add cities to track their times across the globe.",
            actionLabel: "Search cities",
            action: { showCityPicker = true }
        )
        .padding(.horizontal, MeridianSpacing.lg.rawValue)
        .padding(.vertical, MeridianSpacing.sm.rawValue)
        .plainRow()
    }

    private var pinnedLocationsHeader: some View {
        HStack(spacing: MeridianSpacing.sm.rawValue) {
            Image(systemName: "globe")
                .foregroundStyle(MeridianColors.primary)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text("Pinned Locations")
                .font(.titleLarge)
                .foregroundStyle(MeridianColors.onBackground)
                .accessibilityAddTraits(.isHeader)
            Rectangle()
                .fill(MeridianColors.onBackground.opacity(0.12))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, MeridianSpacing.xxl.rawValue)
        .padding(.vertical, MeridianSpacing.md.rawValue)
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

    private var contactLocationsHeader: some View {
        HStack(spacing: MeridianSpacing.sm.rawValue) {
            Image(systemName: "person.2")
                .foregroundStyle(MeridianColors.primary)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text("Contact locations")
                .font(.titleLarge)
                .foregroundStyle(MeridianColors.onBackground)
                .accessibilityAddTraits(.isHeader)
            Rectangle()
                .fill(MeridianColors.onBackground.opacity(0.12))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, MeridianSpacing.xxl.rawValue)
        .padding(.vertical, MeridianSpacing.md.rawValue)
        .plainRow()
    }

    /// One read-mostly row per orphan-contact zone. `contactOnlyLocation` hides the
    /// favorite / set-home / remove actions — the zone isn't pinned, only its people are.
    @ViewBuilder
    private var contactLocationRows: some View {
        ForEach(orphanContactGroups) { group in
            ZoneComparisonRow(
                displayName: group.displayName,
                zoneId: group.zoneId,
                instant: displayInstant,
                use24Hour: use24Hour,
                workStartHour: settings.defaultWorkStartHour,
                workEndHour: settings.defaultWorkEndHour,
                contacts: group.people,
                contactOnlyLocation: true,
                onAddContact: { name in
                    viewModel?.addPerson(
                        name: name,
                        zoneId: group.zoneId,
                        locationName: group.displayName,
                        isFavorite: true
                    )
                },
                onRemoveContact: { viewModel?.deletePerson($0) },
                onToggleContactFavorite: { viewModel?.togglePersonFavorite($0) }
            )
            .padding(.horizontal, MeridianSpacing.lg.rawValue)
            .padding(.vertical, 6)
            .plainRow()
        }
    }

    // MARK: - Row builder

    private func zoneRow(_ zone: SavedZone) -> some View {
        ZoneComparisonRow(
            displayName: zone.displayName,
            zoneId: zone.id,
            instant: displayInstant,
            use24Hour: use24Hour,
            isHome: zone.isHome,
            isFavoriteZone: zone.isFavorite,
            workStartHour: settings.defaultWorkStartHour,
            workEndHour: settings.defaultWorkEndHour,
            contacts: contactsForZone(zone, people: people, savedZones: savedZones),
            onAddContact: { name in
                viewModel?.addPerson(
                    name: name,
                    zoneId: zone.id,
                    locationName: zone.displayName,
                    isFavorite: true
                )
            },
            onRemoveContact: { viewModel?.deletePerson($0) },
            onToggleContactFavorite: { viewModel?.togglePersonFavorite($0) },
            onSetHome: { viewModel?.setHomeZone(id: zone.id, displayName: zone.displayName) },
            onToggleZoneFavorite: { viewModel?.toggleZoneFavorite(id: zone.id) },
            onDelete: { viewModel?.removeZone(id: zone.id) }
        )
        .padding(.horizontal, MeridianSpacing.lg.rawValue)
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

    // MARK: - Scrubber overlay

    private var scrubberOverlay: some View {
        VStack {
            Spacer()
                .allowsHitTesting(false)   // don't block list scrolling above the dial
            VStack(spacing: 6) {
                TimelineScrubber(offsetSeconds: $scrubOffsetSeconds)
                if abs(scrubOffsetSeconds) >= 1 {
                    Button("Reset to Live") {
                        withAnimation(reduceMotion ? nil : Motion.snappy()) { scrubOffsetSeconds = 0 }
                    }
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.primary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityHint("Return the timeline to the current time")
                }
            }
            .padding(.horizontal, MeridianSpacing.lg.rawValue)
            // Lift the dial clear of the floating glass tab bar that ContentView overlays on top
            // (otherwise the pinned scrubber renders underneath it and looks "missing").
            .padding(.bottom, tabBarInsetHeight)
            .background(.clear)
        }
    }

    /// Handles `meridian://addzone` and widget empty-state deep links.
    private func consumeWorldCityPickerRequestIfNeeded() {
        guard worldCityPickerRequest.wrappedValue else { return }
        showCityPicker = true
        worldCityPickerRequest.wrappedValue = false
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

// MARK: - ZoneCardButtonStyle

/// Pressed-state feedback for the expandable zone card: a subtle scale + dim while the finger
/// is down, springing back on release (`Motion.quick()`), gated on Reduce Motion. Gives the
/// large tap target a touch response before the expand panel animates.
private struct ZoneCardButtonStyle: ButtonStyle {
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : Motion.quick(), value: configuration.isPressed)
    }
}

// MARK: - ZoneComparisonRow

/// A single expandable zone card: name + day/night icon + favorite/home markers, the local
/// time + date, a working-hours / off-hours sub-label, the UTC offset, favorite-contact
/// chips, and a sun-times line. Tapping toggles an expanded panel (work window, zone id,
/// contacts with add / star / remove). A context menu surfaces favorite / add-contact /
/// set-home / remove (Android's options menu). Takes plain values instead of a `SavedZone`
/// so the "Contact locations" section can render orphan-contact groups with the same row.
struct ZoneComparisonRow: View {

    let displayName: String
    let zoneId: String
    let instant: Date
    let use24Hour: Bool
    var isHome: Bool = false
    var isFavoriteZone: Bool = false
    var workStartHour: Int = 9
    var workEndHour: Int = 17
    /// Contacts that appear on this row; chips + the expanded list show the starred ones.
    var contacts: [Person] = []
    /// Zone isn't pinned (orphan-contact group): hide favorite / set-home / remove actions.
    var contactOnlyLocation: Bool = false
    var onAddContact: (String) -> Void = { _ in }
    var onRemoveContact: (Person) -> Void = { _ in }
    var onToggleContactFavorite: (Person) -> Void = { _ in }
    var onSetHome: () -> Void = {}
    var onToggleZoneFavorite: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var expanded = false
    @State private var showAddContact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Computed

    private var timeZone: TimeZone { TimeFormats.safeTimeZone(id: zoneId) }

    /// Android shows only starred contacts on the row (chips and expanded list alike).
    private var favoriteContacts: [Person] { contacts.filter(\.isFavorite) }

    private var localHour: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.component(.hour, from: instant)
    }

    private var isWorkingHours: Bool {
        localHour >= workStartHour && localHour < workEndHour
    }

    private var isDaylight: Bool {
        let c = ZoneGeo.coordinate(for: zoneId, at: instant)
        return SolarMath.isDaylight(latitude: c.latitude, longitude: c.longitude, date: instant)
    }

    private var localTime: String {
        TimeFormats.hourMinute(date: instant, timeZone: timeZone, use24Hour: use24Hour)
    }

    private var localDate: String {
        TimeFormats.shortDate(date: instant, timeZoneId: zoneId)
    }

    private var utcOffset: String {
        TimeFormats.utcOffset(for: zoneId, at: instant)
    }

    /// Folds the row's scattered glyphs (name, time, working-hours, day/night, home, favorite)
    /// into one spoken summary so VoiceOver reads the card as a single meaningful element
    /// instead of stopping on each decorative marker.
    private var accessibilitySummary: String {
        var parts: [String] = [displayName, localTime]
        parts.append(isWorkingHours ? "Working hours" : "Off-hours")
        parts.append(isDaylight ? "Daytime" : "Nighttime")
        if isHome { parts.append("Home zone") }
        if isFavoriteZone { parts.append("Favorite") }
        if !favoriteContacts.isEmpty {
            parts.append("\(favoriteContacts.count) starred \(favoriteContacts.count == 1 ? "contact" : "contacts")")
        }
        return parts.joined(separator: ", ")
    }

    /// Expand/collapse spring, gated on Reduce Motion (no user-facing tween otherwise).
    private var expandAnimation: Animation? {
        reduceMotion ? nil : Motion.smooth()
    }

    private var containerTint: Color {
        isWorkingHours ? MeridianColors.primaryContainer.opacity(0.18)
                       : MeridianColors.surface.opacity(0.25)
    }

    private var glowColor: Color {
        (isDaylight ? MeridianColors.daylightGlow : MeridianColors.nightGlow).opacity(0.22)
    }

    /// Card corner, shared by fill, clip, and stroke so they never drift out of sync.
    private var cardCornerRadius: CGFloat { MeridianRadius.medium.rawValue }

    // MARK: Body

    var body: some View {
        // A Button (not a bare .onTapGesture) so the card gets a real pressed affordance via
        // `ZoneCardButtonStyle`, and still coexists cleanly with List scrolling + contextMenu.
        Button {
            withAnimation(expandAnimation) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                mainRow
                if expanded { expandedPanel }
            }
            .padding(MeridianSpacing.lg.rawValue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        }
        .buttonStyle(ZoneCardButtonStyle(reduceMotion: reduceMotion))
        .sensoryFeedback(.selection, trigger: expanded)
        .contextMenu { contextMenuItems }
        .animation(reduceMotion ? nil : Motion.snappy(), value: isWorkingHours)
        .animation(reduceMotion ? nil : Motion.snappy(), value: isDaylight)
        // Keep the expanded panel's own buttons individually reachable; the summary lives on
        // `mainRow` (the tappable header), which is combined into one element there.
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showAddContact) {
            AddContactToZoneSheet(zoneName: displayName) { name in
                onAddContact(name)
            }
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.6))
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
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
        HStack(alignment: .top, spacing: MeridianSpacing.md.rawValue) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MeridianSpacing.xs.rawValue + 2) {
                    Text(displayName)
                        .font(.titleMedium)
                        .foregroundStyle(MeridianColors.onSurface)
                        .lineLimit(1)
                    if isFavoriteZone {
                        Image(systemName: "star.fill")
                            .font(.labelMedium)
                            .foregroundStyle(MeridianColors.daylightGlow)
                            .accessibilityHidden(true)
                    }
                    Image(systemName: isDaylight ? "sun.max.fill" : "moon.stars.fill")
                        .font(.labelMedium)
                        .foregroundStyle(isDaylight ? MeridianColors.daylightAccent
                                                    : MeridianColors.nightAccent)
                        .accessibilityHidden(true)
                    if isHome {
                        Image(systemName: "house.fill")
                            .font(.labelMedium)
                            .foregroundStyle(MeridianColors.primary)
                            .accessibilityHidden(true)
                    }
                }

                Text(isWorkingHours ? "Working hours" : "Off-hours")
                    .font(.labelMedium)
                    .foregroundStyle(isWorkingHours ? MeridianColors.primary.opacity(0.9)
                                                    : MeridianColors.onSurface.opacity(0.55))

                Text(utcOffset)
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.onSurfaceVariant.opacity(0.7))

                if !favoriteContacts.isEmpty {
                    contactChips
                        .padding(.top, MeridianSpacing.xs.rawValue)
                }

                SunTimesLine(
                    zoneId: zoneId,
                    instant: instant,
                    use24Hour: use24Hour,
                    textColor: MeridianColors.onSurface
                )
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: MeridianSpacing.xs.rawValue) {
                    Text(localTime)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(MeridianColors.primary)
                    Image(systemName: "chevron.down")
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant.opacity(0.5))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                Text(localDate)
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.6))
            }
        }
        // Fold every glyph + label above into one spoken element with a synthesized summary.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(expanded ? "Double tap to collapse" : "Double tap to expand")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            withAnimation(expandAnimation) { expanded.toggle() }
        }
    }

    private var contactChips: some View {
        HStack(spacing: MeridianSpacing.xs.rawValue) {
            ForEach(favoriteContacts) { person in
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.labelMedium)
                        .imageScale(.small)
                        .foregroundStyle(MeridianColors.daylightGlow)
                        .accessibilityHidden(true)
                    Text(person.name)
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.onSurface.opacity(0.85))
                }
                .padding(.horizontal, MeridianSpacing.sm.rawValue)
                .padding(.vertical, 2)
                .background(Capsule().fill(MeridianColors.primary.opacity(0.12)))
            }
        }
    }

    // MARK: Expanded panel

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: MeridianSpacing.sm.rawValue) {
            Rectangle()
                .fill(MeridianColors.onSurface.opacity(0.12))
                .frame(height: 1)
                .padding(.top, MeridianSpacing.sm.rawValue)
                .accessibilityHidden(true)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Work window")
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.onSurface.opacity(0.5))
                    Text(String(format: "%02d:00 – %02d:00", workStartHour, workEndHour))
                        .font(.bodyMedium.weight(.bold))
                        .foregroundStyle(MeridianColors.onSurface)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Zone ID")
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.onSurface.opacity(0.5))
                    Text(zoneId)
                        .font(.bodyMedium.weight(.bold))
                        .foregroundStyle(MeridianColors.onSurface.opacity(0.6))
                }
            }

            Rectangle()
                .fill(MeridianColors.onSurface.opacity(0.10))
                .frame(height: 1)
                .accessibilityHidden(true)

            HStack(spacing: MeridianSpacing.xs.rawValue) {
                Image(systemName: "person.2.fill")
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.7))
                    .accessibilityHidden(true)
                Text("Contacts")
                    .font(.bodyMedium.weight(.bold))
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.7))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    showAddContact = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "person.badge.plus")
                        Text("Add")
                    }
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.primary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add contact to \(displayName)")
                .accessibilityAddTraits(.isButton)
            }

            if favoriteContacts.isEmpty {
                Text("No starred contacts — tap Add or star someone to keep them at a glance.")
                    .font(.bodyMedium)
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.4))
            } else {
                ForEach(favoriteContacts) { person in
                    contactRow(person)
                }
            }
        }
    }

    /// One expanded-panel contact line: name + star toggle + remove (Android :1131-1172).
    private func contactRow(_ person: Person) -> some View {
        HStack(spacing: MeridianSpacing.xs.rawValue + 2) {
            Image(systemName: "person.fill")
                .font(.labelMedium)
                .foregroundStyle(MeridianColors.onSurface.opacity(0.4))
                .accessibilityHidden(true)
            Text(person.name)
                .font(.bodyMedium)
                .foregroundStyle(MeridianColors.onSurface)
            Spacer()
            Button {
                onToggleContactFavorite(person)
            } label: {
                Image(systemName: person.isFavorite ? "star.fill" : "star")
                    .font(.bodyMedium)
                    .foregroundStyle(person.isFavorite ? MeridianColors.daylightAccent
                                                       : MeridianColors.onSurface.opacity(0.4))
                    // Keep the glyph small but give it a full 44pt hit area (iOS minimum).
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(person.isFavorite ? "Unstar \(person.name)" : "Star \(person.name)")
            .accessibilityAddTraits(.isButton)
            Button {
                onRemoveContact(person)
            } label: {
                Image(systemName: "trash")
                    .font(.bodyMedium)
                    // Route the destructive tint through the palette's error token, not Color.red.
                    .foregroundStyle(MeridianColors.error)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(person.name)")
            .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: Context menu

    /// Contact-only rows keep just "Add contact" — the zone itself isn't pinned, so
    /// favorite / set-home / remove would act on nothing (Android :1210-1257).
    @ViewBuilder
    private var contextMenuItems: some View {
        if !contactOnlyLocation {
            Button {
                onToggleZoneFavorite()
            } label: {
                Label(isFavoriteZone ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: isFavoriteZone ? "star.slash" : "star")
            }
        }
        Button {
            showAddContact = true
        } label: {
            Label("Add contact to \(displayName)", systemImage: "person.badge.plus")
        }
        if !contactOnlyLocation, !isHome {
            Button {
                onSetHome()
            } label: {
                Label("Set as My Home Zone", systemImage: "house")
            }
        }
        if !contactOnlyLocation {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove from Watchlist", systemImage: "trash")
            }
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
