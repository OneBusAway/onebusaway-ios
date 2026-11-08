//
//  ReferencesExtendedTests.swift
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

/// Tests for `References` decoding from full transit response fixtures,
/// cross-referencing agencies, routes, situations, and stops indexing.
@Suite(.serialized)
final class ReferencesExtendedTests: OBATestCase {

    private var references: References!

    override init() async throws {
        try await super.init()
        let data = Fixtures.loadData(file: "references.json")
        references = try JSONDecoder.RESTDecoder(regionIdentifier: 0).decode(References.self, from: data)
    }

    // MARK: - Routes Collection

    @Test func `References routes are populated with valid agency cross-references`() {
        let routes = references.routes
        #expect(!routes.isEmpty)

        for route in routes {
            #expect(!route.id.isEmpty)
            #expect(!route.agencyID.isEmpty)
            #expect(route.agency != nil)
            #expect(route.agency?.id == route.agencyID)
        }
    }

    // MARK: - Stops Collection

    @Test func `References stops are populated with route associations`() {
        let stops = references.stops
        #expect(!stops.isEmpty)

        for stop in stops {
            #expect(!stop.id.isEmpty)
            #expect(!stop.name.isEmpty)
            #expect(!stop.routeIDs.isEmpty)
        }
    }

    // MARK: - Situations Collection

    @Test func `References situations decode service alerts with valid summaries`() throws {
        let alertData = Fixtures.loadData(file: "arrival-and-departure-for-stop-MTS_11589.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<ArrivalDeparture>.self, from: alertData)
        let alertReferences = try #require(response.references)
        let situations = alertReferences.serviceAlerts
        #expect(!situations.isEmpty)

        for alert in situations {
            #expect(!alert.id.isEmpty)
            #expect(alert.summary != nil)
        }
    }

    // MARK: - Lookup Performance and Completeness

    @Test func `References routes can be indexed by route ID into dictionary`() {
        let routeMap = Dictionary(uniqueKeysWithValues: references.routes.map { ($0.id, $0) })
        #expect(routeMap.count == references.routes.count)

        for route in references.routes {
            #expect(routeMap[route.id] === route)
        }
    }

    @Test func `References stops can be indexed by stop ID into dictionary`() {
        let stopMap = Dictionary(uniqueKeysWithValues: references.stops.map { ($0.id, $0) })
        #expect(stopMap.count == references.stops.count)

        for stop in references.stops {
            #expect(stopMap[stop.id] === stop)
        }
    }
}
