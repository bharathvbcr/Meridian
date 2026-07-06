// NowScreen.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// Home screen. Ported from `NowScreen.kt`:
//   • Greeting + local-zone header (abbreviation · UTC offset · zone id)
//   • Time & Location card with an analog clock and anchor (residence / home-country) sections
//   • Solar & daylight widget for the residence (or local) zone
//   • Upcoming agenda — FIXED window: tasks from (now − 30 min), sorted, take 3
//   • Zone watchlist with a favorites quick-filter and reorder/menu actions
//   • Contact-location groups for starred contacts not pinned to a saved zone
//
// State is driven by `MainViewModel` (injected via `\.mainViewModel`) and `TimeEngine`
// (`displayDate` is the single source of truth for the rendered instant). A 1-second
// ticker advances the displayed time when not scrubbing.

import SwiftUI
import SwiftData

// MARK: - NowScreen

struct NowScreen: View {

    @Environment(\.mainViewModel) private var viewModelOrNil
    @Environment(TimeEngine.self) private var timeEngine
    @Environment(\.selectTab) private var selectTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 1s ticker; we read TimeEngine.displayDate so scrubbing stays authoritative.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var tick: Date = .init()

    @State private var showFavoritesOnly = true
    @State private var addingAnchorRole: ZoneAnchorRole?
    @State private var showAddZoneSheet = false
    @State private var resolvingLocation = false

    // Long-press drag-to-reorder state (Android NowScreen: draggingKey/draggingOffset).
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var draftOrder: [String]? = nil
    @State private var draggingId: String? = nil
    @State private var dragPointerY: CGFloat = 0
    @State private var didDrag = false
    @State private var dragStartTrigger = 0
    /// Hold-still-and-release target: opens the zone's options dialog (Android: menuZoneId).
    @State private var menuZone: SavedZone? = nil
    @State private var addContactZone: SavedZone? = nil

    // The displayed instant — scrub-aware.
    private var now: Date { timeEngine.displayDate }

    /// The one section-divider tone used across this screen — mirrors the hairline
    /// `SectionHeader` draws (white @ 0.10, 1pt) so manual rules never drift from it.
    private let sectionDividerColor = Color.white.opacity(0.10)

