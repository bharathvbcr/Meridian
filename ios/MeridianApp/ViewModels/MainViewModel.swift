// MainViewModel.swift
// Meridian — iOS 27 / Swift 6
//
// Root observable that owns all domain state and drives every screen. Injected as
// an @Environment value from the app root (`\.mainViewModel`).
//
// Behavioral port of Android `MainViewModel.kt` (+ `AppContainer` / `MeridianApplication`
// wiring), adapted to SwiftData + Swift 6 strict concurrency:
//
//  - upsert `addZone`, anchor-first reorder, default-zone seeding on an empty store;
//  - async multi-layer `searchTimeZones` merge (offset → abbreviation → curated PlaceIndex
//    → geo cities → airports → raw IANA), deduped by tzId and capped at 10;
//  - reminder scheduling on add/delete + Live Activity refresh + App-Group zone snapshot;
//  - `createRotatingSeries`, `loadCalendarEvents(from:to:)`;
//  - full AI orchestration via `AiAssistant` (pendingDraft + confirm/discard writing a
//    `PlannedTask`, welcome seed, clearChat).
//
// Scrub state is NOT duplicated here — it is delegated to `TimeEngine.shared`
// (`scrubInstant` is the single source of truth, mirroring Android's `TimeEngine`).

import Foundation
import SwiftData
import Observation
import SwiftUI

// MARK: - MainViewModel

/// Central observable view-model that owns all domain state and coordinates
/// repositories, use-cases, and SwiftData persistence.
///
/// `@MainActor` — all mutations are synchronous from the main thread. Background work
/// (calendar fetch, zone search across the bundled SQLite DB, AI inference) is kicked off
/// with `async` methods that hop off-actor and write results back on the main actor.
@Observable
@MainActor
final class MainViewModel {

    // MARK: - Published domain state

    /// All saved time zones, ordered by `sortOrder` ascending.
    var savedZones: [SavedZone] = []

    /// All planned tasks, ordered by timestamp ascending.
    var plannedTasks: [PlannedTask] = []

    /// All contacts/people, ordered alphabetically by name.
    var people: [Person] = []

    /// Calendar events loaded from EventKit for the current window.
    var calendarEvents: [CalendarEventModel] = []

    /// Chat conversation history shown on the AI screen (seeded with the welcome message).
    var chatMessages: [ChatMessage] = []

    /// Whether the AI assistant is currently generating a response.
    var aiLoading: Bool = false

    /// Partial assistant text while rules/cache/LLM paths stream into the UI.
    var aiPartialText: String? = nil

    /// A model-proposed event awaiting explicit user confirmation before any write (§12.8).
    var pendingDraft: PlannedTask? = nil

    /// Results from the most recent `searchTimeZones(_:)` call, merged + deduped + capped.
    var searchResults: [ZoneMatch] = []

    /// When `true`, the watchlist only shows favorited zones.
    var showFavoritesOnly: Bool = false

    /// The device's last-known coordinate (system cache; no fresh fix). Feeds `homeLocation`.
    private var deviceCoordinate: GeoPoint? = nil

    /// Where to pin the home zone on the day/night map: the device's actual location, but only
    /// while that fix plausibly lies inside the saved home zone (same clock as the zone nearest
    /// the fix). Otherwise nil, and the map falls back to the zone's representative city — so a
    /// home chosen manually for a faraway city still pins at that city (Android parity, §5.2).
    var homeLocation: GeoPoint? {
        guard let coordinate = deviceCoordinate,
              let home = savedZones.first(where: { $0.isHome }) else { return nil }
        return ZoneGeo.pointMatchesZoneClock(zoneId: home.id, point: coordinate) ? coordinate : nil
    }

    /// Re-reads the cached device fix (cheap, offline); safe to call without authorization.
    func refreshDeviceCoordinate() {
        deviceCoordinate = LocationZoneResolver().lastKnownCoordinate
    }

    // MARK: - Dependencies

