//
//  StopsOperationTest.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 10/4/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
import MapKit
@testable import OBAKit
@testable import OBAKitCore

class StopsOperationTest: OBATestCase {
    let defaultCoordinate = CLLocationCoordinate2D(latitude: 47.624, longitude: -122.32)

    // MARK: - Stops Near Coordinate

    func testRetrievingStopsNearCoordinate() {
        let expectedParams = ["lat": "47.624", "lon": "-122.32"]

        stub(condition: isHost(self.host) &&
            isPath(StopsOperation.apiPath) &&
            containsQueryParams(expectedParams)) { _ in
                return OHHTTPStubsResponse.JSONFile(named: "stops_for_location_seattle.json")
        }

        waitUntil { done in
            let op = self.restService.getStops(coordinate: self.defaultCoordinate)
            op.completionBlock = {
                expect(op.entries?.first).toNot(beNil())
                done()
            }
        }
    }

    // MARK: - Stops in Circular Region

    func testRadiusIsClampedAt15000() {
        let region = CLCircularRegion(center: defaultCoordinate, radius: 30000, identifier: "ident")
        let url = StopsOperation.buildURL(circularRegion: region, query: "query!", baseURL: baseURL, defaultQueryItems: [])
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        let lat = components?.queryItemValueMatching(name: "lat")
        let lon = components?.queryItemValueMatching(name: "lon")
        let query = components?.queryItemValueMatching(name: "query")
        let radius = components?.queryItemValueMatching(name: "radius")
        expect(lat).to(equal("47.624"))
        expect(lon).to(equal("-122.32"))
        expect(query).to(equal("query!"))
        expect(radius).to(equal("15000"))
    }

    func testQueryInCircularRegion() {
        let region = CLCircularRegion(center: defaultCoordinate, radius: 30000, identifier: "ident")
        let expectedParams: [String: String] = [
            "lat": String(defaultCoordinate.latitude),
            "lon": String(defaultCoordinate.longitude),
            "query": "query!",
            "radius": "15000"
        ]

        stub(condition: isHost(self.host) && isPath(StopsOperation.apiPath) && containsQueryParams(expectedParams)) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "stops_for_location_seattle_span.json")
        }

        waitUntil { done in
            let op = self.restService.getStops(circularRegion: region, query: "query!")
            op.completionBlock = {
                let entries = op.entries!
                expect(entries.count) == 1
                done()
            }
        }
    }

    // MARK: - Stops in Coordinate Region

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
            return OHHTTPStubsResponse.JSONFile(named: "stops_for_location_seattle_span.json")
        }

        waitUntil { done in
            let op = self.restService.getStops(region: region)
            op.completionBlock = {
                expect(op.entries?.count).to(equal(1))
                done()
            }
        }
    }
}
