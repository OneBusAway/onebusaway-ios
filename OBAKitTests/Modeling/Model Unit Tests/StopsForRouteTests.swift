//
//  StopsForRouteTests.swift
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

// swiftlint:disable force_try force_cast

@Suite(.serialized)
final class StopsForRouteTests: OBATestCase {

    private func loadStopsForRoutePayload(fileName: String = "stops-for-route-1_100002.json") throws -> RESTAPIResponse<StopsForRoute> {
        let data = Fixtures.loadData(file: fileName)
        return try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<StopsForRoute>.self, from: data)
    }

    // MARK: - Decoding and Identity

    @Test func `StopsForRoute decoding and route identification`() throws {
        let response = try loadStopsForRoutePayload()
        let entry = response.entry

        #expect(entry.id == "1_100002")
        #expect(entry.routeID == "1_100002")
        #expect(entry.route != nil)
        #expect(entry.route.id == "1_100002")
        #expect(entry.route.shortName == "10")
        #expect(entry.route.agencyID == "1")
    }

    // MARK: - Polylines and MapRect Bounds

    @Test func `StopsForRoute decodes polylines and computes bounding mapRect`() throws {
        let response = try loadStopsForRoutePayload()
        let entry = response.entry

        #expect(!entry.rawPolylines.isEmpty)
        #expect(entry.polylines.count == entry.rawPolylines.count)

        // Verify computed bounding mapRect contains valid geometric bounds
        let mapRect = entry.mapRect
        #expect(!MKMapRectIsNull(mapRect))
        #expect(!MKMapRectIsEmpty(mapRect))
        #expect(mapRect.size.width > 0)
        #expect(mapRect.size.height > 0)
    }

    // MARK: - Stops and References

    @Test func `StopsForRoute resolves stop references in route and groupings`() throws {
        let response = try loadStopsForRoutePayload()
        let entry = response.entry

        #expect(entry.stops.count == 35)
        for stop in entry.stops {
            #expect(!stop.id.isEmpty)
            #expect(!stop.name.isEmpty)
        }
    }

    // MARK: - StopGroupings and StopGroups

    @Test func `StopsForRoute groupings and groups hierarchy`() throws {
        let response = try loadStopsForRoutePayload()
        let entry = response.entry

        #expect(entry.stopGroupings.count == 1)
        let grouping = try #require(entry.stopGroupings.first)
        #expect(grouping.ordered == true)
        #expect(grouping.groupingType == "direction")
        #expect(grouping.stopGroups.count == 2)

        // Direction 0 Group
        let group0 = grouping.stopGroups[0]
        #expect(group0.id == "0")
        #expect(group0.name == "Capitol Hill Via 15th Ave E")
        #expect(group0.groupingType == "destination")
        #expect(group0.stops.count == 19)
        #expect(!group0.polylines.isEmpty)

        // Direction 1 Group
        let group1 = grouping.stopGroups[1]
        #expect(group1.id == "1")
        #expect(group1.name == "Downtown Seattle Via 15th Ave E")
        #expect(group1.groupingType == "destination")
        #expect(group1.stops.count == 16)
        #expect(!group1.polylines.isEmpty)
    }

    // MARK: - Region Identifier Propagation

    @Test func `Region identifier propagates to nested stop groupings and groups`() throws {
        let response = try loadStopsForRoutePayload()
        let entry = response.entry

        entry.loadReferences(response.references, regionIdentifier: 99)
        #expect(entry.regionIdentifier == 99)

        for grouping in entry.stopGroupings {
            #expect(grouping.regionIdentifier == 99)
            for group in grouping.stopGroups {
                #expect(group.regionIdentifier == 99)
            }
        }
    }
}