    private let modelContext: ModelContext
    let settingsRepo: SettingsRepository
    private let calendarRepo: CalendarRepository
    private let findOverlap: FindOverlapUseCase
    private let reminderScheduler: ReminderScheduler
    private let liveActivityManager: LiveActivityManager
    private let geoPlaces: GeoPlaceRepository
    private let timeEngine: TimeEngine
    private let assistant: AiAssistant

    // MARK: - Constants (Android parity)

    /// Max merged search results (Android `limit = 10`).
    private static let searchLimit = 10
    /// How many airport matches a single search may contribute, so they never crowd out
    /// cities (Android `AIRPORT_RESULT_LIMIT = 6`).
    private static let airportResultLimit = 6

    /// Sorted snapshot of every IANA zone id, for the raw-id fallback layer
    /// (Android `ZoneId.getAvailableZoneIds().sorted()`).
    private let availableZoneIds: [String] = TimeZone.knownTimeZoneIdentifiers.sorted()

    /// The welcome message the conversation always resets to (Android `welcomeMessage`).
    private let welcomeMessage: ChatMessage

    // MARK: - Init

    /// Designated initialiser.
    /// - Parameters:
    ///   - modelContext: SwiftData context injected from the `ModelContainer`.
    ///   - settingsRepo: Shared settings store (defaults to `.shared`).
    ///   - calendarRepo: EventKit actor (defaults to a new instance).
    ///   - findOverlap: Meeting-overlap use case (stateless; defaults to a new instance).
    ///   - reminderScheduler: Local-notification scheduler (defaults to `.shared`).
    ///   - liveActivityManager: Live Activity driver (defaults to `.shared`).
    ///   - geoPlaces: Bundled city/airport SQLite lookup (defaults to `.shared`).
    ///   - timeEngine: Scrub + time helpers (defaults to `.shared`).
    init(
        modelContext: ModelContext,
        settingsRepo: SettingsRepository = .shared,
        calendarRepo: CalendarRepository = CalendarRepository(),
        findOverlap: FindOverlapUseCase = FindOverlapUseCase(),
        reminderScheduler: ReminderScheduler = .shared,
        liveActivityManager: LiveActivityManager = .shared,
        geoPlaces: GeoPlaceRepository = .shared,
        timeEngine: TimeEngine = .shared
    ) {
        self.modelContext = modelContext
        self.settingsRepo = settingsRepo
        self.calendarRepo = calendarRepo
        self.findOverlap = findOverlap
        self.reminderScheduler = reminderScheduler
        self.liveActivityManager = liveActivityManager
        self.geoPlaces = geoPlaces
        self.timeEngine = timeEngine

        // The assistant reads the live system clock for "now" — mirroring Android's
        // `timeEngine.now()` (the wall clock, NOT the scrubbed display instant), so its
        // answers reflect the real current time (§12.7). `now` must be off-actor `Sendable`,
        // so it cannot read `TimeEngine.shared.displayDate` (main-actor isolated).
        self.assistant = AiAssistant(
            settings: settingsRepo,
            findOverlap: findOverlap,
            now: { Date() }
        )

        self.welcomeMessage = ChatMessage(
            isUser: false,
            text: "Hello! I'm Meridian. I can tell you the real current time anywhere, convert times "
                + "between cities, find fair meeting windows, and schedule events across time zones — "
                + "on-device when your phone supports it, with cloud backup otherwise. Try \"What time "
                + "is it in Tokyo right now?\"",
            timestamp: Date()
        )
        self.chatMessages = [welcomeMessage]

        loadData()
        bootstrap()
    }

    /// One-time launch work (Android `init { … }`): prewarm the bundled city DB so the first
    /// search is instant, seed default zones into an empty store, then push the initial zone
    /// snapshot to the widget App-Group container.
    private func bootstrap() {
        Task { await geoPlaces.prewarm() }
        // Precompute the Foundation Models KV cache so the first assistant turn is
        // fast (self-guards on engine + availability; Android warms via model reuse).
        assistant.prewarm()
        seedDefaultZonesIfEmpty()
        publishSharedZones()
        refreshDeviceCoordinate()
    }

    // MARK: - Settings proxy

    /// Live settings snapshot. Views observe changes via `@Observable` tracking.
    var settings: MeridianSettings { settingsRepo.settings }

