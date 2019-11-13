//
//  StopsModelOperationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/1/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
import MapKit
@testable import OBAKit
@testable import OBAKitCore

class StopsModelOperationTests: OBATestCase {
    let coordinate = CLLocationCoordinate2D(latitude: 47.6230999, longitude: -122.3132122)

    func stubApiCall() {
        stub(condition: isHost(self.host) && isPath(StopsOperation.apiPath)) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "stops_for_location_seattle.json")
        }
    }

    func checkExpectations(_ op: StopsModelOperation) {
        expect(op.stops.count) == 26

        let stop = op.stops.first!

        expect(stop.code) == "10914"
        expect(stop.direction) == .s
        expect(stop.id) == "1_10914"
        expect(stop.location.coordinate.latitude).to(beCloseTo(47.656422))
        expect(stop.location.coordinate.longitude).to(beCloseTo(-122.312164))
        expect(stop.locationType) == .stop
        expect(stop.name) == "15th Ave NE & NE Campus Pkwy"

        expect(stop.routes.count) == 12
        expect(stop.routes.first!.id) == "1_100223"

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

    func testLoading_circularRegion_success() {
        stubApiCall()

        waitUntil { done in
            let circularRegion = CLCircularRegion(center: self.coordinate, radius: 100.0, identifier: "query")
            let op = self.restModelService.getStops(circularRegion: circularRegion, query: "query")
            op.completionBlock = {
                self.checkExpectations(op)
                done()
            }
        }
    }
    
    func testLoading_invalidCoordinate() {
        // http://api.pugetsound.onebusaway.org/api/where/stops-for-location.json?lat=nan&lon=nan&latSpan=0.0&lonSpan=0.0&key=test&app_uid=0C816EC3-753B-4D17-A837-DF624E2F12F4&app_ver=1.0&version=2
        
        stub(condition: isHost(self.host) && isPath(StopsOperation.apiPath)) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "stops_for_location_field_errors.json")
        }
        
        waitUntil { done in
            let op = self.restModelService.getStops(region: MKCoordinateRegion(center: kCLLocationCoordinate2DInvalid, span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0)))
            op.completionBlock = {
                self.checkExpectations(op)
                done()
            }
        }
    }
}
