//
//  StopsForRouteOperationTest.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 10/7/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBAKit

// swiftlint:disable force_cast

class StopsForRouteOperationTest: OBATestCase {
    func testStopsForRouteAPIPath() {
        expect(StopsForRouteOperation.buildAPIPath(routeID: "Hello/World")) == "/api/where/stops-for-route/Hello%2FWorld.json"
    }

    func testSuccessfulStopsForRouteRequest() {
        let routeID = "1_100002"
        let apiPath = StopsForRouteOperation.buildAPIPath(routeID: routeID)
        stub(condition: isHost(self.host) && isPath(apiPath)) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "stops-for-route-1_100002.json")
        }

        waitUntil { done in
            let op = self.restService.getStopsForRoute(id: routeID)
            op.completionBlock = {
                expect(op.entries?.count) == 1

                let entry = op.entries!.first!
                expect(entry["routeId"] as? String) == "1_100002"

                let polylines = entry["polylines"] as! [Any]
                expect(polylines.count) == 14

                let references = op.references!
                let agencies = references["agencies"] as! [Any]
                expect(agencies.count) == 2

                let routes = references["routes"] as! [Any]
                expect(routes.count) == 46

                done()
            }
        }
    }
}
