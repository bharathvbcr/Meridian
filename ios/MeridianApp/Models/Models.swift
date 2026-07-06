import Foundation
import SwiftData

// MARK: - ZoneAnchorRole

/// Slots pinned on the Now card alongside local device time (Android: ZoneAnchorRole).
/// Stored as an optional on `SavedZone`: `nil` == watchlist-only zone (Android's NONE = "").
enum ZoneAnchorRole: String, Codable, Sendable {
    /// Usual base — e.g. campus city or apartment.
    case residence
    /// Origin country — e.g. India for family calls while studying abroad.
    case homeCountry
}

// MARK: - SavedZone

@Model
final class SavedZone {
    @Attribute(.unique) var id: String   // IANA id, e.g. "America/Los_Angeles"
    var tzId: String                     // IANA zone id (may equal id; kept explicit per contract)
    var displayName: String              // e.g. "San Francisco"
    var isHome: Bool = false
    var isFavorite: Bool = false
    /// `nil` for watchlist-only zones (Android: anchorRole == "").
    var anchorRole: ZoneAnchorRole? = nil
    var sortOrder: Int = 0
    var latitude: Double? = nil
    var longitude: Double? = nil
    var countryName: String? = nil

    init(
        id: String,
        tzId: String? = nil,
        displayName: String,
        isHome: Bool = false,
        isFavorite: Bool = false,
        anchorRole: ZoneAnchorRole? = nil,
        sortOrder: Int = 0,
        latitude: Double? = nil,
        longitude: Double? = nil,
        countryName: String? = nil
    ) {
        self.id = id
        self.tzId = tzId ?? id
        self.displayName = displayName
        self.isHome = isHome
        self.isFavorite = isFavorite
        self.anchorRole = anchorRole
        self.sortOrder = sortOrder
        self.latitude = latitude
        self.longitude = longitude
        self.countryName = countryName
    }

    /// Android: `isNowAnchor()` — anchorRole non-empty OR isHome.
    var isNowAnchor: Bool {
        anchorRole != nil || isHome
    }

    var isResidence: Bool {
        anchorRole == .residence
    }

    var isHomeCountry: Bool {
        anchorRole == .homeCountry
    }
}

// MARK: - SavedZone collection helpers (Android: ZoneAnchorRole.kt extensions)

extension Array where Element == SavedZone {
    /// Android: `homeCountryZone()`.
    func homeCountryZone() -> SavedZone? {
        first { $0.anchorRole == .homeCountry }
    }

    /// Android: `residenceZone()` — residence anchor, else a plain home zone.
    func residenceZone() -> SavedZone? {
        first { $0.anchorRole == .residence }
            ?? first { $0.isHome && $0.anchorRole == nil }
    }

    /// Android: `localLocationLabel(localZoneId)` — residence/home display name,
    /// else the last IANA segment with underscores replaced by spaces.
    func localLocationLabel(localZoneId: String) -> String {
        if let r = residenceZone() { return r.displayName }
        if let h = first(where: { $0.isHome }) { return h.displayName }
        return localZoneId.split(separator: "/").last.map {
            $0.replacingOccurrences(of: "_", with: " ")
        } ?? localZoneId
    }
}

// MARK: - Person

@Model
final class Person {
    var id: UUID = UUID()
    var name: String
    var tzId: String
    var displayName: String = ""        // city/place label, distinct from tzId
    var isFavorite: Bool = false
    /// Local working window [workStartHour, workEndHour) used by the fairness ranker.
    var workStartHour: Int = 9
    var workEndHour: Int = 17
    /// Optional do-not-disturb window; -1/-1 means none. Wraps midnight if start > end.
    var dndStartHour: Int = -1
    var dndEndHour: Int = -1

    init(
        id: UUID = UUID(),
        name: String,
        tzId: String,
        displayName: String = "",
        isFavorite: Bool = false,
        workStartHour: Int = 9,
        workEndHour: Int = 17,
        dndStartHour: Int = -1,
        dndEndHour: Int = -1
    ) {
        self.id = id
        self.name = name
        self.tzId = tzId
        self.displayName = displayName
        self.isFavorite = isFavorite
        self.workStartHour = workStartHour
        self.workEndHour = workEndHour
        self.dndStartHour = dndStartHour
        self.dndEndHour = dndEndHour
    }

    /// Android: `displayLocation()` — place label, falling back to the zone segment.
    func displayLocation() -> String {
        if !displayName.isEmpty { return displayName }
        return tzId.split(separator: "/").last.map {
            $0.replacingOccurrences(of: "_", with: " ")
        } ?? tzId
    }

    /// Android: `matchesZone(zone)`.
    func matchesZone(_ zone: SavedZone) -> Bool {
        tzId == zone.id &&
            (displayName.isEmpty || displayName.caseInsensitiveCompare(zone.displayName) == .orderedSame)
    }

    /// Android: `sharesTimeZoneWith(zone)`.
    func sharesTimeZoneWith(_ zone: SavedZone) -> Bool {
        tzId == zone.id
    }

    /// Android: `isAssignedToAny(savedZones)`.
    func isAssignedToAny(_ savedZones: [SavedZone]) -> Bool {
        savedZones.contains { matchesZone($0) }
    }

    /// Android: `appearsOnZoneRow(zone, savedZones)`.
    func appearsOnZoneRow(_ zone: SavedZone, savedZones: [SavedZone]) -> Bool {
        isFavorite && (
            matchesZone(zone) ||
                (sharesTimeZoneWith(zone) && zone.isFavorite && !isAssignedToAny(savedZones))
        )
    }
}

// MARK: - PlannedTask

