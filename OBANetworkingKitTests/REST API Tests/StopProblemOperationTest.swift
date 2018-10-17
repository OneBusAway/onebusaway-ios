//
//  StopProblemOperationTest.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/12/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
@testable import OBANetworkingKit

class StopProblemOperationTest: OBATestCase {
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

    func testURLConstruction() {
        let url = StopProblemOperation.buildURL(stopID: stopID, code: .locationWrong, comment: comment, location: location, baseURL: baseURL, queryItems: restService.defaultQueryItems)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        expect(components?.queryItemValueMatching(name: "code")) == "stop_location_wrong"
        expect(components?.queryItemValueMatching(name: "stopId")) == stopID
        expect(components?.queryItemValueMatching(name: "userComment")) == comment
        expect(components?.queryItemValueMatching(name: "userLat")) == "47.1"
        expect(components?.queryItemValueMatching(name: "userLon")) == "-122.1"
    }

    func testSuccessfulRequest() {
        stub(condition: isHost(host) &&
                        isPath(StopProblemOperation.apiPath) &&
                        containsQueryParams(self.expectedParams)) { _ in
            return self.JSONFile(named: "report_stop_problem.json")
        }

        waitUntil { done in
            self.restService.getStopProblem(stopID: self.stopID, code: .locationWrong, comment: self.comment, location: self.location) { (op) in
                expect(op.response!.statusCode) == 200
                done()
            }
        }
    }
}
