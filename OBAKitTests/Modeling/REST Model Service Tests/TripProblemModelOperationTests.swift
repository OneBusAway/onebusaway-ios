//
//  TripProblemModelOperationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
import OBATestHelpers
@testable import OBAKit

class TripProblemModelOperationTests: OBATestCase {
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

    func testSuccessfulRequest() {
        stub(condition: isHost(host) &&
            isPath(TripProblemOperation.apiPath) &&
            containsQueryParams(self.expectedParams)) { _ in
                return self.JSONFile(named: "report_trip_problem.json")
        }

        waitUntil { done in
            let op = self.restModelService.getTripProblem(tripID: self.tripID, serviceDate: self.serviceDate, vehicleID: self.vehicleID, stopID: self.stopID, code: self.code, comment: self.comment, userOnVehicle: self.userOnVehicle, location: self.location)
            op.completionBlock = {
                expect(op.success).to(beTrue())
                done()
            }
        }
    }
}