    // MARK: - Computed properties

    /// The residence (home) anchor zone, or `nil`.
    var homeZone: SavedZone? {
        savedZones.first { $0.anchorRole == .residence }
    }

    /// The home-country anchor zone, or `nil`.
    var homeCountryZone: SavedZone? {
        savedZones.first { $0.anchorRole == .homeCountry }
    }

    /// All saved zones excluding the residence anchor, in `sortOrder`.
    var watchlistZones: [SavedZone] {
        savedZones.filter { $0.anchorRole != .residence }
    }

    /// Watchlist zones filtered by `showFavoritesOnly`.
    var filteredWatchlistZones: [SavedZone] {
        showFavoritesOnly ? watchlistZones.filter(\.isFavorite) : watchlistZones
    }

    /// Tasks whose timestamp falls within the next 2 hours of the displayed time.
    var upcomingTasks: [PlannedTask] {
        let now = timeEngine.displayDate
        let horizon = now.addingTimeInterval(7_200)
        return plannedTasks
            .filter { $0.timestamp >= now && $0.timestamp <= horizon }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Scrub control (delegated to TimeEngine — single source of truth)

    /// Pins the timeline to an absolute instant, or clears it (live) when `nil`.
    /// Mirrors Android `selectScrubTime` → `timeEngine.updateScrub`.
    func selectScrubTime(_ instant: Date?) {
        timeEngine.setScrubInstant(instant)
    }

    /// The instant the whole app should render (scrub instant while scrubbing, else live).
    var displayDate: Date { timeEngine.displayDate }

    // MARK: - Zone CRUD

    /// Upserts a `SavedZone` (Android `addZone`):
    /// - If a zone with the same id exists, keep it but adopt a non-blank display name and OR
    ///   the favorite flag (never downgrade either).
    /// - Otherwise insert with the next `sortOrder` when one was not explicitly provided.
    func addZone(_ zone: SavedZone) {
        if let existing = savedZones.first(where: { $0.id == zone.id }) {
            let newName = zone.displayName.trimmingCharacters(in: .whitespaces)
            if !newName.isEmpty { existing.displayName = zone.displayName }
            existing.isFavorite = existing.isFavorite || zone.isFavorite
        } else {
            let maxOrder = savedZones.map(\.sortOrder).max() ?? 0
            zone.sortOrder = zone.sortOrder == 0 ? maxOrder + 1 : zone.sortOrder
            modelContext.insert(zone)
        }
        saveContext()
        loadData()
        publishSharedZones()
    }

    /// Convenience upsert from primitive fields (used by add-zone sheets).
    func addZone(
        id: String,
        displayName: String,
        anchorRole: ZoneAnchorRole? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        countryName: String? = nil
    ) {
        addZone(
            SavedZone(
                id: id,
                displayName: displayName,
                isHome: anchorRole == .residence,
                anchorRole: anchorRole,
                latitude: latitude,
                longitude: longitude,
                countryName: countryName
            )
        )
    }

    /// Adds a zone resolved from a search hit.
    func addZone(from match: ZoneMatch) {
        addZone(id: match.zoneId, displayName: match.displayName)
    }

    /// Deletes the zone with the given IANA identifier.
    func removeZone(id: String) {
        guard let zone = savedZones.first(where: { $0.id == id }) else { return }
        modelContext.delete(zone)
        saveContext()
        loadData()
        publishSharedZones()
    }

    /// Toggles the `isFavorite` flag on the zone matching `id`.
    func toggleZoneFavorite(id: String) {
        guard let zone = savedZones.first(where: { $0.id == id }) else { return }
        zone.isFavorite.toggle()
        saveContext()
        loadData()
        publishSharedZones()
    }

    /// Marks `id` as the residence (home) anchor and clears the flag on all others.
    func setHomeZone(id: String, displayName: String? = nil) {
        setAnchorZone(id: id, displayName: displayName, role: .residence)
    }

    /// Resolves the device's location to an IANA zone (permission-gated, on-device)
    /// and pins it as the residence anchor. Returns the resolved display name, or
    /// nil when the location/zone could not be read. Shared by the Now card's
    /// "Use location" button and Settings (Android: `resolveHomeFromLocation`).
    func resolveHomeFromLocation() async -> String? {
        let resolver = LocationZoneResolver()
        guard let zoneId = await resolver.resolveHomeZoneId() else { return nil }
        let name = zoneId.split(separator: "/").last
            .map { $0.replacingOccurrences(of: "_", with: " ") } ?? zoneId
        setHomeZone(id: zoneId, displayName: name)
        refreshDeviceCoordinate()
        return name
    }

    /// Pins `id` to an anchor slot on the Now card (`.residence` or `.homeCountry`), replacing
    /// any zone already in that slot. Inserts the zone first if it is not yet saved.
    /// Mirrors Android `setAnchorZone`.
    func setAnchorZone(id: String, displayName: String?, role: ZoneAnchorRole) {
        let name = displayName ?? Self.defaultDisplayName(for: id)

        if !savedZones.contains(where: { $0.id == id }) {
            modelContext.insert(
                SavedZone(
                    id: id,
                    displayName: name,
                    isHome: role == .residence,
                    anchorRole: role,
                    sortOrder: 0
                )
            )
        }

        // Re-fetch is not needed; mutate the in-memory @Model instances directly.
        for zone in savedZones {
            if zone.id == id {
                zone.displayName = name
                zone.anchorRole = role
                zone.isHome = role == .residence
                zone.sortOrder = 0
            } else if zone.anchorRole == role {
                zone.anchorRole = nil
                zone.isHome = false
            }
        }

        if role == .homeCountry {
            settingsRepo.setHomeCountryEnabled(true)
        }

        saveContext()
        loadData()
        publishSharedZones()
    }

    /// Swaps a zone one step up (`direction == -1`) or down (`direction == 1`) in display order.
    /// Mirrors Android `reorderZone`.
    func reorderZone(id: String, direction: Int) {
        guard let index = savedZones.firstIndex(where: { $0.id == id }) else { return }
        let target = index + direction
        guard savedZones.indices.contains(target) else { return }
        let a = savedZones[index]
        let b = savedZones[target]
        swap(&a.sortOrder, &b.sortOrder)
        saveContext()
        loadData()
        publishSharedZones()
    }

    /// Applies a full ordering to the *watchlist* zones, keeping the anchor zones packed at the
    /// front (Android `reorderZones`): anchors take indices `0..<anchorCount`, then `orderedIds`.
    func reorderZones(ids orderedIds: [String]) {
        let anchorZones = savedZones.filter { $0.isNowAnchor }
        for (idx, zone) in anchorZones.enumerated() where zone.sortOrder != idx {
            zone.sortOrder = idx
        }
        let anchorCount = anchorZones.count
        for (idx, id) in orderedIds.enumerated() {
            guard let zone = savedZones.first(where: { $0.id == id }) else { continue }
            let newIndex = idx + anchorCount
            if zone.sortOrder != newIndex { zone.sortOrder = newIndex }
        }
        saveContext()
        loadData()
        publishSharedZones()
    }

    // MARK: - Zone search (multi-layer merge — Android `searchTimeZones`)

    /// Resolves `query` to addable zones across every supported dimension — offset, abbreviation,
    /// curated city index, the bundled city DB, airports, and finally raw IANA ids — merged in
    /// priority order and deduped by zone id (so the same zone never appears twice), capped at 10.
    ///
    /// `async` because the city/airport layers read the bundled SQLite database off the main thread
    /// (the `GeoPlaceRepository` actor). Also stores the result in `searchResults`.
    @discardableResult
    func searchTimeZones(_ query: String) async -> [ZoneMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return []
        }

        let limit = Self.searchLimit
        // Preserve the priority order layers contribute in, collapsing duplicate zones.
        var order: [String] = []
        var byZone: [String: ZoneMatch] = [:]

        func offer(_ match: ZoneMatch) {
            guard byZone.count < limit, byZone[match.zoneId] == nil else { return }
            byZone[match.zoneId] = match
            order.append(match.zoneId)
        }

        // 1. UTC/GMT offsets ("UTC", "gmt+1", "utc+5:30", "-0800").
        for match in OffsetZones.parse(trimmed) { offer(match) }

        // 2. Time-zone abbreviations / phrase hints ("JST", "Pacific Time").
        if let match = TzAbbreviations.resolve(trimmed) { offer(match) }

        // 3. Curated PlaceIndex — friendly names, aliases, airport codes.
        for entry in PlaceIndex.shared.search(query: trimmed, limit: limit) {
            offer(ZoneMatch(entry))
        }

        // 4. Comprehensive bundled city database (long tail).
        if byZone.count < limit {
            for match in await geoPlaces.searchCities(query: trimmed, limit: limit) { offer(match) }
        }

        // 5. Airports by IATA code or name.
        if byZone.count < limit {
            for match in await geoPlaces.searchAirports(query: trimmed, limit: Self.airportResultLimit) {
                offer(match)
            }
        }

        // 6. Raw IANA ids, so even obscure zones stay reachable by their identifier.
        if byZone.count < limit {
            let lower = trimmed.lowercased()
            for id in availableZoneIds {
                if byZone.count >= limit { break }
                if id.lowercased().contains(lower) {
                    offer(ZoneMatch(zoneId: id, displayName: Self.defaultDisplayName(for: id)))
                }
            }
        }

        let results = order.compactMap { byZone[$0] }
        searchResults = results
        return results
    }

