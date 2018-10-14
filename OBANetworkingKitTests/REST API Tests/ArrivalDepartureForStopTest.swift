//
//  ArrivalDepartureForStopTest.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/6/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBANetworkingKit

class ArrivalDepartureForStopTest: OBATestCase {
    let stopID = "stop_123"
    let tripID = "trip_123"
    let serviceDate: Int64 = 1234567890
    let vehicleID = "vehicle_123"
    let stopSequence = 1

    func testOperation_success() {
        let apiPath = ArrivalDepartureForStopOperation.buildAPIPath(stopID: stopID)
        let expectedParams: [String: String] = [
            "tripId": tripID,
            "serviceDate": String(serviceDate),
            "vehicleId": vehicleID,
            "stopSequence": String(stopSequence)
            ]

        stub(condition: isHost(self.host) &&
                        isPath(apiPath) &&
                        containsQueryParams(expectedParams)) { _ in
            return self.JSONFile(named: "arrival-and-departure-for-stop-1_11420.json")
        }

        waitUntil { done in
            self.builder.getTripArrivalDepartureForStop(stopID: self.stopID, tripID: self.tripID, serviceDate: self.serviceDate, vehicleID: self.vehicleID, stopSequence: self.stopSequence, completion: { (op) in

                expect(op.entries).toNot(beNil())
                let entry = op.entries!.first!
                expect(entry["arrivalEnabled"] as? Bool) == true

                expect(op.references).toNot(beNil())

                let agencies = op.references!["agencies"] as! [Any]
                expect(agencies.count) == 1

                done()
            })
        }
    }

    // MARK: - URL Construction Tests

    /// Validate that a good URL is constructed when all needed data is passed in.
    func testBuildURL_withAllData() {
        let url = ArrivalDepartureForStopOperation.buildURL(stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopSequence: stopSequence, baseURL: baseURL, defaultQueryItems: [])
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        expect(components?.queryItemValueMatching(name: "tripId")) == tripID
        expect(components?.queryItemValueMatching(name: "serviceDate")) == String(serviceDate)
        expect(components?.queryItemValueMatching(name: "vehicleId")) ==  vehicleID
        expect(components?.queryItemValueMatching(name: "stopSequence")) == String(stopSequence)

        expect(components?.host) == host
        expect(components?.path) == ArrivalDepartureForStopOperation.buildAPIPath(stopID: stopID)
    }

    /// The lack of a vehicle ID does not impede building a good URL.
    func testBuildURL_withoutVehicleID() {
        let url = ArrivalDepartureForStopOperation.buildURL(stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: nil, stopSequence: stopSequence, baseURL: baseURL, defaultQueryItems: [])
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        expect(components?.queryItemValueMatching(name: "tripId")) == tripID
        expect(components?.queryItemValueMatching(name: "serviceDate")) == String(serviceDate)
        expect(components?.queryItemValueMatching(name: "vehicleId")).to(beNil())
        expect(components?.queryItemValueMatching(name: "stopSequence")) == String(stopSequence)

        expect(components?.host) == host
        expect(components?.path) == ArrivalDepartureForStopOperation.buildAPIPath(stopID: stopID)
    }

    /// A stopSequence value of less than 1 is not included in the URL
    func testBuildURL_invalidStopSequence() {
        let url = ArrivalDepartureForStopOperation.buildURL(stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopSequence: -1, baseURL: baseURL, defaultQueryItems: [])
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        expect(components?.queryItemValueMatching(name: "tripId")) == tripID
        expect(components?.queryItemValueMatching(name: "serviceDate")) == String(serviceDate)
        expect(components?.queryItemValueMatching(name: "vehicleId")) ==  vehicleID
        expect(components?.queryItemValueMatching(name: "stopSequence")).to(beNil())

        expect(components?.host) == host
        expect(components?.path) == ArrivalDepartureForStopOperation.buildAPIPath(stopID: stopID)
    }

    /// Validate that gnarly characters like '/' are properly escaped
    // in stop IDs
    func testBuildAPIPath_crazyCharactersInStopID() {
        expect(ArrivalDepartureForStopOperation.buildAPIPath(stopID: "Hello/Operator")) == "/api/where/arrival-and-departure-for-stop/Hello%2FOperator.json"
    }
}
