//
//  TripProblemModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

@Suite(.serialized)
final class TripProblemModelOperationTests: OBATestCase {
    let tripID = "123456"
    let serviceDate = Date(timeIntervalSince1970: 101010101)
    let vehicleID = "987654321"
    let stopID = "1_1234"
    let code = TripProblemCode.neverCame
    let comment = "comment comment comment"
    let userOnVehicle = true
    let location = CLLocation(latitude: 47.1, longitude: -122.1)
    lazy var expectedParams: [String: String] = [
        "tripId": tripID,
        "serviceDate": "101010101000",
        "code": "vehicle_never_came",
        "vehicleId": vehicleID,
        "userOnVehicle": "true",
        "stopId": stopID,
        "userComment": comment,
        "userLat": "47.1",
        "userLon": "-122.1"
    ]

    @Test func `Successful request`() async throws {
        let dataLoader = (restService.dataLoader as! MockDataLoader)

        // Hoisted: the matcher is @Sendable, so it must not capture `self` — the
        // suite is main-actor isolated and `expectedParams` with it.
        let expectedParams = self.expectedParams
        dataLoader.mock(data: Fixtures.loadData(file: "report_trip_problem.json")) { request -> Bool in
            let url = request.url!
            return url.absoluteString.starts(with: "https://www.example.com/api/where/report-problem-with-trip.json")
            && url.containsQueryParams(expectedParams)
        }

        let report = RESTAPIService.TripProblemReport(tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopID: stopID, code: code, comment: comment, userOnVehicle: userOnVehicle, location: location)
        let response = try await restService.getTripProblem(report: report)
        #expect(response.code == 200)
    }
}
