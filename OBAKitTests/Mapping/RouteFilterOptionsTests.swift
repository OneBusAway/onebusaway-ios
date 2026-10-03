//
//  RouteFilterOptionsTests.swift
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

/// The "Routes on Map" list is built from the stops the map already loaded.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/1414
@MainActor
@Suite(.serialized)
final class RouteFilterOptionsTests {

    private func makeRoute(id: String, shortName: String) throws -> Route {
        try Fixtures.dictionaryToModel(type: Route.self, dictionary: [
            "agencyId": "test_agency",
            "id": id,
            "shortName": shortName,
            "type": 3
        ])
    }

    @Test func `Routes shared by several stops are listed once`() throws {
        let stops = try Fixtures.loadSomeStops()
        let routes = RouteFilterOptions.routes(from: stops)

        let expectedIDs = Set(stops.flatMap { ($0.routes ?? []).map(\.id) })
        #expect(routes.count == expectedIDs.count)
        #expect(Set(routes.map(\.id)) == expectedIDs)
    }

    @Test func `Routes are grouped by agency name`() throws {
        let routes = RouteFilterOptions.routes(from: try Fixtures.loadSomeStops())

        var agencyBlocks = [String]()
        for name in routes.map({ $0.agency?.name ?? "" }) where agencyBlocks.last != name {
            agencyBlocks.append(name)
        }

        #expect(agencyBlocks == ["Community Transit", "Metro Transit", "Seattle Children's Hospital", "Sound Transit"])
    }

    @Test func `Short names within an agency sort numerically`() throws {
        let stop = try #require(try Fixtures.loadSomeStops().first)
        stop.routes = [
            try makeRoute(id: "r10", shortName: "10"),
            try makeRoute(id: "r2", shortName: "2"),
            try makeRoute(id: "r1", shortName: "1")
        ]

        let routes = RouteFilterOptions.routes(from: [stop])

        #expect(routes.map(\.shortName) == ["1", "2", "10"])
    }

    @Test func `A stop whose routes were never reconnected contributes nothing`() throws {
        let stop = try #require(try Fixtures.loadSomeStops().first)
        stop.routes = nil

        #expect(RouteFilterOptions.routes(from: [stop]).isEmpty)
    }

    @Test func `Zoomed out reports zoomed out even when stale stops are in memory`() throws {
        let stops = try Fixtures.loadSomeStops()

        #expect(RouteFilterOptions.content(stops: stops, isZoomedOut: true) == .zoomedOut)
    }

    @Test func `No loaded stops reports no routes`() {
        #expect(RouteFilterOptions.content(stops: [], isZoomedOut: false) == .noRoutes)
    }

    @Test func `Loaded stops report their routes`() throws {
        let stops = try Fixtures.loadSomeStops()

        #expect(RouteFilterOptions.content(stops: stops, isZoomedOut: false) == .routes(RouteFilterOptions.routes(from: stops)))
    }
}
