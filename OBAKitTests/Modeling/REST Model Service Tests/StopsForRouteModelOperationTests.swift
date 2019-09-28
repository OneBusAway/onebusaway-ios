//
//  StopsForRouteModelOperationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
import MapKit
@testable import OBAKit
@testable import OBAKitCore

class StopsForRouteModelOperationTests: OBATestCase {
    let routeID = "12345"
    lazy var apiPath = StopsForRouteOperation.buildAPIPath(routeID: routeID)

    func stubAPICall() {
        stub(condition: isHost(self.host) && isPath(self.apiPath)) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "stops-for-route-1_100002.json")
        }
    }

    func testLoading_success() {
        stubAPICall()

        waitUntil { (done) in
            let op = self.restModelService.getStopsForRoute(routeID: self.routeID)
            op.completionBlock = {
                let stopsForRoute = op.stopsForRoute!

                expect(stopsForRoute.route.routeDescription) == "Capitol Hill - Downtown Seattle"
                expect(stopsForRoute.polylines.count) == 14
                expect(stopsForRoute.rawPolylines.first) == "afvaHbdpiV^?pIFdKDj@?L?xC@tC?f@?xB?`DBn@@rB?B?b@?t@@lC@^?h@?`DBZ?`DB~BHhB@?~A?z@@bD?~B@`C@bC?bC?vB@hC@bC?bC?jG@rA?n@?bC@nBD~@JlAJr@Lv@Rn@Vv@NVR`@^h@h@r@pAbAtC|BbChBdA?lA?`FBCzA?|BPn@j@nB|A~EzA|En@lBl@lBh@dB"

                expect(stopsForRoute.stops.count) == 35
                expect(stopsForRoute.stopGroupings.count) == 1
                let stopGrouping = stopsForRoute.stopGroupings.first!

                expect(stopGrouping.ordered).to(beTrue())
                expect(stopGrouping.groupingType) == "direction"
                expect(stopGrouping.stopGroups.count) == 2

                let group = stopGrouping.stopGroups.first!
                expect(group.id) == "0"
                expect(group.name) == "Capitol Hill Via 15th Ave E"
                expect(group.groupingType) == "destination"
                expect(group.polylines.count) == 2
                expect(group.polylines.first!) == "uzqaHr{tiVCIm@oBo@mBk@mBo@mBm@oBm@oB{A}EgAeDUw@o@mBQi@Oi@Ws@oAeEc@qAI[o@oBUu@ESC]@}AaF?aFC_@?sB?cCiBuC}BqAcAu@cASYSa@OWWw@So@Mw@Ks@KmAE_AAoB?cCAcC?qA?yD?cCAcCAaG?eB?]AcCAaC?_CAcD?{A?_AiBA_CIaDC[?aB?iBC_@?cECc@?C?cDA_@?aCCaD?i@?kB?yCAy@?i@?{IEe@?kHG?oBe@CuHAI?AnCTOr@M|FB"
                expect(group.stops.count) == 19
                expect(group.stops.first!.id) == "1_1085"

                done()
            }
        }
    }
}
