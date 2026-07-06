// ParticipantGrouping.swift
// Meridian — iOS 27 / Swift 6
//
// Pure, deterministic model layer for the Plan screen's participant selection. Direct
// behavioral port of the grouping/consolidation helpers in Android `PlannerComponents.kt`:
//
//   - plannerParticipantPool        favorite non-home cities + favorite contacts
//   - buildParticipantLocationGroups one row per zone (city + its matched people), then
//                                    consolidated so two cities sharing an IANA zone merge
//   - visiblePlannerGroups          hide a city pill that only duplicates the local "You" chip
//   - buildMeetingParticipants      collapse selected zones/people into `[MeetingParticipant]`
//                                    intersecting work windows and unioning DND per zone
//   - buildSelectedParticipantLabels render labels for the SlotCard's participant tags
//
// `PlannerParticipant` (the SwiftUI-friendly wrapper) and `PlannerSlot` are gone — the screen
// computes `[MeetingSlot]` directly via `MainViewModel.computeMeetingSlots` (no UTC baking) and
// renders each slot time in the relevant LOCAL zone.

import Foundation

// MARK: - PlannerParticipantPool

/// Favorite pinned cities (not the residence/home anchor) and favorite contacts offered on the
/// Plan screen. Mirrors Android `PlannerParticipantPool`.
// Holds SwiftData `@Model` values (`SavedZone`/`Person`), which are non-`Sendable` and used
// only on the main actor by the Plan screen, so this wrapper is intentionally not `Sendable`.
struct PlannerParticipantPool {
    let zones: [SavedZone]
    let people: [Person]
}

// MARK: - ParticipantSlotLabel

/// Label rendered against a slot for one zone: the location plus any selected contact names.
/// Mirrors Android `ParticipantSlotLabel`.
struct ParticipantSlotLabel: Identifiable, Sendable, Equatable {
    let zoneId: String
    let locationLabel: String
    let names: [String]

    var id: String { zoneId }

    init(zoneId: String, locationLabel: String, names: [String] = []) {
        self.zoneId = zoneId
        self.locationLabel = locationLabel
        self.names = names
    }

    /// "Alice, Bob · Tokyo" when names exist, else just the location label.
    func displayWho() -> String {
        names.isEmpty ? locationLabel : "\(names.joined(separator: ", ")) · \(locationLabel)"
    }
}

// MARK: - ParticipantLocationGroup

/// One selectable row in the Participants card: an IANA zone, a display name, an optional backing
/// `SavedZone` (city pin), and the contacts that live there. Mirrors Android
/// `ParticipantLocationGroup`. People are referenced by their stable `UUID`.
struct ParticipantLocationGroup: Identifiable, Sendable {
    let zoneId: String
    let displayName: String
    /// The id of the backing pinned city, or `nil` for a people-only group.
    let savedZoneId: String?
    /// Stable ids of the contacts in this group, in input order.
    let peopleIds: [UUID]
    /// Snapshot of the people (kept for label/chip rendering off the @Model objects).
    let people: [PersonRef]

    var id: String { "\(zoneId)\u{001F}\(displayName)" }

    init(
        zoneId: String,
        displayName: String,
        savedZoneId: String?,
        people: [PersonRef]
    ) {
        self.zoneId = zoneId
        self.displayName = displayName
        self.savedZoneId = savedZoneId
        self.peopleIds = people.map(\.id)
        self.people = people
    }
}

/// A `Sendable` value snapshot of the parts of a `Person` the planner UI needs — avoids passing
/// the SwiftData `@Model` reference type through value-type grouping structs.
struct PersonRef: Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let zoneId: String
    let displayLocation: String
    let workStartHour: Int
    let workEndHour: Int
    let dndStartHour: Int
    let dndEndHour: Int

    init(_ person: Person) {
        self.id = person.id
        self.name = person.name
        self.zoneId = person.tzId
        self.displayLocation = person.displayLocation()
        self.workStartHour = person.workStartHour
        self.workEndHour = person.workEndHour
        self.dndStartHour = person.dndStartHour
        self.dndEndHour = person.dndEndHour
    }

    /// Chip label: the contact name, or the location when nameless. Mirrors `personChipLabel`.
    var chipLabel: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? displayLocation : name
    }
}

// MARK: - ParticipantGrouping (stateless)

enum ParticipantGrouping {

    /// Favorite pinned cities (excluding the residence/home anchor and the local zone) and
    /// favorite contacts. Mirrors Android `plannerParticipantPool`.
    static func plannerParticipantPool(
        savedZones: [SavedZone],
        people: [Person],
        localZoneId: String
    ) -> PlannerParticipantPool {
        PlannerParticipantPool(
            zones: savedZones.filter { $0.isFavorite && !$0.isHome && $0.id != localZoneId },
            people: people.filter { $0.isFavorite }
        )
    }

