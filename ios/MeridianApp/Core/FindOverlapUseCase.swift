// FindOverlapUseCase.swift
// Meridian — iOS 27 / Swift 6
//
// Finds and ranks fair meeting slots across participants in different time zones.
// Direct behavioral port of Android `FindOverlapUseCase`. Uses MeetingParticipant,
// MeetingSlot, SlotLabel, and LocalView (canonical types in Models.swift / LocalView.swift).
//
// Scoring (must match Android exactly):
//   discomfortFor(hour): 8.0 if in DND; 0.0 if in work window; else by circular distance
//     outside the window: 0..2h -> 1.5, 3..4h -> 3.0, else -> 6.0.
//   totalDiscomfort = sum of per-participant discomfort.
//   standardDeviation = POPULATION std dev of the discomfort list (divide by n).
//   rankScore = totalDiscomfort * 10 + standardDeviation + (anyDnd ? 1000 : 0).
//   label: anyDnd -> .difficult; sum <= n*1.5 -> .optimal; else .fair.
//   Slots are sorted ascending by rankScore (lower is fairer & better).

import Foundation

/// Pure, stateless use-case that finds candidate meeting slots for a set of
/// participants spread across different time zones.
struct FindOverlapUseCase: Sendable {

    init() {}

    // MARK: - Public API

    /// Zone-only convenience: ranks slots treating every zone as a default 9–17 worker.
    /// Mirrors Android `calculateBestOverlapSlots`.
    func calculateBestOverlapSlots(
        baseDate: Date,
        participantZones: [String]
    ) -> [MeetingSlot] {
        rankParticipantSlots(
            baseDate: baseDate,
            participants: participantZones.map { MeetingParticipant(zoneId: $0) }
        )
    }

    /// Finds and ranks 24 hourly meeting slots over the day starting at `baseDate`,
    /// scoring each participant against their own working/DND window.
    /// Lower `rankScore` == fairer. Mirrors Android `rankParticipantSlots`.
    func rankParticipantSlots(
        baseDate: Date,
        participants: [MeetingParticipant]
    ) -> [MeetingSlot] {
        guard !participants.isEmpty else { return [] }

        // Android: baseDateInstant.truncatedTo(ChronoUnit.HOURS) — floor to the top of the hour.
        let startOfWindow = floorToHour(baseDate)

        var results: [MeetingSlot] = []
        results.reserveCapacity(24)

        for hourOffset in 0..<24 {
            let slotInstant = startOfWindow.addingTimeInterval(Double(hourOffset) * 3600.0)

            var localHours: [String: Int] = [:]
            var localViews: [String: LocalView] = [:]
            var distressList: [Double] = []
            distressList.reserveCapacity(participants.count)
            var isAnyDnd = false

            for participant in participants {
                let hour = localHour(at: slotInstant, in: participant.zoneId)
                let distress = discomfortFor(hour: hour, participant)
                distressList.append(distress)
                if inDndWindow(hour: hour, participant) { isAnyDnd = true }

                // Representative view per zone (first participant seen for that zone wins).
                if localViews[participant.zoneId] == nil {
                    localHours[participant.zoneId] = hour
                    localViews[participant.zoneId] = viewFor(hour: hour, participant)
                }
            }

            let n = Double(distressList.count)
            let sum = distressList.reduce(0.0, +)
            let mean = sum / n
            let variance = distressList.reduce(0.0) { acc, value in
                let delta = value - mean
                return acc + delta * delta
            } / n
            let stdDev = variance.squareRoot()

            let label: SlotLabel
            if isAnyDnd {
                label = .difficult
            } else if sum <= n * 1.5 {
                label = .optimal
            } else {
                label = .fair
            }

            let dndPenalty = isAnyDnd ? 1000.0 : 0.0
            let rankScore = sum * 10.0 + stdDev + dndPenalty

            results.append(
                MeetingSlot(
                    start: slotInstant,
                    localHours: localHours,
                    localViews: localViews,
                    totalDiscomfort: sum,
                    standardDeviation: stdDev,
                    hasDnd: isAnyDnd,
                    rankScore: rankScore,
                    label: label
                )
            )
        }

        return results.sorted { $0.rankScore < $1.rankScore }
    }

    // MARK: - Scoring (private, mirrors Android)

    /// Discomfort cost of a local `hour`: 0 inside the working window, rising with distance.
    private func discomfortFor(hour: Int, _ p: MeetingParticipant) -> Double {
        if inDndWindow(hour: hour, p) { return 8.0 }
        if inWindow(hour: hour, start: p.workStartHour, end: p.workEndHour) { return 0.0 }
        switch hoursOutsideWindow(hour: hour, start: p.workStartHour, end: p.workEndHour) {
        case 0...2: return 1.5
        case 3...4: return 3.0
        default:    return 6.0
        }
    }

    private func viewFor(hour: Int, _ p: MeetingParticipant) -> LocalView {
        if inDndWindow(hour: hour, p) { return .asleep }
        if inWindow(hour: hour, start: p.workStartHour, end: p.workEndHour) { return .working }
        let outside = hoursOutsideWindow(hour: hour, start: p.workStartHour, end: p.workEndHour)
        if outside <= 2 { return .awake }
        if outside <= 4 { return .outsideHours }
        return .asleep
    }

    private func inDndWindow(hour: Int, _ p: MeetingParticipant) -> Bool {
        (0...23).contains(p.dndStartHour) &&
            (0...23).contains(p.dndEndHour) &&
            inWindow(hour: hour, start: p.dndStartHour, end: p.dndEndHour)
    }

    /// True if `hour` falls in `[start, end)`; supports windows that wrap past midnight.
    private func inWindow(hour: Int, start: Int, end: Int) -> Bool {
        if start < 0 || end < 0 || start == end { return false }
        if start < end {
            return hour >= start && hour < end
        } else {
            return hour >= start || hour < end
        }
    }

    /// Circular distance in hours from `hour` to the nearest edge of the working window.
    private func hoursOutsideWindow(hour: Int, start: Int, end: Int) -> Int {
        if inWindow(hour: hour, start: start, end: end) { return 0 }
        let lastWorkingHour = (end + 23) % 24 // end is exclusive
        return min(circularDistance(hour, start), circularDistance(hour, lastWorkingHour))
    }

    private func circularDistance(_ a: Int, _ b: Int) -> Int {
        let diff = ((a - b) % 24 + 24) % 24
        return min(diff, 24 - diff)
    }

    // MARK: - Time helpers

    /// Floors a `Date` to the top of its UTC hour (Android: truncatedTo(HOURS)).
    private func floorToHour(_ date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        let floored = (seconds / 3600.0).rounded(.down) * 3600.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }

    /// Local hour (0–23) at a given absolute instant for an IANA time-zone identifier.
    /// Falls back to UTC when the identifier is unrecognized.
    private func localHour(at date: Date, in tzId: String) -> Int {
        let tz = TimeZone(identifier: tzId) ?? TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.component(.hour, from: date)
    }
}
