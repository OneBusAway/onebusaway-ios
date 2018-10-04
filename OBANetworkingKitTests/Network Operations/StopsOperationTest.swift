//
//  StopsOperationTest.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/4/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Quick
import Nimble
import OHHTTPStubs
import CoreLocation
@testable import OBANetworkingKit

class StopsOperationTest: OperationTest {

    private func testStopsNearCoordinate() {
        describe("Retrieving stops near a coordinate") {
            let coordinate = CLLocationCoordinate2D(latitude: 47.6230999, longitude: -122.3132122)

            beforeSuite {
                return OHHTTPStubs.stubRequests(passingTest: { req -> Bool in
                    guard let url = req.url else {
                        return false
                    }

                    let sameHost = url.host == self.host
                    let samePath = url.path == StopsOperation.apiPath

                    return sameHost && samePath
                }, withStubResponse: { (req) -> OHHTTPStubsResponse in
                    let file = self.JSONFile(named: "stops_for_location_seattle.json")
                    return file
                })
            }
            afterSuite { OHHTTPStubs.removeAllStubs() }

            it("returns the expected list of stops") {
                waitUntil(timeout: 240.0) { done in
                    self.builder.getStops(coordinate: coordinate) { op in
                        expect(op.entries?.first).toNot(beNil())
                        done()
                    }
                }
            }
        }
    }

    override func spec() {
        testStopsNearCoordinate()
    }
}