    // MARK: - Task CRUD

    /// Persists a `PlannedTask`, then schedules its reminder, refreshes the live countdown, and
    /// re-publishes the widget snapshot (Android `addTask`). Assigns the next `sortOrder` when one
    /// was not explicitly provided.
    func addTask(_ task: PlannedTask) {
        if task.sortOrder == 0 {
            let maxOrder = plannedTasks.map(\.sortOrder).max() ?? 0
            task.sortOrder = maxOrder + 1
        }
        modelContext.insert(task)
        saveContext()
        loadData()

        // Snapshot the Sendable fields before crossing the await boundary.
        let id = task.id, title = task.title, timestamp = task.timestamp, tzId = task.tzId
        Task { [reminderScheduler] in
            await reminderScheduler.schedule(
                PlannedTask(id: id, title: title, timestamp: timestamp, tzId: tzId)
            )
        }
        refreshLiveActivity()
    }

    /// Convenience to author a task from primitive fields.
    func addTask(title: String, timestamp: Date, zoneId: String) {
        addTask(PlannedTask(title: title, timestamp: timestamp, tzId: zoneId))
    }

    /// Cancels the reminder for the task, deletes it, then refreshes the live countdown
    /// (Android `deleteTask`).
    func deleteTask(_ task: PlannedTask) {
        let id = task.id
        reminderScheduler.cancel(id: id)
        modelContext.delete(task)
        saveContext()
        loadData()
        refreshLiveActivity()
    }

