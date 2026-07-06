// FindOverlapUseCaseTests.swift
// Meridian — iOS unit tests
//
// Port of app/src/test/java/com/example/FindOverlapUseCaseTest.kt. Locks in behavioral
// parity for the meeting-overlap ranking algorithm (the Planner's signature feature):
// 24 ranked hourly slots, ascending fairness, working-hours preference, and full
// per-participant annotation.

import XCTest
@testable import Meridian

final class FindOverlapUseCaseTests: XCTestCase {

    private let useCase = FindOverlapUseCase()

    private func instant(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: iso)!
    }

    func testReturnsTwentyFourSlotsSortedByFairness() {
        let slots = useCase.calculateBestOverlapSlots(
            baseDate: instant("2026-06-16T00:00:00Z"),
            participantZones: ["UTC", "Asia/Tokyo"]
        )
        XCTAssertEqual(slots.count, 24)
        for i in 0..<(slots.count - 1) {
            XCTAssertLessThanOrEqual(slots[i].rankScore, slots[i + 1].rankScore)
        }
    }

    func testBestSlotForSingleZoneFallsInWorkingHours() {
        let slots = useCase.calculateBestOverlapSlots(
            baseDate: instant("2026-06-16T00:00:00Z"),
            participantZones: ["UTC"]
        )
        let best = try! XCTUnwrap(slots.first)
        let hour = try! XCTUnwrap(best.localHours["UTC"])
        XCTAssertTrue((9...16).contains(hour), "best hour was \(hour)")
        XCTAssertEqual(best.localViews["UTC"], .working)
    }

    func testEverySlotAnnotatesEveryParticipant() {
        let zones = ["Europe/London", "America/New_York"]
        let slots = useCase.calculateBestOverlapSlots(
            baseDate: instant("2026-06-16T00:00:00Z"),
            participantZones: zones
        )
        for slot in slots {
            for tz in zones {
                XCTAssertNotNil(slot.localHours[tz])
                XCTAssertNotNil(slot.localViews[tz])
            }
        }
    }

    func testEmptyParticipantsYieldNoSlots() {
        let slots = useCase.calculateBestOverlapSlots(
            baseDate: instant("2026-06-16T00:00:00Z"),
            participantZones: []
        )
        XCTAssertTrue(slots.isEmpty)
    }
}
