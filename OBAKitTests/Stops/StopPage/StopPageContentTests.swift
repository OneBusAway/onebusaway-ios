//
//  StopPageContentTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Pure-value tests for the Stop page's derivation. This logic used to live
/// inline in `StopPageView.body`, where none of it could be asserted.
@MainActor
@Suite(.serialized)
final class StopPageContentTests: OBATestCase {

    /// A timestamp `minutes` from now, in the units `Fixtures.arrivalDeparture`
    /// actually wants.
    ///
    /// `Fixtures.dictionaryToModel` decodes with a plain `JSONDecoder`, whose
    /// default date strategy is `.deferredToDate` — seconds since Date's 2001
    /// reference date, *not* the epoch, and not the `.millisecondsSince1970` the
    /// real `RESTDecoder` uses. Anchoring to the current time is what lets these
    /// tests say "past" or "upcoming" and mean it, since `temporalState` is
    /// relative to now.
    private static func timestamp(minutesFromNow minutes: Int) -> Int {
        Int(Date().addingTimeInterval(TimeInterval(minutes * 60)).timeIntervalSinceReferenceDate)
    }

    private func departures() throws -> [ArrivalDeparture] {
        [
            try Fixtures.arrivalDeparture(routeID: "route_1", tripID: "trip_1"),
            try Fixtures.arrivalDeparture(routeID: "route_2", tripID: "trip_2"),
            try Fixtures.arrivalDeparture(routeID: "route_2", tripID: "trip_3")
        ]
    }

    private func makeContent(
        allDepartures: [ArrivalDeparture],
        preferences: StopPreferences = StopPreferences(),
        isListFiltered: Bool = false,
        arrivalDepartureFilter: ArrivalDepartureFilter = .all,
        hasLoadedArrivals: Bool = true,
        isLoading: Bool = false,
        hasError: Bool = false,
        isBrokenBookmark: Bool = false
    ) -> StopPageContent {
        StopPageContent(
            stop: nil,
            allDepartures: allDepartures,
            hasLoadedArrivals: hasLoadedArrivals,
            preferences: preferences,
            isListFiltered: isListFiltered,
            arrivalDepartureFilter: arrivalDepartureFilter,
            isLoading: isLoading,
            hasError: hasError,
            isBrokenBookmark: isBrokenBookmark
        )
    }

    // MARK: - Filtering

    @Test func `Unfiltered content keeps every route`() throws {
        let content = makeContent(allDepartures: try departures())
        #expect(content.departures.count == 3)
        #expect(content.routeIDs == ["route_1", "route_2"])
    }

    @Test func `Filtering drops hidden routes only when the filter is on`() throws {
        let prefs = StopPreferences(sortType: .time, hiddenRoutes: ["route_2"])

        let filtered = makeContent(allDepartures: try departures(), preferences: prefs, isListFiltered: true)
        #expect(filtered.departures.count == 1)
        #expect(filtered.routeIDs == ["route_1"])

        let unfiltered = makeContent(allDepartures: try departures(), preferences: prefs, isListFiltered: false)
        #expect(unfiltered.departures.count == 3)
    }

    // MARK: - Terminal duplicates

    /// The API emits a separate arrival and departure row for one vehicle visit
    /// at a terminal or loop stop. `StopPageContent` collapses them, and without
    /// that the rider sees the same bus twice with two different countdowns —
    /// the parity `StopViewController` established.
    @Test func `A terminal's arrival and departure pair collapses to one row`() throws {
        let arrival = try Fixtures.arrivalDeparture(
            scheduledArrival: Self.timestamp(minutesFromNow: 10),
            scheduledDeparture: Self.timestamp(minutesFromNow: 14),
            routeID: "route_1",
            tripID: "trip_1"
        )
        let departure = try Fixtures.arrivalDeparture(
            scheduledArrival: Self.timestamp(minutesFromNow: 10),
            scheduledDeparture: Self.timestamp(minutesFromNow: 14),
            routeID: "route_1",
            tripID: "trip_1"
        )

        let content = makeContent(allDepartures: [arrival, departure])

        #expect(content.departures.count == 1)
    }

