//
//  HomeNearbyDeparturesTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The home sheet's Nearby section lists departures rather than stop names:
/// what leaves, where to, and when.
@Suite(.serialized)
@MainActor
struct HomeNearbyDeparturesTests {

    private func stops() throws -> [Stop] {
        Array(try Fixtures.loadSomeStops().prefix(3))
    }

    private func upcoming() throws -> [ArrivalDeparture] {
        try StopArrivalsFixture.upcoming().arrivalsAndDepartures
    }

    // MARK: - Rows

    @Test func `A stop whose arrivals have not loaded shows as a stop`() throws {
        let stops = try stops()

        let rows = HomeNearbyDepartures.rows(stops: stops, arrivals: [:], excluding: [])

        #expect(rows == stops.map { .stop($0) })
    }

    @Test func `A loaded stop lists its soonest departure per route and headsign`() throws {
        let stop = try #require(try stops().first)
        let departures = try upcoming()

        let rows = HomeNearbyDepartures.rows(
            stops: [stop],
            arrivals: [stop.id: departures],
            excluding: [],
            limit: 100,
            perStopLimit: 100
        )

        let listed = rows.compactMap(\.departure)
        #expect(listed.count == rows.count)
        #expect(!listed.isEmpty)
        // One per route and headsign.
        let keys = listed.map { TripBookmarkKey(arrivalDeparture: $0.arrivalDeparture) }
        #expect(Set(keys).count == keys.count)
        #expect(Set(keys) == Set(departures.map(TripBookmarkKey.init(arrivalDeparture:))))
        // Each is its key's soonest, and they run soonest first.
        for row in listed {
            let key = TripBookmarkKey(arrivalDeparture: row.arrivalDeparture)
            let soonest = departures
                .filter { TripBookmarkKey(arrivalDeparture: $0) == key }
                .map(\.arrivalDepartureDate)
                .min()
            #expect(row.arrivalDeparture.arrivalDepartureDate == soonest)
        }
        let dates = listed.map(\.arrivalDeparture.arrivalDepartureDate)
        #expect(dates == dates.sorted())
        #expect(listed.allSatisfy { $0.stop.id == stop.id })
    }

    /// A departed bus is no answer to "what leaves near me now".
    @Test func `Past departures are left out`() throws {
        let stop = try #require(try stops().first)
        // The fixture as recorded: every time in it is years ago.
        let past = try StopArrivalsFixture.load().arrivalsAndDepartures
        #expect(!past.isEmpty)

        let rows = HomeNearbyDepartures.rows(stops: [stop], arrivals: [stop.id: past], excluding: [])

        #expect(rows == [.stop(stop)])
    }

