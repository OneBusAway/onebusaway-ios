//
//  RouteSearchTests.swift
//  OBAKitCoreTests
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import CoreLocation
@testable import OBAKitCore

final class RouteSearchTests: OBAKitCoreTestCase {
    func testRouteSearching() async throws {
        self.dataLoader.mock(
            URLString: "https://www.example.com/api/where/routes-for-location.json", 
            with: try Fixtures.loadData(file: "routes-for-location-10.json")
        )
        let query = "Link"
        let center = CLLocationCoordinate2D(latitude: 47.0, longitude: -122)
        let radius = 5000.0
        lazy var region = CLCircularRegion(center: center, radius: radius, identifier: "identifier")

        let response = try await restAPIService.getRoute(query: query, region: region)
        let routes = response.list

        XCTAssertEqual(routes.count, 1)
        let route = try XCTUnwrap(routes.first)

        XCTAssertEqual(route.agencyID, "1")
        XCTAssertEqual(route.routeDescription, "Capitol Hill - Downtown Seattle")
        XCTAssertEqual(route.id, "1_100002")
        XCTAssertNil(route.longName)
        XCTAssertEqual(route.shortName, "10")
        XCTAssertNil(route.color)
        XCTAssertNil(route.textColor)
        XCTAssertEqual(route.routeType, .bus)
        XCTAssertEqual(route.routeURL?.absoluteString, "http://metro.kingcounty.gov/schedules/010/n0.html")
    }
}