    /// Deduplication keys on the vehicle visit, so two genuinely different trips
    /// on the same route must both survive.
    @Test func `Two trips on one route both survive deduplication`() throws {
        let first = try Fixtures.arrivalDeparture(
            scheduledArrival: Self.timestamp(minutesFromNow: 10),
            scheduledDeparture: Self.timestamp(minutesFromNow: 10),
            routeID: "route_1",
            tripID: "trip_1"
        )
        let second = try Fixtures.arrivalDeparture(
            scheduledArrival: Self.timestamp(minutesFromNow: 25),
            scheduledDeparture: Self.timestamp(minutesFromNow: 25),
            routeID: "route_1",
            tripID: "trip_2"
        )

        let content = makeContent(allDepartures: [first, second])

        #expect(content.departures.count == 2)
    }

    // MARK: - Grouping

    @Test func `Grouped mode builds one group per route`() throws {
        let prefs = StopPreferences(sortType: .route, hiddenRoutes: [])
        let content = makeContent(allDepartures: try departures(), preferences: prefs)

        #expect(content.isGrouped)
        #expect(content.routeGroups.count == 2)
    }

    @Test func `Chronological mode builds no groups`() throws {
        let content = makeContent(allDepartures: try departures())
        #expect(!content.isGrouped)
        #expect(content.routeGroups.isEmpty)
    }

    // MARK: - Emptiness

    @Test func `Empty departures produce an empty list`() {
        let content = makeContent(allDepartures: [])
        #expect(content.listIsEmpty)
    }

    /// Grouped mode drops past departures, so it can have nothing to render
    /// while `departures` is still non-empty — the last bus of the evening has
    /// left. Emptiness has to follow the groups, or the page renders a void
    /// instead of the empty state.
    @Test func `Grouped mode is empty once every departure is in the past`() throws {
        let past = [
            try Fixtures.arrivalDeparture(
                scheduledArrival: Self.timestamp(minutesFromNow: -40),
                scheduledDeparture: Self.timestamp(minutesFromNow: -40),
                routeID: "route_1",
                tripID: "trip_1"
            ),
            try Fixtures.arrivalDeparture(
                scheduledArrival: Self.timestamp(minutesFromNow: -20),
                scheduledDeparture: Self.timestamp(minutesFromNow: -20),
                routeID: "route_2",
                tripID: "trip_2"
            )
        ]
        let prefs = StopPreferences(sortType: .route, hiddenRoutes: [])
        let content = makeContent(allDepartures: past, preferences: prefs)

        // The departures are still there — only the grouped projection is empty.
        #expect(content.departures.count == 2)
        #expect(content.routeGroups.isEmpty)
        #expect(content.listIsEmpty)
    }

    /// The same feed in chronological mode is *not* empty: that mode keeps past
    /// departures behind the collapsed "past" section.
    @Test func `Chronological mode is not empty for the same past departures`() throws {
        let past = [
            try Fixtures.arrivalDeparture(
                scheduledArrival: Self.timestamp(minutesFromNow: -40),
                scheduledDeparture: Self.timestamp(minutesFromNow: -40),
                routeID: "route_1",
                tripID: "trip_1"
            )
        ]
        let content = makeContent(allDepartures: past)

        #expect(!content.isGrouped)
        #expect(!content.listIsEmpty)
    }

    @Test func `Filtered empty is true only when the filter emptied a non-empty feed`() throws {
        let prefs = StopPreferences(sortType: .time, hiddenRoutes: ["route_1", "route_2"])
        let content = makeContent(allDepartures: try departures(), preferences: prefs, isListFiltered: true)

        #expect(content.departures.isEmpty)
        #expect(content.isFilteredEmpty)
    }

    @Test func `Filtered empty is false when the feed itself is empty`() {
        let content = makeContent(allDepartures: [], isListFiltered: true)
        #expect(!content.isFilteredEmpty)
    }