    /// The Bookmarks cards above already show these.
    @Test func `A departure a bookmark card shows is not listed again`() throws {
        let stop = try #require(try stops().first)
        let departures = try upcoming()
        let bookmarked = TripBookmarkKey(arrivalDeparture: try #require(departures.first))

        let rows = HomeNearbyDepartures.rows(
            stops: [stop],
            arrivals: [stop.id: departures],
            excluding: [bookmarked],
            limit: 100,
            perStopLimit: 100
        )

        let keys = rows.compactMap(\.departure).map { TripBookmarkKey(arrivalDeparture: $0.arrivalDeparture) }
        #expect(!keys.contains(bookmarked))
    }

    /// Late at night, or everything bookmarked: the section still leads somewhere.
    @Test func `With no departures to list, loaded stops show as stops`() throws {
        let stops = try stops()
        let arrivals = Dictionary(uniqueKeysWithValues: stops.map { ($0.id, [ArrivalDeparture]()) })

        let rows = HomeNearbyDepartures.rows(stops: stops, arrivals: arrivals, excluding: [])

        #expect(rows == stops.map { .stop($0) })
    }

    @Test func `One stop cannot fill the section`() throws {
        let stops = try stops()
        let departures = try upcoming()
        let arrivals = Dictionary(uniqueKeysWithValues: stops.map { ($0.id, departures) })

        let rows = HomeNearbyDepartures.rows(stops: stops, arrivals: arrivals, excluding: [], limit: 4, perStopLimit: 2)

        #expect(rows.count == 4)
        #expect(rows.compactMap(\.departure).map(\.stop.id) == [stops[0].id, stops[0].id, stops[1].id, stops[1].id])
    }

    @Test func `Rows have distinct identities`() throws {
        let stops = try stops()
        let departures = try upcoming()

        let rows = HomeNearbyDepartures.rows(
            stops: stops,
            arrivals: [stops[0].id: departures, stops[1].id: departures],
            excluding: [],
            limit: 100,
            perStopLimit: 100
        )

        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    // MARK: - Loading

    private final class FetchLog {
        var stopIDs: [StopID] = []
    }

    private func makeModel(
        log: FetchLog,
        departures: [ArrivalDeparture],
        failing: Bool = false
    ) -> HomeNearbyDeparturesSectionModel {
        HomeNearbyDeparturesSectionModel(
            fetch: { stopID in
                log.stopIDs.append(stopID)
                if failing { throw URLError(.notConnectedToInternet) }
                return departures
            },
            excludedKeys: { [] }
        )
    }

    @Test func `Fetches the nearest stops only, and only while visible`() async throws {
        let all = Array(try Fixtures.loadSomeStops().prefix(6))
        let log = FetchLog()
        let model = makeModel(log: log, departures: try upcoming())
        model.stops = all

        // Hidden: the collapsed sheet, another tab, or a sheet stacked over it.
        #expect(model.loadIfNeeded() == nil)
        #expect(model.loadTask == nil)
        #expect(log.stopIDs.isEmpty)
        #expect(model.rows == all.prefix(HomeNearbyDepartures.stopLimit).map { .stop($0) })

        model.isVisible = true
        await model.loadTask?.value

        #expect(log.stopIDs.sorted() == all.prefix(HomeNearbyDepartures.stopLimit).map(\.id).sorted())
        #expect(model.rows.contains { $0.departure != nil })
    }

    @Test func `A second load inside the staleness window fetches nothing`() async throws {
        let stops = try stops()
        let log = FetchLog()
        let model = makeModel(log: log, departures: try upcoming())
        model.stops = stops
        model.isVisible = true
        await model.loadTask?.value
        let start = Date()
        let fetched = log.stopIDs.count
        #expect(fetched == stops.count)

        #expect(model.loadIfNeeded(now: start.addingTimeInterval(10)) == nil)
        #expect(log.stopIDs.count == fetched)

        await model.loadIfNeeded(now: start.addingTimeInterval(31))?.value
        #expect(log.stopIDs.count == fetched * 2)
    }

    /// Panning the map brings new stops in; the ones already loaded are kept.
    @Test func `Only a newly nearby stop is fetched`() async throws {
        let all = Array(try Fixtures.loadSomeStops().prefix(4))
        let log = FetchLog()
        let model = makeModel(log: log, departures: try upcoming())
        model.stops = Array(all.prefix(3))
        model.isVisible = true
        await model.loadTask?.value
        log.stopIDs.removeAll()

        model.stops = [all[3], all[0], all[1]]
        await model.loadTask?.value

        #expect(log.stopIDs == [all[3].id])
    }

    /// A failed fetch is not "no departures": the stop stays a plain stop row
    /// and is tried again on the next activation.
    @Test func `A failed fetch is retried rather than held as fresh`() async throws {
        let stops = Array(try stops().prefix(1))
        let log = FetchLog()
        let model = makeModel(log: log, departures: [], failing: true)
        model.stops = stops
        model.isVisible = true
        await model.loadTask?.value

        #expect(model.rows == stops.map { .stop($0) })
        await model.loadIfNeeded()?.value
        #expect(log.stopIDs.count == 2)
    }

    // MARK: - Extended Row Equality & Boundary Invariants

    @Test func `Rebuilding rows with newly excluded bookmarks updates row presentation`() async throws {
        let stop = try #require(try stops().first)
        let departures = try upcoming()
        let firstKey = TripBookmarkKey(arrivalDeparture: try #require(departures.first))

        var excluded: Set<TripBookmarkKey> = []
        let model = HomeNearbyDeparturesSectionModel(
            fetch: { _ in departures },
            excludedKeys: { excluded }
        )
        model.stops = [stop]
        model.isVisible = true
        await model.loadTask?.value

        let initialKeys = model.rows.compactMap(\.departure).map { TripBookmarkKey(arrivalDeparture: $0.arrivalDeparture) }
        #expect(initialKeys.contains(firstKey))

        excluded = [firstKey]
        model.rebuildRows()

        let updatedKeys = model.rows.compactMap(\.departure).map { TripBookmarkKey(arrivalDeparture: $0.arrivalDeparture) }
        #expect(!updatedKeys.contains(firstKey))
    }

    @Test func `Empty stops array results in empty rows`() throws {
        let rows = HomeNearbyDepartures.rows(stops: [], arrivals: [:], excluding: [])
        #expect(rows.isEmpty)
    }
}
