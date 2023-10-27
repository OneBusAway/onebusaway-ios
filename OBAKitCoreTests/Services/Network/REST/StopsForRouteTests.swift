//
//  StopsForRouteTests.swift
//  OBAKitCoreTests
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import OBAKitCore

final class StopsForRouteTests: OBAKitCoreTestCase {
    let routeID = "12345"

    func testLoading() async throws {
        dataLoader.mock(
            URLString: "https://www.example.com/api/where/stops-for-route/\(routeID).json",
            with: try Fixtures.loadData(file: "stops-for-route-1_100002.json")
        )

        let response = try await restAPIService.getStopsForRoute(routeID: routeID)
        let stopsForRoute = response.entry

//        XCTAssertEqual(stopsForRoute.route.routeDescription, "Capitol Hill - Downtown Seattle")
        XCTAssertEqual(stopsForRoute.polylines.count, 14)
        XCTAssertEqual(stopsForRoute.polylines.first?.points, "afvaHbdpiV^?pIFdKDj@?L?xC@tC?f@?xB?`DBn@@rB?B?b@?t@@lC@^?h@?`DBZ?`DB~BHhB@?~A?z@@bD?~B@`C@bC?bC?vB@hC@bC?bC?jG@rA?n@?bC@nBD~@JlAJr@Lv@Rn@Vv@NVR`@^h@h@r@pAbAtC|BbChBdA?lA?`FBCzA?|BPn@j@nB|A~EzA|En@lBl@lBh@dB")

        XCTAssertEqual(stopsForRoute.stopIDs.count, 35)
//        XCTAssertEqual(stopsForRoute.stops.count, 35)
        XCTAssertEqual(stopsForRoute.stopGroupings.count, 1)

        let stopGrouping = try XCTUnwrap(stopsForRoute.stopGroupings.first)
        XCTAssertTrue(stopGrouping.ordered)
        XCTAssertEqual(stopGrouping.groupingType, "direction")
        XCTAssertEqual(stopGrouping.stopGroups.count, 2)

        let group = try XCTUnwrap(stopGrouping.stopGroups.first)
        XCTAssertEqual(group.id, "0")
        XCTAssertEqual(group.name, "Capitol Hill Via 15th Ave E")
        XCTAssertEqual(group.groupingType, "destination")
        XCTAssertEqual(group.polylines.count, 2)
        XCTAssertEqual(group.polylines.first?.points, "uzqaHr{tiVCIm@oBo@mBk@mBo@mBm@oBm@oB{A}EgAeDUw@o@mBQi@Oi@Ws@oAeEc@qAI[o@oBUu@ESC]@}AaF?aFC_@?sB?cCiBuC}BqAcAu@cASYSa@OWWw@So@Mw@Ks@KmAE_AAoB?cCAcC?qA?yD?cCAcCAaG?eB?]AcCAaC?_CAcD?{A?_AiBA_CIaDC[?aB?iBC_@?cECc@?C?cDA_@?aCCaD?i@?kB?yCAy@?i@?{IEe@?kHG?oBe@CuHAI?AnCTOr@M|FB")
        XCTAssertEqual(group.stopIDs.count, 19)
        XCTAssertEqual(group.stopIDs.first, "1_1085")
//        XCTAssertEqual(group.stops.count, 19)
//        XCTAssertEqual(group.stops.first?.id, "1_1085")
    }
}