    var body: some View {
        ZStack {
            MeridianColors.background.ignoresSafeArea()

            if let viewModel = viewModelOrNil {
                content(viewModel)
            } else {
                // Should never happen in the running app; keeps previews/safety sane.
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Not Ready",
                    message: "The app is still starting up."
                )
            }
        }
        .onReceive(ticker) { date in
            // Reading drives @State invalidation so time-dependent views recompute each second.
            tick = date
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ viewModel: MainViewModel) -> some View {
        let use24Hour = TimeFormats.uses24Hour(cycle: viewModel.settings.hourCycle)
        let localZoneId = TimeZone.current.identifier
        let residence = viewModel.savedZones.residenceZone()
        let homeCountry = viewModel.homeCountryZone
        let solarZoneId = residence?.id ?? localZoneId

        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: MeridianSpacing.lg.rawValue) {

                Color.clear
                    .frame(height: 0)
                    .reportScrollOffset(in: "nowScroll")

                MeridianWordmark()
                    .padding(.top, 4)

                header(localZoneId: localZoneId)

                TimeAndLocationCard(
                    date: now,
                    use24Hour: use24Hour,
                    localZoneId: localZoneId,
                    residence: residence,
                    homeCountry: viewModel.settings.homeCountryEnabled ? homeCountry : nil,
                    resolvingLocation: resolvingLocation,
                    onPickResidence: { addingAnchorRole = .residence },
                    onPickHomeCountry: { addingAnchorRole = .homeCountry },
                    onUseLocation: { resolveHome(viewModel) }
                )

                SolarDaylightWidget(zoneId: solarZoneId, date: now, use24Hour: use24Hour)

                agendaSection(viewModel)

                watchlistSection(viewModel, use24Hour: use24Hour)

                contactLocationsSection(viewModel, use24Hour: use24Hour)

                Color.clear.frame(height: 120) // clear floating nav bar
            }
            .padding(.horizontal, MeridianSpacing.lg.rawValue)
            .padding(.top, MeridianSpacing.lg.rawValue)
        }
        .coordinateSpace(name: "nowScroll")
        // Anchor picker (residence / home country). The residence picker also offers
        // "Use current location" (Android: HomeCityPickerSheet's location row).
        .sheet(item: $addingAnchorRole) { role in
            AnchorZonePickerSheet(
                title: role == .residence ? "Choose your home city" : "Choose a city",
                onUseLocation: role == .residence ? { resolveHome(viewModel) } : nil,
                search: { await viewModel.searchTimeZones($0) },
                onSelect: { zoneId, name in
                    viewModel.setAnchorZone(id: zoneId, displayName: name, role: role)
                }
            )
        }
        // Add a plain watchlist zone — real add wired via searchTimeZones (replaces the
        // old dead "Add Zone" placeholder).
        .sheet(isPresented: $showAddZoneSheet) {
            AnchorZonePickerSheet(
                title: "Add a zone",
                search: { await viewModel.searchTimeZones($0) },
                onSelect: { zoneId, name in
                    viewModel.addZone(id: zoneId, displayName: name)
                }
            )
        }
    }

    // MARK: - Header

    private func header(localZoneId: String) -> some View {
        let hour: Int = {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .current
            return cal.component(.hour, from: now)
        }()
        let greeting: String = {
            switch hour {
            case 5...11:  return "Good morning"
            case 12...16: return "Good afternoon"
            case 17...21: return "Good evening"
            default:      return "Good night"
            }
        }()
        let abbreviation = TimeZone.current.abbreviation(for: now) ?? ""
        let offset = TimeFormats.utcOffset(for: localZoneId, at: now)

        return VStack(alignment: .leading, spacing: 4) {
            // Crossfade at the morning/afternoon/evening boundaries (Android:
            // AnimatedContent with a 400 ms fade).
            Text(greeting)
                .font(.displayMedium)
                .foregroundStyle(MeridianColors.onBackground)
                .contentTransition(.opacity)
                // Spring-only motion (Meridian rule); reduce-motion skips the crossfade.
                .animation(reduceMotion ? nil : Motion.smooth(), value: greeting)

            Text("\(abbreviation) · \(offset) · \(localZoneId)")
                .font(.bodyMedium)
                .foregroundStyle(MeridianColors.onBackground.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, MeridianSpacing.sm.rawValue)
        // One VoiceOver unit: "Good morning, PST · UTC+0 · America/Los_Angeles".
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Agenda

    @ViewBuilder
    private func agendaSection(_ viewModel: MainViewModel) -> some View {
        // FIXED window: tasks from (now − 30 min), sorted ascending, first 3.
        let cutoff = now.addingTimeInterval(-30 * 60)
        let upcoming = viewModel.plannedTasks
            .filter { $0.timestamp > cutoff }
            .sorted { $0.timestamp < $1.timestamp }
            .prefix(3)

        VStack(alignment: .leading, spacing: MeridianSpacing.sm.rawValue) {
            SectionHeader(title: "Upcoming Agenda")

            if upcoming.isEmpty {
                EmptyStateCard(
                    icon: "calendar.badge.checkmark",
                    title: "Your schedule is clear",
                    message: "Use the Plan tab or AI Assistant to schedule your next multi-zone meeting.",
                    actionLabel: "Open Plan",
                    action: { selectTab(.plan) }
                )
            } else {
                ForEach(Array(upcoming)) { task in
                    AgendaItemRow(task: task, now: now, use24Hour: TimeFormats.uses24Hour(cycle: viewModel.settings.hourCycle)) {
                        viewModel.deleteTask(id: task.id)
                    }
                }
            }
        }
    }

    // MARK: - Watchlist

    @ViewBuilder
    private func watchlistSection(_ viewModel: MainViewModel, use24Hour: Bool) -> some View {
        // Watchlist = saved zones that are NOT a now-anchor (residence/home-country/home).
        let watchlist = viewModel.savedZones.filter { !$0.isNowAnchor }
        let favorites = watchlist.filter(\.isFavorite)
        let hasFavorites = !favorites.isEmpty
        let favOnly = showFavoritesOnly && hasFavorites
        let displayed = applyDraftOrder(favOnly ? favorites : watchlist)

        VStack(alignment: .leading, spacing: MeridianSpacing.sm.rawValue) {
            HStack {
                SectionHeader(title: "Zone Watchlist", showDivider: false)
                Spacer()
                Button {
                    showAddZoneSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(MeridianColors.primary)
                        // Meet the 44pt HIG minimum tap target (icon stays 22pt).
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Add zone")
                .accessibilityHint("Search for a city and pin it to your watchlist")
            }

            if hasFavorites {
                HStack(spacing: MeridianSpacing.sm.rawValue) {
                    MeridianChip(label: "All", isSelected: !favOnly) { showFavoritesOnly = false }
                    MeridianChip(label: "Favorites", isSelected: favOnly) { showFavoritesOnly = true }
                }
            }

            // Shared section divider (same 0.10 white / 1pt SectionHeader draws), kept as
            // a private token so it never drifts from the rest of the screen.
            Rectangle()
                .fill(sectionDividerColor)
                .frame(height: 1)

            if watchlist.isEmpty {
                EmptyStateCard(
                    icon: "globe",
                    title: "Watchlist is empty",
                    message: "Tap + to search and pin cities to monitor them here.",
                    actionLabel: "Add a city",
                    action: { showAddZoneSheet = true }
                )
            } else if displayed.isEmpty {
                EmptyStateCard(
                    icon: "star",
                    title: "No favorites yet",
                    message: "Star a zone to see it here, or browse all zones.",
                    actionLabel: "Show all",
                    action: { showFavoritesOnly = false }
                )
            } else {
                ForEach(Array(displayed.enumerated()), id: \.element.id) { index, zone in
                    watchlistRow(
                        zone: zone,
                        index: index,
                        count: displayed.count,
                        viewModel: viewModel,
                        use24Hour: use24Hour
                    )
                }
            }
        }
        .coordinateSpace(name: "watchlist")
        .onPreferenceChange(WatchlistRowFramesKey.self) { rowFrames = $0 }
        .sensoryFeedback(.impact(weight: .medium), trigger: dragStartTrigger)
        // Hold-still-and-release opens the zone's options (Android: the drag detector
        // opens the card's dropdown when the press never moved).
        .confirmationDialog(
            menuZone?.displayName ?? "",
            isPresented: Binding(get: { menuZone != nil }, set: { if !$0 { menuZone = nil } }),
            titleVisibility: .visible
        ) {
            if let zone = menuZone {
                Button(zone.isFavorite ? "Unfavorite" : "Favorite") {
                    viewModel.toggleZoneFavorite(id: zone.id)
                }
                Button("Add contact to \(zone.displayName)") { addContactZone = zone }
                Button("Set as home") {
                    viewModel.setHomeZone(id: zone.id, displayName: zone.displayName)
                }
                Button("Move up") { viewModel.reorderZone(id: zone.id, direction: -1) }
                Button("Move down") { viewModel.reorderZone(id: zone.id, direction: 1) }
                Button("Remove", role: .destructive) { viewModel.removeZone(id: zone.id) }
            }
        }
        .sheet(item: $addContactZone) { zone in
            AddContactToZoneSheet(zoneName: zone.displayName) { name in
                viewModel.addPerson(
                    name: name,
                    zoneId: zone.id,
                    locationName: zone.displayName,
                    isFavorite: true
                )
            }
        }
    }

    /// A single watchlist row: the zone card plus its drag-lift, drag gesture, and the
    /// VoiceOver reorder actions. Extracted from `watchlistSection`'s `ForEach` so the
    /// modifier chain type-checks in reasonable time.
    @ViewBuilder
    private func watchlistRow(
        zone: SavedZone,
        index: Int,
        count: Int,
        viewModel: MainViewModel,
        use24Hour: Bool
    ) -> some View {
        WatchlistZoneCard(
            zone: zone,
            date: now,
            use24Hour: use24Hour,
            isFirst: index == 0,
            isLast: index == count - 1,
            workStartHour: viewModel.settings.defaultWorkStartHour,
            workEndHour: viewModel.settings.defaultWorkEndHour,
            contacts: contactsForZone(zone, people: viewModel.people, savedZones: viewModel.savedZones),
            onAddContact: { name in
                viewModel.addPerson(
                    name: name,
                    zoneId: zone.id,
                    locationName: zone.displayName,
                    isFavorite: true
                )
            },
            onRemoveContact: { viewModel.deletePerson(id: $0) },
            onToggleContactFavorite: { viewModel.togglePersonFavorite(id: $0) },
            onToggleZoneFavorite: { viewModel.toggleZoneFavorite(id: zone.id) },
            onMoveUp: { viewModel.reorderZone(id: zone.id, direction: -1) },
            onMoveDown: { viewModel.reorderZone(id: zone.id, direction: 1) },
            onSetHome: { viewModel.setHomeZone(id: zone.id, displayName: zone.displayName) },
            onDelete: { viewModel.removeZone(id: zone.id) }
        )
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: WatchlistRowFramesKey.self,
                    value: [zone.id: geo.frame(in: .named("watchlist"))]
                )
            }
        }
        // Dragged-card lift (Android: scale 1.04, alpha 0.93, elevated, zIndex 1).
        .offset(y: dragOffset(for: zone.id))
        .scaleEffect(draggingId == zone.id ? 1.04 : 1)
        .opacity(draggingId == zone.id ? 0.93 : 1)
        .shadow(
            color: .black.opacity(draggingId == zone.id ? 0.45 : 0),
            radius: 14, y: 8
        )
        .zIndex(draggingId == zone.id ? 1 : 0)
        .gesture(reorderGesture(for: zone, viewModel: viewModel))
        // VoiceOver alternative to the long-press drag: the drag/menu gestures
        // are unreachable with VoiceOver on, so expose the same reorder actions
        // (and label the row's zone + wall-clock time) here.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(watchlistRowAccessibilityLabel(zone, use24Hour: use24Hour))
        .accessibilityHint("Actions available for reordering and options")
        .accessibilityAction(named: Text("Move up")) {
            viewModel.reorderZone(id: zone.id, direction: -1)
        }
        .accessibilityAction(named: Text("Move down")) {
            viewModel.reorderZone(id: zone.id, direction: 1)
        }
        .accessibilityAction(named: Text(zone.isFavorite ? "Unfavorite" : "Favorite")) {
            viewModel.toggleZoneFavorite(id: zone.id)
        }
        .accessibilityAction(named: Text("Remove")) {
            viewModel.removeZone(id: zone.id)
        }
    }

    // MARK: - Drag-to-reorder (Android NowScreen drag detector)

    /// Renders the in-flight draft order while a drag is active.
    private func applyDraftOrder(_ zones: [SavedZone]) -> [SavedZone] {
        guard let draft = draftOrder else { return zones }
        return zones.sorted {
            (draft.firstIndex(of: $0.id) ?? .max) < (draft.firstIndex(of: $1.id) ?? .max)
        }
    }

    /// Keeps the dragged card glued to the finger: its laid-out frame already reflects
    /// any in-flight reorder, so the visual offset is simply pointer − current center.
    private func dragOffset(for id: String) -> CGFloat {
        guard draggingId == id, let frame = rowFrames[id] else { return 0 }
        return dragPointerY - frame.midY
    }

    private func reorderGesture(for zone: SavedZone, viewModel: MainViewModel) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("watchlist")))
            .onChanged { value in
                switch value {
                case .first(true):
                    // Long press recognised → lift the card (Android: LongPress haptic).
                    if draggingId == nil {
                        draggingId = zone.id
                        draftOrder = applyDraftOrder(currentWatchlistIds(viewModel)).map(\.id)
                        dragPointerY = rowFrames[zone.id]?.midY ?? 0
                        didDrag = false
                        dragStartTrigger &+= 1
                    }
                case .second(true, let drag?):
                    guard draggingId == zone.id else { return }
                    dragPointerY = drag.location.y
                    if abs(drag.translation.height) > 6 { didDrag = true }
                    // Live shuffle: move the dragged id to the row under the finger.
                    if var order = draftOrder,
                       let target = rowFrames.first(where: {
                           $0.key != zone.id && $0.value.minY <= dragPointerY && dragPointerY < $0.value.maxY
                       })?.key,
                       let from = order.firstIndex(of: zone.id),
                       let to = order.firstIndex(of: target),
                       from != to {
                        order.remove(at: from)
                        order.insert(zone.id, at: to)
                        // Spring shuffle; reduce-motion applies the reorder instantly.
                        if reduceMotion {
                            draftOrder = order
                        } else {
                            withAnimation(Motion.smooth()) { draftOrder = order }
                        }
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                defer {
                    draggingId = nil
                    draftOrder = nil
                    didDrag = false
                }
                guard draggingId == zone.id else { return }
                if didDrag, let order = draftOrder {
                    // Commit: full watchlist order = dragged draft merged over the rest.
                    let all = currentWatchlistIds(viewModel).map(\.id)
                    let committed = order + all.filter { !order.contains($0) }
                    viewModel.reorderZones(ids: committed)
                } else {
                    // Hold-still-and-release → options menu (Android parity).
                    menuZone = zone
                }
            }
    }

    private func currentWatchlistIds(_ viewModel: MainViewModel) -> [SavedZone] {
        let watchlist = viewModel.savedZones.filter { !$0.isNowAnchor }
        let favorites = watchlist.filter(\.isFavorite)
        return (showFavoritesOnly && !favorites.isEmpty) ? favorites : watchlist
    }

    /// One combined VoiceOver phrase for a watchlist row (zone name, wall-clock time, and
    /// favorite state) — the drag/menu gestures are unreachable with VoiceOver, so the row
    /// itself must announce what it is.
    private func watchlistRowAccessibilityLabel(_ zone: SavedZone, use24Hour: Bool) -> String {
        let time = TimeFormats.hourMinute(date: now, timeZoneId: zone.id, use24Hour: use24Hour)
        let fav = zone.isFavorite ? ", favorite" : ""
        return "\(zone.displayName), \(time)\(fav)"
    }

    // MARK: - Contact locations (orphan starred contacts not pinned to a saved zone)

    @ViewBuilder
    private func contactLocationsSection(_ viewModel: MainViewModel, use24Hour: Bool) -> some View {
        let groups = unassignedContactGroups(people: viewModel.people, savedZones: viewModel.savedZones)
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: MeridianSpacing.sm.rawValue) {
                // Shared section chrome so weight + divider match every other section.
                SectionHeader(title: "Contact locations")

                ForEach(groups) { group in
                    ContactLocationRow(
                        group: group,
                        date: now,
                        use24Hour: use24Hour,
                        onAddContact: { name in
                            viewModel.addPerson(
                                name: name,
                                zoneId: group.zoneId,
                                locationName: group.displayName,
                                isFavorite: true
                            )
                        },
                        onRemoveContact: { viewModel.deletePerson(id: $0) },
                        onToggleContactFavorite: { viewModel.togglePersonFavorite(id: $0) }
                    )
                }
            }
        }
    }

    // MARK: - Location resolve

    private func resolveHome(_ viewModel: MainViewModel) {
        guard !resolvingLocation else { return }
        resolvingLocation = true
        Task {
            _ = await viewModel.resolveHomeFromLocation()
            resolvingLocation = false
        }
    }
}