    /// Builds one group per pinned city (with the contacts that match it), then folds in any
    /// remaining contacts grouped by zone+location, and finally consolidates groups that share an
    /// IANA zone into a single row. Mirrors Android `buildParticipantLocationGroups`.
    static func buildParticipantLocationGroups(
        zones: [SavedZone],
        people: [Person]
    ) -> [ParticipantLocationGroup] {
        let refs = people.map(PersonRef.init)

        var assignedIds = Set<UUID>()
        var raw: [ParticipantLocationGroup] = zones.map { zone in
            let matched = refs.filter { ref in
                ref.zoneId == zone.id &&
                    ref.displayLocation.caseInsensitiveCompare(zone.displayName) == .orderedSame
            }
            assignedIds.formUnion(matched.map(\.id))
            return ParticipantLocationGroup(
                zoneId: zone.id,
                displayName: zone.displayName,
                savedZoneId: zone.id,
                people: matched
            )
        }

        // Remaining (un-matched) contacts grouped by zone + location label, first-seen order.
        var orphanOrder: [String] = []
        var orphanBuckets: [String: [PersonRef]] = [:]
        for ref in refs where !assignedIds.contains(ref.id) {
            let key = locationKey(zoneId: ref.zoneId, displayName: ref.displayLocation)
            if orphanBuckets[key] == nil { orphanOrder.append(key) }
            orphanBuckets[key, default: []].append(ref)
        }
        for key in orphanOrder {
            guard let groupPeople = orphanBuckets[key], let first = groupPeople.first else { continue }
            raw.append(
                ParticipantLocationGroup(
                    zoneId: first.zoneId,
                    displayName: first.displayLocation,
                    savedZoneId: nil,
                    people: groupPeople
                )
            )
        }

        return consolidateByTimeZone(raw)
    }

    /// One row per IANA zone so e.g. Denver + El Paso (both America/Denver) collapse into a single
    /// pill. Mirrors Android `consolidateParticipantGroupsByTimeZone`.
    private static func consolidateByTimeZone(
        _ groups: [ParticipantLocationGroup]
    ) -> [ParticipantLocationGroup] {
        var order: [String] = []
        var byZone: [String: [ParticipantLocationGroup]] = [:]
        for group in groups {
            if byZone[group.zoneId] == nil { order.append(group.zoneId) }
            byZone[group.zoneId, default: []].append(group)
        }

        return order.map { zoneId in
            let zoneGroups = byZone[zoneId] ?? []
            if zoneGroups.count == 1 { return zoneGroups[0] }

            let cities = mergedCityNames(zoneGroups)
            // Distinct people by id, preserving order.
            var seen = Set<UUID>()
            var mergedPeople: [PersonRef] = []
            for group in zoneGroups {
                for person in group.people where seen.insert(person.id).inserted {
                    mergedPeople.append(person)
                }
            }
            let savedZoneId = zoneGroups.compactMap(\.savedZoneId).first
            return ParticipantLocationGroup(
                zoneId: zoneGroups[0].zoneId,
                displayName: cities.joined(separator: ", "),
                savedZoneId: savedZoneId,
                people: mergedPeople
            )
        }
    }

    private static func mergedCityNames(_ groups: [ParticipantLocationGroup]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for group in groups {
            for raw in group.displayName.split(separator: ",") {
                let city = raw.trimmingCharacters(in: .whitespaces)
                guard !city.isEmpty else { continue }
                if seen.insert(city.lowercased()).inserted { names.append(city) }
            }
        }
        return names.sorted { $0.lowercased() < $1.lowercased() }
    }

    /// Hide a redundant city pill when it only duplicates the local "You" chip — i.e. a group on
    /// the local zone with no contacts of its own. Mirrors Android `visiblePlannerGroups`.
    static func visiblePlannerGroups(
        _ groups: [ParticipantLocationGroup],
        localZoneId: String
    ) -> [ParticipantLocationGroup] {
        groups.filter { $0.zoneId != localZoneId || !$0.people.isEmpty }
    }

    static func locationKey(zoneId: String, displayName: String) -> String {
        "\(zoneId)::\(displayName.lowercased())"
    }

    // MARK: - Selection state helpers

    /// True when every member of the group (its city pin and all its people) is selected.
    /// Mirrors Android `isGroupFullySelected`.
    static func isGroupFullySelected(
        _ group: ParticipantLocationGroup,
        selectedZones: [String: Bool],
        selectedPeople: [UUID: Bool]
    ) -> Bool {
        if group.people.isEmpty {
            return group.savedZoneId.map { selectedZones[$0] == true } ?? false
        }
        if let zoneId = group.savedZoneId {
            return selectedZones[zoneId] == true &&
                group.people.allSatisfy { selectedPeople[$0.id] == true }
        }
        return group.people.allSatisfy { selectedPeople[$0.id] == true }
    }

    /// True when any member of the group is selected. Mirrors Android `isGroupSelected`.
    static func isGroupSelected(
        _ group: ParticipantLocationGroup,
        selectedZones: [String: Bool],
        selectedPeople: [UUID: Bool]
    ) -> Bool {
        let zoneOn = group.savedZoneId.map { selectedZones[$0] == true } ?? false
        if group.people.isEmpty { return zoneOn }
        let peopleOn = group.people.contains { selectedPeople[$0.id] == true }
        return zoneOn || peopleOn
    }

