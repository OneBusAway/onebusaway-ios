//
//  BookmarkIntentMappingTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class BookmarkIntentMappingTests: OBATestCase {

    override init() async throws {
        try await super.init()
    }

    /// Whole-stop bookmarks have no single route to Track. Including them in
    /// the Shortcut entity query would offer a start path that cannot build
    /// `TripAttributes.StaticData`. Filter them out and this still fails.
    @Test func `Shortcut entities include trip bookmarks and skip whole-stop bookmarks`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try #require(stopArrivals.arrivalsAndDepartures.first)
        let stop = try #require(arrivalDep.stop)

        let trip = Bookmark(
            name: "49 to Downtown",
            regionIdentifier: pugetSoundRegionIdentifier,
            arrivalDeparture: arrivalDep
        )
        let wholeStop = Bookmark(
            name: "The stop",
            regionIdentifier: pugetSoundRegionIdentifier,
            stop: stop
        )

        let entities = BookmarkIntentMapping.entities(
            from: [wholeStop, trip],
            regionIdentifier: pugetSoundRegionIdentifier
        )
        #expect(entities.map(\.id) == [trip.id])
        #expect(entities.map(\.name) == ["49 to Downtown"])
        #expect(trip.isTripBookmark)
        #expect(!wholeStop.isTripBookmark)
    }

    /// Arrivals are only fetched for the current region. Offering an out-of-
    /// region trip bookmark queues a request `hasFetchedArrivals` can never
    /// satisfy. Drop the region filter and this fails.
    @Test func `Shortcut entities skip trip bookmarks from other regions`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try #require(stopArrivals.arrivalsAndDepartures.first)

        let local = Bookmark(
            name: "Local 49",
            regionIdentifier: pugetSoundRegionIdentifier,
            arrivalDeparture: arrivalDep
        )
        let other = Bookmark(
            name: "Other region",
            regionIdentifier: pugetSoundRegionIdentifier + 1,
            arrivalDeparture: arrivalDep
        )

        let entities = BookmarkIntentMapping.entities(
            from: [local, other],
            regionIdentifier: pugetSoundRegionIdentifier
        )
        #expect(entities.map(\.id) == [local.id])

        let none = BookmarkIntentMapping.entities(
            from: [local, other],
            regionIdentifier: nil
        )
        #expect(none.isEmpty)
    }

    /// The entity query is `nonisolated`. Duplicating the region key as a
    /// string drifted from `RegionsService`. Reading the service's own
    /// `nonisolated` constant is the contract.
    @Test func `Entity query reads the RegionsService current-region key`() {
        #expect(
            BookmarkIntentMapping.regionIdentifierUserDefaultsKey
                == RegionsService.currentRegionIdentifierUserDefaultsKey
        )
    }
}