// MARK: - ZoneAnchorRole Identifiable (for .sheet(item:))

extension ZoneAnchorRole: Identifiable {
    var id: String { rawValue }
}

// MARK: - WatchlistRowFramesKey

/// Frames of the watchlist rows in the "watchlist" coordinate space, keyed by zone
/// id — the layout data the drag-to-reorder gesture navigates by (Android reads
/// `LazyListState.layoutInfo.visibleItemsInfo`).
private struct WatchlistRowFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - TimeAndLocationCard

/// The hero card: large local time, analog clock, and anchor sections.
private struct TimeAndLocationCard: View {

    let date: Date
    let use24Hour: Bool
    let localZoneId: String
    let residence: SavedZone?
    let homeCountry: SavedZone?
    /// Spinner state for the residence "Use location" button (Android: isResolving).
    let resolvingLocation: Bool
    let onPickResidence: () -> Void
    let onPickHomeCountry: () -> Void
    /// Resolves the device location into the residence anchor; residence-only.
    let onUseLocation: () -> Void

    private var localTimeString: String {
        TimeFormats.hourMinuteSecond(date: date, timeZoneId: localZoneId, use24Hour: use24Hour)
    }
    private var localDateString: String {
        TimeFormats.shortDate(date: date, timeZoneId: localZoneId)
    }
    private var localOffset: String {
        TimeFormats.utcOffset(for: localZoneId, at: date)
    }

