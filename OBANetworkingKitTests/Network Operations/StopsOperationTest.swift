//
//  StopsOperationTest.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/4/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
import MapKit
@testable import OBANetworkingKit

class StopsOperationTest: XCTestCase, OperationTest {

    override func tearDown() {
        super.tearDown()
        OHHTTPStubs.removeAllStubs()
    }

    func testRetrievingStopsNearCoordinate() {
        let coordinate = CLLocationCoordinate2D(latitude: 47.624, longitude: -122.32)
        let expectedParams = ["lat": "47.624", "lon": "-122.32"]

        stub(condition: isHost(self.host) &&
            isPath(StopsOperation.apiPath) &&
            containsQueryParams(expectedParams)) { _ in
                return self.JSONFile(named: "stops_for_location_seattle.json")
        }

        waitUntil { done in
            self.builder.getStops(coordinate: coordinate) { op in
                expect(op.entries?.first).toNot(beNil())
                done()
            }
        }
    }

    func testRetrievingStopsInACoordinateRegions() {
        let coordinate = CLLocationCoordinate2D(latitude: 47.6230999, longitude: -122.3132122)
        let span = MKCoordinateSpan(latitudeDelta: 0.0015, longitudeDelta: 0.0015)
        let region = MKCoordinateRegion(center: coordinate, span: span)

        let expectedParams = [
            "lat": "47.6230999",
            "lon": "-122.3132122",
            "latSpan": "0.0015",
            "lonSpan": "0.0015"
        ]

        stub(condition: isHost(self.host) && isPath(StopsOperation.apiPath) && containsQueryParams(expectedParams)) { _ in
            return self.JSONFile(named: "stops_for_location_seattle_span.json")
        }

        waitUntil { done in
            self.builder.getStops(region: region) { op in
                expect(op.entries?.count).to(equal(1))
                done()
            }
        }
    }
}
