// ContactGrouping.swift
// Meridian — iOS 27 / Swift 6
//
// Groups meeting participants by their location (IANA zone) so the Plan screen can render
// "who is where" sections and so the overlap engine can reason about distinct locales.
// Pure, deterministic, Sendable — no I/O.

import Foundation

// MARK: - ParticipantGroup

/// A set of participants who all share the same IANA timezone, with a friendly label and
/// the live UTC offset (for sorting east→west and display).
struct ParticipantGroup: Identifiable, Sendable {
    /// Stable id — the IANA zone identifier.
    let id: String
    /// IANA zone identifier shared by every member, e.g. `"Asia/Tokyo"`.
    var zoneId: String { id }
    /// Human-readable location label, e.g. `"Tokyo"` (falls back to the zone id).
    let locationName: String
    /// Members of this group, preserving input order.
    let participants: [MeetingParticipant]
    /// Current offset from UTC in seconds for the group's zone (DST-aware at `referenceDate`).
    let utcOffsetSeconds: Int

    var memberCount: Int { participants.count }
}

// MARK: - ContactGrouping

/// Stateless utility that buckets participants by IANA zone.
enum ContactGrouping {

    /// Groups participants by their `zoneId`.
    ///
    /// Groups are returned sorted east-to-west (largest UTC offset first), which matches the
    /// Plan screen's left-to-right reading order; participants within a group keep their
    /// original relative order. Invalid / unknown zones are tolerated (offset 0).
    ///
    /// - Parameters:
    ///   - participants: The flat participant list.
    ///   - referenceDate: Instant used to resolve DST-correct offsets. Defaults to now.
    /// - Returns: Grouped participants, one ``ParticipantGroup`` per distinct zone.
    static func groupByLocation(
        _ participants: [MeetingParticipant],
        referenceDate: Date = Date()
    ) -> [ParticipantGroup] {
        guard !participants.isEmpty else { return [] }

        // Preserve first-seen order of zones while bucketing.
        var order: [String] = []
        var buckets: [String: [MeetingParticipant]] = [:]
        for participant in participants {
            if buckets[participant.zoneId] == nil {
                order.append(participant.zoneId)
            }
            buckets[participant.zoneId, default: []].append(participant)
        }

        let groups: [ParticipantGroup] = order.map { zoneId in
            let members = buckets[zoneId] ?? []
            let offset = TimeZone(identifier: zoneId)?.secondsFromGMT(for: referenceDate) ?? 0
            return ParticipantGroup(
                id: zoneId,
                locationName: Self.locationLabel(for: zoneId),
                participants: members,
                utcOffsetSeconds: offset
            )
        }

        // East → west: larger offset first; tie-break alphabetically by label for stability.
        return groups.sorted {
            if $0.utcOffsetSeconds != $1.utcOffsetSeconds {
                return $0.utcOffsetSeconds > $1.utcOffsetSeconds
            }
            return $0.locationName < $1.locationName
        }
    }

    /// The number of distinct locations represented in a participant list.
    static func distinctLocationCount(_ participants: [MeetingParticipant]) -> Int {
        Set(participants.map(\.zoneId)).count
    }

    // MARK: - Labels

    /// A friendly location label for a zone id. Prefers the curated ``PlaceIndex`` display
    /// name; otherwise derives the trailing path component (`"America/New_York"` → `"New York"`).
    @MainActor
    static func locationLabel(forKnown zoneId: String) -> String {
        if let entry = PlaceIndex.shared.entry(for: zoneId) {
            return entry.displayName
        }
        return deriveLabel(from: zoneId)
    }

    /// Nonisolated label derivation usable off the main actor (grouping runs on background
    /// work). Uses only the zone id string, so it never touches `PlaceIndex`.
    nonisolated static func locationLabel(for zoneId: String) -> String {
        deriveLabel(from: zoneId)
    }

    private nonisolated static func deriveLabel(from zoneId: String) -> String {
        guard let last = zoneId.split(separator: "/").last else { return zoneId }
        return last.replacingOccurrences(of: "_", with: " ")
    }
}
