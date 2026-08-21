//
//  RouteStopsSheetViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Row mapping for the route-stops sheet, asserted without a view host.
@MainActor
@Suite(.serialized)
final class RouteStopsSheetViewTests {

    private func loadStopsForRoute() throws -> StopsForRoute {
        try Fixtures.loadRESTAPIPayload(type: StopsForRoute.self, fileName: "stops_for_route_1_44.json")
    }

    @Test func `Rows carry each stop name and id`() throws {
        let stopsForRoute = try loadStopsForRoute()
        let rows = RouteStopsRow.rows(from: stopsForRoute)

        #expect(rows.count == (stopsForRoute.stops ?? []).count)
        let first = try #require(rows.first)
        let firstStop = try #require(stopsForRoute.stops?.first)
        #expect(first.title == firstStop.name)
        #expect(first.stopID == firstStop.id)
    }

    /// `RouteStopsViewController` renders the adjective form of the stop's cardinal
    /// direction as its subtitle; the SwiftUI rows must match.
    @Test func `Rows use the adjective form of the stop direction`() throws {
        let stopsForRoute = try loadStopsForRoute()
        let rows = RouteStopsRow.rows(from: stopsForRoute)
        let firstStop = try #require(stopsForRoute.stops?.first)

        let expected = Formatters.adjectiveFormOfCardinalDirection(firstStop.direction) ?? ""
        #expect(rows.first?.subtitle == expected)
    }

    /// `StopsForRoute.stops` is an implicitly-unwrapped optional populated by
    /// `HasReferences`. `RouteStopsViewController` force-unwraps it; the sheet must
    /// not.
    @Test func `Rows are empty when stops have not been resolved`() throws {
        let stopsForRoute = try Fixtures.dictionaryToModel(
            type: StopsForRoute.self,
            dictionary: [
                "routeId": "1_44",
                "polylines": [],
                "stopIds": [],
                "stopGroupings": []
            ]
        )

        #expect(RouteStopsRow.rows(from: stopsForRoute).isEmpty)
    }
}
