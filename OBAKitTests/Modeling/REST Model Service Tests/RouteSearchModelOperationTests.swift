//
//  RouteSearchModelOperationTests.swift
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

class RouteSearchModelOperationTests: OBATestCase {
    let query = "Link"
    let center = CLLocationCoordinate2D(latitude: 47.0, longitude: -122)
    let radius = 5000.0
    lazy var region = CLCircularRegion(center: center, radius: radius, identifier: "identifier")

    func stubAPICall() {
        stub(condition: isHost(self.host) && isPath(RouteSearchOperation.apiPath)) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "routes-for-location-10.json")
        }
    }

    func testLoading_success() {
        stubAPICall()

        waitUntil { (done) in
            let op = self.restModelService.getRoute(query: self.query, region: self.region)
            op.completionBlock = {
                let routes = op.routes

                expect(routes.count) == 1

                let route = routes.first!

                expect(route.agency.id) == "1"
                expect(route.agency.name) == "Metro Transit"
                expect(route.color).to(beNil())
                expect(route.routeDescription) == "Capitol Hill - Downtown Seattle"
                expect(route.id) == "1_100002"
                expect(route.longName).to(beNil())
                expect(route.shortName) == "10"
                expect(route.textColor).to(beNil())
                expect(route.routeType) == .bus
                expect(route.routeURL) == URL(string: "http://metro.kingcounty.gov/schedules/010/n0.html")!

                done()
            }
        }
    }
}