    /// Deletes the task with the given id, if present.
    func deleteTask(id: String) {
        guard let task = plannedTasks.first(where: { $0.id == id }) else { return }
        deleteTask(task)
    }

    /// Swaps a task one step up (`-1`) or down (`1`) in order (Android `reorderTask`).
    func reorderTask(id: String, direction: Int) {
        guard let index = plannedTasks.firstIndex(where: { $0.id == id }) else { return }
        let target = index + direction
        guard plannedTasks.indices.contains(target) else { return }
        let a = plannedTasks[index]
        let b = plannedTasks[target]
        swap(&a.sortOrder, &b.sortOrder)
        saveContext()
        loadData()
    }

    // MARK: - Person CRUD

    /// Persists a new `Person` (Android `addPerson`). No-op on a blank zone id.
    func addPerson(
        name: String,
        zoneId: String,
        locationName: String = "",
        workStartHour: Int = 9,
        workEndHour: Int = 17,
        dndStartHour: Int = -1,
        dndEndHour: Int = -1,
        isFavorite: Bool = false
    ) {
        let tz = zoneId.trimmingCharacters(in: .whitespaces)
        guard !tz.isEmpty else { return }
        let label = locationName.isEmpty ? Self.defaultDisplayName(for: tz) : locationName
        let person = Person(
            name: name.trimmingCharacters(in: .whitespaces),
            tzId: tz,
            displayName: label,
            isFavorite: isFavorite,
            workStartHour: workStartHour,
            workEndHour: workEndHour,
            dndStartHour: dndStartHour,
            dndEndHour: dndEndHour
        )
        modelContext.insert(person)
        saveContext()
        loadData()
    }

