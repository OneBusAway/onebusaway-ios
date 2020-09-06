//
//  StopsModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
import MapKit
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

class StopsModelOperationTests: OBATestCase {
    let coordinate = CLLocationCoordinate2D(latitude: 47.6230999, longitude: -122.3132122)
    let urlString = "https://www.example.com/api/where/stops-for-location.json"

    var dataLoader: MockDataLoader!

    override func setUp() {
        super.setUp()
        dataLoader = (restService.dataLoader as! MockDataLoader)
    }

    func stubApiCall() {
        dataLoader.mock(
            URLString: urlString,
            with: Fixtures.loadData(file: "stops_for_location_seattle.json")
        )
    }

    func checkExpectations(_ response: RESTAPIResponse<[Stop]>) {
        let stops = response.list

        expect(stops.count) == 26

        let stop = stops.first!

        expect(stop.code) == "10914"
        expect(stop.direction) == .s
        expect(stop.id) == "1_10914"
        expect(stop.location.coordinate.latitude).to(beCloseTo(47.656422))
        expect(stop.location.coordinate.longitude).to(beCloseTo(-122.312164))
        expect(stop.locationType) == .stop
        expect(stop.name) == "15th Ave NE & NE Campus Pkwy"

        expect(stop.routes.count) == 12
        expect(stop.routes.first!.id) == "1_100059"     // Test that routes get sorted by ID.

        expect(stop.wheelchairBoarding) == .unknown
    }

    func testLoading_coordinate_success() {
        stubApiCall()

        let op = restService.getStops(coordinate: coordinate)

        waitUntil { done in
            op.complete { result in
                switch result {
                case .failure:
                    fatalError()
                case .success(let response):
                    self.checkExpectations(response)
                    done()
                }
            }
        }
    }

    func testLoading_region_success() {
        stubApiCall()

        let op = restService.getStops(region: MKCoordinateRegion(center: self.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)))

        waitUntil { done in
            op.complete { result in
                switch result {
                case .failure:
                    fatalError()
                case .success(let response):
                    self.checkExpectations(response)
                    done()
                }
            }
        }
    }

    func testLoading_circularRegion_success() {
        stubApiCall()

        let circularRegion = CLCircularRegion(center: self.coordinate, radius: 100.0, identifier: "query")
        let op = self.restService.getStops(circularRegion: circularRegion, query: "query")

        waitUntil { done in
            op.complete { result in
                switch result {
                case .failure:
                    fatalError()
                case .success(let response):
                    self.checkExpectations(response)
                    done()
                }
            }
        }
    }
}
