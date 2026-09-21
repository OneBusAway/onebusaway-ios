//
//  WidgetTimelinePlannerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite struct WidgetTimelinePlannerTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func minutes(_ value: Double) -> Date { now.addingTimeInterval(value * 60) }

    @Test func `No departures is one entry and a sixty minute reload`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [], now: now)

        #expect(plan.entryDates == [now])
        #expect(plan.reloadDate == minutes(60))
    }

    @Test func `With departures the reload is thirty minutes out`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [minutes(10)], now: now)
        #expect(plan.reloadDate == minutes(30))
    }

    /// The defect this type exists to prevent.
    @Test func `An imminent departure does not pull the reload date in`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [minutes(1), minutes(4), minutes(7)], now: now)
        #expect(plan.reloadDate == minutes(30))
    }

    @Test func `Unspaced, every departure before the reload is an entry boundary`() {
        let planner = WidgetTimelinePlanner(minimumEntrySpacing: 0)
        let plan = planner.plan(departureDates: [minutes(12), minutes(3), minutes(10)], now: now)

        #expect(plan.entryDates == [now, minutes(3), minutes(10), minutes(12)])
    }

    @Test func `Boundaries closer than the minimum spacing are coalesced`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [minutes(3), minutes(10), minutes(12), minutes(20)], now: now)

        // +3 is within 5 min of `now`; +12 is within 5 min of +10.
        #expect(plan.entryDates == [now, minutes(10), minutes(20)])
    }

    @Test func `Departures at or after the reload date add no entries`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [minutes(30), minutes(45)], now: now)
        #expect(plan.entryDates == [now])
        #expect(plan.reloadDate == minutes(30))
    }

    @Test func `Past departures are ignored, including for the reload interval`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [minutes(-5)], now: now)

        #expect(plan.entryDates == [now])
        #expect(plan.reloadDate == minutes(60))
    }

    @Test func `Duplicate departure dates produce one boundary`() {
        let planner = WidgetTimelinePlanner(minimumEntrySpacing: 0)
        let plan = planner.plan(departureDates: [minutes(8), minutes(8)], now: now)
        #expect(plan.entryDates == [now, minutes(8)])
    }

    @Test func `Entries are capped`() {
        let planner = WidgetTimelinePlanner(minimumEntrySpacing: 0, maximumEntries: 3)
        let plan = planner.plan(departureDates: (1...20).map { minutes(Double($0)) }, now: now)

        #expect(plan.entryDates == [now, minutes(1), minutes(2)])
    }

    @Test func `A full day of reloads stays inside the WidgetKit budget`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [minutes(10)], now: now)
        let reloadsPerDay = (18 * 60 * 60) / plan.reloadDate.timeIntervalSince(now)
        #expect(reloadsPerDay <= 40)
    }
}