    /// Deletes the specified `Person`.
    func deletePerson(_ person: Person) {
        modelContext.delete(person)
        saveContext()
        loadData()
    }

    /// Deletes the person with the given id, if present.
    func deletePerson(id: UUID) {
        guard let person = people.first(where: { $0.id == id }) else { return }
        deletePerson(person)
    }

    /// Toggles the `isFavorite` flag on the specified person.
    func togglePersonFavorite(_ person: Person) {
        person.isFavorite.toggle()
        saveContext()
        loadData()
    }

    /// Toggles the `isFavorite` flag on the person with the given id.
    func togglePersonFavorite(id: UUID) {
        guard let person = people.first(where: { $0.id == id }) else { return }
        togglePersonFavorite(person)
    }

    // MARK: - Meeting slot computation

    /// Ranks meeting slots for `participants` on `baseDate`. Pure delegation to
    /// `FindOverlapUseCase` — the LLM never computes time (§12.7). Participants whose zone id is
    /// invalid are dropped defensively (Android `computeMeetingSlots`).
    func computeMeetingSlots(
        participants: [MeetingParticipant],
        baseDate: Date
    ) -> [MeetingSlot] {
        let valid = participants.filter { TimeZone(identifier: $0.zoneId) != nil }
        guard !valid.isEmpty else { return [] }
        return findOverlap.rankParticipantSlots(baseDate: baseDate, participants: valid)
    }

    /// Convenience overload: ranks slots from a set of saved `Person` rows.
    func computeMeetingSlots(
        people participants: [Person],
        baseDate: Date
    ) -> [MeetingSlot] {
        let mapped = participants.map {
            MeetingParticipant(
                name: $0.name,
                zoneId: $0.tzId,
                workStartHour: $0.workStartHour,
                workEndHour: $0.workEndHour,
                dndStartHour: $0.dndStartHour,
                dndEndHour: $0.dndEndHour
            )
        }
        return computeMeetingSlots(participants: mapped, baseDate: baseDate)
    }

    /// Creates a rotating weekly series from ranked `slots`: week N uses the Nth rotation pick
    /// (a fairer-for-different-regions time) shifted forward N weeks, saved as plan drafts (§5.8).
    /// Mirrors Android `createRotatingSeries`.
    /// - Parameter participantOrder: zone ids in participant-encounter order, used by
    ///   `RotationPlanner.worstZone` to break ties exactly as Android's LinkedHashMap does.
    func createRotatingSeries(slots: [MeetingSlot], weeks: Int, zoneId: String, participantOrder: [String] = []) {
        let picks = RotationPlanner.rotatingSeries(slots: slots, count: weeks, participantOrder: participantOrder)
        for (index, slot) in picks.enumerated() {
            let weekOffset = TimeInterval(index) * 7 * 24 * 3600
            let start = slot.start.addingTimeInterval(weekOffset)
            addTask(
                PlannedTask(
                    title: "Rotating sync (week \(index + 1))",
                    timestamp: start,
                    tzId: zoneId
                )
            )
        }
    }

    // MARK: - Settings delegates

    func setHourCycle(_ value: HourCycle) { settingsRepo.setHourCycle(value) }
    func setGlassEnabled(_ value: Bool) { settingsRepo.setGlassEnabled(value) }
    func setGlassOpacity(_ value: Double) { settingsRepo.setGlassOpacity(value) }
    func setReduceTransparency(_ value: Bool) { settingsRepo.setReduceTransparency(value) }
    func setBackdropEnabled(_ value: Bool) { settingsRepo.setBackdropEnabled(value) }
    func setBackdropIntensity(_ value: Double) { settingsRepo.setBackdropIntensity(value) }
    func setMapStyle(_ value: MapStyle) { settingsRepo.setMapStyle(value) }
    func setHomeCountryEnabled(_ value: Bool) { settingsRepo.setHomeCountryEnabled(value) }
    func setReminderLeadMinutes(_ value: Int) { settingsRepo.setReminderLeadMinutes(value) }
    func setDefaultWorkStartHour(_ value: Int) { settingsRepo.setDefaultWorkStartHour(value) }
    func setDefaultWorkEndHour(_ value: Int) { settingsRepo.setDefaultWorkEndHour(value) }
    func setAiEngine(_ value: AiEngine) { settingsRepo.setAiEngine(value) }
    func setOnboardingComplete(_ value: Bool) { settingsRepo.setOnboardingComplete(value) }

