//
//  SearchableTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class SearchableTests: OBATestCase {

    private func makeRoute(
        id: String = "1_10",
        shortName: String = "10",
        longName: String? = "Downtown Seattle",
        description: String? = "Express Route"
    ) throws -> Route {
        var dict: [String: Any] = [
            "id": id,
            "shortName": shortName,
            "type": 3,
            "agencyId": "1"
        ]
        if let longName { dict["longName"] = longName }
        if let description { dict["description"] = description }
        return try Fixtures.dictionaryToModel(type: Route.self, dictionary: dict)
    }

    private func makeStop(
        id: String = "1_75403",
        code: String = "75403",
        name: String = "3rd Ave & Pike St",
        routes: [Route] = []
    ) throws -> Stop {
        let stop = Stop(
            id: id,
            name: name,
            code: code,
            location: CLLocation(latitude: 47.6097, longitude: -122.3422),
            regionIdentifier: 1
        )
        stop.routes = routes
        return stop
    }

    @Test func `Route matchesQuery handles nil and matches shortName, longName, and description`() throws {
        let route = try makeRoute(shortName: "44", longName: "Ballard - Montlake", description: "Crosstown service")

        #expect(route.matchesQuery(nil))
        #expect(route.matchesQuery("44"))
        #expect(route.matchesQuery("ballard"))
        #expect(route.matchesQuery("crosstown"))
        #expect(!route.matchesQuery("Downtown"))
    }

    @Test func `Stop matchesQuery matches stop name or associated routes, but not stop code`() throws {
        let route = try makeRoute(shortName: "49", longName: "Broadway")
        let stop = try makeStop(code: "10914", name: "15th Ave E & E Thomas St", routes: [route])

        #expect(stop.matchesQuery(nil))
        #expect(stop.matchesQuery("15th"))
        #expect(stop.matchesQuery("49"))
        #expect(stop.matchesQuery("broadway"))

        // Stop code is not searched
        #expect(!stop.matchesQuery("10914"))
        #expect(!stop.matchesQuery("Pike Place"))
    }

    @Test func `Bookmark matchesQuery matches routeShortName, tripHeadsign, or underlying stop`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try #require(stopArrivals.arrivalsAndDepartures.first)
        let tripBookmark = Bookmark(
            name: "49 to Downtown",
            regionIdentifier: pugetSoundRegionIdentifier,
            arrivalDeparture: arrivalDep
        )

        #expect(tripBookmark.matchesQuery(nil))
        #expect(tripBookmark.matchesQuery("49"))
        let headsign = try #require(tripBookmark.tripHeadsign)
        #expect(tripBookmark.matchesQuery(headsign))
        #expect(tripBookmark.matchesQuery(tripBookmark.stop.name))
        #expect(!tripBookmark.matchesQuery("Nonexistent"))
    }
}