    private var isDaylight: Bool {
        let c = ZoneGeo.coordinate(for: localZoneId, at: date)
        return SolarMath.isDaylight(latitude: c.latitude, longitude: c.longitude, date: date)
    }
    private var glowColor: Color {
        isDaylight ? MeridianColors.daylightGlow : MeridianColors.nightGlow
    }

    /// Wall-clock de-duplication across local → residence → home-country, mirroring
    /// Android `anchorClockVisibility`. Residence shows its digital clock only if its
    /// wall clock differs from local; home-country only if it differs from both local
    /// and residence. Returns `(showResidenceClock, showHomeCountryClock)`.
    private var anchorClockVisibility: (residence: Bool, homeCountry: Bool) {
        var seen: Set<Int> = [TimeFormats.offsetSeconds(for: localZoneId, at: date)]
        func consume(_ zone: SavedZone?) -> Bool {
            guard let zone else { return false }
            let key = TimeFormats.offsetSeconds(for: zone.id, at: date)
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
        let residenceClock = consume(residence)
        let homeCountryClock = consume(homeCountry)
        return (residenceClock, homeCountryClock)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localTimeString)
                        // Type-scale token (displayMedium 36) so the hero tracks Dynamic
                        // Type, keeping the rounded/monospaced hero treatment.
                        .font(.displayMedium)
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(MeridianColors.primary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(localDateString)
                        .font(.titleMedium)
                        .foregroundStyle(MeridianColors.onSurface)
                    Text("\(localOffset) · Now")
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }
                // Group the time/date/offset as a single VoiceOver unit; the analog clock
                // is decorative alongside it.
                .accessibilityElement(children: .combine)
                Spacer()
                AnalogClockView(date: date, timeZoneId: localZoneId)
                    .accessibilityHidden(true)
            }