    /// Chip label for a group: contact names joined with the location. Mirrors `groupChipLabel`.
    static func groupChipLabel(_ group: ParticipantLocationGroup) -> String {
        let names = group.people.map(\.chipLabel)
        switch names.count {
        case 0:  return group.displayName
        case 1:  return "\(names[0]) · \(group.displayName)"
        default: return "\(names.joined(separator: ", ")) · \(group.displayName)"
        }
    }

    // MARK: - Compute inputs

    /// Collapses the active zones/people into `[MeetingParticipant]` — exactly one per IANA zone,
    /// always including the local zone first — intersecting work windows and unioning DND windows
    /// when several people share a zone. Mirrors Android `buildMeetingParticipants`.
    static func buildMeetingParticipants(
        localZoneId: String,
        groups: [ParticipantLocationGroup],
        selectedZones: [String: Bool],
        selectedPeople: [UUID: Bool]
    ) -> [MeetingParticipant] {
        var order: [String] = [localZoneId]
        var byZone: [String: MeetingParticipant] = [localZoneId: MeetingParticipant(zoneId: localZoneId)]

        for group in groups {
            let zoneActive = group.savedZoneId.map { selectedZones[$0] == true } ?? false
            let activePeople = group.people.filter { selectedPeople[$0.id] == true }
            if !zoneActive && activePeople.isEmpty { continue }

            let candidate: MeetingParticipant = activePeople.isEmpty
                ? MeetingParticipant(zoneId: group.zoneId)
                : participantFromPeople(activePeople)

            if byZone[group.zoneId] == nil { order.append(group.zoneId) }
            byZone[group.zoneId] = merge(byZone[group.zoneId], candidate)
        }

        return order.compactMap { byZone[$0] }
    }

    private static func participantFromPeople(_ people: [PersonRef]) -> MeetingParticipant {
        let zoneId = people[0].zoneId
        let work = WorkHourWindows.intersectWorkWindows(
            people.map { (start: $0.workStartHour, end: $0.workEndHour) }
        )
        let dnd = WorkHourWindows.unionDndWindows(
            people.compactMap { person -> (start: Int, end: Int)? in
                (0...23).contains(person.dndStartHour) && (0...23).contains(person.dndEndHour)
                    ? (start: person.dndStartHour, end: person.dndEndHour) : nil
            }
        )
        return MeetingParticipant(
            zoneId: zoneId,
            workStartHour: work.start,
            workEndHour: work.end,
            dndStartHour: dnd.start,
            dndEndHour: dnd.end
        )
    }

    private static func merge(
        _ existing: MeetingParticipant?,
        _ next: MeetingParticipant
    ) -> MeetingParticipant {
        guard let existing else { return next }
        let work = WorkHourWindows.intersectWorkWindows([
            (start: existing.workStartHour, end: existing.workEndHour),
            (start: next.workStartHour, end: next.workEndHour),
        ])
        let dndWindows: [(start: Int, end: Int)] = [
            (start: existing.dndStartHour, end: existing.dndEndHour),
            (start: next.dndStartHour, end: next.dndEndHour),
        ].filter { (0...23).contains($0.start) && (0...23).contains($0.end) }
        let dnd = WorkHourWindows.unionDndWindows(dndWindows)
        return MeetingParticipant(
            zoneId: next.zoneId,
            workStartHour: work.start,
            workEndHour: work.end,
            dndStartHour: dnd.start,
            dndEndHour: dnd.end
        )
    }

    /// Builds the per-zone labels (with selected contact names) for the SlotCard tags, always
    /// leading with the local "You · <city>" row. Mirrors Android `buildSelectedParticipantLabels`.
    static func buildSelectedParticipantLabels(
        localZoneId: String,
        localLocationName: String,
        groups: [ParticipantLocationGroup],
        selectedZones: [String: Bool],
        selectedPeople: [UUID: Bool]
    ) -> [ParticipantSlotLabel] {
        var labels: [ParticipantSlotLabel] = [
            ParticipantSlotLabel(zoneId: localZoneId, locationLabel: "You · \(localLocationName)")
        ]
        var seenZones: Set<String> = [localZoneId]

        for group in groups {
            let zoneActive = group.savedZoneId.map { selectedZones[$0] == true } ?? false
            let activeNames = group.people
                .filter { selectedPeople[$0.id] == true }
                .map(\.chipLabel)
            if !zoneActive && activeNames.isEmpty { continue }
            // Zone-only row duplicating the local "You" chip.
            if group.zoneId == localZoneId && activeNames.isEmpty { continue }
            guard seenZones.insert(group.zoneId).inserted else { continue }

            labels.append(
                ParticipantSlotLabel(
                    zoneId: group.zoneId,
                    locationLabel: group.displayName,
                    names: activeNames
                )
            )
        }
        return labels
    }
}
