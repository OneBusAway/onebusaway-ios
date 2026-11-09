//
//  StopEntityTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class StopEntityTests {

    private func makeRoutes(_ shortNames: [String]) throws -> [Route] {
        try shortNames.map {
            try Fixtures.dictionaryToModel(type: Route.self, dictionary: [
                "agencyId": "1",
                "id": "1_\($0)",
                "shortName": $0,
                "type": 3
            ])
        }
    }

    private func makeStop(code: String = "75403", direction: String? = "N", routes: [Route]?) -> Stop {
        let stop = Stop(id: "1_75403", name: "3rd Ave & Pine St", code: code, direction: direction, location: CLLocation(latitude: 47.6097, longitude: -122.3422), regionIdentifier: 1)
        stop.routes = routes
        return stop
    }

    /// `routes` is nil on a stop decoded from the REST API without them; that
    /// must not crash. Dropping the route limit lists all seven routes.
    @Test func `Subtitle is the direction and the routes`() throws {
        let both = StopEntityMapping.entity(for: makeStop(routes: try makeRoutes(["49", "8"])), regionID: 1)
        #expect(both.subtitle == "Northbound • Routes: 8, 49")

        let noRoutes = StopEntityMapping.entity(for: makeStop(routes: nil), regionID: 1)
        #expect(noRoutes.subtitle == "Northbound")

        let neither = StopEntityMapping.entity(for: makeStop(direction: nil, routes: []), regionID: 1)
        #expect(neither.subtitle == nil)

        let hub = StopEntityMapping.entity(for: makeStop(routes: try makeRoutes(["1", "2", "3", "4", "5", "6", "7"])), regionID: 1)
        #expect(hub.subtitle == "Northbound • Routes: 1, 2, 3, 4, 5, + 2 more")
    }

    @Test func `Attribute set carries the code and the coordinates`() {
        let attributes = StopEntityMapping.entity(for: makeStop(routes: []), regionID: 1).attributeSet
        #expect(attributes.keywords == ["75403"])
        #expect(attributes.latitude?.doubleValue == 47.6097)
        #expect(attributes.longitude?.doubleValue == -122.3422)

        // GTFS leaves the code blank for stops without one; that's no keyword.
        let noCode = StopEntityMapping.entity(for: makeStop(code: "", routes: []), regionID: 1)
        #expect(noCode.code == nil)
        #expect(noCode.attributeSet.keywords?.contains("") != true)
    }

    @Test func `Fallback entity is titled with its stop id`() throws {
        let fallback = try #require(StopEntityMapping.entities(forIdentifiers: ["region_1_stop_1_75403"], bookmarks: [], recentStops: []).first)
        #expect(String(localized: fallback.displayRepresentation.title) == "Stop 1_75403")
        #expect(fallback.displayRepresentation.subtitle == nil)
        #expect(fallback.destination == AppLinksRouter.StopDestination(stopID: "1_75403", regionID: 1))
    }
}
