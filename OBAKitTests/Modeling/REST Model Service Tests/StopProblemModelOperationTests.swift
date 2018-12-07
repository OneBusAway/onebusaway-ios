//
//  StopProblemModelOperationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import OBATestHelpers
import Nimble
import OHHTTPStubs
import CoreLocation
@testable import OBAKit

class StopProblemModelOperationTests: OBATestCase {
    let stopID = "1_1234"
    let comment = "comment comment comment"
    let location = CLLocation(latitude: 47.1, longitude: -122.1)
    lazy var expectedParams = [
        "code": "stop_location_wrong",
        "stopId": stopID,
        "userComment": comment,
        "userLat": "47.1",
        "userLon": "-122.1"
    ]

    func stubAPICall() {
        stub(condition: isHost(host) &&
            isPath(StopProblemOperation.apiPath) &&
            containsQueryParams(self.expectedParams)) { _ in
                return self.JSONFile(named: "report_stop_problem.json")
        }
    }

    func testSuccessfulRequest() {
        stubAPICall()
        waitUntil { done in
            let op = self.restModelService.getStopProblem(stopID: self.stopID, code: .locationWrong, comment: self.comment, location: self.location)
            op.completionBlock = {
                expect(op.success).to(beTrue())
                done()
            }
        }
    }
}