    @Test func `Filtered empty is false when the filter is off`() throws {
        let content = makeContent(allDepartures: [], isListFiltered: false)
        #expect(!content.isFilteredEmpty)
    }

    @Test func `Departure filter empty is true only when the type filter emptied the routes' departures`() throws {
        // The fixtures are all predicted, so `.scheduledOnly` removes every row
        // the route filter let through.
        let content = makeContent(allDepartures: try departures(), arrivalDepartureFilter: .scheduledOnly)

        #expect(content.departures.isEmpty)
        #expect(!content.routeVisibleDepartures.isEmpty)
        #expect(content.isDepartureFilterEmpty)
        // The route filter isn't what emptied it.
        #expect(!content.isFilteredEmpty)
    }

    @Test func `Departure filter empty is false when the feed itself is empty`() {
        let content = makeContent(allDepartures: [], arrivalDepartureFilter: .scheduledOnly)
        #expect(!content.isDepartureFilterEmpty)
    }

    @Test func `Departure filter empty is false when the filter is off`() throws {
        let content = makeContent(allDepartures: try departures())
        #expect(!content.isDepartureFilterEmpty)
    }

    // MARK: - Loading state

    @Test func `Loading state covers the first frame before any fetch`() {
        let content = makeContent(allDepartures: [], hasLoadedArrivals: false)
        #expect(content.showsLoadingState)
    }

    @Test func `Loading state holds while a fetch is in flight`() throws {
        let content = makeContent(allDepartures: try departures(), isLoading: true)
        #expect(content.showsLoadingState)
    }

    @Test func `A first fetch that failed is not a loading state`() {
        let content = makeContent(allDepartures: [], hasLoadedArrivals: false, hasError: true)
        #expect(!content.showsLoadingState)
    }

    @Test func `A broken bookmark is not a loading state`() {
        let content = makeContent(allDepartures: [], hasLoadedArrivals: false, isBrokenBookmark: true)
        #expect(!content.showsLoadingState)
    }

    // MARK: - Attribution

    @Test func `Attribution is empty without a stop`() {
        #expect(makeContent(allDepartures: []).attributionText.isEmpty)
    }

    @Test func `Attribution names the stop's agencies`() throws {
        let stop = try #require(Fixtures.loadSomeStops().first)
        let content = StopPageContent(
            stop: stop,
            allDepartures: [],
            hasLoadedArrivals: true,
            preferences: StopPreferences(),
            isListFiltered: false,
            arrivalDepartureFilter: .all,
            isLoading: false,
            hasError: false,
            isBrokenBookmark: false
        )

        let agencies = Formatters.formattedAgenciesForRoutes(stop.routes)
        #expect(content.attributionText.isEmpty == agencies.isEmpty)
        if !agencies.isEmpty {
            #expect(content.attributionText.contains(agencies))
        }
    }

    // MARK: - fillsPage

    @Test func `fillsPage is true when no stop is provided`() {
        let content = makeContent(allDepartures: [], hasLoadedArrivals: false)
        #expect(content.fillsPage)
    }

    @Test func `fillsPage is false when a stop is provided even after a fetch failed`() throws {
        let stop = try #require(Fixtures.loadSomeStops().first)
        let content = StopPageContent(
            stop: stop,
            allDepartures: [],
            hasLoadedArrivals: false,
            preferences: StopPreferences(),
            isListFiltered: false,
            arrivalDepartureFilter: .all,
            isLoading: false,
            hasError: true,
            isBrokenBookmark: false
        )

        #expect(!content.fillsPage)
    }

    @Test func `fillsPage is false when a stop is provided and arrivals loaded fine`() throws {
        let stop = try #require(Fixtures.loadSomeStops().first)
        let content = StopPageContent(
            stop: stop,
            allDepartures: try departures(),
            hasLoadedArrivals: true,
            preferences: StopPreferences(),
            isListFiltered: false,
            arrivalDepartureFilter: .all,
            isLoading: false,
            hasError: false,
            isBrokenBookmark: false
        )

        #expect(!content.fillsPage)
    }
}
