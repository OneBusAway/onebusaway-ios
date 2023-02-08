//
//  StopProblemModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

class StopProblemModelOperationTests: OBATestCase {
    let stopID = "1_1234"
    let comment = "comment comment comment"
    let location = CLLocation(latitude: 47.1, longitude: -122.1)
    lazy var expectedParams = [
        "code": StopProblemCode.locationWrong.APIStringValue,
        "userComment": comment,
        "userLat": "47.1",
        "userLon": "-122.1"
    ]

    func testSuccessfulRequest() async throws {
        let dataLoader = (restService.dataLoader as! MockDataLoader)

        dataLoader.mock(data: Fixtures.loadData(file: "report_stop_problem.json")) { request -> Bool in
            let url = request.url!
            return url.absoluteString.starts(with: "https://www.example.com/api/where/report-problem-with-stop/1_1234.json")
            && url.containsQueryParams(self.expectedParams)
        }

        let report = RESTAPIService.StopProblemReport(stopID: stopID, code: .locationWrong, comment: comment, location: location)
        let response = try await restService.getStopProblem(report: report)
        expect(response.code) == 200
    }
}
