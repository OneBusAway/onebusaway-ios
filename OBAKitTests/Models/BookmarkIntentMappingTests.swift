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
        let stop = arrivalDep.stop

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

        let entities = BookmarkIntentMapping.entities(from: [wholeStop, trip])
        #expect(entities.map(\.id) == [trip.id])
        #expect(entities.map(\.name) == ["49 to Downtown"])
        #expect(trip.isTripBookmark)
        #expect(!wholeStop.isTripBookmark)
    }
}
