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

    @Test func `Negative minimum entry spacing is clamped to zero`() {
        let planner = WidgetTimelinePlanner(minimumEntrySpacing: -60)
        let plan = planner.plan(departureDates: [minutes(3), minutes(10), minutes(12)], now: now)

        #expect(plan.entryDates == [now, minutes(3), minutes(10), minutes(12)])
    }

    @Test func `Non-positive maximum entries is clamped to one`() {
        let zeroPlanner = WidgetTimelinePlanner(maximumEntries: 0)
        let zeroPlan = zeroPlanner.plan(departureDates: [minutes(5), minutes(10)], now: now)
        #expect(zeroPlan.entryDates == [now])

        let negPlanner = WidgetTimelinePlanner(maximumEntries: -3)
        let negPlan = negPlanner.plan(departureDates: [minutes(5), minutes(10)], now: now)
        #expect(negPlan.entryDates == [now])
    }

    @Test func `Entry dates are strictly monotonically increasing`() {
        let densePlanner = WidgetTimelinePlanner(minimumEntrySpacing: 5 * 60)
        let plan = densePlanner.plan(departureDates: (1...50).map { minutes(Double($0) * 0.5) }, now: now)

        #expect(plan.entryDates.count > 1)
        for i in 1..<plan.entryDates.count {
            #expect(plan.entryDates[i] > plan.entryDates[i - 1])
        }
    }

    @Test func `Strict monotonicity holds across simultaneous bursts, duplicates, zero spacing, and large spacing`() {
        let burstDates: [Date] = [
            minutes(2), minutes(2), minutes(2),
            minutes(2.5),
            minutes(5), minutes(5),
            minutes(5.001),
            minutes(7),
            minutes(7),
            minutes(12),
            minutes(12),
            minutes(28),
            minutes(28),
            minutes(29.999)
        ]

        let planners = [
            WidgetTimelinePlanner(minimumEntrySpacing: 0),
            WidgetTimelinePlanner(minimumEntrySpacing: 1),
            WidgetTimelinePlanner(minimumEntrySpacing: 5 * 60),
            WidgetTimelinePlanner(minimumEntrySpacing: 15 * 60),
            WidgetTimelinePlanner(minimumEntrySpacing: 60 * 60)
        ]

        for planner in planners {
            let plan = planner.plan(departureDates: burstDates, now: now)
            #expect(zip(plan.entryDates, plan.entryDates.dropFirst()).allSatisfy { $0 < $1 })
            #expect(plan.reloadDate > plan.entryDates.last!)
        }

        let largeGaps = [minutes(1), minutes(200), minutes(500), minutes(10_000)]
        for planner in planners {
            let plan = planner.plan(departureDates: largeGaps, now: now)
            #expect(zip(plan.entryDates, plan.entryDates.dropFirst()).allSatisfy { $0 < $1 })
            #expect(plan.reloadDate > plan.entryDates.last!)
        }

        let pastDates = [minutes(-100), minutes(-10), minutes(0)]
        for planner in planners {
            let plan = planner.plan(departureDates: pastDates, now: now)
            #expect(plan.entryDates == [now])
            #expect(plan.reloadDate > now)
        }
    }

    @Test func `Midnight and day rollover produces strictly monotonic entries and rolls reload date into next day`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let nowComponents = DateComponents(year: 2026, month: 10, day: 15, hour: 23, minute: 55, second: 0)
        let testNow = try #require(calendar.date(from: nowComponents))

        let dep1 = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 23, minute: 58, second: 0)))
        let dep2 = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 0, minute: 3, second: 0)))
        let dep3 = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 0, minute: 10, second: 0)))
        let dep4 = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 0, minute: 20, second: 0)))

        let expectedEntry0 = testNow
        let expectedEntry1 = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 0, minute: 0, second: 0)))
        let expectedEntry2 = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 0, minute: 5, second: 0)))
        let expectedEntry3 = dep3
        let expectedEntry4 = dep4
        let expectedReload = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 0, minute: 25, second: 0)))

        let departuresList = [
            try departure(at: dep1, tripID: "day1_2358"),
            try departure(at: dep2, tripID: "day2_0003"),
            try departure(at: dep3, tripID: "day2_0010"),
            try departure(at: dep4, tripID: "day2_0020")
        ]

        let plan = WidgetTimelinePlanner().plan(departureDates: departuresList.map(\.arrivalDepartureDate), now: testNow)

        #expect(plan.entryDates == [expectedEntry0, expectedEntry1, expectedEntry2, expectedEntry3, expectedEntry4])
        #expect(plan.reloadDate == expectedReload)
        #expect(calendar.component(.day, from: plan.reloadDate) == 16)

        #expect(zip(plan.entryDates, plan.entryDates.dropFirst()).allSatisfy { $0 < $1 })

        let visibleAtNow = WidgetTimelinePlanner.departures(departuresList, visibleAt: plan.entryDates[0])
        #expect(visibleAtNow.map(\.tripID) == ["day1_2358", "day2_0003", "day2_0010", "day2_0020"])

        let visibleAtMidnight = WidgetTimelinePlanner.departures(departuresList, visibleAt: plan.entryDates[1])
        #expect(visibleAtMidnight.map(\.tripID) == ["day2_0003", "day2_0010", "day2_0020"])

        let visibleAt0005 = WidgetTimelinePlanner.departures(departuresList, visibleAt: plan.entryDates[2])
        #expect(visibleAt0005.map(\.tripID) == ["day2_0010", "day2_0020"])

        let visibleAt0010 = WidgetTimelinePlanner.departures(departuresList, visibleAt: plan.entryDates[3])
        #expect(visibleAt0010.map(\.tripID) == ["day2_0020"])

        let visibleAt0020 = WidgetTimelinePlanner.departures(departuresList, visibleAt: plan.entryDates[4])
        #expect(visibleAt0020.isEmpty)
    }

    @Test func `DST spring forward transition maintains strictly monotonic entries and proper elapsed spacing across wall clock gap`() throws {
        var calendar = Calendar(identifier: .gregorian)
        let tz = try #require(TimeZone(identifier: "America/New_York"))
        calendar.timeZone = tz

        let testNow = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 50, second: 0)))
        let dep1 = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 55, second: 0)))
        let dep2 = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 5, second: 0)))
        let dep3 = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 15, second: 0)))

        #expect(dep1.timeIntervalSince(testNow) == 5 * 60)
        #expect(dep2.timeIntervalSince(dep1) == 10 * 60)
        #expect(dep3.timeIntervalSince(dep2) == 10 * 60)

        let departuresList = [
            try departure(at: dep1, tripID: "trip_0155_est"),
            try departure(at: dep2, tripID: "trip_0305_edt"),
            try departure(at: dep3, tripID: "trip_0315_edt")
        ]

        let plan = WidgetTimelinePlanner().plan(departureDates: departuresList.map(\.arrivalDepartureDate), now: testNow)

        #expect(zip(plan.entryDates, plan.entryDates.dropFirst()).allSatisfy { $0 < $1 })
        #expect(plan.entryDates == [testNow, dep1, dep2, dep3])

        let expectedReload = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 20, second: 0)))
        #expect(plan.reloadDate == expectedReload)
        #expect(plan.reloadDate.timeIntervalSince(testNow) == 30 * 60)

        #expect(calendar.component(.hour, from: plan.entryDates[1]) == 1)
        #expect(calendar.component(.hour, from: plan.entryDates[2]) == 3)
        #expect(calendar.component(.hour, from: plan.reloadDate) == 3)
        #expect(calendar.component(.minute, from: plan.reloadDate) == 20)
    }

    @Test func `DST fall back transition produces strictly monotonic UTC timestamps and correct reload date`() throws {
        var calendar = Calendar(identifier: .gregorian)
        let tz = try #require(TimeZone(identifier: "America/New_York"))
        calendar.timeZone = tz

        let testNow = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 45, second: 0)))
        #expect(tz.isDaylightSavingTime(for: testNow) == true)

        let dep1 = testNow.addingTimeInterval(10 * 60)
        #expect(calendar.component(.hour, from: dep1) == 1)
        #expect(calendar.component(.minute, from: dep1) == 55)
        #expect(tz.isDaylightSavingTime(for: dep1) == true)

        let dep2 = testNow.addingTimeInterval(25 * 60)
        #expect(calendar.component(.hour, from: dep2) == 1)
        #expect(calendar.component(.minute, from: dep2) == 10)
        #expect(tz.isDaylightSavingTime(for: dep2) == false)

        let dep3 = testNow.addingTimeInterval(40 * 60)
        #expect(calendar.component(.hour, from: dep3) == 1)
        #expect(calendar.component(.minute, from: dep3) == 25)
        #expect(tz.isDaylightSavingTime(for: dep3) == false)

        let departuresList = [
            try departure(at: dep1, tripID: "trip_0155_edt"),
            try departure(at: dep2, tripID: "trip_0110_est"),
            try departure(at: dep3, tripID: "trip_0125_est")
        ]

        let plan = WidgetTimelinePlanner().plan(departureDates: departuresList.map(\.arrivalDepartureDate), now: testNow)

        #expect(zip(plan.entryDates, plan.entryDates.dropFirst()).allSatisfy { $0 < $1 })
        #expect(plan.entryDates == [testNow, dep1, dep2])

        #expect(plan.reloadDate == testNow.addingTimeInterval(1800))
        #expect(calendar.component(.hour, from: plan.reloadDate) == 1)
        #expect(calendar.component(.minute, from: plan.reloadDate) == 15)
        #expect(tz.isDaylightSavingTime(for: plan.reloadDate) == false)
    }

    @Test func `Timeline plan is invariant across stop, agency, and device timezones`() throws {
        let testTimeZones = [
            "UTC",
            "America/New_York",
            "America/Los_Angeles",
            "Asia/Tokyo",
            "Europe/London",
            "Australia/Sydney"
        ]

        let baseNow = Date(timeIntervalSince1970: 1_770_000_000)
        let departureOffsets: [TimeInterval] = [3 * 60, 7 * 60, 15 * 60, 22 * 60, 28 * 60]
        let baseDepartures = departureOffsets.map { baseNow.addingTimeInterval($0) }

        let referencePlan = WidgetTimelinePlanner().plan(departureDates: baseDepartures, now: baseNow)

        for identifier in testTimeZones {
            let timeZone = try #require(TimeZone(identifier: identifier))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone

            let nowComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: baseNow)
            let tzNow = try #require(calendar.date(from: nowComponents))

            let tzDepartures = baseDepartures.map { depDate in
                let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: depDate)
                return calendar.date(from: comps)!
            }

            let tzPlan = WidgetTimelinePlanner().plan(departureDates: tzDepartures, now: tzNow)

            #expect(tzPlan.entryDates == referencePlan.entryDates)
            #expect(tzPlan.reloadDate == referencePlan.reloadDate)
        }
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

    @Test func `Implausible arrival departure dates are excluded from visible departures`() throws {
        let implausible = try Fixtures.arrivalDeparture(
            predicted: false,
            scheduledArrival: 0,
            scheduledDeparture: 0,
            tripID: "trip_epoch"
        )
        let visible = WidgetTimelinePlanner.departures([implausible], visibleAt: Date(timeIntervalSinceReferenceDate: -100))
        #expect(visible.isEmpty)
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

    @Test func `Departures departing within sixty seconds are included in now entry and pruned in next entry`() throws {
        let imminentDate = upcomingNow.addingTimeInterval(45)
        let dep = try departure(at: imminentDate, tripID: "trip_now")

        let plan = WidgetTimelinePlanner().plan(departureDates: [dep.arrivalDepartureDate], now: upcomingNow)
        #expect(plan.entryDates == [upcomingNow, upcomingNow.addingTimeInterval(5 * 60)])

        let initialVisible = WidgetTimelinePlanner.departures([dep], visibleAt: plan.entryDates[0])
        #expect(initialVisible.map(\.tripID) == ["trip_now"])
        #expect(initialVisible.first?.temporalState == .present)

        let nextVisible = WidgetTimelinePlanner.departures([dep], visibleAt: plan.entryDates[1])
        #expect(nextVisible.isEmpty)
    }

    @Test func `Departures at now minus one second and now are omitted while now plus one second is included with present temporal state`() throws {
        let refNow = upcomingNow
        let depPast = try departure(at: refNow.addingTimeInterval(-1), tripID: "trip_past")
        let depExact = try departure(at: refNow, tripID: "trip_exact")
        let depNow = try departure(at: refNow.addingTimeInterval(1), tripID: "trip_now_plus_one")

        let allDepartures = [depPast, depExact, depNow]
        let plan = WidgetTimelinePlanner().plan(
            departureDates: allDepartures.map(\.arrivalDepartureDate),
            now: refNow
        )

        // Only depNow is upcoming (> refNow)
        #expect(plan.entryDates == [refNow, refNow.addingTimeInterval(5 * 60)])
        #expect(plan.reloadDate == refNow.addingTimeInterval(30 * 60))

        // When only past and exact departures are provided, upcoming is empty
        let expiredPlan = WidgetTimelinePlanner().plan(
            departureDates: [depPast.arrivalDepartureDate, depExact.arrivalDepartureDate],
            now: refNow
        )
        #expect(expiredPlan.entryDates == [refNow])
        #expect(expiredPlan.reloadDate == refNow.addingTimeInterval(60 * 60))

        // Entry 0 at refNow: now - 1s and now are omitted; now + 1s is included and marked .present
        let visibleAtEntry0 = WidgetTimelinePlanner.departures(allDepartures, visibleAt: plan.entryDates[0])
        #expect(visibleAtEntry0.map(\.tripID) == ["trip_now_plus_one"])
        #expect(visibleAtEntry0.first?.temporalState == .present)

        // Entry 1 at refNow + 5m: now + 1s has expired
        let visibleAtEntry1 = WidgetTimelinePlanner.departures(allDepartures, visibleAt: plan.entryDates[1])
        #expect(visibleAtEntry1.isEmpty)
    }

    @Test func `Reload date is strictly after every entry date even with large spacing or close departures`() {
        let largeSpacingPlanner = WidgetTimelinePlanner(minimumEntrySpacing: 45 * 60)
        let plan = largeSpacingPlanner.plan(departureDates: [minutes(5), minutes(20)], now: now)

        #expect(plan.entryDates == [now])
        #expect(plan.reloadDate == minutes(30))
        #expect(plan.reloadDate > plan.entryDates.last!)

        let normalPlanner = WidgetTimelinePlanner()
        let latePlan = normalPlanner.plan(departureDates: [minutes(28), minutes(29)], now: now)
        #expect(latePlan.reloadDate > latePlan.entryDates.last!)
    }
}
