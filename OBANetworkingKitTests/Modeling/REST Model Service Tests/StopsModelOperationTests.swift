//
//  StopsModelOperationTests.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 11/1/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
import MapKit
@testable import OBANetworkingKit

class StopsModelOperationTests: OBATestCase {
    let coordinate = CLLocationCoordinate2D(latitude: 47.6230999, longitude: -122.3132122)

    func stubApiCall() {
        stub(condition: isHost(self.host) && isPath(StopsOperation.apiPath)) { _ in
            return self.JSONFile(named: "stops_for_location_seattle.json")
        }
    }

    func checkExpectations(_ op: StopsModelOperation) {
        expect(op.stops.count) == 26

        let stop = op.stops.first!

        expect(stop.code) == "10914"
        expect(stop.direction) == "S"
        expect(stop.id) == "1_10914"
        expect(stop.location.coordinate.latitude).to(beCloseTo(47.656422))
        expect(stop.location.coordinate.longitude).to(beCloseTo(-122.312164))
        expect(stop.locationType) == .stop
        expect(stop.name) == "15th Ave NE & NE Campus Pkwy"
        expect(stop.routeIDs.count) == 12
        expect(stop.routeIDs.first!) == "1_100223"
        expect(stop.wheelchairBoarding) == .unknown
    }

    func testLoading_coordinate_success() {
        stubApiCall()

        waitUntil { done in
            let op = self.restModelService.getStops(coordinate: self.coordinate)
            op.completionBlock = {
                self.checkExpectations(op)
                done()
            }
        }
    }

    func testLoading_region_success() {
        stubApiCall()

        waitUntil { done in
            let op = self.restModelService.getStops(region: MKCoordinateRegion(center: self.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)))
            op.completionBlock = {
                self.checkExpectations(op)
                done()
            }
        }
    }
}
