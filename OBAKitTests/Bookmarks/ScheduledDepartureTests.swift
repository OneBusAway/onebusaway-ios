//
//  ScheduledDepartureTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// `minutes(from:)` is what a timetable row's countdown runs on: computed from
/// the timeline's date, so the row's inputs change on every tick instead of
/// being frozen at the minute the row was built.
@Suite(.serialized)
struct ScheduledDepartureTests {

    private func departure(at interval: TimeInterval, from date: Date) -> ScheduledDeparture {
        ScheduledDeparture(tripID: "t", routeID: "r", tripHeadsign: "h", route: nil, date: date.addingTimeInterval(interval))
    }

    @Test func `Minutes are counted from the date passed in`() {
        let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
        // 90 seconds out is the minute in progress: 1, not 2.
        #expect(departure(at: 90, from: date).minutes(from: date) == 1)
        #expect(departure(at: 0, from: date).minutes(from: date) == 0)
        // 30 seconds past still reads as 0, and 90 seconds past as -1, the
        // way ArrivalDeparture.arrivalDepartureMinutes reads.
        #expect(departure(at: -30, from: date).minutes(from: date) == 0)
        #expect(departure(at: -90, from: date).minutes(from: date) == -1)
    }

    @Test func `Minutes from a later date are fewer`() {
        let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let row = departure(at: 900, from: date)

        #expect(row.minutes(from: date) == 15)
        // The same row, ticked ten minutes on: it counts down.
        #expect(row.minutes(from: date.addingTimeInterval(10 * 60)) == 5)
    }
}