    // MARK: - Calendar

    /// Requests full calendar access from the user via EventKit.
    func requestCalendarAccess() async -> Bool {
        await calendarRepo.requestAccess()
    }

    /// Loads calendar events for `[from, to]` and writes them to `calendarEvents`
    /// (Android `loadCalendarEvents`).
    func loadCalendarEvents(from: Date, to: Date) async {
        calendarEvents = await calendarRepo.fetchEvents(from: from, to: to)
    }

    /// Convenience: loads a ±24-hour window around the displayed instant.
    func loadCalendarEvents() async {
        let anchor = timeEngine.displayDate
        await loadCalendarEvents(
            from: anchor.addingTimeInterval(-24 * 60 * 60),
            to: anchor.addingTimeInterval(24 * 60 * 60)
        )
    }

    // MARK: - AI orchestration (Android `sendAiMessage` / draft confirm-discard)

    /// Sends a user message to the assistant and appends the reply (or proposes a draft).
    /// The assistant resolves any scheduling request locally into a concrete `PlannedTask`;
    /// it is proposed — never auto-written — and the user confirms via `confirmDraft()` (§12.8).
    func sendAiMessage(_ messageText: String) async {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        chatMessages.append(
            ChatMessage(isUser: true, text: messageText, timestamp: Date())
        )
        aiLoading = true
        aiPartialText = nil
        defer {
            aiPartialText = nil
            aiLoading = false
        }

        let homeZoneId = savedZones.first(where: { $0.isHome })?.id ?? TimeZone.current.identifier
        let recentTurns = recentChatTurns()
        let result = await assistant.process(
            prompt: messageText,
            homeZoneId: homeZoneId,
            savedZones: savedZones,
            people: people,
            recentTurns: recentTurns,
            onPartial: { [weak self] partial in
                await MainActor.run { self?.aiPartialText = partial }
            }
        )

        switch result {
        case let .success(replyText, source):
            chatMessages.append(
                ChatMessage(isUser: false, text: replyText, source: source, timestamp: Date())
            )
        case let .scheduled(task, source):
            // Propose, never auto-write — the user confirms below (§12.8).
            pendingDraft = task
            chatMessages.append(
                ChatMessage(
                    isUser: false,
                    text: "I drafted '\(task.title)'. Review and confirm it below to add it.",
                    source: source,
                    timestamp: Date()
                )
            )
        case let .error(message):
            // Rendered as the red error bubble (Android: sender == "System Error").
            chatMessages.append(
                ChatMessage(isUser: false, text: message, isError: true, timestamp: Date())
            )
        }
    }

    /// Commits the pending AI-proposed draft to the plan after explicit user confirmation.
    func confirmDraft() {
        guard let draft = pendingDraft else { return }
        // Detach a fresh model from the draft (the draft is not yet inserted into the context).
        addTask(
            PlannedTask(
                id: draft.id,
                title: draft.title,
                timestamp: draft.timestamp,
                tzId: draft.tzId,
                origin: draft.origin,
                externalId: draft.externalId
            )
        )
        let title = draft.title
        pendingDraft = nil
        chatMessages.append(
            ChatMessage(
                isUser: false,
                text: "Added '\(title)' to your plan.",
                timestamp: Date()
            )
        )
    }

    /// Discards the pending draft without writing it.
    func discardDraft() {
        guard pendingDraft != nil else { return }
        pendingDraft = nil
        chatMessages.append(
            ChatMessage(isUser: false, text: "Discarded the draft.", timestamp: Date())
        )
    }