@Model
final class PlannedTask {
    var id: String = UUID().uuidString
    var title: String
    var timestamp: Date
    var tzId: String
    var sortOrder: Int = 0
    /// Bundle id of the app this row was imported from, or `nil` for locally authored tasks.
    var origin: String? = nil
    /// Stable id of the source row within `origin`; used to upsert imports idempotently.
    var externalId: String? = nil

    init(
        id: String = UUID().uuidString,
        title: String,
        timestamp: Date,
        tzId: String,
        sortOrder: Int = 0,
        origin: String? = nil,
        externalId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.timestamp = timestamp
        self.tzId = tzId
        self.sortOrder = sortOrder
        self.origin = origin
        self.externalId = externalId
    }
}

// MARK: - CalendarEventModel

struct CalendarEventModel: Identifiable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    /// CGColor is not Sendable; stored as raw components when available.
    let calendarColorComponents: [CGFloat]?
    let notes: String?
    let location: String?
    let hasAttendees: Bool
    /// The event's own IANA zone (Android: `EVENT_TIMEZONE`) so it renders at its
    /// native wall-clock time, not the device's. `nil` for floating/all-day events.
    let timeZoneId: String?

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarTitle: String = "",
        calendarColorComponents: [CGFloat]? = nil,
        notes: String? = nil,
        location: String? = nil,
        hasAttendees: Bool = false,
        timeZoneId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.calendarColorComponents = calendarColorComponents
        self.notes = notes
        self.location = location
        self.hasAttendees = hasAttendees
        self.timeZoneId = timeZoneId
    }
}

// MARK: - SlotLabel

/// Rating bucket for a meeting slot (Android: ratingLabel "Optimal"/"Fair"/"Difficult").
enum SlotLabel: Sendable {
    case optimal
    case fair
    case difficult

    /// User-facing string (matches Android labels).
    var displayName: String {
        switch self {
        case .optimal:   return "Optimal"
        case .fair:      return "Fair"
        case .difficult: return "Difficult"
        }
    }
}

// MARK: - MeetingSlot

/// One ranked hourly candidate. `start` is an ABSOLUTE instant; rendering it to a
/// per-zone wall-clock string is the VIEW layer's job (do NOT bake UTC strings here).
struct MeetingSlot: Identifiable, Sendable {
    let id: UUID
    /// Absolute start instant of the slot (Android: utcStartInstant).
    let start: Date
    /// ZoneId -> local hour (0-23). Representative per zone (first participant seen wins).
    let localHours: [String: Int]
    /// ZoneId -> awake/working/asleep/outsideHours tag.
    let localViews: [String: LocalView]
    let totalDiscomfort: Double
    let standardDeviation: Double
    let hasDnd: Bool
    /// Lower is fairer & better.
    let rankScore: Double
    let label: SlotLabel

    init(
        id: UUID = UUID(),
        start: Date,
        localHours: [String: Int],
        localViews: [String: LocalView],
        totalDiscomfort: Double,
        standardDeviation: Double,
        hasDnd: Bool,
        rankScore: Double,
        label: SlotLabel
    ) {
        self.id = id
        self.start = start
        self.localHours = localHours
        self.localViews = localViews
        self.totalDiscomfort = totalDiscomfort
        self.standardDeviation = standardDeviation
        self.hasDnd = hasDnd
        self.rankScore = rankScore
        self.label = label
    }
}

// MARK: - MapStyle

enum MapStyle: String, CaseIterable, Codable, Sendable {
    case realistic
    case balanced
    case performance
    case vector
}

// MARK: - HourCycle

enum HourCycle: String, CaseIterable, Codable, Sendable {
    case system     = "system"
    case twelve     = "12h"
    case twentyFour = "24h"
}

// MARK: - InferenceSource

/// Where an assistant answer was actually computed. Defined here (not in
/// AiResult.swift) because `ChatMessage` below carries it and this file is also
/// compiled into the widget target.
enum InferenceSource: String, Codable, Sendable {
    /// Apple Foundation Models, fully on-device.
    case onDevice
    /// Gemini cloud (the only path that touches the network).
    case cloud
    /// The deterministic local rules engine — offline, no model involved.
    case rules
    /// Semantic cache hit — prior answer reused (<15 ms).
    case cached
}

// MARK: - ChatMessage

struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let isUser: Bool
    let text: String
    /// Where the answer was computed (`nil` for user/system messages that carry
    /// no provenance). Distinguishes on-device / cloud / local rules so the
    /// privacy badge is always truthful (Android: `ChatMessage.onDevice`).
    let source: InferenceSource?
    /// Marks a failed turn so the UI renders the error bubble
    /// (Android: `sender == "System Error"`).
    let isError: Bool
    let timestamp: Date

    init(
        id: UUID = UUID(),
        isUser: Bool,
        text: String,
        source: InferenceSource? = nil,
        isError: Bool = false,
        timestamp: Date
    ) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.source = source
        self.isError = isError
        self.timestamp = timestamp
    }
}

// MARK: - MeetingParticipant

/// A participant in a meeting search: a time zone plus that person's working window
/// and an optional do-not-disturb window. Defaults model a 9–17 worker with no DND.
struct MeetingParticipant: Sendable, Identifiable {
    let id: UUID
    let name: String
    let zoneId: String
    let workStartHour: Int
    let workEndHour: Int
    let dndStartHour: Int
    let dndEndHour: Int

    init(
        id: UUID = UUID(),
        name: String = "",
        zoneId: String,
        workStartHour: Int = 9,
        workEndHour: Int = 17,
        dndStartHour: Int = -1,
        dndEndHour: Int = -1
    ) {
        self.id = id
        self.name = name
        self.zoneId = zoneId
        self.workStartHour = workStartHour
        self.workEndHour = workEndHour
        self.dndStartHour = dndStartHour
        self.dndEndHour = dndEndHour
    }
}
