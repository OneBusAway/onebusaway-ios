//
//  TripProblemOperationTest.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/14/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
@testable import OBANetworkingKit

class TripProblemOperationTest: OBATestCase {
    let tripID = "123456"
    let serviceDate = Int64(101010101)
    let vehicleID = "987654321"
    let stopID = "1_1234"
    let code = TripProblemCode.neverCame
    let comment = "comment comment comment"
    let userOnVehicle = true
    let location = CLLocation(latitude: 47.1, longitude: -122.1)
    lazy var expectedParams: [String: String] = [
        "tripId": tripID,
        "serviceDate": "101010101",
        "code": "vehicle_never_came",
        "vehicleId": vehicleID,
        "userOnVehicle": "true",
        "stopId": stopID,
        "userComment": comment,
        "userLat": "47.1",
        "userLon": "-122.1"
    ]

    func testURLConstruction() {
        let url = TripProblemOperation.buildURL(tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopID: stopID, code: code, comment: comment, userOnVehicle: userOnVehicle, location: location, baseURL: baseURL, queryItems: [URLQueryItem(name: "key", value: "value")])
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        expect(components?.queryItemValueMatching(name: "tripId")) == tripID
        expect(components?.queryItemValueMatching(name: "serviceDate")) == "101010101"
        expect(components?.queryItemValueMatching(name: "code")) == "vehicle_never_came"
        expect(components?.queryItemValueMatching(name: "vehicleId")) == vehicleID
        expect(components?.queryItemValueMatching(name: "userOnVehicle")) == "true"
        expect(components?.queryItemValueMatching(name: "stopId")) == stopID
        expect(components?.queryItemValueMatching(name: "userComment")) == comment
        expect(components?.queryItemValueMatching(name: "userLat")) == "47.1"
        expect(components?.queryItemValueMatching(name: "userLon")) == "-122.1"
    }

    func testSuccessfulRequest() {
        stub(condition: isHost(host) &&
            isPath(TripProblemOperation.apiPath) &&
            containsQueryParams(self.expectedParams)) { _ in
                return self.JSONFile(named: "report_trip_problem.json")
        }

        waitUntil { done in
            self.restService.getTripProblem(tripID: self.tripID, serviceDate: self.serviceDate, vehicleID: self.vehicleID, stopID: self.stopID, code: self.code, comment: self.comment, userOnVehicle: self.userOnVehicle, location: self.location) { (op) in
                expect(op.response!.statusCode) == 200
                done()
            }
        }
    }
}