    /// Resets the conversation back to the initial welcome message and drops any pending draft.
    func clearChat() {
        chatMessages = [welcomeMessage]
        pendingDraft = nil
    }

    /// Releases on-device model memory when the app backgrounds.
    func releaseAiModels() {
        assistant.releaseOnDeviceSession()
    }

    /// Pre-warms the on-device model KV cache when idle.
    func prewarmAi() {
        assistant.prewarm()
    }

    private func recentChatTurns() -> [ChatTurn] {
        chatMessages
            .filter { !$0.isError }
            .dropLast()
            .suffix(4)
            .map { msg in
                ChatTurn(
                    role: msg.isUser ? "User" : "Assistant",
                    text: msg.text
                )
            }
    }

    /// Removes the error bubble and resends the user message that preceded it.
    func retryAiMessage(errorMessageId: UUID) {
        guard !aiLoading else { return }
        guard let errorIdx = chatMessages.firstIndex(where: { $0.id == errorMessageId }),
              errorIdx > 0 else { return }
        guard let userText = chatMessages[..<errorIdx].last(where: { $0.isUser })?.text else { return }
        chatMessages.removeAll { $0.id == errorMessageId }
        Task { await sendAiMessage(userText) }
    }

    // MARK: - Private helpers

    /// Loads all SwiftData models into their published arrays, ordered to match Android.
    private func loadData() {
        do {
            let zoneDescriptor = FetchDescriptor<SavedZone>(
                sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
            )
            savedZones = try modelContext.fetch(zoneDescriptor)

            let taskDescriptor = FetchDescriptor<PlannedTask>(
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
            plannedTasks = try modelContext.fetch(taskDescriptor)

            let personDescriptor = FetchDescriptor<Person>(
                sortBy: [SortDescriptor(\.name, order: .forward)]
            )
            people = try modelContext.fetch(personDescriptor)
        } catch {
            // In production replace with an error-reporting mechanism.
            print("[MainViewModel] loadData error: \(error)")
        }
    }

    /// Saves pending changes to the SwiftData context.
    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("[MainViewModel] saveContext error: \(error)")
        }
    }

    /// Seeds three default zones when the store is empty (Android `init` seeding:
    /// London / Tokyo / New York).
    private func seedDefaultZonesIfEmpty() {
        guard savedZones.isEmpty else { return }
        let defaults = [
            SavedZone(id: "Europe/London", displayName: "London", sortOrder: 0),
            SavedZone(id: "Asia/Tokyo", displayName: "Tokyo", sortOrder: 1),
            SavedZone(id: "America/New_York", displayName: "New York", sortOrder: 2),
        ]
        defaults.forEach { modelContext.insert($0) }
        saveContext()
        loadData()
    }

    /// Re-evaluates the Live Activity against the current task set (Android `LiveUpdates.refreshNow`).
    /// Internal so the app shell can re-arm it on every foreground: ActivityKit can only START
    /// an activity while the app is foregrounded, so the background refresh alone can miss one.
    func refreshLiveActivity() {
        let entries = plannedTasks.map { (id: $0.id, title: $0.title, date: $0.timestamp) }
        let now = timeEngine.displayDate
        Task { [liveActivityManager] in
            await liveActivityManager.reconcile(tasks: entries, now: now)
        }
    }

    /// Writes the current pinned-zone snapshot to the App Group so the widget can render it.
    private func publishSharedZones() {
        let snapshot = savedZones.enumerated().map { index, zone in
            SharedZone(
                id: zone.id,
                tzId: zone.tzId,
                displayName: zone.displayName,
                isHome: zone.isHome,
                orderIndex: zone.sortOrder == 0 ? index : zone.sortOrder
            )
        }
        SharedZoneStore.save(zones: snapshot)
    }

    /// Last IANA segment with underscores replaced by spaces (Android display-name fallback).
    private static func defaultDisplayName(for zoneId: String) -> String {
        zoneId.split(separator: "/").last.map {
            $0.replacingOccurrences(of: "_", with: " ")
        } ?? zoneId
    }
}
