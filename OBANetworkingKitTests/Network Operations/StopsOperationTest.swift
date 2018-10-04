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
                stub(condition: isHost(self.host) && isPath(StopsOperation.apiPath)) { _ in
                    return self.JSONFile(named: "stops_for_location_downtown_seattle1.json")
                }
            }
            afterSuite { OHHTTPStubs.removeAllStubs() }

            it("returns the expected list of stops") {
                waitUntil { done in
                    self.builder.getStops(coordinate: coordinate) { op in
                        expect(op.entry).toNot(beNil())
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
