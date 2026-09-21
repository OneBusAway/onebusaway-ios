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

    @Test func `Boundaries closer than the minimum spacing are deferred to it, not dropped`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [minutes(3), minutes(10), minutes(12), minutes(20)], now: now)

        // +3 is within 5 min of `now`, so its entry waits until +5.
        // +12 is within 5 min of +10, so its entry waits until +15.
        #expect(plan.entryDates == [now, minutes(5), minutes(10), minutes(15), minutes(20)])
    }

    /// The defect this rule fixes: dropping close boundaries left buses that
    /// had departed at +3 and +4 on screen until the +25 entry.
    @Test func `A burst followed by a long gap still clears the departed buses`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [minutes(3), minutes(4), minutes(25)], now: now)

        // One deferred entry at +5 covers both +3 and +4.
        #expect(plan.entryDates == [now, minutes(5), minutes(25)])
    }

    @Test func `A deferred entry that would land at or after the reload is left to the reload`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [minutes(27), minutes(28)], now: now)

        // +28 would defer to +32, past the +30 reload.
        #expect(plan.entryDates == [now, minutes(27)])
        #expect(plan.reloadDate == minutes(30))
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

    // MARK: - departures(_:visibleAt:)

    // The suite's fixed `now` is in 2023, so departures anchored on it have all
    // gone. Nothing under test reads the clock — both the planner and the slice
    // take their reference date as a parameter — but a departed bus is a poor
    // stand-in for one a widget would show, so these anchor on the present.
    // Whole seconds, because `Fixtures.arrivalDeparture` takes integer
    // timestamps and its `.deferredToDate` decode reads them as seconds since
    // the 2001 reference date (see its doc comment).
    private let upcomingNow = Date(timeIntervalSinceReferenceDate: Double(Int(Date.timeIntervalSinceReferenceDate)))
    private func upcoming(_ value: Double) -> Date { upcomingNow.addingTimeInterval(value * 60) }

    private func departure(at date: Date, tripID: String) throws -> ArrivalDeparture {
        let seconds = Int(date.timeIntervalSinceReferenceDate)
        return try Fixtures.arrivalDeparture(scheduledArrival: seconds, scheduledDeparture: seconds, tripID: tripID)
    }

    /// The off-by-one this function exists to prevent: an undeferred entry is
    /// dated exactly at a departure, and it exists to take that bus off screen.
    @Test func `A departure at the entry date is dropped, one second later is kept`() throws {
        let entryDate = upcoming(10)
        let before = try departure(at: entryDate.addingTimeInterval(-1), tripID: "trip_before")
        let at = try departure(at: entryDate, tripID: "trip_at")
        let after = try departure(at: entryDate.addingTimeInterval(1), tripID: "trip_after")

        let visible = WidgetTimelinePlanner.departures([before, at, after], visibleAt: entryDate)

        #expect(visible.map(\.tripID) == ["trip_after"])
    }

    @Test func `Slicing preserves the input order`() throws {
        let later = try departure(at: upcoming(25), tripID: "trip_later")
        let soonest = try departure(at: upcoming(11), tripID: "trip_soonest")
        let soon = try departure(at: upcoming(15), tripID: "trip_soon")

        let visible = WidgetTimelinePlanner.departures([later, soonest, soon], visibleAt: upcoming(10))

        #expect(visible.map(\.tripID) == ["trip_later", "trip_soonest", "trip_soon"])
    }

    /// End to end: the +10 entry exists because the +10 bus leaves then, so
    /// that entry must not still be showing it.
    @Test func `The entry at a departure's own date no longer shows that departure`() throws {
        let departures = [
            try departure(at: upcoming(10), tripID: "trip_10"),
            try departure(at: upcoming(25), tripID: "trip_25")
        ]

        let plan = WidgetTimelinePlanner().plan(departureDates: departures.map(\.arrivalDepartureDate), now: upcomingNow)
        #expect(plan.entryDates == [upcomingNow, upcoming(10), upcoming(25)])

        #expect(WidgetTimelinePlanner.departures(departures, visibleAt: plan.entryDates[0]).map(\.tripID) == ["trip_10", "trip_25"])
        #expect(WidgetTimelinePlanner.departures(departures, visibleAt: plan.entryDates[1]).map(\.tripID) == ["trip_25"])
    }
}