            let clockVisibility = anchorClockVisibility

            anchorSection(
                roleLabel: "Home",
                zone: residence,
                icon: "house.fill",
                emptyTitle: "Home",
                emptySubtitle: "Your usual base — campus city or apartment.",
                showChange: true,
                showDigitalClock: clockVisibility.residence,
                onPick: onPickResidence,
                onUseLocation: onUseLocation
            )

            if let homeCountry {
                anchorSection(
                    roleLabel: "Home country",
                    zone: homeCountry,
                    icon: "globe",
                    emptyTitle: "Home country",
                    emptySubtitle: "",
                    showChange: false,
                    showDigitalClock: clockVisibility.homeCountry,
                    onPick: onPickHomeCountry,
                    onUseLocation: nil
                )
            }
        }
        .padding(MeridianSpacing.xl.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(
            cornerRadius: MeridianRadius.large.rawValue,
            tint: MeridianColors.primary
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [glowColor.opacity(0.22), .clear],
                        center: .center, startRadius: 0, endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .offset(x: 40, y: -40)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: MeridianRadius.large.rawValue, style: .continuous))
    }

    @ViewBuilder
    private func anchorSection(
        roleLabel: String,
        zone: SavedZone?,
        icon: String,
        emptyTitle: String,
        emptySubtitle: String,
        showChange: Bool,
        showDigitalClock: Bool,
        onPick: @escaping () -> Void,
        onUseLocation: (() -> Void)?
    ) -> some View {
        Divider()
            .overlay(MeridianColors.onSurface.opacity(0.1))
            .padding(.vertical, 14)

        if let zone {
            let zoneTime = TimeFormats.hourMinute(date: date, timeZoneId: zone.id, use24Hour: use24Hour)
            let zoneDate = TimeFormats.shortDate(date: date, timeZoneId: zone.id)
            let zoneOffset = TimeFormats.utcOffset(for: zone.id, at: date)
            let localOffsetSeconds = TimeFormats.offsetSeconds(for: localZoneId, at: date)
            let zoneOffsetSeconds = TimeFormats.offsetSeconds(for: zone.id, at: date)
            // Subtitle mirrors Android: when the digital clock is shown the diff label is
            // used ("<role> · +Nh ahead"); otherwise "Same as now" (matches local wall
            // clock) or "Same clock as above".
            let subtitle: String = {
                if showDigitalClock {
                    return "\(roleLabel) · \(offsetDiffLabel(localOffsetSeconds: localOffsetSeconds, otherOffsetSeconds: zoneOffsetSeconds))"
                } else {
                    let matchesLocal = zoneOffsetSeconds == localOffsetSeconds
                    return "\(roleLabel) · \(matchesLocal ? "Same as now" : "Same clock as above")"
                }
            }()

            HStack(alignment: .center) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(MeridianColors.primary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(zone.displayName)
                            .font(.titleMedium)
                            .foregroundStyle(MeridianColors.onSurface)
                        if showDigitalClock {
                            Text("\(zoneDate) · \(zoneOffset)")
                                .font(.bodyMedium)
                                .foregroundStyle(MeridianColors.onSurfaceVariant)
                        }
                        Text(subtitle)
                            .font(.labelMedium)
                            .foregroundStyle(MeridianColors.onSurfaceVariant.opacity(showDigitalClock ? 0.7 : 1.0))
                    }
                }
                Spacer()
                if showDigitalClock {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(zoneTime)
                            .font(.headlineMedium)
                            .monospacedDigit()
                            .foregroundStyle(MeridianColors.primary)
                        if showChange {
                            Button("Change", action: onPick)
                                .font(.labelMedium)
                                .foregroundStyle(MeridianColors.primary)
                        }
                    }
                } else if showChange {
                    Button("Change", action: onPick)
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.primary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(MeridianColors.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(emptyTitle)
                            .font(.titleMedium)
                            .foregroundStyle(MeridianColors.onSurface)
                        if !emptySubtitle.isEmpty {
                            Text(emptySubtitle)
                                .font(.bodyMedium)
                                .foregroundStyle(MeridianColors.onSurfaceVariant)
                        }
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    Button {
                        onPick()
                    } label: {
                        Label("Pick city", systemImage: "magnifyingglass")
                            .font(.titleMedium)
                            .foregroundStyle(MeridianColors.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background {
                                RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                                    .strokeBorder(MeridianColors.primary.opacity(0.4), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)

                    // Resolve from device location (Android: second "Use location" button
                    // with an in-button spinner while resolving).
                    if let onUseLocation {
                        Button {
                            onUseLocation()
                        } label: {
                            HStack(spacing: 6) {
                                if resolvingLocation {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(MeridianColors.primary)
                                } else {
                                    Image(systemName: "location.fill")
                                }
                                Text(resolvingLocation ? "Locating…" : "Use location")
                            }
                            .font(.titleMedium)
                            .foregroundStyle(MeridianColors.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background {
                                RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                                    .strokeBorder(MeridianColors.primary.opacity(0.4), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(resolvingLocation)
                    }
                }
            }
        }
    }
}

// MARK: - AgendaItemRow

private struct AgendaItemRow: View {

    let task: PlannedTask
    let now: Date
    let use24Hour: Bool
    let onDelete: () -> Void

    @State private var deleteTrigger = 0

    private var minutesDiff: Int {
        Int((task.timestamp.timeIntervalSince(now) / 60).rounded(.towardZero))
    }

    private var relativeText: String {
        let absDiff = abs(minutesDiff)
        let hours = absDiff / 60
        let days = hours / 24
        let suffix = minutesDiff >= 0 ? "from now" : "ago"
        switch absDiff {
        case 0:        return "Just now"
        case ..<60:    return "\(absDiff) min \(suffix)"
        case 60..<1440: return "\(hours) hr\(hours > 1 ? "s" : "") \(suffix)"
        default:       return "\(days) day\(days > 1 ? "s" : "") \(suffix)"
        }
    }

    private var tagColor: Color {
        if minutesDiff < 0 { return MeridianColors.onSurfaceVariant.opacity(0.4) }
        // Imminent (< 1h): the M3 dark-error tone tuned for this canvas, not raw red.
        if minutesDiff < 60 { return MeridianColors.error }
        return MeridianColors.primary
    }

    /// Text equivalent of the urgency dot's color so red/grey semantics reach VoiceOver
    /// and colorblind users (finding: the dot is otherwise color-only).
    private var urgencyLabel: String {
        if minutesDiff < 0 { return relativeText }        // e.g. "12 min ago"
        if minutesDiff < 60 { return "Due soon, \(relativeText)" }
        return relativeText
    }

    private var zoneLabel: String? {
        let sysId = TimeZone.current.identifier
        guard task.tzId != sysId else { return nil }
        return task.tzId.split(separator: "/").last.map {
            $0.replacingOccurrences(of: "_", with: " ")
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(tagColor)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.titleMedium)
                    .foregroundStyle(MeridianColors.onSurface)
                    .lineLimit(2)
                Text(detailLine)
                    .font(.bodyMedium)
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
            }
            // Combine title + detail and fold in the urgency the dot color encodes.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(task.title), \(urgencyLabel)")

            Spacer()

            Button {
                deleteTrigger &+= 1   // Haptic on dismiss (Android: LongPress haptic).
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MeridianColors.onSurfaceVariant.opacity(0.6))
                    // Bump to the 44pt HIG minimum (was 28pt).
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss \(task.title)")
            .sensoryFeedback(.impact(weight: .medium), trigger: deleteTrigger)
        }
        .padding(14)
        .opacity(minutesDiff < -30 ? 0.55 : 1)
        .liquidGlass(
            cornerRadius: MeridianRadius.small.rawValue,
            tint: MeridianColors.primary
        )
        .contextMenu {
            Button("Dismiss event", systemImage: "xmark.circle", role: .destructive) {
                deleteTrigger &+= 1
                onDelete()
            }
        }
    }

    private var detailLine: String {
        let time = TimeFormats.hourMinute(date: task.timestamp, timeZoneId: task.tzId, use24Hour: use24Hour)
        let date = TimeFormats.shortDate(date: task.timestamp, timeZoneId: task.tzId)
        var s = "\(time) · \(date) (\(relativeText))"
        if let zoneLabel { s += " · \(zoneLabel)" }
        return s
    }
}

// MARK: - Offset diff label (ported from ZoneAnchorRole.kt `offsetDiffLabel`)

/// Human-readable offset difference between an anchor zone and the local zone, mirroring
/// Android `offsetDiffLabel`. Whole-hour diffs print as integers ("+3h ahead"); fractional
/// diffs print the decimal value ("+5.5h ahead"). Zero prints "Same time as local".
private func offsetDiffLabel(localOffsetSeconds: Int, otherOffsetSeconds: Int) -> String {
    let diffHours = Double(otherOffsetSeconds - localOffsetSeconds) / 3600.0
    func format(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1.0) == 0.0
            ? String(Int(value))
            : String(value)
    }
    if diffHours > 0 {
        return "+\(format(diffHours))h ahead"
    } else if diffHours < 0 {
        return "\(format(diffHours))h behind"
    } else {
        return "Same time as local"
    }
}

// MARK: - Contact grouping (ported from PlannerComponents.kt)

/// Android `contactsForZone` — starred people that appear on this zone's row.
func contactsForZone(_ zone: SavedZone, people: [Person], savedZones: [SavedZone]) -> [Person] {
    people.filter { $0.appearsOnZoneRow(zone, savedZones: savedZones) }
}

/// A bucket of starred contacts in one IANA zone not pinned to any saved zone
/// (Android `ParticipantLocationGroup` for orphans).
// Holds non-`Sendable` SwiftData `@Model` `Person` values, used only on the main actor by the
// Now screen, so this wrapper is intentionally not `Sendable`.
struct ContactLocationGroup: Identifiable {
    let zoneId: String
    let displayName: String
    let people: [Person]
    var id: String { "\(zoneId)::\(displayName.lowercased())" }
}

/// Android `unassignedContactGroups`: starred contacts whose zone isn't a saved/favorite
/// zone, grouped (and consolidated) by IANA zone. City names merge for one row per zone.
func unassignedContactGroups(people: [Person], savedZones: [SavedZone]) -> [ContactLocationGroup] {
    let favoriteZoneIds = Set(savedZones.filter(\.isFavorite).map(\.id))
    let orphans = people.filter { person in
        person.isFavorite
            && !person.isAssignedToAny(savedZones)
            && !favoriteZoneIds.contains(person.tzId)
    }
    guard !orphans.isEmpty else { return [] }

    // Group by (zoneId, displayLocation) preserving first-seen order.
    var order: [String] = []
    var buckets: [String: [Person]] = [:]
    for person in orphans {
        let key = "\(person.tzId)::\(person.displayLocation().lowercased())"
        if buckets[key] == nil { order.append(key) }
        buckets[key, default: []].append(person)
    }
    let raw = order.compactMap { key -> ContactLocationGroup? in
        guard let members = buckets[key], let first = members.first else { return nil }
        return ContactLocationGroup(zoneId: first.tzId, displayName: first.displayLocation(), people: members)
    }

    // Consolidate to one row per IANA zone, merging distinct city names.
    var zoneOrder: [String] = []
    var byZone: [String: [ContactLocationGroup]] = [:]
    for group in raw {
        if byZone[group.zoneId] == nil { zoneOrder.append(group.zoneId) }
        byZone[group.zoneId, default: []].append(group)
    }
    return zoneOrder.compactMap { zoneId -> ContactLocationGroup? in
        guard let zoneGroups = byZone[zoneId], let first = zoneGroups.first else { return nil }
        if zoneGroups.count == 1 { return first }
        let cities = zoneGroups
            .flatMap { $0.displayName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let distinctCities = cities.filter { seen.insert($0.lowercased()).inserted }.sorted { $0.lowercased() < $1.lowercased() }
        let allPeople = zoneGroups.flatMap(\.people)
        var seenPeople = Set<UUID>()
        let dedupedPeople = allPeople.filter { seenPeople.insert($0.id).inserted }
        return ContactLocationGroup(
            zoneId: zoneId,
            displayName: distinctCities.joined(separator: ", "),
            people: dedupedPeople
        )
    }
}

// MARK: - ContactLocationRow

private struct ContactLocationRow: View {

    let group: ContactLocationGroup
    let date: Date
    let use24Hour: Bool
    let onAddContact: (String) -> Void
    let onRemoveContact: (UUID) -> Void
    let onToggleContactFavorite: (UUID) -> Void

    @State private var showAddContact = false

    private var timeString: String {
        TimeFormats.hourMinute(date: date, timeZoneId: group.zoneId, use24Hour: use24Hour)
    }
    private var offsetString: String {
        TimeFormats.utcOffset(for: group.zoneId, at: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.displayName)
                        .font(.titleMedium)
                        .foregroundStyle(MeridianColors.onSurface)
                    Text(offsetString)
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }
                Spacer()
                Text(timeString)
                    // headlineMedium (20 semibold) via token; rounded design retained.
                    .font(.headlineMedium)
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(MeridianColors.primary)
            }

            ForEach(group.people) { person in
                HStack {
                    Text(person.name)
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurface)
                    Spacer()
                    Button {
                        onToggleContactFavorite(person.id)
                    } label: {
                        Image(systemName: person.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundStyle(person.isFavorite ? MeridianColors.daylightAccent : MeridianColors.onSurface.opacity(0.35))
                            // 44pt HIG tap target (icon stays 14pt).
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(person.isFavorite ? "Unfavorite \(person.name)" : "Favorite \(person.name)")
                    Button {
                        onRemoveContact(person.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            // Route destructive tone through the error token, not raw red.
                            .foregroundStyle(MeridianColors.error.opacity(0.7))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Remove \(person.name)")
                }
            }

            Button {
                showAddContact = true
            } label: {
                Label("Add contact", systemImage: "person.badge.plus")
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.primary)
                    // Keep the tappable row at the 44pt minimum height.
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityHint("Adds a contact to \(group.displayName)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(
            cornerRadius: MeridianRadius.medium.rawValue,
            tint: MeridianColors.secondary
        )
        .sheet(isPresented: $showAddContact) {
            AddContactToZoneSheet(zoneName: group.displayName, onConfirm: onAddContact)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("NowScreen") {
    let container = try! ModelContainer(
        for: SavedZone.self, Person.self, PlannedTask.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let settingsRepo = SettingsRepository()
    let vm = MainViewModel(modelContext: container.mainContext, settingsRepo: settingsRepo)

    return NowScreen()
        .environment(\.mainViewModel, vm)
        .environment(TimeEngine.shared)
        .environment(\.glassEnabled, true)
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
#endif
